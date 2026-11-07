import AppKit
import XCTest
@testable import BOLDWriter

@MainActor
final class ParagraphFormattingTests: XCTestCase {
    func testTextDirectionUpdatesSelectionAndSurvivesNativeAndDOCXRoundTrips() throws {
        let (view, controller) = editor("Direction example\n")
        view.setSelectedRange(NSRange(location: 0, length: view.string.utf16.count))
        controller.setTextDirection(.rightToLeft)
        XCTAssertEqual(try paragraphStyle(in: view).baseWritingDirection, .rightToLeft)
        XCTAssertEqual(controller.formatting.textDirection, .rightToLeft)
        XCTAssertEqual(view.textStorage?.attribute(.boldWriterParagraphBidi, at: 0, effectiveRange: nil) as? Bool, true)

        let document = BOLDWriterDocument()
        document.replaceText(with: NSAttributedString(attributedString: try XCTUnwrap(view.textStorage)))
        let package = try BOLDWriterDocument.packageWrapper(text: document.text, metadata: document.metadata)
        let reopened = try BOLDWriterDocument(fileWrapper: package, contentType: .boldWriterDocument)
        XCTAssertEqual((reopened.text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.baseWritingDirection, .rightToLeft)

        let data = try ExportService.data(for: .docx, document: reopened)
        let parts = try DOCXPackage.entries(in: data)
        let xml = try XCTUnwrap(String(data: try XCTUnwrap(parts.first(where: { $0.path == "word/document.xml" })?.data), encoding: .utf8))
        XCTAssertTrue(xml.contains("<w:bidi/>"))
        let imported = try BOLDWriterDocument(fileWrapper: FileWrapper(regularFileWithContents: data), contentType: .docx)
        XCTAssertEqual((imported.text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.baseWritingDirection, .rightToLeft)

        controller.setTextDirection(.leftToRight)
        XCTAssertEqual(try paragraphStyle(in: view).baseWritingDirection, .leftToRight)
        XCTAssertEqual(controller.formatting.textDirection, .leftToRight)
    }

    func testRulerTabStopsSurviveNativeSaveAndDOCXExport() throws {
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .right, location: 144, options: [:])]
        let document = BOLDWriterDocument()
        document.replaceText(with: NSAttributedString(
            string: "One\tTwo", attributes: [.font: NSFont.systemFont(ofSize: 15), .paragraphStyle: paragraph]
        ))

        let package = try BOLDWriterDocument.packageWrapper(text: document.text, metadata: document.metadata)
        let reopened = try BOLDWriterDocument(fileWrapper: package, contentType: .boldWriterDocument)
        let nativeStyle = try XCTUnwrap(reopened.text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        XCTAssertEqual(nativeStyle.tabStops.first?.location, 144)

        let data = try ExportService.data(for: .docx, document: reopened)
        let parts = try DOCXPackage.entries(in: data)
        let body = try XCTUnwrap(parts.first(where: { $0.path == "word/document.xml" })?.data)
        let xml = try XCTUnwrap(String(data: body, encoding: .utf8))
        XCTAssertTrue(xml.contains("<w:tab w:val=\"right\" w:pos=\"2880\"/>"))
        let imported = try BOLDWriterDocument(fileWrapper: FileWrapper(regularFileWithContents: data), contentType: .docx)
        let importedStyle = try XCTUnwrap(imported.text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        let importedTab = try XCTUnwrap(importedStyle.tabStops.first)
        XCTAssertEqual(importedTab.location, 144, accuracy: 0.5)
    }

    func testCustomTabStopDoesNotEraseListIdentityOnDOCXImport() throws {
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .right, location: 144, options: [:])]
        let list = NSTextList(markerFormat: .decimal, options: 0)
        list.startingItemNumber = 3
        paragraph.textLists = [list]
        let source = NSAttributedString(string: "List item\n", attributes: [
            .font: NSFont.systemFont(ofSize: 15), .paragraphStyle: paragraph
        ])
        let data = try DOCXExporter.data(from: source, title: "Custom List Tab")
        let imported = try DOCXImporter.text(from: data)
        let importedStyle = try XCTUnwrap(imported.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        XCTAssertEqual(importedStyle.tabStops.first?.location, 144)
        XCTAssertEqual(importedStyle.textLists.last?.startingItemNumber, 3)
    }

    private func editor(
        _ value: String = "First paragraph\nSecond paragraph\n"
    ) -> (NSTextView, EditorController) {
        let view = NSTextView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: 500,
                height: 500
            )
        )

