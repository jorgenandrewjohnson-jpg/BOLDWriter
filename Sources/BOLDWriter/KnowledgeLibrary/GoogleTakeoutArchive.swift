import Foundation
import CryptoKit
import CoreFoundation

enum TakeoutItemKind: String, CaseIterable, Identifiable, Sendable {
    case document, photo, video, metadata, unsupported, unsafe
    var id: String { rawValue }
    var label: String {
        switch self {
        case .document: "Supported document"
        case .photo: "Photo (skipped)"
        case .video: "Video (skipped)"
        case .metadata: "Takeout metadata"
        case .unsupported: "Unsupported file"
        case .unsafe: "Unsafe archive entry"
        }
    }
}

enum TakeoutSource: Hashable, Sendable {
    case archive(URL)
    case folder(URL)
    var url: URL { switch self { case .archive(let url), .folder(let url): url } }
    var label: String { url.deletingPathExtension().lastPathComponent }
}

struct TakeoutMetadata: Codable, Hashable, Sendable {
    var googleID: String?
    var originalURL: String?
    var title: String?
    var description: String?
    var createdTime: String?
    var modifiedTime: String?
    var modifiedDate: Date? {
        guard let modifiedTime else { return nil }
        return ISO8601DateFormatter().date(from: modifiedTime)
    }
}

struct KnowledgeTakeoutImportRecord: Identifiable, Codable, Hashable, Sendable {
    let sourceIdentity: String
    let documentID: KnowledgeDocumentID
    let relativePath: String
    let originalFilename: String
    let exportFormat: String
    let fingerprint: String
    let importedAt: Date
    let googleFileID: String?
    let originalURL: String?
    let metadata: TakeoutMetadata?
    let archiveCRC32: UInt32?
    let sourceBytes: UInt64
    let sourceModifiedAt: Date?
    let sourceContainerURI: String
    var id: String { sourceIdentity }
}

struct TakeoutEntry: Identifiable, Hashable, Sendable {
    let id: String
    let source: TakeoutSource
    let relativePath: String
    var kind: TakeoutItemKind
    let compressedBytes: UInt64
    let uncompressedBytes: UInt64
    let crc32: UInt32?
    let compressionMethod: UInt16?
    let centralFlags: UInt16?
    let localHeaderOffset: UInt64?
    var sourceModifiedAt: Date?
    var selected: Bool
    var metadata: TakeoutMetadata?
    var format: String { URL(fileURLWithPath: relativePath).pathExtension.lowercased() }
    var folderPath: String { relativePath.split(separator: "/").dropLast().joined(separator: "/") }
}

struct TakeoutIssue: Identifiable, Hashable, Sendable {
    let id = UUID()
    let source: String
    let path: String?
    let message: String
}

struct TakeoutPreview: Sendable {
    var entries: [TakeoutEntry] = []
    var issues: [TakeoutIssue] = []
    var sourceBytes: UInt64 = 0
    var archiveCount = 0
    var folderCount = 0
    var selectedDocuments: [TakeoutEntry] { entries.filter { $0.kind == .document && $0.selected } }
    var supportedDocuments: Int { entries.filter { $0.kind == .document }.count }
    var skippedMedia: Int { entries.filter { $0.kind == .photo || $0.kind == .video }.count }
    var additionalSourceBytes: UInt64 { selectedDocuments.filter { if case .archive = $0.source { true } else { false } }.reduce(0) { $0 &+ $1.uncompressedBytes } }
    var estimatedIndexBytes: UInt64 { selectedDocuments.reduce(0) { $0 &+ $1.uncompressedBytes } / 3 }
}

