import AppKit
import Foundation

/// Bounded Open XML export: text, basic lists, tab-delimited tables, and inline images.
enum DOCXExporter {
    static func data(
        from text: NSAttributedString,
        title: String,
        settings: PageSettings = PageSettings(),
        sections: [DocumentSection]? = nil,
        trackChangesEnabled: Bool? = nil,
        comments: [DocumentComment] = [],
        bookmarks: [DocumentBookmark] = [],
        namedStyles: [NamedStyleDefinition] = [],
        floatingImages: [FloatingImage] = []
    ) throws -> Data {
        let effectiveStyles = NamedStyles.mergedWithBuiltIns(namedStyles)
        try NamedStyles.validate(effectiveStyles)
        let normalized = NSMutableAttributedString(attributedString: text)
        let safeBookmarks = DocumentBookmarks.normalized(bookmarks)
        try DocumentBookmarks.validate(safeBookmarks, textLength: normalized.length)
        try Footnotes.renumber(normalized)
        try Endnotes.renumber(normalized)
        let notes =
            try Footnotes.records(
                in:
                    normalized
            )

        let endnotes =
            try Endnotes.records(
                in:
                    normalized
            )

        let exportComments =
            comments.filter {
                $0.location >= 0
                    && $0.length >= 0
                    && $0.location
                        <= normalized.length
                    && $0.length
                        <= normalized.length
                            - $0.location
            }

        let exportBookmarks = safeBookmarks

        let exportSections =
            DocumentSection.normalized(
                sections ?? [],
                textLength:
                    normalized.length,
                fallbackPage:
                    settings
            )

        let finalSettings =
            exportSections.last?
                .page
            ?? settings

        var writer = Writer(
            text: normalized,
            settings: finalSettings,
            sections: exportSections,
            notes: notes,
            endnotes: endnotes,
            comments:
                exportComments,
            bookmarks:
                exportBookmarks,
            floatingImages: floatingImages
        )

        try FloatingImage.validate(floatingImages, textLength: normalized.length)
        let document =
            try writer.document()

        writer.namedStyles = effectiveStyles

        let furnitureParts =
            writer.furnitureParts

        let includeTrackRevisionsSetting =
            trackChangesEnabled
                ?? writer.hasTrackedChanges

        let includeSettingsPart =
            includeTrackRevisionsSetting
                || writer.usesDifferentOddEvenHeaderFooter
                || writer.usesMirrorMargins
                || writer.usesGutterAtTop
                || writer.usesNoColumnBalance

        var packageContentTypes =
            contentTypes
            .replacingOccurrences(
                of: "</Types>",
                with: "<Default Extension=\"png\" ContentType=\"image/png\"/><Default Extension=\"jpg\" ContentType=\"image/jpeg\"/></Types>"
            )

        if includeSettingsPart {
            packageContentTypes = packageContentTypes
                .replacingOccurrences(
                    of: "</Types>",
                    with: "<Override PartName=\"/word/settings.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml\"/></Types>"
                )
        }

        if !writer.comments.isEmpty {
            packageContentTypes =
                packageContentTypes
                    .replacingOccurrences(
                        of:
                            "</Types>",
                        with:
                            "<Override PartName=\"/word/comments.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.comments+xml\"/></Types>"
                    )
        }

        for part in furnitureParts {
            packageContentTypes =
                packageContentTypes
                    .replacingOccurrences(
                        of:
                            "</Types>",
                        with:
                            "<Override PartName=\"/"
                            + part.path
                            + "\" ContentType=\""
                            + part.contentType
                            + "\"/></Types>"
                    )
        }

        var documentRelationships =
            writer.relationships

        let settingsRelationshipPattern =
            #"<Relationship\b[^>]*Type="[^"]*/settings"[^>]*/>"#

        if includeSettingsPart {
            if !documentRelationships.contains(
                "relationships/settings"
            ) {
                documentRelationships =
                    documentRelationships
                        .replacingOccurrences(
                            of: "</Relationships>",
                            with:
                                "<Relationship Id=\"rSettings\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings\" Target=\"settings.xml\"/></Relationships>"
                        )
            }
        } else {
            let expression =
                try NSRegularExpression(
                    pattern:
                        settingsRelationshipPattern
                )

            let range =
                NSRange(
                    documentRelationships
                        .startIndex...,
                    in:
                        documentRelationships
                )

            documentRelationships =
                expression
                    .stringByReplacingMatches(
                        in:
                            documentRelationships,
                        range:
                            range,
                        withTemplate:
                            ""
                    )
        }

        let boldWriterChecklistXML: String? = {
            guard text.length > 0 else {
                return nil
            }

            let source =
                text.string
                    as NSString

            var location = 0
            var paragraphIndex = 0
            var items: [String] = []

            while location < source.length {
                let range =
                    source.paragraphRange(
                        for:
                            NSRange(
                                location:
                                    location,
                                length:
                                    0
                            )
                    )

                guard range.length > 0 else {
                    break
                }

                if
                    range.location < text.length,
                    (text.attribute(
                        .boldWriterChecklist,
                        at:
                            range.location,
                        effectiveRange:
                            nil
                    ) as? Bool) == true
                {
                    let checked =
                        text.attribute(
                            .boldWriterChecklistChecked,
                            at:
                                range.location,
                            effectiveRange:
                                nil
                        ) as? Bool
                        ?? false

                    items.append(
                        "<bw:item paragraph=\"\(paragraphIndex)\" checked=\"\(checked ? "1" : "0")\"/>"
                    )
                }

                let next =
                    NSMaxRange(
                        range
                    )

                guard next > location else {
                    break
                }

                location =
                    next
                paragraphIndex += 1
            }

            guard !items.isEmpty else {
                return nil
            }

            return
                "<bw:checklists xmlns:bw=\"https://boldwriter.app/ns/checklists/1\">"
                + items.joined()
                + "</bw:checklists>"
        }()

        var parts = [
            ("[Content_Types].xml", packageContentTypes),
            ("_rels/.rels", rootRelationships),
            (
                "docProps/core.xml",
                "<cp:coreProperties xmlns:cp=\"http://schemas.openxmlformats.org/package/2006/metadata/core-properties\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\"><dc:title>\(xml(title))</dc:title><dc:creator>BOLD Writer</dc:creator></cp:coreProperties>"
            ),
            ("word/document.xml", document),
            ("word/styles.xml", styles(text, namedStyles: writer.namedStyles)),
            ("word/numbering.xml", writer.numberingXML),
            (
                "word/_rels/document.xml.rels",
                documentRelationships
            )
        ]

        if let checklistXML =
            boldWriterChecklistXML
        {
            parts.append(
                (
                    "word/boldwriter-checklists.xml",
                    checklistXML
                )
            )

            parts[0].1 =
                parts[0].1
                    .replacingOccurrences(
                        of:
                            "</Types>",
                        with:
                            "<Override PartName=\"/word/boldwriter-checklists.xml\" ContentType=\"application/vnd.boldwriter.checklists+xml\"/></Types>"
                    )

            if let relationshipIndex =
                parts.firstIndex(
                    where: {
                        $0.0
                            == "word/_rels/document.xml.rels"
                    }
                )
            {
                parts[relationshipIndex].1 =
                    parts[relationshipIndex].1
                        .replacingOccurrences(
                            of:
                                "</Relationships>",
                            with:
                                "<Relationship Id=\"rBoldWriterChecklists\" Type=\"https://boldwriter.app/relationships/checklists\" Target=\"boldwriter-checklists.xml\"/></Relationships>"
                        )
            }
        }

        if includeSettingsPart {
            parts.append(
                (
                    "word/settings.xml",
                    writer.settingsXML(
                        trackRevisions: includeTrackRevisionsSetting
                    )
                )
            )
        }

        if !writer.comments.isEmpty {
            parts.append(
                (
                    "word/comments.xml",
                    writer.commentsXML
                )
            )
        }

        for part in furnitureParts {
            parts.append(
                (
                    part.path,
                    part.xml
                )
            )
        }

        if !notes.isEmpty {
            parts[0].1 =
                parts[0].1
                    .replacingOccurrences(
                        of: "</Types>",
                        with:
                            "<Override PartName=\"/word/footnotes.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.footnotes+xml\"/></Types>"
                    )

            func revisionRuns(
                _ value: String,
                deletion: Bool
            ) -> String {
                let tag =
                    deletion
                        ? "w:delText"
                        : "w:t"

                let scalars =
                    Array(
                        value.unicodeScalars
                    )

                var result = ""
                var segment = ""
                var index = 0

                func flush() {
                    guard
                        !segment.isEmpty
                    else {
                        return
                    }

                    result +=
                        "<w:r><\(tag) xml:space=\"preserve\">"
                        + xml(segment)
                        + "</\(tag)></w:r>"

                    segment = ""
                }

                while index
                    < scalars.count {
                    let scalar =
                        scalars[index]

                    switch scalar.value {
                    case 0x09:
                        flush()
                        result +=
                            "<w:r><w:tab/></w:r>"

                    case 0x0A,
                         0x2028,
                         0x2029:
                        flush()
                        result +=
                            "<w:r><w:br/></w:r>"

                    case 0x0D:
                        flush()
                        result +=
                            "<w:r><w:br/></w:r>"

                        if index + 1
                            < scalars.count,
                           scalars[index + 1]
                            .value == 0x0A {
                            index += 1
                        }

                    default:
                        if valid(scalar) {
                            segment
                                .unicodeScalars
                                .append(scalar)
                        }
                    }

                    index += 1
                }

                flush()

                return result
            }

            var bodies =
                "<w:footnote w:type=\"separator\" w:id=\"-1\"><w:p><w:r><w:separator/></w:r></w:p></w:footnote><w:footnote w:type=\"continuationSeparator\" w:id=\"0\"><w:p><w:r><w:continuationSeparator/></w:r></w:p></w:footnote>"

            for (index, note)
                in notes.enumerated() {

                let reference =
                    "<w:r><w:rPr><w:vertAlign w:val=\"superscript\"/></w:rPr><w:footnoteRef/></w:r>"

                let paragraphs: String

                if let original =
                    note.bodyChangeOriginalText {

                    let author =
                        attribute(
                            note
                                .bodyChangeAuthor
                            ?? NSFullUserName()
                        )

                    let date =
                        attribute(
                            ISO8601DateFormatter()
                                .string(
                                    from:
                                        note
                                            .bodyChangeDate
                                        ?? Date()
                                )
                        )

                    let deleteID =
                        1000
                        + index * 2

                    let insertID =
                        deleteID + 1

                    paragraphs =
                        "<w:p>"
                        + reference
                        + "<w:del w:id=\"\(deleteID)\" w:author=\"\(author)\" w:date=\"\(date)\">"
                        + revisionRuns(
                            original,
                            deletion: true
                        )
                        + "</w:del>"
                        + "<w:ins w:id=\"\(insertID)\" w:author=\"\(author)\" w:date=\"\(date)\">"
                        + revisionRuns(
                            note.text,
                            deletion: false
                        )
                        + "</w:ins>"
                        + "</w:p>"
                } else {
                    paragraphs =
                        note.text
                            .components(
                                separatedBy: "\n"
                            )
                            .enumerated()
                            .map {
                                line,
                                value in

                                "<w:p>"
                                + (
                                    line == 0
                                        ? reference
                                        : ""
                                )
                                + "<w:r><w:t xml:space=\"preserve\">"
                                + xml(value)
                                + "</w:t></w:r></w:p>"
                            }
                            .joined()
                }

                bodies +=
                    "<w:footnote w:id=\"\(index + 1)\">"
                    + paragraphs
                    + "</w:footnote>"
            }

            parts.append(
                (
                    "word/footnotes.xml",
                    "<w:footnotes xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">"
                    + bodies
                    + "</w:footnotes>"
                )
            )
        }
if !endnotes.isEmpty {
            parts[0].1 =
                parts[0].1
                    .replacingOccurrences(
                        of: "</Types>",
                        with:
                            "<Override PartName=\"/word/endnotes.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.endnotes+xml\"/></Types>"
                    )

            func revisionRuns(
                _ value: String,
                deletion: Bool
            ) -> String {
                let tag =
                    deletion
                        ? "w:delText"
                        : "w:t"

                let scalars =
                    Array(
                        value.unicodeScalars
                    )

                var result = ""
                var segment = ""
                var index = 0

                func flush() {
                    guard
                        !segment.isEmpty
                    else {
                        return
                    }

                    result +=
                        "<w:r><\(tag) xml:space=\"preserve\">"
                        + xml(segment)
                        + "</\(tag)></w:r>"

                    segment = ""
                }

                while index
                    < scalars.count {
                    let scalar =
                        scalars[index]

                    switch scalar.value {
                    case 0x09:
                        flush()
                        result +=
                            "<w:r><w:tab/></w:r>"

                    case 0x0A,
                         0x2028,
                         0x2029:
                        flush()
                        result +=
                            "<w:r><w:br/></w:r>"

                    case 0x0D:
                        flush()
                        result +=
                            "<w:r><w:br/></w:r>"

                        if index + 1
                            < scalars.count,
                           scalars[index + 1]
                            .value == 0x0A {
                            index += 1
                        }

                    default:
                        if valid(scalar) {
                            segment
                                .unicodeScalars
                                .append(scalar)
                        }
                    }

                    index += 1
                }

                flush()

                return result
            }

            var bodies =
                "<w:endnote w:type=\"separator\" w:id=\"-1\"><w:p><w:r><w:separator/></w:r></w:p></w:endnote><w:endnote w:type=\"continuationSeparator\" w:id=\"0\"><w:p><w:r><w:continuationSeparator/></w:r></w:p></w:endnote>"

            for (index, note)
                in endnotes.enumerated() {

                let reference =
                    "<w:r><w:rPr><w:vertAlign w:val=\"superscript\"/></w:rPr><w:endnoteRef/></w:r>"

                let paragraphs: String

                if let original =
                    note.bodyChangeOriginalText {

                    let author =
                        attribute(
                            note
                                .bodyChangeAuthor
                            ?? NSFullUserName()
                        )

                    let date =
                        attribute(
                            ISO8601DateFormatter()
                                .string(
                                    from:
                                        note
                                            .bodyChangeDate
                                        ?? Date()
                                )
                        )

                    let deleteID =
                        1000
                        + index * 2

                    let insertID =
                        deleteID + 1

                    paragraphs =
                        "<w:p>"
                        + reference
                        + "<w:del w:id=\"\(deleteID)\" w:author=\"\(author)\" w:date=\"\(date)\">"
                        + revisionRuns(
                            original,
                            deletion: true
                        )
                        + "</w:del>"
                        + "<w:ins w:id=\"\(insertID)\" w:author=\"\(author)\" w:date=\"\(date)\">"
                        + revisionRuns(
                            note.text,
                            deletion: false
                        )
                        + "</w:ins>"
                        + "</w:p>"
                } else {
                    paragraphs =
                        note.text
                            .components(
                                separatedBy: "\n"
                            )
                            .enumerated()
                            .map {
                                line,
                                value in

                                "<w:p>"
                                + (
                                    line == 0
                                        ? reference
                                        : ""
                                )
                                + "<w:r><w:t xml:space=\"preserve\">"
                                + xml(value)
                                + "</w:t></w:r></w:p>"
                            }
                            .joined()
                }

                bodies +=
                    "<w:endnote w:id=\"\(index + 1)\">"
                    + paragraphs
                    + "</w:endnote>"
            }

            parts.append(
                (
                    "word/endnotes.xml",
                    "<w:endnotes xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">"
                    + bodies
                    + "</w:endnotes>"
                )
            )
        }
        var media = writer.media
        var drawings: [WordOpaqueDrawing] = []
        normalized.enumerateAttribute(.boldWriterWordOpaqueDrawing,
            in: NSRange(location: 0, length: normalized.length)) { value, _, _ in
            if let drawing = value as? WordOpaqueDrawing { drawings.append(drawing) }
        }
        try DOCXOpaqueDrawingPackage.append(drawings: drawings, to: &parts, media: &media)
        return ZipArchiveWriter.archive(parts.map { ZipEntry(path: $0.0, data: Data(("<?xml version=\"1.0\" encoding=\"UTF-8\"?>" + $0.1).utf8)) } + media)
    }

