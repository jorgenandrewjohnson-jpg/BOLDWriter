import Foundation
import XCTest
@testable import BOLDWriter

@MainActor final class KnowledgeLibraryCollectionTests: XCTestCase {
    private func root() throws -> URL {
        let value = FileManager.default.temporaryDirectory.appendingPathComponent("KnowledgeCollections-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: value, withIntermediateDirectories: true)
        return value
    }

    func testMovePreservesDocumentAndPassageIdentityBacklinksAndSource() throws {
        let temp = try root(); defer { try? FileManager.default.removeItem(at: temp) }
        let libraryURL = temp.appendingPathComponent("library")
        let source = temp.appendingPathComponent("Research.md")
        let referring = temp.appendingPathComponent("Reading Notes.txt")
        try Data("# Passage\nThe covenant section remains stable.".utf8).write(to: source)
        try Data("This reading note points to the passage.".utf8).write(to: referring)
        var store: KnowledgeLibraryStore? = KnowledgeLibraryStore(libraryURL: libraryURL)
        let originalID = try XCTUnwrap(store?.add(url: source))
        _ = try store?.add(url: referring)
        let destination = try XCTUnwrap(store?.search("covenant").first?.reference)
        let origin = try XCTUnwrap(store?.search("points to the passage").first?.reference)
        try store?.createLink(from: origin, to: destination, description: "Collection move regression")
        let collectionID = try XCTUnwrap(try store?.createCollection(name: "Book Research"))
        try store?.move(documentID: originalID, to: collectionID, sourceFolder: "Drive/Book A/Chapter 3")

        XCTAssertEqual(try store?.search("covenant", collectionID: collectionID).first?.document.id, originalID)
        XCTAssertTrue(try store?.search("points", collectionID: collectionID).isEmpty == true)
        XCTAssertEqual(try store?.search("covenant").first?.document.id, originalID)
        XCTAssertEqual(try store?.sourceFolder(for: originalID, in: collectionID), "Drive/Book A/Chapter 3")
        XCTAssertEqual(try store?.backlinks(to: destination).count, 1)
        XCTAssertEqual(store?.collections.first(where: { $0.id == collectionID })?.documentCount, 1)

        store = nil
        store = KnowledgeLibraryStore(libraryURL: libraryURL)
        let reopenedDestination = try XCTUnwrap(store?.search("covenant", collectionID: collectionID).first?.reference)
        XCTAssertEqual(reopenedDestination.documentID, originalID)
        XCTAssertEqual(reopenedDestination.passageID, destination.passageID)
        XCTAssertEqual(try store?.backlinks(to: reopenedDestination).count, 1)
        try store?.remove(documentID: originalID, from: collectionID)
        XCTAssertEqual(store?.collections.first(where: { $0.id == collectionID })?.documentCount, 0)
        XCTAssertEqual(try store?.search("covenant").first?.document.id, originalID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testMetadataOnlyTimestampChangePreservesPassageIdentity() throws {
        let temp = try root(); defer { try? FileManager.default.removeItem(at: temp) }
        let source = temp.appendingPathComponent("Research.md")
        try Data("# Passage\nThe archive fingerprint stays stable.".utf8).write(to: source)
        let store = KnowledgeLibraryStore(libraryURL: temp.appendingPathComponent("library"))
        let documentID = try store.add(url: source)
        let before = try XCTUnwrap(store.search("fingerprint", documentID: documentID).first?.reference)
        let currentDate = try XCTUnwrap((try FileManager.default.attributesOfItem(atPath: source.path)[.modificationDate]) as? Date)
        try FileManager.default.setAttributes([.modificationDate: currentDate.addingTimeInterval(5)], ofItemAtPath: source.path)

        let after = try XCTUnwrap(store.search("fingerprint", documentID: documentID).first?.reference)

        XCTAssertEqual(after.passageID, before.passageID)
        XCTAssertEqual(after.fingerprint, before.fingerprint)
        XCTAssertEqual(store.documents.first(where: { $0.id == documentID })?.status, .available)
    }

    func testImportHistoryAndCollectionCountsPersistInTheSingleLibraryDatabase() throws {
        let temp = try root(); defer { try? FileManager.default.removeItem(at: temp) }
        let libraryURL = temp.appendingPathComponent("library")
        var store: KnowledgeLibraryStore? = KnowledgeLibraryStore(libraryURL: libraryURL)
        let notes = try XCTUnwrap(try store?.createCollection(name: "Notes"))
        let source = temp.appendingPathComponent("note.md")
        try Data("A searchable note.".utf8).write(to: source)
        let docID = try XCTUnwrap(try store?.add(url: source, collectionID: notes, sourceFolder: "Takeout/Drive/Notes"))
        XCTAssertEqual(store?.collections.first(where: { $0.id == notes })?.documentCount, 1)
        XCTAssertEqual(try store?.search("searchable", collectionID: notes).first?.document.id, docID)

        let session = KnowledgeImportSession(id: UUID(), sourceLabel: "takeout-part-001.zip", startedAt: Date(timeIntervalSince1970: 100), completedAt: Date(timeIntervalSince1970: 130), imported: 1, duplicates: 2, unchanged: 3, failures: 1, cancelled: false, summary: ["Unsupported image skipped", "One malformed file failed"])
        try store?.recordTakeoutImportSession(session)
        store = nil
        store = KnowledgeLibraryStore(libraryURL: libraryURL)
        XCTAssertEqual(store?.databaseURL, libraryURL.appendingPathComponent("library.sqlite3"))
        XCTAssertEqual(store?.takeoutImportSessions.first?.id, session.id)
        XCTAssertEqual(store?.takeoutImportSessions.first?.summary, session.summary)
        XCTAssertEqual(store?.collections.first(where: { $0.id == notes })?.documentCount, 1)
        XCTAssertEqual(try store?.sourceFolder(for: docID, in: notes), "Takeout/Drive/Notes")
    }

    func testTakeoutTargetsSelectedCollectionAndPersistsOriginalFolderAndRunSummary() async throws {
        let temp = try root(); defer { try? FileManager.default.removeItem(at: temp) }
        let export = temp.appendingPathComponent("Takeout", isDirectory: true)
        let nested = export.appendingPathComponent("Drive/Book One/Chapter 2", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let source = nested.appendingPathComponent("Research.md")
        let original = Data("# Chapter 2\nThe covenant source stays in the selected collection.".utf8)
        try original.write(to: source)
        let store = KnowledgeLibraryStore(libraryURL: temp.appendingPathComponent("library"))
        let collection = try store.createCollection(name: "Book One")
        let model = GoogleTakeoutImportModel(library: store, collectionID: collection)
        await model.scanAndWait([.folder(export)])
        await model.importSelectedAndWait()

        XCTAssertTrue(model.failures.isEmpty, model.failures.joined(separator: "\n"))
        XCTAssertEqual(store.documents.count, 1)
        XCTAssertEqual(try store.search("covenant", collectionID: collection).count, 1)
        XCTAssertTrue(try store.search("covenant", collectionID: KnowledgeLibraryStore.defaultCollectionID).isEmpty)
        let docID = try XCTUnwrap(store.search("covenant", collectionID: collection).first?.document.id)
        XCTAssertEqual(try store.sourceFolder(for: docID, in: collection), "Drive/Book One/Chapter 2")
        XCTAssertEqual(try Data(contentsOf: source), original)
        XCTAssertEqual(store.takeoutImportSessions.last?.imported, 1)
        let reopened = KnowledgeLibraryStore(libraryURL: temp.appendingPathComponent("library"))
        XCTAssertEqual(reopened.takeoutImportSessions.last?.imported, 1)
        XCTAssertEqual(try reopened.search("covenant", collectionID: collection).first?.document.id, docID)
    }
}
