import CoreGraphics
import PDFKit

/// Reads effective image matrices from page content streams, recursively
/// following Form XObjects. It measures draw transforms, not resource presence.
struct PDFImageGeometryInspection {
    struct Placement {
        let pageIndex: Int
        let unitSquareToPDF: CGAffineTransform
        let bounds: CGRect
    }

    static func placements(in document: PDFDocument) -> [Placement] {
        (0..<document.pageCount).flatMap { pageIndex -> [Placement] in
            guard let page = document.page(at: pageIndex), let cgPage = page.pageRef else { return [] }
            let collector = PDFGeometryCollector(pageIndex: pageIndex)
            let table = CGPDFOperatorTableCreate()!
            CGPDFOperatorTableSetCallback(table, "q", pdfGeometrySave)
            CGPDFOperatorTableSetCallback(table, "Q", pdfGeometryRestore)
            CGPDFOperatorTableSetCallback(table, "cm", pdfGeometryConcat)
            CGPDFOperatorTableSetCallback(table, "Do", pdfGeometryDraw)

            var scan: ((CGPDFContentStreamRef, CGAffineTransform, Int, PDFGeometryCollector) -> Void)!
            scan = { stream, transform, depth, result in
                let frame = PDFGeometryFrame(stream: stream, transform: transform, depth: depth,
                                             collector: result, scan: scan)
                let scanner = CGPDFScannerCreate(stream, table, Unmanaged.passUnretained(frame).toOpaque())
                defer {
                    CGPDFScannerRelease(scanner)
                    CGPDFContentStreamRelease(stream)
                }
                _ = CGPDFScannerScan(scanner)
            }
            scan(CGPDFContentStreamCreateWithPage(cgPage), .identity, 0, collector)
            return collector.placements
        }
    }
}

private final class PDFGeometryCollector {
    let pageIndex: Int
    var placements: [PDFImageGeometryInspection.Placement] = []
    init(pageIndex: Int) { self.pageIndex = pageIndex }

    func append(transform: CGAffineTransform) {
        let corners = [CGPoint.zero, CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]
            .map { $0.applying(transform) }
        guard let minX = corners.map(\.x).min(), let maxX = corners.map(\.x).max(),
              let minY = corners.map(\.y).min(), let maxY = corners.map(\.y).max() else { return }
        placements.append(.init(pageIndex: pageIndex, unitSquareToPDF: transform,
                                bounds: CGRect(x: minX, y: minY,
                                               width: maxX - minX, height: maxY - minY)))
    }
}

private final class PDFGeometryFrame {
    let stream: CGPDFContentStreamRef
    let depth: Int
    let collector: PDFGeometryCollector
    let scan: (CGPDFContentStreamRef, CGAffineTransform, Int, PDFGeometryCollector) -> Void
    var transform: CGAffineTransform
    var stack: [CGAffineTransform] = []

    init(stream: CGPDFContentStreamRef, transform: CGAffineTransform, depth: Int,
         collector: PDFGeometryCollector,
         scan: @escaping (CGPDFContentStreamRef, CGAffineTransform, Int, PDFGeometryCollector) -> Void) {
        self.stream = stream; self.transform = transform; self.depth = depth
        self.collector = collector; self.scan = scan
    }

    static func get(_ raw: UnsafeMutableRawPointer?) -> PDFGeometryFrame {
        Unmanaged<PDFGeometryFrame>.fromOpaque(raw!).takeUnretainedValue()
    }
}

private func pdfGeometrySave(_ scanner: CGPDFScannerRef, _ raw: UnsafeMutableRawPointer?) {
    let frame = PDFGeometryFrame.get(raw)
    frame.stack.append(frame.transform)
}

private func pdfGeometryRestore(_ scanner: CGPDFScannerRef, _ raw: UnsafeMutableRawPointer?) {
    let frame = PDFGeometryFrame.get(raw)
    if let previous = frame.stack.popLast() { frame.transform = previous }
}

private func pdfGeometryNumbers(_ scanner: CGPDFScannerRef, count: Int) -> [CGFloat] {
    var result: [CGFloat] = []
    for _ in 0..<count {
        var value: CGPDFReal = 0
        guard CGPDFScannerPopNumber(scanner, &value), value.isFinite else { return [] }
        result.insert(CGFloat(value), at: 0)
    }
    return result
}

private func pdfGeometryMatrix(_ dictionary: CGPDFDictionaryRef, _ key: String) -> CGAffineTransform {
    var array: CGPDFArrayRef?
    guard CGPDFDictionaryGetArray(dictionary, key, &array), let array,
          CGPDFArrayGetCount(array) == 6 else { return .identity }
    let values = (0..<6).compactMap { index -> CGFloat? in
        var value: CGPDFReal = 0
        return CGPDFArrayGetNumber(array, index, &value) ? CGFloat(value) : nil
    }
    guard values.count == 6 else { return .identity }
    return CGAffineTransform(a: values[0], b: values[1], c: values[2],
                             d: values[3], tx: values[4], ty: values[5])
}

private func pdfGeometryConcat(_ scanner: CGPDFScannerRef, _ raw: UnsafeMutableRawPointer?) {
    let values = pdfGeometryNumbers(scanner, count: 6)
    guard values.count == 6 else { return }
    let frame = PDFGeometryFrame.get(raw)
    let matrix = CGAffineTransform(a: values[0], b: values[1], c: values[2],
                                   d: values[3], tx: values[4], ty: values[5])
    frame.transform = matrix.concatenating(frame.transform)
}

private func pdfGeometryDraw(_ scanner: CGPDFScannerRef, _ raw: UnsafeMutableRawPointer?) {
    let frame = PDFGeometryFrame.get(raw)
    var name: UnsafePointer<CChar>?
    guard CGPDFScannerPopName(scanner, &name), let name,
          let object = CGPDFContentStreamGetResource(frame.stream, "XObject", name) else { return }
    var xObject: CGPDFStreamRef?
    guard CGPDFObjectGetValue(object, .stream, &xObject), let xObject,
          let dictionary = CGPDFStreamGetDictionary(xObject) else { return }
    var subtype: UnsafePointer<CChar>?
    guard CGPDFDictionaryGetName(dictionary, "Subtype", &subtype), let subtype else { return }
    switch String(cString: subtype) {
    case "Image":
        frame.collector.append(transform: frame.transform)
    case "Form" where frame.depth < 12:
        var resources: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources), let resources else { return }
        let nested = CGPDFContentStreamCreateWithStream(xObject, resources, frame.stream)
        let formMatrix = pdfGeometryMatrix(dictionary, "Matrix")
        frame.scan(nested, formMatrix.concatenating(frame.transform), frame.depth + 1, frame.collector)
    default:
        break
    }
}
