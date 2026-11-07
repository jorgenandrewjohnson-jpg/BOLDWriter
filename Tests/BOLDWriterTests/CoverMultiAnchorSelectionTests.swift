import XCTest
@testable import BOLDWriter

final class CoverMultiAnchorSelectionTests: XCTestCase {
    func testGroupTranslationMovesOnlySelectedAnchorsAndCarriesBezierHandles() throws {
        var layer = CoverLayer(
            kind: .path,
            name: "Path"
        )

        layer.pathPoints = [
            CoverPathPoint(
                x: 0.10,
                y: 0.20,
                controlInX: 0.05,
                controlInY: 0.20,
                controlOutX: 0.15,
                controlOutY: 0.20
            ),
            CoverPathPoint(
                x: 0.40,
                y: 0.50,
                controlInX: 0.35,
                controlInY: 0.45,
                controlOutX: 0.45,
                controlOutY: 0.55
            ),
            CoverPathPoint(
                x: 0.80,
                y: 0.75
            )
        ]

        let selected: Set<CoverVectorAnchorIndex> = [
            CoverVectorAnchorIndex(
                contourIndex: 0,
                pointIndex: 0
            ),
            CoverVectorAnchorIndex(
                contourIndex: 0,
                pointIndex: 1
            )
        ]

        let moved =
            CoverEditorEngine
                .translatingVectorAnchors(
                    in: layer,
                    selections: selected,
                    deltaX: 0.10,
                    deltaY: -0.05
                )

        let points =
            try XCTUnwrap(
                moved.pathPoints
            )

        XCTAssertEqual(
            points[0].x,
            0.20,
            accuracy: 0.0000001
        )
        XCTAssertEqual(
            points[0].y,
            0.15,
            accuracy: 0.0000001
        )
        XCTAssertEqual(
            try XCTUnwrap(
                points[0].controlInX
            ),
            0.15,
            accuracy: 0.0000001
        )
        XCTAssertEqual(
            try XCTUnwrap(
                points[0].controlInY
            ),
            0.15,
            accuracy: 0.0000001
        )
        XCTAssertEqual(
            try XCTUnwrap(
                points[0].controlOutX
            ),
            0.25,
            accuracy: 0.0000001
        )
        XCTAssertEqual(
            try XCTUnwrap(
                points[0].controlOutY
            ),
            0.15,
            accuracy: 0.0000001
        )

        XCTAssertEqual(
            points[1].x,
            0.50,
            accuracy: 0.0000001
        )
        XCTAssertEqual(
            points[1].y,
            0.45,
            accuracy: 0.0000001
        )
        XCTAssertEqual(
            try XCTUnwrap(
                points[1].controlInX
            ),
            0.45,
            accuracy: 0.0000001
        )
        XCTAssertEqual(
            try XCTUnwrap(
                points[1].controlInY
            ),
            0.40,
            accuracy: 0.0000001
        )
        XCTAssertEqual(
            try XCTUnwrap(
                points[1].controlOutX
            ),
            0.55,
            accuracy: 0.0000001
        )
        XCTAssertEqual(
            try XCTUnwrap(
                points[1].controlOutY
            ),
            0.50,
            accuracy: 0.0000001
        )

        XCTAssertEqual(
            points[2].x,
            0.80,
            accuracy: 0.0000001
        )
        XCTAssertEqual(
            points[2].y,
            0.75,
            accuracy: 0.0000001
        )

        XCTAssertNil(
            moved.pathContours
        )
    }

