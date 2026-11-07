import AppKit

extension DOCXImporter {
    struct ImportedSectionBoundary {
        let marker: String
        let page: PageSettings
        let breakType: DocumentSection.BreakType
    }

    struct ImportedSections {
        let firstPage: PageSettings
        let firstBreakType: DocumentSection.BreakType
        let boundaries: [ImportedSectionBoundary]
    }

    private static func importSectionBreakType(
        section: XMLElement
    ) throws -> DocumentSection.BreakType {
        let nodes =
            try section.nodes(
                forXPath:
                    "./*[local-name()='type']"
            )
            .compactMap {
                $0 as? XMLElement
            }

        guard
            nodes.count <= 1
        else {
            throw WriterError.message(
                "A Word section contains multiple section-break types."
            )
        }

        guard
            let node =
                nodes.first
        else {
            return .nextPage
        }

        let value =
            node.attributes?
                .first(
                    where: {
                        $0.localName
                            == "val"
                    }
                )?
                .stringValue

        let raw =
            (
                value
                ?? "nextPage"
            )
            .trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )
            .lowercased()

        switch raw {
        case "nextpage":
            return .nextPage

        case "continuous":
            return .continuous

        case "evenpage":
            return .evenPage

        case "oddpage":
            return .oddPage

        case "nextcolumn":
            return .nextColumn

        default:
            throw WriterError.message(
                "This Word document uses an unsupported section-break type."
            )
        }
    }

    private static func documentSettingsContains(
        _ localName: String,
        parts: [String: Data],
        mainPart: String,
        parentLocalName: String? = nil
    ) throws -> Bool {
        let directory =
            (mainPart as NSString)
                .deletingLastPathComponent

        let relationshipPath =
            (
                directory.isEmpty
                    ? ""
                    : directory + "/"
            )
            + "_rels/"
            + (mainPart as NSString)
                .lastPathComponent
            + ".rels"

        guard
            let relationshipData =
                parts[
                    relationshipPath
                ]
        else {
            return false
        }

        let relationships =
            try DOCXPackage.xml(
                relationshipData
            )

        let matches =
            try relationships.nodes(
                forXPath:
                    "//*[local-name()='Relationship']"
            )
            .compactMap {
                $0 as? XMLElement
            }
            .filter {
                relationship in

                relationship.attribute(
                    forName:
                        "Type"
                )?
                .stringValue?
                .hasSuffix(
                    "/settings"
                )
                == true
            }

        guard matches.count <= 1 else {
            throw WriterError.message(
                "The DOCX package contains multiple document settings relationships."
            )
        }

        guard
            let relationship =
                matches.first
        else {
            return false
        }

        guard
            relationship.attribute(
                forName:
                    "TargetMode"
            )?
            .stringValue
                != "External",
            let target =
                relationship.attribute(
                    forName:
                        "Target"
                )?
                .stringValue,
            let settingsPart =
                DOCXPackage.target(
                    target,
                    relativeTo:
                        mainPart
                ),
            let settingsData =
                parts[
                    settingsPart
                ]
        else {
            throw WriterError.message(
                "The Word document settings relationship could not be resolved safely."
            )
        }

        let settings =
            try DOCXPackage.xml(
                settingsData
            )

        let xpath:
            String

        if let parentLocalName {
            xpath =
                "//*[local-name()='\(parentLocalName)']/*[local-name()='\(localName)']"
        } else {
            xpath =
                "//*[local-name()='\(localName)']"
        }

        return try !settings.nodes(
            forXPath:
                xpath
        )
        .isEmpty
    }

    static func prepareSections(
        in documentXML: XMLDocument,
        parts: [String: Data],
        mainPart: String,
        fallbackPage: PageSettings
    ) throws -> ImportedSections {
        let allSectionNodes =
            try documentXML.nodes(
                forXPath:
                    "//*[local-name()='sectPr']"
            )
            .compactMap {
                $0 as? XMLElement
            }

        // Ignore historical sectPr snapshots nested inside
        // tracked paragraph-property changes. Active Word
        // sections are either directly under w:body or under
        // the w:pPr of a real body paragraph.
        let sectionNodes =
            allSectionNodes.filter {
                section in

                guard
                    let parent =
                        section.parent
                            as? XMLElement
                else {
                    return false
                }

                if parent.localName == "body" {
                    return true
                }

                guard
                    parent.localName == "pPr",
                    let paragraph =
                        parent.parent
                            as? XMLElement,
                    paragraph.localName == "p"
                else {
                    return false
                }

                return true
            }

        guard !sectionNodes.isEmpty else {
            return ImportedSections(
                firstPage:
                    fallbackPage,
                firstBreakType:
                    .nextPage,
                boundaries:
                    []
            )
        }

        let usesMirrorMargins =
            try documentSettingsContains(
                "mirrorMargins",
                parts:
                    parts,
                mainPart:
                    mainPart
            )

        let usesGutterAtTop =
            try documentSettingsContains(
                "gutterAtTop",
                parts:
                    parts,
                mainPart:
                    mainPart
            )

        let disablesColumnBalancing =
            try documentSettingsContains(
                "noColumnBalance",
                parts:
                    parts,
                mainPart:
                    mainPart,
                parentLocalName:
                    "compat"
            )

        var pages =
            try sectionNodes.map {
                try importPageSettings(
                    section:
                        $0,
                    parts:
                        parts,
                    mainPart:
                        mainPart
                )
            }

        if usesMirrorMargins
            || usesGutterAtTop
            || disablesColumnBalancing {

            for index in pages.indices {
                if usesMirrorMargins {
                    pages[index].mirrorMargins =
                        true
                }

                if usesGutterAtTop {
                    pages[index].gutterAtTop =
                        true
                }

                if disablesColumnBalancing {
                    pages[index].noColumnBalance =
                        true
                }
            }
        }

        // Word links a later section's header/footer to the
        // preceding section by OMITTING the corresponding SAME-TYPE
        // reference from the later sectPr. importPageSettings parses
        // each sectPr independently, so resolve Word inheritance here
        // after all local section settings exist.
        //
        // BOLD Writer stores resolved visible furniture rather than
        // a live Word "Link to Previous" flag. Explicit references
        // remain authoritative; only omitted references inherit.
        //
        // First-page furniture is materialized only while the later
        // section itself has w:titlePg active, preserving visible Word
        // behavior without activating dormant first-page furniture.
        if pages.count > 1 {
            for index in 1..<pages.count {
                let section =
                    sectionNodes[index]

                func hasReference(
                    _ element: String,
                    type: String
                ) throws -> Bool {
                    try !section.nodes(
                        forXPath:
                            "./*[local-name()='\(element)' and @*[local-name()='type']='\(type)']"
                    )
                    .isEmpty
                }

                let hasDefaultHeader =
                    try hasReference(
                        "headerReference",
                        type:
                            "default"
                    )

                let hasEvenHeader =
                    try hasReference(
                        "headerReference",
                        type:
                            "even"
                    )

                let hasFirstHeader =
                    try hasReference(
                        "headerReference",
                        type:
                            "first"
                    )

                let hasDefaultFooter =
                    try hasReference(
                        "footerReference",
                        type:
                            "default"
                    )

                let hasEvenFooter =
                    try hasReference(
                        "footerReference",
                        type:
                            "even"
                    )

                let hasFirstFooter =
                    try hasReference(
                        "footerReference",
                        type:
                            "first"
                    )

                let previous =
                    pages[index - 1]

                if !hasDefaultHeader {
                    pages[index].headerText =
                        previous.headerText

                    pages[index].headerPosition =
                        previous.headerPosition
                }

                if !hasDefaultFooter {
                    pages[index].footerText =
                        previous.footerText

                    pages[index].footerPosition =
                        previous.footerPosition

                    pages[index].showsPageNumbers =
                        previous.showsPageNumbers

                    pages[index].pageNumberPosition =
                        previous.pageNumberPosition
                }

                if !hasEvenHeader {
                    pages[index].evenPageHeaderText =
                        previous.evenPageHeaderText
                }

                if !hasEvenFooter {
                    pages[index].evenPageFooterText =
                        previous.evenPageFooterText

                    pages[index].evenPageFooterPosition =
                        previous.evenPageFooterPosition

                    pages[index].evenPageNumberPosition =
                        previous.evenPageNumberPosition
                }

                if pages[index]
                    .suppressFirstPageHeaderFooter
                    ?? false {

                    if !hasFirstHeader {
                        pages[index].firstPageHeaderText =
                            previous.firstPageHeaderText
                    }

                    if !hasFirstFooter {
                        pages[index].firstPageFooterText =
                            previous.firstPageFooterText
                    }
                }

                if pages[index].evenPageHeaderText != nil
                    || pages[index].evenPageFooterText != nil {

                    pages[index].differentOddEvenHeaderFooter =
                        true
                }
            }
        }

        let breakTypes =
            try sectionNodes.map {
                try importSectionBreakType(
                    section:
                        $0
                )
            }

        guard sectionNodes.count > 1 else {
            return ImportedSections(
                firstPage:
                    pages[0],
                firstBreakType:
                    .nextPage,
                boundaries:
                    []
            )
        }

        var boundaries:
            [ImportedSectionBoundary] = []

        for index in 0..<(sectionNodes.count - 1) {
            let section =
                sectionNodes[index]

            guard
                let properties =
                    section.parent
                        as? XMLElement,
                properties.localName
                    == "pPr",
                let paragraph =
                    properties.parent
                        as? XMLElement,
                paragraph.localName
                    == "p"
            else {
                throw WriterError.message(
                    "A Word section boundary could not be "
                    + "mapped safely to its paragraph."
                )
            }

            let marker =
                "BOLDSECTION"
                + UUID()
                    .uuidString
                    .replacingOccurrences(
                        of:
                            "-",
                        with:
                            ""
                    )

            // Word applies this sectPr to the section ending
            // with this paragraph. A marker at the paragraph's
            // end lets us recover the exact beginning of the
            // following section after AppKit import.
            paragraph.addChild(
                revisionMarkerRun(
                    marker
                )
            )

            boundaries.append(
                ImportedSectionBoundary(
                    marker:
                        marker,
                    page:
                        pages[index + 1],
                    breakType:
                        breakTypes[index]
                )
            )
        }

        return ImportedSections(
            firstPage:
                pages[0],
            firstBreakType:
                .nextPage,
            boundaries:
                boundaries
        )
    }

    static func restoreSections(
        _ imported: ImportedSections,
        additionalMarkers: [String],
        fallbackPage: PageSettings,
        into result: NSMutableAttributedString
    ) throws -> [DocumentSection] {
        guard !imported.boundaries.isEmpty else {
            return DocumentSection.normalized(
                [
                    DocumentSection(
                        location:
                            0,
                        page:
                            imported.firstPage,
                        breakType:
                            imported.firstBreakType
                    )
                ],
                textLength:
                    result.length,
                fallbackPage:
                    fallbackPage
            )
        }

        struct LocatedBoundary {
            let boundary: ImportedSectionBoundary
            let range: NSRange
            let rawNextSectionLocation: Int
        }

        let source =
            result.string
                as NSString

        var markerRanges:
            [String: NSRange] = [:]

        let sectionMarkerNames =
            imported.boundaries.map {
                $0.marker
            }

        let allMarkerNames =
            sectionMarkerNames
            + additionalMarkers

        for marker in allMarkerNames {
            let first =
                source.range(
                    of:
                        marker
                )

            guard
                first.location
                    != NSNotFound
            else {
                throw WriterError.message(
                    "A DOCX marker needed for section import "
                    + "was lost."
                )
            }

            let after =
                NSMaxRange(
                    first
                )

            if after < source.length {
                let second =
                    source.range(
                        of:
                            marker,
                        options:
                            [],
                        range:
                            NSRange(
                                location:
                                    after,
                                length:
                                    source.length
                                    - after
                            )
                    )

                guard
                    second.location
                        == NSNotFound
                else {
                    throw WriterError.message(
                        "A DOCX marker needed for section import "
                        + "was duplicated."
                    )
                }
            }

            markerRanges[marker] =
                first
        }

        let allRanges =
            markerRanges.values.sorted {
                $0.location
                    < $1.location
            }

        func adjustedLocation(
            _ location: Int
        ) -> Int {
            let removed =
                allRanges.reduce(
                    0
                ) {
                    partial,
                    range in

                    NSMaxRange(
                        range
                    ) <= location
                        ? partial
                            + range.length
                        : partial
                }

            return
                location
                - removed
        }

        var located:
            [LocatedBoundary] = []

        for boundary in imported.boundaries {
            guard
                let range =
                    markerRanges[
                        boundary.marker
                    ]
            else {
                throw WriterError.message(
                    "A Word section boundary marker "
                    + "could not be recovered."
                )
            }

            var rawNext =
                NSMaxRange(
                    range
                )

            // The marker is the final run of the section-break
            // paragraph. AppKit places the paragraph separator
            // immediately after it. The next section begins
            // after that separator.
            if rawNext < source.length {
                let character =
                    source.substring(
                        with:
                            NSRange(
                                location:
                                    rawNext,
                                length:
                                    1
                            )
                    )

                if character == "\n"
                    || character == "\r" {

                    rawNext += 1
                }
            }

            located.append(
                LocatedBoundary(
                    boundary:
                        boundary,
                    range:
                        range,
                    rawNextSectionLocation:
                        rawNext
                )
            )
        }

        var sections:
            [DocumentSection] = [
                DocumentSection(
                    location:
                        0,
                    page:
                        imported.firstPage
                )
            ]

        for item in located {
            sections.append(
                DocumentSection(
                    location:
                        adjustedLocation(
                            item.rawNextSectionLocation
                        ),
                    page:
                        item.boundary.page,
                    breakType:
                        item.boundary.breakType
                )
            )
        }

        // Remove only our own markers. Comment/bookmark/link
        // markers remain for their dedicated restoration passes.
        for range in located
            .map({ $0.range })
            .sorted(
                by: {
                    $0.location
                        > $1.location
                }
            ) {

            result.deleteCharacters(
                in:
                    range
            )
        }

        return DocumentSection.normalized(
            sections,
            textLength:
                result.length
                - additionalMarkers.reduce(
                    0
                ) {
                    partial,
                    marker in

                    partial
                    + (
                        markerRanges[
                            marker
                        ]?
                        .length
                        ?? 0
                    )
                },
            fallbackPage:
                fallbackPage
        )
    }

    private static func importPageSettings(
        section: XMLElement,
        parts: [String: Data],
        mainPart: String
    ) throws -> PageSettings {
        let wrapper =
            XMLElement(
                name:
                    "document"
            )

        let body =
            XMLElement(
                name:
                    "body"
            )

        body.addChild(
            section.copy()
                as! XMLNode
        )

        wrapper.addChild(
            body
        )

        let document =
            XMLDocument(
                rootElement:
                    wrapper
            )

        return try importPageSettings(
            documentXML:
                document,
            parts:
                parts,
            mainPart:
                mainPart
        )
    }


    static func importPageSettings(
        documentXML:
            XMLDocument,
        parts:
            [String: Data],
        mainPart:
            String
    ) throws -> PageSettings {
        func failure(
            _ detail: String
        ) -> WriterError {
            .message(
                "The DOCX page setup could not be imported safely. "
                + detail
            )
        }

        func attribute(
            _ element: XMLElement,
            _ name: String
        ) -> String? {
            element.attributes?
                .first {
                    $0.localName
                        == name
                        || $0.name
                            == name
                        || $0.name
                            == "w:"
                            + name
                        || $0.name
                            == "r:"
                            + name
                }?
                .stringValue
        }

        func child(
            _ parent: XMLElement,
            named name: String
        ) throws -> XMLElement? {
            try parent.nodes(
                forXPath:
                    "./*[local-name()='"
                    + name
                    + "']"
            )
            .first
                as? XMLElement
        }

        func onOff(
            _ element: XMLElement?
        ) -> Bool {
            guard
                let element
            else {
                return false
            }

            guard
                let raw =
                    attribute(
                        element,
                        "val"
                    )?
                    .lowercased()
            else {
                return true
            }

            return ![
                "0",
                "false",
                "off",
                "no"
            ]
            .contains(
                raw
            )
        }

        func twips(
            _ raw: String?
        ) throws -> Double {
            guard
                let raw,
                let value =
                    Double(
                        raw
                    ),
                value.isFinite
            else {
                throw failure(
                    "A page measurement is invalid."
                )
            }

            return
                value
                / 20.0
        }

        func position(
            of paragraph:
                XMLElement
        ) throws
            -> PageSettings.HorizontalPosition {

            guard
                let properties =
                    try child(
                        paragraph,
                        named:
                            "pPr"
                    ),
                let justification =
                    try child(
                        properties,
                        named:
                            "jc"
                    ),
                let raw =
                    attribute(
                        justification,
                        "val"
                    )?
                    .lowercased()
            else {
                return .left
            }

            switch raw {
            case "left", "start":
                return .left

            case "center":
                return .center

            case "right", "end":
                return .right

            default:
                throw failure(
                    "A header or footer uses an alignment "
                    + "BOLD Writer cannot represent yet."
                )
            }
        }

        func isPageInstruction(
            _ raw: String
        ) -> Bool {
            raw.uppercased()
                .range(
                    of:
                        "(^|[^A-Z])PAGE([^A-Z]|$)",
                    options:
                        .regularExpression
                )
                != nil
        }

        func hasAncestor(
            _ node: XMLNode,
            named name: String,
            stoppingAt stop:
                XMLElement
        ) -> Bool {
            var parent =
                node.parent

            while let current =
                parent {

                if current === stop {
                    return false
                }

                if current.localName
                    == name {

                    return true
                }

                parent =
                    current.parent
            }

            return false
        }

        struct Furniture {
            var text = ""
            var textPosition:
                PageSettings.HorizontalPosition =
                    .left

            var hasPageNumber = false

            var pageNumberPosition:
                PageSettings.HorizontalPosition =
                    .right
        }

        func furniture(
            from data: Data,
            expectedRoot:
                String,
            allowsPageNumbers:
                Bool
        ) throws -> Furniture {
            let xml =
                try DOCXPackage.xml(
                    data
                )

            guard
                xml.rootElement()?
                    .localName
                    == expectedRoot
            else {
                throw failure(
                    "A header or footer relationship points "
                    + "to the wrong type of XML part."
                )
            }

            let unsupported =
                try xml.nodes(
                    forXPath:
                        "//*[local-name()='tbl' "
                        + "or local-name()='drawing' "
                        + "or local-name()='pict' "
                        + "or local-name()='txbxContent' "
                        + "or local-name()='hyperlink']"
                )

            guard
                unsupported.isEmpty
            else {
                throw failure(
                    "A header or footer contains tables, "
                    + "graphics, text boxes, or hyperlinks "
                    + "that BOLD Writer cannot represent yet."
                )
            }

            let paragraphs =
                try xml.nodes(
                    forXPath:
                        "//*[local-name()='p']"
                )
                .compactMap {
                    $0 as? XMLElement
                }

            var textLines:
                [String] = []

            var textPositions:
                Set<PageSettings.HorizontalPosition> =
                    []

            var pagePositions:
                Set<PageSettings.HorizontalPosition> =
                    []

            var detectedPageNumber =
                false

            for paragraph
                in paragraphs {

                let simpleFields =
                    try paragraph.nodes(
                        forXPath:
                            ".//*[local-name()='fldSimple']"
                    )
                    .compactMap {
                        $0 as? XMLElement
                    }

                var paragraphHasPage =
                    false

                for field
                    in simpleFields {

                    let instruction =
                        attribute(
                            field,
                            "instr"
                        )
                        ?? ""

                    guard
                        isPageInstruction(
                            instruction
                        )
                    else {
                        throw failure(
                            "A header or footer contains a Word "
                            + "field other than PAGE."
                        )
                    }

                    paragraphHasPage =
                        true
                }

                let fieldCharacters =
                    try paragraph.nodes(
                        forXPath:
                            ".//*[local-name()='fldChar']"
                    )
                    .compactMap {
                        $0 as? XMLElement
                    }

                if !fieldCharacters.isEmpty {
                    let begins =
                        fieldCharacters.filter {
                            attribute(
                                $0,
                                "fldCharType"
                            )?
                            .lowercased()
                                == "begin"
                        }

                    guard
                        begins.count == 1
                    else {
                        throw failure(
                            "A header or footer contains multiple "
                            + "or malformed complex Word fields."
                        )
                    }

                    let instructions =
                        try paragraph.nodes(
                            forXPath:
                                ".//*[local-name()='instrText']"
                        )
                        .compactMap {
                            $0.stringValue
                        }
                        .joined(
                            separator:
                                " "
                        )

                    guard
                        isPageInstruction(
                            instructions
                        )
                    else {
                        throw failure(
                            "A header or footer contains a complex "
                            + "Word field other than PAGE."
                        )
                    }

                    paragraphHasPage =
                        true
                }

                if paragraphHasPage {
                    guard
                        allowsPageNumbers
                    else {
                        throw failure(
                            "A PAGE field appears in a header. "
                            + "BOLD Writer currently places page "
                            + "numbers in footers only."
                        )
                    }

                    detectedPageNumber =
                        true

                    pagePositions.insert(
                        try position(
                            of:
                                paragraph
                        )
                    )
                }

                let ordered =
                    try paragraph.nodes(
                        forXPath:
                            ".//*[local-name()='fldChar' "
                            + "or local-name()='t' "
                            + "or local-name()='tab' "
                            + "or local-name()='br' "
                            + "or local-name()='cr']"
                    )

                var fieldDepth =
                    0

                var value =
                    ""

                for node
                    in ordered {

                    if node.localName
                        == "fldChar",
                       let element =
                        node as? XMLElement {

                        let kind =
                            attribute(
                                element,
                                "fldCharType"
                            )?
                            .lowercased()

                        if kind == "begin" {
                            fieldDepth += 1

                        } else if kind == "end" {
                            fieldDepth =
                                max(
                                    0,
                                    fieldDepth
                                    - 1
                                )
                        }

                        continue
                    }

                    guard
                        fieldDepth == 0,
                        !hasAncestor(
                            node,
                            named:
                                "fldSimple",
                            stoppingAt:
                                paragraph
                        )
                    else {
                        continue
                    }

                    switch node.localName {
                    case "t":
                        value +=
                            node.stringValue
                            ?? ""

                    case "tab":
                        value += "\t"

                    case "br", "cr":
                        value += "\n"

                    default:
                        break
                    }
                }

                if paragraphHasPage,
                   value.hasSuffix(
                        "   •   "
                   ) {

                    value.removeLast(
                        "   •   ".count
                    )
                }

                let clean =
                    value.trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    )

                if !clean.isEmpty {
                    textLines.append(
                        clean
                    )

                    textPositions.insert(
                        try position(
                            of:
                                paragraph
                        )
                    )
                }
            }

            guard
                textPositions.count <= 1
            else {
                throw failure(
                    "Header or footer text uses multiple "
                    + "alignments that BOLD Writer cannot "
                    + "represent with one global position."
                )
            }

            guard
                pagePositions.count <= 1
            else {
                throw failure(
                    "Page-number fields use multiple alignments."
                )
            }

            var result =
                Furniture()

            result.text =
                textLines.joined(
                    separator:
                        "\n"
                )

            result.textPosition =
                textPositions.first
                ?? .left

            result.hasPageNumber =
                detectedPageNumber

            result.pageNumberPosition =
                pagePositions.first
                ?? .right

            return result
        }

        func relationshipPart(
            for reference:
                XMLElement,
            kind:
                String
        ) throws -> Data {
            guard
                let relationshipID =
                    attribute(
                        reference,
                        "id"
                    ),
                !relationshipID.isEmpty
            else {
                throw failure(
                    "A "
                    + kind
                    + " reference has no relationship identifier."
                )
            }

            let directory =
                (mainPart as NSString)
                    .deletingLastPathComponent

            let relationshipPath =
                (directory.isEmpty
                    ? ""
                    : directory + "/")
                + "_rels/"
                + (mainPart as NSString)
                    .lastPathComponent
                + ".rels"

            guard
                let relationshipData =
                    parts[
                        relationshipPath
                    ]
            else {
                throw failure(
                    "The document relationships part is missing."
                )
            }

            let relationships =
                try DOCXPackage.xml(
                    relationshipData
                )

            let matches =
                try relationships.nodes(
                    forXPath:
                        "//*[local-name()='Relationship']"
                )
                .compactMap {
                    $0 as? XMLElement
                }
                .filter {
                    relationship in

                    relationship.attribute(
                        forName:
                            "Id"
                    )?
                    .stringValue
                        == relationshipID

                        && relationship.attribute(
                            forName:
                                "Type"
                        )?
                        .stringValue?
                        .hasSuffix(
                            "/"
                            + kind
                        ) == true
                }

            guard
                matches.count == 1,
                let relationship =
                    matches.first
            else {
                throw failure(
                    "The "
                    + kind
                    + " relationship is missing or ambiguous."
                )
            }

            guard
                relationship.attribute(
                    forName:
                        "TargetMode"
                )?
                .stringValue
                    != "External",
                let target =
                    relationship.attribute(
                        forName:
                            "Target"
                    )?
                    .stringValue,
                let path =
                    DOCXPackage.target(
                        target,
                        relativeTo:
                            mainPart
                    ),
                let data =
                    parts[
                        path
                    ]
            else {
                throw failure(
                    "The "
                    + kind
                    + " relationship does not resolve "
                    + "to an internal DOCX part."
                )
            }

            return data
        }

        func furnitureReference(
            in section:
                XMLElement,
            named name: String,
            type expectedType: String
        ) throws -> XMLElement? {
            let references =
                try section.nodes(
                    forXPath:
                        "./*[local-name()='"
                        + name
                        + "Reference']"
                )
                .compactMap {
                    $0 as? XMLElement
                }

            let unsupported =
                references.filter {
                    reference in

                    let type =
                        attribute(
                            reference,
                            "type"
                        )?
                        .lowercased()
                        ?? "default"

                    return ![
                        "default",
                        "even",
                        "first"
                    ]
                    .contains(
                        type
                    )
                }

            guard
                unsupported.isEmpty
            else {
                throw failure(
                    "Different first-page "
                    + name
                    + " content is not supported yet."
                )
            }

            let matches =
                references.filter {
                    reference in

                    let type =
                        attribute(
                            reference,
                            "type"
                        )?
                        .lowercased()
                        ?? "default"

                    return type
                        == expectedType
                }

            guard
                matches.count <= 1
            else {
                throw failure(
                    "A Word section contains multiple "
                    + expectedType
                    + " "
                    + name
                    + " references."
                )
            }

            return matches.first
        }

        // DOCX import must not inherit the legacy BOLD footer
        // defaults when Word has no header/footer furniture.
        var settings =
            PageSettings()

        settings.headerText =
            ""

        settings.footerText =
            ""

        settings.showsPageNumbers =
            false

        settings.headerPosition =
            .left

        settings.footerPosition =
            .left

        settings.pageNumberPosition =
            .right

        settings.suppressFirstPageHeaderFooter =
            false

        let sections =
            try documentXML.nodes(
                forXPath:
                    "//*[local-name()='sectPr']"
            )
            .compactMap {
                $0 as? XMLElement
            }

        guard
            let section =
                sections.last
        else {
            return settings
        }

        if let pageNumber =
            try child(
                section,
                named:
                    "pgNumType"
            ) {

            if let rawStart =
                attribute(
                    pageNumber,
                    "start"
                )?
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                ),
               !rawStart.isEmpty {

                guard
                    let start =
                        Int(
                            rawStart
                        ),
                    start >= 1
                else {
                    throw failure(
                        "The Word section contains an invalid page-number start value."
                    )
                }

                settings.pageNumberStart =
                    start
            }

            if let rawFormat =
                attribute(
                    pageNumber,
                    "fmt"
                )?
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                ),
               !rawFormat.isEmpty {

                settings.pageNumberFormat =
                    rawFormat
            }
        }

        if let columns =
            try child(
                section,
                named:
                    "cols"
            ) {

            if let rawCount =
                attribute(
                    columns,
                    "num"
                )?
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                ),
               !rawCount.isEmpty {

                guard
                    let count =
                        Int(
                            rawCount
                        ),
                    (1...12).contains(
                        count
                    )
                else {
                    throw failure(
                        "The Word section contains an invalid column count."
                    )
                }

                settings.columnCount =
                    count
            }

            if let rawSpacing =
                attribute(
                    columns,
                    "space"
                )?
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                ),
               !rawSpacing.isEmpty {

                guard
                    let twips =
                        Double(
                            rawSpacing
                        ),
                    twips >= 0
                else {
                    throw failure(
                        "The Word section contains invalid column spacing."
                    )
                }

                settings.columnSpacing =
                    twips
                    / 20
            }
        }

        if let size =
            try child(
                section,
                named:
                    "pgSz"
            ) {

            let width =
                try twips(
                    attribute(
                        size,
                        "w"
                    )
                )

            let height =
                try twips(
                    attribute(
                        size,
                        "h"
                    )
                )

            guard
                width > 0,
                height > 0
            else {
                throw failure(
                    "The Word page size is invalid."
                )
            }

            let orientation =
                attribute(
                    size,
                    "orient"
                )?
                .lowercased()

            switch orientation {
            case nil, "":
                settings.landscape =
                    width > height

            case "portrait":
                settings.landscape =
                    false

            case "landscape":
                settings.landscape =
                    true

            default:
                throw failure(
                    "The Word page orientation is unsupported."
                )
            }

            let shortSide =
                min(
                    width,
                    height
                )

            let longSide =
                max(
                    width,
                    height
                )

            func near(
                _ actual: Double,
                _ expected: Double
            ) -> Bool {
                abs(
                    actual
                    - expected
                ) <= 3.0
            }

            if near(
                shortSide,
                612
            ),
               near(
                    longSide,
                    792
               ) {

                settings.paper =
                    .letter

            } else if near(
                shortSide,
                595.28
            ),
                      near(
                        longSide,
                        841.89
                      ) {

                settings.paper =
                    .a4

            } else {
                settings.paper = .custom
                settings.customPaperSize = CGSize(width: shortSide, height: longSide)
            }
        }

        if let margins =
            try child(
                section,
                named:
                    "pgMar"
            ) {

            let top =
                try twips(
                    attribute(
                        margins,
                        "top"
                    )
                )

            let right =
                try twips(
                    attribute(
                        margins,
                        "right"
                    )
                )

            let bottom =
                try twips(
                    attribute(
                        margins,
                        "bottom"
                    )
                )

            let left =
                try twips(
                    attribute(
                        margins,
                        "left"
                    )
                )

            let headerDistance =
                try attribute(
                    margins,
                    "header"
                )
                .map {
                    try twips(
                        $0
                    )
                }

            let footerDistance =
                try attribute(
                    margins,
                    "footer"
                )
                .map {
                    try twips(
                        $0
                    )
                }

            let furnitureDistances =
                [
                    headerDistance,
                    footerDistance
                ]
                .compactMap {
                    $0
                }

            guard
                [top, right, bottom, left]
                    .allSatisfy({
                        $0 >= 0
                            && $0.isFinite
                    }),
                furnitureDistances
                    .allSatisfy({
                        $0 >= 0
                            && $0.isFinite
                    })
            else {
                throw failure(
                    "The Word document contains negative "
                    + "or invalid page margins."
                )
            }

            settings.topMargin =
                top

            settings.rightMargin =
                right

            settings.bottomMargin =
                bottom

            settings.leftMargin =
                left

            if let rawGutter =
                attribute(
                    margins,
                    "gutter"
                )?
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                ),
               !rawGutter.isEmpty {

                guard
                    let gutterTwips =
                        Double(
                            rawGutter
                        ),
                    gutterTwips.isFinite,
                    gutterTwips >= 0
                else {
                    throw failure(
                        "The Word section contains an invalid gutter margin."
                    )
                }

                settings.gutter =
                    gutterTwips
                    / 20
            }

            settings.headerDistance =
                headerDistance

            settings.footerDistance =
                footerDistance
        }

        let pageSize =
            settings.pageSize

        guard
            pageSize.width
                - settings.leftMargin
                - settings.rightMargin
                >= 72,
            pageSize.height
                - settings.topMargin
                - settings.bottomMargin
                >= 72
        else {
            throw failure(
                "The imported margins leave too little "
                + "printable page area."
            )
        }

        if let verticalAlignment =
            try child(
                section,
                named:
                    "vAlign"
            ) {

            guard
                let rawAlignment =
                    attribute(
                        verticalAlignment,
                        "val"
                    )?
                    .trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    )
                    .lowercased(),
                !rawAlignment.isEmpty
            else {
                throw failure(
                    "The Word section contains an invalid vertical page alignment."
                )
            }

            guard
                let alignment =
                    PageSettings
                        .VerticalPageAlignment(
                            rawValue:
                                rawAlignment
                        )
            else {
                throw failure(
                    "The Word section contains an unsupported vertical page alignment."
                )
            }

            settings.verticalPageAlignment =
                alignment
        }

        settings.suppressFirstPageHeaderFooter =
            onOff(
                try child(
                    section,
                    named:
                        "titlePg"
                )
            )

        let defaultHeaderReference =
            try furnitureReference(
                in:
                    section,
                named:
                    "header",
                type:
                    "default"
            )

        let evenHeaderReference =
            try furnitureReference(
                in:
                    section,
                named:
                    "header",
                type:
                    "even"
            )

        let firstHeaderReference =
            try furnitureReference(
                in:
                    section,
                named:
                    "header",
                type:
                    "first"
            )

        let defaultFooterReference =
            try furnitureReference(
                in:
                    section,
                named:
                    "footer",
                type:
                    "default"
            )

        let evenFooterReference =
            try furnitureReference(
                in:
                    section,
                named:
                    "footer",
                type:
                    "even"
            )

        let firstFooterReference =
            try furnitureReference(
                in:
                    section,
                named:
                    "footer",
                type:
                    "first"
            )

        settings.differentOddEvenHeaderFooter =
            evenHeaderReference != nil
                || evenFooterReference != nil

        if let reference =
            defaultHeaderReference {

            let imported =
                try furniture(
                    from:
                        relationshipPart(
                            for:
                                reference,
                            kind:
                                "header"
                        ),
                    expectedRoot:
                        "hdr",
                    allowsPageNumbers:
                        false
                )

            settings.headerText =
                imported.text

            settings.headerPosition =
                imported.textPosition
        }

        if let reference =
            evenHeaderReference {

            let imported =
                try furniture(
                    from:
                        relationshipPart(
                            for:
                                reference,
                            kind:
                                "header"
                        ),
                    expectedRoot:
                        "hdr",
                    allowsPageNumbers:
                        false
                )

            if defaultHeaderReference != nil,
               imported.textPosition
                    != settings.effectiveHeaderPosition {

                throw failure(
                    "Odd and even headers use different "
                    + "alignments that BOLD Writer cannot "
                    + "represent separately yet."
                )
            }

            settings.evenPageHeaderText =
                imported.text

            if defaultHeaderReference == nil {
                settings.headerPosition =
                    imported.textPosition
            }
        }

        if let reference =
            defaultFooterReference {

            let imported =
                try furniture(
                    from:
                        relationshipPart(
                            for:
                                reference,
                            kind:
                                "footer"
                        ),
                    expectedRoot:
                        "ftr",
                    allowsPageNumbers:
                        true
                )

            settings.footerText =
                imported.text

            settings.footerPosition =
                imported.textPosition

            settings.showsPageNumbers =
                imported.hasPageNumber

            settings.pageNumberPosition =
                imported.pageNumberPosition
        }

        if let reference =
            evenFooterReference {

            let imported =
                try furniture(
                    from:
                        relationshipPart(
                            for:
                                reference,
                            kind:
                                "footer"
                        ),
                    expectedRoot:
                        "ftr",
                    allowsPageNumbers:
                        true
                )

            settings.evenPageFooterPosition = imported.textPosition

            if defaultFooterReference != nil,
               imported.hasPageNumber
                    != settings.showsPageNumbers {

                throw failure(
                    "Odd and even footers use different "
                    + "page-number visibility that BOLD Writer "
                    + "cannot represent separately yet."
                )
            }

            settings.evenPageNumberPosition = imported.pageNumberPosition

            settings.evenPageFooterText =
                imported.text

            if defaultFooterReference == nil {
                settings.footerPosition =
                    imported.textPosition

                settings.showsPageNumbers =
                    imported.hasPageNumber

                settings.pageNumberPosition =
                    imported.pageNumberPosition
            }
        }

        if let reference =
            firstHeaderReference {

            let imported =
                try furniture(
                    from:
                        relationshipPart(
                            for:
                                reference,
                            kind:
                                "header"
                        ),
                    expectedRoot:
                        "hdr",
                    allowsPageNumbers:
                        false
                )

            if imported.textPosition
                != settings.effectiveHeaderPosition {

                throw failure(
                    "The first-page header uses a different "
                    + "alignment that BOLD Writer cannot "
                    + "represent separately yet."
                )
            }

            settings.firstPageHeaderText =
                imported.text
        }

        if let reference =
            firstFooterReference {

            let imported =
                try furniture(
                    from:
                        relationshipPart(
                            for:
                                reference,
                            kind:
                                "footer"
                        ),
                    expectedRoot:
                        "ftr",
                    allowsPageNumbers:
                        true
                )

            if imported.textPosition
                != settings.effectiveFooterPosition {

                throw failure(
                    "The first-page footer uses a different "
                    + "alignment that BOLD Writer cannot "
                    + "represent separately yet."
                )
            }

            if imported.hasPageNumber
                != settings.showsPageNumbers {

                throw failure(
                    "The first-page footer uses different "
                    + "page-number visibility that BOLD Writer "
                    + "cannot represent separately yet."
                )
            }

            if imported.hasPageNumber,
               imported.pageNumberPosition
                    != settings.effectivePageNumberPosition {

                throw failure(
                    "The first-page footer uses a different "
                    + "page-number alignment that BOLD Writer "
                    + "cannot represent separately yet."
                )
            }

            settings.firstPageFooterText =
                imported.text
        }

        return settings
    }
}
