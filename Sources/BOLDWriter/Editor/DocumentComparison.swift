import AppKit
import Foundation

struct DocumentComparison {
    struct Change: Equatable {
        let originalRange: NSRange
        let revisedRange: NSRange
    }

    static func changes(
        from original: NSAttributedString,
        to revised: NSAttributedString
    ) -> [Change] {
        changes(
            from:
                Array(
                    original.string.utf16
                ),
            to:
                Array(
                    revised.string.utf16
                )
        )
    }

    private static func changes(
        from original: [UInt16],
        to revised: [UInt16]
    ) -> [Change] {
        guard
            original != revised
        else {
            return []
        }

        let difference =
            revised.difference(
                from:
                    original
            )

        let removals =
            Set(
                difference.compactMap {
                    change -> Int? in

                    guard
                        case let .remove(
                            offset,
                            _,
                            _
                        ) = change
                    else {
                        return nil
                    }

                    return offset
                }
            )

        let insertions =
            Set(
                difference.compactMap {
                    change -> Int? in

                    guard
                        case let .insert(
                            offset,
                            _,
                            _
                        ) = change
                    else {
                        return nil
                    }

                    return offset
                }
            )

        var oldIndex =
            0

        var newIndex =
            0

        var result: [Change] =
            []

        while
            oldIndex < original.count
                || newIndex < revised.count {

            if oldIndex < original.count,
               newIndex < revised.count,
               !removals.contains(
                    oldIndex
               ),
               !insertions.contains(
                    newIndex
               ),
               original[oldIndex]
                    == revised[newIndex] {

                oldIndex +=
                    1

                newIndex +=
                    1

                continue
            }

            let oldStart =
                oldIndex

            let newStart =
                newIndex

            while
                oldIndex < original.count
                    || newIndex < revised.count {

                if oldIndex < original.count,
                   removals.contains(
                        oldIndex
                   ) {

                    oldIndex +=
                        1

                    continue
                }

                if newIndex < revised.count,
                   insertions.contains(
                        newIndex
                   ) {

                    newIndex +=
                        1

                    continue
                }

                if oldIndex < original.count,
                   newIndex < revised.count,
                   original[oldIndex]
                        == revised[newIndex] {

                    break
                }

                if oldIndex < original.count {
                    oldIndex +=
                        1
                } else if newIndex < revised.count {
                    newIndex +=
                        1
                }
            }

            let originalRange =
                NSRange(
                    location:
                        oldStart,
                    length:
                        oldIndex
                        - oldStart
                )

            let revisedRange =
                NSRange(
                    location:
                        newStart,
                    length:
                        newIndex
                        - newStart
                )

            if originalRange.length > 0
                || revisedRange.length > 0 {

                result.append(
                    Change(
                        originalRange:
                            originalRange,
                        revisedRange:
                            revisedRange
                    )
                )
            }
        }

        return result
    }
}

@MainActor
extension EditorController {
    @discardableResult
    func compareDocument(
        with revised: NSAttributedString,
        in document: BOLDWriterDocument,
        author: String = "Document Comparison"
    ) throws -> Int {
        guard
            let view = textView,
            let storage =
                view.textStorage
        else {
            throw WriterError.message(
                "The document editor is not ready."
            )
        }

        guard
            TrackChanges.records(
                in:
                    storage
            ).isEmpty
        else {
            throw WriterError.message(
                "Resolve the existing tracked changes before comparing another document."
            )
        }

        let original =
            NSAttributedString(
                attributedString:
                    storage
            )

        let changes =
            DocumentComparison.changes(
                from:
                    original,
                to:
                    revised
            )

        guard
            !changes.isEmpty
        else {
            return 0
        }

        let undoManager =
            view.undoManager

        let openedUndoGroup =
            (
                undoManager?
                    .groupingLevel
                ?? 0
            ) == 0

        if openedUndoGroup {
            undoManager?
                .beginUndoGrouping()
        }

        defer {
            undoManager?
                .setActionName(
                    "Compare Documents"
                )

            if openedUndoGroup {
                undoManager?
                    .endUndoGrouping()
            }
        }

        for change
            in changes.reversed() {

            let replacement =
                revised.attributedSubstring(
                    from:
                        change.revisedRange
                )

            guard
                trackTextEdit(
                    range:
                        change.originalRange,
                    replacement:
                        replacement,
                    author:
                        author,
                    actionName:
                        "Compare Documents"
                )
            else {
                throw WriterError.message(
                    "The comparison could not be applied."
                )
            }
        }

        document.replaceEditedText(
            with:
                view.attributedString()
        )

        document.metadata
            .trackChangesEnabled =
            true

        return changes.count
    }
}
