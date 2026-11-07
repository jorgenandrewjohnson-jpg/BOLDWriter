import AppKit

extension NSAttributedString.Key {
    static let tableCell = NSAttributedString.Key("com.boldwriter.tableCell")
}

struct TableCellRecord: Codable, Equatable {
    var tableID: UUID
    var id: UUID
    var row: Int
    var column: Int
    var rows: Int
    var columns: Int
    var widths: [Double]
    var header: Bool
    /// Nil in documents written before merged cells were supported.
    var rowSpan: Int? = nil
    var columnSpan: Int? = nil
    var nestedTables: [NestedTableAnchor]? = nil
    /// Word w:tcPr/w:vAlign. Nil means the default top alignment.
    var verticalAlignment: String? = nil
    /// Word w:trPr/w:cantSplit for every physical row in the table.
    /// Stored on every cell record so rows fully covered by a vertical merge are retained.
    var rowCantSplit: [Bool]? = nil
    var location: Int = 0
    var length: Int = 0

    var effectiveRowSpan: Int { rowSpan ?? 1 }
    var effectiveColumnSpan: Int { columnSpan ?? 1 }
}

struct WriterTable {
    var id = UUID()
    var cells: [[NSAttributedString]]
    var cellIDs: [[UUID]]
    var widths: [Double]
    /// An origin has a positive span; covered grid slots contain zero.
    var rowSpans: [[Int]]
    var columnSpans: [[Int]]
    var nestedTables: [[[NestedTableAnchor]]]
    /// Per-origin-cell Word vertical alignment: top / center / bottom / both.
    var verticalAlignments: [[String?]]
    /// Per-physical-row Word w:cantSplit semantics.
    var rowCantSplit: [Bool]
    var header = false
    var range = NSRange(location: 0, length: 0)
    var rows: Int { cells.count }
    var columns: Int { widths.count }

    init(rows: Int, columns: Int) throws {
        guard (1...100).contains(rows), (1...20).contains(columns), rows * columns <= 1000 else {
            throw WriterError.message("Tables support 1–100 rows, 1–20 columns, and at most 1,000 cells.")
        }
        cells = (0..<rows).map { _ in (0..<columns).map { _ in NSAttributedString(string: "", attributes: [.font: WriterStyle.defaultFont]) } }
        cellIDs = (0..<rows).map { _ in (0..<columns).map { _ in UUID() } }
        rowSpans = (0..<rows).map { _ in Array(repeating: 1, count: columns) }
        columnSpans = (0..<rows).map { _ in Array(repeating: 1, count: columns) }
        nestedTables = (0..<rows).map { _ in (0..<columns).map { _ in [] } }
        verticalAlignments = (0..<rows).map { _ in Array<String?>(repeating: nil, count: columns) }
        rowCantSplit = Array(repeating: false, count: rows)
        widths = Array(repeating: 100 / Double(columns), count: columns)
    }
}

enum Tables {
    static func records(in text: NSAttributedString) throws -> [TableCellRecord] {
        var records: [TableCellRecord] = [], failure = false
        text.enumerateAttribute(.tableCell, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard let value else { return }
            guard let data = value as? Data, var record = try? JSONDecoder().decode(TableCellRecord.self, from: data) else { failure = true; return }
            record.location = range.location; record.length = range.length
            records.append(record)
        }
        guard !failure else { throw WriterError.message("Malformed table metadata.") }
        try validate(records, in: text)
        return records
    }

