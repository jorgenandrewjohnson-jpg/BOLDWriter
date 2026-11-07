import AppKit
import PDFKit
import XCTest
@testable import BOLDWriter

@MainActor
final class ExportTests: XCTestCase {
    private func document() -> BOLDWriterDocument {
        let document = BOLDWriterDocument()
        let (text, metadata) = SampleDocumentFactory.make()
        document.replaceText(with: text)
        document.metadata = metadata
        return document
    }

    func testPDFExportIsValidAndPaginated() throws {
        let data = try ExportService.data(for: .pdf, document: document())
        XCTAssertTrue(data.starts(with: Data("%PDF".utf8)))
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertGreaterThanOrEqual(pdf.pageCount, 2)
        XCTAssertTrue(pdf.string?.contains("The Lantern at North Harbor") == true)
        XCTAssertTrue(pdf.string?.contains("Appendix") == true)
    }

    func testPDFHonorsExplicitPageBreakAndFooterWithoutPageNumbers() throws {
        var settings = PageSettings()
        settings.showsPageNumbers = false
        settings.footerText = "Private Draft"
        let data = try PDFExporter.data(from: NSAttributedString(string: "First page\u{000C}Second page", attributes: [.font: NSFont.systemFont(ofSize: 14)]), settings: settings)
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertEqual(pdf.pageCount, 2)
        XCTAssertTrue(pdf.page(at: 0)?.string?.contains("First page") == true)
        XCTAssertFalse(pdf.page(at: 0)?.string?.contains("Second page") == true)
        XCTAssertTrue(pdf.page(at: 1)?.string?.contains("Second page") == true)
        XCTAssertTrue(pdf.page(at: 1)?.string?.contains("Private Draft") == true)
    }

    func testPDFEmbedsSampleArtworkAndRejectsUnusableMargins() throws {
        let doc = document()
        let data = try PDFExporter.data(from: doc.text, settings: doc.metadata.page)
        XCTAssertNotNil(data.range(of: Data("/Subtype /Image".utf8)))
        doc.metadata.page.leftMargin = 600
        XCTAssertThrowsError(try PDFExporter.data(from: doc.text, settings: doc.metadata.page))
    }

