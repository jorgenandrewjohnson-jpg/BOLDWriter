
import Foundation
import XCTest
@testable import BOLDWriter

final class BOLDConsistencyScannerTests: XCTestCase {
    func testContradictoryDatesSameEvent() {
        let text = """
        The siege of Jerusalem began in AD 66.

        The siege of Jerusalem began in AD 67.
        """

        let findings = BOLDConsistencyScanner().scan(text)

        XCTAssertTrue(
            findings.contains { $0.category == .conflictingDates }
        )
    }

    func testUnrelatedDatesNotContradictions() {
        let text = """
        The siege of Jerusalem began in AD 66.

        The construction of the Temple began in AD 67.
        """

        XCTAssertFalse(
            BOLDConsistencyScanner().scan(text)
                .contains { $0.category == .conflictingDates }
        )
    }

    func testNameSpellingCandidate() {
        let text = """
        Dellano returned. Dellano spoke quietly.

        Delano watched. Delano left the building.
        """

        XCTAssertTrue(
            BOLDConsistencyScanner().scan(text)
                .contains { $0.category == .nameVariants }
        )
    }

    func testCompoundTerminologyAndCapitalization() {
        let text = """
        The physical-book opens. The physical-book closes.
        The physical book opens. The physical book closes.
        The Covenant continues. The Covenant remains.
        The covenant is described. The covenant is explained.
        """

        let categories = Set(
            BOLDConsistencyScanner().scan(text).map(\.category)
        )

        XCTAssertTrue(categories.contains(.terminology))
        XCTAssertTrue(categories.contains(.capitalization))
    }

    func testExactDuplicatesPreserveUnicodeOffsets() {
        let paragraph = "The historical evidence is carefully examined through multiple independent manuscripts and documented ancient witnesses."

        let document = "🍎 Introduction.\n\n\(paragraph)\n\n\(paragraph)"

        let finding = BOLDConsistencyScanner()
            .scan(document)
            .first { $0.category == .duplicateParagraphs }

        XCTAssertNotNil(finding)

        if let finding {
            XCTAssertEqual(
                finding.firstRange.location,
                (document as NSString).range(of: paragraph).location
            )
            XCTAssertNotNil(finding.secondRange)
            XCTAssertTrue(
                NSMaxRange(finding.firstRange)
                    <= (document as NSString).length
            )
        }
    }

    func testRepeatedArgumentCandidate() {
        let shared = """
        covenant chronology prophecy temple destruction historical witnesses Jerusalem \
        priesthood scripture restoration resurrection fulfillment judgment revelation \
        audience interpretation geography documentary scholarship manuscript authorship \
        evidence testimony language translation interpretation community
        """

        let first = shared + """
        ancient regional governance political taxation hereditary administration \
        archival chronology structural analysis metropolitan jurisdiction imperial customs
        """

        let second = shared + """
        literary covenantal audience theology narrative worship ritual symbolism \
        transmitted commentary religious formation traditional interpretation
        """

        let document = first + "\n\n" + second

        XCTAssertTrue(
            BOLDConsistencyScanner().scan(document)
                .contains { $0.category == .repeatedArguments }
        )
    }

    func testPreferredTermGlossary() {
        let document = """
        The first-century audience understood this expression.
        The first century audience discussed this expression.
        """

        let findings = BOLDConsistencyScanner().scan(
            document,
            preferredTerms: [
                "first-century": ["first century"]
            ]
        )

        XCTAssertTrue(
            findings.contains { $0.category == .terminology }
        )
    }

