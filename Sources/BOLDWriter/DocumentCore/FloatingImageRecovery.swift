import AppKit
import CryptoKit
import Foundation

/// Atomic pre-operation copies keyed by the exact serialized native package.
/// If the app terminates before the new manuscript save commits, reopening the
/// original package can find and restore its checkpoint from Application Support.
enum FloatingImageRecovery {
    static func checkpointURL(text: NSAttributedString, metadata: DocumentMetadata,
                              root: URL? = nil) throws -> URL {
        let package = try BOLDWriterDocument.packageWrapper(text: text, metadata: metadata)
        guard let bytes = package.serializedRepresentation else {
            throw WriterError.message("The floating-image recovery package could not be serialized.")
        }
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        return try directory(root: root).appendingPathComponent("\(digest).boldwriter", isDirectory: true)
    }

    @discardableResult
    static func save(text: NSAttributedString, metadata: DocumentMetadata, root: URL? = nil) throws -> URL {
        let package = try BOLDWriterDocument.packageWrapper(text: text, metadata: metadata)
        guard let bytes = package.serializedRepresentation else {
            throw WriterError.message("The floating-image recovery package could not be serialized.")
        }
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let folder = try directory(root: root)
        let destination = folder.appendingPathComponent("\(digest).boldwriter", isDirectory: true)
        try bytes.write(to: destination, options: .atomic)
        try prune(folder: folder, keeping: 20)
        return destination
    }

    static func restore(text: inout NSAttributedString, metadata: inout DocumentMetadata,
                        root: URL? = nil) throws -> Bool {
        let url = try checkpointURL(text: text, metadata: metadata, root: root)
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let serialized = try Data(contentsOf: url, options: .mappedIfSafe)
        guard let wrapper = FileWrapper(serializedRepresentation: serialized) else {
            throw WriterError.message("The floating-image recovery package is damaged and cannot be reopened.")
        }
        let restored = try BOLDWriterDocument(fileWrapper: wrapper, contentType: .boldWriterDocument)
        text = restored.text
        metadata = restored.metadata
        try FileManager.default.removeItem(at: url)
        return true
    }

    private static func directory(root: URL?) throws -> URL {
        let base = try root ?? FileManager.default.url(for: .applicationSupportDirectory,
                                                        in: .userDomainMask, appropriateFor: nil, create: true)
        let folder = base.appendingPathComponent("BOLD Writer/Floating Image Recovery", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func prune(folder: URL, keeping count: Int) throws {
        let urls = try FileManager.default.contentsOfDirectory(at: folder,
                                                               includingPropertiesForKeys: [.contentModificationDateKey],
                                                               options: [.skipsHiddenFiles])
            .filter { $0.pathExtension == "boldwriter" }
            .sorted {
                let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left > right
            }
        for stale in urls.dropFirst(count) { try? FileManager.default.removeItem(at: stale) }
    }
}