    func testDOCXExportCreatesOpenXMLPackage() throws {
        let data = try ExportService.data(for: .docx, document: document())
        XCTAssertEqual(Array(data.prefix(2)), [0x50, 0x4b])
        XCTAssertNotNil(data.range(of: Data("word/document.xml".utf8)))
        XCTAssertNotNil(data.range(of: Data("Heading1".utf8)))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".docx")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let reopened = try NSAttributedString(url: url, options: [.documentType: NSAttributedString.DocumentType.officeOpenXML], documentAttributes: nil)
        XCTAssertTrue(reopened.string.contains("Lantern"))
    }

    func testDOCXRepresentsPageBreaksTablesAndListsAsOpenXML() throws {
        let text = NSAttributedString(string: "Before\u{000C}After\n• First\n• Second\n3. Third\n4. Fourth\nHeading\tDescription\n🌟\tA & B\nTail\n")
        let entries = try storedEntries(try DOCXExporter.data(from: text, title: "A & B"))
        let document = try xmlPart("word/document.xml", entries: entries)
        let numbering = try xmlPart("word/numbering.xml", entries: entries)
        XCTAssertEqual(try document.nodes(forXPath: "//*[local-name()='br' and @*[local-name()='type']='page']").count, 1)
        XCTAssertEqual(try document.nodes(forXPath: "//*[local-name()='tbl']").count, 1)
        XCTAssertEqual(try document.nodes(forXPath: "//*[local-name()='tr']").count, 2)
        XCTAssertEqual(try document.nodes(forXPath: "//*[local-name()='tc']").count, 4)
        XCTAssertEqual(try document.nodes(forXPath: "//*[local-name()='numPr']").count, 4)
        XCTAssertEqual(try numbering.nodes(forXPath: "//*[local-name()='num']").count, 2)
        XCTAssertEqual(try numbering.nodes(forXPath: "//*[local-name()='startOverride' and @*[local-name()='val']='3']").count, 1)
        let bodyText = document.rootElement()?.stringValue ?? ""
        XCTAssertTrue(bodyText.contains("🌟A & B"))
        XCTAssertTrue(bodyText.contains("First"))
        XCTAssertFalse(bodyText.contains("• First"))
        XCTAssertFalse(bodyText.contains("3. Third"))
        XCTAssertFalse(bodyText.contains("\u{000C}"))
    }

    func testDOCXKeepsTabSeparatedListsOutOfTablesAndSupportsNativeLists() throws {
        let native = NSMutableParagraphStyle()
        let list = NSTextList(markerFormat: .decimal, options: 0)
        list.startingItemNumber = 7
        native.textLists = [list]
        let text = NSMutableAttributedString(string: "\t•\tTabbed bullet\n\t2.\tTabbed number\n")
        text.append(NSAttributedString(string: "Native first\nNative second", attributes: [.paragraphStyle: native]))
        let entries = try storedEntries(try DOCXExporter.data(from: text, title: "Lists"))
        let document = try xmlPart("word/document.xml", entries: entries)
        let numbering = try xmlPart("word/numbering.xml", entries: entries)
        XCTAssertEqual(try document.nodes(forXPath: "//*[local-name()='tbl']").count, 0)
        XCTAssertEqual(try document.nodes(forXPath: "//*[local-name()='numPr']").count, 4)
        XCTAssertEqual(try numbering.nodes(forXPath: "//*[local-name()='num']").count, 3)
        XCTAssertEqual(try numbering.nodes(forXPath: "//*[local-name()='startOverride' and @*[local-name()='val']='7']").count, 1)
    }

    func testDOCXPreservesHyperlinksAlignmentEmphasisAndPageSettings() throws {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .justified
        let font = NSFontManager.shared.convert(NSFont.boldSystemFont(ofSize: 18), toHaveTrait: .italicFontMask)
        let text = NSMutableAttributedString(string: "Chapter\nLinked & emphasized", attributes: [.font: font, .paragraphStyle: paragraph])
        text.addAttribute(.boldWriterStyle, value: WriterStyle.heading2.rawValue, range: NSRange(location: 0, length: 7))
        text.addAttribute(.link, value: URL(string: "https://example.com/?a=1&b=2")!, range: NSRange(location: 8, length: text.length - 8))
        var settings = PageSettings()
        settings.paper = .a4
        settings.landscape = true
        settings.leftMargin = 36
        settings.rightMargin = 54
        let entries = try storedEntries(try DOCXExporter.data(from: text, title: "A \"Title\"", settings: settings))
        let document = try xmlPart("word/document.xml", entries: entries)
        let relationships = try xmlPart("word/_rels/document.xml.rels", entries: entries)
        XCTAssertEqual(try document.nodes(forXPath: "//*[local-name()='pStyle' and @*[local-name()='val']='Heading2']").count, 1)
        XCTAssertEqual(try document.nodes(forXPath: "//*[local-name()='jc' and @*[local-name()='val']='both']").count, 2)
        XCTAssertGreaterThan(try document.nodes(forXPath: "//*[local-name()='b']").count, 0)
        XCTAssertGreaterThan(try document.nodes(forXPath: "//*[local-name()='i']").count, 0)
        XCTAssertEqual(try document.nodes(forXPath: "//*[local-name()='hyperlink']").count, 1)
        let relationship = try XCTUnwrap(try relationships.nodes(forXPath: "//*[local-name()='Relationship' and @TargetMode='External']").first as? XMLElement)
        XCTAssertEqual(relationship.attribute(forName: "Target")?.stringValue, "https://example.com/?a=1&b=2")
        let page = try XCTUnwrap(try document.nodes(forXPath: "//*[local-name()='pgSz']").first as? XMLElement)
        XCTAssertEqual(page.attribute(forName: "w:orient")?.stringValue, "landscape")
        XCTAssertEqual(page.attribute(forName: "w:w")?.stringValue, "16838")
        XCTAssertEqual(page.attribute(forName: "w:h")?.stringValue, "11906")
        let margin = try XCTUnwrap(try document.nodes(forXPath: "//*[local-name()='pgMar']").first as? XMLElement)
        XCTAssertEqual(margin.attribute(forName: "w:left")?.stringValue, "720")
        XCTAssertEqual(margin.attribute(forName: "w:right")?.stringValue, "1080")
    }

    func testDOCXPadsUnevenTableRowsAndFiltersInvalidXMLCharacters() throws {
        let text = NSAttributedString(string: "A\tB\tC\r\nD\t\r\n\u{0001}Safe\u{000C}End\u{2028}Line\u{2029}Final")
        let entries = try storedEntries(try DOCXExporter.data(from: text, title: "Title\u{0002}"))
        for (path, _) in entries where path.hasSuffix(".xml") || path.hasSuffix(".rels") { _ = try xmlPart(path, entries: entries) }
        let document = try xmlPart("word/document.xml", entries: entries)
        XCTAssertEqual(try document.nodes(forXPath: "//*[local-name()='tc']").count, 6)
        XCTAssertEqual(try document.nodes(forXPath: "//*[local-name()='br']").count, 2)
        XCTAssertTrue(document.rootElement()?.stringValue?.contains("SafeEndLineFinal") == true)
        _ = try xmlPart("word/document.xml", entries: try storedEntries(try DOCXExporter.data(from: NSAttributedString(), title: "Empty")))
    }

    func testEPUBHasRequiredEntriesAndMimetypeFirst() throws {
        let data = try ExportService.data(for: .epub, document: document())
        XCTAssertEqual(Array(data.prefix(2)), [0x50, 0x4b])
        XCTAssertNotNil(data.range(of: Data("application/epub+zip".utf8)))
        XCTAssertNotNil(data.range(of: Data("META-INF/container.xml".utf8)))
        XCTAssertNotNil(data.range(of: Data("OEBPS/package.opf".utf8)))
        let entries = try storedEntries(data)
        XCTAssertEqual(entries.first?.0, "mimetype")
        XCTAssertEqual(entries.first?.1, Data("application/epub+zip".utf8))
        let package = try xmlPart("OEBPS/package.opf", entries: entries)
        let modified = try XCTUnwrap(try package.nodes(forXPath: "//*[local-name()='meta' and @property='dcterms:modified']").first?.stringValue)
        XCTAssertNotNil(modified.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$", options: .regularExpression))
        for path in ["META-INF/container.xml", "OEBPS/nav.xhtml", "OEBPS/content.xhtml"] { _ = try xmlPart(path, entries: entries) }
    }

    func testEPUBPreservesHeadingStylesAndInlineEmphasis() throws {
        let text = NSMutableAttributedString(string: "A Heading\r\nBold then italic & linked", attributes: [.font: WriterStyle.normal.font])
        text.addAttribute(.boldWriterStyle, value: WriterStyle.heading3.rawValue, range: NSRange(location: 0, length: 9))
        text.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 15), range: NSRange(location: 11, length: 4))
        text.addAttribute(.font, value: WriterStyle.normal.font.withItalicTrait(), range: NSRange(location: 21, length: 6))
        text.addAttribute(.link, value: "https://example.com/?a=1&b=2", range: NSRange(location: 30, length: 6))
        let entries = try storedEntries(EPUBExporter.data(from: text, title: "A & B"))
        let content = try xmlPart("OEBPS/content.xhtml", entries: entries)
        XCTAssertEqual(try content.nodes(forXPath: "//*[local-name()='h3']").first?.stringValue, "A Heading")
        XCTAssertEqual(try content.nodes(forXPath: "//*[local-name()='strong']").first?.stringValue, "Bold")
        XCTAssertEqual(try content.nodes(forXPath: "//*[local-name()='em']").first?.stringValue, "italic")
        let link = try XCTUnwrap(try content.nodes(forXPath: "//*[local-name()='a']").first as? XMLElement)
        XCTAssertEqual(link.attribute(forName: "href")?.stringValue, "https://example.com/?a=1&b=2")
        XCTAssertTrue(content.rootElement()?.stringValue?.contains("Bold then italic & linked") == true)
    }

    func testEPUBEmptyAndControlCharacterContentIsValidXML() throws {
        for text in [NSAttributedString(), NSAttributedString(string: "Text\u{000C}After\u{0001}Safe\u{2028}Line\u{2029}Paragraph")] {
            let entries = try storedEntries(EPUBExporter.data(from: text, title: "Title\u{0002}"))
            for (path, _) in entries where path.hasSuffix(".xml") || path.hasSuffix(".opf") || path.hasSuffix(".xhtml") { _ = try xmlPart(path, entries: entries) }
        }
    }

    func testEPUBExportsLinkedFootnotesAndEndnotes()
        throws {

        let text =
            NSMutableAttributedString(
                string:
                    "Body "
            )

        let footnote =
            Footnote(
                text:
                    "Foot & <one>",
                location:
                    0,
                length:
                    1
            )

        text.append(
            Footnotes.marker(
                footnote,
                number:
                    1
            )
        )

        text.append(
            NSAttributedString(
                string:
                    " middle "
            )
        )

        let endnote =
            Endnote(
                text:
                    "End <two> & more",
                location:
                    0,
                length:
                    1
            )

        text.append(
            Endnotes.marker(
                endnote,
                number:
                    1
            )
        )

        let data =
            try EPUBExporter.data(
                from:
                    text,
                title:
                    "Notes"
            )

        let entries =
            try storedEntries(
                data
            )

        let contentData =
            try XCTUnwrap(
                entries.first {
                    $0.0
                        == "OEBPS/content.xhtml"
                }?
                .1
            )

        let source =
            String(
                decoding:
                    contentData,
                as:
                    UTF8.self
            )

        XCTAssertTrue(
            source.contains(
                "xmlns:epub=\"http://www.idpf.org/2007/ops\""
            )
        )

        XCTAssertEqual(
            source.components(
                separatedBy:
                    "epub:type=\"noteref\""
            )
            .count
                - 1,
            2
        )

        XCTAssertTrue(
            source.contains(
                "epub:type=\"footnotes\""
            )
        )

        XCTAssertTrue(
            source.contains(
                "epub:type=\"footnote\""
            )
        )

        XCTAssertTrue(
            source.contains(
                "epub:type=\"endnotes\""
            )
        )

        XCTAssertTrue(
            source.contains(
                "epub:type=\"endnote\""
            )
        )

        XCTAssertTrue(
            source.contains(
                "Foot &amp; &lt;one&gt;"
            )
        )

        XCTAssertTrue(
            source.contains(
                "End &lt;two&gt; &amp; more"
            )
        )

        XCTAssertTrue(
            source.contains(
                "href=\"#footnote-\(footnote.id.uuidString)\""
            )
        )

        XCTAssertTrue(
            source.contains(
                "href=\"#endnote-\(endnote.id.uuidString)\""
            )
        )

        XCTAssertTrue(
            source.contains(
                "href=\"#footnote-ref-\(footnote.id.uuidString)\""
            )
        )

        XCTAssertTrue(
            source.contains(
                "href=\"#endnote-ref-\(endnote.id.uuidString)\""
            )
        )

        let document =
            try xmlPart(
                "OEBPS/content.xhtml",
                entries:
                    entries
            )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='h2']"
            )
            .compactMap(
                \.stringValue
            ),
            [
                "Footnotes",
                "Endnotes"
            ]
        )
    }

    func testEPUBNoteNumbersRenumberIndependently()
        throws {

        let text =
            NSMutableAttributedString(
                string:
                    "Start "
            )

        for index in 1...2 {
            text.append(
                Footnotes.marker(
                    Footnote(
                        text:
                            "Foot \(index)",
                        location:
                            0,
                        length:
                            1
                    ),
                    number:
                        9
                )
            )

            text.append(
                NSAttributedString(
                    string:
                        " "
                )
            )
        }

        for index in 1...2 {
            text.append(
                Endnotes.marker(
                    Endnote(
                        text:
                            "End \(index)",
                        location:
                            0,
                        length:
                            1
                    ),
                    number:
                        8
                )
            )

            text.append(
                NSAttributedString(
                    string:
                        " "
                )
            )
        }

        let entries =
            try storedEntries(
                try EPUBExporter.data(
                    from:
                        text,
                    title:
                        "Renumber"
                )
            )

        let contentData =
            try XCTUnwrap(
                entries.first {
                    $0.0
                        == "OEBPS/content.xhtml"
                }?
                .1
            )

        let source =
            String(
                decoding:
                    contentData,
                as:
                    UTF8.self
            )

        XCTAssertTrue(
            source.contains(
                ">1. </span>Foot 1"
            )
        )

        XCTAssertTrue(
            source.contains(
                ">2. </span>Foot 2"
            )
        )

        XCTAssertTrue(
            source.contains(
                ">1. </span>End 1"
            )
        )

        XCTAssertTrue(
            source.contains(
                ">2. </span>End 2"
            )
        )
    }

    func testPlainAndMarkdownExport() throws {
        let document = document()
        let plain = try ExportService.data(for: .plainText, document: document)
        let markdown = try ExportService.data(for: .markdown, document: document)
        XCTAssertTrue(String(decoding: plain, as: UTF8.self).contains("North Harbor"))
        XCTAssertTrue(String(decoding: markdown, as: UTF8.self).contains("# Chapter One"))
    }

    /// The application emits stored ZIP entries; inspect exact part boundaries, not raw substring matches.
    private func storedEntries(_ archive: Data) throws -> [(String, Data)] {
        let bytes = [UInt8](archive)
        func number(at index: Int, length: Int) throws -> Int {
            guard index >= 0, index + length <= bytes.count else { throw ArchiveTestError.invalidArchive }
            return (0..<length).reduce(0) { $0 | Int(bytes[index + $1]) << ($1 * 8) }
        }
        var offset = 0
        var entries: [(String, Data)] = []
        while try number(at: offset, length: 4) == 0x04034b50 {
            XCTAssertEqual(try number(at: offset + 8, length: 2), 0, "Export entries must be uncompressed")
            let length = try number(at: offset + 18, length: 4)
            let nameLength = try number(at: offset + 26, length: 2)
            let extraLength = try number(at: offset + 28, length: 2)
            let nameStart = offset + 30
            let dataStart = nameStart + nameLength + extraLength
            let end = dataStart + length
            guard nameStart + nameLength <= bytes.count, end <= bytes.count else { throw ArchiveTestError.invalidArchive }
            entries.append((String(decoding: bytes[nameStart..<(nameStart + nameLength)], as: UTF8.self), Data(bytes[dataStart..<end])))
            offset = end
        }
        return entries
    }

    private func xmlPart(_ path: String, entries: [(String, Data)]) throws -> XMLDocument {
        let data = try XCTUnwrap(entries.first { $0.0 == path }?.1, "Missing \(path)")
        return try XMLDocument(data: data)
    }

    private enum ArchiveTestError: Error { case invalidArchive }

    func testDOCXInternalHyperlinkUsesExportedBookmarkName()
        throws {

        let text =
            NSMutableAttributedString(
                string:
                    "Jump Target"
            )

        text.addAttribute(
            .link,
            value:
                "#Chapter One",
            range:
                NSRange(
                    location:
                        0,
                    length:
                        4
                )
        )

        let bookmark =
            DocumentBookmark(
                name:
                    "Chapter One",
                location:
                    5
            )

        let data =
            try DOCXExporter.data(
                from:
                    text,
                title:
                    "Internal Link",
                bookmarks: [
                    bookmark
                ]
            )

        let entries =
            try storedEntries(
                data
            )

        let document =
            try xmlPart(
                "word/document.xml",
                entries:
                    entries
            )

        let bookmarkStart =
            try XCTUnwrap(
                try document.nodes(
                    forXPath:
                        "//*[local-name()='bookmarkStart']"
                )
                .first
                    as? XMLElement
            )

        let hyperlink =
            try XCTUnwrap(
                try document.nodes(
                    forXPath:
                        "//*[local-name()='hyperlink']"
                )
                .first
                    as? XMLElement
            )

        let exportedBookmarkName =
            try XCTUnwrap(
                bookmarkStart.attributes?
                    .first {
                        $0.localName
                            == "name"
                    }?
                    .stringValue
            )

        let exportedAnchor =
            try XCTUnwrap(
                hyperlink.attributes?
                    .first {
                        $0.localName
                            == "anchor"
                    }?
                    .stringValue
            )

        XCTAssertEqual(
            exportedBookmarkName,
            "Chapter_One"
        )

        XCTAssertEqual(
            exportedAnchor,
            exportedBookmarkName
        )
    }

    func testDOCXHyperlinksRoundTripThroughImporter()
        throws {

        let text =
            NSMutableAttributedString(
                string:
                    "External Internal Target"
            )

        text.addAttribute(
            .link,
            value:
                URL(
                    string:
                        "https://example.com/?a=1&b=2"
                )!,
            range:
                NSRange(
                    location:
                        0,
                    length:
                        8
                )
        )

        text.addAttribute(
            .link,
            value:
                "#Chapter One",
            range:
                NSRange(
                    location:
                        9,
                    length:
                        8
                )
        )

        let bookmark =
            DocumentBookmark(
                name:
                    "Chapter One",
                location:
                    18
            )

        let data =
            try DOCXExporter.data(
                from:
                    text,
                title:
                    "Hyperlink Round Trip",
                bookmarks: [
                    bookmark
                ]
            )

        let imported =
            try DOCXImporter
                .importedDocument(
                    from:
                        data
                )

        XCTAssertEqual(
            imported.text.string,
            "External Internal Target"
        )

        let external =
            imported.text.attribute(
                .link,
                at:
                    0,
                effectiveRange:
                    nil
            )

        let externalString =
            (external as? URL)?
                .absoluteString
            ?? external as? String

        XCTAssertEqual(
            externalString,
            "https://example.com/?a=1&b=2"
        )

        let internalLink =
            imported.text.attribute(
                .link,
                at:
                    9,
                effectiveRange:
                    nil
            )

        let internalString =
            (internalLink as? URL)?
                .absoluteString
            ?? internalLink as? String

        XCTAssertEqual(
            internalString,
            "#Chapter_One"
        )

        XCTAssertEqual(
            imported.bookmarks.count,
            1
        )

        XCTAssertEqual(
            imported.bookmarks
                .first?
                .name,
            "Chapter_One"
        )

        XCTAssertEqual(
            imported.bookmarks
                .first?
                .location,
            18
        )
    }

    func testDOCXExternalHyperlinkRelationshipRemainsExternal()
        throws {

        let text =
            NSMutableAttributedString(
                string:
                    "External"
            )

        text.addAttribute(
            .link,
            value:
                "https://example.com/path?q=one&x=two",
            range:
                NSRange(
                    location:
                        0,
                    length:
                        text.length
                )
        )

        let entries =
            try storedEntries(
                try DOCXExporter.data(
                    from:
                        text,
                    title:
                        "External Link"
                )
            )

        let document =
            try xmlPart(
                "word/document.xml",
                entries:
                    entries
            )

        let relationships =
            try xmlPart(
                "word/_rels/document.xml.rels",
                entries:
                    entries
            )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='hyperlink' and @*[local-name()='id']]"
            )
            .count,
            1
        )

        let relationship =
            try XCTUnwrap(
                try relationships.nodes(
                    forXPath:
                        "//*[local-name()='Relationship' and contains(@Type, '/hyperlink')]"
                )
                .first
                    as? XMLElement
            )

        XCTAssertEqual(
            relationship.attribute(
                forName:
                    "TargetMode"
            )?
            .stringValue,
            "External"
        )

        XCTAssertEqual(
            relationship.attribute(
                forName:
                    "Target"
            )?
            .stringValue,
            "https://example.com/path?q=one&x=two"
        )
    }

}