    private static func validate(_ records: [TableCellRecord], in text: NSAttributedString) throws {
        var tableIDs = Set<UUID>(), cellIDs = Set<UUID>(), index = 0, end = 0
        let string = text.string as NSString
        let supportedVerticalAlignments = Set(["top", "center", "bottom", "both"])
        while index < records.count {
            let first = records[index]
            guard first.rowCantSplit == nil || first.rowCantSplit?.count == first.rows else {
                throw WriterError.message("Malformed table row cannot-split metadata.")
            }
            guard (1...100).contains(first.rows), (1...20).contains(first.columns),
                  first.rows * first.columns <= 1000,
                  first.widths.count == first.columns,
                  first.widths.allSatisfy({ $0.isFinite && $0 > 0 && $0 <= 10000 }),
                  tableIDs.insert(first.tableID).inserted, first.location >= end else {
                throw WriterError.message("Invalid table dimensions or order.")
            }
            var occupied = Array(repeating: false, count: first.rows * first.columns)
            var cursor = first.location
            var previousSlot = -1
            while index < records.count && records[index].tableID == first.tableID {
                let cell = records[index]
                guard cell.rowCantSplit == first.rowCantSplit,
                      cell.verticalAlignment == nil || supportedVerticalAlignments.contains(cell.verticalAlignment!) else {
                    throw WriterError.message("Malformed Word table alignment metadata.")
                }
                let slot = cell.row * first.columns + cell.column
                guard cell.rows == first.rows, cell.columns == first.columns,
                      cell.widths == first.widths, cell.header == first.header,
                      (0..<first.rows).contains(cell.row), (0..<first.columns).contains(cell.column),
                      (1...(first.rows - cell.row)).contains(cell.effectiveRowSpan),
                      (1...(first.columns - cell.column)).contains(cell.effectiveColumnSpan),
                      slot > previousSlot, cellIDs.insert(cell.id).inserted,
                      cell.location == cursor, cell.length > 0,
                      cell.location <= text.length, cell.length <= text.length - cell.location,
                      string.substring(with: NSRange(location: cell.location + cell.length - 1, length: 1)) == "\n" else {
                    throw WriterError.message("A table cell is missing or malformed. The document was not changed.")
                }
                for row in cell.row..<(cell.row + cell.effectiveRowSpan) {
                    for column in cell.column..<(cell.column + cell.effectiveColumnSpan) {
                        let covered = row * first.columns + column
                        guard !occupied[covered] else {
                            throw WriterError.message("Overlapping table cells. The document was not changed.")
                        }
                        occupied[covered] = true
                    }
                }
                previousSlot = slot
                cursor += cell.length
                index += 1
            }
            guard occupied.allSatisfy({ $0 }) else {
                throw WriterError.message("A table cell is missing. The document was not changed.")
            }
            end = cursor
        }
    }

    static func models(in text: NSAttributedString) throws -> [WriterTable] {
        let records = try records(in: text)
        var tables: [WriterTable] = [], index = 0
        while index < records.count {
            let first = records[index]
            var table = try WriterTable(rows: first.rows, columns: first.columns)
            table.id = first.tableID; table.widths = first.widths; table.header = first.header
            if let rowCantSplit = first.rowCantSplit, rowCantSplit.count == table.rows {
                table.rowCantSplit = rowCantSplit
            }
            while index < records.count && records[index].tableID == first.tableID {
                let cell = records[index]
                let content = NSMutableAttributedString(attributedString: text.attributedSubstring(from: NSRange(location: cell.location, length: cell.length - 1)))
                clearStructure(content)
                table.cells[cell.row][cell.column] = content
                table.cellIDs[cell.row][cell.column] = cell.id
                table.rowSpans[cell.row][cell.column] = cell.effectiveRowSpan
                table.columnSpans[cell.row][cell.column] = cell.effectiveColumnSpan
                table.nestedTables[cell.row][cell.column] = cell.nestedTables ?? []
                table.verticalAlignments[cell.row][cell.column] = cell.verticalAlignment
                for row in cell.row..<(cell.row + cell.effectiveRowSpan) {
                    for column in cell.column..<(cell.column + cell.effectiveColumnSpan) where row != cell.row || column != cell.column {
                        table.rowSpans[row][column] = 0
                        table.columnSpans[row][column] = 0
                    }
                }
                index += 1
            }
            let last = records[index - 1]
            table.range = NSRange(location: first.location, length: last.location + last.length - first.location)
            tables.append(table)
        }
        return tables
    }

