import AppKit
import PDFKit
import XCTest
@testable import BOLDWriter

final class HeaderFooterTests: XCTestCase {
    private let text = NSAttributedString(
        string: "First page\u{000C}Second page",
        attributes: [
            .font: NSFont.systemFont(ofSize: 15),
            .foregroundColor: NSColor.textColor
        ]
    )

    func testNewPageSettingsDecodeOldMetadataWithoutNewKeys() throws {
        let json = """
        {
          "paper": "US Letter",
          "landscape": false,
          "topMargin": 72,
          "bottomMargin": 72,
          "leftMargin": 72,
          "rightMargin": 72,
          "showsPageNumbers": true,
          "footerText": "Legacy Footer"
        }
        """

        let settings = try JSONDecoder().decode(
            PageSettings.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(settings.footerText, "Legacy Footer")
        XCTAssertEqual(settings.headerText, nil)
        XCTAssertEqual(settings.headerPosition, nil)
        XCTAssertEqual(settings.footerPosition, nil)
        XCTAssertEqual(settings.pageNumberPosition, nil)
        XCTAssertEqual(
            settings.suppressFirstPageHeaderFooter,
            nil
        )
        XCTAssertTrue(settings.usesLegacyFooterLayout)
    }

    func testConfiguredHeaderFooterFieldsRoundTripThroughCodable() throws {
        var settings = PageSettings()

        settings.headerText = "Chapter Seven"
        settings.headerPosition = .center
        settings.footerText = "Private Draft"
        settings.footerPosition = .left
        settings.pageNumberPosition = .right
        settings.suppressFirstPageHeaderFooter = true

        let data = try JSONEncoder().encode(settings)
        let restored = try JSONDecoder().decode(
            PageSettings.self,
            from: data
        )

        XCTAssertEqual(
            restored.headerText,
            "Chapter Seven"
        )
        XCTAssertEqual(
            restored.headerPosition,
            .center
        )
        XCTAssertEqual(
            restored.footerPosition,
            .left
        )
        XCTAssertEqual(
            restored.pageNumberPosition,
            .right
        )
        XCTAssertTrue(
            restored.hidesHeaderFooterOnFirstPage
        )
    }

    func testPDFIncludesConfiguredHeaderFooterAndPageNumbers() throws {
        var settings = PageSettings()

        settings.headerText = "Book Header"
        settings.headerPosition = .center
        settings.footerText = "Private Draft"
        settings.footerPosition = .left
        settings.pageNumberPosition = .right
        settings.showsPageNumbers = true

        let data = try PDFExporter.data(
            from: text,
            settings: settings
        )

        let pdf = try XCTUnwrap(
            PDFDocument(data: data)
        )

        XCTAssertGreaterThanOrEqual(
            pdf.pageCount,
            2
        )

        let first = try XCTUnwrap(
            pdf.page(at: 0)?.string
        )

        let second = try XCTUnwrap(
            pdf.page(at: 1)?.string
        )

        XCTAssertTrue(first.contains("Book Header"))
        XCTAssertTrue(first.contains("Private Draft"))
        XCTAssertTrue(first.contains("1"))

        XCTAssertTrue(second.contains("Book Header"))
        XCTAssertTrue(second.contains("Private Draft"))
        XCTAssertTrue(second.contains("2"))
    }

    func testZeroDistanceFooterStaysInsideMediaBoxAndRemainsSelectable() throws {
        var settings = PageSettings()
        settings.paper = .custom
        settings.customPaperSize = CGSize(width: 396, height: 612)
        settings.topMargin = 36
        settings.bottomMargin = 0
        settings.leftMargin = 54
        settings.rightMargin = 54
        settings.footerDistance = 0
        settings.footerText = "Page"
        settings.footerPosition = .right
        settings.pageNumberPosition = .right
        settings.showsPageNumbers = true

        let data = try PDFExporter.data(
            from: NSAttributedString(string: "A short body."),
            settings: settings
        )
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        let page = try XCTUnwrap(pdf.page(at: 0))
        XCTAssertTrue(page.string?.contains("Page") == true)
        XCTAssertTrue(page.string?.contains("1") == true)

        let width = 396
        let height = 612
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 255, count: bytesPerRow * height)
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ), let pageRef = page.pageRef else { return false }
            context.setFillColor(NSColor.white.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.drawPDFPage(pageRef)
            return true
        }
        XCTAssertTrue(rendered)
        for row in [0, height - 1] {
            let range = (row * bytesPerRow)..<((row + 1) * bytesPerRow)
            XCTAssertFalse(
                pixels[range].enumerated().contains { offset, component in
                    offset % 4 != 3 && component < 245
                },
                "Footer glyph ink must not be clipped at the physical page edge"
            )
        }
    }

    func testPDFDoesNotDrawAlignedFooterTextTwiceBesidePageNumber() throws {
        var settings = PageSettings()
        settings.headerText = ""
        settings.footerText = "Page "
        settings.footerPosition = .left
        settings.pageNumberPosition = .left
        settings.showsPageNumbers = true

        let data = try PDFExporter.data(
            from: NSAttributedString(string: "A page with a dynamic footer."),
            settings: settings
        )
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        let firstPageText = try XCTUnwrap(pdf.page(at: 0)?.string)
        let duplicateLabel = try NSRegularExpression(
            pattern: #"(?i)Page\s+Page\s*1"#
        )

        XCTAssertNil(
            duplicateLabel.firstMatch(
                in: firstPageText,
                range: NSRange(location: 0, length: (firstPageText as NSString).length)
            ),
            "Aligned footer text must be drawn once when combined with its page number: \(firstPageText)"
        )
        XCTAssertEqual(
            firstPageText.components(separatedBy: "Page").count - 1,
            1,
            "The page label must occur once in PDF text extraction."
        )
        XCTAssertTrue(firstPageText.contains("1"))
    }

    func testFirstPageSuppressionLeavesLaterPagesDecorated() throws {
        var settings = PageSettings()

        settings.headerText = "Later Header"
        settings.footerText = "Later Footer"
        settings.showsPageNumbers = true
        settings.suppressFirstPageHeaderFooter = true

        let data = try PDFExporter.data(
            from: text,
            settings: settings
        )

        let pdf = try XCTUnwrap(
            PDFDocument(data: data)
        )

        XCTAssertGreaterThanOrEqual(
            pdf.pageCount,
            2
        )

        let first = try XCTUnwrap(
            pdf.page(at: 0)?.string
        )

        let second = try XCTUnwrap(
            pdf.page(at: 1)?.string
        )

        XCTAssertFalse(first.contains("Later Header"))
        XCTAssertFalse(first.contains("Later Footer"))

        XCTAssertTrue(second.contains("Later Header"))
        XCTAssertTrue(second.contains("Later Footer"))
        XCTAssertTrue(second.contains("2"))
    }

    func testTerminalBlankPDFPageUsesSecondPageFurnitureAndFirstPageSuppression()
        throws {
        var settings =
            PageSettings()

        settings.headerText =
            "Terminal Header"

        settings.headerPosition =
            .center

        settings.footerText =
            "Terminal Footer"

        settings.footerPosition =
            .left

        settings.pageNumberPosition =
            .right

        settings.showsPageNumbers =
            true

        settings.suppressFirstPageHeaderFooter =
            true

        let manuscript =
            NSAttributedString(
                string:
                    "First-page body\u{000C}",
                attributes: [
                    .font:
                        NSFont.systemFont(
                            ofSize: 15
                        )
                ]
            )

        let data =
            try PDFExporter.data(
                from: manuscript,
                settings: settings
            )

        let pdf =
            try XCTUnwrap(
                PDFDocument(
                    data: data
                )
            )

        XCTAssertEqual(
            pdf.pageCount,
            2
        )

        let first =
            try XCTUnwrap(
                pdf.page(at: 0)?
                    .string
            )

        let second =
            try XCTUnwrap(
                pdf.page(at: 1)?
                    .string
            )

        XCTAssertTrue(
            first.contains(
                "First-page body"
            )
        )

        XCTAssertFalse(
            first.contains(
                "Terminal Header"
            )
        )

        XCTAssertFalse(
            first.contains(
                "Terminal Footer"
            )
        )

        XCTAssertTrue(
            second.contains(
                "Terminal Header"
            )
        )

        XCTAssertTrue(
            second.contains(
                "Terminal Footer"
            )
        )

        XCTAssertTrue(
            second.contains("2")
        )
    }


}
