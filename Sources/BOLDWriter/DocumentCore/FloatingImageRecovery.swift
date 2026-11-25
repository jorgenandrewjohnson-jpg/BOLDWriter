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

/// Full, independently openable native backups, separate from the live file.
/// Each successful generation has its own atomic package and older generations
/// are pruned only after the new package is safely written.
enum ManuscriptRecovery {
    static func recoveryRoot(root: URL? = nil) throws -> URL {
        if let root { return root }
        let support = try FileManager.default.url(for: .applicationSupportDirectory,
                                                   in: .userDomainMask, appropriateFor: nil, create: true)
        let identity = Bundle.main.bundleIdentifier ?? "BOLDWriter"
        return support.appendingPathComponent("BOLD Writer/Manuscript Recovery", isDirectory: true)
            .appendingPathComponent(identity, isDirectory: true)
    }

    static func save(text: NSAttributedString, metadata: DocumentMetadata,
                     sourceURL: URL?, sessionID: UUID, root: URL? = nil) throws -> URL {
        let fm = FileManager.default
        let root = try recoveryRoot(root: root)
        let identity = sourceURL?.standardizedFileURL.path ?? sessionID.uuidString
        let digest = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        let name = String((sourceURL?.deletingPathExtension().lastPathComponent ?? "Untitled").prefix(80))
        let folder = root.appendingPathComponent(name + "-" + digest, isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        let stamp = String(format: "%020.0f", Date().timeIntervalSince1970 * 1_000_000)
        let destination = folder.appendingPathComponent(stamp + "-" + UUID().uuidString + ".boldwriter", isDirectory: true)
        let package = try BOLDWriterDocument.packageWrapper(text: text, metadata: metadata)
        try package.write(to: destination, options: .atomic, originalContentsURL: nil)
        // Retain three independently openable generations. Failure to prune
        // must not turn an already durable checkpoint into a failed save.
        if let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            let older = files.filter { $0.pathExtension == "boldwriter" && $0.lastPathComponent != destination.lastPathComponent }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
            for stale in older.dropFirst(2) { try? fm.removeItem(at: stale) }
        }
        return destination
    }
}
