import Foundation
import zlib

/// In-memory ZIP reading for DOCX. Central-directory sizes also support the data
/// descriptors used by Word. Never extracts paths or follows external targets.
enum DOCXPackage {
    /// Namespace-independent document-order traversal without Foundation's
    /// general XQuery evaluator allocating a query context for the whole DOM.
    static func descendants(in node: XMLNode, named name: String) -> [XMLNode] {
        descendants(in:node,names:[name])
    }
    static func descendants(in node: XMLNode, names: Set<String>) -> [XMLNode] {
        var stack=[node],result:[XMLNode]=[]
        while let next=stack.popLast() {
            if let element=next as? XMLElement,
               names.contains(element.localName ?? String((element.name ?? "").split(separator:":").last ?? "")) { result.append(element) }
            if let children=next.children { stack.append(contentsOf:children.reversed()) }
        }
        return result
    }
    static func bodyParagraphs(in node: XMLNode) -> [XMLNode] {
        var stack:[(XMLNode,Bool)]=[(node,false)],result:[XMLNode]=[]
        while let (next,withinBody)=stack.popLast() {
            let name=next.localName ?? String((next.name ?? "").split(separator:":").last ?? "")
            if withinBody, next is XMLElement, name == "p" { result.append(next) }
            if let children=next.children {
                stack.append(contentsOf:children.reversed().map{($0,withinBody || name == "body")})
            }
        }
        return result
    }
    static func entries(in data: Data) throws -> [ZipEntry] {
        let bytes = [UInt8](data)
        let limit = 256 * 1024 * 1024
        func invalid() -> Error { WriterError.message("The DOCX package is damaged or uses an unsupported ZIP format.") }
        func number(_ offset: Int, _ count: Int) throws -> Int {
            guard offset >= 0, count <= bytes.count, offset <= bytes.count - count else { throw invalid() }
            return (0..<count).reduce(0) { $0 | Int(bytes[offset + $1]) << (8 * $1) }
        }
        guard bytes.count >= 22 else { throw invalid() }
        var end: Int?
        for offset in stride(from: bytes.count - 22, through: max(0, bytes.count - 65_557), by: -1) {
            if try number(offset, 4) == 0x06054b50,
               try offset + 22 + number(offset + 20, 2) == bytes.count { end = offset; break }
        }
        guard let end, try number(end + 4, 2) == 0, try number(end + 6, 2) == 0,
              try number(end + 8, 2) == number(end + 10, 2) else { throw invalid() }
        let count = try number(end + 10, 2)
        let directorySize = try number(end + 12, 4)
        var offset = try number(end + 16, 4)
        guard count < 65_535, offset <= end, directorySize == end - offset else { throw invalid() }
        var entries: [ZipEntry] = [], paths = Set<String>(), total = 0
        for _ in 0..<count {
            guard try number(offset, 4) == 0x02014b50 else { throw invalid() }
            let flags = try number(offset + 8, 2), method = try number(offset + 10, 2)
            let checksum = try number(offset + 16, 4)
            let packed = try number(offset + 20, 4), unpacked = try number(offset + 24, 4)
            let nameLength = try number(offset + 28, 2), extra = try number(offset + 30, 2), comment = try number(offset + 32, 2)
            let local = try number(offset + 42, 4)
            let next = offset + 46 + nameLength + extra + comment
            guard flags & 1 == 0, [0, 8].contains(method), next <= end,
                  unpacked <= limit - total, try number(offset + 34, 2) == 0 else { throw invalid() }
            let path = String(decoding: bytes[(offset + 46)..<(offset + 46 + nameLength)], as: UTF8.self)
            guard paths.insert(path).inserted, !path.hasPrefix("/"), !path.contains("\\"),
                  !path.split(separator: "/").contains(".."), try number(local, 4) == 0x04034b50,
                  try number(local + 8, 2) == method else { throw invalid() }
            let start = try local + 30 + number(local + 26, 2) + number(local + 28, 2)
            guard start <= bytes.count, packed <= bytes.count - start else { throw invalid() }
            let compressed = Data(bytes[start..<(start + packed)])
            let content: Data
            if method == 0 {
                guard packed == unpacked else { throw invalid() }
                content = compressed
            } else {
                var output = Data(count: max(1, unpacked))
                var stream = z_stream()
                guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw invalid() }
                defer { inflateEnd(&stream) }
                let result = compressed.withUnsafeBytes { input in
                    output.withUnsafeMutableBytes { buffer in
                        stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress)
                        stream.avail_in = uInt(packed)
                        stream.next_out = buffer.bindMemory(to: Bytef.self).baseAddress
                        stream.avail_out = uInt(max(1, unpacked))
                        return inflate(&stream, Z_FINISH)
                    }
                }
                guard result == Z_STREAM_END, stream.total_out == unpacked, stream.total_in == packed else { throw invalid() }
                content = output.prefix(unpacked)
            }
            let actualCRC = content.withUnsafeBytes { crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(content.count)) }
            guard actualCRC == checksum else { throw invalid() }
            entries.append(ZipEntry(path: path, data: content))
            total += unpacked
            offset = next
        }
        guard offset == end else { throw invalid() }
        return entries
    }

    static func xml(_ data: Data) throws -> XMLDocument {
        let document = try XMLDocument(
            data: data,
            options: [
                .nodeLoadExternalEntitiesNever,
                .nodePreserveWhitespace
            ]
        )
        guard document.dtd == nil else { throw WriterError.message("DOCX XML with a document type declaration is unsupported.") }
        return document
    }

    static func target(_ target: String, relativeTo part: String) -> String? {
        guard let decoded = target.removingPercentEncoding, !decoded.contains(":"),
              !decoded.contains("\\"), !decoded.contains("?"), !decoded.contains("#") else { return nil }
        var components = decoded.hasPrefix("/") ? [] : part.split(separator: "/").dropLast().map(String.init)
        for component in decoded.split(separator: "/") {
            if component == ".." {
                guard !components.isEmpty else { return nil }
                components.removeLast()
            } else if component != "." { components.append(String(component)) }
        }
        return components.joined(separator: "/")
    }
}
