import XCTest
@testable import BOLDWriter

final class CoverLayerAnchorControlTests:
    XCTestCase
{
    private func project(
        pages: Int = 240
    ) throws -> CoverProject {
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

        return project
    }

    private func assertRect(
        _ actual: CoverRect,
        equals expected: CoverRect,
        accuracy: Double = 0.000000000001,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            actual.x,
            expected.x,
            accuracy:
                accuracy,
            file:
                file,
            line:
                line
        )

        XCTAssertEqual(
            actual.y,
            expected.y,
            accuracy:
                accuracy,
            file:
                file,
            line:
                line
        )

        XCTAssertEqual(
            actual.width,
            expected.width,
            accuracy:
                accuracy,
            file:
                file,
            line:
                line
        )

        XCTAssertEqual(
            actual.height,
            expected.height,
            accuracy:
                accuracy,
            file:
                file,
            line:
                line
        )
    }

    func testAnchorChoicesExposeCanvasBackSpineAndFront() {
        XCTAssertEqual(
            CoverPanelAnchor
                .allCases,
            [
                .canvas,
                .back,
                .spine,
                .front
            ]
        )

        XCTAssertEqual(
            CoverPanelAnchor
                .allCases
                .map(\.title),
            [
                "Canvas",
                "Back",
                "Spine",
                "Front"
            ]
        )
    }

    func testExplicitCanvasAnchorPreventsLegacyPanelInference() throws {
        var project =
            try project()

        let geometry =
            CoverWrapGeometry(
                project:
                    project
            )

        var layer =
            CoverLayer(
                kind:
                    .text,
                name:
                    "Front title kept on canvas",
                frame:
                    geometry.frontSafeArea
            )

        layer.panelAnchor =
            .canvas

        let originalFrame =
            layer.frame

        project.layers =
            [
                layer
            ]

        let resized =
            try XCTUnwrap(
                PhysicalBookGeometry
                    .synchronizedPrintCover(
                        project,
                        manuscriptPageCount:
                            500
                    )
            )

        XCTAssertEqual(
            resized.layers[0]
                .panelAnchor,
            .canvas
        )

        assertRect(
            resized.layers[0]
                .frame,
            equals:
                originalFrame
        )
    }

    func testLegacyNilAnchorStillInfersPhysicalPanel() throws {
        var project =
            try project()

        let originalGeometry =
            CoverWrapGeometry(
                project:
                    project
            )

        let layer =
            CoverLayer(
                kind:
                    .text,
                name:
                    "Legacy front title",
                frame:
                    originalGeometry
                        .frontSafeArea
            )

        XCTAssertNil(
            layer.panelAnchor
        )

        project.layers =
            [
                layer
            ]

        let resized =
            try XCTUnwrap(
                PhysicalBookGeometry
                    .synchronizedPrintCover(
                        project,
                        manuscriptPageCount:
                            500
                    )
            )

        let newGeometry =
            CoverWrapGeometry(
                project:
                    resized
            )

        XCTAssertEqual(
            resized.layers[0]
                .panelAnchor,
            .front
        )

        assertRect(
            resized.layers[0]
                .frame,
            equals:
                newGeometry
                    .frontSafeArea
        )
    }

    func testChangingAnchorMetadataDoesNotMoveLayerImmediately() throws {
        let project =
            try project()

        let geometry =
            CoverWrapGeometry(
                project:
                    project
            )

        var layer =
            CoverLayer(
                kind:
                    .image,
                name:
                    "Artwork",
                frame:
                    geometry.frontSafeArea
            )

        let originalFrame =
            layer.frame

        layer.panelAnchor =
            .spine

        assertRect(
            layer.frame,
            equals:
                originalFrame
        )

        XCTAssertEqual(
            layer.panelAnchor,
            .spine
        )

        layer.panelAnchor =
            .canvas

        assertRect(
            layer.frame,
            equals:
                originalFrame
        )

        XCTAssertEqual(
            layer.panelAnchor,
            .canvas
        )
    }

    func testExplicitBackSpineAndFrontAnchorsFollowTheirPanels() throws {
        var project =
            try project()

        let geometry =
            CoverWrapGeometry(
                project:
                    project
            )

        var back =
            CoverLayer(
                kind:
                    .text,
                name:
                    "Back",
                frame:
                    geometry.backSafeArea
            )

        back.panelAnchor =
            .back

        var spine =
            CoverLayer(
                kind:
                    .text,
                name:
                    "Spine",
                frame:
                    geometry.spineSafeArea
            )

        spine.panelAnchor =
            .spine

        var front =
            CoverLayer(
                kind:
                    .text,
                name:
                    "Front",
                frame:
                    geometry.frontSafeArea
            )

        front.panelAnchor =
            .front

        project.layers =
            [
                back,
                spine,
                front
            ]

        let resized =
            try XCTUnwrap(
                PhysicalBookGeometry
                    .synchronizedPrintCover(
                        project,
                        manuscriptPageCount:
                            500
                    )
            )

        let updated =
            CoverWrapGeometry(
                project:
                    resized
            )

        assertRect(
            resized.layers[0].frame,
            equals:
                updated.backSafeArea
        )

        assertRect(
            resized.layers[1].frame,
            equals:
                updated.spineSafeArea
        )

        assertRect(
            resized.layers[2].frame,
            equals:
                updated.frontSafeArea
        )
    }

    func testCanvasAnchorPersistsThroughCoding() throws {
        var layer =
            CoverLayer(
                kind:
                    .shape,
                name:
                    "Canvas artwork"
            )

        layer.panelAnchor =
            .canvas

        let data =
            try JSONEncoder()
                .encode(
                    layer
                )

        let decoded =
            try JSONDecoder()
                .decode(
                    CoverLayer.self,
                    from:
                        data
                )

        XCTAssertEqual(
            decoded.panelAnchor,
            .canvas
        )
    }
}
