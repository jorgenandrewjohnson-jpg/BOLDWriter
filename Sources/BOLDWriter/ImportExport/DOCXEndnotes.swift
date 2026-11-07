import AppKit

extension DOCXImporter {
    static func prepareEndnotes(
        xml: XMLDocument,
        parts: [String: Data],
        mainPart: String
    ) throws -> [(String, Endnote)] {
        try prepareNotes(
            xml: xml,
            parts: parts,
            mainPart: mainPart,
            kind: .endnote
        ).map { marker, body in
            (
                marker,
                Endnote(
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
