import AppKit

@MainActor
extension EditorController {
    @discardableResult
    func trackAttributedPaste(
        range: NSRange,
        replacement: NSAttributedString
    ) -> Bool {
        guard
            let view = textView,
            range.location != NSNotFound
        else {
            return false
        }

        let safe =
            NoteReferences.editingRange(
                range,
                in:
                    view.attributedString()
            )

        if handleTableEdit(
            range:
                safe,
            replacement:
                replacement,
            trackChanges:
                true
        ) {
            return true
        }

        if safe != range {
            replace(
                range:
                    safe,
                with:
                    replacement,
                actionName:
                    "Paste",
                trackChanges:
                    true
            )

            return true
        }

        return trackTextEdit(
            range:
                safe,
            replacement:
                replacement
        )
    }

    @discardableResult
    func trackTextEdit(
        range: NSRange,
        replacement: NSAttributedString,
        author: String = NSFullUserName(),
        actionName: String = "Track Change"
    ) -> Bool {
        guard
            let view = textView,
            let storage = view.textStorage,
            range.location >= 0,
            range.length >= 0,
            range.location <= storage.length,
            range.length
                <= storage.length - range.location
        else {
            return false
        }

        guard
            range.length > 0
                || replacement.length > 0
        else {
            return true
        }

        // Editing text that is already a pending insertion by the
        // same author should edit that insertion itself. Deleting
        // newly inserted text cancels that portion of the insertion
        // instead of creating a deletion revision on top of it.
        if range.length > 0,
           let existingInsertion =
                insertionMarkerCovering(
                    range,
                    in: storage,
                    author: author
                ) {

            performUndoableMutation(
                actionName
            ) { view in
                guard
                    let storage = view.textStorage
                else {
                    return
                }

                if replacement.length == 0 {
                    storage.deleteCharacters(
                        in: range
                    )

                    view.setSelectedRange(
                        NSRange(
                            location: min(
                                range.location,
                                storage.length
                            ),
                            length: 0
                        )
                    )
                } else {
                    let inserted =
                        NSMutableAttributedString(
                            attributedString:
                                replacement
                        )

                    inserted.addAttribute(
                        .boldWriterTrackChange,
                        value: existingInsertion,
                        range: NSRange(
                            location: 0,
                            length: inserted.length
                        )
                    )

                    storage.replaceCharacters(
                        in: range,
                        with: inserted
                    )

                    view.setSelectedRange(
                        NSRange(
                            location:
                                range.location
                                + inserted.length,
                            length: 0
                        )
                    )
                }
            }

            refreshTrackChangeDisplay()
            return true
        }

        // Mixed selections are analyzed once and handled through
        // one mutation path. The analyzer classifies selected spans
        // as ordinary text, same-author pending insertion text, or
        // existing deletion text.
        //
        // A mixed selection contains at least two of those categories.
        // Pending insertion text is provisional and is cancelled
        // physically. Existing deletions retain their revision identity.
        // Selected ordinary text becomes new deletion revision content.
        if range.length > 0,
           let analysis =
                revisionSelectionAnalysis(
                    in: range,
                    text: storage,
                    author: author
                ),
           !analysis.containsUnsupportedRevision {

            let hasOrdinary =
                !analysis.ordinaryRanges.isEmpty

            let hasInsertions =
                !analysis.insertionRanges.isEmpty

            let hasDeletions =
                !analysis.deletionRanges.isEmpty

            let categoryCount =
                (hasOrdinary ? 1 : 0)
                + (hasInsertions ? 1 : 0)
                + (hasDeletions ? 1 : 0)

            if categoryCount >= 2 {
                let insertionMarker =
                    TrackChanges.marker(
                        kind: .insertion,
                        author: author
                    )

                // Two of the historical mixed-selection paths use one
                // shared deletion identity:
                //
                // ordinary + insertion
                // ordinary + deletion
                //
                // Keep that behavior unchanged during this refactor.
                let sharedDeletionMarker =
                    TrackChanges.marker(
                        kind: .deletion,
                        author: author
                    )

                let removedInsertionLength =
                    analysis.insertionRanges.reduce(0) {
                        $0 + $1.length
                    }

                // When insertions are removed, ordinary ranges to their
                // right shift left. Calculate those post-removal ranges
                // before mutating the storage.
                let adjustedOrdinaryRanges =
                    analysis.ordinaryRanges.map {
                        ordinaryRange in

                        let shift =
                            analysis.insertionRanges
                                .filter {
                                    $0.location
                                        < ordinaryRange.location
                                }
                                .reduce(0) {
                                    $0 + $1.length
                                }

                        return NSRange(
                            location:
                                ordinaryRange.location
                                - shift,
                            length:
                                ordinaryRange.length
                        )
                    }

                let insertionPoint =
                    NSMaxRange(range)
                    - removedInsertionLength

                performUndoableMutation(
                    actionName
                ) { view in
                    guard
                        let storage = view.textStorage
                    else {
                        return
                    }

                    // Pending insertion characters never belonged to
                    // the original document. Cancelling the selected
                    // portions physically is therefore the correct
                    // Track Changes behavior.
                    if hasInsertions {
                        for insertedRange
                            in analysis
                                .insertionRanges
                                .reversed() {

                            storage.deleteCharacters(
                                in: insertedRange
                            )
                        }
                    }

                    if hasOrdinary {
                        if hasInsertions
                            && hasDeletions {

                            // General three-way case. Ordinary spans are
                            // still separated by preserved deletion runs,
                            // so each span remains an independent change.
                            for ordinaryRange
                                in adjustedOrdinaryRanges {

                                storage.addAttribute(
                                    .boldWriterTrackChange,
                                    value:
                                        TrackChanges.marker(
                                            kind: .deletion,
                                            author: author
                                        ),
                                    range: ordinaryRange
                                )
                            }

                        } else if hasInsertions {
                            // With insertion text removed and no deletion
                            // run between the ordinary pieces, the original
                            // selected text collapses into one contiguous
                            // deletion range.
                            let ordinaryLength =
                                analysis
                                    .ordinaryRanges
                                    .reduce(0) {
                                        $0 + $1.length
                                    }

                            let deletionRange =
                                NSRange(
                                    location:
                                        range.location,
                                    length:
                                        ordinaryLength
                                )

                            if deletionRange.length > 0 {
                                storage.addAttribute(
                                    .boldWriterTrackChange,
                                    value:
                                        sharedDeletionMarker,
                                    range:
                                        deletionRange
                                )
                            }

                        } else if hasDeletions {
                            // Preserve the previous ordinary+deletion
                            // behavior: all newly deleted ordinary ranges
                            // share one revision marker while existing
                            // deletion records remain untouched.
                            for ordinaryRange
                                in analysis
                                    .ordinaryRanges {

                                storage.addAttribute(
                                    .boldWriterTrackChange,
                                    value:
                                        sharedDeletionMarker,
                                    range:
                                        ordinaryRange
                                )
                            }
                        }
                    }

                    if replacement.length > 0 {
                        let inserted =
                            NSMutableAttributedString(
                                attributedString:
                                    replacement
                            )

                        inserted.addAttribute(
                            .boldWriterTrackChange,
                            value:
                                insertionMarker,
                            range:
                                NSRange(
                                    location: 0,
                                    length:
                                        inserted.length
                                )
                        )

                        storage.insert(
                            inserted,
                            at: insertionPoint
                        )

                        view.setSelectedRange(
                            NSRange(
                                location:
                                    insertionPoint
                                    + inserted.length,
                                length: 0
                            )
                        )
                    } else {
                        let caretLocation:
                            Int

                        if hasInsertions
                            && hasDeletions
                            && !hasOrdinary {

                            // Preserve the previous insertion+deletion
                            // no-replacement caret behavior.
                            caretLocation =
                                insertionPoint
                        } else {
                            caretLocation =
                                range.location
                        }

                        view.setSelectedRange(
                            NSRange(
                                location:
                                    min(
                                        caretLocation,
                                        storage.length
                                    ),
                                length: 0
                            )
                        )
                    }
                }

                refreshTrackChangeDisplay()
                return true
            }
        }

        // Text already marked as deleted is logically absent from
        // the final document. Do not stack another deletion revision
        // on top of it.
        //
        // Replacing text inside one existing deletion preserves the
        // original deletion and inserts the replacement immediately
        // after the complete deleted run.
        if range.length > 0,
           let existingDeletionRange =
                deletionRangeCovering(
                    range,
                    in: storage
                ) {

            performUndoableMutation(
                actionName
            ) { view in
                guard
                    let storage = view.textStorage
                else {
                    return
                }

                let insertionPoint =
                    NSMaxRange(
                        existingDeletionRange
                    )

                if replacement.length > 0 {
                    let inserted =
                        NSMutableAttributedString(
                            attributedString:
                                replacement
                        )

                    inserted.addAttribute(
                        .boldWriterTrackChange,
                        value:
                            TrackChanges.marker(
                                kind: .insertion,
                                author: author
                            ),
                        range: NSRange(
                            location: 0,
                            length: inserted.length
                        )
                    )

                    storage.insert(
                        inserted,
                        at: insertionPoint
                    )

                    view.setSelectedRange(
                        NSRange(
                            location:
                                insertionPoint
                                + inserted.length,
                            length: 0
                        )
                    )
                } else {
                    view.setSelectedRange(
                        NSRange(
                            location:
                                min(
                                    insertionPoint,
                                    storage.length
                                ),
                            length: 0
                        )
                    )
                }
            }

            refreshTrackChangeDisplay()
            return true
        }

        // Typing with the caret inside deleted text must not split
        // one deletion marker into multiple attributed runs.
        // Redirect the insertion to the end of the deleted run.
        if range.length == 0,
           replacement.length > 0,
           let existingDeletionRange =
                deletionRangeContainingCaret(
                    range.location,
                    in: storage
                ) {

            let insertionPoint =
                NSMaxRange(
                    existingDeletionRange
                )

            let insertionMarker:
                [String: String]

            if let existing =
                insertionMarkerAdjacent(
                    to: insertionPoint,
                    in: storage,
                    author: author
                ) {
                insertionMarker = existing
            } else {
                insertionMarker =
                    TrackChanges.marker(
                        kind: .insertion,
                        author: author
                    )
            }

            performUndoableMutation(
                actionName
            ) { view in
                guard
                    let storage = view.textStorage
                else {
                    return
                }

                let inserted =
                    NSMutableAttributedString(
                        attributedString:
                            replacement
                    )

                inserted.addAttribute(
                    .boldWriterTrackChange,
                    value: insertionMarker,
                    range: NSRange(
                        location: 0,
                        length: inserted.length
                    )
                )

                storage.insert(
                    inserted,
                    at: insertionPoint
                )

                view.setSelectedRange(
                    NSRange(
                        location:
                            insertionPoint
                            + inserted.length,
                        length: 0
                    )
                )
            }

            refreshTrackChangeDisplay()
            return true
        }

        let deletionMarker =
            TrackChanges.marker(
                kind: .deletion,
                author: author
            )

        // Continuous typing beside an insertion by the same author
        // reuses the existing marker. This makes "hello" one tracked
        // insertion instead of five unrelated one-character changes.
        let insertionMarker:
            [String: String]

        if range.length == 0,
           let existing =
                insertionMarkerAdjacent(
                    to: range.location,
                    in: storage,
                    author: author
                ) {
            insertionMarker = existing
        } else {
            insertionMarker =
                TrackChanges.marker(
                    kind: .insertion,
                    author: author
                )
        }

        performUndoableMutation(
            actionName
        ) { view in
            guard
                let storage = view.textStorage
            else {
                return
            }

            // A replacement is represented like Word:
            // original text remains as a deletion, while the
            // replacement follows it as an insertion.
            if range.length > 0 {
                storage.addAttribute(
                    .boldWriterTrackChange,
                    value: deletionMarker,
                    range: range
                )
            }

            if replacement.length > 0 {
                let inserted =
                    NSMutableAttributedString(
                        attributedString:
                            replacement
                    )

                inserted.addAttribute(
                    .boldWriterTrackChange,
                    value: insertionMarker,
                    range: NSRange(
                        location: 0,
                        length: inserted.length
                    )
                )

                let insertionPoint =
                    range.length > 0
                        ? NSMaxRange(range)
                        : range.location

                storage.insert(
                    inserted,
                    at: insertionPoint
                )

                view.setSelectedRange(
                    NSRange(
                        location:
                            insertionPoint
                            + inserted.length,
                        length: 0
                    )
                )
            } else {
                view.setSelectedRange(
                    NSRange(
                        location: range.location,
                        length: 0
                    )
                )
            }
        }

        refreshTrackChangeDisplay()
        return true
    }

