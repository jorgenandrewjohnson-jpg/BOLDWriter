import AppKit
import CryptoKit
import Foundation
import SwiftUI

struct TakeoutFolderGroup: Identifiable {
    let key: String
    let label: String
    let total: Int
    let selected: Int
    var id: String { key }
}

struct TakeoutFormatGroup: Identifiable {
    let format: String
    let total: Int
    let selected: Int
    var id: String { format }
}

private final class TakeoutCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func cancel() { lock.lock(); value = true; lock.unlock() }
}

@MainActor final class GoogleTakeoutImportModel: ObservableObject {
    @Published private(set) var preview: TakeoutPreview?
    @Published private(set) var isScanning = false
    @Published private(set) var isImporting = false
    @Published private(set) var completedCount = 0
    @Published private(set) var importedCount = 0
    @Published private(set) var duplicateCount = 0
    @Published private(set) var unchangedCount = 0
    @Published private(set) var failures: [String] = []
    @Published private(set) var currentItem: String?
    @Published private(set) var resultByEntry: [String: String] = [:]
    @Published private(set) var errorMessage: String?
    private(set) var sources: [TakeoutSource] = []
    private let library: KnowledgeLibraryStore
    @Published var collectionID: KnowledgeCollectionID = KnowledgeLibraryStore.defaultCollectionID
    private var importStartedAt: Date?
    private var cancellation: TakeoutCancellation?
    private var importTask: Task<Void, Never>?

    init(library: KnowledgeLibraryStore? = nil, collectionID: KnowledgeCollectionID? = nil) {
        self.library = library ?? .shared
        _collectionID = Published(initialValue: collectionID ?? KnowledgeLibraryStore.defaultCollectionID)
    }

    func showError(_ message: String) { errorMessage = message }
    func clearError() { errorMessage = nil }

    var selectedDocuments: [TakeoutEntry] { preview?.selectedDocuments ?? [] }
    var selectedBytes: UInt64 { selectedDocuments.reduce(0) { $0 &+ $1.uncompressedBytes } }
    var copiedSourceBytes: UInt64 { preview?.additionalSourceBytes ?? 0 }
    var estimatedIndexBytes: UInt64 { preview?.estimatedIndexBytes ?? 0 }
    var estimatedAdditionalBytes: UInt64 { copiedSourceBytes + estimatedIndexBytes }
    var availableBytes: UInt64 {
        let path = library.databaseURL.deletingLastPathComponent().path
        let values = try? FileManager.default.attributesOfFileSystem(forPath: path)
        return UInt64((values?[.systemFreeSize] as? NSNumber)?.int64Value ?? 0)
    }
    var hasEnoughSpace: Bool { copiedSourceBytes + estimatedIndexBytes + 256 * 1024 * 1024 <= availableBytes }
    var progress: Double {
        let count = preview?.selectedDocuments.count ?? 0
        return count == 0 ? 0 : Double(completedCount) / Double(count)
    }
    var folders: [TakeoutFolderGroup] {
        guard let entries = preview?.entries else { return [] }
        return Dictionary(grouping: entries.filter { $0.kind == .document }, by: folderKey).map { key, values in
            let first = values[0], folder = first.folderPath.isEmpty ? "(root)" : first.folderPath
            return TakeoutFolderGroup(key: key, label: "\(first.source.label) / \(folder)", total: values.count, selected: values.filter(\.selected).count)
        }.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }
    var formats: [TakeoutFormatGroup] {
        guard let entries = preview?.entries else { return [] }
        return Dictionary(grouping: entries.filter { $0.kind == .document }, by: \.format).map { format, values in
            TakeoutFormatGroup(format: format.uppercased(), total: values.count, selected: values.filter(\.selected).count)
        }.sorted { $0.format < $1.format }
    }

    func scan(_ newSources: [TakeoutSource]) {
        Task { await scanAndWait(newSources) }
    }

    func scanAndWait(_ newSources: [TakeoutSource]) async {
        sources = newSources
        preview = nil; errorMessage = nil; failures = []; resultByEntry = [:]; isScanning = true
        do {
            let result = try await Task.detached(priority: .userInitiated) { try GoogleTakeoutScanner.scan(newSources) }.value
            preview = result
        } catch { errorMessage = error.localizedDescription }
        isScanning = false
    }

    func setSelected(_ id: String, _ isSelected: Bool) {
        guard var preview, let index = preview.entries.firstIndex(where: { $0.id == id }), preview.entries[index].kind == .document else { return }
        preview.entries[index].selected = isSelected
        self.preview = preview
    }