// MARK: - Direct RTF / HTML export coverage

extension ExportTests {
    func testRTFExportProducesDecodableRichTextDocument()
        throws
    {
        let source =
            document()

        XCTAssertFalse(
            source.text.string.isEmpty
        )

        let data =
            try ExportService.data(
                for: .rtf,
                document: source
            )

        XCTAssertFalse(
            data.isEmpty
        )

        XCTAssertTrue(
            data.starts(
                with:
                    Data(
                        "{\\rtf".utf8
                    )
            ),
            "RTF export should begin with an RTF document signature."
        )

        let decoded =
            try NSAttributedString(
                data: data,
                options: [
                    .documentType:
                        NSAttributedString
                        .DocumentType
                        .rtf
                ],
                documentAttributes:
                    nil
            )

        XCTAssertFalse(
            decoded.string
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )
                .isEmpty,
            "RTF export should decode back into non-empty attributed text."
        )
    }

    func testHTMLExportProducesDecodableHTMLDocument()
        throws
    {
        let source =
            document()

        XCTAssertFalse(
            source.text.string.isEmpty
        )

        let data =
            try ExportService.data(
                for: .html,
                document: source
            )

        XCTAssertFalse(
            data.isEmpty
        )

        let html =
            try XCTUnwrap(
                String(
                    data: data,
                    encoding: .utf8
                )
            )

        XCTAssertNotNil(
            html.range(
                of: "<html",
                options:
                    .caseInsensitive
            ),
            "HTML export should contain an HTML document element."
        )

        let decoded =
            try NSAttributedString(
                data: data,
                options: [
                    .documentType:
                        NSAttributedString
                        .DocumentType
                        .html,
                    .characterEncoding:
                        String
                        .Encoding
                        .utf8
                        .rawValue
                ],
                documentAttributes:
                    nil
            )

        XCTAssertFalse(
            decoded.string
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )
                .isEmpty,
            "HTML export should decode back into non-empty attributed text."
        )
    }
}

