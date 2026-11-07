import XCTest
import CoreGraphics
@testable import BOLDWriter

final class CoverPathAnchorTypeTests: XCTestCase {
    private func distance(
        _ ax: Double,
        _ ay: Double,
        _ bx: Double,
        _ by: Double
    ) -> Double {
        hypot(
            bx - ax,
            by - ay
        )
    }

    private func cross(
        _ ax: Double,
        _ ay: Double,
        _ bx: Double,
        _ by: Double
    ) -> Double {
        ax * by
        - ay * bx
    }

    func testLegacyCoverPathPointDecodesWithoutAnchorType() throws {
        let data =
            try XCTUnwrap(
                """
                {
                  "x": 0.25,
                  "y": 0.75,
                  "controlInX": 0.1,
                  "controlInY": 0.7
                }
                """
                .data(
                    using: .utf8
                )
            )

        let point =
            try JSONDecoder()
                .decode(
                    CoverPathPoint.self,
                    from: data
                )

        XCTAssertEqual(
            point.x,
            0.25,
            accuracy: 0.0000001
        )

        XCTAssertEqual(
            point.y,
            0.75,
            accuracy: 0.0000001
        )

        XCTAssertNil(
            point.anchorType
        )
    }

    func testAnchorTypeRoundTripsThroughCodable() throws {
        let point =
            CoverPathPoint(
                x: 0.4,
                y: 0.6,
                controlInX: 0.2,
                controlInY: 0.6,
                controlOutX: 0.7,
                controlOutY: 0.6,
                anchorType: .smooth
            )

        let encoded =
            try JSONEncoder()
                .encode(
                    point
                )

        let decoded =
            try JSONDecoder()
                .decode(
                    CoverPathPoint.self,
                    from: encoded
                )

        XCTAssertEqual(
            decoded,
            point
        )

        XCTAssertEqual(
            decoded.anchorType,
            .smooth
        )
    }

    func testCornerConversionPreservesGeometry() {
        let points = [
            CoverPathPoint(
                x: 0,
                y: 0
            ),
            CoverPathPoint(
                x: 0.5,
                y: 0.5,
                controlInX: 0.2,
                controlInY: 0.3,
                controlOutX: 0.8,
                controlOutY: 0.65,
                anchorType: .smooth
            ),
            CoverPathPoint(
                x: 1,
                y: 1
            ),
        ]

        let changed =
            CoverEditorEngine
                .settingPathAnchorType(
                    points,
                    index: 1,
                    type: .corner,
                    closed: false
                )

        XCTAssertEqual(
            changed[1].anchorType,
            .corner
        )

        XCTAssertEqual(
            changed[1].x,
            points[1].x
        )

        XCTAssertEqual(
            changed[1].y,
            points[1].y
        )

        XCTAssertEqual(
            changed[1].controlInX,
            points[1].controlInX
        )

        XCTAssertEqual(
            changed[1].controlInY,
            points[1].controlInY
        )

        XCTAssertEqual(
            changed[1].controlOutX,
            points[1].controlOutX
        )

        XCTAssertEqual(
            changed[1].controlOutY,
            points[1].controlOutY
        )
    }

    func testSmoothConversionIsCollinearAndPreservesHandleLengths() throws {
        let points = [
            CoverPathPoint(
                x: 0,
                y: 0.5
            ),
            CoverPathPoint(
                x: 0.5,
                y: 0.5,
                controlInX: 0.25,
                controlInY: 0.30,
                controlOutX: 0.85,
                controlOutY: 0.75
            ),
            CoverPathPoint(
                x: 1,
                y: 0.5
            ),
        ]

        let inLengthBefore =
            distance(
                points[1].x,
                points[1].y,
                try XCTUnwrap(
                    points[1].controlInX
                ),
                try XCTUnwrap(
                    points[1].controlInY
                )
            )

        let outLengthBefore =
            distance(
                points[1].x,
                points[1].y,
                try XCTUnwrap(
                    points[1].controlOutX
                ),
                try XCTUnwrap(
                    points[1].controlOutY
                )
            )

        let changed =
            CoverEditorEngine
                .settingPathAnchorType(
                    points,
                    index: 1,
                    type: .smooth,
                    closed: false
                )

        let point = changed[1]

        let inX =
            try XCTUnwrap(
                point.controlInX
            )

        let inY =
            try XCTUnwrap(
                point.controlInY
            )

        let outX =
            try XCTUnwrap(
                point.controlOutX
            )

        let outY =
            try XCTUnwrap(
                point.controlOutY
            )

        XCTAssertEqual(
            point.anchorType,
            .smooth
        )

        XCTAssertEqual(
            cross(
                inX - point.x,
                inY - point.y,
                outX - point.x,
                outY - point.y
            ),
            0,
            accuracy: 0.0000001
        )

        XCTAssertLessThan(
            (
                inX - point.x
            )
            * (
                outX - point.x
            )
            + (
                inY - point.y
            )
            * (
                outY - point.y
            ),
            0
        )

        XCTAssertEqual(
            distance(
                point.x,
                point.y,
                inX,
                inY
            ),
            inLengthBefore,
            accuracy: 0.0000001
        )

        XCTAssertEqual(
            distance(
                point.x,
                point.y,
                outX,
                outY
            ),
            outLengthBefore,
            accuracy: 0.0000001
        )
    }

