import AppKit
import XCTest
@testable import BOLDWriter

final class BookProductionStatusStripTests:
    XCTestCase
{
    private func sixByNinePage()
        -> PageSettings
    {
        var page =
            PageSettings()

        page.paper =
            .custom

        page.customPaperSize =
            CGSize(
                width:
                    432,
                height:
                    648
            )

        page.landscape =
            false

        return page
    }

    private func readyProject(
        pageCount:
            Int = 240
    ) throws -> CoverProject {
        let caliper =
            PrintCoverSpecification
                .kdpBlackAndWhiteWhitePaperCaliper

        let spine =
            try XCTUnwrap(
                PhysicalBookGeometry
                    .expectedSpine(
                        pageCount:
                            pageCount,
                        caliper:
                            caliper
                    )
            )

        var project =
            CoverProject(
                type:
                    .printFullWrap
            )

        project.trimWidth =
            6

        project.backWidth =
            6

        project.trimHeight =
            9

        project.bleed =
            0.125

        project.spineWidth =
            spine

        project.spinePageCount =
            pageCount

        project.spineCaliperInches =
            caliper

        project.paperStockPreset =
            .kdpWhite

        project.productionBinding =
            .softcover

        project.productionTemplate =
            .sixByNineWhite

        project.canvasWidth =
            6
            + spine
            + 6
            + 0.25

        project.canvasHeight =
            9.25

        return project
    }

    func testActivePrintProjectPrefersActivePrintCover()
        throws
    {
        let first =
            try readyProject(
                pageCount:
                    200
            )

        var second =
            try readyProject(
                pageCount:
                    240
            )

        second.name =
            "Active"

        XCTAssertEqual(
            BookProductionStatusSnapshot
                .activePrintProject(
                    projects:
                        [
                            first,
                            second
                        ],
                    activeProjectID:
                        second.id
                )?
                .id,
            second.id
        )
    }

    func testMissingPrintCoverHasDedicatedState() {
        let snapshot =
            BookProductionStatusSnapshot
                .make(
                    project:
                        nil,
                    renderedPageCount:
                        nil,
                    manuscriptPageSettings:
                        [
                            sixByNinePage()
                        ]
                )

        XCTAssertEqual(
            snapshot.issue,
            .missingPrintCover
        )
    }

    func testCustomProductionRemainsManualInsteadOfAutoFailure()
        throws
    {
        var project =
            try readyProject()

        project.productionTemplate =
            .custom

        let snapshot =
            BookProductionStatusSnapshot
                .make(
                    project:
                        project,
                    renderedPageCount:
                        240,
                    manuscriptPageSettings:
                        [
                            sixByNinePage()
                        ]
                )

        XCTAssertEqual(
            snapshot.issue,
            .manualCustom
        )
    }

    func testStoredPageCountRemainsVisibleBeforeRenderedPagination()
        throws
    {
        let snapshot =
            BookProductionStatusSnapshot
                .make(
                    project:
                        try readyProject(),
                    renderedPageCount:
                        nil,
                    manuscriptPageSettings:
                        [
                            sixByNinePage()
                        ]
                )

        XCTAssertEqual(
            snapshot.issue,
            .needsManuscriptPagination
        )

        XCTAssertEqual(
            snapshot.pageCountText,
            "240 stored"
        )
    }

    func testReadyProductionUsesRenderedPageCount()
        throws
    {
        let snapshot =
            BookProductionStatusSnapshot
                .make(
                    project:
                        try readyProject(),
                    renderedPageCount:
                        240,
                    manuscriptPageSettings:
                        [
                            sixByNinePage()
                        ]
                )

        XCTAssertEqual(
            snapshot.issue,
            .ready
        )

        XCTAssertEqual(
            snapshot.renderedPageCount,
            240
        )

        XCTAssertEqual(
            snapshot.pageCountText,
            "240"
        )
    }

    func testTrimMismatchIsDistinct()
        throws
    {
        var page =
            sixByNinePage()

        page.customPaperSize =
            CGSize(
                width:
                    450,
                height:
                    648
            )

        let snapshot =
            BookProductionStatusSnapshot
                .make(
                    project:
                        try readyProject(),
                    renderedPageCount:
                        240,
                    manuscriptPageSettings:
                        [
                            page
                        ]
                )

        XCTAssertEqual(
            snapshot.issue,
            .trimMismatch
        )
    }

    func testPageCountMismatchIsDistinct()
        throws
    {
        let snapshot =
            BookProductionStatusSnapshot
                .make(
                    project:
                        try readyProject(
                            pageCount:
                                240
                        ),
                    renderedPageCount:
                        260,
                    manuscriptPageSettings:
                        [
                            sixByNinePage()
                        ]
                )

        XCTAssertEqual(
            snapshot.issue,
            .pageCountMismatch
        )
    }

    func testSpineMismatchIsDistinct()
        throws
    {
        var project =
            try readyProject()

        project.spineWidth +=
            0.1

        let snapshot =
            BookProductionStatusSnapshot
                .make(
                    project:
                        project,
                    renderedPageCount:
                        240,
                    manuscriptPageSettings:
                        [
                            sixByNinePage()
                        ]
                )

        XCTAssertEqual(
            snapshot.issue,
            .spineMismatch
        )
    }

    func testProfileMismatchIsDistinctFromGeometryIssues()
        throws
    {
        var project =
            try readyProject()

        project.paperStockPreset =
            .kdpCream

        let snapshot =
            BookProductionStatusSnapshot
                .make(
                    project:
                        project,
                    renderedPageCount:
                        240,
                    manuscriptPageSettings:
                        [
                            sixByNinePage()
                        ]
                )

        XCTAssertEqual(
            snapshot.profile,
            .sixByNineWhite
        )

        XCTAssertEqual(
            snapshot.issue,
            .productionProfileMismatch
        )
    }

    func testSnapshotExposesSharedProductionMetrics()
        throws
    {
        let snapshot =
            BookProductionStatusSnapshot
                .make(
                    project:
                        try readyProject(),
                    renderedPageCount:
                        240,
                    manuscriptPageSettings:
                        [
                            sixByNinePage()
                        ]
                )

        XCTAssertEqual(
            snapshot.profile,
            .sixByNineWhite
        )

        XCTAssertEqual(
            snapshot.paperStock,
            .kdpWhite
        )

        XCTAssertEqual(
            snapshot.binding,
            .softcover
        )

        XCTAssertEqual(
            snapshot.trimText,
            "6.00 × 9.00 in"
        )

        XCTAssertFalse(
            snapshot.spineText
                .isEmpty
        )
    }
}
