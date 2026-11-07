import AppKit
import XCTest
@testable import BOLDWriter

@MainActor
final class DynamicFieldsTests: XCTestCase {
    private func editor(for document: BOLDWriterDocument) -> (EditorController, WritingTextView) {
        let controller = EditorController()
        let view = WritingTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 800))
        view.textStorage?.setAttributedString(document.text)
        controller.document = document
        controller.attach(view)
        return (controller, view)
    }

    private func fieldRuns(_ text: NSAttributedString) -> [(WordField, NSRange)] {
        var result: [(WordField, NSRange)] = []
        guard text.length > 0 else { return result }
        text.enumerateAttribute(.boldWriterField, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            if let field = value as? WordField { result.append((field, range)) }
        }
        return result
    }

    func testTOCIsSemanticPersistentFieldAndUpdatesHeadingText() throws {
        let text = NSMutableAttributedString(string: "Overview\nDetails\n")
        text.addAttribute(.boldWriterStyle, value: WriterStyle.heading1.rawValue, range: NSRange(location: 0, length: 9))
        text.addAttribute(.boldWriterStyle, value: WriterStyle.heading2.rawValue, range: NSRange(location: 9, length: 8))
        let document = BOLDWriterDocument()
        document.replaceText(with: text)
        let (controller, view) = editor(for: document)
        view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
        controller.insertTableOfContents(levels: 2)

        let toc = try XCTUnwrap(fieldRuns(view.attributedString()).first { $0.0.instruction.contains("TOC") })
        XCTAssertEqual(toc.0.kind, .complex)
        XCTAssertTrue(toc.0.instruction.contains("1-2"))
        XCTAssertTrue(view.string.contains("Overview"))
        XCTAssertTrue(view.string.contains("Details"))
        XCTAssertGreaterThan(fieldRuns(view.attributedString()).filter { $0.0.instruction.contains("TOC") }.count, 0)
        XCTAssertTrue((0..<view.textStorage!.length).contains { view.textStorage!.attribute(.link, at: $0, effectiveRange: nil) != nil })
        XCTAssertEqual(document.metadata.bookmarks.filter { $0.name.hasPrefix("BOLDH_") }.count, 2, "anchors: \(document.metadata.bookmarks.map { ($0.name, $0.location, $0.length) }) text: \(view.string)")
        let saved = try BOLDWriterDocument.packageWrapper(text: view.attributedString(), metadata: document.metadata)
        let reopened = try BOLDWriterDocument(fileWrapper: saved, contentType: .boldWriterDocument)
        let restoredField = try XCTUnwrap(fieldRuns(reopened.text).first?.0)
        XCTAssertEqual(restoredField.id, toc.0.id)
        XCTAssertEqual(restoredField.instruction, toc.0.instruction)
        XCTAssertTrue(reopened.text.string.contains("Details"))

        let docx = try DOCXExporter.data(from: view.attributedString(), title: "Dynamic TOC", bookmarks: document.metadata.bookmarks)
        let docxWrapper = FileWrapper(regularFileWithContents: docx)
        docxWrapper.preferredFilename = "Dynamic TOC.docx"
        let importedDOCX = try BOLDWriterDocument(fileWrapper: docxWrapper, contentType: .docx)
        let importedTOC = try XCTUnwrap(fieldRuns(importedDOCX.text).first { $0.0.instruction.contains("TOC") }?.0)
        XCTAssertEqual(importedTOC.instruction, toc.0.instruction)
        XCTAssertTrue(importedDOCX.text.string.contains("Overview"))
    }

    func testCaptionSEQSequencesAreIndependentAndUpdateAfterDeletion() throws {
        let document = BOLDWriterDocument()
        document.replaceText(with: NSAttributedString(string: ""))
        let (controller, view) = editor(for: document)
        func appendCaption(_ label: String, _ title: String) throws {
            view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
            try controller.insertCaption(label: label, title: title)
        }
        try appendCaption("Figure", "Architecture")
        try appendCaption("Figure", "Details")
        try appendCaption("Table", "Results")
        try appendCaption("Photograph", "Street")
        try appendCaption("Appendix Figure", "Supplement")
        XCTAssertEqual(fieldRuns(view.attributedString()).filter { $0.0.instruction.contains("SEQ Figure") }.count, 2)
        XCTAssertTrue(view.string.contains("Figure 1 — Architecture"), view.string)
        XCTAssertTrue(view.string.contains("Figure 2 — Details"), view.string)
        XCTAssertTrue(view.string.contains("Table 1 — Results"))
        XCTAssertTrue(view.string.contains("Photograph 1 — Street"))
        XCTAssertTrue(view.string.contains("Appendix Figure 1 — Supplement"))
        XCTAssertTrue(fieldRuns(view.attributedString()).contains { $0.0.instruction.contains("SEQ AppendixFigure") })
        XCTAssertTrue(NamedStyleDefinition.builtIns.contains { $0.styleID == "Caption" && $0.kind == .paragraph })
        let captionPoint = (view.string as NSString).range(of: "Figure").location
        let captionStyle = view.textStorage?.attribute(.boldWriterParagraphStyle, at: captionPoint, effectiveRange: nil) as? WordParagraphStyle
        XCTAssertEqual(captionStyle?.styleID, "Caption")
        let captionBookmark = try XCTUnwrap(document.metadata.bookmarks.first { $0.name.hasPrefix("BOLDCap_") })
        controller.insertCrossReference(to: captionBookmark)
        XCTAssertTrue(fieldRuns(view.attributedString()).contains { $0.0.instruction.contains("REF \(captionBookmark.name)") })

        let saved = try BOLDWriterDocument.packageWrapper(text: view.attributedString(), metadata: document.metadata)
        let reopened = try BOLDWriterDocument(fileWrapper: saved, contentType: .boldWriterDocument)
        XCTAssertEqual(Set(fieldRuns(reopened.text).map { $0.0.id }), Set(fieldRuns(view.attributedString()).map { $0.0.id }))
        XCTAssertTrue(fieldRuns(reopened.text).contains { $0.0.instruction.contains("SEQ Photograph") })

        let secondFigure = try XCTUnwrap(view.string.range(of: "Figure 2 — Details"), view.string)
        let secondRange = NSRange(secondFigure, in: view.string)
        view.setSelectedRange(secondRange)
        view.insertText("", replacementRange: secondRange)
        _ = controller.updateAllFields(in: document)
        XCTAssertTrue(view.string.contains("Figure 1 — Architecture"))
        XCTAssertFalse(view.string.contains("Figure 2 — Details"))
        XCTAssertTrue(view.string.contains("Table 1 — Results"))
    }

    func testSEQRestartAndRepeatSwitchesAndTrackMetadataArePreserved() throws {
        let document = BOLDWriterDocument()
        let field1 = WordField(kind: .simple, instruction: " SEQ Equation ")
        let field2 = WordField(kind: .simple, instruction: " SEQ Equation \\r 4 ")
        let field3 = WordField(kind: .simple, instruction: " SEQ Equation ")
        let field4 = WordField(kind: .simple, instruction: " SEQ Equation \\c ")
        let text = NSMutableAttributedString(string: "1 4 5 5")
        for (field, loc) in [(field1, 0), (field2, 2), (field3, 4), (field4, 6)] {
            text.addAttribute(.boldWriterField, value: field, range: NSRange(location: loc, length: 1))
        }
        text.addAttribute(.boldWriterTrackChange, value: "revision-token", range: NSRange(location: 0, length: 1))
        document.replaceText(with: text)
        let (controller, view) = editor(for: document)
        _ = controller.updateAllFields(in: document)
        XCTAssertEqual(view.string, "1 4 5 5")
        XCTAssertEqual(view.textStorage?.attribute(.boldWriterTrackChange, at: 0, effectiveRange: nil) as? String, "revision-token")
        XCTAssertEqual(Set(fieldRuns(view.attributedString()).map { $0.0.id }).count, 4)
    }

    func testSEQFieldSurvivesDOCXRoundTripAsField() throws {
        let field = WordField(kind: .simple, instruction: " SEQ Figure \\* ARABIC ")
        let text = NSMutableAttributedString(string: "Figure 7 — Example")
        text.addAttribute(.boldWriterField, value: field, range: NSRange(location: 7, length: 1))
        let data = try DOCXExporter.data(from: text, title: "SEQ")
        let wrapper = FileWrapper(regularFileWithContents: data)
        wrapper.preferredFilename = "SEQ.docx"
        let imported = try BOLDWriterDocument(fileWrapper: wrapper, contentType: .docx)
        let restored = try XCTUnwrap(fieldRuns(imported.text).first?.0)
        XCTAssertEqual(restored.instruction, field.instruction)
        XCTAssertEqual(restored.kind, .simple)
    }

    func testPAGEREFUsesLivePrintPaginationWhenAvailable() throws {
        let paragraph = "Pagination determines reference numbers through TextKit layout rather than character-count estimates. "
        let text = NSMutableAttributedString(string: Array(repeating: paragraph, count: 180).joined(separator: "\n"), attributes: [.font: NSFont.systemFont(ofSize: 12)])
        let targetLocation = text.length - 40
        let bookmark = DocumentBookmark(name: "LastPage", location: targetLocation, length: 10)
        let field = WordField(kind: .simple, instruction: " PAGEREF LastPage \\h ")
        text.insert(NSAttributedString(string: "? ", attributes: [.boldWriterField: field]), at: 0)
        let document = BOLDWriterDocument()
        document.replaceText(with: text)
        document.metadata.bookmarks = [DocumentBookmark(name: bookmark.name, location: bookmark.location + 2, length: bookmark.length)]

        let canvas = PaginatedEditor(text: text)
        canvas.configure(printLayout: true, settings: PageSettings(), zoom: 1, viewportWidth: 850)
        canvas.finishPagination()
        XCTAssertGreaterThan(canvas.pages.count, 1)
        let controller = EditorController()
        controller.document = document
        controller.attach(canvas.firstView)
        XCTAssertNotNil(canvas.displayPageNumber(containing: bookmark.location + 2))
        _ = controller.updateAllFields(in: document)
        XCTAssertNotEqual((canvas.firstView.string as NSString).substring(to: 1), "?")
    }

    func testTOCLevelRangeCoversAllSixSemanticHeadingStyles() throws {
        let text = NSMutableAttributedString(string: (1...6).map { "Level \($0)" }.joined(separator: "\n") + "\n")
        let source = text.string as NSString
        for level in 1...6 {
            let range = source.range(of: "Level \(level)")
            text.addAttribute(.boldWriterStyle, value: WriterStyle.allCases.first { $0.headingLevel == level }!.rawValue, range: range)
        }
        let document = BOLDWriterDocument()
        document.replaceText(with: text)
        let (controller, view) = editor(for: document)
        view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
        controller.insertTableOfContents(levels: 3)
        XCTAssertTrue(view.string.contains("Level 3"))
        XCTAssertFalse(view.string.contains("Level 4\t"))

        let tocField = try XCTUnwrap(fieldRuns(view.attributedString()).first { $0.0.instruction.contains("TOC") })
        view.setSelectedRange(NSRange(location: tocField.1.location, length: 0))
        controller.removeSelectedTableOfContents()
        XCTAssertFalse(view.string.contains("Table of Contents"))
        view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
        controller.insertTableOfContents(levels: 6)
        XCTAssertTrue(view.string.contains("Level 6"))
        XCTAssertTrue(fieldRuns(view.attributedString()).contains { $0.0.instruction.contains("1-6") })
    }

    func testCaptionFieldsRemainSafeAcrossTrackedEditsAndFieldRefresh() throws {
        let document = BOLDWriterDocument()
        document.replaceText(with: NSAttributedString(string: "Near text."))
        document.metadata.trackChangesEnabled = true
        let (controller, view) = editor(for: document)
        controller.trackChangesProvider = { true }
        view.trackChangesProvider = { true }
        view.setSelectedRange(NSRange(location: 0, length: 0))
        try controller.insertCaption(label: "Figure", title: "Tracked caption")

        let captionField = try XCTUnwrap(fieldRuns(view.attributedString()).first { $0.0.instruction.contains("SEQ Figure") })
        let identity = captionField.0.id
        XCTAssertNotNil(view.textStorage?.attribute(.boldWriterTrackChange, at: captionField.1.location, effectiveRange: nil))
        let trackedIDsBeforeRefresh = Set(TrackChanges.reviewItems(in: view.attributedString()).map(\.id))
        XCTAssertFalse(trackedIDsBeforeRefresh.isEmpty)
        _ = controller.updateAllFields(in: document)
        XCTAssertEqual(Set(TrackChanges.reviewItems(in: view.attributedString()).map(\.id)), trackedIDsBeforeRefresh)
        XCTAssertEqual(fieldRuns(view.attributedString()).first { $0.0.id == identity }?.0.instruction, " SEQ Figure \\* ARABIC ")

        let near = (view.string as NSString).range(of: "Near")
        controller.replace(range: near, with: NSAttributedString(string: "Close"), actionName: "Tracked replacement", trackChanges: true)
        let pending = TrackChanges.reviewItems(in: view.attributedString()).filter { !trackedIDsBeforeRefresh.contains($0.id) }
        XCTAssertGreaterThanOrEqual(pending.count, 2)
        for id in pending.map(\.id) {
            guard let item = TrackChanges.reviewItems(in: view.attributedString()).first(where: { $0.id == id }) else { continue }
            controller.selectTrackedChange(item)
            controller.rejectTrackedChangeAtSelection()
        }
        XCTAssertTrue(view.string.contains("Near text."))
        XCTAssertNotNil(fieldRuns(view.attributedString()).first { $0.0.id == identity })

        let end = view.string.utf16.count
        controller.replace(range: NSRange(location: end, length: 0), with: NSAttributedString(string: "!"), actionName: "Tracked insertion", trackChanges: true)
        let accepted = try XCTUnwrap(TrackChanges.reviewItems(in: view.attributedString()).first { $0.preview.contains("!") })
        controller.selectTrackedChange(accepted)
        controller.acceptTrackedChangeAtSelection()
        XCTAssertTrue(view.string.hasSuffix("!"))
        XCTAssertNotNil(fieldRuns(view.attributedString()).first { $0.0.id == identity })
        XCTAssertNoThrow(try DocumentBookmarks.validate(document.metadata.bookmarks, textLength: view.string.utf16.count))
    }

    func testMalformedAndUnresolvedFieldsFailSafely() throws {
        let document = BOLDWriterDocument()
        let fields = [
            WordField(kind: .simple, instruction: " SEQ "),
            WordField(kind: .simple, instruction: " SEQ Figure \\r invalid "),
            WordField(kind: .simple, instruction: " SEQ Figure \\x unknown "),
            WordField(kind: .simple, instruction: " TOC \\o \"bad-range\" "),
            WordField(kind: .simple, instruction: " REF Missing "),
            WordField(kind: .simple, instruction: " PAGEREF Missing ")
        ]
        let text = NSMutableAttributedString(string: "abcdef")
        for (field, location) in zip(fields, 0..<fields.count) {
            text.addAttribute(.boldWriterField, value: field, range: NSRange(location: location, length: 1))
        }
        document.replaceText(with: text)
        let (controller, view) = editor(for: document)
        XCTAssertNoThrow(controller.updateAllFields(in: document))
        XCTAssertEqual((view.string as NSString).substring(to: 4), "abcd")
        XCTAssertEqual((view.string as NSString).substring(from: 4), "??")
        XCTAssertEqual(fieldRuns(view.attributedString()).map { $0.0.instruction }, fields.map(\.instruction))

        let heading = NSMutableAttributedString(string: "Heading\n")
        heading.addAttribute(.boldWriterStyle, value: WriterStyle.heading1.rawValue, range: NSRange(location: 0, length: 7))
        document.replaceText(with: heading)
        view.textStorage?.setAttributedString(heading)
        let first = controller.ensureHeadingBookmarks(in: document)
        let second = controller.ensureHeadingBookmarks(in: document)
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(second.map(\.id), first.map(\.id))
    }

    func testIndependentWordDOCXFieldsImportAndReexportWithoutFlattening() throws {
        let w = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
        let r = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
        let documentXML = """
        <w:document xmlns:w="\(w)"><w:body>
          <w:p><w:r><w:fldChar w:fldCharType="begin"/></w:r><w:r><w:instrText xml:space="preserve"> TOC \\o "1-3" \\h </w:instrText></w:r><w:r><w:fldChar w:fldCharType="separate"/></w:r><w:r><w:t>Contents</w:t></w:r><w:r><w:fldChar w:fldCharType="end"/></w:r></w:p>
          <w:p><w:bookmarkStart w:id="4" w:name="Fig1"/><w:r><w:t>Figure </w:t></w:r><w:r><w:fldChar w:fldCharType="begin"/></w:r><w:r><w:instrText xml:space="preserve"> SEQ Figure \\* ARABIC </w:instrText></w:r><w:r><w:fldChar w:fldCharType="separate"/></w:r><w:r><w:t>1</w:t></w:r><w:r><w:fldChar w:fldCharType="end"/></w:r><w:r><w:t> — Roof</w:t></w:r><w:bookmarkEnd w:id="4"/></w:p>
          <w:p><w:r><w:t>See </w:t></w:r><w:r><w:fldChar w:fldCharType="begin"/></w:r><w:r><w:instrText xml:space="preserve"> REF Fig1 \\h </w:instrText></w:r><w:r><w:fldChar w:fldCharType="separate"/></w:r><w:r><w:t>Figure 1</w:t></w:r><w:r><w:fldChar w:fldCharType="end"/></w:r><w:r><w:t>.</w:t></w:r></w:p>
          <w:sectPr/></w:body></w:document>
        """
        let parts = [
            ZipEntry(path: "[Content_Types].xml", data: Data("<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/></Types>".utf8)),
            ZipEntry(path: "_rels/.rels", data: Data("<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"document\" Type=\"\(r)/officeDocument\" Target=\"word/document.xml\"/></Relationships>".utf8)),
            ZipEntry(path: "word/_rels/document.xml.rels", data: Data("<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"></Relationships>".utf8)),
            ZipEntry(path: "word/document.xml", data: Data(documentXML.utf8))
        ]
        let fixture = ZipArchiveWriter.archive(parts)
        let imported = try DOCXImporter.importedDocument(from: fixture)
        let instructions = fieldRuns(imported.text).map { $0.0.instruction }
        XCTAssertTrue(instructions.contains { $0.contains("TOC") })
        XCTAssertTrue(instructions.contains { $0.contains("SEQ Figure") })
        XCTAssertTrue(instructions.contains { $0.contains("REF Fig1") })
        let exported = try DOCXExporter.data(from: imported.text, title: "Independent Word Fields", bookmarks: imported.bookmarks)
        let entries = try DOCXPackage.entries(in: exported)
        let main = try DOCXPackage.xml(XCTUnwrap(entries.first { $0.path == "word/document.xml" }?.data))
        let instructionsOut = try main.nodes(forXPath: "//*[local-name()='instrText']").compactMap { $0.stringValue }
        XCTAssertTrue(instructionsOut.contains { $0.contains("TOC") })
        XCTAssertTrue(instructionsOut.contains { $0.contains("SEQ Figure") })
        XCTAssertTrue(instructionsOut.contains { $0.contains("REF Fig1") })
        XCTAssertGreaterThanOrEqual(try main.nodes(forXPath: "//*[local-name()='fldChar']").count, 9)
    }

    func testTableCaptionPreservesWriterTableThroughFieldUpdateAndDOCX() throws {
        var table = try WriterTable(rows: 2, columns: 2)
        table.cells[0][0] = NSAttributedString(string: "Name")
        table.cells[0][1] = NSAttributedString(string: "Result")
        table.cells[1][0] = NSAttributedString(string: "Alpha")
        table.cells[1][1] = NSAttributedString(string: "42")
        let tableText = NSMutableAttributedString(string: "Table follows\n")
        tableText.append(try Tables.rendered(table))
        let document = BOLDWriterDocument()
        document.replaceText(with: tableText)
        let (controller, view) = editor(for: document)
        let originalID = try XCTUnwrap(Tables.models(in: view.attributedString()).first?.id)
        view.setSelectedRange(NSRange(location: 0, length: 0))
        try controller.insertCaption(label: "Table", title: "Results")
        _ = controller.updateAllFields(in: document)

        XCTAssertTrue(view.string.contains("Table 1 — Results"))
        XCTAssertEqual(try Tables.models(in: view.attributedString()).map(\.id), [originalID])
        XCTAssertTrue(fieldRuns(view.attributedString()).contains { $0.0.instruction.contains("SEQ Table") })

        let docx = try DOCXExporter.data(from: view.attributedString(), title: "Table caption", bookmarks: document.metadata.bookmarks)
        let wrapper = FileWrapper(regularFileWithContents: docx)
        wrapper.preferredFilename = "Table caption.docx"
        let imported = try BOLDWriterDocument(fileWrapper: wrapper, contentType: .docx)
        XCTAssertEqual(try Tables.models(in: imported.text).count, 1)
        XCTAssertTrue(fieldRuns(imported.text).contains { $0.0.instruction.contains("SEQ Table") })
        XCTAssertTrue(imported.text.string.contains("Table 1 — Results"))
    }

    func testTOCAndSEQFieldsCoexistWithFootnotesAndEndnotesInDOCX() throws {
        let text = NSMutableAttributedString(string: "Chapter\nBody ")
        text.addAttribute(.boldWriterStyle, value: WriterStyle.heading1.rawValue, range: NSRange(location: 0, length: 7))
        let seq = WordField(kind: .simple, instruction: " SEQ Equation \\* ARABIC ")
        text.append(NSAttributedString(string: "1", attributes: [.boldWriterField: seq]))
        text.append(NSAttributedString(string: " "))
        text.append(Footnotes.marker(Footnote(text: "Footnote body", location: text.length, length: 1), number: 1))
        text.append(NSAttributedString(string: " "))
        text.append(Endnotes.marker(Endnote(text: "Endnote body", location: text.length, length: 1), number: 1))

        let document = BOLDWriterDocument()
        document.replaceText(with: text)
        let (controller, view) = editor(for: document)
        view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
        controller.insertTableOfContents(levels: 1)
        _ = controller.updateAllFields(in: document)
        XCTAssertEqual(try Footnotes.records(in: view.attributedString()).count, 1)
        XCTAssertEqual(try Endnotes.records(in: view.attributedString()).count, 1)

        let data = try DOCXExporter.data(from: view.attributedString(), title: "Notes and fields", bookmarks: document.metadata.bookmarks)
        let wrapper = FileWrapper(regularFileWithContents: data)
        wrapper.preferredFilename = "Notes and fields.docx"
        let imported = try BOLDWriterDocument(fileWrapper: wrapper, contentType: .docx)
        XCTAssertEqual(try Footnotes.records(in: imported.text).map(\.text), ["Footnote body"])
        XCTAssertEqual(try Endnotes.records(in: imported.text).map(\.text), ["Endnote body"])
        XCTAssertTrue(fieldRuns(imported.text).contains { $0.0.instruction.contains("TOC") })
        XCTAssertTrue(fieldRuns(imported.text).contains { $0.0.instruction.contains("SEQ Equation") })
    }

    func testMalformedNativeFieldMetadataFailsSafely() throws {
        let text = NSAttributedString(string: "Unrelated text")
        let package = try BOLDWriterDocument.packageWrapper(text: text, metadata: DocumentMetadata())
        let invalid = NativeFieldRun(id: UUID(), kind: .simple, instruction: " SEQ Figure ", dirtyValue: nil, lockedValue: nil, location: 50, length: 1)
        var metadata = DocumentMetadata()
        metadata.fields = [invalid]
        let json = try JSONEncoder().encode(metadata)
        var children = package.fileWrappers ?? [:]
        children["metadata.json"] = FileWrapper(regularFileWithContents: json)
        let corrupted = FileWrapper(directoryWithFileWrappers: children)
        XCTAssertThrowsError(try BOLDWriterDocument(fileWrapper: corrupted, contentType: .boldWriterDocument))
    }

    func testNativeSaveRejectsDuplicateFieldIDsWithoutMutatingText() throws {
        let id = UUID()
        let field = WordField(id: id, kind: .simple, instruction: " SEQ Figure ")
        let text = NSMutableAttributedString(string: "A B")
        text.addAttribute(.boldWriterField, value: field, range: NSRange(location: 0, length: 1))
        text.addAttribute(.boldWriterField, value: field, range: NSRange(location: 2, length: 1))

        XCTAssertThrowsError(try BOLDWriterDocument.packageWrapper(text: text, metadata: DocumentMetadata()))
        XCTAssertEqual(text.attribute(.boldWriterField, at: 0, effectiveRange: nil) as? WordField, field)
        XCTAssertEqual(text.attribute(.boldWriterField, at: 2, effectiveRange: nil) as? WordField, field)
    }

    func testMalformedComplexDOCXFieldIsRejectedWithoutFlatteningText() throws {
        let w = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
        let r = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
        let body = "<w:p><w:r><w:t>Keep me </w:t></w:r><w:r><w:fldChar w:fldCharType=\"begin\"/></w:r><w:r><w:instrText> TOC \\o \"1-3\" </w:instrText></w:r><w:r><w:fldChar w:fldCharType=\"separate\"/></w:r><w:r><w:t>cached</w:t></w:r></w:p>"
        let parts = [
            ZipEntry(path: "[Content_Types].xml", data: Data("<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/></Types>".utf8)),
            ZipEntry(path: "_rels/.rels", data: Data("<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"document\" Type=\"\(r)/officeDocument\" Target=\"word/document.xml\"/></Relationships>".utf8)),
            ZipEntry(path: "word/_rels/document.xml.rels", data: Data("<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"></Relationships>".utf8)),
            ZipEntry(path: "word/document.xml", data: Data("<w:document xmlns:w=\"\(w)\"><w:body>\(body)<w:sectPr/></w:body></w:document>".utf8))
        ]
        XCTAssertThrowsError(try DOCXImporter.importedDocument(from: ZipArchiveWriter.archive(parts)))
    }


    func testNUMPAGESUsesLivePhysicalPaginationAndMatchesPDF()
        throws
    {
        let instruction =
            " NUMPAGES \\* MERGEFORMAT "

        let field =
            WordField(
                kind:
                    .complex,
                instruction:
                    instruction
            )

        let paragraph =
            "Live NUMPAGES must use completed TextKit print pagination rather than a character-count estimate. "

        let text =
            NSMutableAttributedString(
                string:
                    "999\n"
                    + Array(
                        repeating:
                            paragraph,
                        count:
                            180
                    )
                    .joined(
                        separator:
                            "\n"
                    ),
                attributes:
                    [
                        .font:
                            NSFont.systemFont(
                                ofSize:
                                    12
                            )
                    ]
            )

        text.addAttribute(
            .boldWriterField,
            value:
                field,
            range:
                NSRange(
                    location:
                        0,
                    length:
                        3
                )
        )

        let document =
            BOLDWriterDocument()

        document.replaceText(
            with:
                text
        )

        let canvas =
            PaginatedEditor(
                text:
                    text
            )

        canvas.configure(
            printLayout:
                true,
            settings:
                PageSettings(),
            zoom:
                1,
            viewportWidth:
                850
        )

        canvas.finishPagination()

        XCTAssertNil(
            canvas.lastLayoutError
        )

        XCTAssertTrue(
            canvas.layoutComplete
        )

        XCTAssertGreaterThan(
            canvas.pages.count,
            1
        )

        let controller =
            EditorController()

        controller.document =
            document

        controller.attach(
            canvas.firstView
        )

        let updates =
            controller.updateAllFields(
                in:
                    document
            )

        XCTAssertGreaterThan(
            updates,
            0
        )

        canvas.finishPagination()

        let restored =
            try XCTUnwrap(
                fieldRuns(
                    canvas.firstView
                        .attributedString()
                )
                .first {
                    $0.0.instruction
                        .trimmingCharacters(
                            in:
                                .whitespacesAndNewlines
                        )
                        .uppercased()
                        .hasPrefix(
                            "NUMPAGES"
                        )
                }
            )

        let visible =
            (
                canvas.firstView.string
                    as NSString
            )
            .substring(
                with:
                    restored.1
            )

        XCTAssertEqual(
            visible,
            String(
                canvas.pages.count
            )
        )

        XCTAssertEqual(
            restored.0.id,
            field.id
        )

        XCTAssertEqual(
            restored.0.instruction,
            instruction
        )

        var pdfRanges:
            [NSRange] = []

        let pdf =
            try PDFExporter.data(
                from:
                    canvas.firstView
                        .attributedString(),
                settings:
                    PageSettings(),
                pageRangeSink: {
                    pdfRanges =
                        $0
                }
            )

        XCTAssertFalse(
            pdf.isEmpty
        )

        XCTAssertEqual(
            pdfRanges.count,
            canvas.pages.count
        )

        XCTAssertEqual(
            controller.updateAllFields(
                in:
                    document
            ),
            0,
            "A stable NUMPAGES result must make repeated Update Fields idempotent."
        )

        print(
            "NUMPAGES_LIVE_MULTI "
            + "pages=\\(canvas.pages.count) "
            + "pdfPages=\\(pdfRanges.count) "
            + "value=\\(visible)"
        )
    }

    func testNUMPAGESEvaluatesOnePageDocument()
        throws
    {
        let field =
            WordField(
                kind:
                    .complex,
                instruction:
                    " NUMPAGES \\* MERGEFORMAT "
            )

        let text =
            NSMutableAttributedString(
                string:
                    "42\nShort manuscript.",
                attributes:
                    [
                        .font:
                            NSFont.systemFont(
                                ofSize:
                                    12
                            )
                    ]
            )

        text.addAttribute(
            .boldWriterField,
            value:
                field,
            range:
                NSRange(
                    location:
                        0,
                    length:
                        2
                )
        )

        let document =
            BOLDWriterDocument()

        document.replaceText(
            with:
                text
        )

        let canvas =
            PaginatedEditor(
                text:
                    text
            )

        canvas.configure(
            printLayout:
                true,
            settings:
                PageSettings(),
            zoom:
                1,
            viewportWidth:
                850
        )

        canvas.finishPagination()

        XCTAssertEqual(
            canvas.pages.count,
            1
        )

        let controller =
            EditorController()

        controller.document =
            document

        controller.attach(
            canvas.firstView
        )

        _ =
            controller.updateAllFields(
                in:
                    document
            )

        canvas.finishPagination()

        let run =
            try XCTUnwrap(
                fieldRuns(
                    canvas.firstView
                        .attributedString()
                )
                .first {
                    $0.0.instruction
                        .uppercased()
                        .contains(
                            "NUMPAGES"
                        )
                }
            )

        XCTAssertEqual(
            (
                canvas.firstView.string
                    as NSString
            )
            .substring(
                with:
                    run.1
            ),
            "1"
        )

        XCTAssertEqual(
            run.0.id,
            field.id
        )

        print(
            "NUMPAGES_LIVE_ONE "
            + "pages=\\(canvas.pages.count)"
        )
    }

    func testNUMPAGESUpdatesAfterGrowthAndShrinkRepagination()
        throws
    {
        let instruction =
            " NUMPAGES \\* MERGEFORMAT "

        let field =
            WordField(
                kind:
                    .complex,
                instruction:
                    instruction
            )

        let text =
            NSMutableAttributedString(
                string:
                    "99\nShort starting manuscript.",
                attributes:
                    [
                        .font:
                            NSFont.systemFont(
                                ofSize:
                                    12
                            )
                    ]
            )

        text.addAttribute(
            .boldWriterField,
            value:
                field,
            range:
                NSRange(
                    location:
                        0,
                    length:
                        2
                )
        )

        let document =
            BOLDWriterDocument()

        document.replaceText(
            with:
                text
        )

        let canvas =
            PaginatedEditor(
                text:
                    text
            )

        canvas.configure(
            printLayout:
                true,
            settings:
                PageSettings(),
            zoom:
                1,
            viewportWidth:
                850
        )

        canvas.finishPagination()

        let controller =
            EditorController()

        controller.document =
            document

        controller.attach(
            canvas.firstView
        )

        _ =
            controller.updateAllFields(
                in:
                    document
            )

        canvas.finishPagination()

        XCTAssertEqual(
            canvas.pages.count,
            1
        )

        let marker =
            "\nBOLD_NUMPAGES_GROWTH_BEGIN\n"

        let growthParagraph =
            "Repagination must recalculate the total physical page count after manuscript growth. "

        let growth =
            marker
            + Array(
                repeating:
                    growthParagraph,
                count:
                    220
            )
            .joined(
                separator:
                    "\n"
            )

        let storage =
            try XCTUnwrap(
                canvas.firstView
                    .textStorage
            )

        storage.append(
            NSAttributedString(
                string:
                    growth,
                attributes:
                    [
                        .font:
                            NSFont.systemFont(
                                ofSize:
                                    12
                            )
                    ]
            )
        )

        canvas.firstView
            .didChangeText()

        canvas.finishPagination()

        XCTAssertGreaterThan(
            canvas.pages.count,
            1
        )

        let grownPagesBeforeUpdate =
            canvas.pages.count

        _ =
            controller.updateAllFields(
                in:
                    document
            )

        canvas.finishPagination()

        let grownRun =
            try XCTUnwrap(
                fieldRuns(
                    canvas.firstView
                        .attributedString()
                )
                .first {
                    $0.0.id
                        == field.id
                }
            )

        let grownValue =
            (
                canvas.firstView.string
                    as NSString
            )
            .substring(
                with:
                    grownRun.1
            )

        XCTAssertEqual(
            grownValue,
            String(
                canvas.pages.count
            )
        )

        XCTAssertGreaterThan(
            canvas.pages.count,
            1
        )

        let growthRange =
            (
                storage.string
                    as NSString
            )
            .range(
                of:
                    marker
            )

        XCTAssertNotEqual(
            growthRange.location,
            NSNotFound
        )

        storage.deleteCharacters(
            in:
                NSRange(
                    location:
                        growthRange.location,
                    length:
                        storage.length
                        - growthRange.location
                )
        )

        canvas.firstView
            .didChangeText()

        canvas.finishPagination()

        XCTAssertEqual(
            canvas.pages.count,
            1
        )

        _ =
            controller.updateAllFields(
                in:
                    document
            )

        canvas.finishPagination()

        let shrunkenRun =
            try XCTUnwrap(
                fieldRuns(
                    canvas.firstView
                        .attributedString()
                )
                .first {
                    $0.0.id
                        == field.id
                }
            )

        let shrunkenValue =
            (
                canvas.firstView.string
                    as NSString
            )
            .substring(
                with:
                    shrunkenRun.1
            )

        XCTAssertEqual(
            shrunkenValue,
            "1"
        )

        XCTAssertEqual(
            shrunkenRun.0.instruction,
            instruction
        )

        print(
            "NUMPAGES_REPAGINATION "
            + "grownBefore=\\(grownPagesBeforeUpdate) "
            + "grownFinal=\\(grownValue) "
            + "shrunk=\\(shrunkenValue)"
        )
    }

}
