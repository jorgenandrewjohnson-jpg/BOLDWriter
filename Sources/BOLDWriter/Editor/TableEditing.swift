import AppKit

@MainActor
extension EditorController {
    func insertTable(rows: Int = 3, columns: Int = 3) {
        guard let view = textView else { return }
        do {
            guard try selectedTable() == nil else { throw WriterError.message("Nested tables are not supported. Place the cursor outside the table first.") }
            let table = try WriterTable(rows: rows, columns: columns)
            let point = view.selectedRange().location
            let insertion = NSMutableAttributedString()
            let prefix = point > 0 && (view.string as NSString).substring(with: NSRange(location: point - 1, length: 1)) != "\n" ? "\n" : ""
            insertion.append(NSAttributedString(string: prefix, attributes: [.font: WriterStyle.defaultFont]))
            insertion.append(try Tables.rendered(table))
            insertion.append(NSAttributedString(string: "\n", attributes: [.font: WriterStyle.defaultFont, .foregroundColor: NSColor.textColor]))
            performUndoableMutation("Insert Table") { view in
                view.textStorage?.insert(insertion, at: point)
                view.setSelectedRange(NSRange(location: point + prefix.utf16.count, length: 0))
            }
            updateTableTypingAttributes()
        } catch { showTableError(error) }
    }

