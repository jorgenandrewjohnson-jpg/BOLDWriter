import AppKit
import PDFKit

/// Editable reference objects for measured KDP PDFs. PDFKit supplies decoded text
/// (including embedded-font encodings); Core Graphics supplies vector geometry.
enum CoverPDFLayers {
    static func layers(data: Data) throws -> [CoverLayer] {
        guard let document = PDFDocument(data: data), let page = document.page(at: 0),
              let cgPage = page.pageRef else { throw CocoaError(.fileReadCorruptFile) }
        let bounds = page.bounds(for: .mediaBox)
        let collector = Paths(bounds: bounds)
        let table = CGPDFOperatorTableCreate()!
        func register(_ name: String, _ callback: @escaping CGPDFOperatorCallback) {
            CGPDFOperatorTableSetCallback(table, name, callback)
        }
        register("q") { _, raw in Paths.get(raw).save() }
        register("Q") { _, raw in Paths.get(raw).restore() }
        register("cm") { scanner, raw in
            let p = Paths.get(raw), n = Paths.numbers(scanner, 6)
            guard n.count == 6 else { return }
            p.transform = CGAffineTransform(a:n[0], b:n[1], c:n[2], d:n[3], tx:n[4], ty:n[5]).concatenating(p.transform)
        }
        register("rg") { scanner, raw in Paths.get(raw).fill = Paths.color(scanner) }
        register("RG") { scanner, raw in Paths.get(raw).stroke = Paths.color(scanner) }
        register("w") { scanner, raw in Paths.get(raw).width = Paths.numbers(scanner, 1).first ?? 1 }
        register("d") { scanner, raw in
            let p = Paths.get(raw)
            p.phase = Paths.numbers(scanner, 1).first ?? 0
            var array: CGPDFArrayRef?
            guard CGPDFScannerPopArray(scanner, &array), let array else { return }
            p.dashes = (0..<CGPDFArrayGetCount(array)).compactMap { index in
                var value: CGPDFReal = 0
                return CGPDFArrayGetNumber(array, index, &value) ? Double(value) : nil
            }
        }
        register("m") { scanner, raw in
            let p = Paths.get(raw), n = Paths.numbers(scanner, 2)
            if n.count == 2 { p.contours.append([p.point(n[0], n[1])]); p.closed.append(false) }
        }
        register("l") { scanner, raw in
            let p = Paths.get(raw), n = Paths.numbers(scanner, 2)
            if n.count == 2, !p.contours.isEmpty { p.contours[p.contours.count-1].append(p.point(n[0], n[1])) }
        }
        register("re") { scanner, raw in
            let p = Paths.get(raw), n = Paths.numbers(scanner, 4)
            guard n.count == 4 else { return }
            p.contours.append([p.point(n[0],n[1]), p.point(n[0]+n[2],n[1]),
                               p.point(n[0]+n[2],n[1]+n[3]), p.point(n[0],n[1]+n[3])])
            p.closed.append(true)
        }
        register("h") { _, raw in
            let p = Paths.get(raw)
            if !p.closed.isEmpty { p.closed[p.closed.count-1] = true }
        }
        register("f") { _, raw in Paths.get(raw).emit(fill: true, stroke: false) }
        register("f*") { _, raw in Paths.get(raw).emit(fill: true, stroke: false, evenOdd: true) }
        register("S") { _, raw in Paths.get(raw).emit(fill: false, stroke: true) }
        register("B") { _, raw in Paths.get(raw).emit(fill: true, stroke: true) }
        register("n") { _, raw in Paths.get(raw).clear() }
        let stream = CGPDFContentStreamCreateWithPage(cgPage)
        let scanner = CGPDFScannerCreate(stream, table, Unmanaged.passUnretained(collector).toOpaque())
        guard CGPDFScannerScan(scanner) else { throw CocoaError(.fileReadCorruptFile) }

        var group = CoverLayer(kind: .group, name: "Page 1 — KDP Template")
        group.referenceOnly = true
        var layers = collector.layers
        if let text = page.string, !text.isEmpty,
           let all = page.selection(for: NSRange(location: 0, length: (text as NSString).length)) {
            for line in all.selectionsByLine() {
                guard let string = line.string, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                let rect = line.bounds(for: page)
                guard rect.width > 0, rect.height > 0 else { continue }
                let attributes = line.attributedString?.attributes(at: 0, effectiveRange: nil) ?? [:]
                let font = attributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: 10)
                // PDF text bounds are in points and bottom-left coordinates.
                let vertical = rect.height > rect.width * 3 && string.count > 8
                let measured = NSAttributedString(string: string, attributes: [.font: font]).size()
                let lineWidth = vertical ? rect.height : rect.width
                let lineHeight = max(measured.height, font.ascender-font.descender+font.leading) + 2
                let frame = vertical
                    ? CGRect(x: rect.midX-(lineWidth+2)/2, y: rect.midY-lineHeight/2,
                             width: lineWidth+2, height: lineHeight)
                    : CGRect(x: rect.minX, y: rect.maxY-lineHeight,
                             width: lineWidth+2, height: lineHeight)
                var layer = CoverLayer(kind: .text, name: string, frame: CoverRect(
                    x: (frame.minX-bounds.minX)/bounds.width,
                    y: (bounds.maxY-frame.maxY)/bounds.height,
                    width: frame.width/bounds.width, height: frame.height/bounds.height))
                layer.horizontalScale = max(0.1, min(10, lineWidth / max(1, measured.width)))
                if vertical { layer.rotation = -90 }
                layer.text = string; layer.fontName = font.fontName; layer.fontSize = font.pointSize
                layer.alignment = "left"
                layer.colorHex = (attributes[.foregroundColor] as? NSColor ?? .black).hexRGB
                layer.referencePageWidth = bounds.width
                layers.append(layer)
            }
        }
        guard !layers.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        for index in layers.indices {
            layers[index].referenceOnly = true
            layers[index].groupID = group.id
            layers[index].referencePageWidth = bounds.width
        }
        return [group] + layers
    }

    private final class Paths {
        let bounds: CGRect
        var layers: [CoverLayer] = []
        var contours: [[CoverPathPoint]] = []
        var closed: [Bool] = []
        var fill = "#000000", stroke = "#000000"
        var width = 1.0, phase = 0.0
        var dashes: [Double] = []
        var transform = CGAffineTransform.identity
        var stack: [(String,String,Double,Double,[Double],CGAffineTransform)] = []
        init(bounds: CGRect) { self.bounds = bounds }
        static func get(_ raw: UnsafeMutableRawPointer?) -> Paths { Unmanaged<Paths>.fromOpaque(raw!).takeUnretainedValue() }
        static func numbers(_ scanner: CGPDFScannerRef?, _ count: Int) -> [Double] {
            guard let scanner else { return [] }
            var result: [Double] = []
            for _ in 0..<count {
                var number: CGPDFReal = 0
                guard CGPDFScannerPopNumber(scanner, &number), number.isFinite else { return [] }
                result.insert(Double(number), at: 0)
            }
            return result
        }
        static func color(_ scanner: CGPDFScannerRef?) -> String {
            let n = numbers(scanner, 3)
            guard n.count == 3 else { return "#000000" }
            return NSColor(srgbRed:n[0],green:n[1],blue:n[2],alpha:1).hexRGB
        }
        func point(_ x: Double, _ y: Double) -> CoverPathPoint {
            let p = CGPoint(x:x,y:y).applying(transform)
            return CoverPathPoint(x:(p.x-bounds.minX)/bounds.width,y:(bounds.maxY-p.y)/bounds.height)
        }
        func save() { stack.append((fill,stroke,width,phase,dashes,transform)) }
        func restore() {
            if let state = stack.popLast() { (fill,stroke,width,phase,dashes,transform) = state }
        }
        func clear() { contours=[]; closed=[] }
        func emit(fill shouldFill: Bool, stroke shouldStroke: Bool, evenOdd: Bool = false) {
            defer { clear() }
            guard !contours.isEmpty else { return }
            var layer = CoverLayer(kind:.path,name:"Path \(layers.count+1)")
            layer.pathContours = contours.enumerated().map { index, points in
                !shouldFill && closed[index] && !points.isEmpty ? points + [points[0]] : points
            }
            layer.pathContourClosed = Array(repeating:shouldFill,count:closed.count)
            layer.fillHex = shouldFill ? fill : "#00000000"
            layer.strokeHex = shouldStroke ? stroke : fill
            layer.strokeWidth = shouldStroke ? width : 0.001
            layer.strokeDashPattern = dashes
            layer.strokeDashPhase = phase
            if evenOdd { layer.fillRule = .evenOdd }
            layers.append(layer)
        }
    }
}
