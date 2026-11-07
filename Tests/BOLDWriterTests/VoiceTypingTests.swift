import AppKit
import XCTest

@testable import BOLDWriter

final class VoiceTypingTests: XCTestCase {
    func testTranscriptTrimsRecognitionWhitespace() {
        XCTAssertEqual(
            VoiceTypingText.cleanedTranscript(
                "  This is dictated text. \n"
            ),
            "This is dictated text."
        )
    }

    func testInsertionAddsTrailingSpaceBetweenWords() {
        XCTAssertEqual(
            VoiceTypingText.insertionText(
                transcript:
                    "dictated",
                documentText:
                    "Before after",
                replacementRange:
                    NSRange(
                        location:
                            7,
                        length:
                            0
                    )
            ),
            "dictated "
        )
    }

    func testInsertionAddsLeadingSpaceAfterWord() {
        XCTAssertEqual(
            VoiceTypingText.insertionText(
                transcript:
                    "new",
                documentText:
                    "Before",
                replacementRange:
                    NSRange(
                        location:
                            6,
                        length:
                            0
                    )
            ),
            " new"
        )
    }

    func testInsertionAvoidsTrailingSpaceBeforePunctuation() {
        XCTAssertEqual(
            VoiceTypingText.insertionText(
                transcript:
                    "word",
                documentText:
                    "Hello.",
                replacementRange:
                    NSRange(
                        location:
                            5,
                        length:
                            0
                    )
            ),
            " word"
        )
    }

    func testAttributedReplacementPreservesTypingAttributes() throws {
        let font =
            NSFont.boldSystemFont(
                ofSize:
                    19
            )

        let replacement =
            VoiceTypingText.attributedReplacement(
                transcript:
                    "dictated words",
                documentText:
                    "",
                replacementRange:
                    NSRange(
                        location:
                            0,
                        length:
                            0
                    ),
                typingAttributes: [
                    .font:
                        font
                ]
            )

        XCTAssertEqual(
            replacement.string,
            "dictated words"
        )

        let actual =
            try XCTUnwrap(
                replacement.attribute(
                    .font,
                    at:
                        0,
                    effectiveRange:
                        nil
                )
                as? NSFont
            )

        XCTAssertEqual(
            actual.pointSize,
            19,
            accuracy:
                0.01
        )
    }

    @MainActor
    func testVoiceTypingInsertionCanBecomeTrackedChange() {
        let document =
            BOLDWriterDocument()

        document.replaceText(
            with:
                NSAttributedString(
                    string:
                        "Before after"
                )
        )

        let view =
            WritingTextView(
                frame:
                    NSRect(
                        x:
                            0,
                        y:
                            0,
                        width:
                            500,
                        height:
                            300
                    )
            )

        view.textStorage?
            .setAttributedString(
                document.text
            )

        let controller =
            EditorController()

        controller.attach(
            view
        )

        let insertion =
            NSRange(
                location:
                    7,
                length:
                    0
            )

        let replacement =
            VoiceTypingText.attributedReplacement(
                transcript:
                    "dictated",
                documentText:
                    view.string,
                replacementRange:
                    insertion,
                typingAttributes:
                    view.typingAttributes
            )

        controller.replace(
            range:
                insertion,
            with:
                replacement,
            actionName:
                "Voice Typing",
            trackChanges:
                true
        )

        XCTAssertEqual(
            view.string,
            "Before dictated after"
        )

        XCTAssertFalse(
            TrackChanges.records(
                in:
                    view.attributedString()
            ).isEmpty
        )
    }
}
