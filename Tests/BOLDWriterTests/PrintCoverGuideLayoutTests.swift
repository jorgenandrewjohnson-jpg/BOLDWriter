import Foundation
import XCTest

@testable import BOLDWriter

final class PrintCoverGuideLayoutTests: XCTestCase {
    private func geometry(
        pageCount: Int = 300,
        trimWidth: Double = 6,
        trimHeight: Double = 9,
        bleed: Double = 0.125
    ) throws -> BOLDPrintCoverGeometry.Result {
        try BOLDPrintCoverGeometry.calculate(
            pageCount: pageCount,
            trimWidthInches: trimWidth,
            trimHeightInches: trimHeight,
            sheetCaliperMils: 4,
            bleedInches: bleed
        )
    }

    private func layout(
        pageCount: Int = 300,
        trimWidth: Double = 6,
        trimHeight: Double = 9,
        bleed: Double = 0.125,
        canvasWidth: Double = 520,
        canvasHeight: Double = 170,
        safe: Double = 0.25
    ) throws -> BOLDPrintCoverGuideLayout.Result {
        let g = try geometry(
            pageCount: pageCount,
            trimWidth: trimWidth,
            trimHeight: trimHeight,
            bleed: bleed
        )

        return try XCTUnwrap(
            BOLDPrintCoverGuideLayout.calculate(
                geometry: g,
                safeInsetInches: safe,
                canvasWidth: canvasWidth,
                canvasHeight: canvasHeight
            )
        )
    }

    func testPreviewPreservesPhysicalAspectRatio() throws {
        let result = try layout()

        XCTAssertEqual(
            result.sheet.width / result.sheet.height,
            12.85 / 9.25,
            accuracy: 0.000001
        )
    }

    func testBackSpineFrontHaveNoGaps() throws {
        let result = try layout()

        XCTAssertEqual(
            result.back.maxX,
            result.spine.x,
            accuracy: 0.000001
        )

        XCTAssertEqual(
            result.spine.maxX,
            result.front.x,
            accuracy: 0.000001
        )
    }

    func testEntireCoverFitsInsideCanvasPadding() throws {
        let result = try layout()

        XCTAssertGreaterThanOrEqual(
            result.sheet.x,
            12 - 0.000001
        )

        XCTAssertGreaterThanOrEqual(
            result.sheet.y,
            12 - 0.000001
        )

        XCTAssertLessThanOrEqual(
            result.sheet.maxX,
            520 - 12 + 0.000001
        )

        XCTAssertLessThanOrEqual(
            result.sheet.maxY,
            170 - 12 + 0.000001
        )
    }

    func testBleedMapsToTheCorrectPixelInset() throws {
        let result = try layout()

        XCTAssertEqual(
            result.trim.x - result.sheet.x,
            0.125 * result.scale,
            accuracy: 0.000001
        )

        XCTAssertEqual(
            result.trim.y - result.sheet.y,
            0.125 * result.scale,
            accuracy: 0.000001
        )
    }

    func testSafeZonesRemainInsideTrimPanels() throws {
        let result = try layout()

        XCTAssertGreaterThan(
            result.backSafe.x,
            result.back.x
        )

        XCTAssertLessThan(
            result.backSafe.maxX,
            result.back.maxX
        )

        XCTAssertGreaterThan(
            result.frontSafe.y,
            result.front.y
        )

        XCTAssertLessThan(
            result.frontSafe.maxY,
            result.front.maxY
        )

        XCTAssertEqual(
            result.backSafe.width,
            result.back.width - 0.5 * result.scale,
            accuracy: 0.000001
        )
    }

    func testOddPageCountIncreasesSpineWidth() throws {
        let even = try layout(pageCount: 300)
        let odd = try layout(pageCount: 301)

        XCTAssertEqual(
            even.spine.width / even.scale,
            0.6,
            accuracy: 0.000001
        )

        XCTAssertEqual(
            odd.spine.width / odd.scale,
            0.604,
            accuracy: 0.000001
        )
    }

    func testZeroBleedPlacesTrimAtSheetBoundary() throws {
        let result = try layout(bleed: 0)

        XCTAssertEqual(
            result.trim,
            result.sheet
        )
    }

    func testLandscapeTrimPreservesCorrectProportions() throws {
        let result = try layout(
            trimWidth: 9,
            trimHeight: 6
        )

        XCTAssertEqual(
            result.back.width / result.back.height,
            9 / 6,
            accuracy: 0.000001
        )
    }

    func testImpossibleCanvasDimensionsAreRejected() throws {
        let geometry = try geometry()

        for width in [
            0.0,
            -10,
            Double.nan,
            Double.infinity
        ] {
            XCTAssertNil(
                BOLDPrintCoverGuideLayout.calculate(
                    geometry: geometry,
                    safeInsetInches: 0.25,
                    canvasWidth: width,
                    canvasHeight: 170
                )
            )
        }
    }

    func testUnsafeAndNonfiniteInsetsAreRejected() throws {
        let geometry = try geometry()

        for inset in [
            -1.0,
            3.0,
            Double.nan,
            Double.infinity
        ] {
            XCTAssertNil(
                BOLDPrintCoverGuideLayout.calculate(
                    geometry: geometry,
                    safeInsetInches: inset,
                    canvasWidth: 520,
                    canvasHeight: 170
                )
            )
        }
    }

    func testLayoutIsDeterministic() throws {
        let first = try layout()
        let second = try layout()

        XCTAssertEqual(first, second)
    }

    func testEveryPanelRemainsWithinTrimArea() throws {
        let result = try layout()

        for panel in [
            result.back,
            result.spine,
            result.front
        ] {
            XCTAssertGreaterThanOrEqual(
                panel.x,
                result.trim.x - 0.000001
            )

            XCTAssertLessThanOrEqual(
                panel.maxX,
                result.trim.maxX + 0.000001
            )

            XCTAssertGreaterThanOrEqual(
                panel.y,
                result.trim.y - 0.000001
            )

            XCTAssertLessThanOrEqual(
                panel.maxY,
                result.trim.maxY + 0.000001
            )
        }
    }
}