// MARK: - Export file-type safety

extension ExportTests {
    func testEveryExportFormatHasMatchingContentType()
        throws
    {
        for format in ExportFormat.allCases {
            let preferred =
                try XCTUnwrap(
                    format
                        .contentType
                        .preferredFilenameExtension
                )

            XCTAssertEqual(
                preferred.lowercased(),
                format.extensionName,
                "UTType should agree with the selected export extension for \(format.rawValue)."
            )
        }
    }

    func testExportWriteNormalizesDestinationExtensionForEveryFormat()
        throws
    {
        let directory =
            FileManager
                .default
                .temporaryDirectory
                .appendingPathComponent(
                    "BOLDWriter-Export-Extension-\(UUID().uuidString)",
                    isDirectory: true
                )

        try FileManager
            .default
            .createDirectory(
                at: directory,
                withIntermediateDirectories:
                    true
            )

        defer {
            try? FileManager
                .default
                .removeItem(
                    at: directory
                )
        }

        for format in ExportFormat.allCases {
            let requested =
                directory
                    .appendingPathComponent(
                        "Sample-\(format.extensionName).wrong"
                    )

            let destination =
                try ExportService.write(
                    format,
                    document: document(),
                    to: requested
                )

            XCTAssertEqual(
                destination
                    .pathExtension
                    .lowercased(),
                format.extensionName
            )

            XCTAssertEqual(
                destination
                    .deletingPathExtension()
                    .lastPathComponent,
                "Sample-\(format.extensionName)"
            )

            XCTAssertTrue(
                FileManager
                    .default
                    .fileExists(
                        atPath:
                            destination.path
                    ),
                "Expected \(format.rawValue) export to exist at its normalized destination."
            )

            XCTAssertFalse(
                FileManager
                    .default
                    .fileExists(
                        atPath:
                            requested.path
                    ),
                "Export must not write \(format.rawValue) bytes under the deliberately wrong .wrong extension."
            )

            XCTAssertFalse(
                try Data(
                    contentsOf:
                        destination
                )
                .isEmpty
            )
        }
    }

