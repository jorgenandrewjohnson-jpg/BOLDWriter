import AppKit
import PDFKit
import XCTest
@testable import BOLDWriter

@MainActor
private final class EndnoteTextView: NSTextView {
    let manager = UndoManager()
    override var undoManager: UndoManager? { manager }
}

@MainActor

final class EndnoteTests: XCTestCase {
    private func manuscript() -> NSAttributedString {
        let result = NSMutableAttributedString(string: "Bold body", attributes: [.font: NSFont.boldSystemFont(ofSize: 17)])
        for index in 1...3 {
            result.append(Endnotes.marker(Endnote(text: "Note \(index) & <text>\nSecond paragraph", location: 0, length: 1), number: index))
            result.append(NSAttributedString(string: " italic \(index)", attributes: [.font: NSFont.systemFont(ofSize: 15).withItalicTrait()]))
        }
        return result
    }

    func testDOCXExportAndThreeNoteFormattedRoundTrip() throws {
        let original = manuscript()
        let data = try DOCXExporter.data(from: original, title: "Endnotes")
        let parts = Dictionary(uniqueKeysWithValues: try DOCXPackage.entries(in: data).map { ($0.path, $0.data) })
        let main = try DOCXPackage.xml(XCTUnwrap(parts["word/document.xml"]))
        XCTAssertEqual(try main.nodes(forXPath: "//*[local-name()='endnoteReference']").count, 3)
        let notes = try DOCXPackage.xml(XCTUnwrap(parts["word/endnotes.xml"]))
        XCTAssertEqual(try notes.nodes(forXPath: "//*[local-name()='endnoteRef']").count, 3)
        XCTAssertTrue(String(decoding: parts["word/_rels/document.xml.rels"]!, as: UTF8.self).contains("/endnotes"))
        XCTAssertTrue(String(decoding: parts["[Content_Types].xml"]!, as: UTF8.self).contains("wordprocessingml.endnotes+xml"))
        let imported = try DOCXImporter.text(from: data)
        XCTAssertEqual(imported.string.trimmingCharacters(in: .newlines), original.string)
        XCTAssertEqual(try Endnotes.records(in: imported).map(\.text), try Endnotes.records(in: original).map(\.text))
        let bold = try XCTUnwrap(imported.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: bold).contains(.boldFontMask))
        let italicRange = (imported.string as NSString).range(of: "italic")
        let italic = try XCTUnwrap(imported.attribute(.font, at: italicRange.location, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: italic).contains(.italicFontMask))
        let second = try DOCXImporter.text(from: DOCXExporter.data(from: imported, title: "Again"))
        XCTAssertEqual(try Endnotes.records(in: second).map(\.text), try Endnotes.records(in: imported).map(\.text))
    }

    private func fixture(reference: String = "42", body: String = "<w:r><w:endnoteRef/><w:t>Word note</w:t><w:tab/><w:t>text</w:t></w:r>") -> Data {
        let w = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
        let r = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
        let parts = [
            "[Content_Types].xml": "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/><Override PartName=\"/word/notes.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.endnotes+xml\"/></Types>",
            "_rels/.rels": "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"main\" Type=\"\(r)/officeDocument\" Target=\"word/document.xml\"/></Relationships>",
            "word/_rels/document.xml.rels": "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"notes\" Type=\"\(r)/endnotes\" Target=\"notes.xml\"/></Relationships>",
            "word/document.xml": "<w:document xmlns:w=\"\(w)\"><w:body><w:p><w:r><w:t>Before</w:t><w:endnoteReference w:id=\"\(reference)\"/><w:t>After</w:t></w:r></w:p></w:body></w:document>",
            "word/notes.xml": "<w:endnotes xmlns:w=\"\(w)\"><w:endnote w:type=\"separator\" w:id=\"-1\"><w:p><w:r><w:separator/></w:r></w:p></w:endnote><w:endnote w:id=\"42\"><w:p>\(body)</w:p></w:endnote></w:endnotes>"
        ]
        return ZipArchiveWriter.archive(parts.map { ZipEntry(path: $0.key, data: Data($0.value.utf8)) })
    }

    func testIndependentWordEndnoteImport() throws {
        let text = try DOCXImporter.text(from: fixture())
        XCTAssertEqual(text.string.trimmingCharacters(in: .newlines), "Before1After")
        XCTAssertEqual(try Endnotes.records(in: text).first?.text, "Word note\ttext")
    }

    func testMalformedEndnotesFailWithEndnoteSpecificError() {
        let expected = "The DOCX contains missing, duplicate, or unsupported endnotes. Import was stopped without changing the original file."
        for data in [fixture(reference: "99"), fixture(body: "<w:r><w:drawing/></w:r>")] {
            XCTAssertThrowsError(try DOCXImporter.text(from: data)) { error in
                XCTAssertEqual(error.localizedDescription, expected)
            }
        }
    }

    func testNativePackageStoresEndnoteMetadata() throws {
        let source =
            NSMutableAttributedString(
                string:
                    "Body "
            )

        source.append(
            Endnotes.marker(
                Endnote(
                    text:
                        "Native endnote",
                    location:
                        0,
                    length:
                        1
                ),
                number:
                    1
            )
        )

        let wrapper =
            try BOLDWriterDocument.packageWrapper(
                text:
                    source,
                metadata:
                    DocumentMetadata(
                        title:
                            "Endnotes"
                    )
            )

        let data =
            try XCTUnwrap(
                wrapper
                    .fileWrappers?[
                        "metadata.json"
                    ]?
                    .regularFileContents
            )

        let metadata =
            try JSONDecoder()
                .decode(
                    DocumentMetadata.self,
                    from:
                        data
                )

        XCTAssertEqual(
            metadata.endnotes?
                .map(\.text),
            [
                "Native endnote"
            ]
        )
    }

    func testEndnotesRenumberIndependently() throws {
        let source =
            NSMutableAttributedString(
                string:
                    "A"
            )

        source.append(
            Endnotes.marker(
                Endnote(
                    text:
                        "One",
                    location:
                        0,
                    length:
                        1
                ),
                number:
                    7
            )
        )

        source.append(
            NSAttributedString(
                string:
                    "B"
            )
        )

        source.append(
            Endnotes.marker(
                Endnote(
                    text:
                        "Two",
                    location:
                        0,
                    length:
                        1
                ),
                number:
                    9
            )
        )

        try Endnotes.renumber(
            source
        )

        let notes =
            try Endnotes.records(
                in:
                    source
            )

        XCTAssertEqual(
            notes.map(\.text),
            [
                "One",
                "Two"
            ]
        )

        let markers =
            notes.map {
                (source.string as NSString)
                    .substring(
                        with:
                            NSRange(
                                location:
                                    $0.location,
                                length:
                                    $0.length
                            )
                    )
            }

        XCTAssertEqual(
            markers,
            [
                "1",
                "2"
            ]
        )
    }

    func testPDFIncludesNumberedEndnoteBodies()
        throws {

        let text =
            NSMutableAttributedString(
                string:
                    "Body "
            )

        for index in 1...3 {
            text.append(
                Endnotes.marker(
                    Endnote(
                        text:
                            "Endnote body \(index)",
                        location:
                            0,
                        length:
                            1
                    ),
                    number:
                        index
                )
            )

            text.append(
                NSAttributedString(
                    string:
                        " text "
                )
            )
        }

        let data =
            try PDFExporter.data(
                from:
                    text,
                settings:
                    PageSettings()
            )

        let pdf =
            try XCTUnwrap(
                PDFDocument(
                    data:
                        data
                )
            )

        let body =
            try XCTUnwrap(
                pdf.string
            )

        XCTAssertTrue(
            body.contains(
                "Endnotes"
            )
        )

        for index in 1...3 {
            XCTAssertTrue(
                body.contains(
                    "\(index). Endnote body \(index)"
                )
            )
        }
    }

    func testPDFIncludesFootnotesAndEndnotesTogether()
        throws {

        let text =
            NSMutableAttributedString(
                string:
                    "Mixed "
            )

        text.append(
            Footnotes.marker(
                Footnote(
                    text:
                        "Footnote body",
                    location:
                        0,
                    length:
                        1
                ),
                number:
                    1
            )
        )

        text.append(
            NSAttributedString(
                string:
                    " notes "
            )
        )

        text.append(
            Endnotes.marker(
                Endnote(
                    text:
                        "Endnote body",
                    location:
                        0,
                    length:
                        1
                ),
                number:
                    1
            )
        )

        let data =
            try PDFExporter.data(
                from:
                    text,
                settings:
                    PageSettings()
            )

        let pdf =
            try XCTUnwrap(
                PDFDocument(
                    data:
                        data
                )
            )

        let body =
            try XCTUnwrap(
                pdf.string
            )

        XCTAssertFalse(body.contains("\n\nFootnotes\n"))

        XCTAssertTrue(
            body.contains(
                "1. Footnote body"
            )
        )

        XCTAssertTrue(
            body.contains(
                "Endnotes"
            )
        )

        XCTAssertTrue(
            body.contains(
                "1. Endnote body"
            )
        )
    }
}
