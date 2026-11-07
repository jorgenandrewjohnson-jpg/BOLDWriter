import XCTest
import Foundation
@testable import BOLDWriter

final class CoverContourOrderingTests: XCTestCase {
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

    private func contour(
        _ marker: Double
    ) -> [CoverPathPoint] {
        [
            point(
                marker,
                marker,
                type: .corner,
                outX:
                    marker + 0.1,
                outY:
                    marker + 0.2
            ),
            point(
                marker + 0.5,
                marker + 0.25,
                type: .smooth,
                inX:
                    marker + 0.3,
                inY:
                    marker + 0.2,
                outX:
                    marker + 0.7,
                outY:
                    marker + 0.3
            ),
            point(
                marker + 1,
                marker,
                type: .symmetric,
                inX:
                    marker + 0.9,
                inY:
                    marker + 0.2
            )
        ]
    }

    private func pathLayer(
        contours: [[CoverPathPoint]],
        closures: [Bool]
    ) -> CoverLayer {
        var layer =
            CoverLayer(
                kind: .path,
                name: "Ordered Contours"
            )

        layer.pathPoints =
            contours.first

        layer.pathContours =
            contours

        layer.pathClosed =
            closures.first

        layer.pathContourClosed =
            closures

        return layer
    }

    private func markerOrder(
        _ layer: CoverLayer
    ) -> [Double] {
        CoverEditorEngine
            .vectorContours(
                for: layer
            )
            .compactMap {
                $0.first?.x
            }
    }

    func testRejectsOrderingOnNonPathLayer() {
        var layer =
            CoverLayer(
                kind: .shape,
                name: "Shape"
            )

        layer.pathPoints =
            contour(0)

        XCTAssertNil(
            CoverEditorEngine
                .orderingVectorContour(
                    in: layer,
                    contourIndex: 0,
                    move: .front
                )
        )
    }

    func testRejectsOrderingWithFewerThanTwoContours() {
        let layer =
            pathLayer(
                contours: [
                    contour(0)
                ],
                closures: [
                    true
                ]
            )

        XCTAssertNil(
            CoverEditorEngine
                .orderingVectorContour(
                    in: layer,
                    contourIndex: 0,
                    move: .front
                )
        )
    }

    func testRejectsInvalidContourIndex() {
        let layer =
            pathLayer(
                contours: [
                    contour(0),
                    contour(10)
                ],
                closures: [
                    true,
                    false
                ]
            )

        XCTAssertNil(
            CoverEditorEngine
                .orderingVectorContour(
                    in: layer,
                    contourIndex: 9,
                    move: .back
                )
        )
    }

    func testForwardMovesExactlyOneIndex() throws {
        let layer =
            pathLayer(
                contours: [
                    contour(0),
                    contour(10),
                    contour(20),
                    contour(30)
                ],
                closures: [
                    true,
                    false,
                    true,
                    false
                ]
            )

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .orderingVectorContour(
                        in: layer,
                        contourIndex: 1,
                        move: .forward
                    )
            )

        XCTAssertEqual(
            markerOrder(
                result.layer
            ),
            [
                0,
                20,
                10,
                30
            ]
        )

