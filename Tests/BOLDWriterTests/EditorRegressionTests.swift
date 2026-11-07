import AppKit
import CryptoKit
import XCTest
@testable import BOLDWriter

@MainActor
private final class RegressionTextView: NSTextView {
    let regressionUndoManager = UndoManager()
    override var undoManager: UndoManager? { regressionUndoManager }
}

@MainActor
final class EditorRegressionTests: XCTestCase {
    private func makeEditor(
        text: NSAttributedString,
        selection: NSRange
    ) -> (EditorController, RegressionTextView) {
        let view = RegressionTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 500))
        view.isRichText = true
        view.allowsUndo = true
        view.regressionUndoManager.groupsByEvent = false
        view.regressionUndoManager.disableUndoRegistration()
        view.textStorage?.setAttributedString(text)
        view.setSelectedRange(selection)
        view.regressionUndoManager.enableUndoRegistration()
        view.regressionUndoManager.removeAllActions()
        let editor = EditorController()
        editor.attach(view)
        return (editor, view)
    }

    private func groupedMutation(_ view: RegressionTextView, _ operation: () -> Void) {
        view.regressionUndoManager.beginUndoGrouping()
        operation()
        view.regressionUndoManager.endUndoGrouping()
    }

    private func styledText(_ string: String) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [
            .font: NSFont.systemFont(ofSize: 15),
            .foregroundColor: NSColor.textColor,
            .boldWriterStyle: WriterStyle.normal.rawValue
        ])
    }

    func testCaretFormattingLeavesEmptyAndExistingDocumentsUntouched() throws {
        for (string, caret) in [("", 0), ("Existing text", 0), ("Existing text", 5), ("Existing text", 13)] {
            let (editor, view) = makeEditor(text: styledText(string), selection: NSRange(location: caret, length: 0))
            let before = view.attributedString().copy() as! NSAttributedString
            view.typingAttributes = [.font: NSFont.systemFont(ofSize: 15)]

            editor.toggleUnderline()
            XCTAssertEqual(view.typingAttributes[.underlineStyle] as? Int, NSUnderlineStyle.single.rawValue)
            editor.toggleStrikethrough()
            XCTAssertEqual(view.typingAttributes[.strikethroughStyle] as? Int, NSUnderlineStyle.single.rawValue)
            editor.toggleTrait(.boldFontMask)
            let boldFont = try XCTUnwrap(view.typingAttributes[.font] as? NSFont)
            XCTAssertTrue(NSFontManager.shared.traits(of: boldFont).contains(.boldFontMask))
            editor.setFontSize(28)
            XCTAssertEqual((view.typingAttributes[.font] as? NSFont)?.pointSize, 28)

            XCTAssertTrue(before.isEqual(to: view.attributedString()), "Caret formatting changed existing text at \(caret) in \(string)")
            XCTAssertEqual(view.selectedRange(), NSRange(location: caret, length: 0))
            XCTAssertFalse(view.regressionUndoManager.canUndo)

            editor.toggleUnderline()
            editor.toggleStrikethrough()
            editor.toggleTrait(.boldFontMask)
            XCTAssertEqual(view.typingAttributes[.underlineStyle] as? Int, 0)
            XCTAssertEqual(view.typingAttributes[.strikethroughStyle] as? Int, 0)
            let regularFont = try XCTUnwrap(view.typingAttributes[.font] as? NSFont)
            XCTAssertFalse(NSFontManager.shared.traits(of: regularFont).contains(.boldFontMask))
            XCTAssertTrue(before.isEqual(to: view.attributedString()))
        }
    }

    func testSelectedUnderlineSupportsUndoAndRedo() {
        assertSelectedFormattingUndoRedo { $0.toggleUnderline() }
    }

    func testSelectedStrikethroughSupportsUndoAndRedo() {
        assertSelectedFormattingUndoRedo { $0.toggleStrikethrough() }
    }

    func testSelectedBoldSupportsUndoAndRedo() {
        assertSelectedFormattingUndoRedo { $0.toggleTrait(.boldFontMask) }
    }

    func testSelectedFontSizeSupportsUndoAndRedo() {
        assertSelectedFormattingUndoRedo { $0.setFontSize(24) }
    }

    func testRemovingHighlightClearsAttributeAndSupportsUndo() {
        let highlighted = NSMutableAttributedString(attributedString: styledText("Highlighted text"))
        highlighted.addAttribute(.backgroundColor, value: NSColor.systemYellow, range: NSRange(location: 0, length: 11))
        let (editor, view) = makeEditor(text: highlighted, selection: NSRange(location: 0, length: 11))

        groupedMutation(view) { editor.setHighlight(.clear) }
        XCTAssertNil(view.textStorage?.attribute(.backgroundColor, at: 0, effectiveRange: nil))
        XCTAssertTrue(view.regressionUndoManager.canUndo)

        view.regressionUndoManager.undo()
        XCTAssertEqual(view.textStorage?.attribute(.backgroundColor, at: 0, effectiveRange: nil) as? NSColor, .systemYellow)
    }

    func testParagraphStyleSupportsUndoAndRedo() {
        assertSelectedFormattingUndoRedo { $0.applyStyle(.heading1) }
    }

    func testBookAuditNavigationAndExplicitReplacementSupportUndoRedo() {
        let text = styledText("Yehoshua discusses this term.")
        let range = (text.string as NSString).range(of: "Yehoshua")
        let (editor, view) = makeEditor(text: text, selection: NSRange(location: 0, length: 0))
        editor.navigate(to: range)
        XCTAssertEqual(view.selectedRange(), range)
        XCTAssertEqual(editor.selection, range)

        XCTAssertFalse(editor.applyManuscriptReplacement("Yeshua", in: range, expectedText: "stale"))
        XCTAssertEqual(view.string, text.string)
        XCTAssertFalse(view.regressionUndoManager.canUndo)

        groupedMutation(view) {
            XCTAssertTrue(editor.applyManuscriptReplacement("Yeshua", in: range, expectedText: "Yehoshua"))
        }
        XCTAssertEqual(view.string, "Yeshua discusses this term.")
        XCTAssertTrue(view.regressionUndoManager.canUndo)
        view.regressionUndoManager.undo()
        XCTAssertEqual(view.string, text.string)
        XCTAssertTrue(view.regressionUndoManager.canRedo)
        view.regressionUndoManager.redo()
        XCTAssertEqual(view.string, "Yeshua discusses this term.")
    }

    private func assertSelectedFormattingUndoRedo(
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: (EditorController) -> Void
    ) {
        let selection = NSRange(location: 2, length: 5)
        let (editor, view) = makeEditor(text: styledText("A paragraph of text"), selection: selection)
        let before = view.attributedString().copy() as! NSAttributedString

        groupedMutation(view) { operation(editor) }
        let after = view.attributedString().copy() as! NSAttributedString
        XCTAssertFalse(before.isEqual(to: after), file: file, line: line)
        XCTAssertEqual(view.string, before.string, file: file, line: line)
        XCTAssertEqual(view.selectedRange(), selection, file: file, line: line)
        XCTAssertTrue(view.regressionUndoManager.canUndo, file: file, line: line)

        view.regressionUndoManager.undo()
        XCTAssertTrue(before.isEqual(to: view.attributedString()), file: file, line: line)
        XCTAssertEqual(view.selectedRange(), selection, file: file, line: line)
        XCTAssertEqual(editor.selection, selection, file: file, line: line)
        XCTAssertTrue(view.regressionUndoManager.canRedo, file: file, line: line)

        view.regressionUndoManager.redo()
        XCTAssertTrue(after.isEqual(to: view.attributedString()), file: file, line: line)
        XCTAssertEqual(view.selectedRange(), selection, file: file, line: line)
        XCTAssertEqual(editor.selection, selection, file: file, line: line)
    }

    func testAttributedReplacementRestoresRichTextAndSelectionOnUndoRedo() {
        let original = NSMutableAttributedString(attributedString: styledText("Title\nOriginal body"))
        original.addAttributes([
            .font: WriterStyle.heading1.font,
            .boldWriterStyle: WriterStyle.heading1.rawValue
        ], range: NSRange(location: 0, length: 5))
        let selection = NSRange(location: 6, length: 8)
        let (editor, view) = makeEditor(text: original, selection: selection)
        let replacement = NSAttributedString(string: "New attributed", attributes: [
            .font: NSFont.boldSystemFont(ofSize: 19),
            .foregroundColor: NSColor.systemBlue,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .boldWriterStyle: WriterStyle.quote.rawValue
        ])
        let expected = NSMutableAttributedString(attributedString: original)
        expected.replaceCharacters(in: selection, with: replacement)

        groupedMutation(view) { editor.replace(range: selection, with: replacement, actionName: "AI Replacement") }
        let replacementSelection = NSRange(location: selection.location, length: replacement.length)
        XCTAssertTrue(expected.isEqual(to: view.attributedString()))
        XCTAssertEqual(view.selectedRange(), replacementSelection)
        XCTAssertEqual(view.regressionUndoManager.undoActionName, "AI Replacement")

        view.regressionUndoManager.undo()
        XCTAssertTrue(original.isEqual(to: view.attributedString()))
        XCTAssertEqual(view.selectedRange(), selection)
        XCTAssertEqual(editor.selection, selection)

        view.regressionUndoManager.redo()
        XCTAssertTrue(expected.isEqual(to: view.attributedString()))
        XCTAssertEqual(view.selectedRange(), replacementSelection)
        XCTAssertEqual(editor.selection, replacementSelection)
    }

    func testSelectionUpdatesReadStylesWithoutMutatingRichText() {
        let text = NSMutableAttributedString(attributedString: styledText("Heading\nBody"))
        text.addAttributes([
            .font: WriterStyle.heading1.font,
            .boldWriterStyle: WriterStyle.heading1.rawValue
        ], range: NSRange(location: 0, length: 7))
        let (editor, view) = makeEditor(text: text, selection: NSRange(location: 0, length: 0))
        let before = view.attributedString().copy() as! NSAttributedString
        let typingBefore = NSDictionary(dictionary: view.typingAttributes)

        editor.updateSelection(NSRange(location: 0, length: 0))
        XCTAssertEqual(editor.selectedStyle, .heading1)
        XCTAssertEqual(editor.fontSize, 24)
        editor.updateSelection(NSRange(location: 8, length: 4))
        XCTAssertEqual(editor.selectedStyle, .normal)
        XCTAssertEqual(editor.fontSize, 15)
        editor.updateSelection(NSRange(location: text.length, length: 0))
        XCTAssertEqual(editor.selectedStyle, .normal)
        XCTAssertEqual(editor.fontSize, 15)

        XCTAssertTrue(before.isEqual(to: view.attributedString()))
        XCTAssertTrue(typingBefore.isEqual(to: view.typingAttributes))
        XCTAssertFalse(view.regressionUndoManager.canUndo)
    }

    func testFormattingSnapshotTracksMixedSelectionAndCaretChanges() {
        let text = NSMutableAttributedString(attributedString: styledText("Bold plain"))
        text.addAttributes([
            .font: NSFont.boldSystemFont(ofSize: 20),
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .foregroundColor: NSColor.systemRed
        ], range: NSRange(location: 0, length: 4))
        let (editor, view) = makeEditor(text: text, selection: NSRange(location: 0, length: 10))

        XCTAssertEqual(editor.formatting.bold, .mixed)
        XCTAssertEqual(editor.formatting.underline, .mixed)
        XCTAssertEqual(editor.formatting.styleName, "Normal")
        XCTAssertNil(editor.formatting.fontSize)
        XCTAssertTrue(editor.formatting.textColorIsMixed)
        XCTAssertTrue(editor.formatting.canUndo == false)

        view.setSelectedRange(NSRange(location: 0, length: 4))
        editor.updateSelection(view.selectedRange())
        XCTAssertEqual(editor.formatting.bold, .on)
        XCTAssertEqual(editor.formatting.underline, .on)
        XCTAssertEqual(editor.formatting.fontSize, 20)

        view.setSelectedRange(NSRange(location: text.length, length: 0))
        editor.updateSelection(view.selectedRange())
        editor.toggleUnderline()
        XCTAssertEqual(editor.formatting.underline, .on)
        XCTAssertFalse(editor.formatting.textColorIsMixed)
    }

    func testCustomZoomValidatesAndUpdatesPublishedZoom() {
        let editor = EditorController()
        XCTAssertTrue(editor.setZoomPercent(125))
        XCTAssertEqual(editor.zoom, 1.25)
        XCTAssertTrue(editor.setZoomPercent(50))
        XCTAssertEqual(editor.zoom, 0.5)
        XCTAssertTrue(editor.setZoomPercent(200))
        XCTAssertEqual(editor.zoom, 2.0)
        XCTAssertFalse(editor.setZoomPercent(25))
        XCTAssertFalse(editor.setZoomPercent(400))
        XCTAssertEqual(editor.zoom, 2.0)
    }

    func testFormattingMixedSelectionAppliesTraitToEntireSelection() {
        let text = NSMutableAttributedString(attributedString: styledText("Bold plain"))
        text.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 15), range: NSRange(location: 0, length: 4))
        text.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: 4))
        let (editor, view) = makeEditor(text: text, selection: NSRange(location: 0, length: text.length))

        groupedMutation(view) {
            editor.toggleTrait(.boldFontMask)
            editor.toggleUnderline()
        }
        XCTAssertEqual(editor.formatting.bold, .on)
        XCTAssertEqual(editor.formatting.underline, .on)
        XCTAssertTrue(NSFontManager.shared.traits(of: view.textStorage!.attribute(.font, at: 6, effectiveRange: nil) as! NSFont).contains(.boldFontMask))
        XCTAssertEqual(view.textStorage?.attribute(.underlineStyle, at: 6, effectiveRange: nil) as? Int, NSUnderlineStyle.single.rawValue)

        groupedMutation(view) {
            editor.toggleTrait(.boldFontMask)
            editor.toggleUnderline()
        }
        XCTAssertEqual(editor.formatting.bold, .off)
        XCTAssertEqual(editor.formatting.underline, .off)
    }

    func testContextMenuRespectsSelectionAndViewingMode() throws {
        let view = WritingTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 500))
        view.isEditable = true
        view.textStorage?.setAttributedString(styledText("A heading"))
        view.setSelectedRange(NSRange(location: 0, length: 0))
        var linkRequests = 0
        view.contextInsertLink = { linkRequests += 1 }

        let caretMenu = view.contextMenu()
        XCTAssertFalse(try XCTUnwrap(caretMenu.item(withTitle: "Cut")).isEnabled)
        XCTAssertFalse(try XCTUnwrap(caretMenu.item(withTitle: "Copy")).isEnabled)
        XCTAssertTrue(try XCTUnwrap(caretMenu.item(withTitle: "Insert Link…")).isEnabled)

        view.setSelectedRange(NSRange(location: 0, length: 3))
        let selectionMenu = view.contextMenu()
        XCTAssertTrue(try XCTUnwrap(selectionMenu.item(withTitle: "Cut")).isEnabled)
        XCTAssertTrue(try XCTUnwrap(selectionMenu.item(withTitle: "Copy")).isEnabled)
        let linkItem = try XCTUnwrap(selectionMenu.item(withTitle: "Insert Link…"))
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(linkItem.action), to: linkItem.target, from: linkItem))
        XCTAssertEqual(linkRequests, 1)

        view.isEditable = false
        let viewingMenu = view.contextMenu()
        XCTAssertFalse(try XCTUnwrap(viewingMenu.item(withTitle: "Cut")).isEnabled)
        XCTAssertFalse(try XCTUnwrap(viewingMenu.item(withTitle: "Delete")).isEnabled)
        XCTAssertFalse(try XCTUnwrap(viewingMenu.item(withTitle: "Insert Link…")).isEnabled)
        XCTAssertTrue(try XCTUnwrap(viewingMenu.item(withTitle: "Copy")).isEnabled)
    }

    func testInsertedImageIsSizedToPageAndUndoable() throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 200, pixelsHigh: 100,
            bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ))
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let (editor, view) = makeEditor(text: styledText("Before after"), selection: NSRange(location: 7, length: 0))
        let before = view.attributedString().copy() as! NSAttributedString

        try editor.insertImage(data: data, name: "figure.png", maximumWidth: 100)
        let attachment = try XCTUnwrap(view.textStorage?.attribute(.attachment, at: 7, effectiveRange: nil) as? NSTextAttachment)
        XCTAssertEqual(attachment.bounds.width, 100, accuracy: 0.1)
        XCTAssertEqual(attachment.bounds.height, 50, accuracy: 0.1)
        XCTAssertTrue(view.regressionUndoManager.canUndo)

        view.regressionUndoManager.undo()
        XCTAssertTrue(before.isEqual(to: view.attributedString()))
    }

    func testScaledInlineJPEGKeepsSourceBytesThroughFloatingConversionAndNativeReopen() throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 2400, pixelsHigh: 1600,
            bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ))
        bitmap.setColor(.systemOrange, atX: 100, y: 100)
        let original = try XCTUnwrap(bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.82]))
        let originalHash = SHA256.hash(data: original).map { String(format: "%02x", $0) }.joined()
        let (editor, view) = makeEditor(text: styledText("Before after"), selection: NSRange(location: 7, length: 0))
        try editor.insertImage(data: original, name: "source.jpg", maximumWidth: 180)
        let attachment = try XCTUnwrap(view.textStorage?.attribute(.attachment, at: 7, effectiveRange: nil) as? NSTextAttachment)
        XCTAssertEqual(attachment.fileWrapper?.regularFileContents, original,
                       "Sizing the inline attachment must not replace its JPEG with a re-encoded PNG.")
        XCTAssertEqual(attachment.bounds.width, 180, accuracy: 0.5)

        let inlineNative = BOLDWriterDocument()
        inlineNative.replaceText(with: view.attributedString())
        let inlinePackage = try BOLDWriterDocument.packageWrapper(text: inlineNative.text, metadata: inlineNative.metadata)
        let inlineReopened = try BOLDWriterDocument(fileWrapper: inlinePackage, contentType: .boldWriterDocument)
        let inlineRestored = try XCTUnwrap(inlineReopened.text.attribute(.attachment, at: 7, effectiveRange: nil) as? NSTextAttachment)
        XCTAssertEqual(inlineRestored.fileWrapper?.regularFileContents, original)
        XCTAssertEqual(inlineRestored.bounds.width, 180, accuracy: 0.5,
                       "Inline display geometry should survive native persistence alongside the original encoded source.")

        let document = BOLDWriterDocument()
        document.replaceText(with: view.attributedString())
        editor.document = document
        view.setSelectedRange(NSRange(location: 7, length: 1))
        XCTAssertTrue(editor.convertSelectedInlineImageToFloating())
        XCTAssertEqual(document.metadata.floatingImages?.first?.imageData, original)
        XCTAssertEqual(SHA256.hash(data: try XCTUnwrap(document.metadata.floatingImages?.first?.imageData)).map { String(format: "%02x", $0) }.joined(), originalHash)

        let wrapper = try BOLDWriterDocument.packageWrapper(text: document.text, metadata: document.metadata)
        let reopened = try BOLDWriterDocument(fileWrapper: wrapper, contentType: .boldWriterDocument)
        XCTAssertEqual(reopened.metadata.floatingImages?.first?.imageData, original)
        let imageID = try XCTUnwrap(reopened.metadata.floatingImages?.first?.id)
        editor.document = reopened
        view.setSelectedRange(NSRange(location: 7, length: 0))
        XCTAssertTrue(editor.convertFloatingImageToInline(imageID))
        let convertedBack = try XCTUnwrap(view.textStorage?.attribute(.attachment, at: 7, effectiveRange: nil) as? NSTextAttachment)
        XCTAssertEqual(convertedBack.fileWrapper?.regularFileContents, original)
    }

    func testReplaceAllIsOneUndoableMutationAndRestoresAttributes() {
        let original = NSMutableAttributedString(attributedString: styledText("cat cat cat"))
        original.addAttribute(.foregroundColor, value: NSColor.systemRed, range: NSRange(location: 4, length: 3))
        let selection = NSRange(location: 4, length: 3)
        let (editor, view) = makeEditor(text: original, selection: selection)
        let matches = [0, 4, 8].map { NSRange(location: $0, length: 3) }

        groupedMutation(view) { editor.replaceAll(matches, with: "elephant") }
        let after = view.attributedString().copy() as! NSAttributedString
        let selectionAfter = view.selectedRange()
        XCTAssertEqual(view.string, "elephant elephant elephant")
        XCTAssertEqual(view.regressionUndoManager.undoActionName, "Replace All")

        view.regressionUndoManager.undo()
        XCTAssertTrue(original.isEqual(to: view.attributedString()))
        XCTAssertEqual(view.selectedRange(), selection)
        XCTAssertFalse(view.regressionUndoManager.canUndo)

        view.regressionUndoManager.redo()
        XCTAssertTrue(after.isEqual(to: view.attributedString()))
        XCTAssertEqual(view.selectedRange(), selectionAfter)
    }

    func testTrackedReplaceAllIsOneUndoableMutation() {
        let original =
            NSMutableAttributedString(
                attributedString:
                    styledText(
                        "cat cat cat"
                    )
            )

        original.addAttribute(
            .foregroundColor,
            value:
                NSColor.systemRed,
            range:
                NSRange(
                    location: 4,
                    length: 3
                )
        )

        let selection =
            NSRange(
                location: 4,
                length: 3
            )

        let (
            editor,
            view
        ) =
            makeEditor(
                text:
                    original,
                selection:
                    selection
            )

        let matches =
            [
                0,
                4,
                8
            ]
            .map {
                NSRange(
                    location:
                        $0,
                    length:
                        3
                )
            }

        groupedMutation(
            view
        ) {
            editor.replaceAll(
                matches,
                with:
                    "dog",
                trackChanges:
                    true
            )
        }

        let tracked =
            view.attributedString()
                .copy()
                as! NSAttributedString

        XCTAssertEqual(
            view.string,
            "catdog catdog catdog"
        )

        let records =
            TrackChanges.records(
                in:
                    tracked
            )

        XCTAssertEqual(
            records.count,
            6
        )

        XCTAssertEqual(
            records.filter {
                $0.kind
                    == .deletion
            }
            .count,
            3
        )

        XCTAssertEqual(
            records.filter {
                $0.kind
                    == .insertion
            }
            .count,
            3
        )

        XCTAssertEqual(
            view.regressionUndoManager
                .undoActionName,
            "Replace All"
        )

        XCTAssertTrue(
            view.regressionUndoManager
                .canUndo
        )

        view.regressionUndoManager
            .undo()

        XCTAssertTrue(
            original.isEqual(
                to:
                    view.attributedString()
            )
        )

        XCTAssertEqual(
            view.selectedRange(),
            selection
        )

        // One Undo must consume the complete Replace All command.
        XCTAssertFalse(
            view.regressionUndoManager
                .canUndo
        )

        XCTAssertTrue(
            view.regressionUndoManager
                .canRedo
        )

        view.regressionUndoManager
            .redo()

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
            6
        )

        // Redo must also recreate the whole command at once.
        XCTAssertFalse(
            view.regressionUndoManager
                .canRedo
        )
    }


    func testEquationInsertionUsesNativeEditorPath() {
        _ = NSApplication.shared

        let canvas =
            PaginatedEditor(
                text:
                    NSAttributedString(
                        string:
                            "a+b"
                    )
            )

        let view =
            canvas.firstView

        let editor =
            EditorController()

        editor.attach(
            view
        )

        view.isEditable =
            true

        view.setSelectedRange(
            NSRange(
                location:
                    1,
                length:
                    1
            )
        )

        editor.insertEquationText(
            "∑"
        )

        XCTAssertEqual(
            view.string,
            "a∑b"
        )
    }



    func testChecklistSupportsUndoAndRedo() throws {
        let (controller, view) = makeEditor(
            text: styledText("Checklist item\n"),
            selection: NSRange(location: 0, length: 15)
        )

        view.setSelectedRange(
            NSRange(
                location:
                    0,
                length:
                    view.string.utf16.count
            )
        )

        groupedMutation(view) { controller.toggleChecklist() }

        XCTAssertEqual(
            view.textStorage?
                .attribute(
                    .boldWriterChecklist,
                    at:
                        0,
                    effectiveRange:
                        nil
                )
                as? Bool,
            true
        )

        let manager =
            try XCTUnwrap(
                view.undoManager
            )

        manager.undo()

        XCTAssertNotEqual(
            view.textStorage?
                .attribute(
                    .boldWriterChecklist,
                    at:
                        0,
                    effectiveRange:
                        nil
                )
                as? Bool,
            true
        )

        manager.redo()

        XCTAssertEqual(
            view.textStorage?
                .attribute(
                    .boldWriterChecklist,
                    at:
                        0,
                    effectiveRange:
                        nil
                )
                as? Bool,
            true
        )

        groupedMutation(view) { controller.toggleChecklistItem() }

        XCTAssertEqual(
            view.textStorage?
                .attribute(
                    .boldWriterChecklistChecked,
                    at:
                        0,
                    effectiveRange:
                        nil
                )
                as? Bool,
            true
        )

        manager.undo()

        XCTAssertEqual(
            view.textStorage?
                .attribute(
                    .boldWriterChecklistChecked,
                    at:
                        0,
                    effectiveRange:
                        nil
                )
                as? Bool,
            false
        )

        manager.redo()

        XCTAssertEqual(
            view.textStorage?
                .attribute(
                    .boldWriterChecklistChecked,
                    at:
                        0,
                    effectiveRange:
                        nil
                )
                as? Bool,
            true
        )
    }


    func testRegexReplaceAllPreservesEachMatchesFormattingAndUndo() throws {
        let original = NSMutableAttributedString(attributedString: styledText("cat12 cat3"))
        original.addAttribute(.foregroundColor, value: NSColor.systemRed, range: NSRange(location: 6, length: 4))
        let (editor, view) = makeEditor(text: original, selection: NSRange(location: 0, length: 0))
        let search = try DocumentSearch("cat([0-9]+)", regularExpression: true)
        XCTAssertTrue(editor.replaceMatches(search.replacements(in: view.string, with: "$1 dogs")))
        XCTAssertEqual(view.string, "12 dogs 3 dogs")
        XCTAssertEqual(view.textStorage?.attribute(.foregroundColor, at: 8, effectiveRange: nil) as? NSColor, .systemRed)
        XCTAssertEqual(view.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont, NSFont.systemFont(ofSize: 15))
        let after = view.attributedString().copy() as! NSAttributedString
        view.regressionUndoManager.undo()
        XCTAssertTrue(original.isEqual(to: view.attributedString()))
        XCTAssertFalse(view.regressionUndoManager.canUndo)
        view.regressionUndoManager.redo()
        XCTAssertTrue(after.isEqual(to: view.attributedString()))
    }

    func testSingleSearchReplacementKeepsFontAndParagraphStyle() {
        let original = NSMutableAttributedString(attributedString: styledText("Chapter One"))
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        original.addAttributes([.font: NSFont.boldSystemFont(ofSize: 24), .paragraphStyle: paragraph, .boldWriterStyle: WriterStyle.heading1.rawValue], range: NSRange(location: 0, length: original.length))
        let (editor, view) = makeEditor(text: original, selection: NSRange(location: 0, length: 7))
        XCTAssertTrue(editor.replaceMatches([SearchReplacement(range: NSRange(location: 0, length: 7), text: "Section")], actionName: "Replace"))
        XCTAssertEqual(view.string, "Section One")
        XCTAssertEqual(view.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont, NSFont.boldSystemFont(ofSize: 24))
        XCTAssertEqual((view.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.alignment, .center)
        XCTAssertEqual(view.textStorage?.attribute(.boldWriterStyle, at: 0, effectiveRange: nil) as? String, WriterStyle.heading1.rawValue)
        XCTAssertEqual(view.selectedRange(), NSRange(location: 0, length: 7))
        view.regressionUndoManager.undo()
        XCTAssertTrue(original.isEqual(to: view.attributedString()))
    }

    func testReadOnlySearchAndTrackedReplacementsCannotModifyText() {
        for tracking in [false, true] {
            let original = styledText("cat cat")
            let (editor, view) = makeEditor(text: original, selection: NSRange(location: 0, length: 3))
            view.isEditable = false
            editor.replaceAll([NSRange(location: 0, length: 3)], with: "dog", trackChanges: tracking)
            editor.replace(range: NSRange(location: 0, length: 3), with: NSAttributedString(string: "dog"), actionName: "Replace", trackChanges: tracking)
            XCTAssertFalse(editor.replaceMatches([SearchReplacement(range: NSRange(location: 0, length: 3), text: "dog")], trackChanges: tracking))
            XCTAssertTrue(original.isEqual(to: view.attributedString()))
            XCTAssertFalse(view.regressionUndoManager.canUndo)
        }
    }

    func testInvalidOverlappingAndDuplicateReplacementsAreAtomic() {
        for ranges in [
            [NSRange(location: 0, length: 3), NSRange(location: 99, length: 1)],
            [NSRange(location: 0, length: 3), NSRange(location: 2, length: 3)],
            [NSRange(location: 0, length: 0), NSRange(location: 0, length: 0)]
        ] {
            let original = styledText("cat cat")
            let (editor, view) = makeEditor(text: original, selection: NSRange(location: 0, length: 0))
            XCTAssertFalse(editor.replaceMatches(ranges.map { SearchReplacement(range: $0, text: "dog") }))
            XCTAssertTrue(original.isEqual(to: view.attributedString()))
            XCTAssertFalse(view.regressionUndoManager.canUndo)
        }
    }

    func testZeroWidthSearchReplacementIsOneUndoableInsertionBatch() throws {
        let original = styledText("cat cat")
        let (editor, view) = makeEditor(text: original, selection: NSRange(location: 0, length: 0))
        let search = try DocumentSearch("(?=cat)", regularExpression: true)
        XCTAssertTrue(editor.replaceMatches(search.replacements(in: view.string, with: "•")))
        XCTAssertEqual(view.string, "•cat •cat")
        view.regressionUndoManager.undo()
        XCTAssertTrue(original.isEqual(to: view.attributedString()))
        XCTAssertFalse(view.regressionUndoManager.canUndo)
    }

    func testTrackedRegexReplacementIsOneUndoableCommand() throws {
        let original = styledText("cat12 cat3")
        let (editor, view) = makeEditor(text: original, selection: NSRange(location: 0, length: 0))
        let search = try DocumentSearch("cat([0-9]+)", regularExpression: true)
        XCTAssertTrue(editor.replaceMatches(search.replacements(in: view.string, with: "dog$1"), trackChanges: true))
        XCTAssertEqual(view.string, "cat12dog12 cat3dog3")
        XCTAssertEqual(TrackChanges.records(in: view.attributedString()).count, 4)
        XCTAssertEqual(view.regressionUndoManager.undoActionName, "Replace All")
        view.regressionUndoManager.undo()
        XCTAssertTrue(original.isEqual(to: view.attributedString()))
        XCTAssertFalse(view.regressionUndoManager.canUndo)
    }

    func testBatchNoteProtectionMatchesIndividualEditingRanges() throws {
        let text = NSMutableAttributedString(string: "x12 y34 z")
        let footnote = Footnote(text: "Footnote", location: 1, length: 2)
        let endnote = Endnote(text: "Endnote", location: 5, length: 2)
        text.addAttribute(.footnote, value: Footnotes.payload(footnote), range: NSRange(location: 1, length: 2))
        text.addAttribute(.endnote, value: Endnotes.payload(endnote), range: NSRange(location: 5, length: 2))
        let ranges = (0...text.length).flatMap { location -> [NSRange] in
            [NSRange(location: location, length: 0)]
                + (location < text.length ? [NSRange(location: location, length: 1)] : [])
        }
        let batched = try NoteReferences.editingRanges(ranges, in: text)
        XCTAssertEqual(batched, ranges.map { NoteReferences.editingRange($0, in: text) })
    }

    func testConflictingRegexEditsInsideOneReferenceAreRejected() {
        let original = NSMutableAttributedString(attributedString: styledText("x12 y"))
        let note = Footnote(text: "Footnote", location: 1, length: 2)
        original.addAttribute(.footnote, value: Footnotes.payload(note), range: NSRange(location: 1, length: 2))
        let (editor, view) = makeEditor(text: original, selection: NSRange(location: 0, length: 0))
        XCTAssertFalse(editor.replaceMatches([
            SearchReplacement(range: NSRange(location: 1, length: 1), text: "one"),
            SearchReplacement(range: NSRange(location: 2, length: 1), text: "two")
        ]))
        XCTAssertTrue(original.isEqual(to: view.attributedString()))
        XCTAssertFalse(view.regressionUndoManager.canUndo)
    }

    func testNoteExpansionAndZeroWidthInsertionRemainInOriginalCoordinateOrder() {
        let original = NSMutableAttributedString(attributedString: styledText("x12 y"))
        let note = Footnote(text: "Footnote", location: 1, length: 2)
        original.addAttribute(.footnote, value: Footnotes.payload(note), range: NSRange(location: 1, length: 2))
        let (editor, view) = makeEditor(text: original, selection: NSRange(location: 0, length: 0))
        XCTAssertTrue(editor.replaceMatches([
            SearchReplacement(range: NSRange(location: 2, length: 0), text: "!"),
            SearchReplacement(range: NSRange(location: 2, length: 1), text: "note")
        ]))
        XCTAssertEqual(view.string, "xnote! y")
        XCTAssertTrue((try? Footnotes.records(in: view.attributedString()))?.isEmpty == true)
        view.regressionUndoManager.undo()
        XCTAssertTrue(original.isEqual(to: view.attributedString()))
    }

    func testLargeReplaceAllReplacesBeyondDisplayedLimitAndRetainsUndo() throws {
        let original = styledText(String(repeating: "cat ", count: 5_000))
        let (editor, view) = makeEditor(text: original, selection: NSRange(location: 0, length: 0))
        let search = try DocumentSearch("cat")
        XCTAssertTrue(editor.replaceMatches(search.replacements(in: view.string, with: "dog")))
        XCTAssertEqual(view.string, String(repeating: "dog ", count: 5_000))
        view.regressionUndoManager.undo()
        XCTAssertTrue(original.isEqual(to: view.attributedString()))
        XCTAssertFalse(view.regressionUndoManager.canUndo)
    }

    func testRegexReplacementInsideTableRetainsStructureThroughNativeReopen() throws {
        var table = try WriterTable(rows: 1, columns: 2)
        table.cells[0] = [styledText("cat12"), styledText("cat3")]
        let original = try Tables.rendered(table)
        let (editor, view) = makeEditor(text: original, selection: NSRange(location: 0, length: 0))
        let search = try DocumentSearch("cat([0-9]+)", regularExpression: true)
        XCTAssertTrue(editor.replaceMatches(search.replacements(in: view.string, with: "dog$1")))
        let replaced = try XCTUnwrap(Tables.models(in: view.attributedString()).first)
        XCTAssertEqual(replaced.id, table.id)
        XCTAssertEqual(replaced.cellIDs, table.cellIDs)
        XCTAssertEqual(replaced.cells[0].map(\.string), ["dog12", "dog3"])
        let wrapper = try BOLDWriterDocument.packageWrapper(text: view.attributedString(), metadata: DocumentMetadata())
        let reopened = try BOLDWriterDocument(fileWrapper: wrapper, contentType: .boldWriterDocument)
        XCTAssertEqual(try Tables.models(in: reopened.text).first?.cells[0].map(\.string), ["dog12", "dog3"])
        view.regressionUndoManager.undo()
        XCTAssertTrue(original.isEqual(to: view.attributedString()))
    }

    func testReplaceAllRejectsCrossCellBoundaryWithoutChangingEarlierMatches() throws {
        var table = try WriterTable(rows: 1, columns: 2)
        table.cells[0] = [styledText("cat"), styledText("cat")]
        let original = NSMutableAttributedString(attributedString: styledText("cat\n"))
        original.append(try Tables.rendered(table))
        let (editor, view) = makeEditor(text: original, selection: NSRange(location: 0, length: 0))
        let cells = try Tables.records(in: original)
        XCTAssertFalse(editor.replaceMatches([
            SearchReplacement(range: NSRange(location: 0, length: 3), text: "dog"),
            SearchReplacement(range: NSRange(location: cells[0].location + 2, length: 3), text: "joined")
        ]))
        XCTAssertTrue(original.isEqual(to: view.attributedString()))
        XCTAssertFalse(view.regressionUndoManager.canUndo)
        XCTAssertEqual(try Tables.records(in: view.attributedString()).map(\.id), cells.map(\.id))
    }

}
