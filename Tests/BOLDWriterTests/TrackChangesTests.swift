import AppKit
import XCTest
@testable import BOLDWriter

@MainActor
private final class TrackChangesUndoTextView:
    NSTextView {

    let manager =
        UndoManager()

    override var undoManager:
        UndoManager? {
        manager
    }
}

@MainActor
final class TrackChangesTests: XCTestCase {
    private func makeUndoableEditor(
        _ string: String
    ) -> (
        TrackChangesUndoTextView,
        EditorController
    ) {
        let view =
            TrackChangesUndoTextView(
                frame:
                    NSRect(
                        x: 0,
                        y: 0,
                        width: 500,
                        height: 500
                    )
            )

        view.allowsUndo =
            true

        view.manager.groupsByEvent =
            false

        view.textStorage?
            .setAttributedString(
                NSAttributedString(
                    string:
                        string,
                    attributes: [
                        .font:
                            NSFont.systemFont(
                                ofSize: 15
                            ),
                        .foregroundColor:
                            NSColor.textColor
                    ]
                )
            )

        let controller =
            EditorController()

        controller.attach(
            view
        )

        return (
            view,
            controller
        )
    }

    private func makeEditor(
        _ string: String
    ) -> (NSTextView, EditorController) {
        let view = NSTextView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: 500,
                height: 500
            )
        )

        view.allowsUndo = true

        view.textStorage?.setAttributedString(
            NSAttributedString(
                string: string,
                attributes: [
                    .font: NSFont.systemFont(
                        ofSize: 15
                    ),
                    .foregroundColor:
                        NSColor.textColor
                ]
            )
        )

        let controller = EditorController()
        controller.attach(view)

        return (view, controller)
    }

    func testInsertionIsTrackedWithoutDeletingExistingText() {
        let (view, controller) =
            makeEditor("Hello world")

        XCTAssertTrue(
            controller.trackTextEdit(
                range: NSRange(
                    location: 5,
                    length: 0
                ),
                replacement:
                    NSAttributedString(
                        string: " brave"
                    ),
                author: "Editor"
            )
        )

        XCTAssertEqual(
            view.string,
            "Hello brave world"
        )

        let records =
            TrackChanges.records(
                in: view.attributedString()
            )

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(
            records.first?.kind,
            .insertion
        )
        XCTAssertEqual(
            records.first?.author,
            "Editor"
        )
    }

    func testDeletionRemainsVisibleUntilAccepted() {
        let (view, controller) =
            makeEditor("Hello world")

        controller.trackTextEdit(
            range: NSRange(
                location: 6,
                length: 5
            ),
            replacement:
                NSAttributedString(string: "")
        )

        XCTAssertEqual(
            view.string,
            "Hello world"
        )

        XCTAssertEqual(
            TrackChanges.records(
                in: view.attributedString()
            ).first?.kind,
            .deletion
        )

        view.setSelectedRange(
            NSRange(
                location: 7,
                length: 0
            )
        )

        controller.acceptTrackedChangeAtSelection()

        XCTAssertEqual(
            view.string,
            "Hello "
        )

        XCTAssertTrue(
            TrackChanges.records(
                in: view.attributedString()
            ).isEmpty
        )
    }

    func testRejectInsertionRemovesInsertedText() {
        let (view, controller) =
            makeEditor("One three")

        controller.trackTextEdit(
            range: NSRange(
                location: 4,
                length: 0
            ),
            replacement:
                NSAttributedString(
                    string: "two "
                )
        )

        view.setSelectedRange(
            NSRange(
                location: 6,
                length: 0
            )
        )

        controller.rejectTrackedChangeAtSelection()

        XCTAssertEqual(
            view.string,
            "One three"
        )
    }

    func testReplacementCreatesDeletionAndInsertion() {
        let (view, controller) =
            makeEditor("red fox")

        controller.trackTextEdit(
            range: NSRange(
                location: 0,
                length: 3
            ),
            replacement:
                NSAttributedString(
                    string: "blue"
                )
        )

        XCTAssertEqual(
            view.string,
            "redblue fox"
        )

        let kinds =
            TrackChanges.records(
                in: view.attributedString()
            )
            .map(\.kind)

        XCTAssertEqual(
            kinds,
            [.deletion, .insertion]
        )
    }

    func testAcceptAllProducesFinalText() {
        let (view, controller) =
            makeEditor("old text")

        controller.trackTextEdit(
            range: NSRange(
                location: 0,
                length: 3
            ),
            replacement:
                NSAttributedString(
                    string: "new"
                )
        )

        controller.acceptAllTrackedChanges()

        XCTAssertEqual(
            view.string,
            "new text"
        )

        XCTAssertTrue(
            TrackChanges.records(
                in: view.attributedString()
            ).isEmpty
        )
    }

    func testRejectAllRestoresOriginalText() {
        let (view, controller) =
            makeEditor("old text")

        controller.trackTextEdit(
            range: NSRange(
                location: 0,
                length: 3
            ),
            replacement:
                NSAttributedString(
                    string: "new"
                )
        )

        controller.rejectAllTrackedChanges()

        XCTAssertEqual(
            view.string,
            "old text"
        )

        XCTAssertTrue(
            TrackChanges.records(
                in: view.attributedString()
            ).isEmpty
        )
    }

    func testContinuousTypingCoalescesIntoOneInsertion() {
        let (view, controller) =
            makeEditor("Hello")

        XCTAssertTrue(
            controller.trackTextEdit(
                range: NSRange(
                    location: 5,
                    length: 0
                ),
                replacement:
                    NSAttributedString(
                        string: " "
                    ),
                author: "Editor"
            )
        )

        XCTAssertTrue(
            controller.trackTextEdit(
                range: NSRange(
                    location: 6,
                    length: 0
                ),
                replacement:
                    NSAttributedString(
                        string: "w"
                    ),
                author: "Editor"
            )
        )

        XCTAssertTrue(
            controller.trackTextEdit(
                range: NSRange(
                    location: 7,
                    length: 0
                ),
                replacement:
                    NSAttributedString(
                        string: "o"
                    ),
                author: "Editor"
            )
        )

        XCTAssertEqual(
            view.string,
            "Hello wo"
        )

        let records =
            TrackChanges.records(
                in: view.attributedString()
            )

        XCTAssertEqual(
            records.count,
            1
        )

        XCTAssertEqual(
            records.first?.kind,
            .insertion
        )

        XCTAssertEqual(
            records.first?.author,
            "Editor"
        )

        XCTAssertEqual(
            records.first?.location,
            5
        )

        XCTAssertEqual(
            records.first?.length,
            3
        )
    }

    func testDeletingInsidePendingInsertionShrinksInsertion() {
        let (view, controller) =
            makeEditor("A")

        XCTAssertTrue(
            controller.trackTextEdit(
                range: NSRange(
                    location: 1,
                    length: 0
                ),
                replacement:
                    NSAttributedString(
                        string: "BC"
                    ),
                author: "Editor"
            )
        )

        XCTAssertEqual(
            view.string,
            "ABC"
        )

        XCTAssertTrue(
            controller.trackTextEdit(
                range: NSRange(
                    location: 2,
                    length: 1
                ),
                replacement:
                    NSAttributedString(
                        string: ""
                    ),
                author: "Editor"
            )
        )

        XCTAssertEqual(
            view.string,
            "AB"
        )

        let records =
            TrackChanges.records(
                in: view.attributedString()
            )

        XCTAssertEqual(
            records.count,
            1
        )

        XCTAssertEqual(
            records.first?.kind,
            .insertion
        )

        XCTAssertEqual(
            records.first?.author,
            "Editor"
        )

        XCTAssertEqual(
            records.first?.location,
            1
        )

        XCTAssertEqual(
            records.first?.length,
            1
        )
    }

    func testProgrammaticReplaceCanCreateTrackedRevision() {
        let (view, controller) =
            makeEditor(
                "The old text."
            )

        controller.replace(
            range: NSRange(
                location: 4,
                length: 3
            ),
            with:
                NSAttributedString(
                    string: "new"
                ),
            actionName: "Replace",
            trackChanges: true
        )

        XCTAssertEqual(
            view.string,
            "The oldnew text."
        )

        let records =
            TrackChanges.records(
                in: view.attributedString()
            )

        XCTAssertEqual(
            records.count,
            2
        )

        XCTAssertEqual(
            records.map(\.kind),
            [
                .deletion,
                .insertion
            ]
        )

        XCTAssertEqual(
            records[0].location,
            4
        )

        XCTAssertEqual(
            records[0].length,
            3
        )

        XCTAssertEqual(
            records[1].location,
            7
        )

        XCTAssertEqual(
            records[1].length,
            3
        )
    }

    func testProgrammaticReplaceAllCanCreateTrackedRevisions() {
        let (view, controller) =
            makeEditor(
                "cat and cat"
            )

        controller.replaceAll(
            [
                NSRange(
                    location: 0,
                    length: 3
                ),
                NSRange(
                    location: 8,
                    length: 3
                )
            ],
            with: "dog",
            trackChanges: true
        )

        XCTAssertEqual(
            view.string,
            "catdog and catdog"
        )

        let records =
            TrackChanges.records(
                in: view.attributedString()
            )

        XCTAssertEqual(
            records.count,
            4
        )

        XCTAssertEqual(
            records.filter {
                $0.kind == .deletion
            }.count,
            2
        )

        XCTAssertEqual(
            records.filter {
                $0.kind == .insertion
            }.count,
            2
        )
    }

    func testDeletingInsidePendingDeletionDoesNotStackRevision() {
        let (view, controller) =
            makeEditor(
                "ABCDE"
            )

        XCTAssertTrue(
            controller.trackTextEdit(
                range: NSRange(
                    location: 1,
                    length: 3
                ),
                replacement:
                    NSAttributedString(
                        string: ""
                    ),
                author: "Editor"
            )
        )

        let before =
            TrackChanges.records(
                in: view.attributedString()
            )

        XCTAssertEqual(
            before.count,
            1
        )

        XCTAssertTrue(
            controller.trackTextEdit(
                range: NSRange(
                    location: 2,
                    length: 1
                ),
                replacement:
                    NSAttributedString(
                        string: ""
                    ),
                author: "Editor"
            )
        )

        XCTAssertEqual(
            view.string,
            "ABCDE"
        )

        let after =
            TrackChanges.records(
                in: view.attributedString()
            )

        XCTAssertEqual(
            after.count,
            1
        )

        XCTAssertEqual(
            after.first?.kind,
            .deletion
        )

        XCTAssertEqual(
            after.first?.location,
            1
        )

        XCTAssertEqual(
            after.first?.length,
            3
        )

        XCTAssertEqual(
            after.first?.id,
            before.first?.id
        )
    }

    func testReplacingInsidePendingDeletionPreservesDeletion() {
        let (view, controller) =
            makeEditor(
                "ABCDE"
            )

        XCTAssertTrue(
            controller.trackTextEdit(
                range: NSRange(
                    location: 1,
                    length: 3
                ),
                replacement:
                    NSAttributedString(
                        string: ""
                    ),
                author: "Editor"
            )
        )

        let originalDeletion =
            TrackChanges.records(
                in: view.attributedString()
            ).first

        XCTAssertTrue(
            controller.trackTextEdit(
                range: NSRange(
                    location: 2,
                    length: 1
                ),
                replacement:
                    NSAttributedString(
                        string: "X"
                    ),
                author: "Editor"
            )
        )

        XCTAssertEqual(
            view.string,
            "ABCDXE"
        )

        let records =
            TrackChanges.records(
                in: view.attributedString()
            )

        XCTAssertEqual(
            records.count,
            2
        )

        XCTAssertEqual(
            records[0].kind,
            .deletion
        )

        XCTAssertEqual(
            records[0].location,
            1
        )

        XCTAssertEqual(
            records[0].length,
            3
        )

        XCTAssertEqual(
            records[0].id,
            originalDeletion?.id
        )

        XCTAssertEqual(
            records[1].kind,
            .insertion
        )

        XCTAssertEqual(
            records[1].location,
            4
        )

        XCTAssertEqual(
            records[1].length,
            1
        )
    }

    func testTypingInsidePendingDeletionDoesNotSplitDeletion() {
        let (view, controller) =
            makeEditor(
                "ABCDE"
            )

        XCTAssertTrue(
            controller.trackTextEdit(
                range: NSRange(
                    location: 1,
                    length: 3
                ),
                replacement:
                    NSAttributedString(
                        string: ""
                    ),
                author: "Editor"
            )
        )

        let originalDeletion =
            TrackChanges.records(
                in: view.attributedString()
            ).first

        XCTAssertTrue(
            controller.trackTextEdit(
                range: NSRange(
                    location: 2,
                    length: 0
                ),
                replacement:
                    NSAttributedString(
                        string: "X"
                    ),
                author: "Editor"
            )
        )

        XCTAssertEqual(
            view.string,
            "ABCDXE"
        )

        let records =
            TrackChanges.records(
                in: view.attributedString()
            )

        XCTAssertEqual(
            records.count,
            2
        )

        XCTAssertEqual(
            records[0].kind,
            .deletion
        )

        XCTAssertEqual(
            records[0].location,
            1
        )

        XCTAssertEqual(
            records[0].length,
            3
        )

        XCTAssertEqual(
            records[0].id,
            originalDeletion?.id
        )

        XCTAssertEqual(
            records[1].kind,
            .insertion
        )

        XCTAssertEqual(
            records[1].location,
            4
        )

        XCTAssertEqual(
            records[1].length,
            1
        )
    }

    func testReplacementFromOriginalTextIntoPendingInsertion() {
        let (view, controller) =
            makeEditor(
                "ABC"
            )

        XCTAssertTrue(
            controller.trackTextEdit(
                range: NSRange(
                    location: 2,
                    length: 0
                ),
                replacement:
                    NSAttributedString(
                        string: "XY"
                    ),
                author: "Editor"
            )
        )

        XCTAssertEqual(
            view.string,
            "ABXYC"
        )

        XCTAssertTrue(
            controller.trackTextEdit(
                range: NSRange(
                    location: 1,
                    length: 3
                ),
                replacement:
                    NSAttributedString(
                        string: "Q"
                    ),
                author: "Editor"
            )
        )

        XCTAssertEqual(
            view.string,
            "ABQC"
        )

        let records =
            TrackChanges.records(
                in: view.attributedString()
            )

        XCTAssertEqual(
            records.count,
            2
        )

        XCTAssertEqual(
            records.map(\.kind),
            [
                .deletion,
                .insertion
            ]
        )

        XCTAssertEqual(
            records[0].location,
            1
        )

        XCTAssertEqual(
            records[0].length,
            1
        )

        XCTAssertEqual(
            records[1].location,
            2
        )

        XCTAssertEqual(
            records[1].length,
            1
        )

        controller.rejectAllTrackedChanges()

        XCTAssertEqual(
            view.string,
            "ABC"
        )

        XCTAssertTrue(
            TrackChanges.records(
                in: view.attributedString()
            ).isEmpty
        )
    }

    func testReplacementFromPendingInsertionIntoOriginalText() {
        let (view, controller) =
            makeEditor(
                "ABC"
            )

        XCTAssertTrue(
            controller.trackTextEdit(
                range: NSRange(
                    location: 1,
                    length: 0
                ),
                replacement:
                    NSAttributedString(
                        string: "XY"
                    ),
                author: "Editor"
            )
        )

        XCTAssertEqual(
            view.string,
            "AXYBC"
        )

        XCTAssertTrue(
            controller.trackTextEdit(
                range: NSRange(
                    location: 1,
                    length: 3
                ),
                replacement:
                    NSAttributedString(
                        string: "Q"
                    ),
                author: "Editor"
            )
        )

        XCTAssertEqual(
            view.string,
            "ABQC"
        )

        let records =
            TrackChanges.records(
                in: view.attributedString()
            )

        XCTAssertEqual(
            records.count,
            2
        )

        XCTAssertEqual(
            records.map(\.kind),
            [
                .deletion,
                .insertion
            ]
        )

        XCTAssertEqual(
            records[0].location,
            1
        )

        XCTAssertEqual(
            records[0].length,
            1
        )

        XCTAssertEqual(
            records[1].location,
            2
        )

        XCTAssertEqual(
            records[1].length,
            1
        )

        controller.acceptAllTrackedChanges()

        XCTAssertEqual(
            view.string,
            "AQC"
        )

        XCTAssertTrue(
            TrackChanges.records(
                in: view.attributedString()
            ).isEmpty
        )
    }

    func testReplacementAcrossPendingDeletionAndOriginalTextAcceptsCorrectly() {
        let (view, controller) =
            makeEditor(
                "ABCDE"
            )

        XCTAssertTrue(
            controller.trackTextEdit(
                range: NSRange(
                    location: 1,
                    length: 2
                ),
                replacement:
                    NSAttributedString(
                        string: ""
                    ),
                author: "Editor"
            )
        )

        let originalDeletion =
            TrackChanges.records(
                in: view.attributedString()
            ).first

        XCTAssertTrue(
            controller.trackTextEdit(
                range: NSRange(
                    location: 1,
                    length: 3
                ),
                replacement:
                    NSAttributedString(
                        string: "X"
                    ),
                author: "Editor"
            )
        )

        XCTAssertEqual(
            view.string,
            "ABCDXE"
        )

        let records =
            TrackChanges.records(
                in: view.attributedString()
            )

        XCTAssertEqual(
            records.count,
            3
        )

        XCTAssertEqual(
            records[0].kind,
            .deletion
        )

        XCTAssertEqual(
            records[0].location,
            1
        )

        XCTAssertEqual(
            records[0].length,
            2
        )

        XCTAssertEqual(
            records[0].id,
            originalDeletion?.id
        )

        XCTAssertEqual(
            records[1].kind,
            .deletion
        )

        XCTAssertEqual(
            records[1].location,
            3
        )

        XCTAssertEqual(
            records[1].length,
            1
        )

        XCTAssertEqual(
            records[2].kind,
            .insertion
        )

        XCTAssertEqual(
            records[2].location,
            4
        )

        XCTAssertEqual(
            records[2].length,
            1
        )

        controller.acceptAllTrackedChanges()

        XCTAssertEqual(
            view.string,
            "AXE"
        )

        XCTAssertTrue(
            TrackChanges.records(
                in: view.attributedString()
            ).isEmpty
        )
    }

    func testReplacementAcrossPendingDeletionAndOriginalTextRejectsCorrectly() {
        let (view, controller) =
            makeEditor(
                "ABCDE"
            )

        XCTAssertTrue(
            controller.trackTextEdit(
                range: NSRange(
                    location: 1,
                    length: 2
                ),
                replacement:
                    NSAttributedString(
                        string: ""
                    ),
                author: "Editor"
            )
        )

        XCTAssertTrue(
            controller.trackTextEdit(
                range: NSRange(
                    location: 1,
                    length: 3
                ),
                replacement:
                    NSAttributedString(
                        string: "X"
                    ),
                author: "Editor"
            )
        )

        controller.rejectAllTrackedChanges()

        XCTAssertEqual(
            view.string,
            "ABCDE"
        )

        XCTAssertTrue(
            TrackChanges.records(
                in: view.attributedString()
            ).isEmpty
        )
    }

    func testReplacementAcrossPendingInsertionAndDeletionAcceptsCorrectly() {
        let (view, controller) =
            makeEditor(
                "ABCD"
            )

        XCTAssertTrue(
            controller.trackTextEdit(
                range: NSRange(
                    location: 1,
                    length: 0
                ),
                replacement:
                    NSAttributedString(
                        string: "X"
                    ),
                author: "Editor"
            )
        )

        XCTAssertEqual(
            view.string,
            "AXBCD"
        )

        XCTAssertTrue(
            controller.trackTextEdit(
                range: NSRange(
                    location: 2,
                    length: 2
                ),
                replacement:
                    NSAttributedString(
                        string: ""
                    ),
                author: "Editor"
            )
        )

        XCTAssertEqual(
            view.string,
            "AXBCD"
        )

        let deletionBefore =
            TrackChanges.records(
                in: view.attributedString()
            )
            .first {
                $0.kind == .deletion
            }

        XCTAssertTrue(
            controller.trackTextEdit(
                range: NSRange(
                    location: 1,
                    length: 3
                ),
                replacement:
                    NSAttributedString(
                        string: "Q"
                    ),
                author: "Editor"
            )
        )

        XCTAssertEqual(
            view.string,
            "ABCQD"
        )

        let records =
            TrackChanges.records(
                in: view.attributedString()
            )

        XCTAssertEqual(
            records.count,
            2
        )

        XCTAssertEqual(
            records[0].kind,
            .deletion
        )

        XCTAssertEqual(
            records[0].location,
            1
        )

        XCTAssertEqual(
            records[0].length,
            2
        )

        XCTAssertEqual(
            records[0].id,
            deletionBefore?.id
        )

        XCTAssertEqual(
            records[1].kind,
            .insertion
        )

        XCTAssertEqual(
            records[1].location,
            3
        )

        XCTAssertEqual(
            records[1].length,
            1
        )

        controller.acceptAllTrackedChanges()

        XCTAssertEqual(
            view.string,
            "AQD"
        )

        XCTAssertTrue(
            TrackChanges.records(
                in: view.attributedString()
            ).isEmpty
        )
    }

    func testReplacementAcrossPendingInsertionAndDeletionRejectsCorrectly() {
        let (view, controller) =
            makeEditor(
                "ABCD"
            )

        XCTAssertTrue(
            controller.trackTextEdit(
                range: NSRange(
                    location: 1,
                    length: 0
                ),
                replacement:
                    NSAttributedString(
                        string: "X"
                    ),
                author: "Editor"
            )
        )

        XCTAssertTrue(
            controller.trackTextEdit(
                range: NSRange(
                    location: 2,
                    length: 2
                ),
                replacement:
                    NSAttributedString(
                        string: ""
                    ),
                author: "Editor"
            )
        )

        XCTAssertTrue(
            controller.trackTextEdit(
                range: NSRange(
                    location: 1,
                    length: 3
                ),
                replacement:
                    NSAttributedString(
                        string: "Q"
                    ),
                author: "Editor"
            )
        )

        controller.rejectAllTrackedChanges()

        XCTAssertEqual(
            view.string,
            "ABCD"
        )

        XCTAssertTrue(
            TrackChanges.records(
                in: view.attributedString()
            ).isEmpty
        )
    }

    func testGeneralMixedRevisionReplacementAcceptsCorrectly() {
        let (view, controller) =
            makeEditor(
                "ABCDEFG"
            )

        // Pending insertion XY after B.
        XCTAssertTrue(
            controller.trackTextEdit(
                range: NSRange(
                    location: 2,
                    length: 0
                ),
                replacement:
                    NSAttributedString(
                        string: "XY"
                    ),
                author: "Editor"
            )
        )

        XCTAssertEqual(
            view.string,
            "ABXYCDEFG"
        )

        // Existing pending deletion DE.
        XCTAssertTrue(
            controller.trackTextEdit(
                range: NSRange(
                    location: 5,
                    length: 2
                ),
                replacement:
                    NSAttributedString(
                        string: ""
                    ),
                author: "Editor"
            )
        )

        let existingDeletion =
            TrackChanges.records(
                in: view.attributedString()
            )
            .first {
                $0.kind == .deletion
            }

        XCTAssertNotNil(
            existingDeletion
        )

        // Select B + XY + C + DE + F and replace with Q.
        XCTAssertTrue(
            controller.trackTextEdit(
                range: NSRange(
                    location: 1,
                    length: 7
                ),
                replacement:
                    NSAttributedString(
                        string: "Q"
                    ),
                author: "Editor"
            )
        )

        XCTAssertEqual(
            view.string,
            "ABCDEFQG"
        )

        let records =
            TrackChanges.records(
                in: view.attributedString()
            )

        XCTAssertEqual(
            records.count,
            5
        )

        XCTAssertEqual(
            records.filter {
                $0.kind == .deletion
            }.count,
            4
        )

        XCTAssertEqual(
            records.filter {
                $0.kind == .insertion
            }.count,
            1
        )

        let deletionRecords =
            records.filter {
                $0.kind == .deletion
            }

        XCTAssertEqual(
            deletionRecords.map(\.location),
            [
                1,
                2,
                3,
                5
            ]
        )

        XCTAssertEqual(
            deletionRecords.map(\.length),
            [
                1,
                1,
                2,
                1
            ]
        )

        XCTAssertTrue(
            deletionRecords.contains {
                $0.id == existingDeletion?.id
                    && $0.location == 3
                    && $0.length == 2
            }
        )

        let insertionRecord =
            records.first {
                $0.kind == .insertion
            }

        XCTAssertEqual(
            insertionRecord?.location,
            6
        )

        XCTAssertEqual(
            insertionRecord?.length,
            1
        )

        controller.acceptAllTrackedChanges()

        XCTAssertEqual(
            view.string,
            "AQG"
        )

        XCTAssertTrue(
            TrackChanges.records(
                in: view.attributedString()
            ).isEmpty
        )
    }

    func testGeneralMixedRevisionReplacementRejectsCorrectly() {
        let (view, controller) =
            makeEditor(
                "ABCDEFG"
            )

        XCTAssertTrue(
            controller.trackTextEdit(
                range: NSRange(
                    location: 2,
                    length: 0
                ),
                replacement:
                    NSAttributedString(
                        string: "XY"
                    ),
                author: "Editor"
            )
        )

        XCTAssertTrue(
            controller.trackTextEdit(
                range: NSRange(
                    location: 5,
                    length: 2
                ),
                replacement:
                    NSAttributedString(
                        string: ""
                    ),
                author: "Editor"
            )
        )

        XCTAssertTrue(
            controller.trackTextEdit(
                range: NSRange(
                    location: 1,
                    length: 7
                ),
                replacement:
                    NSAttributedString(
                        string: "Q"
                    ),
                author: "Editor"
            )
        )

        controller.rejectAllTrackedChanges()

        XCTAssertEqual(
            view.string,
            "ABCDEFG"
        )

        XCTAssertTrue(
            TrackChanges.records(
                in: view.attributedString()
            ).isEmpty
        )
    }

    func testReplacementAcrossMultipleIndependentRevisionsAcceptsCorrectly() {
        let (view, controller) =
            makeEditor(
                "ABCDEFGHIJ"
            )

        // Independent insertion X after B.
        XCTAssertTrue(
            controller.trackTextEdit(
                range: NSRange(
                    location: 2,
                    length: 0
                ),
                replacement:
                    NSAttributedString(
                        string: "X"
                    ),
                author: "Editor"
            )
        )

        // Independent insertion Y after H.
        XCTAssertTrue(
            controller.trackTextEdit(
                range: NSRange(
                    location: 9,
                    length: 0
                ),
                replacement:
                    NSAttributedString(
                        string: "Y"
                    ),
                author: "Editor"
            )
        )

        XCTAssertEqual(
            view.string,
            "ABXCDEFGHYIJ"
        )

        // Independent deletion D.
        XCTAssertTrue(
            controller.trackTextEdit(
                range: NSRange(
                    location: 4,
                    length: 1
                ),
                replacement:
                    NSAttributedString(
                        string: ""
                    ),
                author: "Editor"
            )
        )

        // Independent deletion G.
        XCTAssertTrue(
            controller.trackTextEdit(
                range: NSRange(
                    location: 7,
                    length: 1
                ),
                replacement:
                    NSAttributedString(
                        string: ""
                    ),
                author: "Editor"
            )
        )

        let oldDeletions =
            TrackChanges.records(
                in: view.attributedString()
            )
            .filter {
                $0.kind == .deletion
            }

        XCTAssertEqual(
            oldDeletions.count,
            2
        )

        XCTAssertNotEqual(
            oldDeletions[0].id,
            oldDeletions[1].id
        )

        // Select:
        // B + X + C + D + E + F + G + H + Y + I
        //
        // This contains:
        // - 2 independent insertion records
        // - 2 independent deletion records
        // - several separated ordinary-text ranges
        XCTAssertTrue(
            controller.trackTextEdit(
                range: NSRange(
                    location: 1,
                    length: 10
                ),
                replacement:
                    NSAttributedString(
                        string: "Q"
                    ),
                author: "Editor"
            )
        )

        XCTAssertEqual(
            view.string,
            "ABCDEFGHIQJ"
        )

        let records =
            TrackChanges.records(
                in: view.attributedString()
            )

        let deletions =
            records.filter {
                $0.kind == .deletion
            }

        let insertions =
            records.filter {
                $0.kind == .insertion
            }

        // Five newly deleted ordinary segments:
        // B, C, EF, H, I
        //
        // Plus the two preserved deletion revisions:
        // D and G
        XCTAssertEqual(
            deletions.count,
            7
        )

        XCTAssertEqual(
            insertions.count,
            1
        )

        // Both independent pre-existing deletion identities
        // must survive the mixed replacement.
        XCTAssertTrue(
            deletions.contains {
                $0.id == oldDeletions[0].id
            }
        )

        XCTAssertTrue(
            deletions.contains {
                $0.id == oldDeletions[1].id
            }
        )

        let newDeletionIDs =
            Set(
                deletions
                    .filter {
                        $0.id != oldDeletions[0].id
                            && $0.id != oldDeletions[1].id
                    }
                    .map(\.id)
            )

        // Each separated newly deleted ordinary range receives
        // its own independent revision identity.
        XCTAssertEqual(
            newDeletionIDs.count,
            5
        )

        XCTAssertEqual(
            insertions.first?.location,
            9
        )

        XCTAssertEqual(
            insertions.first?.length,
            1
        )

        controller.acceptAllTrackedChanges()

        XCTAssertEqual(
            view.string,
            "AQJ"
        )

        XCTAssertTrue(
            TrackChanges.records(
                in: view.attributedString()
            ).isEmpty
        )
    }

    func testReplacementAcrossMultipleIndependentRevisionsRejectsCorrectly() {
        let (view, controller) =
            makeEditor(
                "ABCDEFGHIJ"
            )

        XCTAssertTrue(
            controller.trackTextEdit(
                range: NSRange(
                    location: 2,
                    length: 0
                ),
                replacement:
                    NSAttributedString(
                        string: "X"
                    ),
                author: "Editor"
            )
        )

        XCTAssertTrue(
            controller.trackTextEdit(
                range: NSRange(
                    location: 9,
                    length: 0
                ),
                replacement:
                    NSAttributedString(
                        string: "Y"
                    ),
                author: "Editor"
            )
        )

        XCTAssertTrue(
            controller.trackTextEdit(
                range: NSRange(
                    location: 4,
                    length: 1
                ),
                replacement:
                    NSAttributedString(
                        string: ""
                    ),
                author: "Editor"
            )
        )

        XCTAssertTrue(
            controller.trackTextEdit(
                range: NSRange(
                    location: 7,
                    length: 1
                ),
                replacement:
                    NSAttributedString(
                        string: ""
                    ),
                author: "Editor"
            )
        )

        XCTAssertTrue(
            controller.trackTextEdit(
                range: NSRange(
                    location: 1,
                    length: 10
                ),
                replacement:
                    NSAttributedString(
                        string: "Q"
                    ),
                author: "Editor"
            )
        )

        controller.rejectAllTrackedChanges()

        XCTAssertEqual(
            view.string,
            "ABCDEFGHIJ"
        )

        XCTAssertTrue(
            TrackChanges.records(
                in: view.attributedString()
            ).isEmpty
        )
    }

    func testTrackChangeRecordsRestoreAfterMetadataRoundTrip() throws {
        let original =
            NSMutableAttributedString(
                string: "Changed",
                attributes: [
                    .font:
                        NSFont.systemFont(ofSize: 15)
                ]
            )

        original.addAttribute(
            .boldWriterTrackChange,
            value: TrackChanges.marker(
                kind: .insertion,
                author: "Editor"
            ),
            range: NSRange(
                location: 0,
                length: original.length
            )
        )

        let records =
            TrackChanges.records(in: original)

        let data =
            try JSONEncoder().encode(records)

        let decoded =
            try JSONDecoder().decode(
                [TrackChangeRecord].self,
                from: data
            )

        let restored =
            NSMutableAttributedString(
                string: "Changed"
            )

        TrackChanges.restore(
            decoded,
            into: restored
        )

        let result =
            TrackChanges.records(in: restored)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(
            result.first?.kind,
            .insertion
        )
        XCTAssertEqual(
            result.first?.author,
            "Editor"
        )
    }

    func testAcceptAndRejectTrackedFootnoteDeletionKeepsMetadataConsistent()
        throws {
        func footnoteDocument()
            -> NSMutableAttributedString {
            let result =
                NSMutableAttributedString(
                    string: "A",
                    attributes: [
                        .font:
                            NSFont.systemFont(
                                ofSize: 15
                            )
                    ]
                )

            result.append(
                Footnotes.marker(
                    Footnote(
                        text: "First note",
                        location: 1,
                        length: 1
                    ),
                    number: 1
                )
            )

            result.append(
                Footnotes.marker(
                    Footnote(
                        text: "Second note",
                        location: 2,
                        length: 1
                    ),
                    number: 2
                )
            )

            result.append(
                NSAttributedString(
                    string: "B",
                    attributes: [
                        .font:
                            NSFont.systemFont(
                                ofSize: 15
                            )
                    ]
                )
            )

            return result
        }

        do {
            let (view, controller) =
                makeEditor("")

            view.textStorage?
                .setAttributedString(
                    footnoteDocument()
                )

            let before =
                try Footnotes.records(
                    in:
                        view.attributedString()
                )

            XCTAssertEqual(
                before.count,
                2
            )

            let first =
                try XCTUnwrap(
                    before.first
                )

            XCTAssertTrue(
                controller.trackTextEdit(
                    range:
                        NSRange(
                            location:
                                first.location,
                            length:
                                first.length
                        ),
                    replacement:
                        NSAttributedString(
                            string: ""
                        ),
                    author:
                        "Editor"
                )
            )

            XCTAssertEqual(
                TrackChanges.records(
                    in:
                        view.attributedString()
                )
                .filter {
                    $0.kind == .deletion
                }
                .count,
                1
            )

            XCTAssertEqual(
                try Footnotes.records(
                    in:
                        view.attributedString()
                ).count,
                2
            )

            controller.acceptAllTrackedChanges()

            let accepted =
                try Footnotes.records(
                    in:
                        view.attributedString()
                )

            XCTAssertEqual(
                accepted.count,
                1
            )

            XCTAssertEqual(
                accepted.first?
                    .text,
                "Second note"
            )

            XCTAssertTrue(
                TrackChanges.records(
                    in:
                        view.attributedString()
                ).isEmpty
            )

            XCTAssertEqual(
                view.string,
                "A1B"
            )
        }

        do {
            let (view, controller) =
                makeEditor("")

            view.textStorage?
                .setAttributedString(
                    footnoteDocument()
                )

            let first =
                try XCTUnwrap(
                    Footnotes.records(
                        in:
                            view.attributedString()
                    )
                    .first
                )

            XCTAssertTrue(
                controller.trackTextEdit(
                    range:
                        NSRange(
                            location:
                                first.location,
                            length:
                                first.length
                        ),
                    replacement:
                        NSAttributedString(
                            string: ""
                        ),
                    author:
                        "Editor"
                )
            )

            controller.rejectAllTrackedChanges()

            let rejected =
                try Footnotes.records(
                    in:
                        view.attributedString()
                )

            XCTAssertEqual(
                rejected.count,
                2
            )

            XCTAssertEqual(
                rejected.map(\.text),
                [
                    "First note",
                    "Second note"
                ]
            )

            XCTAssertEqual(
                view.string,
                "A12B"
            )

            XCTAssertTrue(
                TrackChanges.records(
                    in:
                        view.attributedString()
                ).isEmpty
            )
        }
    }

    func testResolvingTrackedTableCellEditsPreservesStructure()
        throws {
        func tableDocument()
            throws
            -> NSAttributedString {
            var table =
                try WriterTable(
                    rows: 2,
                    columns: 2
                )

            table.cells[0][0] =
                NSAttributedString(
                    string: "Delete me",
                    attributes: [
                        .font:
                            NSFont.systemFont(
                                ofSize: 15
                            )
                    ]
                )

            table.cells[0][1] =
                NSAttributedString(
                    string: "Keep",
                    attributes: [
                        .font:
                            NSFont.systemFont(
                                ofSize: 15
                            )
                    ]
                )

            table.cells[1][0] =
                NSAttributedString(
                    string: "Lower left",
                    attributes: [
                        .font:
                            NSFont.systemFont(
                                ofSize: 15
                            )
                    ]
                )

            table.cells[1][1] =
                NSAttributedString(
                    string: "Lower right",
                    attributes: [
                        .font:
                            NSFont.systemFont(
                                ofSize: 15
                            )
                    ]
                )

            return try Tables.rendered(
                table
            )
        }

        do {
            let (view, controller) =
                makeEditor("")

            view.textStorage?
                .setAttributedString(
                    try tableDocument()
                )

            let before =
                try XCTUnwrap(
                    Tables.models(
                        in:
                            view.attributedString()
                    )
                    .first
                )

            let originalTableID =
                before.id

            let originalCellIDs =
                before.cellIDs

            let firstCell =
                try XCTUnwrap(
                    Tables.records(
                        in:
                            view.attributedString()
                    )
                    .first
                )

            XCTAssertTrue(
                controller.handleTableEdit(
                    range:
                        NSRange(
                            location:
                                firstCell.location,
                            length:
                                "Delete me"
                                    .utf16
                                    .count
                        ),
                    replacement:
                        NSAttributedString(
                            string: ""
                        ),
                    trackChanges: true
                )
            )

            XCTAssertEqual(
                TrackChanges.records(
                    in:
                        view.attributedString()
                )
                .filter {
                    $0.kind == .deletion
                }
                .count,
                1
            )

            controller.acceptAllTrackedChanges()

            let accepted =
                try XCTUnwrap(
                    Tables.models(
                        in:
                            view.attributedString()
                    )
                    .first
                )

            XCTAssertEqual(
                accepted.id,
                originalTableID
            )

            XCTAssertEqual(
                accepted.cellIDs,
                originalCellIDs
            )

            XCTAssertEqual(
                accepted.rows,
                2
            )

            XCTAssertEqual(
                accepted.columns,
                2
            )

            XCTAssertEqual(
                accepted.cells[0][0]
                    .string,
                ""
            )

            XCTAssertEqual(
                accepted.cells[0][1]
                    .string,
                "Keep"
            )

            XCTAssertTrue(
                TrackChanges.records(
                    in:
                        view.attributedString()
                ).isEmpty
            )

            XCTAssertEqual(
                try Tables.records(
                    in:
                        view.attributedString()
                ).count,
                4
            )
        }

        do {
            let (view, controller) =
                makeEditor("")

            view.textStorage?
                .setAttributedString(
                    try tableDocument()
                )

            let before =
                try XCTUnwrap(
                    Tables.models(
                        in:
                            view.attributedString()
                    )
                    .first
                )

            let originalTableID =
                before.id

            let originalCellIDs =
                before.cellIDs

            let firstCell =
                try XCTUnwrap(
                    Tables.records(
                        in:
                            view.attributedString()
                    )
                    .first
                )

            XCTAssertTrue(
                controller.handleTableEdit(
                    range:
                        NSRange(
                            location:
                                firstCell.location,
                            length: 0
                        ),
                    replacement:
                        NSAttributedString(
                            string:
                                "Pending ",
                            attributes: [
                                .font:
                                    NSFont.systemFont(
                                        ofSize: 15
                                    )
                            ]
                        ),
                    trackChanges: true
                )
            )

            XCTAssertEqual(
                TrackChanges.records(
                    in:
                        view.attributedString()
                )
                .filter {
                    $0.kind == .insertion
                }
                .count,
                1
            )

            controller.rejectAllTrackedChanges()

            let rejected =
                try XCTUnwrap(
                    Tables.models(
                        in:
                            view.attributedString()
                    )
                    .first
                )

            XCTAssertEqual(
                rejected.id,
                originalTableID
            )

            XCTAssertEqual(
                rejected.cellIDs,
                originalCellIDs
            )

            XCTAssertEqual(
                rejected.cells[0][0]
                    .string,
                "Delete me"
            )

            XCTAssertEqual(
                try Tables.records(
                    in:
                        view.attributedString()
                ).count,
                4
            )

            XCTAssertTrue(
                TrackChanges.records(
                    in:
                        view.attributedString()
                ).isEmpty
            )
        }
    }

    func testResolvingTrackedPageBreakDeletionReflowsPagination()
        throws {
        func pageCount(
            _ attributed:
                NSAttributedString
        ) -> Int {
            let editor =
                PaginatedEditor(
                    text: attributed
                )

            editor.configure(
                printLayout: true,
                settings:
                    PageSettings(),
                zoom: 1,
                viewportWidth: 900
            )

            editor.finishPagination()

            XCTAssertNil(
                editor.lastLayoutError
            )

            XCTAssertTrue(
                editor.layoutComplete
            )

            return editor.pages.count
        }

        do {
            let (view, controller) =
                makeEditor(
                    "Before\u{000C}After"
                )

            XCTAssertEqual(
                pageCount(
                    view.attributedString()
                ),
                2
            )

            XCTAssertTrue(
                controller.trackTextEdit(
                    range:
                        NSRange(
                            location: 6,
                            length: 1
                        ),
                    replacement:
                        NSAttributedString(
                            string: ""
                        ),
                    author:
                        "Editor"
                )
            )

            XCTAssertEqual(
                pageCount(
                    view.attributedString()
                ),
                2
            )

            controller.acceptAllTrackedChanges()

            XCTAssertEqual(
                view.string,
                "BeforeAfter"
            )

            XCTAssertTrue(
                TrackChanges.records(
                    in:
                        view.attributedString()
                ).isEmpty
            )

            XCTAssertEqual(
                pageCount(
                    view.attributedString()
                ),
                1
            )
        }

        do {
            let (view, controller) =
                makeEditor(
                    "Before\u{000C}After"
                )

            XCTAssertTrue(
                controller.trackTextEdit(
                    range:
                        NSRange(
                            location: 6,
                            length: 1
                        ),
                    replacement:
                        NSAttributedString(
                            string: ""
                        ),
                    author:
                        "Editor"
                )
            )

            controller.rejectAllTrackedChanges()

            XCTAssertEqual(
                view.string,
                "Before\u{000C}After"
            )

            XCTAssertTrue(
                TrackChanges.records(
                    in:
                        view.attributedString()
                ).isEmpty
            )

            XCTAssertEqual(
                pageCount(
                    view.attributedString()
                ),
                2
            )
        }
    }

    func testResolvingTrackedPageBreakInsertionControlsPagination()
        throws {
        func pageCount(
            _ attributed:
                NSAttributedString
        ) -> Int {
            let editor =
                PaginatedEditor(
                    text: attributed
                )

            editor.configure(
                printLayout: true,
                settings:
                    PageSettings(),
                zoom: 1,
                viewportWidth: 900
            )

            editor.finishPagination()

            XCTAssertNil(
                editor.lastLayoutError
            )

            XCTAssertTrue(
                editor.layoutComplete
            )

            return editor.pages.count
        }

        do {
            let (view, controller) =
                makeEditor(
                    "BeforeAfter"
                )

            XCTAssertEqual(
                pageCount(
                    view.attributedString()
                ),
                1
            )

            XCTAssertTrue(
                controller.trackTextEdit(
                    range:
                        NSRange(
                            location: 6,
                            length: 0
                        ),
                    replacement:
                        NSAttributedString(
                            string:
                                "\u{000C}"
                        ),
                    author:
                        "Editor"
                )
            )

            XCTAssertEqual(
                view.string,
                "Before\u{000C}After"
            )

            XCTAssertEqual(
                pageCount(
                    view.attributedString()
                ),
                2
            )

            controller.acceptAllTrackedChanges()

            XCTAssertEqual(
                view.string,
                "Before\u{000C}After"
            )

            XCTAssertTrue(
                TrackChanges.records(
                    in:
                        view.attributedString()
                ).isEmpty
            )

            XCTAssertEqual(
                pageCount(
                    view.attributedString()
                ),
                2
            )
        }

        do {
            let (view, controller) =
                makeEditor(
                    "BeforeAfter"
                )

            XCTAssertTrue(
                controller.trackTextEdit(
                    range:
                        NSRange(
                            location: 6,
                            length: 0
                        ),
                    replacement:
                        NSAttributedString(
                            string:
                                "\u{000C}"
                        ),
                    author:
                        "Editor"
                )
            )

            controller.rejectAllTrackedChanges()

            XCTAssertEqual(
                view.string,
                "BeforeAfter"
            )

            XCTAssertTrue(
                TrackChanges.records(
                    in:
                        view.attributedString()
                ).isEmpty
            )

            XCTAssertEqual(
                pageCount(
                    view.attributedString()
                ),
                1
            )
        }
    }



    func testTrackedPageBreaksAndTrackingStateSurviveNativePersistence()
        throws {

        func reopen(
            _ text: NSAttributedString,
            tracking: Bool
        ) throws -> BOLDWriterDocument {
            let url =
                FileManager.default
                    .temporaryDirectory
                    .appendingPathComponent(
                        UUID().uuidString
                            + ".boldwriter"
                    )

            defer {
                try? FileManager.default
                    .removeItem(at: url)
            }

            var metadata =
                DocumentMetadata()

            metadata.trackChangesEnabled =
                tracking

            try BOLDWriterDocument
                .packageWrapper(
                    text: text,
                    metadata: metadata
                )
                .write(
                    to: url,
                    options: .atomic,
                    originalContentsURL: nil
                )

            return try BOLDWriterDocument(
                fileWrapper:
                    FileWrapper(url: url),
                contentType:
                    .boldWriterDocument
            )
        }

        do {
            let (view, controller) =
                makeEditor(
                    "BeforeAfter"
                )

            XCTAssertTrue(
                controller.trackTextEdit(
                    range:
                        NSRange(
                            location: 6,
                            length: 0
                        ),
                    replacement:
                        NSAttributedString(
                            string:
                                "\u{000C}"
                        ),
                    author:
                        "Persistence Editor"
                )
            )

            let reopened =
                try reopen(
                    view.attributedString(),
                    tracking: false
                )

            XCTAssertEqual(
                reopened
                    .metadata
                    .trackChangesEnabled,
                false
            )

            XCTAssertEqual(
                reopened.text.string,
                "Before\u{000C}After"
            )

            XCTAssertEqual(
                TrackChanges.records(
                    in:
                        reopened.text
                )
                .filter {
                    $0.kind == .insertion
                }
                .count,
                1
            )

            let (
                reopenedView,
                reopenedController
            ) =
                makeEditor("")

            reopenedView
                .textStorage?
                .setAttributedString(
                    reopened.text
                )

            reopenedController
                .rejectAllTrackedChanges()

            XCTAssertEqual(
                reopenedView.string,
                "BeforeAfter"
            )

            XCTAssertTrue(
                TrackChanges.records(
                    in:
                        reopenedView
                            .attributedString()
                )
                .isEmpty
            )
        }

        do {
            let (view, controller) =
                makeEditor(
                    "Before\u{000C}After"
                )

            XCTAssertTrue(
                controller.trackTextEdit(
                    range:
                        NSRange(
                            location: 6,
                            length: 1
                        ),
                    replacement:
                        NSAttributedString(
                            string: ""
                        ),
                    author:
                        "Persistence Editor"
                )
            )

            let reopened =
                try reopen(
                    view.attributedString(),
                    tracking: true
                )

            XCTAssertEqual(
                reopened
                    .metadata
                    .trackChangesEnabled,
                true
            )

            XCTAssertEqual(
                reopened.text.string,
                "Before\u{000C}After"
            )

            XCTAssertEqual(
                TrackChanges.records(
                    in:
                        reopened.text
                )
                .filter {
                    $0.kind == .deletion
                }
                .count,
                1
            )

            let (
                reopenedView,
                reopenedController
            ) =
                makeEditor("")

            reopenedView
                .textStorage?
                .setAttributedString(
                    reopened.text
                )

            reopenedController
                .acceptAllTrackedChanges()

            XCTAssertEqual(
                reopenedView.string,
                "BeforeAfter"
            )

            XCTAssertTrue(
                TrackChanges.records(
                    in:
                        reopenedView
                            .attributedString()
                )
                .isEmpty
            )
        }

        do {
            let reopened =
                try reopen(
                    NSAttributedString(
                        string:
                            "Tracking stays enabled"
                    ),
                    tracking: true
                )

            XCTAssertEqual(
                reopened
                    .metadata
                    .trackChangesEnabled,
                true
            )

            XCTAssertTrue(
                TrackChanges.records(
                    in:
                        reopened.text
                )
                .isEmpty
            )
        }
    }


    func testReviewNavigationTraversesTrackedChangesWithoutWrapping()
        throws {

        do {
            let (view, controller) =
                makeEditor(
                    "abcdef"
                )

            let storage =
                try XCTUnwrap(
                    view.textStorage
                )

            storage.addAttribute(
                .boldWriterTrackChange,
                value:
                    TrackChanges.marker(
                        kind: .insertion,
                        author:
                            "Reviewer"
                    ),
                range:
                    NSRange(
                        location: 1,
                        length: 1
                    )
            )

            storage.addAttribute(
                .boldWriterTrackChange,
                value:
                    TrackChanges.marker(
                        kind: .deletion,
                        author:
                            "Reviewer"
                    ),
                range:
                    NSRange(
                        location: 4,
                        length: 1
                    )
            )

            view.setSelectedRange(
                NSRange(
                    location: 0,
                    length: 0
                )
            )

            XCTAssertTrue(
                controller
                    .nextTrackedChange()
            )

            XCTAssertEqual(
                view.selectedRange(),
                NSRange(
                    location: 1,
                    length: 1
                )
            )

            XCTAssertTrue(
                controller
                    .nextTrackedChange()
            )

            XCTAssertEqual(
                view.selectedRange(),
                NSRange(
                    location: 4,
                    length: 1
                )
            )

            XCTAssertFalse(
                controller
                    .nextTrackedChange()
            )

            XCTAssertEqual(
                view.selectedRange(),
                NSRange(
                    location: 4,
                    length: 1
                )
            )

            XCTAssertTrue(
                controller
                    .previousTrackedChange()
            )

            XCTAssertEqual(
                view.selectedRange(),
                NSRange(
                    location: 1,
                    length: 1
                )
            )

            XCTAssertFalse(
                controller
                    .previousTrackedChange()
            )

            XCTAssertEqual(
                view.selectedRange(),
                NSRange(
                    location: 1,
                    length: 1
                )
            )
        }

        do {
            let (view, controller) =
                makeEditor(
                    "A"
                )

            var note =
                Footnote(
                    text:
                        "Proposed body",
                    location: 1,
                    length: 1
                )

            note.bodyChangeOriginalText =
                "Original body"

            note.bodyChangeID =
                UUID()

            view.textStorage?
                .append(
                    Footnotes.marker(
                        note,
                        number: 1
                    )
                )

            view.setSelectedRange(
                NSRange(
                    location: 0,
                    length: 0
                )
            )

            XCTAssertTrue(
                controller
                    .nextTrackedChange()
            )

            XCTAssertEqual(
                view.selectedRange(),
                NSRange(
                    location: 1,
                    length: 1
                )
            )

            XCTAssertFalse(
                controller
                    .nextTrackedChange()
            )
        }

        do {
            let (view, controller) =
                makeEditor(
                    "A"
                )

            let note =
                Footnote(
                    text:
                        "Tracked reference",
                    location: 1,
                    length: 1
                )

            view.textStorage?
                .append(
                    Footnotes.marker(
                        note,
                        number: 1
                    )
                )

            view.textStorage?
                .addAttribute(
                    .boldWriterTrackChange,
                    value:
                        TrackChanges.marker(
                            kind:
                                .insertion,
                            author:
                                "Reviewer"
                        ),
                    range:
                        NSRange(
                            location: 1,
                            length: 1
                        )
                )

            view.setSelectedRange(
                NSRange(
                    location: 0,
                    length: 0
                )
            )

            XCTAssertTrue(
                controller
                    .nextTrackedChange()
            )

            XCTAssertEqual(
                view.selectedRange(),
                NSRange(
                    location: 1,
                    length: 1
                )
            )
        }

        do {
            var table =
                try WriterTable(
                    rows: 1,
                    columns: 1
                )

            table.cells[0][0] =
                NSAttributedString(
                    string:
                        "Tracked cell"
                )

            let rendered =
                try Tables.rendered(
                    table
                )

            let (view, controller) =
                makeEditor("")

            view.textStorage?
                .setAttributedString(
                    rendered
                )

            let cell =
                try XCTUnwrap(
                    Tables.records(
                        in:
                            view.attributedString()
                    )
                    .first
                )

            view.textStorage?
                .addAttribute(
                    .boldWriterTrackChange,
                    value:
                        TrackChanges.marker(
                            kind:
                                .insertion,
                            author:
                                "Reviewer"
                        ),
                    range:
                        NSRange(
                            location:
                                cell.location,
                            length: 1
                        )
                )

            view.setSelectedRange(
                NSRange(
                    location: 0,
                    length: 0
                )
            )

            XCTAssertTrue(
                controller
                    .nextTrackedChange()
            )

            XCTAssertEqual(
                view.selectedRange(),
                NSRange(
                    location:
                        cell.location,
                    length: 1
                )
            )

            XCTAssertEqual(
                try Tables.models(
                    in:
                        view.attributedString()
                )
                .first?
                .id,
                table.id
            )
        }
    }


    func testReviewItemsDescribeTrackedContentAndFootnoteBodyEdits()
        throws {

        do {
            let text =
                NSMutableAttributedString(
                    string:
                        "Alpha\u{000C}Omega"
                )

            text.addAttribute(
                .boldWriterTrackChange,
                value:
                    TrackChanges.marker(
                        kind:
                            .insertion,
                        author:
                            "Alice",
                        date:
                            Date(
                                timeIntervalSince1970:
                                    100
                            )
                    ),
                range:
                    NSRange(
                        location: 5,
                        length: 1
                    )
            )

            text.addAttribute(
                .boldWriterTrackChange,
                value:
                    TrackChanges.marker(
                        kind:
                            .deletion,
                        author:
                            "Bob",
                        date:
                            Date(
                                timeIntervalSince1970:
                                    200
                            )
                    ),
                range:
                    NSRange(
                        location: 6,
                        length: 5
                    )
            )

            let items =
                TrackChanges.reviewItems(
                    in: text
                )

            XCTAssertEqual(
                items.count,
                2
            )

            XCTAssertEqual(
                items[0].title,
                "Inserted page break"
            )

            XCTAssertEqual(
                items[0].preview,
                "Page break"
            )

            XCTAssertEqual(
                items[0].author,
                "Alice"
            )

            XCTAssertEqual(
                items[1].title,
                "Deleted text"
            )

            XCTAssertEqual(
                items[1].preview,
                "Omega"
            )

            XCTAssertEqual(
                items[1].author,
                "Bob"
            )
        }

        do {
            let text =
                NSMutableAttributedString(
                    string: "Body"
                )

            var note =
                Footnote(
                    text:
                        "New footnote body",
                    location: 4,
                    length: 1
                )

            note.bodyChangeOriginalText =
                "Old footnote body"

            note.bodyChangeID =
                UUID()

            note.bodyChangeAuthor =
                "Carol"

            note.bodyChangeDate =
                Date(
                    timeIntervalSince1970:
                        300
                )

            text.append(
                Footnotes.marker(
                    note,
                    number: 1
                )
            )

            let items =
                TrackChanges.reviewItems(
                    in: text
                )

            XCTAssertEqual(
                items.count,
                1
            )

            XCTAssertEqual(
                items[0].kind,
                .footnoteBodyEdit
            )

            XCTAssertEqual(
                items[0].title,
                "Edited footnote"
            )

            XCTAssertEqual(
                items[0].author,
                "Carol"
            )

            XCTAssertTrue(
                items[0].preview
                    .contains(
                        "Old footnote body"
                    )
            )

            XCTAssertTrue(
                items[0].preview
                    .contains(
                        "New footnote body"
                    )
            )

            XCTAssertEqual(
                items[0].range,
                NSRange(
                    location: 4,
                    length: 1
                )
            )
        }

        do {
            let text =
                NSMutableAttributedString(
                    string:
                        "Paragraph"
                )

            let note =
                Footnote(
                    text:
                        "Reference body",
                    location: 9,
                    length: 1
                )

            text.append(
                Footnotes.marker(
                    note,
                    number: 1
                )
            )

            text.addAttribute(
                .boldWriterTrackChange,
                value:
                    TrackChanges.marker(
                        kind:
                            .insertion,
                        author:
                            "Dana"
                    ),
                range:
                    NSRange(
                        location: 9,
                        length: 1
                    )
            )

            let items =
                TrackChanges.reviewItems(
                    in: text
                )

            XCTAssertEqual(
                items.count,
                1
            )

            XCTAssertEqual(
                items[0].title,
                "Inserted footnote"
            )

            XCTAssertEqual(
                items[0].preview,
                "Reference body"
            )
        }
    }


    func testReviewResolutionTargetsExactItemAndAutomaticallyAdvances()
        throws {

        do {
            let (view, controller) =
                makeEditor(
                    "abcdefg"
                )

            let storage =
                try XCTUnwrap(
                    view.textStorage
                )

            let firstID =
                UUID()

            let middleID =
                UUID()

            let lastID =
                UUID()

            storage.addAttribute(
                .boldWriterTrackChange,
                value:
                    TrackChanges.marker(
                        id:
                            firstID,
                        kind:
                            .insertion,
                        author:
                            "Reviewer"
                    ),
                range:
                    NSRange(
                        location: 1,
                        length: 1
                    )
            )

            storage.addAttribute(
                .boldWriterTrackChange,
                value:
                    TrackChanges.marker(
                        id:
                            middleID,
                        kind:
                            .insertion,
                        author:
                            "Reviewer"
                    ),
                range:
                    NSRange(
                        location: 3,
                        length: 1
                    )
            )

            storage.addAttribute(
                .boldWriterTrackChange,
                value:
                    TrackChanges.marker(
                        id:
                            lastID,
                        kind:
                            .insertion,
                        author:
                            "Reviewer"
                    ),
                range:
                    NSRange(
                        location: 5,
                        length: 1
                    )
            )

            let initial =
                TrackChanges.reviewItems(
                    in: storage
                )

            let middle =
                try XCTUnwrap(
                    initial.first {
                        $0.id
                            == middleID
                    }
                )

            controller.selectTrackedChange(
                middle
            )

            XCTAssertEqual(
                controller
                    .selectedReviewChangeID,
                middleID
            )

            controller
                .acceptTrackedChangeAtSelection()

            let afterMiddle =
                TrackChanges.reviewItems(
                    in: storage
                )

            XCTAssertFalse(
                afterMiddle.contains {
                    $0.id
                        == middleID
                }
            )

            XCTAssertEqual(
                controller
                    .selectedReviewChangeID,
                lastID
            )

            XCTAssertEqual(
                view.selectedRange(),
                NSRange(
                    location: 5,
                    length: 1
                )
            )

            controller
                .acceptTrackedChangeAtSelection()

            XCTAssertEqual(
                controller
                    .selectedReviewChangeID,
                firstID
            )

            XCTAssertEqual(
                view.selectedRange(),
                NSRange(
                    location: 1,
                    length: 1
                )
            )

            XCTAssertEqual(
                TrackChanges.reviewItems(
                    in: storage
                )
                .map(\.id),
                [firstID]
            )

            controller
                .acceptTrackedChangeAtSelection()

            XCTAssertTrue(
                TrackChanges.reviewItems(
                    in: storage
                )
                .isEmpty
            )

            XCTAssertNil(
                controller
                    .selectedReviewChangeID
            )
        }

        do {
            let (view, controller) =
                makeEditor(
                    "A"
                )

            var note =
                Footnote(
                    text:
                        "Proposed body",
                    location: 1,
                    length: 1
                )

            let bodyID =
                UUID()

            let referenceID =
                UUID()

            note.bodyChangeOriginalText =
                "Original body"

            note.bodyChangeID =
                bodyID

            note.bodyChangeAuthor =
                "Reviewer"

            view.textStorage?
                .append(
                    Footnotes.marker(
                        note,
                        number: 1
                    )
                )

            view.textStorage?
                .addAttribute(
                    .boldWriterTrackChange,
                    value:
                        TrackChanges.marker(
                            id:
                                referenceID,
                            kind:
                                .insertion,
                            author:
                                "Reviewer"
                        ),
                    range:
                        NSRange(
                            location: 1,
                            length: 1
                        )
                )

            let before =
                TrackChanges.reviewItems(
                    in:
                        view.attributedString()
                )

            XCTAssertEqual(
                before.count,
                2
            )

            let referenceItem =
                try XCTUnwrap(
                    before.first {
                        $0.id
                            == referenceID
                    }
                )

            controller.selectTrackedChange(
                referenceItem
            )

            controller
                .acceptTrackedChangeAtSelection()

            XCTAssertTrue(
                TrackChanges.records(
                    in:
                        view.attributedString()
                )
                .isEmpty
            )

            let persistedNote =
                try XCTUnwrap(
                    Footnotes.records(
                        in:
                            view.attributedString()
                    )
                    .first
                )

            XCTAssertTrue(
                persistedNote
                    .hasPendingBodyChange
            )

            XCTAssertEqual(
                persistedNote
                    .bodyChangeID,
                bodyID
            )

            XCTAssertEqual(
                controller
                    .selectedReviewChangeID,
                bodyID
            )

            XCTAssertEqual(
                TrackChanges.reviewItems(
                    in:
                        view.attributedString()
                )
                .map(\.id),
                [bodyID]
            )

            controller
                .rejectTrackedChangeAtSelection()

            let rejected =
                try XCTUnwrap(
                    Footnotes.records(
                        in:
                            view.attributedString()
                    )
                    .first
                )

            XCTAssertEqual(
                rejected.text,
                "Original body"
            )

            XCTAssertFalse(
                rejected
                    .hasPendingBodyChange
            )

            XCTAssertTrue(
                TrackChanges.reviewItems(
                    in:
                        view.attributedString()
                )
                .isEmpty
            )

            XCTAssertNil(
                controller
                    .selectedReviewChangeID
            )
        }
    }


    func testReviewResolutionUndoRedoPreservesExactRevisionIdentity()
        throws {

        // ----------------------------------------------------
        // Accepting a tracked insertion:
        // undo restores the same revision ID;
        // redo resolves it again.
        // ----------------------------------------------------

        do {
            let (view, controller) =
                makeUndoableEditor(
                    "abc"
                )

            let manager =
                try XCTUnwrap(
                    view.undoManager
                )

            let revisionID =
                UUID()

            view.textStorage?
                .addAttribute(
                    .boldWriterTrackChange,
                    value:
                        TrackChanges.marker(
                            id:
                                revisionID,
                            kind:
                                .insertion,
                            author:
                                "Reviewer"
                        ),
                    range:
                        NSRange(
                            location: 1,
                            length: 1
                        )
                )

            let item =
                try XCTUnwrap(
                    TrackChanges.reviewItems(
                        in:
                            view.attributedString()
                    )
                    .first {
                        $0.id
                            == revisionID
                    }
                )

            controller.selectTrackedChange(
                item
            )

            manager.beginUndoGrouping()

            controller
                .acceptTrackedChangeAtSelection()

            manager.endUndoGrouping()

            XCTAssertTrue(
                TrackChanges.reviewItems(
                    in:
                        view.attributedString()
                )
                .isEmpty
            )

            XCTAssertNil(
                controller
                    .selectedReviewChangeID
            )

            XCTAssertTrue(
                manager.canUndo
            )

            manager.undo()

            XCTAssertEqual(
                view.string,
                "abc"
            )

            XCTAssertEqual(
                TrackChanges.reviewItems(
                    in:
                        view.attributedString()
                )
                .map(\.id),
                [revisionID]
            )

            XCTAssertEqual(
                controller
                    .selectedReviewChangeID,
                revisionID
            )

            XCTAssertEqual(
                view.selectedRange(),
                NSRange(
                    location: 1,
                    length: 1
                )
            )

            XCTAssertTrue(
                manager.canRedo
            )

            manager.redo()

            XCTAssertEqual(
                view.string,
                "abc"
            )

            XCTAssertTrue(
                TrackChanges.reviewItems(
                    in:
                        view.attributedString()
                )
                .isEmpty
            )

            XCTAssertNil(
                controller
                    .selectedReviewChangeID
            )
        }

        // ----------------------------------------------------
        // Rejecting an insertion deletes its text.
        // Undo must restore both the text and revision marker.
        // Redo must delete it again.
        // ----------------------------------------------------

        do {
            let (view, controller) =
                makeUndoableEditor(
                    "abc"
                )

            let manager =
                try XCTUnwrap(
                    view.undoManager
                )

            let revisionID =
                UUID()

            view.textStorage?
                .addAttribute(
                    .boldWriterTrackChange,
                    value:
                        TrackChanges.marker(
                            id:
                                revisionID,
                            kind:
                                .insertion,
                            author:
                                "Reviewer"
                        ),
                    range:
                        NSRange(
                            location: 1,
                            length: 1
                        )
                )

            let item =
                try XCTUnwrap(
                    TrackChanges.reviewItems(
                        in:
                            view.attributedString()
                    )
                    .first
                )

            controller.selectTrackedChange(
                item
            )

            manager.beginUndoGrouping()

            controller
                .rejectTrackedChangeAtSelection()

            manager.endUndoGrouping()

            XCTAssertEqual(
                view.string,
                "ac"
            )

            XCTAssertTrue(
                TrackChanges.reviewItems(
                    in:
                        view.attributedString()
                )
                .isEmpty
            )

            manager.undo()

            XCTAssertEqual(
                view.string,
                "abc"
            )

            XCTAssertEqual(
                TrackChanges.reviewItems(
                    in:
                        view.attributedString()
                )
                .map(\.id),
                [revisionID]
            )

            XCTAssertEqual(
                controller
                    .selectedReviewChangeID,
                revisionID
            )

            manager.redo()

            XCTAssertEqual(
                view.string,
                "ac"
            )

            XCTAssertTrue(
                TrackChanges.reviewItems(
                    in:
                        view.attributedString()
                )
                .isEmpty
            )

            XCTAssertNil(
                controller
                    .selectedReviewChangeID
            )
        }

        // ----------------------------------------------------
        // A footnote reference revision and footnote-body
        // revision can occupy the exact same document range.
        //
        // Undo/redo must preserve which one Review selected.
        // ----------------------------------------------------

        do {
            let (view, controller) =
                makeUndoableEditor(
                    "A"
                )

            let manager =
                try XCTUnwrap(
                    view.undoManager
                )

            let referenceID =
                UUID()

            let bodyID =
                UUID()

            var note =
                Footnote(
                    text:
                        "Proposed body",
                    location: 1,
                    length: 1
                )

            note.bodyChangeOriginalText =
                "Original body"

            note.bodyChangeID =
                bodyID

            note.bodyChangeAuthor =
                "Reviewer"

            view.textStorage?
                .append(
                    Footnotes.marker(
                        note,
                        number: 1
                    )
                )

            view.textStorage?
                .addAttribute(
                    .boldWriterTrackChange,
                    value:
                        TrackChanges.marker(
                            id:
                                referenceID,
                            kind:
                                .insertion,
                            author:
                                "Reviewer"
                        ),
                    range:
                        NSRange(
                            location: 1,
                            length: 1
                        )
                )

            let originalItems =
                TrackChanges.reviewItems(
                    in:
                        view.attributedString()
                )

            XCTAssertEqual(
                Set(
                    originalItems
                        .map(\.id)
                ),
                Set(
                    [
                        referenceID,
                        bodyID
                    ]
                )
            )

            let referenceItem =
                try XCTUnwrap(
                    originalItems.first {
                        $0.id
                            == referenceID
                    }
                )

            controller.selectTrackedChange(
                referenceItem
            )

            manager.beginUndoGrouping()

            controller
                .acceptTrackedChangeAtSelection()

            manager.endUndoGrouping()

            XCTAssertEqual(
                TrackChanges.reviewItems(
                    in:
                        view.attributedString()
                )
                .map(\.id),
                [bodyID]
            )

            XCTAssertEqual(
                controller
                    .selectedReviewChangeID,
                bodyID
            )

            manager.undo()

            XCTAssertEqual(
                Set(
                    TrackChanges.reviewItems(
                        in:
                            view.attributedString()
                    )
                    .map(\.id)
                ),
                Set(
                    [
                        referenceID,
                        bodyID
                    ]
                )
            )

            XCTAssertEqual(
                controller
                    .selectedReviewChangeID,
                referenceID
            )

            let restoredNote =
                try XCTUnwrap(
                    Footnotes.records(
                        in:
                            view.attributedString()
                    )
                    .first
                )

            XCTAssertEqual(
                restoredNote.text,
                "Proposed body"
            )

            XCTAssertTrue(
                restoredNote
                    .hasPendingBodyChange
            )

            XCTAssertEqual(
                restoredNote
                    .bodyChangeID,
                bodyID
            )

            manager.redo()

            XCTAssertEqual(
                TrackChanges.reviewItems(
                    in:
                        view.attributedString()
                )
                .map(\.id),
                [bodyID]
            )

            XCTAssertEqual(
                controller
                    .selectedReviewChangeID,
                bodyID
            )

            let bodyItem =
                try XCTUnwrap(
                    TrackChanges.reviewItems(
                        in:
                            view.attributedString()
                    )
                    .first {
                        $0.id
                            == bodyID
                    }
                )

            controller.selectTrackedChange(
                bodyItem
            )

            manager.beginUndoGrouping()

            controller
                .rejectTrackedChangeAtSelection()

            manager.endUndoGrouping()

            let rejectedNote =
                try XCTUnwrap(
                    Footnotes.records(
                        in:
                            view.attributedString()
                    )
                    .first
                )

            XCTAssertEqual(
                rejectedNote.text,
                "Original body"
            )

            XCTAssertFalse(
                rejectedNote
                    .hasPendingBodyChange
            )

            XCTAssertTrue(
                TrackChanges.reviewItems(
                    in:
                        view.attributedString()
                )
                .isEmpty
            )

            manager.undo()

            let undoBodyNote =
                try XCTUnwrap(
                    Footnotes.records(
                        in:
                            view.attributedString()
                    )
                    .first
                )

            XCTAssertEqual(
                undoBodyNote.text,
                "Proposed body"
            )

            XCTAssertEqual(
                undoBodyNote
                    .bodyChangeOriginalText,
                "Original body"
            )

            XCTAssertEqual(
                undoBodyNote
                    .bodyChangeID,
                bodyID
            )

            XCTAssertTrue(
                undoBodyNote
                    .hasPendingBodyChange
            )

            XCTAssertEqual(
                TrackChanges.reviewItems(
                    in:
                        view.attributedString()
                )
                .map(\.id),
                [bodyID]
            )

            XCTAssertEqual(
                controller
                    .selectedReviewChangeID,
                bodyID
            )

            manager.redo()

            let redoBodyNote =
                try XCTUnwrap(
                    Footnotes.records(
                        in:
                            view.attributedString()
                    )
                    .first
                )

            XCTAssertEqual(
                redoBodyNote.text,
                "Original body"
            )

            XCTAssertFalse(
                redoBodyNote
                    .hasPendingBodyChange
            )

            XCTAssertTrue(
                TrackChanges.reviewItems(
                    in:
                        view.attributedString()
                )
                .isEmpty
            )

            XCTAssertNil(
                controller
                    .selectedReviewChangeID
            )
        }
    }


    func testTrackedImageInsertionDeletionReviewAndDOCXRoundTrip()
        throws {

        func imageAttachment()
            throws -> NSTextAttachment {

            let bytes =
                try XCTUnwrap(
                    Data(
                        base64Encoded:
                            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aHksAAAAASUVORK5CYII="
                    )
                )

            let wrapper =
                FileWrapper(
                    regularFileWithContents:
                        bytes
                )

            wrapper.preferredFilename =
                "tracked-image.png"

            return NSTextAttachment(
                fileWrapper:
                    wrapper
            )
        }

        func attachmentAt(
            _ location: Int,
            in text: NSAttributedString
        ) -> NSTextAttachment? {
            guard
                location >= 0,
                location < text.length
            else {
                return nil
            }

            return text.attribute(
                .attachment,
                at:
                    location,
                effectiveRange:
                    nil
            ) as? NSTextAttachment
        }

        // ----------------------------------------------------
        // Rich/image paste becomes one insertion revision.
        // ----------------------------------------------------

        let (
            view,
            controller
        ) =
            makeEditor(
                "AB"
            )

        view.setSelectedRange(
            NSRange(
                location: 1,
                length: 0
            )
        )

        let inserted =
            NSAttributedString(
                attachment:
                    try imageAttachment()
            )

        XCTAssertTrue(
            controller
                .trackAttributedPaste(
                    range:
                        view.selectedRange(),
                    replacement:
                        inserted
                )
        )

        XCTAssertEqual(
            view.string,
            "A\u{FFFC}B"
        )

        XCTAssertNotNil(
            attachmentAt(
                1,
                in:
                    view.attributedString()
            )
        )

        let insertionRecord =
            try XCTUnwrap(
                TrackChanges.records(
                    in:
                        view.attributedString()
                )
                .first
            )

        XCTAssertEqual(
            insertionRecord.kind,
            .insertion
        )

        XCTAssertEqual(
            insertionRecord.location,
            1
        )

        XCTAssertEqual(
            insertionRecord.length,
            1
        )

        let insertionItem =
            try XCTUnwrap(
                TrackChanges.reviewItems(
                    in:
                        view.attributedString()
                )
                .first
            )

        XCTAssertEqual(
            insertionItem.title,
            "Inserted image"
        )

        XCTAssertTrue(
            insertionItem.preview
                .contains(
                    "Image"
                )
        )

        // ----------------------------------------------------
        // DOCX export/import retains both the drawing and its
        // insertion revision.
        // ----------------------------------------------------

        let docx =
            try DOCXExporter.data(
                from:
                    view.attributedString(),
                title:
                    "Tracked image"
            )

        let imported =
            try DOCXImporter.text(
                from:
                    docx
            )

        XCTAssertEqual(
            imported.string,
            "A\u{FFFC}B"
        )

        XCTAssertNotNil(
            attachmentAt(
                1,
                in:
                    imported
            )
        )

        let importedRecord =
            try XCTUnwrap(
                TrackChanges.records(
                    in:
                        imported
                )
                .first
            )

        XCTAssertEqual(
            importedRecord.kind,
            .insertion
        )

        XCTAssertEqual(
            importedRecord.location,
            1
        )

        XCTAssertEqual(
            importedRecord.length,
            1
        )

        XCTAssertEqual(
            TrackChanges.reviewItems(
                in:
                    imported
            )
            .first?
            .title,
            "Inserted image"
        )

        // Accept keeps the image and removes only revision
        // metadata.
        do {
            let (
                acceptedView,
                acceptedController
            ) =
                makeEditor(
                    ""
                )

            acceptedView.textStorage?
                .setAttributedString(
                    imported
                )

            acceptedView.setSelectedRange(
                NSRange(
                    location: 1,
                    length: 1
                )
            )

            acceptedController
                .acceptTrackedChangeAtSelection()

            XCTAssertEqual(
                acceptedView.string,
                "A\u{FFFC}B"
            )

            XCTAssertNotNil(
                attachmentAt(
                    1,
                    in:
                        acceptedView
                            .attributedString()
                )
            )

            XCTAssertTrue(
                TrackChanges.records(
                    in:
                        acceptedView
                            .attributedString()
                )
                .isEmpty
            )
        }

        // Reject removes the inserted image itself.
        do {
            let (
                rejectedView,
                rejectedController
            ) =
                makeEditor(
                    ""
                )

            rejectedView.textStorage?
                .setAttributedString(
                    imported
                )

            rejectedView.setSelectedRange(
                NSRange(
                    location: 1,
                    length: 1
                )
            )

            rejectedController
                .rejectTrackedChangeAtSelection()

            XCTAssertEqual(
                rejectedView.string,
                "AB"
            )

            XCTAssertTrue(
                TrackChanges.records(
                    in:
                        rejectedView
                            .attributedString()
                )
                .isEmpty
            )
        }

        // ----------------------------------------------------
        // Existing image deletion is independently reviewable.
        // ----------------------------------------------------

        do {
            let source =
                NSMutableAttributedString(
                    string:
                        "A"
                )

            source.append(
                NSAttributedString(
                    attachment:
                        try imageAttachment()
                )
            )

            source.append(
                NSAttributedString(
                    string:
                        "B"
                )
            )

            let (
                deletionView,
                deletionController
            ) =
                makeEditor(
                    ""
                )

            deletionView.textStorage?
                .setAttributedString(
                    source
                )

            XCTAssertTrue(
                deletionController
                    .trackTextEdit(
                        range:
                            NSRange(
                                location: 1,
                                length: 1
                            ),
                        replacement:
                            NSAttributedString(
                                string: ""
                            )
                    )
            )

            XCTAssertEqual(
                deletionView.string,
                "A\u{FFFC}B"
            )

            XCTAssertNotNil(
                attachmentAt(
                    1,
                    in:
                        deletionView
                            .attributedString()
                )
            )

            let deletionItem =
                try XCTUnwrap(
                    TrackChanges.reviewItems(
                        in:
                            deletionView
                                .attributedString()
                    )
                    .first
                )

            XCTAssertEqual(
                deletionItem.kind,
                .deletion
            )

            XCTAssertEqual(
                deletionItem.title,
                "Deleted image"
            )

            deletionView.setSelectedRange(
                NSRange(
                    location: 1,
                    length: 1
                )
            )

            deletionController
                .acceptTrackedChangeAtSelection()

            XCTAssertEqual(
                deletionView.string,
                "AB"
            )

            XCTAssertTrue(
                TrackChanges.records(
                    in:
                        deletionView
                            .attributedString()
                )
                .isEmpty
            )
        }

        do {
            let source =
                NSMutableAttributedString(
                    string:
                        "A"
                )

            source.append(
                NSAttributedString(
                    attachment:
                        try imageAttachment()
                )
            )

            source.append(
                NSAttributedString(
                    string:
                        "B"
                )
            )

            let (
                deletionView,
                deletionController
            ) =
                makeEditor(
                    ""
                )

            deletionView.textStorage?
                .setAttributedString(
                    source
                )

            XCTAssertTrue(
                deletionController
                    .trackTextEdit(
                        range:
                            NSRange(
                                location: 1,
                                length: 1
                            ),
                        replacement:
                            NSAttributedString(
                                string: ""
                            )
                    )
            )

            deletionView.setSelectedRange(
                NSRange(
                    location: 1,
                    length: 1
                )
            )

            deletionController
                .rejectTrackedChangeAtSelection()

            XCTAssertEqual(
                deletionView.string,
                "A\u{FFFC}B"
            )

            XCTAssertNotNil(
                attachmentAt(
                    1,
                    in:
                        deletionView
                            .attributedString()
                )
            )

            XCTAssertTrue(
                TrackChanges.records(
                    in:
                        deletionView
                            .attributedString()
                )
                .isEmpty
            )
        }
    }


    func testMetadataAnchorsFollowTrackedInsertionAndDeletionResolution()
        throws {

        let document =
            BOLDWriterDocument()

        document.replaceText(
            with:
                NSAttributedString(
                    string:
                        "ABCDE"
                )
        )

        document.metadata.bookmarks = [
            DocumentBookmark(
                name:
                    "Before E",
                location:
                    4
            )
        ]

        document.metadata.comments = [
            DocumentComment(
                text:
                    "CD",
                location:
                    2,
                length:
                    2
            )
        ]

        let (
            view,
            controller
        ) =
            makeEditor(
                "ABCDE"
            )

        // A tracked insertion physically exists in the backing
        // text, so annotations after it must move immediately.
        XCTAssertTrue(
            controller.trackTextEdit(
                range:
                    NSRange(
                        location:
                            1,
                        length:
                            0
                    ),
                replacement:
                    NSAttributedString(
                        string:
                            "XX"
                    )
            )
        )

        document.replaceEditedText(
            with:
                view.attributedString()
        )

        XCTAssertEqual(
            document.text.string,
            "AXXBCDE"
        )

        XCTAssertEqual(
            document.metadata
                .bookmarks
                .first?
                .location,
            6
        )

        XCTAssertEqual(
            document.metadata
                .comments
                .first?
                .location,
            4
        )

        XCTAssertEqual(
            document.metadata
                .comments
                .first?
                .length,
            2
        )

        view.setSelectedRange(
            NSRange(
                location:
                    1,
                length:
                    2
            )
        )

        controller
            .rejectTrackedChangeAtSelection()

        document.replaceEditedText(
            with:
                view.attributedString()
        )

        XCTAssertEqual(
            document.text.string,
            "ABCDE"
        )

        XCTAssertEqual(
            document.metadata
                .bookmarks
                .first?
                .location,
            4
        )

        XCTAssertEqual(
            document.metadata
                .comments
                .first?
                .location,
            2
        )

        // A tracked deletion leaves the original characters in
        // the document until accepted, so anchor positions must
        // remain unchanged while the deletion is pending.
        XCTAssertTrue(
            controller.trackTextEdit(
                range:
                    NSRange(
                        location:
                            1,
                        length:
                            1
                    ),
                replacement:
                    NSAttributedString(
                        string: ""
                    )
            )
        )

        document.replaceEditedText(
            with:
                view.attributedString()
        )

        XCTAssertEqual(
            document.text.string,
            "ABCDE"
        )

        XCTAssertEqual(
            document.metadata
                .bookmarks
                .first?
                .location,
            4
        )

        XCTAssertEqual(
            document.metadata
                .comments
                .first?
                .location,
            2
        )

        view.setSelectedRange(
            NSRange(
                location:
                    1,
                length:
                    1
            )
        )

        controller
            .acceptTrackedChangeAtSelection()

        document.replaceEditedText(
            with:
                view.attributedString()
        )

        XCTAssertEqual(
            document.text.string,
            "ACDE"
        )

        XCTAssertEqual(
            document.metadata
                .bookmarks
                .first?
                .location,
            3
        )

        XCTAssertEqual(
            document.metadata
                .comments
                .first?
                .location,
            1
        )

        XCTAssertEqual(
            document.metadata
                .comments
                .first?
                .length,
            2
        )
    }


    func testFormattingChangesBecomeSingleReviewableRevision()
        throws {

        func isBold(
            _ text: NSAttributedString,
            at location: Int
        ) throws -> Bool {
            let font =
                try XCTUnwrap(
                    text.attribute(
                        .font,
                        at:
                            location,
                        effectiveRange:
                            nil
                    ) as? NSFont
                )

            return
                NSFontManager.shared
                    .traits(
                        of:
                            font
                    )
                    .contains(
                        .boldFontMask
                    )
        }

        // ----------------------------------------------------
        // Accept keeps the proposed formatting.
        // ----------------------------------------------------

        do {
            let (
                view,
                controller
            ) =
                makeEditor(
                    "Hello"
                )

            controller
                .trackChangesProvider = {
                    true
                }

            view.setSelectedRange(
                NSRange(
                    location: 0,
                    length: 5
                )
            )

            controller.toggleTrait(
                .boldFontMask
            )

            XCTAssertEqual(
                view.string,
                "HelloHello"
            )

            let records =
                TrackChanges.records(
                    in:
                        view
                            .attributedString()
                )

            XCTAssertEqual(
                records.count,
                2
            )

            XCTAssertEqual(
                Set(
                    records.map(
                        \.id
                    )
                )
                .count,
                1
            )

            XCTAssertEqual(
                records.map(
                    \.kind
                ),
                [
                    .deletion,
                    .insertion
                ]
            )

            XCTAssertFalse(
                try isBold(
                    view.attributedString(),
                    at: 0
                )
            )

            XCTAssertTrue(
                try isBold(
                    view.attributedString(),
                    at: 5
                )
            )

            let items =
                TrackChanges.reviewItems(
                    in:
                        view
                            .attributedString()
                )

            XCTAssertEqual(
                items.count,
                1
            )

            let item =
                try XCTUnwrap(
                    items.first
                )

            XCTAssertEqual(
                item.kind,
                .formatting
            )

            XCTAssertEqual(
                item.title,
                "Formatting change"
            )

            XCTAssertEqual(
                item.preview,
                "Hello"
            )

            controller
                .selectTrackedChange(
                    item
                )

            controller
                .acceptTrackedChangeAtSelection()

            XCTAssertEqual(
                view.string,
                "Hello"
            )

            XCTAssertTrue(
                try isBold(
                    view.attributedString(),
                    at: 0
                )
            )

            XCTAssertTrue(
                TrackChanges.records(
                    in:
                        view
                            .attributedString()
                )
                .isEmpty
            )
        }

        // ----------------------------------------------------
        // Reject restores the original formatting.
        // ----------------------------------------------------

        do {
            let (
                view,
                controller
            ) =
                makeEditor(
                    "Hello"
                )

            controller
                .trackChangesProvider = {
                    true
                }

            view.setSelectedRange(
                NSRange(
                    location: 0,
                    length: 5
                )
            )

            controller.toggleTrait(
                .boldFontMask
            )

            let item =
                try XCTUnwrap(
                    TrackChanges.reviewItems(
                        in:
                            view
                                .attributedString()
                    )
                    .first
                )

            controller
                .selectTrackedChange(
                    item
                )

            controller
                .rejectTrackedChangeAtSelection()

            XCTAssertEqual(
                view.string,
                "Hello"
            )

            XCTAssertFalse(
                try isBold(
                    view.attributedString(),
                    at: 0
                )
            )

            XCTAssertTrue(
                TrackChanges.records(
                    in:
                        view
                            .attributedString()
                )
                .isEmpty
            )
        }

        // ----------------------------------------------------
        // Paragraph formatting is tracked too.
        // ----------------------------------------------------

        do {
            let (
                view,
                controller
            ) =
                makeEditor(
                    "Alpha\nBeta"
                )

            controller
                .trackChangesProvider = {
                    true
                }

            view.setSelectedRange(
                NSRange(
                    location: 1,
                    length: 0
                )
            )

            controller.setAlignment(
                .center
            )

            XCTAssertEqual(
                view.string,
                "Alpha\nAlpha\nBeta"
            )

            let item =
                try XCTUnwrap(
                    TrackChanges.reviewItems(
                        in:
                            view
                                .attributedString()
                    )
                    .first
                )

            XCTAssertEqual(
                item.kind,
                .formatting
            )

            controller
                .selectTrackedChange(
                    item
                )

            controller
                .acceptTrackedChangeAtSelection()

            XCTAssertEqual(
                view.string,
                "Alpha\nBeta"
            )

            let paragraph =
                try XCTUnwrap(
                    view.attributedString()
                        .attribute(
                            .paragraphStyle,
                            at: 0,
                            effectiveRange:
                                nil
                        )
                        as? NSParagraphStyle
                )

            XCTAssertEqual(
                paragraph.alignment,
                .center
            )
        }
    }

    func testFormattingRevisionDOCXRoundTripPreservesGrouping()
        throws {

        let (
            view,
            controller
        ) =
            makeEditor(
                "Hello"
            )

        controller
            .trackChangesProvider = {
                true
            }

        view.setSelectedRange(
            NSRange(
                location: 0,
                length: 5
            )
        )

        controller.toggleUnderline()

        let before =
            TrackChanges.records(
                in:
                    view
                        .attributedString()
            )

        XCTAssertEqual(
            before.count,
            2
        )

        XCTAssertEqual(
            Set(
                before.map(
                    \.id
                )
            )
            .count,
            1
        )

        let data =
            try DOCXExporter.data(
                from:
                    view
                        .attributedString(),
                title:
                    "Formatting Revision"
            )

        let restored =
            try DOCXImporter.text(
                from:
                    data
            )

        XCTAssertEqual(
            restored.string,
            "HelloHello"
        )

        let records =
            TrackChanges.records(
                in:
                    restored
            )

        XCTAssertEqual(
            records.count,
            2
        )

        XCTAssertEqual(
            Set(
                records.map(
                    \.id
                )
            )
            .count,
            1
        )

        let items =
            TrackChanges.reviewItems(
                in:
                    restored
            )

        XCTAssertEqual(
            items.count,
            1
        )

        XCTAssertEqual(
            items.first?.kind,
            .formatting
        )

        XCTAssertEqual(
            items.first?.title,
            "Formatting change"
        )

        let (
            acceptedView,
            acceptedController
        ) =
            makeEditor(
                ""
            )

        acceptedView.textStorage?
            .setAttributedString(
                restored
            )

        let item =
            try XCTUnwrap(
                TrackChanges.reviewItems(
                    in:
                        acceptedView
                            .attributedString()
                )
                .first
            )

        acceptedController
            .selectTrackedChange(
                item
            )

        acceptedController
            .acceptTrackedChangeAtSelection()

        XCTAssertEqual(
            acceptedView.string,
            "Hello"
        )

        XCTAssertEqual(
            acceptedView
                .attributedString()
                .attribute(
                    .underlineStyle,
                    at: 0,
                    effectiveRange:
                        nil
                ) as? Int,
            NSUnderlineStyle
                .single
                .rawValue
        )

        XCTAssertTrue(
            TrackChanges.records(
                in:
                    acceptedView
                        .attributedString()
            )
            .isEmpty
        )
    }


    @MainActor
    func testPasteboardReadRoutesRichDropThroughTrackChanges()
        throws {

        let storage =
            NSTextStorage(
                attributedString:
                    NSAttributedString(
                        string:
                            "AB",
                        attributes: [
                            .font:
                                NSFont.systemFont(
                                    ofSize: 15
                                )
                        ]
                    )
            )

        let layoutManager =
            NSLayoutManager()

        storage.addLayoutManager(
            layoutManager
        )

        let textContainer =
            NSTextContainer(
                size:
                    NSSize(
                        width: 600,
                        height: 400
                    )
            )

        layoutManager.addTextContainer(
            textContainer
        )

        let view =
            WritingTextView(
                frame:
                    NSRect(
                        x: 0,
                        y: 0,
                        width: 600,
                        height: 400
                    ),
                textContainer:
                    textContainer
            )

        view.typingAttributes = [
            .font:
                NSFont.systemFont(
                    ofSize: 15
                )
        ]

        let controller =
            EditorController()

        controller.attach(
            view
        )

        view.trackChangesProvider = {
            true
        }

        view.trackAttributedPaste = {
            replacement,
            range in

            controller.attach(
                view
            )

            return controller
                .trackAttributedPaste(
                    range:
                        range,
                    replacement:
                        replacement
                )
        }

        view.setSelectedRange(
            NSRange(
                location: 1,
                length: 0
            )
        )

        let dropped =
            NSAttributedString(
                string:
                    "X",
                attributes: [
                    .font:
                        NSFont.boldSystemFont(
                            ofSize: 15
                        )
                ]
            )

        let rtf =
            try dropped.data(
                from:
                    NSRange(
                        location: 0,
                        length:
                            dropped.length
                    ),
                documentAttributes: [
                    .documentType:
                        NSAttributedString
                            .DocumentType
                            .rtf
                ]
            )

        let pasteboard =
            NSPasteboard(
                name:
                    NSPasteboard.Name(
                        "com.boldwriter.tests.tracked-drop"
                    )
            )

        pasteboard.clearContents()

        XCTAssertTrue(
            pasteboard.setData(
                rtf,
                forType:
                    .rtf
            )
        )

        XCTAssertTrue(
            view.readSelection(
                from:
                    pasteboard,
                type:
                    .rtf
            )
        )

        XCTAssertEqual(
            view.string,
            "AXB"
        )

        let records =
            TrackChanges.records(
                in:
                    view.attributedString()
            )

        XCTAssertEqual(
            records.count,
            1
        )

        let record =
            try XCTUnwrap(
                records.first
            )

        XCTAssertEqual(
            record.kind,
            .insertion
        )

        XCTAssertEqual(
            record.location,
            1
        )

        XCTAssertEqual(
            record.length,
            1
        )

        let font =
            try XCTUnwrap(
                view.attributedString()
                    .attribute(
                        .font,
                        at:
                            1,
                        effectiveRange:
                            nil
                    )
                    as? NSFont
            )

        XCTAssertTrue(
            NSFontManager.shared
                .traits(
                    of:
                        font
                )
                .contains(
                    .boldFontMask
                )
        )

        // Accepting the dropped insertion keeps it normally.
        view.setSelectedRange(
            NSRange(
                location: 1,
                length: 1
            )
        )

        controller
            .acceptTrackedChangeAtSelection()

        XCTAssertEqual(
            view.string,
            "AXB"
        )

        XCTAssertTrue(
            TrackChanges.records(
                in:
                    view.attributedString()
            )
            .isEmpty
        )
    }


    @MainActor
    func testCutCopiesSelectionAndCreatesTrackedDeletion() {
        let storage =
            NSTextStorage(
                attributedString:
                    NSAttributedString(
                        string:
                            "Hello",
                        attributes: [
                            .font:
                                NSFont.systemFont(
                                    ofSize: 15
                                )
                        ]
                    )
            )

        let layoutManager =
            NSLayoutManager()

        storage.addLayoutManager(
            layoutManager
        )

        let textContainer =
            NSTextContainer(
                size:
                    NSSize(
                        width: 600,
                        height: 400
                    )
            )

        layoutManager.addTextContainer(
            textContainer
        )

        let view =
            WritingTextView(
                frame:
                    NSRect(
                        x: 0,
                        y: 0,
                        width: 600,
                        height: 400
                    ),
                textContainer:
                    textContainer
            )

        let undoManager =
            UndoManager()

        undoManager
            .groupsByEvent =
                false

        view.sessionUndoManager =
            undoManager

        let controller =
            EditorController()

        controller.attach(
            view
        )

        view.tableController =
            controller

        view.trackChangesProvider = {
            true
        }

        view.setSelectedRange(
            NSRange(
                location: 1,
                length: 3
            )
        )

        NSPasteboard.general
            .clearContents()

        // groupsByEvent is disabled so the test supplies the event
        // group that a real Edit > Cut command normally receives.
        undoManager.beginUndoGrouping()

        view.cut(nil)

        undoManager.endUndoGrouping()

        XCTAssertEqual(
            NSPasteboard.general
                .string(
                    forType:
                        .string
                ),
            "ell"
        )

        // A tracked Cut leaves the original characters visible
        // until the deletion is accepted.
        XCTAssertEqual(
            view.string,
            "Hello"
        )

        let records =
            TrackChanges.records(
                in:
                    view.attributedString()
            )

        XCTAssertEqual(
            records.count,
            1
        )

        let deletion =
            records.first

        XCTAssertEqual(
            deletion?.kind,
            .deletion
        )

        XCTAssertEqual(
            deletion?.location,
            1
        )

        XCTAssertEqual(
            deletion?.length,
            3
        )

        XCTAssertEqual(
            undoManager
                .undoActionName,
            "Cut"
        )

        XCTAssertTrue(
            undoManager.canUndo
        )

        undoManager.undo()

        XCTAssertEqual(
            view.string,
            "Hello"
        )

        XCTAssertTrue(
            TrackChanges.records(
                in:
                    view.attributedString()
            )
            .isEmpty
        )

        XCTAssertFalse(
            undoManager.canUndo
        )

        XCTAssertTrue(
            undoManager.canRedo
        )

        XCTAssertEqual(
            undoManager
                .redoActionName,
            "Cut"
        )

        undoManager.redo()

        XCTAssertEqual(
            TrackChanges.records(
                in:
                    view.attributedString()
            )
            .count,
            1
        )

        XCTAssertEqual(
            view.string,
            "Hello"
        )

        XCTAssertFalse(
            undoManager.canRedo
        )
    }


    @MainActor
    func testTrackChangesForcesInternalTextDragToCopyOnly() {
        let view =
            WritingTextView(
                frame:
                    NSRect(
                        x: 0,
                        y: 0,
                        width: 600,
                        height: 400
                    )
            )

        let nativeMask:
            NSDragOperation = [
                .copy,
                .move
            ]

        // Normal editing preserves NSTextView's native operation
        // choices, including MOVE.
        view.trackChangesProvider = {
            false
        }

        let ordinaryMask =
            view.constrainedDragSourceOperationMask(
                nativeMask
            )

        XCTAssertTrue(
            ordinaryMask.contains(
                .copy
            )
        )

        XCTAssertTrue(
            ordinaryMask.contains(
                .move
            )
        )

        // Under Track Changes, MOVE would let AppKit physically
        // remove the source selection outside BOLD's revision
        // engine. Force the drag to COPY instead.
        view.trackChangesProvider = {
            true
        }

        let trackedMask =
            view.constrainedDragSourceOperationMask(
                nativeMask
            )

        XCTAssertEqual(
            trackedMask,
            .copy
        )

        XCTAssertTrue(
            trackedMask.contains(
                .copy
            )
        )

        XCTAssertFalse(
            trackedMask.contains(
                .move
            )
        )

        // Even if AppKit reports only MOVE as the native option,
        // BOLD still offers safe COPY semantics rather than allowing
        // an invisible source deletion.
        XCTAssertEqual(
            view.constrainedDragSourceOperationMask(
                .move
            ),
            .copy
        )
    }

}