        XCTAssertEqual(
            result.contourIndex,
            2
        )
    }

    func testBackwardMovesExactlyOneIndex() throws {
        let layer =
            pathLayer(
                contours: [
                    contour(0),
                    contour(10),
                    contour(20),
                    contour(30)
                ],
                closures: [
                    true,
                    false,
                    true,
                    false
                ]
            )

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .orderingVectorContour(
                        in: layer,
                        contourIndex: 2,
                        move: .backward
                    )
            )

        XCTAssertEqual(
            markerOrder(
                result.layer
            ),
            [
                0,
                20,
                10,
                30
            ]
        )

        XCTAssertEqual(
            result.contourIndex,
            1
        )
    }

    func testFrontMovesToFinalIndex() throws {
        let layer =
            pathLayer(
                contours: [
                    contour(0),
                    contour(10),
                    contour(20),
                    contour(30)
                ],
                closures: [
                    true,
                    false,
                    true,
                    false
                ]
            )

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .orderingVectorContour(
                        in: layer,
                        contourIndex: 1,
                        move: .front
                    )
            )

        XCTAssertEqual(
            markerOrder(
                result.layer
            ),
            [
                0,
                20,
                30,
                10
            ]
        )

        XCTAssertEqual(
            result.contourIndex,
            3
        )
    }

    func testBackMovesToZero() throws {
        let layer =
            pathLayer(
                contours: [
                    contour(0),
                    contour(10),
                    contour(20),
                    contour(30)
                ],
                closures: [
                    true,
                    false,
                    true,
                    false
                ]
            )

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .orderingVectorContour(
                        in: layer,
                        contourIndex: 2,
                        move: .back
                    )
            )

        XCTAssertEqual(
            markerOrder(
                result.layer
            ),
            [
                20,
                0,
                10,
                30
            ]
        )

        XCTAssertEqual(
            result.contourIndex,
            0
        )
    }

    func testForwardRejectsFinalContour() {
        let layer =
            pathLayer(
                contours: [
                    contour(0),
                    contour(10)
                ],
                closures: [
                    true,
                    false
                ]
            )

        XCTAssertNil(
            CoverEditorEngine
                .orderingVectorContour(
                    in: layer,
                    contourIndex: 1,
                    move: .forward
                )
        )
    }

    func testBackwardRejectsZeroContour() {
        let layer =
            pathLayer(
                contours: [
                    contour(0),
                    contour(10)
                ],
                closures: [
                    true,
                    false
                ]
            )

        XCTAssertNil(
            CoverEditorEngine
                .orderingVectorContour(
                    in: layer,
                    contourIndex: 0,
                    move: .backward
                )
        )
    }

    func testFrontRejectsFinalContour() {
        let layer =
            pathLayer(
                contours: [
                    contour(0),
                    contour(10)
                ],
                closures: [
                    true,
                    false
                ]
            )

        XCTAssertNil(
            CoverEditorEngine
                .orderingVectorContour(
                    in: layer,
                    contourIndex: 1,
                    move: .front
                )
        )
    }

    func testBackRejectsZeroContour() {
        let layer =
            pathLayer(
                contours: [
                    contour(0),
                    contour(10)
                ],
                closures: [
                    true,
                    false
                ]
            )

        XCTAssertNil(
            CoverEditorEngine
                .orderingVectorContour(
                    in: layer,
                    contourIndex: 0,
                    move: .back
                )
        )
    }

    func testGeometryMovesWithoutChangingAnyContourPoints() throws {
        let a = contour(0)
        let b = contour(10)
        let c = contour(20)

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .orderingVectorContour(
                        in:
                            pathLayer(
                                contours: [
                                    a,
                                    b,
                                    c
                                ],
                                closures: [
                                    true,
                                    false,
                                    true
                                ]
                            ),
                        contourIndex: 1,
                        move: .front
                    )
            )

        XCTAssertEqual(
            result.layer.pathContours,
            [
                a,
                c,
                b
            ]
        )
    }

    func testClosureMovesWithMatchingContour() throws {
        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .orderingVectorContour(
                        in:
                            pathLayer(
                                contours: [
                                    contour(0),
                                    contour(10),
                                    contour(20)
                                ],
                                closures: [
                                    true,
                                    false,
                                    true
                                ]
                            ),
                        contourIndex: 0,
                        move: .front
                    )
            )

        XCTAssertEqual(
            result.layer.pathContourClosed,
            [
                false,
                true,
                true
            ]
        )
    }

    func testPathClosedMirrorsNewContourZero() throws {
        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .orderingVectorContour(
                        in:
                            pathLayer(
                                contours: [
                                    contour(0),
                                    contour(10),
                                    contour(20)
                                ],
                                closures: [
                                    true,
                                    false,
                                    true
                                ]
                            ),
                        contourIndex: 2,
                        move: .back
                    )
            )

        XCTAssertEqual(
            result.layer.pathContourClosed,
            [
                true,
                true,
                false
            ]
        )

        XCTAssertEqual(
            result.layer.pathClosed,
            true
        )
    }

    func testPathPointsMirrorsNewContourZero() throws {
        let a = contour(0)
        let b = contour(10)
        let c = contour(20)

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .orderingVectorContour(
                        in:
                            pathLayer(
                                contours: [
                                    a,
                                    b,
                                    c
                                ],
                                closures: [
                                    true,
                                    false,
                                    true
                                ]
                            ),
                        contourIndex: 2,
                        move: .back
                    )
            )

        XCTAssertEqual(
            result.layer.pathPoints,
            c
        )

        XCTAssertEqual(
            result.layer.pathPoints,
            result.layer
                .pathContours?
                .first
        )
    }

    func testMovingContourZeroForwardSynchronizesPrimaryMirror() throws {
        let a = contour(0)
        let b = contour(10)
        let c = contour(20)

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .orderingVectorContour(
                        in:
                            pathLayer(
                                contours: [
                                    a,
                                    b,
                                    c
                                ],
                                closures: [
                                    true,
                                    false,
                                    true
                                ]
                            ),
                        contourIndex: 0,
                        move: .forward
                    )
            )

        XCTAssertEqual(
            result.layer.pathContours,
            [
                b,
                a,
                c
            ]
        )

        XCTAssertEqual(
            result.layer.pathPoints,
            b
        )

        XCTAssertEqual(
            result.layer.pathClosed,
            false
        )
    }

    func testMovingSecondaryContourToBackSynchronizesPrimaryMirror() throws {
        let a = contour(0)
        let b = contour(10)
        let c = contour(20)

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .orderingVectorContour(
                        in:
                            pathLayer(
                                contours: [
                                    a,
                                    b,
                                    c
                                ],
                                closures: [
                                    false,
                                    true,
                                    true
                                ]
                            ),
                        contourIndex: 1,
                        move: .back
                    )
            )

        XCTAssertEqual(
            result.layer.pathContours,
            [
                b,
                a,
                c
            ]
        )

        XCTAssertEqual(
            result.layer.pathPoints,
            b
        )

        XCTAssertEqual(
            result.layer.pathClosed,
            true
        )
    }

    func testActiveContourIndexRemapsToDestination() throws {
        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .orderingVectorContour(
                        in:
                            pathLayer(
                                contours: [
                                    contour(0),
                                    contour(10),
                                    contour(20),
                                    contour(30)
                                ],
                                closures: [
                                    false,
                                    false,
                                    true,
                                    true
                                ]
                            ),
                        contourIndex: 1,
                        move: .front
                    )
            )

        XCTAssertEqual(
            result.contourIndex,
            3
        )
    }

    func testSelectedAnchorsOnMovedContourRemapToDestination() throws {
        let selection:
            Set<CoverVectorAnchorIndex> = [
                CoverVectorAnchorIndex(
                    contourIndex: 1,
                    pointIndex: 0
                ),
                CoverVectorAnchorIndex(
                    contourIndex: 1,
                    pointIndex: 2
                )
            ]

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .orderingVectorContour(
                        in:
                            pathLayer(
                                contours: [
                                    contour(0),
                                    contour(10),
                                    contour(20)
                                ],
                                closures: [
                                    true,
                                    false,
                                    true
                                ]
                            ),
                        contourIndex: 1,
                        move: .front,
                        selectedAnchors:
                            selection
                    )
            )

        XCTAssertEqual(
            result.selectedAnchors,
            Set(
                [
                    CoverVectorAnchorIndex(
                        contourIndex: 2,
                        pointIndex: 0
                    ),
                    CoverVectorAnchorIndex(
                        contourIndex: 2,
                        pointIndex: 2
                    )
                ]
            )
        )

        XCTAssertEqual(
            result.activeAnchor,
            CoverVectorAnchorIndex(
                contourIndex: 2,
                pointIndex: 0
            )
        )
    }

    func testShiftedNeighborSelectionRemapsWhenMovingForward() throws {
        let selection:
            Set<CoverVectorAnchorIndex> = [
                CoverVectorAnchorIndex(
                    contourIndex: 2,
                    pointIndex: 1
                )
            ]

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .orderingVectorContour(
                        in:
                            pathLayer(
                                contours: [
                                    contour(0),
                                    contour(10),
                                    contour(20),
                                    contour(30)
                                ],
                                closures: [
                                    false,
                                    true,
                                    false,
                                    true
                                ]
                            ),
                        contourIndex: 1,
                        move: .front,
                        selectedAnchors:
                            selection
                    )
            )

        XCTAssertEqual(
            result.selectedAnchors,
            Set(
                [
                    CoverVectorAnchorIndex(
                        contourIndex: 1,
                        pointIndex: 1
                    )
                ]
            )
        )
    }

    func testShiftedNeighborSelectionRemapsWhenMovingBackward() throws {
        let selection:
            Set<CoverVectorAnchorIndex> = [
                CoverVectorAnchorIndex(
                    contourIndex: 1,
                    pointIndex: 2
                )
            ]

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .orderingVectorContour(
                        in:
                            pathLayer(
                                contours: [
                                    contour(0),
                                    contour(10),
                                    contour(20),
                                    contour(30)
                                ],
                                closures: [
                                    false,
                                    true,
                                    false,
                                    true
                                ]
                            ),
                        contourIndex: 3,
                        move: .back,
                        selectedAnchors:
                            selection
                    )
            )

        XCTAssertEqual(
            result.selectedAnchors,
            Set(
                [
                    CoverVectorAnchorIndex(
                        contourIndex: 2,
                        pointIndex: 2
                    )
                ]
            )
        )
    }

    func testUnaffectedSelectionKeepsContourIndex() throws {
        let selection:
            Set<CoverVectorAnchorIndex> = [
                CoverVectorAnchorIndex(
                    contourIndex: 0,
                    pointIndex: 1
                )
            ]

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .orderingVectorContour(
                        in:
                            pathLayer(
                                contours: [
                                    contour(0),
                                    contour(10),
                                    contour(20),
                                    contour(30)
                                ],
                                closures: [
                                    false,
                                    true,
                                    false,
                                    true
                                ]
                            ),
                        contourIndex: 2,
                        move: .forward,
                        selectedAnchors:
                            selection
                    )
            )

        XCTAssertEqual(
            result.selectedAnchors,
            selection
        )
    }

    func testMultiContourSelectionSurvivesForwardReorder() throws {
        let selection:
            Set<CoverVectorAnchorIndex> = [
                CoverVectorAnchorIndex(
                    contourIndex: 0,
                    pointIndex: 0
                ),
                CoverVectorAnchorIndex(
                    contourIndex: 1,
                    pointIndex: 1
                ),
                CoverVectorAnchorIndex(
                    contourIndex: 2,
                    pointIndex: 2
                ),
                CoverVectorAnchorIndex(
                    contourIndex: 3,
                    pointIndex: 0
                )
            ]

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .orderingVectorContour(
                        in:
                            pathLayer(
                                contours: [
                                    contour(0),
                                    contour(10),
                                    contour(20),
                                    contour(30)
                                ],
                                closures: [
                                    true,
                                    false,
                                    true,
                                    false
                                ]
                            ),
                        contourIndex: 1,
                        move: .front,
                        selectedAnchors:
                            selection
                    )
            )

        XCTAssertEqual(
            result.selectedAnchors,
            Set(
                [
                    CoverVectorAnchorIndex(
                        contourIndex: 0,
                        pointIndex: 0
                    ),
                    CoverVectorAnchorIndex(
                        contourIndex: 3,
                        pointIndex: 1
                    ),
                    CoverVectorAnchorIndex(
                        contourIndex: 1,
                        pointIndex: 2
                    ),
                    CoverVectorAnchorIndex(
                        contourIndex: 2,
                        pointIndex: 0
                    )
                ]
            )
        )
    }

    func testMultiContourSelectionSurvivesBackwardReorder() throws {
        let selection:
            Set<CoverVectorAnchorIndex> = [
                CoverVectorAnchorIndex(
                    contourIndex: 0,
                    pointIndex: 2
                ),
                CoverVectorAnchorIndex(
                    contourIndex: 1,
                    pointIndex: 0
                ),
                CoverVectorAnchorIndex(
                    contourIndex: 2,
                    pointIndex: 1
                ),
                CoverVectorAnchorIndex(
                    contourIndex: 3,
                    pointIndex: 2
                )
            ]

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .orderingVectorContour(
                        in:
                            pathLayer(
                                contours: [
                                    contour(0),
                                    contour(10),
                                    contour(20),
                                    contour(30)
                                ],
                                closures: [
                                    true,
                                    false,
                                    true,
                                    false
                                ]
                            ),
                        contourIndex: 3,
                        move: .back,
                        selectedAnchors:
                            selection
                    )
            )

        XCTAssertEqual(
            result.selectedAnchors,
            Set(
                [
                    CoverVectorAnchorIndex(
                        contourIndex: 1,
                        pointIndex: 2
                    ),
                    CoverVectorAnchorIndex(
                        contourIndex: 2,
                        pointIndex: 0
                    ),
                    CoverVectorAnchorIndex(
                        contourIndex: 3,
                        pointIndex: 1
                    ),
                    CoverVectorAnchorIndex(
                        contourIndex: 0,
                        pointIndex: 2
                    )
                ]
            )
        )
    }

    func testAnchorPointIndicesNeverChangeDuringRemap() throws {
        let selection:
            Set<CoverVectorAnchorIndex> = [
                CoverVectorAnchorIndex(
                    contourIndex: 0,
                    pointIndex: 2
                ),
                CoverVectorAnchorIndex(
                    contourIndex: 1,
                    pointIndex: 1
                ),
                CoverVectorAnchorIndex(
                    contourIndex: 2,
                    pointIndex: 0
                )
            ]

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .orderingVectorContour(
                        in:
                            pathLayer(
                                contours: [
                                    contour(0),
                                    contour(10),
                                    contour(20)
                                ],
                                closures: [
                                    true,
                                    false,
                                    true
                                ]
                            ),
                        contourIndex: 0,
                        move: .front,
                        selectedAnchors:
                            selection
                    )
            )

        XCTAssertEqual(
            Set(
                result.selectedAnchors.map(
                    \.pointIndex
                )
            ),
            Set(
                [
                    0,
                    1,
                    2
                ]
            )
        )
    }

    func testMixedClosureStatesRemainAlignedWithContours() throws {
        let a = contour(0)
        let b = contour(10)
        let c = contour(20)
        let d = contour(30)

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .orderingVectorContour(
                        in:
                            pathLayer(
                                contours: [
                                    a,
                                    b,
                                    c,
                                    d
                                ],
                                closures: [
                                    true,
                                    false,
                                    false,
                                    true
                                ]
                            ),
                        contourIndex: 3,
                        move: .back
                    )
            )

        XCTAssertEqual(
            result.layer.pathContours,
            [
                d,
                a,
                b,
                c
            ]
        )

        XCTAssertEqual(
            result.layer.pathContourClosed,
            [
                true,
                true,
                false,
                false
            ]
        )
    }

    func testOrderingResultPersistsThroughCodable() throws {
        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .orderingVectorContour(
                        in:
                            pathLayer(
                                contours: [
                                    contour(0),
                                    contour(10),
                                    contour(20)
                                ],
                                closures: [
                                    true,
                                    false,
                                    true
                                ]
                            ),
                        contourIndex: 0,
                        move: .front
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
    }

    func testForwardThenBackwardRestoresOriginalLayer() throws {
        let original =
            pathLayer(
                contours: [
                    contour(0),
                    contour(10),
                    contour(20)
                ],
                closures: [
                    true,
                    false,
                    true
                ]
            )

        let forward =
            try XCTUnwrap(
                CoverEditorEngine
                    .orderingVectorContour(
                        in: original,
                        contourIndex: 1,
                        move: .forward
                    )
            )

        let backward =
            try XCTUnwrap(
                CoverEditorEngine
                    .orderingVectorContour(
                        in: forward.layer,
                        contourIndex:
                            forward.contourIndex,
                        move: .backward
                    )
            )

        XCTAssertEqual(
            backward.layer,
            original
        )
    }

    func testBackThenForwardRestoresOriginalLayerForOneStepMove() throws {
        let original =
            pathLayer(
                contours: [
                    contour(0),
                    contour(10),
                    contour(20)
                ],
                closures: [
                    false,
                    true,
                    false
                ]
            )

        let backward =
            try XCTUnwrap(
                CoverEditorEngine
                    .orderingVectorContour(
                        in: original,
                        contourIndex: 1,
                        move: .backward
                    )
            )

        let forward =
            try XCTUnwrap(
                CoverEditorEngine
                    .orderingVectorContour(
                        in: backward.layer,
                        contourIndex:
                            backward.contourIndex,
                        move: .forward
                    )
            )

        XCTAssertEqual(
            forward.layer,
            original
        )
    }

    func testOrderingDoesNotMutateOriginalLayerValue() throws {
        let original =
            pathLayer(
                contours: [
                    contour(0),
                    contour(10),
                    contour(20)
                ],
                closures: [
                    true,
                    false,
                    true
                ]
            )

        let snapshot =
            original

        _ =
            try XCTUnwrap(
                CoverEditorEngine
                    .orderingVectorContour(
                        in: original,
                        contourIndex: 1,
                        move: .front
                    )
            )

        XCTAssertEqual(
            original,
            snapshot
        )
    }

    func testStaleSelectedAnchorsAreDroppedSafely() throws {
        let selection:
            Set<CoverVectorAnchorIndex> = [
                CoverVectorAnchorIndex(
                    contourIndex: 1,
                    pointIndex: 1
                ),
                CoverVectorAnchorIndex(
                    contourIndex: 99,
                    pointIndex: 99
                )
            ]

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .orderingVectorContour(
                        in:
                            pathLayer(
                                contours: [
                                    contour(0),
                                    contour(10),
                                    contour(20)
                                ],
                                closures: [
                                    true,
                                    false,
                                    true
                                ]
                            ),
                        contourIndex: 1,
                        move: .front,
                        selectedAnchors:
                            selection
                    )
            )

        XCTAssertEqual(
            result.selectedAnchors,
            Set(
                [
                    CoverVectorAnchorIndex(
                        contourIndex: 2,
                        pointIndex: 1
                    )
                ]
            )
        )
    }
}
