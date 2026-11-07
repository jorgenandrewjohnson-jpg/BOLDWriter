import Foundation
import XCTest
import Darwin
@testable import BOLDWriter

@MainActor
final class BOLDCrossDocumentAuditTests: XCTestCase {
    private struct Fixture {
        let root: URL
        let library: KnowledgeLibraryStore
        let records: [KnowledgeDocumentRecord]
        let sourceURLs: [URL]
        let sourceHashes: [String]
    }

    func testTwentySelectedLibraryDocumentsFindExactDuplicatesAndReviewCandidates() throws {
        let fixture = try makeFixture(documentCount: 20)
        let descriptors = try descriptors(for: fixture.records, store: fixture.library)
        let repeatedRule = BOLDConsistencyRule(
            kind: .preferredTerm, matchText: "YHWH", replacement: "YHVH",
            explanation: "Project spelling", scope: .outsideQuotationMarks
        )
        let quotedRule = BOLDConsistencyRule(
            kind: .preferredTerm, matchText: "YHWH", replacement: "YHVH", scope: .entireManuscript
        )
        let result = BOLDCrossDocumentSnapshotter.scan(sources: descriptors, rules: [repeatedRule, quotedRule]) { false }

        XCTAssertFalse(result.cancelled)
        XCTAssertEqual(result.scannedDocumentCount, 20)
        XCTAssertTrue(result.candidates.contains { $0.category == .repeatedPassage && $0.confidence == .exactDuplicate })
        XCTAssertTrue(result.candidates.contains { $0.category == .dateReview && $0.confidence == .potentialInconsistency })
        XCTAssertTrue(result.candidates.contains { $0.category == .nameReview && $0.confidence == .potentialInconsistency })
        XCTAssertTrue(result.candidates.contains { $0.ruleID == repeatedRule.id && $0.confidence == .exactRuleViolation && !$0.isQuoted })
        XCTAssertTrue(result.candidates.contains { $0.ruleID == quotedRule.id && $0.isQuoted })
        XCTAssertEqual(fixture.sourceHashes, try fixture.sourceURLs.map(Self.sha256))
    }

    func testCoordinatorUsesCanonicalPassageReferencesAndNavigation() async throws {
        let fixture = try makeFixture(documentCount: 20)
        let rule = BOLDConsistencyRule(kind: .preferredTerm, matchText: "YHWH", replacement: "YHVH", wholeWord: true)
        var openedLibrary = false
        let adapter = BOLDKnowledgeLibraryAuditAdapter(library: fixture.library) { openedLibrary = true }
        let cancellation = BOLDAuditCancellationToken()
        let selected = Set(fixture.records.map { $0.id.rawValue })
        let optionalResult = await BOLDCrossDocumentAuditCoordinator(library: adapter)
            .run(selectedDocumentIDs: selected, rules: [rule], cancellation: cancellation)
        let result = try XCTUnwrap(optionalResult)

        XCTAssertEqual(result.scannedDocumentCount, 20)
        XCTAssertGreaterThan(result.findings.count, 0)
        let duplicate = try XCTUnwrap(result.findings.first { $0.confidence == .exactDuplicate })
        let first = try XCTUnwrap(duplicate.primary)
        let second = try XCTUnwrap(duplicate.comparison)
        XCTAssertNotEqual(first.document.id, second.document.id)
        XCTAssertEqual(try fixture.library.resolve(first.reference).0, .current)
        XCTAssertEqual(try fixture.library.resolve(second.reference).0, .current)
        XCTAssertTrue(adapter.open(first, query: duplicate.query))
        XCTAssertTrue(openedLibrary)
        let request = try XCTUnwrap(fixture.library.consumeNavigationRequest())
        XCTAssertEqual(request.reference.documentID, first.reference.documentID)
        XCTAssertEqual(request.reference.utf16Range, first.reference.utf16Range)
        XCTAssertEqual(request.quotation, first.excerpt)

        let report = BOLDCrossDocumentReportExporter.markdown(
            title: "Synthetic", findings: result.findings,
            scannedDocumentCount: result.scannedDocumentCount, omittedCount: result.omittedPassageCount,
            staleCount: result.staleResultCount
        )
        XCTAssertTrue(report.contains("Canonical document ID:"))
        XCTAssertTrue(report.contains("Passage ID:"))
        XCTAssertTrue(report.contains("UTF-16 offset"))
        XCTAssertTrue(report.contains("not factual contradictions"))
        XCTAssertEqual(fixture.sourceHashes, try fixture.sourceURLs.map(Self.sha256))
    }