    func testExportWriteRejectsNativeManuscriptBeforeExtensionNormalization()
        throws
    {
        let directory =
            FileManager
                .default
                .temporaryDirectory
                .appendingPathComponent(
                    "BOLDWriter-Export-Native-Protection-\(UUID().uuidString)",
                    isDirectory: true
                )

        try FileManager
            .default
            .createDirectory(
                at: directory,
                withIntermediateDirectories:
                    true
            )

        defer {
            try? FileManager
                .default
                .removeItem(
                    at: directory
                )
        }

        let nativeURL =
            directory
                .appendingPathComponent(
                    "Protected.boldwriter"
                )

        XCTAssertThrowsError(
            try ExportService.write(
                .pdf,
                document: document(),
                to: nativeURL
            )
        )

        XCTAssertFalse(
            FileManager
                .default
                .fileExists(
                    atPath:
                        nativeURL.path
                )
        )

        XCTAssertFalse(
            FileManager
                .default
                .fileExists(
                    atPath:
                        nativeURL
                            .deletingPathExtension()
                            .appendingPathExtension(
                                "pdf"
                            )
                            .path
                ),
            "Native manuscript protection must run before extension normalization."
        )
    }
}




// MARK: - Word final-section column balancing — PDF parity

extension ExportTests {
    private func wordColumnBalanceParityText(
        paragraphs: Int
    ) -> NSAttributedString {
        NSAttributedString(
            string:
                (1...paragraphs)
                .map {
                    String(
                        format:
                            "P%03d",
                        $0
                    )
                }
                .joined(
                    separator:
                        "\n"
                ),
            attributes:
                [
                    .font:
                        NSFont.systemFont(
                            ofSize:
                                14
                        )
                ]
        )
    }

    private func screenColumnHeightsForWordPDFParity(
        _ editor: PaginatedEditor
    ) -> [[CGFloat]] {
        editor
            .pageContainerIndices
            .map {
                indices in

                indices.compactMap {
                    index -> CGFloat? in

                    guard
                        index >= 0,
                        index
                            < editor.flow
                                .manager
                                .textContainers
                                .count
                    else {
                        return nil
                    }

                    return editor.flow
                        .manager
                        .textContainers[
                            index
                        ]
                        .containerSize
                        .height
                }
            }
    }

    private func assertWordPDFColumnHeightsEqual(
        _ lhs: [CGFloat],
        _ rhs: [CGFloat],
        accuracy: CGFloat = 0.1,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            lhs.count,
            rhs.count,
            file:
                file,
            line:
                line
        )

