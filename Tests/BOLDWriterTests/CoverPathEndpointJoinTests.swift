import XCTest
@testable import BOLDWriter

final class CoverPathEndpointJoinTests: XCTestCase {
    private func point(
        _ x: Double,
        _ y: Double = 0,
        type: CoverPathAnchorType? = nil,
        inX: Double? = nil,
        inY: Double? = nil,
        outX: Double? = nil,
        outY: Double? = nil
    ) -> CoverPathPoint {
        CoverPathPoint(
            x: x,
            y: y,
            controlInX: inX,
            controlInY: inY,
            controlOutX: outX,
            controlOutY: outY,
            anchorType: type
        )
    }

    private func openSingle(
        _ points: [CoverPathPoint]
    ) -> CoverLayer {
        var layer =
            CoverLayer(
                kind: .path,
                name: "Open Path"
            )

        layer.pathPoints = points
        layer.pathClosed = false

        return layer
    }

    private func openCompound(
        _ first: [CoverPathPoint],
        _ second: [CoverPathPoint]
    ) -> CoverLayer {
        var layer =
            CoverLayer(
                kind: .path,
                name: "Open Compound"
            )

        layer.pathPoints = first
        layer.pathContours = [
            first,
            second
        ]
        layer.pathClosed = false

        return layer
    }

    func testRejectsSameAnchorTwice() {
        let layer =
            openSingle(
                [
                    point(0),
                    point(1)
                ]
            )

        let anchor =
            CoverVectorAnchorIndex(
                contourIndex: 0,
                pointIndex: 0
            )

        XCTAssertNil(
            CoverEditorEngine
                .joiningVectorEndpoints(
                    in: layer,
                    first: anchor,
                    second: anchor
                )
        )
    }

    func testRejectsInteriorAnchor() {
        let layer =
            openSingle(
                [
                    point(0),
                    point(0.5),
                    point(1)
                ]
            )

        XCTAssertNil(
            CoverEditorEngine
                .joiningVectorEndpoints(
                    in: layer,
                    first:
                        CoverVectorAnchorIndex(
                            contourIndex: 0,
                            pointIndex: 1
                        ),
                    second:
                        CoverVectorAnchorIndex(
                            contourIndex: 0,
                            pointIndex: 2
                        )
                )
        )
    }

    func testSameContourFirstAndLastClosesWithoutChangingAnchors() throws {
        let original = [
            point(
                0,
                type: .corner
            ),
            point(
                0.5,
                0.4,
                type: .smooth,
                inX: 0.3,
                inY: 0.4,
                outX: 0.7,
                outY: 0.4
            ),
            point(
                1,
                type: .symmetric
            )
        ]

        let layer =
            openSingle(
                original
            )

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .joiningVectorEndpoints(
                        in: layer,
                        first:
                            CoverVectorAnchorIndex(
                                contourIndex: 0,
                                pointIndex: 0
                            ),
                        second:
                            CoverVectorAnchorIndex(
                                contourIndex: 0,
                                pointIndex: 2
                            )
                    )
            )

        XCTAssertEqual(
            result.layer.pathClosed,
            true
        )

        XCTAssertEqual(
            result.layer.pathPoints,
            original
        )

        XCTAssertEqual(
            result.layer.pathPoints?.count,
            original.count
        )