    private struct Writer {
        let text: NSAttributedString
        let settings: PageSettings
        let sections: [DocumentSection]
        let notes: [Footnote]
        let endnotes: [Endnote]
        let comments: [DocumentComment]
        let bookmarks: [DocumentBookmark]
        let floatingImages: [FloatingImage]
        var namedStyles: [NamedStyleDefinition] = []
        var links: [String] = []
        var media: [ZipEntry] = []
        var numbers: [(ordered: Bool, start: Int)] = []
        var current: (
            ordered: Bool,
            id: Int,
            next: Int,
            native: ObjectIdentifier?
        )?

        var revisionIDs: [UUID: Int] = [:]
        var emittedFloatingImageIDs: Set<UUID> = []

        var ns: NSString { text.string as NSString }

        mutating func document() throws -> String {
            let tables =
                try Tables.models(
                    in:
                        text
                )

            let ranges =
                paragraphRanges(
                    text.string
                )

            let sectionEnds =
                Dictionary(
                    uniqueKeysWithValues:
                        (1..<sections.count)
                            .map {
                                index in

                                (
                                    sections[index]
                                        .location,
                                    index - 1
                                )
                            }
                )

            var emittedSectionEnds:
                Set<Int> = []

            var blocks = ""
            var index = 0

            while index < ranges.count {
                if let table =
                    tables.first(
                        where: {
                            $0.range.location
                                == ranges[index].location
                        }
                    ) {

                    current = nil

                    blocks +=
                        try structuredTable(
                            table
                        )

                    while index < ranges.count
                        && ranges[index].location
                            < NSMaxRange(
                                table.range
                            ) {

                        index += 1
                    }

                    if index < ranges.count,
                       sectionEnds[
                            ranges[index]
                                .location
                       ] != nil {

                        throw WriterError.message(
                            "A Word section boundary immediately "
                            + "after a structured table cannot yet "
                            + "be exported without changing the "
                            + "document text."
                        )
                    }

                } else if isLegacyTableStart(
                    at:
                        index,
                    ranges:
                        ranges
                ) {

                    current = nil

                    var rows:
                        [NSRange] = []

                    while index < ranges.count,
                          isTableRow(
                            ranges[index]
                          ) {

                        rows.append(
                            ranges[index]
                        )

                        index += 1
                    }

                    blocks +=
                        try table(
                            rows
                        )

                    if index < ranges.count,
                       sectionEnds[
                            ranges[index]
                                .location
                       ] != nil {

                        throw WriterError.message(
                            "A Word section boundary immediately "
                            + "after a legacy table cannot yet be "
                            + "exported without changing the "
                            + "document text."
                        )
                    }

                } else {
                    let range =
                        ranges[index]

                    let nextLocation =
                        index + 1
                            < ranges.count
                        ? ranges[index + 1]
                            .location
                        : text.length

                    let endingSection =
                        sectionEnds[
                            nextLocation
                        ]

                    if endingSection != nil {
                        emittedSectionEnds.insert(
                            nextLocation
                        )
                    }

                    blocks +=
                        try paragraph(
                            range,
                            endingSection:
                                endingSection
                        )

                    index += 1
                }
            }

            let unplaced = floatingImages.filter { !emittedFloatingImageIDs.contains($0.id) }
            if !unplaced.isEmpty {
                guard ranges.isEmpty else {
                    throw WriterError.message("A floating image's logical text anchor does not fall inside an exportable Word paragraph. DOCX export stopped instead of moving that image to a different paragraph.")
                }
                var emptyParagraphImages = ""
                for image in unplaced { emptyParagraphImages += try floatingDrawing(image) }
                blocks += "<w:p><w:pPr></w:pPr>\(emptyParagraphImages)</w:p>"
            }

            let expectedSectionEnds =
                Set(
                    sectionEnds.keys
                )

            guard
                emittedSectionEnds
                    == expectedSectionEnds
            else {
                throw WriterError.message(
                    "A document section boundary does not fall "
                    + "on a paragraph boundary that Word can "
                    + "export safely."
                )
            }

            let finalPage =
                sections.last?
                    .page
                ?? settings

            return
                "<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><w:body>"
                + blocks
                + sectionPropertiesXML(
                    finalPage,
                    sectionIndex:
                        max(
                            0,
                            sections.count - 1
                        )
                )
                + "</w:body></w:document>"
        }

        private func sectionPropertiesXML(
            _ page: PageSettings,
            sectionIndex: Int
        ) -> String {
            let size =
                page.pageSize

            let orientation =
                page.landscape
                    ? " w:orient=\"landscape\""
                    : ""

            var properties = ""

            if hasHeader(
                page
            ) {
                properties +=
                    "<w:headerReference w:type=\"default\" r:id=\""
                    + headerRelationshipID(
                        sectionIndex:
                            sectionIndex,
                        even:
                            false
                    )
                    + "\"/>"
            }

            if hasFooter(
                page
            ) {
                properties +=
                    "<w:footerReference w:type=\"default\" r:id=\""
                    + footerRelationshipID(
                        sectionIndex:
                            sectionIndex,
                        even:
                            false
                    )
                    + "\"/>"
            }

            if hasEvenHeader(
                page
            ) {
                properties +=
                    "<w:headerReference w:type=\"even\" r:id=\""
                    + headerRelationshipID(
                        sectionIndex:
                            sectionIndex,
                        even:
                            true
                    )
                    + "\"/>"
            }

            if hasEvenFooter(
                page
            ) {
                properties +=
                    "<w:footerReference w:type=\"even\" r:id=\""
                    + footerRelationshipID(
                        sectionIndex:
                            sectionIndex,
                        even:
                            true
                    )
                    + "\"/>"
            }

            if hasFirstHeader(
                page
            ) {
                properties +=
                    "<w:headerReference w:type=\"first\" r:id=\""
                    + firstHeaderRelationshipID(
                        sectionIndex:
                            sectionIndex
                    )
                    + "\"/>"
            }

            if hasFirstFooter(
                page
            ) {
                properties +=
                    "<w:footerReference w:type=\"first\" r:id=\""
                    + firstFooterRelationshipID(
                        sectionIndex:
                            sectionIndex
                    )
                    + "\"/>"
            }

            if (
                page.hidesHeaderFooterOnFirstPage
                    || page.hasDistinctFirstPageHeaderFooter
            )
                && (
                    hasHeader(page)
                    || hasFooter(page)
                    || hasEvenHeader(page)
                    || hasEvenFooter(page)
                    || hasFirstHeader(page)
                    || hasFirstFooter(page)
                ) {

                properties +=
                    "<w:titlePg/>"
            }

            // Word stores the section-break type on the sectPr
            // that ends the PRECEDING section. BOLD stores breakType
            // on the section that STARTS after that boundary.
            let followingSectionIndex =
                sectionIndex + 1

            let breakType =
                sections.indices.contains(
                    followingSectionIndex
                )
                ? sections[
                    followingSectionIndex
                ]
                .effectiveBreakType
                : .nextPage

            properties +=
                "<w:type w:val=\""
                + breakType.rawValue
                + "\"/>"

            if sections.indices.contains(
                sectionIndex
            ) {
                let numberingPage =
                    sections[
                        sectionIndex
                    ]
                    .page

                var attributes =
                    ""

                if let start =
                    numberingPage
                        .pageNumberStart {

                    attributes +=
                        " w:start=\""
                        + String(
                            max(
                                1,
                                start
                            )
                        )
                        + "\""
                }

                if let format =
                    numberingPage
                        .pageNumberFormat?
                        .trimmingCharacters(
                            in:
                                .whitespacesAndNewlines
                        ),
                   !format.isEmpty {

                    attributes +=
                        " w:fmt=\""
                        + attribute(
                            format
                        )
                        + "\""
                }

                if !attributes.isEmpty {
                    properties +=
                        "<w:pgNumType"
                        + attributes
                        + "/>"
                }
            }


            if page.columnCount != nil
                || page.columnSpacing != nil
                || page.effectiveColumnCount > 1 {

                properties +=
                    "<w:cols w:num=\""
                    + String(
                        page.effectiveColumnCount
                    )
                    + "\" w:space=\""
                    + String(
                        twips(
                            page.effectiveColumnSpacing
                        )
                    )
                    + "\"/>"
            }

            if let verticalAlignment =
                page.verticalPageAlignment {

                properties +=
                    "<w:vAlign w:val=\""
                    + verticalAlignment.rawValue
                    + "\"/>"
            }

            properties +=
                "<w:pgSz w:w=\"\(twips(size.width))\" w:h=\"\(twips(size.height))\"\(orientation)/>"

            var pageMargins =
                "<w:pgMar w:top=\"\(twips(page.topMargin))\" w:right=\"\(twips(page.rightMargin))\" w:bottom=\"\(twips(page.bottomMargin))\" w:left=\"\(twips(page.leftMargin))\""

            if let gutter =
                page.gutter {

                pageMargins +=
                    " w:gutter=\""
                    + String(
                        twips(
                            gutter
                        )
                    )
                    + "\""
            }

            if let headerDistance =
                page.headerDistance {

                pageMargins +=
                    " w:header=\""
                    + String(
                        twips(
                            headerDistance
                        )
                    )
                    + "\""
            }

            if let footerDistance =
                page.footerDistance {

                pageMargins +=
                    " w:footer=\""
                    + String(
                        twips(
                            footerDistance
                        )
                    )
                    + "\""
            }

            pageMargins +=
                "/>"

            properties +=
                pageMargins

            return
                "<w:sectPr>"
                + properties
                + "</w:sectPr>"
        }

        func isLegacyTableStart(
            at index: Int,
            ranges: [NSRange]
        ) -> Bool {
            guard
                index >= 0,
                index + 1 < ranges.count,
                isTableRow(ranges[index]),
                isTableRow(ranges[index + 1])
            else {
                return false
            }

            return true
        }

        func isTableRow(_ range: NSRange) -> Bool {
            let value = ns.substring(with: range)
            guard value.contains("\t") else { return false }
            // TextKit list markers commonly use tabs too; they are not table cells.
            let style = paragraphAttributes(range)[.paragraphStyle] as? NSParagraphStyle
            // Aligned/leader tabs (notably TOC page numbers) are paragraph
            // layout, not an implicit table. Explicit native tables use models.
            if style?.tabStops.contains(where: { $0.alignment != .left }) == true { return false }
            return listItem(value, style: style) == nil
        }

        func paragraphAttributes(_ range: NSRange) -> [NSAttributedString.Key: Any] {
            guard range.length > 0 else { return [:] }
            let units = Array(ns.substring(with: range).utf16)
            let offset = units.firstIndex { ![UInt16(0x0c), 0x20, 0x09].contains($0) } ?? 0
            return text.attributes(at: range.location + offset, effectiveRange: nil)
        }

        mutating func structuredTable(_ table: WriterTable) throws -> String {
            let available = max(72, settings.pageSize.width - settings.leftMargin - settings.rightMargin)
            let widths = table.widths.map { twips(available * $0 / table.widths.reduce(0, +)) }
            let grid = widths.map { "<w:gridCol w:w=\"\($0)\"/>" }.joined()
            let borders = ["top", "left", "bottom", "right", "insideH", "insideV"].map { "<w:\($0) w:val=\"single\" w:sz=\"4\" w:color=\"808080\"/>" }.joined()
            var result = "<w:tbl><w:tblPr><w:tblW w:w=\"\(twips(available))\" w:type=\"dxa\"/><w:tblLayout w:type=\"fixed\"/><w:tblBorders>\(borders)</w:tblBorders><w:tblCellMar><w:top w:w=\"120\" w:type=\"dxa\"/><w:left w:w=\"120\" w:type=\"dxa\"/><w:bottom w:w=\"120\" w:type=\"dxa\"/><w:right w:w=\"120\" w:type=\"dxa\"/></w:tblCellMar></w:tblPr><w:tblGrid>\(grid)</w:tblGrid>"
            let cells = try Tables.records(in: text).filter { $0.tableID == table.id }
            let bySlot = Dictionary(uniqueKeysWithValues: cells.map { ($0.row * table.columns + $0.column, $0) })
            var owners = Array(repeating: -1, count: table.rows * table.columns)
            for cell in cells {
                let origin = cell.row * table.columns + cell.column
                for coveredRow in cell.row..<(cell.row + cell.effectiveRowSpan) {
                    for coveredColumn in cell.column..<(cell.column + cell.effectiveColumnSpan) {
                        owners[coveredRow * table.columns + coveredColumn] = origin
                    }
                }
            }
            for row in 0..<table.rows {
                var rowProperties = ""
                if row == 0 && table.header { rowProperties += "<w:tblHeader/>" }
                if table.rowCantSplit[row] { rowProperties += "<w:cantSplit/>" }
                result += "<w:tr>" + (rowProperties.isEmpty ? "" : "<w:trPr>" + rowProperties + "</w:trPr>")
                var column = 0
                while column < table.columns {
                    let owner = owners[row * table.columns + column]
                    guard let cell = bySlot[owner] else { throw WriterError.message("A merged table cell is missing.") }
                    if cell.column != column { column += 1; continue }
                    let spanWidth = widths[column..<(column + cell.effectiveColumnSpan)].reduce(0, +)
                    let span = cell.effectiveColumnSpan > 1 ? "<w:gridSpan w:val=\"\(cell.effectiveColumnSpan)\"/>" : ""
                    let merge = cell.effectiveRowSpan > 1
                        ? "<w:vMerge w:val=\"\(row == cell.row ? "restart" : "continue")\"/>" : ""
                    let verticalAlignment = row == cell.row
                        ? (cell.verticalAlignment.map { "<w:vAlign w:val=\"\($0)\"/>" } ?? "")
                        : ""
                    result += "<w:tc><w:tcPr><w:tcW w:w=\"\(spanWidth)\" w:type=\"dxa\"/>" + span + merge + verticalAlignment + (row == 0 && table.header ? "<w:shd w:fill=\"E8E8E8\"/>" : "") + "</w:tcPr>"
                    if row == cell.row {
                        let content = ns.substring(with: NSRange(location: cell.location, length: cell.length - 1))
                        let nested = table.nestedTables[row][column]
                        var emittedNested = 0
                        for range in paragraphRanges(content) {
                            if emittedNested < nested.count,
                               range.location == nested[emittedNested].offset,
                               (content as NSString).substring(with: range).trimmingCharacters(in: .newlines) == NestedTableAnchor.placeholder {
                                result += nested[emittedNested].table.xml
                                emittedNested += 1
                            } else {
                                result += try paragraph(NSRange(location: cell.location + range.location, length: range.length), lists: true)
                            }
                        }
                        guard emittedNested == nested.count else {
                            throw WriterError.message("A nested table placeholder is malformed. DOCX export was stopped.")
                        }
                    } else {
                        result += "<w:p/>"
                    }
                    result += "</w:tc>"
                    column += cell.effectiveColumnSpan
                }
                result += "</w:tr>"
            }
            return result + "</w:tbl>"
        }