        for (
            left,
            right
        ) in zip(
            lhs,
            rhs
        ) {
            XCTAssertEqual(
                left,
                right,
                accuracy:
                    accuracy,
                file:
                    file,
                line:
                    line
            )
        }
    }

    func testPDFBalancesFinalTwoColumnPageInParityWithScreen()
        throws
    {
        var settings =
            PageSettings()

        settings.columnCount =
            2

        settings.columnSpacing =
            24

        let geometry =
            try PageGeometry(
                settings
            )

        let text =
            wordColumnBalanceParityText(
                paragraphs:
                    50
            )

        let editor =
            PaginatedEditor(
                text:
                    text
            )

        editor.configure(
            printLayout:
                true,
            settings:
                settings,
            zoom:
                1,
            viewportWidth:
                1000
        )

        editor.finishPagination()

        XCTAssertNil(
            editor.lastLayoutError
        )

        XCTAssertTrue(
            editor.layoutComplete
        )

        var pdfRanges:
            [NSRange] = []

        var pdfHeights:
            [[CGFloat]] = []

        let data =
            try PDFExporter.data(
                from:
                    text,
                settings:
                    settings,
                pageColumnHeightSink: {
                    pdfHeights =
                        $0
                },
                pageRangeSink: {
                    pdfRanges =
                        $0
                }
            )

        XCTAssertFalse(
            data.isEmpty
        )

        XCTAssertEqual(
            pdfRanges,
            editor.pageRanges
        )

        let screenHeights =
            screenColumnHeightsForWordPDFParity(
                editor
            )

        XCTAssertEqual(
            pdfHeights.count,
            1
        )

        XCTAssertEqual(
            screenHeights.count,
            1
        )

        XCTAssertEqual(
            pdfHeights[0].count,
            2
        )

        assertWordPDFColumnHeightsEqual(
            pdfHeights[0],
            screenHeights[0]
        )

        XCTAssertLessThan(
            pdfHeights[0].max()
                ?? geometry
                    .contentSize
                    .height,
            geometry
                .contentSize
                .height - 1
        )

        print(
            "COLUMN_BALANCE_PDF_2 "
            + "pdf=\(pdfHeights) "
            + "screen=\(screenHeights) "
            + "ranges=\(pdfRanges)"
        )
    }

    func testPDFBalancesFinalThreeColumnPageInParityWithScreen()
        throws
    {
        var settings =
            PageSettings()

        settings.columnCount =
            3

        settings.columnSpacing =
            24

        let geometry =
            try PageGeometry(
                settings
            )

        let text =
            wordColumnBalanceParityText(
                paragraphs:
                    50
            )

        let editor =
            PaginatedEditor(
                text:
                    text
            )

        editor.configure(
            printLayout:
                true,
            settings:
                settings,
            zoom:
                1,
            viewportWidth:
                1000
        )

        editor.finishPagination()

        XCTAssertNil(
            editor.lastLayoutError
        )

        XCTAssertTrue(
            editor.layoutComplete
        )

        var pdfRanges:
            [NSRange] = []

        var pdfHeights:
            [[CGFloat]] = []

        let data =
            try PDFExporter.data(
                from:
                    text,
                settings:
                    settings,
                pageColumnHeightSink: {
                    pdfHeights =
                        $0
                },
                pageRangeSink: {
                    pdfRanges =
                        $0
                }
            )

        XCTAssertFalse(
            data.isEmpty
        )

        XCTAssertEqual(
            pdfRanges,
            editor.pageRanges
        )

        let screenHeights =
            screenColumnHeightsForWordPDFParity(
                editor
            )

        XCTAssertEqual(
            pdfHeights.count,
            1
        )

        XCTAssertEqual(
            screenHeights.count,
            1
        )

        XCTAssertEqual(
            pdfHeights[0].count,
            3
        )

        assertWordPDFColumnHeightsEqual(
            pdfHeights[0],
            screenHeights[0]
        )

        XCTAssertLessThan(
            pdfHeights[0].max()
                ?? geometry
                    .contentSize
                    .height,
            geometry
                .contentSize
                .height - 1
        )

        print(
            "COLUMN_BALANCE_PDF_3 "
            + "pdf=\(pdfHeights) "
            + "screen=\(screenHeights) "
            + "ranges=\(pdfRanges)"
        )
    }

    func testPDFKeepsIntermediateColumnsFullHeightInParityWithScreen()
        throws
    {
        var settings =
            PageSettings()

        settings.columnCount =
            2

        settings.columnSpacing =
            24

        let geometry =
            try PageGeometry(
                settings
            )

        let text =
            wordColumnBalanceParityText(
                paragraphs:
                    100
            )

        let editor =
            PaginatedEditor(
                text:
                    text
            )

        editor.configure(
            printLayout:
                true,
            settings:
                settings,
            zoom:
                1,
            viewportWidth:
                1000
        )

        editor.finishPagination()

        XCTAssertNil(
            editor.lastLayoutError
        )

        XCTAssertGreaterThanOrEqual(
            editor.pages.count,
            2
        )

        var pdfRanges:
            [NSRange] = []

        var pdfHeights:
            [[CGFloat]] = []

        let data =
            try PDFExporter.data(
                from:
                    text,
                settings:
                    settings,
                pageColumnHeightSink: {
                    pdfHeights =
                        $0
                },
                pageRangeSink: {
                    pdfRanges =
                        $0
                }
            )

        XCTAssertFalse(
            data.isEmpty
        )

        XCTAssertEqual(
            pdfRanges,
            editor.pageRanges
        )

        let screenHeights =
            screenColumnHeightsForWordPDFParity(
                editor
            )

        XCTAssertEqual(
            pdfHeights.count,
            screenHeights.count
        )

        assertWordPDFColumnHeightsEqual(
            pdfHeights[0],
            screenHeights[0]
        )

        for height
            in pdfHeights[0] {

            XCTAssertEqual(
                height,
                geometry
                    .contentSize
                    .height,
                accuracy:
                    0.5
            )
        }

        let finalIndex =
            pdfHeights.count - 1

        assertWordPDFColumnHeightsEqual(
            pdfHeights[
                finalIndex
            ],
            screenHeights[
                finalIndex
            ]
        )

        XCTAssertLessThan(
            pdfHeights[
                finalIndex
            ]
            .max()
                ?? geometry
                    .contentSize
                    .height,
            geometry
                .contentSize
                .height - 1
        )

        print(
            "COLUMN_BALANCE_PDF_FINAL_ONLY "
            + "pages=\(pdfHeights.count) "
            + "pdf=\(pdfHeights) "
            + "screen=\(screenHeights) "
            + "ranges=\(pdfRanges)"
        )
    }

    func testPDFHonorsNoColumnBalanceInParityWithScreen()
        throws
    {
        var settings =
            PageSettings()

        settings.columnCount =
            2

        settings.columnSpacing =
            24

        settings.noColumnBalance =
            true

        let geometry =
            try PageGeometry(
                settings
            )

        let text =
            wordColumnBalanceParityText(
                paragraphs:
                    50
            )

        let editor =
            PaginatedEditor(
                text:
                    text
            )

        editor.configure(
            printLayout:
                true,
            settings:
                settings,
            zoom:
                1,
            viewportWidth:
                1000
        )

        editor.finishPagination()

        XCTAssertNil(
            editor.lastLayoutError
        )

        var pdfRanges:
            [NSRange] = []

        var pdfHeights:
            [[CGFloat]] = []

        let data =
            try PDFExporter.data(
                from:
                    text,
                settings:
                    settings,
                pageColumnHeightSink: {
                    pdfHeights =
                        $0
                },
                pageRangeSink: {
                    pdfRanges =
                        $0
                }
            )

        XCTAssertFalse(
            data.isEmpty
        )

        XCTAssertEqual(
            pdfRanges,
            editor.pageRanges
        )

        let screenHeights =
            screenColumnHeightsForWordPDFParity(
                editor
            )

        XCTAssertEqual(
            pdfHeights.count,
            1
        )

        XCTAssertEqual(
            pdfHeights[0].count,
            2
        )

        assertWordPDFColumnHeightsEqual(
            pdfHeights[0],
            screenHeights[0]
        )

        for height
            in pdfHeights[0] {

            XCTAssertEqual(
                height,
                geometry
                    .contentSize
                    .height,
                accuracy:
                    0.5
            )
        }

        print(
            "COLUMN_BALANCE_PDF_DISABLED "
            + "pdf=\(pdfHeights) "
            + "screen=\(screenHeights) "
            + "ranges=\(pdfRanges)"
        )
    }
}



