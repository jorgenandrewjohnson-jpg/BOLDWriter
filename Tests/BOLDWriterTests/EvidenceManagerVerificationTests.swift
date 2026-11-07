import AppKit
import PDFKit
import XCTest

@testable import BOLDWriter

final class EvidenceManagerVerificationTests: XCTestCase {
    private let manuscript = "The migration took place in 1848. The record is disputed."
    private let claim = "The migration took place in 1848."

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("EvidenceVerification-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func evidence(quotation: String, location: String = "page 1", manuscript: String? = nil) throws -> (CitationSource, ClaimEvidence, String) {
        let value = manuscript ?? self.manuscript
        let anchor = try XCTUnwrap(ClaimAnchor.make(text: value, range: (value as NSString).range(of: claim)))
        let source = CitationSource(title: "Synthetic Source")
        let record = ClaimEvidence(anchor: anchor, sourceID: source.id, kind: .supporting, quotation: quotation, sourceLocation: location, authorNote: "Synthetic fixture", verificationStatus: .unverified)
        return (source, record, value)
    }

    private func writeSearchablePDF(_ text: String, to url: URL) throws {
        let data = try PDFExporter.data(from: NSAttributedString(string: text), settings: PageSettings())
        try data.write(to: url)
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

    func testSearchablePDFVerifiesQuotationAndExactPage() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("primary-source.pdf")
        let quote = "The archive recorded the full migration in the spring of 1848."
        let filler = Array(repeating: "Context paragraph for pagination and source text verification.\n\n", count: 180).joined()
        try writeSearchablePDF(filler + quote, to: path)
        let pdf = try XCTUnwrap(PDFDocument(url: path))
        XCTAssertGreaterThan(pdf.pageCount, 1)
        let expectedPage = (1...pdf.pageCount).first { pdf.page(at: $0 - 1)?.string?.contains(quote) == true }
        let (base, record, text) = try evidence(quotation: quote, location: "page \(expectedPage ?? 1)")
        var source = base
        source.localFilePath = path.path
        source.contentFingerprint = EvidenceVerification.sha256(try Data(contentsOf: path))

        let report = EvidenceVerification.report(for: source, evidence: record, manuscript: text)
        XCTAssertTrue(report.findings.contains(.verifiedPassage))
        XCTAssertEqual(report.verifiedPDFPage, expectedPage)
        XCTAssertFalse(report.findings.contains(.staleLocation))
        XCTAssertFalse(report.assertsArgumentTruth)
    }

    func testPDFPageMismatchIsStaleEvenWhenQuotationStillExists() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("dated-record.pdf")
        let filler = Array(repeating: "Context before the record.\n\n", count: 180).joined()
        let quote = "The register lists the journey in 1848."
        try writeSearchablePDF(filler + quote, to: path)
        let (base, record, text) = try evidence(quotation: quote, location: "page 1")
        var source = base
        source.localFilePath = path.path
        source.contentFingerprint = EvidenceVerification.sha256(try Data(contentsOf: path))

