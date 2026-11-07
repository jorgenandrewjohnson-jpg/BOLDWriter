import AppKit
import Foundation

enum EPUBExporter {
    static func data(
        from text: NSAttributedString,
        title: String,
        bookmarks: [DocumentBookmark] = [],
        tocSettings: [PublishingTOCSettings] = []
    ) throws -> Data {
        let exportText =
            NSMutableAttributedString(
                attributedString:
                    text
            )

        try Footnotes.renumber(
            exportText
        )

        try Endnotes.renumber(
            exportText
        )

        let footnotes =
            try Footnotes.records(
                in:
                    exportText
            )

        let endnotes =
            try Endnotes.records(
                in:
                    exportText
            )

        let safeTitle =
            xml(
                title
            )

        let headings = semanticHeadings(in: exportText)
        let headingIDs = Dictionary(uniqueKeysWithValues: headings.enumerated().map { ($0.element.location, "bold-heading-\($0.offset + 1)") })
        let bookmarkTargets = Dictionary(uniqueKeysWithValues: bookmarks.compactMap { bookmark in
            headings.first(where: { NSLocationInRange(bookmark.location, $0.range) || bookmark.location == $0.range.location }).flatMap { heading in headingIDs[heading.location].map { (bookmark.name.lowercased(), $0) } }
        })

        let paragraphs =
            paragraphs(
                from:
                    exportText,
                headingIDs: headingIDs,
                bookmarkTargets: bookmarkTargets
            )

        let notes =
            noteSections(
                footnotes:
                    footnotes,
                endnotes:
                    endnotes
            )

        let identifier =
            UUID()
                .uuidString

        let formatter =
            ISO8601DateFormatter()

        formatter.timeZone =
            TimeZone(
                secondsFromGMT:
                    0
            )

        let modified =
            formatter.string(
                from:
                    Date()
            )

        let entries = [
            ZipEntry(
                path:
                    "mimetype",
                data:
                    Data(
                        "application/epub+zip"
                            .utf8
                    )
            ),
            ZipEntry(
                path:
                    "META-INF/container.xml",
                data:
                    Data(
                        container
                            .utf8
                    )
            ),
            ZipEntry(
                path:
                    "OEBPS/package.opf",
                data:
                    Data(
                        package(
                            title:
                                safeTitle,
                            identifier:
                                identifier,
                            modified:
                                modified
                        )
                        .utf8
                    )
            ),
            ZipEntry(
                path:
                    "OEBPS/nav.xhtml",
                data:
                    Data(
                        nav(
                            title:
                                title,
                            headings: headings,
                            ids: headingIDs,
                            maximumLevel: tocSettings.first(where: { $0.mode == .kindle })?.maximumHeadingLevel ?? 6
                        )
                        .utf8
                    )
            ),
            ZipEntry(
                path:
                    "OEBPS/content.xhtml",
                data:
                    Data(
                        content(
                            title:
                                safeTitle,
                            paragraphs:
                                paragraphs,
                            notes:
                                notes
                        )
                        .utf8
                    )
            )
        ]

        return ZipArchiveWriter.archive(
            entries
        )
    }