// MARK: - Word multi-column vertical-justification PDF parity

extension ExportTests {
    private func wordMultiColumnVAlignPDFText(
        paragraphs: Int
    ) -> NSAttributedString {
        NSAttributedString(
            string:
                (1...paragraphs)
                .map {
                    String(
                        format:
                            "P%03d",
                        $0
                    )
                }
                .joined(
                    separator:
                        "\n"
                ),
            attributes:
                [
                    .font:
                        NSFont.systemFont(
                            ofSize:
                                14
                        )
                ]
        )
    }

    private func wordMultiColumnVAlignScreenBottoms(
        _ editor: PaginatedEditor,
        page: Int
    ) -> [CGFloat] {
        editor.pageContainerIndices[page]
            .map {
                index in

                let container =
                    editor.flow
                        .manager
                        .textContainers[index]

                let glyphs =
                    editor.flow
                        .manager
                        .glyphRange(
                            for:
                                container
                        )

                var bottom: CGFloat = 0

                editor.flow
                    .manager
                    .enumerateLineFragments(
                        forGlyphRange:
                            glyphs
                    ) {
                        _,
                        usedRect,
                        textContainer,
                        lineGlyphRange,
                        _ in

                        if textContainer === container,
                           lineGlyphRange.length > 0 {

                            bottom =
                                max(
                                    bottom,
                                    usedRect.maxY
                                )
                        }
                    }

                return bottom
            }
    }

    func testPDFMultiColumnVerticalJustificationMatchesScreenGeometry()
        throws
    {
        var settings =
            PageSettings()

        settings.columnCount =
            3

        settings.columnSpacing =
            24

        settings.verticalPageAlignment =
            .both

        let text =
            wordMultiColumnVAlignPDFText(
                paragraphs:
                    50
            )

        let editor =
            PaginatedEditor(
                text:
                    text
            )

        editor.configure(
            printLayout:
                true,
            settings:
                settings,
            zoom:
                1,
            viewportWidth:
                1000
        )

        editor.finishPagination()

        XCTAssertNil(
            editor.lastLayoutError
        )

        var pdfRanges: [NSRange] = []
        var pdfHeights: [[CGFloat]] = []
        var pdfBottoms: [[CGFloat]] = []

        let data =
            try PDFExporter.data(
                from:
                    text,
                settings:
                    settings,
                pageColumnHeightSink: {
                    pdfHeights =
                        $0
                },
                pageColumnBottomSink: {
                    pdfBottoms =
                        $0
                },
                pageRangeSink: {
                    pdfRanges =
                        $0
                }
            )

        XCTAssertFalse(
            data.isEmpty
        )

        XCTAssertEqual(
            pdfRanges,
            editor.pageRanges
        )

        XCTAssertEqual(
            pdfHeights.count,
            1
        )

        XCTAssertEqual(
            pdfBottoms.count,
            1
        )

        XCTAssertEqual(
            pdfHeights[0].count,
            3
        )

        XCTAssertEqual(
            pdfBottoms[0].count,
            3
        )

        let screenBottoms =
            wordMultiColumnVAlignScreenBottoms(
                editor,
                page:
                    0
            )

        let screenHeights =
            editor.pageContainerIndices[0]
                .map {
                    index in

                    editor.flow
                        .manager
                        .textContainers[index]
                        .containerSize
                        .height
                }

        for index in 0..<3 {
            XCTAssertEqual(
                pdfHeights[0][index],
                screenHeights[index],
                accuracy:
                    0.1
            )

            XCTAssertEqual(
                pdfBottoms[0][index],
                screenBottoms[index],
                accuracy:
                    0.1
            )
        }

        XCTAssertEqual(
            pdfBottoms[0][0],
            289,
            accuracy:
                0.1
        )

        XCTAssertEqual(
            pdfBottoms[0][1],
            289,
            accuracy:
                0.1
        )

        XCTAssertEqual(
            pdfBottoms[0][2],
            pdfHeights[0][2],
            accuracy:
                0.1
        )

        print(
            "WORD_VALIGN_MULTICOL_PDF_PARITY "
            + "ranges=\(pdfRanges) "
            + "pdfHeights=\(pdfHeights) "
            + "screenHeights=\(screenHeights) "
            + "pdfBottoms=\(pdfBottoms) "
            + "screenBottoms=\(screenBottoms)"
        )
    }

    func testPDFNoColumnBalanceVerticalBothRemainsFullHeightAndMatchesScreen()
        throws
    {
        var settings =
            PageSettings()

        settings.columnCount =
            2

        settings.columnSpacing =
            24

        settings.noColumnBalance =
            true

        settings.verticalPageAlignment =
            .both

        let geometry =
            try PageGeometry(
                settings
            )

        let text =
            wordMultiColumnVAlignPDFText(
                paragraphs:
                    50
            )

        let editor =
            PaginatedEditor(
                text:
                    text
            )

        editor.configure(
            printLayout:
                true,
            settings:
                settings,
            zoom:
                1,
            viewportWidth:
                1000
        )

        editor.finishPagination()

        XCTAssertNil(
            editor.lastLayoutError
        )

        var pdfRanges: [NSRange] = []
        var pdfHeights: [[CGFloat]] = []
        var pdfBottoms: [[CGFloat]] = []

        _ =
            try PDFExporter.data(
                from:
                    text,
                settings:
                    settings,
                pageColumnHeightSink: {
                    pdfHeights =
                        $0
                },
                pageColumnBottomSink: {
                    pdfBottoms =
                        $0
                },
                pageRangeSink: {
                    pdfRanges =
                        $0
                }
            )

        XCTAssertEqual(
            pdfRanges,
            editor.pageRanges
        )

        XCTAssertEqual(
            pdfHeights.count,
            1
        )

        XCTAssertEqual(
            pdfBottoms.count,
            1
        )

        XCTAssertEqual(
            pdfHeights[0].count,
            2
        )

        let screenBottoms =
            wordMultiColumnVAlignScreenBottoms(
                editor,
                page:
                    0
            )

        for index in 0..<2 {
            XCTAssertEqual(
                pdfHeights[0][index],
                geometry.contentSize.height,
                accuracy:
                    0.5
            )

            XCTAssertEqual(
                pdfBottoms[0][index],
                screenBottoms[index],
                accuracy:
                    0.1
            )

            XCTAssertEqual(
                pdfBottoms[0][index],
                geometry.contentSize.height,
                accuracy:
                    0.1
            )
        }

        print(
            "WORD_VALIGN_MULTICOL_PDF_NCB "
            + "ranges=\(pdfRanges) "
            + "heights=\(pdfHeights) "
            + "pdfBottoms=\(pdfBottoms) "
            + "screenBottoms=\(screenBottoms)"
        )
    }
}



