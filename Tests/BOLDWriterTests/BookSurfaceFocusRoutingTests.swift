import AppKit
import XCTest
@testable import BOLDWriter

final class BookSurfaceFocusRoutingTests:
    XCTestCase
{
    private func project()
        throws -> CoverProject
    {
        let pageCount =
            240

        let caliper =
            PrintCoverSpecification
                .kdpBlackAndWhiteWhitePaperCaliper

        let spine =
            try CoverCalculator
                .spineWidth(
                    pageCount:
                        pageCount,
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
                    dimensions.totalWidthInches,
                height:
                    dimensions.totalHeightInches
            )

        project.trimWidth =
            6

        project.backWidth =
            6

        project.trimHeight =
            9

        project.spineWidth =
            spine

        project.bleed =
            0.125

        project.canvasWidth =
            dimensions.totalWidthInches

        project.canvasHeight =
            dimensions.totalHeightInches

        project.spinePageCount =
            pageCount

        project.spineCaliperInches =
            caliper

        return project
    }

    func testCoverPhysicalPanelsMapToExactStudioComponents() {
        XCTAssertEqual(
            BookStudioProductionRouting
                .studioComponent(
                    for:
                        .front
                ),
            .front
        )

        XCTAssertEqual(
            BookStudioProductionRouting
                .studioComponent(
                    for:
                        .spine
                ),
            .spine
        )

        XCTAssertEqual(
            BookStudioProductionRouting
                .studioComponent(
                    for:
                        .back
                ),
            .back
        )

        XCTAssertNil(
            BookStudioProductionRouting
                .studioComponent(
                    for:
                        .canvas
                )
        )

        XCTAssertNil(
            BookStudioProductionRouting
                .studioComponent(
                    for:
                        nil
                )
        )
    }

    func testStudioPhysicalComponentsUseExistingFocusTargets() {
        XCTAssertEqual(
            PhysicalBookPreview
                .focusTarget(
                    for:
                        .front
                ),
            .front
        )

        XCTAssertEqual(
            PhysicalBookPreview
                .focusTarget(
                    for:
                        .spine
                ),
            .spine
        )

        XCTAssertEqual(
            PhysicalBookPreview
                .focusTarget(
                    for:
                        .back
                ),
            .back
        )

        XCTAssertNil(
            PhysicalBookPreview
                .focusTarget(
                    for:
                        .pages
                )
        )
    }

    func testNavigatorCarriesTransientReverseStudioFocusIntent() {
        let document =
            BOLDWriterDocument()

        var navigation =
            BookWorkspaceNavigation(
                document:
                    document
            )

        XCTAssertNil(
            navigation
                .studioFocusComponent
        )

        XCTAssertNil(
            navigation
                .studioFocusRequestID
        )

        navigation.requestStudioFocus(
            panel:
                .spine
        )

        XCTAssertEqual(
            navigation
                .studioFocusComponent,
            .spine
        )

        let firstRequest =
            navigation
                .studioFocusRequestID

        XCTAssertNotNil(
            firstRequest
        )

        navigation.requestStudioFocus(
            panel:
                .front
        )

        XCTAssertEqual(
            navigation
                .studioFocusComponent,
            .front
        )

        XCTAssertNotEqual(
            navigation
                .studioFocusRequestID,
            firstRequest
        )
    }

    func testPanelCenteringKeepsCurrentScaleAndCentersEachPanel()
        throws
    {
        let project =
            try project()

        let geometry =
            CoverWrapGeometry(
                project:
                    project
            )

        let scale =
            143.25

        let cases:
            [
                (
                    CoverPanelAnchor,
                    CoverRect
                )
            ] =
        [
            (
                .back,
                geometry.back
            ),
            (
                .spine,
                geometry.spine
            ),
            (
                .front,
                geometry.front
            )
        ]

        for (
            panel,
            region
        ) in cases
        {
            let pan =
                try XCTUnwrap(
                    BookCoverCreatorView
                        .centeredPanelPan(
                            for:
                                panel,
                            in:
                                project,
                            scale:
                                scale
                        )
                )

            let panelMidX =
                region.x
                + region.width / 2

            let panelMidY =
                region.y
                + region.height / 2

            let projectedX =
                (
                    panelMidX
                    - 0.5
                )
                * project.canvasWidth
                * scale
                + pan.width

            let projectedY =
                (
                    panelMidY
                    - 0.5
                )
                * project.canvasHeight
                * scale
                + pan.height

            XCTAssertEqual(
                projectedX,
                0,
                accuracy:
                    0.000001
            )

            XCTAssertEqual(
                projectedY,
                0,
                accuracy:
                    0.000001
            )
        }
    }

    func testCanvasIsNotTreatedAsPhysicalSurfaceFocus()
        throws
    {
        XCTAssertNil(
            BookCoverCreatorView
                .centeredPanelPan(
                    for:
                        .canvas,
                    in:
                        try project(),
                    scale:
                        100
                )
        )
    }

    func testBidirectionalFocusIntentDoesNotMutateProductionProject()
        throws
    {
        let document =
            BOLDWriterDocument()

        let project =
            try project()

        document.metadata.coverProjects =
            [
                project
            ]

        document.metadata.activeCoverProjectID =
            project.id

        let before =
            document.metadata
                .coverProjects

        var navigation =
            BookWorkspaceNavigation(
                document:
                    document
            )

        navigation.requestCoverEdit(
            projectID:
                project.id,
            panel:
                .front
        )

        navigation.requestStudioFocus(
            panel:
                .front
        )

        XCTAssertEqual(
            document.metadata
                .coverProjects,
            before
        )
    }
}
