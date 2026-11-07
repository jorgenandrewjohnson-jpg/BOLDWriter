import AppKit
import PDFKit
import XCTest
@testable import BOLDWriter

final class DOCXHeaderFooterTests: XCTestCase {
    private let text = NSAttributedString(
        string: "A short manuscript.",
        attributes: [
            .font: NSFont.systemFont(ofSize: 15),
            .foregroundColor: NSColor.textColor
        ]
    )

    func testDOCXPackageContainsNativeHeaderAndFooterParts() throws {
        var settings = PageSettings()

        settings.headerText = "Book Header"
        settings.headerPosition = .center
        settings.footerText = "Private Draft"
        settings.footerPosition = .left
        settings.pageNumberPosition = .right
        settings.showsPageNumbers = true

        let data = try DOCXExporter.data(
            from: text,
            title: "Header Footer",
            settings: settings
        )

        // ZIP central directory keeps entry names visible even when XML
        // payloads are compressed.
        XCTAssertNotNil(
            data.range(of: Data("word/header1.xml".utf8))
        )

        XCTAssertNotNil(
            data.range(of: Data("word/footer1.xml".utf8))
        )

        XCTAssertNotNil(
            data.range(
                of: Data("word/document.xml".utf8)
            )
        )
    }

    func testDOCXWithoutHeaderStillCreatesFooterForPageNumbers() throws {
        var settings = PageSettings()

        settings.headerText = ""
        settings.footerText = ""
        settings.showsPageNumbers = true

        let data = try DOCXExporter.data(
            from: text,
            title: "Page Numbers",
            settings: settings
        )

        XCTAssertNil(
            data.range(of: Data("word/header1.xml".utf8))
        )

        XCTAssertNotNil(
            data.range(of: Data("word/footer1.xml".utf8))
        )
    }

    func testDOCXWithNoFurnitureCreatesNoHeaderFooterParts() throws {
        var settings = PageSettings()

        settings.headerText = ""
        settings.footerText = ""
        settings.showsPageNumbers = false

        let data = try DOCXExporter.data(
            from: text,
            title: "Plain",
            settings: settings
        )

        XCTAssertNil(
            data.range(of: Data("word/header1.xml".utf8))
        )

        XCTAssertNil(
            data.range(of: Data("word/footer1.xml".utf8))
        )
    }

    func testDOCXFirstPageSuppressionAndPageFieldUseNativeWordStructure()
        throws {
        var settings =
            PageSettings()

        settings.headerText =
            "Native Header"

        settings.headerPosition =
            .center

        settings.footerText =
            "Native Footer"

        settings.footerPosition =
            .left

        settings.pageNumberPosition =
            .right

        settings.showsPageNumbers =
            true

        settings.suppressFirstPageHeaderFooter =
            true

        let data =
            try DOCXExporter.data(
                from: text,
                title:
                    "Native Header Footer",
                settings: settings
            )

        let parts =
            Dictionary(
                uniqueKeysWithValues:
                    try DOCXPackage
                        .entries(in: data)
                        .map {
                            ($0.path, $0.data)
                        }
            )

        let document =
            try DOCXPackage.xml(
                XCTUnwrap(
                    parts[
                        "word/document.xml"
                    ]
                )
            )

        let header =
            try DOCXPackage.xml(
                XCTUnwrap(
                    parts[
                        "word/header1.xml"
                    ]
                )
            )

        let footer =
            try DOCXPackage.xml(
                XCTUnwrap(
                    parts[
                        "word/footer1.xml"
                    ]
                )
            )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='titlePg']"
            ).count,
            1
        )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='headerReference']"
            ).count,
            1
        )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='footerReference']"
            ).count,
            1
        )

        XCTAssertEqual(
            try header.nodes(
                forXPath:
                    "//*[local-name()='t' and contains(text(),'Native Header')]"
            ).count,
            1
        )

        XCTAssertEqual(
            try header.nodes(
                forXPath:
                    "//*[local-name()='jc' and @*[local-name()='val']='center']"
            ).count,
            1
        )

        XCTAssertEqual(
            try footer.nodes(
                forXPath:
                    "//*[local-name()='t' and contains(text(),'Native Footer')]"
            ).count,
            1
        )

        XCTAssertGreaterThanOrEqual(
            try footer.nodes(
                forXPath:
                    "//*[local-name()='jc' and @*[local-name()='val']='left']"
            ).count,
            1
        )

        XCTAssertGreaterThanOrEqual(
            try footer.nodes(
                forXPath:
                    "//*[local-name()='jc' and @*[local-name()='val']='right']"
            ).count,
            1
        )

        XCTAssertEqual(
            try footer.nodes(
                forXPath:
                    "//*[local-name()='fldSimple' and contains(@*[local-name()='instr'],'PAGE')]"
            ).count,
            1
        )
    }



    func testDOCXRoundTripImportsGlobalPageSetupAndFurniture()
        throws {

        var settings =
            PageSettings()

        settings.paper =
            .a4

        settings.landscape =
            true

        settings.topMargin =
            36

        settings.rightMargin =
            54

        settings.bottomMargin =
            72

        settings.leftMargin =
            90

        settings.headerText =
            "Book Header"

        settings.headerPosition =
            .center

        settings.footerText =
            "Private Draft"

        settings.footerPosition =
            .left

        settings.showsPageNumbers =
            true

        settings.pageNumberPosition =
            .right

        settings.suppressFirstPageHeaderFooter =
            true

        let data =
            try DOCXExporter.data(
                from:
                    text,
                title:
                    "Layout Round Trip",
                settings:
                    settings
            )

        let wrapper =
            FileWrapper(
                regularFileWithContents:
                    data
            )

        wrapper.preferredFilename =
            "Layout Round Trip.docx"

        let imported =
            try BOLDWriterDocument(
                fileWrapper:
                    wrapper,
                contentType:
                    .docx
            )

        let page =
            imported.metadata.page

        XCTAssertEqual(
            page.paper,
            .a4
        )

        XCTAssertTrue(
            page.landscape
        )

        XCTAssertEqual(
            page.topMargin,
            36,
            accuracy:
                0.1
        )

        XCTAssertEqual(
            page.rightMargin,
            54,
            accuracy:
                0.1
        )

        XCTAssertEqual(
            page.bottomMargin,
            72,
            accuracy:
                0.1
        )

        XCTAssertEqual(
            page.leftMargin,
            90,
            accuracy:
                0.1
        )

        XCTAssertEqual(
            page.effectiveHeaderText,
            "Book Header"
        )

        XCTAssertEqual(
            page.effectiveHeaderPosition,
            .center
        )

        XCTAssertEqual(
            page.footerText,
            "Private Draft"
        )

        XCTAssertEqual(
            page.effectiveFooterPosition,
            .left
        )

        XCTAssertTrue(
            page.showsPageNumbers
        )

        XCTAssertEqual(
            page.effectivePageNumberPosition,
            .right
        )

        XCTAssertTrue(
            page.hidesHeaderFooterOnFirstPage
        )
    }

    func testDOCXRoundTripImportsCombinedFooterPageNumber()
        throws {

        var settings =
            PageSettings()

        settings.headerText =
            ""

        settings.footerText =
            "Confidential"

        settings.footerPosition =
            .center

        settings.showsPageNumbers =
            true

        settings.pageNumberPosition =
            .center

        let data =
            try DOCXExporter.data(
                from:
                    text,
                title:
                    "Combined Footer",
                settings:
                    settings
            )

        let imported =
            try DOCXImporter
                .importedDocument(
                    from:
                        data
                )

        XCTAssertEqual(
            imported.page.footerText,
            "Confidential"
        )

        XCTAssertEqual(
            imported.page.effectiveFooterPosition,
            .center
        )

        XCTAssertTrue(
            imported.page.showsPageNumbers
        )

        XCTAssertEqual(
            imported.page.effectivePageNumberPosition,
            .center
        )
    }

    func testImportedStaticPageLabelAndPAGEFieldRenderAsOneLabel()
        throws {
        var settings = PageSettings()
        settings.headerText = ""
        settings.footerText = "Page "
        settings.footerPosition = .left
        settings.pageNumberPosition = .left
        settings.showsPageNumbers = true

        let docx = try DOCXExporter.data(
            from: NSAttributedString(string: "Imported footer field."),
            title: "Static Label and PAGE Field",
            settings: settings
        )
        let imported = try DOCXImporter.importedDocument(from: docx)
        let pdfData = try PDFExporter.data(
            from: imported.text,
            settings: imported.page,
            sections: imported.sections
        )
        let pdf = try XCTUnwrap(PDFDocument(data: pdfData))
        let firstPageText = try XCTUnwrap(pdf.page(at: 0)?.string)

        XCTAssertEqual(
            firstPageText.components(separatedBy: "Page").count - 1,
            1,
            "An imported static Page label plus PAGE field must produce one PDF label: \(firstPageText)"
        )
        XCTAssertTrue(firstPageText.contains("1"))
    }

    func testDOCXImportWithoutFurnitureDoesNotGainLegacyBOLDFooter()
        throws {

        var settings =
            PageSettings()

        settings.headerText =
            ""

        settings.footerText =
            ""

        settings.showsPageNumbers =
            false

        let data =
            try DOCXExporter.data(
                from:
                    text,
                title:
                    "No Furniture",
                settings:
                    settings
            )

        let wrapper =
            FileWrapper(
                regularFileWithContents:
                    data
            )

        wrapper.preferredFilename =
            "No Furniture.docx"

        let imported =
            try BOLDWriterDocument(
                fileWrapper:
                    wrapper,
                contentType:
                    .docx
            )

        XCTAssertEqual(
            imported.metadata.page.effectiveHeaderText,
            ""
        )

        XCTAssertEqual(
            imported.metadata.page.footerText,
            ""
        )

        XCTAssertFalse(
            imported.metadata.page.showsPageNumbers
        )

        XCTAssertFalse(
            imported.metadata.page.usesLegacyFooterLayout
        )
    }


    func testDOCXOddEvenPageFurnitureUsesNativeWordStructure()
        throws {

        var settings =
            PageSettings()

        settings.headerText =
            "Primary Header"

        settings.footerText =
            "Primary Footer"

        settings.showsPageNumbers =
            true

        settings.differentOddEvenHeaderFooter =
            true

        settings.evenPageHeaderText =
            "Even Header"

        settings.evenPageFooterText =
            "Even Footer"

        let data =
            try DOCXExporter.data(
                from:
                    text,
                title:
                    "Odd Even Furniture",
                settings:
                    settings
            )

        let parts =
            Dictionary(
                uniqueKeysWithValues:
                    try DOCXPackage
                        .entries(in: data)
                        .map {
                            ($0.path, $0.data)
                        }
            )

        let document =
            try DOCXPackage.xml(
                XCTUnwrap(
                    parts[
                        "word/document.xml"
                    ]
                )
            )

        let settingsXML =
            try DOCXPackage.xml(
                XCTUnwrap(
                    parts[
                        "word/settings.xml"
                    ]
                )
            )

        let headerReferences =
            try document.nodes(
                forXPath:
                    "//*[local-name()='headerReference']"
            )

        let footerReferences =
            try document.nodes(
                forXPath:
                    "//*[local-name()='footerReference']"
            )

        XCTAssertEqual(
            headerReferences.count,
            2
        )

        XCTAssertEqual(
            footerReferences.count,
            2
        )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='headerReference' and @*[local-name()='type']='default']"
            ).count,
            1
        )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='headerReference' and @*[local-name()='type']='even']"
            ).count,
            1
        )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='footerReference' and @*[local-name()='type']='default']"
            ).count,
            1
        )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='footerReference' and @*[local-name()='type']='even']"
            ).count,
            1
        )

        XCTAssertEqual(
            try settingsXML.nodes(
                forXPath:
                    "//*[local-name()='evenAndOddHeaders']"
            ).count,
            1
        )

        let headerPaths =
            parts.keys
                .filter {
                    $0.hasPrefix(
                        "word/header"
                    )
                    && $0.hasSuffix(
                        ".xml"
                    )
                }
                .sorted()

        let footerPaths =
            parts.keys
                .filter {
                    $0.hasPrefix(
                        "word/footer"
                    )
                    && $0.hasSuffix(
                        ".xml"
                    )
                }
                .sorted()

        XCTAssertEqual(
            headerPaths.count,
            2
        )

        XCTAssertEqual(
            footerPaths.count,
            2
        )

        let headerXML =
            try headerPaths.map {
                try DOCXPackage.xml(
                    XCTUnwrap(
                        parts[$0]
                    )
                )
            }

        let footerXML =
            try footerPaths.map {
                try DOCXPackage.xml(
                    XCTUnwrap(
                        parts[$0]
                    )
                )
            }

        XCTAssertEqual(
            try headerXML.reduce(0) {
                $0
                    + (try $1.nodes(
                        forXPath:
                            "//*[local-name()='t' and contains(text(),'Primary Header')]"
                    ).count)
            },
            1
        )

        XCTAssertEqual(
            try headerXML.reduce(0) {
                $0
                    + (try $1.nodes(
                        forXPath:
                            "//*[local-name()='t' and contains(text(),'Even Header')]"
                    ).count)
            },
            1
        )

        XCTAssertEqual(
            try footerXML.reduce(0) {
                $0
                    + (try $1.nodes(
                        forXPath:
                            "//*[local-name()='t' and contains(text(),'Primary Footer')]"
                    ).count)
            },
            1
        )

        XCTAssertEqual(
            try footerXML.reduce(0) {
                $0
                    + (try $1.nodes(
                        forXPath:
                            "//*[local-name()='t' and contains(text(),'Even Footer')]"
                    ).count)
            },
            1
        )
    }

}