    func testChangedAndMissingSourcesAreNotTrustedAtOldOffsets() throws {
        let fixture = try makeFixture(documentCount: 2)
        let original = try XCTUnwrap(fixture.records.first)
        let oldReference = try XCTUnwrap(fixture.library.search("YHWH", documentID: original.id).first?.reference)
        let changedURL = try XCTUnwrap(fixture.sourceURLs.first)
        try Data("A wholly changed manuscript without the old passage.\n".utf8).write(to: changedURL)
        try fixture.library.refresh(documentID: original.id)
        let status = try fixture.library.resolve(oldReference).0
        XCTAssertTrue(status == .stale || status == .unresolved)

        let missingRecord = try XCTUnwrap(fixture.records.last)
        let missingURL = try XCTUnwrap(fixture.sourceURLs.last)
        try FileManager.default.removeItem(at: missingURL)
        let descriptor = BOLDCrossDocumentSourceDescriptor(
            id: missingRecord.id.rawValue, title: missingRecord.title, sourceURI: missingRecord.sourceURI,
            fingerprint: missingRecord.fingerprint, isReference: false, status: "available", url: missingURL
        )
        let scan = BOLDCrossDocumentSnapshotter.scan(sources: [descriptor], rules: []) { false }
        XCTAssertEqual(scan.scannedDocumentCount, 0)
        XCTAssertEqual(scan.unavailable.count, 1)
    }

    func testSnapshotScanCancelsAndDoesNotRetainSourceText() throws {
        let fixture = try makeFixture(documentCount: 20)
        let descriptors = try self.descriptors(for: fixture.records, store: fixture.library)
        var shouldCancel = false
        let result = BOLDCrossDocumentSnapshotter.scan(sources: descriptors, rules: []) {
            shouldCancel = true
            return true
        }
        XCTAssertTrue(result.cancelled)
        XCTAssertLessThanOrEqual(result.passages.count, BOLDCrossDocumentSnapshotter.maximumPassages)
        XCTAssertTrue(result.passages.allSatisfy { $0.normalizedText.count <= BOLDCrossDocumentSnapshotter.maximumPassagesPerParagraphCharacters })
        XCTAssertTrue(shouldCancel)
    }

    func testFourHundredChapterLibraryScanIsBoundedAndFindsFinalLocation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("BOLDCrossDocumentLong-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Long-Book.md")
        let repeated = String(repeating: "The archive preserves careful historical testimony and gives readers context for the source record. ", count: 7)
        var chapters: [String] = []
        for chapter in 1...400 {
            chapters.append("# Chapter \(chapter)\n\n\(repeated)\n\nYHWH guided the witnesses through the record.\n\n")
        }
        chapters[399] += "Final navigation marker M3ENDMARKER remains at the end of the long source.\n"
        let data = Data(chapters.joined().utf8)
        try data.write(to: url)
        let beforeHash = EvidenceVerification.sha256(data)
        let library = KnowledgeLibraryStore(libraryURL: root.appendingPathComponent("library", isDirectory: true))
        let id = try library.add(url: url)
        let record = try XCTUnwrap(library.documents.first { $0.id == id })
        let descriptor = BOLDCrossDocumentSourceDescriptor(
            id: id.rawValue, title: record.title, sourceURI: record.sourceURI,
            fingerprint: record.fingerprint, isReference: false, status: record.status.rawValue, url: url
        )
        let rules = [BOLDConsistencyRule(kind: .preferredTerm, matchText: "YHWH", replacement: "YHVH")]
        let started = ProcessInfo.processInfo.systemUptime
        let result = BOLDCrossDocumentSnapshotter.scan(sources: [descriptor], rules: rules) { false }
        let elapsed = ProcessInfo.processInfo.systemUptime - started

