import AppKit
import XCTest
@testable import BOLDWriter

final class BookAuditStructuralTests: XCTestCase {
    func testSemanticHeadingsFindEmptySectionsAndHierarchySkips() throws {
        let text = "Chapter One\n\nChapter Two\n\nDeep Topic\nBody text follows."
        let storage = NSMutableAttributedString(string: text)
        let source = text as NSString
        for (title, style) in [("Chapter One", WriterStyle.heading1), ("Chapter Two", WriterStyle.heading1), ("Deep Topic", WriterStyle.heading3)] {
            storage.addAttribute(.boldWriterStyle, value: style.rawValue, range: source.range(of: title))
        }
        let snapshot = BOLDBookAuditAnalyzer.snapshot(from: storage)
        let findings = try XCTUnwrap(BOLDBookAuditAnalyzer.analyze(snapshot, metadata: metadata(), shouldCancel: { false }))
        XCTAssertTrue(findings.contains { $0.category == .emptySection && $0.firstRange.location == source.range(of: "Chapter One").location })
        XCTAssertTrue(findings.contains { $0.category == .headingHierarchy && $0.firstRange.location == source.range(of: "Deep Topic").location })
        XCTAssertEqual(findings.first(where: { $0.category == .emptySection })?.auditConfidence, .confirmedStructuralDefect)
    }

    func testBrokenInternalReferenceAndLinkAreReportedFromNativeRuns() throws {
        let text = "See reference and link."
        let storage = NSMutableAttributedString(string: text)
        let source = text as NSString
        let fieldRange = source.range(of: "reference")
        let field = WordField(kind: .simple, instruction: "REF MissingAnchor", dirtyValue: "?")
        storage.addAttribute(.boldWriterField, value: field, range: fieldRange)
        storage.addAttribute(.link, value: "#MissingAnchor", range: source.range(of: "link"))
        let snapshot = BOLDBookAuditAnalyzer.snapshot(from: storage)
        let findings = try XCTUnwrap(BOLDBookAuditAnalyzer.analyze(snapshot, metadata: metadata(), shouldCancel: { false }))
        XCTAssertTrue(findings.contains { $0.category == .brokenCrossReference && $0.firstRange == fieldRange })
        XCTAssertTrue(findings.contains { $0.category == .unresolvedLink })
    }

    func testEmptyContentsFieldIsAReviewSuggestionUntilConfirmed() throws {
        let text = " "
        let storage = NSMutableAttributedString(string: text)
        let field = WordField(kind: .simple, instruction: "TOC \\o \"1-3\"")
        storage.addAttribute(.boldWriterField, value: field, range: NSRange(location: 0, length: (text as NSString).length))
        let findings = try XCTUnwrap(BOLDBookAuditAnalyzer.analyze(BOLDBookAuditAnalyzer.snapshot(from: storage), metadata: metadata(), shouldCancel: { false }))
        let contents = try XCTUnwrap(findings.first { $0.category == .malformedTableOfContents })
        XCTAssertEqual(contents.auditConfidence, .reviewSuggestion)
    }

    func testStyledBlockQuotationIsProtectedFromOriginalProseRules() throws {
        let text = "Yehoshua said this in the source."
        let storage = NSMutableAttributedString(string: text)
        storage.addAttribute(.boldWriterStyle, value: WriterStyle.blockQuote.rawValue, range: NSRange(location: 0, length: (text as NSString).length))
        var settings = metadata()
        settings.rules = [BOLDConsistencyRule(kind: .preferredTerm, matchText: "Yehoshua", replacement: "Yeshua", scope: .outsideQuotationMarks)]
        let snapshot = BOLDBookAuditAnalyzer.snapshot(from: storage)
        let findings = try XCTUnwrap(BOLDBookAuditAnalyzer.analyze(snapshot, metadata: settings, shouldCancel: { false }))
        XCTAssertFalse(findings.contains { $0.category == .authorRuleViolation })
    }

