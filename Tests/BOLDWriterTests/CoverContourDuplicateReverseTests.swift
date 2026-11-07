import XCTest
import Foundation
@testable import BOLDWriter

final class CoverContourDuplicateReverseTests: XCTestCase {
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
        contours: [[CoverPathPoint]],
        closures: [Bool]
    ) -> CoverLayer {
        var layer =
            CoverLayer(
                kind: .path,
                name: "Contours"
            )

        layer.pathPoints =
            contours.first

        layer.pathContours =
            contours.count > 1
            ? contours
            : nil

        layer.pathClosed =
            closures.first

        layer.pathContourClosed =
            closures

        return layer
    }

    func testDuplicateRejectsNonPathLayer() {
        var layer =
            CoverLayer(
                kind: .shape,
                name: "Shape"
            )

        layer.pathPoints = [
            point(0),
            point(1)
        ]

        XCTAssertNil(
            CoverEditorEngine
                .duplicatingVectorContour(
                    in: layer,
                    contourIndex: 0
                )
        )
    }

    func testDuplicateRejectsInvalidContourIndex() {
        let layer =
            pathLayer(
                contours: [
                    [
                        point(0),
                        point(1)
                    ]
                ],
                closures: [
                    false
                ]
            )

        XCTAssertNil(
            CoverEditorEngine
                .duplicatingVectorContour(
                    in: layer,
                    contourIndex: 5
                )
        )
    }

    func testDuplicateSingleContourCreatesExactSecondContour() throws {
        let original = [
            point(0),
            point(1),
            point(2)
        ]

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .duplicatingVectorContour(
                        in:
                            pathLayer(
                                contours: [
                                    original
                                ],
                                closures: [
                                    false
                                ]
                            ),
                        contourIndex: 0
                    )
            )

        let contours =
            try XCTUnwrap(
                result.layer.pathContours
            )

        XCTAssertEqual(
            contours,
            [
                original,
                original
            ]
        )

        XCTAssertEqual(
            result.contourIndex,
            1
        )

        XCTAssertEqual(
            result.layer.pathPoints,
            original
        )
    }

    func testDuplicateMiddleContourInsertsImmediatelyAfterSource() throws {
        let a = [
            point(0),
            point(1)
        ]

        let b = [
            point(2),
            point(3),
            point(4)
        ]

        let c = [
            point(5),
            point(6)
        ]

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .duplicatingVectorContour(
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
                        contourIndex: 1
                    )
            )

        XCTAssertEqual(
            result.layer.pathContours,
            [
                a,
                b,
                b,
                c
            ]
        )

        XCTAssertEqual(
            result.contourIndex,
            2
        )
    }

    func testDuplicatePreservesOpenClosureState() throws {
        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .duplicatingVectorContour(
                        in:
                            pathLayer(
                                contours: [
                                    [
                                        point(0),
                                        point(1)
                                    ]
                                ],
                                closures: [
                                    false
                                ]
                            ),
                        contourIndex: 0
                    )
            )

        XCTAssertEqual(
            result.layer.pathContourClosed,
            [
                false,
                false
            ]
        )

        XCTAssertEqual(
            result.layer.pathClosed,
            false
        )
    }

    func testDuplicatePreservesClosedClosureState() throws {
        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .duplicatingVectorContour(
                        in:
                            pathLayer(
                                contours: [
                                    [
                                        point(0),
                                        point(1),
                                        point(2)
                                    ]
                                ],
                                closures: [
                                    true
                                ]
                            ),
                        contourIndex: 0
                    )
            )

        XCTAssertEqual(
            result.layer.pathContourClosed,
            [
                true,
                true
            ]
        )

        XCTAssertEqual(
            result.layer.pathClosed,
            true
        )
    }

    func testDuplicatePreservesUnrelatedClosureStates() throws {
        let a = [
            point(0),
            point(1),
            point(2)
        ]

        let b = [
            point(3),
            point(4)
        ]

        let c = [
            point(5),
            point(6),
            point(7)
        ]

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .duplicatingVectorContour(
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
                        contourIndex: 1
                    )
            )

        XCTAssertEqual(
            result.layer.pathContourClosed,
            [
                true,
                false,
                false,
                true
            ]
        )
    }

    func testDuplicatePreservesAnchorTypesAndBezierHandlesExactly() throws {
        let original = [
            point(
                0,
                0,
                type: .corner,
                inX: -0.2,
                inY: -0.1,
                outX: 0.2,
                outY: 0.3
            ),
            point(
                1,
                1,
                type: .smooth,
                inX: 0.7,
                inY: 0.8,
                outX: 1.3,
                outY: 1.2
            ),
            point(
                2,
                0,
                type: .symmetric,
                inX: 1.7,
                inY: 0.2,
                outX: 2.3,
                outY: -0.2
            )
        ]

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .duplicatingVectorContour(
                        in:
                            pathLayer(
                                contours: [
                                    original
                                ],
                                closures: [
                                    true
                                ]
                            ),
                        contourIndex: 0
                    )
            )

        XCTAssertEqual(
            result.layer.pathContours?[1],
            original
        )
    }

    func testDuplicateSelectsEveryAnchorInDuplicate() throws {
        let original = [
            point(0),
            point(1),
            point(2),
            point(3)
        ]

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .duplicatingVectorContour(
                        in:
                            pathLayer(
                                contours: [
                                    original
                                ],
                                closures: [
                                    false
                                ]
                            ),
                        contourIndex: 0
                    )
            )

        XCTAssertEqual(
            result.selectedAnchors,
            Set(
                [
                    CoverVectorAnchorIndex(
                        contourIndex: 1,
                        pointIndex: 0
                    ),
                    CoverVectorAnchorIndex(
                        contourIndex: 1,
                        pointIndex: 1
                    ),
                    CoverVectorAnchorIndex(
                        contourIndex: 1,
                        pointIndex: 2
                    ),
                    CoverVectorAnchorIndex(
                        contourIndex: 1,
                        pointIndex: 3
                    )
                ]
            )
        )

        XCTAssertEqual(
            result.activeAnchor,
            CoverVectorAnchorIndex(
                contourIndex: 1,
                pointIndex: 0
            )
        )
    }

    func testDuplicateContourZeroKeepsPathPointsSynchronized() throws {
        let a = [
            point(0),
            point(1),
            point(2)
        ]

        let b = [
            point(3),
            point(4)
        ]

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .duplicatingVectorContour(
                        in:
                            pathLayer(
                                contours: [
                                    a,
                                    b
                                ],
                                closures: [
                                    true,
                                    false
                                ]
                            ),
                        contourIndex: 0
                    )
            )

        XCTAssertEqual(
            result.layer.pathPoints,
            a
        )

        XCTAssertEqual(
            result.layer.pathPoints,
            result.layer
                .pathContours?
                .first
        )
    }

    func testReverseRejectsNonPathLayer() {
        var layer =
            CoverLayer(
                kind: .shape,
                name: "Shape"
            )

        layer.pathPoints = [
            point(0),
            point(1)
        ]

        XCTAssertNil(
            CoverEditorEngine
                .reversingVectorContour(
                    in: layer,
                    contourIndex: 0
                )
        )
    }

    func testReverseRejectsInvalidContourIndex() {
        let layer =
            pathLayer(
                contours: [
                    [
                        point(0),
                        point(1)
                    ]
                ],
                closures: [
                    false
                ]
            )

        XCTAssertNil(
            CoverEditorEngine
                .reversingVectorContour(
                    in: layer,
                    contourIndex: 9
                )
        )
    }

    func testReverseOpenContourReversesAnchorOrder() throws {
        let original = [
            point(0),
            point(1),
            point(2),
            point(3)
        ]

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .reversingVectorContour(
                        in:
                            pathLayer(
                                contours: [
                                    original
                                ],
                                closures: [
                                    false
                                ]
                            ),
                        contourIndex: 0
                    )
            )

        XCTAssertEqual(
            result.layer
                .pathPoints?
                .map(\.x),
            [
                3,
                2,
                1,
                0
            ]
        )

        XCTAssertEqual(
            result.layer.pathContourClosed,
            [
                false
            ]
        )

        XCTAssertEqual(
            result.layer.pathClosed,
            false
        )
    }

    func testReverseClosedContourPreservesClosure() throws {
        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .reversingVectorContour(
                        in:
                            pathLayer(
                                contours: [
                                    [
                                        point(0),
                                        point(1),
                                        point(2)
                                    ]
                                ],
                                closures: [
                                    true
                                ]
                            ),
                        contourIndex: 0
                    )
            )

        XCTAssertEqual(
            result.layer.pathContourClosed,
            [
                true
            ]
        )

        XCTAssertEqual(
            result.layer.pathClosed,
            true
        )
    }

    func testReverseSwapsIncomingAndOutgoingHandlesAndPreservesTypes() throws {
        let original = [
            point(
                0,
                0,
                type: .corner,
                inX: -0.2,
                inY: -0.3,
                outX: 0.2,
                outY: 0.3
            ),
            point(
                1,
                1,
                type: .smooth,
                inX: 0.7,
                inY: 0.8,
                outX: 1.3,
                outY: 1.2
            ),
            point(
                2,
                0,
                type: .symmetric,
                inX: 1.7,
                inY: 0.2,
                outX: 2.3,
                outY: -0.2
            )
        ]

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .reversingVectorContour(
                        in:
                            pathLayer(
                                contours: [
                                    original
                                ],
                                closures: [
                                    true
                                ]
                            ),
                        contourIndex: 0
                    )
            )

        let reversed =
            try XCTUnwrap(
                result.layer.pathPoints
            )

        XCTAssertEqual(
            reversed[0].x,
            original[2].x
        )

        XCTAssertEqual(
            reversed[0].controlInX,
            original[2].controlOutX
        )

        XCTAssertEqual(
            reversed[0].controlInY,
            original[2].controlOutY
        )

        XCTAssertEqual(
            reversed[0].controlOutX,
            original[2].controlInX
        )

        XCTAssertEqual(
            reversed[0].controlOutY,
            original[2].controlInY
        )

        XCTAssertEqual(
            reversed[0].anchorType,
            .symmetric
        )

        XCTAssertEqual(
            reversed[1].anchorType,
            .smooth
        )

        XCTAssertEqual(
            reversed[2].anchorType,
            .corner
        )
    }

    func testDoubleReverseRestoresOriginalContourExactly() throws {
        let original = [
            point(
                0,
                0,
                type: .corner,
                inX: -0.1,
                inY: 0,
                outX: 0.2,
                outY: 0.3
            ),
            point(
                1,
                1,
                type: .smooth,
                inX: 0.7,
                inY: 0.9,
                outX: 1.3,
                outY: 1.1
            ),
            point(
                2,
                0,
                type: .symmetric,
                inX: 1.8,
                inY: 0.2,
                outX: 2.2,
                outY: -0.2
            )
        ]

        let first =
            try XCTUnwrap(
                CoverEditorEngine
                    .reversingVectorContour(
                        in:
                            pathLayer(
                                contours: [
                                    original
                                ],
                                closures: [
                                    true
                                ]
                            ),
                        contourIndex: 0
                    )
            )

        let second =
            try XCTUnwrap(
                CoverEditorEngine
                    .reversingVectorContour(
                        in:
                            first.layer,
                        contourIndex: 0
                    )
            )

        XCTAssertEqual(
            second.layer.pathPoints,
            original
        )
    }

    func testReverseSecondaryContourPreservesUnrelatedContoursAndClosures() throws {
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

        let c = [
            point(6),
            point(7)
        ]

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .reversingVectorContour(
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
                        contourIndex: 1
                    )
            )

        XCTAssertEqual(
            result.layer.pathContours?[0],
            a
        )

        XCTAssertEqual(
            result.layer
                .pathContours?[1]
                .map(\.x),
            [
                5,
                4,
                3
            ]
        )

        XCTAssertEqual(
            result.layer.pathContours?[2],
            c
        )

        XCTAssertEqual(
            result.layer.pathContourClosed,
            [
                true,
                false,
                true
            ]
        )
    }

    func testReversePrimaryContourSynchronizesPathPoints() throws {
        let a = [
            point(0),
            point(1),
            point(2)
        ]

        let b = [
            point(3),
            point(4)
        ]

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .reversingVectorContour(
                        in:
                            pathLayer(
                                contours: [
                                    a,
                                    b
                                ],
                                closures: [
                                    true,
                                    false
                                ]
                            ),
                        contourIndex: 0
                    )
            )

        XCTAssertEqual(
            result.layer
                .pathPoints?
                .map(\.x),
            [
                2,
                1,
                0
            ]
        )

        XCTAssertEqual(
            result.layer.pathPoints,
            result.layer
                .pathContours?
                .first
        )
    }

    func testReverseSelectsEveryAnchorAndKeepsContourIndex() throws {
        let a = [
            point(0),
            point(1)
        ]

        let b = [
            point(2),
            point(3),
            point(4)
        ]

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .reversingVectorContour(
                        in:
                            pathLayer(
                                contours: [
                                    a,
                                    b
                                ],
                                closures: [
                                    false,
                                    true
                                ]
                            ),
                        contourIndex: 1
                    )
            )

        XCTAssertEqual(
            result.contourIndex,
            1
        )

        XCTAssertEqual(
            result.selectedAnchors,
            Set(
                [
                    CoverVectorAnchorIndex(
                        contourIndex: 1,
                        pointIndex: 0
                    ),
                    CoverVectorAnchorIndex(
                        contourIndex: 1,
                        pointIndex: 1
                    ),
                    CoverVectorAnchorIndex(
                        contourIndex: 1,
                        pointIndex: 2
                    )
                ]
            )
        )

        XCTAssertEqual(
            result.activeAnchor,
            CoverVectorAnchorIndex(
                contourIndex: 1,
                pointIndex: 0
            )
        )
    }

    func testDuplicateResultPersistsThroughCodable() throws {
        let source =
            pathLayer(
                contours: [
                    [
                        point(
                            0,
                            type: .corner
                        ),
                        point(
                            1,
                            type: .smooth,
                            inX: 0.8,
                            inY: 0,
                            outX: 1.2,
                            outY: 0
                        ),
                        point(
                            2,
                            type: .symmetric
                        )
                    ]
                ],
                closures: [
                    true
                ]
            )

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .duplicatingVectorContour(
                        in: source,
                        contourIndex: 0
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

    func testReverseResultPersistsThroughCodable() throws {
        let source =
            pathLayer(
                contours: [
                    [
                        point(
                            0,
                            type: .corner,
                            outX: 0.2,
                            outY: 0.1
                        ),
                        point(
                            1,
                            type: .smooth,
                            inX: 0.8,
                            inY: 0.9,
                            outX: 1.2,
                            outY: 1.1
                        ),
                        point(
                            2,
                            type: .symmetric,
                            inX: 1.8,
                            inY: 0.2
                        )
                    ]
                ],
                closures: [
                    true
                ]
            )

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .reversingVectorContour(
                        in: source,
                        contourIndex: 0
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

    func testDuplicateDoesNotMutateOriginalLayerValue() throws {
        let original =
            pathLayer(
                contours: [
                    [
                        point(0),
                        point(1),
                        point(2)
                    ]
                ],
                closures: [
                    true
                ]
            )

        let snapshot =
            original

        _ =
            try XCTUnwrap(
                CoverEditorEngine
                    .duplicatingVectorContour(
                        in: original,
                        contourIndex: 0
                    )
            )

        XCTAssertEqual(
            original,
            snapshot
        )
    }

    func testReverseDoesNotMutateOriginalLayerValue() throws {
        let original =
            pathLayer(
                contours: [
                    [
                        point(0),
                        point(1),
                        point(2)
                    ]
                ],
                closures: [
                    false
                ]
            )

        let snapshot =
            original

        _ =
            try XCTUnwrap(
                CoverEditorEngine
                    .reversingVectorContour(
                        in: original,
                        contourIndex: 0
                    )
            )

        XCTAssertEqual(
            original,
            snapshot
        )
    }
}