    private func revisionSelectionAnalysis(
        in selection: NSRange,
        text: NSAttributedString,
        author: String
    ) -> (
        ordinaryRanges: [NSRange],
        insertionRanges: [NSRange],
        deletionRanges: [NSRange],
        containsUnsupportedRevision: Bool
    )? {
        guard
            selection.length > 0,
            selection.location >= 0,
            selection.location < text.length,
            selection.length
                <= text.length - selection.location
        else {
            return nil
        }

        var ordinaryRanges: [NSRange] = []
        var insertionRanges: [NSRange] = []
        var deletionRanges: [NSRange] = []
        var containsUnsupportedRevision = false

        text.enumerateAttribute(
            .boldWriterTrackChange,
            in: selection,
            options: [.longestEffectiveRangeNotRequired]
        ) { value, effectiveRange, _ in

            let intersection =
                NSIntersectionRange(
                    effectiveRange,
                    selection
                )

            guard intersection.length > 0 else {
                return
            }

            guard let value else {
                ordinaryRanges.append(
                    intersection
                )
                return
            }

            guard
                let marker =
                    value as? [String: String],
                let record =
                    TrackChanges.record(
                        from: marker,
                        range: effectiveRange
                    )
            else {
                containsUnsupportedRevision = true
                return
            }

            switch record.kind {
            case .insertion:
                guard record.author == author else {
                    containsUnsupportedRevision = true
                    return
                }

                insertionRanges.append(
                    intersection
                )

            case .deletion:
                deletionRanges.append(
                    intersection
                )
            }
        }

        ordinaryRanges.sort {
            $0.location < $1.location
        }

        insertionRanges.sort {
            $0.location < $1.location
        }

        deletionRanges.sort {
            $0.location < $1.location
        }

        return (
            ordinaryRanges: ordinaryRanges,
            insertionRanges: insertionRanges,
            deletionRanges: deletionRanges,
            containsUnsupportedRevision:
                containsUnsupportedRevision
        )
    }

