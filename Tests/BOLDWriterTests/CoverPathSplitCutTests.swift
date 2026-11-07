import XCTest
@testable import BOLDWriter

final class CoverPathSplitCutTests: XCTestCase {
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

    private func pathLayer(
        _ points: [CoverPathPoint],
        closed: Bool
    ) -> CoverLayer {
        var layer =
            CoverLayer(
                kind: .path,
                name: "Vector Path"
            )

        layer.pathPoints =
            points

        layer.pathClosed =
            closed

        return layer
    }

    func testSplitRejectsNonPathLayer() {
        var layer =
            CoverLayer(
                kind: .shape,
                name: "Shape"
            )

        layer.pathPoints = [
            point(0),
            point(0.5),
            point(1)
        ]

        layer.pathClosed = false

        XCTAssertNil(
            CoverEditorEngine
                .splittingVectorPath(
                    in: layer,
                    at:
                        CoverVectorAnchorIndex(
                            contourIndex: 0,
                            pointIndex: 1
                        )
                )
        )
    }

    func testSplitExistingCompoundPathPreservesUnrelatedContour() throws {
        let first = [
            point(0),
            point(1),
            point(2)
        ]

        let second = [
            point(3),
            point(4),
            point(5)
        ]

        var layer =
            pathLayer(
                first,
                closed: true
            )

        layer.pathContours = [
            first,
            second
        ]

        layer.pathContourClosed = [
            true,
            false
        ]

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .splittingVectorPath(
                        in: layer,
                        at:
                            CoverVectorAnchorIndex(
                                contourIndex: 1,
                                pointIndex: 1
                            )
                    )
            )

        let contours =
            try XCTUnwrap(
                result.layer.pathContours
            )

        XCTAssertEqual(
            contours.count,
            3
        )

        XCTAssertEqual(
            contours[0],
            first
        )

        XCTAssertEqual(
            contours[1].map(\.x),
            [
                3,
                4
            ]
        )

        XCTAssertEqual(
            contours[2].map(\.x),
            [
                4,
                5
            ]
        )

        XCTAssertEqual(
            result.layer.pathContourClosed,
            [
                true,
                false,
                false
            ]
        )