enum GoogleTakeoutError: LocalizedError {
    case malformedArchive(String)
    case unsupportedArchive(String)
    case unsafePath(String)
    case limitsExceeded(String)
    case extractionFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .malformedArchive(let detail): "Malformed Takeout archive: \(detail)"
        case .unsupportedArchive(let detail): "Unsupported Takeout archive: \(detail)"
        case .unsafePath(let path): "Unsafe archive path was rejected: \(path)"
        case .limitsExceeded(let detail): "Takeout import limit exceeded: \(detail)"
        case .extractionFailed(let detail): "Could not safely extract \(detail)"
        case .cancelled: "Takeout import was cancelled. Completed documents remain available."
        }
    }
}

/// Inspects only selected input roots. ZIP entries are read from the central directory
/// and never extracted by their archive-provided paths.
enum GoogleTakeoutScanner {
    static let maximumEntries = 100_000
    static let maximumEntryBytes: UInt64 = 512 * 1024 * 1024
    static let maximumExpandedBytes: UInt64 = 20 * 1024 * 1024 * 1024
    static let maximumCompressionRatio: UInt64 = 10_000

    static func scan(_ sources: [TakeoutSource]) throws -> TakeoutPreview {
        var preview = TakeoutPreview()
        var entryCount = 0
        var totalExpanded: UInt64 = 0
        for source in sources {
            switch source {
            case .archive(let url):
                let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                preview.archiveCount += 1
                preview.sourceBytes &+= (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(UInt64.init) ?? 0
                do {
                    let zip = try SafeTakeoutZIP(url: url)
                    let archiveEntries = zip.entries
                    entryCount += archiveEntries.count
                    guard entryCount <= maximumEntries else { throw GoogleTakeoutError.limitsExceeded("more than \(maximumEntries) archive entries") }
                    for item in archiveEntries {
                        guard let safePath = safeRelativePath(item.path) else {
                            preview.entries.append(TakeoutEntry(id: "\(url.path)::unsafe::\(item.path)", source: source, relativePath: item.path, kind: .unsafe, compressedBytes: item.compressedSize, uncompressedBytes: item.uncompressedSize, crc32: item.crc32, compressionMethod: item.method, centralFlags: item.flags, localHeaderOffset: item.localOffset, sourceModifiedAt: nil, selected: false))
                            preview.issues.append(TakeoutIssue(source: url.lastPathComponent, path: item.path, message: "Absolute, traversal, or malformed path rejected."))
                            continue
                        }
                        let kind: TakeoutItemKind = item.isSymbolicLink ? .unsafe : (item.method == 0 || item.method == 8 ? classify(safePath) : .unsupported)
                        if item.isSymbolicLink { preview.issues.append(TakeoutIssue(source: url.lastPathComponent, path: safePath, message: "ZIP symbolic link skipped.")) }
                        if item.method != 0 && item.method != 8 { preview.issues.append(TakeoutIssue(source: url.lastPathComponent, path: safePath, message: "Compression method \(item.method) is unsupported.")) }
                        let sidecars = [safePath + ".json", URL(fileURLWithPath: safePath).deletingPathExtension().appendingPathExtension("json").path]
                        let metadata = sidecars.lazy.compactMap { zip.readSmall($0, limit: 1_000_000) }.compactMap(TakeoutMetadata.decode).first
                        var entry = TakeoutEntry(id: "\(url.path)::\(safePath)", source: source, relativePath: safePath, kind: kind, compressedBytes: item.compressedSize, uncompressedBytes: item.uncompressedSize, crc32: item.crc32, compressionMethod: item.method, centralFlags: item.flags, localHeaderOffset: item.localOffset, sourceModifiedAt: metadata?.modifiedDate ?? item.modifiedAt, selected: kind == .document, metadata: metadata)
                        if entry.kind == .document {
                            do {
                                try validateLimits(entry)
                                guard totalExpanded <= maximumExpandedBytes - entry.uncompressedBytes else { throw GoogleTakeoutError.limitsExceeded("supported documents exceed 20 GiB total") }
                                totalExpanded += entry.uncompressedBytes
                            } catch {
                                entry.kind = .unsupported; entry.selected = false
                                preview.issues.append(TakeoutIssue(source: url.lastPathComponent, path: safePath, message: error.localizedDescription))
                            }
                        }
                        preview.entries.append(entry)
                    }
                } catch {
                    preview.issues.append(TakeoutIssue(source: url.lastPathComponent, path: nil, message: error.localizedDescription))
                }
            case .folder(let root):
                let scoped = root.startAccessingSecurityScopedResource(); defer { if scoped { root.stopAccessingSecurityScopedResource() } }
                preview.folderCount += 1
                guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .isPackageKey], options: [.skipsHiddenFiles]) else {
                    preview.issues.append(TakeoutIssue(source: root.lastPathComponent, path: nil, message: "Could not enumerate selected folder.")); continue
                }
                for case let url as URL in enumerator {
                    entryCount += 1
                    if entryCount > maximumEntries { throw GoogleTakeoutError.limitsExceeded("more than \(maximumEntries) files") }
                    let attrs = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .isPackageKey])
                    if attrs?.isSymbolicLink == true {
                        enumerator.skipDescendants()
                        let rel = relativePath(url, root: root)
                        preview.entries.append(TakeoutEntry(id: "\(root.path)::unsafe::\(rel)", source: source, relativePath: rel, kind: .unsafe, compressedBytes: 0, uncompressedBytes: 0, crc32: nil, compressionMethod: nil, centralFlags: nil, localHeaderOffset: nil, sourceModifiedAt: nil, selected: false))
                        preview.issues.append(TakeoutIssue(source: root.lastPathComponent, path: rel, message: "Symbolic link skipped.")); continue
                    }
                    let rel = relativePath(url, root: root)
                    guard safeRelativePath(rel) != nil else {
                        enumerator.skipDescendants(); preview.issues.append(TakeoutIssue(source: root.lastPathComponent, path: rel, message: "Unsafe relative path skipped.")); continue
                    }
                    let isPackage = attrs?.isPackage == true || ["rtfd", "boldwriter"].contains(url.pathExtension.lowercased()) && attrs?.isDirectory == true
                    guard attrs?.isRegularFile == true || isPackage else { continue }
                    if isPackage { enumerator.skipDescendants() }
                    let bytes = isPackage ? (try folderPackageSize(url)) : UInt64(max(0, attrs?.fileSize ?? 0))
                    var item = TakeoutEntry(id: "\(root.path)::\(rel)", source: source, relativePath: rel, kind: classify(rel), compressedBytes: bytes, uncompressedBytes: bytes, crc32: nil, compressionMethod: nil, centralFlags: nil, localHeaderOffset: nil, sourceModifiedAt: attrs?.contentModificationDate, selected: classify(rel) == .document)
                    if item.kind == .document {
                        do {
                            try validateLimits(item)
                            guard totalExpanded <= maximumExpandedBytes - item.uncompressedBytes else { throw GoogleTakeoutError.limitsExceeded("supported documents exceed 20 GiB total") }
                            totalExpanded += item.uncompressedBytes
                        } catch {
                            item.kind = .unsupported; item.selected = false
                            preview.issues.append(TakeoutIssue(source: root.lastPathComponent, path: rel, message: error.localizedDescription))
                        }
                    }
                    preview.entries.append(item)
                }
            }
        }
        attachFolderMetadata(to: &preview.entries)
        preview.entries.sort { $0.source.url.path == $1.source.url.path ? $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending : $0.source.url.path < $1.source.url.path }
        return preview
    }

    static func safeRelativePath(_ path: String) -> String? {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.hasPrefix("~"), !path.hasPrefix("-"), !path.contains("\\"), !path.contains(":"), !path.unicodeScalars.contains(where: { $0.value == 0 }) else { return nil }
        if path.count >= 2, path[path.index(after: path.startIndex)] == ":" { return nil }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && $0.count <= 255 && !$0.hasSuffix(".") && !$0.hasSuffix(" ") }) else { return nil }
        return parts.joined(separator: "/")
    }

    static func classify(_ path: String) -> TakeoutItemKind {
        let lower = path.lowercased()
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        if lower.hasSuffix(".json") { return .metadata }
        if ["jpg", "jpeg", "png", "gif", "heic", "heif", "tif", "tiff", "bmp", "webp", "raw", "cr2", "nef", "arw"].contains(ext) { return .photo }
        if ["mp4", "mov", "m4v", "avi", "mkv", "webm", "3gp", "mpeg", "mpg"].contains(ext) { return .video }
        if ["boldwriter", "txt", "md", "markdown", "docx", "pdf", "rtf", "rtfd", "html", "htm"].contains(ext) { return .document }
        return .unsupported
    }

    private static func validateLimits(_ item: TakeoutEntry) throws {
        guard item.uncompressedBytes <= maximumEntryBytes else { throw GoogleTakeoutError.limitsExceeded("file \(item.relativePath) exceeds 512 MiB") }
        if item.uncompressedBytes > 0 {
            guard item.uncompressedBytes <= maximumExpandedBytes else { throw GoogleTakeoutError.limitsExceeded("expanded size exceeds 20 GiB") }
            if item.compressedBytes == 0 || item.uncompressedBytes / max(1, item.compressedBytes) > maximumCompressionRatio {
                throw GoogleTakeoutError.limitsExceeded("compression ratio is excessive for \(item.relativePath)")
            }
        }
    }

    private static func relativePath(_ url: URL, root: URL) -> String {
        let base = root.standardizedFileURL.pathComponents
        let full = url.standardizedFileURL.pathComponents
        return full.dropFirst(base.count).joined(separator: "/")
    }

    private static func folderPackageSize(_ root: URL) throws -> UInt64 {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey], options: [.skipsHiddenFiles]) else { throw CocoaError(.fileReadNoPermission) }
        var total: UInt64 = 0
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            if values.isSymbolicLink == true { enumerator.skipDescendants(); throw GoogleTakeoutError.unsafePath(url.lastPathComponent) }
            if values.isRegularFile == true { total &+= UInt64(max(0, values.fileSize ?? 0)); guard total <= maximumEntryBytes else { throw GoogleTakeoutError.limitsExceeded("package \(root.lastPathComponent) exceeds 512 MiB") } }
        }
        return total
    }

    private static func attachFolderMetadata(to entries: inout [TakeoutEntry]) {
        let bySourceAndPath = Dictionary(uniqueKeysWithValues: entries.enumerated().map { ("\($0.element.source.url.path)::\($0.element.relativePath)", $0.offset) })
        for index in entries.indices where entries[index].kind == .document {
            let path = entries[index].relativePath
            let candidates = [path + ".json", URL(fileURLWithPath: path).deletingPathExtension().appendingPathExtension("json").path]
            for sidecar in candidates {
                guard bySourceAndPath["\(entries[index].source.url.path)::\(sidecar)"] != nil,
                      case .folder(let root) = entries[index].source else { continue }
                let url = root.appendingPathComponent(sidecar)
                guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]), values.isRegularFile == true, values.isSymbolicLink != true, let size = values.fileSize, size <= 1_000_000,
                      let data = try? Data(contentsOf: url) else { continue }
                entries[index].metadata = TakeoutMetadata.decode(data)
                entries[index].sourceModifiedAt = entries[index].metadata?.modifiedDate ?? entries[index].sourceModifiedAt
                break
            }
        }
    }
}

