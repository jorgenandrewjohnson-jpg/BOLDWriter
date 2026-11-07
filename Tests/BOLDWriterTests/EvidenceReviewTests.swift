import Foundation
import XCTest

@testable import BOLDWriter

final class EvidenceReviewTests: XCTestCase {
    func testWriteDisposableM3ReviewGUIFixtureWhenExplicitlyRequested() throws {
        guard let output = ProcessInfo.processInfo.environment["BOLD_EVIDENCE_M3_GUI_FIXTURE_ROOT"] else {
            throw XCTSkip("Set BOLD_EVIDENCE_M3_GUI_FIXTURE_ROOT to generate the disposable Milestone 3 GUI fixture.")
        }
        let root = URL(fileURLWithPath: output, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let manuscript = "Chapter One\nThe migration began in 1848.\nThe town ledger records a departure on May 3.\n\nChapter Two\nA later annotation disputes the migration date.\nThe recorded passage was copied in 1850.\n\nChapter Three\nThe archive closed to researchers in 1960.\nA separate county record lists another route.\n"
        let body = NSMutableAttributedString(string: manuscript)
        let ns = manuscript as NSString
        for title in ["Chapter One", "Chapter Two", "Chapter Three"] {
            let range = ns.range(of: title)
            body.addAttributes([.boldWriterStyle: WriterStyle.heading1.rawValue, .font: NSFont.boldSystemFont(ofSize: 24)], range: range)
        }

        let pdfOne = root.appendingPathComponent("Synthetic town ledger.pdf")
        try PDFExporter.data(from: NSAttributedString(string: "Town Ledger — 1848\n\nThe migration departed on the third day of May in 1848.\nThe town ledger records a departure on May 3."), settings: PageSettings()).write(to: pdfOne)
        let pdfTwo = root.appendingPathComponent("Synthetic county map notes.pdf")
        try PDFExporter.data(from: NSAttributedString(string: "County Map Notes\n\nA separate county record lists another route."), settings: PageSettings()).write(to: pdfTwo)
        let staleCopy = root.appendingPathComponent("Disposable changed-source copy.pdf")
        try FileManager.default.copyItem(at: pdfTwo, to: staleCopy)
        let docx = root.appendingPathComponent("Synthetic counter-record.docx")
        try writeSyntheticDOCX("Counter-record\n\nA later annotation disputes the migration date.\nThe recorded passage was copied in 1850.", to: docx)

        let sources = [
            CitationSource(type: .archive, author: "A. Ledger Keeper", title: "Town ledger", year: "1848", publisher: "Town Archive", localFilePath: pdfOne.path, contentFingerprint: EvidenceVerification.sha256(try Data(contentsOf: pdfOne)), sourceAvailability: .available),
            CitationSource(type: .archive, author: "B. Map Clerk", title: "County map notes", year: "1850", publisher: "County Archive", localFilePath: pdfTwo.path, contentFingerprint: EvidenceVerification.sha256(try Data(contentsOf: pdfTwo)), sourceAvailability: .available),
            CitationSource(type: .archive, author: "C. Copyist", title: "Counter-record", year: "1850", publisher: "Town Archive", localFilePath: docx.path, contentFingerprint: EvidenceVerification.sha256(try Data(contentsOf: docx)), sourceAvailability: .available)
        ]
        let metadata = DocumentMetadata(title: "Synthetic Evidence Review — Three Chapters")
        var storedMetadata = metadata
        storedMetadata.citationSources = sources
        storedMetadata.citationStyle = .apa
        let packageURL = root.appendingPathComponent("TEST-COPY-DO-NOT-USE-AS-ORIGINAL-Evidence-Review.boldwriter", isDirectory: true)
        try BOLDWriterDocument.packageWrapper(text: body, metadata: storedMetadata).write(to: packageURL, options: .atomic, originalContentsURL: nil)

        let hash: (Data) -> String = { EvidenceVerification.sha256($0) }
        let manifest: [String: Any] = [
            "claimPassages": ["The migration began in 1848.", "The town ledger records a departure on May 3.", "A later annotation disputes the migration date.", "The recorded passage was copied in 1850.", "The archive closed to researchers in 1960.", "A separate county record lists another route."],
            "manuscriptTextSHA256": hash(Data(manuscript.utf8)),
            "sources": [
                ["file": pdfOne.lastPathComponent, "sha256": hash(try Data(contentsOf: pdfOne))],
                ["file": pdfTwo.lastPathComponent, "sha256": hash(try Data(contentsOf: pdfTwo))],
                ["file": staleCopy.lastPathComponent, "sha256": hash(try Data(contentsOf: staleCopy)), "role": "Disposable file to mutate during stale-source GUI check"],
                ["file": docx.lastPathComponent, "sha256": hash(try Data(contentsOf: docx))]
            ],
            "linkedSourceMutation": "The GUI stale-source case deliberately changes a disposable copy of Synthetic town ledger.pdf after recording its initial hash."
        ]
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: root.appendingPathComponent("fixture-manifest.json"), options: .atomic)
        try Data("""
        # Evidence Review M3 disposable GUI fixture

        All manuscript/source files are synthetic. Open TEST-COPY-DO-NOT-USE-AS-ORIGINAL-Evidence-Review.boldwriter in the isolated candidate. The document has three heading-styled chapters and several unassociated sentence passages. Attach sources from this fixture only. Do not use this package as an original manuscript.

        The fixture manifest records initial source SHA-256 values. Attach Disposable changed-source copy.pdf as a separate source for the stale-source check, then mutate that copy only. The two baseline PDFs and DOCX remain hash controls.
        """.utf8).write(to: root.appendingPathComponent("README.md"))
    }