    private func deletionRangeCovering(
        _ range: NSRange,
        in text: NSAttributedString
    ) -> NSRange? {
        guard
            range.length > 0,
            range.location < text.length
        else {
            return nil
        }

        var effectiveRange =
            NSRange(
                location: 0,
                length: 0
            )

        let value =
            text.attribute(
                .boldWriterTrackChange,
                at: range.location,
                effectiveRange: &effectiveRange
            )

        guard
            let marker =
                value as? [String: String],
            let record =
                TrackChanges.record(
                    from: marker,
                    range: effectiveRange
                ),
            record.kind == .deletion,
            effectiveRange.location
                <= range.location,
            NSMaxRange(effectiveRange)
                >= NSMaxRange(range)
        else {
            return nil
        }

        return effectiveRange
    }

    private func deletionRangeContainingCaret(
        _ location: Int,
        in text: NSAttributedString
    ) -> NSRange? {
        guard
            text.length > 0,
            location > 0,
            location < text.length
        else {
            return nil
        }

        var effectiveRange =
            NSRange(
                location: 0,
                length: 0
            )

        let value =
            text.attribute(
                .boldWriterTrackChange,
                at: location,
                effectiveRange: &effectiveRange
            )

        guard
            let marker =
                value as? [String: String],
            let record =
                TrackChanges.record(
                    from: marker,
                    range: effectiveRange
                ),
            record.kind == .deletion,
            location > effectiveRange.location,
            location < NSMaxRange(effectiveRange)
        else {
            return nil
        }

        return effectiveRange
    }

