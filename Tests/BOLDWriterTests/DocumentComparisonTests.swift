import AppKit
import XCTest

@testable import BOLDWriter

@MainActor
final class DocumentComparisonTests:
    XCTestCase {

    private func makeEditor(
        _ string: String
    ) -> (
        BOLDWriterDocument,
        WritingTextView,
        EditorController
    ) {
        let document =
            BOLDWriterDocument()

        document.replaceText(
            with:
                NSAttributedString(
                    string:
                        string
                )
        )

        let view =
            WritingTextView(
                frame:
                    NSRect(
                        x: 0,
                        y: 0,
                        width: 600,
                        height: 500
                    )
            )

        view.textStorage?
            .setAttributedString(
                document.text
            )

        let undo =
            UndoManager()

        undo.groupsByEvent =
            false

        view.sessionUndoManager =
            undo

        view.allowsUndo =
            true

        let controller =
            EditorController()

        controller.attach(
            view
        )

        return (
            document,
            view,
            controller
        )
    }

    func testCompareDocumentsAcceptAllProducesRevisedText() throws {
        let (
            document,
            view,
            controller
        ) =
            makeEditor(
                "Alpha old middle Omega"
            )

        let revised =
            NSAttributedString(
                string:
                    "Alpha revised middle Omega and tail"
            )

        let changeCount =
            try controller.compareDocument(
                with:
                    revised,
                in:
                    document,
                author:
                    "Compared Document"
            )

        XCTAssertGreaterThan(
            changeCount,
            0
        )

        XCTAssertFalse(
            TrackChanges.records(
                in:
                    view.attributedString()
            ).isEmpty
        )

        XCTAssertTrue(
            document.metadata
                .trackChangesEnabled
                ?? false
        )

        XCTAssertTrue(
            TrackChanges.records(
                in:
                    view.attributedString()
            ).allSatisfy {
                $0.author
                    == "Compared Document"
            }
        )

        controller
            .acceptAllTrackedChanges()

        XCTAssertEqual(
            view.string,
            revised.string
        )
    }

    func testCompareDocumentsRejectAllRestoresOriginalText() throws {
        let original =
            "One two three four"

        let (
            document,
            view,
            controller
        ) =
            makeEditor(
                original
            )

        _ =
            try controller.compareDocument(
                with:
                    NSAttributedString(
                        string:
                            "One second three final"
                    ),
                in:
                    document
            )

        controller
            .rejectAllTrackedChanges()

        XCTAssertEqual(
            view.string,
            original
        )

        XCTAssertTrue(
            TrackChanges.records(
                in:
                    view.attributedString()
            ).isEmpty
        )
    }

    func testCompareDocumentsNoDifferenceCreatesNoTrackedChanges() throws {
        let (
            document,
            view,
            controller
        ) =
            makeEditor(
                "Identical text"
            )

        let count =
            try controller.compareDocument(
                with:
                    NSAttributedString(
                        string:
                            "Identical text"
                    ),
                in:
                    document
            )

        XCTAssertEqual(
            count,
            0
        )

        XCTAssertTrue(
            TrackChanges.records(
                in:
                    view.attributedString()
            ).isEmpty
        )
    }

    func testComparisonPreservesInsertedFormatting() throws {
        let (
            document,
            view,
            controller
        ) =
            makeEditor(
                "Before after"
            )

        let revised =
            NSMutableAttributedString(
                string:
                    "Before bold after"
            )

        let insertedRange =
            (
                revised.string
                    as NSString
            )
            .range(
                of:
                    "bold"
            )

        revised.addAttribute(
            .font,
            value:
                NSFont.boldSystemFont(
                    ofSize:
                        19
                ),
            range:
                insertedRange
        )

        _ =
            try controller.compareDocument(
                with:
                    revised,
                in:
                    document
            )

        controller
            .acceptAllTrackedChanges()

        let finalRange =
            (
                view.string
                    as NSString
            )
            .range(
                of:
                    "bold"
            )

        let font =
            try XCTUnwrap(
                view.attributedString()
                    .attribute(
                        .font,
                        at:
                            finalRange.location,
                        effectiveRange:
                            nil
                    )
                    as? NSFont
            )

        XCTAssertTrue(
            font.fontDescriptor
                .symbolicTraits
                .contains(
                    .bold
                )
        )

        XCTAssertEqual(
            font.pointSize,
            19,
            accuracy:
                0.01
        )
    }
}