    func testReviewIndexListsCoveredAndUncoveredPassagesAndChapter() throws {
        let text = "Chapter One\n\nThe river froze in January. The record names the date.\n\nChapter Two\n\nThe archive lists a second departure."
        let ns = text as NSString
        let first = try XCTUnwrap(ClaimAnchor.make(text: text, range: ns.range(of: "The river froze in January.")))
        let source = CitationSource(author: "A. Reader", title: "Town Ledger", year: "1848")
        let evidence = ClaimEvidence(anchor: first, sourceID: source.id, kind: .supporting, quotation: "The river froze in January.", sourceLocation: "page 2", authorNote: "", verificationStatus: .unverified)
        let outline = [
            OutlineItem(title: "Chapter One", level: 1, range: ns.range(of: "Chapter One")),
            OutlineItem(title: "Chapter Two", level: 1, range: ns.range(of: "Chapter Two"))
        ]

        let claims = EvidenceReviewIndex.claims(in: text, evidence: [evidence], sources: [source], style: .apa, outline: outline)

        XCTAssertEqual(claims.map(\.text), ["The river froze in January.", "The record names the date.", "The archive lists a second departure."])
        XCTAssertEqual(claims.map(\.chapter), ["Chapter One", "Chapter One", "Chapter Two"])
        XCTAssertEqual(claims.filter(\.hasRecordedEvidence).count, 1)
        XCTAssertEqual(claims.filter { !$0.hasRecordedEvidence }.count, 2)
        XCTAssertTrue(claims[0].evidence.contains(where: { $0.id == evidence.id }))
    }

    func testReviewIndexExcludesBibliographyEntriesFromClaimCoverage() {
        let text = "A dated statement appears in the chapter.\n\nReferences\nA. Author. (1848). A Ledger of Dates. Town Archive.\n"
        let claims = EvidenceReviewIndex.claims(in: text, evidence: [], sources: [], style: .apa)

        XCTAssertEqual(claims.map(\.text), ["A dated statement appears in the chapter."])
    }

    func testReviewIndexKeepsAmbiguousOrChangedAnchorsAsUnresolvedRows() throws {
        let text = "A repeated claim. A repeated claim. A different sentence."
        let source = CitationSource(title: "Notes")
        let repeated = ClaimAnchor(selectedText: "A repeated claim.", utf16Location: 900, utf16Length: 17, precedingContext: "", followingContext: "", selectedTextSHA256: EvidenceVerification.sha256(Data("A repeated claim.".utf8)))
        let item = ClaimEvidence(anchor: repeated, sourceID: source.id, kind: .contextual, quotation: "The notes", sourceLocation: "section 1", authorNote: "", verificationStatus: .unverified)

        let claims = EvidenceReviewIndex.claims(in: text, evidence: [item], sources: [source], style: .apa)

        XCTAssertEqual(claims.filter { !$0.unresolvedEvidence.isEmpty }.count, 1)
        XCTAssertEqual(claims.last?.chapter, "Unresolved anchor")
    }

    func testReviewIndexPreservesUnicodeAndUsesUTF16NavigationRanges() throws {
        let text = "The archivist wrote café and 東京. Another event happened."
        let ns = text as NSString
        let claimText = "The archivist wrote café and 東京."
        let range = ns.range(of: claimText)
        let anchor = try XCTUnwrap(ClaimAnchor.make(text: text, range: range))
        let source = CitationSource(title: "Unicode notes")
        let record = ClaimEvidence(anchor: anchor, sourceID: source.id, kind: .supporting, quotation: "café and 東京", sourceLocation: "paragraph 1", authorNote: "", verificationStatus: .unverified)
        let claims = EvidenceReviewIndex.claims(in: text, evidence: [record], sources: [source], style: .apa)

        XCTAssertEqual(claims.first?.text, claimText)
        XCTAssertEqual((text as NSString).substring(with: claims[0].range), claimText)
        XCTAssertEqual(claims[0].evidence.map(\.id), [record.id])
    }