    private func insertionMarkerCovering(
        _ range: NSRange,
        in text: NSAttributedString,
        author: String
    ) -> [String: String]? {
        guard
            range.length > 0,
            range.location < text.length
        else {
            return nil
        }

        var effectiveRange =
            NSRange(
                location: 0,
                length: 0
            )

        let value =
            text.attribute(
                .boldWriterTrackChange,
                at: range.location,
                effectiveRange: &effectiveRange
            )

        guard
            let marker = value as? [String: String],
            let record =
                TrackChanges.record(
                    from: marker,
                    range: effectiveRange
                ),
            record.kind == .insertion,
            record.author == author,
            effectiveRange.location
                <= range.location,
            NSMaxRange(effectiveRange)
                >= NSMaxRange(range)
        else {
            return nil
        }

        return marker
    }

    private func insertionMarkerAdjacent(
        to location: Int,
        in text: NSAttributedString,
        author: String
    ) -> [String: String]? {
        guard text.length > 0 else {
            return nil
        }

        func marker(
            at index: Int,
            requiring boundary:
                (NSRange) -> Bool
        ) -> [String: String]? {
            guard
                index >= 0,
                index < text.length
            else {
                return nil
            }

            var effectiveRange =
                NSRange(
                    location: 0,
                    length: 0
                )

            let value =
                text.attribute(
                    .boldWriterTrackChange,
                    at: index,
                    effectiveRange: &effectiveRange
                )

            guard
                let dictionary =
                    value as? [String: String],
                let record =
                    TrackChanges.record(
                        from: dictionary,
                        range: effectiveRange
                    ),
                record.kind == .insertion,
                record.author == author,
                boundary(effectiveRange)
            else {
                return nil
            }

            return dictionary
        }

        // Normal continuous typing occurs at the end of the
        // insertion, so prefer the marker immediately to the left.
        if location > 0,
           let left =
                marker(
                    at: location - 1,
                    requiring: {
                        NSMaxRange($0)
                            == location
                    }
                ) {
            return left
        }

        // Also support typing at the beginning of an existing
        // insertion, such as after moving the caret manually.
        if location < text.length,
           let right =
                marker(
                    at: location,
                    requiring: {
                        $0.location
                            == location
                    }
                ) {
            return right
        }

        return nil
    }

