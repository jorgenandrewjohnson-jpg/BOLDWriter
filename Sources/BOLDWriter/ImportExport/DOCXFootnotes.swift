import AppKit

extension DOCXImporter {
    static func prepareFootnotes(
        xml: XMLDocument,
        parts: [String: Data],
        mainPart: String
    ) throws -> [(String, Footnote)] {
        try prepareNotes(
            xml: xml,
            parts: parts,
            mainPart: mainPart,
            kind: .footnote
        ).map { marker, body in
            (
                marker,
                Footnote(
                    id: body.id,
                    text: body.text,
                    location: body.location,
                    length: body.length,
                    bodyChangeOriginalText: body.bodyChangeOriginalText,
                    bodyChangeID: body.bodyChangeID,
                    bodyChangeAuthor: body.bodyChangeAuthor,
                    bodyChangeDate: body.bodyChangeDate
                )
            )
        }
    }
}
