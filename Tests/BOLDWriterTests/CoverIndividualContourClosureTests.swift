import XCTest
import Foundation
import AppKit
@testable import BOLDWriter

final class CoverIndividualContourClosureTests: XCTestCase {
    private func point(
        _ x: Double,
        _ y: Double = 0,
        type: CoverPathAnchorType? = nil
    ) -> CoverPathPoint {
        CoverPathPoint(
            x: x,
            y: y,
            anchorType: type
        )
    }

    private func compoundLayer(
        closures: [Bool]
    ) -> CoverLayer {
        let first = [
            point(0, 0),
            point(1, 0),
            point(1, 1)
        ]

        let second = [
            point(2, 0),
            point(3, 0),
            point(3, 1)
        ]

        var layer =
            CoverLayer(
                kind: .path,
                name: "Compound"
            )

        layer.pathPoints = first
        layer.pathContours = [
            first,
            second
        ]
        layer.pathClosed =
            closures.first

        layer.pathContourClosed =
            closures

        return layer
    }

    func testLegacyClosedStateResolvesAcrossContours() {
        var layer =
            compoundLayer(
                closures: [
                    true,
                    true
                ]
            )

        layer.pathContourClosed =
            nil

        layer.pathClosed =
            true

        XCTAssertEqual(
            CoverEditorEngine
                .vectorContourClosures(
                    for: layer,
                    contourCount: 2
                ),
            [
                true,
                true
            ]
        )
    }

    func testLegacyOpenStateResolvesAcrossContours() {
        var layer =
            compoundLayer(
                closures: [
                    false,
                    false
                ]
            )

        layer.pathContourClosed =
            nil

        layer.pathClosed =
            false

        XCTAssertEqual(
            CoverEditorEngine
                .vectorContourClosures(
                    for: layer,
                    contourCount: 2
                ),
            [
                false,
                false
            ]
        )
    }

    func testExplicitContourClosuresOverrideLegacyMirror() {
        var layer =
            compoundLayer(
                closures: [
                    true,
                    false
                ]
            )

        layer.pathClosed =
            true

        XCTAssertEqual(
            CoverEditorEngine
                .vectorContourClosures(
                    for: layer,
                    contourCount: 2
                ),
            [
                true,
                false
            ]
        )
    }

    func testSettingSecondaryContourClosureLeavesPrimaryMirrorUnchanged() throws {
        let layer =
            compoundLayer(
                closures: [
                    true,
                    false
                ]
            )

        let changed =
            try XCTUnwrap(
                CoverEditorEngine
                    .settingVectorContourClosed(
                        in: layer,
                        contourIndex: 1,
                        closed: true
                    )
            )

        XCTAssertEqual(
            changed.pathContourClosed,
            [
                true,
                true
            ]
        )

        XCTAssertEqual(
            changed.pathClosed,
            true
        )

        XCTAssertEqual(
            changed.pathContours,
            layer.pathContours
        )

        XCTAssertEqual(
            changed.pathPoints,
            layer.pathPoints
        )
    }

    func testSettingPrimaryContourSynchronizesLegacyPathClosed() throws {
        let layer =
            compoundLayer(
                closures: [
                    true,
                    false
                ]
            )

        let changed =
            try XCTUnwrap(
                CoverEditorEngine
                    .settingVectorContourClosed(
                        in: layer,
                        contourIndex: 0,
                        closed: false
                    )
            )

        XCTAssertEqual(
            changed.pathContourClosed,
            [
                false,
                false
            ]
        )

        XCTAssertEqual(
            changed.pathClosed,
            false
        )
    }

    func testMixedContourClosuresRoundTripThroughCodable() throws {
        let layer =
            compoundLayer(
                closures: [
                    true,
                    false
                ]
            )

        let reopened =
            try JSONDecoder()
                .decode(
                    CoverLayer.self,
                    from:
                        JSONEncoder()
                            .encode(
                                layer
                            )
                )

        XCTAssertEqual(
            reopened,
            layer
        )

        XCTAssertEqual(
            reopened.pathContourClosed,
            [
                true,
                false
            ]
        )
    }