    func acceptTrackedChangeAtSelection() {
        resolveTrackedChange(
            accept: true
        )
    }

    func rejectTrackedChangeAtSelection() {
        resolveTrackedChange(
            accept: false
        )
    }

    func acceptAllTrackedChanges() {
        resolveAllTrackedChanges(
            accept: true
        )
    }

    func rejectAllTrackedChanges() {
        resolveAllTrackedChanges(
            accept: false
        )
    }

    func selectTrackedChange(
        _ item: TrackChanges.ReviewItem
    ) {
        navigate(
            to: item.range
        )

        selectedReviewChangeID =
            item.id
    }

    @discardableResult
    func nextTrackedChange() -> Bool {
        navigateTrackedChange(
            direction: 1
        )
    }

    @discardableResult
    func previousTrackedChange() -> Bool {
        navigateTrackedChange(
            direction: -1
        )
    }

    private func reviewItemContainsSelection(
        _ item: TrackChanges.ReviewItem,
        selection: NSRange
    ) -> Bool {
        if selection.length > 0 {
            return
                NSIntersectionRange(
                    selection,
                    item.range
                )
                .length > 0
        }

        return
            selection.location
                >= item.range.location
            && selection.location
                <= NSMaxRange(
                    item.range
                )
    }

    @discardableResult
    private func navigateTrackedChange(
        direction: Int
    ) -> Bool {
        guard
            let view = textView,
            let storage =
                view.textStorage
        else {
            return false
        }

        let items =
            TrackChanges.reviewItems(
                in: storage
            )

        guard !items.isEmpty else {
            selectedReviewChangeID =
                nil
            NSSound.beep()
            return false
        }

        let selection =
            view.selectedRange()

        var target:
            TrackChanges.ReviewItem?

        if let selectedID =
            selectedReviewChangeID,
           let index =
            items.firstIndex(
                where: {
                    $0.id
                        == selectedID
                }
           ),
           reviewItemContainsSelection(
                items[index],
                selection:
                    selection
           ) {

            let candidate =
                direction >= 0
                ? index + 1
                : index - 1

            if items.indices
                .contains(candidate) {
                target =
                    items[candidate]
            }
        } else if direction >= 0 {
            let anchor =
                selection.length > 0
                ? NSMaxRange(
                    selection
                )
                : selection.location

            target =
                items.first {
                    $0.range.location
                        >= anchor
                }
        } else {
            let anchor =
                selection.location

            target =
                items.reversed()
                    .first {
                        NSMaxRange(
                            $0.range
                        )
                        <= anchor
                    }
        }

        guard let target else {
            NSSound.beep()
            return false
        }

        navigate(
            to: target.range
        )

        selectedReviewChangeID =
            target.id

        return true
    }

    private func advanceAfterReviewResolution(
        from anchor: Int
    ) {
        guard
            let view = textView,
            let storage =
                view.textStorage
        else {
            selectedReviewChangeID =
                nil
            return
        }

        let remaining =
            TrackChanges.reviewItems(
                in: storage
            )

        guard !remaining.isEmpty else {
            selectedReviewChangeID =
                nil
            updateSelection(
                view.selectedRange()
            )
            return
        }

        let safeAnchor =
            min(
                max(0, anchor),
                storage.length
            )

        let target =
            remaining.first {
                $0.range.location
                    >= safeAnchor
            }
            ?? remaining.last!

        navigate(
            to: target.range
        )

        selectedReviewChangeID =
            target.id
    }

