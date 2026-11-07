import Foundation
import XCTest

@testable import BOLDWriter

final class DictionaryLookupTests:
    XCTestCase {

    func testSelectedTextBecomesDictionaryTerm() {
        let string =
            "The remarkable result."

        let range =
            (string as NSString)
                .range(
                    of:
                        "remarkable"
                )

        XCTAssertEqual(
            DictionaryLookup.term(
                in:
                    string,
                selectedRange:
                    range
            ),
            "remarkable"
        )
    }

    func testCaretInsideWordFindsWholeWord() {
        let string =
            "A covenant promise remains."

        let range =
            (string as NSString)
                .range(
                    of:
                        "covenant"
                )

        XCTAssertEqual(
            DictionaryLookup.term(
                in:
                    string,
                selectedRange:
                    NSRange(
                        location:
                            range.location + 3,
                        length:
                            0
                    )
            ),
            "covenant"
        )
    }

    func testCaretImmediatelyAfterWordFindsPreviousWord() {
        let string =
            "covenant promise"

        let range =
            (string as NSString)
                .range(
                    of:
                        "covenant"
                )

        XCTAssertEqual(
            DictionaryLookup.term(
                in:
                    string,
                selectedRange:
                    NSRange(
                        location:
                            NSMaxRange(range),
                        length:
                            0
                    )
            ),
            "covenant"
        )
    }

    func testApostropheAndHyphenRemainPartOfWord() {
        let string =
            "A well-known writer's term."

        let hyphenated =
            (string as NSString)
                .range(
                    of:
                        "well-known"
                )

        XCTAssertEqual(
            DictionaryLookup.term(
                in:
                    string,
                selectedRange:
                    NSRange(
                        location:
                            hyphenated.location + 5,
                        length:
                            0
                    )
            ),
            "well-known"
        )

        let possessive =
            (string as NSString)
                .range(
                    of:
                        "writer's"
                )

        XCTAssertEqual(
            DictionaryLookup.term(
                in:
                    string,
                selectedRange:
                    NSRange(
                        location:
                            possessive.location + 3,
                        length:
                            0
                    )
            ),
            "writer's"
        )
    }

    func testWhitespaceCaretReturnsNoTerm() {
        let string =
            "alpha   beta"

        XCTAssertNil(
            DictionaryLookup.term(
                in:
                    string,
                selectedRange:
                    NSRange(
                        location:
                            6,
                        length:
                            0
                    )
            )
        )
    }

    func testEmptySelectionInEmptyDocumentReturnsNil() {
        XCTAssertNil(
            DictionaryLookup.term(
                in:
                    "",
                selectedRange:
                    NSRange(
                        location:
                            0,
                        length:
                            0
                    )
            )
        )
    }

    func testDictionaryURLPercentEncodesPhrase() {
        let url =
            DictionaryLookup.dictionaryURL(
                for:
                    "New Testament"
            )

        XCTAssertEqual(
            url?.scheme,
            "dict"
        )

        XCTAssertEqual(
            url?.absoluteString,
            "dict://New%20Testament"
        )
    }
}