        XCTAssertEqual(
            result.layer.pathClosed,
            true
        )
    }

    func testSplitRejectsInvalidAnchorAndOpenEndpoints() {
        let layer =
            pathLayer(
                [
                    point(0),
                    point(1),
                    point(2),
                    point(3)
                ],
                closed: false
            )

        XCTAssertNil(
            CoverEditorEngine
                .splittingVectorPath(
                    in: layer,
                    at:
                        CoverVectorAnchorIndex(
                            contourIndex: 4,
                            pointIndex: 1
                        )
                )
        )

        XCTAssertNil(
            CoverEditorEngine
                .splittingVectorPath(
                    in: layer,
                    at:
                        CoverVectorAnchorIndex(
                            contourIndex: 0,
                            pointIndex: 99
                        )
                )
        )

        XCTAssertNil(
            CoverEditorEngine
                .splittingVectorPath(
                    in: layer,
                    at:
                        CoverVectorAnchorIndex(
                            contourIndex: 0,
                            pointIndex: 0
                        )
                )
        )

        XCTAssertNil(
            CoverEditorEngine
                .splittingVectorPath(
                    in: layer,
                    at:
                        CoverVectorAnchorIndex(
                            contourIndex: 0,
                            pointIndex: 3
                        )
                )
        )
    }

    func testSplitOpenContourCreatesTwoOpenPieces() throws {
        let original = [
            point(0),
            point(1),
            point(2),
            point(3),
            point(4)
        ]

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .splittingVectorPath(
                        in:
                            pathLayer(
                                original,
                                closed: false
                            ),
                        at:
                            CoverVectorAnchorIndex(
                                contourIndex: 0,
                                pointIndex: 2
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
                2
            ]
        )

        XCTAssertEqual(
            contours[1].map(\.x),
            [
                2,
                3,
                4
            ]
        )

        XCTAssertEqual(
            result.layer.pathClosed,
            false
        )

        XCTAssertEqual(
            result.layer.pathPoints,
            contours[0]
        )

        XCTAssertEqual(
            result.selectedAnchors,
            [
                CoverVectorAnchorIndex(
                    contourIndex: 0,
                    pointIndex: 2
                ),
                CoverVectorAnchorIndex(
                    contourIndex: 1,
                    pointIndex: 0
                )
            ]
        )
    }

    func testSplitBoundaryCopiesPreserveOnlySurvivingHandlesAndBecomeCorner() throws {
        let split =
            point(
                1,
                1,
                type: .symmetric,
                inX: 0.7,
                inY: 0.8,
                outX: 1.3,
                outY: 1.2
            )

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .splittingVectorPath(
                        in:
                            pathLayer(
                                [
                                    point(0),
                                    split,
                                    point(2)
                                ],
                                closed: false
                            ),
                        at:
                            CoverVectorAnchorIndex(
                                contourIndex: 0,
                                pointIndex: 1
                            )
                    )
            )

        let contours =
            try XCTUnwrap(
                result.layer.pathContours
            )

        let incomingSide =
            try XCTUnwrap(
                contours[0].last
            )

        let outgoingSide =
            contours[1][0]

        XCTAssertEqual(
            incomingSide.x,
            split.x
        )

        XCTAssertEqual(
            incomingSide.y,
            split.y
        )

        XCTAssertEqual(
            incomingSide.controlInX,
            split.controlInX
        )

        XCTAssertEqual(
            incomingSide.controlInY,
            split.controlInY
        )

        XCTAssertNil(
            incomingSide.controlOutX
        )

        XCTAssertNil(
            incomingSide.controlOutY
        )

        XCTAssertEqual(
            incomingSide.anchorType,
            .corner
        )

        XCTAssertNil(
            outgoingSide.controlInX
        )

        XCTAssertNil(
            outgoingSide.controlInY
        )

        XCTAssertEqual(
            outgoingSide.controlOutX,
            split.controlOutX
        )

        XCTAssertEqual(
            outgoingSide.controlOutY,
            split.controlOutY
        )

        XCTAssertEqual(
            outgoingSide.anchorType,
            .corner
        )
    }

    func testSplitOpenContourPreservesEveryNonBoundaryAnchorExactlyOnce() throws {
        let original = [
            point(0, type: .corner),
            point(1, type: .smooth),
            point(2, type: .symmetric),
            point(3, type: .corner),
            point(4, type: .smooth)
        ]

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .splittingVectorPath(
                        in:
                            pathLayer(
                                original,
                                closed: false
                            ),
                        at:
                            CoverVectorAnchorIndex(
                                contourIndex: 0,
                                pointIndex: 2
                            )
                    )
            )

        let contours =
            try XCTUnwrap(
                result.layer.pathContours
            )

        let flattened =
            contours.flatMap {
                $0
            }

        XCTAssertEqual(
            flattened.count,
            original.count + 1
        )

        XCTAssertEqual(
            flattened.filter {
                $0.x == 0
            }
            .count,
            1
        )

        XCTAssertEqual(
            flattened.filter {
                $0.x == 1
            }
            .count,
            1
        )

        XCTAssertEqual(
            flattened.filter {
                $0.x == 2
            }
            .count,
            2
        )

        XCTAssertEqual(
            flattened.filter {
                $0.x == 3
            }
            .count,
            1
        )

        XCTAssertEqual(
            flattened.filter {
                $0.x == 4
            }
            .count,
            1
        )
    }

    func testSplitClosedContourOpensAtSelectedAnchorAndRotatesOrder() throws {
        let original = [
            point(0),
            point(1),
            point(2),
            point(3)
        ]

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .splittingVectorPath(
                        in:
                            pathLayer(
                                original,
                                closed: true
                            ),
                        at:
                            CoverVectorAnchorIndex(
                                contourIndex: 0,
                                pointIndex: 2
                            )
                    )
            )

        let contours =
            try XCTUnwrap(
                result.layer.pathContours
            )

        XCTAssertEqual(
            contours.count,
            1
        )

        XCTAssertEqual(
            contours[0].map(\.x),
            [
                2,
                3,
                0,
                1,
                2
            ]
        )

        XCTAssertEqual(
            result.layer.pathClosed,
            false
        )

        XCTAssertEqual(
            result.layer.pathPoints,
            contours[0]
        )

        XCTAssertEqual(
            result.selectedAnchors,
            [
                CoverVectorAnchorIndex(
                    contourIndex: 0,
                    pointIndex: 0
                ),
                CoverVectorAnchorIndex(
                    contourIndex: 0,
                    pointIndex: 4
                )
            ]
        )
    }

    func testSplitClosedContourPreservesBothSidesOfCutBezierAnchor() throws {
        let selected =
            point(
                2,
                2,
                type: .smooth,
                inX: 1.7,
                inY: 1.8,
                outX: 2.3,
                outY: 2.2
            )

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .splittingVectorPath(
                        in:
                            pathLayer(
                                [
                                    point(0),
                                    point(1),
                                    selected,
                                    point(3)
                                ],
                                closed: true
                            ),
                        at:
                            CoverVectorAnchorIndex(
                                contourIndex: 0,
                                pointIndex: 2
                            )
                    )
            )

        let contour =
            try XCTUnwrap(
                result.layer
                    .pathContours?
                    .first
            )

        let outgoingCopy =
            contour[0]

        let incomingCopy =
            try XCTUnwrap(
                contour.last
            )

        XCTAssertNil(
            outgoingCopy.controlInX
        )

        XCTAssertEqual(
            outgoingCopy.controlOutX,
            selected.controlOutX
        )

        XCTAssertEqual(
            outgoingCopy.anchorType,
            .corner
        )

        XCTAssertEqual(
            incomingCopy.controlInX,
            selected.controlInX
        )

        XCTAssertNil(
            incomingCopy.controlOutX
        )

        XCTAssertEqual(
            incomingCopy.anchorType,
            .corner
        )
    }

    func testCutOpenContourAtTwoInteriorAnchorsCreatesThreePieces() throws {
        let original = [
            point(0),
            point(1),
            point(2),
            point(3),
            point(4),
            point(5)
        ]

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .cuttingVectorPath(
                        in:
                            pathLayer(
                                original,
                                closed: false
                            ),
                        first:
                            CoverVectorAnchorIndex(
                                contourIndex: 0,
                                pointIndex: 1
                            ),
                        second:
                            CoverVectorAnchorIndex(
                                contourIndex: 0,
                                pointIndex: 4
                            )
                    )
            )

        let contours =
            try XCTUnwrap(
                result.layer.pathContours
            )

        XCTAssertEqual(
            contours.count,
            3
        )

        XCTAssertEqual(
            contours[0].map(\.x),
            [
                0,
                1
            ]
        )

        XCTAssertEqual(
            contours[1].map(\.x),
            [
                1,
                2,
                3,
                4
            ]
        )

        XCTAssertEqual(
            contours[2].map(\.x),
            [
                4,
                5
            ]
        )

        XCTAssertEqual(
            result.layer.pathClosed,
            false
        )

        XCTAssertEqual(
            result.layer.pathPoints,
            contours[0]
        )

        XCTAssertEqual(
            result.selectedAnchors.count,
            4
        )
    }

    func testCutOpenContourAllowsEndpointAndInteriorAnchor() throws {
        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .cuttingVectorPath(
                        in:
                            pathLayer(
                                [
                                    point(0),
                                    point(1),
                                    point(2),
                                    point(3)
                                ],
                                closed: false
                            ),
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
                2
            ]
        )

        XCTAssertEqual(
            contours[1].map(\.x),
            [
                2,
                3
            ]
        )
    }

    func testCutOpenContourRejectsBothExistingEndpointsBecauseNothingIsSplit() {
        let layer =
            pathLayer(
                [
                    point(0),
                    point(1),
                    point(2),
                    point(3)
                ],
                closed: false
            )

        XCTAssertNil(
            CoverEditorEngine
                .cuttingVectorPath(
                    in: layer,
                    first:
                        CoverVectorAnchorIndex(
                            contourIndex: 0,
                            pointIndex: 0
                        ),
                    second:
                        CoverVectorAnchorIndex(
                            contourIndex: 0,
                            pointIndex: 3
                        )
                )
        )
    }

    func testCutClosedContourProducesTwoOpenWraparoundPieces() throws {
        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .cuttingVectorPath(
                        in:
                            pathLayer(
                                [
                                    point(0),
                                    point(1),
                                    point(2),
                                    point(3),
                                    point(4)
                                ],
                                closed: true
                            ),
                        first:
                            CoverVectorAnchorIndex(
                                contourIndex: 0,
                                pointIndex: 1
                            ),
                        second:
                            CoverVectorAnchorIndex(
                                contourIndex: 0,
                                pointIndex: 3
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
                1,
                2,
                3
            ]
        )

        XCTAssertEqual(
            contours[1].map(\.x),
            [
                3,
                4,
                0,
                1
            ]
        )

        XCTAssertEqual(
            result.layer.pathClosed,
            false
        )

        XCTAssertEqual(
            result.selectedAnchors.count,
            4
        )
    }

    func testCutClosedBoundaryHandlesPreserveOnlySurvivingSide() throws {
        let first =
            point(
                1,
                1,
                type: .symmetric,
                inX: 0.7,
                inY: 0.8,
                outX: 1.3,
                outY: 1.2
            )

        let second =
            point(
                3,
                3,
                type: .smooth,
                inX: 2.7,
                inY: 2.8,
                outX: 3.3,
                outY: 3.2
            )

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .cuttingVectorPath(
                        in:
                            pathLayer(
                                [
                                    point(0),
                                    first,
                                    point(2),
                                    second,
                                    point(4)
                                ],
                                closed: true
                            ),
                        first:
                            CoverVectorAnchorIndex(
                                contourIndex: 0,
                                pointIndex: 1
                            ),
                        second:
                            CoverVectorAnchorIndex(
                                contourIndex: 0,
                                pointIndex: 3
                            )
                    )
            )

        let contours =
            try XCTUnwrap(
                result.layer.pathContours
            )

        let aFirst =
            contours[0][0]

        let aLast =
            try XCTUnwrap(
                contours[0].last
            )

        let bFirst =
            contours[1][0]

        let bLast =
            try XCTUnwrap(
                contours[1].last
            )

        XCTAssertNil(
            aFirst.controlInX
        )

        XCTAssertEqual(
            aFirst.controlOutX,
            first.controlOutX
        )

        XCTAssertEqual(
            aFirst.anchorType,
            .corner
        )

        XCTAssertEqual(
            aLast.controlInX,
            second.controlInX
        )

        XCTAssertNil(
            aLast.controlOutX
        )

        XCTAssertEqual(
            aLast.anchorType,
            .corner
        )

        XCTAssertNil(
            bFirst.controlInX
        )

        XCTAssertEqual(
            bFirst.controlOutX,
            second.controlOutX
        )

        XCTAssertEqual(
            bFirst.anchorType,
            .corner
        )

        XCTAssertEqual(
            bLast.controlInX,
            first.controlInX
        )

        XCTAssertNil(
            bLast.controlOutX
        )

        XCTAssertEqual(
            bLast.anchorType,
            .corner
        )
    }

    func testCutCompoundPathPreservesUnrelatedContourAndRejectsCrossContourSelection() throws {
        let first = [
            point(0),
            point(1),
            point(2)
        ]

        let second = [
            point(3),
            point(4),
            point(5),
            point(6)
        ]

        var layer =
            pathLayer(
                first,
                closed: true
            )

        layer.pathContours = [
            first,
            second
        ]

        layer.pathContourClosed = [
            true,
            false
        ]

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .cuttingVectorPath(
                        in: layer,
                        first:
                            CoverVectorAnchorIndex(
                                contourIndex: 1,
                                pointIndex: 1
                            ),
                        second:
                            CoverVectorAnchorIndex(
                                contourIndex: 1,
                                pointIndex: 2
                            )
                    )
            )

        let contours =
            try XCTUnwrap(
                result.layer.pathContours
            )

        XCTAssertEqual(
            contours[0],
            first
        )

        XCTAssertEqual(
            result.layer
                .pathContourClosed?
                .first,
            true
        )

        XCTAssertNil(
            CoverEditorEngine
                .cuttingVectorPath(
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
    }

    func testSplitPreservesLayerMetadataAndStyling() throws {
        var layer =
            pathLayer(
                [
                    point(0),
                    point(1),
                    point(2)
                ],
                closed: false
            )

        layer.name =
            "Styled Split"

        layer.frame =
            CoverRect(
                x: 0.12,
                y: 0.17,
                width: 0.64,
                height: 0.42
            )

        layer.fillHex =
            "#123456"

        layer.strokeHex =
            "#FEDCBA"

        layer.strokeWidth =
            5.5

        layer.opacity =
            0.71

        layer.rotation =
            17

        layer.flipHorizontal =
            true

        layer.flipVertical =
            true

        let originalID =
            layer.id

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .splittingVectorPath(
                        in: layer,
                        at:
                            CoverVectorAnchorIndex(
                                contourIndex: 0,
                                pointIndex: 1
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

    func testCutPreservesLayerMetadataAndStyling() throws {
        var layer =
            pathLayer(
                [
                    point(0),
                    point(1),
                    point(2),
                    point(3)
                ],
                closed: false
            )

        layer.name =
            "Styled Cut"

        layer.frame =
            CoverRect(
                x: 0.2,
                y: 0.3,
                width: 0.5,
                height: 0.4
            )

        layer.strokeWidth =
            8

        layer.opacity =
            0.55

        let originalID =
            layer.id

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .cuttingVectorPath(
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
            result.layer.strokeWidth,
            layer.strokeWidth,
            accuracy: 0.0000001
        )

        XCTAssertEqual(
            result.layer.opacity,
            layer.opacity,
            accuracy: 0.0000001
        )
    }

    func testSplitResultPersistsAndReopens() throws {
        let original = [
            point(0),
            point(
                1,
                type: .smooth,
                inX: 0.7,
                inY: 0,
                outX: 1.3,
                outY: 0
            ),
            point(2)
        ]

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .splittingVectorPath(
                        in:
                            pathLayer(
                                original,
                                closed: false
                            ),
                        at:
                            CoverVectorAnchorIndex(
                                contourIndex: 0,
                                pointIndex: 1
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
            reopened.pathClosed,
            false
        )

        XCTAssertEqual(
            reopened.pathPoints,
            reopened.pathContours?.first
        )
    }

    func testCutResultPersistsAndReopens() throws {
        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .cuttingVectorPath(
                        in:
                            pathLayer(
                                [
                                    point(0),
                                    point(1),
                                    point(2),
                                    point(3),
                                    point(4)
                                ],
                                closed: true
                            ),
                        first:
                            CoverVectorAnchorIndex(
                                contourIndex: 0,
                                pointIndex: 1
                            ),
                        second:
                            CoverVectorAnchorIndex(
                                contourIndex: 0,
                                pointIndex: 3
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
            reopened.pathClosed,
            false
        )

        XCTAssertEqual(
            reopened.pathContours?.count,
            2
        )

        XCTAssertEqual(
            reopened.pathPoints,
            reopened.pathContours?.first
        )
    }

    func testResultActiveAnchorAlwaysBelongsToReturnedSelection() throws {
        let split =
            try XCTUnwrap(
                CoverEditorEngine
                    .splittingVectorPath(
                        in:
                            pathLayer(
                                [
                                    point(0),
                                    point(1),
                                    point(2)
                                ],
                                closed: false
                            ),
                        at:
                            CoverVectorAnchorIndex(
                                contourIndex: 0,
                                pointIndex: 1
                            )
                    )
            )

        XCTAssertTrue(
            split.selectedAnchors.contains(
                split.activeAnchor
            )
        )

        let cut =
            try XCTUnwrap(
                CoverEditorEngine
                    .cuttingVectorPath(
                        in:
                            pathLayer(
                                [
                                    point(0),
                                    point(1),
                                    point(2),
                                    point(3),
                                    point(4)
                                ],
                                closed: true
                            ),
                        first:
                            CoverVectorAnchorIndex(
                                contourIndex: 0,
                                pointIndex: 1
                            ),
                        second:
                            CoverVectorAnchorIndex(
                                contourIndex: 0,
                                pointIndex: 3
                            )
                    )
            )

        XCTAssertTrue(
            cut.selectedAnchors.contains(
                cut.activeAnchor
            )
        )
    }
}
