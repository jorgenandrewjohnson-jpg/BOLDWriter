import AppKit
import XCTest
@testable import BOLDWriter

@MainActor
final class EndnotePersistenceTests: XCTestCase {
    private func reopen(_ text: NSAttributedString, tracking: Bool = false) throws -> BOLDWriterDocument {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".boldwriter")
        defer { try? FileManager.default.removeItem(at: url) }
        var metadata = DocumentMetadata()
        metadata.trackChangesEnabled = tracking
        try BOLDWriterDocument.packageWrapper(text: text, metadata: metadata).write(to: url, options: .atomic, originalContentsURL: nil)
        return try BOLDWriterDocument(fileWrapper: FileWrapper(url: url), contentType: .boldWriterDocument)
    }

    private func editor(_ text: NSAttributedString = NSAttributedString(string: "Body")) -> (EditorController, WritingTextView, UndoManager) {
        let view = WritingTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 800))
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        view.sessionUndoManager = undoManager
        view.allowsUndo = true
        view.textStorage?.setAttributedString(text)
        view.setSelectedRange(NSRange(location: text.length, length: 0))
        let controller = EditorController()
        controller.attach(view)
        return (controller, view, undoManager)
    }

    func testEndnoteNativeSaveReopenAndEditSaveReopen() throws {
        let (controller, view, _) = editor()
        controller.insertEndnote(text: "Original note")
        let first = try XCTUnwrap(Endnotes.records(in: view.attributedString()).first)
        let reopened = try reopen(view.attributedString())
        let restored = try XCTUnwrap(Endnotes.records(in: reopened.text).first)
        XCTAssertEqual(restored.id, first.id)
        XCTAssertEqual(restored.text, "Original note")

        let (editController, editView, _) = editor(reopened.text)
        editController.updateEndnote(id: restored.id, text: "Edited — Ω & <note>", trackChanges: false)
        let second = try reopen(editView.attributedString())
        let final = try XCTUnwrap(Endnotes.records(in: second.text).first)
        XCTAssertEqual(final.id, first.id)
        XCTAssertEqual(final.text, "Edited — Ω & <note>")
        let docx = try DOCXExporter.data(from: second.text, title: "Round trip")
        let imported = try DOCXImporter.text(from: docx)
        XCTAssertEqual(try Endnotes.records(in: imported).map(\.text), [final.text])
    }

    func testMultipleEndnotesKeepOrderLocationsIdentityAndBodiesAcrossPersistence() throws {
        let (controller, view, _) = editor()
        controller.insertEndnote(text: "First")
        view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
        controller.insertEndnote(text: "Second")
        view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
        controller.insertEndnote(text: "Third")
        let before = try Endnotes.records(in: view.attributedString())
        let after = try Endnotes.records(in: reopen(view.attributedString()).text)
        XCTAssertEqual(after.map(\.id), before.map(\.id))
        XCTAssertEqual(after.map(\.text), ["First", "Second", "Third"])
        XCTAssertEqual(after.map(\.location), before.map(\.location))
        XCTAssertEqual(after.map(\.length), [1, 1, 1])
    }

    func testTrackedEndnoteBodyEditPersistsReviewAndResolvesAfterReopen() throws {
        let (controller, view, _) = editor()
        controller.insertEndnote(text: "Before")
        let note = try XCTUnwrap(Endnotes.records(in: view.attributedString()).first)
        controller.updateEndnote(id: note.id, text: "After", trackChanges: true)
        let reopened = try reopen(view.attributedString(), tracking: true)
        let persisted = try XCTUnwrap(Endnotes.records(in: reopened.text).first)
        XCTAssertEqual(persisted.bodyChangeOriginalText, "Before")
        XCTAssertTrue(TrackChanges.reviewItems(in: reopened.text).contains { $0.kind == .endnoteBodyEdit })

        for accept in [true, false] {
            let (resolution, resolutionView, _) = editor(reopened.text)
            let item = try XCTUnwrap(TrackChanges.reviewItems(in: resolutionView.attributedString()).first { $0.kind == .endnoteBodyEdit })
            resolution.selectTrackedChange(item)
            if accept { resolution.acceptTrackedChangeAtSelection() } else { resolution.rejectTrackedChangeAtSelection() }
            let result = try XCTUnwrap(Endnotes.records(in: resolutionView.attributedString()).first)
            XCTAssertEqual(result.text, accept ? "After" : "Before")
            XCTAssertFalse(result.hasPendingBodyChange)
        }
    }

    func testTrackedEndnoteInsertionAndDeletionSurviveReopenAndResolve() throws {
        let (controller, view, _) = editor()
        controller.insertEndnote(text: "Tracked insertion", trackChanges: true)
        let inserted = try XCTUnwrap(Endnotes.records(in: view.attributedString()).first)
        let reopened = try reopen(view.attributedString(), tracking: true)
        XCTAssertEqual(try Endnotes.records(in: reopened.text).first?.id, inserted.id)
        let (rejector, rejectView, _) = editor(reopened.text)
        rejector.rejectAllTrackedChanges()
        XCTAssertTrue(try Endnotes.records(in: rejectView.attributedString()).isEmpty)

        let (deleter, deleteView, _) = editor()
        deleter.insertEndnote(text: "Tracked deletion")
        let original = try XCTUnwrap(Endnotes.records(in: deleteView.attributedString()).first)
        deleter.deleteEndnote(id: original.id, trackChanges: true)
        let deletionReopen = try reopen(deleteView.attributedString(), tracking: true)
        let (restorer, restoredView, _) = editor(deletionReopen.text)
        restorer.rejectAllTrackedChanges()
        XCTAssertEqual(try Endnotes.records(in: restoredView.attributedString()).first?.id, original.id)
        let (acceptor, acceptView, _) = editor(deletionReopen.text)
        acceptor.acceptAllTrackedChanges()
        XCTAssertTrue(try Endnotes.records(in: acceptView.attributedString()).isEmpty)
    }

    func testMalformedAndDuplicateEndnoteReferencesFailSafely() throws {
        for payload in [["id": "bad", "text": "Note"], ["id": UUID().uuidString, "text": "Note"]] {
            let malformed = NSMutableAttributedString(string: "Body1")
            malformed.addAttribute(.endnote, value: payload, range: NSRange(location: 4, length: 1))
            if payload["id"] == "bad" {
                XCTAssertThrowsError(try Endnotes.records(in: malformed))
                XCTAssertThrowsError(try BOLDWriterDocument.packageWrapper(text: malformed, metadata: DocumentMetadata()))
            }
        }
        let duplicate = NSMutableAttributedString(string: "Body12")
        let id = UUID().uuidString
        // Distinguish adjacent attributed runs so Foundation doesn't coalesce
        // identical payloads into one two-digit reference.
        duplicate.addAttribute(.endnote, value: ["id": id, "text": "First"], range: NSRange(location: 4, length: 1))
        duplicate.addAttribute(.endnote, value: ["id": id, "text": "Second"], range: NSRange(location: 5, length: 1))
        XCTAssertThrowsError(try Endnotes.records(in: duplicate))
        XCTAssertEqual(String(duplicate.string.prefix(4)), "Body")
    }

    func testReplaceAllOnEndnoteMarkerRemovesNoteSafely() throws {
        let (controller, view, undoManager) = editor()
        controller.insertEndnote(text: "Marker note")
        controller.replaceAll([NSRange(location: 4, length: 1)], with: "replacement")
        XCTAssertEqual(view.string, "Bodyreplacement")
        XCTAssertTrue(try Endnotes.records(in: view.attributedString()).isEmpty)

        undoManager.undo()
        XCTAssertEqual(try Endnotes.records(in: view.attributedString()).first?.text, "Marker note")
    }
}
