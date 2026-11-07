import AppKit
import CryptoKit
import Foundation
import PDFKit
import SQLite3
import UniformTypeIdentifiers

struct KnowledgeDocumentID: Codable, Hashable, Identifiable, Sendable { let rawValue: UUID; var id: UUID { rawValue }; init(_ value: UUID = UUID()) { rawValue = value } }
struct KnowledgePassageReference: Codable, Hashable, Identifiable {
    let documentID: KnowledgeDocumentID
    let passageID: UUID
    let sourceURI: String
    let fingerprint: String
    let utf16Range: NSRange
    let excerptSignature: String
    let context: String
    var id: UUID { passageID }
}
enum KnowledgeSourceStatus: String, Codable { case available, changed, unavailable, referenceOnly }
enum KnowledgeReferenceStatus: String, Codable { case current, revalidated, stale, unresolved }
struct KnowledgeDocumentRecord: Identifiable, Codable {
    let id: KnowledgeDocumentID
    var title: String
    var sourceURI: String
    var provenance: String
    var fingerprint: String
    var modifiedAt: Date?
    var byteCount: Int64
    var status: KnowledgeSourceStatus
    var isReference: Bool
}
struct KnowledgeSearchResult: Identifiable {
    let document: KnowledgeDocumentRecord
    let reference: KnowledgePassageReference
    let excerpt: String
    let rank: Double
    var id: UUID { reference.passageID }
}
struct KnowledgeLink: Identifiable, Codable {
    let id: UUID
    let origin: KnowledgePassageReference
    let destination: KnowledgePassageReference
    var description: String?
    var originalSourceLocation: String
    var lastVerifiedStatus: KnowledgeReferenceStatus
}

struct KnowledgeLibraryNavigationRequest: Equatable {
    let reference: KnowledgePassageReference
    let quotation: String
}

@MainActor final class KnowledgeLibraryStore: ObservableObject {
    static let shared: KnowledgeLibraryStore = {
        if let path = ProcessInfo.processInfo.environment["BOLDWRITER_KNOWLEDGE_LIBRARY_ROOT"], !path.isEmpty {
            return KnowledgeLibraryStore(libraryURL: URL(fileURLWithPath: path, isDirectory: true))
        }
        if let bundleIdentifier = Bundle.main.bundleIdentifier, bundleIdentifier != "com.boldwriter.app" {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let root = support.appendingPathComponent("BOLDWriter/KnowledgeLibraries/Acceptance/\(bundleIdentifier)", isDirectory: true)
            return KnowledgeLibraryStore(libraryURL: root)
        }
        return KnowledgeLibraryStore()
    }()
    static let defaultCollectionID = KnowledgeCollectionID(UUID(uuidString: "6A8D5D32-5E4A-49FD-A8FD-5C3B3888D9D1")!)
    @Published private(set) var documents: [KnowledgeDocumentRecord] = []
    @Published private(set) var collections: [KnowledgeCollection] = []
    @Published private(set) var takeoutImportSessions: [KnowledgeImportSession] = []
    @Published private(set) var lastError: String?
    @Published private(set) var pendingNavigationRequest: KnowledgeLibraryNavigationRequest?
    let databaseURL: URL
    private var db: OpaquePointer?

