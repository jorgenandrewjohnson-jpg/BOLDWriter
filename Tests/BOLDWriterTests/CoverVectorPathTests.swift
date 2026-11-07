import AppKit
import XCTest
@testable import BOLDWriter

final class CoverVectorPathTests: XCTestCase {
    func testPenAndPathToolsAreExposedAndGrouped() {
        XCTAssertTrue(CoverEditorTool.pen.isImplemented)
        XCTAssertTrue(CoverEditorTool.path.isImplemented)

        let tools = CoverEditorTool.toolbarGroups.flatMap { $0 }

        XCTAssertTrue(tools.contains(.pen))
        XCTAssertTrue(tools.contains(.path))
        XCTAssertEqual(tools.count, Set(tools).count)
    }

    func testBezierBuilderUsesStoredHandlesAndSupportsOpenAndClosedPaths() {
        let points = [
            CoverPathPoint(
                x: 0.1,
                y: 0.5,
                controlOutX: 0.25,
                controlOutY: 0.05
            ),
            CoverPathPoint(
                x: 0.9,
                y: 0.5,
                controlInX: 0.75,
                controlInY: 0.95
            )
        ]

        XCTAssertTrue(
            CoverEditorEngine.vectorSegmentIsCurved(
                points[0],
                points[1]
            )
        )

        let open = CoverEditorEngine.vectorPath(
            points: points,
            in: NSRect(
                x: 0,
                y: 0,
                width: 200,
                height: 100
            ),
            closed: false
        )

        let closed = CoverEditorEngine.vectorPath(
            points: points,
            in: NSRect(
                x: 0,
                y: 0,
                width: 200,
                height: 100
            ),
            closed: true
        )

        XCTAssertEqual(open.elementCount, 2)
        XCTAssertGreaterThan(
            closed.elementCount,
            open.elementCount
        )
        XCTAssertGreaterThan(
            open.controlPointBounds.height,
            0
        )
    }

    func testPathAnchorMoveCarriesItsBezierHandles() throws {
        let original = [
            CoverPathPoint(
                x: 0.25,
                y: 0.25,
                controlInX: 0.20,
                controlInY: 0.20,
                controlOutX: 0.30,
                controlOutY: 0.30
            )
        ]

        let moved = CoverEditorEngine.movedPathPoint(
            original,
            index: 0,
            to: CGPoint(
                x: 0.50,
                y: 0.60
            )
        )

        XCTAssertEqual(
            moved[0].x,
            0.50,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            moved[0].y,
            0.60,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            try XCTUnwrap(moved[0].controlInX),
            0.45,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            try XCTUnwrap(moved[0].controlInY),
            0.55,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            try XCTUnwrap(moved[0].controlOutX),
            0.55,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            try XCTUnwrap(moved[0].controlOutY),
            0.65,
            accuracy: 0.0001
        )
    }

    func testOptionStyleControlMoveMirrorsOppositeHandle() throws {
        let changed = CoverEditorEngine.movedPathControl(
            [
                CoverPathPoint(
                    x: 0.5,
                    y: 0.5
                )
            ],
            index: 0,
            to: CGPoint(
                x: 0.8,
                y: 0.6
            ),
            incoming: false,
            mirrorOpposite: true
        )

        XCTAssertEqual(
            try XCTUnwrap(changed[0].controlOutX),
            0.8,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            try XCTUnwrap(changed[0].controlOutY),
            0.6,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            try XCTUnwrap(changed[0].controlInX),
            0.2,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            try XCTUnwrap(changed[0].controlInY),
            0.4,
            accuracy: 0.0001
        )
    }

    func testAppendingDraggedAnchorCreatesSymmetricHandles() throws {
        let points = CoverEditorEngine.appendedPathPoint(
            [],
            anchor: CGPoint(
                x: 0.4,
                y: 0.5
            ),
            draggedTo: CGPoint(
                x: 0.7,
                y: 0.8
            )
        )

        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(
            try XCTUnwrap(points[0].controlOutX),
            0.7,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            try XCTUnwrap(points[0].controlOutY),
            0.8,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            try XCTUnwrap(points[0].controlInX),
            0.1,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            try XCTUnwrap(points[0].controlInY),
            0.2,
            accuracy: 0.0001
        )
    }

    func testPathClosedAndBezierControlsPersist() throws {
        var layer = CoverLayer(
            kind: .path,
            name: "Bezier"
        )

        layer.pathClosed = true
        layer.pathPoints = [
            CoverPathPoint(
                x: 0.2,
                y: 0.3,
                controlOutX: 0.4,
                controlOutY: 0.1
            ),
            CoverPathPoint(
                x: 0.8,
                y: 0.7,
                controlInX: 0.6,
                controlInY: 0.9
            )
        ]

        let reopened = try JSONDecoder().decode(
            CoverLayer.self,
            from: JSONEncoder().encode(layer)
        )

        XCTAssertEqual(reopened.pathClosed, true)
        XCTAssertEqual(reopened.pathPoints, layer.pathPoints)
    }

    func testRemovingPointKeepsRemainingStableAndSafe() {
        let points = [
            CoverPathPoint(
                x: 0.1,
                y: 0.1
            ),
            CoverPathPoint(
                x: 0.5,
                y: 0.5
            ),
            CoverPathPoint(
                x: 0.9,
                y: 0.9
            )
        ]

        let result = CoverEditorEngine.removedPathPoint(
            points,
            index: 1
        )

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0], points[0])
        XCTAssertEqual(result[1], points[2])

        XCTAssertEqual(
            CoverEditorEngine.removedPathPoint(
                points,
                index: 99
            ),
            points
        )
    }
}