        let report = EvidenceVerification.report(for: source, evidence: record, manuscript: text)
        XCTAssertTrue(report.findings.contains(.verifiedPassage))
        XCTAssertTrue(report.findings.contains(.staleLocation))
        XCTAssertNotEqual(report.verifiedPDFPage, 1)
    }

    func testDOCXAndResearchNotesVerifyExactQuotationWithoutInventingPage() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let quote = "The river froze before the first thaw, according to the ledger."
        let unicodeQuote = "naïve café — 東京 🖋"
        let docx = root.appendingPathComponent("ledger.docx")
        try writeDOCX("Town ledger. \(quote) \(unicodeQuote)", to: docx)
        let (base, record, text) = try evidence(quotation: quote, location: "ledger, paragraph 1")
        var source = base
        source.localFilePath = docx.path
        source.contentFingerprint = EvidenceVerification.sha256(try Data(contentsOf: docx))
        let report = EvidenceVerification.report(for: source, evidence: record, manuscript: text)
        XCTAssertTrue(report.findings.contains(.verifiedPassage))
        XCTAssertTrue(report.findings.contains(.userEnteredNotVerified))
        XCTAssertNil(report.verifiedPDFPage)
        let unicodeRecord = ClaimEvidence(anchor: record.anchor, sourceID: source.id, kind: .supporting, quotation: unicodeQuote, sourceLocation: "ledger, paragraph 1", authorNote: "Unicode fixture", verificationStatus: .unverified)
        XCTAssertTrue(EvidenceVerification.report(for: source, evidence: unicodeRecord, manuscript: text).findings.contains(.verifiedPassage))

        let notes = root.appendingPathComponent("field-notes.md")
        try Data("Interview notes\n\n\(quote)\n".utf8).write(to: notes)
        source.localFilePath = notes.path
        source.contentFingerprint = EvidenceVerification.sha256(try Data(contentsOf: notes))
        XCTAssertTrue(EvidenceVerification.report(for: source, evidence: record, manuscript: text).findings.contains(.verifiedPassage))
    }

    func testChangedMissingUnsupportedAndMismatchedSourcesAreDistinct() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let txt = root.appendingPathComponent("research.txt")
        try Data("The initial source passage.".utf8).write(to: txt)
        let (base, record, text) = try evidence(quotation: "The initial source passage.")
        var source = base
        source.localFilePath = txt.path
        source.contentFingerprint = EvidenceVerification.sha256(try Data(contentsOf: txt))
        try Data("A later source passage.".utf8).write(to: txt)
        var report = EvidenceVerification.report(for: source, evidence: record, manuscript: text)
        XCTAssertTrue(report.findings.contains(.changedSource))
        XCTAssertTrue(report.findings.contains(.quotationMismatch))

        source.localFilePath = root.appendingPathComponent("removed.pdf").path
        report = EvidenceVerification.report(for: source, evidence: record, manuscript: text)
        XCTAssertTrue(report.findings.contains(.missingSource))

        let unsupported = root.appendingPathComponent("image.psd")
        try Data("not searchable".utf8).write(to: unsupported)
        source.localFilePath = unsupported.path
        source.contentFingerprint = EvidenceVerification.sha256(try Data(contentsOf: unsupported))
        report = EvidenceVerification.report(for: source, evidence: record, manuscript: text)
        XCTAssertTrue(report.findings.contains(.unsupportedSourceFormat))

        source.localFilePath = nil
        source.url = "https://example.invalid/research"
        report = EvidenceVerification.report(for: source, evidence: record, manuscript: text)
        XCTAssertTrue(report.findings.contains(.userEnteredNotVerified))
        XCTAssertFalse(report.findings.contains(.verifiedPassage))
    }

    func testChangedManuscriptAnchorStaysUnresolvedWithoutReanchoring() throws {
        let quote = "The source supports this exact claim."
        let (base, record, text) = try evidence(quotation: quote)
        let report = EvidenceVerification.report(for: base, evidence: record, manuscript: "An edited passage with no matching claim.")
        XCTAssertTrue(report.findings.contains(.unresolvedClaim))
        XCTAssertEqual(record.anchor.selectedText, claim)
        XCTAssertFalse(report.findings.contains(.verifiedPassage))
        XCTAssertEqual(text, manuscript)
    }

    func testWriteDisposableGUIFixturesWhenExplicitlyRequested() throws {
        guard let output = ProcessInfo.processInfo.environment["BOLD_EVIDENCE_GUI_FIXTURE_ROOT"] else {
            throw XCTSkip("Set BOLD_EVIDENCE_GUI_FIXTURE_ROOT to generate disposable GUI acceptance inputs.")
        }
        let root = URL(fileURLWithPath: output, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let manuscriptPath = root.appendingPathComponent("TEST-COPY-DO-NOT-USE-AS-ORIGINAL-Evidence-Claim.boldwriter", isDirectory: true)
        let body = NSAttributedString(string: "The migration took place in 1848.\n\nThe surviving record remains disputed.\n")
        let metadata = DocumentMetadata(title: "TEST-COPY-DO-NOT-USE-AS-ORIGINAL Evidence Claim")
        let package = try BOLDWriterDocument.packageWrapper(text: body, metadata: metadata)
        try package.write(to: manuscriptPath, options: .atomic, originalContentsURL: nil)

        let pdfPath = root.appendingPathComponent("Synthetic town ledger.pdf")
        try writeSearchablePDF("Town ledger, 1848\n\nThe migration departed on the third day of May in 1848.", to: pdfPath)
        let docxPath = root.appendingPathComponent("Synthetic counter-record.docx")
        try writeDOCX("Counter-record\n\nA later annotation disputes the migration date.", to: docxPath)
        let notesPath = root.appendingPathComponent("Research notes.md")
        try Data("Background notes\n\nUse only as contextual evidence; these notes do not establish that the claim is true.\n".utf8).write(to: notesPath)

        struct Manifest: Codable {
            var manuscriptSHA256: String
            var manuscriptPackageMetadataSHA256: String
            var pdfSHA256: String
            var docxSHA256: String
            var notesSHA256: String
            var claim: String
            var supportingQuotation: String
            var challengingQuotation: String
        }
        let manifest = Manifest(
            manuscriptSHA256: EvidenceVerification.sha256(Data(body.string.utf8)),
            manuscriptPackageMetadataSHA256: EvidenceVerification.sha256(try Data(contentsOf: manuscriptPath.appendingPathComponent("metadata.json"))),
            pdfSHA256: EvidenceVerification.sha256(try Data(contentsOf: pdfPath)),
            docxSHA256: EvidenceVerification.sha256(try Data(contentsOf: docxPath)),
            notesSHA256: EvidenceVerification.sha256(try Data(contentsOf: notesPath)),
            claim: claim,
            supportingQuotation: "The migration departed on the third day of May in 1848.",
            challengingQuotation: "A later annotation disputes the migration date."
        )
        try JSONEncoder().encode(manifest).write(to: root.appendingPathComponent("fixture-manifest.json"))
    }
}
