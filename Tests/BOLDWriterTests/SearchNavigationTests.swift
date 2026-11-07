import Foundation
import XCTest
@testable import BOLDWriter

final class SearchNavigationTests: XCTestCase {
    private let text =
        "alpha beta alpha gamma alpha"

    private var results: [SearchResult] {
        DocumentAnalysis.search(
            "alpha",
            in: text
        )
    }

    func testSearchReturnsAllMatchesInDocumentOrder() {
        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(
            results.map(\.range.location),
            [0, 11, 23]
        )
    }

    func testNextResultAdvancesAndWraps() throws {
        let first = try XCTUnwrap(results.first)

        let second = try XCTUnwrap(
            DocumentAnalysis.nextResult(
                in: results,
                selection: first.range
            )
        )

        XCTAssertEqual(second.range.location, 11)

        let last = try XCTUnwrap(results.last)

        let wrapped = try XCTUnwrap(
            DocumentAnalysis.nextResult(
                in: results,
                selection: last.range
            )
        )

        XCTAssertEqual(wrapped.range.location, 0)
    }

    func testPreviousResultMovesBackwardAndWraps() throws {
        let second = results[1]

        let first = try XCTUnwrap(
            DocumentAnalysis.previousResult(
                in: results,
                selection: second.range
            )
        )

        XCTAssertEqual(first.range.location, 0)

        let wrapped = try XCTUnwrap(
            DocumentAnalysis.previousResult(
                in: results,
                selection: results[0].range
            )
        )

        XCTAssertEqual(wrapped.range.location, 23)
    }

    func testCursorPositionChoosesNearestDirectionalResult() throws {
        let next = try XCTUnwrap(
            DocumentAnalysis.nextResult(
                in: results,
                selection: NSRange(
                    location: 5,
                    length: 0
                )
            )
        )

        XCTAssertEqual(next.range.location, 11)

        let previous = try XCTUnwrap(
            DocumentAnalysis.previousResult(
                in: results,
                selection: NSRange(
                    location: 20,
                    length: 0
                )
            )
        )

        XCTAssertEqual(previous.range.location, 11)
    }

    func testCurrentResultIndexRequiresExactSelectedMatch() {
        XCTAssertEqual(
            DocumentAnalysis.currentResultIndex(
                in: results,
                selection: results[1].range
            ),
            1
        )

        XCTAssertNil(
            DocumentAnalysis.currentResultIndex(
                in: results,
                selection: NSRange(
                    location: 11,
                    length: 0
                )
            )
        )
    }

    func testSearchOptionsStillWorkWithNavigation() {
        XCTAssertEqual(
            DocumentAnalysis.search(
                "ALPHA",
                in: text,
                matchCase: false
            ).count,
            3
        )

        XCTAssertEqual(
            DocumentAnalysis.search(
                "ALPHA",
                in: text,
                matchCase: true
            ).count,
            0
        )

        XCTAssertEqual(
            DocumentAnalysis.search(
                "alp",
                in: text,
                wholeWord: true
            ).count,
            0
        )

        XCTAssertEqual(
            DocumentAnalysis.search(
                "a[a-z]+a",
                in: text,
                regularExpression: true
            ).count,
            4
        )
    }
    func testSearchLimitsIncludeZeroAndNegativeWithoutCrashing() {
        XCTAssertEqual(DocumentAnalysis.search("alpha", in: text, limit: 1).map(\.range.location), [0])
        XCTAssertTrue(DocumentAnalysis.search("alpha", in: text, limit: 0).isEmpty)
        XCTAssertTrue(DocumentAnalysis.search("alpha", in: text, limit: -1).isEmpty)
        let repeated = String(repeating: "alpha ", count: 20_000)
        XCTAssertEqual(DocumentAnalysis.search("alpha", in: repeated).count, 1_000)
    }

