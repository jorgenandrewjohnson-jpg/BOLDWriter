import AppKit
import Foundation

extension NSAttributedString.Key {
    static let boldWriterTrackChange =
        NSAttributedString.Key("com.boldwriter.trackChange")
}

struct TrackChangeRecord: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case insertion
        case deletion
    }

    var id = UUID()
    var kind: Kind
    var author = NSFullUserName()
    var date = Date()
    var location: Int
    var length: Int
}

enum TrackChanges {
    struct ReviewItem:
        Identifiable,
        Equatable {

        enum Kind:
            String,
            Equatable {
            case insertion
            case deletion
            case formatting
            case footnoteBodyEdit
            case endnoteBodyEdit
        }

        var id: UUID
        var kind: Kind
        var title: String
        var author: String
        var date: Date
        var range: NSRange
        var preview: String
    }

    static func reviewItems(
        in text: NSAttributedString
    ) -> [ReviewItem] {
        let notes =
            (
                try? Footnotes.records(
                    in: text
                )
            ) ?? []

        let endnotes =
            (
                try? Endnotes.records(
                    in: text
                )
            ) ?? []

        let tableCells =
            (
                try? Tables.records(
                    in: text
                )
            ) ?? []

        func clippedPreview(
            _ value: String,
            limit: Int = 90
        ) -> String {
            let normalized =
                value
                    .replacingOccurrences(
                        of: "\u{000C}",
                        with: "Page break"
                    )
                    .replacingOccurrences(
                        of: "\r",
                        with: " "
                    )
                    .replacingOccurrences(
                        of: "\n",
                        with: " ↵ "
                    )
                    .replacingOccurrences(
                        of: "\t",
                        with: " ⇥ "
                    )
                    .trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    )

            guard
                normalized.count
                    > limit
            else {
                return
                    normalized.isEmpty
                    ? "No text preview"
                    : normalized
            }

            let end =
                normalized.index(
                    normalized.startIndex,
                    offsetBy:
                        limit
                )

            return
                String(
                    normalized[..<end]
                )
                + "…"
        }

        func valid(
            _ range: NSRange
        ) -> Bool {
            range.location >= 0
                && range.length > 0
                && range.location
                    <= text.length
                && range.length
                    <= text.length
                        - range.location
        }

        func overlaps(
            _ lhs: NSRange,
            _ rhs: NSRange
        ) -> Bool {
            NSIntersectionRange(
                lhs,
                rhs
            )
            .length > 0
        }

        let ns =
            text.string
                as NSString

        var items:
            [ReviewItem] = []

        let allRecords =
            records(
                in:
                    text
            )

        var formattingIDs:
            Set<UUID> = []