extension DOCXHeaderFooterTests {
    func testDOCXImportsTwoNativeWordSectionsAtExactTextBoundary()
        throws {

        let base =
            try DOCXExporter.data(
                from:
                    NSAttributedString(
                        string:
                            "placeholder"
                    ),
                title:
                    "Multi Section Import",
                settings:
                    PageSettings()
            )

        var entries =
            try DOCXPackage.entries(
                in:
                    base
            )

        let documentIndex =
            try XCTUnwrap(
                entries.firstIndex {
                    $0.path
                        == "word/document.xml"
                }
            )

        let documentXML =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:document
                xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
              <w:body>
                <w:p>
                  <w:r>
                    <w:t>First section</w:t>
                  </w:r>
                </w:p>

                <w:p>
                  <w:pPr>
                    <w:sectPr>
                      <w:pgSz w:w="12240" w:h="15840"/>
                      <w:pgMar
                          w:top="1440"
                          w:right="1440"
                          w:bottom="1440"
                          w:left="1440"/>
                    </w:sectPr>
                  </w:pPr>
                  <w:r>
                    <w:t>End first</w:t>
                  </w:r>
                </w:p>

                <w:p>
                  <w:r>
                    <w:t>Second section</w:t>
                  </w:r>
                </w:p>

                <w:sectPr>
                  <w:pgSz
                      w:w="16838"
                      w:h="11906"
                      w:orient="landscape"/>
                  <w:pgMar
                      w:top="720"
                      w:right="1080"
                      w:bottom="1440"
                      w:left="1800"/>
                </w:sectPr>
              </w:body>
            </w:document>
            """

        entries[
            documentIndex
        ].data =
            Data(
                documentXML.utf8
            )

        let data =
            ZipArchiveWriter.archive(
                entries
            )

        let imported =
            try DOCXImporter.importedDocument(
                from:
                    data
            )

        XCTAssertEqual(
            imported.sections.count,
            2
        )

        XCTAssertEqual(
            imported.sections[0].location,
            0
        )

        let secondSectionLocation =
            (
                imported.text.string
                    as NSString
            )
            .range(
                of:
                    "Second section"
            )
            .location

        XCTAssertNotEqual(
            secondSectionLocation,
            NSNotFound
        )

        XCTAssertEqual(
            imported.sections[1].location,
            secondSectionLocation
        )

        let first =
            imported.sections[0].page

        XCTAssertEqual(
            first.paper,
            .letter
        )

        XCTAssertFalse(
            first.landscape
        )

        XCTAssertEqual(
            first.topMargin,
            72,
            accuracy:
                0.01
        )

        XCTAssertEqual(
            first.leftMargin,
            72,
            accuracy:
                0.01
        )

        let second =
            imported.sections[1].page

        XCTAssertEqual(
            second.paper,
            .a4
        )

        XCTAssertTrue(
            second.landscape
        )

        XCTAssertEqual(
            second.topMargin,
            36,
            accuracy:
                0.01
        )

        XCTAssertEqual(
            second.rightMargin,
            54,
            accuracy:
                0.01
        )

        XCTAssertEqual(
            second.bottomMargin,
            72,
            accuracy:
                0.01
        )

        XCTAssertEqual(
            second.leftMargin,
            90,
            accuracy:
                0.01
        )

        // Keep the existing global-page compatibility behavior:
        // metadata.page still represents Word's final section.
        XCTAssertEqual(
            imported.page.paper,
            .a4
        )

        XCTAssertTrue(
            imported.page.landscape
        )

        XCTAssertFalse(
            imported.text.string
                .contains(
                    "BOLDSECTION"
                )
        )

        let wrapper =
            FileWrapper(
                regularFileWithContents:
                    data
            )

        wrapper.preferredFilename =
            "Multi Section Import.docx"

        let document =
            try BOLDWriterDocument(
                fileWrapper:
                    wrapper,
                contentType:
                    .docx
            )

        let storedSections =
            try XCTUnwrap(
                document.metadata.sections
            )

        XCTAssertEqual(
            storedSections.count,
            2
        )

        XCTAssertEqual(
            storedSections[0].location,
            0
        )

        let storedSecondLocation =
            (
                document.text.string
                    as NSString
            )
            .range(
                of:
                    "Second section"
            )
            .location

        XCTAssertNotEqual(
            storedSecondLocation,
            NSNotFound
        )

        XCTAssertEqual(
            storedSections[1].location,
            storedSecondLocation
        )

        XCTAssertEqual(
            storedSections[0].page.paper,
            .letter
        )

        XCTAssertFalse(
            storedSections[0].page.landscape
        )

        XCTAssertEqual(
            storedSections[1].page.paper,
            .a4
        )

        XCTAssertTrue(
            storedSections[1].page.landscape
        )

        XCTAssertEqual(
            document.metadata.page,
            imported.page
        )

        XCTAssertEqual(
            storedSections,
            imported.sections
        )
    }
}


extension DOCXHeaderFooterTests {
    func testDOCXExportsNativeWordMultiSectionPageSetup()
        throws {

        let value =
            "First section\nSecond section"

        let text =
            NSAttributedString(
                string:
                    value,
                attributes:
                    [
                        .font:
                            NSFont.systemFont(
                                ofSize:
                                    15
                            )
                    ]
            )

        var first =
            PageSettings()

        first.paper =
            .letter

        first.landscape =
            false

        first.topMargin =
            72

        first.rightMargin =
            72

        first.bottomMargin =
            72

        first.leftMargin =
            72

        first.headerText =
            ""

        first.footerText =
            ""

        first.showsPageNumbers =
            false

        var second =
            PageSettings()

        second.paper =
            .a4

        second.landscape =
            true

        second.topMargin =
            36

        second.rightMargin =
            54

        second.bottomMargin =
            72

        second.leftMargin =
            90

        second.headerText =
            ""

        second.footerText =
            ""

        second.showsPageNumbers =
            false

        let boundary =
            (
                "First section\n"
                    as NSString
            )
            .length

        let sections = [
            DocumentSection(
                location:
                    0,
                page:
                    first
            ),
            DocumentSection(
                location:
                    boundary,
                page:
                    second
            )
        ]

        let data =
            try DOCXExporter.data(
                from:
                    text,
                title:
                    "Native Multi Section Export",
                settings:
                    second,
                sections:
                    sections
            )

        let parts =
            Dictionary(
                uniqueKeysWithValues:
                    try DOCXPackage
                        .entries(
                            in:
                                data
                        )
                        .map {
                            (
                                $0.path,
                                $0.data
                            )
                        }
            )

        let document =
            try DOCXPackage.xml(
                XCTUnwrap(
                    parts[
                        "word/document.xml"
                    ]
                )
            )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='sectPr']"
            ).count,
            2
        )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='pPr']/*[local-name()='sectPr']"
            ).count,
            1
        )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "/*[local-name()='document']/*[local-name()='body']/*[local-name()='sectPr']"
            ).count,
            1
        )

        let paragraphSection =
            try XCTUnwrap(
                document.nodes(
                    forXPath:
                        "//*[local-name()='pPr']/*[local-name()='sectPr']"
                )
                .first
                    as? XMLElement
            )

        XCTAssertEqual(
            try paragraphSection.nodes(
                forXPath:
                    "./*[local-name()='pgSz' and @*[local-name()='w']='12240' and @*[local-name()='h']='15840']"
            ).count,
            1
        )

        XCTAssertEqual(
            try paragraphSection.nodes(
                forXPath:
                    "./*[local-name()='pgMar' and @*[local-name()='top']='1440' and @*[local-name()='right']='1440' and @*[local-name()='bottom']='1440' and @*[local-name()='left']='1440']"
            ).count,
            1
        )

        let finalSection =
            try XCTUnwrap(
                document.nodes(
                    forXPath:
                        "/*[local-name()='document']/*[local-name()='body']/*[local-name()='sectPr']"
                )
                .first
                    as? XMLElement
            )

        XCTAssertEqual(
            try finalSection.nodes(
                forXPath:
                    "./*[local-name()='pgSz' and @*[local-name()='w']='16838' and @*[local-name()='h']='11906' and @*[local-name()='orient']='landscape']"
            ).count,
            1
        )

        XCTAssertEqual(
            try finalSection.nodes(
                forXPath:
                    "./*[local-name()='pgMar' and @*[local-name()='top']='720' and @*[local-name()='right']='1080' and @*[local-name()='bottom']='1440' and @*[local-name()='left']='1800']"
            ).count,
            1
        )

        let imported =
            try DOCXImporter
                .importedDocument(
                    from:
                        data
                )

        XCTAssertEqual(
            imported.sections.count,
            2
        )

        XCTAssertEqual(
            imported.sections[0]
                .location,
            0
        )

        let importedBoundary =
            (
                imported.text.string
                    as NSString
            )
            .range(
                of:
                    "Second section"
            )
            .location

        XCTAssertNotEqual(
            importedBoundary,
            NSNotFound
        )

        XCTAssertEqual(
            imported.sections[1]
                .location,
            importedBoundary
        )

        XCTAssertEqual(
            imported.sections[0]
                .page
                .paper,
            .letter
        )

        XCTAssertFalse(
            imported.sections[0]
                .page
                .landscape
        )

        XCTAssertEqual(
            imported.sections[0]
                .page
                .leftMargin,
            72,
            accuracy:
                0.01
        )

        XCTAssertEqual(
            imported.sections[1]
                .page
                .paper,
            .a4
        )

        XCTAssertTrue(
            imported.sections[1]
                .page
                .landscape
        )

        XCTAssertEqual(
            imported.sections[1]
                .page
                .topMargin,
            36,
            accuracy:
                0.01
        )

        XCTAssertEqual(
            imported.sections[1]
                .page
                .rightMargin,
            54,
            accuracy:
                0.01
        )

        XCTAssertEqual(
            imported.sections[1]
                .page
                .leftMargin,
            90,
            accuracy:
                0.01
        )
    }
}


extension DOCXHeaderFooterTests {
    func testDOCXExportsDistinctHeadersAndFootersPerSection()
        throws {

        let text =
            NSAttributedString(
                string:
                    "First section\nSecond section"
            )

        let boundary =
            (
                "First section\n"
                    as NSString
            )
            .length

        var first =
            PageSettings()

        first.headerText =
            "FIRST SECTION HEADER"

        first.footerText =
            "FIRST SECTION FOOTER"

        first.showsPageNumbers =
            false

        var second =
            PageSettings()

        second.headerText =
            "SECOND SECTION HEADER"

        second.footerText =
            "SECOND SECTION FOOTER"

        second.showsPageNumbers =
            false

        let data =
            try DOCXExporter.data(
                from:
                    text,
                title:
                    "Section Furniture",
                settings:
                    second,
                sections:
                    [
                        DocumentSection(
                            location:
                                0,
                            page:
                                first
                        ),
                        DocumentSection(
                            location:
                                boundary,
                            page:
                                second
                        )
                    ]
            )

        let entries =
            try DOCXPackage.entries(
                in:
                    data
            )

        let parts =
            Dictionary(
                uniqueKeysWithValues:
                    entries.map {
                        (
                            $0.path,
                            $0.data
                        )
                    }
            )

        func stringPart(
            _ path: String
        ) throws -> String {

            let data =
                try XCTUnwrap(
                    parts[
                        path
                    ]
                )

            return
                try XCTUnwrap(
                    String(
                        data:
                            data,
                        encoding:
                            .utf8
                    )
                )
        }

        XCTAssertTrue(
            try stringPart(
                "word/header-section1-default.xml"
            )
            .contains(
                "FIRST SECTION HEADER"
            )
        )

        XCTAssertTrue(
            try stringPart(
                "word/footer-section1-default.xml"
            )
            .contains(
                "FIRST SECTION FOOTER"
            )
        )

        XCTAssertTrue(
            try stringPart(
                "word/header-section2-default.xml"
            )
            .contains(
                "SECOND SECTION HEADER"
            )
        )

        XCTAssertTrue(
            try stringPart(
                "word/footer-section2-default.xml"
            )
            .contains(
                "SECOND SECTION FOOTER"
            )
        )

        let relationships =
            try stringPart(
                "word/_rels/document.xml.rels"
            )

        XCTAssertTrue(
            relationships.contains(
                "Id=\"rHeaderSection1Default\""
            )
        )

        XCTAssertTrue(
            relationships.contains(
                "Target=\"header-section1-default.xml\""
            )
        )

        XCTAssertTrue(
            relationships.contains(
                "Id=\"rFooterSection1Default\""
            )
        )

        XCTAssertTrue(
            relationships.contains(
                "Target=\"footer-section1-default.xml\""
            )
        )

        XCTAssertTrue(
            relationships.contains(
                "Id=\"rHeaderSection2Default\""
            )
        )

        XCTAssertTrue(
            relationships.contains(
                "Target=\"header-section2-default.xml\""
            )
        )

        XCTAssertTrue(
            relationships.contains(
                "Id=\"rFooterSection2Default\""
            )
        )

        XCTAssertTrue(
            relationships.contains(
                "Target=\"footer-section2-default.xml\""
            )
        )

        let document =
            try DOCXPackage.xml(
                XCTUnwrap(
                    parts[
                        "word/document.xml"
                    ]
                )
            )

        let sectionNodes =
            try document.nodes(
                forXPath:
                    "//*[local-name()='sectPr']"
            )
            .compactMap {
                $0 as? XMLElement
            }

        XCTAssertEqual(
            sectionNodes.count,
            2
        )

        let firstNode =
            try XCTUnwrap(
                sectionNodes.first
            )

        XCTAssertEqual(
            try firstNode.nodes(
                forXPath:
                    "./*[local-name()='headerReference' and @*[local-name()='id']='rHeaderSection1Default']"
            ).count,
            1
        )

        XCTAssertEqual(
            try firstNode.nodes(
                forXPath:
                    "./*[local-name()='footerReference' and @*[local-name()='id']='rFooterSection1Default']"
            ).count,
            1
        )

        let secondNode =
            try XCTUnwrap(
                sectionNodes.last
            )

        XCTAssertEqual(
            try secondNode.nodes(
                forXPath:
                    "./*[local-name()='headerReference' and @*[local-name()='id']='rHeaderSection2Default']"
            ).count,
            1
        )

        XCTAssertEqual(
            try secondNode.nodes(
                forXPath:
                    "./*[local-name()='footerReference' and @*[local-name()='id']='rFooterSection2Default']"
            ).count,
            1
        )

        let imported =
            try DOCXImporter
                .importedDocument(
                    from:
                        data
                )

        XCTAssertEqual(
            imported.sections.count,
            2
        )

        XCTAssertEqual(
            imported.sections[0]
                .page
                .effectiveHeaderText,
            "FIRST SECTION HEADER"
        )

        XCTAssertEqual(
            imported.sections[0]
                .page
                .footerText,
            "FIRST SECTION FOOTER"
        )

        XCTAssertEqual(
            imported.sections[1]
                .page
                .effectiveHeaderText,
            "SECOND SECTION HEADER"
        )

        XCTAssertEqual(
            imported.sections[1]
                .page
                .footerText,
            "SECOND SECTION FOOTER"
        )

        XCTAssertEqual(
            imported.sections[1]
                .location,
            (
                imported.text.string
                    as NSString
            )
            .range(
                of:
                    "Second section"
            )
            .location
        )
    }
}


extension DOCXHeaderFooterTests {
    func testDOCXRoundTripsDistinctOddEvenFurniturePerSection()
        throws {

        let text =
            NSAttributedString(
                string:
                    "Section one\nSection two"
            )

        let boundary =
            (
                "Section one\n"
                    as NSString
            )
            .length

        var first =
            PageSettings()

        first.headerText =
            "SECTION ONE ODD HEADER"

        first.footerText =
            "SECTION ONE ODD FOOTER"

        first.differentOddEvenHeaderFooter =
            true

        first.evenPageHeaderText =
            "SECTION ONE EVEN HEADER"

        first.evenPageFooterText =
            "SECTION ONE EVEN FOOTER"

        first.showsPageNumbers =
            false

        var second =
            PageSettings()

        second.headerText =
            "SECTION TWO ODD HEADER"

        second.footerText =
            "SECTION TWO ODD FOOTER"

        second.differentOddEvenHeaderFooter =
            true

        second.evenPageHeaderText =
            "SECTION TWO EVEN HEADER"

        second.evenPageFooterText =
            "SECTION TWO EVEN FOOTER"

        second.showsPageNumbers =
            false

        let data =
            try DOCXExporter.data(
                from:
                    text,
                title:
                    "Section Odd Even Round Trip",
                settings:
                    second,
                sections:
                    [
                        DocumentSection(
                            location:
                                0,
                            page:
                                first
                        ),
                        DocumentSection(
                            location:
                                boundary,
                            page:
                                second
                        )
                    ]
            )

        let imported =
            try DOCXImporter
                .importedDocument(
                    from:
                        data
                )

        XCTAssertEqual(
            imported.sections.count,
            2
        )

        let firstImported =
            imported.sections[0]
                .page

        XCTAssertTrue(
            firstImported
                .usesDifferentOddEvenHeaderFooter
        )

        XCTAssertEqual(
            firstImported
                .effectiveHeaderText,
            "SECTION ONE ODD HEADER"
        )

        XCTAssertEqual(
            firstImported
                .footerText,
            "SECTION ONE ODD FOOTER"
        )

        XCTAssertEqual(
            firstImported
                .effectiveEvenPageHeaderText,
            "SECTION ONE EVEN HEADER"
        )

        XCTAssertEqual(
            firstImported
                .effectiveEvenPageFooterText,
            "SECTION ONE EVEN FOOTER"
        )

        let secondImported =
            imported.sections[1]
                .page

        XCTAssertTrue(
            secondImported
                .usesDifferentOddEvenHeaderFooter
        )

        XCTAssertEqual(
            secondImported
                .effectiveHeaderText,
            "SECTION TWO ODD HEADER"
        )

        XCTAssertEqual(
            secondImported
                .footerText,
            "SECTION TWO ODD FOOTER"
        )

        XCTAssertEqual(
            secondImported
                .effectiveEvenPageHeaderText,
            "SECTION TWO EVEN HEADER"
        )

        XCTAssertEqual(
            secondImported
                .effectiveEvenPageFooterText,
            "SECTION TWO EVEN FOOTER"
        )

        XCTAssertEqual(
            imported.sections[1]
                .location,
            (
                imported.text.string
                    as NSString
            )
            .range(
                of:
                    "Section two"
            )
            .location
        )
    }
}


extension DOCXHeaderFooterTests {
    func testDOCXRoundTripsSectionSpecificFirstPageSuppression()
        throws {

        let text =
            NSAttributedString(
                string:
                    "First section\nSecond section"
            )

        let boundary =
            (
                "First section\n"
                    as NSString
            )
            .length

        var first =
            PageSettings()

        first.headerText =
            "FIRST HEADER"

        first.footerText =
            "FIRST FOOTER"

        first.showsPageNumbers =
            false

        first.suppressFirstPageHeaderFooter =
            true

        var second =
            PageSettings()

        second.headerText =
            "SECOND HEADER"

        second.footerText =
            "SECOND FOOTER"

        second.showsPageNumbers =
            false

        second.suppressFirstPageHeaderFooter =
            false

        let data =
            try DOCXExporter.data(
                from:
                    text,
                title:
                    "Section First Page Suppression",
                settings:
                    second,
                sections:
                    [
                        DocumentSection(
                            location:
                                0,
                            page:
                                first
                        ),
                        DocumentSection(
                            location:
                                boundary,
                            page:
                                second
                        )
                    ]
            )

        let parts =
            Dictionary(
                uniqueKeysWithValues:
                    try DOCXPackage
                        .entries(
                            in:
                                data
                        )
                        .map {
                            (
                                $0.path,
                                $0.data
                            )
                        }
            )

        let document =
            try DOCXPackage.xml(
                XCTUnwrap(
                    parts[
                        "word/document.xml"
                    ]
                )
            )

        let sectionNodes =
            try document.nodes(
                forXPath:
                    "//*[local-name()='sectPr']"
            )
            .compactMap {
                $0 as? XMLElement
            }

        XCTAssertEqual(
            sectionNodes.count,
            2
        )

        let firstSection =
            try XCTUnwrap(
                sectionNodes.first
            )

        let secondSection =
            try XCTUnwrap(
                sectionNodes.last
            )

        XCTAssertEqual(
            try firstSection.nodes(
                forXPath:
                    "./*[local-name()='titlePg']"
            ).count,
            1
        )

        XCTAssertEqual(
            try secondSection.nodes(
                forXPath:
                    "./*[local-name()='titlePg']"
            ).count,
            0
        )

        let imported =
            try DOCXImporter
                .importedDocument(
                    from:
                        data
                )

        XCTAssertEqual(
            imported.sections.count,
            2
        )

        XCTAssertTrue(
            imported.sections[0]
                .page
                .hidesHeaderFooterOnFirstPage
        )

        XCTAssertFalse(
            imported.sections[1]
                .page
                .hidesHeaderFooterOnFirstPage
        )

        XCTAssertEqual(
            imported.sections[0]
                .page
                .effectiveHeaderText,
            "FIRST HEADER"
        )

        XCTAssertEqual(
            imported.sections[0]
                .page
                .footerText,
            "FIRST FOOTER"
        )

        XCTAssertEqual(
            imported.sections[1]
                .page
                .effectiveHeaderText,
            "SECOND HEADER"
        )

        XCTAssertEqual(
            imported.sections[1]
                .page
                .footerText,
            "SECOND FOOTER"
        )

        XCTAssertEqual(
            imported.sections[1]
                .location,
            (
                imported.text.string
                    as NSString
            )
            .range(
                of:
                    "Second section"
            )
            .location
        )
    }
}


extension DOCXHeaderFooterTests {
    func testDOCXRoundTripsDistinctFirstPageFurniturePerSection()
        throws {

        let text =
            NSAttributedString(
                string:
                    "First section\nSecond section"
            )

        let boundary =
            (
                "First section\n"
                    as NSString
            )
            .length

        var first =
            PageSettings()

        first.headerText =
            "FIRST NORMAL HEADER"

        first.footerText =
            "FIRST NORMAL FOOTER"

        first.firstPageHeaderText =
            "FIRST SPECIAL HEADER"

        first.firstPageFooterText =
            "FIRST SPECIAL FOOTER"

        first.showsPageNumbers =
            false

        var second =
            PageSettings()

        second.headerText =
            "SECOND NORMAL HEADER"

        second.footerText =
            "SECOND NORMAL FOOTER"

        second.firstPageHeaderText =
            "SECOND SPECIAL HEADER"

        second.firstPageFooterText =
            "SECOND SPECIAL FOOTER"

        second.showsPageNumbers =
            false

        let data =
            try DOCXExporter.data(
                from:
                    text,
                title:
                    "Distinct First Page Furniture",
                settings:
                    second,
                sections:
                    [
                        DocumentSection(
                            location:
                                0,
                            page:
                                first
                        ),
                        DocumentSection(
                            location:
                                boundary,
                            page:
                                second
                        )
                    ]
            )

        let entries =
            try DOCXPackage.entries(
                in:
                    data
            )

        let parts =
            Dictionary(
                uniqueKeysWithValues:
                    entries.map {
                        (
                            $0.path,
                            $0.data
                        )
                    }
            )

        func stringPart(
            _ path: String
        ) throws -> String {

            let data =
                try XCTUnwrap(
                    parts[
                        path
                    ]
                )

            return
                try XCTUnwrap(
                    String(
                        data:
                            data,
                        encoding:
                            .utf8
                    )
                )
        }

        XCTAssertTrue(
            try stringPart(
                "word/header-section1-first.xml"
            )
            .contains(
                "FIRST SPECIAL HEADER"
            )
        )

        XCTAssertTrue(
            try stringPart(
                "word/footer-section1-first.xml"
            )
            .contains(
                "FIRST SPECIAL FOOTER"
            )
        )

        XCTAssertTrue(
            try stringPart(
                "word/header-section2-first.xml"
            )
            .contains(
                "SECOND SPECIAL HEADER"
            )
        )

        XCTAssertTrue(
            try stringPart(
                "word/footer-section2-first.xml"
            )
            .contains(
                "SECOND SPECIAL FOOTER"
            )
        )

        let document =
            try DOCXPackage.xml(
                XCTUnwrap(
                    parts[
                        "word/document.xml"
                    ]
                )
            )

        let sections =
            try document.nodes(
                forXPath:
                    "//*[local-name()='sectPr']"
            )
            .compactMap {
                $0 as? XMLElement
            }

        XCTAssertEqual(
            sections.count,
            2
        )

        for section in sections {
            XCTAssertEqual(
                try section.nodes(
                    forXPath:
                        "./*[local-name()='titlePg']"
                ).count,
                1
            )

            XCTAssertEqual(
                try section.nodes(
                    forXPath:
                        "./*[local-name()='headerReference' and @*[local-name()='type']='first']"
                ).count,
                1
            )

            XCTAssertEqual(
                try section.nodes(
                    forXPath:
                        "./*[local-name()='footerReference' and @*[local-name()='type']='first']"
                ).count,
                1
            )
        }

        let imported =
            try DOCXImporter
                .importedDocument(
                    from:
                        data
                )

        XCTAssertEqual(
            imported.sections.count,
            2
        )

        XCTAssertEqual(
            imported.sections[0]
                .page
                .effectiveFirstPageHeaderText,
            "FIRST SPECIAL HEADER"
        )

        XCTAssertEqual(
            imported.sections[0]
                .page
                .effectiveFirstPageFooterText,
            "FIRST SPECIAL FOOTER"
        )

        XCTAssertEqual(
            imported.sections[1]
                .page
                .effectiveFirstPageHeaderText,
            "SECOND SPECIAL HEADER"
        )

        XCTAssertEqual(
            imported.sections[1]
                .page
                .effectiveFirstPageFooterText,
            "SECOND SPECIAL FOOTER"
        )

        XCTAssertTrue(
            imported.sections[0]
                .page
                .hasDistinctFirstPageHeaderFooter
        )

        XCTAssertTrue(
            imported.sections[1]
                .page
                .hasDistinctFirstPageHeaderFooter
        )

        XCTAssertEqual(
            imported.sections[1]
                .location,
            (
                imported.text.string
                    as NSString
            )
            .range(
                of:
                    "Second section"
            )
            .location
        )
    }
}

extension DOCXHeaderFooterTests {
    func testDOCXRoundTripsMixedFirstOddEvenFurniturePerSection()
        throws {

        let text =
            NSAttributedString(
                string:
                    "Alpha section\nBeta section"
            )

        let boundary =
            ("Alpha section\n" as NSString).length

        var first =
            PageSettings()

        first.headerText = "ALPHA ODD HEADER"
        first.footerText = "ALPHA ODD FOOTER"
        first.differentOddEvenHeaderFooter = true
        first.evenPageHeaderText = "ALPHA EVEN HEADER"
        first.evenPageFooterText = "ALPHA EVEN FOOTER"
        first.firstPageHeaderText = "ALPHA FIRST HEADER"
        first.firstPageFooterText = "ALPHA FIRST FOOTER"
        first.showsPageNumbers = true
        first.headerPosition = .center
        first.footerPosition = .left
        first.pageNumberPosition = .right

        var second =
            PageSettings()

        second.headerText = "BETA ODD HEADER"
        second.footerText = "BETA ODD FOOTER"
        second.differentOddEvenHeaderFooter = true
        second.evenPageHeaderText = "BETA EVEN HEADER"
        second.evenPageFooterText = "BETA EVEN FOOTER"
        second.firstPageHeaderText = "BETA FIRST HEADER"
        second.firstPageFooterText = "BETA FIRST FOOTER"
        second.showsPageNumbers = true
        second.headerPosition = .right
        second.footerPosition = .center
        second.pageNumberPosition = .left

        let data =
            try DOCXExporter.data(
                from: text,
                title:
                    "Mixed First Odd Even Furniture",
                settings: second,
                sections: [
                    DocumentSection(
                        location: 0,
                        page: first
                    ),
                    DocumentSection(
                        location: boundary,
                        page: second
                    )
                ]
            )

        let parts =
            Dictionary(
                uniqueKeysWithValues:
                    try DOCXPackage.entries(in: data)
                        .map {
                            ($0.path, $0.data)
                        }
            )

        let document =
            try DOCXPackage.xml(
                XCTUnwrap(
                    parts["word/document.xml"]
                )
            )

        let sectionNodes =
            try document.nodes(
                forXPath:
                    "//*[local-name()='sectPr']"
            )

        XCTAssertEqual(
            sectionNodes.count,
            2
        )

        for section in sectionNodes {
            XCTAssertEqual(
                try section.nodes(
                    forXPath:
                        "./*[local-name()='headerReference']"
                ).count,
                3
            )

            XCTAssertEqual(
                try section.nodes(
                    forXPath:
                        "./*[local-name()='footerReference']"
                ).count,
                3
            )

            for type in [
                "default",
                "even",
                "first"
            ] {
                XCTAssertEqual(
                    try section.nodes(
                        forXPath:
                            "./*[local-name()='headerReference' and @*[local-name()='type']='\(type)']"
                    ).count,
                    1
                )

                XCTAssertEqual(
                    try section.nodes(
                        forXPath:
                            "./*[local-name()='footerReference' and @*[local-name()='type']='\(type)']"
                    ).count,
                    1
                )
            }

            XCTAssertEqual(
                try section.nodes(
                    forXPath:
                        "./*[local-name()='titlePg']"
                ).count,
                1
            )
        }

        let imported =
            try DOCXImporter.importedDocument(
                from: data
            )

        XCTAssertEqual(
            imported.sections.count,
            2
        )
        XCTAssertEqual(
            imported.sections[0].location,
            0
        )
        XCTAssertEqual(
            imported.sections[1].location,
            boundary
        )

        let alpha =
            imported.sections[0].page

        XCTAssertTrue(
            alpha.usesDifferentOddEvenHeaderFooter
        )
        XCTAssertTrue(
            alpha.hasDistinctFirstPageHeaderFooter
        )
        XCTAssertEqual(
            alpha.effectiveHeaderText,
            "ALPHA ODD HEADER"
        )
        XCTAssertEqual(
            alpha.footerText,
            "ALPHA ODD FOOTER"
        )
        XCTAssertEqual(
            alpha.effectiveEvenPageHeaderText,
            "ALPHA EVEN HEADER"
        )
        XCTAssertEqual(
            alpha.effectiveEvenPageFooterText,
            "ALPHA EVEN FOOTER"
        )
        XCTAssertEqual(
            alpha.effectiveFirstPageHeaderText,
            "ALPHA FIRST HEADER"
        )
        XCTAssertEqual(
            alpha.effectiveFirstPageFooterText,
            "ALPHA FIRST FOOTER"
        )
        XCTAssertTrue(
            alpha.showsPageNumbers
        )
        XCTAssertEqual(
            alpha.effectiveHeaderPosition,
            .center
        )
        XCTAssertEqual(
            alpha.effectiveFooterPosition,
            .left
        )
        XCTAssertEqual(
            alpha.effectivePageNumberPosition,
            .right
        )

        let beta =
            imported.sections[1].page

        XCTAssertTrue(
            beta.usesDifferentOddEvenHeaderFooter
        )
        XCTAssertTrue(
            beta.hasDistinctFirstPageHeaderFooter
        )
        XCTAssertEqual(
            beta.effectiveHeaderText,
            "BETA ODD HEADER"
        )
        XCTAssertEqual(
            beta.footerText,
            "BETA ODD FOOTER"
        )
        XCTAssertEqual(
            beta.effectiveEvenPageHeaderText,
            "BETA EVEN HEADER"
        )
        XCTAssertEqual(
            beta.effectiveEvenPageFooterText,
            "BETA EVEN FOOTER"
        )
        XCTAssertEqual(
            beta.effectiveFirstPageHeaderText,
            "BETA FIRST HEADER"
        )
        XCTAssertEqual(
            beta.effectiveFirstPageFooterText,
            "BETA FIRST FOOTER"
        )
        XCTAssertTrue(
            beta.showsPageNumbers
        )
        XCTAssertEqual(
            beta.effectiveHeaderPosition,
            .right
        )
        XCTAssertEqual(
            beta.effectiveFooterPosition,
            .center
        )
        XCTAssertEqual(
            beta.effectivePageNumberPosition,
            .left
        )
    }
}

extension DOCXHeaderFooterTests {
    func testDOCXRoundTripsNativeSectionBreakTypes()
        throws {

        let text =
            NSAttributedString(
                string:
                    "One\nTwo\nThree\nFour"
            )

        let firstBoundary =
            (
                "One\n"
                as NSString
            )
            .length

        let secondBoundary =
            (
                "One\nTwo\n"
                as NSString
            )
            .length

        let thirdBoundary =
            (
                "One\nTwo\nThree\n"
                as NSString
            )
            .length

        var page =
            PageSettings()

        page.footerText =
            ""

        page.showsPageNumbers =
            false

        let data =
            try DOCXExporter.data(
                from:
                    text,
                title:
                    "Section Break Types",
                settings:
                    page,
                sections:
                    [
                        DocumentSection(
                            location:
                                0,
                            page:
                                page,
                            breakType:
                                .nextPage
                        ),
                        DocumentSection(
                            location:
                                firstBoundary,
                            page:
                                page,
                            breakType:
                                .continuous
                        ),
                        DocumentSection(
                            location:
                                secondBoundary,
                            page:
                                page,
                            breakType:
                                .oddPage
                        ),
                        DocumentSection(
                            location:
                                thirdBoundary,
                            page:
                                page,
                            breakType:
                                .evenPage
                        )
                    ]
            )

        let parts =
            Dictionary(
                uniqueKeysWithValues:
                    try DOCXPackage
                        .entries(
                            in:
                                data
                        )
                        .map {
                            (
                                $0.path,
                                $0.data
                            )
                        }
            )

        let document =
            try DOCXPackage.xml(
                XCTUnwrap(
                    parts[
                        "word/document.xml"
                    ]
                )
            )

        let sectionNodes =
            try document.nodes(
                forXPath:
                    "//*[local-name()='sectPr']"
            )

        XCTAssertEqual(
            sectionNodes.count,
            4
        )

        // In WordprocessingML the type on a sectPr ending one
        // section specifies the break that starts the FOLLOWING
        // section. The final body sectPr therefore has no following
        // BOLD section and uses the default nextPage value.
        let expected = [
            "continuous",
            "oddPage",
            "evenPage",
            "nextPage"
        ]

        for (
            index,
            value
        ) in expected.enumerated() {

            XCTAssertEqual(
                try sectionNodes[
                    index
                ]
                .nodes(
                    forXPath:
                        "./*[local-name()='type' and @*[local-name()='val']='\(value)']"
                )
                .count,
                1
            )
        }

        let imported =
            try DOCXImporter
                .importedDocument(
                    from:
                        data
                )

        XCTAssertEqual(
            imported.sections.map(
                \.location
            ),
            [
                0,
                firstBoundary,
                secondBoundary,
                thirdBoundary
            ]
        )

        XCTAssertEqual(
            imported.sections.map(
                \.effectiveBreakType
            ),
            [
                .nextPage,
                .continuous,
                .oddPage,
                .evenPage
            ]
        )
    }
}


extension DOCXHeaderFooterTests {
    func testDOCXRoundTripsSectionPageNumberStartAndFormat()
        throws {

        let firstText =
            "Alpha section\n"

        let boundary =
            (
                firstText
                as NSString
            )
            .length

        let text =
            NSAttributedString(
                string:
                    firstText
                    + "Beta section"
            )

        var first =
            PageSettings()

        first.footerText =
            ""

        first.pageNumberStart =
            3

        first.pageNumberFormat =
            "lowerRoman"

        var second =
            PageSettings()

        second.footerText =
            ""

        second.pageNumberStart =
            8

        second.pageNumberFormat =
            "upperLetter"

        let data =
            try DOCXExporter.data(
                from:
                    text,
                title:
                    "Section Page Numbers",
                settings:
                    first,
                sections:
                    [
                        DocumentSection(
                            location:
                                0,
                            page:
                                first
                        ),
                        DocumentSection(
                            location:
                                boundary,
                            page:
                                second
                        )
                    ]
            )

        let entries =
            try DOCXPackage.entries(
                in:
                    data
            )

        let documentData =
            try XCTUnwrap(
                entries.first {
                    $0.path
                        == "word/document.xml"
                }?
                .data
            )

        let document =
            try DOCXPackage.xml(
                documentData
            )

        let sectionNodes =
            try document.nodes(
                forXPath:
                    "//*[local-name()='sectPr']"
            )

        XCTAssertEqual(
            sectionNodes.count,
            2
        )

        XCTAssertEqual(
            try sectionNodes[0]
                .nodes(
                    forXPath:
                        "./*[local-name()='pgNumType' and @*[local-name()='start']='3' and @*[local-name()='fmt']='lowerRoman']"
                )
                .count,
            1
        )

        XCTAssertEqual(
            try sectionNodes[1]
                .nodes(
                    forXPath:
                        "./*[local-name()='pgNumType' and @*[local-name()='start']='8' and @*[local-name()='fmt']='upperLetter']"
                )
                .count,
            1
        )

        let imported =
            try DOCXImporter
                .importedDocument(
                    from:
                        data
                )

        XCTAssertEqual(
            imported.sections.count,
            2
        )

        XCTAssertEqual(
            imported.sections[0]
                .page
                .pageNumberStart,
            3
        )

        XCTAssertEqual(
            imported.sections[0]
                .page
                .pageNumberFormat,
            "lowerRoman"
        )

        XCTAssertEqual(
            imported.sections[1]
                .page
                .pageNumberStart,
            8
        )

        XCTAssertEqual(
            imported.sections[1]
                .page
                .pageNumberFormat,
            "upperLetter"
        )
    }
}


extension DOCXHeaderFooterTests {
    func testDOCXExportsNativeWordColumnSettings()
        throws {

        var page =
            PageSettings()

        page.footerText =
            ""

        page.columnCount =
            2

        page.columnSpacing =
            36

        let data =
            try DOCXExporter.data(
                from:
                    NSAttributedString(
                        string:
                            "Two column export"
                    ),
                title:
                    "Columns",
                settings:
                    page
            )

        let entries =
            try DOCXPackage.entries(
                in:
                    data
            )

        let documentData =
            try XCTUnwrap(
                entries.first {
                    $0.path
                        == "word/document.xml"
                }?
                .data
            )

        let document =
            try DOCXPackage.xml(
                documentData
            )

        let columns =
            try document.nodes(
                forXPath:
                    "//*[local-name()='sectPr']/*[local-name()='cols']"
            )

        XCTAssertEqual(
            columns.count,
            1
        )

        let element =
            try XCTUnwrap(
                columns.first
                    as? XMLElement
            )

        func attribute(
            _ name: String
        ) -> String? {
            element.attributes?
                .first {
                    $0.localName == name
                        || $0.name == name
                        || $0.name == "w:" + name
                }?
                .stringValue
        }

        XCTAssertEqual(
            attribute(
                "num"
            ),
            "2"
        )

        // 36 points = 0.5 inch = 720 twentieths of a point.
        XCTAssertEqual(
            attribute(
                "space"
            ),
            "720"
        )
    }

    func testDOCXOmitsColumnsForLegacySingleColumnDefaults()
        throws {

        var page =
            PageSettings()

        page.footerText =
            ""

        XCTAssertNil(
            page.columnCount
        )

        XCTAssertNil(
            page.columnSpacing
        )

        let data =
            try DOCXExporter.data(
                from:
                    NSAttributedString(
                        string:
                            "Legacy single column"
                    ),
                title:
                    "Single Column",
                settings:
                    page
            )

        let entries =
            try DOCXPackage.entries(
                in:
                    data
            )

        let documentData =
            try XCTUnwrap(
                entries.first {
                    $0.path
                        == "word/document.xml"
                }?
                .data
            )

        let document =
            try DOCXPackage.xml(
                documentData
            )

        XCTAssertTrue(
            try document.nodes(
                forXPath:
                    "//*[local-name()='sectPr']/*[local-name()='cols']"
            )
            .isEmpty
        )
    }
}


extension DOCXHeaderFooterTests {
    func testDOCXImportsNativeWordColumnSettings()
        throws {

        var page =
            PageSettings()

        page.footerText =
            ""

        page.columnCount =
            3

        page.columnSpacing =
            24

        let data =
            try DOCXExporter.data(
                from:
                    NSAttributedString(
                        string:
                            "Three column round trip"
                    ),
                title:
                    "Columns",
                settings:
                    page
            )

        let imported =
            try DOCXImporter
                .importedDocument(
                    from:
                        data
                )

        XCTAssertEqual(
            imported.page
                .columnCount,
            3
        )

        XCTAssertEqual(
            imported.page
                .columnSpacing,
            24
        )

        XCTAssertEqual(
            imported.page
                .effectiveColumnCount,
            3
        )

        XCTAssertEqual(
            imported.page
                .effectiveColumnSpacing,
            24,
            accuracy:
                0.001
        )
    }

    func testDOCXImportWithoutColsKeepsLegacySingleColumnDefaults()
        throws {

        var page =
            PageSettings()

        page.footerText =
            ""

        let data =
            try DOCXExporter.data(
                from:
                    NSAttributedString(
                        string:
                            "Legacy document"
                    ),
                title:
                    "Legacy",
                settings:
                    page
            )

        let imported =
            try DOCXImporter
                .importedDocument(
                    from:
                        data
                )

        XCTAssertNil(
            imported.page
                .columnCount
        )

        XCTAssertNil(
            imported.page
                .columnSpacing
        )

        XCTAssertEqual(
            imported.page
                .effectiveColumnCount,
            1
        )

        XCTAssertEqual(
            imported.page
                .effectiveColumnSpacing,
            36
        )
    }
}


extension DOCXHeaderFooterTests {
    func testDOCXRoundTripsNextColumnSectionBreak() throws {
        let first = "Alpha\n"
        let boundary = (first as NSString).length
        let text = NSAttributedString(string: first + "Beta")

        var page = PageSettings()
        page.footerText = ""
        page.columnCount = 2
        page.columnSpacing = 36

        let data =
            try DOCXExporter.data(
                from: text,
                title: "Next Column",
                settings: page,
                sections: [
                    DocumentSection(
                        location: 0,
                        page: page
                    ),
                    DocumentSection(
                        location: boundary,
                        page: page,
                        breakType: .nextColumn
                    )
                ]
            )

        let imported =
            try DOCXImporter.importedDocument(
                from: data
            )

        XCTAssertEqual(imported.sections.count, 2)

        XCTAssertEqual(
            imported.sections[1].location,
            boundary
        )

        XCTAssertEqual(
            imported.sections[1].effectiveBreakType,
            .nextColumn
        )

        XCTAssertEqual(
            imported.sections[1].page.effectiveColumnCount,
            2
        )
    }
}

// MARK: - Independent Word continuous section compatibility

extension DOCXHeaderFooterTests {
    func testIndependentWordContinuousSectionBreakImportsAndReexports()
        throws
    {
        let contentTypes =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
              <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
              <Default Extension="xml" ContentType="application/xml"/>
              <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
            </Types>
            """

        let rootRelationships =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
              <Relationship
                Id="rId1"
                Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument"
                Target="word/document.xml"/>
            </Relationships>
            """

        // Authored independently of BOLD Writer's exporter.
        //
        // The paragraph-level sectPr ends the first Word section.
        // Its w:type=continuous describes the boundary that starts
        // the following section.
        //
        // The first section is one column. The following section is
        // two columns so the test independently checks that break
        // ownership and page-property ownership are not conflated.
        let documentXML =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:document
              xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
              <w:body>
                <w:p>
                  <w:pPr>
                    <w:sectPr>
                      <w:type w:val="continuous"/>
                      <w:pgSz
                        w:w="12240"
                        w:h="15840"/>
                      <w:pgMar
                        w:top="1440"
                        w:right="1440"
                        w:bottom="1440"
                        w:left="1440"
                        w:header="720"
                        w:footer="720"
                        w:gutter="0"/>
                      <w:cols
                        w:num="1"
                        w:space="720"/>
                    </w:sectPr>
                  </w:pPr>
                  <w:r>
                    <w:t>Alpha</w:t>
                  </w:r>
                </w:p>
                <w:p>
                  <w:r>
                    <w:t>Beta</w:t>
                  </w:r>
                </w:p>
                <w:sectPr>
                  <w:pgSz
                    w:w="12240"
                    w:h="15840"/>
                  <w:pgMar
                    w:top="1440"
                    w:right="1440"
                    w:bottom="1440"
                    w:left="1440"
                    w:header="720"
                    w:footer="720"
                    w:gutter="0"/>
                  <w:cols
                    w:num="2"
                    w:space="720"/>
                </w:sectPr>
              </w:body>
            </w:document>
            """

        let data =
            ZipArchiveWriter.archive(
                [
                    ZipEntry(
                        path:
                            "[Content_Types].xml",
                        data:
                            Data(
                                contentTypes.utf8
                            )
                    ),
                    ZipEntry(
                        path:
                            "_rels/.rels",
                        data:
                            Data(
                                rootRelationships.utf8
                            )
                    ),
                    ZipEntry(
                        path:
                            "word/document.xml",
                        data:
                            Data(
                                documentXML.utf8
                            )
                    ),
                ]
            )

        let imported =
            try DOCXImporter.importedDocument(
                from: data
            )

        XCTAssertEqual(
            imported.sections.count,
            2
        )

        let betaRange =
            (
                imported.text.string
                as NSString
            )
            .range(
                of: "Beta"
            )

        XCTAssertNotEqual(
            betaRange.location,
            NSNotFound
        )

        XCTAssertEqual(
            imported.sections[0].location,
            0
        )

        XCTAssertEqual(
            imported.sections[0].effectiveBreakType,
            .nextPage,
            "The first BOLD section has no preceding Word section break."
        )

        XCTAssertEqual(
            imported.sections[1].location,
            betaRange.location
        )

        XCTAssertEqual(
            imported.sections[1].effectiveBreakType,
            .continuous,
            "Word's first section-ending w:type=continuous must become the break type of the following BOLD section."
        )

        XCTAssertEqual(
            imported.sections[0]
                .page
                .effectiveColumnCount,
            1
        )

        XCTAssertEqual(
            imported.sections[1]
                .page
                .effectiveColumnCount,
            2
        )

        let reexported =
            try DOCXExporter.data(
                from:
                    imported.text,
                title:
                    "Independent Continuous Section",
                settings:
                    imported.page,
                sections:
                    imported.sections
            )

        let entries =
            try DOCXPackage.entries(
                in: reexported
            )

        let documentPart =
            try XCTUnwrap(
                entries.first {
                    $0.path
                        == "word/document.xml"
                }
            )

        let xml =
            try DOCXPackage.xml(
                documentPart.data
            )

        let sectionNodes =
            try xml.nodes(
                forXPath:
                    "//*[local-name()='sectPr']"
            )

        XCTAssertEqual(
            sectionNodes.count,
            2
        )

        XCTAssertEqual(
            try sectionNodes[0]
                .nodes(
                    forXPath:
                        "./*[local-name()='type' and @*[local-name()='val']='continuous']"
                )
                .count,
            1,
            "The sectPr ending the first exported Word section must own the continuous break."
        )

        XCTAssertEqual(
            try sectionNodes[0]
                .nodes(
                    forXPath:
                        "./*[local-name()='cols' and @*[local-name()='num']='1']"
                )
                .count,
            1
        )

        XCTAssertEqual(
            try sectionNodes[1]
                .nodes(
                    forXPath:
                        "./*[local-name()='cols' and @*[local-name()='num']='2']"
                )
                .count,
            1
        )

        let reopened =
            try DOCXImporter.importedDocument(
                from:
                    reexported
            )

        XCTAssertEqual(
            reopened.sections.count,
            2
        )

        let reopenedBeta =
            (
                reopened.text.string
                as NSString
            )
            .range(
                of: "Beta"
            )

        XCTAssertNotEqual(
            reopenedBeta.location,
            NSNotFound
        )

        XCTAssertEqual(
            reopened.sections[1].location,
            reopenedBeta.location
        )

        XCTAssertEqual(
            reopened.sections[1].effectiveBreakType,
            .continuous
        )

        XCTAssertEqual(
            reopened.sections[1]
                .page
                .effectiveColumnCount,
            2
        )
    }
}

