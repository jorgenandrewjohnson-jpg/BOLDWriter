import AppKit

struct ImportedTable {
    var model: WriterTable
    var markers: [(start: String, end: String, row: Int, column: Int)]
}

extension DOCXImporter {
    static func prepareTables(in xml: XMLDocument) throws -> [ImportedTable] {
        let nodes = try xml.nodes(forXPath: "//*[local-name()='tbl' and not(ancestor::*[local-name()='tbl'])]").compactMap { $0 as? XMLElement }
        var result: [ImportedTable] = []
        func failure() -> WriterError { .message("This DOCX table has malformed cells or an unsupported irregular grid. Import was stopped without changing the source file.") }
        func value(_ node: XMLNode, _ attribute: String) -> String? {
            (node as? XMLElement)?.attributes?.first { $0.localName == attribute }?.stringValue
        }
        func markerRun(_ marker: String) -> XMLElement {
            let run = XMLElement(name: "w:r")
            run.addChild(XMLElement(name: "w:t", stringValue: marker))
            return run
        }
        var nestedCellBudget = 0
        func snapshot(_ table: XMLElement, depth: Int) throws -> NestedTableSnapshot {
            guard depth <= 12, table.xmlString.utf8.count <= 8_000_000 else { throw failure() }
            let rowNodes = try table.nodes(forXPath: "./*[local-name()='tr']")
            guard !rowNodes.isEmpty, rowNodes.count <= 1000 else { throw failure() }
            var rows: [[NestedTableCellSnapshot]] = []
            for row in rowNodes {
                let cells = try row.nodes(forXPath: "./*[local-name()='tc']")
                guard !cells.isEmpty, cells.count <= 1000 else { throw failure() }
                nestedCellBudget += cells.count
                guard nestedCellBudget <= 10_000 else { throw failure() }
                var decoded: [NestedTableCellSnapshot] = []
                for cell in cells {
                    var blocks: [NestedTableBlockSnapshot] = []
                    for child in (cell.children ?? []).compactMap({ $0 as? XMLElement }) {
                        switch child.localName {
                        case "tcPr": break
                        case "p": blocks.append(NestedTableBlockSnapshot(paragraphXML: child.xmlString))
                        case "tbl": blocks.append(NestedTableBlockSnapshot(table: try snapshot(child, depth: depth + 1)))
                        default: throw failure()
                        }
                    }
                    guard !blocks.isEmpty else { throw failure() }
                    decoded.append(NestedTableCellSnapshot(blocks: blocks))
                }
                rows.append(decoded)
            }
            return NestedTableSnapshot(xml: table.xmlString, rows: rows)
        }
        for node in nodes {
            guard try node.nodes(forXPath: ".//*[local-name()='gridBefore' or local-name()='gridAfter' or local-name()='hMerge']").isEmpty else { throw failure() }
            let rows = try node.nodes(forXPath: "./*[local-name()='tr']")
            guard let first = rows.first else { throw failure() }
            let grid = try node.nodes(forXPath: "./*[local-name()='tblGrid']/*[local-name()='gridCol']")
            let firstCells = try first.nodes(forXPath: "./*[local-name()='tc']")
            func span(_ cell: XMLNode) throws -> Int {
                guard let element = try cell.nodes(forXPath: "./*[local-name()='tcPr']/*[local-name()='gridSpan']").first else { return 1 }
                guard let raw = value(element, "val"), let count = Int(raw), (1...20).contains(count) else { throw failure() }
                return count
            }
            let firstColumns = try firstCells.reduce(0) { try $0 + span($1) }
            let columns = grid.isEmpty ? firstColumns : grid.count
            guard (1...20).contains(columns), firstColumns == columns else { throw failure() }
            var model = try WriterTable(rows: rows.count, columns: columns)
            if !grid.isEmpty {
                let widths = grid.compactMap { Double(value($0, "w") ?? "") }
                guard widths.count == columns, widths.allSatisfy({ $0.isFinite && $0 > 0 && $0 < 1_000_000 }) else { throw failure() }
                model.widths = widths.map { $0 / widths.reduce(0, +) * 100 }
            } else if firstCells.count == columns {
                let widths = try firstCells.map { cell -> Double? in
                    guard let width = try cell.nodes(forXPath: "./*[local-name()='tcPr']/*[local-name()='tcW']").first else { return nil }
                    return Double(value(width, "w") ?? "")
                }.compactMap { $0 }
                if widths.count == columns, widths.allSatisfy({ $0.isFinite && $0 > 0 && $0 < 1_000_000 }) { model.widths = widths.map { $0 / widths.reduce(0, +) * 100 } }
            }
            if let header = try first.nodes(forXPath: "./*[local-name()='trPr']/*[local-name()='tblHeader']").first {
                model.header = !["0", "false", "off"].contains(value(header, "val") ?? "true")
            }
            var paragraphs: [XMLElement] = []
            var markers: [(start: String, end: String, row: Int, column: Int)] = []
            var activeVertical: [Int: (row: Int, column: Int)] = [:]
            for (rowIndex, row) in rows.enumerated() {
                if let cantSplit = try row.nodes(forXPath: "./*[local-name()='trPr']/*[local-name()='cantSplit']").first {
                    let raw = (value(cantSplit, "val") ?? "true").lowercased()
                    guard ["true", "1", "on", "false", "0", "off"].contains(raw) else { throw failure() }
                    model.rowCantSplit[rowIndex] = !["false", "0", "off"].contains(raw)
                }
                let cells = try row.nodes(forXPath: "./*[local-name()='tc']")
                var column = 0
                var nextVertical: [Int: (row: Int, column: Int)] = [:]
                for cell in cells {
                    let width = try span(cell)
                    guard column + width <= columns else { throw failure() }
                    let mergeNode = try cell.nodes(forXPath: "./*[local-name()='tcPr']/*[local-name()='vMerge']").first
                    let merge = mergeNode.map { value($0, "val") ?? "continue" }
                    if let merge, merge != "restart" && merge != "continue" { throw failure() }
                    let origin: (row: Int, column: Int)
                    if merge == "continue" {
                        guard let previous = activeVertical[column],
                              (column..<(column + width)).allSatisfy({ activeVertical[$0]?.row == previous.row && activeVertical[$0]?.column == previous.column }),
                              model.columnSpans[previous.row][previous.column] == width else { throw failure() }
                        origin = previous
                        model.rowSpans[origin.row][origin.column] += 1
                        for covered in column..<(column + width) {
                            model.rowSpans[rowIndex][covered] = 0
                            model.columnSpans[rowIndex][covered] = 0
                        }
                    } else {
                        origin = (rowIndex, column)
                        model.columnSpans[rowIndex][column] = width
                        for covered in (column + 1)..<(column + width) {
                            model.rowSpans[rowIndex][covered] = 0
                            model.columnSpans[rowIndex][covered] = 0
                        }
                    }
                    if let verticalNode = try cell.nodes(forXPath: "./*[local-name()='tcPr']/*[local-name()='vAlign']").first {
                        guard let rawValue = value(verticalNode, "val")?.lowercased(),
                              ["top", "center", "bottom", "both"].contains(rawValue) else { throw failure() }
                        let existing = model.verticalAlignments[origin.row][origin.column]
                        guard existing == nil || existing == rawValue else { throw failure() }
                        model.verticalAlignments[origin.row][origin.column] = rawValue
                    }
                    if merge != nil {
                        for covered in column..<(column + width) { nextVertical[covered] = origin }
                    }
                    let children = (cell.children ?? []).compactMap { $0 as? XMLElement }
                    guard children.allSatisfy({ ["tcPr", "p", "tbl"].contains($0.localName ?? "") }) else { throw failure() }
                    var content: [XMLElement] = []
                    for child in children {
                        if child.localName == "p" {
                            content.append(child.copy() as! XMLElement)
                        } else if child.localName == "tbl" {
                            let anchor = NestedTableAnchor(table: try snapshot(child, depth: 1))
                            model.nestedTables[origin.row][origin.column].append(anchor)
                            let paragraph = XMLElement(name: "w:p")
                            paragraph.addChild(markerRun(anchor.importMarker))
                            content.append(paragraph)
                        }
                    }
                    guard let firstParagraph = content.first, let lastParagraph = content.last else { throw failure() }
                    let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
                    let start = "BOLDTABLESTART" + token, end = "BOLDTABLEEND" + token
                    let insertionIndex = firstParagraph.children?.first?.localName == "pPr" ? 1 : 0
                    firstParagraph.insertChild(markerRun(start), at: insertionIndex)
                    lastParagraph.addChild(markerRun(end))
                    markers.append((start, end, origin.row, origin.column))
                    paragraphs.append(contentsOf: content)
                    column += width
                }
                guard column == columns else { throw failure() }
                activeVertical = nextVertical
            }
            guard let parent = node.parent as? XMLElement else { throw failure() }
            let index = node.index
            node.detach()
            for (offset, paragraph) in paragraphs.enumerated() { parent.insertChild(paragraph, at: index + offset) }
            result.append(ImportedTable(model: model, markers: markers))
        }
        return result
    }