        XCTAssertFalse(result.cancelled)
        XCTAssertEqual(result.scannedDocumentCount, 1)
        XCTAssertLessThanOrEqual(result.passages.count, BOLDCrossDocumentSnapshotter.maximumPassagesPerDocument)
        XCTAssertLessThanOrEqual(result.candidates.count, BOLDCrossDocumentSnapshotter.maximumCandidates)
        XCTAssertTrue(result.candidates.contains { $0.category == .terminology && $0.confidence == .exactRuleViolation })
        let endResult = try XCTUnwrap(library.search("M3ENDMARKER", documentID: id).first)
        let (status, range) = try library.resolve(endResult.reference)
        XCTAssertEqual(status, .current)
        XCTAssertNotNil(range)
        XCTAssertEqual(beforeHash, EvidenceVerification.sha256(try Data(contentsOf: url)))
        print("CROSS_DOCUMENT_PERF fixture=400-chapter-long-book bytes=\(data.count) passages=\(result.passages.count) candidates=\(result.candidates.count) wallSeconds=\(String(format: "%.3f", elapsed))")
        XCTAssertLessThan(elapsed, 30, "Long-source snapshot exceeded the broad, hardware-tolerant acceptance ceiling")
        let beforeRepeatedScans = try XCTUnwrap(currentPhysicalFootprint())
        for _ in 0..<5 {
            autoreleasepool {
                let repeatedResult = BOLDCrossDocumentSnapshotter.scan(sources: [descriptor], rules: rules) { false }
                XCTAssertFalse(repeatedResult.cancelled)
                XCTAssertLessThanOrEqual(repeatedResult.passages.count, BOLDCrossDocumentSnapshotter.maximumPassagesPerDocument)
            }
        }
        let afterRepeatedScans = try XCTUnwrap(currentPhysicalFootprint())
        let growth = afterRepeatedScans > beforeRepeatedScans ? afterRepeatedScans - beforeRepeatedScans : 0
        let memoryBudget = max(64 * 1_024 * 1_024, min(256 * 1_024 * 1_024, ProcessInfo.processInfo.physicalMemory / 128))
        print("CROSS_DOCUMENT_MEMORY repeatedScans=5 growthBytes=\(growth) allowedBytes=\(memoryBudget)")
        XCTAssertLessThan(growth, memoryBudget, "Repeated cross-document scans retained too much memory")
    }

    func testEvidenceAuditProtocolSupportsSyntheticStatesAndReportsIntegrationUnavailable() async {
        let expected = [
            BOLDAuditEvidenceSignal.claimWithoutEvidence,
            .onlyUnverifiedEvidence,
            .referencedSourceUnavailable,
            .sourceCitationUnresolved,
            .evidenceRecordStale,
            .internalLinkUnverified
        ]
        let provider = SyntheticEvidenceSummaryProvider(signals: expected)
        XCTAssertFalse(provider.integrationAvailable)
        let summaries = await provider.summaries(for: [UUID()])
        XCTAssertEqual(summaries.map(\.signal), expected)
        XCTAssertTrue(summaries.allSatisfy { $0.explanation.contains("recorded") })
    }

    func testSelectedLibraryPreferencesPersistInNativeMetadata() throws {
        var metadata = DocumentMetadata()
        metadata.manuscriptAuditLibraryDocumentIDs = [UUID(), UUID()]
        let encoded = try JSONEncoder().encode(metadata)
        let reopened = try JSONDecoder().decode(DocumentMetadata.self, from: encoded)
        XCTAssertEqual(reopened.manuscriptAuditLibraryDocumentIDs, metadata.manuscriptAuditLibraryDocumentIDs)
    }

    private func makeFixture(documentCount: Int) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("BOLDCrossDocument-\(UUID().uuidString)", isDirectory: true)
        let sourceRoot = root.appendingPathComponent("sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let library = KnowledgeLibraryStore(libraryURL: root.appendingPathComponent("library", isDirectory: true))
        var records: [KnowledgeDocumentRecord] = []
        var urls: [URL] = []
        let repeated = "The archive preserves careful historical testimony and gives readers context for the source record across generations."
        for index in 0..<documentCount {
            let book = index / 5 + 1
            let chapter = index % 5 + 1
            let url = sourceRoot.appendingPathComponent("Book-\(book)-Chapter-\(chapter).md")
            var paragraphs = [
                "# Chapter \(chapter)\n",
                "YHWH guided the witnesses through the difficult winter and preserved the public record for future study.\n",
                "Quoted source: “YHWH should remain exactly as the source prints it.”\n",
                "The river campaign began in \(index == 1 ? 1849 : 1848), after the spring flood receded and the northern road reopened.\n",
                "Historian Marcellus assembled the council notes and compared them with testimony collected from local families.\n",
                "The committee evaluated the records, compared the witness accounts, and explained why the chronology remains uncertain to modern readers.\n"
            ]
            if index == 0 || index == 11 { paragraphs.append(repeated + "\n") }
            if index == 1 { paragraphs.append("Historian Marcelluus assembled the council notes and compared them with testimony collected from local families.\n") }
            if index == 0 || index == 11 { paragraphs.append("YHWH guided the witnesses through the difficult winter and preserved the public record for future study.\n") }
            try Data(paragraphs.joined().utf8).write(to: url)
            _ = try library.add(url: url)
            records.append(try XCTUnwrap(library.documents.first { $0.sourceURI == url.standardizedFileURL.absoluteString }))
            urls.append(url)
        }
        return Fixture(root: root, library: library, records: records, sourceURLs: urls, sourceHashes: try urls.map(Self.sha256))
    }

    private func descriptors(for records: [KnowledgeDocumentRecord], store: KnowledgeLibraryStore) throws -> [BOLDCrossDocumentSourceDescriptor] {
        try records.map { record in
            BOLDCrossDocumentSourceDescriptor(
                id: record.id.rawValue, title: record.title, sourceURI: record.sourceURI,
                fingerprint: record.fingerprint, isReference: record.isReference,
                status: record.status.rawValue, url: try store.sourceURL(for: record.id)
            )
        }
    }

    private static func sha256(_ url: URL) throws -> String {
        EvidenceVerification.sha256(try Data(contentsOf: url))
    }

    private func currentPhysicalFootprint() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : nil
    }
}

@MainActor
private final class SyntheticEvidenceSummaryProvider: BOLDAuditEvidenceSummaryProviding {
    let integrationAvailable = false
    private let signals: [BOLDAuditEvidenceSignal]
    init(signals: [BOLDAuditEvidenceSignal]) { self.signals = signals }
    func summaries(for documentIDs: Set<UUID>) async -> [BOLDAuditEvidenceSummary] {
        guard let documentID = documentIDs.first else { return [] }
        return signals.map { signal in
            BOLDAuditEvidenceSummary(documentID: documentID, claimID: UUID(), signal: signal, explanation: "Synthetic state from an explicitly recorded evidence record.")
        }
    }
}