    init(libraryURL suppliedRoot: URL? = nil) {
        let isolatedRoot = ProcessInfo.processInfo.environment["BOLDWRITER_KNOWLEDGE_LIBRARY_ROOT"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
        let root = suppliedRoot ?? isolatedRoot ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BOLDWriter/KnowledgeLibraries/Default", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        Self.removeAbandonedTakeoutStaging(in: root)
        databaseURL = root.appendingPathComponent("library.sqlite3")
        if sqlite3_open(databaseURL.path, &db) != SQLITE_OK { lastError = "Could not open the local library index." }
        if !integrityOK() {
            if let db { sqlite3_close(db); self.db = nil }
            let backup = root.appendingPathComponent("library-corrupt-\(Int(Date().timeIntervalSince1970)).sqlite3")
            try? FileManager.default.moveItem(at: databaseURL, to: backup)
            try? FileManager.default.moveItem(at: URL(fileURLWithPath: databaseURL.path + "-wal"), to: URL(fileURLWithPath: backup.path + "-wal"))
            try? FileManager.default.moveItem(at: URL(fileURLWithPath: databaseURL.path + "-shm"), to: URL(fileURLWithPath: backup.path + "-shm"))
            if sqlite3_open(databaseURL.path, &db) != SQLITE_OK { lastError = "Could not recreate the local library index." }
        }
        execute("PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;")
        execute("CREATE TABLE IF NOT EXISTS documents(id TEXT PRIMARY KEY,title TEXT NOT NULL,uri TEXT NOT NULL,bookmark BLOB,provenance TEXT NOT NULL,fingerprint TEXT NOT NULL,modified REAL,bytes INTEGER NOT NULL,status TEXT NOT NULL,is_reference INTEGER NOT NULL DEFAULT 0);")
        let hadCollections = (try? query("SELECT name FROM sqlite_master WHERE type='table' AND name='knowledge_collections'", [])).map { !$0.isEmpty } ?? false
        execute("CREATE TABLE IF NOT EXISTS knowledge_collections(id TEXT PRIMARY KEY,name TEXT NOT NULL,created REAL NOT NULL);")
        execute("CREATE UNIQUE INDEX IF NOT EXISTS knowledge_collections_name_idx ON knowledge_collections(name COLLATE NOCASE);")
        execute("CREATE TABLE IF NOT EXISTS knowledge_collection_documents(collection_id TEXT NOT NULL REFERENCES knowledge_collections(id) ON DELETE CASCADE,document_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,source_folder TEXT NOT NULL DEFAULT '',added REAL NOT NULL,PRIMARY KEY(collection_id,document_id));")
        execute("CREATE INDEX IF NOT EXISTS knowledge_collection_documents_doc_idx ON knowledge_collection_documents(document_id);")
        execute("CREATE TABLE IF NOT EXISTS takeout_import_sessions(id TEXT PRIMARY KEY,source_label TEXT NOT NULL,started REAL NOT NULL,completed REAL,imported INTEGER NOT NULL,duplicates INTEGER NOT NULL,unchanged INTEGER NOT NULL,failures INTEGER NOT NULL,cancelled INTEGER NOT NULL,summary_json TEXT NOT NULL DEFAULT '[]');")
        execute("CREATE TABLE IF NOT EXISTS passages(id TEXT PRIMARY KEY,document_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,fingerprint TEXT NOT NULL,start INTEGER NOT NULL,length INTEGER NOT NULL,context TEXT NOT NULL,body TEXT NOT NULL,signature TEXT NOT NULL);")
        execute("CREATE VIRTUAL TABLE IF NOT EXISTS passage_fts USING fts5(passage_id UNINDEXED,document_id UNINDEXED,context,body, tokenize='unicode61 remove_diacritics 2');")
        execute("CREATE TABLE IF NOT EXISTS links(id TEXT PRIMARY KEY,origin_json TEXT NOT NULL,destination_json TEXT NOT NULL,description TEXT,source_location TEXT NOT NULL,status TEXT NOT NULL);")
        execute("CREATE TABLE IF NOT EXISTS takeout_imports(source_identity TEXT NOT NULL,document_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,relative_path TEXT NOT NULL,original_filename TEXT NOT NULL,export_format TEXT NOT NULL,fingerprint TEXT NOT NULL,imported_at REAL NOT NULL,google_file_id TEXT,original_url TEXT,metadata_json TEXT NOT NULL DEFAULT '{}',archive_crc INTEGER,source_bytes INTEGER NOT NULL DEFAULT 0,source_modified REAL,source_container_uri TEXT NOT NULL DEFAULT '',PRIMARY KEY(source_identity,fingerprint));")
        execute("CREATE INDEX IF NOT EXISTS documents_uri_idx ON documents(uri);")
        execute("CREATE INDEX IF NOT EXISTS documents_fingerprint_idx ON documents(fingerprint);")
        try? run("INSERT OR IGNORE INTO knowledge_collections(id,name,created) VALUES(?,?,?)", [.text(Self.defaultCollectionID.rawValue.uuidString), .text("My Library"), .double(Date().timeIntervalSince1970)])
        if !hadCollections {
            try? run("INSERT OR IGNORE INTO knowledge_collection_documents(collection_id,document_id,source_folder,added) SELECT ?,id,'',strftime('%s','now') FROM documents", [.text(Self.defaultCollectionID.rawValue.uuidString)])
        }
        reloadCollections()
        reloadTakeoutImportSessions()
        reloadDocuments()
    }
    deinit { if let db { sqlite3_close(db) } }

    private static func removeAbandonedTakeoutStaging(in root: URL) {
        let staging = root.appendingPathComponent("ImportStaging", isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(at: staging, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey]) else { return }
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        for entry in entries {
            guard UUID(uuidString: entry.lastPathComponent) != nil,
                  let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey]),
                  values.isDirectory == true, values.isSymbolicLink != true,
                  let modified = values.contentModificationDate, modified < cutoff else { continue }
            try? FileManager.default.removeItem(at: entry)
        }
    }

    func add(url: URL, preferredDocumentID: KnowledgeDocumentID? = nil, provenanceLabel: String? = nil, titleLabel: String? = nil, expectedFingerprint: String? = nil, takeoutRecord: KnowledgeTakeoutImportRecord? = nil, collectionID: KnowledgeCollectionID? = nil, sourceFolder: String? = nil, publishUpdates: Bool = true) throws -> KnowledgeDocumentID {
        let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let (digest, byteCount) = try Self.fingerprint(url)
        if let expectedFingerprint, digest != expectedFingerprint { throw CocoaError(.fileReadCorruptFile) }
        let attributed = try BOLDWriterDocument(fileWrapper: FileWrapper(url: url), contentType: BOLDWriterDocument.inferredContentType(for: url)).text
        let (verifiedDigest, verifiedBytes) = try Self.fingerprint(url)
        guard digest == verifiedDigest, byteCount == verifiedBytes else { throw CocoaError(.fileReadCorruptFile) }
        let canonicalURL = url.standardizedFileURL
        let existingID = try findExisting(uri: canonicalURL.absoluteString)
        let id = existingID ?? preferredDocumentID ?? KnowledgeDocumentID()
        let targetCollectionID = collectionID ?? (existingID == nil && preferredDocumentID == nil ? Self.defaultCollectionID : nil)
        let bookmark = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        let values = try Self.paragraphs(attributed)
        var takeoutPassageIDs: [String: [UUID]] = [:]
        if takeoutRecord != nil {
            let existingPassages = try query("SELECT id,signature FROM passages WHERE document_id=? ORDER BY start", [.text(id.rawValue.uuidString)])
            for row in existingPassages {
                if let passageID = row.uuid(0) { takeoutPassageIDs[row.string(1), default: []].append(passageID) }
            }
        }
        try transaction {
            try self.insertDocument(id: id, title: titleLabel ?? url.deletingPathExtension().lastPathComponent, uri: canonicalURL.absoluteString,
                                    bookmark: bookmark, provenance: provenanceLabel ?? Self.provenance(url), fingerprint: digest,
                                    modified: (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate),
                                    bytes: byteCount, reference: false)
            try self.deletePassages(id)
            for item in values {
                let signature = Self.sha(Data(item.body.utf8))
                let retainedID = takeoutPassageIDs[signature]?.isEmpty == false ? takeoutPassageIDs[signature]?.removeFirst() : nil
                try self.insertPassage(documentID: id, fingerprint: digest, item: item, passageID: retainedID)
            }
            if let takeoutRecord {
                let normalized = KnowledgeTakeoutImportRecord(sourceIdentity: takeoutRecord.sourceIdentity, documentID: id, relativePath: takeoutRecord.relativePath, originalFilename: takeoutRecord.originalFilename, exportFormat: takeoutRecord.exportFormat, fingerprint: digest, importedAt: takeoutRecord.importedAt, googleFileID: takeoutRecord.googleFileID, originalURL: takeoutRecord.originalURL, metadata: takeoutRecord.metadata, archiveCRC32: takeoutRecord.archiveCRC32, sourceBytes: UInt64(max(0, byteCount)), sourceModifiedAt: takeoutRecord.sourceModifiedAt, sourceContainerURI: takeoutRecord.sourceContainerURI)
                try self.insertTakeoutImport(normalized)
            }
            if let targetCollectionID {
                try self.insertCollectionMembership(documentID: id, collectionID: targetCollectionID, sourceFolder: sourceFolder ?? "")
            }
        }
        if publishUpdates { reloadDocuments(); reloadCollections() }
        return id
    }

    func takeoutImport(sourceIdentity: String) throws -> KnowledgeTakeoutImportRecord? {
        guard let row = try query("SELECT source_identity,document_id,relative_path,original_filename,export_format,fingerprint,imported_at,google_file_id,original_url,metadata_json,archive_crc,source_bytes,source_modified,source_container_uri FROM takeout_imports WHERE source_identity=? ORDER BY imported_at DESC LIMIT 1", [.text(sourceIdentity)]).first,
              let documentID = row.uuid(1) else { return nil }
        let sourceModified = row.double(12)
        return KnowledgeTakeoutImportRecord(sourceIdentity: row.string(0), documentID: KnowledgeDocumentID(documentID), relativePath: row.string(2), originalFilename: row.string(3), exportFormat: row.string(4), fingerprint: row.string(5), importedAt: Date(timeIntervalSince1970: row.double(6)), googleFileID: row.stringOptional(7), originalURL: row.stringOptional(8), metadata: TakeoutMetadata.decode(Data(row.string(9).utf8)), archiveCRC32: row.int(10) == 0 ? nil : UInt32(truncatingIfNeeded: row.int(10)), sourceBytes: UInt64(max(0, row.int(11))), sourceModifiedAt: sourceModified > 0 ? Date(timeIntervalSince1970: sourceModified) : nil, sourceContainerURI: row.string(13))
    }

    func latestTakeoutImport(for documentID: KnowledgeDocumentID) throws -> KnowledgeTakeoutImportRecord? {
        guard let row = try query("SELECT source_identity,document_id,relative_path,original_filename,export_format,fingerprint,imported_at,google_file_id,original_url,metadata_json,archive_crc,source_bytes,source_modified,source_container_uri FROM takeout_imports WHERE document_id=? ORDER BY imported_at DESC LIMIT 1", [.text(documentID.rawValue.uuidString)]).first,
              let id = row.uuid(1) else { return nil }
        let sourceModified = row.double(12)
        return KnowledgeTakeoutImportRecord(sourceIdentity: row.string(0), documentID: KnowledgeDocumentID(id), relativePath: row.string(2), originalFilename: row.string(3), exportFormat: row.string(4), fingerprint: row.string(5), importedAt: Date(timeIntervalSince1970: row.double(6)), googleFileID: row.stringOptional(7), originalURL: row.stringOptional(8), metadata: TakeoutMetadata.decode(Data(row.string(9).utf8)), archiveCRC32: row.int(10) == 0 ? nil : UInt32(truncatingIfNeeded: row.int(10)), sourceBytes: UInt64(max(0, row.int(11))), sourceModifiedAt: sourceModified > 0 ? Date(timeIntervalSince1970: sourceModified) : nil, sourceContainerURI: row.string(13))
    }

    func documentID(matchingFingerprint fingerprint: String) throws -> KnowledgeDocumentID? {
        try query("SELECT id FROM documents WHERE fingerprint=? AND is_reference=0 ORDER BY rowid LIMIT 1", [.text(fingerprint)]).first?.uuid(0).map(KnowledgeDocumentID.init)
    }

    func recordTakeoutImport(_ record: KnowledgeTakeoutImportRecord) throws {
        try insertTakeoutImport(record)
    }

    func addToCollection(documentID: KnowledgeDocumentID, collectionID: KnowledgeCollectionID, sourceFolder: String = "") throws {
        try insertCollectionMembership(documentID: documentID, collectionID: collectionID, sourceFolder: sourceFolder)
        reloadCollections()
    }

    func move(documentID: KnowledgeDocumentID, to collectionID: KnowledgeCollectionID, sourceFolder: String? = nil) throws {
        let priorFolder = try query("SELECT source_folder FROM knowledge_collection_documents WHERE document_id=? LIMIT 1", [.text(documentID.rawValue.uuidString)]).first?.string(0)
        let oldFolder = sourceFolder ?? priorFolder ?? ""
        try transaction {
            try self.run("DELETE FROM knowledge_collection_documents WHERE document_id=?", [.text(documentID.rawValue.uuidString)])
            try self.insertCollectionMembership(documentID: documentID, collectionID: collectionID, sourceFolder: oldFolder)
        }
        reloadCollections()
    }

    func remove(documentID: KnowledgeDocumentID, from collectionID: KnowledgeCollectionID) throws {
        try run("DELETE FROM knowledge_collection_documents WHERE document_id=? AND collection_id=?", [.text(documentID.rawValue.uuidString), .text(collectionID.rawValue.uuidString)])
        reloadCollections()
    }

    func createCollection(name: String) throws -> KnowledgeCollectionID {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.count <= 100 else { throw WriterError.message("Collection names must contain 1–100 characters.") }
        let id = KnowledgeCollectionID()
        try run("INSERT INTO knowledge_collections(id,name,created) VALUES(?,?,?)", [.text(id.rawValue.uuidString), .text(normalized), .double(Date().timeIntervalSince1970)])
        reloadCollections()
        return id
    }

    func renameCollection(_ id: KnowledgeCollectionID, to name: String) throws {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.count <= 100 else { throw WriterError.message("Collection names must contain 1–100 characters.") }
        try run("UPDATE knowledge_collections SET name=? WHERE id=?", [.text(normalized), .text(id.rawValue.uuidString)])
        reloadCollections()
    }

    func deleteCollection(_ id: KnowledgeCollectionID) throws {
        guard id != Self.defaultCollectionID else { throw WriterError.message("The My Library collection cannot be deleted.") }
        try run("DELETE FROM knowledge_collections WHERE id=?", [.text(id.rawValue.uuidString)])
        reloadCollections()
    }

    func sourceFolder(for documentID: KnowledgeDocumentID, in collectionID: KnowledgeCollectionID) throws -> String? {
        try query("SELECT source_folder FROM knowledge_collection_documents WHERE document_id=? AND collection_id=?", [.text(documentID.rawValue.uuidString), .text(collectionID.rawValue.uuidString)]).first?.string(0)
    }

    func sourceFolders(for documentID: KnowledgeDocumentID) throws -> [String] {
        try query("SELECT DISTINCT source_folder FROM knowledge_collection_documents WHERE document_id=? AND source_folder<>'' ORDER BY source_folder COLLATE NOCASE", [.text(documentID.rawValue.uuidString)]).map { $0.string(0) }
    }

    func documents(in collectionID: KnowledgeCollectionID) throws -> [KnowledgeDocumentRecord] {
        let ids = Set(try query("SELECT document_id FROM knowledge_collection_documents WHERE collection_id=?", [.text(collectionID.rawValue.uuidString)]).compactMap { $0.uuid(0) })
        return documents.filter { ids.contains($0.id.rawValue) }
    }

    func duplicateSourceCount(for documentID: KnowledgeDocumentID) -> Int {
        let rows = try? query("SELECT COUNT(DISTINCT source_identity) FROM takeout_imports WHERE document_id=?", [.text(documentID.rawValue.uuidString)])
        return max(0, (rows?.first?.int(0) ?? 0) - 1)
    }

    func recordTakeoutImportSession(_ session: KnowledgeImportSession) throws {
        try run("INSERT INTO takeout_import_sessions(id,source_label,started,completed,imported,duplicates,unchanged,failures,cancelled,summary_json) VALUES(?,?,?,?,?,?,?,?,?,?)", [.text(session.id.uuidString), .text(session.sourceLabel), .double(session.startedAt.timeIntervalSince1970), .double(session.completedAt?.timeIntervalSince1970 ?? 0), .int(Int64(session.imported)), .int(Int64(session.duplicates)), .int(Int64(session.unchanged)), .int(Int64(session.failures)), .int(session.cancelled ? 1 : 0), .text(try Self.encode(session.summary))])
        try run("DELETE FROM takeout_import_sessions WHERE id IN (SELECT id FROM takeout_import_sessions ORDER BY started DESC LIMIT -1 OFFSET 100)", [])
        reloadTakeoutImportSessions()
    }

    private func insertTakeoutImport(_ record: KnowledgeTakeoutImportRecord) throws {
        let metadata = try Self.encode(record.metadata ?? TakeoutMetadata())
        try run("INSERT INTO takeout_imports(source_identity,document_id,relative_path,original_filename,export_format,fingerprint,imported_at,google_file_id,original_url,metadata_json,archive_crc,source_bytes,source_modified,source_container_uri) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(source_identity,fingerprint) DO UPDATE SET document_id=excluded.document_id,relative_path=excluded.relative_path,original_filename=excluded.original_filename,export_format=excluded.export_format,imported_at=excluded.imported_at,google_file_id=excluded.google_file_id,original_url=excluded.original_url,metadata_json=excluded.metadata_json,archive_crc=excluded.archive_crc,source_bytes=excluded.source_bytes,source_modified=excluded.source_modified,source_container_uri=excluded.source_container_uri", [.text(record.sourceIdentity), .text(record.documentID.rawValue.uuidString), .text(record.relativePath), .text(record.originalFilename), .text(record.exportFormat), .text(record.fingerprint), .double(record.importedAt.timeIntervalSince1970), .optional(record.googleFileID), .optional(record.originalURL), .text(metadata), record.archiveCRC32.map { .int(Int64($0)) } ?? .int(0), .int(Int64(clamping: record.sourceBytes)), .double(record.sourceModifiedAt?.timeIntervalSince1970 ?? 0), .text(record.sourceContainerURI)])
    }

    func takeoutImportRecords() throws -> [KnowledgeTakeoutImportRecord] {
        try query("SELECT source_identity,document_id,relative_path,original_filename,export_format,fingerprint,imported_at,google_file_id,original_url,metadata_json,archive_crc,source_bytes,source_modified,source_container_uri FROM takeout_imports ORDER BY imported_at DESC", []).compactMap { row in
            guard let id = row.uuid(1) else { return nil }
            let sourceModified = row.double(12)
            return KnowledgeTakeoutImportRecord(sourceIdentity: row.string(0), documentID: KnowledgeDocumentID(id), relativePath: row.string(2), originalFilename: row.string(3), exportFormat: row.string(4), fingerprint: row.string(5), importedAt: Date(timeIntervalSince1970: row.double(6)), googleFileID: row.stringOptional(7), originalURL: row.stringOptional(8), metadata: TakeoutMetadata.decode(Data(row.string(9).utf8)), archiveCRC32: row.int(10) == 0 ? nil : UInt32(truncatingIfNeeded: row.int(10)), sourceBytes: UInt64(max(0, row.int(11))), sourceModifiedAt: sourceModified > 0 ? Date(timeIntervalSince1970: sourceModified) : nil, sourceContainerURI: row.string(13))
        }
    }

    /// Indexes supported documents contained in a folder the user explicitly chose.
    /// Enumeration is bounded to that folder and never descends into symbolic links.
    func add(folderURL: URL, collectionID: KnowledgeCollectionID? = nil) throws -> [KnowledgeDocumentID] {
        let scoped = folderURL.startAccessingSecurityScopedResource(); defer { if scoped { folderURL.stopAccessingSecurityScopedResource() } }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw NSError(domain: "KnowledgeLibrary", code: 5, userInfo: [NSLocalizedDescriptionKey: "Choose an available folder."])
        }
        guard let enumerator = FileManager.default.enumerator(at: folderURL, includingPropertiesForKeys: [.isRegularFileKey, .isPackageKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) else {
            throw NSError(domain: "KnowledgeLibrary", code: 6, userInfo: [NSLocalizedDescriptionKey: "Could not read the selected folder."])
        }
        let supported = Set(["boldwriter", "txt", "md", "markdown", "docx", "pdf", "rtf", "html", "rtfd"])
        var ids: [KnowledgeDocumentID] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isPackageKey, .isSymbolicLinkKey])
            if values?.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            guard supported.contains(url.pathExtension.lowercased()) else { continue }
            guard values?.isRegularFile == true || values?.isPackage == true else { continue }
            if values?.isPackage == true { enumerator.skipDescendants() }
            let components = url.standardizedFileURL.pathComponents.dropFirst(folderURL.standardizedFileURL.pathComponents.count)
            ids.append(try add(url: url, collectionID: collectionID, sourceFolder: components.dropLast().joined(separator: "/")))
        }
        return ids
    }

    func addReference(title: String, uri: String, notes: String = "", collectionID: KnowledgeCollectionID? = nil) throws -> KnowledgeDocumentID {
        let id = KnowledgeDocumentID(); let digest = Self.sha(Data(notes.utf8))
        try insertDocument(id: id, title: title, uri: uri, bookmark: nil, provenance: "External reference", fingerprint: digest, modified: nil, bytes: Int64(notes.utf8.count), reference: true)
        if !notes.isEmpty { for item in try Self.paragraphs(NSAttributedString(string: notes)) { try insertPassage(documentID: id, fingerprint: digest, item: item) } }
        try insertCollectionMembership(documentID: id, collectionID: collectionID ?? Self.defaultCollectionID, sourceFolder: "")
        reloadDocuments(); reloadCollections(); return id
    }

    func requestNavigation(to reference: KnowledgePassageReference, quotation: String) {
        pendingNavigationRequest = KnowledgeLibraryNavigationRequest(reference: reference, quotation: quotation)
    }

    func consumeNavigationRequest() -> KnowledgeLibraryNavigationRequest? {
        defer { pendingNavigationRequest = nil }
        return pendingNavigationRequest
    }

    func remove(documentID: KnowledgeDocumentID) throws {
        try run("DELETE FROM documents WHERE id=?", [.text(documentID.rawValue.uuidString)])
        try run("DELETE FROM passage_fts WHERE document_id=?", [.text(documentID.rawValue.uuidString)])
        reloadDocuments(); reloadCollections()
    }
    func refresh(documentID: KnowledgeDocumentID) throws {
        guard let record = documents.first(where: { $0.id == documentID }), !record.isReference,
              let url = try sourceURL(for: documentID) else {
            try setStatus(documentID, .unavailable); return
        }
        let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard FileManager.default.fileExists(atPath: url.path) else { try setStatus(documentID, .unavailable); return }
        let takeoutRecord = try latestTakeoutImport(for: documentID)
        _ = try add(url: url, preferredDocumentID: documentID, provenanceLabel: record.provenance, titleLabel: record.title, takeoutRecord: takeoutRecord)
    }
    func sourceURL(for documentID: KnowledgeDocumentID) throws -> URL? {
        guard let row = try query("SELECT uri,bookmark FROM documents WHERE id=?", [.text(documentID.rawValue.uuidString)]).first else { return nil }
        if let bookmark = row.data(1) {
            var stale = false
            if let resolved = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) { return resolved }
        }
        return URL(string: row.string(0))
    }
    func sourceMatches(documentID: KnowledgeDocumentID, fingerprint: String) throws -> Bool {
        guard let url = try sourceURL(for: documentID) else { return false }
        let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        return try Self.fingerprint(url).0 == fingerprint
    }
    func rebuildIndex() throws { for doc in documents where !doc.isReference { try refresh(documentID: doc.id) } }
    func reloadDocumentList() { reloadDocuments(); reloadCollections() }
    func detectSourceChanges() {
        var changed: [KnowledgeDocumentID] = [], missing: [KnowledgeDocumentID] = []
        for document in documents where !document.isReference {
            guard let url = (try? sourceURL(for: document.id)) ?? nil else { missing.append(document.id); continue }
            let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]), let modified = values.contentModificationDate, let size = values.fileSize else { missing.append(document.id); continue }
            if document.status == .unavailable || document.modifiedAt != modified || document.byteCount != Int64(size) { changed.append(document.id) }
        }
        for id in changed { try? run("UPDATE documents SET status='changed' WHERE id=?", [.text(id.rawValue.uuidString)]) }
        for id in missing { try? run("UPDATE documents SET status='unavailable' WHERE id=?", [.text(id.rawValue.uuidString)]) }
        if !changed.isEmpty || !missing.isEmpty { reloadDocuments() }
    }

    func search(_ query: String, documentID: KnowledgeDocumentID? = nil, context: String? = nil, limit: Int = 100, collectionID: KnowledgeCollectionID? = nil) throws -> [KnowledgeSearchResult] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        try refreshChangedSources()
        let match: String
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.count >= 2, trimmedQuery.first == "\"", trimmedQuery.last == "\"" { match = "\"\(trimmedQuery.dropFirst().dropLast().replacingOccurrences(of: "\"", with: "\"\""))\"" }
        else { match = query.split(whereSeparator: \.isWhitespace).map { "\"\($0)\"" }.joined(separator: " AND ") }
        var sql = "SELECT p.id,p.document_id,p.fingerprint,p.start,p.length,p.context,p.body,p.signature,d.id,d.title,d.uri,d.provenance,d.fingerprint,d.modified,d.bytes,d.status,d.is_reference,bm25(passage_fts) FROM passage_fts JOIN passages p ON p.id=passage_fts.passage_id JOIN documents d ON d.id=p.document_id WHERE passage_fts MATCH ?"
        var bindings: [SQLiteValue] = [.text(match)]
        if let documentID { sql += " AND d.id=?"; bindings.append(.text(documentID.rawValue.uuidString)) }
        if let collectionID {
            sql += " AND EXISTS(SELECT 1 FROM knowledge_collection_documents cm WHERE cm.document_id=d.id AND cm.collection_id=?)"
            bindings.append(.text(collectionID.rawValue.uuidString))
        }
        if let context { sql += " AND p.context LIKE ?"; bindings.append(.text("%\(context)%")) }
        sql += " ORDER BY bm25(passage_fts) LIMIT ?"; bindings.append(.int(Int64(max(1, min(limit, 1000)))))
        return try self.query(sql, bindings).compactMap { row in
            guard let passage = row.uuid(0), let doc = row.uuid(8) else { return nil }
            let reference = KnowledgePassageReference(documentID: KnowledgeDocumentID(doc), passageID: passage, sourceURI: row.string(10), fingerprint: row.string(2), utf16Range: NSRange(location: row.int(3), length: row.int(4)), excerptSignature: row.string(7), context: row.string(5))
            let record = KnowledgeDocumentRecord(id: KnowledgeDocumentID(doc), title: row.string(9), sourceURI: row.string(10), provenance: row.string(11), fingerprint: row.string(12), modifiedAt: row.double(13) > 0 ? Date(timeIntervalSince1970: row.double(13)) : nil, byteCount: Int64(row.int(14)), status: KnowledgeSourceStatus(rawValue: row.string(15)) ?? .unavailable, isReference: row.int(16) == 1)
            return KnowledgeSearchResult(document: record, reference: reference, excerpt: Self.excerpt(row.string(6), query: query), rank: row.double(17))
        }
    }
    func related(to phrase: String, excluding id: KnowledgeDocumentID? = nil) throws -> [KnowledgeSearchResult] { try search("\"\(phrase)\"", documentID: nil).filter { $0.document.id != id } }
    func createLink(from origin: KnowledgePassageReference, to destination: KnowledgePassageReference, description: String? = nil) throws {
        let link = KnowledgeLink(id: UUID(), origin: origin, destination: destination, description: description, originalSourceLocation: "\(origin.documentID.rawValue.uuidString):\(origin.utf16Range.location)", lastVerifiedStatus: .current)
        try run("INSERT INTO links VALUES(?,?,?,?,?,?)", [.text(link.id.uuidString), .text(try Self.encode(link.origin)), .text(try Self.encode(link.destination)), .optional(description), .text(link.originalSourceLocation), .text(link.lastVerifiedStatus.rawValue)])
    }
    func backlinks(to reference: KnowledgePassageReference) throws -> [KnowledgeLink] {
        try query("SELECT id,origin_json,destination_json,description,source_location,status FROM links", []).compactMap { row in
            guard let dst = try? Self.decode(row.string(2), as: KnowledgePassageReference.self),
                  dst.documentID == reference.documentID,
                  (dst.passageID == reference.passageID || dst.excerptSignature == reference.excerptSignature),
                  let id = row.uuid(0), let src = try? Self.decode(row.string(1), as: KnowledgePassageReference.self) else { return nil }
            let originStatus = (try? resolve(src).0) ?? .unresolved
            let destinationStatus = (try? resolve(dst).0) ?? .unresolved
            let status: KnowledgeReferenceStatus = [originStatus, destinationStatus].contains(.unresolved) ? .unresolved : ([originStatus, destinationStatus].contains(.stale) ? .stale : ([originStatus, destinationStatus].contains(.revalidated) ? .revalidated : .current))
            try? run("UPDATE links SET status=? WHERE id=?", [.text(status.rawValue), .text(id.uuidString)])
            return KnowledgeLink(id: id, origin: src, destination: dst, description: row.stringOptional(3), originalSourceLocation: row.string(4), lastVerifiedStatus: status)
        }
    }
    func resolve(_ reference: KnowledgePassageReference) throws -> (KnowledgeReferenceStatus, NSRange?) {
        try refreshChangedSources()
        guard let doc = documents.first(where: { $0.id == reference.documentID }), doc.status != .unavailable else { return (.unresolved, nil) }
        if doc.fingerprint == reference.fingerprint { return (.current, reference.utf16Range) }
        let found = try query("SELECT start,length,body,signature FROM passages WHERE document_id=? AND signature=?", [.text(reference.documentID.rawValue.uuidString), .text(reference.excerptSignature)])
        if let row = try query("SELECT start,length FROM passages WHERE document_id=? AND id=?", [.text(reference.documentID.rawValue.uuidString), .text(reference.passageID.uuidString)]).first {
            return (.revalidated, NSRange(location: row.int(0), length: row.int(1)))
        }
        if let row = found.first { return (.revalidated, NSRange(location: row.int(0), length: row.int(1))) }
        return (.stale, nil)
    }

    private enum SQLiteValue { case text(String), int(Int64), double(Double), optional(String?) }
    private struct Row {
        private enum Value { case text(String), int(Int64), double(Double), blob(Data), null }
        private let values: [Value]
        init(_ stmt: OpaquePointer) {
            values = (0..<sqlite3_column_count(stmt)).map { index -> Value in
                switch sqlite3_column_type(stmt, index) {
                case SQLITE_INTEGER: return Value.int(sqlite3_column_int64(stmt, index))
                case SQLITE_FLOAT: return Value.double(sqlite3_column_double(stmt, index))
                case SQLITE_TEXT: return Value.text(sqlite3_column_text(stmt, index).map { String(cString: $0) } ?? "")
                case SQLITE_BLOB:
                    let count = Int(sqlite3_column_bytes(stmt, index))
                    if let bytes = sqlite3_column_blob(stmt, index), count > 0 { return Value.blob(Data(bytes: bytes.assumingMemoryBound(to: UInt8.self), count: count)) } else { return Value.blob(Data()) }
                default: return Value.null
                }
            }
        }
        func string(_ i: Int32) -> String { guard Int(i) < values.count else { return "" }; if case .text(let value) = values[Int(i)] { return value }; return "" }
        func stringOptional(_ i: Int32) -> String? { guard Int(i) < values.count else { return nil }; if case .null = values[Int(i)] { return nil }; return string(i) }
        func data(_ i: Int32) -> Data? { guard Int(i) < values.count, case .blob(let value) = values[Int(i)] else { return nil }; return value }
        func int(_ i: Int32) -> Int { guard Int(i) < values.count else { return 0 }; if case .int(let value) = values[Int(i)] { return Int(value) }; if case .double(let value) = values[Int(i)] { return Int(value) }; return 0 }
        func double(_ i: Int32) -> Double { guard Int(i) < values.count else { return 0 }; if case .double(let value) = values[Int(i)] { return value }; if case .int(let value) = values[Int(i)] { return Double(value) }; return 0 }
        func uuid(_ i: Int32) -> UUID? { UUID(uuidString: string(i)) }
    }
    private func execute(_ sql: String) { guard let db else { return }; if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK { lastError = String(cString: sqlite3_errmsg(db)) } }
    private func integrityOK() -> Bool {
        guard let db else { return false }
        var stmt: OpaquePointer?; guard sqlite3_prepare_v2(db, "PRAGMA quick_check", -1, &stmt, nil) == SQLITE_OK, let stmt else { return false }
        defer { sqlite3_finalize(stmt) }; guard sqlite3_step(stmt) == SQLITE_ROW, let value = sqlite3_column_text(stmt, 0) else { return false }
        return String(cString: value) == "ok"
    }
    private func refreshChangedSources() throws {
        for doc in documents where !doc.isReference {
            guard let url = try sourceURL(for: doc.id) else { try setStatus(doc.id, .unavailable); continue }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else { try setStatus(doc.id, .unavailable); continue }
            guard let modified = values.contentModificationDate, let size = values.fileSize else { try setStatus(doc.id, .unavailable); continue }
            guard doc.status != .available || doc.modifiedAt != modified || doc.byteCount != Int64(size) else { continue }
            let observedFingerprint = try Self.fingerprint(url).0
            if observedFingerprint == doc.fingerprint {
                try updateSourceObservation(documentID: doc.id, modified: modified, bytes: Int64(size))
            } else {
                try refresh(documentID: doc.id)
            }
        }
    }

    private func updateSourceObservation(documentID: KnowledgeDocumentID, modified: Date, bytes: Int64) throws {
        try run("UPDATE documents SET modified=?,bytes=?,status='available' WHERE id=?", [
            .double(modified.timeIntervalSince1970), .int(bytes), .text(documentID.rawValue.uuidString)
        ])
        reloadDocuments()
    }
    private func prepare(_ sql: String, _ values: [SQLiteValue]) throws -> OpaquePointer {
        guard let db else { throw NSError(domain: "KnowledgeLibrary", code: 1) }
        var stmt: OpaquePointer?; guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { throw NSError(domain: "KnowledgeLibrary", code: 2, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))]) }
        for (i, value) in values.enumerated() { let n = Int32(i + 1); switch value { case .text(let s): sqlite3_bind_text(stmt, n, s, -1, SQLITE_TRANSIENT); case .int(let n): sqlite3_bind_int64(stmt, Int32(i + 1), n); case .double(let value): sqlite3_bind_double(stmt, n, value); case .optional(let s): if let s { sqlite3_bind_text(stmt, n, s, -1, SQLITE_TRANSIENT) } else { sqlite3_bind_null(stmt, n) } } }
        return stmt
    }
    private func run(_ sql: String, _ values: [SQLiteValue]) throws { let stmt = try prepare(sql, values); defer { sqlite3_finalize(stmt) }; guard sqlite3_step(stmt) == SQLITE_DONE else { throw NSError(domain: "KnowledgeLibrary", code: 3, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))]) } }
    private func query(_ sql: String, _ values: [SQLiteValue]) throws -> [Row] { let stmt = try prepare(sql, values); defer { sqlite3_finalize(stmt) }; var rows: [Row] = []; while sqlite3_step(stmt) == SQLITE_ROW { rows.append(Row(stmt)) }; return rows }
    private func transaction(_ body: () throws -> Void) throws { execute("BEGIN IMMEDIATE"); do { try body(); execute("COMMIT") } catch { execute("ROLLBACK"); throw error } }
    private func insertCollectionMembership(documentID: KnowledgeDocumentID, collectionID: KnowledgeCollectionID, sourceFolder: String) throws {
        try run("INSERT INTO knowledge_collection_documents(collection_id,document_id,source_folder,added) VALUES(?,?,?,?) ON CONFLICT(collection_id,document_id) DO UPDATE SET source_folder=excluded.source_folder", [.text(collectionID.rawValue.uuidString), .text(documentID.rawValue.uuidString), .text(sourceFolder), .double(Date().timeIntervalSince1970)])
    }
    private func reloadCollections() {
        guard let rows = try? query("SELECT c.id,c.name,c.created,COUNT(m.document_id) FROM knowledge_collections c LEFT JOIN knowledge_collection_documents m ON m.collection_id=c.id GROUP BY c.id ORDER BY c.name COLLATE NOCASE", []) else { return }
        collections = rows.compactMap { row in guard let id = row.uuid(0) else { return nil }; return KnowledgeCollection(id: KnowledgeCollectionID(id), name: row.string(1), createdAt: Date(timeIntervalSince1970: row.double(2)), documentCount: row.int(3)) }
    }
    private func reloadTakeoutImportSessions() {
        guard let rows = try? query("SELECT id,source_label,started,completed,imported,duplicates,unchanged,failures,cancelled,summary_json FROM takeout_import_sessions ORDER BY started DESC LIMIT 100", []) else { return }
        takeoutImportSessions = rows.compactMap { row in
            guard let id = row.uuid(0) else { return nil }
            return KnowledgeImportSession(id: id, sourceLabel: row.string(1), startedAt: Date(timeIntervalSince1970: row.double(2)), completedAt: row.double(3) > 0 ? Date(timeIntervalSince1970: row.double(3)) : nil, imported: row.int(4), duplicates: row.int(5), unchanged: row.int(6), failures: row.int(7), cancelled: row.int(8) == 1, summary: (try? Self.decode(row.string(9), as: [String].self)) ?? [])
        }
    }
    private func reloadDocuments() { guard let rows = try? query("SELECT id,title,uri,provenance,fingerprint,modified,bytes,status,is_reference FROM documents ORDER BY title COLLATE NOCASE", []) else { return }; documents = rows.compactMap { row in guard let id = row.uuid(0) else { return nil }; return KnowledgeDocumentRecord(id: KnowledgeDocumentID(id), title: row.string(1), sourceURI: row.string(2), provenance: row.string(3), fingerprint: row.string(4), modifiedAt: row.double(5) > 0 ? Date(timeIntervalSince1970: row.double(5)) : nil, byteCount: Int64(row.int(6)), status: KnowledgeSourceStatus(rawValue: row.string(7)) ?? .unavailable, isReference: row.int(8) == 1) } }
    private func findExisting(uri: String) throws -> KnowledgeDocumentID? {
        return try query("SELECT id FROM documents WHERE uri=?", [.text(uri)]).first?.uuid(0).map(KnowledgeDocumentID.init)
    }
    private func insertDocument(id: KnowledgeDocumentID, title: String, uri: String, bookmark: Data?, provenance: String, fingerprint: String, modified: Date?, bytes: Int64, reference: Bool) throws {
        guard let db else { throw NSError(domain: "KnowledgeLibrary", code: 1) }; let sql = "INSERT INTO documents VALUES(?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET title=excluded.title,uri=excluded.uri,bookmark=excluded.bookmark,provenance=excluded.provenance,fingerprint=excluded.fingerprint,modified=excluded.modified,bytes=excluded.bytes,status=excluded.status,is_reference=excluded.is_reference"
        let stmt = try prepare(sql, [.text(id.rawValue.uuidString), .text(title), .text(uri), .optional(nil), .text(provenance), .text(fingerprint), .double(modified?.timeIntervalSince1970 ?? 0), .int(bytes), .text("available"), .int(reference ? 1 : 0)])
        defer { sqlite3_finalize(stmt) }; if let bookmark { _ = bookmark.withUnsafeBytes { sqlite3_bind_blob(stmt, 4, $0.baseAddress, Int32(bookmark.count), SQLITE_TRANSIENT) } }
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw NSError(domain: "KnowledgeLibrary", code: 4, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))]) }
    }
    private func deletePassages(_ id: KnowledgeDocumentID) throws { try run("DELETE FROM passage_fts WHERE document_id=?", [.text(id.rawValue.uuidString)]); try run("DELETE FROM passages WHERE document_id=?", [.text(id.rawValue.uuidString)]) }
    private func insertPassage(documentID: KnowledgeDocumentID, fingerprint: String, item: Passage, passageID: UUID? = nil) throws {
        let pid = passageID ?? UUID(); let sig = Self.sha(Data(item.body.utf8)); let id = documentID.rawValue.uuidString
        try run("INSERT INTO passages VALUES(?,?,?,?,?,?,?,?)", [.text(pid.uuidString), .text(id), .text(fingerprint), .int(Int64(item.range.location)), .int(Int64(item.range.length)), .text(item.context), .text(item.body), .text(sig)])
        try run("INSERT INTO passage_fts VALUES(?,?,?,?)", [.text(pid.uuidString), .text(id), .text(item.context), .text(item.body)])
    }
    private func setStatus(_ id: KnowledgeDocumentID, _ status: KnowledgeSourceStatus) throws { try run("UPDATE documents SET status=? WHERE id=?", [.text(status.rawValue), .text(id.rawValue.uuidString)]); reloadDocuments() }
    private struct Passage { let range: NSRange; let context: String; let body: String }
    private static func paragraphs(_ attributed: NSAttributedString) throws -> [Passage] {
        let ns = attributed.string as NSString; var rows: [Passage] = []; var heading = ""; var paragraph = 0
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byParagraphs) { value, range, _, _ in
            guard let value else { return }; let body = value.trimmingCharacters(in: .whitespacesAndNewlines); guard !body.isEmpty else { return }
            paragraph += 1
            if body.hasPrefix("#") { heading = body.trimmingCharacters(in: CharacterSet(charactersIn: "# ")) }
            else if let raw = attributed.attribute(.boldWriterStyle, at: range.location, effectiveRange: nil) as? String, WriterStyle(rawValue: raw)?.headingLevel != nil { heading = body }
            let context = heading.isEmpty ? "Paragraph \(paragraph)" : "\(heading) · Paragraph \(paragraph)"
            rows.append(Passage(range: range, context: context, body: body))
        }
        for (index, note) in try Footnotes.records(in: attributed).enumerated() {
            let hostContext = rows.first(where: { NSLocationInRange(note.location, $0.range) })?.context
            let context = "Footnote \(index + 1)" + (hostContext.map { " · \($0)" } ?? "")
            rows.append(Passage(range: NSRange(location: note.location, length: note.length), context: context, body: note.text))
        }
        return rows
    }
    private static func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static func fingerprint(_ url: URL) throws -> (String, Int64) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { throw CocoaError(.fileNoSuchFile) }
        var hasher = SHA256(); var total: Int64 = 0
        func consume(_ file: URL, label: String?) throws {
            if let label { hasher.update(data: Data(label.utf8)); hasher.update(data: Data([0])) }
            let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
            while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
                hasher.update(data: chunk); total += Int64(chunk.count)
            }
        }
        if isDirectory.boolValue {
            guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) else { throw CocoaError(.fileReadNoPermission) }
            var files: [URL] = []
            for case let child as URL in enumerator {
                let values = try child.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
                if values.isRegularFile == true { files.append(child) }
            }
            for file in files.sorted(by: { $0.path < $1.path }) {
                let relative = String(file.path.dropFirst(url.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                try consume(file, label: relative)
            }
        } else { try consume(url, label: nil) }
        return (hasher.finalize().map { String(format: "%02x", $0) }.joined(), total)
    }
    private static func provenance(_ url: URL) -> String { switch url.pathExtension.lowercased() { case "boldwriter": "BOLD Writer native"; case "md", "markdown": "Markdown"; case "txt": "Plain text"; case "docx": "DOCX import"; case "pdf": "PDFKit text extraction"; default: "Imported document" } }
    private static func excerpt(_ text: String, query: String) -> String { guard text.count > 380 else { return text }; let found = text.range(of: query.replacingOccurrences(of: "\"", with: ""), options: .caseInsensitive)?.lowerBound ?? text.startIndex; let start = text.index(found, offsetBy: -min(110, text.distance(from: text.startIndex, to: found))); let end = text.index(start, offsetBy: min(280, text.distance(from: start, to: text.endIndex))); return "…\(text[start..<end])…" }
    private static func encode<T: Encodable>(_ value: T) throws -> String { String(data: try JSONEncoder().encode(value), encoding: .utf8)! }
    private static func decode<T: Decodable>(_ value: String, as type: T.Type) throws -> T { try JSONDecoder().decode(type, from: Data(value.utf8)) }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