    static func clearStructure(_ text: NSMutableAttributedString) {
        let range = NSRange(location: 0, length: text.length)
        text.removeAttribute(.tableCell, range: range)
        var paragraphs: [(NSRange, NSParagraphStyle)] = []
        text.enumerateAttribute(.paragraphStyle, in: range) { value, range, _ in
            if let style = value as? NSParagraphStyle { paragraphs.append((range, style)) }
        }
        for (range, style) in paragraphs {
            let copy = style.mutableCopy() as! NSMutableParagraphStyle
            copy.textBlocks = []
            text.addAttribute(.paragraphStyle, value: copy, range: range)
        }
    }

    static func rendered(_ model: WriterTable) throws -> NSAttributedString {
        let supportedVerticalAlignments =
            Set(
                [
                    "top",
                    "center",
                    "bottom",
                    "both"
                ]
            )

        guard
            model.verticalAlignments.count == model.rows,
            model.verticalAlignments.allSatisfy({
                $0.count == model.columns
            }),
            model.rowCantSplit.count == model.rows,
            model.verticalAlignments
                .flatMap({ $0 })
                .allSatisfy({
                    value in

                    value == nil
                        || supportedVerticalAlignments
                            .contains(
                                value!
                            )
                })
        else {
            throw WriterError.message(
                "Invalid Word table alignment metadata."
            )
        }


        guard (1...100).contains(model.rows), (1...20).contains(model.columns), model.rows * model.columns <= 1000,
              model.widths.allSatisfy({ $0.isFinite && $0 > 0 && $0 <= 10000 }),
              model.cells.count == model.rows, model.cellIDs.count == model.rows,
              model.rowSpans.count == model.rows, model.columnSpans.count == model.rows,
              model.nestedTables.count == model.rows,
              model.cells.allSatisfy({ $0.count == model.columns }), model.cellIDs.allSatisfy({ $0.count == model.columns }),
              model.rowSpans.allSatisfy({ $0.count == model.columns }),
              model.columnSpans.allSatisfy({ $0.count == model.columns }),
              model.nestedTables.allSatisfy({ $0.count == model.columns }) else { throw WriterError.message("Invalid table cells.") }
        let table = NSTextTable()
        table.numberOfColumns = model.columns
        table.layoutAlgorithm = .fixedLayoutAlgorithm
        table.collapsesBorders = true
        table.setValue(100, type: .percentageValueType, for: .width)
        let result = NSMutableAttributedString()
        for row in 0..<model.rows {
            for column in 0..<model.columns {
                let rowSpan = model.rowSpans[row][column]
                let columnSpan = model.columnSpans[row][column]
                guard rowSpan >= 0, columnSpan >= 0,
                      rowSpan <= model.rows - row, columnSpan <= model.columns - column,
                      (rowSpan == 0) == (columnSpan == 0) else {
                    throw WriterError.message("Invalid merged table cells.")
                }
                if rowSpan == 0 { continue }
                let content = NSMutableAttributedString(attributedString: model.cells[row][column])
                clearStructure(content)
                var nested = model.nestedTables[row][column]
                if !nested.isEmpty {
                    let ns = content.string as NSString
                    var search = 0
                    for index in nested.indices {
                        let found = ns.range(of: NestedTableAnchor.placeholder,
                                             options: [],
                                             range: NSRange(location: search, length: ns.length - search))
                        guard found.location != NSNotFound else {
                            throw WriterError.message("A nested table placeholder is missing. The table was not changed.")
                        }
                        nested[index].offset = found.location
                        search = NSMaxRange(found)
                    }
                }
                // Each cell owns a final paragraph terminator, including empty cells.
                content.append(NSAttributedString(string: "\n", attributes: [.font: WriterStyle.defaultFont, .foregroundColor: NSColor.textColor]))
                let block = NSTextTableBlock(table: table, startingRow: row, rowSpan: rowSpan, startingColumn: column, columnSpan: columnSpan)
                let spanWidth = model.widths[column..<(column + columnSpan)].reduce(0, +)
                block.setValue(spanWidth / model.widths.reduce(0, +) * 100, type: .percentageValueType, for: .width)
                block.setWidth(6, type: .absoluteValueType, for: .padding)
                block.setWidth(0.5, type: .absoluteValueType, for: .border)
                block.setBorderColor(.gray)
                if model.header && row == 0 { block.backgroundColor = NSColor.quaternaryLabelColor }
                let full = NSRange(location: 0, length: content.length)
                var styles: [(NSRange, NSParagraphStyle?)] = []
                content.enumerateAttribute(.paragraphStyle, in: full) { value, range, _ in styles.append((range, value as? NSParagraphStyle)) }
                for (range, style) in styles {
                    let paragraph = style?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
                    paragraph.textBlocks = [block]
                    content.addAttribute(.paragraphStyle, value: paragraph, range: range)
                }
                let record = TableCellRecord(tableID: model.id, id: model.cellIDs[row][column], row: row, column: column, rows: model.rows, columns: model.columns, widths: model.widths, header: model.header, rowSpan: rowSpan == 1 ? nil : rowSpan, columnSpan: columnSpan == 1 ? nil : columnSpan, nestedTables: nested.isEmpty ? nil : nested, verticalAlignment: model.verticalAlignments[row][column], rowCantSplit: model.rowCantSplit)
                content.addAttribute(.tableCell, value: try JSONEncoder().encode(record), range: full)
                result.append(content)
            }
        }
        _ = try records(in: result)
        return result
    }

