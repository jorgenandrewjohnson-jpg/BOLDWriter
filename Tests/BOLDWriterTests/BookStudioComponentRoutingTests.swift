import AppKit
import XCTest
@testable import BOLDWriter

final class BookStudioComponentRoutingTests:
    XCTestCase
{
    func testCoverComponentsRouteToExactPhysicalPanels() {
        let spread =
            BookSpread(
                index:
                    4,
                leftPage:
                    8,
                rightPage:
                    9
            )

        XCTAssertEqual(
            BookStudioProductionRouting
                .editRoute(
                    for:
                        .front,
                    spread:
                        spread
                ),
            .cover(
                .front
            )
        )

        XCTAssertEqual(
            BookStudioProductionRouting
                .editRoute(
                    for:
                        .spine,
                    spread:
                        spread
                ),
            .cover(
                .spine
            )
        )

        XCTAssertEqual(
            BookStudioProductionRouting
                .editRoute(
                    for:
                        .back,
                    spread:
                        spread
                ),
            .cover(
                .back
            )
        )

        XCTAssertEqual(
            BookStudioProductionRouting
                .editRoute(
                    for:
                        .book,
                    spread:
                        spread
                ),
            .cover(
                nil
            )
        )
    }

    func testPageComponentsRouteToVisiblePhysicalPages() {
        let spread =
            BookSpread(
                index:
                    4,
                leftPage:
                    8,
                rightPage:
                    9
            )

        XCTAssertEqual(
            BookStudioProductionRouting
                .editRoute(
                    for:
                        .leftPage,
                    spread:
                        spread
                ),
            .manuscript(
                8
            )
        )

        XCTAssertEqual(
            BookStudioProductionRouting
                .editRoute(
                    for:
                        .rightPage,
                    spread:
                        spread
                ),
            .manuscript(
                9
            )
        )

        XCTAssertEqual(
            BookStudioProductionRouting
                .editRoute(
                    for:
                        .pages,
                    spread:
                        spread
                ),
            .manuscript(
                9
            )
        )
    }

    func testFirstSpreadFallsBackToPageOne() {
        let spread =
            PhysicalBookGeometry
                .spread(
                    at:
                        0,
                    pageCount:
                        300
                )

        XCTAssertNil(
            spread.leftPage
        )

        XCTAssertEqual(
            spread.rightPage,
            1
        )

        XCTAssertEqual(
            BookStudioProductionRouting
                .editRoute(
                    for:
                        .leftPage,
                    spread:
                        spread
                ),
            .manuscript(
                1
            )
        )

        XCTAssertEqual(
            BookStudioProductionRouting
                .editRoute(
                    for:
                        .rightPage,
                    spread:
                        spread
                ),
            .manuscript(
                1
            )
        )
    }

    func testNonProductionSceneComponentsDoNotNavigate() {
        let spread =
            BookSpread(
                index:
                    2,
                leftPage:
                    4,
                rightPage:
                    5
            )

        XCTAssertNil(
            BookStudioProductionRouting
                .editRoute(
                    for:
                        .environment,
                    spread:
                        spread
                )
        )

        XCTAssertNil(
            BookStudioProductionRouting
                .editRoute(
                    for:
                        .lights,
                    spread:
                        spread
                )
        )

        XCTAssertNil(
            BookStudioProductionRouting
                .editRoute(
                    for:
                        .camera,
                    spread:
                        spread
                )
        )
    }

    func testWorkspaceNavigatorCarriesTransientCoverPanelIntent() {
        let document =
            BOLDWriterDocument()

        let project =
            CoverProject(
                type:
                    .printFullWrap
            )

        document.metadata.coverProjects =
            [
                project
            ]

        var navigation =
            BookWorkspaceNavigation(
                document:
                    document
            )

        navigation.requestCoverEdit(
            projectID:
                project.id,
            panel:
                .spine
        )

        XCTAssertEqual(
            document.metadata
                .activeCoverProjectID,
            project.id
        )

        XCTAssertEqual(
            navigation.coverFocusPanel,
            .spine
        )

        XCTAssertNotNil(
            navigation.coverFocusRequestID
        )
    }

    func testWorkspaceNavigatorCarriesExactManuscriptPageAndRange() {
        let document =
            BOLDWriterDocument()

        var navigation =
            BookWorkspaceNavigation(
                document:
                    document
            )

        let range =
            NSRange(
                location:
                    125,
                length:
                    41
            )

        navigation.requestManuscriptEdit(
            pageNumber:
                17,
            range:
                range
        )

        XCTAssertEqual(
            navigation.manuscriptPageRequest,
            17
        )

        XCTAssertEqual(
            navigation.manuscriptRangeRequest,
            range
        )

        XCTAssertNotNil(
            navigation.manuscriptRequestID
        )
    }

    func testCoverCreatorPrefersExplicitPanelLayer() {
        var project =
            CoverProject(
                type:
                    .printFullWrap
            )

        let geometry =
            CoverWrapGeometry(
                project:
                    project
            )

        var legacy =
            CoverLayer(
                kind:
                    .text,
                name:
                    "Legacy front",
                frame:
                    geometry.frontSafeArea
            )

        legacy.panelAnchor =
            nil

        var explicit =
            CoverLayer(
                kind:
                    .text,
                name:
                    "Explicit front",
                frame:
                    geometry.frontSafeArea
            )

        explicit.panelAnchor =
            .front

        project.layers =
            [
                legacy,
                explicit
            ]

        XCTAssertEqual(
            BookCoverCreatorView
                .preferredLayerID(
                    for:
                        .front,
                    in:
                        project
                ),
            explicit.id
        )
    }

    func testCoverCreatorFallsBackToLegacyPanelInference() throws {
        let pages =
            240

        let caliper =
            PrintCoverSpecification
                .kdpBlackAndWhiteWhitePaperCaliper

        let spine =
            try CoverCalculator
                .spineWidth(
                    pageCount:
                        pages,
                    caliperInches:
                        caliper
                )

        let dimensions =
            try CoverCalculator
                .fullWrap(
                    backWidth:
                        6,
                    frontWidth:
                        6,
                    trimHeight:
                        9,
                    spineWidth:
                        spine,
                    bleed:
                        0.125
                )

        var project =
            CoverProject(
                type:
                    .printFullWrap,
                width:
                    dimensions
                        .totalWidthInches,
                height:
                    dimensions
                        .totalHeightInches
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
            pages

        project.spineCaliperInches =
            caliper

        project.canvasWidth =
            dimensions
                .totalWidthInches

        project.canvasHeight =
            dimensions
                .totalHeightInches

        let geometry =
            CoverWrapGeometry(
                project:
                    project
            )

        let legacy =
            CoverLayer(
                kind:
                    .text,
                name:
                    "Legacy spine",
                frame:
                    geometry
                        .spineSafeArea
            )

        XCTAssertNil(
            legacy.panelAnchor
        )

        XCTAssertEqual(
            CoverCalculator
                .inferredPanelAnchor(
                    for:
                        legacy.frame,
                    in:
                        project
                ),
            .spine
        )

        project.layers =
            [
                legacy
            ]

        XCTAssertEqual(
            BookCoverCreatorView
                .preferredLayerID(
                    for:
                        .spine,
                    in:
                        project
                ),
            legacy.id
        )
    }

    func testCoverCreatorDoesNotInventArtworkForEmptyPanel() {
        let project =
            CoverProject(
                type:
                    .printFullWrap
            )

        XCTAssertNil(
            BookCoverCreatorView
                .preferredLayerID(
                    for:
                        .back,
                    in:
                        project
                )
        )
    }
}