struct ZIPDirectoryEntry {
    let path: String
    let compressedSize: UInt64
    let uncompressedSize: UInt64
    let crc32: UInt32
    let method: UInt16
    let flags: UInt16
    let localOffset: UInt64
    let isSymbolicLink: Bool
    let modifiedAt: Date?
}

/// ZIP central-directory reader with ZIP64 support. Entry paths remain data until
/// callers validate them; symbolic links and multi-disk archives are rejected.
struct SafeTakeoutZIP {
    let url: URL
    let entries: [ZIPDirectoryEntry]
    private let fileSize: UInt64

    init(url: URL) throws {
        self.url = url
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize, size >= 22 else { throw GoogleTakeoutError.malformedArchive("file is too short") }
        fileSize = UInt64(size)
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        let tailLength = min(size, 65_557)
        try handle.seek(toOffset: UInt64(size - tailLength))
        let tail = try handle.read(upToCount: tailLength) ?? Data()
        guard let eocdOffset = Self.findEndRecord(in: tail) else { throw GoogleTakeoutError.malformedArchive("end record is missing or malformed") }
        let eocd = tail.subdata(in: eocdOffset..<(eocdOffset + 22))
        let diskNumber = eocd.u16(4), centralDisk = eocd.u16(6)
        guard diskNumber == 0, centralDisk == 0 else { throw GoogleTakeoutError.unsupportedArchive("multi-disk ZIP layout; select Google Takeout's numbered ZIP parts together") }
        var entryCount = UInt64(eocd.u16(10)), directorySize = UInt64(eocd.u32(12)), directoryOffset = UInt64(eocd.u32(16))
        if entryCount == 0xFFFF || directorySize == 0xFFFF_FFFF || directoryOffset == 0xFFFF_FFFF {
            let absoluteEOCD = UInt64(size - tailLength + eocdOffset)
            guard absoluteEOCD >= 20 else { throw GoogleTakeoutError.malformedArchive("ZIP64 locator missing") }
            let locator = try Self.read(handle, at: absoluteEOCD - 20, count: 20)
            guard locator.u32(0) == 0x07064b50, locator.u32(4) == 0, locator.u32(16) == 1 else { throw GoogleTakeoutError.unsupportedArchive("ZIP64 multi-disk archives are not supported") }
            let zip64Offset = locator.u64(8)
            let record = try Self.read(handle, at: zip64Offset, count: 56)
            guard record.u32(0) == 0x06064b50, record.u32(16) == 0, record.u32(20) == 0 else { throw GoogleTakeoutError.malformedArchive("invalid ZIP64 end record") }
            entryCount = record.u64(32); directorySize = record.u64(40); directoryOffset = record.u64(48)
        }
        guard entryCount <= UInt64(GoogleTakeoutScanner.maximumEntries), directorySize <= 64 * 1024 * 1024,
              directoryOffset <= fileSize, directorySize <= fileSize - directoryOffset else { throw GoogleTakeoutError.limitsExceeded("central directory is too large or out of bounds") }
        var entries: [ZIPDirectoryEntry] = []; entries.reserveCapacity(Int(entryCount))
        var offset = directoryOffset
        var seen = Set<String>(), caseInsensitiveNames = Set<String>()
        for _ in 0..<entryCount {
            let header = try Self.read(handle, at: offset, count: 46)
            guard header.u32(0) == 0x02014b50 else { throw GoogleTakeoutError.malformedArchive("invalid central directory entry") }
            let flags = header.u16(8), method = header.u16(10), crc = header.u32(16)
            let modifiedAt = Self.dosDate(time: header.u16(12), date: header.u16(14))
            let rawCompressed = UInt64(header.u32(20)), rawUncompressed = UInt64(header.u32(24))
            let nameLength = Int(header.u16(28)), extraLength = Int(header.u16(30)), commentLength = Int(header.u16(32))
            let diskStart = header.u16(34), external = header.u32(38), rawLocalOffset = UInt64(header.u32(42))
            guard diskStart == 0 else { throw GoogleTakeoutError.unsupportedArchive("split entry spans multiple archive disks") }
            guard flags & (1 | (1 << 6) | (1 << 13)) == 0 else { throw GoogleTakeoutError.unsupportedArchive("encrypted ZIP entries") }
            let variable = try Self.read(handle, at: offset + 46, count: nameLength + extraLength + commentLength)
            let rawName = variable.prefix(nameLength)
            guard let name = Self.decodeName(Data(rawName), utf8: flags & 0x0800 != 0) else { throw GoogleTakeoutError.malformedArchive("filename cannot be decoded") }
            let extra = Data(variable.dropFirst(nameLength).prefix(extraLength))
            var compressed = rawCompressed, uncompressed = rawUncompressed, localOffset = rawLocalOffset
            if rawCompressed == 0xFFFF_FFFF || rawUncompressed == 0xFFFF_FFFF || rawLocalOffset == 0xFFFF_FFFF {
                guard let zip64 = Self.zip64(extra) else { throw GoogleTakeoutError.malformedArchive("ZIP64 size fields are missing") }
                var cursor = 0
                if rawUncompressed == 0xFFFF_FFFF { guard cursor + 8 <= zip64.count else { throw GoogleTakeoutError.malformedArchive("truncated ZIP64 size") }; uncompressed = zip64.u64(cursor); cursor += 8 }
                if rawCompressed == 0xFFFF_FFFF { guard cursor + 8 <= zip64.count else { throw GoogleTakeoutError.malformedArchive("truncated ZIP64 size") }; compressed = zip64.u64(cursor); cursor += 8 }
                if rawLocalOffset == 0xFFFF_FFFF { guard cursor + 8 <= zip64.count else { throw GoogleTakeoutError.malformedArchive("truncated ZIP64 local offset") }; localOffset = zip64.u64(cursor) }
            }
            let unixMode = external >> 16, kind = unixMode & 0xF000
            let isDirectory = name.hasSuffix("/") || kind == 0x4000
            let candidatePath = isDirectory && name.hasSuffix("/") ? String(name.dropLast()) : name
            let filesystemKey = candidatePath.precomposedStringWithCanonicalMapping.lowercased()
            guard seen.insert(candidatePath).inserted, caseInsensitiveNames.insert(filesystemKey).inserted else { throw GoogleTakeoutError.malformedArchive("duplicate or case-colliding path \(name)") }
            if isDirectory {
                if GoogleTakeoutScanner.safeRelativePath(candidatePath) == nil {
                    entries.append(ZIPDirectoryEntry(path: name, compressedSize: compressed, uncompressedSize: uncompressed, crc32: crc, method: method, flags: flags, localOffset: localOffset, isSymbolicLink: false, modifiedAt: modifiedAt))
                }
            } else {
                if kind == 0xA000 {
                    entries.append(ZIPDirectoryEntry(path: candidatePath, compressedSize: compressed, uncompressedSize: uncompressed, crc32: crc, method: method, flags: flags, localOffset: localOffset, isSymbolicLink: true, modifiedAt: modifiedAt))
                    offset += UInt64(46 + nameLength + extraLength + commentLength); continue
                }
                guard kind == 0 || kind == 0x8000 else { throw GoogleTakeoutError.unsafePath(candidatePath) }
                guard method == 0 || method == 8 else {
                    entries.append(ZIPDirectoryEntry(path: candidatePath, compressedSize: compressed, uncompressedSize: uncompressed, crc32: crc, method: method, flags: flags, localOffset: localOffset, isSymbolicLink: false, modifiedAt: modifiedAt))
                    offset += UInt64(46 + nameLength + extraLength + commentLength); continue
                }
                entries.append(ZIPDirectoryEntry(path: candidatePath, compressedSize: compressed, uncompressedSize: uncompressed, crc32: crc, method: method, flags: flags, localOffset: localOffset, isSymbolicLink: false, modifiedAt: modifiedAt))
            }
            offset += UInt64(46 + nameLength + extraLength + commentLength)
        }
        self.entries = entries
    }

