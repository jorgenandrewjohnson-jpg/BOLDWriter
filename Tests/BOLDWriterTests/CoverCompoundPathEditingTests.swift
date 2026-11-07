import XCTest
@testable import BOLDWriter

final class CoverCompoundPathEditingTests: XCTestCase {
    private func square(
        x: Double = 0,
        y: Double = 0,
        size: Double = 1
    ) -> [CoverPathPoint] {
        [
            CoverPathPoint(
                x: x,
                y: y
            ),
            CoverPathPoint(
                x: x + size,
                y: y
            ),
            CoverPathPoint(
                x: x + size,
                y: y + size
            ),
            CoverPathPoint(
                x: x,
                y: y + size
            )
        ]
    }

    private func compoundLayer() -> CoverLayer {
        var layer = CoverLayer(
            kind: .path,
            name: "Compound"
        )

        let outer = square()

        let hole = square(
            x: 0.25,
            y: 0.25,
            size: 0.5
        )

        layer.pathPoints = outer

        layer.pathContours = [
            outer,
            hole
        ]

        layer.pathClosed = true

        return layer
    }

    func testAnchorCountIncludesEveryContour() {
        let layer = compoundLayer()

        XCTAssertEqual(
            CoverEditorEngine
                .vectorAnchorCount(
                    for: layer
                ),
            8
        )

        XCTAssertEqual(
            CoverPathPanelModel
                .anchorCount(
                    for: layer
                ),
            8
        )
    }

    func testReplacingSecondaryContourLeavesPrimaryStable() {
        let layer = compoundLayer()
        let primary = layer.pathPoints

        let replacement = [
            CoverPathPoint(
                x: 0.2,
                y: 0.2
            ),
            CoverPathPoint(
                x: 0.8,
                y: 0.2
            ),
            CoverPathPoint(
                x: 0.5,
                y: 0.8
            )
        ]

        let changed =
            CoverEditorEngine
                .replacingVectorContour(
                    in: layer,
                    contourIndex: 1,
                    points: replacement
                )

        XCTAssertEqual(
            changed.pathPoints,
            primary
        )

        XCTAssertEqual(
            changed.pathContours?[1],
            replacement
        )
    }

    func testReplacingPrimaryContourSynchronizesLegacyPoints() {
        let layer = compoundLayer()

        let replacement = [
            CoverPathPoint(
                x: 0,
                y: 0
            ),
            CoverPathPoint(
                x: 0.9,
                y: 0
            ),
            CoverPathPoint(
                x: 0.9,
                y: 0.9
            ),
            CoverPathPoint(
                x: 0,
                y: 0.9
            )
        ]

        let changed =
            CoverEditorEngine
                .replacingVectorContour(
                    in: layer,
                    contourIndex: 0,
                    points: replacement
                )

        XCTAssertEqual(
            changed.pathPoints,
            replacement
        )

        XCTAssertEqual(
            changed.pathContours?[0],
            replacement
        )
    }

    func testDeletingSecondaryContourAnchorDoesNotTouchPrimary() {
        let layer = compoundLayer()
        let primary = layer.pathPoints

        let changed =
            CoverEditorEngine
                .deletingVectorPoint(
                    in: layer,
                    contourIndex: 1,
                    pointIndex: 0
                )

        XCTAssertEqual(
            changed.pathPoints,
            primary
        )

        XCTAssertEqual(
            changed.pathContours?[1].count,
            3
        )

        XCTAssertTrue(
            changed.pathClosed == true
        )
    }

    func testDeletingBelowThreeAnchorsRemovesOnlySecondaryContour() {
        var layer = compoundLayer()

        layer.pathContours?[1] = [
            CoverPathPoint(
                x: 0.25,
                y: 0.25
            ),
            CoverPathPoint(
                x: 0.75,
                y: 0.25
            ),
            CoverPathPoint(
                x: 0.5,
                y: 0.75
            )
        ]

        let primary = layer.pathPoints

        let changed =
            CoverEditorEngine
                .deletingVectorPoint(
                    in: layer,
                    contourIndex: 1,
                    pointIndex: 0
                )

        XCTAssertEqual(
            changed.pathContours?.count,
            1
        )

        XCTAssertEqual(
            changed.pathPoints,
            primary
        )

        XCTAssertTrue(
            changed.pathClosed == true
        )
    }

    func testDeletingLegacySingleContourPreservesOldOpenBehavior() {
        var layer = CoverLayer(
            kind: .path,
            name: "Legacy"
        )

        layer.pathPoints = [
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
            )
        ]

        layer.pathClosed = true
        layer.pathContours = nil

        let changed =
            CoverEditorEngine
                .deletingVectorPoint(
                    in: layer,
                    contourIndex: 0,
                    pointIndex: 1
                )

        XCTAssertEqual(
            changed.pathPoints?.count,
            2
        )

        XCTAssertNil(
            changed.pathContours
        )

        XCTAssertFalse(
            changed.pathClosed
            ?? true
        )
    }

    func testSecondaryContourBezierHandlesRemainEditable() throws {
        var layer = compoundLayer()

        var hole = try XCTUnwrap(
            layer.pathContours?[1]
        )

        hole[0].controlOutX = 0.4
        hole[0].controlOutY = 0.25

        layer =
            CoverEditorEngine
                .replacingVectorContour(
                    in: layer,
                    contourIndex: 1,
                    points: hole
                )

        var edited = try XCTUnwrap(
            layer.pathContours?[1]
        )

        edited =
            CoverEditorEngine
                .movedPathControl(
                    edited,
                    index: 0,
                    to: CGPoint(
                        x: 0.45,
                        y: 0.30
                    ),
                    incoming: false,
                    mirrorOpposite: true
                )

        let changed =
            CoverEditorEngine
                .replacingVectorContour(
                    in: layer,
                    contourIndex: 1,
                    points: edited
                )

        let changedHole = try XCTUnwrap(
            changed.pathContours?[1]
        )

        let outX = try XCTUnwrap(
            changedHole[0].controlOutX
        )

        let outY = try XCTUnwrap(
            changedHole[0].controlOutY
        )

        XCTAssertEqual(
            outX,
            0.45,
            accuracy: 0.000001
        )

        XCTAssertEqual(
            outY,
            0.30,
            accuracy: 0.000001
        )
    }

    func testCompoundContourEditingPersists() throws {
        let original = compoundLayer()

        let encoded =
            try JSONEncoder()
                .encode(original)

        let reopened =
            try JSONDecoder()
                .decode(
                    CoverLayer.self,
                    from: encoded
                )

        XCTAssertEqual(
            reopened.pathContours,
            original.pathContours
        )

        XCTAssertEqual(
            reopened.pathPoints,
            original.pathPoints
        )
    }
}
