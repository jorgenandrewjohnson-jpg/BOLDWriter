import AppKit
import PDFKit
import XCTest
@testable import BOLDWriter

@MainActor
private final class TableTextView: NSTextView {
    let manager = UndoManager()
    override var undoManager: UndoManager? { manager }
}

@MainActor
final class TableTests: XCTestCase {
    private func table(rows: Int = 2, columns: Int = 2) throws -> WriterTable {
        var model = try WriterTable(rows: rows, columns: columns)
        for row in 0..<rows {
            for column in 0..<columns {
                model.cells[row][column] = NSAttributedString(string: "Row \(row + 1), cell \(column + 1)", attributes: [.font: column == 0 ? NSFont(name: "Helvetica-Bold", size: 13)! : NSFont(name: "Helvetica-Oblique", size: 13)!])
            }
        }
        return model
    }
    private func editor() -> (EditorController, TableTextView) {
        let view = TableTextView(frame: NSRect(x: 0, y: 0, width: 650, height: 700))
        view.allowsUndo = true; view.isRichText = true
        view.manager.groupsByEvent = false
        view.textStorage?.setAttributedString(NSAttributedString(string: "Before\nAfter", attributes: [.font: WriterStyle.defaultFont]))
        view.setSelectedRange(NSRange(location: 7, length: 0))
        let controller = EditorController(); controller.attach(view)
        return (controller, view)
    }
    private func change(_ view: TableTextView, _ action: () -> Void) {
        view.manager.beginUndoGrouping(); action(); view.manager.endUndoGrouping()
    }
    private func models(_ view: NSTextView) throws -> [WriterTable] { try Tables.models(in: view.attributedString()) }