// MARK: - Independent Word section page-numbering compatibility

extension DOCXHeaderFooterTests {
    func testIndependentWordSectionPageNumberStartAndFormatRoundTrip()
        throws
    {
        let contentTypes =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
              <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
              <Default Extension="xml" ContentType="application/xml"/>
              <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
            </Types>
            """

        let rootRelationships =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
              <Relationship
                Id="rId1"
                Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument"
                Target="word/document.xml"/>
            </Relationships>
            """

        // Independently authored WordprocessingML.
        //
        // Page-number settings belong to each section's own sectPr,
        // unlike w:type, whose value describes the break that starts
        // the following section.
        let documentXML =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:document
              xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
              <w:body>
                <w:p>
                  <w:pPr>
                    <w:sectPr>
                      <w:type w:val="nextPage"/>
                      <w:pgNumType
                        w:start="3"
                        w:fmt="lowerRoman"/>
                      <w:pgSz
                        w:w="12240"
                        w:h="15840"/>
                      <w:pgMar
                        w:top="1440"
                        w:right="1440"
                        w:bottom="1440"
                        w:left="1440"/>
                    </w:sectPr>
                  </w:pPr>
                  <w:r>
                    <w:t>Roman Front Matter</w:t>
                  </w:r>
                </w:p>
                <w:p>
                  <w:r>
                    <w:t>Decimal Body</w:t>
                  </w:r>
                </w:p>
                <w:sectPr>
                  <w:pgNumType
                    w:start="8"
                    w:fmt="decimal"/>
                  <w:pgSz
                    w:w="12240"
                    w:h="15840"/>
                  <w:pgMar
                    w:top="1440"
                    w:right="1440"
                    w:bottom="1440"
                    w:left="1440"/>
                </w:sectPr>
              </w:body>
            </w:document>
            """

        let data =
            ZipArchiveWriter.archive(
                [
                    ZipEntry(
                        path:
                            "[Content_Types].xml",
                        data:
                            Data(
                                contentTypes.utf8
                            )
                    ),
                    ZipEntry(
                        path:
                            "_rels/.rels",
                        data:
                            Data(
                                rootRelationships.utf8
                            )
                    ),
                    ZipEntry(
                        path:
                            "word/document.xml",
                        data:
                            Data(
                                documentXML.utf8
                            )
                    ),
                ]
            )

        let imported =
            try DOCXImporter.importedDocument(
                from: data
            )

        XCTAssertEqual(
            imported.sections.count,
            2
        )

        let bodyRange =
            (
                imported.text.string
                as NSString
            )
            .range(
                of:
                    "Decimal Body"
            )

        XCTAssertNotEqual(
            bodyRange.location,
            NSNotFound
        )

        XCTAssertEqual(
            imported.sections[0].location,
            0
        )

        XCTAssertEqual(
            imported.sections[1].location,
            bodyRange.location
        )

        XCTAssertEqual(
            imported.sections[0]
                .page
                .pageNumberStart,
            3
        )

        XCTAssertEqual(
            imported.sections[0]
                .page
                .pageNumberFormat,
            "lowerRoman"
        )

        XCTAssertEqual(
            imported.sections[1]
                .page
                .pageNumberStart,
            8
        )

        XCTAssertEqual(
            imported.sections[1]
                .page
                .pageNumberFormat,
            "decimal"
        )

        let reexported =
            try DOCXExporter.data(
                from:
                    imported.text,
                title:
                    "Independent Word Page Numbering",
                settings:
                    imported.page,
                sections:
                    imported.sections
            )

        let entries =
            try DOCXPackage.entries(
                in:
                    reexported
            )

        let documentPart =
            try XCTUnwrap(
                entries.first {
                    $0.path
                        == "word/document.xml"
                }
            )

        let xml =
            try DOCXPackage.xml(
                documentPart.data
            )

        let sectionNodes =
            try xml.nodes(
                forXPath:
                    "//*[local-name()='sectPr']"
            )

        XCTAssertEqual(
            sectionNodes.count,
            2
        )

        XCTAssertEqual(
            try sectionNodes[0]
                .nodes(
                    forXPath:
                        "./*[local-name()='pgNumType' and @*[local-name()='start']='3' and @*[local-name()='fmt']='lowerRoman']"
                )
                .count,
            1,
            "The first Word section must retain its Roman numbering start and format."
        )

        XCTAssertEqual(
            try sectionNodes[1]
                .nodes(
                    forXPath:
                        "./*[local-name()='pgNumType' and @*[local-name()='start']='8' and @*[local-name()='fmt']='decimal']"
                )
                .count,
            1,
            "The second Word section must retain its decimal numbering restart."
        )

        let reopened =
            try DOCXImporter.importedDocument(
                from:
                    reexported
            )

        XCTAssertEqual(
            reopened.sections.count,
            2
        )

        let reopenedBody =
            (
                reopened.text.string
                as NSString
            )
            .range(
                of:
                    "Decimal Body"
            )

        XCTAssertNotEqual(
            reopenedBody.location,
            NSNotFound
        )

        XCTAssertEqual(
            reopened.sections[1].location,
            reopenedBody.location
        )

        XCTAssertEqual(
            reopened.sections[0]
                .page
                .pageNumberStart,
            3
        )

        XCTAssertEqual(
            reopened.sections[0]
                .page
                .pageNumberFormat,
            "lowerRoman"
        )

        XCTAssertEqual(
            reopened.sections[1]
                .page
                .pageNumberStart,
            8
        )

        XCTAssertEqual(
            reopened.sections[1]
                .page
                .pageNumberFormat,
            "decimal"
        )
    }
}

// MARK: - Independent Word odd/even header/footer compatibility

extension DOCXHeaderFooterTests {
    func testIndependentWordOddEvenHeadersAndFootersRoundTrip()
        throws
    {
        let contentTypes =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
              <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
              <Default Extension="xml" ContentType="application/xml"/>
              <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
              <Override PartName="/word/header1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/>
              <Override PartName="/word/header2.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/>
              <Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>
              <Override PartName="/word/footer2.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>
              <Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/>
            </Types>
            """

        let rootRelationships =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
              <Relationship
                Id="rId1"
                Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument"
                Target="word/document.xml"/>
            </Relationships>
            """

        let documentRelationships =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
              <Relationship
                Id="rIdDefaultHeader"
                Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/header"
                Target="header1.xml"/>
              <Relationship
                Id="rIdEvenHeader"
                Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/header"
                Target="header2.xml"/>
              <Relationship
                Id="rIdDefaultFooter"
                Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer"
                Target="footer1.xml"/>
              <Relationship
                Id="rIdEvenFooter"
                Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer"
                Target="footer2.xml"/>
              <Relationship
                Id="rIdSettings"
                Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings"
                Target="settings.xml"/>
            </Relationships>
            """

        let documentXML =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:document
              xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
              xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
              <w:body>
                <w:p>
                  <w:r>
                    <w:t>Odd Even Body</w:t>
                  </w:r>
                </w:p>
                <w:sectPr>
                  <w:headerReference
                    w:type="default"
                    r:id="rIdDefaultHeader"/>
                  <w:headerReference
                    w:type="even"
                    r:id="rIdEvenHeader"/>
                  <w:footerReference
                    w:type="default"
                    r:id="rIdDefaultFooter"/>
                  <w:footerReference
                    w:type="even"
                    r:id="rIdEvenFooter"/>
                  <w:pgSz
                    w:w="12240"
                    w:h="15840"/>
                  <w:pgMar
                    w:top="1440"
                    w:right="1440"
                    w:bottom="1440"
                    w:left="1440"
                    w:header="720"
                    w:footer="720"/>
                </w:sectPr>
              </w:body>
            </w:document>
            """

        let defaultHeader =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:hdr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
              <w:p>
                <w:r>
                  <w:t>DEFAULT HEADER</w:t>
                </w:r>
              </w:p>
            </w:hdr>
            """

        let evenHeader =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:hdr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
              <w:p>
                <w:r>
                  <w:t>EVEN HEADER</w:t>
                </w:r>
              </w:p>
            </w:hdr>
            """

        let defaultFooter =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:ftr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
              <w:p>
                <w:r>
                  <w:t>DEFAULT FOOTER</w:t>
                </w:r>
              </w:p>
            </w:ftr>
            """

        let evenFooter =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:ftr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
              <w:p>
                <w:r>
                  <w:t>EVEN FOOTER</w:t>
                </w:r>
              </w:p>
            </w:ftr>
            """

        let settingsXML =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
              <w:evenAndOddHeaders/>
            </w:settings>
            """

        let data =
            ZipArchiveWriter.archive(
                [
                    ZipEntry(
                        path:
                            "[Content_Types].xml",
                        data:
                            Data(
                                contentTypes.utf8
                            )
                    ),
                    ZipEntry(
                        path:
                            "_rels/.rels",
                        data:
                            Data(
                                rootRelationships.utf8
                            )
                    ),
                    ZipEntry(
                        path:
                            "word/document.xml",
                        data:
                            Data(
                                documentXML.utf8
                            )
                    ),
                    ZipEntry(
                        path:
                            "word/_rels/document.xml.rels",
                        data:
                            Data(
                                documentRelationships.utf8
                            )
                    ),
                    ZipEntry(
                        path:
                            "word/header1.xml",
                        data:
                            Data(
                                defaultHeader.utf8
                            )
                    ),
                    ZipEntry(
                        path:
                            "word/header2.xml",
                        data:
                            Data(
                                evenHeader.utf8
                            )
                    ),
                    ZipEntry(
                        path:
                            "word/footer1.xml",
                        data:
                            Data(
                                defaultFooter.utf8
                            )
                    ),
                    ZipEntry(
                        path:
                            "word/footer2.xml",
                        data:
                            Data(
                                evenFooter.utf8
                            )
                    ),
                    ZipEntry(
                        path:
                            "word/settings.xml",
                        data:
                            Data(
                                settingsXML.utf8
                            )
                    ),
                ]
            )

        let imported =
            try DOCXImporter.importedDocument(
                from:
                    data
            )

        XCTAssertEqual(
            imported.sections.count,
            1
        )

        let page =
            imported.sections[0].page

        XCTAssertTrue(
            page.usesDifferentOddEvenHeaderFooter
        )

        XCTAssertTrue(
            page.effectiveHeaderText.contains(
                "DEFAULT HEADER"
            )
        )

        XCTAssertTrue(
            page.effectiveEvenPageHeaderText.contains(
                "EVEN HEADER"
            )
        )

        XCTAssertTrue(
            page.footerText.contains(
                "DEFAULT FOOTER"
            )
        )

        XCTAssertTrue(
            page.effectiveEvenPageFooterText.contains(
                "EVEN FOOTER"
            )
        )

        let reexported =
            try DOCXExporter.data(
                from:
                    imported.text,
                title:
                    "Independent Odd Even Header Footer",
                settings:
                    imported.page,
                sections:
                    imported.sections
            )

        let entries =
            try DOCXPackage.entries(
                in:
                    reexported
            )

        let documentPart =
            try XCTUnwrap(
                entries.first {
                    $0.path
                        == "word/document.xml"
                }
            )

        let document =
            try DOCXPackage.xml(
                documentPart.data
            )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='sectPr']/*[local-name()='headerReference' and @*[local-name()='type']='default']"
            )
            .count,
            1
        )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='sectPr']/*[local-name()='headerReference' and @*[local-name()='type']='even']"
            )
            .count,
            1
        )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='sectPr']/*[local-name()='footerReference' and @*[local-name()='type']='default']"
            )
            .count,
            1
        )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='sectPr']/*[local-name()='footerReference' and @*[local-name()='type']='even']"
            )
            .count,
            1
        )

        let settingsPart =
            try XCTUnwrap(
                entries.first {
                    $0.path
                        == "word/settings.xml"
                }
            )

        let exportedSettings =
            try DOCXPackage.xml(
                settingsPart.data
            )

        XCTAssertEqual(
            try exportedSettings.nodes(
                forXPath:
                    "//*[local-name()='evenAndOddHeaders']"
            )
            .count,
            1
        )

        let reopened =
            try DOCXImporter.importedDocument(
                from:
                    reexported
            )

        XCTAssertEqual(
            reopened.sections.count,
            1
        )

        let reopenedPage =
            reopened.sections[0].page

        XCTAssertTrue(
            reopenedPage.usesDifferentOddEvenHeaderFooter
        )

        XCTAssertTrue(
            reopenedPage.effectiveHeaderText.contains(
                "DEFAULT HEADER"
            )
        )

        XCTAssertTrue(
            reopenedPage.effectiveEvenPageHeaderText.contains(
                "EVEN HEADER"
            )
        )

        XCTAssertTrue(
            reopenedPage.footerText.contains(
                "DEFAULT FOOTER"
            )
        )

        XCTAssertTrue(
            reopenedPage.effectiveEvenPageFooterText.contains(
                "EVEN FOOTER"
            )
        )
    }
}

// MARK: - Independent Word odd/even section-start compatibility

extension DOCXHeaderFooterTests {
    func testIndependentWordOddAndEvenPageSectionStartsRoundTrip()
        throws
    {
        let contentTypes =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
              <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
              <Default Extension="xml" ContentType="application/xml"/>
              <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
            </Types>
            """

        let rootRelationships =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
              <Relationship
                Id="rId1"
                Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument"
                Target="word/document.xml"/>
            </Relationships>
            """

        // Word stores the break starting the FOLLOWING section on
        // the sectPr that ends the current section.
        //
        // Section 1 ends with oddPage -> section 2 begins on odd page.
        // Section 2 ends with evenPage -> section 3 begins on even page.
        let documentXML =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:document
              xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
              <w:body>
                <w:p>
                  <w:pPr>
                    <w:sectPr>
                      <w:type w:val="oddPage"/>
                      <w:pgSz
                        w:w="12240"
                        w:h="15840"/>
                      <w:pgMar
                        w:top="1440"
                        w:right="1440"
                        w:bottom="1440"
                        w:left="1440"/>
                    </w:sectPr>
                  </w:pPr>
                  <w:r>
                    <w:t>FIRST SECTION</w:t>
                  </w:r>
                </w:p>

                <w:p>
                  <w:pPr>
                    <w:sectPr>
                      <w:type w:val="evenPage"/>
                      <w:pgSz
                        w:w="12240"
                        w:h="15840"/>
                      <w:pgMar
                        w:top="1440"
                        w:right="1440"
                        w:bottom="1440"
                        w:left="1440"/>
                    </w:sectPr>
                  </w:pPr>
                  <w:r>
                    <w:t>ODD START SECTION</w:t>
                  </w:r>
                </w:p>

                <w:p>
                  <w:r>
                    <w:t>EVEN START SECTION</w:t>
                  </w:r>
                </w:p>

                <w:sectPr>
                  <w:pgSz
                    w:w="12240"
                    w:h="15840"/>
                  <w:pgMar
                    w:top="1440"
                    w:right="1440"
                    w:bottom="1440"
                    w:left="1440"/>
                </w:sectPr>
              </w:body>
            </w:document>
            """

        let data =
            ZipArchiveWriter.archive(
                [
                    ZipEntry(
                        path:
                            "[Content_Types].xml",
                        data:
                            Data(
                                contentTypes.utf8
                            )
                    ),
                    ZipEntry(
                        path:
                            "_rels/.rels",
                        data:
                            Data(
                                rootRelationships.utf8
                            )
                    ),
                    ZipEntry(
                        path:
                            "word/document.xml",
                        data:
                            Data(
                                documentXML.utf8
                            )
                    ),
                ]
            )

        let imported =
            try DOCXImporter.importedDocument(
                from:
                    data
            )

        XCTAssertEqual(
            imported.sections.count,
            3
        )

        let oddStart =
            (
                imported.text.string
                as NSString
            )
            .range(
                of:
                    "ODD START SECTION"
            )

        let evenStart =
            (
                imported.text.string
                as NSString
            )
            .range(
                of:
                    "EVEN START SECTION"
            )

        XCTAssertNotEqual(
            oddStart.location,
            NSNotFound
        )

        XCTAssertNotEqual(
            evenStart.location,
            NSNotFound
        )

        XCTAssertEqual(
            imported.sections.map(
                \.location
            ),
            [
                0,
                oddStart.location,
                evenStart.location
            ]
        )

        XCTAssertEqual(
            imported.sections.map(
                \.effectiveBreakType
            ),
            [
                .nextPage,
                .oddPage,
                .evenPage
            ]
        )

        let reexported =
            try DOCXExporter.data(
                from:
                    imported.text,
                title:
                    "Independent Odd Even Section Starts",
                settings:
                    imported.page,
                sections:
                    imported.sections
            )

        let entries =
            try DOCXPackage.entries(
                in:
                    reexported
            )

        let documentPart =
            try XCTUnwrap(
                entries.first {
                    $0.path
                        == "word/document.xml"
                }
            )

        let xml =
            try DOCXPackage.xml(
                documentPart.data
            )

        let sectionNodes =
            try xml.nodes(
                forXPath:
                    "//*[local-name()='sectPr']"
            )

        XCTAssertEqual(
            sectionNodes.count,
            3
        )

        XCTAssertEqual(
            try sectionNodes[0]
                .nodes(
                    forXPath:
                        "./*[local-name()='type' and @*[local-name()='val']='oddPage']"
                )
                .count,
            1,
            "The sectPr ending section one must carry the odd-page break that starts section two."
        )

        XCTAssertEqual(
            try sectionNodes[1]
                .nodes(
                    forXPath:
                        "./*[local-name()='type' and @*[local-name()='val']='evenPage']"
                )
                .count,
            1,
            "The sectPr ending section two must carry the even-page break that starts section three."
        )

        XCTAssertEqual(
            try sectionNodes[2]
                .nodes(
                    forXPath:
                        "./*[local-name()='type' and @*[local-name()='val']='nextPage']"
                )
                .count,
            1,
            "The final Word sectPr has no following BOLD section and uses the default nextPage value."
        )

        let reopened =
            try DOCXImporter.importedDocument(
                from:
                    reexported
            )

        XCTAssertEqual(
            reopened.sections.count,
            3
        )

        let reopenedOdd =
            (
                reopened.text.string
                as NSString
            )
            .range(
                of:
                    "ODD START SECTION"
            )

        let reopenedEven =
            (
                reopened.text.string
                as NSString
            )
            .range(
                of:
                    "EVEN START SECTION"
            )

        XCTAssertNotEqual(
            reopenedOdd.location,
            NSNotFound
        )

        XCTAssertNotEqual(
            reopenedEven.location,
            NSNotFound
        )

        XCTAssertEqual(
            reopened.sections.map(
                \.location
            ),
            [
                0,
                reopenedOdd.location,
                reopenedEven.location
            ]
        )

        XCTAssertEqual(
            reopened.sections.map(
                \.effectiveBreakType
            ),
            [
                .nextPage,
                .oddPage,
                .evenPage
            ]
        )
    }
}

// MARK: - Independent Word mixed section geometry compatibility

extension DOCXHeaderFooterTests {
    func testIndependentWordMixedSectionPageGeometryAndMarginsRoundTrip()
        throws
    {
        let contentTypes =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
              <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
              <Default Extension="xml" ContentType="application/xml"/>
              <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
            </Types>
            """

        let rootRelationships =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
              <Relationship
                Id="rId1"
                Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument"
                Target="word/document.xml"/>
            </Relationships>
            """

        // Authored independently of DOCXExporter.
        //
        // Section one is portrait Letter with four deliberately distinct
        // margins. Section two is landscape Letter with four different
        // margins. The values are exact multiples of 20 twips per point
        // so import/export can round-trip them without ambiguous rounding.
        let documentXML =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:document
              xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
              <w:body>
                <w:p>
                  <w:pPr>
                    <w:sectPr>
                      <w:type w:val="nextPage"/>
                      <w:pgSz
                        w:w="12240"
                        w:h="15840"/>
                      <w:pgMar
                        w:top="1440"
                        w:right="1080"
                        w:bottom="1260"
                        w:left="900"/>
                    </w:sectPr>
                  </w:pPr>
                  <w:r>
                    <w:t>PORTRAIT SECTION</w:t>
                  </w:r>
                </w:p>

                <w:p>
                  <w:r>
                    <w:t>LANDSCAPE SECTION</w:t>
                  </w:r>
                </w:p>

                <w:sectPr>
                  <w:pgSz
                    w:w="15840"
                    w:h="12240"
                    w:orient="landscape"/>
                  <w:pgMar
                    w:top="720"
                    w:right="840"
                    w:bottom="960"
                    w:left="1200"/>
                </w:sectPr>
              </w:body>
            </w:document>
            """

        let data =
            ZipArchiveWriter.archive(
                [
                    ZipEntry(
                        path:
                            "[Content_Types].xml",
                        data:
                            Data(
                                contentTypes.utf8
                            )
                    ),
                    ZipEntry(
                        path:
                            "_rels/.rels",
                        data:
                            Data(
                                rootRelationships.utf8
                            )
                    ),
                    ZipEntry(
                        path:
                            "word/document.xml",
                        data:
                            Data(
                                documentXML.utf8
                            )
                    ),
                ]
            )

        let imported =
            try DOCXImporter.importedDocument(
                from:
                    data
            )

        XCTAssertEqual(
            imported.sections.count,
            2
        )

        let landscapeRange =
            (
                imported.text.string
                as NSString
            )
            .range(
                of:
                    "LANDSCAPE SECTION"
            )

        XCTAssertNotEqual(
            landscapeRange.location,
            NSNotFound
        )

        XCTAssertEqual(
            imported.sections.map(
                \.location
            ),
            [
                0,
                landscapeRange.location
            ]
        )

        func assertGeometry(
            _ data: Data,
            file: StaticString = #filePath,
            line: UInt = #line
        ) throws {
            let entries =
                try DOCXPackage.entries(
                    in:
                        data
                )

            let documentPart =
                try XCTUnwrap(
                    entries.first {
                        $0.path
                            == "word/document.xml"
                    },
                    file:
                        file,
                    line:
                        line
                )

            let xml =
                try DOCXPackage.xml(
                    documentPart.data
                )

            let sections =
                try xml.nodes(
                    forXPath:
                        "//*[local-name()='sectPr']"
                )

            XCTAssertEqual(
                sections.count,
                2,
                file:
                    file,
                line:
                    line
            )

            XCTAssertEqual(
                try sections[0]
                    .nodes(
                        forXPath:
                            "./*[local-name()='pgSz' and @*[local-name()='w']='12240' and @*[local-name()='h']='15840']"
                    )
                    .count,
                1,
                "First section must retain portrait Letter dimensions.",
                file:
                    file,
                line:
                    line
            )

            XCTAssertEqual(
                try sections[0]
                    .nodes(
                        forXPath:
                            "./*[local-name()='pgMar' and @*[local-name()='top']='1440' and @*[local-name()='right']='1080' and @*[local-name()='bottom']='1260' and @*[local-name()='left']='900']"
                    )
                    .count,
                1,
                "First section margins must remain section-specific.",
                file:
                    file,
                line:
                    line
            )

            XCTAssertEqual(
                try sections[1]
                    .nodes(
                        forXPath:
                            "./*[local-name()='pgSz' and @*[local-name()='w']='15840' and @*[local-name()='h']='12240' and @*[local-name()='orient']='landscape']"
                    )
                    .count,
                1,
                "Second section must retain landscape Letter dimensions.",
                file:
                    file,
                line:
                    line
            )

            XCTAssertEqual(
                try sections[1]
                    .nodes(
                        forXPath:
                            "./*[local-name()='pgMar' and @*[local-name()='top']='720' and @*[local-name()='right']='840' and @*[local-name()='bottom']='960' and @*[local-name()='left']='1200']"
                    )
                    .count,
                1,
                "Second section margins must remain section-specific.",
                file:
                    file,
                line:
                    line
            )
        }

        let firstExport =
            try DOCXExporter.data(
                from:
                    imported.text,
                title:
                    "Independent Mixed Geometry",
                settings:
                    imported.page,
                sections:
                    imported.sections
            )

        try assertGeometry(
            firstExport
        )

        let reopened =
            try DOCXImporter.importedDocument(
                from:
                    firstExport
            )

        XCTAssertEqual(
            reopened.sections.count,
            2
        )

        let reopenedLandscape =
            (
                reopened.text.string
                as NSString
            )
            .range(
                of:
                    "LANDSCAPE SECTION"
            )

        XCTAssertNotEqual(
            reopenedLandscape.location,
            NSNotFound
        )

        XCTAssertEqual(
            reopened.sections[1].location,
            reopenedLandscape.location
        )

        let secondExport =
            try DOCXExporter.data(
                from:
                    reopened.text,
                title:
                    "Independent Mixed Geometry Twice",
                settings:
                    reopened.page,
                sections:
                    reopened.sections
            )

        try assertGeometry(
            secondExport
        )
    }
}

// MARK: - Independent Word first-page header/footer compatibility

extension DOCXHeaderFooterTests {
    func testIndependentWordFirstPageHeaderFooterTitlePgRoundTrip()
        throws
    {
        let contentTypes =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
              <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
              <Default Extension="xml" ContentType="application/xml"/>
              <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
              <Override PartName="/word/header1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/>
              <Override PartName="/word/header2.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/>
              <Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>
              <Override PartName="/word/footer2.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>
            </Types>
            """

        let rootRelationships =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
              <Relationship
                Id="rId1"
                Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument"
                Target="word/document.xml"/>
            </Relationships>
            """

        let documentRelationships =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
              <Relationship
                Id="rIdDefaultHeader"
                Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/header"
                Target="header1.xml"/>
              <Relationship
                Id="rIdFirstHeader"
                Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/header"
                Target="header2.xml"/>
              <Relationship
                Id="rIdDefaultFooter"
                Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer"
                Target="footer1.xml"/>
              <Relationship
                Id="rIdFirstFooter"
                Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer"
                Target="footer2.xml"/>
            </Relationships>
            """

        let documentXML =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:document
              xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
              xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
              <w:body>
                <w:p>
                  <w:r>
                    <w:t>FIRST PAGE FURNITURE BODY</w:t>
                  </w:r>
                </w:p>
                <w:sectPr>
                  <w:headerReference
                    w:type="default"
                    r:id="rIdDefaultHeader"/>
                  <w:headerReference
                    w:type="first"
                    r:id="rIdFirstHeader"/>
                  <w:footerReference
                    w:type="default"
                    r:id="rIdDefaultFooter"/>
                  <w:footerReference
                    w:type="first"
                    r:id="rIdFirstFooter"/>
                  <w:titlePg/>
                  <w:pgSz
                    w:w="12240"
                    w:h="15840"/>
                  <w:pgMar
                    w:top="1440"
                    w:right="1440"
                    w:bottom="1440"
                    w:left="1440"
                    w:header="720"
                    w:footer="720"/>
                </w:sectPr>
              </w:body>
            </w:document>
            """

        let defaultHeader =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:hdr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
              <w:p>
                <w:r>
                  <w:t>DEFAULT HEADER</w:t>
                </w:r>
              </w:p>
            </w:hdr>
            """

        let firstHeader =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:hdr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
              <w:p>
                <w:r>
                  <w:t>FIRST HEADER</w:t>
                </w:r>
              </w:p>
            </w:hdr>
            """

        let defaultFooter =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:ftr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
              <w:p>
                <w:r>
                  <w:t>DEFAULT FOOTER</w:t>
                </w:r>
              </w:p>
            </w:ftr>
            """

        let firstFooter =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:ftr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
              <w:p>
                <w:r>
                  <w:t>FIRST FOOTER</w:t>
                </w:r>
              </w:p>
            </w:ftr>
            """

        let source =
            ZipArchiveWriter.archive(
                [
                    ZipEntry(
                        path:
                            "[Content_Types].xml",
                        data:
                            Data(
                                contentTypes.utf8
                            )
                    ),
                    ZipEntry(
                        path:
                            "_rels/.rels",
                        data:
                            Data(
                                rootRelationships.utf8
                            )
                    ),
                    ZipEntry(
                        path:
                            "word/document.xml",
                        data:
                            Data(
                                documentXML.utf8
                            )
                    ),
                    ZipEntry(
                        path:
                            "word/_rels/document.xml.rels",
                        data:
                            Data(
                                documentRelationships.utf8
                            )
                    ),
                    ZipEntry(
                        path:
                            "word/header1.xml",
                        data:
                            Data(
                                defaultHeader.utf8
                            )
                    ),
                    ZipEntry(
                        path:
                            "word/header2.xml",
                        data:
                            Data(
                                firstHeader.utf8
                            )
                    ),
                    ZipEntry(
                        path:
                            "word/footer1.xml",
                        data:
                            Data(
                                defaultFooter.utf8
                            )
                    ),
                    ZipEntry(
                        path:
                            "word/footer2.xml",
                        data:
                            Data(
                                firstFooter.utf8
                            )
                    ),
                ]
            )

        func assertFurniture(
            _ data: Data,
            file: StaticString = #filePath,
            line: UInt = #line
        ) throws {
            let parts =
                Dictionary(
                    uniqueKeysWithValues:
                        try DOCXPackage.entries(
                            in:
                                data
                        )
                        .map {
                            (
                                $0.path,
                                $0.data
                            )
                        }
                )

            let document =
                try DOCXPackage.xml(
                    XCTUnwrap(
                        parts[
                            "word/document.xml"
                        ],
                        file:
                            file,
                        line:
                            line
                    )
                )

            let relationships =
                try DOCXPackage.xml(
                    XCTUnwrap(
                        parts[
                            "word/_rels/document.xml.rels"
                        ],
                        file:
                            file,
                        line:
                            line
                    )
                )

            XCTAssertEqual(
                try document.nodes(
                    forXPath:
                        "//*[local-name()='sectPr']/*[local-name()='titlePg']"
                )
                .count,
                1,
                "Word first-page furniture requires w:titlePg.",
                file:
                    file,
                line:
                    line
            )

            func referencedPart(
                element:
                    String,
                type:
                    String
            ) throws -> Data {
                let references =
                    try document.nodes(
                        forXPath:
                            "//*[local-name()='sectPr']/*[local-name()='\(element)' and @*[local-name()='type']='\(type)']"
                    )

                XCTAssertEqual(
                    references.count,
                    1,
                    file:
                        file,
                    line:
                        line
                )

                let reference =
                    try XCTUnwrap(
                        references.first
                            as? XMLElement,
                        file:
                            file,
                        line:
                            line
                    )

                let relationshipID =
                    try XCTUnwrap(
                        reference
                            .attributes?
                            .first {
                                $0.localName
                                    == "id"
                            }?
                            .stringValue,
                        file:
                            file,
                        line:
                            line
                    )

                let relationship =
                    try XCTUnwrap(
                        try relationships.nodes(
                            forXPath:
                                "//*[local-name()='Relationship']"
                        )
                        .compactMap {
                            $0 as? XMLElement
                        }
                        .first {
                            $0.attribute(
                                forName:
                                    "Id"
                            )?
                            .stringValue
                                == relationshipID
                        },
                        file:
                            file,
                        line:
                            line
                    )

                let rawTarget =
                    try XCTUnwrap(
                        relationship.attribute(
                            forName:
                                "Target"
                        )?
                        .stringValue,
                        file:
                            file,
                        line:
                            line
                    )

                let decodedTarget =
                    rawTarget.removingPercentEncoding
                    ?? rawTarget

                let partPath:
                    String

                if decodedTarget.hasPrefix(
                    "/"
                ) {
                    partPath =
                        String(
                            decodedTarget.dropFirst()
                        )
                } else if decodedTarget.hasPrefix(
                    "word/"
                ) {
                    partPath =
                        decodedTarget
                } else {
                    partPath =
                        "word/"
                        + decodedTarget
                }

                return try XCTUnwrap(
                    parts[
                        partPath
                    ],
                    "Missing related Word part \(partPath)",
                    file:
                        file,
                    line:
                        line
                )
            }

            func partText(
                _ data: Data
            ) throws -> String {
                let xml =
                    try DOCXPackage.xml(
                        data
                    )

                return xml
                    .rootElement()?
                    .stringValue
                    ?? ""
            }

            XCTAssertTrue(
                try partText(
                    referencedPart(
                        element:
                            "headerReference",
                        type:
                            "default"
                    )
                )
                .contains(
                    "DEFAULT HEADER"
                ),
                file:
                    file,
                line:
                    line
            )

            XCTAssertTrue(
                try partText(
                    referencedPart(
                        element:
                            "headerReference",
                        type:
                            "first"
                    )
                )
                .contains(
                    "FIRST HEADER"
                ),
                file:
                    file,
                line:
                    line
            )

            XCTAssertTrue(
                try partText(
                    referencedPart(
                        element:
                            "footerReference",
                        type:
                            "default"
                    )
                )
                .contains(
                    "DEFAULT FOOTER"
                ),
                file:
                    file,
                line:
                    line
            )

            XCTAssertTrue(
                try partText(
                    referencedPart(
                        element:
                            "footerReference",
                        type:
                            "first"
                    )
                )
                .contains(
                    "FIRST FOOTER"
                ),
                file:
                    file,
                line:
                    line
            )
        }

        let imported =
            try DOCXImporter.importedDocument(
                from:
                    source
            )

        XCTAssertEqual(
            imported.sections.count,
            1
        )

        XCTAssertTrue(
            imported.text.string.contains(
                "FIRST PAGE FURNITURE BODY"
            )
        )

        let firstExport =
            try DOCXExporter.data(
                from:
                    imported.text,
                title:
                    "Independent First Page Furniture",
                settings:
                    imported.page,
                sections:
                    imported.sections
            )

        try assertFurniture(
            firstExport
        )

        let reopened =
            try DOCXImporter.importedDocument(
                from:
                    firstExport
            )

        XCTAssertEqual(
            reopened.sections.count,
            1
        )

        let secondExport =
            try DOCXExporter.data(
                from:
                    reopened.text,
                title:
                    "Independent First Page Furniture Twice",
                settings:
                    reopened.page,
                sections:
                    reopened.sections
            )

        try assertFurniture(
            secondExport
        )
    }
}

// MARK: - Independent Word header/footer inheritance compatibility

extension DOCXHeaderFooterTests {
    func testIndependentWordHeaderFooterInheritanceAcrossSections()
        throws
    {
        let contentTypes =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
              <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
              <Default Extension="xml" ContentType="application/xml"/>
              <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
              <Override PartName="/word/header1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/>
              <Override PartName="/word/header3.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/>
              <Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>
            </Types>
            """

        let rootRelationships =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
              <Relationship
                Id="rId1"
                Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument"
                Target="word/document.xml"/>
            </Relationships>
            """

        let documentRelationships =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
              <Relationship
                Id="rIdHeaderOne"
                Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/header"
                Target="header1.xml"/>
              <Relationship
                Id="rIdHeaderThree"
                Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/header"
                Target="header3.xml"/>
              <Relationship
                Id="rIdFooterOne"
                Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer"
                Target="footer1.xml"/>
            </Relationships>
            """

        let documentXML =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:document
              xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
              xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
              <w:body>
                <w:p>
                  <w:pPr>
                    <w:sectPr>
                      <w:type w:val="nextPage"/>
                      <w:headerReference
                        w:type="default"
                        r:id="rIdHeaderOne"/>
                      <w:footerReference
                        w:type="default"
                        r:id="rIdFooterOne"/>
                      <w:pgSz
                        w:w="12240"
                        w:h="15840"/>
                      <w:pgMar
                        w:top="1440"
                        w:right="1440"
                        w:bottom="1440"
                        w:left="1440"/>
                    </w:sectPr>
                  </w:pPr>
                  <w:r>
                    <w:t>SECTION ONE</w:t>
                  </w:r>
                </w:p>

                <w:p>
                  <w:pPr>
                    <w:sectPr>
                      <w:type w:val="nextPage"/>
                      <w:pgSz
                        w:w="12240"
                        w:h="15840"/>
                      <w:pgMar
                        w:top="1440"
                        w:right="1440"
                        w:bottom="1440"
                        w:left="1440"/>
                    </w:sectPr>
                  </w:pPr>
                  <w:r>
                    <w:t>SECTION TWO</w:t>
                  </w:r>
                </w:p>

                <w:p>
                  <w:r>
                    <w:t>SECTION THREE</w:t>
                  </w:r>
                </w:p>

                <w:sectPr>
                  <w:headerReference
                    w:type="default"
                    r:id="rIdHeaderThree"/>
                  <w:pgSz
                    w:w="12240"
                    w:h="15840"/>
                  <w:pgMar
                    w:top="1440"
                    w:right="1440"
                    w:bottom="1440"
                    w:left="1440"/>
                </w:sectPr>
              </w:body>
            </w:document>
            """

        let headerOne =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:hdr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
              <w:p>
                <w:r>
                  <w:t>HEADER ONE</w:t>
                </w:r>
              </w:p>
            </w:hdr>
            """

        let headerThree =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:hdr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
              <w:p>
                <w:r>
                  <w:t>HEADER THREE</w:t>
                </w:r>
              </w:p>
            </w:hdr>
            """

        let footerOne =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:ftr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
              <w:p>
                <w:r>
                  <w:t>FOOTER ONE</w:t>
                </w:r>
              </w:p>
            </w:ftr>
            """

        let source =
            ZipArchiveWriter.archive(
                [
                    ZipEntry(
                        path:
                            "[Content_Types].xml",
                        data:
                            Data(
                                contentTypes.utf8
                            )
                    ),
                    ZipEntry(
                        path:
                            "_rels/.rels",
                        data:
                            Data(
                                rootRelationships.utf8
                            )
                    ),
                    ZipEntry(
                        path:
                            "word/document.xml",
                        data:
                            Data(
                                documentXML.utf8
                            )
                    ),
                    ZipEntry(
                        path:
                            "word/_rels/document.xml.rels",
                        data:
                            Data(
                                documentRelationships.utf8
                            )
                    ),
                    ZipEntry(
                        path:
                            "word/header1.xml",
                        data:
                            Data(
                                headerOne.utf8
                            )
                    ),
                    ZipEntry(
                        path:
                            "word/header3.xml",
                        data:
                            Data(
                                headerThree.utf8
                            )
                    ),
                    ZipEntry(
                        path:
                            "word/footer1.xml",
                        data:
                            Data(
                                footerOne.utf8
                            )
                    ),
                ]
            )

        func assertSemantics(
            _ imported: DOCXImporter.ImportedDocument,
            file: StaticString = #filePath,
            line: UInt = #line
        ) {
            XCTAssertEqual(
                imported.sections.count,
                3,
                file:
                    file,
                line:
                    line
            )

            let sectionTwo =
                (
                    imported.text.string
                    as NSString
                )
                .range(
                    of:
                        "SECTION TWO"
                )

            let sectionThree =
                (
                    imported.text.string
                    as NSString
                )
                .range(
                    of:
                        "SECTION THREE"
                )

            XCTAssertNotEqual(
                sectionTwo.location,
                NSNotFound,
                file:
                    file,
                line:
                    line
            )

            XCTAssertNotEqual(
                sectionThree.location,
                NSNotFound,
                file:
                    file,
                line:
                    line
            )

            XCTAssertEqual(
                imported.sections.map(
                    \.location
                ),
                [
                    0,
                    sectionTwo.location,
                    sectionThree.location
                ],
                file:
                    file,
                line:
                    line
            )

            let first =
                imported.sections[0].page

            let second =
                imported.sections[1].page

            let third =
                imported.sections[2].page

            XCTAssertTrue(
                first.effectiveHeaderText.contains(
                    "HEADER ONE"
                ),
                file:
                    file,
                line:
                    line
            )

            XCTAssertTrue(
                first.footerText.contains(
                    "FOOTER ONE"
                ),
                file:
                    file,
                line:
                    line
            )

            XCTAssertTrue(
                second.effectiveHeaderText.contains(
                    "HEADER ONE"
                ),
                "Missing later default headerReference must inherit the previous section header.",
                file:
                    file,
                line:
                    line
            )

            XCTAssertTrue(
                second.footerText.contains(
                    "FOOTER ONE"
                ),
                "Missing later default footerReference must inherit the previous section footer.",
                file:
                    file,
                line:
                    line
            )

            XCTAssertTrue(
                third.effectiveHeaderText.contains(
                    "HEADER THREE"
                ),
                "Explicit later headerReference must replace inherited header content.",
                file:
                    file,
                line:
                    line
            )

            XCTAssertTrue(
                third.footerText.contains(
                    "FOOTER ONE"
                ),
                "Missing later footerReference must continue the inherited footer chain.",
                file:
                    file,
                line:
                    line
            )
        }

        let imported =
            try DOCXImporter.importedDocument(
                from:
                    source
            )

        assertSemantics(
            imported
        )

        let firstExport =
            try DOCXExporter.data(
                from:
                    imported.text,
                title:
                    "Independent Word Header Footer Inheritance",
                settings:
                    imported.page,
                sections:
                    imported.sections
            )

        let reopened =
            try DOCXImporter.importedDocument(
                from:
                    firstExport
            )

        assertSemantics(
            reopened
        )

        let secondExport =
            try DOCXExporter.data(
                from:
                    reopened.text,
                title:
                    "Independent Word Header Footer Inheritance Twice",
                settings:
                    reopened.page,
                sections:
                    reopened.sections
            )

        let reopenedTwice =
            try DOCXImporter.importedDocument(
                from:
                    secondExport
            )

        assertSemantics(
            reopenedTwice
        )
    }
}

// MARK: - Independent Word even/first inheritance compatibility

extension DOCXHeaderFooterTests {
    func testIndependentWordEvenAndFirstHeaderFooterInheritanceAcrossSections()
        throws
    {
        let contentTypes =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
              <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
              <Default Extension="xml" ContentType="application/xml"/>
              <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
              <Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/>
              <Override PartName="/word/header1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/>
              <Override PartName="/word/header2.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/>
              <Override PartName="/word/header3.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/>
              <Override PartName="/word/header4.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/>
              <Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>
              <Override PartName="/word/footer2.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>
              <Override PartName="/word/footer3.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>
              <Override PartName="/word/footer4.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>
            </Types>
            """

        let rootRelationships =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
              <Relationship
                Id="rId1"
                Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument"
                Target="word/document.xml"/>
            </Relationships>
            """

        let documentRelationships =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
              <Relationship
                Id="rIdDefaultHeaderOne"
                Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/header"
                Target="header1.xml"/>
              <Relationship
                Id="rIdEvenHeaderOne"
                Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/header"
                Target="header2.xml"/>
              <Relationship
                Id="rIdFirstHeaderOne"
                Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/header"
                Target="header3.xml"/>
              <Relationship
                Id="rIdEvenHeaderThree"
                Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/header"
                Target="header4.xml"/>
              <Relationship
                Id="rIdDefaultFooterOne"
                Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer"
                Target="footer1.xml"/>
              <Relationship
                Id="rIdEvenFooterOne"
                Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer"
                Target="footer2.xml"/>
              <Relationship
                Id="rIdFirstFooterOne"
                Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer"
                Target="footer3.xml"/>
              <Relationship
                Id="rIdFirstFooterThree"
                Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer"
                Target="footer4.xml"/>
              <Relationship
                Id="rIdSettings"
                Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings"
                Target="settings.xml"/>
            </Relationships>
            """

        let documentXML =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:document
              xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
              xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
              <w:body>
                <w:p>
                  <w:pPr>
                    <w:sectPr>
                      <w:type w:val="nextPage"/>
                      <w:headerReference w:type="default" r:id="rIdDefaultHeaderOne"/>
                      <w:headerReference w:type="even" r:id="rIdEvenHeaderOne"/>
                      <w:headerReference w:type="first" r:id="rIdFirstHeaderOne"/>
                      <w:footerReference w:type="default" r:id="rIdDefaultFooterOne"/>
                      <w:footerReference w:type="even" r:id="rIdEvenFooterOne"/>
                      <w:footerReference w:type="first" r:id="rIdFirstFooterOne"/>
                      <w:titlePg/>
                      <w:pgSz w:w="12240" w:h="15840"/>
                      <w:pgMar
                        w:top="1440"
                        w:right="1440"
                        w:bottom="1440"
                        w:left="1440"
                        w:header="720"
                        w:footer="720"/>
                    </w:sectPr>
                  </w:pPr>
                  <w:r>
                    <w:t>ALL TYPES SECTION ONE</w:t>
                  </w:r>
                </w:p>

                <w:p>
                  <w:pPr>
                    <w:sectPr>
                      <w:type w:val="nextPage"/>
                      <w:titlePg/>
                      <w:pgSz w:w="12240" w:h="15840"/>
                      <w:pgMar
                        w:top="1440"
                        w:right="1440"
                        w:bottom="1440"
                        w:left="1440"
                        w:header="720"
                        w:footer="720"/>
                    </w:sectPr>
                  </w:pPr>
                  <w:r>
                    <w:t>ALL TYPES SECTION TWO</w:t>
                  </w:r>
                </w:p>

                <w:p>
                  <w:r>
                    <w:t>ALL TYPES SECTION THREE</w:t>
                  </w:r>
                </w:p>

                <w:sectPr>
                  <w:headerReference
                    w:type="even"
                    r:id="rIdEvenHeaderThree"/>
                  <w:footerReference
                    w:type="first"
                    r:id="rIdFirstFooterThree"/>
                  <w:titlePg/>
                  <w:pgSz w:w="12240" w:h="15840"/>
                  <w:pgMar
                    w:top="1440"
                    w:right="1440"
                    w:bottom="1440"
                    w:left="1440"
                    w:header="720"
                    w:footer="720"/>
                </w:sectPr>
              </w:body>
            </w:document>
            """

        func header(
            _ text: String
        ) -> Data {
            Data(
                """
                <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
                <w:hdr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
                  <w:p>
                    <w:pPr>
                      <w:jc w:val="left"/>
                    </w:pPr>
                    <w:r>
                      <w:t>\(text)</w:t>
                    </w:r>
                  </w:p>
                </w:hdr>
                """.utf8
            )
        }

        func footer(
            _ text: String
        ) -> Data {
            Data(
                """
                <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
                <w:ftr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
                  <w:p>
                    <w:pPr>
                      <w:jc w:val="left"/>
                    </w:pPr>
                    <w:r>
                      <w:t>\(text)</w:t>
                    </w:r>
                  </w:p>
                </w:ftr>
                """.utf8
            )
        }

        let settingsXML =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
              <w:evenAndOddHeaders/>
            </w:settings>
            """

        let source =
            ZipArchiveWriter.archive(
                [
                    ZipEntry(
                        path: "[Content_Types].xml",
                        data: Data(contentTypes.utf8)
                    ),
                    ZipEntry(
                        path: "_rels/.rels",
                        data: Data(rootRelationships.utf8)
                    ),
                    ZipEntry(
                        path: "word/document.xml",
                        data: Data(documentXML.utf8)
                    ),
                    ZipEntry(
                        path: "word/_rels/document.xml.rels",
                        data: Data(documentRelationships.utf8)
                    ),
                    ZipEntry(
                        path: "word/settings.xml",
                        data: Data(settingsXML.utf8)
                    ),
                    ZipEntry(
                        path: "word/header1.xml",
                        data: header("SECTION ONE DEFAULT HEADER")
                    ),
                    ZipEntry(
                        path: "word/header2.xml",
                        data: header("SECTION ONE EVEN HEADER")
                    ),
                    ZipEntry(
                        path: "word/header3.xml",
                        data: header("SECTION ONE FIRST HEADER")
                    ),
                    ZipEntry(
                        path: "word/header4.xml",
                        data: header("SECTION THREE EVEN HEADER")
                    ),
                    ZipEntry(
                        path: "word/footer1.xml",
                        data: footer("SECTION ONE DEFAULT FOOTER")
                    ),
                    ZipEntry(
                        path: "word/footer2.xml",
                        data: footer("SECTION ONE EVEN FOOTER")
                    ),
                    ZipEntry(
                        path: "word/footer3.xml",
                        data: footer("SECTION ONE FIRST FOOTER")
                    ),
                    ZipEntry(
                        path: "word/footer4.xml",
                        data: footer("SECTION THREE FIRST FOOTER")
                    ),
                ]
            )

        func assertSemantics(
            _ imported: DOCXImporter.ImportedDocument,
            file: StaticString = #filePath,
            line: UInt = #line
        ) {
            XCTAssertEqual(
                imported.sections.count,
                3,
                file: file,
                line: line
            )

            let secondLocation =
                (
                    imported.text.string
                    as NSString
                )
                .range(
                    of: "ALL TYPES SECTION TWO"
                )
                .location

            let thirdLocation =
                (
                    imported.text.string
                    as NSString
                )
                .range(
                    of: "ALL TYPES SECTION THREE"
                )
                .location

            XCTAssertNotEqual(
                secondLocation,
                NSNotFound,
                file: file,
                line: line
            )

            XCTAssertNotEqual(
                thirdLocation,
                NSNotFound,
                file: file,
                line: line
            )

            XCTAssertEqual(
                imported.sections.map(\.location),
                [
                    0,
                    secondLocation,
                    thirdLocation
                ],
                file: file,
                line: line
            )

            let first =
                imported.sections[0].page

            let second =
                imported.sections[1].page

            let third =
                imported.sections[2].page

            XCTAssertTrue(
                first.effectiveHeaderText.contains(
                    "SECTION ONE DEFAULT HEADER"
                ),
                file: file,
                line: line
            )

            XCTAssertTrue(
                first.effectiveEvenPageHeaderText.contains(
                    "SECTION ONE EVEN HEADER"
                ),
                file: file,
                line: line
            )

            XCTAssertTrue(
                first.effectiveFirstPageHeaderText.contains(
                    "SECTION ONE FIRST HEADER"
                ),
                file: file,
                line: line
            )

            XCTAssertTrue(
                first.footerText.contains(
                    "SECTION ONE DEFAULT FOOTER"
                ),
                file: file,
                line: line
            )

            XCTAssertTrue(
                first.effectiveEvenPageFooterText.contains(
                    "SECTION ONE EVEN FOOTER"
                ),
                file: file,
                line: line
            )

            XCTAssertTrue(
                first.effectiveFirstPageFooterText.contains(
                    "SECTION ONE FIRST FOOTER"
                ),
                file: file,
                line: line
            )

            XCTAssertTrue(
                second.usesDifferentOddEvenHeaderFooter,
                file: file,
                line: line
            )

            XCTAssertTrue(
                second.hasDistinctFirstPageHeaderFooter,
                file: file,
                line: line
            )

            XCTAssertTrue(
                second.effectiveHeaderText.contains(
                    "SECTION ONE DEFAULT HEADER"
                ),
                file: file,
                line: line
            )

            XCTAssertTrue(
                second.effectiveEvenPageHeaderText.contains(
                    "SECTION ONE EVEN HEADER"
                ),
                "Missing even headerReference must inherit.",
                file: file,
                line: line
            )

            XCTAssertTrue(
                second.effectiveFirstPageHeaderText.contains(
                    "SECTION ONE FIRST HEADER"
                ),
                "Missing first headerReference must inherit.",
                file: file,
                line: line
            )

            XCTAssertTrue(
                second.footerText.contains(
                    "SECTION ONE DEFAULT FOOTER"
                ),
                file: file,
                line: line
            )

            XCTAssertTrue(
                second.effectiveEvenPageFooterText.contains(
                    "SECTION ONE EVEN FOOTER"
                ),
                "Missing even footerReference must inherit.",
                file: file,
                line: line
            )

            XCTAssertTrue(
                second.effectiveFirstPageFooterText.contains(
                    "SECTION ONE FIRST FOOTER"
                ),
                "Missing first footerReference must inherit.",
                file: file,
                line: line
            )

            XCTAssertTrue(
                third.effectiveHeaderText.contains(
                    "SECTION ONE DEFAULT HEADER"
                ),
                file: file,
                line: line
            )

            XCTAssertTrue(
                third.effectiveEvenPageHeaderText.contains(
                    "SECTION THREE EVEN HEADER"
                ),
                "Explicit even header must replace inherited even header.",
                file: file,
                line: line
            )

            XCTAssertTrue(
                third.effectiveFirstPageHeaderText.contains(
                    "SECTION ONE FIRST HEADER"
                ),
                file: file,
                line: line
            )

            XCTAssertTrue(
                third.footerText.contains(
                    "SECTION ONE DEFAULT FOOTER"
                ),
                file: file,
                line: line
            )

            XCTAssertTrue(
                third.effectiveEvenPageFooterText.contains(
                    "SECTION ONE EVEN FOOTER"
                ),
                file: file,
                line: line
            )

            XCTAssertTrue(
                third.effectiveFirstPageFooterText.contains(
                    "SECTION THREE FIRST FOOTER"
                ),
                "Explicit first footer must replace inherited first footer.",
                file: file,
                line: line
            )
        }

        let imported =
            try DOCXImporter.importedDocument(
                from: source
            )

        assertSemantics(
            imported
        )

        let firstExport =
            try DOCXExporter.data(
                from: imported.text,
                title:
                    "Independent All Type Furniture Inheritance",
                settings: imported.page,
                sections: imported.sections
            )

        let reopened =
            try DOCXImporter.importedDocument(
                from: firstExport
            )

        assertSemantics(
            reopened
        )

        let secondExport =
            try DOCXExporter.data(
                from: reopened.text,
                title:
                    "Independent All Type Furniture Inheritance Twice",
                settings: reopened.page,
                sections: reopened.sections
            )

        let reopenedTwice =
            try DOCXImporter.importedDocument(
                from: secondExport
            )

        assertSemantics(
            reopenedTwice
        )
    }
}



// MARK: - Independent Word header/footer edge-distance compatibility

extension DOCXHeaderFooterTests {
    func testIndependentWordSectionHeaderFooterDistancesRoundTrip()
        throws
    {
        let contentTypes =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
              <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
              <Default Extension="xml" ContentType="application/xml"/>
              <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
            </Types>
            """

        let rootRelationships =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
              <Relationship
                Id="rId1"
                Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument"
                Target="word/document.xml"/>
            </Relationships>
            """

        let documentXML =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:document
              xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
              <w:body>
                <w:p>
                  <w:pPr>
                    <w:sectPr>
                      <w:type w:val="nextPage"/>
                      <w:pgSz
                        w:w="12240"
                        w:h="15840"/>
                      <w:pgMar
                        w:top="1440"
                        w:right="1440"
                        w:bottom="1440"
                        w:left="1440"
                        w:header="720"
                        w:footer="720"/>
                    </w:sectPr>
                  </w:pPr>
                  <w:r>
                    <w:t>FIRST DISTANCE SECTION</w:t>
                  </w:r>
                </w:p>

                <w:p>
                  <w:r>
                    <w:t>SECOND DISTANCE SECTION</w:t>
                  </w:r>
                </w:p>

                <w:sectPr>
                  <w:pgSz
                    w:w="12240"
                    w:h="15840"/>
                  <w:pgMar
                    w:top="1440"
                    w:right="1440"
                    w:bottom="1440"
                    w:left="1440"
                    w:header="360"
                    w:footer="1080"/>
                </w:sectPr>
              </w:body>
            </w:document>
            """

        let source =
            ZipArchiveWriter.archive(
                [
                    ZipEntry(
                        path:
                            "[Content_Types].xml",
                        data:
                            Data(
                                contentTypes.utf8
                            )
                    ),
                    ZipEntry(
                        path:
                            "_rels/.rels",
                        data:
                            Data(
                                rootRelationships.utf8
                            )
                    ),
                    ZipEntry(
                        path:
                            "word/document.xml",
                        data:
                            Data(
                                documentXML.utf8
                            )
                    ),
                ]
            )

        func assertImportedDistances(
            _ imported:
                DOCXImporter.ImportedDocument,
            file: StaticString = #filePath,
            line: UInt = #line
        ) {
            XCTAssertEqual(
                imported.sections.count,
                2,
                file:
                    file,
                line:
                    line
            )

            let secondRange =
                (
                    imported.text.string
                    as NSString
                )
                .range(
                    of:
                        "SECOND DISTANCE SECTION"
                )

            XCTAssertNotEqual(
                secondRange.location,
                NSNotFound,
                file:
                    file,
                line:
                    line
            )

            XCTAssertEqual(
                imported.sections.map(
                    \.location
                ),
                [
                    0,
                    secondRange.location
                ],
                file:
                    file,
                line:
                    line
            )

            let first =
                imported.sections[0].page

            let second =
                imported.sections[1].page

            XCTAssertEqual(
                first.headerDistance,
                36,
                file:
                    file,
                line:
                    line
            )

            XCTAssertEqual(
                first.footerDistance,
                36,
                file:
                    file,
                line:
                    line
            )

            XCTAssertEqual(
                second.headerDistance,
                18,
                file:
                    file,
                line:
                    line
            )

            XCTAssertEqual(
                second.footerDistance,
                54,
                file:
                    file,
                line:
                    line
            )

            XCTAssertEqual(
                first.effectiveHeaderDistance,
                36,
                file:
                    file,
                line:
                    line
            )

            XCTAssertEqual(
                first.effectiveFooterDistance,
                36,
                file:
                    file,
                line:
                    line
            )

            XCTAssertEqual(
                second.effectiveHeaderDistance,
                18,
                file:
                    file,
                line:
                    line
            )

            XCTAssertEqual(
                second.effectiveFooterDistance,
                54,
                file:
                    file,
                line:
                    line
            )

            XCTAssertEqual(
                first.topMargin,
                72,
                file:
                    file,
                line:
                    line
            )

            XCTAssertEqual(
                second.topMargin,
                72,
                file:
                    file,
                line:
                    line
            )

            XCTAssertEqual(
                first.bottomMargin,
                72,
                file:
                    file,
                line:
                    line
            )

            XCTAssertEqual(
                second.bottomMargin,
                72,
                file:
                    file,
                line:
                    line
            )
        }

        func assertExportedDistances(
            _ data: Data,
            file: StaticString = #filePath,
            line: UInt = #line
        ) throws {
            let entries =
                try DOCXPackage.entries(
                    in:
                        data
                )

            let documentPart =
                try XCTUnwrap(
                    entries.first {
                        $0.path
                            == "word/document.xml"
                    },
                    file:
                        file,
                    line:
                        line
                )

            let xml =
                try DOCXPackage.xml(
                    documentPart.data
                )

            let sectionNodes =
                try xml.nodes(
                    forXPath:
                        "//*[local-name()='sectPr']"
                )

            XCTAssertEqual(
                sectionNodes.count,
                2,
                file:
                    file,
                line:
                    line
            )

            XCTAssertEqual(
                try sectionNodes[0]
                    .nodes(
                        forXPath:
                            "./*[local-name()='pgMar' and @*[local-name()='top']='1440' and @*[local-name()='bottom']='1440' and @*[local-name()='header']='720' and @*[local-name()='footer']='720']"
                    )
                    .count,
                1,
                file:
                    file,
                line:
                    line
            )

            XCTAssertEqual(
                try sectionNodes[1]
                    .nodes(
                        forXPath:
                            "./*[local-name()='pgMar' and @*[local-name()='top']='1440' and @*[local-name()='bottom']='1440' and @*[local-name()='header']='360' and @*[local-name()='footer']='1080']"
                    )
                    .count,
                1,
                file:
                    file,
                line:
                    line
            )
        }

        let imported =
            try DOCXImporter.importedDocument(
                from:
                    source
            )

        assertImportedDistances(
            imported
        )

        let firstExport =
            try DOCXExporter.data(
                from:
                    imported.text,
                title:
                    "Independent Header Footer Distances",
                settings:
                    imported.page,
                sections:
                    imported.sections
            )

        try assertExportedDistances(
            firstExport
        )

        let reopened =
            try DOCXImporter.importedDocument(
                from:
                    firstExport
            )

        assertImportedDistances(
            reopened
        )

        let secondExport =
            try DOCXExporter.data(
                from:
                    reopened.text,
                title:
                    "Independent Header Footer Distances Twice",
                settings:
                    reopened.page,
                sections:
                    reopened.sections
            )

        try assertExportedDistances(
            secondExport
        )
    }
}

// MARK: - Independent Word gutter / mirror-margin compatibility

extension DOCXHeaderFooterTests {
    func testIndependentWordGutterAndMirrorMarginsRoundTrip()
        throws
    {
        let contentTypes =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
              <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
              <Default Extension="xml" ContentType="application/xml"/>
              <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
              <Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/>
            </Types>
            """

        let rootRelationships =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
              <Relationship
                Id="rId1"
                Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument"
                Target="word/document.xml"/>
            </Relationships>
            """

        let documentRelationships =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
              <Relationship
                Id="rIdSettings"
                Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings"
                Target="settings.xml"/>
            </Relationships>
            """

        let documentXML =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:document
              xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
              <w:body>
                <w:p>
                  <w:pPr>
                    <w:sectPr>
                      <w:type w:val="nextPage"/>
                      <w:pgSz
                        w:w="12240"
                        w:h="15840"/>
                      <w:pgMar
                        w:top="1440"
                        w:right="720"
                        w:bottom="1440"
                        w:left="1440"
                        w:gutter="360"/>
                    </w:sectPr>
                  </w:pPr>
                  <w:r>
                    <w:t>GUTTER SECTION ONE</w:t>
                  </w:r>
                </w:p>

                <w:p>
                  <w:r>
                    <w:t>GUTTER SECTION TWO</w:t>
                  </w:r>
                </w:p>

                <w:sectPr>
                  <w:pgSz
                    w:w="12240"
                    w:h="15840"/>
                  <w:pgMar
                    w:top="1440"
                    w:right="900"
                    w:bottom="1440"
                    w:left="1800"
                    w:gutter="540"/>
                </w:sectPr>
              </w:body>
            </w:document>
            """

        let settingsXML =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
              <w:mirrorMargins/>
            </w:settings>
            """

        let source =
            ZipArchiveWriter.archive(
                [
                    ZipEntry(
                        path:
                            "[Content_Types].xml",
                        data:
                            Data(
                                contentTypes.utf8
                            )
                    ),
                    ZipEntry(
                        path:
                            "_rels/.rels",
                        data:
                            Data(
                                rootRelationships.utf8
                            )
                    ),
                    ZipEntry(
                        path:
                            "word/document.xml",
                        data:
                            Data(
                                documentXML.utf8
                            )
                    ),
                    ZipEntry(
                        path:
                            "word/_rels/document.xml.rels",
                        data:
                            Data(
                                documentRelationships.utf8
                            )
                    ),
                    ZipEntry(
                        path:
                            "word/settings.xml",
                        data:
                            Data(
                                settingsXML.utf8
                            )
                    ),
                ]
            )

        func assertImported(
            _ imported:
                DOCXImporter.ImportedDocument,
            file: StaticString = #filePath,
            line: UInt = #line
        ) throws {
            XCTAssertEqual(
                imported.sections.count,
                2,
                file:
                    file,
                line:
                    line
            )

            let secondRange =
                (
                    imported.text.string
                    as NSString
                )
                .range(
                    of:
                        "GUTTER SECTION TWO"
                )

            XCTAssertNotEqual(
                secondRange.location,
                NSNotFound,
                file:
                    file,
                line:
                    line
            )

            XCTAssertEqual(
                imported.sections[1].location,
                secondRange.location,
                file:
                    file,
                line:
                    line
            )

            let first =
                imported.sections[0].page

            let second =
                imported.sections[1].page

            XCTAssertEqual(
                first.effectiveGutter,
                18,
                accuracy:
                    0.001,
                file:
                    file,
                line:
                    line
            )

            XCTAssertEqual(
                second.effectiveGutter,
                27,
                accuracy:
                    0.001,
                file:
                    file,
                line:
                    line
            )

            XCTAssertTrue(
                first.usesMirrorMargins,
                file:
                    file,
                line:
                    line
            )

            XCTAssertTrue(
                second.usesMirrorMargins,
                file:
                    file,
                line:
                    line
            )

            let oddGeometry =
                try PageGeometry(
                    first
                )
                .resolvingPhysicalPage(
                    1
                )

            let evenGeometry =
                try PageGeometry(
                    second
                )
                .resolvingPhysicalPage(
                    2
                )

            XCTAssertEqual(
                oddGeometry.contentOrigin.x,
                90,
                accuracy:
                    0.001,
                file:
                    file,
                line:
                    line
            )

            XCTAssertEqual(
                oddGeometry.contentSize.width,
                486,
                accuracy:
                    0.001,
                file:
                    file,
                line:
                    line
            )

            XCTAssertEqual(
                evenGeometry.contentOrigin.x,
                45,
                accuracy:
                    0.001,
                file:
                    file,
                line:
                    line
            )

            XCTAssertEqual(
                evenGeometry.contentSize.width,
                450,
                accuracy:
                    0.001,
                file:
                    file,
                line:
                    line
            )
        }

        func assertExported(
            _ data:
                Data,
            file: StaticString = #filePath,
            line: UInt = #line
        ) throws {
            let parts =
                Dictionary(
                    uniqueKeysWithValues:
                        try DOCXPackage.entries(
                            in:
                                data
                        )
                        .map {
                            (
                                $0.path,
                                $0.data
                            )
                        }
                )

            let document =
                try DOCXPackage.xml(
                    XCTUnwrap(
                        parts[
                            "word/document.xml"
                        ],
                        file:
                            file,
                        line:
                            line
                    )
                )

            let settings =
                try DOCXPackage.xml(
                    XCTUnwrap(
                        parts[
                            "word/settings.xml"
                        ],
                        file:
                            file,
                        line:
                            line
                    )
                )

            XCTAssertEqual(
                try settings.nodes(
                    forXPath:
                        "//*[local-name()='mirrorMargins']"
                )
                .count,
                1,
                file:
                    file,
                line:
                    line
            )

            let sections =
                try document.nodes(
                    forXPath:
                        "//*[local-name()='sectPr']"
                )

            XCTAssertEqual(
                sections.count,
                2,
                file:
                    file,
                line:
                    line
            )

            XCTAssertEqual(
                try sections[0]
                    .nodes(
                        forXPath:
                            "./*[local-name()='pgMar' and @*[local-name()='gutter']='360']"
                    )
                    .count,
                1,
                file:
                    file,
                line:
                    line
            )

            XCTAssertEqual(
                try sections[1]
                    .nodes(
                        forXPath:
                            "./*[local-name()='pgMar' and @*[local-name()='gutter']='540']"
                    )
                    .count,
                1,
                file:
                    file,
                line:
                    line
            )
        }

        let imported =
            try DOCXImporter.importedDocument(
                from:
                    source
            )

        try assertImported(
            imported
        )

        let firstExport =
            try DOCXExporter.data(
                from:
                    imported.text,
                title:
                    "Independent Word Mirror Margins",
                settings:
                    imported.page,
                sections:
                    imported.sections
            )

        try assertExported(
            firstExport
        )

        let reopened =
            try DOCXImporter.importedDocument(
                from:
                    firstExport
            )

        try assertImported(
            reopened
        )

        let secondExport =
            try DOCXExporter.data(
                from:
                    reopened.text,
                title:
                    "Independent Word Mirror Margins Twice",
                settings:
                    reopened.page,
                sections:
                    reopened.sections
            )

        try assertExported(
            secondExport
        )
    }
}



// MARK: - Independent Word gutter-at-top compatibility

extension DOCXHeaderFooterTests {
    func testIndependentWordGutterAtTopRoundTrip()
        throws
    {
        let contentTypes =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
              <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
              <Default Extension="xml" ContentType="application/xml"/>
              <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
              <Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/>
            </Types>
            """

        let rootRelationships =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
              <Relationship
                Id="rId1"
                Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument"
                Target="word/document.xml"/>
            </Relationships>
            """

        let documentRelationships =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
              <Relationship
                Id="rIdSettings"
                Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings"
                Target="settings.xml"/>
            </Relationships>
            """

        // Independent WordprocessingML:
        //
        // Letter page:
        // left  = 72 pt
        // right = 36 pt
        // top   = 54 pt
        // bottom = 45 pt
        // gutter = 18 pt
        //
        // w:gutterAtTop moves the 18 pt gutter from the binding side
        // to the top edge. Therefore:
        //
        // printable width  = 612 - 72 - 36 = 504 pt
        // printable height = 792 - 54 - 45 - 18 = 675 pt
        // content origin   = (72, 72)
        let documentXML =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:document
              xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
              <w:body>
                <w:p>
                  <w:r>
                    <w:t>GUTTER AT TOP BODY</w:t>
                  </w:r>
                </w:p>
                <w:sectPr>
                  <w:pgSz
                    w:w="12240"
                    w:h="15840"/>
                  <w:pgMar
                    w:top="1080"
                    w:right="720"
                    w:bottom="900"
                    w:left="1440"
                    w:gutter="360"/>
                </w:sectPr>
              </w:body>
            </w:document>
            """

        let settingsXML =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
              <w:gutterAtTop/>
            </w:settings>
            """

        let source =
            ZipArchiveWriter.archive(
                [
                    ZipEntry(
                        path:
                            "[Content_Types].xml",
                        data:
                            Data(
                                contentTypes.utf8
                            )
                    ),
                    ZipEntry(
                        path:
                            "_rels/.rels",
                        data:
                            Data(
                                rootRelationships.utf8
                            )
                    ),
                    ZipEntry(
                        path:
                            "word/document.xml",
                        data:
                            Data(
                                documentXML.utf8
                            )
                    ),
                    ZipEntry(
                        path:
                            "word/_rels/document.xml.rels",
                        data:
                            Data(
                                documentRelationships.utf8
                            )
                    ),
                    ZipEntry(
                        path:
                            "word/settings.xml",
                        data:
                            Data(
                                settingsXML.utf8
                            )
                    ),
                ]
            )

        func assertImported(
            _ imported:
                DOCXImporter.ImportedDocument,
            file: StaticString = #filePath,
            line: UInt = #line
        ) throws {
            XCTAssertEqual(
                imported.sections.count,
                1,
                file:
                    file,
                line:
                    line
            )

            let page =
                imported.sections[0].page

            XCTAssertEqual(
                page.effectiveGutter,
                18,
                accuracy:
                    0.001,
                file:
                    file,
                line:
                    line
            )

            XCTAssertTrue(
                page.usesGutterAtTop,
                file:
                    file,
                line:
                    line
            )

            let geometry =
                try PageGeometry(
                    page
                )

            XCTAssertEqual(
                geometry.contentOrigin.x,
                72,
                accuracy:
                    0.001,
                "Top gutter must not move the horizontal body origin.",
                file:
                    file,
                line:
                    line
            )

            XCTAssertEqual(
                geometry.contentOrigin.y,
                72,
                accuracy:
                    0.001,
                "Top gutter must extend the physical top writing margin.",
                file:
                    file,
                line:
                    line
            )

            XCTAssertEqual(
                geometry.contentSize.width,
                504,
                accuracy:
                    0.001,
                "Top gutter must not consume printable width.",
                file:
                    file,
                line:
                    line
            )

            XCTAssertEqual(
                geometry.contentSize.height,
                675,
                accuracy:
                    0.001,
                "Top gutter must consume printable height.",
                file:
                    file,
                line:
                    line
            )
        }

        func assertExported(
            _ data: Data,
            file: StaticString = #filePath,
            line: UInt = #line
        ) throws {
            let parts =
                Dictionary(
                    uniqueKeysWithValues:
                        try DOCXPackage.entries(
                            in:
                                data
                        )
                        .map {
                            (
                                $0.path,
                                $0.data
                            )
                        }
                )

            let document =
                try DOCXPackage.xml(
                    XCTUnwrap(
                        parts[
                            "word/document.xml"
                        ],
                        file:
                            file,
                        line:
                            line
                    )
                )

            let settings =
                try DOCXPackage.xml(
                    XCTUnwrap(
                        parts[
                            "word/settings.xml"
                        ],
                        file:
                            file,
                        line:
                            line
                    )
                )

            XCTAssertEqual(
                try settings.nodes(
                    forXPath:
                        "//*[local-name()='gutterAtTop']"
                )
                .count,
                1,
                file:
                    file,
                line:
                    line
            )

            XCTAssertEqual(
                try document.nodes(
                    forXPath:
                        "//*[local-name()='sectPr']/*[local-name()='pgMar' and @*[local-name()='gutter']='360']"
                )
                .count,
                1,
                file:
                    file,
                line:
                    line
            )
        }

        let imported =
            try DOCXImporter.importedDocument(
                from:
                    source
            )

        try assertImported(
            imported
        )

        let firstExport =
            try DOCXExporter.data(
                from:
                    imported.text,
                title:
                    "Independent Word Gutter At Top",
                settings:
                    imported.page,
                sections:
                    imported.sections
            )

        try assertExported(
            firstExport
        )

        let reopened =
            try DOCXImporter.importedDocument(
                from:
                    firstExport
            )

        try assertImported(
            reopened
        )

        let secondExport =
            try DOCXExporter.data(
                from:
                    reopened.text,
                title:
                    "Independent Word Gutter At Top Twice",
                settings:
                    reopened.page,
                sections:
                    reopened.sections
            )

        try assertExported(
            secondExport
        )
    }
}


// MARK: - Independent Word section vertical page alignment compatibility

extension DOCXHeaderFooterTests {
    func testIndependentWordVerticalPageAlignmentRoundTrip()
        throws
    {
        let contentTypes =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
              <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
              <Default Extension="xml" ContentType="application/xml"/>
              <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
            </Types>
            """

        let rootRelationships =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
              <Relationship
                Id="rId1"
                Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument"
                Target="word/document.xml"/>
            </Relationships>
            """

        let documentXML =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:document
              xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
              <w:body>
                <w:p>
                  <w:pPr>
                    <w:sectPr>
                      <w:type w:val="nextPage"/>
                      <w:vAlign w:val="top"/>
                      <w:pgSz w:w="12240" w:h="15840"/>
                      <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/>
                    </w:sectPr>
                  </w:pPr>
                  <w:r><w:t>VERTICAL TOP SECTION</w:t></w:r>
                </w:p>

                <w:p>
                  <w:pPr>
                    <w:sectPr>
                      <w:type w:val="nextPage"/>
                      <w:vAlign w:val="center"/>
                      <w:pgSz w:w="12240" w:h="15840"/>
                      <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/>
                    </w:sectPr>
                  </w:pPr>
                  <w:r><w:t>VERTICAL CENTER SECTION</w:t></w:r>
                </w:p>

                <w:p>
                  <w:r><w:t>VERTICAL BOTTOM SECTION</w:t></w:r>
                </w:p>

                <w:sectPr>
                  <w:vAlign w:val="bottom"/>
                  <w:pgSz w:w="12240" w:h="15840"/>
                  <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/>
                </w:sectPr>
              </w:body>
            </w:document>
            """

        let source =
            ZipArchiveWriter.archive(
                [
                    ZipEntry(
                        path:
                            "[Content_Types].xml",
                        data:
                            Data(
                                contentTypes.utf8
                            )
                    ),
                    ZipEntry(
                        path:
                            "_rels/.rels",
                        data:
                            Data(
                                rootRelationships.utf8
                            )
                    ),
                    ZipEntry(
                        path:
                            "word/document.xml",
                        data:
                            Data(
                                documentXML.utf8
                            )
                    ),
                ]
            )

        func assertImported(
            _ imported:
                DOCXImporter.ImportedDocument,
            file: StaticString = #filePath,
            line: UInt = #line
        ) {
            XCTAssertEqual(
                imported.sections.count,
                3,
                file:
                    file,
                line:
                    line
            )

            let centerLocation =
                (
                    imported.text.string
                    as NSString
                )
                .range(
                    of:
                        "VERTICAL CENTER SECTION"
                )
                .location

            let bottomLocation =
                (
                    imported.text.string
                    as NSString
                )
                .range(
                    of:
                        "VERTICAL BOTTOM SECTION"
                )
                .location

            XCTAssertNotEqual(
                centerLocation,
                NSNotFound,
                file:
                    file,
                line:
                    line
            )

            XCTAssertNotEqual(
                bottomLocation,
                NSNotFound,
                file:
                    file,
                line:
                    line
            )

            XCTAssertEqual(
                imported.sections.map(
                    \.location
                ),
                [
                    0,
                    centerLocation,
                    bottomLocation
                ],
                file:
                    file,
                line:
                    line
            )

            XCTAssertEqual(
                imported.sections[0]
                    .page
                    .effectiveVerticalPageAlignment,
                .top,
                file:
                    file,
                line:
                    line
            )

            XCTAssertEqual(
                imported.sections[1]
                    .page
                    .effectiveVerticalPageAlignment,
                .center,
                file:
                    file,
                line:
                    line
            )

            XCTAssertEqual(
                imported.sections[2]
                    .page
                    .effectiveVerticalPageAlignment,
                .bottom,
                file:
                    file,
                line:
                    line
            )
        }

        func assertExported(
            _ data: Data,
            file: StaticString = #filePath,
            line: UInt = #line
        ) throws {
            let parts =
                Dictionary(
                    uniqueKeysWithValues:
                        try DOCXPackage.entries(
                            in:
                                data
                        )
                        .map {
                            (
                                $0.path,
                                $0.data
                            )
                        }
                )

            let document =
                try DOCXPackage.xml(
                    XCTUnwrap(
                        parts[
                            "word/document.xml"
                        ],
                        file:
                            file,
                        line:
                            line
                    )
                )

            let sections =
                try document.nodes(
                    forXPath:
                        "//*[local-name()='sectPr']"
                )

            XCTAssertEqual(
                sections.count,
                3,
                file:
                    file,
                line:
                    line
            )

            for (
                index,
                expected
            ) in [
                "top",
                "center",
                "bottom"
            ]
            .enumerated() {

                XCTAssertEqual(
                    try sections[
                        index
                    ]
                    .nodes(
                        forXPath:
                            "./*[local-name()='vAlign' and @*[local-name()='val']='\(expected)']"
                    )
                    .count,
                    1,
                    file:
                        file,
                    line:
                        line
                )
            }
        }

        let imported =
            try DOCXImporter.importedDocument(
                from:
                    source
            )

        assertImported(
            imported
        )

        let firstExport =
            try DOCXExporter.data(
                from:
                    imported.text,
                title:
                    "Independent Word Vertical Page Alignment",
                settings:
                    imported.page,
                sections:
                    imported.sections
            )

        try assertExported(
            firstExport
        )

        let reopened =
            try DOCXImporter.importedDocument(
                from:
                    firstExport
            )

        assertImported(
            reopened
        )

        let secondExport =
            try DOCXExporter.data(
                from:
                    reopened.text,
                title:
                    "Independent Word Vertical Page Alignment Twice",
                settings:
                    reopened.page,
                sections:
                    reopened.sections
            )

        try assertExported(
            secondExport
        )
    }
}


// MARK: - Independent Word vertical-justification preservation

extension DOCXHeaderFooterTests {
    func testIndependentWordVerticalJustificationBothRoundTrip()
        throws
    {
        let contentTypes =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
              <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
              <Default Extension="xml" ContentType="application/xml"/>
              <Override
                PartName="/word/document.xml"
                ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
            </Types>
            """

        let rootRelationships =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
              <Relationship
                Id="rId1"
                Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument"
                Target="word/document.xml"/>
            </Relationships>
            """

        let documentXML =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:document
              xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
              <w:body>
                <w:p>
                  <w:r>
                    <w:t>VERTICALLY JUSTIFIED WORD SECTION</w:t>
                  </w:r>
                </w:p>

                <w:sectPr>
                  <w:vAlign w:val="both"/>
                  <w:pgSz
                    w:w="12240"
                    w:h="15840"/>
                  <w:pgMar
                    w:top="1440"
                    w:right="1440"
                    w:bottom="1440"
                    w:left="1440"/>
                </w:sectPr>
              </w:body>
            </w:document>
            """

        let source =
            ZipArchiveWriter.archive(
                [
                    ZipEntry(
                        path:
                            "[Content_Types].xml",
                        data:
                            Data(
                                contentTypes.utf8
                            )
                    ),
                    ZipEntry(
                        path:
                            "_rels/.rels",
                        data:
                            Data(
                                rootRelationships.utf8
                            )
                    ),
                    ZipEntry(
                        path:
                            "word/document.xml",
                        data:
                            Data(
                                documentXML.utf8
                            )
                    ),
                ]
            )

        func assertImported(
            _ imported:
                DOCXImporter.ImportedDocument,
            file: StaticString = #filePath,
            line: UInt = #line
        ) {
            XCTAssertEqual(
                imported.page
                    .effectiveVerticalPageAlignment,
                .both,
                file:
                    file,
                line:
                    line
            )
        }

        func assertExported(
            _ data: Data,
            file: StaticString = #filePath,
            line: UInt = #line
        ) throws {
            let parts =
                Dictionary(
                    uniqueKeysWithValues:
                        try DOCXPackage.entries(
                            in:
                                data
                        )
                        .map {
                            (
                                $0.path,
                                $0.data
                            )
                        }
                )

            let document =
                try DOCXPackage.xml(
                    XCTUnwrap(
                        parts[
                            "word/document.xml"
                        ],
                        file:
                            file,
                        line:
                            line
                    )
                )

            XCTAssertEqual(
                try document.nodes(
                    forXPath:
                        "//*[local-name()='sectPr']/*[local-name()='vAlign' and @*[local-name()='val']='both']"
                )
                .count,
                1,
                file:
                    file,
                line:
                    line
            )
        }

        let imported =
            try DOCXImporter.importedDocument(
                from:
                    source
            )

        assertImported(
            imported
        )

        let firstExport =
            try DOCXExporter.data(
                from:
                    imported.text,
                title:
                    "Independent Word Vertical Justification",
                settings:
                    imported.page,
                sections:
                    imported.sections
            )

        try assertExported(
            firstExport
        )

        let reopened =
            try DOCXImporter.importedDocument(
                from:
                    firstExport
            )

        assertImported(
            reopened
        )

        let secondExport =
            try DOCXExporter.data(
                from:
                    reopened.text,
                title:
                    "Independent Word Vertical Justification Twice",
                settings:
                    reopened.page,
                sections:
                    reopened.sections
            )

        try assertExported(
            secondExport
        )

        let reopenedTwice =
            try DOCXImporter.importedDocument(
                from:
                    secondExport
            )

        assertImported(
            reopenedTwice
        )
    }
}



// MARK: - Word noColumnBalance compatibility preservation

extension DOCXHeaderFooterTests {
    func testIndependentWordNoColumnBalanceRoundTrip()
        throws
    {
        let contentTypes =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
              <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
              <Default Extension="xml" ContentType="application/xml"/>
              <Override PartName="/word/document.xml"
                ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
              <Override PartName="/word/settings.xml"
                ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/>
            </Types>
            """

        let rootRelationships =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
              <Relationship Id="rId1"
                Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument"
                Target="word/document.xml"/>
            </Relationships>
            """

        let documentRelationships =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
              <Relationship Id="rIdSettings"
                Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings"
                Target="settings.xml"/>
            </Relationships>
            """

        let documentXML =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
              <w:body>
                <w:p>
                  <w:r>
                    <w:t>WORD COLUMN BALANCE COMPATIBILITY</w:t>
                  </w:r>
                </w:p>
                <w:sectPr>
                  <w:cols w:num="2" w:space="720"/>
                  <w:pgSz w:w="12240" w:h="15840"/>
                  <w:pgMar
                    w:top="1440"
                    w:right="1440"
                    w:bottom="1440"
                    w:left="1440"/>
                </w:sectPr>
              </w:body>
            </w:document>
            """

        func package(
            settingsXML: String
        ) -> Data {
            ZipArchiveWriter.archive(
                [
                    ZipEntry(
                        path:
                            "[Content_Types].xml",
                        data:
                            Data(
                                contentTypes.utf8
                            )
                    ),
                    ZipEntry(
                        path:
                            "_rels/.rels",
                        data:
                            Data(
                                rootRelationships.utf8
                            )
                    ),
                    ZipEntry(
                        path:
                            "word/document.xml",
                        data:
                            Data(
                                documentXML.utf8
                            )
                    ),
                    ZipEntry(
                        path:
                            "word/_rels/document.xml.rels",
                        data:
                            Data(
                                documentRelationships.utf8
                            )
                    ),
                    ZipEntry(
                        path:
                            "word/settings.xml",
                        data:
                            Data(
                                settingsXML.utf8
                            )
                    ),
                ]
            )
        }

        func imported(
            _ settingsXML: String
        ) throws -> DOCXImporter.ImportedDocument {
            try DOCXImporter.importedDocument(
                from:
                    package(
                        settingsXML:
                            settingsXML
                    )
            )
        }

        func settingsDocument(
            in data: Data
        ) throws -> XMLDocument? {
            let parts =
                Dictionary(
                    uniqueKeysWithValues:
                        try DOCXPackage.entries(
                            in:
                                data
                        )
                        .map {
                            (
                                $0.path,
                                $0.data
                            )
                        }
                )

            guard
                let settingsData =
                    parts[
                        "word/settings.xml"
                    ]
            else {
                return nil
            }

            return try DOCXPackage.xml(
                settingsData
            )
        }

        func assertEnabled(
            _ document:
                DOCXImporter.ImportedDocument,
            file: StaticString = #filePath,
            line: UInt = #line
        ) {
            XCTAssertEqual(
                document.page
                    .noColumnBalance,
                true,
                file:
                    file,
                line:
                    line
            )

            XCTAssertTrue(
                document.page
                    .disablesColumnBalancing,
                file:
                    file,
                line:
                    line
            )

            XCTAssertFalse(
                document.sections.isEmpty,
                file:
                    file,
                line:
                    line
            )

            for section in document.sections {
                XCTAssertTrue(
                    section.page
                        .disablesColumnBalancing,
                    file:
                        file,
                    line:
                        line
                )
            }
        }

        let enabledSettings =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
              <w:compat>
                <w:noColumnBalance/>
              </w:compat>
            </w:settings>
            """

        let original =
            try imported(
                enabledSettings
            )

        assertEnabled(
            original
        )

        XCTAssertEqual(
            original.page
                .effectiveColumnCount,
            2
        )

        let firstExport =
            try DOCXExporter.data(
                from:
                    original.text,
                title:
                    "No Column Balance",
                settings:
                    original.page,
                sections:
                    original.sections
            )

        let firstSettings =
            try XCTUnwrap(
                settingsDocument(
                    in:
                        firstExport
                )
            )

        XCTAssertEqual(
            try firstSettings.nodes(
                forXPath:
                    "//*[local-name()='compat']/*[local-name()='noColumnBalance']"
            )
            .count,
            1
        )

        XCTAssertTrue(
            try firstSettings.nodes(
                forXPath:
                    "/*[local-name()='settings']/*[local-name()='noColumnBalance']"
            )
            .isEmpty
        )

        let reopened =
            try DOCXImporter.importedDocument(
                from:
                    firstExport
            )

        assertEnabled(
            reopened
        )

        let secondExport =
            try DOCXExporter.data(
                from:
                    reopened.text,
                title:
                    "No Column Balance Twice",
                settings:
                    reopened.page,
                sections:
                    reopened.sections
            )

        let reopenedTwice =
            try DOCXImporter.importedDocument(
                from:
                    secondExport
            )

        assertEnabled(
            reopenedTwice
        )

        let misplacedSettings =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
              <w:noColumnBalance/>
            </w:settings>
            """

        let misplaced =
            try imported(
                misplacedSettings
            )

        XCTAssertNil(
            misplaced.page
                .noColumnBalance
        )

        XCTAssertFalse(
            misplaced.page
                .disablesColumnBalancing
        )

        let defaults =
            PageSettings()

        XCTAssertNil(
            defaults.noColumnBalance
        )

        XCTAssertFalse(
            defaults.disablesColumnBalancing
        )

        let defaultExport =
            try DOCXExporter.data(
                from:
                    NSAttributedString(
                        string:
                            "DEFAULT COLUMN BALANCING"
                    ),
                title:
                    "Default Column Balancing",
                settings:
                    defaults
            )

        if let settings =
            try settingsDocument(
                in:
                    defaultExport
            ) {

            XCTAssertTrue(
                try settings.nodes(
                    forXPath:
                        "//*[local-name()='compat']/*[local-name()='noColumnBalance']"
                )
                .isEmpty
            )
        }
    }
}
