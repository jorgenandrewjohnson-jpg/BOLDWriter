import CoreGraphics
import Foundation

struct PDFRasterPlacement: Equatable {
    let pageNumber: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let displayedWidthPoints: Double
    let displayedHeightPoints: Double

    var horizontalDPI: Double { Double(pixelWidth) * 72 / displayedWidthPoints }
    var verticalDPI: Double { Double(pixelHeight) * 72 / displayedHeightPoints }
    var minimumDPI: Double { min(horizontalDPI, verticalDPI) }
}

/// Measures image XObjects at their actual PDF draw transforms, including
/// images inside bounded Form XObjects. This inspects the exported artifact,
/// so inline and floating manuscript images use the same preflight path.
/// Inspired by Scribus PDF analyzer's pixel-versus-placement check; no GPL
/// implementation is included.
enum PDFImageResolutionPreflight {
    static func placements(in data: Data) -> [PDFRasterPlacement] {
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider), document.numberOfPages > 0 else { return [] }
        var placements: [PDFRasterPlacement] = []
        let table = CGPDFOperatorTableCreate()!
        CGPDFOperatorTableSetCallback(table, "q", pdfImageSave)
        CGPDFOperatorTableSetCallback(table, "Q", pdfImageRestore)
        CGPDFOperatorTableSetCallback(table, "cm", pdfImageConcat)
        CGPDFOperatorTableSetCallback(table, "Do", pdfImageDraw)
        for number in 1...document.numberOfPages {
            guard placements.count < 10_000, let page = document.page(at: number) else { break }
            let collector = PDFImagePlacementCollector(pageNumber: number)
            var scan: ((CGPDFContentStreamRef, CGAffineTransform, Int) -> Void)!
            scan = { stream, transform, depth in
                let frame = PDFImageScanFrame(stream: stream, transform: transform,
                                               depth: depth, collector: collector, scan: scan)
                let scanner = CGPDFScannerCreate(stream, table, Unmanaged.passUnretained(frame).toOpaque())
                defer {
                    CGPDFScannerRelease(scanner)
                    CGPDFContentStreamRelease(stream)
                }
                _ = CGPDFScannerScan(scanner)
            }
            scan(CGPDFContentStreamCreateWithPage(page), .identity, 0)
            placements.append(contentsOf: collector.placements.prefix(10_000 - placements.count))
        }
        return placements
    }
}

private final class PDFImagePlacementCollector {
    let pageNumber: Int
    var placements: [PDFRasterPlacement] = []
    init(pageNumber: Int) { self.pageNumber = pageNumber }

    func append(dictionary: CGPDFDictionaryRef, transform: CGAffineTransform) {
        guard placements.count < 10_000 else { return }
        var width: CGPDFInteger = 0, height: CGPDFInteger = 0
        guard CGPDFDictionaryGetInteger(dictionary, "Width", &width),
              CGPDFDictionaryGetInteger(dictionary, "Height", &height),
              width > 1, height > 1 else { return }
        var isMask = false
        if CGPDFDictionaryGetBoolean(dictionary, "ImageMask", &isMask), isMask { return }
        let drawnWidth = Double(hypot(transform.a, transform.b))
        let drawnHeight = Double(hypot(transform.c, transform.d))
        guard drawnWidth.isFinite, drawnHeight.isFinite,
              drawnWidth > 0.01, drawnHeight > 0.01 else { return }
        placements.append(.init(pageNumber: pageNumber, pixelWidth: width, pixelHeight: height,
                                displayedWidthPoints: drawnWidth, displayedHeightPoints: drawnHeight))
    }
}

private final class PDFImageScanFrame {
    let stream: CGPDFContentStreamRef
    let depth: Int
    let collector: PDFImagePlacementCollector
    let scan: (CGPDFContentStreamRef, CGAffineTransform, Int) -> Void
    var transform: CGAffineTransform
    var stack: [CGAffineTransform] = []

    init(stream: CGPDFContentStreamRef, transform: CGAffineTransform, depth: Int,
         collector: PDFImagePlacementCollector,
         scan: @escaping (CGPDFContentStreamRef, CGAffineTransform, Int) -> Void) {
        self.stream = stream
        self.transform = transform
        self.depth = depth
        self.collector = collector
        self.scan = scan
    }

    static func get(_ pointer: UnsafeMutableRawPointer?) -> PDFImageScanFrame {
        Unmanaged<PDFImageScanFrame>.fromOpaque(pointer!).takeUnretainedValue()
    }
}

private func pdfImageSave(_ scanner: CGPDFScannerRef, _ pointer: UnsafeMutableRawPointer?) {
    let frame = PDFImageScanFrame.get(pointer)
    frame.stack.append(frame.transform)
}

private func pdfImageRestore(_ scanner: CGPDFScannerRef, _ pointer: UnsafeMutableRawPointer?) {
    let frame = PDFImageScanFrame.get(pointer)
    if let previous = frame.stack.popLast() { frame.transform = previous }
}

private func pdfImageConcat(_ scanner: CGPDFScannerRef, _ pointer: UnsafeMutableRawPointer?) {
    var values: [CGFloat] = []
    for _ in 0..<6 {
        var value: CGPDFReal = 0
        guard CGPDFScannerPopNumber(scanner, &value), value.isFinite else { return }
        values.insert(CGFloat(value), at: 0)
    }
    let matrix = CGAffineTransform(a: values[0], b: values[1], c: values[2],
                                   d: values[3], tx: values[4], ty: values[5])
    let frame = PDFImageScanFrame.get(pointer)
    frame.transform = matrix.concatenating(frame.transform)
}

private func pdfImageDraw(_ scanner: CGPDFScannerRef, _ pointer: UnsafeMutableRawPointer?) {
    let frame = PDFImageScanFrame.get(pointer)
    var name: UnsafePointer<CChar>?
    guard CGPDFScannerPopName(scanner, &name), let name,
          let object = CGPDFContentStreamGetResource(frame.stream, "XObject", name) else { return }
    var stream: CGPDFStreamRef?
    guard CGPDFObjectGetValue(object, .stream, &stream), let stream,
          let dictionary = CGPDFStreamGetDictionary(stream) else { return }
    var subtype: UnsafePointer<CChar>?
    guard CGPDFDictionaryGetName(dictionary, "Subtype", &subtype), let subtype else { return }
    switch String(cString: subtype) {
    case "Image":
        frame.collector.append(dictionary: dictionary, transform: frame.transform)
    case "Form" where frame.depth < 12 && frame.collector.placements.count < 10_000:
        var resources: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources),
              let resources else { return }
        var matrixValues: CGPDFArrayRef?
        var matrix = CGAffineTransform.identity
        if CGPDFDictionaryGetArray(dictionary, "Matrix", &matrixValues), let matrixValues,
           CGPDFArrayGetCount(matrixValues) == 6 {
            var components: [CGFloat] = []
            for index in 0..<6 {
                var value: CGPDFReal = 0
                guard CGPDFArrayGetNumber(matrixValues, index, &value), value.isFinite else { return }
                components.append(CGFloat(value))
            }
            matrix = CGAffineTransform(a: components[0], b: components[1], c: components[2],
                                       d: components[3], tx: components[4], ty: components[5])
        }
        frame.scan(CGPDFContentStreamCreateWithStream(stream, resources, frame.stream),
                   matrix.concatenating(frame.transform), frame.depth + 1)
    default:
        break
    }
}