    static func extract(_ entry: TakeoutEntry, from url: URL, to destination: URL, shouldCancel: () -> Bool) throws {
        guard let expectedCRC = entry.crc32, let method = entry.compressionMethod, let flags = entry.centralFlags, let offset = entry.localHeaderOffset else { throw GoogleTakeoutError.extractionFailed(entry.relativePath) }
        let archiveSize = UInt64((try url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        guard offset < archiveSize else { throw GoogleTakeoutError.malformedArchive("local entry offset is outside the archive") }
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        let header = try Self.read(handle, at: offset, count: 30)
        guard header.u32(0) == 0x04034b50, header.u16(8) == method, header.u16(6) == flags, header.u16(6) & 1 == 0 else { throw GoogleTakeoutError.malformedArchive("local entry header does not match \(entry.relativePath)") }
        let nameLength = Int(header.u16(26)), extraLength = Int(header.u16(28))
        let dataOffset = offset + UInt64(30 + nameLength + extraLength)
        guard dataOffset <= archiveSize, entry.compressedBytes <= archiveSize - dataOffset else { throw GoogleTakeoutError.malformedArchive("entry data is outside the archive") }
        let localVariable = try Self.read(handle, at: offset + 30, count: nameLength + extraLength)
        guard let localName = Self.decodeName(Data(localVariable.prefix(nameLength)), utf8: flags & 0x0800 != 0), localName == entry.relativePath else { throw GoogleTakeoutError.malformedArchive("local entry name mismatch") }

        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let output = FileManager.default.createFile(atPath: destination.path, contents: nil)
        guard output else { throw GoogleTakeoutError.extractionFailed(entry.relativePath) }
        let sink = try FileHandle(forWritingTo: destination); defer { try? sink.close() }
        var completed = false
        defer { if !completed { try? FileManager.default.removeItem(at: destination) } }
        let pipe = Pipe(); let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", url.path, Self.escapeUnzipPattern(entry.relativePath)]
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw GoogleTakeoutError.extractionFailed(entry.relativePath) }
        defer { if process.isRunning { process.terminate(); process.waitUntilExit() } }
        pipe.fileHandleForWriting.closeFile()
        var written: UInt64 = 0; var crc: UInt32 = 0xFFFF_FFFF
        while let chunk = try pipe.fileHandleForReading.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            if shouldCancel() { process.terminate(); process.waitUntilExit(); throw GoogleTakeoutError.cancelled }
            written &+= UInt64(chunk.count)
            guard written <= entry.uncompressedBytes, written <= GoogleTakeoutScanner.maximumEntryBytes else { process.terminate(); throw GoogleTakeoutError.limitsExceeded("actual expansion exceeds declared bounds") }
            try sink.write(contentsOf: chunk); crc = CRC32.update(crc, with: chunk)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0, written == entry.uncompressedBytes, ~crc == expectedCRC else {
            try? FileManager.default.removeItem(at: destination)
            throw GoogleTakeoutError.extractionFailed(entry.relativePath + " (size or CRC validation failed)")
        }
        completed = true
    }

    func readSmall(_ path: String, limit: Int) -> Data? {
        guard let entry = entries.first(where: { $0.path == path }), !entry.isSymbolicLink,
              entry.method == 0 || entry.method == 8, entry.uncompressedSize <= UInt64(limit),
              let safe = GoogleTakeoutScanner.safeRelativePath(path), safe == path else { return nil }
        let pipe = Pipe(), process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", url.path, Self.escapeUnzipPattern(path)]
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        defer { if process.isRunning { process.terminate(); process.waitUntilExit() } }
        pipe.fileHandleForWriting.closeFile()
        var output = Data(); var crc: UInt32 = 0xFFFF_FFFF
        do {
            while let chunk = try pipe.fileHandleForReading.read(upToCount: 64 * 1024), !chunk.isEmpty {
                guard output.count + chunk.count <= limit else { process.terminate(); return nil }
                output.append(chunk); crc = CRC32.update(crc, with: chunk)
            }
        } catch { process.terminate(); return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0, UInt64(output.count) == entry.uncompressedSize, ~crc == entry.crc32 else { return nil }
        return output
    }

    private static func read(_ handle: FileHandle, at offset: UInt64, count: Int) throws -> Data {
        try handle.seek(toOffset: offset)
        let data = try handle.read(upToCount: count) ?? Data()
        guard data.count == count else { throw GoogleTakeoutError.malformedArchive("truncated ZIP record") }
        return data
    }
    private static func escapeUnzipPattern(_ path: String) -> String {
        path.replacingOccurrences(of: "[", with: "[[]")
            .replacingOccurrences(of: "*", with: "[*]")
            .replacingOccurrences(of: "?", with: "[?]")
    }
    private static func decodeName(_ data: Data, utf8: Bool) -> String? {
        if utf8 { return String(data: data, encoding: .utf8) }
        let dosLatinUS = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(0x0400)))
        return String(data: data, encoding: dosLatinUS) ?? String(data: data, encoding: .utf8)
    }
    private static func dosDate(time: UInt16, date: UInt16) -> Date? {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: Int((date >> 9) & 0x7F) + 1980, month: Int((date >> 5) & 0x0F), day: Int(date & 0x1F), hour: Int((time >> 11) & 0x1F), minute: Int((time >> 5) & 0x3F), second: Int(time & 0x1F) * 2)
        return calendar.date(from: components)
    }
    private static func findEndRecord(in data: Data) -> Int? {
        guard data.count >= 22 else { return nil }
        for index in stride(from: data.count - 22, through: 0, by: -1) {
            guard data.u32(index) == 0x06054b50 else { continue }
            let commentLength = Int(data.u16(index + 20))
            if index + 22 + commentLength == data.count { return index }
        }
        return nil
    }
    private static func zip64(_ data: Data) -> Data? {
        var offset = 0
        while offset + 4 <= data.count {
            let id = data.u16(offset), length = Int(data.u16(offset + 2)); offset += 4
            guard offset + length <= data.count else { return nil }
            if id == 0x0001 { return data.subdata(in: offset..<(offset + length)) }
            offset += length
        }
        return nil
    }
}

private enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { initial in
        (0..<8).reduce(UInt32(initial)) { value, _ in value & 1 == 1 ? (value >> 1) ^ 0xEDB88320 : value >> 1 }
    }
    static func update(_ value: UInt32, with data: Data) -> UInt32 {
        data.reduce(value) { table[Int(($0 ^ UInt32($1)) & 0xFF)] ^ ($0 >> 8) }
    }
}

private extension Data {
    func u16(_ offset: Int) -> UInt16 { UInt16(self[offset]) | UInt16(self[offset + 1]) << 8 }
    func u32(_ offset: Int) -> UInt32 { UInt32(u16(offset)) | UInt32(u16(offset + 2)) << 16 }
    func u64(_ offset: Int) -> UInt64 { UInt64(u32(offset)) | UInt64(u32(offset + 4)) << 32 }
}

extension TakeoutMetadata {
    static func decode(_ data: Data) -> TakeoutMetadata? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func string(_ keys: String...) -> String? { keys.lazy.compactMap { json[$0] as? String }.first }
        let originalURL = string("url", "webViewLink", "alternateLink")
        let explicitID = string("id", "fileId", "googleId")
        let url = originalURL.flatMap(URL.init(string:))
        let isGoogleURL = ["docs.google.com", "drive.google.com", "sheets.google.com", "slides.google.com"].contains { url?.host?.lowercased() == $0 }
        let pathParts = url?.path.split(separator: "/") ?? []
        let pathID: String? = isGoogleURL ? pathParts.indices.first(where: { ["d", "folders"].contains(String(pathParts[$0])) && $0 + 1 < pathParts.count }).map { String(pathParts[$0 + 1]) } : nil
        let queryID = isGoogleURL ? URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "id" })?.value : nil
        return TakeoutMetadata(googleID: explicitID ?? queryID ?? pathID, originalURL: originalURL, title: string("title", "name"), description: string("description"), createdTime: string("createdTime", "creationTime"), modifiedTime: string("modifiedTime", "modificationTime"))
    }
}