    func refreshTrackChangeDisplay() {
        guard
            let view = textView,
            let storage = view.textStorage,
            let manager = view.layoutManager
        else {
            return
        }

        let full = NSRange(
            location: 0,
            length: storage.length
        )

        guard full.length > 0 else { return }

        manager.removeTemporaryAttribute(
            .backgroundColor,
            forCharacterRange: full
        )

        manager.removeTemporaryAttribute(
            .underlineStyle,
            forCharacterRange: full
        )

        manager.removeTemporaryAttribute(
            .strikethroughStyle,
            forCharacterRange: full
        )

        if let notes =
            try? Footnotes.records(
                in: storage
            ) {
            for note in notes
                where
                    note.hasPendingBodyChange {
                let range =
                    NSRange(
                        location:
                            note.location,
                        length:
                            note.length
                    )

                manager
                    .addTemporaryAttribute(
                        .backgroundColor,
                        value:
                            NSColor.systemBlue
                                .withAlphaComponent(
                                    0.12
                                ),
                        forCharacterRange:
                            range
                    )

                manager
                    .addTemporaryAttribute(
                        .underlineStyle,
                        value:
                            NSUnderlineStyle
                                .single
                                .rawValue,
                        forCharacterRange:
                            range
                    )
            }
        }

        if let notes =
            try? Endnotes.records(
                in: storage
            ) {
            for note in notes
                where
                    note.hasPendingBodyChange {
                let range =
                    NSRange(
                        location:
                            note.location,
                        length:
                            note.length
                    )

                manager
                    .addTemporaryAttribute(
                        .backgroundColor,
                        value:
                            NSColor.systemBlue
                                .withAlphaComponent(
                                    0.12
                                ),
                        forCharacterRange:
                            range
                    )

                manager
                    .addTemporaryAttribute(
                        .underlineStyle,
                        value:
                            NSUnderlineStyle
                                .single
                                .rawValue,
                        forCharacterRange:
                            range
                    )
            }
        }

        storage.enumerateAttribute(
            .boldWriterTrackChange,
            in: full
        ) { value, range, _ in
            guard
                let record = TrackChanges.record(
                    from: value,
                    range: range
                )
            else {
                return
            }

            switch record.kind {
            case .insertion:
                manager.addTemporaryAttribute(
                    .backgroundColor,
                    value: NSColor.systemGreen
                        .withAlphaComponent(0.14),
                    forCharacterRange: range
                )

                manager.addTemporaryAttribute(
                    .underlineStyle,
                    value: NSUnderlineStyle.single.rawValue,
                    forCharacterRange: range
                )

            case .deletion:
                manager.addTemporaryAttribute(
                    .backgroundColor,
                    value: NSColor.systemRed
                        .withAlphaComponent(0.12),
                    forCharacterRange: range
                )

                manager.addTemporaryAttribute(
                    .strikethroughStyle,
                    value: NSUnderlineStyle.single.rawValue,
                    forCharacterRange: range
                )
            }
        }
    }

    private func resolveFootnoteBodyChange(
        _ note: Footnote,
        accept: Bool,
        in storage:
            NSMutableAttributedString
    ) {
        guard
            note.location >= 0,
            note.length > 0,
            note.location
                <= storage.length,
            note.length
                <= storage.length
                    - note.location
        else {
            return
        }

        var resolved = note

        if !accept,
           let original =
            note.bodyChangeOriginalText {
            resolved.text =
                original
        }

        resolved.bodyChangeOriginalText =
            nil
        resolved.bodyChangeID =
            nil
        resolved.bodyChangeAuthor =
            nil
        resolved.bodyChangeDate =
            nil

        storage.addAttribute(
            .footnote,
            value:
                Footnotes.payload(
                    resolved
                ),
            range:
                NSRange(
                    location:
                        resolved.location,
                    length:
                        resolved.length
                )
        )
    }