        mutating func table(_ rows: [NSRange]) throws -> String {
            let columns = rows.map { ns.substring(with: $0).components(separatedBy: "\t").count }.max() ?? 1
            let available = max(72, settings.pageSize.width - settings.leftMargin - settings.rightMargin)
            let width = twips(available / Double(columns))
            let grid = String(repeating: "<w:gridCol w:w=\"\(width)\"/>", count: columns)
            let borders = ["top", "left", "bottom", "right", "insideH", "insideV"].map { "<w:\($0) w:val=\"single\" w:sz=\"4\" w:color=\"B7C2CA\"/>" }.joined()
            var result = "<w:tbl><w:tblPr><w:tblW w:w=\"0\" w:type=\"auto\"/><w:tblBorders>\(borders)</w:tblBorders></w:tblPr><w:tblGrid>\(grid)</w:tblGrid>"
            for row in rows {
                var location = row.location
                let cells = ns.substring(with: row).components(separatedBy: "\t")
                result += "<w:tr>"
                for column in 0..<columns {
                    let length = column < cells.count ? (cells[column] as NSString).length : 0
                    let range = NSRange(location: min(location, text.length), length: length)
                    result += "<w:tc><w:tcPr><w:tcW w:w=\"\(width)\" w:type=\"dxa\"/></w:tcPr>\(try paragraph(range, lists: false))</w:tc>"
                    if column < cells.count { location += length + 1 }
                }
                result += "</w:tr>"
            }
            return result + "</w:tbl>"
        }

        mutating func paragraph(
            _ range: NSRange,
            lists: Bool = true,
            endingSection: Int? = nil
        ) throws -> String {
            let value = ns.substring(with: range)
            let attributes = paragraphAttributes(range)
            let style = attributes[.paragraphStyle] as? NSParagraphStyle
            var content = range
            var properties = ""
            if let wordStyle =
                attributes[
                    .boldWriterParagraphStyle
                ] as? WordParagraphStyle,
               !wordStyle.styleID.isEmpty {

                properties +=
                    "<w:pStyle w:val=\""
                    + attribute(
                        wordStyle.styleID
                    )
                    + "\"/>"

            } else if let raw =
                attributes[
                    .boldWriterStyle
                ] as? String,
                      let named =
                WriterStyle(
                    rawValue:
                        raw
                ) {

                properties +=
                    "<w:pStyle w:val=\""
                    + attribute(
                        named.rawValue
                            .replacingOccurrences(
                                of:
                                    " ",
                                with:
                                    ""
                            )
                    )
                    + "\"/>"
            }
            if lists, let item = listItem(value, style: style) {
                let id: Int
                let ordinal: Int
                if let previous = current, previous.ordered == item.ordered, previous.native == item.native,
                   !item.ordered || item.number == nil || item.number == previous.next {
                    id = previous.id
                    ordinal = item.number ?? previous.next
                } else {
                    ordinal = max(1, item.number ?? item.start)
                    numbers.append((item.ordered, ordinal)); id = numbers.count
                }
                current = (item.ordered, id, ordinal == Int.max ? Int.max : ordinal + 1, item.native)
                properties += "<w:numPr><w:ilvl w:val=\"0\"/><w:numId w:val=\"\(id)\"/></w:numPr>"
                content.location += item.prefix; content.length -= item.prefix
            } else { current = nil }
            if let style {
                let alignment: String
                switch style.alignment {
                case .center: alignment = "center"
                case .right: alignment = "right"
                case .justified: alignment = "both"
                default: alignment = "left"
                }
                properties += "<w:jc w:val=\"\(alignment)\"/>"
                if style.headIndent != 0 || style.firstLineHeadIndent != 0 || style.tailIndent < 0 {
                    let first = style.firstLineHeadIndent - style.headIndent
                    properties += "<w:ind w:left=\"\(twips(style.headIndent))\" w:right=\"\(twips(max(0, -style.tailIndent)))\" \(first < 0 ? "w:hanging" : "w:firstLine")=\"\(twips(abs(first)))\"/>"
                }
                let defaultTabs = NSParagraphStyle.default.tabStops
                let hasCustomTabs = style.tabStops.count != defaultTabs.count
                    || zip(style.tabStops, defaultTabs).contains { tab, standard in
                        tab.alignment != standard.alignment || abs(tab.location - standard.location) > 0.01
                    }
                let tabStops = hasCustomTabs
                    ? style.tabStops.filter { $0.location.isFinite && $0.location >= 0 }
                    : []
                if !tabStops.isEmpty {
                    let tabs = tabStops.map { tab -> String in
                        let alignment: String
                        switch tab.alignment {
                        case .right: alignment = "right"
                        case .center: alignment = "center"
                        default: alignment = "left"
                        }
                        return "<w:tab w:val=\"\(alignment)\" w:pos=\"\(twips(tab.location))\"/>"
                    }.joined()
                    properties += "<w:tabs>\(tabs)</w:tabs>"
                }
                var spacing =
                    "<w:spacing w:before=\"\(twips(style.paragraphSpacingBefore))\""
                    + " w:after=\"\(twips(style.paragraphSpacing))\""

                if style.minimumLineHeight > 0,
                   style.maximumLineHeight > 0,
                   abs(
                        style.minimumLineHeight
                        - style.maximumLineHeight
                   ) < 0.01 {

                    spacing +=
                        " w:line=\"\(twips(style.minimumLineHeight))\""
                        + " w:lineRule=\"exact\""

                } else if style.lineHeightMultiple > 0,
                          abs(
                            style.lineHeightMultiple - 1
                          ) > 0.001 {

                    let wordLine =
                        Int(
                            (
                                240
                                * style.lineHeightMultiple
                            )
                            .rounded()
                        )

                    spacing +=
                        " w:line=\"\(max(1, wordLine))\""
                        + " w:lineRule=\"auto\""
                }

                spacing += "/>"
                properties += spacing
            }
            if attributes[.boldWriterKeepWithNext] as? Bool == true {
                properties += "<w:keepNext/>"
            }

            if attributes[.boldWriterKeepLinesTogether] as? Bool == true {
                properties += "<w:keepLines/>"
            }

            if attributes[.boldWriterPageBreakBefore] as? Bool == true {
                properties += "<w:pageBreakBefore/>"
            }

            if let widowControl =
                attributes[
                    .boldWriterWidowControl
                ] as? Bool {

                properties +=
                    widowControl
                        ? "<w:widowControl/>"
                        : "<w:widowControl w:val=\"0\"/>"
            }

            let bidi = (attributes[.boldWriterParagraphBidi] as? Bool)
                ?? (style?.baseWritingDirection == .rightToLeft ? true
                    : style?.baseWritingDirection == .leftToRight ? false : nil)
            if let bidi {

                properties +=
                    bidi
                        ? "<w:bidi/>"
                        : "<w:bidi w:val=\"0\"/>"
            }

            if let textDirection =
                attributes[
                    .boldWriterTextDirection
                ] as? String,
               !textDirection.isEmpty {

                properties +=
                    "<w:textDirection w:val=\""
                    + attribute(
                        textDirection
                    )
                    + "\"/>"
            }

            if let contextualSpacing =
                attributes[
                    .boldWriterContextualSpacing
                ] as? Bool {

                properties +=
                    contextualSpacing
                        ? "<w:contextualSpacing/>"
                        : "<w:contextualSpacing w:val=\"0\"/>"
            }

            if let suppressLineNumbers =
                attributes[
                    .boldWriterSuppressLineNumbers
                ] as? Bool {

                properties +=
                    suppressLineNumbers
                        ? "<w:suppressLineNumbers/>"
                        : "<w:suppressLineNumbers w:val=\"0\"/>"
            }

            if let mirrorIndents =
                attributes[
                    .boldWriterMirrorIndents
                ] as? Bool {

                properties +=
                    mirrorIndents
                        ? "<w:mirrorIndents/>"
                        : "<w:mirrorIndents w:val=\"0\"/>"
            }

            if let borders =
                attributes[
                    .boldWriterParagraphBorders
                ] as? WordParagraphBorders,
               !borders.isEmpty {

                func borderXML(
                    _ name: String,
                    _ border: WordParagraphBorder?
                ) -> String {
                    guard
                        let border
                    else {
                        return ""
                    }

                    var values =
                        " w:val=\""
                        + attribute(
                            border.style
                        )
                        + "\""

                    if let size =
                        border.size {

                        values +=
                            " w:sz=\""
                            + String(
                                max(
                                    0,
                                    size
                                )
                            )
                            + "\""
                    }

                    if let space =
                        border.space {

                        values +=
                            " w:space=\""
                            + String(
                                max(
                                    0,
                                    space
                                )
                            )
                            + "\""
                    }

                    if let color =
                        border.color,
                       !color.isEmpty {

                        values +=
                            " w:color=\""
                            + attribute(
                                color.uppercased()
                            )
                            + "\""
                    }

                    return
                        "<w:"
                        + name
                        + values
                        + "/>"
                }

                let values =
                    borderXML(
                        "top",
                        borders.top
                    )
                    + borderXML(
                        "left",
                        borders.left
                    )
                    + borderXML(
                        "bottom",
                        borders.bottom
                    )
                    + borderXML(
                        "right",
                        borders.right
                    )
                    + borderXML(
                        "between",
                        borders.between
                    )

                if !values.isEmpty {
                    properties +=
                        "<w:pBdr>"
                        + values
                        + "</w:pBdr>"
                }
            }

            if let shading =
                attributes[
                    .boldWriterParagraphShading
                ] as? WordParagraphShading {

                func wordColor(
                    _ raw: String
                ) -> String {
                    raw.lowercased()
                        == "auto"
                        ? "auto"
                        : raw.uppercased()
                }

                var shadingAttributes =
                    " w:val=\""
                    + attribute(
                        shading.value
                    )
                    + "\""

                if let color =
                    shading.color,
                   !color.isEmpty {

                    shadingAttributes +=
                        " w:color=\""
                        + attribute(
                            wordColor(
                                color
                            )
                        )
                        + "\""
                }

                if let fill =
                    shading.fill,
                   !fill.isEmpty {

                    shadingAttributes +=
                        " w:fill=\""
                        + attribute(
                            wordColor(
                                fill
                            )
                        )
                        + "\""
                }

                properties +=
                    "<w:shd"
                    + shadingAttributes
                    + "/>"
            }

            if let endingSection {
                properties +=
                    sectionPropertiesXML(
                        sections[
                            endingSection
                        ].page,
                        sectionIndex:
                            endingSection
                    )
            }

            return "<w:p><w:pPr>\(properties)</w:pPr>\(try runs(content))</w:p>"
        }

