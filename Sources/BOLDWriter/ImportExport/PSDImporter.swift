import AppKit
import zlib

/// Local, bounded PSD v1 reader. Layer records, never the merged preview, are authoritative.
enum PSDImporter {
    struct Result {
        var project: CoverProject
        var warnings: [String]
    }
    static func recognizes(_ data: Data) -> Bool { data.prefix(4) == Data("8BPS".utf8) }
    private static func fail(_ message: String) -> WriterError { .message("PSD import: \(message)") }
    private struct Reader {
        var bytes: [UInt8]
        var position = 0
        var remaining: Int { bytes.count - position }
        init(_ data: Data) { bytes = Array(data) }
        mutating func take(_ n: Int) throws -> Data {
            guard n >= 0, n <= remaining else { throw fail("truncated section.") }
            defer { position += n }; return Data(bytes[position..<position+n])
        }
        mutating func uint(_ n: Int) throws -> UInt64 { try take(n).reduce(0) { ($0 << 8) | UInt64($1) } }
        mutating func int32() throws -> Int { Int(Int32(bitPattern: UInt32(try uint(4)))) }
        mutating func text(_ n: Int) throws -> String { String(decoding: try take(n), as: UTF8.self) }
        mutating func section() throws -> Reader { Reader(try take(Int(try uint(4)))) }
        mutating func unicode() throws -> String {
            let n = Int(try uint(4)); guard n <= 1_000_000 else { throw fail("oversized Unicode string.") }
            return String(data: try take(n*2), encoding: .utf16BigEndian) ?? ""
        }
        mutating func double() throws -> Double {
            let value = Double(bitPattern: try uint(8)); guard value.isFinite else { throw fail("nonfinite transform.") }; return value
        }
        mutating func key() throws -> String { let n = Int(try uint(4)); return try text(n == 0 ? 4 : n) }
    }
    private struct Record {
        var top: Int; var left: Int; var bottom: Int; var right: Int
        var name: String; var opacity: UInt8; var flags: UInt8; var blend: String
        var channels: [(Int, Int)]; var blocks: [String: Data]; var mask: Data
    }
    static func read(_ data: Data, filename: String) throws -> Result {
        guard data.count <= 750_000_000 else { throw fail("file exceeds the import budget.") }
        var r = Reader(data)
        guard try r.text(4) == "8BPS", try r.uint(2) == 1 else { throw fail("only PSD version 1 is supported.") }
        _ = try r.take(6); let channels = try r.uint(2)
        let h = Int(try r.uint(4)), w = Int(try r.uint(4))
        guard (1...30000).contains(w), (1...30000).contains(h), w*h <= 50_000_000,
              (3...56).contains(channels), try r.uint(2) == 8, try r.uint(2) == 3 else {
            throw fail("requires bounded 8-bit RGB artwork; other depths/color modes are unsupported.")
        }
        _ = try r.section()
        var resources = try r.section(); var dpi = 300.0; var resourceWarnings: [String] = []
        while resources.remaining > 0 {
            guard try resources.text(4) == "8BIM" else { throw fail("invalid resource signature.") }
            let id = try resources.uint(2); let n = Int(try resources.uint(1)); _ = try resources.take(n)
            if (n+1)%2 != 0 { _ = try resources.take(1) }
            var resource = try resources.section()
            if resource.bytes.count%2 != 0 { _ = try resources.take(1) }
            if id != 1005 { resourceWarnings.append("Image resource \(id) is not mapped; RGB samples are retained without profile conversion.") }
            if id == 1005 {
                let x = Double(try resource.uint(4))/65536; _ = try resource.take(4)
                let y = Double(try resource.uint(4))/65536
                guard x == y, (1...2400).contains(x) else { throw fail("unsupported anisotropic/invalid resolution.") }; dpi = x
            }
        }
        var layerMask = try r.section()
        // Validate that the saved file also has a complete merged-image section.
        // This does not participate in layer import or substitute for layer channels.
        let compositeCompression = try r.uint(2)
        if compositeCompression == 0 {
            guard r.remaining == w*h*Int(channels) else { throw fail("truncated/invalid composite channel data.") }
        } else if compositeCompression == 1 {
            var total = 0
            for _ in 0..<h*Int(channels) { total += Int(try r.uint(2)) }
            guard total == r.remaining else { throw fail("truncated/invalid composite RLE data.") }
        } else { throw fail("ZIP merged-image compression is unsupported; save a raw/RLE composite.") }

        guard layerMask.remaining >= 4 else { throw fail("no editable layer records.") }
        var info = try layerMask.section()
        let count = abs(Int(Int16(bitPattern: UInt16(try info.uint(2)))))
        guard (1...1000).contains(count) else { throw fail("no layers or too many layer records.") }
        var records: [Record] = []
        for _ in 0..<count {
            let top = try info.int32(), left = try info.int32(), bottom = try info.int32(), right = try info.int32()
            guard right >= left, bottom >= top, right-left <= 30000, bottom-top <= 30000,
                  (right-left)*(bottom-top) <= 50_000_000 else { throw fail("invalid layer bounds.") }
            let channelCount = Int(try info.uint(2)); guard channelCount <= 56 else { throw fail("too many channels.") }
            var channelInfo: [(Int,Int)] = []
            for _ in 0..<channelCount { channelInfo.append((Int(Int16(bitPattern: UInt16(try info.uint(2)))), Int(try info.uint(4)))) }
            guard try info.text(4) == "8BIM" else { throw fail("invalid blend signature.") }
            let blend = try info.text(4), opacity = UInt8(try info.uint(1))
            let clipping = try info.uint(1), flags = UInt8(try info.uint(1)); _ = try info.take(1)
            guard clipping == 0 else { throw fail("clipping stacks require conversion before import.") }
            var extra = try info.section(); let mask = Data(try extra.section().bytes); _ = try extra.section()
            let nameLength = Int(try extra.uint(1)); var name = String(data: try extra.take(nameLength), encoding: .macOSRoman) ?? "Layer"
            let padding = (4 - (nameLength+1)%4)%4; _ = try extra.take(padding)
            var blocks: [String:Data] = [:]
            while extra.remaining >= 12 {
                let signature = try extra.text(4); guard signature == "8BIM" || signature == "8B64" else { throw fail("invalid layer metadata signature.") }
                let key = try extra.text(4); let block = try extra.take(Int(try extra.uint(4))); blocks[key] = block
                if block.count%2 != 0 { _ = try extra.take(1) }
            }
            if let unicode = blocks["luni"] { var u = Reader(unicode); name = try u.unicode() }
            records.append(Record(top:top,left:left,bottom:bottom,right:right,name:name,opacity:opacity,flags:flags,blend:blend,channels:channelInfo,blocks:blocks,mask:mask))
        }
        var project = CoverProject(type:.ebookFront,width:Double(w)/dpi,height:Double(h)/dpi)
        project.name = URL(fileURLWithPath:filename).deletingPathExtension().lastPathComponent; project.dpi = dpi
        var warnings: [String] = resourceWarnings; var groups: [UUID] = []; var decodedBudget = 0
        for record in records {
            let lw = record.right-record.left, lh = record.bottom-record.top
            var planes: [Int:[UInt8]] = [:]
            for (id, length) in record.channels {
                let bytes = try info.take(length)
                if [-2,-3].contains(id) {
                    // Masks cannot be silently flattened: reject until model geometry is supported.
                    throw fail("editable mask channels are not supported; the original PSD is unchanged.")
                }
                decodedBudget += lw*lh
                guard decodedBudget <= 750_000_000 else { throw fail("decoded channel budget exceeded.") }
                planes[id] = try decode(bytes,width:lw,height:lh)
            }
            var divider: UInt64 = 0
            if let block = record.blocks["lsct"] ?? record.blocks["lsdk"] { var b = Reader(block); divider = try b.uint(4) }
            if divider == 3 {
                guard groups.isEmpty else { throw fail("nested folders are unsupported for PSD re-export.") }
                let group = CoverLayer(kind:.group,name:"PSD group"); project.layers.append(group); groups.append(group.id); continue
            }
            if divider == 1 || divider == 2 {
                guard record.opacity == 255, record.blend == "norm" || record.blend == "pass" else { throw fail("group opacity/blending is unsupported.") }
                if record.blocks.keys.contains(where:{ !["luni","lsct","lsdk","lyid"].contains($0) }) { warnings.append("\(record.name): extra folder metadata is not mapped.") }
                guard let id = groups.popLast(), let i = project.layers.firstIndex(where:{$0.id == id}) else { throw fail("unbalanced group records.") }
                project.layers[i].name = record.name; project.layers[i].visible = record.flags & 2 == 0
                project.layers[i].opacity = Double(record.opacity)/255; project.layers[i].groupID = groups.last
                continue
            }
            guard lw > 0, lh > 0, let red = planes[0], let green = planes[1], let blue = planes[2] else { throw fail("layer lacks editable RGB channels.") }
            var layer = CoverLayer(kind:.image,name:record.name,frame:CoverRect(x:Double(record.left)/Double(w),y:Double(record.top)/Double(h),width:Double(lw)/Double(w),height:Double(lh)/Double(h)))
            layer.psdRasterPixelBasis = true
            layer.imageData = try png(red:red,green:green,blue:blue,alpha:planes[-1] ?? [UInt8](repeating:255,count:lw*lh),width:lw,height:lh)
            layer.transparencyLocked = record.flags & 1 != 0
            if let protection = record.blocks["lspf"] {
                var p = Reader(protection); let flags = try p.uint(4)
                layer.transparencyLocked = flags & 1 != 0; layer.pixelsLocked = flags & 2 != 0
                layer.positionLocked = flags & 4 != 0; layer.locked = flags & 0x80000000 != 0
            }
            layer.opacity = Double(record.opacity)/255; layer.visible = record.flags & 2 == 0; layer.groupID = groups.last
            guard let blend = blendMode(record.blend) else { throw fail("unsupported blend mode \(record.blend).") }; layer.blendMode = blend
            if !record.mask.isEmpty { throw fail("editable mask metadata is unsupported.") }
            if let text = record.blocks["TySh"] {
                try applyText(text,to:&layer,canvasWidth:w,canvasHeight:h); layer.imageData = nil; layer.psdRasterPixelBasis = nil
                if NSFont(name:layer.fontName,size:layer.fontSize) == nil { warnings.append("\(record.name): font \(layer.fontName) is unavailable; native rendering uses a substitute.") }
            }
            let supported: Set<String> = ["luni","TySh","lsct","lsdk","lyid","lspf"]
            let unsupported = record.blocks.keys.filter { !supported.contains($0) }.sorted()
            if !unsupported.isEmpty { warnings.append("\(record.name): raster appearance retained; editable metadata unsupported: \(unsupported.joined(separator:", ")).") }
            project.layers.append(layer)
        }
        guard groups.isEmpty else { throw fail("unclosed group records.") }
        guard project.layers.contains(where:{$0.kind != .group}) else { throw fail("no editable artwork.") }
        try CoverProject.validate([project]); return Result(project:project,warnings:warnings)
    }
    static func blendMode(_ key: String) -> CoverBlendMode? {
        CoverBlendMode.allCases.first { PSDExporter.blendKey($0) == key }
    }
    private static func decode(_ data: Data, width: Int, height: Int) throws -> [UInt8] {
        var r = Reader(data); let compression = try r.uint(2); let count = width*height
        if compression == 0 { guard r.remaining == count else { throw fail("raw channel length mismatch.") }; return Array(try r.take(count)) }
        if compression == 1 {
            var lengths: [Int] = []; for _ in 0..<height { lengths.append(Int(try r.uint(2))) }
            var result: [UInt8] = []; result.reserveCapacity(count)
            for length in lengths {
                var row = Reader(try r.take(length)); var pixels: [UInt8] = []
                while row.remaining > 0 {
                    let control = Int(Int8(bitPattern: UInt8(try row.uint(1))))
                    if control >= 0 { pixels.append(contentsOf:try row.take(control+1)) }
                    else if control != -128 { let value = UInt8(try row.uint(1)); pixels.append(contentsOf:repeatElement(value,count:1-control)) }
                    guard pixels.count <= width else { throw fail("RLE row overflow.") }
                }
                guard pixels.count == width else { throw fail("RLE row length mismatch.") }; result += pixels
            }
            guard r.remaining == 0 else { throw fail("unexpected RLE trailing data.") }; return result
        }
        if compression == 2 || compression == 3 {
            guard width > 0, height > 0 else { throw fail("ZIP channel has empty layer bounds.") }
            var result = [UInt8](repeating:0,count:count); var outputLength = uLongf(count)
            let input = Array(try r.take(r.remaining))
            let status = result.withUnsafeMutableBufferPointer { output in input.withUnsafeBufferPointer { source in uncompress(output.baseAddress,&outputLength,source.baseAddress,uLong(input.count)) } }
            guard status == Z_OK, outputLength == count else { throw fail("invalid ZIP channel.") }
            if compression == 3 { for y in 0..<height { for x in 1..<width { let i = y*width+x; result[i] = result[i] &+ result[i-1] } } }
            return result
        }
        throw fail("unsupported channel compression.")
    }
    private static func png(red:[UInt8],green:[UInt8],blue:[UInt8],alpha:[UInt8],width:Int,height:Int) throws -> Data {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:width,pixelsHigh:height,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bitmapFormat:.alphaNonpremultiplied,bytesPerRow:width*4,bitsPerPixel:32),let pixels = bitmap.bitmapData else { throw fail("cannot allocate raster.") }
        for i in 0..<width*height { pixels[i*4] = red[i]; pixels[i*4+1] = green[i]; pixels[i*4+2] = blue[i]; pixels[i*4+3] = alpha[i] }
        guard let data = bitmap.representation(using:.png,properties:[:]) else { throw fail("cannot embed raster.") }; return data
    }
    // Photoshop descriptors are length-delimited. Parse only known typed values; never scan arbitrary bytes for text.
    private static func descriptor(_ r: inout Reader, depth: Int = 0) throws -> [String:Any] {
        guard depth < 16 else { throw fail("descriptor nesting limit.") }
        _ = try r.unicode(); _ = try r.key(); let count = Int(try r.uint(4)); guard count <= 10000 else { throw fail("oversized descriptor.") }
        var result: [String:Any] = [:]
        for _ in 0..<count {
            let key = try r.key(), type = try r.text(4)
            switch type {
            case "TEXT": result[key] = try r.unicode()
            case "Objc","GlbO": result[key] = try descriptor(&r,depth:depth+1)
            case "enum": _ = try r.key(); result[key] = try r.key()
            case "UntF": _ = try r.text(4); result[key] = try r.double()
            case "doub": result[key] = try r.double()
            case "long": result[key] = try r.int32()
            case "bool": result[key] = try r.uint(1) != 0
            case "tdta": result[key] = try r.take(Int(try r.uint(4)))
            default: throw fail("unsupported text descriptor value \(type).")
            }
        }; return result
    }
    private static func applyText(_ data: Data, to layer: inout CoverLayer, canvasWidth:Int, canvasHeight:Int) throws {
        var r = Reader(data); guard try r.uint(2) == 1 else { throw fail("unsupported type tool.") }
        let xx = try r.double(), xy = try r.double(), yx = try r.double(), yy = try r.double(), tx = try r.double(), ty = try r.double()
        guard abs(xx*xx+xy*xy-1) < 0.00001, abs(yx+xy)<0.00001, abs(yy-xx)<0.00001 else { throw fail("skewed/scaled editable text transforms are unsupported.") }
        guard try r.uint(2) == 50, try r.uint(4) == 16 else { throw fail("unsupported text descriptor version.") }
        let d = try descriptor(&r)
        guard try r.uint(2) == 1, try r.uint(4) == 16 else { throw fail("unsupported text warp version.") }
        let warp = try descriptor(&r)
        guard warp["warpStyle"] as? String == "warpNone",
              abs(warp["warpValue"] as? Double ?? 0) < 0.000001,
              abs(warp["warpPerspective"] as? Double ?? 0) < 0.000001,
              abs(warp["warpPerspectiveOther"] as? Double ?? 0) < 0.000001 else { throw fail("editable text warp is unsupported.") }
        guard let text = d["Txt "] as? String, let bounds = d["bounds"] as? [String:Any],
              let left = bounds["Left"] as? Double, let top = bounds["Top "] as? Double,
              let right = bounds["Rght"] as? Double, let bottom = bounds["Btom"] as? Double,
              let engine = d["EngineData"] as? Data else { throw fail("editable text lacks bounds/style data.") }
        let e = try PSDEngineData.parse(engine)
        guard let root = e as? [String:Any], let dict = root["EngineDict"] as? [String:Any],
              let runs = dict["StyleRun"] as? [String:Any], let array = runs["RunArray"] as? [Any], array.count == 1,
              let run = array.first as? [String:Any], let sheet = run["StyleSheet"] as? [String:Any], let style = sheet["StyleSheetData"] as? [String:Any],
              let resources = root["ResourceDict"] as? [String:Any], let fonts = resources["FontSet"] as? [[String:Any]],
              let index = style["Font"] as? Double, index >= 0, index < Double(fonts.count), index.rounded(.towardZero) == index,
              let font = fonts[Int(index)]["Name"] as? String, let size = style["FontSize"] as? Double else { throw fail("mixed/unsupported text style runs.") }
        layer.kind = .text; layer.text = text; layer.fontName = font; layer.fontSize = size
        layer.referencePageWidth = Double(canvasWidth); layer.psdTextPixelBasis = true
        layer.rotation = atan2(xy,xx)*180 / .pi
        let fw = right-left, fh = bottom-top, cx = (right+left)/2, cy = (bottom+top)/2
        layer.frame = CoverRect(x:(tx+xx*cx+yx*cy-fw/2)/Double(canvasWidth),y:(ty+xy*cx+yy*cy-fh/2)/Double(canvasHeight),width:fw/Double(canvasWidth),height:fh/Double(canvasHeight))
        layer.bold = style["FauxBold"] as? Bool ?? false; layer.italic = style["FauxItalic"] as? Bool ?? false
        layer.letterSpacing = style["Tracking"] as? Double ?? 0; layer.leading = style["Leading"] as? Double
        layer.horizontalScale = style["HorizontalScale"] as? Double; layer.verticalScale = style["VerticalScale"] as? Double
        layer.baselineShift = style["BaselineShift"] as? Double; layer.underline = style["Underline"] as? Bool; layer.strikethrough = style["Strikethrough"] as? Bool
        if let color = style["FillColor"] as? [String:Any], let values = color["Values"] as? [Double], values.count == 4, values.allSatisfy({ (0...1).contains($0) }) {
            layer.colorHex = String(format:"#%02X%02X%02X",Int((values[1]*255).rounded()),Int((values[2]*255).rounded()),Int((values[3]*255).rounded()))
        }
        if let paragraphs = dict["ParagraphRun"] as? [String:Any], let runs = paragraphs["RunArray"] as? [[String:Any]], runs.count == 1,
           let sheet = runs[0]["ParagraphSheet"] as? [String:Any], let p = sheet["Properties"] as? [String:Any] {
            layer.alignment = ["left","right","center","justified"][min(3,max(0,Int(p["Justification"] as? Double ?? 0)))]
            layer.paragraphIndent = p["FirstLineIndent"] as? Double; layer.paragraphSpacing = p["SpaceAfter"] as? Double
        } else { throw fail("mixed/unsupported paragraph style runs.") }
    }
}