    func testSymmetricConversionCreatesEqualOpposingHandles() throws {
        let points = [
            CoverPathPoint(
                x: 0,
                y: 0.5
            ),
            CoverPathPoint(
                x: 0.5,
                y: 0.5,
                controlInX: 0.30,
                controlInY: 0.20,
                controlOutX: 0.90,
                controlOutY: 0.70
            ),
            CoverPathPoint(
                x: 1,
                y: 0.5
            ),
        ]

        let changed =
            CoverEditorEngine
                .settingPathAnchorType(
                    points,
                    index: 1,
                    type: .symmetric,
                    closed: false
                )

        let point = changed[1]

        let inX =
            try XCTUnwrap(
                point.controlInX
            )

        let inY =
            try XCTUnwrap(
                point.controlInY
            )

        let outX =
            try XCTUnwrap(
                point.controlOutX
            )

        let outY =
            try XCTUnwrap(
                point.controlOutY
            )

        XCTAssertEqual(
            point.anchorType,
            .symmetric
        )

        XCTAssertEqual(
            inX + outX,
            point.x * 2,
            accuracy: 0.0000001
        )

        XCTAssertEqual(
            inY + outY,
            point.y * 2,
            accuracy: 0.0000001
        )

        XCTAssertEqual(
            distance(
                point.x,
                point.y,
                inX,
                inY
            ),
            distance(
                point.x,
                point.y,
                outX,
                outY
            ),
            accuracy: 0.0000001
        )
    }

    func testCornerHandleDragChangesOnlyDraggedHandle() throws {
        let points = [
            CoverPathPoint(
                x: 0.5,
                y: 0.5,
                controlInX: 0.2,
                controlInY: 0.5,
                controlOutX: 0.8,
                controlOutY: 0.5,
                anchorType: .corner
            )
        ]

        let changed =
            CoverEditorEngine
                .movedPathControl(
                    points,
                    index: 0,
                    to:
                        CGPoint(
                            x: 0.9,
                            y: 0.7
                        ),
                    incoming: false,
                    mirrorOpposite: true
                )

        XCTAssertEqual(
            try XCTUnwrap(
                changed[0].controlOutX
            ),
            0.9,
            accuracy: 0.0000001
        )

        XCTAssertEqual(
            try XCTUnwrap(
                changed[0].controlOutY
            ),
            0.7,
            accuracy: 0.0000001
        )

        XCTAssertEqual(
            changed[0].controlInX,
            points[0].controlInX
        )

        XCTAssertEqual(
            changed[0].controlInY,
            points[0].controlInY
        )
    }

    func testSmoothHandleDragPreservesOppositeLength() throws {
        let points = [
            CoverPathPoint(
                x: 0.5,
                y: 0.5,
                controlInX: 0.2,
                controlInY: 0.5,
                controlOutX: 0.8,
                controlOutY: 0.5,
                anchorType: .smooth
            )
        ]

        let oppositeLength =
            distance(
                0.5,
                0.5,
                0.2,
                0.5
            )

        let changed =
            CoverEditorEngine
                .movedPathControl(
                    points,
                    index: 0,
                    to:
                        CGPoint(
                            x: 0.7,
                            y: 0.8
                        ),
                    incoming: false,
                    mirrorOpposite: false
                )

        let point = changed[0]

        let inX =
            try XCTUnwrap(
                point.controlInX
            )

        let inY =
            try XCTUnwrap(
                point.controlInY
            )

        let outX =
            try XCTUnwrap(
                point.controlOutX
            )

        let outY =
            try XCTUnwrap(
                point.controlOutY
            )

        XCTAssertEqual(
            cross(
                inX - point.x,
                inY - point.y,
                outX - point.x,
                outY - point.y
            ),
            0,
            accuracy: 0.0000001
        )

        XCTAssertLessThan(
            (
                inX - point.x
            )
            * (
                outX - point.x
            )
            + (
                inY - point.y
            )
            * (
                outY - point.y
            ),
            0
        )

        XCTAssertEqual(
            distance(
                point.x,
                point.y,
                inX,
                inY
            ),
            oppositeLength,
            accuracy: 0.0000001
        )
    }

    func testSymmetricHandleDragMirrorsExactly() throws {
        let points = [
            CoverPathPoint(
                x: 0.5,
                y: 0.5,
                controlInX: 0.2,
                controlInY: 0.5,
                controlOutX: 0.8,
                controlOutY: 0.5,
                anchorType: .symmetric
            )
        ]

        let changed =
            CoverEditorEngine
                .movedPathControl(
                    points,
                    index: 0,
                    to:
                        CGPoint(
                            x: 0.75,
                            y: 0.90
                        ),
                    incoming: false,
                    mirrorOpposite: false
                )

        XCTAssertEqual(
            try XCTUnwrap(
                changed[0].controlOutX
            ),
            0.75,
            accuracy: 0.0000001
        )

        XCTAssertEqual(
            try XCTUnwrap(
                changed[0].controlOutY
            ),
            0.90,
            accuracy: 0.0000001
        )

        XCTAssertEqual(
            try XCTUnwrap(
                changed[0].controlInX
            ),
            0.25,
            accuracy: 0.0000001
        )

        XCTAssertEqual(
            try XCTUnwrap(
                changed[0].controlInY
            ),
            0.10,
            accuracy: 0.0000001
        )
    }