        mutating func runs(
            _ range: NSRange
        ) throws -> String {
            func wordVMLXMLAttribute(
                _ name: String,
                _ value: String?
            ) -> String {
                guard
                    let value,
                    !value.isEmpty
                else {
                    return ""
                }

                let escaped =
                    value
                        .replacingOccurrences(
                            of: "&",
                            with: "&amp;"
                        )
                        .replacingOccurrences(
                            of: "<",
                            with: "&lt;"
                        )
                        .replacingOccurrences(
                            of: ">",
                            with: "&gt;"
                        )
                        .replacingOccurrences(
                            of: "\"",
                            with: "&quot;"
                        )

                return
                    " "
                    + name
                    + "=\""
                    + escaped
                    + "\""
            }

            func wordVMLText(
                _ value: String
            ) -> String {
                value
                    .replacingOccurrences(
                        of: "&",
                        with: "&amp;"
                    )
                    .replacingOccurrences(
                        of: "<",
                        with: "&lt;"
                    )
                    .replacingOccurrences(
                        of: ">",
                        with: "&gt;"
                    )
            }

            func wordVMLShapeXML(
                _ shape: WordVMLShape,
                content: String
            ) -> String {
                let kind =
                    shape.shapeKind
                        .lowercased()

                guard
                    [
                        "rect",
                        "roundrect",
                        "oval"
                    ]
                    .contains(kind)
                else {
                    return ""
                }

                let shapeAttributes =
                    wordVMLXMLAttribute(
                        "id",
                        shape.shapeID
                    )
                    + wordVMLXMLAttribute(
                        "style",
                        shape.style
                    )
                    + wordVMLXMLAttribute(
                        "fillcolor",
                        shape.fillColor
                    )
                    + wordVMLXMLAttribute(
                        "strokecolor",
                        shape.strokeColor
                    )
                    + wordVMLXMLAttribute(
                        "strokeweight",
                        shape.strokeWeight
                    )

                let textboxAttributes =
                    wordVMLXMLAttribute(
                        "inset",
                        shape.textBoxInset
                    )

                return
                    "<w:r><w:pict>"
                    + "<v:"
                    + kind
                    + " xmlns:v=\"urn:schemas-microsoft-com:vml\""
                    + shapeAttributes
                    + ">"
                    + "<v:textbox"
                    + textboxAttributes
                    + ">"
                    + "<w:txbxContent>"
                    + "<w:p><w:r><w:t xml:space=\"preserve\">"
                    + wordVMLText(content)
                    + "</w:t></w:r></w:p>"
                    + "</w:txbxContent>"
                    + "</v:textbox>"
                    + "</v:"
                    + kind
                    + ">"
                    + "</w:pict></w:r>"
            }


            var result = ""

            var rawSpans:
                [(
                    [NSAttributedString.Key: Any],
                    NSRange
                )] = []

            text.enumerateAttributes(
                in:
                    range
            ) {
                attributes,
                subrange,
                _ in

                rawSpans.append(
                    (
                        attributes,
                        subrange
                    )
                )
            }

            let boundaries =
                Set(
                    comments.flatMap {
                        comment in

                        [
                            comment.location,
                            comment.location
                                + comment.length
                        ]
                    }
                    + bookmarks.flatMap { [$0.location, $0.location + $0.length] }
                    + floatingImages.map { max(0, $0.anchorLocation) }
                )

            var spans:
                [(
                    [NSAttributedString.Key: Any],
                    NSRange
                )] = []

            for (
                attributes,
                subrange
            ) in rawSpans {
                let start =
                    subrange.location

                let end =
                    NSMaxRange(
                        subrange
                    )

                let cuts =
                    boundaries
                        .filter {
                            $0 > start
                                && $0 < end
                        }
                        .sorted()

                var cursor =
                    start

                for cut in cuts {
                    spans.append(
                        (
                            attributes,
                            NSRange(
                                location:
                                    cursor,
                                length:
                                    cut - cursor
                            )
                        )
                    )

                    cursor =
                        cut
                }

                if cursor < end {
                    spans.append(
                        (
                            attributes,
                            NSRange(
                                location:
                                    cursor,
                                length:
                                    end - cursor
                            )
                        )
                    )
                }
            }

            for (
                attributes,
                subrange
            ) in spans {
                let anchoredHere = floatingImages.filter { max(0, $0.anchorLocation) == subrange.location }
                for image in anchoredHere {
                    result += try floatingDrawing(image)
                }
                result +=
                    bookmarkBoundaryXML(
                        at:
                            subrange.location
                    )

                result +=
                    commentBoundaryXML(
                        at:
                            subrange.location
                    )
                let trackedChange =
                    TrackChanges.record(
                        from: attributes[.boldWriterTrackChange],
                        range: subrange
                    )

                if let payload = attributes[.footnote] as? [String: String],
                   let index = notes.firstIndex(where: { $0.id.uuidString == payload["id"] }) {
                    if subrange.location == notes[index].location {
                        var rendered =
                            "<w:r><w:rPr><w:vertAlign w:val=\"superscript\"/></w:rPr><w:footnoteReference w:id=\"\(index + 1)\"/></w:r>"

                        if let trackedChange {
                            rendered =
                                revisionXML(
                                    trackedChange,
                                    content: rendered
                                )
                        }

                        result += rendered
                    }
                    continue
                }

                if let payload = attributes[.endnote] as? [String: String],
                   let index = endnotes.firstIndex(where: { $0.id.uuidString == payload["id"] }) {
                    if subrange.location == endnotes[index].location {
                        var rendered =
                            "<w:r><w:rPr><w:vertAlign w:val=\"superscript\"/></w:rPr><w:endnoteReference w:id=\"\(index + 1)\"/></w:r>"

                        if let trackedChange {
                            rendered =
                                revisionXML(
                                    trackedChange,
                                    content: rendered
                                )
                        }

                        result += rendered
                    }
                    continue
                }

                var properties = ""

                if let characterStyle =
                    attributes[
                        .boldWriterCharacterStyle
                    ] as? WordCharacterStyle,
                   !characterStyle.styleID.isEmpty {

                    properties +=
                        "<w:rStyle w:val=\""
                        + attribute(
                            characterStyle.styleID
                        )
                        + "\"/>"
                }
                let nativeFont =
                    attributes[
                        .font
                    ] as? NSFont

                let wordFonts =
                    attributes[
                        .boldWriterRunFonts
                    ] as? WordRunFonts

                if nativeFont != nil
                    || wordFonts != nil {

                    let rawFamily =
                        nativeFont?
                            .familyName
                        ?? "Helvetica"

                    let fallbackFamily =
                        rawFamily.hasPrefix(".")
                            ? "Helvetica"
                            : rawFamily

                    func fontAttribute(
                        _ name: String,
                        _ value: String?
                    ) -> String {
                        guard
                            let value,
                            !value.isEmpty
                        else {
                            return ""
                        }

                        return
                            " w:"
                            + name
                            + "=\""
                            + attribute(
                                value
                            )
                            + "\""
                    }

                    var fontValues = ""

                    if let wordFonts {
                        fontValues += fontAttribute("ascii", wordFonts.ascii)
                        fontValues += fontAttribute("hAnsi", wordFonts.hAnsi)
                        fontValues += fontAttribute("eastAsia", wordFonts.eastAsia)
                        fontValues += fontAttribute("cs", wordFonts.complexScript)
                        fontValues += fontAttribute("asciiTheme", wordFonts.asciiTheme)
                        fontValues += fontAttribute("hAnsiTheme", wordFonts.hAnsiTheme)
                        fontValues += fontAttribute("eastAsiaTheme", wordFonts.eastAsiaTheme)
                        fontValues += fontAttribute("cstheme", wordFonts.complexScriptTheme)
                        fontValues += fontAttribute("hint", wordFonts.hint)
                    }

                    if fontValues.isEmpty,
                       nativeFont != nil {

                        fontValues +=
                            fontAttribute(
                                "ascii",
                                fallbackFamily
                            )

                        fontValues +=
                            fontAttribute(
                                "hAnsi",
                                fallbackFamily
                            )
                    }

                    if !fontValues.isEmpty {
                        properties +=
                            "<w:rFonts"
                            + fontValues
                            + "/>"
                    }
                }

                if let font = nativeFont {
                    let traits =
                        NSFontManager.shared
                            .traits(
                                of:
                                    font
                            )

                    properties +=
                        "<w:sz w:val=\""
                        + String(
                            Int(
                                (
                                    font.pointSize
                                    * 2
                                )
                                .rounded()
                            )
                        )
                        + "\"/>"

                    if traits.contains(
                        .boldFontMask
                    ) {
                        properties += "<w:b/>"
                    }

                    if traits.contains(
                        .italicFontMask
                    ) {
                        properties += "<w:i/>"
                    }
                }
                if let rawUnderline =
                    attributes[
                        .boldWriterUnderlineVariant
                    ] as? String,
                   !rawUnderline.isEmpty {

                    properties +=
                        "<w:u w:val=\""
                        + attribute(
                            rawUnderline
                        )
                        + "\"/>"
                } else if let underline =
                    attributes[
                        .underlineStyle
                    ] as? NSNumber,
                          underline.intValue != 0 {

                    let style =
                        NSUnderlineStyle(
                            rawValue:
                                underline.intValue
                        )

                    let wordValue:
                        String

                    if style.contains(
                        .double
                    ) {
                        wordValue = "double"
                    } else if style.contains(
                        .patternDot
                    ) {
                        wordValue = "dotted"
                    } else if style.contains(
                        .patternDash
                    ) {
                        wordValue = "dash"
                    } else if style.contains(
                        .patternDashDot
                    ) {
                        wordValue = "dotDash"
                    } else if style.contains(
                        .patternDashDotDot
                    ) {
                        wordValue = "dotDotDash"
                    } else {
                        wordValue = "single"
                    }

                    properties +=
                        "<w:u w:val=\""
                        + wordValue
                        + "\"/>"
                }
                if let strike = attributes[.strikethroughStyle] as? Int { properties += strike != 0 ? "<w:strike/>":"<w:strike w:val=\"0\"/>" }
                if let color = attributes[.foregroundColor] as? NSColor, let hex = colorHex(color) { properties += "<w:color w:val=\"\(hex)\"/>" }
                if let smallCaps =
                    attributes[
                        .boldWriterSmallCaps
                    ] as? Bool {

                    properties +=
                        smallCaps
                            ? "<w:smallCaps/>"
                            : "<w:smallCaps w:val=\"0\"/>"
                }

                if let hidden =
                    attributes[
                        .boldWriterHiddenText
                    ] as? Bool {

                    properties +=
                        hidden
                            ? "<w:vanish/>"
                            : "<w:vanish w:val=\"0\"/>"
                }

                if let noProof =
                    attributes[
                        .boldWriterNoProof
                    ] as? Bool {

                    properties +=
                        noProof
                            ? "<w:noProof/>"
                            : "<w:noProof w:val=\"0\"/>"
                }

                if let rtl =
                    attributes[
                        .boldWriterRTL
                    ] as? Bool {

                    properties +=
                        rtl
                            ? "<w:rtl/>"
                            : "<w:rtl w:val=\"0\"/>"
                }

                if let complexScript =
                    attributes[
                        .boldWriterComplexScript
                    ] as? Bool {

                    properties +=
                        complexScript
                            ? "<w:cs/>"
                            : "<w:cs w:val=\"0\"/>"
                }

                if let boldCS =
                    attributes[
                        .boldWriterComplexScriptBold
                    ] as? Bool {

                    properties +=
                        boldCS
                            ? "<w:bCs/>"
                            : "<w:bCs w:val=\"0\"/>"
                }

                if let italicCS =
                    attributes[
                        .boldWriterComplexScriptItalic
                    ] as? Bool {

                    properties +=
                        italicCS
                            ? "<w:iCs/>"
                            : "<w:iCs w:val=\"0\"/>"
                }

                if let sizeCS =
                    attributes[
                        .boldWriterComplexScriptSize
                    ] as? NSNumber {

                    properties +=
                        "<w:szCs w:val=\""
                        + String(
                            max(
                                1,
                                sizeCS.intValue
                            )
                        )
                        + "\"/>"
                }

                if let border =
                    attributes[
                        .boldWriterRunBorder
                    ] as? WordRunBorder {

                    var values =
                        " w:val=\""
                        + attribute(
                            border.style
                        )
                        + "\""

                    if let size =
                        border.size {

                        values +=
                            " w:sz=\""
                            + String(
                                max(
                                    0,
                                    size
                                )
                            )
                            + "\""
                    }

                    if let space =
                        border.space {

                        values +=
                            " w:space=\""
                            + String(
                                max(
                                    0,
                                    space
                                )
                            )
                            + "\""
                    }

                    if let color =
                        border.color,
                       !color.isEmpty {

                        values +=
                            " w:color=\""
                            + attribute(
                                color.lowercased() == "auto"
                                    ? "auto"
                                    : color.uppercased()
                            )
                            + "\""
                    }

                    if let themeColor =
                        border.themeColor,
                       !themeColor.isEmpty {

                        values +=
                            " w:themeColor=\""
                            + attribute(
                                themeColor
                            )
                            + "\""
                    }

                    if let themeTint =
                        border.themeTint,
                       !themeTint.isEmpty {

                        values +=
                            " w:themeTint=\""
                            + attribute(
                                themeTint.uppercased()
                            )
                            + "\""
                    }

                    if let themeShade =
                        border.themeShade,
                       !themeShade.isEmpty {

                        values +=
                            " w:themeShade=\""
                            + attribute(
                                themeShade.uppercased()
                            )
                            + "\""
                    }

                    properties +=
                        "<w:bdr"
                        + values
                        + "/>"
                }

                if let shading =
                    attributes[
                        .boldWriterRunShading
                    ] as? WordRunShading {

                    func wordColor(
                        _ raw: String
                    ) -> String {
                        raw.lowercased()
                            == "auto"
                            ? "auto"
                            : raw.uppercased()
                    }

                    var values =
                        " w:val=\""
                        + attribute(
                            shading.value
                        )
                        + "\""

                    if let color =
                        shading.color,
                       !color.isEmpty {

                        values +=
                            " w:color=\""
                            + attribute(
                                wordColor(
                                    color
                                )
                            )
                            + "\""
                    }

                    if let fill =
                        shading.fill,
                       !fill.isEmpty {

                        values +=
                            " w:fill=\""
                            + attribute(
                                wordColor(
                                    fill
                                )
                            )
                            + "\""
                    }

                    let themeValues: [
                        (
                            String,
                            String?
                        )
                    ] = [
                        (
                            "themeColor",
                            shading.themeColor
                        ),
                        (
                            "themeTint",
                            shading.themeTint
                        ),
                        (
                            "themeShade",
                            shading.themeShade
                        ),
                        (
                            "themeFill",
                            shading.themeFill
                        ),
                        (
                            "themeFillTint",
                            shading.themeFillTint
                        ),
                        (
                            "themeFillShade",
                            shading.themeFillShade
                        )
                    ]

                    for (
                        name,
                        value
                    ) in themeValues {
                        if let value,
                           !value.isEmpty {

                            let rendered =
                                (
                                    name.lowercased()
                                        .contains(
                                            "tint"
                                        )
                                    || name.lowercased()
                                        .contains(
                                            "shade"
                                        )
                                )
                                ? value.uppercased()
                                : value

                            values +=
                                " w:"
                                + name
                                + "=\""
                                + attribute(
                                    rendered
                                )
                                + "\""
                        }
                    }

                    properties +=
                        "<w:shd"
                        + values
                        + "/>"
                } else if let color =
                    attributes[
                        .backgroundColor
                    ] as? NSColor,
                          let hex =
                    colorHex(
                        color
                    ) {

                    properties +=
                        "<w:shd w:val=\"clear\" w:fill=\""
                        + hex
                        + "\"/>"
                }

                if let highlight =
                    attributes[
                        .boldWriterHighlight
                    ] as? String,
                   !highlight.isEmpty {

                    properties +=
                        "<w:highlight w:val=\""
                        + attribute(
                            highlight
                        )
                        + "\"/>"
                }

                if let doubleStrike =
                    attributes[
                        .boldWriterDoubleStrikethrough
                    ] as? Bool {

                    properties +=
                        doubleStrike
                            ? "<w:dstrike/>"
                            : "<w:dstrike w:val=\"0\"/>"
                }

                if let allCaps =
                    attributes[
                        .boldWriterAllCaps
                    ] as? Bool {

                    properties +=
                        allCaps
                            ? "<w:caps/>"
                            : "<w:caps w:val=\"0\"/>"
                }

                if let scale =
                    attributes[
                        .boldWriterCharacterScale
                    ] as? NSNumber {

                    properties +=
                        "<w:w w:val=\""
                        + String(
                            max(
                                1,
                                min(
                                    600,
                                    scale.intValue
                                )
                            )
                        )
                        + "\"/>"
                }

                if let outline =
                    attributes[
                        .boldWriterOutlineText
                    ] as? Bool {

                    properties +=
                        outline
                            ? "<w:outline/>"
                            : "<w:outline w:val=\"0\"/>"
                }

                if let shadow =
                    attributes[
                        .boldWriterShadowText
                    ] as? Bool {

                    properties +=
                        shadow
                            ? "<w:shadow/>"
                            : "<w:shadow w:val=\"0\"/>"
                }

                if let emboss =
                    attributes[
                        .boldWriterEmbossText
                    ] as? Bool {

                    properties +=
                        emboss
                            ? "<w:emboss/>"
                            : "<w:emboss w:val=\"0\"/>"
                }

                if let imprint =
                    attributes[
                        .boldWriterImprintText
                    ] as? Bool {

                    properties +=
                        imprint
                            ? "<w:imprint/>"
                            : "<w:imprint w:val=\"0\"/>"
                }

                if let superscript =
                    attributes[
                        .superscript
                    ] as? NSNumber {

                    let value =
                        superscript.intValue

                    if value > 0 {
                        properties +=
                            "<w:vertAlign w:val=\"superscript\"/>"
                    } else if value < 0 {
                        properties +=
                            "<w:vertAlign w:val=\"subscript\"/>"
                    } else {
                        properties +=
                            "<w:vertAlign w:val=\"baseline\"/>"
                    }
                }

                if let kern =
                    attributes[
                        .kern
                    ] as? NSNumber {

                    let twentieths =
                        Int(
                            (
                                kern.doubleValue
                                * 20
                            )
                            .rounded()
                        )

                    properties +=
                        "<w:spacing w:val=\""
                        + String(
                            twentieths
                        )
                        + "\"/>"
                }

                if let baseline =
                    attributes[
                        .baselineOffset
                    ] as? NSNumber {

                    let halfPoints =
                        Int(
                            (
                                baseline.doubleValue
                                * 2
                            )
                            .rounded()
                        )

                    properties +=
                        "<w:position w:val=\""
                        + String(
                            halfPoints
                        )
                        + "\"/>"
                }

                if let wordLanguage =
                    attributes[
                        .boldWriterWordLanguage
                    ] as? WordLanguage {

                    var values = ""

                    if let value =
                        wordLanguage.value,
                       !value.isEmpty {

                        values +=
                            " w:val=\""
                            + attribute(
                                value
                            )
                            + "\""
                    }

                    if let eastAsia =
                        wordLanguage.eastAsia,
                       !eastAsia.isEmpty {

                        values +=
                            " w:eastAsia=\""
                            + attribute(
                                eastAsia
                            )
                            + "\""
                    }

                    if let bidi =
                        wordLanguage.bidi,
                       !bidi.isEmpty {

                        values +=
                            " w:bidi=\""
                            + attribute(
                                bidi
                            )
                            + "\""
                    }

                    if !values.isEmpty {
                        properties +=
                            "<w:lang"
                            + values
                            + "/>"
                    }

                } else if let language =
                    attributes[
                        .boldWriterLanguage
                    ] as? String,
                          !language.isEmpty {

                    properties +=
                        "<w:lang w:val=\""
                        + attribute(
                            language
                        )
                        + "\"/>"
                }

                if let kernThreshold =
                    attributes[
                        .boldWriterKernThreshold
                    ] as? NSNumber {

                    properties +=
                        "<w:kern w:val=\""
                        + String(
                            max(
                                0,
                                kernThreshold.intValue
                            )
                        )
                        + "\"/>"
                }

                if let emphasis =
                    attributes[
                        .boldWriterEmphasis
                    ] as? String,
                   !emphasis.isEmpty {

                    properties +=
                        "<w:em w:val=\""
                        + attribute(
                            emphasis
                        )
                        + "\"/>"
                }

                if let specVanish =
                    attributes[
                        .boldWriterSpecVanish
                    ] as? Bool {

                    properties +=
                        specVanish
                            ? "<w:specVanish/>"
                            : "<w:specVanish w:val=\"0\"/>"
                }

                if let webHidden =
                    attributes[
                        .boldWriterWebHidden
                    ] as? Bool {

                    properties +=
                        webHidden
                            ? "<w:webHidden/>"
                            : "<w:webHidden w:val=\"0\"/>"
                }

                if let opaqueDrawing = attributes[.boldWriterWordOpaqueDrawing] as? WordOpaqueDrawing {
                    guard ns.substring(with: subrange) == WordOpaqueDrawing.markerText else {
                        throw WriterError.message("A preserved Word drawing marker was edited. Restore the marker or remove it before DOCX export.")
                    }
                    let preserved = try WordOpaqueDrawing.validated(
                        id: opaqueDrawing.id, xml: opaqueDrawing.xml,
                        isRunChild: opaqueDrawing.isRunChild,
                        relationships: opaqueDrawing.relationships, parts: opaqueDrawing.parts
                    )
                    result += preserved.isRunChild ? "<w:r>\(preserved.xml)</w:r>" : preserved.xml
                    continue
                }

                if let wordVMLShape =
                    attributes[
                        .boldWriterWordVMLShape
                    ] as? WordVMLShape {
                    let wordVMLContent =
                        ns.substring(
                            with: subrange
                        )

                    let wordVMLXML =
                        wordVMLShapeXML(
                            wordVMLShape,
                            content: wordVMLContent
                        )

                    guard !wordVMLXML.isEmpty else {
                        throw WriterError.message(
                            "A Word VML shape is unsupported and cannot be exported without changing it."
                        )
                    }

                    result += wordVMLXML
                    continue
                }

                var body = ""
                var segment = ""

                func flush() {
                    guard !segment.isEmpty else { return }

                    let tag =
                        trackedChange?.kind == .deletion
                            ? "w:delText"
                            : "w:t"

                    body +=
                        "<\(tag) xml:space=\"preserve\">"
                        + xml(segment)
                        + "</\(tag)>"

                    segment = ""
                }
                for scalar in ns.substring(with: subrange).unicodeScalars {
                    switch scalar.value {
                    case 0xfffc:
                        flush()
                        guard let attachment = attributes[.attachment] as? NSTextAttachment else {
                            throw WriterError.message("A DOCX image attachment is missing. The document was not changed.")
                        }
                        body += try drawing(attachment, crop: attributes[.boldWriterWordPictureCrop] as? WordPictureCrop, altText: attributes[.boldWriterWordPictureAltText] as? WordPictureAltText)
                    case 0x0c: flush(); body += "<w:br w:type=\"page\"/>"
                    case 0x09: flush(); body += "<w:tab/>"
                    case 0x0a, 0x0d, 0x2028: flush(); body += "<w:br/>"
                    default: if valid(scalar) { segment.unicodeScalars.append(scalar) }
                    }
                }
                flush()
                guard !body.isEmpty else { continue }
                let run =
                    "<w:r><w:rPr>\(properties)</w:rPr>\(body)</w:r>"

                let target =
                    (attributes[.link] as? URL)?.absoluteString
                    ?? attributes[.link] as? String

                var rendered = run

                if let target, !target.isEmpty {
                    if target.hasPrefix("#") {
                        let rawAnchor =
                            String(
                                target.dropFirst()
                            )

                        let wordAnchor =
                            wordBookmarkAnchor(
                                for:
                                    rawAnchor
                            )

                        rendered =
                            "<w:hyperlink w:anchor=\""
                            + attribute(
                                wordAnchor
                            )
                            + "\">"
                            + run
                            + "</w:hyperlink>"
                    } else {
                        if !links.contains(target) {
                            links.append(target)
                        }

                        rendered =
                            "<w:hyperlink r:id=\"rId"
                            + String(
                                (links.firstIndex(of: target) ?? 0)
                                + 3
                            )
                            + "\">"
                            + run
                            + "</w:hyperlink>"
                    }
                }

                if let trackedChange {
                    rendered = revisionXML(
                        trackedChange,
                        content: rendered
                    )
                }

                var fieldPrefix = ""
                var fieldSuffix = ""

                if let field =
                    attributes[
                        .boldWriterField
                    ] as? WordField {

                    var effectiveFieldRange =
                        NSRange(
                            location:
                                NSNotFound,
                            length:
                                0
                        )

                    _ =
                        text.attribute(
                            .boldWriterField,
                            at:
                                subrange.location,
                            longestEffectiveRange:
                                &effectiveFieldRange,
                            in:
                                field.kind == .complex
                                    ? NSRange(location: 0, length: text.length)
                                    : range
                        )

                    // Paragraph terminators are emitted as XML structure, not
                    // runs. Attach cross-paragraph field markers to the first
                    // and last visible run, including fields with blank edges.
                    if field.kind == .complex {
                        let source = text.string as NSString
                        while effectiveFieldRange.length > 0,
                              [10, 13].contains(Int(source.character(at: effectiveFieldRange.location))) {
                            effectiveFieldRange.location += 1
                            effectiveFieldRange.length -= 1
                        }
                        while effectiveFieldRange.length > 0,
                              [10, 13].contains(Int(source.character(at: NSMaxRange(effectiveFieldRange) - 1))) {
                            effectiveFieldRange.length -= 1
                        }
                    }

                    func fieldAttribute(
                        _ name: String,
                        _ value: String?
                    ) -> String {
                        guard
                            let value
                        else {
                            return ""
                        }

                        return
                            " w:"
                            + name
                            + "=\""
                            + attribute(
                                value
                            )
                            + "\""
                    }

                    let startsField =
                        subrange.location
                        == effectiveFieldRange.location

                    let endsField =
                        NSMaxRange(
                            subrange
                        )
                        == NSMaxRange(
                            effectiveFieldRange
                        )

                    if startsField {
                        switch field.kind {
                        case .simple:
                            fieldPrefix =
                                "<w:fldSimple w:instr=\""
                                + attribute(
                                    field.instruction
                                )
                                + "\""
                                + fieldAttribute(
                                    "dirty",
                                    field.dirtyValue
                                )
                                + fieldAttribute(
                                    "fldLock",
                                    field.lockedValue
                                )
                                + ">"

                        case .complex:
                            fieldPrefix =
                                "<w:r><w:fldChar w:fldCharType=\"begin\""
                                + fieldAttribute(
                                    "dirty",
                                    field.dirtyValue
                                )
                                + fieldAttribute(
                                    "fldLock",
                                    field.lockedValue
                                )
                                + "/></w:r>"
                                + "<w:r><w:instrText xml:space=\"preserve\">"
                                + xml(
                                    field.instruction
                                )
                                + "</w:instrText></w:r>"
                                + "<w:r><w:fldChar w:fldCharType=\"separate\"/></w:r>"
                        }
                    }

                    if endsField {
                        switch field.kind {
                        case .simple:
                            fieldSuffix =
                                "</w:fldSimple>"

                        case .complex:
                            fieldSuffix =
                                "<w:r><w:fldChar w:fldCharType=\"end\"/></w:r>"
                        }
                    }
                }

                result +=
                    fieldPrefix
                    + rendered
                    + fieldSuffix
            }

            result +=
                bookmarkBoundaryXML(
                    at:
                        NSMaxRange(
                            range
                        )
                )

            result +=
                commentBoundaryXML(
                    at:
                        NSMaxRange(
                            range
                        )
                )

            if NSMaxRange(range) == text.length {
                for image in floatingImages where max(0, image.anchorLocation) == text.length {
                    result += try floatingDrawing(image)
                }
            }

            return result
        }

