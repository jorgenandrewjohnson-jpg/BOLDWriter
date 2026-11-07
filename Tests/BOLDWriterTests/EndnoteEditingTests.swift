import AppKit
import XCTest
@testable import BOLDWriter

@MainActor
final class EndnoteEditingTests: XCTestCase {
    private func editor() -> (
        EditorController,
        WritingTextView,
        UndoManager
    ) {
        let view =
            WritingTextView(
                frame:
                    NSRect(
                        x: 0,
                        y: 0,
                        width: 600,
                        height: 800
                    )
            )

        let manager =
            UndoManager()

        // Match the established Footnote test harness.
        // Each controller mutation must be its own deterministic
        // undo action rather than one implicit event group.
        manager.groupsByEvent =
            false

        view.sessionUndoManager =
            manager

        view.allowsUndo =
            true

        view.textStorage?
            .setAttributedString(
                NSAttributedString(
                    string:
                        "Body"
                )
            )

        view.setSelectedRange(
            NSRange(
                location: 4,
                length: 0
            )
        )

        let controller =
            EditorController()

        controller.attach(
            view
        )

        return (
            controller,
            view,
            manager
        )
    }

    func testInsertEndnoteSupportsUndoAndRedo()
        throws {

        let (
            controller,
            view,
            manager
        ) =
            editor()

        controller.insertEndnote(
            text:
                "First endnote"
        )

        let first =
            try XCTUnwrap(
                Endnotes.records(
                    in:
                        view.attributedString()
                )
                .first
            )

        XCTAssertEqual(
            first.text,
            "First endnote"
        )

        XCTAssertEqual(
            view.string,
            "Body1"
        )

        manager.undo()

        XCTAssertEqual(
            view.string,
            "Body"
        )

        XCTAssertTrue(
            try Endnotes.records(
                in:
                    view.attributedString()
            )
            .isEmpty
        )

        manager.redo()

        XCTAssertEqual(
            try Endnotes.records(
                in:
                    view.attributedString()
            )
            .first?
            .id,
            first.id
        )
    }

    func testEndnoteEditDeleteAndUndo()
        throws {

        let (
            controller,
            view,
            manager
        ) =
            editor()

        controller.insertEndnote(
            text:
                "Original"
        )

        let original =
            try XCTUnwrap(
                Endnotes.records(
                    in:
                        view.attributedString()
                )
                .first
            )

        controller.updateEndnote(
            id:
                original.id,
            text:
                "Edited"
        )

        XCTAssertEqual(
            try Endnotes.records(
                in:
                    view.attributedString()
            )
            .first?
            .text,
            "Edited"
        )

        manager.undo()

        XCTAssertEqual(
            try Endnotes.records(
                in:
                    view.attributedString()
            )
            .first?
            .text,
            "Original"
        )

        manager.redo()

        let edited =
            try XCTUnwrap(
                Endnotes.records(
                    in:
                        view.attributedString()
                )
                .first
            )

        controller.deleteEndnote(
            id:
                edited.id
        )

        XCTAssertTrue(
            try Endnotes.records(
                in:
                    view.attributedString()
            )
            .isEmpty
        )

        manager.undo()

        XCTAssertEqual(
            try Endnotes.records(
                in:
                    view.attributedString()
            )
            .first?
            .id,
            edited.id
        )
    }

    func testMultiDigitEndnoteReferenceIsAtomic()
        throws {

        let (
            controller,
            view,
            manager
        ) =
            editor()

        for index in 1...10 {
            view.setSelectedRange(
                NSRange(
                    location:
                        view.string
                            .utf16
                            .count,
                    length: 0
                )
            )

            controller.insertEndnote(
                text:
                    "Endnote \(index)"
            )
        }

        let notes =
            try Endnotes.records(
                in:
                    view.attributedString()
            )

        XCTAssertEqual(
            notes.count,
            10
        )

        let tenth =
            notes[9]

        XCTAssertEqual(
            tenth.length,
            2
        )

        let partial =
            NSRange(
                location:
                    tenth.location + 1,
                length:
                    1
            )

        let protected =
            NoteReferences.editingRange(
                partial,
                in:
                    view.attributedString()
            )

        XCTAssertEqual(
            protected,
            NSRange(
                location:
                    tenth.location,
                length:
                    tenth.length
            )
        )

        controller.replace(
            range:
                partial,
            with:
                NSAttributedString(
                    string: ""
                ),
            actionName:
                "Delete Text"
        )

        XCTAssertEqual(
            try Endnotes.records(
                in:
                    view.attributedString()
            )
            .count,
            9
        )

        manager.undo()

        XCTAssertEqual(
            try Endnotes.records(
                in:
                    view.attributedString()
            )
            .count,
            10
        )
    }