    private static func paragraphs(
        from text: NSAttributedString,
        headingIDs: [Int: String],
        bookmarkTargets: [String: String]
    ) -> String {
        let string =
            text.string
                as NSString

        var blocks:
            [String] = []

        var location =
            0

        while location
                < string.length {
            var start =
                0

            var end =
                0

            var contentsEnd =
                0

            string.getParagraphStart(
                &start,
                end:
                    &end,
                contentsEnd:
                    &contentsEnd,
                for:
                    NSRange(
                        location:
                            location,
                        length:
                            0
                    )
            )

            let range =
                NSRange(
                    location:
                        start,
                    length:
                        contentsEnd
                        - start
                )

            let attributes =
                text.attributes(
                    at:
                        start,
                    effectiveRange:
                        nil
                )

            let style =
                (
                    attributes[
                        .boldWriterStyle
                    ]
                    as? String
                )
                .flatMap(
                    WriterStyle.init(
                        rawValue:
                    )
                )
                ?? .normal

            let tag =
                style.headingLevel
                    .map {
                        "h\($0)"
                    }
                ?? (
                    style
                        == .title
                    ? "h1"
                    : (
                        style
                            == .blockQuote
                        ? "blockquote"
                        : "p"
                    )
                )

            let className:
                String

            switch style {
            case .title:
                className =
                    "title"

            case .subtitle:
                className =
                    "subtitle"

            case .quote:
                className =
                    "quote"

            case .blockQuote:
                className =
                    "block-quote"

            case .caption:
                className =
                    "caption"

            default:
                className =
                    ""
            }

            var properties =
                className.isEmpty
                ? ""
                : " class=\"\(className)\""
            if let id = headingIDs[start] { properties += " id=\"\(id)\"" }

            if let paragraph =
                attributes[
                    .paragraphStyle
                ]
                as? NSParagraphStyle {
                let alignment:
                    String?

                switch paragraph.alignment {
                case .left:
                    alignment =
                        "left"

                case .right:
                    alignment =
                        "right"

                case .center:
                    alignment =
                        "center"

                case .justified:
                    alignment =
                        "justify"

                default:
                    alignment =
                        nil
                }

                if let alignment {
                    properties +=
                        " style=\"text-align:\(alignment);\""
                }
            }

            let body =
                inlineContent(
                    from:
                        text,
                    range:
                        range,
                    bookmarkTargets: bookmarkTargets
                )

            blocks.append(
                "<\(tag)\(properties)>"
                + (
                    body.isEmpty
                    ? "<br/>"
                    : body
                )
                + "</\(tag)>"
            )

            location =
                end
        }

        return blocks.isEmpty
            ? "<p><br/></p>"
            : blocks.joined(
                separator:
                    "\n"
            )
    }

    private static func inlineContent(
        from text: NSAttributedString,
        range: NSRange,
        bookmarkTargets: [String: String]
    ) -> String {
        let string =
            text.string
                as NSString

        var result =
            ""

        text.enumerateAttributes(
            in:
                range
        ) {
            attributes,
            subrange,
            _
            in

            var run =
                xml(
                    string.substring(
                        with:
                            subrange
                    )
                )
                .replacingOccurrences(
                    of:
                        "\u{2028}",
                    with:
                        "<br/>"
                )
                .replacingOccurrences(
                    of:
                        "\u{2029}",
                    with:
                        "<br/>"
                )

            if let font =
                attributes[
                    .font
                ]
                as? NSFont {
                let traits =
                    NSFontManager
                        .shared
                        .traits(
                            of:
                                font
                        )

                if traits.contains(
                    .italicFontMask
                ) {
                    run =
                        "<em>\(run)</em>"
                }

                if traits.contains(
                    .boldFontMask
                ) {
                    run =
                        "<strong>\(run)</strong>"
                }
            }

            if let reference =
                noteReference(
                    attributes:
                        attributes,
                    content:
                        run
                ) {
                run =
                    reference
            } else {
                let target =
                    (
                        attributes[
                            .link
                        ]
                        as? URL
                    )?
                    .absoluteString
                    ?? (
                        attributes[
                            .link
                        ]
                        as? String
                    )

                if let target,
                   let scheme =
                    URL(
                        string:
                            target
                    )?
                    .scheme?
                    .lowercased(),
                   [
                        "http",
                        "https",
                        "mailto"
                   ]
                    .contains(
                        scheme
                    ) {
                    run =
                        "<a href=\"\(xml(target))\">\(run)</a>"
                } else if let target, target.hasPrefix("#"), let resolved = bookmarkTargets[String(target.dropFirst()).lowercased()] {
                    run = "<a href=\"#\(xml(resolved))\">\(run)</a>"
                }
            }

            result +=
                run
        }

        return result
    }