        private func bookmarkBoundaryXML(
            at location: Int
        ) -> String {
            var result = ""

            for (index, bookmark) in bookmarks.enumerated() where bookmark.length > 0 && bookmark.location + bookmark.length == location {
                result += "<w:bookmarkEnd w:id=\"\(index)\"/>"
            }
            for (index, bookmark) in bookmarks.enumerated() where bookmark.location == location {
                let name = wordBookmarkName(at: index)
                result += "<w:bookmarkStart w:id=\"\(index)\" w:name=\"\(attribute(name))\"/>"
                if bookmark.length == 0 { result += "<w:bookmarkEnd w:id=\"\(index)\"/>" }
            }

            return result
        }

        private func wordBookmarkAnchor(
            for rawName: String
        ) -> String {
            guard
                let index =
                    bookmarks.firstIndex(
                        where: {
                            $0.name.caseInsensitiveCompare(DocumentBookmarks.normalizedName(rawName)) == .orderedSame
                        }
                    )
            else {
                // Preserve an unresolved internal link as an
                // internal Word anchor. Never reinterpret it as
                // an external URL.
                return rawName
            }

            return wordBookmarkName(
                at:
                    index
            )
        }

        private func wordBookmarkName(at index: Int) -> String {
            // The export entry point normalizes and validates every bookmark
            // name once, including case-insensitive collision suffixes. Reusing
            // it avoids recursively regenerating all previous names per anchor.
            bookmarks[index].name
        }

        private func commentBoundaryXML(
            at location: Int
        ) -> String {
            var result = ""

            // End existing ranges first.
            for (
                index,
                comment
            ) in comments.enumerated()
            where comment.length > 0
                && comment.location
                    + comment.length
                    == location {

                result +=
                    "<w:commentRangeEnd w:id=\"\(index)\"/>"

                result +=
                    "<w:r><w:commentReference w:id=\"\(index)\"/></w:r>"
            }

            // A BOLD point comment becomes a zero-width Word range.
            for (
                index,
                comment
            ) in comments.enumerated()
            where comment.length == 0
                && comment.location
                    == location {

                result +=
                    "<w:commentRangeStart w:id=\"\(index)\"/>"

                result +=
                    "<w:commentRangeEnd w:id=\"\(index)\"/>"

                result +=
                    "<w:r><w:commentReference w:id=\"\(index)\"/></w:r>"
            }

            // Open new non-empty ranges last.
            for (
                index,
                comment
            ) in comments.enumerated()
            where comment.length > 0
                && comment.location
                    == location {

                result +=
                    "<w:commentRangeStart w:id=\"\(index)\"/>"
            }

            return result
        }

        mutating func revisionXML(
            _ revision: TrackChangeRecord,
            content: String
        ) -> String {
            let wordID: Int

            if let existing = revisionIDs[revision.id] {
                wordID = existing
            } else {
                wordID = revisionIDs.count + 1
                revisionIDs[revision.id] = wordID
            }

            let tag =
                revision.kind == .insertion
                    ? "w:ins"
                    : "w:del"

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [
                .withInternetDateTime
            ]

            let date =
                formatter.string(from: revision.date)

            return
                "<\(tag) w:id=\"\(wordID)\" w:author=\""
                + attribute(revision.author)
                + "\" w:date=\""
                + attribute(date)
                + "\">"
                + content
                + "</\(tag)>"
        }

        private func pictureAltAttributes(title: String?, description: String?) -> String {
            var result = ""
            if let title, !title.isEmpty { result += " title=\"\(attribute(title))\"" }
            if let description, !description.isEmpty { result += " descr=\"\(attribute(description))\"" }
            return result
        }

        mutating func drawing(_ attachment: NSTextAttachment, crop: WordPictureCrop? = nil, altText: WordPictureAltText? = nil) throws -> String {
            let image = try DOCXImages.encode(attachment)
            let cropXML: String

            if let crop,
               !crop.isEmpty {
                guard crop.hasValidGeometry else {
                    throw WriterError.message(
                        "A Word picture crop is invalid and cannot be exported without changing it."
                    )
                }

                cropXML =
                    "<a:srcRect"
                    + " l=\"\(crop.left)\""
                    + " t=\"\(crop.top)\""
                    + " r=\"\(crop.right)\""
                    + " b=\"\(crop.bottom)\""
                    + "/>"
            } else {
                cropXML = ""
            }

            let altAttributes = pictureAltAttributes(title: altText?.title, description: altText?.alternativeDescription)
            let id = media.count + 1
            let name = "image\(id).\(image.extensionName)"
            media.append(ZipEntry(path: "word/media/" + name, data: image.data))
            let cx = Int((image.size.width * 12_700).rounded())
            let cy = Int((image.size.height * 12_700).rounded())
            return """
            <w:drawing><wp:inline xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" distT="0" distB="0" distL="0" distR="0"><wp:extent cx="\(cx)" cy="\(cy)"/><wp:docPr id="\(id)" name="\(name)"\(altAttributes)/><wp:cNvGraphicFramePr><a:graphicFrameLocks xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" noChangeAspect="1"/></wp:cNvGraphicFramePr><a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:nvPicPr><pic:cNvPr id="\(id)" name="\(name)"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed="rImage\(id)"/>\(cropXML)<a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="\(cx)" cy="\(cy)"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing>
            """
        }

