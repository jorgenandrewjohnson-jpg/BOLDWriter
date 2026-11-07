import XCTest
import CoreGraphics
@testable import BOLDWriter

final class CoverPathSegmentInsertionTests: XCTestCase {
    private func makePath(
        _ points: [CoverPathPoint],
        closed: Bool
    ) -> CoverLayer {
        var layer =
            CoverLayer(
                kind: .path,
                name: "Path"
            )

        layer.pathPoints = points
        layer.pathClosed = closed

        return layer
    }

    private func cubicPoint(
        from: CoverPathPoint,
        to: CoverPathPoint,
        t: Double
    ) -> CGPoint {
        let u = 1 - t

        func component(
            _ p0: Double,
            _ p1: Double,
            _ p2: Double,
            _ p3: Double
        ) -> Double {
            u * u * u * p0
            + 3 * u * u * t * p1
            + 3 * u * t * t * p2
            + t * t * t * p3
        }

        return CGPoint(
            x:
                component(
                    from.x,
                    from.controlOutX
                        ?? from.x,
                    to.controlInX
                        ?? to.x,
                    to.x
                ),
            y:
                component(
                    from.y,
                    from.controlOutY
                        ?? from.y,
                    to.controlInY
                        ?? to.y,
                    to.y
                )
        )
    }

    func testStraightOpenSegmentInsertion() throws {
        let layer =
            makePath(
                [
                    CoverPathPoint(
                        x: 0,
                        y: 0
                    ),
                    CoverPathPoint(
                        x: 1,
                        y: 0
                    ),
                ],
                closed: false
            )

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .insertingVectorPoint(
                        in: layer,
                        contourIndex: 0,
                        startPointIndex: 0,
                        t: 0.25
                    )
            )

        let points =
            try XCTUnwrap(
                result.layer.pathPoints
            )

        XCTAssertEqual(
            points.count,
            3
        )

        XCTAssertEqual(
            result.anchor,
            CoverVectorAnchorIndex(
                contourIndex: 0,
                pointIndex: 1
            )
        )

        XCTAssertEqual(
            points[1].x,
            0.25,
            accuracy: 0.0000001
        )

        XCTAssertEqual(
            points[1].y,
            0,
            accuracy: 0.0000001
        )

        XCTAssertNil(
            points[1].controlInX
        )

