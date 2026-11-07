import AppKit
import XCTest
@testable import BOLDWriter

final class CoverShapeToPathTests:
    XCTestCase
{
    private func shape(
        _ kind: CoverShapeKind
    ) -> CoverLayer {
        var layer = CoverLayer(
            kind: .shape,
            name:
                kind.rawValue.capitalized,
            frame:
                CoverRect(
                    x: 0.15,
                    y: 0.20,
                    width: 0.60,
                    height: 0.40
                )
        )

        layer.shape = kind
        layer.fillHex = "#336699"
        layer.strokeHex = "#CC8844"
        layer.strokeWidth = 3.5
        layer.opacity = 0.72
        layer.rotation = 17
        layer.flipHorizontal = true
        layer.flipVertical = false
        layer.blendMode = .multiply
        layer.fillOpacity = 0.81
        layer.positionLocked = false
        layer.pixelsLocked = true
        layer.transparencyLocked = true

        layer.dropShadow =
            CoverDropShadow(
                colorHex: "#111111",
                opacity: 0.35,
                angle: 32,
                distance: 0.04,
                blur: 0.06,
                enabled: true
            )

        layer.colorOverlay =
            CoverColorOverlay(
                colorHex: "#ABCDEF",
                opacity: 0.25,
                enabled: true
            )

        return layer
    }

    private func project(
        layers: [CoverLayer]
    ) -> CoverProject {
        var project = CoverProject(
            width: 10,
            height: 10
        )

        project.dpi = 72
        project.backgroundHex = "#FFFFFF"
        project.layers = layers

        return project
    }

    func testRectangleConvertsToFourStraightClosedAnchors() throws {
        let source =
            shape(.rectangle)

        let converted =
            try XCTUnwrap(
                CoverEditorEngine
                    .convertedShapeToPath(
                        source
                    )
            )

        XCTAssertEqual(
            converted.kind,
            .path
        )

        XCTAssertEqual(
            converted.pathPoints?.count,
            4
        )

        XCTAssertEqual(
            converted.pathContours?.count,
            1
        )

        XCTAssertTrue(
            converted.pathClosed
            == true
        )

        let points =
            try XCTUnwrap(
                converted.pathPoints
            )

        XCTAssertEqual(
            points[0],
            CoverPathPoint(
                x: 0,
                y: 0
            )
        )

        XCTAssertEqual(
            points[1],
            CoverPathPoint(
                x: 1,
                y: 0
            )
        )

        XCTAssertEqual(
            points[2],
            CoverPathPoint(
                x: 1,
                y: 1
            )
        )

        XCTAssertEqual(
            points[3],
            CoverPathPoint(
                x: 0,
                y: 1
            )
        )

        XCTAssertTrue(
            points.allSatisfy {
                $0.controlInX == nil &&
                $0.controlInY == nil &&
                $0.controlOutX == nil &&
                $0.controlOutY == nil
            }
        )
    }

    func testEllipseUsesFourExactCubicBezierAnchors() throws {
        let converted =
            try XCTUnwrap(
                CoverEditorEngine
                    .convertedShapeToPath(
                        shape(.ellipse)
                    )
            )

        let points =
            try XCTUnwrap(
                converted.pathPoints
            )

        XCTAssertEqual(
            points.count,
            4
        )

        XCTAssertTrue(
            converted.pathClosed
            == true
        )

        let handle =
            CoverEditorEngine
                .ellipseBezierKappa
                * 0.5

        XCTAssertEqual(
            points[0].x,
            0.5,
            accuracy: 0.000000001
        )

        XCTAssertEqual(
            points[0].y,
            0,
            accuracy: 0.000000001
        )

        XCTAssertEqual(
            try XCTUnwrap(
                points[0].controlOutX
            ),
            0.5 + handle,
            accuracy: 0.000000001
        )

        XCTAssertEqual(
            try XCTUnwrap(
                points[0].controlInX
            ),
            0.5 - handle,
            accuracy: 0.000000001
        )

        XCTAssertEqual(
            try XCTUnwrap(
                points[1].controlInY
            ),
            0.5 - handle,
            accuracy: 0.000000001
        )

        XCTAssertEqual(
            try XCTUnwrap(
                points[1].controlOutY
            ),
            0.5 + handle,
            accuracy: 0.000000001
        )

        XCTAssertTrue(
            points.allSatisfy {
                $0.controlInX != nil &&
                $0.controlInY != nil &&
                $0.controlOutX != nil &&
                $0.controlOutY != nil
            }
        )
    }

    func testLineConvertsToOpenTwoAnchorPath() throws {
        let converted =
            try XCTUnwrap(
                CoverEditorEngine
                    .convertedShapeToPath(
                        shape(.line)
                    )
            )

        XCTAssertEqual(
            converted.kind,
            .path
        )

        XCTAssertFalse(
            converted.pathClosed
            ?? true
        )

        XCTAssertEqual(
            converted.pathPoints,
            [
                CoverPathPoint(
                    x: 0,
                    y: 0.5
                ),
                CoverPathPoint(
                    x: 1,
                    y: 0.5
                )
            ]
        )

        XCTAssertEqual(
            converted.pathContours,
            [
                [
                    CoverPathPoint(
                        x: 0,
                        y: 0.5
                    ),
                    CoverPathPoint(
                        x: 1,
                        y: 0.5
                    )
                ]
            ]
        )
    }

    func testConversionPreservesIdentityFrameAndCompatibleStyle() throws {
        let source =
            shape(.ellipse)

        let converted =
            try XCTUnwrap(
                CoverEditorEngine
                    .convertedShapeToPath(
                        source
                    )
            )

        XCTAssertEqual(
            converted.id,
            source.id
        )

        XCTAssertEqual(
            converted.name,
            source.name
        )

        XCTAssertEqual(
            converted.frame,
            source.frame
        )

        XCTAssertEqual(
            converted.opacity,
            source.opacity
        )

        XCTAssertEqual(
            converted.rotation,
            source.rotation
        )

        XCTAssertEqual(
            converted.flipHorizontal,
            source.flipHorizontal
        )

        XCTAssertEqual(
            converted.flipVertical,
            source.flipVertical
        )

        XCTAssertEqual(
            converted.fillHex,
            source.fillHex
        )

        XCTAssertEqual(
            converted.strokeHex,
            source.strokeHex
        )

        XCTAssertEqual(
            converted.strokeWidth,
            source.strokeWidth
        )

        XCTAssertEqual(
            converted.blendMode,
            source.blendMode
        )

        XCTAssertEqual(
            converted.fillOpacity,
            source.fillOpacity
        )

        XCTAssertEqual(
            converted.positionLocked,
            source.positionLocked
        )

        XCTAssertEqual(
            converted.pixelsLocked,
            source.pixelsLocked
        )

        XCTAssertEqual(
            converted.transparencyLocked,
            source.transparencyLocked
        )

        XCTAssertEqual(
            converted.dropShadow,
            source.dropShadow
        )

        XCTAssertEqual(
            converted.colorOverlay,
            source.colorOverlay
        )
    }

    func testConversionPersistsAsEditablePath() throws {
        let source =
            shape(.ellipse)

        let converted =
            try XCTUnwrap(
                CoverEditorEngine
                    .convertedShapeToPath(
                        source
                    )
            )

        let data =
            try JSONEncoder()
                .encode(converted)

        let reopened =
            try JSONDecoder()
                .decode(
                    CoverLayer.self,
                    from: data
                )

        XCTAssertEqual(
            reopened.kind,
            .path
        )

        XCTAssertEqual(
            reopened.pathPoints,
            converted.pathPoints
        )

        XCTAssertEqual(
            reopened.pathContours,
            converted.pathContours
        )

        XCTAssertEqual(
            reopened.pathClosed,
            converted.pathClosed
        )
    }

    func testConvertedRectanglesImmediatelySupportBooleanUnion() throws {
        var left =
            shape(.rectangle)

        left.frame =
            CoverRect(
                x: 0,
                y: 0,
                width: 0.6,
                height: 1
            )

        var right =
            shape(.rectangle)

        right.frame =
            CoverRect(
                x: 0.4,
                y: 0,
                width: 0.6,
                height: 1
            )

        left =
            try XCTUnwrap(
                CoverEditorEngine
                    .convertedShapeToPath(
                        left
                    )
            )

        right =
            try XCTUnwrap(
                CoverEditorEngine
                    .convertedShapeToPath(
                        right
                    )
            )

        let source =
            project(
                layers: [
                    left,
                    right
                ]
            )

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .booleanPathLayer(
                        project: source,
                        ids:
                            Set(
                                [
                                    left.id,
                                    right.id
                                ]
                            ),
                        primaryID: left.id,
                        operation: .union
                    )
            )

        XCTAssertEqual(
            result.kind,
            .path
        )

        XCTAssertFalse(
            result.pathContours?
                .isEmpty
            ?? true
        )

        XCTAssertTrue(
            result.pathClosed
            == true
        )
    }

    func testConvertedLineRemainsInvalidBooleanOperand() throws {
        let line =
            try XCTUnwrap(
                CoverEditorEngine
                    .convertedShapeToPath(
                        shape(.line)
                    )
            )

        let rectangle =
            try XCTUnwrap(
                CoverEditorEngine
                    .convertedShapeToPath(
                        shape(.rectangle)
                    )
            )

        let source =
            project(
                layers: [
                    line,
                    rectangle
                ]
            )

        XCTAssertNil(
            CoverEditorEngine
                .booleanPathLayer(
                    project: source,
                    ids:
                        Set(
                            [
                                line.id,
                                rectangle.id
                            ]
                        ),
                    primaryID: line.id,
                    operation: .union
                )
        )
    }

    func testNonShapeLayerCannotConvert() {
        var layer =
            shape(.rectangle)

        layer.kind = .path

        XCTAssertNil(
            CoverEditorEngine
                .convertedShapeToPath(
                    layer
                )
        )
    }

    func testRectangleRenderingMatchesAfterConversion() throws {
        var source =
            shape(.rectangle)

        source.rotation = 0
        source.flipHorizontal = false
        source.opacity = 1
        source.blendMode = .normal
        source.dropShadow = nil
        source.colorOverlay = nil
        source.strokeWidth = 0
        source.fillHex = "#336699"

        let converted =
            try XCTUnwrap(
                CoverEditorEngine
                    .convertedShapeToPath(
                        source
                    )
            )

        var shapeProject =
            CoverProject(
                width: 1,
                height: 1
            )

        shapeProject.backgroundHex =
            "#FFFFFF"

        shapeProject.layers = [
            source
        ]

        var pathProject =
            shapeProject

        pathProject.layers = [
            converted
        ]

        let shapeImage =
            try CoverArtwork.render(
                shapeProject,
                scale: 64
            )

        let pathImage =
            try CoverArtwork.render(
                pathProject,
                scale: 64
            )

        let shapeData =
            try XCTUnwrap(
                shapeImage.tiffRepresentation
            )

        let pathData =
            try XCTUnwrap(
                pathImage.tiffRepresentation
            )

        let shapeRep =
            try XCTUnwrap(
                NSBitmapImageRep(
                    data: shapeData
                )
            )

        let pathRep =
            try XCTUnwrap(
                NSBitmapImageRep(
                    data: pathData
                )
            )

        let shapeColor =
            try XCTUnwrap(
                shapeRep.colorAt(
                    x: 32,
                    y: 32
                )
            )

        let pathColor =
            try XCTUnwrap(
                pathRep.colorAt(
                    x: 32,
                    y: 32
                )
            )

        let shapeRGB =
            try XCTUnwrap(
                shapeColor.usingColorSpace(
                    .deviceRGB
                )
            )

        let pathRGB =
            try XCTUnwrap(
                pathColor.usingColorSpace(
                    .deviceRGB
                )
            )

        XCTAssertEqual(
            shapeRGB.redComponent,
            pathRGB.redComponent,
            accuracy: 0.01
        )

        XCTAssertEqual(
            shapeRGB.greenComponent,
            pathRGB.greenComponent,
            accuracy: 0.01
        )

        XCTAssertEqual(
            shapeRGB.blueComponent,
            pathRGB.blueComponent,
            accuracy: 0.01
        )
    }
}
