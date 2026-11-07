import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import XCTest

@testable import BOLDWriter

final class PrintCoverTemplateSVGTests: XCTestCase {
    private func geometry(
        pages: Int = 300,
        bleed: Double = 0.125
    ) throws -> BOLDPrintCoverGeometry.Result {
        try BOLDPrintCoverGeometry.calculate(
            pageCount: pages,
            trimWidthInches: 6,
            trimHeightInches: 9,
            sheetCaliperMils: 4,
            bleedInches: bleed
        )
    }

    func testCreatesWellFormedSVG() throws {
        let value = try BOLDPrintCoverTemplateSVG.render(
            geometry: geometry()
        )

        let parser = XMLParser(
            data: Data(value.utf8)
        )

        XCTAssertTrue(
            parser.parse(),
            String(describing: parser.parserError)
        )

        XCTAssertTrue(
            value.hasPrefix(
                "<?xml version=\"1.0\""
            )
        )
    }

    func testPhysicalPageSizeAndViewBox() throws {
        let value = try BOLDPrintCoverTemplateSVG.render(
            geometry: geometry()
        )

        XCTAssertTrue(
            value.contains(
                "width=\"12.850000in\""
            )
        )

        XCTAssertTrue(
            value.contains(
                "height=\"9.250000in\""
            )
        )

        XCTAssertTrue(
            value.contains(
                "viewBox=\"0 0 925.200000 666.000000\""
            )
        )
    }

    func testPanelBoundariesRespectBleedAndSpine() throws {
        let value = try BOLDPrintCoverTemplateSVG.render(
            geometry: geometry()
        )

        XCTAssertTrue(
            value.contains(
                "id=\"back-panel\" x=\"9.000000\" y=\"9.000000\" width=\"432.000000\""
            )
        )

        XCTAssertTrue(
            value.contains(
                "id=\"spine-panel\" x=\"441.000000\" y=\"9.000000\" width=\"43.200000\""
            )
        )

        XCTAssertTrue(
            value.contains(
                "id=\"front-panel\" x=\"484.200000\" y=\"9.000000\" width=\"432.000000\""
            )
        )
    }

    func testFrontAndBackSafeTextRectangles() throws {
        let value = try BOLDPrintCoverTemplateSVG.render(
            geometry: geometry()
        )

        XCTAssertTrue(
            value.contains(
                "id=\"back-safe\" x=\"27.000000\" y=\"27.000000\""
            )
        )

        XCTAssertTrue(
            value.contains(
                "id=\"front-safe\" x=\"502.200000\" y=\"27.000000\""
            )
        )

        XCTAssertFalse(
            value.contains(
                "id=\"spine-safe\""
            )
        )
    }

    func testZeroSafeInsetKeepsSafeZonesInsideTrim() throws {
        let value = try BOLDPrintCoverTemplateSVG.render(
            geometry: geometry(),
            safeInsetInches: 0
        )

        XCTAssertTrue(
            value.contains(
                "id=\"back-safe\" x=\"9.000000\" y=\"9.000000\" width=\"432.000000\""
            )
        )
    }

    func testInvalidSafeInsetRejected() throws {
        let result = try geometry()

        for inset in [
            -1.0,
            .nan,
            .infinity,
            3.0,
            5.0
        ] {
            XCTAssertThrowsError(
                try BOLDPrintCoverTemplateSVG.render(
                    geometry: result,
                    safeInsetInches: inset
                )
            )
        }
    }

    func testOddPageCountAdjustsSpineAndFrontStart() throws {
        let value = try BOLDPrintCoverTemplateSVG.render(
            geometry: geometry(pages: 301)
        )

        XCTAssertTrue(
            value.contains(
                "id=\"spine-panel\" x=\"441.000000\" y=\"9.000000\" width=\"43.488000\""
            )
        )

        XCTAssertTrue(
            value.contains(
                "id=\"front-panel\" x=\"484.488000\""
            )
        )
    }

    func testNoBleedStartsPanelAtOrigin() throws {
        let value = try BOLDPrintCoverTemplateSVG.render(
            geometry: geometry(bleed: 0)
        )

        XCTAssertTrue(
            value.contains(
                "id=\"back-panel\" x=\"0.000000\" y=\"0.000000\""
            )
        )
    }

    func testRendererIsDeterministicAndWarnsToRemoveGuides() throws {
        let result = try geometry()

        let first = try BOLDPrintCoverTemplateSVG.render(
            geometry: result
        )

        let second = try BOLDPrintCoverTemplateSVG.render(
            geometry: result
        )

        XCTAssertEqual(first, second)

        XCTAssertTrue(
            first.contains(
                "GUIDE ONLY — REMOVE BEFORE PRINTING"
            )
        )
    }
}