    func testLegacyLayerWithoutPathContourClosedStillDecodes() throws {
        let layer =
            compoundLayer(
                closures: [
                    true,
                    false
                ]
            )

        let encoded =
            try JSONEncoder()
                .encode(
                    layer
                )

        var object =
            try XCTUnwrap(
                JSONSerialization
                    .jsonObject(
                        with: encoded
                    )
                    as? [String: Any]
            )

        object.removeValue(
            forKey:
                "pathContourClosed"
        )

        let legacyData =
            try JSONSerialization
                .data(
                    withJSONObject:
                        object
                )

        let reopened =
            try JSONDecoder()
                .decode(
                    CoverLayer.self,
                    from:
                        legacyData
                )

        XCTAssertNil(
            reopened.pathContourClosed
        )

        XCTAssertEqual(
            CoverEditorEngine
                .vectorContourClosures(
                    for: reopened,
                    contourCount: 2
                ),
            [
                true,
                true
            ]
        )
    }

    func testMixedCompoundPathRendererClosesOnlyRequestedContour() {
        let contours = [
            [
                point(0, 0),
                point(1, 0),
                point(1, 1)
            ],
            [
                point(2, 0),
                point(3, 0),
                point(3, 1)
            ]
        ]

        let mixed =
            CoverEditorEngine
                .vectorCompoundPath(
                    contours:
                        contours,
                    in:
                        NSRect(
                            x: 0,
                            y: 0,
                            width: 100,
                            height: 100
                        ),
                    closures: [
                        true,
                        false
                    ]
                )

        let allOpen =
            CoverEditorEngine
                .vectorCompoundPath(
                    contours:
                        contours,
                    in:
                        NSRect(
                            x: 0,
                            y: 0,
                            width: 100,
                            height: 100
                        ),
                    closures: [
                        false,
                        false
                    ]
                )

        XCTAssertGreaterThan(
            mixed.elementCount,
            allOpen.elementCount
        )
    }