    func testGroupTranslationSupportsSelectionsAcrossCompoundContours() throws {
        let primary = [
            CoverPathPoint(
                x: 0.10,
                y: 0.10
            ),
            CoverPathPoint(
                x: 0.40,
                y: 0.10
            ),
            CoverPathPoint(
                x: 0.40,
                y: 0.40
            ),
            CoverPathPoint(
                x: 0.10,
                y: 0.40
            )
        ]

        let secondary = [
            CoverPathPoint(
                x: 0.60,
                y: 0.60,
                controlOutX: 0.65,
                controlOutY: 0.60
            ),
            CoverPathPoint(
                x: 0.80,
                y: 0.60
            ),
            CoverPathPoint(
                x: 0.80,
                y: 0.80
            ),
            CoverPathPoint(
                x: 0.60,
                y: 0.80
            )
        ]

        var layer = CoverLayer(
            kind: .path,
            name: "Compound"
        )

        layer.pathPoints = primary
        layer.pathContours = [
            primary,
            secondary
        ]
        layer.pathClosed = true

        let selected: Set<CoverVectorAnchorIndex> = [
            CoverVectorAnchorIndex(
                contourIndex: 0,
                pointIndex: 1
            ),
            CoverVectorAnchorIndex(
                contourIndex: 1,
                pointIndex: 0
            )
        ]

        let moved =
            CoverEditorEngine
                .translatingVectorAnchors(
                    in: layer,
                    selections: selected,
                    deltaX: 0.05,
                    deltaY: 0.10
                )

        let contours =
            try XCTUnwrap(
                moved.pathContours
            )

        XCTAssertEqual(
            contours.count,
            2
        )

        XCTAssertEqual(
            contours[0][0],
            primary[0]
        )
        XCTAssertEqual(
            contours[0][1].x,
            0.45,
            accuracy: 0.0000001
        )
        XCTAssertEqual(
            contours[0][1].y,
            0.20,
            accuracy: 0.0000001
        )

        XCTAssertEqual(
            contours[1][0].x,
            0.65,
            accuracy: 0.0000001
        )
        XCTAssertEqual(
            contours[1][0].y,
            0.70,
            accuracy: 0.0000001
        )
        XCTAssertEqual(
            try XCTUnwrap(
                contours[1][0].controlOutX
            ),
            0.70,
            accuracy: 0.0000001
        )
        XCTAssertEqual(
            try XCTUnwrap(
                contours[1][0].controlOutY
            ),
            0.70,
            accuracy: 0.0000001
        )

        XCTAssertEqual(
            moved.pathPoints,
            contours.first
        )
    }

    func testGroupTranslationIgnoresInvalidAnchorSelections() throws {
        var layer = CoverLayer(
            kind: .path,
            name: "Path"
        )

        layer.pathPoints = [
            CoverPathPoint(
                x: 0.20,
                y: 0.30
            ),
            CoverPathPoint(
                x: 0.70,
                y: 0.80
            )
        ]

        let original =
            try XCTUnwrap(
                layer.pathPoints
            )

        let selected: Set<CoverVectorAnchorIndex> = [
            CoverVectorAnchorIndex(
                contourIndex: 4,
                pointIndex: 10
            )
        ]

        let moved =
            CoverEditorEngine
                .translatingVectorAnchors(
                    in: layer,
                    selections: selected,
                    deltaX: 0.25,
                    deltaY: 0.25
                )

        XCTAssertEqual(
            moved.pathPoints,
            original
        )
        XCTAssertNil(
            moved.pathContours
        )
    }

    func testClampedAnchorTranslationCarriesHandlesByActualAppliedDelta() throws {
        var layer = CoverLayer(
            kind: .path,
            name: "Path"
        )

        layer.pathPoints = [
            CoverPathPoint(
                x: 4.95,
                y: 0.40,
                controlInX: 4.75,
                controlInY: 0.40,
                controlOutX: 5.15,
                controlOutY: 0.40
            )
        ]

        let selected: Set<CoverVectorAnchorIndex> = [
            CoverVectorAnchorIndex(
                contourIndex: 0,
                pointIndex: 0
            )
        ]

        let moved =
            CoverEditorEngine
                .translatingVectorAnchors(
                    in: layer,
                    selections: selected,
                    deltaX: 0.20,
                    deltaY: 0
                )

        let point =
            try XCTUnwrap(
                moved.pathPoints?.first
            )

        XCTAssertEqual(
            point.x,
            5.0,
            accuracy: 0.0000001
        )

        XCTAssertEqual(
            try XCTUnwrap(
                point.controlInX
            ),
            4.80,
            accuracy: 0.0000001
        )

        XCTAssertEqual(
            try XCTUnwrap(
                point.controlOutX
            ),
            5.20,
            accuracy: 0.0000001
        )
    }
}