// MARK: - Continuous / nextColumn final balancing PDF parity

extension ExportTests {
    private func sectionBalancePDFText(
        firstParagraphs: Int,
        secondParagraphs: Int
    ) -> (
        text: NSAttributedString,
        boundary: Int
    ) {
        let first =
            (1...firstParagraphs)
                .map {
                    String(
                        format:
                            "A%03d",
                        $0
                    )
                }
                .joined(
                    separator:
                        "\n"
                )
                + "\n"

        let second =
            (1...secondParagraphs)
                .map {
                    String(
                        format:
                            "B%03d",
                        $0
                    )
                }
                .joined(
                    separator:
                        "\n"
                )

        return (
            NSAttributedString(
                string:
                    first + second,
                attributes:
                    [
                        .font:
                            NSFont.systemFont(
                                ofSize:
                                    14
                            )
                    ]
            ),
            (
                first
                    as NSString
            )
            .length
        )
    }

    private func sectionBalancePDFActiveScreenHeights(
        _ editor: PaginatedEditor
    ) -> [[CGFloat]] {
        zip(
            editor.pageContainerIndices,
            editor.pageRanges
        )
        .map {
            indices,
            pageRange in

            let pageEnd =
                NSMaxRange(
                    pageRange
                )

            return indices.compactMap {
                index -> CGFloat? in

                guard
                    index >= 0,
                    index
                        < editor.flow
                            .manager
                            .textContainers
                            .count
                else {
                    return nil
                }

                let container =
                    editor.flow
                        .manager
                        .textContainers[
                            index
                        ]

                let glyphs =
                    editor.flow
                        .manager
                        .glyphRange(
                            for:
                                container
                        )

                let characters =
                    editor.flow
                        .manager
                        .characterRange(
                            forGlyphRange:
                                glyphs,
                            actualGlyphRange:
                                nil
                        )

                if characters.length == 0,
                   characters.location >= pageEnd {
                    return nil
                }

                return container
                    .containerSize
                    .height
            }
        }
    }

    private func assertSectionBalancePDFHeights(
        _ lhs: [CGFloat],
        _ rhs: [CGFloat],
        accuracy: CGFloat = 0.1,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            lhs.count,
            rhs.count,
            file:
                file,
            line:
                line
        )

        for (
            left,
            right
        ) in zip(
            lhs,
            rhs
        ) {
            XCTAssertEqual(
                left,
                right,
                accuracy:
                    accuracy,
                file:
                    file,
                line:
                    line
            )
        }
    }

    private func assertSectionBalancePDFParity(
        breakType: DocumentSection.BreakType,
        noColumnBalance: Bool
    ) throws {
        var first =
            PageSettings()

        first.columnCount =
            2

        first.columnSpacing =
            24

        var second =
            first

        if noColumnBalance {
            second.noColumnBalance =
                true
        }

        let source =
            sectionBalancePDFText(
                firstParagraphs:
                    8,
                secondParagraphs:
                    92
            )

        let sections =
            [
                DocumentSection(
                    location:
                        0,
                    page:
                        first
                ),

                DocumentSection(
                    location:
                        source.boundary,
                    page:
                        second,
                    breakType:
                        breakType
                )
            ]

        let editor =
            PaginatedEditor(
                text:
                    source.text
            )

        editor.configure(
            printLayout:
                true,
            settings:
                first,
            sections:
                sections,
            zoom:
                1,
            viewportWidth:
                1000
        )

        editor.finishPagination()

        XCTAssertNil(
            editor.lastLayoutError
        )

        var pdfRanges:
            [NSRange] = []

        var pdfHeights:
            [[CGFloat]] = []

        let data =
            try PDFExporter.data(
                from:
                    source.text,
                settings:
                    first,
                sections:
                    sections,
                pageColumnHeightSink: {
                    pdfHeights =
                        $0
                },
                pageRangeSink: {
                    pdfRanges =
                        $0
                }
            )

        XCTAssertFalse(
            data.isEmpty
        )

        XCTAssertEqual(
            pdfRanges,
            editor.pageRanges
        )

        let screenHeights =
            sectionBalancePDFActiveScreenHeights(
                editor
            )

        XCTAssertEqual(
            pdfHeights.count,
            screenHeights.count
        )

        for page
            in pdfHeights.indices {

            assertSectionBalancePDFHeights(
                pdfHeights[
                    page
                ],
                screenHeights[
                    page
                ]
            )
        }

        let fullHeight =
            try PageGeometry(
                first
            )
            .contentSize
            .height

        for height
            in screenHeights[0] {

            XCTAssertEqual(
                height,
                fullHeight,
                accuracy:
                    0.5
            )
        }

        let finalPage =
            screenHeights.count - 1

        if noColumnBalance {
            for height
                in screenHeights[
                    finalPage
                ] {

                XCTAssertEqual(
                    height,
                    fullHeight,
                    accuracy:
                        0.5
                )
            }
        } else {
            XCTAssertEqual(
                screenHeights[
                    finalPage
                ]
                .count,
                2
            )

            XCTAssertLessThan(
                screenHeights[
                    finalPage
                ]
                .max()
                    ?? fullHeight,
                fullHeight - 1
            )
        }

        print(
            "SECTION_BALANCE_PDF_PARITY "
            + "break=\(breakType.rawValue) "
            + "noColumnBalance=\(noColumnBalance) "
            + "ranges=\(pdfRanges) "
            + "pdfHeights=\(pdfHeights) "
            + "screenHeights=\(screenHeights)"
        )
    }

    func testPDFContinuousAndNextColumnFinalBalancingMatchesScreen()
        throws
    {
        try assertSectionBalancePDFParity(
            breakType:
                .continuous,
            noColumnBalance:
                false
        )

        try assertSectionBalancePDFParity(
            breakType:
                .nextColumn,
            noColumnBalance:
                false
        )
    }

    func testPDFContinuousAndNextColumnNoColumnBalanceMatchesScreen()
        throws
    {
        try assertSectionBalancePDFParity(
            breakType:
                .continuous,
            noColumnBalance:
                true
        )

        try assertSectionBalancePDFParity(
            breakType:
                .nextColumn,
            noColumnBalance:
                true
        )
    }
}