    private static func noteReference(
        attributes:
            [NSAttributedString.Key: Any],
        content: String
    ) -> String? {
        if let payload =
            attributes[
                .footnote
            ]
            as? [String: String],
           let id =
            payload[
                "id"
            ] {
            let safeID =
                xml(
                    id
                )

            return
                "<a id=\"footnote-ref-\(safeID)\" "
                + "epub:type=\"noteref\" "
                + "href=\"#footnote-\(safeID)\">"
                + content
                + "</a>"
        }

        if let payload =
            attributes[
                .endnote
            ]
            as? [String: String],
           let id =
            payload[
                "id"
            ] {
            let safeID =
                xml(
                    id
                )

            return
                "<a id=\"endnote-ref-\(safeID)\" "
                + "epub:type=\"noteref\" "
                + "href=\"#endnote-\(safeID)\">"
                + content
                + "</a>"
        }

        return nil
    }

    private static func noteSections(
        footnotes: [Footnote],
        endnotes: [Endnote]
    ) -> String {
        var sections:
            [String] = []

        if !footnotes.isEmpty {
            let items =
                footnotes
                .enumerated()
                .map {
                    index,
                    note
                    in

                    let id =
                        xml(
                            note.id
                                .uuidString
                        )

                    return
                        "<li id=\"footnote-\(id)\" "
                        + "epub:type=\"footnote\">"
                        + "<span class=\"note-number\">\(index + 1). </span>"
                        + noteBody(
                            note.text
                        )
                        + " <a class=\"backlink\" "
                        + "href=\"#footnote-ref-\(id)\" "
                        + "aria-label=\"Back to footnote reference\">↩</a>"
                        + "</li>"
                }
                .joined(
                    separator:
                        "\n"
                )

            sections.append(
                "<section class=\"notes footnotes\" "
                + "epub:type=\"footnotes\">"
                + "<h2>Footnotes</h2>"
                + "<ol>"
                + items
                + "</ol>"
                + "</section>"
            )
        }

        if !endnotes.isEmpty {
            let items =
                endnotes
                .enumerated()
                .map {
                    index,
                    note
                    in

                    let id =
                        xml(
                            note.id
                                .uuidString
                        )

                    return
                        "<li id=\"endnote-\(id)\" "
                        + "epub:type=\"endnote\">"
                        + "<span class=\"note-number\">\(index + 1). </span>"
                        + noteBody(
                            note.text
                        )
                        + " <a class=\"backlink\" "
                        + "href=\"#endnote-ref-\(id)\" "
                        + "aria-label=\"Back to endnote reference\">↩</a>"
                        + "</li>"
                }
                .joined(
                    separator:
                        "\n"
                )

            sections.append(
                "<section class=\"notes endnotes\" "
                + "epub:type=\"endnotes\">"
                + "<h2>Endnotes</h2>"
                + "<ol>"
                + items
                + "</ol>"
                + "</section>"
            )
        }

        return sections.joined(
            separator:
                "\n"
        )
    }

    private static func noteBody(
        _ value: String
    ) -> String {
        xml(
            value
        )
        .replacingOccurrences(
            of:
                "\r\n",
            with:
                "<br/>"
        )
        .replacingOccurrences(
            of:
                "\r",
            with:
                "<br/>"
        )
        .replacingOccurrences(
            of:
                "\n",
            with:
                "<br/>"
        )
        .replacingOccurrences(
            of:
                "\u{2028}",
            with:
                "<br/>"
        )
        .replacingOccurrences(
            of:
                "\u{2029}",
            with:
                "<br/>"
        )
    }

    private static let container =
        """
        <?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/package.opf" media-type="application/oebps-package+xml"/></rootfiles></container>
        """