    func testTrackedEndnoteInsertionPreservesMarker()
        throws {

        let (
            controller,
            view,
            _
        ) =
            editor()

        controller.insertEndnote(
            text:
                "Tracked endnote",
            trackChanges:
                true
        )

        let note =
            try XCTUnwrap(
                Endnotes.records(
                    in:
                        view.attributedString()
                )
                .first
            )

        XCTAssertEqual(
            note.text,
            "Tracked endnote"
        )

        let revisions =
            TrackChanges.records(
                in:
                    view.attributedString()
            )

        XCTAssertEqual(
            revisions.count,
            1
        )

        XCTAssertEqual(
            revisions.first?
                .kind,
            .insertion
        )

        XCTAssertEqual(
            revisions.first?
                .location,
            note.location
        )

        XCTAssertEqual(
            revisions.first?
                .length,
            note.length
        )

        let exported =
            try DOCXExporter.data(
                from:
                    view.attributedString(),
                title:
                    "Tracked Endnote"
            )

        let imported =
            try DOCXImporter.text(
                from:
                    exported
            )

        XCTAssertEqual(
            try Endnotes.records(
                in:
                    imported
            )
            .first?
            .text,
            "Tracked endnote"
        )
    }

    func testTrackedEndnoteBodyEditStoresPendingMetadata()
        throws {

        let (
            controller,
            view,
            _
        ) =
            editor()

        controller.insertEndnote(
            text:
                "Original body"
        )

        let original =
            try XCTUnwrap(
                Endnotes.records(
                    in:
                        view.attributedString()
                )
                .first
            )

        controller.updateEndnote(
            id:
                original.id,
            text:
                "Proposed body",
            trackChanges:
                true
        )

        let pending =
            try XCTUnwrap(
                Endnotes.records(
                    in:
                        view.attributedString()
                )
                .first
            )

        XCTAssertEqual(
            pending.text,
            "Proposed body"
        )

        XCTAssertEqual(
            pending.bodyChangeOriginalText,
            "Original body"
        )

        XCTAssertNotNil(
            pending.bodyChangeID
        )

        XCTAssertTrue(
            pending.hasPendingBodyChange
        )
    }

    func testReviewItemsIncludeTrackedEndnoteBodyEdit()
        throws {

        let (
            controller,
            view,
            _
        ) =
            editor()

        controller.insertEndnote(
            text:
                "Original body"
        )

        let note =
            try XCTUnwrap(
                Endnotes.records(
                    in:
                        view.attributedString()
                )
                .first
            )

        controller.updateEndnote(
            id:
                note.id,
            text:
                "Edited body",
            trackChanges:
                true
        )

        let item =
            try XCTUnwrap(
                TrackChanges.reviewItems(
                    in:
                        view.attributedString()
                )
                .first {
                    $0.kind
                        == .endnoteBodyEdit
                }
            )

        XCTAssertEqual(
            item.title,
            "Edited endnote"
        )

        XCTAssertTrue(
            item.preview
                .contains(
                    "Original body"
                )
        )

        XCTAssertTrue(
            item.preview
                .contains(
                    "Edited body"
                )
        )
    }

    func testRejectTrackedEndnoteBodyEditRestoresOriginal()
        throws {

        let (
            controller,
            view,
            _
        ) =
            editor()

        controller.insertEndnote(
            text:
                "Original body"
        )

        let note =
            try XCTUnwrap(
                Endnotes.records(
                    in:
                        view.attributedString()
                )
                .first
            )

        controller.updateEndnote(
            id:
                note.id,
            text:
                "Rejected body",
            trackChanges:
                true
        )

        let item =
            try XCTUnwrap(
                TrackChanges.reviewItems(
                    in:
                        view.attributedString()
                )
                .first {
                    $0.kind
                        == .endnoteBodyEdit
                }
            )

        controller.selectTrackedChange(
            item
        )

        controller.rejectTrackedChangeAtSelection()

        let resolved =
            try XCTUnwrap(
                Endnotes.records(
                    in:
                        view.attributedString()
                )
                .first
            )

        XCTAssertEqual(
            resolved.text,
            "Original body"
        )

        XCTAssertFalse(
            resolved.hasPendingBodyChange
        )

        XCTAssertNil(
            resolved.bodyChangeID
        )

        XCTAssertFalse(
            TrackChanges.reviewItems(
                in:
                    view.attributedString()
            )
            .contains {
                $0.kind
                    == .endnoteBodyEdit
            }
        )
    }