        mutating func floatingDrawing(_ image: FloatingImage) throws -> String {
            guard emittedFloatingImageIDs.insert(image.id).inserted else {
                throw WriterError.message("A floating image was assigned to more than one DOCX paragraph. Export stopped to prevent duplicate artwork.")
            }
            guard image.anchor != .page || image.pageIndex == 0 else {
                throw WriterError.message("This page-anchored image is on a later physical page, but DOCX page-relative anchors also require a paragraph anchor. Choose paragraph anchoring before exporting.")
            }
            guard image.anchor == .page || image.anchor == .margins || (image.anchorOffsetX != nil && image.anchorOffsetY != nil) else {
                throw WriterError.message("This text-anchored image has no stable anchor offsets and cannot be exported without changing its placement.")
            }
            guard image.horizontalAlignment == nil || image.horizontalPositionReference == .page || image.horizontalPositionReference == .margins,
                  image.verticalAlignment == nil || image.verticalPositionReference == .page || image.verticalPositionReference == .margins else {
                throw WriterError.message("Word alignment is supported only relative to page or margins. Choose a fixed position or a supported reference frame before exporting.")
            }
            let wrapDistances = image.effectiveWrapDistances
            guard wrapDistances.values.allSatisfy({ $0.isFinite && (0...288).contains($0) }) else {
                throw WriterError.message("The floating image's text distance is outside the DOCX-supported range.")
            }
            let ext = (image.assetName as NSString).pathExtension.lowercased()
            let fileExtension: String
            switch ext {
            case "jpg", "jpeg": fileExtension = "jpg"
            case "png": fileExtension = "png"
            default:
                throw WriterError.message("DOCX floating-image export preserves JPEG and PNG source bytes. The source format for \(image.assetName) is not supported for anchored export.")
            }
            guard NSImage(data: image.imageData) != nil else {
                throw WriterError.message("The floating image source data is invalid and cannot be exported to DOCX.")
            }
            let id = media.count + 1
            let name = "floating\(id).\(fileExtension)"
            media.append(ZipEntry(path: "word/media/" + name, data: image.imageData))
            let altAttributes = pictureAltAttributes(title: image.altTitle, description: image.altDescription)
            let relationshipID = "rImage\(id)"
            let hReference: String
            let vReference: String
            let x: Double
            let y: Double
            switch image.anchor {
            case .page:
                hReference = "page"; vReference = "page"; x = image.x; y = image.y
            case .margins:
                hReference = "margin"; vReference = "margin"; x = image.x; y = image.y
            case .paragraph:
                hReference = "paragraph"; vReference = "paragraph"; x = image.anchorOffsetX!; y = image.anchorOffsetY!
            case .character:
                hReference = "character"; vReference = "paragraph"; x = image.anchorOffsetX!; y = image.anchorOffsetY!
            }
            func wordReference(_ reference: FloatingImage.PositionReference?, fallback: String) -> String {
                switch reference {
                case .page: return "page"
                case .margins: return "margin"
                case .paragraph: return "paragraph"
                case .character: return "character"
                case .line: return "line"
                case .anchor, .none: return fallback
                }
            }
            let actualHReference = wordReference(image.horizontalPositionReference, fallback: hReference)
            let actualVReference = wordReference(image.verticalPositionReference, fallback: vReference)
            let actualX = image.anchorOffsetX ?? x
            let actualY = image.anchorOffsetY ?? y
            guard actualX.isFinite, actualY.isFinite, actualX >= 0, actualY >= 0, actualX <= 20_000, actualY <= 20_000 else {
                throw WriterError.message("This floating image has a negative or out-of-range DOCX position offset that cannot be represented safely.")
            }
            let cx = Int((image.width * 12_700).rounded())
            let cy = Int((image.height * 12_700).rounded())
            let xEmu = Int((actualX * 12_700).rounded())
            let yEmu = Int((actualY * 12_700).rounded())
            let horizontalPosition: String
            if let alignment = image.horizontalAlignment {
                horizontalPosition = "<wp:align>\(alignment.rawValue)</wp:align>"
            } else {
                horizontalPosition = "<wp:posOffset>\(xEmu)</wp:posOffset>"
            }
            let verticalPosition: String
            if let alignment = image.verticalAlignment {
                verticalPosition = "<wp:align>\(alignment.rawValue)</wp:align>"
            } else {
                verticalPosition = "<wp:posOffset>\(yEmu)</wp:posOffset>"
            }
            let rotation = Int((image.rotationDegrees * 60_000).rounded())
            let behind = image.layer == .behindText ? 1 : 0
            let wrap: String
            switch image.wrapping {
            case .none: wrap = "<wp:wrapNone/>"
            case .square: wrap = "<wp:wrapSquare wrapText=\"\(wordWrapSide(image.effectiveWrapSide))\"/>"
            case .topAndBottom: wrap = "<wp:wrapTopAndBottom/>"
            case .tight, .through:
                let polygon: String
                let edited: String
                if let original = image.wrapPolygon {
                    guard original.isValid else {
                        throw WriterError.message("This Word Tight Wrap image has invalid polygon coordinates; DOCX export stopped to protect its text flow.")
                    }
                    let points = original.points
                    polygon = (points + [points[0]]).enumerated().map { index, point in
                        "<wp:\(index == 0 ? "start" : "lineTo") x=\"\(point.x)\" y=\"\(point.y)\"/>"
                    }.joined()
                    edited = original.edited ? "1" : "0"
                } else {
                    guard let displayed = image.displayImage(),
                          let generated = tightWrapPolygon(displayed) else {
                        throw WriterError.message("This Tight Wrap image has disconnected or internally cut-out transparency that cannot be represented as one Word DrawingML wrap polygon. Change it to Square, Top and Bottom, or No Wrap before exporting.")
                    }
                    polygon = generated
                    edited = "0"
                }
                let tag = image.wrapping == .through ? "wrapThrough" : "wrapTight"
                wrap = "<wp:\(tag) wrapText=\"\(wordWrapSide(image.effectiveWrapSide))\"><wp:wrapPolygon edited=\"\(edited)\">\(polygon)</wp:wrapPolygon></wp:\(tag)>"
            }
            let distanceTop = Int((wrapDistances.top * 12_700).rounded())
            let distanceRight = Int((wrapDistances.right * 12_700).rounded())
            let distanceBottom = Int((wrapDistances.bottom * 12_700).rounded())
            let distanceLeft = Int((wrapDistances.left * 12_700).rounded())
            let insets = "distT=\"\(distanceTop)\" distR=\"\(distanceRight)\" distB=\"\(distanceBottom)\" distL=\"\(distanceLeft)\""
            let cropXML: String
            if let crop = image.sourceCrop, !crop.isEmpty {
                guard crop.hasValidGeometry else {
                    throw WriterError.message("A floating Word picture has an invalid source crop; DOCX export stopped to protect its artwork.")
                }
                cropXML = "<a:srcRect l=\"\(crop.left)\" t=\"\(crop.top)\" r=\"\(crop.right)\" b=\"\(crop.bottom)\"/>"
            } else {
                cropXML = ""
            }
            return """
            <w:r><w:drawing><wp:anchor xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" \(insets) simplePos="0" relativeHeight="\(max(0, image.zOrder))" behindDoc="\(behind)" locked="\(image.positionLocked ? 1 : 0)" layoutInCell="1" allowOverlap="1"><wp:simplePos x="0" y="0"/><wp:positionH relativeFrom="\(actualHReference)">\(horizontalPosition)</wp:positionH><wp:positionV relativeFrom="\(actualVReference)">\(verticalPosition)</wp:positionV><wp:extent cx="\(cx)" cy="\(cy)"/><wp:effectExtent l="0" t="0" r="0" b="0"/>\(wrap)<wp:docPr id="\(id)" name="\(attribute(name))"\(altAttributes)/><wp:cNvGraphicFramePr><a:graphicFrameLocks xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" noChangeAspect="\(image.preservesAspectRatio ? 1 : 0)"/></wp:cNvGraphicFramePr><a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:nvPicPr><pic:cNvPr id="\(id)" name="\(attribute(name))"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed="\(relationshipID)"/>\(cropXML)<a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm rot="\(rotation)"><a:off x="0" y="0"/><a:ext cx="\(cx)" cy="\(cy)"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:anchor></w:drawing></w:r>
            """
        }

        private func wordWrapSide(_ side: FloatingImage.WrapSide) -> String {
            switch side {
            case .both, .automatic: return "bothSides"
            case .leftOnly: return "left"
            case .rightOnly: return "right"
            case .largestSide: return "largest"
            }
        }

        /// Word Tight Wrap uses one normalized polygon. A horizontal alpha
        /// silhouette can be represented exactly enough by its sampled left
        /// and right boundaries. Disconnected runs or holes are refused rather
        /// than exported as a misleading rectangular contour.
        private func tightWrapPolygon(_ image: NSImage) -> String? {
            guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let provider = cgImage.dataProvider?.data,
                  let bytes = CFDataGetBytePtr(provider) else { return nil }
            let sampleWidth = 48, sampleHeight = 48
            let bytesPerPixel = max(1, cgImage.bitsPerPixel / 8)
            let alphaIndex: Int?
            switch cgImage.alphaInfo {
            case .alphaOnly: alphaIndex = 0
            case .first, .premultipliedFirst: alphaIndex = 0
            case .last, .premultipliedLast: alphaIndex = bytesPerPixel - 1
            case .none, .noneSkipFirst, .noneSkipLast: alphaIndex = nil
            @unknown default: alphaIndex = nil
            }
            var rows: [(Int, Int, Int)] = []
            for row in 0..<sampleHeight {
                var occupied: [Int] = []
                for column in 0..<sampleWidth {
                    let pixelX = min(cgImage.width - 1, column * cgImage.width / sampleWidth)
                    let pixelY = min(cgImage.height - 1, row * cgImage.height / sampleHeight)
                    let offset = pixelY * cgImage.bytesPerRow + pixelX * bytesPerPixel
                    if alphaIndex.map({ bytes[offset + $0] > 20 }) ?? true { occupied.append(column) }
                }
                guard let first = occupied.first, let last = occupied.last else {
                    rows.append((row, -1, -1)); continue
                }
                guard occupied.count == last - first + 1 else { return nil }
                rows.append((row, first, last + 1))
            }
            guard let first = rows.firstIndex(where: { $0.1 >= 0 }),
                  let last = rows.lastIndex(where: { $0.1 >= 0 }),
                  !rows[first...last].contains(where: { $0.1 < 0 }) else { return nil }
            let activeRows = Array(rows[first...last])
            func normalized(_ x: Int, _ y: Int) -> (Int, Int) {
                (max(0, min(21_600, Int((Double(x) / Double(sampleWidth) * 21_600).rounded()))),
                 max(0, min(21_600, Int((Double(y) / Double(sampleHeight) * 21_600).rounded()))))
            }
            var points = activeRows.map { normalized($0.1, $0.0) }
            points.append(contentsOf: activeRows.reversed().map { normalized($0.2, $0.0 + 1) })
            var compact: [(Int, Int)] = []
            for point in points where compact.last?.0 != point.0 || compact.last?.1 != point.1 { compact.append(point) }
            guard compact.count >= 4 else { return nil }
            let firstPoint = compact[0]
            let remaining = compact.dropFirst().map { "<wp:lineTo x=\"\($0.0)\" y=\"\($0.1)\"/>" }.joined()
            return "<wp:start x=\"\(firstPoint.0)\" y=\"\(firstPoint.1)\"/>" + remaining
                + "<wp:lineTo x=\"\(firstPoint.0)\" y=\"\(firstPoint.1)\"/>"
        }

        var hasTrackedChanges: Bool {
            !TrackChanges.records(
                in: text
            ).isEmpty
                || notes.contains {
                    $0.hasPendingBodyChange
                }
        }

        func settingsXML(
            trackRevisions: Bool
        ) -> String {
            var values = ""

            if trackRevisions {
                values += "<w:trackRevisions/>"
            }

            if usesDifferentOddEvenHeaderFooter {
                values += "<w:evenAndOddHeaders/>"
            }

            if usesMirrorMargins {
                values += "<w:mirrorMargins/>"
            }

            if usesGutterAtTop {
                values += "<w:gutterAtTop/>"
            }

            if usesNoColumnBalance {
                values += "<w:compat><w:noColumnBalance/></w:compat>"
            }

            return
                "<w:settings xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">\(values)</w:settings>"
        }

        struct FurniturePart {
            let path: String
            let target: String
            let relationshipID: String
            let relationshipType: String
            let contentType: String
            let xml: String
        }

        var usesNoColumnBalance: Bool {
            settings.disablesColumnBalancing
                || sections.contains {
                    $0.page
                        .disablesColumnBalancing
                }
        }

        var usesDifferentOddEvenHeaderFooter: Bool {
            sections.contains {
                $0.page
                    .usesDifferentOddEvenHeaderFooter
            }
        }

        var usesMirrorMargins: Bool {
            sections.contains {
                $0.page
                    .usesMirrorMargins
            }
        }

        var usesGutterAtTop: Bool {
            sections.contains {
                $0.page
                    .usesGutterAtTop
            }
        }

        private func hasHeader(
            _ page: PageSettings
        ) -> Bool {
            !page
                .effectiveHeaderText
                .isEmpty
        }

        private func hasFooter(
            _ page: PageSettings
        ) -> Bool {
            !page.footerText.isEmpty
                || page.showsPageNumbers
        }

        private func hasEvenHeader(
            _ page: PageSettings
        ) -> Bool {
            usesDifferentOddEvenHeaderFooter
                && !page
                    .effectiveEvenPageHeaderText
                    .isEmpty
        }

        private func hasEvenFooter(
            _ page: PageSettings
        ) -> Bool {
            usesDifferentOddEvenHeaderFooter
                && (
                    !page
                        .effectiveEvenPageFooterText
                        .isEmpty
                    || page.showsPageNumbers
                )
        }

        private func hasFirstHeader(
            _ page: PageSettings
        ) -> Bool {
            page.firstPageHeaderText != nil
                && !page
                    .effectiveFirstPageHeaderText
                    .isEmpty
        }

        private func hasFirstFooter(
            _ page: PageSettings
        ) -> Bool {
            page.firstPageFooterText != nil
                && (
                    !page
                        .effectiveFirstPageFooterText
                        .isEmpty
                    || page.showsPageNumbers
                )
        }