    private static func package(
        title: String,
        identifier: String,
        modified: String
    ) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="book-id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="book-id">urn:uuid:\(identifier)</dc:identifier><dc:title>\(title)</dc:title><dc:language>en</dc:language><meta property="dcterms:modified">\(modified)</meta></metadata><manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/><item id="content" href="content.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="content"/></spine></package>
        """
    }

    private struct EPUBHeading { var location: Int; var range: NSRange; var level: Int; var title: String }

    private static func semanticHeadings(in text: NSAttributedString) -> [EPUBHeading] {
        let source=text.string as NSString
        var result:[EPUBHeading]=[]
        var position=0
        while position < source.length {
            var start=0, end=0, contentsEnd=0
            source.getParagraphStart(&start,end:&end,contentsEnd:&contentsEnd,for:NSRange(location:position,length:0))
            if contentsEnd > start {
                let style=(text.attribute(.boldWriterStyle,at:start,effectiveRange:nil) as? String).flatMap(WriterStyle.init(rawValue:))
                if let level=style?.headingLevel, (1...6).contains(level) {
                    let headingTitle=source.substring(with:NSRange(location:start,length:contentsEnd-start)).trimmingCharacters(in:.whitespacesAndNewlines)
                    if !headingTitle.isEmpty { result.append(EPUBHeading(location:start,range:NSRange(location:start,length:contentsEnd-start),level:level,title:headingTitle)) }
                }
            }
            position=max(end,position+1)
        }
        return result
    }

    private static func nav(title: String, headings: [EPUBHeading], ids: [Int:String], maximumLevel: Int) -> String {
        let items=headings.filter { $0.level <= maximumLevel }
        var index=0
        func list(_ level:Int) -> String {
            var result="<ol>"
            while index < items.count {
                let item=items[index]
                if item.level < level { break }
                if item.level > level { result += list(item.level); continue }
                index += 1
                let target=ids[item.location] ?? "bold-heading-\(index)"
                result += "<li><a href=\"content.xhtml#\(xml(target))\">\(xml(item.title))</a>"
                if index < items.count && items[index].level > level { result += list(items[index].level) }
                result += "</li>"
            }
            return result + "</ol>"
        }
        let listContent=items.isEmpty ? "<ol><li><a href=\"content.xhtml\">\(xml(title))</a></li></ol>" : list(max(1,items.first?.level ?? 1))
        return "<?xml version=\"1.0\" encoding=\"UTF-8\"?><html xmlns=\"http://www.w3.org/1999/xhtml\"><head><title>\(xml(title))</title></head><body><nav xmlns:epub=\"http://www.idpf.org/2007/ops\" epub:type=\"toc\"><h1>\(xml(title))</h1>\(listContent)</nav></body></html>"
    }

    private static func content(
        title: String,
        paragraphs: String,
        notes: String
    ) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?><html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>\(title)</title><style>body{font-family:serif;line-height:1.55;margin:5%;}p{margin:.7em 0;white-space:pre-wrap;}.title{font-size:2em;}.subtitle{font-size:1.2em;}.quote,.block-quote{font-style:italic;}.caption{font-size:.8em;}blockquote{margin:1em 2em;}a[epub|type="noteref"]{vertical-align:super;font-size:.75em;text-decoration:none;}.notes{margin-top:2em;}.notes li{margin:.6em 0;}.backlink{text-decoration:none;}.note-number{font-weight:bold;}</style></head><body><h1>\(title)</h1>\(paragraphs)\(notes)</body></html>
        """
    }

    private static func xml(
        _ value: String
    ) -> String {
        var result =
            ""

        for scalar
            in value.unicodeScalars {
            switch scalar.value {
            case 0x26:
                result +=
                    "&amp;"

            case 0x3c:
                result +=
                    "&lt;"

            case 0x3e:
                result +=
                    "&gt;"

            case 0x22:
                result +=
                    "&quot;"

            case 0x27:
                result +=
                    "&apos;"

            case
                0x09,
                0x0a,
                0x0d,
                0x20...0xd7ff,
                0xe000...0xfffd,
                0x10000...0x10ffff:
                result
                    .unicodeScalars
                    .append(
                        scalar
                    )

            default:
                break
            }
        }

        return result
    }
}