    func testAcceptTrackedEndnoteBodyEditKeepsProposed()
        throws {

        let (
            controller,
            view,
            _
        ) =
            editor()

        controller.insertEndnote(
            text:
                "Original body"
        )

        let note =
            try XCTUnwrap(
                Endnotes.records(
                    in:
                        view.attributedString()
                )
                .first
            )

        controller.updateEndnote(
            id:
                note.id,
            text:
                "Accepted body",
            trackChanges:
                true
        )

        let item =
            try XCTUnwrap(
                TrackChanges.reviewItems(
                    in:
                        view.attributedString()
                )
                .first {
                    $0.kind
                        == .endnoteBodyEdit
                }
            )

        controller.selectTrackedChange(
            item
        )

        controller.acceptTrackedChangeAtSelection()

        let resolved =
            try XCTUnwrap(
                Endnotes.records(
                    in:
                        view.attributedString()
                )
                .first
            )

        XCTAssertEqual(
            resolved.text,
            "Accepted body"
        )

        XCTAssertFalse(
            resolved.hasPendingBodyChange
        )

        XCTAssertNil(
            resolved.bodyChangeOriginalText
        )

        XCTAssertNil(
            resolved.bodyChangeID
        )
    }

    func testAcceptAndRejectAllResolveTrackedEndnotes()
        throws {

        do {
            let (
                controller,
                view,
                _
            ) =
                editor()

            controller.insertEndnote(
                text:
                    "Original"
            )

            let note =
                try XCTUnwrap(
                    Endnotes.records(
                        in:
                            view.attributedString()
                    )
                    .first
                )

            controller.updateEndnote(
                id:
                    note.id,
                text:
                    "Proposed",
                trackChanges:
                    true
            )

            controller.rejectAllTrackedChanges()

            let rejected =
                try XCTUnwrap(
                    Endnotes.records(
                        in:
                            view.attributedString()
                    )
                    .first
                )

            XCTAssertEqual(
                rejected.text,
                "Original"
            )

            XCTAssertFalse(
                rejected.hasPendingBodyChange
            )
        }

        do {
            let (
                controller,
                view,
                _
            ) =
                editor()

            controller.insertEndnote(
                text:
                    "Original"
            )

            let note =
                try XCTUnwrap(
                    Endnotes.records(
                        in:
                            view.attributedString()
                    )
                    .first
                )

            controller.updateEndnote(
                id:
                    note.id,
                text:
                    "Proposed",
                trackChanges:
                    true
            )

            controller.acceptAllTrackedChanges()

            let accepted =
                try XCTUnwrap(
                    Endnotes.records(
                        in:
                            view.attributedString()
                    )
                    .first
                )

            XCTAssertEqual(
                accepted.text,
                "Proposed"
            )

            XCTAssertFalse(
                accepted.hasPendingBodyChange
            )
        }
    }

    func testTrackedEndnoteDeletionAcceptAndRejectAll()
        throws {

        do {
            let (
                controller,
                view,
                _
            ) =
                editor()

            controller.insertEndnote(
                text:
                    "Keep me"
            )

            let note =
                try XCTUnwrap(
                    Endnotes.records(
                        in:
                            view.attributedString()
                    )
                    .first
                )

            controller.deleteEndnote(
                id:
                    note.id,
                trackChanges:
                    true
            )

            XCTAssertEqual(
                try Endnotes.records(
                    in:
                        view.attributedString()
                )
                .count,
                1
            )

            XCTAssertTrue(
                TrackChanges.records(
                    in:
                        view.attributedString()
                )
                .contains {
                    $0.kind
                        == .deletion
                }
            )

            controller.rejectAllTrackedChanges()

            XCTAssertEqual(
                try Endnotes.records(
                    in:
                        view.attributedString()
                )
                .first?
                .text,
                "Keep me"
            )

            XCTAssertTrue(
                TrackChanges.records(
                    in:
                        view.attributedString()
                )
                .isEmpty
            )
        }

        do {
            let (
                controller,
                view,
                _
            ) =
                editor()

            controller.insertEndnote(
                text:
                    "Delete me"
            )

            let note =
                try XCTUnwrap(
                    Endnotes.records(
                        in:
                            view.attributedString()
                    )
                    .first
                )

            controller.deleteEndnote(
                id:
                    note.id,
                trackChanges:
                    true
            )

            controller.acceptAllTrackedChanges()

            XCTAssertTrue(
                try Endnotes.records(
                    in:
                        view.attributedString()
                )
                .isEmpty
            )
        }
    }
}
