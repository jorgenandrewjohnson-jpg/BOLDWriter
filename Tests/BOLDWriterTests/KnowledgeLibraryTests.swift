import Foundation
import CryptoKit
import XCTest
@testable import BOLDWriter

@MainActor final class KnowledgeLibraryTests: XCTestCase {
    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("KnowledgeLibrary-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    private func write(_ text: String, at url: URL) throws { try Data(text.utf8).write(to: url) }

    func testTenSyntheticDocumentsSearchPhraseUnicodeContextAndDuplicateNames() throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let store = KnowledgeLibraryStore(libraryURL: root.appendingPathComponent("library"))
        var ids: [KnowledgeDocumentID] = []
        for index in 0..<10 {
            let folder = root.appendingPathComponent("Book-\(index)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let path = folder.appendingPathComponent("Notes.md")
            let content = "# Chapter \(index)\nThe New Covenant appears in this synthetic chapter.\nUnicode: ἐν ἀρχῇ, 日本語, café.\nOther material about covenant history."
            try write(content, at: path)
            let before = SHA256.hash(data: try Data(contentsOf: path))
            ids.append(try store.add(url: path))
            XCTAssertEqual(SHA256.hash(data: try Data(contentsOf: path)), before, "Indexing must not modify source files")
        }
        XCTAssertEqual(store.documents.count, 10)
        XCTAssertEqual(try store.add(url: root.appendingPathComponent("Book-0/Notes.md")), ids[0], "Adding the same path twice must update the existing record")
        let phrase = try store.search("\"New Covenant\"")
        XCTAssertEqual(phrase.count, 10)
        XCTAssertEqual(Set(phrase.map(\.document.id)), Set(ids))
        XCTAssertTrue(phrase[0].excerpt.localizedCaseInsensitiveContains("New Covenant"))
        XCTAssertEqual(try store.search("café").count, 10)
        XCTAssertEqual(try store.search("Covenant", documentID: ids[4]).count, 2)
        XCTAssertEqual(try store.search("Covenant", context: "Chapter 2").count, 2)
    }

    func testLinksBacklinksPersistAcrossStoreReopenAndRemovalKeepsOriginal() throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let libraryURL = root.appendingPathComponent("library")
        let a = root.appendingPathComponent("a.txt"), b = root.appendingPathComponent("b.txt")
        try write("Origin paragraph with shared term.", at: a); try write("Destination paragraph with shared term.", at: b)
        var store: KnowledgeLibraryStore? = KnowledgeLibraryStore(libraryURL: libraryURL)
        let aID = try XCTUnwrap(store?.add(url: a)), _ = try store?.add(url: b)
        let found = try XCTUnwrap(store?.search("Origin").first)
        let destination = try XCTUnwrap(store?.search("Destination").first)
        try store?.createLink(from: found.reference, to: destination.reference, description: "Related discussion")
        XCTAssertEqual(try store?.backlinks(to: destination.reference).count, 1)
        _ = try store?.add(url: b) // Re-indexing replaces passage UUIDs while preserving canonical document and excerpt identity.
        let refreshedDestination = try XCTUnwrap(store?.search("Destination").first?.reference)
        XCTAssertNotEqual(refreshedDestination.passageID, destination.reference.passageID)
        XCTAssertEqual(try store?.backlinks(to: refreshedDestination).count, 1)
        store = nil
        store = KnowledgeLibraryStore(libraryURL: libraryURL)
        XCTAssertEqual(try store?.backlinks(to: refreshedDestination).count, 1)
        try store?.remove(documentID: aID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.path))
    }

    func testChangedSourceRevalidatesMatchingPassageAndMarksEditedPassageStale() throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.txt")
        try write("Stable paragraph for reference.\nAnother passage that will change.", at: source)
        let store = KnowledgeLibraryStore(libraryURL: root.appendingPathComponent("library"))
        let id = try store.add(url: source)
        let stable = try XCTUnwrap(store.search("Stable").first?.reference)
        let changed = try XCTUnwrap(store.search("Another").first?.reference)
        try write("Inserted text moves the stable paragraph.\nStable paragraph for reference.\nThe changed passage is now replaced.", at: source)
        try store.refresh(documentID: id)
        XCTAssertEqual(try store.resolve(stable).0, .revalidated)
        XCTAssertEqual(try store.resolve(changed).0, .stale)
    }

    func testLargeSyntheticManuscriptIndexesSearchableParagraphLocations() throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Long Manuscript.md")
        let blocks = (0..<12_000).map { index in "## Chapter \(index / 100 + 1)\nParagraph \(index) carries recurring terminology and Unicode — naïve authoring.\n" }
        try write(blocks.joined(), at: source)
        let store = KnowledgeLibraryStore(libraryURL: root.appendingPathComponent("library"))
        let started = Date(); let id = try store.add(url: source); let elapsed = Date().timeIntervalSince(started)
        XCTAssertLessThan(elapsed, 30, "Synthetic indexing should remain bounded on the acceptance machine")
        let hits = try store.search("Paragraph 11999")
        XCTAssertEqual(hits.first?.document.id, id)
        XCTAssertGreaterThan(hits.first?.reference.utf16Range.location ?? 0, 0)
    }

    func testCorruptIndexIsPreservedAndNewIndexRecovers() throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let library = root.appendingPathComponent("library", isDirectory: true)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        try Data("not a SQLite database".utf8).write(to: library.appendingPathComponent("library.sqlite3"))
        let store = KnowledgeLibraryStore(libraryURL: library)
        XCTAssertTrue((try FileManager.default.contentsOfDirectory(atPath: library.path)).contains(where: { $0.hasPrefix("library-corrupt-") }))
        let source = root.appendingPathComponent("recover.txt"); try write("Recoverable local text", at: source)
        _ = try store.add(url: source)
        XCTAssertEqual(try store.search("Recoverable").count, 1)
    }

    func testUnavailableSourceMakesPassageReferenceUnresolved() throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("temporary.txt"); try write("Source that becomes unavailable", at: source)
        let store = KnowledgeLibraryStore(libraryURL: root.appendingPathComponent("library"))
        let id = try store.add(url: source)
        let reference = try XCTUnwrap(store.search("unavailable").first?.reference)
        try FileManager.default.removeItem(at: source)
        XCTAssertEqual(try store.resolve(reference).0, .unresolved)
        XCTAssertEqual(store.documents.first(where: { $0.id == id })?.status, .unavailable)
    }

    func testExplicitFolderImportIndexesSupportedFilesRecursivelyOnly() throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let chosen = root.appendingPathComponent("Chosen", isDirectory: true)
        let nested = chosen.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let first = chosen.appendingPathComponent("book.txt"), second = nested.appendingPathComponent("note.md")
        try write("Selected folder manuscript", at: first); try write("Selected folder research note", at: second)
        try write("Ignored unsupported metadata", at: chosen.appendingPathComponent("data.json"))
        let outside = root.appendingPathComponent("outside.txt"); try write("Outside folder text", at: outside)
        let store = KnowledgeLibraryStore(libraryURL: root.appendingPathComponent("library"))
        XCTAssertEqual(try store.add(folderURL: chosen).count, 2)
        XCTAssertEqual(store.documents.count, 2)
        XCTAssertEqual(try store.search("Selected").count, 2)
        XCTAssertEqual(try store.search("Outside").count, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }
}
