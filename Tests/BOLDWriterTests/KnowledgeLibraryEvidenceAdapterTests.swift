import Foundation
import PDFKit
import XCTest

@testable import BOLDWriter

@MainActor final class KnowledgeLibraryEvidenceAdapterTests: XCTestCase {
    private func root() throws -> URL {
        let value = FileManager.default.temporaryDirectory.appendingPathComponent("EvidenceLibraryAdapter-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: value, withIntermediateDirectories: true)
        return value
    }

    private func writeDOCX(_ text: String, to url: URL) throws {
        let w = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
        let rel = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
        let escaped = text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        let parts = [
            "[Content_Types].xml": "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/></Types>",
            "_rels/.rels": "<Relationships xmlns=\"\(rel)\"><Relationship Id=\"main\" Type=\"\(rel)/officeDocument\" Target=\"word/document.xml\"/></Relationships>",
            "word/document.xml": "<w:document xmlns:w=\"\(w)\"><w:body><w:p><w:r><w:t xml:space=\"preserve\">\(escaped)</w:t></w:r></w:p><w:sectPr/></w:body></w:document>"
        ]
        try ZipArchiveWriter.archive(parts.map { ZipEntry(path: $0.key, data: Data($0.value.utf8)) }).write(to: url)
    }

    func testSelectedSourceGetsCanonicalIdentityAndExactPassagesCanBackMultipleClaims() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("ledger.md")
        let original = "# Register\nThe migration departed on 3 May 1848 — naïve readers should check the original record.\n\n# Counter entry\nA later annotation disputes the migration date.\n"
        try Data(original.utf8).write(to: path)
        let library = KnowledgeLibraryStore(libraryURL: root.appendingPathComponent("library"))
        let adapter = KnowledgeLibraryEvidenceAdapter(store: library)
        let source = CitationSource(type: .archive, author: "Town Recorder", title: "Town register", localFilePath: path.path)

        let document = try adapter.addOrFindSelectedSource(source)
        XCTAssertEqual(library.documents.first?.id, document.id)
        XCTAssertEqual(EvidenceVerification.sha256(try Data(contentsOf: path)), EvidenceVerification.sha256(Data(original.utf8)))

        let supportQuote = "The migration departed on 3 May 1848 — naïve readers should check the original record."
        let support = try XCTUnwrap(adapter.exactPassages(for: source, quotation: supportQuote).first)
        XCTAssertEqual(support.reference.documentID, document.id)
        XCTAssertTrue(support.reference.context.contains("Register"))
        XCTAssertTrue(support.excerpt.localizedCaseInsensitiveContains("migration departed"))

        let challengeQuote = "A later annotation disputes the migration date."
        let challenge = try XCTUnwrap(adapter.exactPassages(for: source, quotation: challengeQuote).first)
        XCTAssertEqual(challenge.reference.documentID, support.reference.documentID, "One canonical source can support and challenge evidence on a claim.")
        XCTAssertNotEqual(challenge.reference.passageID, support.reference.passageID)

        let stored = try adapter.serializedReference(for: support)
        let decoded = try JSONDecoder().decode(KnowledgePassageReference.self, from: stored)
        XCTAssertEqual(decoded.documentID, document.id)
        XCTAssertEqual(decoded.passageID, support.reference.passageID)
        XCTAssertEqual(adapter.resolve(stored, exactQuotation: supportQuote).status, .current)
    }