        private func headerRelationshipID(
            sectionIndex: Int,
            even: Bool
        ) -> String {
            if sections.count == 1 {
                return even
                    ? "rHeader2"
                    : "rHeader1"
            }

            return
                "rHeaderSection"
                + String(
                    sectionIndex + 1
                )
                + (
                    even
                        ? "Even"
                        : "Default"
                )
        }

        private func footerRelationshipID(
            sectionIndex: Int,
            even: Bool
        ) -> String {
            if sections.count == 1 {
                return even
                    ? "rFooter2"
                    : "rFooter1"
            }

            return
                "rFooterSection"
                + String(
                    sectionIndex + 1
                )
                + (
                    even
                        ? "Even"
                        : "Default"
                )
        }

        private func headerTarget(
            sectionIndex: Int,
            even: Bool
        ) -> String {
            if sections.count == 1 {
                return even
                    ? "header2.xml"
                    : "header1.xml"
            }

            return
                "header-section"
                + String(
                    sectionIndex + 1
                )
                + "-"
                + (
                    even
                        ? "even"
                        : "default"
                )
                + ".xml"
        }

        private func footerTarget(
            sectionIndex: Int,
            even: Bool
        ) -> String {
            if sections.count == 1 {
                return even
                    ? "footer2.xml"
                    : "footer1.xml"
            }

            return
                "footer-section"
                + String(
                    sectionIndex + 1
                )
                + "-"
                + (
                    even
                        ? "even"
                        : "default"
                )
                + ".xml"
        }

        private func firstHeaderRelationshipID(
            sectionIndex: Int
        ) -> String {
            if sections.count == 1 {
                return "rHeaderFirst"
            }

            return
                "rHeaderSection"
                + String(
                    sectionIndex + 1
                )
                + "First"
        }

        private func firstFooterRelationshipID(
            sectionIndex: Int
        ) -> String {
            if sections.count == 1 {
                return "rFooterFirst"
            }

            return
                "rFooterSection"
                + String(
                    sectionIndex + 1
                )
                + "First"
        }

        private func firstHeaderTarget(
            sectionIndex: Int
        ) -> String {
            if sections.count == 1 {
                return "header-first.xml"
            }

            return
                "header-section"
                + String(
                    sectionIndex + 1
                )
                + "-first.xml"
        }

        private func firstFooterTarget(
            sectionIndex: Int
        ) -> String {
            if sections.count == 1 {
                return "footer-first.xml"
            }

            return
                "footer-section"
                + String(
                    sectionIndex + 1
                )
                + "-first.xml"
        }

        private func headerXML(
            for page: PageSettings,
            even: Bool
        ) -> String {
            let paragraph =
                furnitureParagraph(
                    text:
                        even
                            ? page
                                .effectiveEvenPageHeaderText
                            : page
                                .effectiveHeaderText,
                    position:
                        page
                            .effectiveHeaderPosition,
                    pageNumber:
                        false
                )

            return
                "<w:hdr xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">\(paragraph)</w:hdr>"
        }

        private func footerXML(
            for page: PageSettings,
            even: Bool
        ) -> String {
            let page = page.resolvingEvenFooter(even)
            let text =
                even
                    ? page
                        .effectiveEvenPageFooterText
                    : page.footerText

            if page.showsPageNumbers,
               !text.isEmpty,
               page.effectiveFooterPosition
                    == page.effectivePageNumberPosition {

                return
                    "<w:ftr xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">"
                    + combinedFooterParagraph(
                        text:
                            text,
                        position:
                            page.effectiveFooterPosition
                    )
                    + "</w:ftr>"
            }

            var paragraphs = ""

            if !text.isEmpty {
                paragraphs +=
                    furnitureParagraph(
                        text:
                            text,
                        position:
                            page.effectiveFooterPosition,
                        pageNumber:
                            false
                    )
            }

            if page.showsPageNumbers {
                paragraphs +=
                    furnitureParagraph(
                        text:
                            "",
                        position:
                            page.effectivePageNumberPosition,
                        pageNumber:
                            true
                    )
            }

            if paragraphs.isEmpty {
                paragraphs =
                    "<w:p><w:r><w:t></w:t></w:r></w:p>"
            }

            return
                "<w:ftr xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">"
                + paragraphs
                + "</w:ftr>"
        }

        private func firstHeaderXML(
            for page: PageSettings
        ) -> String {
            let paragraph =
                furnitureParagraph(
                    text:
                        page
                            .effectiveFirstPageHeaderText,
                    position:
                        page
                            .effectiveHeaderPosition,
                    pageNumber:
                        false
                )

            return
                "<w:hdr xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">\(paragraph)</w:hdr>"
        }

        private func firstFooterXML(
            for page: PageSettings
        ) -> String {
            let text =
                page
                    .effectiveFirstPageFooterText

            if page.showsPageNumbers,
               !text.isEmpty,
               page.effectiveFooterPosition
                    == page.effectivePageNumberPosition {

                return
                    "<w:ftr xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">"
                    + combinedFooterParagraph(
                        text:
                            text,
                        position:
                            page.effectiveFooterPosition
                    )
                    + "</w:ftr>"
            }

            var paragraphs = ""

            if !text.isEmpty {
                paragraphs +=
                    furnitureParagraph(
                        text:
                            text,
                        position:
                            page.effectiveFooterPosition,
                        pageNumber:
                            false
                    )
            }

            if page.showsPageNumbers {
                paragraphs +=
                    furnitureParagraph(
                        text:
                            "",
                        position:
                            page.effectivePageNumberPosition,
                        pageNumber:
                            true
                    )
            }

            if paragraphs.isEmpty {
                paragraphs =
                    "<w:p><w:r><w:t></w:t></w:r></w:p>"
            }

            return
                "<w:ftr xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">"
                + paragraphs
                + "</w:ftr>"
        }

        var furnitureParts: [FurniturePart] {
            var result: [FurniturePart] = []

            for (
                sectionIndex,
                section
            ) in sections.enumerated() {

                let page =
                    section.page

                if hasHeader(page) {
                    let target =
                        headerTarget(
                            sectionIndex:
                                sectionIndex,
                            even:
                                false
                        )

                    result.append(
                        FurniturePart(
                            path:
                                "word/"
                                + target,
                            target:
                                target,
                            relationshipID:
                                headerRelationshipID(
                                    sectionIndex:
                                        sectionIndex,
                                    even:
                                        false
                                ),
                            relationshipType:
                                "header",
                            contentType:
                                "application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml",
                            xml:
                                headerXML(
                                    for:
                                        page,
                                    even:
                                        false
                                )
                        )
                    )
                }

                if hasEvenHeader(page) {
                    let target =
                        headerTarget(
                            sectionIndex:
                                sectionIndex,
                            even:
                                true
                        )

                    result.append(
                        FurniturePart(
                            path:
                                "word/"
                                + target,
                            target:
                                target,
                            relationshipID:
                                headerRelationshipID(
                                    sectionIndex:
                                        sectionIndex,
                                    even:
                                        true
                                ),
                            relationshipType:
                                "header",
                            contentType:
                                "application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml",
                            xml:
                                headerXML(
                                    for:
                                        page,
                                    even:
                                        true
                                )
                        )
                    )
                }

                if hasFooter(page) {
                    let target =
                        footerTarget(
                            sectionIndex:
                                sectionIndex,
                            even:
                                false
                        )

                    result.append(
                        FurniturePart(
                            path:
                                "word/"
                                + target,
                            target:
                                target,
                            relationshipID:
                                footerRelationshipID(
                                    sectionIndex:
                                        sectionIndex,
                                    even:
                                        false
                                ),
                            relationshipType:
                                "footer",
                            contentType:
                                "application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml",
                            xml:
                                footerXML(
                                    for:
                                        page,
                                    even:
                                        false
                                )
                        )
                    )
                }

                if hasEvenFooter(page) {
                    let target =
                        footerTarget(
                            sectionIndex:
                                sectionIndex,
                            even:
                                true
                        )

                    result.append(
                        FurniturePart(
                            path:
                                "word/"
                                + target,
                            target:
                                target,
                            relationshipID:
                                footerRelationshipID(
                                    sectionIndex:
                                        sectionIndex,
                                    even:
                                        true
                                ),
                            relationshipType:
                                "footer",
                            contentType:
                                "application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml",
                            xml:
                                footerXML(
                                    for:
                                        page,
                                    even:
                                        true
                                )
                        )
                    )
                }
                if hasFirstHeader(page) {
                    let target =
                        firstHeaderTarget(
                            sectionIndex:
                                sectionIndex
                        )

                    result.append(
                        FurniturePart(
                            path:
                                "word/"
                                + target,
                            target:
                                target,
                            relationshipID:
                                firstHeaderRelationshipID(
                                    sectionIndex:
                                        sectionIndex
                                ),
                            relationshipType:
                                "header",
                            contentType:
                                "application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml",
                            xml:
                                firstHeaderXML(
                                    for:
                                        page
                                )
                        )
                    )
                }

                if hasFirstFooter(page) {
                    let target =
                        firstFooterTarget(
                            sectionIndex:
                                sectionIndex
                        )

                    result.append(
                        FurniturePart(
                            path:
                                "word/"
                                + target,
                            target:
                                target,
                            relationshipID:
                                firstFooterRelationshipID(
                                    sectionIndex:
                                        sectionIndex
                                ),
                            relationshipType:
                                "footer",
                            contentType:
                                "application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml",
                            xml:
                                firstFooterXML(
                                    for:
                                        page
                                )
                        )
                    )
                }

            }

            return result
        }

        private func furnitureParagraph(
            text: String,
            position: PageSettings.HorizontalPosition,
            pageNumber: Bool
        ) -> String {
            let alignment = wordAlignment(position)

            var body = ""

            if !text.isEmpty {
                body +=
                    "<w:r><w:t xml:space=\"preserve\">\(xml(text))</w:t></w:r>"
            }

            if pageNumber {
                body += pageFieldXML
            }

            if body.isEmpty {
                body = "<w:r><w:t></w:t></w:r>"
            }

            return
                "<w:p><w:pPr><w:jc w:val=\"\(alignment)\"/></w:pPr>\(body)</w:p>"
        }

        private func combinedFooterParagraph(
            text: String,
            position: PageSettings.HorizontalPosition
        ) -> String {
            let alignment = wordAlignment(position)

            return
                "<w:p><w:pPr><w:jc w:val=\"\(alignment)\"/></w:pPr>"
                + "<w:r><w:t xml:space=\"preserve\">\(xml(text))   •   </w:t></w:r>"
                + pageFieldXML
                + "</w:p>"
        }

        private var pageFieldXML: String {
            "<w:fldSimple w:instr=\" PAGE \">"
                + "<w:r><w:t>1</w:t></w:r>"
                + "</w:fldSimple>"
        }

        private func wordAlignment(
            _ position: PageSettings.HorizontalPosition
        ) -> String {
            switch position {
            case .left:
                return "left"
            case .center:
                return "center"
            case .right:
                return "right"
            }
        }

        var commentsXML: String {
            let formatter =
                ISO8601DateFormatter()

            formatter.formatOptions = [
                .withInternetDateTime
            ]

            var body = ""

            for (
                index,
                comment
            ) in comments.enumerated() {
                let lines =
                    comment.text
                        .components(
                            separatedBy:
                                .newlines
                        )

                let paragraphs =
                    (
                        lines.isEmpty
                            ? [""]
                            : lines
                    )
                    .map {
                        value in

                        "<w:p><w:r><w:t xml:space=\"preserve\">"
                        + xml(value)
                        + "</w:t></w:r></w:p>"
                    }
                    .joined()

                body +=
                    "<w:comment w:id=\"\(index)\" w:author=\""
                    + attribute(
                        comment.author
                    )
                    + "\" w:date=\""
                    + attribute(
                        formatter.string(
                            from:
                                comment.createdAt
                        )
                    )
                    + "\">"
                    + paragraphs
                    + "</w:comment>"
            }

            return
                "<w:comments xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">"
                + body
                + "</w:comments>"
        }

        var relationships: String {
            var values =
                "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>"
                + "<Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering\" Target=\"numbering.xml\"/>"

            if hasTrackedChanges {
                values +=
                    "<Relationship Id=\"rSettings\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings\" Target=\"settings.xml\"/>"
            }

            if !notes.isEmpty {
                values +=
                    "<Relationship Id=\"rFootnotes\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/footnotes\" Target=\"footnotes.xml\"/>"
            }
if !endnotes.isEmpty {
                values +=
                    "<Relationship Id=\"rEndnotes\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/endnotes\" Target=\"endnotes.xml\"/>"
            }

            if !comments.isEmpty {
                values +=
                    "<Relationship Id=\"rComments\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/comments\" Target=\"comments.xml\"/>"
            }

            for part in furnitureParts {
                values +=
                    "<Relationship Id=\""
                    + attribute(
                        part.relationshipID
                    )
                    + "\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/"
                    + part.relationshipType
                    + "\" Target=\""
                    + attribute(
                        part.target
                    )
                    + "\"/>"
            }

            for (index, target) in links.enumerated() {
                values +=
                    "<Relationship Id=\"rId\(index + 3)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink\" Target=\"\(attribute(target))\" TargetMode=\"External\"/>"
            }

            for (index, entry) in media.enumerated() {
                values +=
                    "<Relationship Id=\"rImage\(index + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"\(entry.path.dropFirst(5))\"/>"
            }

            return
                "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">\(values)</Relationships>"
        }

        var numberingXML: String {
            var abstract = ""
            for (id, format, marker) in [(0, "bullet", "•"), (1, "decimal", "%1.")] {
                abstract += "<w:abstractNum w:abstractNumId=\"\(id)\"><w:multiLevelType w:val=\"singleLevel\"/><w:lvl w:ilvl=\"0\"><w:start w:val=\"1\"/><w:numFmt w:val=\"\(format)\"/><w:lvlText w:val=\"\(marker)\"/><w:lvlJc w:val=\"left\"/><w:pPr><w:tabs><w:tab w:val=\"num\" w:pos=\"720\"/></w:tabs><w:ind w:left=\"720\" w:hanging=\"360\"/></w:pPr></w:lvl></w:abstractNum>"
            }
            let instances = numbers.enumerated().map { index, number in "<w:num w:numId=\"\(index + 1)\"><w:abstractNumId w:val=\"\(number.ordered ? 1 : 0)\"/><w:lvlOverride w:ilvl=\"0\"><w:startOverride w:val=\"\(number.start)\"/></w:lvlOverride></w:num>" }.joined()
            return "<w:numbering xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">\(abstract)\(instances)</w:numbering>"
        }
    }