/// Bounded parser for Photoshop's PostScript-like EngineData (uniform text styles).
private enum PSDEngineData {
    static func parse(_ data: Data) throws -> Any {
        let bytes = Array(data); var i = 0; var tokens = 0
        func skip() { while i < bytes.count && [UInt8(0),9,10,13,32].contains(bytes[i]) { i += 1 } }
        func word() -> String { let start = i; while i < bytes.count && ![UInt8(0),9,10,13,32,91,93,60,62].contains(bytes[i]) { i += 1 }; return String(decoding:bytes[start..<i],as:UTF8.self) }
        func value(_ depth: Int) throws -> Any {
            tokens += 1; skip(); guard depth < 32, tokens <= 100000, i < bytes.count else { throw WriterError.message("PSD import: invalid EngineData.") }
            if i+1 < bytes.count && bytes[i] == 60 && bytes[i+1] == 60 {
                i += 2; var d: [String:Any] = [:]
                while true { skip(); guard i+1 < bytes.count else { throw WriterError.message("PSD import: truncated EngineData dictionary.") }
                    if bytes[i] == 62 && bytes[i+1] == 62 { i += 2; return d }
                    guard bytes[i] == 47 else { throw WriterError.message("PSD import: invalid EngineData key.") }; i += 1
                    let k = word(); d[k] = try value(depth+1)
                }
            }
            if bytes[i] == 91 { i += 1; var a: [Any] = []; while true { skip(); guard i < bytes.count else { throw WriterError.message("PSD import: truncated EngineData array.") }; if bytes[i] == 93 { i += 1; return a }; a.append(try value(depth+1)) } }
            if bytes[i] == 40 {
                i += 1; var raw: [UInt8] = []; var closed = false
                while i < bytes.count { let b = bytes[i]; i += 1; if b == 41 { closed = true; break }; if b == 92 { guard i < bytes.count else { break }; raw.append(bytes[i]); i += 1 } else { raw.append(b) } }
                guard closed else { throw WriterError.message("PSD import: truncated EngineData string.") }
                if raw.prefix(2) == [254,255] { return String(data:Data(raw.dropFirst(2)),encoding:.utf16BigEndian) ?? "" }
                return String(decoding:raw,as:UTF8.self)
            }
            let s = word(); if s == "true" { return true }; if s == "false" { return false }; if let n = Double(s), n.isFinite { return n }
            throw WriterError.message("PSD import: unsupported EngineData token.")
        }
        let result = try value(0); skip(); guard i == bytes.count else { throw WriterError.message("PSD import: trailing EngineData.") }; return result
    }
}