    func testCreateTwoByTwoAndLargerTableWithStableCellIDs() throws {
        for (rows, columns) in [(2, 2), (12, 8)] {
            let original = try table(rows: rows, columns: columns)
            let rendered = try Tables.rendered(original)
            let model = try XCTUnwrap(Tables.models(in: rendered).first)
            XCTAssertEqual(model.id, original.id)
            XCTAssertEqual(model.rows, rows); XCTAssertEqual(model.columns, columns)
            XCTAssertEqual(model.cellIDs, original.cellIDs)
            XCTAssertEqual(model.cells[rows - 1][columns - 1].string, original.cells[rows - 1][columns - 1].string)
            let style = try XCTUnwrap(rendered.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
            let block = try XCTUnwrap(style.textBlocks.first as? NSTextTableBlock)
            XCTAssertEqual(block.table.numberOfColumns, columns)
            XCTAssertGreaterThan(block.width(for: .border, edge: .minX), 0)
        }
    }

    func testInsertDeleteAndUndoRedoPreserveSurroundingText() throws {
        let (controller, view) = editor()
        change(view) { controller.insertTable(rows: 2, columns: 2) }
        let originalID = try XCTUnwrap(models(view).first?.id)
        XCTAssertTrue(view.string.hasPrefix("Before\n")); XCTAssertTrue(view.string.hasSuffix("After"))
        view.manager.undo(); XCTAssertEqual(view.string, "Before\nAfter")
        view.manager.redo(); XCTAssertEqual(try models(view).first?.id, originalID)
        change(view) { controller.tableCommand("deleteTable") }
        XCTAssertTrue(try models(view).isEmpty)
        XCTAssertTrue(view.string.hasPrefix("Before\n")); XCTAssertTrue(view.string.hasSuffix("After"))
        view.manager.undo(); XCTAssertEqual(try models(view).first?.id, originalID)
        view.manager.redo(); XCTAssertTrue(try models(view).isEmpty)
    }

    func testCellTypingMultilineAndUndoRedo() throws {
        let (controller, view) = editor()
        change(view) { controller.insertTable(rows: 2, columns: 2) }
        let id = try XCTUnwrap(models(view).first?.cellIDs[0][0])
        change(view) {
            XCTAssertTrue(controller.handleTableEdit(range: view.selectedRange(), replacement: NSAttributedString(string: "Hello\nworld", attributes: [.font: NSFont.boldSystemFont(ofSize: 14)])))
        }
        XCTAssertEqual(try models(view)[0].cells[0][0].string, "Hello\nworld")
        XCTAssertEqual(try models(view)[0].cellIDs[0][0], id)
        view.manager.undo(); XCTAssertEqual(try models(view)[0].cells[0][0].string, "")
        view.manager.redo(); XCTAssertEqual(try models(view)[0].cells[0][0].string, "Hello\nworld")
        let record = try Tables.records(in: view.attributedString())[0]
        change(view) { XCTAssertTrue(controller.handleTableEdit(range: NSRange(location: record.location + record.length - 1, length: 1), replacement: NSAttributedString(string: ""))) }
        XCTAssertEqual(try models(view)[0].cells[0][0].string, "Hello\nworld")
        XCTAssertEqual(try models(view)[0].rows, 2)
    }

    func testRowAndColumnOperationsUndoRedo() throws {
        let (controller, view) = editor()
        change(view) { controller.insertTable(rows: 2, columns: 2) }
        let id = try models(view)[0].cellIDs[0][0]
        for (command, rows, columns) in [("addRow", 3, 2), ("addColumn", 3, 3), ("deleteRow", 2, 3), ("deleteColumn", 2, 2)] {
            let before = try models(view)[0]
            change(view) { controller.tableCommand(command) }
            XCTAssertEqual(try models(view)[0].rows, rows); XCTAssertEqual(try models(view)[0].columns, columns)
            XCTAssertEqual(try models(view)[0].cellIDs[0][0], id)
            view.manager.undo()
            XCTAssertEqual(try models(view)[0].cellIDs, before.cellIDs)
            view.manager.redo()
            XCTAssertEqual(try models(view)[0].rows, rows); XCTAssertEqual(try models(view)[0].columns, columns)
        }
    }

    func testTabShiftTabAndFinalCellAddsRow() throws {
        let (controller, view) = editor()
        change(view) { controller.insertTable(rows: 2, columns: 2) }
        XCTAssertTrue(controller.navigateTable(forward: true))
        XCTAssertEqual(try controller.selectedTable()?.1.column, 1)
        XCTAssertTrue(controller.navigateTable(forward: false))
        XCTAssertEqual(try controller.selectedTable()?.1.column, 0)
        let last = try XCTUnwrap(Tables.records(in: view.attributedString()).last)
        view.setSelectedRange(NSRange(location: last.location, length: 0))
        change(view) { XCTAssertTrue(controller.navigateTable(forward: true)) }
        XCTAssertEqual(try models(view)[0].rows, 3)
        XCTAssertEqual(try controller.selectedTable()?.1.column, 0)
        XCTAssertEqual(try controller.selectedTable()?.1.row, 2)
        view.manager.undo(); XCTAssertEqual(try models(view)[0].rows, 2)
    }

    func testNativeSaveCloseReopenEditSaveAgainAndRecovery() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".boldwriter")
        defer { try? FileManager.default.removeItem(at: url) }
        var model = try table(); model.header = true; model.widths = [30, 70]
        let text = NSMutableAttributedString(string: "Before\n")
        text.append(try Tables.rendered(model)); text.append(NSAttributedString(string: "After"))
        try BOLDWriterDocument.packageWrapper(text: text, metadata: DocumentMetadata()).write(to: url, options: .atomic, originalContentsURL: nil)
        var document: BOLDWriterDocument? = try BOLDWriterDocument(fileWrapper: FileWrapper(url: url), contentType: .boldWriterDocument)
        var restored = try XCTUnwrap(Tables.models(in: document!.text).first)
        XCTAssertEqual(restored.id, model.id); XCTAssertEqual(restored.cellIDs, model.cellIDs)
        XCTAssertEqual(restored.widths, [30, 70]); XCTAssertTrue(restored.header)
        XCTAssertEqual(document!.text.string, text.string)
        XCTAssertTrue(document!.createRevision(named: "Before cell edit"))
        let revision = try XCTUnwrap(document!.metadata.revisions.first)
        restored.cells[1][1] = NSAttributedString(string: "Reopened edit 🌟")
        let changed = NSMutableAttributedString(attributedString: document!.text)
        changed.replaceCharacters(in: restored.range, with: try Tables.rendered(restored))
        document!.replaceText(with: changed)
        try BOLDWriterDocument.packageWrapper(text: document!.text, metadata: document!.metadata).write(to: url, options: .atomic, originalContentsURL: url)
        document = nil
        let reopened = try BOLDWriterDocument(fileWrapper: FileWrapper(url: url), contentType: .boldWriterDocument)
        XCTAssertEqual(try Tables.models(in: reopened.text)[0].cells[1][1].string, "Reopened edit 🌟")
        try reopened.restore(revision)
        XCTAssertEqual(try Tables.models(in: reopened.text)[0].cells[1][1].string, model.cells[1][1].string)
    }

    func testDOCXExportAndMultipleTableRoundTripWithFormattingWidthsAndHeader() throws {
        var first = try table(); first.header = true; first.widths = [25, 75]
        let second = try table(rows: 3, columns: 4)
        let text = NSMutableAttributedString(string: "Before\n")
        text.append(try Tables.rendered(first)); text.append(NSAttributedString(string: "Between\n"))
        text.append(try Tables.rendered(second)); text.append(NSAttributedString(string: "After"))
        let data = try DOCXExporter.data(from: text, title: "Tables")
        let part = try XCTUnwrap(DOCXPackage.entries(in: data).first { $0.path == "word/document.xml" })
        let xml = try DOCXPackage.xml(part.data)
        XCTAssertEqual(try xml.nodes(forXPath: "//*[local-name()='tbl']").count, 2)
        XCTAssertEqual(try xml.nodes(forXPath: "//*[local-name()='tc']").count, 16)
        XCTAssertEqual(try xml.nodes(forXPath: "//*[local-name()='tblHeader']").count, 1)
        let imported = try DOCXImporter.text(from: data)
        let tables = try Tables.models(in: imported)
        XCTAssertEqual(tables.count, 2)
        XCTAssertEqual(tables[0].rows, 2); XCTAssertEqual(tables[1].columns, 4)
        XCTAssertEqual(tables[1].cells[2][3].string, second.cells[2][3].string)
        XCTAssertTrue(tables[0].header); XCTAssertEqual(tables[0].widths[0], 25, accuracy: 0.1)
        XCTAssertEqual(imported.string.trimmingCharacters(in: .newlines), text.string)
        let bold = try XCTUnwrap(tables[0].cells[0][0].attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: bold).contains(.boldFontMask))
        let italic = try XCTUnwrap(tables[0].cells[0][1].attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: italic).contains(.italicFontMask))
        let again = try DOCXImporter.text(from: DOCXExporter.data(from: imported, title: "Again"))
        XCTAssertEqual(try Tables.models(in: again)[1].cells[2][3].string, second.cells[2][3].string)
    }

    private func wordFixture(cell: String = "<w:p><w:r><w:t>Word cell</w:t></w:r></w:p>", properties: String = "") -> Data {
        let w = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
        let parts = [
            "[Content_Types].xml": "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/></Types>",
            "_rels/.rels": "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"main\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/></Relationships>",
            "word/document.xml": "<w:document xmlns:w=\"\(w)\"><w:body><w:p><w:r><w:t>Before</w:t></w:r></w:p><w:tbl><w:tblGrid><w:gridCol w:w=\"2000\"/></w:tblGrid><w:tr><w:trPr><w:tblHeader/></w:trPr><w:tc><w:tcPr>\(properties)</w:tcPr>\(cell)</w:tc></w:tr></w:tbl><w:p><w:r><w:t>After</w:t></w:r></w:p></w:body></w:document>"
        ]
        return ZipArchiveWriter.archive(parts.map { ZipEntry(path: $0.key, data: Data($0.value.utf8)) })
    }

    private func wordTableFixture(_ table: String) -> Data {
        let w = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
        let parts = [
            "[Content_Types].xml": "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/></Types>",
            "_rels/.rels": "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"main\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/></Relationships>",
            "word/document.xml": "<w:document xmlns:w=\"\(w)\"><w:body>\(table)<w:p/></w:body></w:document>"
        ]
        return ZipArchiveWriter.archive(parts.map { ZipEntry(path: $0.key, data: Data($0.value.utf8)) })
    }

    private func wordCell(_ text: String, properties: String = "") -> String {
        "<w:tc><w:tcPr>\(properties)</w:tcPr><w:p><w:r><w:t>\(text)</w:t></w:r></w:p></w:tc>"
    }

    private func mergedFixture(columns: Int, rows: [String]) -> Data {
        let grid = String(repeating: "<w:gridCol w:w=\"1800\"/>", count: columns)
        return wordTableFixture("<w:tbl><w:tblGrid>\(grid)</w:tblGrid>\(rows.map { "<w:tr>\($0)</w:tr>" }.joined())</w:tbl>")
    }

    func testHorizontalMergesUseLogicalOriginsAndRoundTrip() throws {
        for span in [2, 3] {
            let merged = wordCell("Merged", properties: "<w:gridSpan w:val=\"\(span)\"/>")
            let data = mergedFixture(columns: span, rows: [merged, (0..<span).map { wordCell("Cell \($0)") }.joined()])
            let imported = try DOCXImporter.text(from: data)
            let table = try XCTUnwrap(Tables.models(in: imported).first)
            XCTAssertEqual(table.columnSpans[0][0], span)
            XCTAssertEqual(table.cells[0][0].string, "Merged")
            XCTAssertEqual(try Tables.records(in: imported).count, span + 1)
            let exported = try DOCXExporter.data(from: imported, title: "Merged")
            let xml = try DOCXPackage.xml(XCTUnwrap(DOCXPackage.entries(in: exported).first { $0.path == "word/document.xml" }).data)
            XCTAssertEqual(try xml.nodes(forXPath: "//*[local-name()='gridSpan']").count, 1)
            XCTAssertEqual(try xml.nodes(forXPath: "//*[local-name()='tc']").count, span + 1)
            let again = try XCTUnwrap(Tables.models(in: DOCXImporter.text(from: exported)).first)
            XCTAssertEqual(again.columnSpans[0][0], span)
            XCTAssertEqual(again.cells[0][0].string, "Merged")
        }
    }

    func testVerticalAndMixedMergesRoundTripWithoutDuplicatingText() throws {
        for rowCount in [2, 4] {
            let first = wordCell("Origin", properties: "<w:gridSpan w:val=\"2\"/><w:vMerge w:val=\"restart\"/>") + wordCell("Right 0")
            let following = (1..<rowCount).map { row in
                wordCell("", properties: "<w:gridSpan w:val=\"2\"/><w:vMerge/>") + wordCell("Right \(row)")
            }
            let imported = try DOCXImporter.text(from: mergedFixture(columns: 3, rows: [first] + following))
            let table = try XCTUnwrap(Tables.models(in: imported).first)
            XCTAssertEqual(table.rowSpans[0][0], rowCount)
            XCTAssertEqual(table.columnSpans[0][0], 2)
            XCTAssertEqual(table.cells[0][0].string, "Origin")
            XCTAssertEqual(try Tables.records(in: imported).count, rowCount + 1)
            let exported = try DOCXExporter.data(from: imported, title: "Vertical")
            let xml = try DOCXPackage.xml(XCTUnwrap(DOCXPackage.entries(in: exported).first { $0.path == "word/document.xml" }).data)
            XCTAssertEqual(try xml.nodes(forXPath: "//*[local-name()='vMerge']").count, rowCount)
            let again = try XCTUnwrap(Tables.models(in: DOCXImporter.text(from: exported)).first)
            XCTAssertEqual(again.rowSpans[0][0], rowCount)
            XCTAssertEqual(again.cells[0][0].string, "Origin")
            XCTAssertFalse(again.cells.flatMap { $0 }.dropFirst().contains { $0.string == "Origin" })
        }
    }

    func testMergedTableNativePersistencePreservesSpans() throws {
        var table = try WriterTable(rows: 2, columns: 2)
        table.cells[0][0] = NSAttributedString(string: "Bold", attributes: [.font: NSFont.boldSystemFont(ofSize: 13)])
        table.columnSpans[0][0] = 2
        table.columnSpans[0][1] = 0
        table.rowSpans[0][1] = 0
        let original = try Tables.rendered(table)
        let wrapper = try BOLDWriterDocument.packageWrapper(text: original, metadata: DocumentMetadata())
        let reopened = try BOLDWriterDocument(fileWrapper: wrapper, contentType: .boldWriterDocument)
        let restored = try XCTUnwrap(Tables.models(in: reopened.text).first)
        XCTAssertEqual(restored.columnSpans[0][0], 2)
        XCTAssertEqual(restored.cells[0][0].string, "Bold")
        let font = try XCTUnwrap(restored.cells[0][0].attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
    }

    private func nestedXML(depth: Int, merged: Bool = false) -> String {
        let grid = merged ? "<w:gridCol w:w=\"1000\"/><w:gridCol w:w=\"1000\"/>" : "<w:gridCol w:w=\"2000\"/>"
        let properties = merged ? "<w:tcPr><w:gridSpan w:val=\"2\"/></w:tcPr>" : "<w:tcPr/>"
        let inner = depth > 1 ? nestedXML(depth: depth - 1) : ""
        return "<w:tbl><w:tblGrid>\(grid)</w:tblGrid><w:tr><w:tc>\(properties)<w:p><w:r><w:rPr><w:b/></w:rPr><w:t>Depth \(depth)</w:t></w:r></w:p>\(inner)<w:p/></w:tc></w:tr></w:tbl>"
    }

    func testNestedTablesKeepStructureThroughNativeSaveAndDOCXRoundTrip() throws {
        for depth in [1, 2, 3] {
            let inner = nestedXML(depth: depth, merged: depth == 1)
            let outer = "<w:tbl><w:tblGrid><w:gridCol w:w=\"2000\"/></w:tblGrid><w:tr><w:tc><w:tcPr/><w:p><w:r><w:t>Before</w:t></w:r></w:p>\(inner)<w:p><w:r><w:t>After</w:t></w:r></w:p></w:tc></w:tr></w:tbl>"
            let imported = try DOCXImporter.text(from: wordTableFixture(outer))
            let table = try XCTUnwrap(Tables.models(in: imported).first)
            XCTAssertEqual(table.cells[0][0].string, "Before\n[Nested table]\nAfter")
            XCTAssertEqual(table.nestedTables[0][0].count, 1)
            XCTAssertEqual(table.nestedTables[0][0][0].table.rows.count, 1)
            XCTAssertEqual(table.nestedTables[0][0][0].table.rows[0][0].blocks.filter { $0.table != nil }.count, depth > 1 ? 1 : 0)
            let wrapper = try BOLDWriterDocument.packageWrapper(text: imported, metadata: DocumentMetadata())
            let reopened = try BOLDWriterDocument(fileWrapper: wrapper, contentType: .boldWriterDocument)
            let saved = try XCTUnwrap(Tables.models(in: reopened.text).first)
            XCTAssertEqual(saved.nestedTables[0][0], table.nestedTables[0][0])
            let exported = try DOCXExporter.data(from: reopened.text, title: "Nested")
            let xml = try DOCXPackage.xml(XCTUnwrap(DOCXPackage.entries(in: exported).first { $0.path == "word/document.xml" }).data)
            XCTAssertEqual(try xml.nodes(forXPath: "//*[local-name()='tbl']").count, depth + 1)
            XCTAssertEqual(try xml.nodes(forXPath: "//*[local-name()='tbl']/*[local-name()='tr']/*[local-name()='tc']/*[local-name()='tbl']").count, depth)
            let again = try XCTUnwrap(Tables.models(in: DOCXImporter.text(from: exported)).first)
            XCTAssertEqual(again.nestedTables[0][0][0].table.rows.count, 1)
            XCTAssertEqual(again.cells[0][0].string, "Before\n[Nested table]\nAfter")
        }
    }

    func testExcessivelyDeepNestedTableFailsSafely() throws {
        let outer = "<w:tbl><w:tblGrid><w:gridCol w:w=\"2000\"/></w:tblGrid><w:tr><w:tc><w:tcPr/><w:p/>\(nestedXML(depth: 14))<w:p/></w:tc></w:tr></w:tbl>"
        XCTAssertThrowsError(try DOCXImporter.text(from: wordTableFixture(outer)))
    }
    func testIndependentWordTableImport() throws {
        let imported = try DOCXImporter.text(from: wordFixture())
        let model = try XCTUnwrap(Tables.models(in: imported).first)
        XCTAssertEqual(model.rows, 1); XCTAssertEqual(model.columns, 1)
        XCTAssertEqual(model.cells[0][0].string, "Word cell"); XCTAssertTrue(model.header)
        XCTAssertEqual(imported.string.trimmingCharacters(in: .newlines), "Before\nWord cell\nAfter")
    }

    func testMalformedAndMergedTablesFailSafely() throws {
        XCTAssertThrowsError(try DOCXImporter.text(from: wordFixture(cell: "")))
        XCTAssertThrowsError(try DOCXImporter.text(from: wordFixture(properties: "<w:gridSpan w:val=\"2\"/>")))
        XCTAssertThrowsError(try DOCXImporter.text(from: wordFixture(properties: "<w:vMerge/>")))
        XCTAssertThrowsError(try WriterTable(rows: Int.max, columns: 2))
        let text = NSMutableAttributedString(string: "Body\n")
        text.addAttribute(.tableCell, value: Data("bad".utf8), range: NSRange(location: 0, length: 5))
        XCTAssertThrowsError(try BOLDWriterDocument.packageWrapper(text: text, metadata: DocumentMetadata()))
        XCTAssertThrowsError(try DOCXExporter.data(from: text, title: "Bad"))
    }

    func testTablesImagesAndFootnotesTogether() throws {
        let (sample, _) = SampleDocumentFactory.make()
        let text = NSMutableAttributedString(attributedString: sample)
        text.append(NSAttributedString(string: "\n")); text.append(try Tables.rendered(table()))
        let imported = try DOCXImporter.text(from: DOCXExporter.data(from: text, title: "Mixed"))
        XCTAssertFalse(try Tables.models(in: imported).isEmpty)
        XCTAssertEqual(try Footnotes.records(in: imported).map(\.text), try Footnotes.records(in: text).map(\.text))
        var images = 0
        imported.enumerateAttribute(.attachment, in: NSRange(location: 0, length: imported.length)) { value, _, _ in if value is NSTextAttachment { images += 1 } }
        XCTAssertEqual(images, 1)
    }

    func testHeaderAndColumnWidthsUndoRedo() throws {
        let (controller, view) = editor()
        change(view) { controller.insertTable(rows: 2, columns: 2) }
        change(view) { controller.tableCommand("header") }
        XCTAssertTrue(try models(view)[0].header)
        view.manager.undo(); XCTAssertFalse(try models(view)[0].header)
        view.manager.redo(); XCTAssertTrue(try models(view)[0].header)
        change(view) { controller.tableCommand("wider") }
        XCTAssertGreaterThan(try models(view)[0].widths[0], 50)
        view.manager.undo(); XCTAssertEqual(try models(view)[0].widths[0], 50)
    }

    func testWholeTableClipboardPreservesStructureWithFreshIDs() throws {
        let original = try table()
        let rendered = try Tables.rendered(original)
        let data = try Tables.clipboardData(rendered)
        let copy = try Tables.clipboardText(data)
        let model = try XCTUnwrap(Tables.models(in: copy).first)
        XCTAssertNotEqual(model.id, original.id)
        XCTAssertNotEqual(model.cellIDs[0][0], original.cellIDs[0][0])
        XCTAssertEqual(copy.string, rendered.string)
        let (controller, view) = editor()
        change(view) { XCTAssertTrue(controller.pasteTables(data)) }
        XCTAssertEqual(try models(view).count, 1)
        view.manager.undo(); XCTAssertTrue(try models(view).isEmpty)
        view.manager.redo(); XCTAssertEqual(try models(view)[0].cells[0][0].string, original.cells[0][0].string)
    }

    func testSearchReplaceAndParagraphStylePreserveCellStructure() throws {
        let (controller, view) = editor()
        change(view) { controller.insertTable(rows: 2, columns: 2) }
        change(view) { _ = controller.handleTableEdit(range: view.selectedRange(), replacement: NSAttributedString(string: "Find me")) }
        let first = try Tables.records(in: view.attributedString())[0]
        change(view) { controller.replaceAll([NSRange(location: first.location, length: 4)], with: "Found") }
        XCTAssertEqual(try models(view)[0].cells[0][0].string, "Found me")
        let refreshed = try Tables.records(in: view.attributedString())[0]
        let before = view.string
        change(view) { controller.replaceAll([NSRange(location: refreshed.location + refreshed.length - 1, length: 1)], with: "bad") }
        XCTAssertEqual(view.string, before)
        view.setSelectedRange(NSRange(location: refreshed.location, length: 0))
        change(view) { controller.applyStyle(.heading2) }
        let paragraph = try XCTUnwrap(view.attributedString().attribute(.paragraphStyle, at: refreshed.location, effectiveRange: nil) as? NSParagraphStyle)
        XCTAssertTrue(paragraph.textBlocks.first is NSTextTableBlock)
        XCTAssertEqual(try models(view).count, 1)
    }

    func testFootnoteWithinCellSurvivesRenumberAndDOCX() throws {
        let (controller, view) = editor()
        change(view) { controller.insertTable(rows: 2, columns: 2) }
        change(view) { controller.insertFootnote(text: "Inside a cell") }
        view.setSelectedRange(NSRange(location: 0, length: 0))
        change(view) { controller.insertFootnote(text: "Before the table") }
        XCTAssertEqual(try Tables.models(in: view.attributedString())[0].cells[0][0].string, "2")
        let imported = try DOCXImporter.text(from: DOCXExporter.data(from: view.attributedString(), title: "Note in table"))
        XCTAssertEqual(try Tables.models(in: imported)[0].cells[0][0].string, "2")
        XCTAssertEqual(try Footnotes.records(in: imported).map(\.text), ["Before the table", "Inside a cell"])
    }

    func testEndnoteTypingAttributesAreClearedInsideTableCell()
        throws {

        let (
            controller,
            view
        ) =
            editor()

        change(
            view
        ) {
            controller.insertTable(
                rows:
                    2,
                columns:
                    2
            )
        }

        change(
            view
        ) {
            controller.insertEndnote(
                text:
                    "Inside a cell"
            )
        }

        let note =
            try XCTUnwrap(
                Endnotes.records(
                    in:
                        view.attributedString()
                )
                .first
            )

        view.setSelectedRange(
            NSRange(
                location:
                    note.location,
                length:
                    0
            )
        )

        controller
            .updateTableTypingAttributes()

        XCTAssertNotNil(
            view.typingAttributes[
                .tableCell
            ]
        )

        XCTAssertNil(
            view.typingAttributes[
                .endnote
            ]
        )

        XCTAssertNil(
            view.typingAttributes[
                .superscript
            ]
        )

        XCTAssertEqual(
            try Endnotes.records(
                in:
                    view.attributedString()
            )
            .map(
                \.text
            ),
            [
                "Inside a cell"
            ]
        )
    }

    func testEndnoteWithinCellSurvivesRenumberAndDOCX()
        throws {

        let (
            controller,
            view
        ) =
            editor()

        change(
            view
        ) {
            controller.insertTable(
                rows:
                    2,
                columns:
                    2
            )
        }

        change(
            view
        ) {
            controller.insertEndnote(
                text:
                    "Inside a cell"
            )
        }

        view.setSelectedRange(
            NSRange(
                location:
                    0,
                length:
                    0
            )
        )

        change(
            view
        ) {
            controller.insertEndnote(
                text:
                    "Before the table"
            )
        }

        XCTAssertEqual(
            try Tables.models(
                in:
                    view.attributedString()
            )[0]
            .cells[0][0]
            .string,
            "2"
        )

        let imported =
            try DOCXImporter.text(
                from:
                    DOCXExporter.data(
                        from:
                            view.attributedString(),
                        title:
                            "Endnote in table"
                    )
            )

        XCTAssertEqual(
            try Tables.models(
                in:
                    imported
            )[0]
            .cells[0][0]
            .string,
            "2"
        )

        XCTAssertEqual(
            try Endnotes.records(
                in:
                    imported
            )
            .map(
                \.text
            ),
            [
                "Before the table",
                "Inside a cell"
            ]
        )
    }

    func testNativeTableLightAndDarkRendering() throws {
        var model = try table(); model.header = true
        for (name, output) in [(NSAppearance.Name.aqua, "Light"), (.darkAqua, "Dark")] {
            let view = WritingTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 220))
            view.writingMargins = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
            view.appearance = NSAppearance(named: name)
            view.usesAdaptiveColorMappingForDarkAppearance = true
            view.backgroundColor = .textBackgroundColor
            view.textStorage?.setAttributedString(try Tables.rendered(model))
            view.layoutManager?.ensureLayout(for: view.textContainer!)
            let image = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: image)
            try image.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/BOLDTable" + output + ".png"))
            XCTAssertEqual(try Tables.models(in: view.attributedString())[0].cellIDs, model.cellIDs)
        }
    }

    func testPDFRendersCellsAndBordersAcrossPages() throws {
        var model = try table(rows: 35, columns: 3); model.header = true
        let text = NSMutableAttributedString(string: "Structured Table Preview\n", attributes: [.font: NSFont.boldSystemFont(ofSize: 20)])
        text.append(try Tables.rendered(model)); text.append(NSAttributedString(string: "After table"))
        let data = try PDFExporter.data(from: text, settings: PageSettings())
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertGreaterThan(pdf.pageCount, 1)
        XCTAssertTrue(pdf.string?.contains("Row 35, cell 3") == true)
        XCTAssertTrue(pdf.string?.contains("After table") == true)
        let image = try XCTUnwrap(pdf.page(at: 0)).thumbnail(of: NSSize(width: 612, height: 792), for: .mediaBox)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
        try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/BOLDTablePreview.png"))
    }

    func testTrackedEditingInsideTableCellPreservesStructureAndDOCXRoundTrip()
        throws {
        let (controller, view) =
            editor()

        change(view) {
            controller.insertTable(
                rows: 2,
                columns: 2
            )
        }

        let original =
            try XCTUnwrap(
                Tables.records(
                    in:
                        view.attributedString()
                )
                .first
            )

        let originalTableID =
            original.tableID

        let originalCellID =
            original.id

        view.setSelectedRange(
            NSRange(
                location:
                    original.location,
                length: 0
            )
        )

        let attributes =
            view.attributedString()
                .attributes(
                    at:
                        original.location,
                    effectiveRange: nil
                )

        change(view) {
            XCTAssertTrue(
                controller.handleTableEdit(
                    range:
                        view.selectedRange(),
                    replacement:
                        NSAttributedString(
                            string:
                                "Tracked cell text",
                            attributes:
                                attributes
                        ),
                    trackChanges: true
                )
            )
        }

        let modelsAfterInsertion =
            try models(view)

        XCTAssertEqual(
            modelsAfterInsertion.count,
            1
        )

        XCTAssertEqual(
            modelsAfterInsertion[0]
                .id,
            originalTableID
        )

        XCTAssertEqual(
            modelsAfterInsertion[0]
                .cellIDs[0][0],
            originalCellID
        )

        XCTAssertEqual(
            modelsAfterInsertion[0]
                .cells[0][0]
                .string,
            "Tracked cell text"
        )

        let insertionRecords =
            TrackChanges.records(
                in:
                    view.attributedString()
            )

        XCTAssertEqual(
            insertionRecords.count,
            1
        )

        XCTAssertEqual(
            insertionRecords.first?
                .kind,
            .insertion
        )

        let refreshedCell =
            try XCTUnwrap(
                Tables.records(
                    in:
                        view.attributedString()
                )
                .first
            )

        let beforeBoundaryAttempt =
            view.attributedString()
                .copy()
                as! NSAttributedString

        change(view) {
            XCTAssertTrue(
                controller.handleTableEdit(
                    range:
                        NSRange(
                            location:
                                refreshedCell.location
                                + refreshedCell.length
                                - 1,
                            length: 1
                        ),
                    replacement:
                        NSAttributedString(
                            string: ""
                        ),
                    trackChanges: true
                )
            )
        }

        XCTAssertTrue(
            beforeBoundaryAttempt
                .isEqual(
                    to:
                        view.attributedString()
                )
        )

        XCTAssertEqual(
            TrackChanges.records(
                in:
                    view.attributedString()
            ).count,
            1
        )

        XCTAssertEqual(
            try models(view)[0]
                .rows,
            2
        )

        XCTAssertEqual(
            try models(view)[0]
                .columns,
            2
        )

        let data =
            try DOCXExporter.data(
                from:
                    view.attributedString(),
                title:
                    "Tracked Table Cell"
            )

        let imported =
            try DOCXImporter.text(
                from: data
            )

        let importedTables =
            try Tables.models(
                in: imported
            )

        XCTAssertEqual(
            importedTables.count,
            1
        )

        XCTAssertEqual(
            importedTables[0]
                .rows,
            2
        )

        XCTAssertEqual(
            importedTables[0]
                .columns,
            2
        )

        XCTAssertEqual(
            importedTables[0]
                .cells[0][0]
                .string,
            "Tracked cell text"
        )

        let importedChanges =
            TrackChanges.records(
                in: imported
            )

        XCTAssertEqual(
            importedChanges.count,
            1
        )

        XCTAssertEqual(
            importedChanges.first?
                .kind,
            .insertion
        )

        let documentPart =
            try XCTUnwrap(
                DOCXPackage
                    .entries(in: data)
                    .first {
                        $0.path
                            == "word/document.xml"
                    }
            )

        let xml =
            try DOCXPackage.xml(
                documentPart.data
            )

        XCTAssertEqual(
            try xml.nodes(
                forXPath:
                    "//*[local-name()='tbl']"
            ).count,
            1
        )

        XCTAssertEqual(
            try xml.nodes(
                forXPath:
                    "//*[local-name()='ins']"
            ).count,
            1
        )
    }



    func testTrackedTableCellEditSurvivesNativeSaveCloseReopen()
        throws {

        func reopen(
            _ text: NSAttributedString
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
                true

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
            TableTextView
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

        let (controller, view) =
            editor()

        change(view) {
            controller.insertTable(
                rows: 2,
                columns: 2
            )
        }

        let originalModel =
            try XCTUnwrap(
                Tables.models(
                    in:
                        view.attributedString()
                )
                .first
            )

        let originalID =
            originalModel.id

        let originalCellIDs =
            originalModel.cellIDs

        let firstCell =
            try XCTUnwrap(
                Tables.records(
                    in:
                        view.attributedString()
                )
                .first
            )

        view.setSelectedRange(
            NSRange(
                location:
                    firstCell.location,
                length: 0
            )
        )

        let attributes =
            view.attributedString()
                .attributes(
                    at:
                        firstCell.location,
                    effectiveRange: nil
                )

        change(view) {
            XCTAssertTrue(
                controller.handleTableEdit(
                    range:
                        view.selectedRange(),
                    replacement:
                        NSAttributedString(
                            string:
                                "Persisted cell edit",
                            attributes:
                                attributes
                        ),
                    trackChanges:
                        true
                )
            )
        }

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
                view.attributedString()
            )

        let reopenedModel =
            try XCTUnwrap(
                Tables.models(
                    in:
                        acceptedDocument.text
                )
                .first
            )

        XCTAssertEqual(
            reopenedModel.id,
            originalID
        )

        XCTAssertEqual(
            reopenedModel.cellIDs,
            originalCellIDs
        )

        XCTAssertEqual(
            reopenedModel
                .cells[0][0]
                .string,
            "Persisted cell edit"
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

        let acceptedModel =
            try XCTUnwrap(
                Tables.models(
                    in:
                        acceptView
                            .attributedString()
                )
                .first
            )

        XCTAssertEqual(
            acceptedModel.id,
            originalID
        )

        XCTAssertEqual(
            acceptedModel.cellIDs,
            originalCellIDs
        )

        XCTAssertEqual(
            acceptedModel
                .cells[0][0]
                .string,
            "Persisted cell edit"
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
                view.attributedString()
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

        let rejectedModel =
            try XCTUnwrap(
                Tables.models(
                    in:
                        rejectView
                            .attributedString()
                )
                .first
            )

        XCTAssertEqual(
            rejectedModel.id,
            originalID
        )

        XCTAssertEqual(
            rejectedModel.cellIDs,
            originalCellIDs
        )

        XCTAssertFalse(
            rejectedModel
                .cells[0][0]
                .string
                .contains(
                    "Persisted cell edit"
                )
        )

        XCTAssertEqual(
            try Tables.records(
                in:
                    rejectView
                        .attributedString()
            )
            .count,
            4
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