    func testLegacyMirrorBehaviorRemainsCompatible() throws {
        let points = [
            CoverPathPoint(
                x: 0.5,
                y: 0.5,
                controlInX: 0.2,
                controlInY: 0.5,
                controlOutX: 0.8,
                controlOutY: 0.5
            )
        ]

        let changed =
            CoverEditorEngine
                .movedPathControl(
                    points,
                    index: 0,
                    to:
                        CGPoint(
                            x: 0.9,
                            y: 0.6
                        ),
                    incoming: false,
                    mirrorOpposite: true
                )

        XCTAssertNil(
            changed[0].anchorType
        )

        XCTAssertEqual(
            try XCTUnwrap(
                changed[0].controlInX
            ),
            0.1,
            accuracy: 0.0000001
        )

        XCTAssertEqual(
            try XCTUnwrap(
                changed[0].controlInY
            ),
            0.4,
            accuracy: 0.0000001
        )
    }

    func testBreakHandlesPreservesGeometry() {
        let point =
            CoverPathPoint(
                x: 0.5,
                y: 0.5,
                controlInX: 0.2,
                controlInY: 0.4,
                controlOutX: 0.8,
                controlOutY: 0.6,
                anchorType: .symmetric
            )

        let changed =
            CoverEditorEngine
                .settingPathAnchorType(
                    [
                        point
                    ],
                    index: 0,
                    type: .corner,
                    closed: false
                )

        XCTAssertEqual(
            changed[0].anchorType,
            .corner
        )

        XCTAssertEqual(
            changed[0].controlInX,
            point.controlInX
        )

        XCTAssertEqual(
            changed[0].controlInY,
            point.controlInY
        )

        XCTAssertEqual(
            changed[0].controlOutX,
            point.controlOutX
        )

        XCTAssertEqual(
            changed[0].controlOutY,
            point.controlOutY
        )
    }

    func testMultiAnchorConversionAcrossCompoundContours() throws {
        let primary = [
            CoverPathPoint(
                x: 0,
                y: 0
            ),
            CoverPathPoint(
                x: 0.4,
                y: 0,
                controlInX: 0.3,
                controlInY: 0,
                controlOutX: 0.5,
                controlOutY: 0
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
                y: 0.6,
                controlInX: 0.8,
                controlInY: 0.6,
                controlOutX: 1.0,
                controlOutY: 0.6
            ),
            CoverPathPoint(
                x: 0.9,
                y: 0.9
            ),
        ]

        var layer =
            CoverLayer(
                kind: .path,
                name: "Compound"
            )

        layer.pathPoints = primary
        layer.pathContours = [
            primary,
            secondary
        ]
        layer.pathClosed = true

        let changed =
            CoverEditorEngine
                .settingVectorAnchorType(
                    in: layer,
                    selections: [
                        CoverVectorAnchorIndex(
                            contourIndex: 0,
                            pointIndex: 1
                        ),
                        CoverVectorAnchorIndex(
                            contourIndex: 1,
                            pointIndex: 1
                        )
                    ],
                    type: .symmetric
                )

        let contours =
            try XCTUnwrap(
                changed.pathContours
            )

        XCTAssertEqual(
            contours[0][1].anchorType,
            .symmetric
        )

        XCTAssertEqual(
            contours[1][1].anchorType,
            .symmetric
        )

        XCTAssertNil(
            contours[0][0].anchorType
        )

        XCTAssertNil(
            contours[1][0].anchorType
        )

        XCTAssertEqual(
            changed.pathPoints,
            contours[0]
        )
    }

    func testSingleContourConversionKeepsPathPointsSynchronized() throws {
        var layer =
            CoverLayer(
                kind: .path,
                name: "Path"
            )

        layer.pathPoints = [
            CoverPathPoint(
                x: 0,
                y: 0
            ),
            CoverPathPoint(
                x: 0.5,
                y: 0.5
            ),
            CoverPathPoint(
                x: 1,
                y: 0
            )
        ]

        let changed =
            CoverEditorEngine
                .settingVectorAnchorType(
                    in: layer,
                    selections: [
                        CoverVectorAnchorIndex(
                            contourIndex: 0,
                            pointIndex: 1
                        )
                    ],
                    type: .smooth
                )

        let points =
            try XCTUnwrap(
                changed.pathPoints
            )

        XCTAssertEqual(
            points[1].anchorType,
            .smooth
        )

        XCTAssertNil(
            changed.pathContours
        )
    }
}