        for deletion
            in allRecords
            where deletion.kind
                == .deletion {

            guard
                !formattingIDs
                    .contains(
                        deletion.id
                    ),
                let insertion =
                    allRecords.first(
                        where: {
                            $0.id
                                == deletion.id
                            && $0.kind
                                == .insertion
                        }
                    )
            else {
                continue
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
                valid(
                    deletionRange
                ),
                valid(
                    insertionRange
                ),
                deletionRange.length
                    == insertionRange.length,
                NSMaxRange(
                    deletionRange
                )
                    == insertionRange.location
            else {
                continue
            }

            let original =
                ns.substring(
                    with:
                        deletionRange
                )

            let proposed =
                ns.substring(
                    with:
                        insertionRange
                )

            guard
                original == proposed
            else {
                continue
            }

            formattingIDs.insert(
                deletion.id
            )

            items.append(
                ReviewItem(
                    id:
                        deletion.id,
                    kind:
                        .formatting,
                    title:
                        "Formatting change",
                    author:
                        deletion.author,
                    date:
                        deletion.date,
                    range:
                        NSRange(
                            location:
                                deletionRange
                                    .location,
                            length:
                                deletionRange
                                    .length
                                + insertionRange
                                    .length
                        ),
                    preview:
                        clippedPreview(
                            original
                        )
                )
            )
        }

        for record
            in allRecords
            where
                !formattingIDs
                    .contains(
                        record.id
                    ) {

            let range =
                NSRange(
                    location:
                        record.location,
                    length:
                        record.length
                )

            guard valid(range) else {
                continue
            }

            let raw =
                ns.substring(
                    with: range
                )

            let note =
                notes.first {
                    overlaps(
                        range,
                        NSRange(
                            location:
                                $0.location,
                            length:
                                $0.length
                        )
                    )
                }

            let inTable =
                tableCells.contains {
                    overlaps(
                        range,
                        NSRange(
                            location:
                                $0.location,
                            length:
                                $0.length
                        )
                    )
                }

            let pageBreak =
                raw.contains(
                    "\u{000C}"
                )

            var containsAttachment =
                false

            text.enumerateAttribute(
                .attachment,
                in:
                    range
            ) {
                value,
                _,
                stop in

                if value != nil {
                    containsAttachment =
                        true

                    stop.pointee =
                        true
                }
            }

            let title:
                String

            if pageBreak {
                title =
                    record.kind
                        == .insertion
                    ? "Inserted page break"
                    : "Deleted page break"
            } else if containsAttachment {
                title =
                    record.kind
                        == .insertion
                    ? "Inserted image"
                    : "Deleted image"
            } else if note != nil {
                title =
                    record.kind
                        == .insertion
                    ? "Inserted footnote"
                    : "Deleted footnote"
            } else if inTable {
                title =
                    record.kind
                        == .insertion
                    ? "Inserted table text"
                    : "Deleted table text"
            } else {
                title =
                    record.kind
                        == .insertion
                    ? "Inserted text"
                    : "Deleted text"
            }

            let preview:
                String

            if let note {
                preview =
                    clippedPreview(
                        note.text
                    )
            } else if pageBreak {
                preview =
                    "Page break"
            } else if containsAttachment {
                let imagePreview =
                    raw.replacingOccurrences(
                        of:
                            "\u{FFFC}",
                        with:
                            "Image"
                    )

                preview =
                    clippedPreview(
                        imagePreview
                    )
            } else {
                preview =
                    clippedPreview(
                        raw
                    )
            }

            items.append(
                ReviewItem(
                    id:
                        record.id,
                    kind:
                        record.kind
                            == .insertion
                        ? .insertion
                        : .deletion,
                    title:
                        title,
                    author:
                        record.author,
                    date:
                        record.date,
                    range:
                        range,
                    preview:
                        preview
                )
            )
        }

        for note
            in notes
            where
                note.hasPendingBodyChange {

            let original =
                note
                    .bodyChangeOriginalText
                ?? ""

            let preview =
                clippedPreview(
                    original
                )
                + " → "
                + clippedPreview(
                    note.text
                )

            items.append(
                ReviewItem(
                    id:
                        note.bodyChangeID
                        ?? note.id,
                    kind:
                        .footnoteBodyEdit,
                    title:
                        "Edited footnote",
                    author:
                        note
                            .bodyChangeAuthor
                        ?? "Unknown",
                    date:
                        note
                            .bodyChangeDate
                        ?? Date(
                            timeIntervalSince1970:
                                0
                        ),
                    range:
                        NSRange(
                            location:
                                note.location,
                            length:
                                note.length
                        ),
                    preview:
                        preview
                )
            )
        }

        for note
            in endnotes
            where
                note.hasPendingBodyChange {

            let original =
                note
                    .bodyChangeOriginalText
                ?? ""

            let preview =
                clippedPreview(
                    original
                )
                + " → "
                + clippedPreview(
                    note.text
                )

            items.append(
                ReviewItem(
                    id:
                        note.bodyChangeID
                        ?? note.id,
                    kind:
                        .endnoteBodyEdit,
                    title:
                        "Edited endnote",
                    author:
                        note
                            .bodyChangeAuthor
                        ?? "Unknown",
                    date:
                        note
                            .bodyChangeDate
                        ?? Date(
                            timeIntervalSince1970:
                                0
                        ),
                    range:
                        NSRange(
                            location:
                                note.location,
                            length:
                                note.length
                        ),
                    preview:
                        preview
                )
            )
        }

        return items.sorted {
            if $0.range.location
                == $1.range.location {

                if $0.range.length
                    == $1.range.length {
                    return
                        $0.title
                        < $1.title
                }

                return
                    $0.range.length
                    < $1.range.length
            }

            return
                $0.range.location
                < $1.range.location
        }
    }

    static func marker(
        id: UUID = UUID(),
        kind: TrackChangeRecord.Kind,
        author: String = NSFullUserName(),
        date: Date = Date()
    ) -> [String: String] {
        [
            "id": id.uuidString,
            "kind": kind.rawValue,
            "author": author,
            "date": String(date.timeIntervalSince1970)
        ]
    }

    static func record(
        from value: Any?,
        range: NSRange
    ) -> TrackChangeRecord? {
        guard
            let dictionary = value as? [String: String],
            let rawID = dictionary["id"],
            let id = UUID(uuidString: rawID),
            let rawKind = dictionary["kind"],
            let kind = TrackChangeRecord.Kind(rawValue: rawKind)
        else {
            return nil
        }

        let author = dictionary["author"] ?? "Unknown"
        let interval =
            Double(dictionary["date"] ?? "") ?? 0

        return TrackChangeRecord(
            id: id,
            kind: kind,
            author: author,
            date: Date(timeIntervalSince1970: interval),
            location: range.location,
            length: range.length
        )
    }

    static func records(
        in text: NSAttributedString
    ) -> [TrackChangeRecord] {
        guard text.length > 0 else { return [] }

        var result: [TrackChangeRecord] = []

        text.enumerateAttribute(
            .boldWriterTrackChange,
            in: NSRange(location: 0, length: text.length)
        ) { value, range, _ in
            if let record = record(
                from: value,
                range: range
            ) {
                result.append(record)
            }
        }

        return result.sorted {
            if $0.location == $1.location {
                return $0.length < $1.length
            }
            return $0.location < $1.location
        }
    }

    static func restore(
        _ records: [TrackChangeRecord],
        into text: NSMutableAttributedString
    ) {
        let full = NSRange(
            location: 0,
            length: text.length
        )

        if full.length > 0 {
            text.removeAttribute(
                .boldWriterTrackChange,
                range: full
            )
        }

        for record in records {
            guard
                record.location >= 0,
                record.length > 0,
                record.location <= text.length,
                record.length <= text.length - record.location
            else {
                continue
            }

            text.addAttribute(
                .boldWriterTrackChange,
                value: marker(
                    id: record.id,
                    kind: record.kind,
                    author: record.author,
                    date: record.date
                ),
                range: NSRange(
                    location: record.location,
                    length: record.length
                )
            )
        }
    }

    static func count(
        _ kind: TrackChangeRecord.Kind,
        in text: NSAttributedString
    ) -> Int {
        records(in: text).filter {
            $0.kind == kind
        }.count
    }
}
