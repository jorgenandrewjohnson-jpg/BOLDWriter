import Foundation

struct ZipEntry {
    var path: String
    var data: Data
}

enum ZipArchiveWriter {
    static func archive(_ entries: [ZipEntry]) -> Data {
        var output = Data()
        var directory = Data()
        var records = 0

        for entry in entries {
            let name = Data(entry.path.utf8)
            let checksum = crc32(entry.data)
            let offset = UInt32(output.count)
            output.appendLE(UInt32(0x04034b50))
            output.appendLE(UInt16(20))
            output.appendLE(UInt16(0x0800))
            output.appendLE(UInt16(0))
            output.appendLE(UInt16(0))
            output.appendLE(UInt16(0))
            output.appendLE(checksum)
            output.appendLE(UInt32(entry.data.count))
            output.appendLE(UInt32(entry.data.count))
            output.appendLE(UInt16(name.count))
            output.appendLE(UInt16(0))
            output.append(name)
            output.append(entry.data)

            directory.appendLE(UInt32(0x02014b50))
            directory.appendLE(UInt16(20))
            directory.appendLE(UInt16(20))
            directory.appendLE(UInt16(0x0800))
            directory.appendLE(UInt16(0))
            directory.appendLE(UInt16(0))
            directory.appendLE(UInt16(0))
            directory.appendLE(checksum)
            directory.appendLE(UInt32(entry.data.count))
            directory.appendLE(UInt32(entry.data.count))
            directory.appendLE(UInt16(name.count))
            directory.appendLE(UInt16(0))
            directory.appendLE(UInt16(0))
            directory.appendLE(UInt16(0))
            directory.appendLE(UInt16(0))
            directory.appendLE(UInt32(0))
            directory.appendLE(offset)
            directory.append(name)
            records += 1
        }

        let directoryOffset = UInt32(output.count)
        output.append(directory)
        output.appendLE(UInt32(0x06054b50))
        output.appendLE(UInt16(0))
        output.appendLE(UInt16(0))
        output.appendLE(UInt16(records))
        output.appendLE(UInt16(records))
        output.appendLE(UInt32(directory.count))
        output.appendLE(directoryOffset)
        output.appendLE(UInt16(0))
        return output
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ (0xedb88320 & (0 &- (crc & 1))) }
        }
        return crc ^ 0xffffffff
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}
