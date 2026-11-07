import AppKit
import XCTest
@testable import BOLDWriter

@MainActor
final class AISafetyTests: XCTestCase {
    func testSelectionContextSendsOnlySelection() {
        let document = BOLDWriterDocument()
        document.replaceText(with: NSAttributedString(string: "First paragraph.\nSecond paragraph."))
        let editor = EditorController()
        editor.selection = NSRange(location: 6, length: 9)
        let manager = AIManager()
        manager.scope = .selection
        let context = manager.makeContext(document: document, editor: editor)
        XCTAssertEqual(context.text, "paragraph")
        XCTAssertEqual(context.range, editor.selection)
    }

    func testParagraphScopeIsBounded() {
        let document = BOLDWriterDocument()
        document.replaceText(with: NSAttributedString(string: "First paragraph.\nSecond paragraph."))
        let editor = EditorController()
        editor.selection = NSRange(location: 20, length: 0)
        let manager = AIManager()
        manager.scope = .paragraph
        XCTAssertEqual(manager.makeContext(document: document, editor: editor).text, "Second paragraph.")
    }

    func testStaleProposalIsRejected() {
        let document = BOLDWriterDocument()
        document.replaceText(with: NSAttributedString(string: "Original"))
        let editor = EditorController()
        let manager = AIManager()
        manager.proposal = AIEditProposal(operation: .replaceSelection, range: NSRange(location: 0, length: 8), originalText: "Original", replacementText: "Changed", summary: "Test", documentRevisionID: UUID())
        XCTAssertThrowsError(try manager.applyProposal(document: document, editor: editor))
        XCTAssertEqual(document.text.string, "Original")
        XCTAssertEqual(document.metadata.revisions.count, 0)
    }

    func testDocumentChangeWhileAIRequestIsInFlightRejectsProposal() async {
        let document = BOLDWriterDocument()
        document.replaceText(with: NSAttributedString(string: "Original writing"))
        let editor = EditorController()
        editor.selection = NSRange(location: 0, length: document.text.length)
        let manager = AIManager()
        manager.command = "Improve this writing"
        let provider = SuspendedAIProvider()

        let request = Task { await manager.requestProposal(document: document, editor: editor, provider: provider) }
        await provider.waitUntilRequested()
        XCTAssertTrue(manager.isWorking)
        document.replaceText(with: NSAttributedString(string: "Newer writing typed while waiting"))
        await provider.resolve(operation: .replaceSelection, replacement: "Old AI replacement")
        await request.value

        XCTAssertNil(manager.proposal)
        XCTAssertFalse(manager.isWorking)
        XCTAssertTrue(manager.errorMessage?.contains("document changed") == true)
        XCTAssertEqual(document.text.string, "Newer writing typed while waiting")
        XCTAssertTrue(document.metadata.revisions.isEmpty)
    }

    func testInsertProposalUsesCaretAndCommandCapturedBeforeAwait() async throws {
        let document = BOLDWriterDocument()
        document.replaceText(with: NSAttributedString(string: "Original writing"))
        let editor = EditorController()
        editor.selection = NSRange(location: 4, length: 0)
        let manager = AIManager()
        manager.command = "Original command"
        let provider = SuspendedAIProvider()

        let request = Task { await manager.requestProposal(document: document, editor: editor, provider: provider) }
        await provider.waitUntilRequested()
        editor.selection = NSRange(location: 12, length: 0)
        manager.command = "Different command"
        await provider.resolve(operation: .insertAtCursor, replacement: "New words")
        await request.value

        let proposal = try XCTUnwrap(manager.proposal)
        XCTAssertEqual(proposal.range, NSRange(location: 4, length: 0))
        XCTAssertEqual(proposal.originalText, "")
        XCTAssertEqual(proposal.documentRevisionID, document.revisionID)
        let requestedCommand = await provider.requestedCommand
        XCTAssertEqual(requestedCommand, "Original command")
        XCTAssertEqual(document.text.string, "Original writing")
        XCTAssertTrue(document.metadata.revisions.isEmpty)
    }

    func testMalformedProposalRangesAreRejectedWithoutChangesOrRecoverySnapshots() {
        let document = BOLDWriterDocument()
        document.replaceText(with: NSAttributedString(string: "Original"))
        let editor = EditorController()
        let manager = AIManager()
        let ranges = [
            NSRange(location: -1, length: 0),
            NSRange(location: 0, length: -1),
            NSRange(location: Int.max, length: 1),
            NSRange(location: 1, length: Int.max),
            NSRange(location: 9, length: 0),
            NSRange(location: 7, length: 2)
        ]
        for range in ranges {
            manager.proposal = AIEditProposal(operation: .replaceSelection, range: range, originalText: "", replacementText: "Unsafe replacement", summary: "Malformed range", documentRevisionID: document.revisionID)
            XCTAssertThrowsError(try manager.applyProposal(document: document, editor: editor), "Accepted invalid range \(range)")
            XCTAssertEqual(document.text.string, "Original")
            XCTAssertTrue(document.metadata.revisions.isEmpty)
        }
    }

    func testChangedOriginalTextIsRejectedEvenWithMatchingRevisionIdentifier() {
        let document = BOLDWriterDocument()
        document.replaceText(with: NSAttributedString(string: "Original"))
        let manager = AIManager()
        manager.proposal = AIEditProposal(operation: .replaceSelection, range: NSRange(location: 0, length: 8), originalText: "Mismatch", replacementText: "Changed", summary: "Mismatch", documentRevisionID: document.revisionID)
        XCTAssertThrowsError(try manager.applyProposal(document: document, editor: EditorController()))
        XCTAssertEqual(document.text.string, "Original")
        XCTAssertTrue(document.metadata.revisions.isEmpty)
    }