        view.textStorage?.setAttributedString(
            NSAttributedString(
                string: value,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 15),
                    .foregroundColor: NSColor.textColor
                ]
            )
        )

        let controller = EditorController()
        controller.attach(view)

        return (view, controller)
    }

    private func paragraphStyle(
        in view: NSTextView,
        at location: Int = 0
    ) throws -> NSParagraphStyle {
        try XCTUnwrap(
            view.textStorage?.attribute(
                .paragraphStyle,
                at: location,
                effectiveRange: nil
            ) as? NSParagraphStyle
        )
    }

    func testFirstLineIndentUsesRelativeParagraphIndent() throws {
        let (view, controller) = editor()

        view.setSelectedRange(
            NSRange(location: 0, length: 15)
        )

        controller.setFirstLineIndentInches(0.5)

        let style = try paragraphStyle(in: view)

        XCTAssertEqual(
            style.firstLineHeadIndent - style.headIndent,
            36,
            accuracy: 0.01
        )

        XCTAssertEqual(
            controller.firstLineIndentInches,
            0.5,
            accuracy: 0.001
        )
    }

    func testHangingIndentUsesNegativeRelativeIndent() throws {
        let (view, controller) = editor()

        view.setSelectedRange(
            NSRange(location: 0, length: 15)
        )

        controller.setHangingIndentInches(0.25)

        let style = try paragraphStyle(in: view)

        XCTAssertEqual(
            style.firstLineHeadIndent - style.headIndent,
            -18,
            accuracy: 0.01
        )

        XCTAssertEqual(
            controller.hangingIndentInches,
            0.25,
            accuracy: 0.001
        )
    }

    func testParagraphSpacingAndExactLineSpacing() throws {
        let (view, controller) = editor()

        view.setSelectedRange(
            NSRange(location: 0, length: 15)
        )

        controller.setParagraphSpacingBefore(8)
        controller.setParagraphSpacing(12)
        controller.setExactLineSpacing(18)

        let style = try paragraphStyle(in: view)

        XCTAssertEqual(
            style.paragraphSpacingBefore,
            8,
            accuracy: 0.01
        )

        XCTAssertEqual(
            style.paragraphSpacing,
            12,
            accuracy: 0.01
        )

        XCTAssertEqual(
            style.minimumLineHeight,
            18,
            accuracy: 0.01
        )

        XCTAssertEqual(
            style.maximumLineHeight,
            18,
            accuracy: 0.01
        )
    }

    func testParagraphFormattingPreservesNativeListMetadata() throws {
        let (view, controller) = editor()

        view.setSelectedRange(
            NSRange(
                location: 0,
                length: view.string.utf16.count
            )
        )

        controller.toggleBulletList()
        controller.setParagraphSpacingBefore(6)
        controller.setParagraphSpacing(10)
        controller.setHangingIndentInches(0.25)

        let style = try paragraphStyle(in: view)

        let list = try XCTUnwrap(style.textLists.last)

        XCTAssertFalse(list.isOrdered)
        XCTAssertEqual(
            style.paragraphSpacingBefore,
            6,
            accuracy: 0.01
        )
        XCTAssertEqual(
            style.paragraphSpacing,
            10,
            accuracy: 0.01
        )
    }

    func testDOCXRoundTripsExactAndMultipleLineSpacing() throws {
        let exact =
            NSMutableParagraphStyle()

        exact.paragraphSpacingBefore =
            6

        exact.paragraphSpacing =
            10

        exact.lineHeightMultiple =
            0

        exact.minimumLineHeight =
            24

        exact.maximumLineHeight =
            24

        let multiple =
            NSMutableParagraphStyle()

        multiple.paragraphSpacingBefore =
            4

        multiple.paragraphSpacing =
            8

        multiple.lineHeightMultiple =
            1.5

        let text =
            NSMutableAttributedString(
                string:
                    "Exact paragraph\n",
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize:
                                15
                        ),
                    .paragraphStyle:
                        exact
                ]
            )

        text.append(
            NSAttributedString(
                string:
                    "Multiple paragraph",
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize:
                                15
                        ),
                    .paragraphStyle:
                        multiple
                ]
            )
        )

        let data =
            try DOCXExporter.data(
                from:
                    text,
                title:
                    "Paragraph Line Spacing"
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

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='spacing' and @*[local-name()='before']='120' and @*[local-name()='after']='200' and @*[local-name()='line']='480' and @*[local-name()='lineRule']='exact']"
            )
            .count,
            1
        )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='spacing' and @*[local-name()='before']='80' and @*[local-name()='after']='160' and @*[local-name()='line']='360' and @*[local-name()='lineRule']='auto']"
            )
            .count,
            1
        )

        let restored =
            try DOCXImporter.text(
                from:
                    data
            )

        XCTAssertEqual(
            restored.string,
            text.string
        )

        let exactStyle =
            try XCTUnwrap(
                restored.attribute(
                    .paragraphStyle,
                    at:
                        0,
                    effectiveRange:
                        nil
                )
                    as? NSParagraphStyle
            )

        let secondLocation =
            (
                restored.string
                    as NSString
            )
            .range(
                of:
                    "Multiple paragraph"
            )
            .location

        let multipleStyle =
            try XCTUnwrap(
                restored.attribute(
                    .paragraphStyle,
                    at:
                        secondLocation,
                    effectiveRange:
                        nil
                )
                    as? NSParagraphStyle
            )

        XCTAssertEqual(
            exactStyle.paragraphSpacingBefore,
            6,
            accuracy:
                0.5
        )

        XCTAssertEqual(
            exactStyle.paragraphSpacing,
            10,
            accuracy:
                0.5
        )

        XCTAssertEqual(
            exactStyle.minimumLineHeight,
            24,
            accuracy:
                0.5
        )

        XCTAssertEqual(
            exactStyle.maximumLineHeight,
            24,
            accuracy:
                0.5
        )

        XCTAssertEqual(
            multipleStyle.paragraphSpacingBefore,
            4,
            accuracy:
                0.5
        )

        XCTAssertEqual(
            multipleStyle.paragraphSpacing,
            8,
            accuracy:
                0.5
        )

        XCTAssertEqual(
            multipleStyle.lineHeightMultiple,
            1.5,
            accuracy:
                0.05
        )
    }


    func testDOCXRoundTripsWordParagraphPaginationFlags() throws {
        let text =
            NSMutableAttributedString(
                string:
                    "Heading paragraph\n"
                    + "Body paragraph\n"
                    + "Page-start paragraph",
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize:
                                15
                        )
                ]
            )

        let firstRange =
            (
                text.string
                    as NSString
            )
            .paragraphRange(
                for:
                    NSRange(
                        location:
                            0,
                        length:
                            0
                    )
            )

        text.addAttribute(
            .boldWriterKeepWithNext,
            value:
                true,
            range:
                firstRange
        )

        text.addAttribute(
            .boldWriterKeepLinesTogether,
            value:
                true,
            range:
                firstRange
        )

        let thirdLocation =
            (
                text.string
                    as NSString
            )
            .range(
                of:
                    "Page-start paragraph"
            )
            .location

        let thirdRange =
            (
                text.string
                    as NSString
            )
            .paragraphRange(
                for:
                    NSRange(
                        location:
                            thirdLocation,
                        length:
                            0
                    )
            )

        text.addAttribute(
            .boldWriterPageBreakBefore,
            value:
                true,
            range:
                thirdRange
        )

        let data =
            try DOCXExporter.data(
                from:
                    text,
                title:
                    "Paragraph Pagination Flags"
            )

        let entries =
            try DOCXPackage.entries(
                in:
                    data
            )

        let document =
            try DOCXPackage.xml(
                XCTUnwrap(
                    entries.first {
                        $0.path
                            == "word/document.xml"
                    }?
                    .data
                )
            )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='p'][1]/*[local-name()='pPr']/*[local-name()='keepNext']"
            )
            .count,
            1
        )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='p'][1]/*[local-name()='pPr']/*[local-name()='keepLines']"
            )
            .count,
            1
        )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='p'][3]/*[local-name()='pPr']/*[local-name()='pageBreakBefore']"
            )
            .count,
            1
        )

        let restored =
            try DOCXImporter.text(
                from:
                    data
            )

        XCTAssertEqual(
            restored.string,
            text.string
        )

        XCTAssertEqual(
            restored.attribute(
                .boldWriterKeepWithNext,
                at:
                    0,
                effectiveRange:
                    nil
            ) as? Bool,
            true
        )

        XCTAssertEqual(
            restored.attribute(
                .boldWriterKeepLinesTogether,
                at:
                    0,
                effectiveRange:
                    nil
            ) as? Bool,
            true
        )

        let bodyLocation =
            (
                restored.string
                    as NSString
            )
            .range(
                of:
                    "Body paragraph"
            )
            .location

        XCTAssertNil(
            restored.attribute(
                .boldWriterKeepWithNext,
                at:
                    bodyLocation,
                effectiveRange:
                    nil
            )
        )

        XCTAssertNil(
            restored.attribute(
                .boldWriterKeepLinesTogether,
                at:
                    bodyLocation,
                effectiveRange:
                    nil
            )
        )

        let restoredThird =
            (
                restored.string
                    as NSString
            )
            .range(
                of:
                    "Page-start paragraph"
            )
            .location

        XCTAssertEqual(
            restored.attribute(
                .boldWriterPageBreakBefore,
                at:
                    restoredThird,
                effectiveRange:
                    nil
            ) as? Bool,
            true
        )
    }


    func testDOCXRoundTripsWordWidowControl() throws {
        let text =
            NSMutableAttributedString(
                string:
                    "Widow control enabled\n"
                    + "Widow control disabled\n"
                    + "Widow control unspecified",
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize:
                                15
                        )
                ]
            )

        let source =
            text.string
                as NSString

        let enabledLocation =
            source.range(
                of:
                    "Widow control enabled"
            )
            .location

        let disabledLocation =
            source.range(
                of:
                    "Widow control disabled"
            )
            .location

        let unspecifiedLocation =
            source.range(
                of:
                    "Widow control unspecified"
            )
            .location

        let enabledRange =
            source.paragraphRange(
                for:
                    NSRange(
                        location:
                            enabledLocation,
                        length:
                            0
                    )
            )

        let disabledRange =
            source.paragraphRange(
                for:
                    NSRange(
                        location:
                            disabledLocation,
                        length:
                            0
                    )
            )

        text.addAttribute(
            .boldWriterWidowControl,
            value:
                true,
            range:
                enabledRange
        )

        text.addAttribute(
            .boldWriterWidowControl,
            value:
                false,
            range:
                disabledRange
        )

        let data =
            try DOCXExporter.data(
                from:
                    text,
                title:
                    "Widow Control"
            )

        let entries =
            try DOCXPackage.entries(
                in:
                    data
            )

        let document =
            try DOCXPackage.xml(
                XCTUnwrap(
                    entries.first {
                        $0.path
                            == "word/document.xml"
                    }?
                    .data
                )
            )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='p'][1]"
                    + "/*[local-name()='pPr']"
                    + "/*[local-name()='widowControl'"
                    + " and not(@*[local-name()='val'])]"
            )
            .count,
            1
        )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='p'][2]"
                    + "/*[local-name()='pPr']"
                    + "/*[local-name()='widowControl'"
                    + " and @*[local-name()='val']='0']"
            )
            .count,
            1
        )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='p'][3]"
                    + "/*[local-name()='pPr']"
                    + "/*[local-name()='widowControl']"
            )
            .count,
            0
        )

        let restored =
            try DOCXImporter.text(
                from:
                    data
            )

        XCTAssertEqual(
            restored.string,
            text.string
        )

        XCTAssertEqual(
            restored.attribute(
                .boldWriterWidowControl,
                at:
                    enabledLocation,
                effectiveRange:
                    nil
            ) as? Bool,
            true
        )

        XCTAssertEqual(
            restored.attribute(
                .boldWriterWidowControl,
                at:
                    disabledLocation,
                effectiveRange:
                    nil
            ) as? Bool,
            false
        )

        XCTAssertNil(
            restored.attribute(
                .boldWriterWidowControl,
                at:
                    unspecifiedLocation,
                effectiveRange:
                    nil
            )
        )
    }


    func testDOCXRoundTripsWordParagraphBorders() throws {
        let text =
            NSMutableAttributedString(
                string:
                    "Bordered paragraph\n"
                    + "Plain paragraph",
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize:
                                15
                        )
                ]
            )

        let borderedRange =
            (
                text.string
                    as NSString
            )
            .paragraphRange(
                for:
                    NSRange(
                        location:
                            0,
                        length:
                            0
                    )
            )

        let borders =
            WordParagraphBorders(
                top:
                    WordParagraphBorder(
                        style:
                            "single",
                        size:
                            8,
                        space:
                            1,
                        color:
                            "112233"
                    ),
                left:
                    WordParagraphBorder(
                        style:
                            "double",
                        size:
                            12,
                        space:
                            2,
                        color:
                            "445566"
                    ),
                bottom:
                    WordParagraphBorder(
                        style:
                            "dashed",
                        size:
                            6,
                        space:
                            3,
                        color:
                            "778899"
                    ),
                right:
                    WordParagraphBorder(
                        style:
                            "single",
                        size:
                            4,
                        space:
                            0,
                        color:
                            "ABCDEF"
                    ),
                between:
                    WordParagraphBorder(
                        style:
                            "dotted",
                        size:
                            4,
                        space:
                            1,
                        color:
                            "010203"
                    )
            )

        text.addAttribute(
            .boldWriterParagraphBorders,
            value:
                borders,
            range:
                borderedRange
        )

        let data =
            try DOCXExporter.data(
                from:
                    text,
                title:
                    "Paragraph Borders"
            )

        let entries =
            try DOCXPackage.entries(
                in:
                    data
            )

        let document =
            try DOCXPackage.xml(
                XCTUnwrap(
                    entries.first {
                        $0.path
                            == "word/document.xml"
                    }?
                    .data
                )
            )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='p'][1]"
                    + "/*[local-name()='pPr']"
                    + "/*[local-name()='pBdr']"
            )
            .count,
            1
        )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='p'][1]"
                    + "/*[local-name()='pPr']"
                    + "/*[local-name()='pBdr']"
                    + "/*[local-name()='top'"
                    + " and @*[local-name()='val']='single'"
                    + " and @*[local-name()='sz']='8'"
                    + " and @*[local-name()='space']='1'"
                    + " and @*[local-name()='color']='112233']"
            )
            .count,
            1
        )

        let restored =
            try DOCXImporter.text(
                from:
                    data
            )

        XCTAssertEqual(
            restored.string,
            text.string
        )

        let restoredBorders =
            try XCTUnwrap(
                restored.attribute(
                    .boldWriterParagraphBorders,
                    at:
                        0,
                    effectiveRange:
                        nil
                )
                    as? WordParagraphBorders
            )

        XCTAssertTrue(
            restoredBorders.isEqual(
                borders
            )
        )

        let plainLocation =
            (
                restored.string
                    as NSString
            )
            .range(
                of:
                    "Plain paragraph"
            )
            .location

        XCTAssertNil(
            restored.attribute(
                .boldWriterParagraphBorders,
                at:
                    plainLocation,
                effectiveRange:
                    nil
            )
        )

        let secondData =
            try DOCXExporter.data(
                from:
                    restored,
                title:
                    "Paragraph Borders Again"
            )

        let secondEntries =
            try DOCXPackage.entries(
                in:
                    secondData
            )

        let secondDocument =
            try DOCXPackage.xml(
                XCTUnwrap(
                    secondEntries.first {
                        $0.path
                            == "word/document.xml"
                    }?
                    .data
                )
            )

        XCTAssertEqual(
            try secondDocument.nodes(
                forXPath:
                    "//*[local-name()='p'][1]"
                    + "/*[local-name()='pPr']"
                    + "/*[local-name()='pBdr']"
                    + "/*[local-name()='between'"
                    + " and @*[local-name()='val']='dotted'"
                    + " and @*[local-name()='sz']='4'"
                    + " and @*[local-name()='space']='1'"
                    + " and @*[local-name()='color']='010203']"
            )
            .count,
            1
        )
    }


    func testDOCXRoundTripsWordParagraphShading() throws {
        let text =
            NSMutableAttributedString(
                string:
                    "Shaded paragraph\n"
                    + "Plain paragraph",
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize:
                                15
                        )
                ]
            )

        let shadedRange =
            (
                text.string
                    as NSString
            )
            .paragraphRange(
                for:
                    NSRange(
                        location:
                            0,
                        length:
                            0
                    )
            )

        let shading =
            WordParagraphShading(
                value:
                    "clear",
                color:
                    "auto",
                fill:
                    "D9EAF7"
            )

        text.addAttribute(
            .boldWriterParagraphShading,
            value:
                shading,
            range:
                shadedRange
        )

        let data =
            try DOCXExporter.data(
                from:
                    text,
                title:
                    "Paragraph Shading"
            )

        let entries =
            try DOCXPackage.entries(
                in:
                    data
            )

        let document =
            try DOCXPackage.xml(
                XCTUnwrap(
                    entries.first {
                        $0.path
                            == "word/document.xml"
                    }?
                    .data
                )
            )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='p'][1]"
                    + "/*[local-name()='pPr']"
                    + "/*[local-name()='shd'"
                    + " and @*[local-name()='val']='clear'"
                    + " and @*[local-name()='color']='auto'"
                    + " and @*[local-name()='fill']='D9EAF7']"
            )
            .count,
            1
        )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='p'][2]"
                    + "/*[local-name()='pPr']"
                    + "/*[local-name()='shd']"
            )
            .count,
            0
        )

        let restored =
            try DOCXImporter.text(
                from:
                    data
            )

        XCTAssertEqual(
            restored.string,
            text.string
        )

        let restoredShading =
            try XCTUnwrap(
                restored.attribute(
                    .boldWriterParagraphShading,
                    at:
                        0,
                    effectiveRange:
                        nil
                )
                    as? WordParagraphShading
            )

        XCTAssertTrue(
            restoredShading.isEqual(
                shading
            )
        )

        XCTAssertEqual(
            restoredShading.value.lowercased(),
            "clear"
        )

        XCTAssertEqual(
            restoredShading.color?.lowercased(),
            "auto"
        )

        XCTAssertEqual(
            restoredShading.fill?.uppercased(),
            "D9EAF7"
        )

        let plainLocation =
            (
                restored.string
                    as NSString
            )
            .range(
                of:
                    "Plain paragraph"
            )
            .location

        XCTAssertNil(
            restored.attribute(
                .boldWriterParagraphShading,
                at:
                    plainLocation,
                effectiveRange:
                    nil
            )
        )

        let secondData =
            try DOCXExporter.data(
                from:
                    restored,
                title:
                    "Paragraph Shading Again"
            )

        let secondEntries =
            try DOCXPackage.entries(
                in:
                    secondData
            )

        let secondDocument =
            try DOCXPackage.xml(
                XCTUnwrap(
                    secondEntries.first {
                        $0.path
                            == "word/document.xml"
                    }?
                    .data
                )
            )

        XCTAssertEqual(
            try secondDocument.nodes(
                forXPath:
                    "//*[local-name()='p'][1]"
                    + "/*[local-name()='pPr']"
                    + "/*[local-name()='shd'"
                    + " and @*[local-name()='color']='auto'"
                    + " and @*[local-name()='fill']='D9EAF7']"
            )
            .count,
            1
        )
    }


    func testDOCXRoundTripsWordSmallCapsAndHiddenText() throws {
        let text =
            NSMutableAttributedString(
                string:
                    "SMALL hidden plain explicitOff",
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize:
                                15
                        )
                ]
            )

        let source =
            text.string
                as NSString

        let smallRange =
            source.range(
                of:
                    "SMALL"
            )

        let hiddenRange =
            source.range(
                of:
                    "hidden"
            )

        let plainRange =
            source.range(
                of:
                    "plain"
            )

        let offRange =
            source.range(
                of:
                    "explicitOff"
            )

        text.addAttribute(
            .boldWriterSmallCaps,
            value:
                true,
            range:
                smallRange
        )

        text.addAttribute(
            .boldWriterHiddenText,
            value:
                true,
            range:
                hiddenRange
        )

        text.addAttribute(
            .boldWriterSmallCaps,
            value:
                false,
            range:
                offRange
        )

        text.addAttribute(
            .boldWriterHiddenText,
            value:
                false,
            range:
                offRange
        )

        let data =
            try DOCXExporter.data(
                from:
                    text,
                title:
                    "Small Caps Hidden"
            )

        let entries =
            try DOCXPackage.entries(
                in:
                    data
            )

        let document =
            try DOCXPackage.xml(
                XCTUnwrap(
                    entries.first {
                        $0.path
                            == "word/document.xml"
                    }?
                    .data
                )
            )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='r']"
                    + "[*[local-name()='t' and contains(text(),'SMALL')]]"
                    + "/*[local-name()='rPr']"
                    + "/*[local-name()='smallCaps'"
                    + " and not(@*[local-name()='val'])]"
            )
            .count,
            1
        )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='r']"
                    + "[*[local-name()='t' and contains(text(),'hidden')]]"
                    + "/*[local-name()='rPr']"
                    + "/*[local-name()='vanish'"
                    + " and not(@*[local-name()='val'])]"
            )
            .count,
            1
        )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='r']"
                    + "[*[local-name()='t' and contains(text(),'explicitOff')]]"
                    + "/*[local-name()='rPr']"
                    + "/*[local-name()='smallCaps'"
                    + " and @*[local-name()='val']='0']"
            )
            .count,
            1
        )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='r']"
                    + "[*[local-name()='t' and contains(text(),'explicitOff')]]"
                    + "/*[local-name()='rPr']"
                    + "/*[local-name()='vanish'"
                    + " and @*[local-name()='val']='0']"
            )
            .count,
            1
        )

        let restored =
            try DOCXImporter.text(
                from:
                    data
            )

        XCTAssertEqual(
            restored.string,
            text.string
        )

        XCTAssertEqual(
            restored.attribute(
                .boldWriterSmallCaps,
                at:
                    smallRange.location,
                effectiveRange:
                    nil
            ) as? Bool,
            true
        )

        XCTAssertEqual(
            restored.attribute(
                .boldWriterHiddenText,
                at:
                    hiddenRange.location,
                effectiveRange:
                    nil
            ) as? Bool,
            true
        )

        XCTAssertNil(
            restored.attribute(
                .boldWriterSmallCaps,
                at:
                    plainRange.location,
                effectiveRange:
                    nil
            )
        )

        XCTAssertNil(
            restored.attribute(
                .boldWriterHiddenText,
                at:
                    plainRange.location,
                effectiveRange:
                    nil
            )
        )

        XCTAssertEqual(
            restored.attribute(
                .boldWriterSmallCaps,
                at:
                    offRange.location,
                effectiveRange:
                    nil
            ) as? Bool,
            false
        )

        XCTAssertEqual(
            restored.attribute(
                .boldWriterHiddenText,
                at:
                    offRange.location,
                effectiveRange:
                    nil
            ) as? Bool,
            false
        )

        let secondData =
            try DOCXExporter.data(
                from:
                    restored,
                title:
                    "Small Caps Hidden Again"
            )

        let secondEntries =
            try DOCXPackage.entries(
                in:
                    secondData
            )

        let secondDocument =
            try DOCXPackage.xml(
                XCTUnwrap(
                    secondEntries.first {
                        $0.path
                            == "word/document.xml"
                    }?
                    .data
                )
            )

        XCTAssertEqual(
            try secondDocument.nodes(
                forXPath:
                    "//*[local-name()='r']"
                    + "[*[local-name()='t' and contains(text(),'SMALL')]]"
                    + "/*[local-name()='rPr']"
                    + "/*[local-name()='smallCaps']"
            )
            .count,
            1
        )

        XCTAssertEqual(
            try secondDocument.nodes(
                forXPath:
                    "//*[local-name()='r']"
                    + "[*[local-name()='t' and contains(text(),'hidden')]]"
                    + "/*[local-name()='rPr']"
                    + "/*[local-name()='vanish']"
            )
            .count,
            1
        )
    }


    func testDOCXRoundTripsWordSuperscriptSubscriptAndCharacterSpacing() throws {
        let text =
            NSMutableAttributedString(
                string:
                    "super sub spaced normal",
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize:
                                15
                        )
                ]
            )

        let source =
            text.string
                as NSString

        let superRange =
            source.range(
                of:
                    "super"
            )

        let subRange =
            source.range(
                of:
                    "sub"
            )

        let spacedRange =
            source.range(
                of:
                    "spaced"
            )

        let normalRange =
            source.range(
                of:
                    "normal"
            )

        text.addAttribute(
            .superscript,
            value:
                1,
            range:
                superRange
        )

        text.addAttribute(
            .superscript,
            value:
                -1,
            range:
                subRange
        )

        text.addAttribute(
            .kern,
            value:
                1.5,
            range:
                spacedRange
        )

        let data =
            try DOCXExporter.data(
                from:
                    text,
                title:
                    "Vertical Align Character Spacing"
            )

        let entries =
            try DOCXPackage.entries(
                in:
                    data
            )

        let document =
            try DOCXPackage.xml(
                XCTUnwrap(
                    entries.first {
                        $0.path
                            == "word/document.xml"
                    }?
                    .data
                )
            )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='r']"
                    + "[*[local-name()='t' and contains(text(),'super')]]"
                    + "/*[local-name()='rPr']"
                    + "/*[local-name()='vertAlign'"
                    + " and @*[local-name()='val']='superscript']"
            )
            .count,
            1
        )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='r']"
                    + "[*[local-name()='t' and contains(text(),'sub')]]"
                    + "/*[local-name()='rPr']"
                    + "/*[local-name()='vertAlign'"
                    + " and @*[local-name()='val']='subscript']"
            )
            .count,
            1
        )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='r']"
                    + "[*[local-name()='t' and contains(text(),'spaced')]]"
                    + "/*[local-name()='rPr']"
                    + "/*[local-name()='spacing'"
                    + " and @*[local-name()='val']='30']"
            )
            .count,
            1
        )

        let restored =
            try DOCXImporter.text(
                from:
                    data
            )

        XCTAssertEqual(
            restored.string,
            text.string
        )

        XCTAssertEqual(
            (
                restored.attribute(
                    .superscript,
                    at:
                        superRange.location,
                    effectiveRange:
                        nil
                ) as? NSNumber
            )?
            .intValue,
            1
        )

        XCTAssertEqual(
            (
                restored.attribute(
                    .superscript,
                    at:
                        subRange.location,
                    effectiveRange:
                        nil
                ) as? NSNumber
            )?
            .intValue,
            -1
        )

        XCTAssertEqual(
            (
                restored.attribute(
                    .kern,
                    at:
                        spacedRange.location,
                    effectiveRange:
                        nil
                ) as? NSNumber
            )?
            .doubleValue
            ?? 0,
            1.5,
            accuracy:
                0.001
        )

        XCTAssertNil(
            restored.attribute(
                .superscript,
                at:
                    normalRange.location,
                effectiveRange:
                    nil
            )
        )

        XCTAssertNil(
            restored.attribute(
                .kern,
                at:
                    normalRange.location,
                effectiveRange:
                    nil
            )
        )

        let secondData =
            try DOCXExporter.data(
                from:
                    restored,
                title:
                    "Vertical Align Character Spacing Again"
            )

        let secondEntries =
            try DOCXPackage.entries(
                in:
                    secondData
            )

        let secondDocument =
            try DOCXPackage.xml(
                XCTUnwrap(
                    secondEntries.first {
                        $0.path
                            == "word/document.xml"
                    }?
                    .data
                )
            )

        XCTAssertEqual(
            try secondDocument.nodes(
                forXPath:
                    "//*[local-name()='r']"
                    + "[*[local-name()='t' and contains(text(),'super')]]"
                    + "/*[local-name()='rPr']"
                    + "/*[local-name()='vertAlign'"
                    + " and @*[local-name()='val']='superscript']"
            )
            .count,
            1
        )

        XCTAssertEqual(
            try secondDocument.nodes(
                forXPath:
                    "//*[local-name()='r']"
                    + "[*[local-name()='t' and contains(text(),'spaced')]]"
                    + "/*[local-name()='rPr']"
                    + "/*[local-name()='spacing'"
                    + " and @*[local-name()='val']='30']"
            )
            .count,
            1
        )
    }


    func testDOCXRoundTripsWordOutlineShadowEmbossAndImprint() throws {
        let text =
            NSMutableAttributedString(
                string:
                    "outline shadow emboss imprint off plain",
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize:
                                15
                        )
                ]
            )

        let source =
            text.string
                as NSString

        let outlineRange =
            source.range(
                of:
                    "outline"
            )

        let shadowRange =
            source.range(
                of:
                    "shadow"
            )

        let embossRange =
            source.range(
                of:
                    "emboss"
            )

        let imprintRange =
            source.range(
                of:
                    "imprint"
            )

        let offRange =
            source.range(
                of:
                    "off"
            )

        let plainRange =
            source.range(
                of:
                    "plain"
            )

        text.addAttribute(
            .boldWriterOutlineText,
            value:
                true,
            range:
                outlineRange
        )

        text.addAttribute(
            .boldWriterShadowText,
            value:
                true,
            range:
                shadowRange
        )

        text.addAttribute(
            .boldWriterEmbossText,
            value:
                true,
            range:
                embossRange
        )

        text.addAttribute(
            .boldWriterImprintText,
            value:
                true,
            range:
                imprintRange
        )

        for key in [
            NSAttributedString.Key.boldWriterOutlineText,
            .boldWriterShadowText,
            .boldWriterEmbossText,
            .boldWriterImprintText
        ] {
            text.addAttribute(
                key,
                value:
                    false,
                range:
                    offRange
            )
        }

        let data =
            try DOCXExporter.data(
                from:
                    text,
                title:
                    "Text Effects"
            )

        let entries =
            try DOCXPackage.entries(
                in:
                    data
            )

        let document =
            try DOCXPackage.xml(
                XCTUnwrap(
                    entries.first {
                        $0.path
                            == "word/document.xml"
                    }?
                    .data
                )
            )

        func count(
            _ word: String,
            _ property: String,
            value: String? = nil
        ) throws -> Int {
            var xpath =
                "//*[local-name()='r']"
                + "[*[local-name()='t' and contains(text(),'"
                + word
                + "')]]"
                + "/*[local-name()='rPr']"
                + "/*[local-name()='"
                + property
                + "'"

            if let value {
                xpath +=
                    " and @*[local-name()='val']='"
                    + value
                    + "'"
            } else {
                xpath +=
                    " and not(@*[local-name()='val'])"
            }

            xpath += "]"

            return try document.nodes(
                forXPath:
                    xpath
            )
            .count
        }

        XCTAssertEqual(
            try count(
                "outline",
                "outline"
            ),
            1
        )

        XCTAssertEqual(
            try count(
                "shadow",
                "shadow"
            ),
            1
        )

        XCTAssertEqual(
            try count(
                "emboss",
                "emboss"
            ),
            1
        )

        XCTAssertEqual(
            try count(
                "imprint",
                "imprint"
            ),
            1
        )

        XCTAssertEqual(
            try count(
                "off",
                "outline",
                value:
                    "0"
            ),
            1
        )

        XCTAssertEqual(
            try count(
                "off",
                "shadow",
                value:
                    "0"
            ),
            1
        )

        XCTAssertEqual(
            try count(
                "off",
                "emboss",
                value:
                    "0"
            ),
            1
        )

        XCTAssertEqual(
            try count(
                "off",
                "imprint",
                value:
                    "0"
            ),
            1
        )

        let restored =
            try DOCXImporter.text(
                from:
                    data
            )

        XCTAssertEqual(
            restored.string,
            text.string
        )

        XCTAssertEqual(
            restored.attribute(
                .boldWriterOutlineText,
                at:
                    outlineRange.location,
                effectiveRange:
                    nil
            ) as? Bool,
            true
        )

        XCTAssertEqual(
            restored.attribute(
                .boldWriterShadowText,
                at:
                    shadowRange.location,
                effectiveRange:
                    nil
            ) as? Bool,
            true
        )

        XCTAssertEqual(
            restored.attribute(
                .boldWriterEmbossText,
                at:
                    embossRange.location,
                effectiveRange:
                    nil
            ) as? Bool,
            true
        )

        XCTAssertEqual(
            restored.attribute(
                .boldWriterImprintText,
                at:
                    imprintRange.location,
                effectiveRange:
                    nil
            ) as? Bool,
            true
        )

        XCTAssertEqual(
            restored.attribute(
                .boldWriterOutlineText,
                at:
                    offRange.location,
                effectiveRange:
                    nil
            ) as? Bool,
            false
        )

        XCTAssertEqual(
            restored.attribute(
                .boldWriterShadowText,
                at:
                    offRange.location,
                effectiveRange:
                    nil
            ) as? Bool,
            false
        )

        XCTAssertEqual(
            restored.attribute(
                .boldWriterEmbossText,
                at:
                    offRange.location,
                effectiveRange:
                    nil
            ) as? Bool,
            false
        )

        XCTAssertEqual(
            restored.attribute(
                .boldWriterImprintText,
                at:
                    offRange.location,
                effectiveRange:
                    nil
            ) as? Bool,
            false
        )

        XCTAssertNil(
            restored.attribute(
                .boldWriterOutlineText,
                at:
                    plainRange.location,
                effectiveRange:
                    nil
            )
        )

        XCTAssertNil(
            restored.attribute(
                .boldWriterShadowText,
                at:
                    plainRange.location,
                effectiveRange:
                    nil
            )
        )

        XCTAssertNil(
            restored.attribute(
                .boldWriterEmbossText,
                at:
                    plainRange.location,
                effectiveRange:
                    nil
            )
        )

        XCTAssertNil(
            restored.attribute(
                .boldWriterImprintText,
                at:
                    plainRange.location,
                effectiveRange:
                    nil
            )
        )

        let secondData =
            try DOCXExporter.data(
                from:
                    restored,
                title:
                    "Text Effects Again"
            )

        let secondEntries =
            try DOCXPackage.entries(
                in:
                    secondData
            )

        let secondDocument =
            try DOCXPackage.xml(
                XCTUnwrap(
                    secondEntries.first {
                        $0.path
                            == "word/document.xml"
                    }?
                    .data
                )
            )

        XCTAssertEqual(
            try secondDocument.nodes(
                forXPath:
                    "//*[local-name()='r']"
                    + "[*[local-name()='t' and contains(text(),'outline')]]"
                    + "/*[local-name()='rPr']"
                    + "/*[local-name()='outline']"
            )
            .count,
            1
        )

        XCTAssertEqual(
            try secondDocument.nodes(
                forXPath:
                    "//*[local-name()='r']"
                    + "[*[local-name()='t' and contains(text(),'shadow')]]"
                    + "/*[local-name()='rPr']"
                    + "/*[local-name()='shadow']"
            )
            .count,
            1
        )

        XCTAssertEqual(
            try secondDocument.nodes(
                forXPath:
                    "//*[local-name()='r']"
                    + "[*[local-name()='t' and contains(text(),'emboss')]]"
                    + "/*[local-name()='rPr']"
                    + "/*[local-name()='emboss']"
            )
            .count,
            1
        )

        XCTAssertEqual(
            try secondDocument.nodes(
                forXPath:
                    "//*[local-name()='r']"
                    + "[*[local-name()='t' and contains(text(),'imprint')]]"
                    + "/*[local-name()='rPr']"
                    + "/*[local-name()='imprint']"
            )
            .count,
            1
        )
    }


    func testDOCXRoundTripsWordDoubleStrikeAllCapsAndCharacterScaling() throws {
        let text =
            NSMutableAttributedString(
                string:
                    "double caps scaled off plain",
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize:
                                15
                        )
                ]
            )

        let source =
            text.string
                as NSString

        let doubleRange =
            source.range(
                of:
                    "double"
            )

        let capsRange =
            source.range(
                of:
                    "caps"
            )

        let scaledRange =
            source.range(
                of:
                    "scaled"
            )

        let offRange =
            source.range(
                of:
                    "off"
            )

        let plainRange =
            source.range(
                of:
                    "plain"
            )

        text.addAttribute(
            .boldWriterDoubleStrikethrough,
            value:
                true,
            range:
                doubleRange
        )

        text.addAttribute(
            .boldWriterAllCaps,
            value:
                true,
            range:
                capsRange
        )

        text.addAttribute(
            .boldWriterCharacterScale,
            value:
                80,
            range:
                scaledRange
        )

        text.addAttribute(
            .boldWriterDoubleStrikethrough,
            value:
                false,
            range:
                offRange
        )

        text.addAttribute(
            .boldWriterAllCaps,
            value:
                false,
            range:
                offRange
        )

        let data =
            try DOCXExporter.data(
                from:
                    text,
                title:
                    "Double Strike Caps Scaling"
            )

        let entries =
            try DOCXPackage.entries(
                in:
                    data
            )

        let document =
            try DOCXPackage.xml(
                XCTUnwrap(
                    entries.first {
                        $0.path
                            == "word/document.xml"
                    }?
                    .data
                )
            )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='r']"
                    + "[*[local-name()='t' and contains(text(),'double')]]"
                    + "/*[local-name()='rPr']"
                    + "/*[local-name()='dstrike'"
                    + " and not(@*[local-name()='val'])]"
            )
            .count,
            1
        )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='r']"
                    + "[*[local-name()='t' and contains(text(),'caps')]]"
                    + "/*[local-name()='rPr']"
                    + "/*[local-name()='caps'"
                    + " and not(@*[local-name()='val'])]"
            )
            .count,
            1
        )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='r']"
                    + "[*[local-name()='t' and contains(text(),'scaled')]]"
                    + "/*[local-name()='rPr']"
                    + "/*[local-name()='w'"
                    + " and @*[local-name()='val']='80']"
            )
            .count,
            1
        )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='r']"
                    + "[*[local-name()='t' and contains(text(),'off')]]"
                    + "/*[local-name()='rPr']"
                    + "/*[local-name()='dstrike'"
                    + " and @*[local-name()='val']='0']"
            )
            .count,
            1
        )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='r']"
                    + "[*[local-name()='t' and contains(text(),'off')]]"
                    + "/*[local-name()='rPr']"
                    + "/*[local-name()='caps'"
                    + " and @*[local-name()='val']='0']"
            )
            .count,
            1
        )

        let restored =
            try DOCXImporter.text(
                from:
                    data
            )

        XCTAssertEqual(
            restored.string,
            text.string
        )

        XCTAssertEqual(
            restored.attribute(
                .boldWriterDoubleStrikethrough,
                at:
                    doubleRange.location,
                effectiveRange:
                    nil
            ) as? Bool,
            true
        )

        XCTAssertEqual(
            restored.attribute(
                .boldWriterAllCaps,
                at:
                    capsRange.location,
                effectiveRange:
                    nil
            ) as? Bool,
            true
        )

        XCTAssertEqual(
            (
                restored.attribute(
                    .boldWriterCharacterScale,
                    at:
                        scaledRange.location,
                    effectiveRange:
                        nil
                ) as? NSNumber
            )?
            .intValue,
            80
        )

        XCTAssertEqual(
            restored.attribute(
                .boldWriterDoubleStrikethrough,
                at:
                    offRange.location,
                effectiveRange:
                    nil
            ) as? Bool,
            false
        )

        XCTAssertEqual(
            restored.attribute(
                .boldWriterAllCaps,
                at:
                    offRange.location,
                effectiveRange:
                    nil
            ) as? Bool,
            false
        )

        XCTAssertNil(
            restored.attribute(
                .boldWriterDoubleStrikethrough,
                at:
                    plainRange.location,
                effectiveRange:
                    nil
            )
        )

        XCTAssertNil(
            restored.attribute(
                .boldWriterAllCaps,
                at:
                    plainRange.location,
                effectiveRange:
                    nil
            )
        )

        XCTAssertNil(
            restored.attribute(
                .boldWriterCharacterScale,
                at:
                    plainRange.location,
                effectiveRange:
                    nil
            )
        )

        let secondData =
            try DOCXExporter.data(
                from:
                    restored,
                title:
                    "Double Strike Caps Scaling Again"
            )

        let secondEntries =
            try DOCXPackage.entries(
                in:
                    secondData
            )

        let secondDocument =
            try DOCXPackage.xml(
                XCTUnwrap(
                    secondEntries.first {
                        $0.path
                            == "word/document.xml"
                    }?
                    .data
                )
            )

        XCTAssertEqual(
            try secondDocument.nodes(
                forXPath:
                    "//*[local-name()='r']"
                    + "[*[local-name()='t' and contains(text(),'double')]]"
                    + "/*[local-name()='rPr']"
                    + "/*[local-name()='dstrike']"
            )
            .count,
            1
        )

        XCTAssertEqual(
            try secondDocument.nodes(
                forXPath:
                    "//*[local-name()='r']"
                    + "[*[local-name()='t' and contains(text(),'caps')]]"
                    + "/*[local-name()='rPr']"
                    + "/*[local-name()='caps']"
            )
            .count,
            1
        )

        XCTAssertEqual(
            try secondDocument.nodes(
                forXPath:
                    "//*[local-name()='r']"
                    + "[*[local-name()='t' and contains(text(),'scaled')]]"
                    + "/*[local-name()='rPr']"
                    + "/*[local-name()='w'"
                    + " and @*[local-name()='val']='80']"
            )
            .count,
            1
        )
    }


    func testDOCXRoundTripsWordPositionUnderlineVariantsAndLanguage() throws {
        let text =
            NSMutableAttributedString(
                string:
                    "position double wave language plain",
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize:
                                15
                        )
                ]
            )

        let source =
            text.string
                as NSString

        let positionRange =
            source.range(
                of:
                    "position"
            )

        let doubleRange =
            source.range(
                of:
                    "double"
            )

        let waveRange =
            source.range(
                of:
                    "wave"
            )

        let languageRange =
            source.range(
                of:
                    "language"
            )

        let plainRange =
            source.range(
                of:
                    "plain"
            )

        text.addAttribute(
            .baselineOffset,
            value:
                2.5,
            range:
                positionRange
        )

        text.addAttribute(
            .underlineStyle,
            value:
                NSUnderlineStyle.double.rawValue,
            range:
                doubleRange
        )

        text.addAttribute(
            .boldWriterUnderlineVariant,
            value:
                "wave",
            range:
                waveRange
        )

        text.addAttribute(
            .underlineStyle,
            value:
                NSUnderlineStyle.single.rawValue,
            range:
                waveRange
        )

        text.addAttribute(
            .boldWriterLanguage,
            value:
                "fr-FR",
            range:
                languageRange
        )

        let data =
            try DOCXExporter.data(
                from:
                    text,
                title:
                    "Position Underline Language"
            )

        let entries =
            try DOCXPackage.entries(
                in:
                    data
            )

        let document =
            try DOCXPackage.xml(
                XCTUnwrap(
                    entries.first {
                        $0.path
                            == "word/document.xml"
                    }?
                    .data
                )
            )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='r']"
                    + "[*[local-name()='t' and contains(text(),'position')]]"
                    + "/*[local-name()='rPr']"
                    + "/*[local-name()='position'"
                    + " and @*[local-name()='val']='5']"
            )
            .count,
            1
        )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='r']"
                    + "[*[local-name()='t' and contains(text(),'double')]]"
                    + "/*[local-name()='rPr']"
                    + "/*[local-name()='u'"
                    + " and @*[local-name()='val']='double']"
            )
            .count,
            1
        )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='r']"
                    + "[*[local-name()='t' and contains(text(),'wave')]]"
                    + "/*[local-name()='rPr']"
                    + "/*[local-name()='u'"
                    + " and @*[local-name()='val']='wave']"
            )
            .count,
            1
        )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='r']"
                    + "[*[local-name()='t' and contains(text(),'language')]]"
                    + "/*[local-name()='rPr']"
                    + "/*[local-name()='lang'"
                    + " and @*[local-name()='val']='fr-FR']"
            )
            .count,
            1
        )

        let restored =
            try DOCXImporter.text(
                from:
                    data
            )

        XCTAssertEqual(
            restored.string,
            text.string
        )

        XCTAssertEqual(
            (
                restored.attribute(
                    .baselineOffset,
                    at:
                        positionRange.location,
                    effectiveRange:
                        nil
                ) as? NSNumber
            )?
            .doubleValue
            ?? 0,
            2.5,
            accuracy:
                0.001
        )

        XCTAssertEqual(
            restored.attribute(
                .boldWriterUnderlineVariant,
                at:
                    doubleRange.location,
                effectiveRange:
                    nil
            ) as? String,
            "double"
        )

        XCTAssertEqual(
            restored.attribute(
                .boldWriterUnderlineVariant,
                at:
                    waveRange.location,
                effectiveRange:
                    nil
            ) as? String,
            "wave"
        )

        XCTAssertNotEqual(
            (
                restored.attribute(
                    .underlineStyle,
                    at:
                        waveRange.location,
                    effectiveRange:
                        nil
                ) as? NSNumber
            )?
            .intValue
            ?? 0,
            0
        )

        XCTAssertEqual(
            restored.attribute(
                .boldWriterLanguage,
                at:
                    languageRange.location,
                effectiveRange:
                    nil
            ) as? String,
            "fr-FR"
        )

        XCTAssertNil(
            restored.attribute(
                .boldWriterUnderlineVariant,
                at:
                    plainRange.location,
                effectiveRange:
                    nil
            )
        )

        XCTAssertNil(
            restored.attribute(
                .boldWriterLanguage,
                at:
                    plainRange.location,
                effectiveRange:
                    nil
            )
        )

        let secondData =
            try DOCXExporter.data(
                from:
                    restored,
                title:
                    "Position Underline Language Again"
            )

        let secondEntries =
            try DOCXPackage.entries(
                in:
                    secondData
            )

        let secondDocument =
            try DOCXPackage.xml(
                XCTUnwrap(
                    secondEntries.first {
                        $0.path
                            == "word/document.xml"
                    }?
                    .data
                )
            )

        XCTAssertEqual(
            try secondDocument.nodes(
                forXPath:
                    "//*[local-name()='r']"
                    + "[*[local-name()='t' and contains(text(),'wave')]]"
                    + "/*[local-name()='rPr']"
                    + "/*[local-name()='u'"
                    + " and @*[local-name()='val']='wave']"
            )
            .count,
            1
        )

        XCTAssertEqual(
            try secondDocument.nodes(
                forXPath:
                    "//*[local-name()='r']"
                    + "[*[local-name()='t' and contains(text(),'language')]]"
                    + "/*[local-name()='rPr']"
                    + "/*[local-name()='lang'"
                    + " and @*[local-name()='val']='fr-FR']"
            )
            .count,
            1
        )
    }


    func testDOCXRoundTripsWordRunBorderThemedShadingAndNoProof() throws {
        let text =
            NSMutableAttributedString(
                string:
                    "border shading proof off plain",
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize:
                                15
                        )
                ]
            )

        let source =
            text.string
                as NSString

        let borderRange =
            source.range(
                of:
                    "border"
            )

        let shadingRange =
            source.range(
                of:
                    "shading"
            )

        let proofRange =
            source.range(
                of:
                    "proof"
            )

        let offRange =
            source.range(
                of:
                    "off"
            )

        let plainRange =
            source.range(
                of:
                    "plain"
            )

        let border =
            WordRunBorder(
                style:
                    "single",
                size:
                    8,
                space:
                    1,
                color:
                    "336699",
                themeColor:
                    "accent1",
                themeTint:
                    "66",
                themeShade:
                    nil
            )

        let shading =
            WordRunShading(
                value:
                    "clear",
                color:
                    "auto",
                fill:
                    "DDEEFF",
                themeColor:
                    "text1",
                themeTint:
                    nil,
                themeShade:
                    nil,
                themeFill:
                    "accent2",
                themeFillTint:
                    "99",
                themeFillShade:
                    nil
            )

        text.addAttribute(
            .boldWriterRunBorder,
            value:
                border,
            range:
                borderRange
        )

        text.addAttribute(
            .boldWriterRunShading,
            value:
                shading,
            range:
                shadingRange
        )

        text.addAttribute(
            .boldWriterNoProof,
            value:
                true,
            range:
                proofRange
        )

        text.addAttribute(
            .boldWriterNoProof,
            value:
                false,
            range:
                offRange
        )

        let data =
            try DOCXExporter.data(
                from:
                    text,
                title:
                    "Run Border Shading NoProof"
            )

        let entries =
            try DOCXPackage.entries(
                in:
                    data
            )

        let document =
            try DOCXPackage.xml(
                XCTUnwrap(
                    entries.first {
                        $0.path
                            == "word/document.xml"
                    }?
                    .data
                )
            )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='r']"
                    + "[*[local-name()='t' and contains(text(),'border')]]"
                    + "/*[local-name()='rPr']"
                    + "/*[local-name()='bdr'"
                    + " and @*[local-name()='val']='single'"
                    + " and @*[local-name()='sz']='8'"
                    + " and @*[local-name()='space']='1'"
                    + " and @*[local-name()='color']='336699'"
                    + " and @*[local-name()='themeColor']='accent1'"
                    + " and @*[local-name()='themeTint']='66']"
            )
            .count,
            1
        )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='r']"
                    + "[*[local-name()='t' and contains(text(),'shading')]]"
                    + "/*[local-name()='rPr']"
                    + "/*[local-name()='shd'"
                    + " and @*[local-name()='val']='clear'"
                    + " and @*[local-name()='color']='auto'"
                    + " and @*[local-name()='fill']='DDEEFF'"
                    + " and @*[local-name()='themeColor']='text1'"
                    + " and @*[local-name()='themeFill']='accent2'"
                    + " and @*[local-name()='themeFillTint']='99']"
            )
            .count,
            1
        )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='r']"
                    + "[*[local-name()='t' and contains(text(),'proof')]]"
                    + "/*[local-name()='rPr']"
                    + "/*[local-name()='noProof'"
                    + " and not(@*[local-name()='val'])]"
            )
            .count,
            1
        )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='r']"
                    + "[*[local-name()='t' and contains(text(),'off')]]"
                    + "/*[local-name()='rPr']"
                    + "/*[local-name()='noProof'"
                    + " and @*[local-name()='val']='0']"
            )
            .count,
            1
        )

        let restored =
            try DOCXImporter.text(
                from:
                    data
            )

        XCTAssertEqual(
            restored.string,
            text.string
        )

        let restoredBorder =
            try XCTUnwrap(
                restored.attribute(
                    .boldWriterRunBorder,
                    at:
                        borderRange.location,
                    effectiveRange:
                        nil
                ) as? WordRunBorder
            )

        XCTAssertTrue(
            restoredBorder.isEqual(
                border
            )
        )

        let restoredShading =
            try XCTUnwrap(
                restored.attribute(
                    .boldWriterRunShading,
                    at:
                        shadingRange.location,
                    effectiveRange:
                        nil
                ) as? WordRunShading
            )

        XCTAssertTrue(
            restoredShading.isEqual(
                shading
            )
        )

        XCTAssertEqual(
            restored.attribute(
                .boldWriterNoProof,
                at:
                    proofRange.location,
                effectiveRange:
                    nil
            ) as? Bool,
            true
        )

        XCTAssertEqual(
            restored.attribute(
                .boldWriterNoProof,
                at:
                    offRange.location,
                effectiveRange:
                    nil
            ) as? Bool,
            false
        )

        XCTAssertNil(
            restored.attribute(
                .boldWriterRunBorder,
                at:
                    plainRange.location,
                effectiveRange:
                    nil
            )
        )

        XCTAssertNil(
            restored.attribute(
                .boldWriterRunShading,
                at:
                    plainRange.location,
                effectiveRange:
                    nil
            )
        )

        XCTAssertNil(
            restored.attribute(
                .boldWriterNoProof,
                at:
                    plainRange.location,
                effectiveRange:
                    nil
            )
        )

        let secondData =
            try DOCXExporter.data(
                from:
                    restored,
                title:
                    "Run Border Shading NoProof Again"
            )

        let secondEntries =
            try DOCXPackage.entries(
                in:
                    secondData
            )

        let secondDocument =
            try DOCXPackage.xml(
                XCTUnwrap(
                    secondEntries.first {
                        $0.path
                            == "word/document.xml"
                    }?
                    .data
                )
            )

        XCTAssertEqual(
            try secondDocument.nodes(
                forXPath:
                    "//*[local-name()='r']"
                    + "[*[local-name()='t' and contains(text(),'border')]]"
                    + "/*[local-name()='rPr']"
                    + "/*[local-name()='bdr'"
                    + " and @*[local-name()='themeColor']='accent1']"
            )
            .count,
            1
        )

        XCTAssertEqual(
            try secondDocument.nodes(
                forXPath:
                    "//*[local-name()='r']"
                    + "[*[local-name()='t' and contains(text(),'shading')]]"
                    + "/*[local-name()='rPr']"
                    + "/*[local-name()='shd'"
                    + " and @*[local-name()='themeFill']='accent2']"
            )
            .count,
            1
        )
    }


    func testDOCXRoundTripsWordRTLComplexScriptAndFontThemes() throws {
        let text =
            NSMutableAttributedString(
                string:
                    "rtl complex themed off plain",
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize:
                                15
                        )
                ]
            )

        let source =
            text.string as NSString

        let rtlRange = source.range(of: "rtl")
        let complexRange = source.range(of: "complex")
        let themedRange = source.range(of: "themed")
        let offRange = source.range(of: "off")
        let plainRange = source.range(of: "plain")

        text.addAttribute(
            .boldWriterRTL,
            value:
                true,
            range:
                rtlRange
        )

        text.addAttribute(
            .boldWriterComplexScriptBold,
            value:
                true,
            range:
                complexRange
        )

        text.addAttribute(
            .boldWriterComplexScriptItalic,
            value:
                true,
            range:
                complexRange
        )

        text.addAttribute(
            .boldWriterComplexScriptSize,
            value:
                30,
            range:
                complexRange
        )

        let fonts =
            WordRunFonts(
                ascii:
                    "Aptos",
                hAnsi:
                    "Aptos",
                eastAsia:
                    "MS Mincho",
                complexScript:
                    "Arial",
                asciiTheme:
                    "minorHAnsi",
                hAnsiTheme:
                    "minorHAnsi",
                eastAsiaTheme:
                    "minorEastAsia",
                complexScriptTheme:
                    "minorBidi",
                hint:
                    "eastAsia"
            )

        text.addAttribute(
            .boldWriterRunFonts,
            value:
                fonts,
            range:
                themedRange
        )

        text.addAttribute(
            .boldWriterRTL,
            value:
                false,
            range:
                offRange
        )

        text.addAttribute(
            .boldWriterComplexScriptBold,
            value:
                false,
            range:
                offRange
        )

        text.addAttribute(
            .boldWriterComplexScriptItalic,
            value:
                false,
            range:
                offRange
        )

        let data =
            try DOCXExporter.data(
                from:
                    text,
                title:
                    "RTL Complex Script Font Themes"
            )

        let entries =
            try DOCXPackage.entries(
                in:
                    data
            )

        let document =
            try DOCXPackage.xml(
                XCTUnwrap(
                    entries.first {
                        $0.path == "word/document.xml"
                    }?
                    .data
                )
            )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='r']"
                    + "[*[local-name()='t' and contains(text(),'rtl')]]"
                    + "/*[local-name()='rPr']"
                    + "/*[local-name()='rtl'"
                    + " and not(@*[local-name()='val'])]"
            )
            .count,
            1
        )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='r']"
                    + "[*[local-name()='t' and contains(text(),'complex')]]"
                    + "/*[local-name()='rPr']"
                    + "/*[local-name()='bCs'"
                    + " and not(@*[local-name()='val'])]"
            )
            .count,
            1
        )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='r']"
                    + "[*[local-name()='t' and contains(text(),'complex')]]"
                    + "/*[local-name()='rPr']"
                    + "/*[local-name()='iCs'"
                    + " and not(@*[local-name()='val'])]"
            )
            .count,
            1
        )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='r']"
                    + "[*[local-name()='t' and contains(text(),'complex')]]"
                    + "/*[local-name()='rPr']"
                    + "/*[local-name()='szCs'"
                    + " and @*[local-name()='val']='30']"
            )
            .count,
            1
        )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='r']"
                    + "[*[local-name()='t' and contains(text(),'themed')]]"
                    + "/*[local-name()='rPr']"
                    + "/*[local-name()='rFonts'"
                    + " and @*[local-name()='ascii']='Aptos'"
                    + " and @*[local-name()='hAnsi']='Aptos'"
                    + " and @*[local-name()='eastAsia']='MS Mincho'"
                    + " and @*[local-name()='cs']='Arial'"
                    + " and @*[local-name()='asciiTheme']='minorHAnsi'"
                    + " and @*[local-name()='hAnsiTheme']='minorHAnsi'"
                    + " and @*[local-name()='eastAsiaTheme']='minorEastAsia'"
                    + " and @*[local-name()='cstheme']='minorBidi'"
                    + " and @*[local-name()='hint']='eastAsia']"
            )
            .count,
            1
        )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='r']"
                    + "[*[local-name()='t' and contains(text(),'off')]]"
                    + "/*[local-name()='rPr']"
                    + "/*[local-name()='rtl'"
                    + " and @*[local-name()='val']='0']"
            )
            .count,
            1
        )

        let restored =
            try DOCXImporter.text(
                from:
                    data
            )

        XCTAssertEqual(
            restored.string,
            text.string
        )

        XCTAssertEqual(
            restored.attribute(
                .boldWriterRTL,
                at:
                    rtlRange.location,
                effectiveRange:
                    nil
            ) as? Bool,
            true
        )

        XCTAssertEqual(
            restored.attribute(
                .boldWriterComplexScriptBold,
                at:
                    complexRange.location,
                effectiveRange:
                    nil
            ) as? Bool,
            true
        )

        XCTAssertEqual(
            restored.attribute(
                .boldWriterComplexScriptItalic,
                at:
                    complexRange.location,
                effectiveRange:
                    nil
            ) as? Bool,
            true
        )

        XCTAssertEqual(
            (
                restored.attribute(
                    .boldWriterComplexScriptSize,
                    at:
                        complexRange.location,
                    effectiveRange:
                        nil
                ) as? NSNumber
            )?
            .intValue,
            30
        )

        let restoredFonts =
            try XCTUnwrap(
                restored.attribute(
                    .boldWriterRunFonts,
                    at:
                        themedRange.location,
                    effectiveRange:
                        nil
                ) as? WordRunFonts
            )

        XCTAssertTrue(
            restoredFonts.isEqual(
                fonts
            )
        )

        XCTAssertEqual(
            restored.attribute(
                .boldWriterRTL,
                at:
                    offRange.location,
                effectiveRange:
                    nil
            ) as? Bool,
            false
        )

        XCTAssertEqual(
            restored.attribute(
                .boldWriterComplexScriptBold,
                at:
                    offRange.location,
                effectiveRange:
                    nil
            ) as? Bool,
            false
        )

        XCTAssertEqual(
            restored.attribute(
                .boldWriterComplexScriptItalic,
                at:
                    offRange.location,
                effectiveRange:
                    nil
            ) as? Bool,
            false
        )

        XCTAssertNil(
            restored.attribute(
                .boldWriterRTL,
                at:
                    plainRange.location,
                effectiveRange:
                    nil
            )
        )

        XCTAssertNil(
            restored.attribute(
                .boldWriterRunFonts,
                at:
                    plainRange.location,
                effectiveRange:
                    nil
            )
        )

        let secondData =
            try DOCXExporter.data(
                from:
                    restored,
                title:
                    "RTL Complex Script Font Themes Again"
            )

        let secondEntries =
            try DOCXPackage.entries(
                in:
                    secondData
            )

        let secondDocument =
            try DOCXPackage.xml(
                XCTUnwrap(
                    secondEntries.first {
                        $0.path == "word/document.xml"
                    }?
                    .data
                )
            )

        XCTAssertEqual(
            try secondDocument.nodes(
                forXPath:
                    "//*[local-name()='r']"
                    + "[*[local-name()='t' and contains(text(),'themed')]]"
                    + "/*[local-name()='rPr']"
                    + "/*[local-name()='rFonts'"
                    + " and @*[local-name()='eastAsiaTheme']='minorEastAsia'"
                    + " and @*[local-name()='cstheme']='minorBidi']"
            )
            .count,
            1
        )
    }


    func testDOCXRoundTripsWordCharacterStyleIdentityAndInheritance() throws {
        let text =
            NSMutableAttributedString(
                string:
                    "styled plain",
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize:
                                15
                        )
                ]
            )

        let source =
            text.string as NSString

        let styledRange =
            source.range(
                of:
                    "styled"
            )

        let plainRange =
            source.range(
                of:
                    "plain"
            )

        let characterStyle =
            WordCharacterStyle(
                styleID:
                    "EmphasisCustom",
                name:
                    "Custom Emphasis",
                basedOn:
                    "DefaultParagraphFont"
            )

        text.addAttribute(
            .boldWriterCharacterStyle,
            value:
                characterStyle,
            range:
                styledRange
        )

        text.addAttribute(
            .font,
            value:
                NSFontManager.shared.convert(
                    NSFont.systemFont(
                        ofSize:
                            15
                    ),
                    toHaveTrait:
                        .italicFontMask
                ),
            range:
                styledRange
        )

        let data =
            try DOCXExporter.data(
                from:
                    text,
                title:
                    "Character Styles"
            )

        let entries =
            try DOCXPackage.entries(
                in:
                    data
            )

        let document =
            try DOCXPackage.xml(
                XCTUnwrap(
                    entries.first {
                        $0.path
                            == "word/document.xml"
                    }?
                    .data
                )
            )

        let styles =
            try DOCXPackage.xml(
                XCTUnwrap(
                    entries.first {
                        $0.path
                            == "word/styles.xml"
                    }?
                    .data
                )
            )

        XCTAssertEqual(
            try document.nodes(
                forXPath:
                    "//*[local-name()='r']"
                    + "[*[local-name()='t' and contains(text(),'styled')]]"
                    + "/*[local-name()='rPr']"
                    + "/*[local-name()='rStyle'"
                    + " and @*[local-name()='val']='EmphasisCustom']"
            )
            .count,
            1
        )

        XCTAssertEqual(
            try styles.nodes(
                forXPath:
                    "/*[local-name()='styles']"
                    + "/*[local-name()='style'"
                    + " and @*[local-name()='type']='character'"
                    + " and @*[local-name()='styleId']='EmphasisCustom']"
                    + "/*[local-name()='name'"
                    + " and @*[local-name()='val']='Custom Emphasis']"
            )
            .count,
            1
        )

        XCTAssertEqual(
            try styles.nodes(
                forXPath:
                    "/*[local-name()='styles']"
                    + "/*[local-name()='style'"
                    + " and @*[local-name()='type']='character'"
                    + " and @*[local-name()='styleId']='EmphasisCustom']"
                    + "/*[local-name()='basedOn'"
                    + " and @*[local-name()='val']='DefaultParagraphFont']"
            )
            .count,
            1
        )

        let restored =
            try DOCXImporter.text(
                from:
                    data
            )

        XCTAssertEqual(
            restored.string,
            text.string
        )

        let restoredStyle =
            try XCTUnwrap(
                restored.attribute(
                    .boldWriterCharacterStyle,
                    at:
                        styledRange.location,
                    effectiveRange:
                        nil
                ) as? WordCharacterStyle
            )

        XCTAssertEqual(
            restoredStyle.styleID,
            "EmphasisCustom"
        )

        XCTAssertEqual(
            restoredStyle.name,
            "Custom Emphasis"
        )

        XCTAssertEqual(
            restoredStyle.basedOn,
            "DefaultParagraphFont"
        )

        XCTAssertNil(
            restored.attribute(
                .boldWriterCharacterStyle,
                at:
                    plainRange.location,
                effectiveRange:
                    nil
            )
        )

        let secondData =
            try DOCXExporter.data(
                from:
                    restored,
                title:
                    "Character Styles Again"
            )

        let secondEntries =
            try DOCXPackage.entries(
                in:
                    secondData
            )

        let secondDocument =
            try DOCXPackage.xml(
                XCTUnwrap(
                    secondEntries.first {
                        $0.path
                            == "word/document.xml"
                    }?
                    .data
                )
            )

        let secondStyles =
            try DOCXPackage.xml(
                XCTUnwrap(
                    secondEntries.first {
                        $0.path
                            == "word/styles.xml"
                    }?
                    .data
                )
            )

        XCTAssertEqual(
            try secondDocument.nodes(
                forXPath:
                    "//*[local-name()='r']"
                    + "[*[local-name()='t' and contains(text(),'styled')]]"
                    + "/*[local-name()='rPr']"
                    + "/*[local-name()='rStyle'"
                    + " and @*[local-name()='val']='EmphasisCustom']"
            )
            .count,
            1
        )

        XCTAssertEqual(
            try secondStyles.nodes(
                forXPath:
                    "/*[local-name()='styles']"
                    + "/*[local-name()='style'"
                    + " and @*[local-name()='type']='character'"
                    + " and @*[local-name()='styleId']='EmphasisCustom']"
                    + "/*[local-name()='basedOn'"
                    + " and @*[local-name()='val']='DefaultParagraphFont']"
            )
            .count,
            1
        )
    }


    func testDOCXImportsWordDocDefaultsAndInheritedCharacterFormatting() throws {
        let original =
            NSMutableAttributedString(
                string:
                    "default|inherited|override|plain",
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize:
                                15
                        )
                ]
            )

        let source =
            original.string as NSString

        for word in [
            "default",
            "inherited",
            "override"
        ] {
            original.addAttribute(
                .boldWriterNoProof,
                value:
                    false,
                range:
                    source.range(
                        of:
                            word
                    )
            )
        }

        let exported =
            try DOCXExporter.data(
                from:
                    original,
                title:
                    "Inherited Formatting"
            )

        let fileManager =
            FileManager.default

        let root =
            fileManager.temporaryDirectory
                .appendingPathComponent(
                    "BOLDWriterInheritanceTest-"
                    + UUID().uuidString,
                    isDirectory:
                        true
                )

        let sourceURL =
            root.appendingPathComponent(
                "source.docx"
            )

        let unpackedURL =
            root.appendingPathComponent(
                "unpacked",
                isDirectory:
                    true
            )

        let rebuiltURL =
            root.appendingPathComponent(
                "rebuilt.docx"
            )

        try fileManager.createDirectory(
            at:
                root,
            withIntermediateDirectories:
                true
        )

        defer {
            try? fileManager.removeItem(
                at:
                    root
            )
        }

        try exported.write(
            to:
                sourceURL
        )

        try fileManager.createDirectory(
            at:
                unpackedURL,
            withIntermediateDirectories:
                true
        )

        func run(
            _ executable: String,
            _ arguments: [String],
            currentDirectory:
                URL? = nil
        ) throws {
            let process =
                Process()

            process.executableURL =
                URL(
                    fileURLWithPath:
                        executable
                )

            process.arguments =
                arguments

            process.currentDirectoryURL =
                currentDirectory

            process.standardOutput =
                Pipe()

            process.standardError =
                Pipe()

            try process.run()
            process.waitUntilExit()

            XCTAssertEqual(
                process.terminationStatus,
                0
            )

            guard
                process.terminationStatus == 0
            else {
                throw NSError(
                    domain:
                        "BOLDWriterTests",
                    code:
                        Int(
                            process.terminationStatus
                        )
                )
            }
        }

        try run(
            "/usr/bin/unzip",
            [
                "-q",
                sourceURL.path,
                "-d",
                unpackedURL.path
            ]
        )

        let documentURL =
            unpackedURL
                .appendingPathComponent(
                    "word/document.xml"
                )

        let stylesURL =
            unpackedURL
                .appendingPathComponent(
                    "word/styles.xml"
                )

        let documentXML =
            try XMLDocument(
                data:
                    Data(
                        contentsOf:
                            documentURL
                    ),
                options:
                    []
            )

        func child(
            _ element: XMLElement,
            named name: String
        ) -> XMLElement? {
            element.children?
                .compactMap {
                    $0 as? XMLElement
                }
                .first {
                    $0.localName == name
                }
        }

        func runForWord(
            _ word: String
        ) throws -> XMLElement {
            let matches =
                try documentXML.nodes(
                    forXPath:
                        "//*[local-name()='r']"
                    + "[*[local-name()='t' and text()='"
                    + word
                    + "']]"
                )
                .compactMap {
                    $0 as? XMLElement
                }

            XCTAssertEqual(
                matches.count,
                1
            )

            return try XCTUnwrap(
                matches.first
            )
        }

        func setProperties(
            _ run: XMLElement,
            xml:
                String?
        ) throws {
            if let existing =
                child(
                    run,
                    named:
                        "rPr"
                ) {

                existing.detach()
            }

            guard
                let xml
            else {
                return
            }

            let wrapper =
                try XMLDocument(
                    xmlString:
                        "<root xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:rPr>"
                        + xml
                        + "</w:rPr></root>",
                    options:
                        []
                )

            let replacement =
                try XCTUnwrap(
                    wrapper.nodes(
                        forXPath:
                            "/*[local-name()='root']/*[local-name()='rPr']"
                    )
                    .first?
                    .copy()
                    as? XMLElement
                )

            run.insertChild(
                replacement,
                at:
                    0
            )
        }

        try setProperties(
            runForWord(
                "default"
            ),
            xml:
                nil
        )

        try setProperties(
            runForWord(
                "inherited"
            ),
            xml:
                "<w:rStyle w:val=\"ChildProbe\"/>"
        )

        try setProperties(
            runForWord(
                "override"
            ),
            xml:
                "<w:rStyle w:val=\"ChildProbe\"/>"
                + "<w:color w:val=\"0000FF\"/>"
                + "<w:sz w:val=\"44\"/>"
        )

        try documentXML.xmlData(
            options:
                []
        )
        .write(
            to:
                documentURL
        )

        let stylesXML =
            try XMLDocument(
                data:
                    Data(
                        contentsOf:
                            stylesURL
                    ),
                options:
                    []
            )

        let rootElement =
            try XCTUnwrap(
                stylesXML.rootElement()
            )

        func copiedElement(
            _ xml: String
        ) throws -> XMLElement {
            let wrapper =
                try XMLDocument(
                    xmlString:
                        "<root xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">"
                        + xml
                        + "</root>",
                    options:
                        []
                )

            return try XCTUnwrap(
                wrapper.rootElement()?
                    .children?
                    .compactMap {
                        $0 as? XMLElement
                    }
                    .first?
                    .copy()
                    as? XMLElement
            )
        }

        rootElement.insertChild(
            try copiedElement(
                """
                <w:docDefaults>
                  <w:rPrDefault>
                    <w:rPr>
                      <w:color w:val="AA0000"/>
                      <w:sz w:val="28"/>
                    </w:rPr>
                  </w:rPrDefault>
                </w:docDefaults>
                """
            ),
            at:
                0
        )

        rootElement.insertChild(
            try copiedElement(
                """
                <w:style w:type="character" w:styleId="BaseProbe">
                  <w:name w:val="Base Probe"/>
                  <w:rPr>
                    <w:b/>
                    <w:color w:val="006600"/>
                  </w:rPr>
                </w:style>
                """
            ),
            at:
                1
        )

        rootElement.insertChild(
            try copiedElement(
                """
                <w:style w:type="character" w:styleId="ChildProbe">
                  <w:name w:val="Child Probe"/>
                  <w:basedOn w:val="BaseProbe"/>
                  <w:rPr>
                    <w:i/>
                    <w:sz w:val="36"/>
                  </w:rPr>
                </w:style>
                """
            ),
            at:
                2
        )

        try stylesXML.xmlData(
            options:
                []
        )
        .write(
            to:
                stylesURL
        )

        try run(
            "/usr/bin/zip",
            [
                "-q",
                "-r",
                rebuiltURL.path,
                "."
            ],
            currentDirectory:
                unpackedURL
        )

        let imported =
            try DOCXImporter.text(
                from:
                    Data(
                        contentsOf:
                            rebuiltURL
                    )
            )

        XCTAssertEqual(
            imported.string,
            original.string
        )

        let importedSource =
            imported.string as NSString

        func attributes(
            _ word: String
        ) throws -> [NSAttributedString.Key: Any] {
            let range =
                importedSource.range(
                    of:
                        word
                )

            XCTAssertNotEqual(
                range.location,
                NSNotFound
            )

            return imported.attributes(
                at:
                    range.location,
                effectiveRange:
                    nil
            )
        }

        func rgb(
            _ attributes:
                [NSAttributedString.Key: Any]
        ) -> (
            Double,
            Double,
            Double
        )? {
            guard
                let color =
                    (
                        attributes[
                            .foregroundColor
                        ] as? NSColor
                    )?
                    .usingColorSpace(
                        .deviceRGB
                    )
            else {
                return nil
            }

            return (
                Double(color.redComponent),
                Double(color.greenComponent),
                Double(color.blueComponent)
            )
        }

        func traits(
            _ attributes:
                [NSAttributedString.Key: Any]
        ) -> NSFontTraitMask {
            guard
                let font =
                    attributes[
                        .font
                    ] as? NSFont
            else {
                return []
            }

            return NSFontManager.shared
                .traits(
                    of:
                        font
                )
        }

        let defaultAttributes =
            try attributes(
                "default"
            )

        let inheritedAttributes =
            try attributes(
                "inherited"
            )

        let overrideAttributes =
            try attributes(
                "override"
            )

        let defaultFont =
            try XCTUnwrap(
                defaultAttributes[
                    .font
                ] as? NSFont
            )

        XCTAssertEqual(
            defaultFont.pointSize,
            14,
            accuracy:
                0.1
        )

        let defaultRGB =
            try XCTUnwrap(
                rgb(
                    defaultAttributes
                )
            )

        XCTAssertGreaterThan(
            defaultRGB.0,
            defaultRGB.1 + 0.25
        )

        XCTAssertGreaterThan(
            defaultRGB.0,
            defaultRGB.2 + 0.25
        )

        let inheritedFont =
            try XCTUnwrap(
                inheritedAttributes[
                    .font
                ] as? NSFont
            )

        XCTAssertEqual(
            inheritedFont.pointSize,
            18,
            accuracy:
                0.1
        )

        XCTAssertTrue(
            traits(
                inheritedAttributes
            )
            .contains(
                .boldFontMask
            )
        )

        XCTAssertTrue(
            traits(
                inheritedAttributes
            )
            .contains(
                .italicFontMask
            )
        )

        let inheritedRGB =
            try XCTUnwrap(
                rgb(
                    inheritedAttributes
                )
            )

        XCTAssertGreaterThan(
            inheritedRGB.1,
            inheritedRGB.0 + 0.20
        )

        XCTAssertGreaterThan(
            inheritedRGB.1,
            inheritedRGB.2 + 0.20
        )

        let inheritedStyle =
            try XCTUnwrap(
                inheritedAttributes[
                    .boldWriterCharacterStyle
                ] as? WordCharacterStyle
            )

        XCTAssertEqual(
            inheritedStyle.styleID,
            "ChildProbe"
        )

        XCTAssertEqual(
            inheritedStyle.basedOn,
            "BaseProbe"
        )

        let overrideFont =
            try XCTUnwrap(
                overrideAttributes[
                    .font
                ] as? NSFont
            )

        XCTAssertEqual(
            overrideFont.pointSize,
            22,
            accuracy:
                0.1
        )

        XCTAssertTrue(
            traits(
                overrideAttributes
            )
            .contains(
                .boldFontMask
            )
        )

        XCTAssertTrue(
            traits(
                overrideAttributes
            )
            .contains(
                .italicFontMask
            )
        )

        let overrideRGB =
            try XCTUnwrap(
                rgb(
                    overrideAttributes
                )
            )

        XCTAssertGreaterThan(
            overrideRGB.2,
            overrideRGB.0 + 0.25
        )

        XCTAssertGreaterThan(
            overrideRGB.2,
            overrideRGB.1 + 0.25
        )

        let overrideStyle =
            try XCTUnwrap(
                overrideAttributes[
                    .boldWriterCharacterStyle
                ] as? WordCharacterStyle
            )

        XCTAssertEqual(
            overrideStyle.styleID,
            "ChildProbe"
        )
    }


    func testDOCXImportsWordParagraphStyleInheritanceAndPPrDefault() throws {
        let source =
            NSAttributedString(
                string:
                    "default paragraph\n"
                    + "inherited paragraph\n"
                    + "override paragraph\n"
                    + "plain paragraph",
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize:
                                15
                        )
                ]
            )

        let exported =
            try DOCXExporter.data(
                from:
                    source,
                title:
                    "Paragraph Inheritance"
            )

        let fileManager =
            FileManager.default

        let root =
            fileManager.temporaryDirectory
                .appendingPathComponent(
                    "BOLDWriterParagraphInheritance-"
                    + UUID().uuidString,
                    isDirectory:
                        true
                )

        let sourceURL =
            root.appendingPathComponent(
                "source.docx"
            )

        let unpackedURL =
            root.appendingPathComponent(
                "unpacked",
                isDirectory:
                    true
            )

        let rebuiltURL =
            root.appendingPathComponent(
                "rebuilt.docx"
            )

        try fileManager.createDirectory(
            at:
                root,
            withIntermediateDirectories:
                true
        )

        defer {
            try? fileManager.removeItem(
                at:
                    root
            )
        }

        try exported.write(
            to:
                sourceURL
        )

        try fileManager.createDirectory(
            at:
                unpackedURL,
            withIntermediateDirectories:
                true
        )

        func run(
            _ executable: String,
            _ arguments: [String],
            currentDirectory:
                URL? = nil
        ) throws {
            let process =
                Process()

            process.executableURL =
                URL(
                    fileURLWithPath:
                        executable
                )

            process.arguments =
                arguments

            process.currentDirectoryURL =
                currentDirectory

            process.standardOutput =
                Pipe()

            process.standardError =
                Pipe()

            try process.run()
            process.waitUntilExit()

            XCTAssertEqual(
                process.terminationStatus,
                0
            )

            guard process.terminationStatus == 0
            else {
                throw NSError(
                    domain:
                        "BOLDWriterTests",
                    code:
                        Int(
                            process.terminationStatus
                        )
                )
            }
        }

        try run(
            "/usr/bin/unzip",
            [
                "-q",
                sourceURL.path,
                "-d",
                unpackedURL.path
            ]
        )

        let documentURL =
            unpackedURL
                .appendingPathComponent(
                    "word/document.xml"
                )

        let stylesURL =
            unpackedURL
                .appendingPathComponent(
                    "word/styles.xml"
                )

        let documentXML =
            try XMLDocument(
                data:
                    Data(
                        contentsOf:
                            documentURL
                    ),
                options:
                    []
            )

        func child(
            _ element: XMLElement,
            named name: String
        ) -> XMLElement? {
            element.children?
                .compactMap {
                    $0 as? XMLElement
                }
                .first {
                    $0.localName == name
                }
        }

        func paragraph(
            containing value: String
        ) throws -> XMLElement {
            let matches =
                try documentXML.nodes(
                    forXPath:
                        "//*[local-name()='body']/*[local-name()='p']"
                )
                .compactMap {
                    $0 as? XMLElement
                }
                .filter {
                    paragraph in

                    let nodes =
                        (try? paragraph.nodes(
                            forXPath:
                                ".//*[local-name()='t']"
                        ))
                        ?? []

                    return nodes
                        .compactMap {
                            $0.stringValue
                        }
                        .joined()
                        .contains(
                            value
                        )
                }

            XCTAssertEqual(
                matches.count,
                1
            )

            return try XCTUnwrap(
                matches.first
            )
        }

        func setProperties(
            _ paragraph: XMLElement,
            xml:
                String?
        ) throws {
            if let existing =
                child(
                    paragraph,
                    named:
                        "pPr"
                ) {

                existing.detach()
            }

            guard
                let xml
            else {
                return
            }

            let wrapper =
                try XMLDocument(
                    xmlString:
                        "<root xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:pPr>"
                        + xml
                        + "</w:pPr></root>",
                    options:
                        []
                )

            let replacement =
                try XCTUnwrap(
                    wrapper.nodes(
                        forXPath:
                            "/*[local-name()='root']/*[local-name()='pPr']"
                    )
                    .first?
                    .copy()
                    as? XMLElement
                )

            paragraph.insertChild(
                replacement,
                at:
                    0
            )
        }

        try setProperties(
            paragraph(
                containing:
                    "default paragraph"
            ),
            xml:
                nil
        )

        try setProperties(
            paragraph(
                containing:
                    "inherited paragraph"
            ),
            xml:
                "<w:pStyle w:val=\"ChildProbe\"/>"
        )

        try setProperties(
            paragraph(
                containing:
                    "override paragraph"
            ),
            xml:
                "<w:pStyle w:val=\"ChildProbe\"/>"
                + "<w:jc w:val=\"right\"/>"
                + "<w:spacing w:before=\"480\"/>"
                + "<w:keepNext w:val=\"0\"/>"
        )

        try documentXML.xmlData(
            options:
                []
        )
        .write(
            to:
                documentURL
        )

        let stylesXML =
            try XMLDocument(
                data:
                    Data(
                        contentsOf:
                            stylesURL
                    ),
                options:
                    []
            )

        let stylesRoot =
            try XCTUnwrap(
                stylesXML.rootElement()
            )

        func copiedElement(
            _ xml: String
        ) throws -> XMLElement {
            let wrapper =
                try XMLDocument(
                    xmlString:
                        "<root xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">"
                        + xml
                        + "</root>",
                    options:
                        []
                )

            return try XCTUnwrap(
                wrapper.rootElement()?
                    .children?
                    .compactMap {
                        $0 as? XMLElement
                    }
                    .first?
                    .copy()
                    as? XMLElement
            )
        }

        stylesRoot.insertChild(
            try copiedElement(
                """
                <w:docDefaults>
                  <w:pPrDefault>
                    <w:pPr>
                      <w:jc w:val="left"/>
                      <w:widowControl/>
                    </w:pPr>
                  </w:pPrDefault>
                </w:docDefaults>
                """
            ),
            at:
                0
        )

        stylesRoot.insertChild(
            try copiedElement(
                """
                <w:style w:type="paragraph" w:styleId="BaseProbe">
                  <w:name w:val="Base Probe"/>
                  <w:pPr>
                    <w:jc w:val="center"/>
                    <w:keepNext/>
                  </w:pPr>
                </w:style>
                """
            ),
            at:
                1
        )

        stylesRoot.insertChild(
            try copiedElement(
                """
                <w:style w:type="paragraph" w:styleId="ChildProbe">
                  <w:name w:val="Child Probe"/>
                  <w:basedOn w:val="BaseProbe"/>
                  <w:pPr>
                    <w:spacing w:before="240"/>
                    <w:keepLines/>
                  </w:pPr>
                </w:style>
                """
            ),
            at:
                2
        )

        try stylesXML.xmlData(
            options:
                []
        )
        .write(
            to:
                stylesURL
        )

        try run(
            "/usr/bin/zip",
            [
                "-q",
                "-r",
                rebuiltURL.path,
                "."
            ],
            currentDirectory:
                unpackedURL
        )

        let imported =
            try DOCXImporter.text(
                from:
                    Data(
                        contentsOf:
                            rebuiltURL
                    )
            )

        XCTAssertEqual(
            imported.string,
            source.string
        )

        let importedSource =
            imported.string as NSString

        func attributes(
            containing value: String
        ) throws -> [NSAttributedString.Key: Any] {
            let range =
                importedSource.range(
                    of:
                        value
                )

            XCTAssertNotEqual(
                range.location,
                NSNotFound
            )

            return imported.attributes(
                at:
                    range.location,
                effectiveRange:
                    nil
            )
        }

        let defaultAttributes =
            try attributes(
                containing:
                    "default paragraph"
            )

        let inheritedAttributes =
            try attributes(
                containing:
                    "inherited paragraph"
            )

        let overrideAttributes =
            try attributes(
                containing:
                    "override paragraph"
            )

        let defaultStyle =
            try XCTUnwrap(
                defaultAttributes[
                    .paragraphStyle
                ] as? NSParagraphStyle
            )

        XCTAssertTrue(
            defaultStyle.alignment == .left
                || defaultStyle.alignment == .natural
        )

        XCTAssertEqual(
            defaultAttributes[
                .boldWriterWidowControl
            ] as? Bool,
            true
        )

        let inheritedStyle =
            try XCTUnwrap(
                inheritedAttributes[
                    .paragraphStyle
                ] as? NSParagraphStyle
            )

        XCTAssertEqual(
            inheritedStyle.alignment,
            .center
        )

        XCTAssertEqual(
            inheritedStyle.paragraphSpacingBefore,
            12,
            accuracy:
                0.2
        )

        XCTAssertEqual(
            inheritedAttributes[
                .boldWriterKeepWithNext
            ] as? Bool,
            true
        )

        XCTAssertEqual(
            inheritedAttributes[
                .boldWriterKeepLinesTogether
            ] as? Bool,
            true
        )

        XCTAssertEqual(
            inheritedAttributes[
                .boldWriterWidowControl
            ] as? Bool,
            true
        )

        let overrideStyle =
            try XCTUnwrap(
                overrideAttributes[
                    .paragraphStyle
                ] as? NSParagraphStyle
            )

        XCTAssertEqual(
            overrideStyle.alignment,
            .right
        )

        XCTAssertEqual(
            overrideStyle.paragraphSpacingBefore,
            24,
            accuracy:
                0.2
        )

        XCTAssertNotEqual(
            overrideAttributes[
                .boldWriterKeepWithNext
            ] as? Bool,
            true
        )

        XCTAssertEqual(
            overrideAttributes[
                .boldWriterKeepLinesTogether
            ] as? Bool,
            true
        )

        XCTAssertEqual(
            overrideAttributes[
                .boldWriterWidowControl
            ] as? Bool,
            true
        )

        // A custom Word style based on another style stays
        // visually inherited only; it must not become a BOLD
        // semantic paragraph style merely through basedOn.
        XCTAssertNil(
            inheritedAttributes[
                .boldWriterStyle
            ]
        )
    }


    func testDOCXImportsParagraphStyleRunPropertiesWithCorrectPrecedence() throws {
        let source =
            NSMutableAttributedString(
                string:
                    "paragraph-style|character-style|direct",
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize:
                                15
                        )
                ]
            )

        // Force three distinct exported runs without changing visible text.
        let sourceString =
            source.string as NSString

        source.addAttribute(
            .boldWriterNoProof,
            value:
                false,
            range:
                sourceString.range(
                    of:
                        "paragraph-style"
                )
        )

        source.addAttribute(
            .boldWriterNoProof,
            value:
                true,
            range:
                sourceString.range(
                    of:
                        "character-style"
                )
        )

        let exported =
            try DOCXExporter.data(
                from:
                    source,
                title:
                    "Paragraph Style Run Properties"
            )

        let fileManager =
            FileManager.default

        let root =
            fileManager.temporaryDirectory
                .appendingPathComponent(
                    "BOLDWriterParagraphRunStyle-"
                    + UUID().uuidString,
                    isDirectory:
                        true
                )

        let sourceURL =
            root.appendingPathComponent(
                "source.docx"
            )

        let unpackedURL =
            root.appendingPathComponent(
                "unpacked",
                isDirectory:
                    true
            )

        let rebuiltURL =
            root.appendingPathComponent(
                "rebuilt.docx"
            )

        try fileManager.createDirectory(
            at:
                root,
            withIntermediateDirectories:
                true
        )

        defer {
            try? fileManager.removeItem(
                at:
                    root
            )
        }

        try exported.write(
            to:
                sourceURL
        )

        try fileManager.createDirectory(
            at:
                unpackedURL,
            withIntermediateDirectories:
                true
        )

        func run(
            _ executable: String,
            _ arguments: [String],
            currentDirectory:
                URL? = nil
        ) throws {
            let process =
                Process()

            process.executableURL =
                URL(
                    fileURLWithPath:
                        executable
                )

            process.arguments =
                arguments

            process.currentDirectoryURL =
                currentDirectory
            process.standardOutput =
                Pipe()
            process.standardError =
                Pipe()

            try process.run()
            process.waitUntilExit()

            XCTAssertEqual(
                process.terminationStatus,
                0
            )

            guard
                process.terminationStatus == 0
            else {
                throw NSError(
                    domain:
                        "BOLDWriterTests",
                    code:
                        Int(
                            process.terminationStatus
                        )
                )
            }
        }

        try run(
            "/usr/bin/unzip",
            [
                "-q",
                sourceURL.path,
                "-d",
                unpackedURL.path
            ]
        )

        let documentURL =
            unpackedURL
                .appendingPathComponent(
                    "word/document.xml"
                )

        let stylesURL =
            unpackedURL
                .appendingPathComponent(
                    "word/styles.xml"
                )

        let documentXML =
            try XMLDocument(
                data:
                    Data(
                        contentsOf:
                            documentURL
                    ),
                options:
                    []
            )

        let paragraphNodes =
            try documentXML.nodes(
                forXPath:
                    "//*[local-name()='body']/*[local-name()='p']"
            )

        let paragraph =
            try XCTUnwrap(
                paragraphNodes.first
                    as? XMLElement
            )

        if let oldProperties =
            paragraph.children?
                .compactMap({
                    $0 as? XMLElement
                })
                .first(where: {
                    $0.localName
                        == "pPr"
                }) {

            oldProperties.detach()
        }

        let pWrapper =
            try XMLDocument(
                xmlString:
                    "<root xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">"
                    + "<w:pPr><w:pStyle w:val=\"ChildParagraph\"/></w:pPr>"
                    + "</root>",
                options:
                    []
            )

        let pNodes =
            try pWrapper.nodes(
                forXPath:
                    "/*[local-name()='root']/*[local-name()='pPr']"
            )

        let paragraphProperties =
            try XCTUnwrap(
                pNodes.first?
                    .copy()
                    as? XMLElement
            )

        paragraph.insertChild(
            paragraphProperties,
            at:
                0
        )

        let runNodes =
            try paragraph.nodes(
                forXPath:
                    "./*[local-name()='r']"
            )

        let runs =
            runNodes.compactMap {
                $0 as? XMLElement
            }

        func text(
            of run: XMLElement
        ) -> String {
            let nodes =
                (try? run.nodes(
                    forXPath:
                        ".//*[local-name()='t']"
                ))
                ?? []

            return nodes
                .compactMap {
                    $0.stringValue
                }
                .joined()
        }

        func runContaining(
            _ value: String
        ) throws -> XMLElement {
            let matches =
                runs.filter {
                    text(
                        of:
                            $0
                    )
                    .contains(
                        value
                    )
                }

            XCTAssertEqual(
                matches.count,
                1
            )

            return try XCTUnwrap(
                matches.first
            )
        }

        func replaceProperties(
            in run: XMLElement,
            with value: String?
        ) throws {
            if let old =
                run.children?
                    .compactMap({
                        $0 as? XMLElement
                    })
                    .first(where: {
                        $0.localName
                            == "rPr"
                    }) {

                old.detach()
            }

            guard
                let value
            else {
                return
            }

            let wrapper =
                try XMLDocument(
                    xmlString:
                        "<root xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">"
                        + "<w:rPr>"
                        + value
                        + "</w:rPr>"
                        + "</root>",
                    options:
                        []
                )

            let nodes =
                try wrapper.nodes(
                    forXPath:
                        "/*[local-name()='root']/*[local-name()='rPr']"
                )

            let replacement =
                try XCTUnwrap(
                    nodes.first?
                        .copy()
                        as? XMLElement
                )

            run.insertChild(
                replacement,
                at:
                    0
            )
        }

        try replaceProperties(
            in:
                runContaining(
                    "paragraph-style"
                ),
            with:
                nil
        )

        try replaceProperties(
            in:
                runContaining(
                    "character-style"
                ),
            with:
                "<w:rStyle w:val=\"CharacterProbe\"/>"
        )

        try replaceProperties(
            in:
                runContaining(
                    "direct"
                ),
            with:
                "<w:rStyle w:val=\"CharacterProbe\"/>"
                + "<w:color w:val=\"FF0000\"/>"
                + "<w:sz w:val=\"44\"/>"
        )

        try documentXML.xmlData(
            options:
                []
        )
        .write(
            to:
                documentURL
        )

        let stylesXML =
            try XMLDocument(
                data:
                    Data(
                        contentsOf:
                            stylesURL
                    ),
                options:
                    []
            )

        let stylesRoot =
            try XCTUnwrap(
                stylesXML.rootElement()
            )

        func copiedElement(
            _ value: String
        ) throws -> XMLElement {
            let wrapper =
                try XMLDocument(
                    xmlString:
                        "<root xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">"
                        + value
                        + "</root>",
                    options:
                        []
                )

            let children =
                wrapper.rootElement()?
                    .children?
                    .compactMap {
                        $0 as? XMLElement
                    }
                    ?? []

            return try XCTUnwrap(
                children.first?
                    .copy()
                    as? XMLElement
            )
        }

        stylesRoot.insertChild(
            try copiedElement(
                """
                <w:style w:type="paragraph" w:styleId="BaseParagraph">
                  <w:name w:val="Base Paragraph"/>
                  <w:rPr>
                    <w:b/>
                    <w:color w:val="006600"/>
                  </w:rPr>
                </w:style>
                """
            ),
            at:
                0
        )

        stylesRoot.insertChild(
            try copiedElement(
                """
                <w:style w:type="paragraph" w:styleId="ChildParagraph">
                  <w:name w:val="Child Paragraph"/>
                  <w:basedOn w:val="BaseParagraph"/>
                  <w:rPr>
                    <w:i/>
                    <w:sz w:val="36"/>
                  </w:rPr>
                </w:style>
                """
            ),
            at:
                1
        )

        stylesRoot.insertChild(
            try copiedElement(
                """
                <w:style w:type="character" w:styleId="CharacterProbe">
                  <w:name w:val="Character Probe"/>
                  <w:rPr>
                    <w:color w:val="0000FF"/>
                    <w:sz w:val="40"/>
                  </w:rPr>
                </w:style>
                """
            ),
            at:
                2
        )

        try stylesXML.xmlData(
            options:
                []
        )
        .write(
            to:
                stylesURL
        )

        try run(
            "/usr/bin/zip",
            [
                "-q",
                "-r",
                rebuiltURL.path,
                "."
            ],
            currentDirectory:
                unpackedURL
        )

        let imported =
            try DOCXImporter.text(
                from:
                    Data(
                        contentsOf:
                            rebuiltURL
                    )
            )

        let importedSource =
            imported.string as NSString

        func attributes(
            _ value: String
        ) throws -> [NSAttributedString.Key: Any] {
            let range =
                importedSource.range(
                    of:
                        value
                )

            XCTAssertNotEqual(
                range.location,
                NSNotFound
            )

            return imported.attributes(
                at:
                    range.location,
                effectiveRange:
                    nil
            )
        }

        func font(
            _ attributes:
                [NSAttributedString.Key: Any]
        ) throws -> NSFont {
            try XCTUnwrap(
                attributes[
                    .font
                ] as? NSFont
            )
        }

        func traits(
            _ attributes:
                [NSAttributedString.Key: Any]
        ) throws -> NSFontTraitMask {
            NSFontManager.shared
                .traits(
                    of:
                        try font(
                            attributes
                        )
                )
        }

        func dominantChannel(
            _ attributes:
                [NSAttributedString.Key: Any]
        ) throws -> Int {
            let color =
                try XCTUnwrap(
                    (
                        attributes[
                            .foregroundColor
                        ] as? NSColor
                    )?
                    .usingColorSpace(
                        .deviceRGB
                    )
                )

            let red =
                color.redComponent

            let green =
                color.greenComponent

            let blue =
                color.blueComponent

            if red >= green
                && red >= blue {

                return 0
            }

            if green >= red
                && green >= blue {

                return 1
            }

            return 2
        }

        let paragraphAttributes =
            try attributes(
                "paragraph-style"
            )

        XCTAssertEqual(
            try font(
                paragraphAttributes
            )
            .pointSize,
            18,
            accuracy:
                0.1
        )

        XCTAssertTrue(
            try traits(
                paragraphAttributes
            )
            .contains(
                .boldFontMask
            )
        )

        XCTAssertTrue(
            try traits(
                paragraphAttributes
            )
            .contains(
                .italicFontMask
            )
        )

        XCTAssertEqual(
            try dominantChannel(
                paragraphAttributes
            ),
            1
        )

        let characterAttributes =
            try attributes(
                "character-style"
            )

        XCTAssertEqual(
            try font(
                characterAttributes
            )
            .pointSize,
            20,
            accuracy:
                0.1
        )

        XCTAssertTrue(
            try traits(
                characterAttributes
            )
            .contains(
                .boldFontMask
            )
        )

        XCTAssertTrue(
            try traits(
                characterAttributes
            )
            .contains(
                .italicFontMask
            )
        )

        XCTAssertEqual(
            try dominantChannel(
                characterAttributes
            ),
            2
        )

        let directAttributes =
            try attributes(
                "direct"
            )

        XCTAssertEqual(
            try font(
                directAttributes
            )
            .pointSize,
            22,
            accuracy:
                0.1
        )

        XCTAssertTrue(
            try traits(
                directAttributes
            )
            .contains(
                .boldFontMask
            )
        )

        XCTAssertTrue(
            try traits(
                directAttributes
            )
            .contains(
                .italicFontMask
            )
        )

        XCTAssertEqual(
            try dominantChannel(
                directAttributes
            ),
            0
        )
    }

    func testDOCXRoundTripsLinkedWordCharacterStyle() throws {
        let source =
            NSMutableAttributedString(
                string:
                    "linked style",
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize:
                                15
                        )
                ]
            )

        let style =
            WordCharacterStyle(
                styleID:
                    "LinkedEmphasis",
                name:
                    "Linked Emphasis",
                basedOn:
                    nil,
                linkedStyleID:
                    "Heading1"
            )

        source.addAttribute(
            .boldWriterCharacterStyle,
            value:
                style,
            range:
                NSRange(
                    location:
                        0,
                    length:
                        source.length
                )
        )

        let data =
            try DOCXExporter.data(
                from:
                    source,
                title:
                    "Linked Character Style"
            )

        let entries =
            try DOCXPackage.entries(
                in:
                    data
            )

        let stylesEntry =
            entries.first {
                $0.path
                    == "word/styles.xml"
            }

        let stylesData =
            try XCTUnwrap(
                stylesEntry?
                    .data
            )

        let stylesXML =
            try DOCXPackage.xml(
                stylesData
            )

        let linkedNodes =
            try stylesXML.nodes(
                forXPath:
                    "/*[local-name()='styles']"
                    + "/*[local-name()='style'"
                    + " and @*[local-name()='type']='character'"
                    + " and @*[local-name()='styleId']='LinkedEmphasis']"
                    + "/*[local-name()='link'"
                    + " and @*[local-name()='val']='Heading1']"
            )

        XCTAssertEqual(
            linkedNodes.count,
            1
        )

        let imported =
            try DOCXImporter.text(
                from:
                    data
            )

        let importedStyle =
            try XCTUnwrap(
                imported.attribute(
                    .boldWriterCharacterStyle,
                    at:
                        0,
                    effectiveRange:
                        nil
                )
                    as? WordCharacterStyle
            )

        XCTAssertEqual(
            importedStyle.styleID,
            "LinkedEmphasis"
        )

        XCTAssertEqual(
            importedStyle.name,
            "Linked Emphasis"
        )

        XCTAssertEqual(
            importedStyle.linkedStyleID,
            "Heading1"
        )
    }


    func testDOCXRoundTripsCustomWordParagraphStyleIdentityAndLink() throws {
        let source =
            NSAttributedString(
                string:
                    "custom paragraph",
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize:
                                15
                        )
                ]
            )

        let initial =
            try DOCXExporter.data(
                from:
                    source,
                title:
                    "Custom Paragraph Style"
            )

        let fileManager =
            FileManager.default

        let root =
            fileManager.temporaryDirectory
                .appendingPathComponent(
                    "BOLDWriterCustomParagraphStyle-"
                    + UUID().uuidString,
                    isDirectory:
                        true
                )

        let sourceURL =
            root.appendingPathComponent(
                "source.docx"
            )

        let unpackedURL =
            root.appendingPathComponent(
                "unpacked",
                isDirectory:
                    true
            )

        let customURL =
            root.appendingPathComponent(
                "custom.docx"
            )

        defer {
            try? fileManager.removeItem(
                at:
                    root
            )
        }

        try fileManager.createDirectory(
            at:
                root,
            withIntermediateDirectories:
                true
        )

        try initial.write(
            to:
                sourceURL
        )

        try fileManager.createDirectory(
            at:
                unpackedURL,
            withIntermediateDirectories:
                true
        )

        func run(
            _ executable: String,
            _ arguments: [String],
            currentDirectory:
                URL? = nil
        ) throws {
            let process =
                Process()

            process.executableURL =
                URL(
                    fileURLWithPath:
                        executable
                )

            process.arguments =
                arguments

            process.currentDirectoryURL =
                currentDirectory
            process.standardOutput =
                Pipe()
            process.standardError =
                Pipe()

            try process.run()
            process.waitUntilExit()

            XCTAssertEqual(
                process.terminationStatus,
                0
            )

            guard
                process.terminationStatus == 0
            else {
                throw NSError(
                    domain:
                        "BOLDWriterTests",
                    code:
                        Int(
                            process.terminationStatus
                        )
                )
            }
        }

        try run(
            "/usr/bin/unzip",
            [
                "-q",
                sourceURL.path,
                "-d",
                unpackedURL.path
            ]
        )

        let documentURL =
            unpackedURL
                .appendingPathComponent(
                    "word/document.xml"
                )

        let stylesURL =
            unpackedURL
                .appendingPathComponent(
                    "word/styles.xml"
                )

        let documentXML =
            try XMLDocument(
                data:
                    Data(
                        contentsOf:
                            documentURL
                    ),
                options:
                    []
            )

        let paragraphs =
            try documentXML.nodes(
                forXPath:
                    "//*[local-name()='body']/*[local-name()='p']"
            )
            .compactMap {
                $0 as? XMLElement
            }

        let paragraph =
            try XCTUnwrap(
                paragraphs.first
            )

        if let oldProperties =
            paragraph.children?
                .compactMap({
                    $0 as? XMLElement
                })
                .first(where: {
                    $0.localName
                        == "pPr"
                }) {

            oldProperties.detach()
        }

        let pWrapper =
            try XMLDocument(
                xmlString:
                    "<root xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">"
                    + "<w:pPr><w:pStyle w:val=\"MyCustomParagraph\"/></w:pPr>"
                    + "</root>",
                options:
                    []
            )

        let pNodes =
            try pWrapper.nodes(
                forXPath:
                    "/*[local-name()='root']/*[local-name()='pPr']"
            )

        let properties =
            try XCTUnwrap(
                pNodes.first?
                    .copy()
                    as? XMLElement
            )

        paragraph.insertChild(
            properties,
            at:
                0
        )

        try documentXML.xmlData(
            options:
                []
        )
        .write(
            to:
                documentURL
        )

        let stylesXML =
            try XMLDocument(
                data:
                    Data(
                        contentsOf:
                            stylesURL
                    ),
                options:
                    []
            )

        let stylesRoot =
            try XCTUnwrap(
                stylesXML.rootElement()
            )

        let wrapper =
            try XMLDocument(
                xmlString:
                    """
                    <root xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
                      <w:style w:type="paragraph" w:styleId="MyCustomParagraph">
                        <w:name w:val="My Custom Paragraph"/>
                        <w:basedOn w:val="Normal"/>
                        <w:link w:val="MyCustomCharacter"/>
                      </w:style>
                    </root>
                    """,
                options:
                    []
            )

        let customDefinition =
            try XCTUnwrap(
                wrapper.rootElement()?
                    .children?
                    .compactMap {
                        $0 as? XMLElement
                    }
                    .first?
                    .copy()
                    as? XMLElement
            )

        stylesRoot.addChild(
            customDefinition
        )

        try stylesXML.xmlData(
            options:
                []
        )
        .write(
            to:
                stylesURL
        )

        try run(
            "/usr/bin/zip",
            [
                "-q",
                "-r",
                customURL.path,
                "."
            ],
            currentDirectory:
                unpackedURL
        )

        let imported =
            try DOCXImporter.text(
                from:
                    Data(
                        contentsOf:
                            customURL
                    )
            )

        let importedStyle =
            try XCTUnwrap(
                imported.attribute(
                    .boldWriterParagraphStyle,
                    at:
                        0,
                    effectiveRange:
                        nil
                )
                    as? WordParagraphStyle
            )

        XCTAssertEqual(
            importedStyle.styleID,
            "MyCustomParagraph"
        )

        XCTAssertEqual(
            importedStyle.name,
            "My Custom Paragraph"
        )

        XCTAssertEqual(
            importedStyle.basedOn,
            "Normal"
        )

        XCTAssertEqual(
            importedStyle.linkedStyleID,
            "MyCustomCharacter"
        )

        XCTAssertNil(
            imported.attribute(
                .boldWriterStyle,
                at:
                    0,
                effectiveRange:
                    nil
            )
        )

        let roundTrip =
            try DOCXExporter.data(
                from:
                    imported,
                title:
                    "Custom Paragraph Style Round Trip"
            )

        let entries =
            try DOCXPackage.entries(
                in:
                    roundTrip
            )

        let roundTripDocument =
            try XCTUnwrap(
                entries.first {
                    $0.path
                        == "word/document.xml"
                }?
                .data
            )

        let roundTripStyles =
            try XCTUnwrap(
                entries.first {
                    $0.path
                        == "word/styles.xml"
                }?
                .data
            )

        let roundTripDocumentXML =
            try DOCXPackage.xml(
                roundTripDocument
            )

        let pStyleNodes =
            try roundTripDocumentXML.nodes(
                forXPath:
                    "//*[local-name()='body']"
                    + "//*[local-name()='pPr']"
                    + "/*[local-name()='pStyle'"
                    + " and @*[local-name()='val']='MyCustomParagraph']"
            )

        XCTAssertEqual(
            pStyleNodes.count,
            1
        )

        let roundTripStylesXML =
            try DOCXPackage.xml(
                roundTripStyles
            )

        let styleNodes =
            try roundTripStylesXML.nodes(
                forXPath:
                    "/*[local-name()='styles']"
                    + "/*[local-name()='style'"
                    + " and @*[local-name()='type']='paragraph'"
                    + " and @*[local-name()='styleId']='MyCustomParagraph']"
            )

        XCTAssertEqual(
            styleNodes.count,
            1
        )

        let nameNodes =
            try roundTripStylesXML.nodes(
                forXPath:
                    "/*[local-name()='styles']"
                    + "/*[local-name()='style'"
                    + " and @*[local-name()='styleId']='MyCustomParagraph']"
                    + "/*[local-name()='name'"
                    + " and @*[local-name()='val']='My Custom Paragraph']"
            )

        XCTAssertEqual(
            nameNodes.count,
            1
        )

        let basedOnNodes =
            try roundTripStylesXML.nodes(
                forXPath:
                    "/*[local-name()='styles']"
                    + "/*[local-name()='style'"
                    + " and @*[local-name()='styleId']='MyCustomParagraph']"
                    + "/*[local-name()='basedOn'"
                    + " and @*[local-name()='val']='Normal']"
            )

        XCTAssertEqual(
            basedOnNodes.count,
            1
        )

        let linkNodes =
            try roundTripStylesXML.nodes(
                forXPath:
                    "/*[local-name()='styles']"
                    + "/*[local-name()='style'"
                    + " and @*[local-name()='styleId']='MyCustomParagraph']"
                    + "/*[local-name()='link'"
                    + " and @*[local-name()='val']='MyCustomCharacter']"
            )

        XCTAssertEqual(
            linkNodes.count,
            1
        )
    }


    func testDOCXPreservesTransitiveWordStyleDependencyGraph() throws {
        let source =
            NSAttributedString(
                string:
                    "dependency graph",
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize:
                                15
                        )
                ]
            )

        let initial =
            try DOCXExporter.data(
                from:
                    source,
                title:
                    "Style Dependency Graph"
            )

        let fm =
            FileManager.default

        let root =
            fm.temporaryDirectory
                .appendingPathComponent(
                    "BOLDWriterStyleGraph-"
                    + UUID().uuidString,
                    isDirectory:
                        true
                )

        let sourceURL =
            root.appendingPathComponent(
                "source.docx"
            )

        let unpacked =
            root.appendingPathComponent(
                "unpacked",
                isDirectory:
                    true
            )

        let modified =
            root.appendingPathComponent(
                "modified.docx"
            )

        try fm.createDirectory(
            at:
                root,
            withIntermediateDirectories:
                true
        )

        defer {
            try? fm.removeItem(
                at:
                    root
            )
        }

        try initial.write(
            to:
                sourceURL
        )

        try fm.createDirectory(
            at:
                unpacked,
            withIntermediateDirectories:
                true
        )

        func run(
            _ path: String,
            _ args: [String],
            cwd: URL? = nil
        ) throws {
            let process =
                Process()

            process.executableURL =
                URL(
                    fileURLWithPath:
                        path
                )

            process.arguments =
                args

            process.currentDirectoryURL =
                cwd
            process.standardOutput =
                Pipe()
            process.standardError =
                Pipe()

            try process.run()
            process.waitUntilExit()

            XCTAssertEqual(
                process.terminationStatus,
                0
            )
        }

        try run(
            "/usr/bin/unzip",
            [
                "-q",
                sourceURL.path,
                "-d",
                unpacked.path
            ]
        )

        let documentURL =
            unpacked.appendingPathComponent(
                "word/document.xml"
            )

        let stylesURL =
            unpacked.appendingPathComponent(
                "word/styles.xml"
            )

        let document =
            try XMLDocument(
                data:
                    Data(
                        contentsOf:
                            documentURL
                    ),
                options:
                    []
            )

        let paragraph =
            try XCTUnwrap(
                try document.nodes(
                    forXPath:
                        "//*[local-name()='body']/*[local-name()='p']"
                )
                .first
                    as? XMLElement
            )

        if let old =
            paragraph.children?
                .compactMap({
                    $0 as? XMLElement
                })
                .first(where: {
                    $0.localName == "pPr"
                }) {

            old.detach()
        }

        let pWrapper =
            try XMLDocument(
                xmlString:
                    "<root xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">"
                    + "<w:pPr><w:pStyle w:val=\"ChildParagraph\"/></w:pPr>"
                    + "</root>",
                options:
                    []
            )

        let pPr =
            try XCTUnwrap(
                try pWrapper.nodes(
                    forXPath:
                        "/*[local-name()='root']/*[local-name()='pPr']"
                )
                .first?
                .copy()
                    as? XMLElement
            )

        paragraph.insertChild(
            pPr,
            at:
                0
        )

        try document.xmlData(
            options:
                []
        )
        .write(
            to:
                documentURL
        )

        let styles =
            try XMLDocument(
                data:
                    Data(
                        contentsOf:
                            stylesURL
                    ),
                options:
                    []
            )

        let rootElement =
            try XCTUnwrap(
                styles.rootElement()
            )

        func addStyle(
            _ xml: String
        ) throws {
            let wrapper =
                try XMLDocument(
                    xmlString:
                        "<root xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">"
                        + xml
                        + "</root>",
                    options:
                        []
                )

            let element =
                try XCTUnwrap(
                    wrapper.rootElement()?
                        .children?
                        .compactMap {
                            $0 as? XMLElement
                        }
                        .first?
                        .copy()
                        as? XMLElement
                )

            rootElement.addChild(
                element
            )
        }

        try addStyle(
            """
            <w:style w:type="paragraph" w:styleId="GrandparentParagraph">
              <w:name w:val="Grandparent Paragraph"/>
            </w:style>
            """
        )

        try addStyle(
            """
            <w:style w:type="paragraph" w:styleId="ParentParagraph">
              <w:name w:val="Parent Paragraph"/>
              <w:basedOn w:val="GrandparentParagraph"/>
            </w:style>
            """
        )

        try addStyle(
            """
            <w:style w:type="paragraph" w:styleId="ChildParagraph">
              <w:name w:val="Child Paragraph"/>
              <w:basedOn w:val="ParentParagraph"/>
              <w:link w:val="ChildCharacter"/>
              <w:next w:val="ParentParagraph"/>
            </w:style>
            """
        )

        try addStyle(
            """
            <w:style w:type="character" w:styleId="BaseCharacter">
              <w:name w:val="Base Character"/>
            </w:style>
            """
        )

        try addStyle(
            """
            <w:style w:type="character" w:styleId="ChildCharacter">
              <w:name w:val="Child Character"/>
              <w:basedOn w:val="BaseCharacter"/>
              <w:link w:val="ChildParagraph"/>
            </w:style>
            """
        )

        try styles.xmlData(
            options:
                []
        )
        .write(
            to:
                stylesURL
        )

        try run(
            "/usr/bin/zip",
            [
                "-q",
                "-r",
                modified.path,
                "."
            ],
            cwd:
                unpacked
        )

        let imported =
            try DOCXImporter.text(
                from:
                    Data(
                        contentsOf:
                            modified
                    )
            )

        let importedStyle =
            try XCTUnwrap(
                imported.attribute(
                    .boldWriterParagraphStyle,
                    at:
                        0,
                    effectiveRange:
                        nil
                )
                    as? WordParagraphStyle
            )

        XCTAssertEqual(
            importedStyle.styleID,
            "ChildParagraph"
        )

        XCTAssertEqual(
            importedStyle.basedOn,
            "ParentParagraph"
        )

        XCTAssertEqual(
            importedStyle.linkedStyleID,
            "ChildCharacter"
        )

        XCTAssertEqual(
            importedStyle.nextStyleID,
            "ParentParagraph"
        )

        let dependencyIDs =
            Set(
                importedStyle.dependencies.map {
                    $0.styleID
                }
            )

        XCTAssertEqual(
            dependencyIDs,
            Set([
                "ParentParagraph",
                "GrandparentParagraph",
                "ChildCharacter",
                "BaseCharacter"
            ])
        )

        let roundTrip =
            try DOCXExporter.data(
                from:
                    imported,
                title:
                    "Style Dependency Graph Round Trip"
            )

        let entries =
            try DOCXPackage.entries(
                in:
                    roundTrip
            )

        let styleData =
            try XCTUnwrap(
                entries.first {
                    $0.path
                        == "word/styles.xml"
                }?
                .data
            )

        let roundTripStyles =
            try DOCXPackage.xml(
                styleData
            )

        for styleID in [
            "ChildParagraph",
            "ParentParagraph",
            "GrandparentParagraph",
            "ChildCharacter",
            "BaseCharacter",
        ] {
            let nodes =
                try roundTripStyles.nodes(
                    forXPath:
                        "/*[local-name()='styles']"
                        + "/*[local-name()='style'"
                        + " and @*[local-name()='styleId']='"
                        + styleID
                        + "']"
                )

            XCTAssertEqual(
                nodes.count,
                1,
                styleID
            )
        }

        let childNext =
            try roundTripStyles.nodes(
                forXPath:
                    "/*[local-name()='styles']"
                    + "/*[local-name()='style'"
                    + " and @*[local-name()='styleId']='ChildParagraph']"
                    + "/*[local-name()='next'"
                    + " and @*[local-name()='val']='ParentParagraph']"
            )

        XCTAssertEqual(
            childNext.count,
            1
        )

        let characterLink =
            try roundTripStyles.nodes(
                forXPath:
                    "/*[local-name()='styles']"
                    + "/*[local-name()='style'"
                    + " and @*[local-name()='styleId']='ChildCharacter']"
                    + "/*[local-name()='link'"
                    + " and @*[local-name()='val']='ChildParagraph']"
            )

        XCTAssertEqual(
            characterLink.count,
            1
        )
    }


    func testDOCXRoundTripsExtendedWordRunMetadataCluster() throws {
        let source =
            NSMutableAttributedString(
                string:
                    "extended Word run metadata",
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize:
                                15
                        )
                ]
            )

        let fullRange =
            NSRange(
                location:
                    0,
                length:
                    source.length
            )

        source.addAttribute(
            .boldWriterLanguage,
            value:
                "en-US",
            range:
                fullRange
        )

        source.addAttribute(
            .boldWriterWordLanguage,
            value:
                WordLanguage(
                    value:
                        "en-US",
                    eastAsia:
                        "ja-JP",
                    bidi:
                        "ar-SA"
                ),
            range:
                fullRange
        )

        source.addAttribute(
            .boldWriterComplexScript,
            value:
                true,
            range:
                fullRange
        )

        source.addAttribute(
            .boldWriterKernThreshold,
            value:
                24,
            range:
                fullRange
        )

        source.addAttribute(
            .boldWriterEmphasis,
            value:
                "dot",
            range:
                fullRange
        )

        source.addAttribute(
            .boldWriterSpecVanish,
            value:
                true,
            range:
                fullRange
        )

        source.addAttribute(
            .boldWriterWebHidden,
            value:
                false,
            range:
                fullRange
        )

        let data =
            try DOCXExporter.data(
                from:
                    source,
                title:
                    "Extended Word Run Metadata"
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

        let xml =
            try DOCXPackage.xml(
                documentData
            )

        XCTAssertEqual(
            try xml.nodes(
                forXPath:
                    "//*[local-name()='rPr']"
                    + "/*[local-name()='lang'"
                    + " and @*[local-name()='val']='en-US'"
                    + " and @*[local-name()='eastAsia']='ja-JP'"
                    + " and @*[local-name()='bidi']='ar-SA']"
            )
            .count,
            1
        )

        XCTAssertEqual(
            try xml.nodes(
                forXPath:
                    "//*[local-name()='rPr']"
                    + "/*[local-name()='cs']"
            )
            .count,
            1
        )

        XCTAssertEqual(
            try xml.nodes(
                forXPath:
                    "//*[local-name()='rPr']"
                    + "/*[local-name()='kern'"
                    + " and @*[local-name()='val']='24']"
            )
            .count,
            1
        )

        XCTAssertEqual(
            try xml.nodes(
                forXPath:
                    "//*[local-name()='rPr']"
                    + "/*[local-name()='em'"
                    + " and @*[local-name()='val']='dot']"
            )
            .count,
            1
        )

        XCTAssertEqual(
            try xml.nodes(
                forXPath:
                    "//*[local-name()='rPr']"
                    + "/*[local-name()='specVanish']"
            )
            .count,
            1
        )

        XCTAssertEqual(
            try xml.nodes(
                forXPath:
                    "//*[local-name()='rPr']"
                    + "/*[local-name()='webHidden'"
                    + " and @*[local-name()='val']='0']"
            )
            .count,
            1
        )

        let imported =
            try DOCXImporter.text(
                from:
                    data
            )

        XCTAssertEqual(
            imported.attribute(
                .boldWriterLanguage,
                at:
                    0,
                effectiveRange:
                    nil
            ) as? String,
            "en-US"
        )

        let importedLanguage =
            try XCTUnwrap(
                imported.attribute(
                    .boldWriterWordLanguage,
                    at:
                        0,
                    effectiveRange:
                        nil
                )
                    as? WordLanguage
            )

        XCTAssertEqual(
            importedLanguage.value,
            "en-US"
        )

        XCTAssertEqual(
            importedLanguage.eastAsia,
            "ja-JP"
        )

        XCTAssertEqual(
            importedLanguage.bidi,
            "ar-SA"
        )

        XCTAssertEqual(
            imported.attribute(
                .boldWriterComplexScript,
                at:
                    0,
                effectiveRange:
                    nil
            ) as? Bool,
            true
        )

        XCTAssertEqual(
            (
                imported.attribute(
                    .boldWriterKernThreshold,
                    at:
                        0,
                    effectiveRange:
                        nil
                )
                    as? NSNumber
            )?
            .intValue,
            24
        )

        XCTAssertEqual(
            imported.attribute(
                .boldWriterEmphasis,
                at:
                    0,
                effectiveRange:
                    nil
            ) as? String,
            "dot"
        )

        XCTAssertEqual(
            imported.attribute(
                .boldWriterSpecVanish,
                at:
                    0,
                effectiveRange:
                    nil
            ) as? Bool,
            true
        )

        XCTAssertEqual(
            imported.attribute(
                .boldWriterWebHidden,
                at:
                    0,
                effectiveRange:
                    nil
            ) as? Bool,
            false
        )
    }


    func testDOCXRoundTripsWordHighlightAndParagraphDirectionMetadata() throws {
        let source =
            NSMutableAttributedString(
                string:
                    "Word fidelity paragraph\n",
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize:
                                15
                        )
                ]
            )

        let range =
            NSRange(
                location:
                    0,
                length:
                    source.length
            )

        source.addAttribute(
            .boldWriterHighlight,
            value:
                "darkYellow",
            range:
                range
        )

        source.addAttribute(
            .boldWriterParagraphBidi,
            value:
                true,
            range:
                range
        )

        source.addAttribute(
            .boldWriterTextDirection,
            value:
                "tbRl",
            range:
                range
        )

        source.addAttribute(
            .boldWriterContextualSpacing,
            value:
                false,
            range:
                range
        )

        source.addAttribute(
            .boldWriterSuppressLineNumbers,
            value:
                true,
            range:
                range
        )

        source.addAttribute(
            .boldWriterMirrorIndents,
            value:
                false,
            range:
                range
        )

        let data =
            try DOCXExporter.data(
                from:
                    source,
                title:
                    "Word Highlight Paragraph Metadata"
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

        let xml =
            try DOCXPackage.xml(
                documentData
            )

        XCTAssertEqual(
            try xml.nodes(
                forXPath:
                    "//*[local-name()='rPr']"
                    + "/*[local-name()='highlight'"
                    + " and @*[local-name()='val']='darkYellow']"
            )
            .count,
            1
        )

        XCTAssertEqual(
            try xml.nodes(
                forXPath:
                    "//*[local-name()='pPr']"
                    + "/*[local-name()='bidi']"
            )
            .count,
            1
        )

        XCTAssertEqual(
            try xml.nodes(
                forXPath:
                    "//*[local-name()='pPr']"
                    + "/*[local-name()='textDirection'"
                    + " and @*[local-name()='val']='tbRl']"
            )
            .count,
            1
        )

        XCTAssertEqual(
            try xml.nodes(
                forXPath:
                    "//*[local-name()='pPr']"
                    + "/*[local-name()='contextualSpacing'"
                    + " and @*[local-name()='val']='0']"
            )
            .count,
            1
        )

        XCTAssertEqual(
            try xml.nodes(
                forXPath:
                    "//*[local-name()='pPr']"
                    + "/*[local-name()='suppressLineNumbers']"
            )
            .count,
            1
        )

        XCTAssertEqual(
            try xml.nodes(
                forXPath:
                    "//*[local-name()='pPr']"
                    + "/*[local-name()='mirrorIndents'"
                    + " and @*[local-name()='val']='0']"
            )
            .count,
            1
        )

        let imported =
            try DOCXImporter.text(
                from:
                    data
            )

        XCTAssertEqual(
            imported.attribute(
                .boldWriterHighlight,
                at:
                    0,
                effectiveRange:
                    nil
            ) as? String,
            "darkYellow"
        )

        XCTAssertEqual(
            imported.attribute(
                .boldWriterParagraphBidi,
                at:
                    0,
                effectiveRange:
                    nil
            ) as? Bool,
            true
        )

        XCTAssertEqual(
            imported.attribute(
                .boldWriterTextDirection,
                at:
                    0,
                effectiveRange:
                    nil
            ) as? String,
            "tbRl"
        )

        XCTAssertEqual(
            imported.attribute(
                .boldWriterContextualSpacing,
                at:
                    0,
                effectiveRange:
                    nil
            ) as? Bool,
            false
        )

        XCTAssertEqual(
            imported.attribute(
                .boldWriterSuppressLineNumbers,
                at:
                    0,
                effectiveRange:
                    nil
            ) as? Bool,
            true
        )

        XCTAssertEqual(
            imported.attribute(
                .boldWriterMirrorIndents,
                at:
                    0,
                effectiveRange:
                    nil
            ) as? Bool,
            false
        )
    }


    func testDOCXRoundTripsEditableWordBodyFields() throws {
        let value =
            "September 19, 2026 / 42"

        let source =
            NSMutableAttributedString(
                string:
                    value,
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize:
                                15
                        )
                ]
            )

        let ns =
            value as NSString

        let simpleRange =
            ns.range(
                of:
                    "September 19, 2026"
            )

        let complexRange =
            ns.range(
                of:
                    "42"
            )

        source.addAttribute(
            .boldWriterField,
            value:
                WordField(
                    kind:
                        .simple,
                    instruction:
                        " DATE ",
                    dirtyValue:
                        "1",
                    lockedValue:
                        "0"
                ),
            range:
                simpleRange
        )

        let complexField =
            WordField(
                kind:
                    .complex,
                instruction:
                    " NUMPAGES ",
                dirtyValue:
                    "0",
                lockedValue:
                    "1"
            )

        source.addAttribute(
            .boldWriterField,
            value:
                complexField,
            range:
                complexRange
        )

        // Force the complex result across multiple formatting runs.
        source.addAttribute(
            .font,
            value:
                NSFont.boldSystemFont(
                    ofSize:
                        15
                ),
            range:
                NSRange(
                    location:
                        complexRange.location
                        + 1,
                    length:
                        1
                )
        )

        let data =
            try DOCXExporter.data(
                from:
                    source,
                title:
                    "Word Fields"
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

        let xml =
            try DOCXPackage.xml(
                documentData
            )

        let simpleNodes =
            try xml.nodes(
                forXPath:
                    "//*[local-name()='body']"
                    + "//*[local-name()='fldSimple'"
                    + " and @*[local-name()='instr']=' DATE '"
                    + " and @*[local-name()='dirty']='1'"
                    + " and @*[local-name()='fldLock']='0']"
            )

        XCTAssertEqual(
            simpleNodes.count,
            1
        )

        let beginNodes =
            try xml.nodes(
                forXPath:
                    "//*[local-name()='body']"
                    + "//*[local-name()='fldChar'"
                    + " and @*[local-name()='fldCharType']='begin'"
                    + " and @*[local-name()='dirty']='0'"
                    + " and @*[local-name()='fldLock']='1']"
            )

        XCTAssertEqual(
            beginNodes.count,
            1
        )

        let separateNodes =
            try xml.nodes(
                forXPath:
                    "//*[local-name()='body']"
                    + "//*[local-name()='fldChar'"
                    + " and @*[local-name()='fldCharType']='separate']"
            )

        XCTAssertEqual(
            separateNodes.count,
            1
        )

        let endNodes =
            try xml.nodes(
                forXPath:
                    "//*[local-name()='body']"
                    + "//*[local-name()='fldChar'"
                    + " and @*[local-name()='fldCharType']='end']"
            )

        XCTAssertEqual(
            endNodes.count,
            1
        )

        let instructionNodes =
            try xml.nodes(
                forXPath:
                    "//*[local-name()='body']"
                    + "//*[local-name()='instrText'"
                    + " and text()=' NUMPAGES ']"
            )

        XCTAssertEqual(
            instructionNodes.count,
            1
        )

        let imported =
            try DOCXImporter.text(
                from:
                    data
            )

        XCTAssertEqual(
            imported.string,
            value
        )

        var importedSimpleRange =
            NSRange()

        let importedSimple =
            try XCTUnwrap(
                imported.attribute(
                    .boldWriterField,
                    at:
                        simpleRange.location,
                    longestEffectiveRange:
                        &importedSimpleRange,
                    in:
                        NSRange(
                            location:
                                0,
                            length:
                                imported.length
                        )
                )
                    as? WordField
            )

        XCTAssertEqual(
            importedSimple.kind,
            .simple
        )

        XCTAssertEqual(
            importedSimple.instruction,
            " DATE "
        )

        XCTAssertEqual(
            importedSimple.dirtyValue,
            "1"
        )

        XCTAssertEqual(
            importedSimple.lockedValue,
            "0"
        )

        XCTAssertEqual(
            importedSimpleRange,
            simpleRange
        )

        var importedComplexRange =
            NSRange()

        let importedComplex =
            try XCTUnwrap(
                imported.attribute(
                    .boldWriterField,
                    at:
                        complexRange.location,
                    longestEffectiveRange:
                        &importedComplexRange,
                    in:
                        NSRange(
                            location:
                                0,
                            length:
                                imported.length
                        )
                )
                    as? WordField
            )

        XCTAssertEqual(
            importedComplex.kind,
            .complex
        )

        XCTAssertEqual(
            importedComplex.instruction,
            " NUMPAGES "
        )

        XCTAssertEqual(
            importedComplex.dirtyValue,
            "0"
        )

        XCTAssertEqual(
            importedComplex.lockedValue,
            "1"
        )

        XCTAssertEqual(
            importedComplexRange,
            complexRange
        )

        let secondExport =
            try DOCXExporter.data(
                from:
                    imported,
                title:
                    "Word Fields Again"
            )

        let secondEntries =
            try DOCXPackage.entries(
                in:
                    secondExport
            )

        let secondDocumentData =
            try XCTUnwrap(
                secondEntries.first {
                    $0.path
                        == "word/document.xml"
                }?
                .data
            )

        let secondXML =
            try DOCXPackage.xml(
                secondDocumentData
            )

        XCTAssertEqual(
            try secondXML.nodes(
                forXPath:
                    "//*[local-name()='body']"
                    + "//*[local-name()='fldSimple']"
            )
            .count,
            1
        )

        XCTAssertEqual(
            try secondXML.nodes(
                forXPath:
                    "//*[local-name()='body']"
                    + "//*[local-name()='fldChar'"
                    + " and @*[local-name()='fldCharType']='begin']"
            )
            .count,
            1
        )

        XCTAssertEqual(
            try secondXML.nodes(
                forXPath:
                    "//*[local-name()='body']"
                    + "//*[local-name()='fldChar'"
                    + " and @*[local-name()='fldCharType']='separate']"
            )
            .count,
            1
        )

        XCTAssertEqual(
            try secondXML.nodes(
                forXPath:
                    "//*[local-name()='body']"
                    + "//*[local-name()='fldChar'"
                    + " and @*[local-name()='fldCharType']='end']"
            )
            .count,
            1
        )
    }

}
