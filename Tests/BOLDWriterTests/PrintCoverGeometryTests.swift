import XCTest
@testable import BOLDWriter

final class PrintCoverGeometryTests: XCTestCase {
    func test300PagesComputes150PhysicalSheetsAndSixTenthsInchSpine() throws {
        let result = try BOLDPrintCoverGeometry.calculate(
            pageCount: 300,
            trimWidthInches: 6,
            trimHeightInches: 9,
            sheetCaliperMils: 4,
            bleedInches: 0.125
        )

        XCTAssertEqual(result.sheetCount, 150)
        XCTAssertEqual(
            result.spineWidthInches,
            0.6,
            accuracy: 0.0000001
        )
        XCTAssertEqual(
            result.totalCoverWidthInches,
            12.85,
            accuracy: 0.0000001
        )
        XCTAssertEqual(
            result.totalCoverHeightInches,
            9.25,
            accuracy: 0.0000001
        )
    }

    func testOddPageCountRoundsUpToPhysicalSheet() throws {
        let result = try BOLDPrintCoverGeometry.calculate(
            pageCount: 301,
            trimWidthInches: 6,
            trimHeightInches: 9,
            sheetCaliperMils: 4,
            bleedInches: 0.125
        )

        XCTAssertEqual(result.sheetCount, 151)
        XCTAssertEqual(
            result.spineWidthInches,
            0.604,
            accuracy: 0.0000001
        )
    }

    func testBackSpineFrontAreContiguousAndWithinFlatCover() throws {
        let result = try BOLDPrintCoverGeometry.calculate(
            pageCount: 312,
            trimWidthInches: 5.5,
            trimHeightInches: 8.5,
            sheetCaliperMils: 3.8,
            bleedInches: 0.125
        )

        XCTAssertEqual(
            result.spine.xInches,
            result.back.xInches + result.back.widthInches,
            accuracy: 0.0000001
        )

        XCTAssertEqual(
            result.front.xInches,
            result.spine.xInches + result.spine.widthInches,
            accuracy: 0.0000001
        )

        XCTAssertEqual(
            result.totalCoverWidthInches,
            result.front.xInches
                + result.front.widthInches
                + result.bleedInches,
            accuracy: 0.0000001
        )
    }

    func testSpineAllowanceChangesSpineAndCoverEqually() throws {
        let base = try BOLDPrintCoverGeometry.calculate(
            pageCount: 300,
            trimWidthInches: 6,
            trimHeightInches: 9,
            sheetCaliperMils: 4,
            bleedInches: 0.125
        )

        let withAllowance = try BOLDPrintCoverGeometry.calculate(
            pageCount: 300,
            trimWidthInches: 6,
            trimHeightInches: 9,
            sheetCaliperMils: 4,
            bleedInches: 0.125,
            spineAllowanceInches: 0.02
        )

        XCTAssertEqual(
            withAllowance.spineWidthInches
                - base.spineWidthInches,
            0.02,
            accuracy: 0.0000001
        )

        XCTAssertEqual(
            withAllowance.totalCoverWidthInches
                - base.totalCoverWidthInches,
            0.02,
            accuracy: 0.0000001
        )
    }

    func testBleedIncreasesOverallDimensionsButNotPanels() throws {
        let without = try BOLDPrintCoverGeometry.calculate(
            pageCount: 300,
            trimWidthInches: 6,
            trimHeightInches: 9,
            sheetCaliperMils: 4,
            bleedInches: 0
        )

        let with = try BOLDPrintCoverGeometry.calculate(
            pageCount: 300,
            trimWidthInches: 6,
            trimHeightInches: 9,
            sheetCaliperMils: 4,
            bleedInches: 0.125
        )

        XCTAssertEqual(
            with.totalCoverWidthInches
                - without.totalCoverWidthInches,
            0.25,
            accuracy: 0.0000001
        )

        XCTAssertEqual(
            with.totalCoverHeightInches
                - without.totalCoverHeightInches,
            0.25,
            accuracy: 0.0000001
        )

        XCTAssertEqual(
            with.front.widthInches,
            without.front.widthInches
        )
    }

    func testInvalidPageCountsRejected() {
        for pages in [-1, 0, 1_000_001] {
            XCTAssertThrowsError(
                try BOLDPrintCoverGeometry.calculate(
                    pageCount: pages,
                    trimWidthInches: 6,
                    trimHeightInches: 9,
                    sheetCaliperMils: 4,
                    bleedInches: 0.125
                )
            )
        }
    }

    func testInvalidTrimAndCaliperRejected() {
        XCTAssertThrowsError(
            try BOLDPrintCoverGeometry.calculate(
                pageCount: 300,
                trimWidthInches: .nan,
                trimHeightInches: 9,
                sheetCaliperMils: 4,
                bleedInches: 0.125
            )
        )

        XCTAssertThrowsError(
            try BOLDPrintCoverGeometry.calculate(
                pageCount: 300,
                trimWidthInches: 6,
                trimHeightInches: 9,
                sheetCaliperMils: 0,
                bleedInches: 0.125
            )
        )

        XCTAssertThrowsError(
            try BOLDPrintCoverGeometry.calculate(
                pageCount: 300,
                trimWidthInches: 6,
                trimHeightInches: 9,
                sheetCaliperMils: .infinity,
                bleedInches: 0.125
            )
        )
    }

    func testInvalidBleedAndAllowanceRejected() {
        XCTAssertThrowsError(
            try BOLDPrintCoverGeometry.calculate(
                pageCount: 300,
                trimWidthInches: 6,
                trimHeightInches: 9,
                sheetCaliperMils: 4,
                bleedInches: -0.125
            )
        )

        XCTAssertThrowsError(
            try BOLDPrintCoverGeometry.calculate(
                pageCount: 300,
                trimWidthInches: 6,
                trimHeightInches: 9,
                sheetCaliperMils: 4,
                bleedInches: 0.125,
                spineAllowanceInches: -0.1
            )
        )
    }
}