    func testAuthorRuleLiteralMatchingCaseAndWordBoundary() {
        let document = "YHWH yHWH YHWHs"
        let rule = BOLDConsistencyRule(
            kind: .preferredTerm,
            matchText: "YHWH",
            replacement: "YHVH",
            caseSensitive: true,
            wholeWord: true
        )
        let findings = BOLDConsistencyScanner().scan(document, rules: [rule])
        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings.first?.matchedText, "YHWH")
        XCTAssertEqual(findings.first?.suggestedReplacement, "YHVH")
        XCTAssertEqual(findings.first?.ruleID, rule.id)
    }

    func testInsensitiveRulesRespectWholeWordAndDisabledState() {
        let wholeWord = BOLDConsistencyRule(
            kind: .disallowedTerm,
            matchText: "term",
            wholeWord: true
        )
        let substring = BOLDConsistencyRule(
            kind: .disallowedTerm,
            matchText: "term",
            wholeWord: false
        )
        let disabled = BOLDConsistencyRule(
            kind: .disallowedTerm,
            matchText: "TERM",
            enabled: false
        )
        let scanner = BOLDConsistencyScanner()
        XCTAssertEqual(scanner.scan("Term terminology", rules: [wholeWord]).count, 1)
        XCTAssertEqual(scanner.scan("Term terminology", rules: [substring]).count, 2)
        XCTAssertTrue(scanner.scan("TERM", rules: [disabled]).isEmpty)
    }

    func testOriginalProseRuleSkipsRecognizedQuotationText() {
        let rule = BOLDConsistencyRule(
            kind: .preferredTerm,
            matchText: "Yehoshua",
            replacement: "Yeshua",
            scope: .outsideQuotationMarks
        )
        let findings = BOLDConsistencyScanner().scan(
            "Yehoshua wrote. \"Yehoshua said this.\" “Yehoshua spoke.”",
            rules: [rule]
        )
        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings.first?.matchedText, "Yehoshua")
        XCTAssertEqual(findings.first?.isInsideQuotationText, false)
    }

    func testWholeManuscriptRuleFlagsQuotesWithSourceContextMarker() {
        let rule = BOLDConsistencyRule(
            kind: .preferredTerm,
            matchText: "Yehoshua",
            replacement: "Yeshua"
        )
        let findings = BOLDConsistencyScanner().scan("\"Yehoshua said this.\"", rules: [rule])
        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings.first?.isInsideQuotationText, true)
    }

    func testRuleConfigurationSurvivesNativeDocumentSaveAndReopen() throws {
        var metadata = DocumentMetadata()
        let rule = BOLDConsistencyRule(
            kind: .preferredTerm,
            matchText: "Yehoshua",
            replacement: "Yeshua",
            explanation: "Project spelling",
            caseSensitive: true,
            wholeWord: false,
            scope: .outsideQuotationMarks
        )
        metadata.manuscriptConsistencyRules = [rule]
        metadata.manuscriptLiveAuditEnabled = true
        metadata.ignoredManuscriptFindings = ["authorRuleViolation:9:-1"]
        let package = try BOLDWriterDocument.packageWrapper(
            text: NSAttributedString(string: "A synthetic manuscript."),
            metadata: metadata
        )
        let reopened = try BOLDWriterDocument(
            fileWrapper: package,
            contentType: .boldWriterDocument
        )
        XCTAssertEqual(reopened.metadata.manuscriptConsistencyRules, [rule])
        XCTAssertEqual(reopened.metadata.manuscriptLiveAuditEnabled, true)
        XCTAssertEqual(reopened.metadata.ignoredManuscriptFindings, ["authorRuleViolation:9:-1"])
    }

    func testIssueCapAndEmptyText() {
        XCTAssertTrue(
            BOLDConsistencyScanner().scan("").isEmpty
        )

        XCTAssertTrue(
            BOLDConsistencyScanner().scan(
                "A brief paragraph",
                maximumFindings: 0
            ).isEmpty
        )
    }

    func testFourHundredPageSyntheticBookOffsetsStayWithinDocument() {
        let paragraph = """
        The historical chronology records independent witnesses \
        concerning covenantal developments in the ancient world.
        """

        let text = String(
            repeating: paragraph + "\n\n",
            count: 8000
        )

        let findings = BOLDConsistencyScanner().scan(
            text,
            maximumFindings: 50
        )

        XCTAssertLessThanOrEqual(findings.count, 50)

        let length = (text as NSString).length

        for finding in findings {
            XCTAssertLessThanOrEqual(
                NSMaxRange(finding.firstRange),
                length
            )

            if let second = finding.secondRange {
                XCTAssertLessThanOrEqual(
                    NSMaxRange(second),
                    length
                )
            }
        }
    }

    func testCancellableScanStopsAfterCancellation() {
        let text = String(repeating: "A very long paragraph with YHWH repeated throughout the source.\n\n", count: 20_000)
        var checks = 0
        let result = BOLDConsistencyScanner().scanCancellable(text, shouldCancel: {
            checks += 1
            return checks > 3
        })
        XCTAssertNil(result, "A cancelled scan must not publish partial findings")
        XCTAssertGreaterThan(checks, 3)
    }

    func testSemanticQuoteRangesCanSpanParagraphsAndNest() {
        let text = "Prose “quoted first paragraph\n\nsecond ‘nested’ paragraph” and more prose."
        let quotation = BOLDQuotationAnalyzer.analyze(text: NSAttributedString(string: text))
        let rule = BOLDConsistencyRule(
            kind: .preferredTerm,
            matchText: "Yehoshua",
            replacement: "Yeshua",
            scope: .outsideQuotationMarks
        )
        let source = "Yehoshua prose “Yehoshua quoted\n\n‘Yehoshua nested’” Yehoshua prose"
        let context = BOLDQuotationAnalyzer.analyze(text: NSAttributedString(string: source))
        let findings = BOLDConsistencyScanner().scan(
            source,
            rules: [rule],
            quotationRanges: context.protectedRanges
        )
        XCTAssertEqual(findings.count, 2)
        XCTAssertFalse(findings.contains(where: \.isInsideQuotationText))
        XCTAssertTrue(quotation.protectedRanges.contains { NSLocationInRange((text as NSString).range(of: "first").location, $0) })
    }

    func testAmbiguousUnclosedQuotationIsProtectedAndReported() {
        let source = "Original prose. “quoted across paragraphs\n\nYehoshua appears in an unfinished source quotation"
        let result = BOLDQuotationAnalyzer.analyze(text: NSAttributedString(string: source))
        XCTAssertFalse(result.uncertainRanges.isEmpty)
        let rule = BOLDConsistencyRule(kind: .preferredTerm, matchText: "Yehoshua", replacement: "Yeshua", scope: .outsideQuotationMarks)
        let findings = BOLDConsistencyScanner().scan(source, rules: [rule], quotationRanges: result.protectedRanges)
        XCTAssertTrue(findings.isEmpty, "Uncertain quoted content must not be treated as ordinary prose")
    }

    func testStraightAndCurlySingleQuotesProtectProseWithoutTreatingApostrophesAsQuotes() {
        let text = "The author's notes say 'Yehoshua arrived.' Then “Yeshua’s account” is discussed."
        let analysis = BOLDQuotationAnalyzer.analyze(string: text)!
        let source = text as NSString
        let quoted = source.range(of: "Yehoshua")
        XCTAssertTrue(analysis.protectedRanges.contains { $0.intersects(quoted) })
        XCTAssertTrue(analysis.uncertainRanges.isEmpty)
        let prose = source.range(of: "author's")
        XCTAssertFalse(analysis.protectedRanges.contains { $0.intersects(prose) })
    }
}