    private func resolveEndnoteBodyChange(
        _ note: Endnote,
        accept: Bool,
        in storage:
            NSMutableAttributedString
    ) {
        guard
            note.location >= 0,
            note.length > 0,
            note.location
                <= storage.length,
            note.length
                <= storage.length
                    - note.location
        else {
            return
        }

        var resolved = note

        if !accept,
           let original =
            note.bodyChangeOriginalText {
            resolved.text =
                original
        }

        resolved.bodyChangeOriginalText =
            nil
        resolved.bodyChangeID =
            nil
        resolved.bodyChangeAuthor =
            nil
        resolved.bodyChangeDate =
            nil

        storage.addAttribute(
            .endnote,
            value:
                Endnotes.payload(
                    resolved
                ),
            range:
                NSRange(
                    location:
                        resolved.location,
                    length:
                        resolved.length
                )
        )
    }

    private func selectedReviewItem(
        in text: NSAttributedString,
        selection: NSRange
    ) -> TrackChanges.ReviewItem? {
        let items =
            TrackChanges.reviewItems(
                in: text
            )

        if let selectedID =
            selectedReviewChangeID,
           let item =
            items.first(
                where: {
                    $0.id
                        == selectedID
                }
           ),
           reviewItemContainsSelection(
                item,
                selection:
                    selection
           ) {
            return item
        }

        return items.first {
            reviewItemContainsSelection(
                $0,
                selection:
                    selection
            )
        }
    }

    @discardableResult
    private func resolveReviewItem(
        _ item: TrackChanges.ReviewItem,
        accept: Bool,
        in storage:
            NSMutableAttributedString,
        view: NSTextView
    ) -> Bool {
        switch item.kind {
        case .formatting:
            let paired =
                TrackChanges.records(
                    in:
                        storage
                )
                .filter {
                    $0.id
                        == item.id
                }

            guard
                let deletion =
                    paired.first(
                        where: {
                            $0.kind
                                == .deletion
                        }
                    ),
                let insertion =
                    paired.first(
                        where: {
                            $0.kind
                                == .insertion
                        }
                    )
            else {
                return false
            }

            let deletionRange =
                NSRange(
                    location:
                        deletion.location,
                    length:
                        deletion.length
                )

            let insertionRange =
                NSRange(
                    location:
                        insertion.location,
                    length:
                        insertion.length
                )

            guard
                deletionRange.location >= 0,
                deletionRange.length > 0,
                insertionRange.location >= 0,
                insertionRange.length > 0,
                NSMaxRange(
                    deletionRange
                )
                    == insertionRange.location,
                insertionRange.location
                    <= storage.length,
                insertionRange.length
                    <= storage.length
                        - insertionRange.location
            else {
                return false
            }

            if accept {
                storage.deleteCharacters(
                    in:
                        deletionRange
                )

                let kept =
                    NSRange(
                        location:
                            deletionRange
                                .location,
                        length:
                            insertionRange
                                .length
                    )

                guard
                    kept.location
                        <= storage.length,
                    kept.length
                        <= storage.length
                            - kept.location
                else {
                    return false
                }

                storage.removeAttribute(
                    .boldWriterTrackChange,
                    range:
                        kept
                )
            } else {
                storage.deleteCharacters(
                    in:
                        insertionRange
                )

                guard
                    deletionRange.location
                        <= storage.length,
                    deletionRange.length
                        <= storage.length
                            - deletionRange.location
                else {
                    return false
                }

                storage.removeAttribute(
                    .boldWriterTrackChange,
                    range:
                        deletionRange
                )
            }

            view.setSelectedRange(
                NSRange(
                    location:
                        min(
                            deletionRange
                                .location,
                            storage.length
                        ),
                    length: 0
                )
            )

            return true

        case .footnoteBodyEdit:
            guard
                let notes =
                    try? Footnotes.records(
                        in: storage
                    ),
                let note =
                    notes.first(
                        where: {
                            $0
                                .hasPendingBodyChange
                            && (
                                $0.bodyChangeID
                                ?? $0.id
                            ) == item.id
                        }
                    )
            else {
                return false
            }

            resolveFootnoteBodyChange(
                note,
                accept:
                    accept,
                in:
                    storage
            )

            view.setSelectedRange(
                NSRange(
                    location:
                        min(
                            note.location,
                            storage.length
                        ),
                    length: 0
                )
            )

            return true

        case .endnoteBodyEdit:
            guard
                let notes =
                    try? Endnotes.records(
                        in: storage
                    ),
                let note =
                    notes.first(
                        where: {
                            $0
                                .hasPendingBodyChange
                            && (
                                $0.bodyChangeID
                                ?? $0.id
                            ) == item.id
                        }
                    )
            else {
                return false
            }

            resolveEndnoteBodyChange(
                note,
                accept:
                    accept,
                in:
                    storage
            )

            view.setSelectedRange(
                NSRange(
                    location:
                        min(
                            note.location,
                            storage.length
                        ),
                    length: 0
                )
            )

            return true

        case .insertion,
             .deletion:
            guard
                let record =
                    TrackChanges.records(
                        in: storage
                    )
                    .first(
                        where: {
                            $0.id
                                == item.id
                        }
                    )
            else {
                return false
            }

            let range =
                NSRange(
                    location:
                        record.location,
                    length:
                        record.length
                )

            guard
                range.location >= 0,
                range.length > 0,
                range.location
                    <= storage.length,
                range.length
                    <= storage.length
                        - range.location
            else {
                return false
            }

            let shouldDelete =
                accept
                ? record.kind
                    == .deletion
                : record.kind
                    == .insertion

            if shouldDelete {
                storage.deleteCharacters(
                    in: range
                )
            } else {
                storage.removeAttribute(
                    .boldWriterTrackChange,
                    range: range
                )
            }

            view.setSelectedRange(
                NSRange(
                    location:
                        min(
                            range.location,
                            storage.length
                        ),
                    length: 0
                )
            )

            return true
        }
    }

