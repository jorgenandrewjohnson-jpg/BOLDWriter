import AppKit

extension NSAttributedString.Key {
    static let footnote = NSAttributedString.Key("com.boldwriter.footnote")
}

/// Immutable reference payloads travel with text edits and the editor's undo snapshots.
struct Footnote: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var text: String
    var location: Int
    var length: Int

    // Optional so older .boldwriter files decode without migration.
    var bodyChangeOriginalText: String? = nil
    var bodyChangeID: UUID? = nil
    var bodyChangeAuthor: String? = nil
    var bodyChangeDate: Date? = nil

    var hasPendingBodyChange: Bool {
        bodyChangeOriginalText != nil
    }
}

enum Footnotes {
    static func records(in text: NSAttributedString) throws -> [Footnote] {
        var notes: [Footnote] = []
        var invalid = false
        var ids = Set<UUID>()
        text.enumerateAttribute(.footnote, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard let value else { return }
            guard let payload = value as? [String: String], let raw = payload["id"],
                  let id = UUID(uuidString: raw), let body = payload["text"],
                  (text.string as NSString).substring(with: range).utf16.allSatisfy({ (48...57).contains($0) }),
                  ids.insert(id).inserted else { invalid = true; return }
            var note =
                Footnote(
                    id: id,
                    text: body,
                    location: range.location,
                    length: range.length
                )

            note.bodyChangeOriginalText =
                payload["bodyChangeOriginalText"]

            if let raw =
                payload["bodyChangeID"] {
                note.bodyChangeID =
                    UUID(uuidString: raw)
            }

            note.bodyChangeAuthor =
                payload["bodyChangeAuthor"]

            if let raw =
                payload["bodyChangeDate"],
               let interval = Double(raw) {
                note.bodyChangeDate =
                    Date(
                        timeIntervalSince1970:
                            interval
                    )
            }

            notes.append(note)
        }
        guard !invalid else { throw WriterError.message("Invalid or duplicated footnote reference. The document was not saved or imported.") }
        return notes
    }

    /// Treat all digits of a reference as one editable unit.
    static func editingRange(_ range: NSRange, in text: NSAttributedString) -> NSRange {
        guard let notes = try? records(in: text) else { return range }
        var result = range
        for note in notes {
            let reference = NSRange(location: note.location, length: note.length)
            if range.length == 0 {
                if range.location > note.location && range.location < NSMaxRange(reference) {
                    return NSRange(location: NSMaxRange(reference), length: 0)
                }
            } else if NSIntersectionRange(result, reference).length > 0 {
                result = NSUnionRange(result, reference)
            }
        }
        return result
    }

    static func payload(
        _ note: Footnote
    ) -> [String: String] {
        var value: [String: String] = [
            "id": note.id.uuidString,
            "text": note.text
        ]

        if let original =
            note.bodyChangeOriginalText {
            value["bodyChangeOriginalText"] =
                original
        }

        if let id = note.bodyChangeID {
            value["bodyChangeID"] =
                id.uuidString
        }

        if let author =
            note.bodyChangeAuthor {
            value["bodyChangeAuthor"] =
                author
        }

        if let date =
            note.bodyChangeDate {
            value["bodyChangeDate"] =
                String(
                    date.timeIntervalSince1970
                )
        }

        return value
    }

    static func marker(
        _ note: Footnote,
        number: Int
    ) -> NSAttributedString {
        NSAttributedString(
            string: String(number),
            attributes: [
                .footnote: payload(note),
                .font:
                    NSFont.systemFont(
                        ofSize: 11
                    ),
                .superscript: 1,
                .foregroundColor:
                    NSColor.textColor
            ]
        )
    }

    static func renumber(_ text: NSMutableAttributedString) throws {
        let notes = try records(in: text)
        for (index, note) in notes.enumerated().reversed() {
            let range = NSRange(location: note.location, length: note.length)
            if (text.string as NSString).substring(with: range) != String(index + 1) {
                var attributes = text.attributes(at: range.location, effectiveRange: nil)
                attributes.merge(marker(note, number: index + 1).attributes(at: 0, effectiveRange: nil)) { _, new in new }
                text.replaceCharacters(in: range, with: NSAttributedString(string: String(index + 1), attributes: attributes))
            }
        }
    }

    static func restore(_ notes: [Footnote], into text: NSMutableAttributedString) throws {
        var ids = Set<UUID>(), end = 0
        for note in notes {
            guard ids.insert(note.id).inserted, note.location >= end, note.length > 0,
                  note.location <= text.length, note.length <= text.length - note.location,
                  (text.string as NSString).substring(with: NSRange(location: note.location, length: note.length)).allSatisfy({ $0.isNumber }) else {
                throw WriterError.message("The document contains malformed footnote data.")
            }
            end = note.location + note.length
        }
        for note in notes {
            text.addAttribute(
                .footnote,
                value: payload(note),
                range:
                    NSRange(
                        location:
                            note.location,
                        length:
                            note.length
                    )
            )
        }
        try renumber(text)
    }

    static func printable(_ text: NSAttributedString) throws -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: text)
        try renumber(result)
        let notes = try records(in: result)
        if !notes.isEmpty {
            result.append(NSAttributedString(string: "\n\nFootnotes\n", attributes: [.font: NSFont.boldSystemFont(ofSize: 14)]))
            for (index, note) in notes.enumerated() {
                result.append(NSAttributedString(string: "\(index + 1). \(note.text)\n", attributes: [.font: NSFont.systemFont(ofSize: 11)]))
            }
        }
        return result
    }
}