    func testReviewIndexHandlesSeveralHundredEvidenceRecordsAndOneSourceReused() throws {
        let count = 350
        let sentences = (0..<count).map { "The archive entry records date \($0)." }
        let text = sentences.joined(separator: "\n")
        let ns = text as NSString
        let source = CitationSource(title: "Shared archive record")
        let records = try sentences.map { sentence -> ClaimEvidence in
            let range = ns.range(of: sentence)
            let anchor = try XCTUnwrap(ClaimAnchor.make(text: text, range: range))
            return ClaimEvidence(anchor: anchor, sourceID: source.id, kind: .contextual, quotation: sentence, sourceLocation: "entry", authorNote: "", verificationStatus: .unverified)
        }

        let claims = EvidenceReviewIndex.claims(in: text, evidence: records, sources: [source], style: .apa)

        XCTAssertEqual(claims.count, count)
        XCTAssertTrue(claims.allSatisfy { $0.evidence.count == 1 })
        XCTAssertEqual(Set(records.map(\.sourceID)), [source.id])
    }

    func testCitationResolutionReportsMetadataOutdatedAndUpdatesOnlyUnambiguousDisplay() throws {
        let text = "The report confirms it (Reader, 1848)."
        let old = CitationSource(author: "A. Reader", title: "Ledger", year: "1848")
        var edited = old
        edited.author = "A. Author"
        edited.citationDisplayHistory = [.apa: CitationFormatter.citation(for: old, style: .apa)]
        let resolution = DocumentCitations.citedSourceResolution(in: text, sources: [edited], style: .apa)
        let range = NSRange(location: 0, length: (text as NSString).length)

        XCTAssertEqual(resolution.citedSourceIDs, [edited.id])
        XCTAssertEqual(resolution.outdatedCitationSourceIDs, [edited.id])
        let replacements = DocumentCitations.outdatedCitationReplacements(in: text, sources: [edited], style: .apa, within: range)
        XCTAssertEqual(replacements.count, 1)
        XCTAssertEqual((text as NSString).substring(with: replacements[0].range), "(Reader, 1848)")
        XCTAssertEqual(replacements[0].replacement, "(Author, 1848)")
    }

    func testCitationResolutionDoesNotGuessBetweenDuplicateDisplays() {
        let first = CitationSource(author: "A. Reader", title: "Ledger A", year: "1848")
        let second = CitationSource(author: "B. Reader", title: "Ledger B", year: "1848")
        let text = "The record says so (Reader, 1848)."
        let resolution = DocumentCitations.citedSourceResolution(in: text, sources: [first, second], style: .apa)

        XCTAssertTrue(resolution.citedSourceIDs.isEmpty)
        XCTAssertEqual(resolution.ambiguousDisplays, ["(Reader, 1848)"])
    }

    func testBibliographyDeduplicatesOneRepeatedSourceIdentity() {
        let source = CitationSource(author: "A Reader", title: "Ledger", year: "1848")
        let result = CitationFormatter.bibliography(sources: [source, source], style: .apa)
        XCTAssertEqual(result.components(separatedBy: "Ledger.").count - 1, 1)
    }

    func testBibliographyDeduplicatesDifferentRecordsForSameCanonicalSource() {
        let first = CitationSource(author: "A Reader", title: "Ledger", year: "1848", url: "https://archive.example/ledger")
        let duplicate = CitationSource(author: "A Reader", title: "Ledger copy", year: "1848", url: "https://archive.example/ledger")
        let result = CitationFormatter.bibliography(sources: [first, duplicate], style: .apa)
        XCTAssertEqual(result.components(separatedBy: "A Reader").count - 1, 1)
    }

    func testCitationMetadataHintsDoNotClaimStyleCompliance() {
        let source = CitationSource(type: .book, title: "Ledger")
        XCTAssertTrue(DocumentCitations.metadataHints(for: source).contains("Author or responsible body is missing"))
        XCTAssertTrue(DocumentCitations.metadataHints(for: source).contains("Publication year is missing"))
        XCTAssertFalse(DocumentCitations.metadataHints(for: source).contains { $0.localizedCaseInsensitiveContains("APA") })
    }