    func testApplyingAIProposalWithTrackChangesCreatesReviewableUndoableEdit()
        throws {

        let original =
            NSAttributedString(
                string:
                    "Original",
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize: 15
                        )
                ]
            )

        let document =
            BOLDWriterDocument()

        document.replaceText(
            with:
                original
        )

        document.metadata
            .trackChangesEnabled =
                true

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

        let undoManager =
            UndoManager()

        undoManager
            .groupsByEvent =
                false

        view.sessionUndoManager =
            undoManager

        view.textStorage?
            .setAttributedString(
                document.text
            )

        let editor =
            EditorController()

        editor.attach(
            view
        )

        let manager =
            AIManager()

        manager.proposal =
            AIEditProposal(
                operation:
                    .replaceSelection,
                range:
                    NSRange(
                        location: 0,
                        length: 8
                    ),
                originalText:
                    "Original",
                replacementText:
                    "Improved",
                summary:
                    "Improve wording",
                documentRevisionID:
                    document.revisionID
            )

        XCTAssertTrue(
            document.metadata
                .revisions
                .isEmpty
        )

        // groupsByEvent is intentionally disabled in this test
        // so undo boundaries are deterministic. Simulate the one
        // AppKit event that would normally contain the Apply click.
        undoManager.beginUndoGrouping()

        do {
            try manager.applyProposal(
                document:
                    document,
                editor:
                    editor
            )

            undoManager.endUndoGrouping()
        } catch {
            undoManager.endUndoGrouping()
            throw error
        }

        // AI edits create a recovery point before mutation.
        XCTAssertEqual(
            document.metadata
                .revisions
                .count,
            1
        )

        XCTAssertNil(
            manager.proposal
        )

        // Track Changes keeps the original visible and appends
        // the proposed replacement as a separate insertion.
        XCTAssertEqual(
            view.string,
            "OriginalImproved"
        )

        let records =
            TrackChanges.records(
                in:
                    view.attributedString()
            )

        XCTAssertEqual(
            records.count,
            2
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

        let items =
            TrackChanges.reviewItems(
                in:
                    view.attributedString()
            )

        XCTAssertEqual(
            items.count,
            2
        )

        XCTAssertTrue(
            items.contains {
                $0.kind
                    == .deletion
            }
        )

        XCTAssertTrue(
            items.contains {
                $0.kind
                    == .insertion
            }
        )

        let tracked =
            view.attributedString()
                .copy()
                as! NSAttributedString

        // Even though the underlying mutation is a tracked edit,
        // the user initiated an AI command, so the Edit menu must
        // identify it as such.
        XCTAssertEqual(
            undoManager
                .undoActionName,
            "AI Edit"
        )

        XCTAssertTrue(
            undoManager.canUndo
        )

        undoManager.undo()

        XCTAssertTrue(
            original.isEqual(
                to:
                    view.attributedString()
            )
        )

        XCTAssertTrue(
            TrackChanges.records(
                in:
                    view.attributedString()
            )
            .isEmpty
        )

        // Applying one AI proposal is exactly one undo command.
        XCTAssertFalse(
            undoManager.canUndo
        )

        XCTAssertTrue(
            undoManager.canRedo
        )

        XCTAssertEqual(
            undoManager
                .redoActionName,
            "AI Edit"
        )

        undoManager.redo()

        XCTAssertTrue(
            tracked.isEqual(
                to:
                    view.attributedString()
            )
        )

        XCTAssertEqual(
            TrackChanges.records(
                in:
                    view.attributedString()
            )
            .count,
            2
        )

        XCTAssertFalse(
            undoManager.canRedo
        )

        // The tracked AI result participates in the same review
        // workflow as a human edit.
        //
        // This test disables groupsByEvent for deterministic undo
        // assertions, so explicitly provide the AppKit-style event
        // group for the final review command as well.
        undoManager.beginUndoGrouping()

        editor.acceptAllTrackedChanges()

        undoManager.endUndoGrouping()

        XCTAssertEqual(
            view.string,
            "Improved"
        )

        XCTAssertTrue(
            TrackChanges.records(
                in:
                    view.attributedString()
            )
            .isEmpty
        )
    }

}

private actor SuspendedAIProvider: AIProvider {
    private var responseContinuation: CheckedContinuation<(operation: AIEditOperation, replacement: String, summary: String), Error>?
    private var startedContinuations: [CheckedContinuation<Void, Never>] = []
    private(set) var requestedCommand: String?

    func propose(command: String, context: AIContext) async throws -> (operation: AIEditOperation, replacement: String, summary: String) {
        requestedCommand = command
        return try await withCheckedThrowingContinuation { continuation in
            responseContinuation = continuation
            for waiter in startedContinuations { waiter.resume() }
            startedContinuations.removeAll()
        }
    }

    func waitUntilRequested() async {
        if responseContinuation != nil { return }
        await withCheckedContinuation { startedContinuations.append($0) }
    }

    func resolve(operation: AIEditOperation, replacement: String) {
        responseContinuation?.resume(returning: (operation, replacement, "Mock proposal"))
        responseContinuation = nil
    }

    func testConnection() async throws {}
}