    func testDuplicateExactPassagesRemainSeparateAndWrongQuotationCannotLink() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("repeated.txt")
        try Data("First occurrence of the exact statement.\n\nSecond occurrence of the exact statement.\n".utf8).write(to: path)
        let library = KnowledgeLibraryStore(libraryURL: root.appendingPathComponent("library"))
        let adapter = KnowledgeLibraryEvidenceAdapter(store: library)
        let source = CitationSource(title: "Repeated register", localFilePath: path.path)
        let matches = try adapter.exactPassages(for: source, quotation: "occurrence of the exact statement")
        XCTAssertEqual(matches.count, 2)
        XCTAssertNotEqual(matches[0].reference.passageID, matches[1].reference.passageID)
        XCTAssertTrue(try adapter.exactPassages(for: source, quotation: "A quotation not in the source").isEmpty)
    }

    func testCanonicalLibraryAdapterVerifiesSearchablePDFAndDOCXQuotations() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let library = KnowledgeLibraryStore(libraryURL: root.appendingPathComponent("library"))
        let adapter = KnowledgeLibraryEvidenceAdapter(store: library)

        let pdfURL = root.appendingPathComponent("ledger.pdf")
        let pdfQuote = "The county ledger records the spring migration of 1848."
        try PDFExporter.data(from: NSAttributedString(string: "Archive transcription.\n\n\(pdfQuote)"), settings: PageSettings()).write(to: pdfURL)
        let pdfSource = CitationSource(type: .archive, title: "County ledger", localFilePath: pdfURL.path)
        let pdfPassage = try XCTUnwrap(adapter.exactPassages(for: pdfSource, quotation: pdfQuote).first)
        XCTAssertEqual(pdfPassage.reference.documentID, library.documents.first(where: { $0.title == "ledger" })?.id)
        XCTAssertEqual(adapter.resolve(try adapter.serializedReference(for: pdfPassage), exactQuotation: pdfQuote).status, .current)

        let docxURL = root.appendingPathComponent("correspondence.docx")
        let unicodeQuote = "naïve café — 東京 was copied into the dispatch."
        try writeDOCX("Office copy. \(unicodeQuote)", to: docxURL)
        let docxSource = CitationSource(type: .archive, title: "Correspondence", localFilePath: docxURL.path)
        let docxPassage = try XCTUnwrap(adapter.exactPassages(for: docxSource, quotation: unicodeQuote).first)
        XCTAssertTrue(docxPassage.reference.context.contains("Paragraph"))
        XCTAssertEqual(adapter.resolve(try adapter.serializedReference(for: docxPassage), exactQuotation: unicodeQuote).status, .current)
    }

    func testChangedAndMissingPassagesWarnAndNeverNavigateToAnUnrelatedRange() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("archive.txt")
        try Data("Stable passage: the bridge opened in 1901.\nThe report was signed in June.".utf8).write(to: path)
        let library = KnowledgeLibraryStore(libraryURL: root.appendingPathComponent("library"))
        let adapter = KnowledgeLibraryEvidenceAdapter(store: library)
        let source = CitationSource(title: "Archive report", localFilePath: path.path)
        let option = try XCTUnwrap(adapter.exactPassages(for: source, quotation: "the bridge opened in 1901").first)
        let reference = try adapter.serializedReference(for: option)

        try Data("Inserted cover note.\nStable passage: the bridge opened in 1901.\nThe report was signed in June.".utf8).write(to: path)
        let moved = adapter.resolve(reference, exactQuotation: "the bridge opened in 1901")
        XCTAssertEqual(moved.status, .revalidated)
        XCTAssertNotNil(moved.verifiedLocation)

        try Data("Inserted cover note.\nStable passage: bridge dates were removed.\nThe report was signed in June.".utf8).write(to: path)
        let changed = adapter.resolve(reference, exactQuotation: "the bridge opened in 1901", revalidateDisk: true)
        XCTAssertEqual(changed.status, .stale)
        XCTAssertNil(changed.verifiedLocation)

        try FileManager.default.removeItem(at: path)
        let missing = adapter.resolve(reference, exactQuotation: "the bridge opened in 1901", revalidateDisk: true)
        XCTAssertEqual(missing.status, .unresolved)
        XCTAssertNil(missing.verifiedLocation)
    }

    func testNativeSaveReopenPreservesCanonicalPassageAndDeletingAssociationKeepsSource() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("field notes.md")
        let sourceText = "Field notes from the expedition.\nThe glacier ended at the northern ridge.\n"
        try Data(sourceText.utf8).write(to: path)
        let library = KnowledgeLibraryStore(libraryURL: root.appendingPathComponent("library"))
        let adapter = KnowledgeLibraryEvidenceAdapter(store: library)
        let citation = CitationSource(type: .archive, author: "Field team", title: "Expedition notes", localFilePath: path.path)
        let option = try XCTUnwrap(adapter.exactPassages(for: citation, quotation: "The glacier ended at the northern ridge.").first)
        let manuscript = "The ice margin was limited by a northern ridge."
        let anchor = try XCTUnwrap(ClaimAnchor.make(text: manuscript, range: (manuscript as NSString).range(of: manuscript)))
        var evidence = ClaimEvidence(anchor: anchor, sourceID: citation.id, kind: .supporting, quotation: "The glacier ended at the northern ridge.", sourceLocation: option.reference.context, authorNote: "Field measurement", verificationStatus: .unverified)
        evidence.libraryPassageReference = try adapter.serializedReference(for: option)
        var metadata = DocumentMetadata(title: "Disposable evidence test")
        metadata.citationSources = [citation]
        metadata.claimEvidence = [evidence]
        let wrapper = try BOLDWriterDocument.packageWrapper(text: NSAttributedString(string: manuscript), metadata: metadata)
        let packageURL = root.appendingPathComponent("evidence.boldwriter", isDirectory: true)
        try wrapper.write(to: packageURL, options: .atomic, originalContentsURL: nil)
        let reopened = try BOLDWriterDocument(fileWrapper: FileWrapper(url: packageURL), contentType: .boldWriterDocument)
        let roundTrip = try XCTUnwrap(reopened.metadata.claimEvidence?.first)
        XCTAssertEqual(roundTrip.libraryPassageReference, evidence.libraryPassageReference)
        XCTAssertEqual(adapter.resolve(try XCTUnwrap(roundTrip.libraryPassageReference), exactQuotation: roundTrip.quotation).status, .current)
        XCTAssertEqual(EvidenceVerification.sha256(Data(reopened.text.string.utf8)), EvidenceVerification.sha256(Data(manuscript.utf8)))

        reopened.metadata.claimEvidence = []
        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path), "Removing the association must not delete the source file.")
        XCTAssertTrue(library.documents.contains(where: { $0.id == option.reference.documentID }), "Removing an association must not delete the Knowledge Library identity.")
    }

    func testChangingEvidenceSourceCreatesSeparateAssociationInsteadOfReassigning() throws {
        let manuscript = "A claim with two competing sources."
        let anchor = try XCTUnwrap(ClaimAnchor.make(text: manuscript, range: (manuscript as NSString).range(of: manuscript)))
        let firstSource = CitationSource(title: "First source")
        let secondSource = CitationSource(title: "Counter source")
        let first = ClaimEvidence(anchor: anchor, sourceID: firstSource.id, kind: .supporting, quotation: "The first text supports the claim.", sourceLocation: "section A", authorNote: "Original association", verificationStatus: .unverified)
        let edit = ClaimEvidence(anchor: anchor, sourceID: secondSource.id, kind: .challenging, quotation: "The second text disputes the claim.", sourceLocation: "section B", authorNote: "Counter evidence", verificationStatus: .unverified)
        let outcome = DocumentEvidence.upsert(edit, editing: first.id, in: [first])
        XCTAssertEqual(outcome.records.count, 2)
        XCTAssertEqual(outcome.records.first, first)
        XCTAssertEqual(outcome.records.last?.sourceID, secondSource.id)
        XCTAssertNotEqual(outcome.selectedID, first.id)
    }
}
