import XCTest

@testable import BOLDWriter

final class PrintCoverArtworkAlignmentTests: XCTestCase {
    private func geometry(
        pages: Int = 300
    ) throws -> BOLDPrintCoverGeometry.Result {
        try BOLDPrintCoverGeometry.calculate(
            pageCount: pages,
            trimWidthInches: 6,
            trimHeightInches: 9,
            sheetCaliperMils: 4,
            bleedInches: 0.125
        )
    }

    private func project(
        width: Double = 12.85,
        height: Double = 9.25
    ) -> CoverProject {
        CoverProject(
            type: .printFullWrap,
            width: width,
            height: height
        )
    }

    func testMatchingPhysicalArtworkIsAccepted() throws {
        let check = try XCTUnwrap(
            BOLDPrintCoverArtworkAlignment.evaluate(
                project: project(),
                geometry: geometry()
            )
        )

        XCTAssertTrue(check.matches)
        XCTAssertNil(check.warning)
    }

    func testDifferentCoverWidthIsRejected() throws {
        let check = try XCTUnwrap(
            BOLDPrintCoverArtworkAlignment.evaluate(
                project: project(width: 12.79),
                geometry: geometry()
            )
        )

        XCTAssertFalse(check.matches)
        XCTAssertNotNil(check.warning)
    }

    func testDifferentCoverHeightIsRejected() throws {
        let check = try XCTUnwrap(
            BOLDPrintCoverArtworkAlignment.evaluate(
                project: project(height: 9),
                geometry: geometry()
            )
        )

        XCTAssertFalse(check.matches)
    }

    func testSmallSubPointRoundingDifferenceIsAllowed() throws {
        let check = try XCTUnwrap(
            BOLDPrintCoverArtworkAlignment.evaluate(
                project: project(width: 12.855),
                geometry: geometry()
            )
        )

        XCTAssertTrue(check.matches)
    }

    func testPageCountChangesRequiredArtworkSpine() throws {
        let unchanged = project()

        let assessment = try XCTUnwrap(
            BOLDPrintCoverArtworkAlignment.evaluate(
                project: unchanged,
                geometry: geometry(pages: 400)
            )
        )

        XCTAssertFalse(assessment.matches)
        XCTAssertGreaterThan(
            assessment.targetWidthInches,
            assessment.artworkWidthInches
        )
    }

    func testNonfiniteAndNegativeToleranceRejected() throws {
        for tolerance in [
            -0.1,
            Double.nan,
            Double.infinity
        ] {
            XCTAssertNil(
                try BOLDPrintCoverArtworkAlignment.evaluate(
                    project: project(),
                    geometry: geometry(),
                    toleranceInches: tolerance
                )
            )
        }
    }

    func testInvalidProjectDimensionsRejected() throws {
        for dimension in [
            0.0,
            -1.0,
            Double.nan,
            Double.infinity
        ] {
            XCTAssertNil(
                try BOLDPrintCoverArtworkAlignment.evaluate(
                    project: project(width: dimension),
                    geometry: geometry()
                )
            )
        }
    }

    func testAssessmentIsDeterministic() throws {
        let source = project(width: 12.79)
        let target = try geometry()

        let first = BOLDPrintCoverArtworkAlignment.evaluate(
            project: source,
            geometry: target
        )

        let second = BOLDPrintCoverArtworkAlignment.evaluate(
            project: source,
            geometry: target
        )

        XCTAssertEqual(first, second)
    }
}