    static func restore(_ records: [TableCellRecord], into text: NSMutableAttributedString) throws {
        try validate(records, in: text)
        for var record in records {
            let range = NSRange(location: record.location, length: record.length)
            record.location = 0; record.length = 0
            text.addAttribute(.tableCell, value: try JSONEncoder().encode(record), range: range)
        }
        // Rebuild native blocks without changing the text or its offsets.
        for model in try models(in: text).reversed() { text.replaceCharacters(in: model.range, with: try rendered(model)) }
    }

    static func archivable(_ text: NSAttributedString) throws -> NSAttributedString {
        let cells = try records(in: text)
        let result = NSMutableAttributedString(attributedString: text)
        for cell in cells.reversed() {
            let range = NSRange(location: cell.location, length: cell.length)
            let content = NSMutableAttributedString(attributedString: result.attributedSubstring(from: range))
            clearStructure(content)
            result.replaceCharacters(in: range, with: content)
        }
        return result
    }
}


extension Tables {
    static let pasteboardType = NSPasteboard.PasteboardType("com.boldwriter.structured-tables")

    static func clipboardData(_ text: NSAttributedString) throws -> Data {
        guard !(try records(in: text)).isEmpty,
              let data = try BOLDWriterDocument.packageWrapper(text: text, metadata: DocumentMetadata()).serializedRepresentation else {
            throw WriterError.message("Select a complete table to copy its structure.")
        }
        return data
    }

    static func clipboardText(_ data: Data) throws -> NSAttributedString {
        guard let wrapper = FileWrapper(serializedRepresentation: data) else { throw WriterError.message("Invalid table clipboard data.") }
        let document = try BOLDWriterDocument(fileWrapper: wrapper, contentType: .boldWriterDocument)
        let result = NSMutableAttributedString(attributedString: document.text)
        // A pasted copy gets new identities; edits to it cannot affect the original.
        for note in try Footnotes.records(in: result) {
            result.addAttribute(.footnote, value: ["id": UUID().uuidString, "text": note.text], range: NSRange(location: note.location, length: note.length))
        }

        for note in try Endnotes.records(in: result) {
            result.addAttribute(.endnote, value: ["id": UUID().uuidString, "text": note.text], range: NSRange(location: note.location, length: note.length))
        }
        for var model in try models(in: result).reversed() {
            model.id = UUID()
            model.cellIDs = (0..<model.rows).map { _ in (0..<model.columns).map { _ in UUID() } }
            result.replaceCharacters(in: model.range, with: try rendered(model))
        }
        return result
    }
}