    private func resolveTrackedChange(
        accept: Bool
    ) {
        guard
            let view = textView,
            let storage =
                view.textStorage,
            let item =
                selectedReviewItem(
                    in: storage,
                    selection:
                        view.selectedRange()
                )
        else {
            selectedReviewChangeID =
                nil
            NSSound.beep()
            return
        }

        let anchor =
            item.range.location

        var resolved =
            false

        performUndoableMutation(
            accept
            ? "Accept Change"
            : "Reject Change"
        ) { view in
            guard
                let storage =
                    view.textStorage
            else {
                return
            }

            resolved =
                resolveReviewItem(
                    item,
                    accept:
                        accept,
                    in:
                        storage,
                    view:
                        view
                )
        }

        guard resolved else {
            selectedReviewChangeID =
                nil
            NSSound.beep()
            return
        }

        refreshTrackChangeDisplay()

        advanceAfterReviewResolution(
            from: anchor
        )
    }

    private func resolveAllTrackedChanges(
        accept: Bool
    ) {
        guard
            let view = textView,
            let storage = view.textStorage
        else {
            return
        }

        let records =
            TrackChanges.records(in: storage)

        let footnoteBodyChanges =
            (try? Footnotes.records(
                in: storage
            ))?
            .filter {
                $0.hasPendingBodyChange
            } ?? []

        let endnoteBodyChanges =
            (try? Endnotes.records(
                in: storage
            ))?
            .filter {
                $0.hasPendingBodyChange
            } ?? []

        guard
            !records.isEmpty
                || !footnoteBodyChanges
                    .isEmpty
                || !endnoteBodyChanges
                    .isEmpty
        else {
            return
        }

        performUndoableMutation(
            accept
                ? "Accept All Changes"
                : "Reject All Changes"
        ) { view in
            guard let storage = view.textStorage else {
                return
            }

            for note
                in footnoteBodyChanges {
                resolveFootnoteBodyChange(
                    note,
                    accept: accept,
                    in: storage
                )
            }

            for note
                in endnoteBodyChanges {
                resolveEndnoteBodyChange(
                    note,
                    accept: accept,
                    in: storage
                )
            }

            for record in records.reversed() {
                let range = NSRange(
                    location: record.location,
                    length: record.length
                )

                guard
                    range.location <= storage.length,
                    range.length
                        <= storage.length - range.location
                else {
                    continue
                }

                let shouldDelete =
                    accept
                        ? record.kind == .deletion
                        : record.kind == .insertion

                if shouldDelete {
                    storage.deleteCharacters(
                        in: range
                    )
                } else {
                    storage.removeAttribute(
                        .boldWriterTrackChange,
                        range: range
                    )
                }
            }

            view.setSelectedRange(
                NSRange(
                    location: min(
                        view.selectedRange().location,
                        storage.length
                    ),
                    length: 0
                )
            )
        }

        selectedReviewChangeID =
            nil
        refreshTrackChangeDisplay()
    }

}