    func testArgumentStructureUsesReviewPromptsForLongSectionsAndEarlyConclusions() throws {
        let body = "In conclusion, the surviving records require further discussion. " + String(repeating: "context evidence interpretation development ", count: 1_400)
        let text = "Chapter One\n\n\(body)\n\nChapter Two\n\nA shorter section."
        let storage = NSMutableAttributedString(string: text)
        let source = text as NSString
        storage.addAttribute(.boldWriterStyle, value: WriterStyle.heading1.rawValue, range: source.range(of: "Chapter One"))
        storage.addAttribute(.boldWriterStyle, value: WriterStyle.heading1.rawValue, range: source.range(of: "Chapter Two"))

        let findings = try XCTUnwrap(BOLDBookAuditAnalyzer.analyze(
            BOLDBookAuditAnalyzer.snapshot(from: storage), metadata: metadata(), shouldCancel: { false }
        ))
        let prompts = findings.filter { $0.category == .argumentStructure }
        XCTAssertTrue(prompts.contains { $0.explanation.contains("unusually long") })
        XCTAssertTrue(prompts.contains { $0.explanation.contains("conclusion marker") })
        XCTAssertTrue(prompts.allSatisfy { $0.auditConfidence == .reviewSuggestion })
        XCTAssertEqual(storage.string, text)
    }

    func testComprehensiveAuditDoesNotMutateAttributedManuscript() throws {
        let text = NSMutableAttributedString(string: "Original prose says Yehoshua.\n\n‘Quoted Yehoshua’ stays source text.")
        let original = NSAttributedString(attributedString: text)
        var settings = metadata()
        settings.rules = [BOLDConsistencyRule(kind: .preferredTerm, matchText: "Yehoshua", replacement: "Yeshua", scope: .outsideQuotationMarks)]
        let findings = try XCTUnwrap(BOLDBookAuditAnalyzer.analyze(BOLDBookAuditAnalyzer.snapshot(from: text), metadata: settings, shouldCancel: { false }))
        XCTAssertFalse(findings.isEmpty)
        XCTAssertEqual(text, original)
    }

    func testAuditReportContainsConfidenceLocationAndReason() {
        let text = "Yehoshua wrote the original record."
        let rule = BOLDConsistencyRule(kind: .preferredTerm, matchText: "Yehoshua", replacement: "Yeshua", explanation: "Project spelling")
        let findings = BOLDConsistencyScanner().scan(text, rules: [rule])
        let report = BOLDAuditReportExporter.markdown(title: "Synthetic", text: text, findings: findings, ignoredCount: 2, generatedAt: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(report.contains("Exact rule violation"))
        XCTAssertTrue(report.contains("Paragraph 1 · line 1"))
        XCTAssertTrue(report.contains("Preferred terminology"))
        XCTAssertTrue(report.contains("Ignored: 2"))
        XCTAssertTrue(report.contains("Citation target checks are unavailable"))
    }

    func testAuditReportBoundsLargeFindingSetsAndStatesWhatWasOmitted() {
        let source = String(repeating: "Yehoshua wrote the record.\n", count: 300)
        let rule = BOLDConsistencyRule(kind: .preferredTerm, matchText: "Yehoshua", replacement: "Yeshua")
        let findings = BOLDConsistencyScanner().scan(source, rules: [rule], maximumFindings: 400)
        XCTAssertEqual(findings.count, 300)
        let report = BOLDAuditReportExporter.markdown(title: "Synthetic", text: source, findings: findings, ignoredCount: 0)
        XCTAssertTrue(report.contains("Findings available: 300 · Included: 250 · Omitted: 50"))
        XCTAssertEqual(report.components(separatedBy: "## ").count - 1, 250)
        XCTAssertLessThan(report.utf8.count, 100_000)
    }

    private func metadata() -> BOLDAuditMetadataSnapshot {
        BOLDAuditMetadataSnapshot(sections: [], bookmarks: [], tableOfContents: [], footnotes: nil, rules: [])
    }
}