    func setFolder(_ key: String, selected: Bool) {
        guard var preview else { return }
        for index in preview.entries.indices where preview.entries[index].kind == .document && folderKey(preview.entries[index]) == key {
            preview.entries[index].selected = selected
        }
        self.preview = preview
    }

    func setFormat(_ format: String, selected: Bool) {
        guard var preview else { return }
        for index in preview.entries.indices where preview.entries[index].kind == .document && preview.entries[index].format == format {
            preview.entries[index].selected = selected
        }
        self.preview = preview
    }

    func cancelImport() { cancellation?.cancel() }

    func startImport() {
        guard let (work, token) = prepareImport() else { return }
        importTask = Task { await performImport(work, cancellation: token) }
    }

    func importSelectedAndWait() async {
        guard let (work, token) = prepareImport() else { return }
        await performImport(work, cancellation: token)
    }

    func waitForImport() async { await importTask?.value }

    private func prepareImport() -> ([TakeoutEntry], TakeoutCancellation)? {
        guard !isImporting, !selectedDocuments.isEmpty, hasEnoughSpace else { return nil }
        let work = selectedDocuments, token = TakeoutCancellation()
        cancellation = token; isImporting = true; completedCount = 0; importedCount = 0; duplicateCount = 0; unchangedCount = 0; failures = []; resultByEntry = [:]; importStartedAt = Date()
        return (work, token)
    }

    private func performImport(_ work: [TakeoutEntry], cancellation token: TakeoutCancellation) async {
        for entry in work {
            if token.isCancelled { break }
            currentItem = entry.relativePath
            do {
                let outcome = try await process(entry, cancellation: token)
                switch outcome {
                case .imported: importedCount += 1; resultByEntry[entry.id] = "Imported"
                case .duplicate: duplicateCount += 1; resultByEntry[entry.id] = "Duplicate content linked"
                case .unchanged: unchangedCount += 1; resultByEntry[entry.id] = "Already current"
                }
            } catch {
                failures.append("\(entry.relativePath): \(error.localizedDescription)")
                resultByEntry[entry.id] = "Failed"
            }
            completedCount += 1
            if completedCount.isMultiple(of: 4) { library.reloadDocumentList() }
            await Task.yield()
        }
        library.reloadDocumentList()
        if token.isCancelled { errorMessage = GoogleTakeoutError.cancelled.localizedDescription }
        let session = KnowledgeImportSession(id: UUID(), sourceLabel: sources.map { $0.url.lastPathComponent }.joined(separator: ", "), startedAt: importStartedAt ?? Date(), completedAt: Date(), imported: importedCount, duplicates: duplicateCount, unchanged: unchangedCount, failures: failures.count, cancelled: token.isCancelled, summary: sessionSummary())
        try? library.recordTakeoutImportSession(session)
        currentItem = nil; isImporting = false; cancellation = nil
    }

    private enum EntryOutcome { case imported, duplicate, unchanged }

