import AppKit
import PDFKit
import XCTest
@testable import BOLDWriter

@MainActor
private final class FootnoteTextView: NSTextView {
    let manager = UndoManager()
    override var undoManager: UndoManager? { manager }
}

@MainActor
final class FootnoteTests: XCTestCase {
    private func editor() -> (EditorController, FootnoteTextView) {
        let view = FootnoteTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 500))
        view.allowsUndo = true
        view.manager.groupsByEvent = false
        view.textStorage?.setAttributedString(NSAttributedString(string: "Body", attributes: [.font: NSFont.boldSystemFont(ofSize: 15)]))
        view.setSelectedRange(NSRange(location: 4, length: 0))
        let controller = EditorController()
        controller.attach(view)
        return (controller, view)
    }
    private func change(_ view: FootnoteTextView, _ body: () -> Void) {
        view.manager.beginUndoGrouping(); body(); view.manager.endUndoGrouping()
    }
    private func manuscript() -> NSAttributedString {
        let result = NSMutableAttributedString(string: "Bold body", attributes: [.font: NSFont.boldSystemFont(ofSize: 17)])
        for index in 1...3 {
            result.append(Footnotes.marker(Footnote(text: "Note \(index) & <text>\nSecond paragraph", location: 0, length: 1), number: index))
            result.append(NSAttributedString(string: " italic \(index)", attributes: [.font: NSFont.systemFont(ofSize: 15).withItalicTrait()]))
        }
        return result
    }

    func testInsertOneAndUndoRedoInsertion() throws {
        let (controller, view) = editor()
        change(view) { controller.insertFootnote(text: "First") }
        let first = try XCTUnwrap(Footnotes.records(in: view.attributedString()).first)
        XCTAssertEqual(first.text, "First")
        XCTAssertEqual(view.string, "Body1")
        XCTAssertEqual(view.textStorage?.attribute(.superscript, at: 4, effectiveRange: nil) as? Int, 1)
        view.manager.undo()
        XCTAssertEqual(view.string, "Body")
        XCTAssertTrue(try Footnotes.records(in: view.attributedString()).isEmpty)
        view.manager.redo()
        XCTAssertEqual(try Footnotes.records(in: view.attributedString()).first?.id, first.id)
    }

    func testMultipleInsertionRenumberDeleteEditAndUndo() throws {
        let (controller, view) = editor()
        for index in 1...12 {
            view.setSelectedRange(NSRange(location: 4, length: 0))
            change(view) { controller.insertFootnote(text: "Note \(index)") }
        }
        var notes = try Footnotes.records(in: view.attributedString())
        XCTAssertEqual(notes.count, 12)
        XCTAssertEqual(notes.first?.text, "Note 12")
        XCTAssertEqual(view.string, "Body123456789101112")
        let deleted = notes[4]
        change(view) { controller.deleteFootnote(id: deleted.id) }
        notes = try Footnotes.records(in: view.attributedString())
        XCTAssertEqual(notes.count, 11)
        XCTAssertEqual(view.string, "Body1234567891011")
        view.manager.undo()
        XCTAssertEqual(try Footnotes.records(in: view.attributedString())[4].id, deleted.id)
        view.manager.redo()
        XCTAssertEqual(try Footnotes.records(in: view.attributedString()).count, 11)
        change(view) { controller.updateFootnote(id: notes[0].id, text: "Edited") }
        XCTAssertEqual(try Footnotes.records(in: view.attributedString())[0].text, "Edited")
        view.manager.undo()
        XCTAssertEqual(try Footnotes.records(in: view.attributedString())[0].text, "Note 12")
    }

    func testNativeSaveCloseReopenEditSaveAgainAndRevision() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".boldwriter")
        defer { try? FileManager.default.removeItem(at: url) }
        let original = manuscript()
        let ids = try Footnotes.records(in: original).map(\.id)
        try BOLDWriterDocument.packageWrapper(text: original, metadata: DocumentMetadata()).write(to: url, options: .atomic, originalContentsURL: nil)
        var document: BOLDWriterDocument? = try BOLDWriterDocument(fileWrapper: FileWrapper(url: url), contentType: .boldWriterDocument)
        XCTAssertEqual(try Footnotes.records(in: document!.text).map(\.id), ids)
        XCTAssertTrue(document!.createRevision(named: "Before note edit"))
        let revision = try XCTUnwrap(document!.metadata.revisions.first)
        let mutable = NSMutableAttributedString(attributedString: document!.text)
        let note = try Footnotes.records(in: mutable)[1]
        mutable.addAttribute(.footnote, value: ["id": note.id.uuidString, "text": "Reopened edit"], range: NSRange(location: note.location, length: note.length))
        document!.replaceText(with: mutable)
        try BOLDWriterDocument.packageWrapper(text: document!.text, metadata: document!.metadata).write(to: url, options: .atomic, originalContentsURL: url)
        document = nil
        let reopened = try BOLDWriterDocument(fileWrapper: FileWrapper(url: url), contentType: .boldWriterDocument)
        XCTAssertEqual(try Footnotes.records(in: reopened.text)[1].text, "Reopened edit")
        XCTAssertEqual(try Footnotes.records(in: reopened.text).map(\.id), ids)
        try reopened.restore(revision)
        XCTAssertEqual(try Footnotes.records(in: reopened.text)[1].text, "Note 2 & <text>\nSecond paragraph")
    }

    func testDOCXExportAndThreeNoteFormattedRoundTrip() throws {
        let original = manuscript()
        let data = try DOCXExporter.data(from: original, title: "Footnotes")
        let parts = Dictionary(uniqueKeysWithValues: try DOCXPackage.entries(in: data).map { ($0.path, $0.data) })
        let main = try DOCXPackage.xml(XCTUnwrap(parts["word/document.xml"]))
        XCTAssertEqual(try main.nodes(forXPath: "//*[local-name()='footnoteReference']").count, 3)
        let notes = try DOCXPackage.xml(XCTUnwrap(parts["word/footnotes.xml"]))
        XCTAssertEqual(try notes.nodes(forXPath: "//*[local-name()='footnoteRef']").count, 3)
        XCTAssertTrue(String(decoding: parts["word/_rels/document.xml.rels"]!, as: UTF8.self).contains("/footnotes"))
        XCTAssertTrue(String(decoding: parts["[Content_Types].xml"]!, as: UTF8.self).contains("wordprocessingml.footnotes+xml"))
        let imported = try DOCXImporter.text(from: data)
        XCTAssertEqual(imported.string.trimmingCharacters(in: .newlines), original.string)
        XCTAssertEqual(try Footnotes.records(in: imported).map(\.text), try Footnotes.records(in: original).map(\.text))
        let bold = try XCTUnwrap(imported.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: bold).contains(.boldFontMask))
        let italicRange = (imported.string as NSString).range(of: "italic")
        let italic = try XCTUnwrap(imported.attribute(.font, at: italicRange.location, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: italic).contains(.italicFontMask))
        let second = try DOCXImporter.text(from: DOCXExporter.data(from: imported, title: "Again"))
        XCTAssertEqual(try Footnotes.records(in: second).map(\.text), try Footnotes.records(in: imported).map(\.text))
    }

    // Independent Word-style XML, including nonsequential IDs and separator notes.
    private func fixture(reference: String = "42", body: String = "<w:r><w:footnoteRef/><w:t>Word note</w:t><w:tab/><w:t>text</w:t></w:r>") -> Data {
        let w = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
        let r = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
        let parts = [
            "[Content_Types].xml": "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/><Override PartName=\"/word/notes.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.footnotes+xml\"/></Types>",
            "_rels/.rels": "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"main\" Type=\"\(r)/officeDocument\" Target=\"word/document.xml\"/></Relationships>",
            "word/_rels/document.xml.rels": "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"notes\" Type=\"\(r)/footnotes\" Target=\"notes.xml\"/></Relationships>",
            "word/document.xml": "<w:document xmlns:w=\"\(w)\"><w:body><w:p><w:r><w:t>Before</w:t><w:footnoteReference w:id=\"\(reference)\"/><w:t>After</w:t></w:r></w:p></w:body></w:document>",
            "word/notes.xml": "<w:footnotes xmlns:w=\"\(w)\"><w:footnote w:type=\"separator\" w:id=\"-1\"><w:p><w:r><w:separator/></w:r></w:p></w:footnote><w:footnote w:id=\"42\"><w:p>\(body)</w:p></w:footnote></w:footnotes>"
        ]
        return ZipArchiveWriter.archive(parts.map { ZipEntry(path: $0.key, data: Data($0.value.utf8)) })
    }

    func testIndependentWordFootnoteImport() throws {
        let text = try DOCXImporter.text(from: fixture())
        XCTAssertEqual(text.string.trimmingCharacters(in: .newlines), "Before1After")
        XCTAssertEqual(try Footnotes.records(in: text).first?.text, "Word note\ttext")
    }

    func testMalformedFootnotesFailSafely() throws {
        XCTAssertThrowsError(try DOCXImporter.text(from: fixture(reference: "99")))
        XCTAssertThrowsError(try DOCXImporter.text(from: fixture(body: "<w:r><w:drawing/></w:r>")))
        let text = NSMutableAttributedString(string: "Body1")
        text.addAttribute(.footnote, value: ["id": "invalid", "text": "Note"], range: NSRange(location: 4, length: 1))
        XCTAssertThrowsError(try BOLDWriterDocument.packageWrapper(text: text, metadata: DocumentMetadata()))
        XCTAssertThrowsError(try DOCXExporter.data(from: text, title: "Bad"))
        var metadata = DocumentMetadata()
        metadata.footnotes = [Footnote(text: "Bad", location: Int.max, length: 2)]
        let wrapper = try BOLDWriterDocument.packageWrapper(text: NSAttributedString(string: "Body1"), metadata: DocumentMetadata())
        wrapper.removeFileWrapper(wrapper.fileWrappers!["metadata.json"]!)
        let bad = FileWrapper(regularFileWithContents: try JSONEncoder().encode(metadata)); bad.preferredFilename = "metadata.json"
        wrapper.addFileWrapper(bad)
        XCTAssertThrowsError(try BOLDWriterDocument(fileWrapper: wrapper, contentType: .boldWriterDocument))
    }

    func testKeyboardDeletionTreatsMultiDigitReferenceAtomically() throws {
        let (controller, view) = editor()
        for index in 1...10 {
            view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
            change(view) { controller.insertFootnote(text: "Note \(index)") }
        }
        let document = BOLDWriterDocument()
        document.replaceText(with: view.attributedString())
        let coordinator = RichTextEditor.Coordinator(document: document, controller: controller)
        view.delegate = coordinator
        let note = try Footnotes.records(in: view.attributedString())[9]
        let partial = NSRange(location: note.location + 1, length: 1)
        change(view) {
            XCTAssertFalse(coordinator.textView(view, shouldChangeTextIn: partial, replacementString: ""))
        }
        XCTAssertEqual(try Footnotes.records(in: document.text).count, 9)
        view.manager.undo()
        XCTAssertEqual(try Footnotes.records(in: document.text).count, 10)
        XCTAssertEqual(try Footnotes.records(in: document.text)[9].text, "Note 10")
        view.manager.redo()
        XCTAssertEqual(try Footnotes.records(in: document.text).count, 9)
    }

    func testReplaceAllOnReferenceRemovesNoteWithoutMalformedPayload() throws {
        let (controller, view) = editor()
        change(view) { controller.insertFootnote(text: "Note") }
        change(view) { controller.replaceAll([NSRange(location: 4, length: 1)], with: "replacement") }
        XCTAssertEqual(view.string, "Bodyreplacement")
        XCTAssertTrue(try Footnotes.records(in: view.attributedString()).isEmpty)
        view.manager.undo()
        XCTAssertEqual(try Footnotes.records(in: view.attributedString()).first?.text, "Note")
    }

    func testImagesAndFootnotesSurviveTogether() throws {
        let (original, _) = SampleDocumentFactory.make()
        let imported = try DOCXImporter.text(from: DOCXExporter.data(from: original, title: "Mixed content"))
        XCTAssertEqual(try Footnotes.records(in: imported).map(\.text), try Footnotes.records(in: original).map(\.text))
        var count = 0
        imported.enumerateAttribute(.attachment, in: NSRange(location: 0, length: imported.length)) { value, _, _ in
            if value is NSTextAttachment { count += 1 }
        }
        XCTAssertEqual(count, 1)
    }

    func testPDFIncludesNumberedFootnoteBodies() throws {
        let pdf = try XCTUnwrap(PDFDocument(data: PDFExporter.data(from: manuscript(), settings: PageSettings())))
        XCTAssertFalse(pdf.string?.contains("\n\nFootnotes\n") == true)
        for index in 1...3 { XCTAssertTrue(pdf.string?.contains("\(index). Note \(index)") == true) }
    }

    private func paginated(_ text: NSAttributedString, settings: PageSettings = PageSettings()) -> PaginatedEditor {
        let editor = PaginatedEditor(text: text)
        editor.configure(printLayout: true, settings: settings, zoom: 1, viewportWidth: 900)
        editor.finishPagination()
        return editor
    }

    func testSinglePageBottomFootnoteReservesBodyAndMatchesPDF() throws {
        let text = NSMutableAttributedString(string: "Body text ", attributes: [.font: NSFont.systemFont(ofSize: 14)])
        text.append(Footnotes.marker(Footnote(text: "A page-bottom note", location: 0, length: 1), number: 1))
        let editor = paginated(text)
        XCTAssertNil(editor.lastLayoutError)
        XCTAssertEqual(editor.pages.count, 1)
        XCTAssertEqual(editor.pages[0].pageFootnotes.fragments.count, 1)
        XCTAssertGreaterThan(editor.pages[0].reservedFootnoteHeight, 0)
        XCTAssertEqual(try XCTUnwrap(editor.pages[0].textContainer).containerSize.height,
                       try XCTUnwrap(editor.pages[0].pageGeometry).contentSize.height - editor.pages[0].reservedFootnoteHeight,
                       accuracy: 0.5)
        let pdf = try XCTUnwrap(PDFDocument(data: PDFExporter.data(from: text, settings: PageSettings())))
        XCTAssertEqual(pdf.pageCount, 1)
        XCTAssertTrue(pdf.page(at: 0)?.string?.contains("1. A page-bottom note") == true)
    }

    func testLongFootnoteContinuesWithoutLosingText() throws {
        let body = String(repeating: "Long footnote text that should continue across physical pages. ", count: 150)
        let text = NSMutableAttributedString(string: "Reference ", attributes: [.font: NSFont.systemFont(ofSize: 14)])
        text.append(Footnotes.marker(Footnote(text: body, location: 0, length: 1), number: 1))
        let editor = paginated(text)
        XCTAssertNil(editor.lastLayoutError)
        XCTAssertGreaterThan(editor.pages.count, 1)
        XCTAssertTrue(editor.pages[0].pageFootnotes.fragments.first?.text.hasPrefix("1. ") == true)
        XCTAssertTrue(editor.pages[1].pageFootnotes.fragments.first?.continued == true)
        XCTAssertTrue(editor.pages.last?.pageFootnotes.outgoing.isEmpty == true)
        let noteID = try XCTUnwrap(Footnotes.records(in: text).first?.id)
        let recovered = editor.pages.flatMap { $0.pageFootnotes.fragments }
            .filter { $0.id == noteID }
            .map { fragment in
                fragment.text.replacingOccurrences(of: fragment.continued ? "1. (continued) " : "1. ", with: "", range: fragment.text.startIndex..<fragment.text.endIndex)
            }
            .joined()
        XCTAssertEqual(recovered, body)
        let pdf = try XCTUnwrap(PDFDocument(data: PDFExporter.data(from: text, settings: PageSettings())))
        XCTAssertEqual(pdf.pageCount, editor.pages.count)
        XCTAssertTrue(pdf.page(at: 1)?.string?.contains("(continued)") == true)
    }

    func testTwoReferencesSharePageInOrder() throws {
        let text = NSMutableAttributedString(string: "Opening ", attributes: [.font: NSFont.systemFont(ofSize: 14)])
        text.append(Footnotes.marker(Footnote(text: "First bottom note", location: 0, length: 1), number: 1))
        text.append(NSAttributedString(string: " then another "))
        text.append(Footnotes.marker(Footnote(text: "Second bottom note", location: 0, length: 1), number: 2))
        let editor = paginated(text)
        XCTAssertEqual(editor.pages.count, 1)
        XCTAssertEqual(editor.pages[0].pageFootnotes.fragments.map(\.number), [1, 2])
        let pdf = try XCTUnwrap(PDFDocument(data: PDFExporter.data(from: text, settings: PageSettings())))
        let page = try XCTUnwrap(pdf.page(at: 0)?.string)
        XCTAssertLessThan(try XCTUnwrap(page.range(of: "First bottom note")?.lowerBound),
                          try XCTUnwrap(page.range(of: "Second bottom note")?.lowerBound))
    }

    func testManualPageBreakOwnsFollowingFootnote() throws {
        let text = NSMutableAttributedString(string: "First page\u{000C}Second page ", attributes: [.font: NSFont.systemFont(ofSize: 14)])
        text.append(Footnotes.marker(Footnote(text: "Belongs on second", location: 0, length: 1), number: 1))
        let editor = paginated(text)
        XCTAssertNil(editor.lastLayoutError)
        XCTAssertEqual(editor.pages.count, 2)
        XCTAssertTrue(editor.pages[0].pageFootnotes.fragments.isEmpty)
        XCTAssertEqual(editor.pages[1].pageFootnotes.fragments.first?.number, 1)
        let pdf = try XCTUnwrap(PDFDocument(data: PDFExporter.data(from: text, settings: PageSettings())))
        XCTAssertFalse(pdf.page(at: 0)?.string?.contains("Belongs on second") == true)
        XCTAssertTrue(pdf.page(at: 1)?.string?.contains("Belongs on second") == true)
    }

    func testFootnoteReservationCanMoveReferenceToNextPageWithoutOscillation() throws {
        let line = "A measured manuscript line fills the physical page before the footnote arrives.\n"
        let original = NSAttributedString(string: String(repeating: line, count: 100),
                                          attributes: [.font: NSFont.systemFont(ofSize: 14)])
        let baseline = paginated(original)
        let firstEnd = try XCTUnwrap(baseline.pageRanges.first).length
        XCTAssertGreaterThan(firstEnd, 20)
        let text = NSMutableAttributedString(attributedString: original)
        let referenceLocation = firstEnd - 4
        text.insert(Footnotes.marker(Footnote(text: String(repeating: "Reserve this footnote area. ", count: 30), location: 0, length: 1), number: 1),
                    at: referenceLocation)
        let editor = paginated(text)
        XCTAssertNil(editor.lastLayoutError)
        let note = try XCTUnwrap(Footnotes.records(in: text).first)
        let owner = try XCTUnwrap(editor.pageRanges.firstIndex { NSLocationInRange(note.location, $0) })
        XCTAssertGreaterThan(owner, 0)
        XCTAssertEqual(editor.pages[owner].pageFootnotes.fragments.first?.number, 1)
        let stableRanges = editor.pageRanges
        editor.finishPagination()
        XCTAssertEqual(editor.pageRanges, stableRanges)
        var pdfRanges: [NSRange] = []
        _ = try PDFExporter.data(from: text, settings: PageSettings(), pageRangeSink: { pdfRanges = $0 })
        XCTAssertEqual(pdfRanges, stableRanges)
    }

    func testSeveralLongNotesCompleteWithBoundedContinuation() throws {
        let text = NSMutableAttributedString(string: "Start ", attributes: [.font: NSFont.systemFont(ofSize: 14)])
        for number in 1...3 {
            text.append(Footnotes.marker(Footnote(text: String(repeating: "Note \(number) words continue. ", count: 80), location: 0, length: 1), number: number))
            text.append(NSAttributedString(string: " more body "))
        }
        let editor = paginated(text)
        XCTAssertNil(editor.lastLayoutError)
        XCTAssertGreaterThan(editor.pages.count, 2)
        XCTAssertLessThan(editor.pages.count, 30)
        XCTAssertTrue(editor.pages.last?.pageFootnotes.outgoing.isEmpty == true)
        let pdf = try XCTUnwrap(PDFDocument(data: PDFExporter.data(from: text, settings: PageSettings())))
        XCTAssertEqual(pdf.pageCount, editor.pages.count)
    }

    func testFootnoteAndHeaderFooterStayInSeparatePDFRegions() throws {
        var settings = PageSettings()
        settings.headerText = "Running header"
        settings.footerText = "Running footer"
        let text = NSMutableAttributedString(string: "Main manuscript ", attributes: [.font: NSFont.systemFont(ofSize: 14)])
        text.append(Footnotes.marker(Footnote(text: "Bottom-page note", location: 0, length: 1), number: 1))
        let pdf = try XCTUnwrap(PDFDocument(data: PDFExporter.data(from: text, settings: settings)))
        let page = try XCTUnwrap(pdf.page(at: 0))
        let labels = ["Running header", "Main manuscript", "Bottom-page note", "Running footer"]
        let bounds = try labels.map { label -> CGRect in
            let selection = try XCTUnwrap(pdf.findString(label, withOptions: []).first)
            return selection.bounds(for: page)
        }
        XCTAssertGreaterThan(bounds[0].midY, bounds[1].midY)
        XCTAssertGreaterThan(bounds[1].midY, bounds[2].midY)
        XCTAssertGreaterThan(bounds[2].midY, bounds[3].midY)
    }

    func testSectionLandscapeFootnoteUsesThatPagesGeometry() throws {
        var first = PageSettings()
        first.headerText = "Portrait header"
        var second = PageSettings()
        second.landscape = true
        second.leftMargin = 90
        second.rightMargin = 54
        second.headerText = "Landscape header"
        second.footerText = "Landscape footer"
        let text = NSMutableAttributedString(string: "Portrait section\n", attributes: [.font: NSFont.systemFont(ofSize: 14)])
        let boundary = text.length
        text.append(NSAttributedString(string: "Landscape manuscript ", attributes: [.font: NSFont.systemFont(ofSize: 14)]))
        text.append(Footnotes.marker(Footnote(text: "Landscape bottom note", location: 0, length: 1), number: 1))
        let sections = [DocumentSection(location: 0, page: first), DocumentSection(location: boundary, page: second)]
        let editor = PaginatedEditor(text: text)
        editor.configure(printLayout: true, settings: first, sections: sections, zoom: 1, viewportWidth: 900)
        editor.finishPagination()
        XCTAssertNil(editor.lastLayoutError)
        XCTAssertEqual(editor.pages.count, 2)
        XCTAssertTrue(editor.pages[0].pageFootnotes.fragments.isEmpty)
        XCTAssertEqual(editor.pages[1].pageFootnotes.fragments.first?.text, "1. Landscape bottom note")
        XCTAssertEqual(editor.pages[1].pageGeometry?.contentOrigin.x, 90)
        let pdf = try XCTUnwrap(PDFDocument(data: PDFExporter.data(from: text, settings: first, sections: sections)))
        XCTAssertEqual(pdf.pageCount, 2)
        XCTAssertGreaterThan(try XCTUnwrap(pdf.page(at: 1)).bounds(for: .mediaBox).width,
                             try XCTUnwrap(pdf.page(at: 0)).bounds(for: .mediaBox).width)
        XCTAssertTrue(pdf.page(at: 1)?.string?.contains("Landscape bottom note") == true)
    }

    func testImportedDOCXFootnoteParticipatesInPhysicalPagination() throws {
        let imported = try DOCXImporter.text(from: fixture())
        let editor = paginated(imported)
        XCTAssertNil(editor.lastLayoutError)
        XCTAssertEqual(editor.pages[0].pageFootnotes.fragments.first?.text, "1. Word note\ttext")
        let pdf = try XCTUnwrap(PDFDocument(data: PDFExporter.data(from: imported, settings: PageSettings())))
        XCTAssertTrue(pdf.page(at: 0)?.string?.contains("Word note") == true)
        XCTAssertFalse(pdf.string?.contains("\n\nFootnotes\n") == true)
    }

    func testNativeReopenRetainsPageFootnoteOwnership() throws {
        let text = NSMutableAttributedString(string: "Persistent reference ", attributes: [.font: NSFont.systemFont(ofSize: 14)])
        text.append(Footnotes.marker(Footnote(text: "Saved bottom note", location: 0, length: 1), number: 1))
        let wrapper = try BOLDWriterDocument.packageWrapper(text: text, metadata: DocumentMetadata())
        let reopened = try BOLDWriterDocument(fileWrapper: wrapper, contentType: .boldWriterDocument)
        let editor = paginated(reopened.text)
        XCTAssertNil(editor.lastLayoutError)
        XCTAssertEqual(editor.pages[0].pageFootnotes.fragments.first?.text, "1. Saved bottom note")
    }

    func testUndoRedoRecomputesDerivedFootnoteLayout() throws {
        let (controller, view) = editor()
        change(view) { controller.insertFootnote(text: "Undoable page note") }
        XCTAssertEqual(paginated(view.attributedString()).pages[0].pageFootnotes.fragments.count, 1)
        view.manager.undo()
        XCTAssertTrue(paginated(view.attributedString()).pages[0].pageFootnotes.fragments.isEmpty)
        view.manager.redo()
        XCTAssertEqual(paginated(view.attributedString()).pages[0].pageFootnotes.fragments.first?.text,
                       "1. Undoable page note")
    }

    func testInlineFormattingSurvivesPhysicalFootnoteLayout() throws {
        let text = NSMutableAttributedString(string: "Styled body ",
                                             attributes: [.font: NSFont.boldSystemFont(ofSize: 16)])
        text.append(Footnotes.marker(Footnote(text: "Plain editable body", location: 0, length: 1), number: 1))
        let editor = paginated(text)
        XCTAssertNil(editor.lastLayoutError)
        let displayed = editor.flow.storage
        let font = try XCTUnwrap(displayed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
        XCTAssertEqual(displayed.attribute(.superscript, at: text.length - 1, effectiveRange: nil) as? Int, 1)
        XCTAssertEqual(editor.pages[0].pageFootnotes.fragments.first?.text, "1. Plain editable body")
    }

    func testPlainManuscriptDoesNotAcquireFootnoteRegion() throws {
        let text = NSAttributedString(string: String(repeating: "Plain manuscript without notes.\n", count: 120),
                                      attributes: [.font: NSFont.systemFont(ofSize: 14)])
        let editor = paginated(text)
        XCTAssertNil(editor.lastLayoutError)
        XCTAssertTrue(editor.pages.allSatisfy { $0.reservedFootnoteHeight == 0 && $0.pageFootnotes.fragments.isEmpty })
        var pdfRanges: [NSRange] = []
        _ = try PDFExporter.data(from: text, settings: PageSettings(), pageRangeSink: { pdfRanges = $0 })
        XCTAssertEqual(editor.pageRanges, pdfRanges)
    }

    func testTrackedAtomicFootnoteDeletionPreservesReferenceAndDOCXRevision()
        throws {
        let (controller, view) =
            editor()

        view.setSelectedRange(
            NSRange(
                location:
                    view.string.utf16.count,
                length: 0
            )
        )

        change(view) {
            controller.insertFootnote(
                text:
                    "Tracked note body"
            )
        }

        let originalNote =
            try XCTUnwrap(
                Footnotes.records(
                    in:
                        view.attributedString()
                )
                .first
            )

        let document =
            BOLDWriterDocument()

        document.replaceText(
            with:
                view.attributedString()
        )

        document.metadata
            .trackChangesEnabled = true

        let coordinator =
            RichTextEditor.Coordinator(
                document: document,
                controller: controller
            )

        view.delegate =
            coordinator

        let partial =
            NSRange(
                location:
                    originalNote.location,
                length: 1
            )

        change(view) {
            XCTAssertFalse(
                coordinator.textView(
                    view,
                    shouldChangeTextIn:
                        partial,
                    replacementString:
                        ""
                )
            )
        }

        let notesAfterDelete =
            try Footnotes.records(
                in:
                    view.attributedString()
            )

        XCTAssertEqual(
            notesAfterDelete.count,
            1
        )

        XCTAssertEqual(
            notesAfterDelete.first?
                .id,
            originalNote.id
        )

        XCTAssertEqual(
            notesAfterDelete.first?
                .text,
            "Tracked note body"
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

        let deletion =
            try XCTUnwrap(
                revisions.first
            )

        XCTAssertEqual(
            deletion.kind,
            .deletion
        )

        XCTAssertEqual(
            deletion.location,
            notesAfterDelete[0]
                .location
        )

        XCTAssertEqual(
            deletion.length,
            notesAfterDelete[0]
                .length
        )

        let data =
            try DOCXExporter.data(
                from:
                    view.attributedString(),
                title:
                    "Tracked Footnote"
            )

        let parts =
            Dictionary(
                uniqueKeysWithValues:
                    try DOCXPackage
                        .entries(in: data)
                        .map {
                            ($0.path, $0.data)
                        }
            )

        let main =
            try DOCXPackage.xml(
                XCTUnwrap(
                    parts[
                        "word/document.xml"
                    ]
                )
            )

        XCTAssertEqual(
            try main.nodes(
                forXPath:
                    "//*[local-name()='del']/*[local-name()='r']/*[local-name()='footnoteReference']"
            ).count,
            1
        )

        XCTAssertEqual(
            try main.nodes(
                forXPath:
                    "//*[local-name()='footnoteReference']"
            ).count,
            1
        )

        XCTAssertNotNil(
            parts[
                "word/footnotes.xml"
            ]
        )

        let imported =
            try DOCXImporter.text(
                from: data
            )

        let importedNotes =
            try Footnotes.records(
                in: imported
            )

        XCTAssertEqual(
            importedNotes.count,
            1
        )

        XCTAssertEqual(
            importedNotes.first?
                .text,
            "Tracked note body"
        )

        let importedRevisions =
            TrackChanges.records(
                in: imported
            )

        XCTAssertEqual(
            importedRevisions.count,
            1
        )

        XCTAssertEqual(
            importedRevisions.first?
                .kind,
            .deletion
        )

        XCTAssertEqual(
            importedRevisions.first?
                .location,
            importedNotes.first?
                .location
        )

        XCTAssertEqual(
            importedRevisions.first?
                .length,
            importedNotes.first?
                .length
        )
    }



    func testDeleteFootnoteCommandRespectsTrackChanges()
        throws {
        func insertedFootnote()
            throws
            -> (
                EditorController,
                FootnoteTextView,
                Footnote
            ) {
            let (controller, view) =
                editor()

            view.setSelectedRange(
                NSRange(
                    location:
                        view.string
                            .utf16
                            .count,
                    length: 0
                )
            )

            change(view) {
                controller.insertFootnote(
                    text:
                        "Command note"
                )
            }

            let note =
                try XCTUnwrap(
                    Footnotes.records(
                        in:
                            view.attributedString()
                    )
                    .first
                )

            return (
                controller,
                view,
                note
            )
        }

        do {
            let (
                controller,
                view,
                note
            ) =
                try insertedFootnote()

            change(view) {
                controller.deleteFootnote(
                    id: note.id,
                    trackChanges: false
                )
            }

            XCTAssertTrue(
                try Footnotes.records(
                    in:
                        view.attributedString()
                ).isEmpty
            )

            XCTAssertTrue(
                TrackChanges.records(
                    in:
                        view.attributedString()
                ).isEmpty
            )

            XCTAssertEqual(
                view.string,
                "Body"
            )
        }

        do {
            let (
                controller,
                view,
                note
            ) =
                try insertedFootnote()

            let originalString =
                view.string

            change(view) {
                controller.deleteFootnote(
                    id: note.id,
                    trackChanges: true
                )
            }

            let pendingNotes =
                try Footnotes.records(
                    in:
                        view.attributedString()
                )

            XCTAssertEqual(
                pendingNotes.count,
                1
            )

            XCTAssertEqual(
                pendingNotes.first?
                    .id,
                note.id
            )

            XCTAssertEqual(
                pendingNotes.first?
                    .text,
                "Command note"
            )

            XCTAssertEqual(
                view.string,
                originalString
            )

            let pendingChanges =
                TrackChanges.records(
                    in:
                        view.attributedString()
                )

            XCTAssertEqual(
                pendingChanges.count,
                1
            )

            XCTAssertEqual(
                pendingChanges.first?
                    .kind,
                .deletion
            )

            XCTAssertEqual(
                pendingChanges.first?
                    .location,
                note.location
            )

            XCTAssertEqual(
                pendingChanges.first?
                    .length,
                note.length
            )

            change(view) {
                controller.acceptAllTrackedChanges()
            }

            XCTAssertTrue(
                try Footnotes.records(
                    in:
                        view.attributedString()
                ).isEmpty
            )

            XCTAssertTrue(
                TrackChanges.records(
                    in:
                        view.attributedString()
                ).isEmpty
            )

            XCTAssertEqual(
                view.string,
                "Body"
            )
        }

        do {
            let (
                controller,
                view,
                note
            ) =
                try insertedFootnote()

            let originalString =
                view.string

            change(view) {
                controller.deleteFootnote(
                    id: note.id,
                    trackChanges: true
                )
            }

            change(view) {
                controller.rejectAllTrackedChanges()
            }

            let restoredNotes =
                try Footnotes.records(
                    in:
                        view.attributedString()
                )

            XCTAssertEqual(
                restoredNotes.count,
                1
            )

            XCTAssertEqual(
                restoredNotes.first?
                    .id,
                note.id
            )

            XCTAssertEqual(
                restoredNotes.first?
                    .text,
                "Command note"
            )

            XCTAssertEqual(
                view.string,
                originalString
            )

            XCTAssertTrue(
                TrackChanges.records(
                    in:
                        view.attributedString()
                ).isEmpty
            )
        }
    }



    func testInsertFootnoteCommandRespectsTrackChangesAndDOCXRoundTrip()
        throws {
        do {
            let (controller, view) =
                editor()

            view.setSelectedRange(
                NSRange(
                    location:
                        view.string
                            .utf16
                            .count,
                    length: 0
                )
            )

            change(view) {
                controller.insertFootnote(
                    text:
                        "Immediate note",
                    trackChanges:
                        false
                )
            }

            let notes =
                try Footnotes.records(
                    in:
                        view.attributedString()
                )

            XCTAssertEqual(
                notes.count,
                1
            )

            XCTAssertEqual(
                notes.first?
                    .text,
                "Immediate note"
            )

            XCTAssertTrue(
                TrackChanges.records(
                    in:
                        view.attributedString()
                ).isEmpty
            )

            XCTAssertEqual(
                view.string,
                "Body1"
            )
        }

        do {
            let (controller, view) =
                editor()

            view.setSelectedRange(
                NSRange(
                    location:
                        view.string
                            .utf16
                            .count,
                    length: 0
                )
            )

            change(view) {
                controller.insertFootnote(
                    text:
                        "Tracked inserted note",
                    trackChanges:
                        true
                )
            }

            let pendingNotes =
                try Footnotes.records(
                    in:
                        view.attributedString()
                )

            XCTAssertEqual(
                pendingNotes.count,
                1
            )

            let pendingNote =
                try XCTUnwrap(
                    pendingNotes.first
                )

            XCTAssertEqual(
                pendingNote.text,
                "Tracked inserted note"
            )

            XCTAssertEqual(
                pendingNote.id,
                controller.editingFootnote?
                    .id
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

            let insertion =
                try XCTUnwrap(
                    revisions.first
                )

            XCTAssertEqual(
                insertion.kind,
                .insertion
            )

            XCTAssertEqual(
                insertion.location,
                pendingNote.location
            )

            XCTAssertEqual(
                insertion.length,
                pendingNote.length
            )

            let data =
                try DOCXExporter.data(
                    from:
                        view.attributedString(),
                    title:
                        "Tracked Inserted Footnote"
                )

            let parts =
                Dictionary(
                    uniqueKeysWithValues:
                        try DOCXPackage
                            .entries(in: data)
                            .map {
                                (
                                    $0.path,
                                    $0.data
                                )
                            }
                )

            let main =
                try DOCXPackage.xml(
                    XCTUnwrap(
                        parts[
                            "word/document.xml"
                        ]
                    )
                )

            XCTAssertEqual(
                try main.nodes(
                    forXPath:
                        "//*[local-name()='ins']/*[local-name()='r']/*[local-name()='footnoteReference']"
                ).count,
                1
            )

            XCTAssertEqual(
                try main.nodes(
                    forXPath:
                        "//*[local-name()='footnoteReference']"
                ).count,
                1
            )

            XCTAssertNotNil(
                parts[
                    "word/footnotes.xml"
                ]
            )

            let imported =
                try DOCXImporter.text(
                    from: data
                )

            let importedNotes =
                try Footnotes.records(
                    in: imported
                )

            XCTAssertEqual(
                importedNotes.count,
                1
            )

            XCTAssertEqual(
                importedNotes.first?
                    .text,
                "Tracked inserted note"
            )

            let importedRevisions =
                TrackChanges.records(
                    in: imported
                )

            XCTAssertEqual(
                importedRevisions.count,
                1
            )

            XCTAssertEqual(
                importedRevisions.first?
                    .kind,
                .insertion
            )

            XCTAssertEqual(
                importedRevisions.first?
                    .location,
                importedNotes.first?
                    .location
            )

            XCTAssertEqual(
                importedRevisions.first?
                    .length,
                importedNotes.first?
                    .length
            )

            change(view) {
                controller.acceptAllTrackedChanges()
            }

            let acceptedNotes =
                try Footnotes.records(
                    in:
                        view.attributedString()
                )

            XCTAssertEqual(
                acceptedNotes.count,
                1
            )

            XCTAssertEqual(
                acceptedNotes.first?
                    .id,
                pendingNote.id
            )

            XCTAssertEqual(
                acceptedNotes.first?
                    .text,
                "Tracked inserted note"
            )

            XCTAssertTrue(
                TrackChanges.records(
                    in:
                        view.attributedString()
                ).isEmpty
            )

            XCTAssertEqual(
                view.string,
                "Body1"
            )
        }

        do {
            let (controller, view) =
                editor()

            view.setSelectedRange(
                NSRange(
                    location:
                        view.string
                            .utf16
                            .count,
                    length: 0
                )
            )

            change(view) {
                controller.insertFootnote(
                    text:
                        "Reject this note",
                    trackChanges:
                        true
                )
            }

            XCTAssertEqual(
                try Footnotes.records(
                    in:
                        view.attributedString()
                ).count,
                1
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

            change(view) {
                controller.rejectAllTrackedChanges()
            }

            XCTAssertTrue(
                try Footnotes.records(
                    in:
                        view.attributedString()
                ).isEmpty
            )

            XCTAssertTrue(
                TrackChanges.records(
                    in:
                        view.attributedString()
                ).isEmpty
            )

            XCTAssertEqual(
                view.string,
                "Body"
            )
        }
    }



    func testTrackedFootnotesSurviveNativeSaveCloseReopenAndResolution()
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

        func restoredEditor(
            _ text: NSAttributedString
        ) -> (
            EditorController,
            FootnoteTextView
        ) {
            let (controller, view) =
                editor()

            view.textStorage?
                .setAttributedString(text)

            controller
                .refreshTrackChangeDisplay()

            return (
                controller,
                view
            )
        }

        do {
            let (controller, view) =
                editor()

            change(view) {
                controller.insertFootnote(
                    text:
                        "Persisted insertion",
                    trackChanges:
                        true
                )
            }

            let originalNote =
                try XCTUnwrap(
                    Footnotes.records(
                        in:
                            view.attributedString()
                    )
                    .first
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

            let acceptedDocument =
                try reopen(
                    view.attributedString(),
                    tracking: true
                )

            XCTAssertEqual(
                acceptedDocument
                    .metadata
                    .trackChangesEnabled,
                true
            )

            let reopenedNote =
                try XCTUnwrap(
                    Footnotes.records(
                        in:
                            acceptedDocument.text
                    )
                    .first
                )

            XCTAssertEqual(
                reopenedNote.id,
                originalNote.id
            )

            XCTAssertEqual(
                reopenedNote.text,
                originalNote.text
            )

            XCTAssertEqual(
                TrackChanges.records(
                    in:
                        acceptedDocument.text
                )
                .filter {
                    $0.kind == .insertion
                }
                .count,
                1
            )

            let (
                acceptController,
                acceptView
            ) =
                restoredEditor(
                    acceptedDocument.text
                )

            change(acceptView) {
                acceptController
                    .acceptAllTrackedChanges()
            }

            let acceptedNote =
                try XCTUnwrap(
                    Footnotes.records(
                        in:
                            acceptView
                                .attributedString()
                    )
                    .first
                )

            XCTAssertEqual(
                acceptedNote.id,
                originalNote.id
            )

            XCTAssertEqual(
                acceptedNote.text,
                originalNote.text
            )

            XCTAssertTrue(
                TrackChanges.records(
                    in:
                        acceptView
                            .attributedString()
                )
                .isEmpty
            )

            let rejectedDocument =
                try reopen(
                    view.attributedString(),
                    tracking: true
                )

            let (
                rejectController,
                rejectView
            ) =
                restoredEditor(
                    rejectedDocument.text
                )

            change(rejectView) {
                rejectController
                    .rejectAllTrackedChanges()
            }

            XCTAssertTrue(
                try Footnotes.records(
                    in:
                        rejectView
                            .attributedString()
                )
                .isEmpty
            )

            XCTAssertEqual(
                rejectView.string,
                "Body"
            )

            XCTAssertTrue(
                TrackChanges.records(
                    in:
                        rejectView
                            .attributedString()
                )
                .isEmpty
            )
        }

        do {
            let (controller, view) =
                editor()

            change(view) {
                controller.insertFootnote(
                    text:
                        "Persisted deletion"
                )
            }

            let originalNote =
                try XCTUnwrap(
                    Footnotes.records(
                        in:
                            view.attributedString()
                    )
                    .first
                )

            change(view) {
                controller.deleteFootnote(
                    id:
                        originalNote.id,
                    trackChanges:
                        true
                )
            }

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

            let acceptedDocument =
                try reopen(
                    view.attributedString(),
                    tracking: false
                )

            XCTAssertEqual(
                acceptedDocument
                    .metadata
                    .trackChangesEnabled,
                false
            )

            let reopenedNote =
                try XCTUnwrap(
                    Footnotes.records(
                        in:
                            acceptedDocument.text
                    )
                    .first
                )

            XCTAssertEqual(
                reopenedNote.id,
                originalNote.id
            )

            XCTAssertEqual(
                reopenedNote.text,
                originalNote.text
            )

            XCTAssertEqual(
                TrackChanges.records(
                    in:
                        acceptedDocument.text
                )
                .filter {
                    $0.kind == .deletion
                }
                .count,
                1
            )

            let (
                acceptController,
                acceptView
            ) =
                restoredEditor(
                    acceptedDocument.text
                )

            change(acceptView) {
                acceptController
                    .acceptAllTrackedChanges()
            }

            XCTAssertTrue(
                try Footnotes.records(
                    in:
                        acceptView
                            .attributedString()
                )
                .isEmpty
            )

            XCTAssertEqual(
                acceptView.string,
                "Body"
            )

            XCTAssertTrue(
                TrackChanges.records(
                    in:
                        acceptView
                            .attributedString()
                )
                .isEmpty
            )

            let rejectedDocument =
                try reopen(
                    view.attributedString(),
                    tracking: false
                )

            let (
                rejectController,
                rejectView
            ) =
                restoredEditor(
                    rejectedDocument.text
                )

            change(rejectView) {
                rejectController
                    .rejectAllTrackedChanges()
            }

            let rejectedNote =
                try XCTUnwrap(
                    Footnotes.records(
                        in:
                            rejectView
                                .attributedString()
                    )
                    .first
                )

            XCTAssertEqual(
                rejectedNote.id,
                originalNote.id
            )

            XCTAssertEqual(
                rejectedNote.text,
                originalNote.text
            )

            XCTAssertTrue(
                TrackChanges.records(
                    in:
                        rejectView
                            .attributedString()
                )
                .isEmpty
            )
        }
    }


    func testFootnoteBodyEditsHonorTrackChangesNativePersistenceAndDOCX()
        throws {

        func note(
            in view: NSTextView
        ) throws -> Footnote {
            try XCTUnwrap(
                Footnotes.records(
                    in:
                        view.attributedString()
                )
                .first
            )
        }

        func editor(
            from text:
                NSAttributedString
        ) -> (
            EditorController,
            FootnoteTextView
        ) {
            let (controller, view) =
                self.editor()

            view.textStorage?
                .setAttributedString(text)

            controller
                .refreshTrackChangeDisplay()

            return (
                controller,
                view
            )
        }

        do {
            let (controller, view) =
                self.editor()

            change(view) {
                controller.insertFootnote(
                    text:
                        "Original"
                )
            }

            let original =
                try note(in: view)

            change(view) {
                controller.updateFootnote(
                    id:
                        original.id,
                    text:
                        "Immediate",
                    trackChanges:
                        false
                )
            }

            let updated =
                try note(in: view)

            XCTAssertEqual(
                updated.id,
                original.id
            )

            XCTAssertEqual(
                updated.text,
                "Immediate"
            )

            XCTAssertFalse(
                updated.hasPendingBodyChange
            )
        }

        let (
            sourceController,
            sourceView
        ) =
            self.editor()

        change(sourceView) {
            sourceController
                .insertFootnote(
                    text:
                        "Original body"
                )
        }

        let original =
            try note(
                in: sourceView
            )

        change(sourceView) {
            sourceController
                .updateFootnote(
                    id:
                        original.id,
                    text:
                        "Proposed body",
                    trackChanges:
                        true
                )
        }

        let pending =
            try note(
                in: sourceView
            )

        XCTAssertEqual(
            pending.id,
            original.id
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

        do {
            let (
                controller,
                view
            ) =
                editor(
                    from:
                        sourceView
                            .attributedString()
                )

            change(view) {
                controller
                    .acceptAllTrackedChanges()
            }

            let accepted =
                try note(in: view)

            XCTAssertEqual(
                accepted.id,
                original.id
            )

            XCTAssertEqual(
                accepted.text,
                "Proposed body"
            )

            XCTAssertFalse(
                accepted.hasPendingBodyChange
            )
        }

        do {
            let (
                controller,
                view
            ) =
                editor(
                    from:
                        sourceView
                            .attributedString()
                )

            change(view) {
                controller
                    .rejectAllTrackedChanges()
            }

            let rejected =
                try note(in: view)

            XCTAssertEqual(
                rejected.id,
                original.id
            )

            XCTAssertEqual(
                rejected.text,
                "Original body"
            )

            XCTAssertFalse(
                rejected.hasPendingBodyChange
            )
        }

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
            true

        try BOLDWriterDocument
            .packageWrapper(
                text:
                    sourceView
                        .attributedString(),
                metadata:
                    metadata
            )
            .write(
                to: url,
                options: .atomic,
                originalContentsURL:
                    nil
            )

        let reopened =
            try BOLDWriterDocument(
                fileWrapper:
                    FileWrapper(
                        url: url
                    ),
                contentType:
                    .boldWriterDocument
            )

        let reopenedNote =
            try XCTUnwrap(
                Footnotes.records(
                    in:
                        reopened.text
                )
                .first
            )

        XCTAssertEqual(
            reopenedNote.id,
            original.id
        )

        XCTAssertEqual(
            reopenedNote.text,
            "Proposed body"
        )

        XCTAssertEqual(
            reopenedNote
                .bodyChangeOriginalText,
            "Original body"
        )

        let data =
            try DOCXExporter.data(
                from:
                    reopened.text,
                title:
                    "Tracked Footnote Body"
            )

        let parts =
            Dictionary(
                uniqueKeysWithValues:
                    try DOCXPackage
                        .entries(
                            in: data
                        )
                        .map {
                            (
                                $0.path,
                                $0.data
                            )
                        }
            )

        let footnotes =
            try DOCXPackage.xml(
                XCTUnwrap(
                    parts[
                        "word/footnotes.xml"
                    ]
                )
            )

        XCTAssertEqual(
            try footnotes.nodes(
                forXPath:
                    "//*[local-name()='del']"
            ).count,
            1
        )

        XCTAssertEqual(
            try footnotes.nodes(
                forXPath:
                    "//*[local-name()='ins']"
            ).count,
            1
        )

        XCTAssertEqual(
            try footnotes.nodes(
                forXPath:
                    "//*[local-name()='delText']"
            ).count,
            1
        )

        XCTAssertEqual(
            try footnotes.nodes(
                forXPath:
                    "//*[local-name()='delText']"
            )
            .first?
            .stringValue,
            "Original body"
        )

        XCTAssertEqual(
            try footnotes.nodes(
                forXPath:
                    "//*[local-name()='ins']//*[local-name()='t']"
            )
            .first?
            .stringValue,
            "Proposed body"
        )

        let imported =
            try DOCXImporter.text(
                from: data
            )

        let importedNote =
            try XCTUnwrap(
                Footnotes.records(
                    in: imported
                )
                .first
            )

        XCTAssertEqual(
            importedNote.text,
            "Proposed body"
        )

        XCTAssertEqual(
            importedNote
                .bodyChangeOriginalText,
            "Original body"
        )

        XCTAssertTrue(
            importedNote
                .hasPendingBodyChange
        )

        let (
            importedController,
            importedView
        ) =
            editor(
                from:
                    imported
            )

        change(importedView) {
            importedController
                .rejectAllTrackedChanges()
        }

        XCTAssertEqual(
            try note(
                in:
                    importedView
            )
            .text,
            "Original body"
        )
    }


    func testTrackedFootnoteBodyEdgeCasesCoalesceRevertAndResolveWhenTrackingOff()
        throws {

        func firstNote(
            _ view: NSTextView
        ) throws -> Footnote {
            try XCTUnwrap(
                Footnotes.records(
                    in:
                        view.attributedString()
                )
                .first
            )
        }

        let (controller, view) =
            editor()

        change(view) {
            controller.insertFootnote(
                text:
                    "Original body"
            )
        }

        let original =
            try firstNote(view)

        change(view) {
            controller.updateFootnote(
                id:
                    original.id,
                text:
                    "First proposal",
                trackChanges:
                    true
            )
        }

        let first =
            try firstNote(view)

        let revisionID =
            try XCTUnwrap(
                first.bodyChangeID
            )

        let revisionAuthor =
            try XCTUnwrap(
                first.bodyChangeAuthor
            )

        let revisionDate =
            try XCTUnwrap(
                first.bodyChangeDate
            )

        XCTAssertEqual(
            first.bodyChangeOriginalText,
            "Original body"
        )

        change(view) {
            controller.updateFootnote(
                id:
                    original.id,
                text:
                    "Second proposal",
                trackChanges:
                    true
            )
        }

        let second =
            try firstNote(view)

        XCTAssertEqual(
            second.text,
            "Second proposal"
        )

        XCTAssertEqual(
            second.bodyChangeOriginalText,
            "Original body"
        )

        XCTAssertEqual(
            second.bodyChangeID,
            revisionID
        )

        XCTAssertEqual(
            second.bodyChangeAuthor,
            revisionAuthor
        )

        XCTAssertEqual(
            second.bodyChangeDate,
            revisionDate
        )

        let pendingSnapshot =
            view.attributedString()
                .copy()
                as! NSAttributedString

        // Undo the second tracked save.
        view.manager.undo()

        let afterUndo =
            try firstNote(view)

        XCTAssertEqual(
            afterUndo.text,
            "First proposal"
        )

        XCTAssertEqual(
            afterUndo.bodyChangeOriginalText,
            "Original body"
        )

        XCTAssertEqual(
            afterUndo.bodyChangeID,
            revisionID
        )

        // Redo the second tracked save.
        view.manager.redo()

        let afterRedo =
            try firstNote(view)

        XCTAssertEqual(
            afterRedo.text,
            "Second proposal"
        )

        XCTAssertEqual(
            afterRedo.bodyChangeID,
            revisionID
        )

        // Returning the proposal to the first original body
        // means there is no longer a change to review.
        change(view) {
            controller.updateFootnote(
                id:
                    original.id,
                text:
                    "Original body",
                trackChanges:
                    true
            )
        }

        let reverted =
            try firstNote(view)

        XCTAssertEqual(
            reverted.text,
            "Original body"
        )

        XCTAssertFalse(
            reverted.hasPendingBodyChange
        )

        XCTAssertNil(
            reverted.bodyChangeOriginalText
        )

        XCTAssertNil(
            reverted.bodyChangeID
        )

        XCTAssertNil(
            reverted.bodyChangeAuthor
        )

        XCTAssertNil(
            reverted.bodyChangeDate
        )

        // Undoing the revert restores the exact pending
        // aggregate revision.
        view.manager.undo()

        let restoredPending =
            try firstNote(view)

        XCTAssertEqual(
            restoredPending.text,
            "Second proposal"
        )

        XCTAssertEqual(
            restoredPending.bodyChangeOriginalText,
            "Original body"
        )

        XCTAssertEqual(
            restoredPending.bodyChangeID,
            revisionID
        )

        XCTAssertEqual(
            restoredPending.bodyChangeAuthor,
            revisionAuthor
        )

        XCTAssertEqual(
            restoredPending.bodyChangeDate,
            revisionDate
        )

        view.manager.redo()

        XCTAssertFalse(
            try firstNote(view)
                .hasPendingBodyChange
        )

        // ----------------------------------------------------
        // Turning document Track Changes off must not strand
        // an already-pending body revision.
        // ----------------------------------------------------

        do {
            let document =
                BOLDWriterDocument()

            document.replaceText(
                with:
                    pendingSnapshot
            )

            document.metadata
                .trackChangesEnabled =
                false

            XCTAssertEqual(
                document.metadata
                    .trackChangesEnabled,
                false
            )

            let (
                offController,
                offView
            ) =
                editor()

            offView.textStorage?
                .setAttributedString(
                    document.text
                )

            offController
                .refreshTrackChangeDisplay()

            let pending =
                try firstNote(
                    offView
                )

            XCTAssertTrue(
                pending.hasPendingBodyChange
            )

            offView.setSelectedRange(
                NSRange(
                    location:
                        pending.location,
                    length:
                        pending.length
                )
            )

            change(offView) {
                offController
                    .rejectTrackedChangeAtSelection()
            }

            let rejected =
                try firstNote(
                    offView
                )

            XCTAssertEqual(
                rejected.text,
                "Original body"
            )

            XCTAssertFalse(
                rejected.hasPendingBodyChange
            )
        }

        do {
            let document =
                BOLDWriterDocument()

            document.replaceText(
                with:
                    pendingSnapshot
            )

            document.metadata
                .trackChangesEnabled =
                false

            let (
                offController,
                offView
            ) =
                editor()

            offView.textStorage?
                .setAttributedString(
                    document.text
                )

            offController
                .refreshTrackChangeDisplay()

            change(offView) {
                offController
                    .acceptAllTrackedChanges()
            }

            let accepted =
                try firstNote(
                    offView
                )

            XCTAssertEqual(
                accepted.text,
                "Second proposal"
            )

            XCTAssertFalse(
                accepted.hasPendingBodyChange
            )
        }
    }

    func testTrackedFootnoteBodyDOCXSpecialCharactersAndRevisionMetadata()
        throws {

        let originalBody =
            "Old & <body>\tαβ\n"
            + "Second \"line\" 😀"

        let proposedBody =
            "New & <body>\tγδ\n"
            + "Second 'line' 🚀"

        let revisionID =
            UUID()

        let revisionDate =
            Date(
                timeIntervalSince1970:
                    1_700_000_000
            )

        var note =
            Footnote(
                text:
                    proposedBody,
                location: 4,
                length: 1
            )

        note.bodyChangeOriginalText =
            originalBody

        note.bodyChangeID =
            revisionID

        note.bodyChangeAuthor =
            "Word Reviewer"

        note.bodyChangeDate =
            revisionDate

        let source =
            NSMutableAttributedString(
                string:
                    "Body"
            )

        source.append(
            Footnotes.marker(
                note,
                number: 1
            )
        )

        let data =
            try DOCXExporter.data(
                from: source,
                title:
                    "Tracked Footnote Special Characters"
            )

        let parts =
            Dictionary(
                uniqueKeysWithValues:
                    try DOCXPackage
                        .entries(
                            in: data
                        )
                        .map {
                            (
                                $0.path,
                                $0.data
                            )
                        }
            )

        let footnotesData =
            try XCTUnwrap(
                parts[
                    "word/footnotes.xml"
                ]
            )

        let footnotesXML =
            String(
                decoding:
                    footnotesData,
                as:
                    UTF8.self
            )

        XCTAssertTrue(
            footnotesXML
                .contains(
                    "<w:tab/>"
                )
        )

        let footnotes =
            try DOCXPackage.xml(
                footnotesData
            )

        XCTAssertEqual(
            try footnotes.nodes(
                forXPath:
                    "//*[local-name()='del']//*[local-name()='tab']"
            ).count,
            1
        )

        XCTAssertEqual(
            try footnotes.nodes(
                forXPath:
                    "//*[local-name()='ins']//*[local-name()='tab']"
            ).count,
            1
        )

        XCTAssertEqual(
            try footnotes.nodes(
                forXPath:
                    "//*[local-name()='del']//*[local-name()='br']"
            ).count,
            1
        )

        XCTAssertEqual(
            try footnotes.nodes(
                forXPath:
                    "//*[local-name()='ins']//*[local-name()='br']"
            ).count,
            1
        )

        let imported =
            try DOCXImporter.text(
                from: data
            )

        let importedNote =
            try XCTUnwrap(
                Footnotes.records(
                    in: imported
                )
                .first
            )

        XCTAssertEqual(
            importedNote.text,
            proposedBody
        )

        XCTAssertEqual(
            importedNote
                .bodyChangeOriginalText,
            originalBody
        )

        XCTAssertEqual(
            importedNote
                .bodyChangeAuthor,
            "Word Reviewer"
        )

        XCTAssertEqual(
            importedNote
                .bodyChangeDate,
            revisionDate
        )

        XCTAssertTrue(
            importedNote
                .hasPendingBodyChange
        )

        // ----------------------------------------------------
        // Independent Word-style revision metadata import.
        // ----------------------------------------------------

        let wordDate =
            "2026-09-18T12:34:56Z"

        let wordBody =
            """
            <w:r><w:footnoteRef/></w:r>
            <w:del w:id="7" w:author="Alice Reviewer" w:date="\(wordDate)"><w:r><w:delText>Old Word body</w:delText></w:r></w:del>
            <w:ins w:id="8" w:author="Alice Reviewer" w:date="\(wordDate)"><w:r><w:t>New Word body</w:t></w:r></w:ins>
            """

        let wordImported =
            try DOCXImporter.text(
                from:
                    fixture(
                        body:
                            wordBody
                    )
            )

        let wordNote =
            try XCTUnwrap(
                Footnotes.records(
                    in:
                        wordImported
                )
                .first
            )

        XCTAssertEqual(
            wordNote.text,
            "New Word body"
        )

        XCTAssertEqual(
            wordNote
                .bodyChangeOriginalText,
            "Old Word body"
        )

        XCTAssertEqual(
            wordNote
                .bodyChangeAuthor,
            "Alice Reviewer"
        )

        XCTAssertEqual(
            wordNote
                .bodyChangeDate,
            ISO8601DateFormatter()
                .date(
                    from:
                        wordDate
                )
        )

        XCTAssertTrue(
            wordNote
                .hasPendingBodyChange
        )
    }

    func testRecoveryPointPreservesPendingFootnoteBodyRevisionMetadata()
        throws {

        let (controller, view) =
            editor()

        change(view) {
            controller.insertFootnote(
                text:
                    "Recovery original"
            )
        }

        let original =
            try XCTUnwrap(
                Footnotes.records(
                    in:
                        view.attributedString()
                )
                .first
            )

        change(view) {
            controller.updateFootnote(
                id:
                    original.id,
                text:
                    "Recovery proposal",
                trackChanges:
                    true
            )
        }

        let pending =
            try XCTUnwrap(
                Footnotes.records(
                    in:
                        view.attributedString()
                )
                .first
            )

        let pendingID =
            try XCTUnwrap(
                pending.bodyChangeID
            )

        let pendingAuthor =
            try XCTUnwrap(
                pending.bodyChangeAuthor
            )

        let pendingDate =
            try XCTUnwrap(
                pending.bodyChangeDate
            )

        let document =
            BOLDWriterDocument()

        document.replaceText(
            with:
                view.attributedString()
        )

        XCTAssertTrue(
            document.createRevision(
                named:
                    "Pending footnote body"
            )
        )

        let revision =
            try XCTUnwrap(
                document.metadata
                    .revisions
                    .first
            )

        document.replaceText(
            with:
                NSAttributedString(
                    string:
                        "Temporary replacement"
                )
        )

        try document.restore(
            revision
        )

        let restored =
            try XCTUnwrap(
                Footnotes.records(
                    in:
                        document.text
                )
                .first
            )

        XCTAssertEqual(
            restored.id,
            original.id
        )

        XCTAssertEqual(
            restored.text,
            "Recovery proposal"
        )

        XCTAssertEqual(
            restored
                .bodyChangeOriginalText,
            "Recovery original"
        )

        XCTAssertEqual(
            restored
                .bodyChangeID,
            pendingID
        )

        XCTAssertEqual(
            restored
                .bodyChangeAuthor,
            pendingAuthor
        )

        XCTAssertEqual(
            restored
                .bodyChangeDate,
            pendingDate
        )

        XCTAssertTrue(
            restored
                .hasPendingBodyChange
        )

        XCTAssertEqual(
            TrackChanges.reviewItems(
                in:
                    document.text
            )
            .filter {
                $0.kind
                    == .footnoteBodyEdit
            }
            .count,
            1
        )
    }

}