        XCTAssertNil(
            points[1].controlOutX
        )
    }

    func testClosedFinalToFirstSegmentInsertion() throws {
        let points = [
            CoverPathPoint(
                x: 0,
                y: 0
            ),
            CoverPathPoint(
                x: 1,
                y: 0
            ),
            CoverPathPoint(
                x: 1,
                y: 1
            ),
        ]

        var layer =
            makePath(
                points,
                closed: true
            )

        layer.pathContours = [
            points
        ]

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .insertingVectorPoint(
                        in: layer,
                        contourIndex: 0,
                        startPointIndex: 2,
                        t: 0.5
                    )
            )

        let contour =
            try XCTUnwrap(
                result.layer
                    .pathContours?
                    .first
            )

        XCTAssertEqual(
            contour.count,
            4
        )

        XCTAssertEqual(
            result.anchor.pointIndex,
            3
        )

        XCTAssertEqual(
            contour[3].x,
            0.5,
            accuracy: 0.0000001
        )

        XCTAssertEqual(
            contour[3].y,
            0.5,
            accuracy: 0.0000001
        )

        XCTAssertEqual(
            result.layer.pathPoints,
            contour
        )
    }

    func testOpenPathRejectsFinalToFirstSegment() {
        let layer =
            makePath(
                [
                    CoverPathPoint(
                        x: 0,
                        y: 0
                    ),
                    CoverPathPoint(
                        x: 1,
                        y: 0
                    ),
                    CoverPathPoint(
                        x: 1,
                        y: 1
                    ),
                ],
                closed: false
            )

        XCTAssertNil(
            CoverEditorEngine
                .insertingVectorPoint(
                    in: layer,
                    contourIndex: 0,
                    startPointIndex: 2,
                    t: 0.5
                )
        )
    }

    func testCubicInsertionUsesExactDeCasteljauHandles() throws {
        let start =
            CoverPathPoint(
                x: 0,
                y: 0,
                controlOutX: 0.25,
                controlOutY: 0
            )

        let end =
            CoverPathPoint(
                x: 1,
                y: 1,
                controlInX: 0.75,
                controlInY: 1
            )

        let layer =
            makePath(
                [
                    start,
                    end,
                ],
                closed: false
            )

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .insertingVectorPoint(
                        in: layer,
                        contourIndex: 0,
                        startPointIndex: 0,
                        t: 0.4
                    )
            )

        let points =
            try XCTUnwrap(
                result.layer.pathPoints
            )

        XCTAssertEqual(
            points.count,
            3
        )

        XCTAssertEqual(
            try XCTUnwrap(
                points[0].controlOutX
            ),
            0.10,
            accuracy: 0.0000001
        )

        XCTAssertEqual(
            try XCTUnwrap(
                points[0].controlOutY
            ),
            0,
            accuracy: 0.0000001
        )

        XCTAssertEqual(
            points[1].x,
            0.388,
            accuracy: 0.0000001
        )

        XCTAssertEqual(
            points[1].y,
            0.352,
            accuracy: 0.0000001
        )

        XCTAssertEqual(
            try XCTUnwrap(
                points[1].controlInX
            ),
            0.24,
            accuracy: 0.0000001
        )

        XCTAssertEqual(
            try XCTUnwrap(
                points[1].controlInY
            ),
            0.16,
            accuracy: 0.0000001
        )

        XCTAssertEqual(
            try XCTUnwrap(
                points[1].controlOutX
            ),
            0.61,
            accuracy: 0.0000001
        )

        XCTAssertEqual(
            try XCTUnwrap(
                points[1].controlOutY
            ),
            0.64,
            accuracy: 0.0000001
        )

        XCTAssertEqual(
            try XCTUnwrap(
                points[2].controlInX
            ),
            0.85,
            accuracy: 0.0000001
        )

        XCTAssertEqual(
            try XCTUnwrap(
                points[2].controlInY
            ),
            1,
            accuracy: 0.0000001
        )
    }

    func testCubicInsertionPreservesOriginalCurveGeometry() throws {
        let split = 0.37

        let start =
            CoverPathPoint(
                x: 0.05,
                y: 0.15,
                controlOutX: 0.40,
                controlOutY: -0.10
            )

        let end =
            CoverPathPoint(
                x: 0.90,
                y: 0.80,
                controlInX: 0.55,
                controlInY: 1.05
            )

        let original =
            makePath(
                [
                    start,
                    end,
                ],
                closed: false
            )

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .insertingVectorPoint(
                        in: original,
                        contourIndex: 0,
                        startPointIndex: 0,
                        t: split
                    )
            )

        let points =
            try XCTUnwrap(
                result.layer.pathPoints
            )

        for step in 0...80 {
            let originalT =
                Double(step)
                / 80

            let expected =
                cubicPoint(
                    from: start,
                    to: end,
                    t: originalT
                )

            let actual: CGPoint

            if originalT <= split {
                actual =
                    cubicPoint(
                        from: points[0],
                        to: points[1],
                        t:
                            originalT
                            / split
                    )
            } else {
                actual =
                    cubicPoint(
                        from: points[1],
                        to: points[2],
                        t:
                            (
                                originalT
                                - split
                            )
                            / (
                                1
                                - split
                            )
                    )
            }

            XCTAssertEqual(
                Double(actual.x),
                Double(expected.x),
                accuracy: 0.000000001
            )

            XCTAssertEqual(
                Double(actual.y),
                Double(expected.y),
                accuracy: 0.000000001
            )
        }
    }

    func testInsertionWorksOnSecondaryCompoundContour() throws {
        let primary = [
            CoverPathPoint(
                x: 0,
                y: 0
            ),
            CoverPathPoint(
                x: 0.4,
                y: 0
            ),
            CoverPathPoint(
                x: 0.4,
                y: 0.4
            ),
        ]

        let secondary = [
            CoverPathPoint(
                x: 0.6,
                y: 0.6
            ),
            CoverPathPoint(
                x: 0.9,
                y: 0.6
            ),
            CoverPathPoint(
                x: 0.9,
                y: 0.9
            ),
        ]

        var layer =
            makePath(
                primary,
                closed: true
            )

        layer.pathContours = [
            primary,
            secondary,
        ]

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .insertingVectorPoint(
                        in: layer,
                        contourIndex: 1,
                        startPointIndex: 0,
                        t: 0.5
                    )
            )

        let contours =
            try XCTUnwrap(
                result.layer.pathContours
            )

        XCTAssertEqual(
            contours[0],
            primary
        )

        XCTAssertEqual(
            contours[1].count,
            4
        )

        XCTAssertEqual(
            contours[1][1].x,
            0.75,
            accuracy: 0.0000001
        )

        XCTAssertEqual(
            contours[1][1].y,
            0.60,
            accuracy: 0.0000001
        )

        XCTAssertEqual(
            result.layer.pathPoints,
            primary
        )

        XCTAssertEqual(
            result.anchor,
            CoverVectorAnchorIndex(
                contourIndex: 1,
                pointIndex: 1
            )
        )
    }

    func testInvalidContourAndSegmentAreRejected() {
        let layer =
            makePath(
                [
                    CoverPathPoint(
                        x: 0,
                        y: 0
                    ),
                    CoverPathPoint(
                        x: 1,
                        y: 1
                    ),
                ],
                closed: false
            )

        XCTAssertNil(
            CoverEditorEngine
                .insertingVectorPoint(
                    in: layer,
                    contourIndex: 4,
                    startPointIndex: 0,
                    t: 0.5
                )
        )

        XCTAssertNil(
            CoverEditorEngine
                .insertingVectorPoint(
                    in: layer,
                    contourIndex: 0,
                    startPointIndex: 9,
                    t: 0.5
                )
        )
    }

    func testInsertionPreservesLayerMetadataAndStyling() throws {
        var layer =
            makePath(
                [
                    CoverPathPoint(
                        x: 0,
                        y: 0
                    ),
                    CoverPathPoint(
                        x: 1,
                        y: 0
                    ),
                ],
                closed: false
            )

        layer.name = "Styled Path"

        layer.frame =
            CoverRect(
                x: 0.12,
                y: 0.18,
                width: 0.62,
                height: 0.44
            )

        layer.fillHex = "#123456"
        layer.strokeHex = "#FEDCBA"
        layer.strokeWidth = 7.5
        layer.opacity = 0.63
        layer.rotation = 27
        layer.flipHorizontal = true
        layer.flipVertical = true

        let originalID =
            layer.id

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .insertingVectorPoint(
                        in: layer,
                        contourIndex: 0,
                        startPointIndex: 0,
                        t: 0.5
                    )
            )

        XCTAssertEqual(
            result.layer.id,
            originalID
        )

        XCTAssertEqual(
            result.layer.name,
            layer.name
        )

        XCTAssertEqual(
            result.layer.frame,
            layer.frame
        )

        XCTAssertEqual(
            result.layer.fillHex,
            layer.fillHex
        )

        XCTAssertEqual(
            result.layer.strokeHex,
            layer.strokeHex
        )

        XCTAssertEqual(
            result.layer.strokeWidth,
            layer.strokeWidth,
            accuracy: 0.0000001
        )

        XCTAssertEqual(
            result.layer.opacity,
            layer.opacity,
            accuracy: 0.0000001
        )

        XCTAssertEqual(
            result.layer.rotation,
            layer.rotation,
            accuracy: 0.0000001
        )

        XCTAssertEqual(
            result.layer.flipHorizontal,
            layer.flipHorizontal
        )

        XCTAssertEqual(
            result.layer.flipVertical,
            layer.flipVertical
        )
    }

    func testStraightSegmentHitTestingReturnsNearestParameter() throws {
        let layer =
            makePath(
                [
                    CoverPathPoint(
                        x: 0,
                        y: 0
                    ),
                    CoverPathPoint(
                        x: 1,
                        y: 0
                    ),
                ],
                closed: false
            )

        let hit =
            try XCTUnwrap(
                CoverEditorEngine
                    .nearestVectorSegment(
                        in: layer,
                        to:
                            CGPoint(
                                x: 0.50,
                                y: 0.02
                            ),
                        scaleX: 100,
                        scaleY: 100
                    )
            )

        XCTAssertEqual(
            hit.contourIndex,
            0
        )

        XCTAssertEqual(
            hit.startPointIndex,
            0
        )

        XCTAssertEqual(
            hit.t,
            0.5,
            accuracy: 0.0000001
        )

        XCTAssertEqual(
            hit.distance,
            2,
            accuracy: 0.0000001
        )
    }

    func testCubicSegmentHitTestingConvergesToExactCurvePoint() throws {
        let start =
            CoverPathPoint(
                x: 0,
                y: 0,
                controlOutX: 0.2,
                controlOutY: 0.8
            )

        let end =
            CoverPathPoint(
                x: 1,
                y: 1,
                controlInX: 0.8,
                controlInY: 0.2
            )

        let layer =
            makePath(
                [
                    start,
                    end,
                ],
                closed: false
            )

        let exact =
            cubicPoint(
                from: start,
                to: end,
                t: 0.5
            )

        let hit =
            try XCTUnwrap(
                CoverEditorEngine
                    .nearestVectorSegment(
                        in: layer,
                        to: exact,
                        scaleX: 500,
                        scaleY: 500
                    )
            )

        XCTAssertEqual(
            hit.contourIndex,
            0
        )

        XCTAssertEqual(
            hit.startPointIndex,
            0
        )

        XCTAssertEqual(
            hit.t,
            0.5,
            accuracy: 0.00001
        )

        XCTAssertLessThan(
            hit.distance,
            0.001
        )
    }

    func testNearestSegmentChoosesCorrectCompoundContour() throws {
        let primary = [
            CoverPathPoint(
                x: 0.05,
                y: 0.10
            ),
            CoverPathPoint(
                x: 0.35,
                y: 0.10
            ),
            CoverPathPoint(
                x: 0.35,
                y: 0.35
            ),
        ]

        let secondary = [
            CoverPathPoint(
                x: 0.65,
                y: 0.70
            ),
            CoverPathPoint(
                x: 0.95,
                y: 0.70
            ),
            CoverPathPoint(
                x: 0.95,
                y: 0.95
            ),
        ]

        var layer =
            makePath(
                primary,
                closed: true
            )

        layer.pathContours = [
            primary,
            secondary,
        ]

        let hit =
            try XCTUnwrap(
                CoverEditorEngine
                    .nearestVectorSegment(
                        in: layer,
                        to:
                            CGPoint(
                                x: 0.80,
                                y: 0.705
                            ),
                        scaleX: 1000,
                        scaleY: 1000
                    )
            )

        XCTAssertEqual(
            hit.contourIndex,
            1
        )

        XCTAssertEqual(
            hit.startPointIndex,
            0
        )

        XCTAssertEqual(
            hit.t,
            0.5,
            accuracy: 0.0000001
        )

        XCTAssertEqual(
            hit.distance,
            5,
            accuracy: 0.0000001
        )
    }
}