    func testNearestSegmentUsesClosureOfTargetContour() throws {
        var layer =
            compoundLayer(
                closures: [
                    false,
                    true
                ]
            )

        layer.pathContours = [
            [
                point(0.0, 0.0),
                point(0.4, 0.0),
                point(0.4, 0.4)
            ],
            [
                point(0.6, 0.6),
                point(0.9, 0.6),
                point(0.9, 0.9)
            ]
        ]

        layer.pathPoints =
            layer.pathContours?.first

        let hit =
            try XCTUnwrap(
                CoverEditorEngine
                    .nearestVectorSegment(
                        in: layer,
                        to:
                            CGPoint(
                                x: 0.75,
                                y: 0.75
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
            2
        )
    }

    func testAddAnchorClosingSegmentUsesTargetContourClosure() throws {
        let layer =
            compoundLayer(
                closures: [
                    false,
                    true
                ]
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

        let inserted =
            try XCTUnwrap(
                CoverEditorEngine
                    .insertingVectorPoint(
                        in: layer,
                        contourIndex: 1,
                        startPointIndex: 2,
                        t: 0.5
                    )
            )

        XCTAssertEqual(
            inserted.anchor.contourIndex,
            1
        )

        XCTAssertEqual(
            inserted.layer
                .pathContours?[1]
                .count,
            4
        )
    }

    func testJoinTwoOpenContoursInsideMixedCompoundPreservesClosedContour() throws {
        let first = [
            point(0),
            point(1)
        ]

        let second = [
            point(2),
            point(3)
        ]

        let third = [
            point(4),
            point(5),
            point(6)
        ]

        var layer =
            CoverLayer(
                kind: .path,
                name: "Mixed"
            )

        layer.pathPoints = first
        layer.pathContours = [
            first,
            second,
            third
        ]
        layer.pathContourClosed = [
            false,
            false,
            true
        ]
        layer.pathClosed = false

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
            result.layer
                .pathContours?
                .count,
            2
        )

        XCTAssertEqual(
            result.layer.pathContourClosed,
            [
                false,
                true
            ]
        )

        XCTAssertEqual(
            result.layer
                .pathContours?[1],
            third
        )
    }

    func testSameContourJoinClosesOnlySelectedContour() throws {
        let layer =
            compoundLayer(
                closures: [
                    false,
                    true
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
                                contourIndex: 0,
                                pointIndex: 2
                            )
                    )
            )

        XCTAssertEqual(
            result.layer.pathContourClosed,
            [
                true,
                true
            ]
        )
    }

    func testSplitOpenContourInsideCompoundPreservesUnrelatedClosure() throws {
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
            CoverLayer(
                kind: .path,
                name: "Mixed Split"
            )

        layer.pathPoints = first
        layer.pathContours = [
            first,
            second
        ]
        layer.pathContourClosed = [
            true,
            false
        ]
        layer.pathClosed = true

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

        XCTAssertEqual(
            result.layer.pathContourClosed,
            [
                true,
                false,
                false
            ]
        )

        XCTAssertEqual(
            result.layer
                .pathContours?
                .first,
            first
        )

        XCTAssertEqual(
            result.layer.pathClosed,
            true
        )
    }

    func testSplitClosedContourInsideCompoundOpensOnlyThatContour() throws {
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
            CoverLayer(
                kind: .path,
                name: "Mixed Closed Split"
            )

        layer.pathPoints = first
        layer.pathContours = [
            first,
            second
        ]
        layer.pathContourClosed = [
            false,
            true
        ]
        layer.pathClosed = false

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

        XCTAssertEqual(
            result.layer.pathContourClosed,
            [
                false,
                false
            ]
        )

        XCTAssertEqual(
            result.layer
                .pathContours?
                .count,
            2
        )
    }

    func testCutContourInsideCompoundPreservesUnrelatedContour() throws {
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
            CoverLayer(
                kind: .path,
                name: "Mixed Cut"
            )

        layer.pathPoints = first
        layer.pathContours = [
            first,
            second
        ]
        layer.pathContourClosed = [
            true,
            false
        ]
        layer.pathClosed = true

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

        XCTAssertEqual(
            result.layer
                .pathContours?
                .first,
            first
        )

        XCTAssertEqual(
            result.layer
                .pathContourClosed?
                .first,
            true
        )

        XCTAssertTrue(
            result.layer
                .pathContourClosed?
                .dropFirst()
                .allSatisfy {
                    !$0
                }
            ?? false
        )
    }

    func testDeletingSecondaryContourBelowThreeAnchorsRemovesMatchingClosure() {
        let first = [
            point(0),
            point(1),
            point(2)
        ]

        let second = [
            point(3),
            point(4)
        ]

        var layer =
            CoverLayer(
                kind: .path,
                name: "Delete Contour"
            )

        layer.pathPoints = first
        layer.pathContours = [
            first,
            second
        ]
        layer.pathContourClosed = [
            true,
            false
        ]
        layer.pathClosed = true

        let result =
            CoverEditorEngine
                .deletingVectorPoint(
                    in: layer,
                    contourIndex: 1,
                    pointIndex: 1
                )

        XCTAssertEqual(
            result.pathContours?.count,
            1
        )

        XCTAssertEqual(
            result.pathContourClosed,
            [
                true
            ]
        )

        XCTAssertEqual(
            result.pathClosed,
            true
        )
    }

    func testDeletingLegacySingleContourBelowThreeAnchorsKeepsContourOpen() {
        var layer =
            CoverLayer(
                kind: .path,
                name: "Legacy Single"
            )

        layer.pathPoints = [
            point(0),
            point(1),
            point(2)
        ]
        layer.pathContours = nil
        layer.pathClosed = true
        layer.pathContourClosed = nil

        let result =
            CoverEditorEngine
                .deletingVectorPoint(
                    in: layer,
                    contourIndex: 0,
                    pointIndex: 1
                )

        XCTAssertEqual(
            result.pathPoints?.count,
            2
        )

        XCTAssertNil(
            result.pathContours
        )

        XCTAssertEqual(
            result.pathContourClosed,
            [
                false
            ]
        )

        XCTAssertEqual(
            result.pathClosed,
            false
        )
    }

    func testReplacingSecondaryContourPreservesItsClosure() {
        let layer =
            compoundLayer(
                closures: [
                    true,
                    false
                ]
            )

        let replacement = [
            point(10),
            point(11),
            point(12)
        ]

        let result =
            CoverEditorEngine
                .replacingVectorContour(
                    in: layer,
                    contourIndex: 1,
                    points: replacement
                )

        XCTAssertEqual(
            result.pathContourClosed,
            [
                true,
                false
            ]
        )

        XCTAssertEqual(
            result.pathContours?[1],
            replacement
        )
    }
}