    func testSourceMergeRequiresSameStableLocatorAndPreservesEvidenceAssociations() throws {
        let first = CitationSource(author: "Reader", title: "Ledger", year: "1848", localFilePath: "/tmp/synthetic-ledger.pdf")
        let second = CitationSource(author: "Reader", title: "Duplicate catalog entry", year: "1848", localFilePath: "/tmp/synthetic-ledger.pdf")
        let anchor = try XCTUnwrap(ClaimAnchor.make(text: "Claim.", range: NSRange(location: 0, length: 6)))
        let record = ClaimEvidence(anchor: anchor, sourceID: second.id, kind: .challenging, quotation: "Quote", sourceLocation: "page 1", authorNote: "", verificationStatus: .unverified)

        let merged = try DocumentEvidence.mergeSourceRecords(keeping: first.id, removing: second.id, sources: [first, second], evidence: [record])

        XCTAssertEqual(merged.sources.map(\.id), [first.id])
        XCTAssertEqual(merged.evidence.first?.sourceID, first.id)
        XCTAssertEqual(merged.evidence.first?.kind, .challenging)
        let unsafe = CitationSource(author: "Reader", title: "Ledger", year: "1848", localFilePath: "/tmp/another.pdf")
        XCTAssertThrowsError(try DocumentEvidence.mergeSourceRecords(keeping: first.id, removing: unsafe.id, sources: [first, unsafe], evidence: [record]))
    }

    func testDuplicateCandidateDetectionUsesStableSourceLocator() {
        let first = CitationSource(author: "Reader A", title: "Ledger", year: "1848", localFilePath: "/tmp/shared-ledger.pdf")
        let duplicate = CitationSource(author: "Unknown", title: "Copied catalog record", localFilePath: "/tmp/shared-ledger.pdf")
        let groups = DocumentEvidence.duplicateSourceIDs(in: [first, duplicate])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(Set(groups[0]), [first.id, duplicate.id])
        XCTAssertFalse(DocumentEvidence.canSafelyMerge(first, duplicate), "A shared source locator is necessary but not sufficient when citation displays differ.")
    }

    @MainActor
    func testResearchReportStatesCoverageLimitsAndSourceIdentity() {
        let sentences = (0..<EvidenceResearchReport.maximumClaims + 1).map { "Claim number \($0) is stated." }
        let text = sentences.joined(separator: " ")
        let source = CitationSource(title: "Research notes")
        let report = EvidenceResearchReport.markdown(manuscript: text, evidence: [], sources: [source], style: .apa)

        XCTAssertTrue(report.contains("do not determine whether a claim is true"))
        XCTAssertTrue(report.contains("No evidence recorded in BOLD Writer"))
        XCTAssertTrue(report.contains("At least one additional passage was omitted"))
        XCTAssertTrue(report.contains(source.id.uuidString))
    }

    @MainActor
    func testReadOnlyAuditSummaryCountsCoverageWithoutTruthJudgment() {
        let text = "Covered sentence. Uncovered sentence."
        let ns = text as NSString
        let anchor = ClaimAnchor.make(text: text, range: ns.range(of: "Covered sentence."))!
        let source = CitationSource(title: "Local notes")
        let record = ClaimEvidence(anchor: anchor, sourceID: source.id, kind: .challenging, quotation: "Counterpoint", sourceLocation: "section A", authorNote: "", verificationStatus: .unverified)
        let summary = EvidenceAuditSummaryProvider.summary(manuscript: text, evidence: [record], sources: [source])

        XCTAssertEqual(summary.claimCount, 2)
        XCTAssertEqual(summary.claimsWithoutEvidence, 1)
        XCTAssertEqual(summary.claimsWithOnlyUnverifiedEvidence, 1)
        XCTAssertEqual(summary.challengingEvidenceCount, 1)
        XCTAssertEqual(summary.unresolvedAnchorCount, 0)
    }

    private func writeSyntheticDOCX(_ text: String, to url: URL) throws {
        let word = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
        let office = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
        let paragraphs = text.components(separatedBy: "\n").map { paragraph in "<w:p><w:r><w:t xml:space=\"preserve\">\(paragraph.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;"))</w:t></w:r></w:p>" }.joined()
        let parts = [
            "[Content_Types].xml": "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/></Types>",
            "_rels/.rels": "<Relationships xmlns=\"\(office)\"><Relationship Id=\"main\" Type=\"\(office)officeDocument\" Target=\"word/document.xml\"/></Relationships>",
            "word/document.xml": "<w:document xmlns:w=\"\(word)\"><w:body>\(paragraphs)<w:sectPr/></w:body></w:document>"
        ]
        try ZipArchiveWriter.archive(parts.map { ZipEntry(path: $0.key, data: Data($0.value.utf8)) }).write(to: url)
    }
}