    func testInvalidRegexThrowsWhileLiteralBracketsRemainSearchable() throws {
        XCTAssertThrowsError(try DocumentSearch("[", regularExpression: true))
        XCTAssertEqual(try DocumentSearch("[").results(in: "a[b").first?.range, NSRange(location: 1, length: 1))
    }

    func testRegexReplacementUsesCapturesAndUTF16Ranges() throws {
        let search = try DocumentSearch("(Chapter) ([0-9]+)", regularExpression: true)
        let text = "📖 Chapter 12 and Chapter 3"
        let edits = search.replacements(in: text, with: "$2: $1")
        XCTAssertEqual(edits.map(\.text), ["12: Chapter", "3: Chapter"])
        XCTAssertEqual(edits[0].range, NSRange(location: 3, length: 10))
        let output = NSMutableString(string: text)
        for edit in edits.reversed() { output.replaceCharacters(in: edit.range, with: edit.text) }
        XCTAssertEqual(output as String, "📖 12: Chapter and 3: Chapter")
    }

    func testLiteralReplacementDoesNotExpandDollarOrBackslash() throws {
        let search = try DocumentSearch("cat")
        let template = #"$1 \ $0"#
        XCTAssertEqual(search.replacements(in: "cat cat", with: template).map(\.text), [template, template])
    }

    func testSelectedRegexReplacementRetainsLookbehindContext() throws {
        let search = try DocumentSearch("(?<=Chapter )([0-9]+)", regularExpression: true)
        let text = "Chapter 12 and Chapter 3"
        XCTAssertEqual(search.replacement(in: text, range: NSRange(location: 8, length: 2), with: "[$1]")?.text, "[12]")
        XCTAssertNil(search.replacement(in: text, range: NSRange(location: 8, length: 1), with: "[$1]"))
    }

    func testWholeWordHandlesPunctuationAndUnicodeCombiningMarks() throws {
        XCTAssertEqual(try DocumentSearch("C++", wholeWord: true).results(in: "C++ C++Builder XC++").count, 1)
        XCTAssertEqual(try DocumentSearch("cafe", wholeWord: true).results(in: "cafe cafe\u{0301} cafeteria").count, 1)
        XCTAssertEqual(try DocumentSearch("猫", wholeWord: true).results(in: "猫 猫咪").count, 1)
    }

    func testSnippetsDoNotSplitSurrogatePairs() throws {
        let text = String(repeating: "a", count: 24) + "😀" + String(repeating: "b", count: 43) + "target"
        let result = try XCTUnwrap(DocumentSearch("target").results(in: text).first)
        XCTAssertTrue(result.context.contains("😀"))
        XCTAssertFalse(result.context.contains("\u{FFFD}"))
    }

    func testNavigationReachesResultsBeyondSidebarLimitAndWraps() throws {
        let search = try DocumentSearch("cat")
        let text = String(repeating: "cat ", count: 1_200)
        XCTAssertEqual(search.results(in: text).count, 1_000)
        XCTAssertEqual(search.navigationResult(in: text, selection: NSRange(location: 3_996, length: 3))?.range.location, 4_000)
        XCTAssertEqual(search.navigationResult(in: text, selection: NSRange(location: 4_796, length: 3))?.range.location, 0)
        XCTAssertEqual(search.navigationResult(in: text, selection: NSRange(location: 0, length: 3), previous: true)?.range.location, 4_796)
        XCTAssertEqual(search.navigationResult(in: text, selection: NSRange(location: 4_000, length: 3), previous: true)?.range.location, 3_996)
    }

    func testZeroWidthRegexNavigationAndReplacements() throws {
        let search = try DocumentSearch("(?=cat)", regularExpression: true)
        XCTAssertEqual(search.results(in: "cat cat").map(\.range), [NSRange(location: 0, length: 0), NSRange(location: 4, length: 0)])
        XCTAssertEqual(search.navigationResult(in: "cat cat", selection: NSRange(location: 0, length: 0))?.range.location, 4)
        XCTAssertEqual(search.replacements(in: "cat cat", with: "•").map(\.text), ["•", "•"])
    }

}
