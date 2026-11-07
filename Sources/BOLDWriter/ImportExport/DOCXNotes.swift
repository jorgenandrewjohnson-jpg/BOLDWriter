import AppKit

enum DOCXNoteKind {
    case footnote
    case endnote

    var name: String {
        switch self {
        case .footnote: "footnote"
        case .endnote: "endnote"
        }
    }

    var pluralName: String { name + "s" }
    var referenceName: String { name + "Reference" }
    var bodyReferenceName: String { name + "Ref" }
    var markerPrefix: String { "BOLD" + name.uppercased() }
}

struct DOCXImportedNote {
    var id = UUID()
    var text: String
    var location: Int
    var length: Int
    var bodyChangeOriginalText: String? = nil
    var bodyChangeID: UUID? = nil
    var bodyChangeAuthor: String? = nil
    var bodyChangeDate: Date? = nil
}

extension DOCXImporter {
    static func prepareNotes(
        xml: XMLDocument,
        parts: [String: Data],
        mainPart: String,
        kind: DOCXNoteKind
    ) throws -> [(String, DOCXImportedNote)] {
        let references =
            try xml.nodes(
                forXPath:
                    "//*[local-name()='\(kind.referenceName)']"
            )
            .compactMap {
                $0 as? XMLElement
            }

        guard !references.isEmpty else {
            return []
        }

        func failure() -> WriterError {
            .message(
                "The DOCX contains missing, duplicate, or unsupported \(kind.pluralName). Import was stopped without changing the original file."
            )
        }

        func attr(
            _ element: XMLElement,
            _ name: String
        ) -> String? {
            element.attributes?
                .first {
                    $0.localName == name
                }?
                .stringValue
        }

        func hasAncestor(
            _ node: XMLNode,
            named name: String
        ) -> Bool {
            var parent =
                node.parent

            while let current = parent {
                if current.localName == name {
                    return true
                }

                parent =
                    current.parent
            }

            return false
        }

        func bodyText(
            _ note: XMLElement,
            excludingRevision:
                String?
        ) throws -> String {
            let paragraphs =
                try note.nodes(
                    forXPath:
                        "./*[local-name()='p']"
                )

            return try paragraphs.map {
                paragraph in

                let nodes =
                    try paragraph.nodes(
                        forXPath:
                            ".//*[local-name()='t' or local-name()='delText' or local-name()='tab' or local-name()='br' or local-name()='cr']"
                    )

                return nodes.compactMap {
                    node -> String? in

                    if let excluded =
                        excludingRevision,
                       hasAncestor(
                            node,
                            named: excluded
                       ) {
                        return nil
                    }

                    switch node.localName {
                    case "tab":
                        return "\t"

                    case "br", "cr":
                        return "\n"

                    case "t":
                        if hasAncestor(
                            node,
                            named: "del"
                        ) {
                            return nil
                        }

                        return
                            node.stringValue
                            ?? ""

                    case "delText":
                        if hasAncestor(
                            node,
                            named: "ins"
                        ) {
                            return nil
                        }

                        return
                            node.stringValue
                            ?? ""

                    default:
                        return nil
                    }
                }
                .joined()
            }
            .joined(separator: "\n")
        }

        let directory =
            (mainPart as NSString)
                .deletingLastPathComponent

        let relPath =
            (directory.isEmpty
                ? ""
                : directory + "/")
            + "_rels/"
            + (mainPart as NSString)
                .lastPathComponent
            + ".rels"

        guard
            let relData = parts[relPath]
        else {
            throw failure()
        }

        let rels =
            try DOCXPackage
                .xml(relData)
                .nodes(
                    forXPath:
                        "//*[local-name()='Relationship']"
                )
                .compactMap {
                    $0 as? XMLElement
                }

        let matching =
            rels.filter {
                attr(
                    $0,
                    "Type"
                )?
                .hasSuffix(
                    "/\(kind.pluralName)"
                ) == true
            }

        guard
            matching.count == 1,
            let rel =
                matching.first,
            attr(
                rel,
                "TargetMode"
            ) != "External",
            let target =
                attr(
                    rel,
                    "Target"
                ),
            let path =
                DOCXPackage.target(
                    target,
                    relativeTo:
                        mainPart
                ),
            let data =
                parts[path]
        else {
            throw failure()
        }

        let document =
            try DOCXPackage.xml(data)

        var bodies:
            [String: DOCXImportedNote] = [:]

        for case let note
            as XMLElement
            in try document.nodes(
                forXPath:
                    "/*[local-name()='\(kind.pluralName)']/*[local-name()='\(kind.name)']"
            ) {

            if let type =
                attr(
                    note,
                    "type"
                ),
               type != "normal" {
                continue
            }

            guard
                let id =
                    attr(
                        note,
                        "id"
                    ),
                Int(id) != nil,
                bodies[id] == nil
            else {
                throw failure()
            }

            let allowed:
                Set<String> = [
                    "p",
                    "pPr",
                    "r",
                    "rPr",
                    "t",
                    "delText",
                    "tab",
                    "br",
                    "cr",
                    kind.bodyReferenceName,
                    "hyperlink",
                    "bookmarkStart",
                    "bookmarkEnd",
                    "proofErr",
                    "ins",
                    "del"
                ]

            for node
                in try note.nodes(
                    forXPath: ".//*"
                ) {

                if node.parent?
                    .localName == "pPr"
                    || node.parent?
                        .localName == "rPr" {
                    continue
                }

                var parent =
                    node.parent
                var property =
                    false

                while let p = parent {
                    if [
                        "pPr",
                        "rPr"
                    ]
                    .contains(
                        p.localName
                        ?? ""
                    ) {
                        property = true
                    }

                    parent =
                        p.parent
                }

                if !property
                    && !allowed
                        .contains(
                            node.localName
                            ?? ""
                        ) {
                    throw failure()
                }
            }

            let revisions =
                try note.nodes(
                    forXPath:
                        ".//*[local-name()='ins' or local-name()='del']"
                )
                .compactMap {
                    $0 as? XMLElement
                }

            let proposed =
                try bodyText(
                    note,
                    excludingRevision:
                        "del"
                )

            let original =
                try bodyText(
                    note,
                    excludingRevision:
                        "ins"
                )

            var importedNote =
                DOCXImportedNote(
                    text:
                        proposed,
                    location: 0,
                    length: 1
                )

            if !revisions.isEmpty,
               original != proposed {
                importedNote
                    .bodyChangeOriginalText =
                    original

                importedNote.bodyChangeID =
                    UUID()

                if let revision =
                    revisions.first {
                    importedNote
                        .bodyChangeAuthor =
                        attr(
                            revision,
                            "author"
                        )

                    if let rawDate =
                        attr(
                            revision,
                            "date"
                        ) {
                        importedNote
                            .bodyChangeDate =
                            ISO8601DateFormatter()
                                .date(
                                    from:
                                        rawDate
                                )
                    }
                }
            }

            bodies[id] =
                importedNote
        }

        var seen =
            Set<String>()

        var replacements:
            [(String, DOCXImportedNote)] = []

        for reference
            in references {

            guard
                let id =
                    attr(
                        reference,
                        "id"
                    ),
                var body =
                    bodies[id],
                seen.insert(id)
                    .inserted,
                attr(
                    reference,
                    "customMarkFollows"
                ) == nil,
                let parent =
                    reference.parent
                        as? XMLElement,
                parent.localName == "r"
            else {
                throw failure()
            }

            let marker =
                kind.markerPrefix
                + UUID()
                    .uuidString
                    .replacingOccurrences(
                        of: "-",
                        with: ""
                    )

            let node =
                XMLElement(
                    name: "w:t",
                    stringValue:
                        marker
                )

            node.addNamespace(
                XMLNode.namespace(
                    withName: "w",
                    stringValue:
                        "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
                ) as! XMLNode
            )

            parent.replaceChild(
                at:
                    reference.index,
                with: node
            )

            body.location = 0
            body.length = 1

            replacements.append(
                (
                    marker,
                    body
                )
            )
        }

        return replacements
    }
}