    private func process(_ entry: TakeoutEntry, cancellation token: TakeoutCancellation) async throws -> EntryOutcome {
        let sourceIdentity: String
        if let googleID = entry.metadata?.googleID, !googleID.isEmpty { sourceIdentity = "google-drive:\(googleID)" }
        else { sourceIdentity = "takeout-source:\(entry.source.url.standardizedFileURL.path)::\(entry.relativePath)" }
        let prior = try library.takeoutImport(sourceIdentity: sourceIdentity)
        let libraryRoot = library.databaseURL.deletingLastPathComponent()
        let stagingRoot = libraryRoot.appendingPathComponent("ImportStaging/\(UUID().uuidString)", isDirectory: true)
        let stagedURL = Self.append(entry.relativePath, to: stagingRoot)
        var importURL: URL
        var ownsNewSourceCopy = false
        let digest: (sha256: String, bytes: UInt64)
        do {
            switch entry.source {
            case .archive:
                digest = try await Task.detached(priority: .utility) {
                    try Self.stage(entry, to: stagedURL, shouldCancel: { token.isCancelled })
                    return try Self.fingerprint(stagedURL, shouldCancel: { token.isCancelled })
                }.value
                importURL = stagedURL
            case .folder(let root):
                let source = Self.append(entry.relativePath, to: root).standardizedFileURL
                guard source.path.hasPrefix(root.standardizedFileURL.path + "/") else { throw GoogleTakeoutError.unsafePath(entry.relativePath) }
                let scoped = root.startAccessingSecurityScopedResource(); defer { if scoped { root.stopAccessingSecurityScopedResource() } }
                digest = try await Task.detached(priority: .utility) { try Self.fingerprintFolderEntry(source, root: root, shouldCancel: { token.isCancelled }) }.value
                importURL = source
            }
        } catch {
            try? FileManager.default.removeItem(at: stagingRoot)
            throw error
        }
        if let prior, prior.fingerprint == digest.sha256 {
            try library.recordTakeoutImport(makeRecord(entry, sourceIdentity: sourceIdentity, documentID: prior.documentID, fingerprint: digest.sha256, importedAt: prior.importedAt))
            try library.addToCollection(documentID: prior.documentID, collectionID: collectionID, sourceFolder: entry.folderPath)
            try? FileManager.default.removeItem(at: stagingRoot)
            return .unchanged
        }

        do {
            if let matching = try library.documentID(matchingFingerprint: digest.sha256), matching != prior?.documentID {
                let record = makeRecord(entry, sourceIdentity: sourceIdentity, documentID: matching, fingerprint: digest.sha256)
                try library.recordTakeoutImport(record)
                try library.addToCollection(documentID: matching, collectionID: collectionID, sourceFolder: entry.folderPath)
                try? FileManager.default.removeItem(at: stagingRoot)
                return .duplicate
            }
            if case .archive = entry.source {
                let identityFolder = Self.sha(Data(sourceIdentity.utf8))
                let version = String(digest.sha256.prefix(24))
                let destination = Self.append(entry.relativePath, to: libraryRoot.appendingPathComponent("ImportedSources/GoogleTakeout/\(identityFolder)/\(version)", isDirectory: true))
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: destination.path) {
                    guard (try? Self.fingerprint(destination).sha256) == digest.sha256 else { throw GoogleTakeoutError.extractionFailed(entry.relativePath + " (destination collision)") }
                    try? FileManager.default.removeItem(at: stagingRoot)
                } else {
                    try FileManager.default.moveItem(at: stagedURL, to: destination)
                    ownsNewSourceCopy = true
                    try? FileManager.default.removeItem(at: stagingRoot)
                }
                importURL = destination
            }
            let record = makeRecord(entry, sourceIdentity: sourceIdentity, documentID: prior?.documentID ?? KnowledgeDocumentID(), fingerprint: digest.sha256)
            let title = entry.metadata?.title.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
            _ = try library.add(url: importURL, preferredDocumentID: prior?.documentID, provenanceLabel: "Google Takeout · \(entry.format.uppercased())", titleLabel: title, expectedFingerprint: digest.sha256, takeoutRecord: record, collectionID: collectionID, sourceFolder: entry.folderPath, publishUpdates: false)
            return .imported
        } catch {
            try? FileManager.default.removeItem(at: stagingRoot)
            if ownsNewSourceCopy {
                try? FileManager.default.removeItem(at: importURL)
                let importedRoot = libraryRoot.appendingPathComponent("ImportedSources", isDirectory: true).standardizedFileURL
                var parent = importURL.deletingLastPathComponent().standardizedFileURL
                while parent.path.hasPrefix(importedRoot.path + "/"),
                      let children = try? FileManager.default.contentsOfDirectory(atPath: parent.path), children.isEmpty {
                    try? FileManager.default.removeItem(at: parent)
                    parent = parent.deletingLastPathComponent()
                }
            }
            throw error
        }
    }

    private func makeRecord(_ entry: TakeoutEntry, sourceIdentity: String, documentID: KnowledgeDocumentID, fingerprint: String, importedAt: Date = Date()) -> KnowledgeTakeoutImportRecord {
        KnowledgeTakeoutImportRecord(sourceIdentity: sourceIdentity, documentID: documentID, relativePath: entry.relativePath, originalFilename: URL(fileURLWithPath: entry.relativePath).lastPathComponent, exportFormat: entry.format, fingerprint: fingerprint, importedAt: importedAt, googleFileID: entry.metadata?.googleID, originalURL: entry.metadata?.originalURL, metadata: entry.metadata, archiveCRC32: entry.crc32, sourceBytes: entry.uncompressedBytes, sourceModifiedAt: entry.sourceModifiedAt, sourceContainerURI: entry.source.url.standardizedFileURL.absoluteString)
    }

    private func folderKey(_ entry: TakeoutEntry) -> String { "\(entry.source.url.path)::\(entry.folderPath.isEmpty ? "(root)" : entry.folderPath)" }

    private func sessionSummary() -> [String] {
        let messages = (preview?.issues.map { issue in "\(issue.source)\(issue.path.map { ": \($0)" } ?? ""): \(issue.message)" } ?? []) + failures
        let kept = Array(messages.prefix(100))
        guard messages.count > kept.count else { return kept }
        return kept + ["\(messages.count - kept.count) additional findings were omitted from the saved history. Rescan the source to see the full list."]
    }

    nonisolated private static func append(_ relative: String, to root: URL) -> URL {
        relative.split(separator: "/").reduce(root) { $0.appendingPathComponent(String($1)) }
    }

    nonisolated private static func stage(_ entry: TakeoutEntry, to destination: URL, shouldCancel: () -> Bool) throws {
        guard !shouldCancel(), GoogleTakeoutScanner.safeRelativePath(entry.relativePath) == entry.relativePath else { throw GoogleTakeoutError.cancelled }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        switch entry.source {
        case .archive(let archive):
            let scoped = archive.startAccessingSecurityScopedResource(); defer { if scoped { archive.stopAccessingSecurityScopedResource() } }
            try SafeTakeoutZIP.extract(entry, from: archive, to: destination, shouldCancel: shouldCancel)
        case .folder(let root):
            let scoped = root.startAccessingSecurityScopedResource(); defer { if scoped { root.stopAccessingSecurityScopedResource() } }
            let source = Self.append(entry.relativePath, to: root).standardizedFileURL
            guard source.path.hasPrefix(root.standardizedFileURL.path + "/"), FileManager.default.fileExists(atPath: source.path), !shouldCancel() else { throw GoogleTakeoutError.unsafePath(entry.relativePath) }
            let isDirectory = (try? source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            if isDirectory {
                guard try Self.packageHasNoSymlinks(source) else { throw GoogleTakeoutError.unsafePath(entry.relativePath + " (contains a symbolic link)") }
            } else {
                let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else { throw GoogleTakeoutError.unsafePath(entry.relativePath) }
            }
            try FileManager.default.copyItem(at: source, to: destination)
        }
    }

    nonisolated private static func packageHasNoSymlinks(_ url: URL) throws -> Bool {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [.skipsHiddenFiles]) else { return false }
        for case let child as URL in enumerator {
            let values = try child.resourceValues(forKeys: [.isSymbolicLinkKey])
            if values.isSymbolicLink == true { enumerator.skipDescendants(); return false }
        }
        return true
    }

    nonisolated private static func fingerprintFolderEntry(_ source: URL, root: URL, shouldCancel: () -> Bool) throws -> (sha256: String, bytes: UInt64) {
        let safeRoot = root.resolvingSymlinksInPath().standardizedFileURL.path
        let resolved = source.resolvingSymlinksInPath().standardizedFileURL
        guard resolved.path.hasPrefix(safeRoot + "/") else { throw GoogleTakeoutError.unsafePath(source.lastPathComponent) }
        let values = try source.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey])
        guard values.isSymbolicLink != true, values.isRegularFile == true || values.isDirectory == true else { throw GoogleTakeoutError.unsafePath(source.lastPathComponent) }
        return try fingerprint(source, shouldCancel: shouldCancel)
    }

    nonisolated private static func fingerprint(_ url: URL, shouldCancel: () -> Bool = { false }) throws -> (sha256: String, bytes: UInt64) {
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) else { throw CocoaError(.fileNoSuchFile) }
        var hasher = SHA256(); var total: UInt64 = 0
        func feed(_ file: URL, label: String?) throws {
            if let label { hasher.update(data: Data(label.utf8)); hasher.update(data: Data([0])) }
            let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
            while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
                if shouldCancel() { throw GoogleTakeoutError.cancelled }
                total &+= UInt64(data.count); hasher.update(data: data)
            }
        }
        if directory.boolValue {
            guard try packageHasNoSymlinks(url), let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { throw GoogleTakeoutError.unsafePath(url.lastPathComponent) }
            let files = enumerator.compactMap { $0 as? URL }.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }.sorted { $0.path < $1.path }
            for file in files { try feed(file, label: String(file.path.dropFirst(url.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))) }
        } else { try feed(url, label: nil) }
        guard total <= GoogleTakeoutScanner.maximumEntryBytes else { throw GoogleTakeoutError.limitsExceeded("actual document size exceeds 512 MiB") }
        return (hasher.finalize().map { String(format: "%02x", $0) }.joined(), total)
    }

    private static func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