    func showInsertTable() {
        let alert = NSAlert()
        alert.messageText = "Insert Table"
        alert.informativeText = "Choose rows and columns (up to 1,000 cells)."
        let rows = NSTextField(string: "3"), columns = NSTextField(string: "3")
        let stack = NSStackView(views: [NSTextField(labelWithString: "Rows"), rows, NSTextField(labelWithString: "Columns"), columns])
        stack.orientation = .horizontal; stack.spacing = 8
        stack.frame = NSRect(x: 0, y: 0, width: 320, height: 28)
        alert.accessoryView = stack
        alert.addButton(withTitle: "Insert"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        insertTable(rows: rows.integerValue, columns: columns.integerValue)
    }

    func selectedTable() throws -> (WriterTable, TableCellRecord)? {
        guard let view = textView else { return nil }
        let point = view.selectedRange().location
        guard let record = try Tables.records(in: view.attributedString()).first(where: { NSLocationInRange(point, NSRange(location: $0.location, length: $0.length)) }),
              let model = try Tables.models(in: view.attributedString()).first(where: { $0.id == record.tableID }) else { return nil }
        return (model, record)
    }

    func tableCommand(_ command: String) {
        do {
            guard var (model, cell) = try selectedTable() else { return }
            let hasMerges = model.rowSpans.flatMap { $0 }.contains { $0 != 1 }
                || model.columnSpans.flatMap { $0 }.contains { $0 != 1 }
            if hasMerges && ["addRow", "deleteRow", "addColumn", "deleteColumn"].contains(command) {
                throw WriterError.message("Changing the grid of a merged table is not supported. Its merged cells have been preserved.")
            }
            switch command {
            case "addRow":
                guard model.rows < 100, (model.rows + 1) * model.columns <= 1000 else { throw WriterError.message("This table has reached the supported size limit.") }
                model.cells.insert(Array(repeating: NSAttributedString(string: ""), count: model.columns), at: cell.row + 1)
                model.cellIDs.insert((0..<model.columns).map { _ in UUID() }, at: cell.row + 1)
                model.rowSpans.insert(Array(repeating: 1, count: model.columns), at: cell.row + 1)
                model.columnSpans.insert(Array(repeating: 1, count: model.columns), at: cell.row + 1)
                model.nestedTables.insert((0..<model.columns).map { _ in [] }, at: cell.row + 1)
                model.verticalAlignments.insert(Array<String?>(repeating: nil, count: model.columns), at: cell.row + 1)
                model.rowCantSplit.insert(false, at: cell.row + 1)
                cell.row += 1
            case "deleteRow":
                if model.rows == 1 { deleteTable(model); return }
                model.cells.remove(at: cell.row); model.cellIDs.remove(at: cell.row)
                model.rowSpans.remove(at: cell.row); model.columnSpans.remove(at: cell.row)
                model.nestedTables.remove(at: cell.row)
                model.verticalAlignments.remove(at: cell.row)
                model.rowCantSplit.remove(at: cell.row)
                cell.row = min(cell.row, model.rows - 1)
            case "addColumn":
                guard model.columns < 20, model.rows * (model.columns + 1) <= 1000 else { throw WriterError.message("This table has reached the supported size limit.") }
                for row in 0..<model.rows {
                    model.cells[row].insert(NSAttributedString(string: ""), at: cell.column + 1)
                    model.cellIDs[row].insert(UUID(), at: cell.column + 1)
                    model.rowSpans[row].insert(1, at: cell.column + 1)
                    model.columnSpans[row].insert(1, at: cell.column + 1)
                    model.nestedTables[row].insert([], at: cell.column + 1)
                    model.verticalAlignments[row].insert(nil, at: cell.column + 1)
                }
                model.widths.insert(model.widths[cell.column], at: cell.column + 1)
                cell.column += 1
            case "deleteColumn":
                if model.columns == 1 { deleteTable(model); return }
                for row in 0..<model.rows {
                    model.cells[row].remove(at: cell.column)
                    model.cellIDs[row].remove(at: cell.column)
                    model.rowSpans[row].remove(at: cell.column)
                    model.columnSpans[row].remove(at: cell.column)
                    model.nestedTables[row].remove(at: cell.column)
                    model.verticalAlignments[row].remove(at: cell.column)
                }
                model.widths.remove(at: cell.column)
                cell.column = min(cell.column, model.columns - 1)
            case "deleteTable": deleteTable(model); return
            case "header": model.header.toggle()
            case "wider": model.widths[cell.column] = min(1000, model.widths[cell.column] * 1.2)
            case "narrower": model.widths[cell.column] = max(1, model.widths[cell.column] / 1.2)
            default: return
            }
            let names = ["addRow": "Add Table Row", "deleteRow": "Delete Table Row", "addColumn": "Add Table Column", "deleteColumn": "Delete Table Column", "header": "Toggle Header Row", "wider": "Widen Column", "narrower": "Narrow Column"]
            try replaceTable(model, selecting: model.cellIDs[cell.row][cell.column], action: names[command] ?? "Edit Table")
        } catch { showTableError(error) }
    }

    private func deleteTable(_ table: WriterTable) {
        performUndoableMutation("Delete Table") { view in
            view.textStorage?.deleteCharacters(in: table.range)
            view.setSelectedRange(NSRange(location: table.range.location, length: 0))
        }
        updateTableTypingAttributes()
    }

    func replaceTable(_ table: WriterTable, selecting cellID: UUID, offset: Int = 0, action: String) throws {
        let replacement = try Tables.rendered(table)
        let cell = try Tables.records(in: replacement).first { $0.id == cellID }
        performUndoableMutation(action) { view in
            view.textStorage?.replaceCharacters(in: table.range, with: replacement)
            let point = table.range.location + (cell?.location ?? 0) + min(offset, max(0, (cell?.length ?? 1) - 1))
            view.setSelectedRange(NSRange(location: point, length: 0))
        }
        updateTableTypingAttributes()
    }

    /// Cell terminators are structural boundaries. Edit content with a table snapshot
    /// so AppKit cannot accidentally merge adjacent cells when deleting a newline.
    func handleTableEdit(
        range: NSRange,
        replacement: NSAttributedString,
        trackChanges: Bool = false
    ) -> Bool {
        guard let view = textView else { return false }
        do {
            let records = try Tables.records(in: view.attributedString())
            let touched = records.filter { range.length == 0 ? NSLocationInRange(range.location, NSRange(location: $0.location, length: $0.length)) : NSIntersectionRange(range, NSRange(location: $0.location, length: $0.length)).length > 0 }
            guard !touched.isEmpty else { return false }
            let models = try Tables.models(in: view.attributedString())
            if touched.count == 1, let cell = touched.first,
               range.location >= cell.location, NSMaxRange(range) <= cell.location + cell.length - 1,
               var table = models.first(where: { $0.id == cell.tableID }) {

                if trackChanges {
                    let tracked =
                        NSMutableAttributedString(
                            attributedString:
                                replacement
                        )

                    if tracked.length > 0,
                       view.attributedString().length > 0 {
                        let anchor =
                            min(
                                max(
                                    range.location,
                                    cell.location
                                ),
                                cell.location
                                    + cell.length
                                    - 1
                            )

                        if anchor
                            < view.attributedString()
                                .length {
                            let structural =
                                view.attributedString()
                                    .attributes(
                                        at: anchor,
                                        effectiveRange: nil
                                    )

                            if let value =
                                structural[
                                    .tableCell
                                ] {
                                tracked.addAttribute(
                                    .tableCell,
                                    value: value,
                                    range:
                                        NSRange(
                                            location: 0,
                                            length:
                                                tracked.length
                                        )
                                )
                            }

                            if let tableStyle =
                                structural[
                                    .paragraphStyle
                                ]
                                    as? NSParagraphStyle {
                                tracked.enumerateAttribute(
                                    .paragraphStyle,
                                    in:
                                        NSRange(
                                            location: 0,
                                            length:
                                                tracked.length
                                        )
                                ) {
                                    value,
                                    subrange,
                                    _ in

                                    let style =
                                        (
                                            value
                                                as? NSParagraphStyle
                                        )?
                                        .mutableCopy()
                                            as? NSMutableParagraphStyle
                                        ?? NSMutableParagraphStyle()

                                    style.textBlocks =
                                        tableStyle
                                            .textBlocks

                                    tracked.addAttribute(
                                        .paragraphStyle,
                                        value: style,
                                        range:
                                            subrange
                                    )
                                }
                            }
                        }
                    }

                    if trackTextEdit(
                        range: range,
                        replacement: tracked
                    ) {
                        _ =
                            try Tables.records(
                                in:
                                    view.attributedString()
                            )

                        updateTableTypingAttributes()
                        return true
                    }
                }

                let content = NSMutableAttributedString(attributedString: table.cells[cell.row][cell.column])
                let clean = NSMutableAttributedString(attributedString: replacement)
                Tables.clearStructure(clean)
                content.replaceCharacters(in: NSRange(location: range.location - cell.location, length: range.length), with: clean)
                table.cells[cell.row][cell.column] = content
                try replaceTable(table, selecting: cell.id, offset: range.location - cell.location + clean.length, action: "Edit Table Cell")
            } else if models.filter({ model in touched.contains(where: { $0.tableID == model.id }) }).allSatisfy({ NSIntersectionRange(range, $0.range) == $0.range }) {
                let clean = NSMutableAttributedString(attributedString: replacement); Tables.clearStructure(clean)
                performUndoableMutation("Replace Table") { view in
                    view.textStorage?.replaceCharacters(in: range, with: clean)
                    view.setSelectedRange(NSRange(location: range.location + clean.length, length: 0))
                }
                updateTableTypingAttributes()
            } else { NSSound.beep() }
            return true
        } catch { showTableError(error); return true }
    }

    func navigateTable(forward: Bool) -> Bool {
        do {
            guard let view = textView, let (table, cell) = try selectedTable() else { return false }
            let records = try Tables.records(in: view.attributedString()).filter { $0.tableID == table.id }
            guard let current = records.firstIndex(where: { $0.id == cell.id }) else { return false }
            let next = current + (forward ? 1 : -1)
            if next == records.count {
                tableCommand("addRow")
                if let (_, current) = try selectedTable(), let first = try Tables.records(in: view.attributedString()).first(where: { $0.tableID == current.tableID && $0.row == current.row && $0.column == 0 }) {
                    navigate(to: NSRange(location: first.location, length: 0))
                }
            } else if records.indices.contains(next) { navigate(to: NSRange(location: records[next].location, length: 0)) }
            updateTableTypingAttributes()
            return true
        } catch { showTableError(error); return true }
    }

    func updateTableTypingAttributes() {
        guard let view = textView else { return }
        let point = view.selectedRange().location
        if point < view.attributedString().length, view.attributedString().attribute(.tableCell, at: point, effectiveRange: nil) != nil {
            view.typingAttributes = view.attributedString().attributes(at: point, effectiveRange: nil)
            clearFootnoteTypingAttributes()
            clearEndnoteTypingAttributes()
        } else if view.typingAttributes[.tableCell] != nil {
            var attrs = view.typingAttributes
            attrs.removeValue(forKey: .tableCell)
            let style = (attrs[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            style.textBlocks = []; attrs[.paragraphStyle] = style
            view.typingAttributes = attrs
        }
    }

    func pasteTables(
        _ data: Data,
        trackChanges: Bool = false
    ) -> Bool {
        guard let view = textView else { return false }
        do {
            guard try selectedTable() == nil else { return false }
            let content = NSMutableAttributedString(attributedString: try Tables.clipboardText(data))
            let selection = view.selectedRange()
            if selection.location > 0 && (view.string as NSString).substring(with: NSRange(location: selection.location - 1, length: 1)) != "\n" {
                content.insert(NSAttributedString(string: "\n", attributes: [.font: WriterStyle.defaultFont]), at: 0)
            }
            if !content.string.hasSuffix("\n") { content.append(NSAttributedString(string: "\n")) }
            content.append(NSAttributedString(string: "\n", attributes: [.font: WriterStyle.defaultFont]))
            replace(
                range:
                    selection,
                with:
                    content,
                actionName:
                    "Paste Table",
                trackChanges:
                    trackChanges
            )
            updateTableTypingAttributes()
            return true
        } catch { showTableError(error); return true }
    }

    private func showTableError(_ error: Error) {
        let alert = NSAlert(); alert.messageText = "Could not edit table"; alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}