    private static func listItem(_ value: String, style: NSParagraphStyle?) -> (ordered: Bool, number: Int?, prefix: Int, start: Int, native: ObjectIdentifier?)? {
        let list = style?.textLists.last
        let native = list.map(ObjectIdentifier.init)
        let start = max(1, list?.startingItemNumber ?? 1)
        // Preserve formatted ordinary paragraphs verbatim. A literal "1. "
        // is not automatic numbering when its paragraph has no native list.
        // Plain unstyled legacy input retains the existing convenience inference.
        if style != nil && list == nil { return nil }
        if let match = value.range(of: "^[ \\t]*[•◦▪*-][ \\t]+", options: .regularExpression) { return (false, nil, NSRange(match, in: value).length, start, native) }
        let ns = value as NSString
        if let regex = try? NSRegularExpression(pattern: "^[ \\t]*([0-9]+)[.)][ \\t]+"), let match = regex.firstMatch(in: value, range: NSRange(location: 0, length: ns.length)) {
            return (true, Int(ns.substring(with: match.range(at: 1))), match.range.length, start, native)
        }
        if let list { return (list.isOrdered, nil, 0, start, native) }
        return nil
    }

    private static func paragraphRanges(_ value: String) -> [NSRange] {
        let units = Array(value.utf16)
        var ranges: [NSRange] = [], start = 0, index = 0
        while index < units.count {
            if [UInt16(0x0a), 0x0d, 0x2029].contains(units[index]) {
                ranges.append(NSRange(location: start, length: index - start))
                if units[index] == 0x0d, index + 1 < units.count, units[index + 1] == 0x0a { index += 1 }
                start = index + 1
            }
            index += 1
        }
        ranges.append(NSRange(location: start, length: units.count - start)); return ranges
    }

    private static let contentTypes = "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/><Override PartName=\"/word/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml\"/><Override PartName=\"/word/numbering.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml\"/><Override PartName=\"/docProps/core.xml\" ContentType=\"application/vnd.openxmlformats-package.core-properties+xml\"/></Types>"
    private static let rootRelationships = "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/><Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties\" Target=\"docProps/core.xml\"/></Relationships>"
    private static func styles(
        _ text: NSAttributedString,
        namedStyles: [NamedStyleDefinition]
    ) -> String {
        let definitions = NamedStyles.mergedWithBuiltIns(namedStyles)
        let definitionsByID = Dictionary(definitions.map { ($0.styleID, $0) }, uniquingKeysWith: { first, _ in first })
        let encounteredParagraphStyles = Set((0..<text.length).compactMap { index -> String? in
            (text.attribute(.boldWriterParagraphStyle, at: index, effectiveRange: nil) as? WordParagraphStyle)?.styleID
        })
        let encounteredCharacterStyles = Set((0..<text.length).compactMap { index -> String? in
            (text.attribute(.boldWriterCharacterStyle, at: index, effectiveRange: nil) as? WordCharacterStyle)?.styleID
        })
        var values = ""

        for style
            in WriterStyle.allCases
        {
            let definition = definitionsByID[style.wordStyleID]
            let name = definition?.name ?? style.rawValue
            let defaultAttribute = style == .normal || definition?.isDefault == true ? " w:default=\"1\"" : ""
            let quickFormat = style == .normal || definition?.isQuickStyle == true || style.headingLevel != nil || [.title, .subtitle, .quote, .intenseQuote].contains(style) ? "<w:qFormat/>" : ""
            let basedOn = definition?.basedOn ?? (style == .normal ? nil : "Normal")

            values +=
                "<w:style w:type=\"paragraph\"" + defaultAttribute + " w:styleId=\""
                + attribute(style.wordStyleID)
                + "\"><w:name w:val=\""
                + attribute(name)
                + "\"/>" + (basedOn.map { "<w:basedOn w:val=\"\(attribute($0))\"/>" } ?? "")
                + ((definition?.nextStyleID ?? (style.headingLevel != nil ? "Normal" : nil)).map { "<w:next w:val=\"\(attribute($0))\"/>" } ?? "")
                + ((definition?.linkedStyleID).map { "<w:link w:val=\"\(attribute($0))\"/>" } ?? "")
                + quickFormat
                + styleFormattingXML(definition?.formatting ?? NamedStyleDefinition.builtIns.first(where: { $0.styleID == style.wordStyleID })?.formatting ?? NamedStyleFormatting(), kind: .paragraph, outlineLevel: style.headingLevel.map { $0 - 1 })
                + "</w:style>"
        }

        var paragraphStyles:
            [String: WordParagraphStyle] = [:]

        var characterStyles:
            [String: WordCharacterStyle] = [:]

        if text.length > 0 {
            text.enumerateAttribute(
                .boldWriterParagraphStyle,
                in:
                    NSRange(
                        location:
                            0,
                        length:
                            text.length
                    ),
                options:
                    []
            ) {
                value,
                _,
                _ in

                guard
                    let style =
                        value as? WordParagraphStyle,
                    !style.styleID.isEmpty
                else {
                    return
                }

                paragraphStyles[
                    style.styleID
                ] = style
            }

            text.enumerateAttribute(
                .boldWriterCharacterStyle,
                in:
                    NSRange(
                        location:
                            0,
                        length:
                            text.length
                    ),
                options:
                    []
            ) {
                value,
                _,
                _ in

                guard
                    let style =
                        value as? WordCharacterStyle,
                    !style.styleID.isEmpty
                else {
                    return
                }

                characterStyles[
                    style.styleID
                ] = style
            }
        }

        var dependencyStyles:
            [String: WordStyleDependency] = [:]

        for style in paragraphStyles.values {
            for dependency
                in style.dependencies {

                dependencyStyles[
                    dependency.styleID
                ] = dependency
            }
        }

        for style in characterStyles.values {
            for dependency
                in style.dependencies {

                dependencyStyles[
                    dependency.styleID
                ] = dependency
            }
        }

        let reservedParagraphStyleIDs =
            Set(
                WriterStyle.allCases.map {
                    $0.rawValue
                        .replacingOccurrences(
                            of:
                                " ",
                            with:
                                ""
                        )
                }
            )

        func styleDependencyXML(
            _ style: WordStyleDependency
        ) -> String {
            let type =
                style.kind == .character
                    ? "character"
                    : "paragraph"

            var value =
                "<w:style w:type=\""
                + type
                + "\" w:styleId=\""
                + attribute(
                    style.styleID
                )
                + "\">"

            value +=
                "<w:name w:val=\""
                + attribute(
                    style.name
                        ?? style.styleID
                )
                + "\"/>"

            if let basedOn =
                style.basedOn,
               !basedOn.isEmpty {

                value +=
                    "<w:basedOn w:val=\""
                    + attribute(
                        basedOn
                    )
                    + "\"/>"
            }

            if let linked =
                style.linkedStyleID,
               !linked.isEmpty {

                value +=
                    "<w:link w:val=\""
                    + attribute(
                        linked
                    )
                    + "\"/>"
            }

            if style.kind == .paragraph,
               let next =
                style.nextStyleID,
               !next.isEmpty {

                value +=
                    "<w:next w:val=\""
                    + attribute(
                        next
                    )
                    + "\"/>"
            }

            value +=
                "</w:style>"

            return value
        }

        let directlyEmittedStyleIDs =
            Set(
                paragraphStyles.keys
            )
            .union(
                characterStyles.keys
            )
            .union(
                reservedParagraphStyleIDs
            )
            .union(
                ["Normal"]
            )

        for styleID
            in dependencyStyles.keys.sorted() {

            guard
                !directlyEmittedStyleIDs.contains(
                    styleID
                ),
                let dependency =
                    dependencyStyles[
                        styleID
                    ]
            else {
                continue
            }

            values +=
                styleDependencyXML(
                    dependency
                )
        }

        for styleID
            in paragraphStyles.keys.sorted() {

            guard
                !reservedParagraphStyleIDs.contains(
                    styleID
                ),
                let style =
                    paragraphStyles[
                        styleID
                    ]
            else {
                continue
            }

            values +=
                "<w:style w:type=\"paragraph\" w:styleId=\""
                + attribute(
                    style.styleID
                )
                + "\">"

            values +=
                "<w:name w:val=\""
                + attribute(
                    style.name
                        ?? style.styleID
                )
                + "\"/>"

            if let basedOn =
                style.basedOn,
               !basedOn.isEmpty {

                values +=
                    "<w:basedOn w:val=\""
                    + attribute(
                        basedOn
                    )
                    + "\"/>"
            }

            if let linkedStyleID =
                style.linkedStyleID,
               !linkedStyleID.isEmpty {

                values +=
                    "<w:link w:val=\""
                    + attribute(
                        linkedStyleID
                    )
                    + "\"/>"
            }

            if let nextStyleID =
                style.nextStyleID,
               !nextStyleID.isEmpty {

                values +=
                    "<w:next w:val=\""
                    + attribute(
                        nextStyleID
                    )
                    + "\"/>"
            }

            if let definition = definitionsByID[styleID] {
                if definition.isQuickStyle { values += "<w:qFormat/>" }
                values += styleFormattingXML(definition.formatting, kind: .paragraph)
            }

            values +=
                "</w:style>"
        }

        for styleID
            in characterStyles.keys.sorted() {

            guard
                let style =
                    characterStyles[
                        styleID
                    ]
            else {
                continue
            }

            values +=
                "<w:style w:type=\"character\" w:styleId=\""
                + attribute(
                    style.styleID
                )
                + "\">"

            values +=
                "<w:name w:val=\""
                + attribute(
                    style.name
                        ?? style.styleID
                )
                + "\"/>"

            if let basedOn =
                style.basedOn,
               !basedOn.isEmpty {

                values +=
                    "<w:basedOn w:val=\""
                    + attribute(
                        basedOn
                    )
                    + "\"/>"
            }

            if let linkedStyleID =
                style.linkedStyleID,
               !linkedStyleID.isEmpty {

                values +=
                    "<w:link w:val=\""
                    + attribute(
                        linkedStyleID
                    )
                    + "\"/>"
            }

            if let definition = definitionsByID[styleID] {
                if definition.isQuickStyle { values += "<w:qFormat/>" }
                values += styleFormattingXML(definition.formatting, kind: .character)
            }

            values += "</w:style>"
        }

        for style in definitions.sorted(by: { $0.styleID < $1.styleID }) where !WriterStyle.allCases.contains(where: { $0.wordStyleID == style.styleID }) && !encounteredParagraphStyles.contains(style.styleID) && !encounteredCharacterStyles.contains(style.styleID) {
            let type = style.kind == .character ? "character" : "paragraph"
            values += "<w:style w:type=\"\(type)\"" + (style.isDefault ? " w:default=\"1\"" : "") + " w:styleId=\"\(attribute(style.styleID))\"><w:name w:val=\"\(attribute(style.name))\"/>"
            if let basedOn = style.basedOn { values += "<w:basedOn w:val=\"\(attribute(basedOn))\"/>" }
            if let next = style.nextStyleID { values += "<w:next w:val=\"\(attribute(next))\"/>" }
            if let linked = style.linkedStyleID { values += "<w:link w:val=\"\(attribute(linked))\"/>" }
            if style.isQuickStyle { values += "<w:qFormat/>" }
            values += styleFormattingXML(style.formatting, kind: style.kind) + "</w:style>"
        }

        return
            "<w:styles xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">"
            + values
            + "</w:styles>"
    }

    private static func styleFormattingXML(_ f: NamedStyleFormatting, kind: NamedStyleKind, outlineLevel: Int? = nil) -> String {
        var pPr = "", rPr = ""
        if let family = f.fontFamily { rPr += "<w:rFonts w:ascii=\"\(attribute(family))\" w:hAnsi=\"\(attribute(family))\"/>" }
        if let size = f.fontSize { rPr += "<w:sz w:val=\"\(Int((size * 2).rounded()))\"/>" }
        if let bold = f.bold { rPr += "<w:b" + (bold ? "/>" : " w:val=\"0\"/>") }
        if let italic = f.italic { rPr += "<w:i" + (italic ? "/>" : " w:val=\"0\"/>") }
        if let underline = f.underline { rPr += underline ? "<w:u w:val=\"single\"/>" : "<w:u w:val=\"none\"/>" }
        if let color = f.foregroundColor, color.count == 6 { rPr += "<w:color w:val=\"\(attribute(color.uppercased()))\"/>" }
        if kind == .paragraph {
            if let outlineLevel { pPr += "<w:outlineLvl w:val=\"\(outlineLevel)\"/>" }
            if let alignment = f.alignment { pPr += "<w:jc w:val=\"\(attribute(alignment == "justified" ? "both" : alignment))\"/>" }
            var ind: [String] = []
            if let value = f.leftIndent { ind.append("w:left=\"\(Int((value * 20).rounded()))\"") }
            if let value = f.rightIndent { ind.append("w:right=\"\(Int((value * 20).rounded()))\"") }
            if let value = f.firstLineIndent { ind.append("w:firstLine=\"\(Int((value * 20).rounded()))\"") }
            if !ind.isEmpty { pPr += "<w:ind \(ind.joined(separator: " "))/>" }
            var spacing: [String] = []
            if let value = f.spaceBefore { spacing.append("w:before=\"\(Int((value * 20).rounded()))\"") }
            if let value = f.spaceAfter { spacing.append("w:after=\"\(Int((value * 20).rounded()))\"") }
            if let value = f.lineSpacing { spacing.append("w:line=\"\(Int((value * 240).rounded()))\" w:lineRule=\"auto\"") }
            if !spacing.isEmpty { pPr += "<w:spacing \(spacing.joined(separator: " "))/>" }
            for (name, value) in [("keepNext", f.keepWithNext), ("keepLines", f.keepLinesTogether), ("pageBreakBefore", f.pageBreakBefore), ("widowControl", f.widowControl)] {
                if let value { pPr += "<w:\(name)" + (value ? "/>" : " w:val=\"0\"/>") }
            }
        }
        return (pPr.isEmpty ? "" : "<w:pPr>\(pPr)</w:pPr>") + (rPr.isEmpty ? "" : "<w:rPr>\(rPr)</w:rPr>")
    }
    private static func twips(_ points: Double) -> Int { Int((min(1_000_000, max(0, points.isFinite ? points : 0)) * 20).rounded()) }
    private static func colorHex(_ color: NSColor) -> String? {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return nil }
        func channel(_ value: CGFloat) -> Int { Int((min(1, max(0, value.isFinite ? value : 0)) * 255).rounded()) }
        return String(format: "%02X%02X%02X", channel(rgb.redComponent), channel(rgb.greenComponent), channel(rgb.blueComponent))
    }
    private static func valid(_ scalar: Unicode.Scalar) -> Bool { scalar.value == 9 || scalar.value == 10 || scalar.value == 13 || (0x20...0xd7ff).contains(scalar.value) || (0xe000...0xfffd).contains(scalar.value) || (0x10000...0x10ffff).contains(scalar.value) }
    private static func xml(_ value: String) -> String { String(value.unicodeScalars.filter(valid)).replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;") }
    private static func attribute(_ value: String) -> String { xml(value).replacingOccurrences(of: "\"", with: "&quot;") }
}