    static func restoreTables(_ tables: [ImportedTable], into text: NSMutableAttributedString) throws {
        for imported in tables.reversed() {
            var model = imported.model
            var start = 0, end = 0
            for (index, markers) in imported.markers.enumerated() {
                let ns = text.string as NSString
                let begin = ns.range(of: markers.start), finish = ns.range(of: markers.end)
                guard begin.location != NSNotFound, finish.location != NSNotFound,
                      NSMaxRange(begin) <= finish.location else { throw WriterError.message("A DOCX table cell could not be recovered.") }
                if index == 0 { start = begin.location }
                end = NSMaxRange(finish)
                let content = text.attributedSubstring(from: NSRange(location: NSMaxRange(begin), length: finish.location - NSMaxRange(begin)))
                let existing = model.cells[markers.row][markers.column]
                if existing.length == 0 {
                    model.cells[markers.row][markers.column] = content
                } else if !content.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let joined = NSMutableAttributedString(attributedString: existing)
                    joined.append(NSAttributedString(string: "\n"))
                    joined.append(content)
                    model.cells[markers.row][markers.column] = joined
                }
            }
            for row in 0..<model.rows {
                for column in 0..<model.columns where !model.nestedTables[row][column].isEmpty {
                    let content = NSMutableAttributedString(attributedString: model.cells[row][column])
                    for index in model.nestedTables[row][column].indices {
                        let marker = model.nestedTables[row][column][index].importMarker
                        let found = (content.string as NSString).range(of: marker)
                        guard found.location != NSNotFound else { throw WriterError.message("A nested DOCX table could not be recovered.") }
                        content.replaceCharacters(in: found, with: NestedTableAnchor.placeholder)
                        model.nestedTables[row][column][index].offset = found.location
                    }
                    model.cells[row][column] = content
                }
            }
            if end < text.length, (text.string as NSString).substring(with: NSRange(location: end, length: 1)) == "\n" { end += 1 }
            text.replaceCharacters(in: NSRange(location: start, length: end - start), with: try Tables.rendered(model))
        }
    }
}