        XCTAssertEqual(
            result.selectedAnchors.count,
            2
        )
    }

    func testSameContourClosePreservesExplicitContourRepresentation() throws {
        let original = [
            point(0),
            point(0.5),
            point(1)
        ]

        var layer =
            openSingle(
                original
            )

        layer.pathContours = [
            original
        ]

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .joiningVectorEndpoints(
                        in: layer,
                        first:
                            CoverVectorAnchorIndex(
                                contourIndex: 0,
                                pointIndex: 2
                            ),
                        second:
                            CoverVectorAnchorIndex(
                                contourIndex: 0,
                                pointIndex: 0
                            )
                    )
            )

        XCTAssertEqual(
            result.layer.pathContours,
            [
                original
            ]
        )

        XCTAssertEqual(
            result.layer.pathPoints,
            original
        )

        XCTAssertEqual(
            result.layer.pathClosed,
            true
        )
    }

    func testDifferentContoursLastToFirstNeedsNoReversal() throws {
        let a = [
            point(0),
            point(1)
        ]

        let b = [
            point(2),
            point(3)
        ]

        let layer =
            openCompound(
                a,
                b
            )

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .joiningVectorEndpoints(
                        in: layer,
                        first:
                            CoverVectorAnchorIndex(
                                contourIndex: 0,
                                pointIndex: 1
                            ),
                        second:
                            CoverVectorAnchorIndex(
                                contourIndex: 1,
                                pointIndex: 0
                            )
                    )
            )

        let points =
            try XCTUnwrap(
                result.layer.pathPoints
            )

        XCTAssertEqual(
            points.map(\.x),
            [
                0,
                1,
                2,
                3
            ]
        )

        XCTAssertEqual(
            result.layer.pathClosed,
            false
        )

        XCTAssertEqual(
            result.layer.pathContours?.count,
            1
        )

        XCTAssertEqual(
            result.selectedAnchors,
            [
                CoverVectorAnchorIndex(
                    contourIndex: 0,
                    pointIndex: 1
                ),
                CoverVectorAnchorIndex(
                    contourIndex: 0,
                    pointIndex: 2
                )
            ]
        )
    }

    func testFirstToFirstReversesFirstContour() throws {
        let layer =
            openCompound(
                [
                    point(0),
                    point(1)
                ],
                [
                    point(2),
                    point(3)
                ]
            )

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .joiningVectorEndpoints(
                        in: layer,
                        first:
                            CoverVectorAnchorIndex(
                                contourIndex: 0,
                                pointIndex: 0
                            ),
                        second:
                            CoverVectorAnchorIndex(
                                contourIndex: 1,
                                pointIndex: 0
                            )
                    )
            )

        XCTAssertEqual(
            result.layer
                .pathPoints?
                .map(\.x),
            [
                1,
                0,
                2,
                3
            ]
        )
    }

    func testLastToLastReversesSecondContour() throws {
        let layer =
            openCompound(
                [
                    point(0),
                    point(1)
                ],
                [
                    point(2),
                    point(3)
                ]
            )

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .joiningVectorEndpoints(
                        in: layer,
                        first:
                            CoverVectorAnchorIndex(
                                contourIndex: 0,
                                pointIndex: 1
                            ),
                        second:
                            CoverVectorAnchorIndex(
                                contourIndex: 1,
                                pointIndex: 1
                            )
                    )
            )

        XCTAssertEqual(
            result.layer
                .pathPoints?
                .map(\.x),
            [
                0,
                1,
                3,
                2
            ]
        )
    }

    func testFirstToLastReversesBothContours() throws {
        let layer =
            openCompound(
                [
                    point(0),
                    point(1)
                ],
                [
                    point(2),
                    point(3)
                ]
            )

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .joiningVectorEndpoints(
                        in: layer,
                        first:
                            CoverVectorAnchorIndex(
                                contourIndex: 0,
                                pointIndex: 0
                            ),
                        second:
                            CoverVectorAnchorIndex(
                                contourIndex: 1,
                                pointIndex: 1
                            )
                    )
            )

        XCTAssertEqual(
            result.layer
                .pathPoints?
                .map(\.x),
            [
                1,
                0,
                3,
                2
            ]
        )
    }

    func testReversingContourSwapsBezierHandlesAndPreservesAnchorType() throws {
        let original = [
            point(
                0,
                0,
                type: .corner,
                inX: -0.1,
                inY: -0.2,
                outX: 0.2,
                outY: 0.3
            ),
            point(
                1,
                1,
                type: .smooth,
                inX: 0.7,
                inY: 0.8,
                outX: 1.2,
                outY: 1.3
            )
        ]

        let reversed =
            CoverEditorEngine
                .reversedVectorContour(
                    original
                )

        XCTAssertEqual(
            reversed.count,
            2
        )

        XCTAssertEqual(
            reversed[0].x,
            original[1].x
        )

        XCTAssertEqual(
            reversed[0].y,
            original[1].y
        )

        XCTAssertEqual(
            reversed[0].controlInX,
            original[1].controlOutX
        )

        XCTAssertEqual(
            reversed[0].controlInY,
            original[1].controlOutY
        )

        XCTAssertEqual(
            reversed[0].controlOutX,
            original[1].controlInX
        )

        XCTAssertEqual(
            reversed[0].controlOutY,
            original[1].controlInY
        )

        XCTAssertEqual(
            reversed[0].anchorType,
            .smooth
        )

        XCTAssertEqual(
            reversed[1].controlInX,
            original[0].controlOutX
        )

        XCTAssertEqual(
            reversed[1].controlOutX,
            original[0].controlInX
        )

        XCTAssertEqual(
            reversed[1].anchorType,
            .corner
        )
    }

    func testJoinContainsEveryAnchorExactlyOnce() throws {
        let a = [
            point(0),
            point(1),
            point(2)
        ]

        let b = [
            point(3),
            point(4),
            point(5)
        ]

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .joiningVectorEndpoints(
                        in:
                            openCompound(
                                a,
                                b
                            ),
                        first:
                            CoverVectorAnchorIndex(
                                contourIndex: 0,
                                pointIndex: 2
                            ),
                        second:
                            CoverVectorAnchorIndex(
                                contourIndex: 1,
                                pointIndex: 0
                            )
                    )
            )

        let points =
            try XCTUnwrap(
                result.layer.pathPoints
            )

        XCTAssertEqual(
            points.count,
            6
        )

        XCTAssertEqual(
            points.map(\.x),
            [
                0,
                1,
                2,
                3,
                4,
                5
            ]
        )

        XCTAssertEqual(
            Set(
                points.map(\.x)
            )
            .count,
            6
        )
    }

    func testRejectsClosedLayer() {
        var layer =
            openSingle(
                [
                    point(0),
                    point(1),
                    point(2)
                ]
            )

        layer.pathClosed = true

        XCTAssertNil(
            CoverEditorEngine
                .joiningVectorEndpoints(
                    in: layer,
                    first:
                        CoverVectorAnchorIndex(
                            contourIndex: 0,
                            pointIndex: 0
                        ),
                    second:
                        CoverVectorAnchorIndex(
                            contourIndex: 0,
                            pointIndex: 2
                        )
                )
        )
    }

    func testJoinInsideThreeContourLayerPreservesUnrelatedContour() throws {
        let a = [
            point(0),
            point(1)
        ]

        let b = [
            point(2),
            point(3)
        ]

        let c = [
            point(4),
            point(5),
            point(6)
        ]

        var layer =
            CoverLayer(
                kind: .path,
                name: "Mixed Contours"
            )

        layer.pathPoints = a
        layer.pathContours = [
            a,
            b,
            c
        ]
        layer.pathClosed = false
        layer.pathContourClosed = [
            false,
            false,
            true
        ]

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .joiningVectorEndpoints(
                        in: layer,
                        first:
                            CoverVectorAnchorIndex(
                                contourIndex: 0,
                                pointIndex: 1
                            ),
                        second:
                            CoverVectorAnchorIndex(
                                contourIndex: 1,
                                pointIndex: 0
                            )
                    )
            )

        let contours =
            try XCTUnwrap(
                result.layer.pathContours
            )

        XCTAssertEqual(
            contours.count,
            2
        )

        XCTAssertEqual(
            contours[0].map(\.x),
            [
                0,
                1,
                2,
                3
            ]
        )

        XCTAssertEqual(
            contours[1],
            c
        )

        XCTAssertEqual(
            result.layer.pathContourClosed,
            [
                false,
                true
            ]
        )

        XCTAssertEqual(
            result.layer.pathClosed,
            false
        )
    }

    func testJoinPreservesLayerMetadataAndStyling() throws {
        var layer =
            openCompound(
                [
                    point(0),
                    point(1)
                ],
                [
                    point(2),
                    point(3)
                ]
            )

        layer.name =
            "Styled Open Path"

        layer.frame =
            CoverRect(
                x: 0.12,
                y: 0.18,
                width: 0.61,
                height: 0.43
            )

        layer.fillHex =
            "#112233"

        layer.strokeHex =
            "#AABBCC"

        layer.strokeWidth = 6.5
        layer.opacity = 0.72
        layer.rotation = 19
        layer.flipHorizontal = true
        layer.flipVertical = true

        let originalID =
            layer.id

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .joiningVectorEndpoints(
                        in: layer,
                        first:
                            CoverVectorAnchorIndex(
                                contourIndex: 0,
                                pointIndex: 1
                            ),
                        second:
                            CoverVectorAnchorIndex(
                                contourIndex: 1,
                                pointIndex: 0
                            )
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

    func testJoinedLayerPersistsAndReopens() throws {
        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .joiningVectorEndpoints(
                        in:
                            openCompound(
                                [
                                    point(
                                        0,
                                        type: .corner
                                    ),
                                    point(
                                        1,
                                        type: .smooth,
                                        outX: 1.2,
                                        outY: 0.1
                                    )
                                ],
                                [
                                    point(
                                        2,
                                        type: .symmetric,
                                        inX: 1.8,
                                        inY: -0.1
                                    ),
                                    point(3)
                                ]
                            ),
                        first:
                            CoverVectorAnchorIndex(
                                contourIndex: 0,
                                pointIndex: 1
                            ),
                        second:
                            CoverVectorAnchorIndex(
                                contourIndex: 1,
                                pointIndex: 0
                            )
                    )
            )

        let reopened =
            try JSONDecoder()
                .decode(
                    CoverLayer.self,
                    from:
                        JSONEncoder()
                            .encode(
                                result.layer
                            )
                )

        XCTAssertEqual(
            reopened,
            result.layer
        )

        XCTAssertEqual(
            reopened.pathPoints,
            reopened.pathContours?.first
        )

        XCTAssertEqual(
            reopened.pathClosed,
            false
        )
    }
}
