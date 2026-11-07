import CryptoKit
import Foundation
import AppKit
import PDFKit
import XCTest
@testable import BOLDWriter

@MainActor final class GoogleTakeoutImportTests: XCTestCase {
    private struct ZIPFixtureEntry {
        let path: String
        let data: Data
        var unixMode: UInt32 = 0x81A4
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GoogleTakeout-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    func testReopeningLibraryRemovesOnlyAbandonedOldTakeoutStaging() throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let libraryURL = root.appendingPathComponent("library", isDirectory: true)
        let staging = libraryURL.appendingPathComponent("ImportStaging", isDirectory: true)
        let abandoned = staging.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let recent = staging.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let durable = libraryURL.appendingPathComponent("ImportedSources/GoogleTakeout/source.md")
        try FileManager.default.createDirectory(at: abandoned, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: recent, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: durable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("partial member".utf8).write(to: abandoned.appendingPathComponent("member.md"))
        try Data("recent work".utf8).write(to: recent.appendingPathComponent("member.md"))
        let durableSource = Data("verified imported source".utf8)
        try durableSource.write(to: durable)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-48 * 60 * 60)], ofItemAtPath: abandoned.path)

        _ = KnowledgeLibraryStore(libraryURL: libraryURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: abandoned.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recent.path))
        XCTAssertEqual(try Data(contentsOf: durable), durableSource)
    }

    func testMultipartHundredDocumentTakeoutPreviewImportSearchAndIdempotentRetry() async throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        var firstPart: [ZIPFixtureEntry] = [], secondPart: [ZIPFixtureEntry] = []
        for index in 0..<100 {
            let path = "Takeout/Drive/Book-\(index % 10 + 1)/Chapter-\(index / 10 + 1)/Research Notes.md"
            let bodyIndex = index == 99 ? 0 : index
            let body = "# Book \(bodyIndex % 10 + 1) · Chapter \(bodyIndex / 10 + 1)\nThe New Covenant appears in document \(bodyIndex). Unicode: café, Ελληνικά, 日本語."
            let fixture = ZIPFixtureEntry(path: path, data: Data(body.utf8))
            if index < 50 { firstPart.append(fixture) } else { secondPart.append(fixture) }
        }
        firstPart.append(ZIPFixtureEntry(path: "Takeout/Drive/Book-1/Chapter-1/Research Notes.md.json", data: Data(#"{"id":"gdrive-doc-001","url":"https://docs.google.com/document/d/gdrive-doc-001/edit","title":"Original Google title","modifiedTime":"2026-10-20T12:00:00Z"}"#.utf8)))
        let longText = (0..<12_000).map { index in
            (index % 100 == 0 ? "## Chapter \(index / 100 + 1)\n" : "") + "Long manuscript marker \(index) carries extended synthetic research text and Unicode — naïve café.\n"
        }.joined()
        secondPart += [
            ZIPFixtureEntry(path: "Takeout/Drive/Manuscripts/Long Synthetic Manuscript.md", data: Data(longText.utf8)),
            ZIPFixtureEntry(path: "Takeout/Drive/Book-1/image.jpg", data: Data([0xFF, 0xD8, 0xFF])),
            ZIPFixtureEntry(path: "Takeout/Drive/Book-1/video.mp4", data: Data([0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70])),
            ZIPFixtureEntry(path: "Takeout/Drive/Book-1/table.csv", data: Data("a,b\n1,2".utf8)),
            ZIPFixtureEntry(path: "../escape.txt", data: Data("must never write outside".utf8)),
            ZIPFixtureEntry(path: "/absolute/escape.txt", data: Data("must never write absolute".utf8)),
            ZIPFixtureEntry(path: "Takeout/Drive/Book-1/linked.md", data: Data("target".utf8), unixMode: 0xA1FF)
        ]
        let archiveA = root.appendingPathComponent("takeout-drive-001.zip")
        let archiveB = root.appendingPathComponent("takeout-drive-002.zip")
        try makeZIP64(makeZIP(firstPart)).write(to: archiveA); try makeZIP(secondPart).write(to: archiveB)
        let archiveHashes = [archiveA, archiveB].map { Self.sha(try! Data(contentsOf: $0)) }

        let library = KnowledgeLibraryStore(libraryURL: root.appendingPathComponent("library"))
        let model = GoogleTakeoutImportModel(library: library)
        await model.scanAndWait([.archive(archiveA), .archive(archiveB)])
        let preview = try XCTUnwrap(model.preview)
        XCTAssertEqual(preview.archiveCount, 2)
        XCTAssertEqual(preview.supportedDocuments, 101)
        XCTAssertEqual(preview.skippedMedia, 2)
        XCTAssertEqual(preview.entries.filter { $0.kind == .unsafe }.count, 3)
        XCTAssertEqual(preview.entries.filter { $0.kind == .unsupported }.count, 1)
        XCTAssertEqual(preview.entries.filter { $0.kind == .metadata }.count, 1)
        XCTAssertEqual(preview.selectedDocuments.count, 101)
        XCTAssertEqual(preview.entries.first(where: { $0.metadata?.googleID == "gdrive-doc-001" })?.metadata?.originalURL, "https://docs.google.com/document/d/gdrive-doc-001/edit")
        XCTAssertGreaterThan(preview.additionalSourceBytes, 0)

        await model.importSelectedAndWait()
        XCTAssertTrue(model.failures.isEmpty, model.failures.joined(separator: "\n"))
        XCTAssertEqual(model.importedCount, 100)
        XCTAssertEqual(model.duplicateCount, 1)
        XCTAssertEqual(library.documents.count, 100)
        XCTAssertEqual(try library.search("\"New Covenant\"").count, 99)
        XCTAssertEqual(try library.search("café").count, 100)
        XCTAssertEqual(try library.takeoutImportRecords().count, 101)
        let longResult = try XCTUnwrap(library.search("\"Long manuscript marker 11999\"").first)
        XCTAssertEqual(longResult.reference.context.components(separatedBy: " · ").first, "Chapter 120")
        XCTAssertGreaterThan(longResult.reference.utf16Range.location, 0)
        let googleOrigin = try XCTUnwrap(library.takeoutImportRecords().first { $0.googleFileID == "gdrive-doc-001" })
        XCTAssertEqual(googleOrigin.originalFilename, "Research Notes.md")
        XCTAssertEqual(googleOrigin.sourceContainerURI, archiveA.standardizedFileURL.absoluteString)
        XCTAssertTrue(googleOrigin.relativePath.contains("Book-1/Chapter-1"))
        XCTAssertEqual(googleOrigin.metadata?.title, "Original Google title")
        XCTAssertEqual(library.documents.first(where: { $0.id == googleOrigin.documentID })?.title, "Original Google title")

        let origin = try XCTUnwrap(library.search("document 2").first?.reference)
        let destination = try XCTUnwrap(library.search("document 0").first?.reference)
        try library.createLink(from: origin, to: destination, description: "Synthetic provenance link")
        let reopened = KnowledgeLibraryStore(libraryURL: root.appendingPathComponent("library"))
        XCTAssertEqual(try reopened.takeoutImportRecords().count, 101)
        XCTAssertEqual(try reopened.backlinks(to: destination).count, 1)

        await model.importSelectedAndWait()
        XCTAssertTrue(model.failures.isEmpty)
        XCTAssertEqual(model.unchangedCount, 101)
        XCTAssertEqual(library.documents.count, 100)
        XCTAssertEqual([archiveA, archiveB].map { Self.sha(try! Data(contentsOf: $0)) }, archiveHashes, "Takeout archives must remain byte-for-byte unchanged")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("escape.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: "/absolute/escape.txt"))
    }

    func testCancelAndRetryResumesCompletedItemsWithoutDuplicatingRecords() async throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let entries = (0..<12).map { ZIPFixtureEntry(path: "Drive/Notes/Note-\($0).md", data: Data("Stable searchable note \($0) with covenant.".utf8)) }
        let archive = root.appendingPathComponent("takeout-001.zip"); try makeZIP(entries).write(to: archive)
        let library = KnowledgeLibraryStore(libraryURL: root.appendingPathComponent("library"))
        let model = GoogleTakeoutImportModel(library: library)
        await model.scanAndWait([.archive(archive)])
        model.startImport()
        for _ in 0..<200 where library.documents.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        model.cancelImport()
        await model.waitForImport()
        XCTAssertFalse(model.isImporting)
        XCTAssertGreaterThan(library.documents.count, 0)
        XCTAssertLessThan(library.documents.count, 12)
        await model.importSelectedAndWait()
        XCTAssertTrue(model.failures.isEmpty, model.failures.joined(separator: "\n"))
        XCTAssertEqual(library.documents.count, 12)
        XCTAssertEqual(try library.search("covenant").count, 12)
        XCTAssertEqual(try library.takeoutImportRecords().count, 12)
    }

    func testExtractedFolderIsIndexedInPlaceAndOnlyChosenRootIsIncluded() async throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let selected = root.appendingPathComponent("Takeout Drive", isDirectory: true)
        let nested = selected.appendingPathComponent("My Drive/Books", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let source = nested.appendingPathComponent("Research.md")
        try Data("# Selected folder\nIn-place import keeps this searchable.".utf8).write(to: source)
        try Data(#"{"url":"https://drive.google.com/open?id=gdrive-extracted-001","title":"Extracted folder research"}"#.utf8).write(to: nested.appendingPathComponent("Research.md.json"))
        let ignored = root.appendingPathComponent("outside.md"); try Data("Not selected.".utf8).write(to: ignored)
        let before = Self.sha(try Data(contentsOf: source))
        let libraryURL = root.appendingPathComponent("library")
        let library = KnowledgeLibraryStore(libraryURL: libraryURL)
        let model = GoogleTakeoutImportModel(library: library)
        await model.scanAndWait([.folder(selected)])
        XCTAssertEqual(model.preview?.supportedDocuments, 1)
        await model.importSelectedAndWait()
        XCTAssertEqual(library.documents.count, 1)
        XCTAssertEqual(try library.search("searchable").count, 1)
        let originalID = try XCTUnwrap(library.documents.first?.id)
        let oldReference = try XCTUnwrap(library.search("searchable").first?.reference)
        let backlinkSource = root.appendingPathComponent("backlink-source.txt")
        try Data("A research note that points to the selected passage.".utf8).write(to: backlinkSource)
        _ = try library.add(url: backlinkSource)
        let originReference = try XCTUnwrap(library.search("points to the selected").first?.reference)
        try library.createLink(from: originReference, to: oldReference, description: "Preserve this source link after reindexing")
        XCTAssertEqual(Self.sha(try Data(contentsOf: source)), before)
        XCTAssertTrue(FileManager.default.fileExists(atPath: ignored.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: libraryURL.appendingPathComponent("ImportedSources/GoogleTakeout").path))
        XCTAssertEqual(try XCTUnwrap(library.takeoutImportRecords().first).relativePath, "My Drive/Books/Research.md")
        XCTAssertEqual(try XCTUnwrap(library.takeoutImportRecords().first).googleFileID, "gdrive-extracted-001")
        try Data("# Selected folder\nInserted passage before the original text.\nIn-place import keeps this searchable.".utf8).write(to: source)
        await model.scanAndWait([.folder(selected)])
        await model.importSelectedAndWait()
        XCTAssertTrue(library.documents.contains(where: { $0.id == originalID }))
        XCTAssertEqual(try library.takeoutImportRecords().count, 2, "Changed fingerprints retain provenance history for prior local source revisions.")
        XCTAssertEqual(try library.resolve(oldReference).0, .revalidated)
        XCTAssertGreaterThan(try XCTUnwrap(library.resolve(oldReference).1).location, oldReference.utf16Range.location)
        let currentReference = try XCTUnwrap(library.search("searchable").first?.reference)
        XCTAssertEqual(currentReference.passageID, oldReference.passageID, "Unchanged passage identity survives source edits and reindexing.")
        XCTAssertEqual(try library.backlinks(to: currentReference).count, 1, "Backlinks follow the preserved passage identity.")
    }

    func testCorruptMemberFailsClearlyAndLeavesNoPartialDocumentOrStagingCopy() async throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let path = "Takeout/Drive/Corrupt.md", content = Data("CRC must match before import".utf8)
        var archiveData = makeZIP([ZIPFixtureEntry(path: path, data: content)])
        let localDataOffset = 30 + path.utf8.count
        archiveData[localDataOffset] ^= 0x40
        let archive = root.appendingPathComponent("corrupt.zip"); try archiveData.write(to: archive)
        let libraryURL = root.appendingPathComponent("library")
        let library = KnowledgeLibraryStore(libraryURL: libraryURL)
        let model = GoogleTakeoutImportModel(library: library)
        await model.scanAndWait([.archive(archive)])
        await model.importSelectedAndWait()
        XCTAssertEqual(library.documents.count, 0)
        XCTAssertEqual(model.failures.count, 1)
        XCTAssertTrue(model.failures[0].contains("Corrupt.md"))
        let staging = libraryURL.appendingPathComponent("ImportStaging")
        XCTAssertTrue((try? FileManager.default.contentsOfDirectory(atPath: staging.path).isEmpty) ?? true)
    }

    func testMalformedSupportedDocumentLeavesNoOrphanCopyOrProvenanceRecord() async throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let libraryURL = root.appendingPathComponent("library")
        let archive = root.appendingPathComponent("malformed-docx.zip")
        try makeZIP([ZIPFixtureEntry(path: "Takeout/Drive/Research/broken.docx", data: Data("not an Office document".utf8))]).write(to: archive)
        let store = KnowledgeLibraryStore(libraryURL: libraryURL)
        let model = GoogleTakeoutImportModel(library: store)
        await model.scanAndWait([.archive(archive)])
        await model.importSelectedAndWait()
        XCTAssertEqual(store.documents.count, 0)
        XCTAssertEqual(try store.takeoutImportRecords().count, 0)
        XCTAssertEqual(model.failures.count, 1)
        let copiedFiles = FileManager.default.enumerator(atPath: libraryURL.appendingPathComponent("ImportedSources").path)?.allObjects ?? []
        XCTAssertTrue(copiedFiles.isEmpty, "A parser failure must clean up the newly staged durable copy.")
    }

    func testMixedSupportedFormatsAndDOCXFootnoteRemainSearchableAndPreserved() async throws {
        let root = try makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let docxBody = NSMutableAttributedString(string: "DOCX manuscript source. ")
        docxBody.append(Footnotes.marker(Footnote(text: "FootnoteOnlySearchToken and Unicode résumé", location: docxBody.length, length: 1), number: 1))
        let docx = try DOCXExporter.data(from: docxBody, title: "Takeout research DOCX")
        let pdfView = NSTextView(frame: NSRect(x: 0, y: 0, width: 540, height: 100))
        pdfView.string = "PDF searchable marker: QuartzSourcePhrase."
        let pdf = pdfView.dataWithPDF(inside: pdfView.bounds)
        XCTAssertTrue(PDFDocument(data: pdf)?.string?.contains("QuartzSourcePhrase") == true)
        let archive = root.appendingPathComponent("takeout-mixed.zip")
        let entries = [
            ZIPFixtureEntry(path: "Takeout/Drive/Notes/readme.txt", data: Data("PlainTextSearchToken.".utf8)),
            ZIPFixtureEntry(path: "Takeout/Drive/Notes/web.html", data: Data("<html><body><h1>Web notes</h1><p>HTMLSearchToken content.</p></body></html>".utf8)),
            ZIPFixtureEntry(path: "Takeout/Drive/Notes/manuscript.docx", data: docx),
            ZIPFixtureEntry(path: "Takeout/Drive/Notes/paper.pdf", data: pdf),
            ZIPFixtureEntry(path: "Takeout/Drive/Notes/research.md", data: Data("# Markdown source\nMarkdownSearchToken.".utf8))
        ]
        try makeZIP(entries).write(to: archive)
        let store = KnowledgeLibraryStore(libraryURL: root.appendingPathComponent("library"))
        let model = GoogleTakeoutImportModel(library: store)
        await model.scanAndWait([.archive(archive)])
        XCTAssertEqual(model.preview?.supportedDocuments, 5)
        await model.importSelectedAndWait()
        XCTAssertTrue(model.failures.isEmpty, model.failures.joined(separator: "\n"))
        XCTAssertEqual(store.documents.count, 5)
        for token in ["PlainTextSearchToken", "HTMLSearchToken", "DOCX", "QuartzSourcePhrase", "MarkdownSearchToken"] {
            XCTAssertFalse(try store.search(token).isEmpty, "Expected \(token) in imported source text")
        }
        let note = try XCTUnwrap(store.search("FootnoteOnlySearchToken").first)
        XCTAssertTrue(note.reference.context.contains("Footnote 1"))
        XCTAssertEqual(note.reference.utf16Range.length, 1, "Footnote search navigates to the verified in-text marker.")
        let docxRecord = try XCTUnwrap(store.takeoutImportRecords().first { $0.originalFilename == "manuscript.docx" })
        XCTAssertEqual(docxRecord.fingerprint, Self.sha(docx))
        XCTAssertEqual(docxRecord.metadata?.title, nil)
        let localCopy = try XCTUnwrap(store.sourceURL(for: docxRecord.documentID))
        let reopened = try BOLDWriterDocument(fileWrapper: FileWrapper(url: localCopy), contentType: .docx)
        XCTAssertEqual(try Footnotes.records(in: reopened.text).first?.text, "FootnoteOnlySearchToken and Unicode résumé")
    }

    private func makeZIP(_ entries: [ZIPFixtureEntry]) -> Data {
        var data = Data(), central = Data()
        let flags: UInt16 = 0x0800
        for item in entries {
            let name = Data(item.path.utf8), crc = Self.crc32(item.data), offset = UInt32(data.count), length = UInt32(item.data.count)
            data.appendLE(UInt32(0x04034b50)); data.appendLE(UInt16(20)); data.appendLE(flags); data.appendLE(UInt16(0)); data.appendLE(UInt16(0)); data.appendLE(UInt16(0))
            data.appendLE(crc); data.appendLE(length); data.appendLE(length); data.appendLE(UInt16(name.count)); data.appendLE(UInt16(0)); data.append(name); data.append(item.data)
            central.appendLE(UInt32(0x02014b50)); central.appendLE(UInt16(0x0314)); central.appendLE(UInt16(20)); central.appendLE(flags); central.appendLE(UInt16(0)); central.appendLE(UInt16(0)); central.appendLE(UInt16(0))
            central.appendLE(crc); central.appendLE(length); central.appendLE(length); central.appendLE(UInt16(name.count)); central.appendLE(UInt16(0)); central.appendLE(UInt16(0)); central.appendLE(UInt16(0)); central.appendLE(UInt16(0)); central.appendLE(item.unixMode << 16); central.appendLE(offset); central.append(name)
        }
        let centralOffset = UInt32(data.count), centralSize = UInt32(central.count), count = UInt16(entries.count)
        data.append(central)
        data.appendLE(UInt32(0x06054b50)); data.appendLE(UInt16(0)); data.appendLE(UInt16(0)); data.appendLE(count); data.appendLE(count); data.appendLE(centralSize); data.appendLE(centralOffset); data.appendLE(UInt16(0))
        return data
    }

    private func makeZIP64(_ zip32: Data) -> Data {
        let end = zip32.count - 22
        let count = zip32.readLE16(end + 10), centralSize = zip32.readLE32(end + 12), centralOffset = zip32.readLE32(end + 16)
        var data = Data(zip32.prefix(end))
        let zip64Offset = UInt64(data.count)
        data.appendLE(UInt32(0x06064b50)); data.appendLE(UInt64(44)); data.appendLE(UInt16(45)); data.appendLE(UInt16(45))
        data.appendLE(UInt32(0)); data.appendLE(UInt32(0)); data.appendLE(UInt64(count)); data.appendLE(UInt64(count))
        data.appendLE(UInt64(centralSize)); data.appendLE(UInt64(centralOffset))
        data.appendLE(UInt32(0x07064b50)); data.appendLE(UInt32(0)); data.appendLE(zip64Offset); data.appendLE(UInt32(1))
        data.appendLE(UInt32(0x06054b50)); data.appendLE(UInt16(0)); data.appendLE(UInt16(0)); data.appendLE(UInt16.max); data.appendLE(UInt16.max)
        data.appendLE(UInt32.max); data.appendLE(UInt32.max); data.appendLE(UInt16(0))
        return data
    }

    private static func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1 }
        }
        return ~crc
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
    func readLE16(_ offset: Int) -> UInt16 { UInt16(self[offset]) | UInt16(self[offset + 1]) << 8 }
    func readLE32(_ offset: Int) -> UInt32 { UInt32(readLE16(offset)) | UInt32(readLE16(offset + 2)) << 16 }
}
