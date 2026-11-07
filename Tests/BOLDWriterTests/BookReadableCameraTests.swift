import XCTest
import SceneKit
@testable import BOLDWriter

final class BookReadableCameraTests: XCTestCase {
    func testReadableSpreadOpensFlat() {
        var source = BookStudioPresentation()
        source.open = false
        source.openAngle = 25
        source.cameraPreset = .front

        let result = BookStudioQuickView.readableSpread.apply(
            to: source
        )

        XCTAssertTrue(result.open)
        XCTAssertEqual(result.openAngle, 180)
        XCTAssertEqual(result.cameraPreset, .reading)
        XCTAssertEqual(result.cameraFieldOfView, 34)
    }

    func testInspectThicknessUsesThreeQuarterPose() {
        var source = BookStudioPresentation()
        source.open = false
        source.cameraPreset = .spine

        let result = BookStudioQuickView.inspectThickness.apply(
            to: source
        )

        XCTAssertTrue(result.open)
        XCTAssertEqual(result.openAngle, 125)
        XCTAssertEqual(result.cameraPreset, .perspective)
        XCTAssertEqual(result.cameraFieldOfView, 34)
    }

    func testQuickViewsClearOldCameraOverride() {
        for view in BookStudioQuickView.allCases {
            var source = BookStudioPresentation()
            source.exploded = true

            let result = view.apply(to: source)

            XCTAssertNil(result.savedCamera)
            XCTAssertFalse(result.exploded)
        }
    }

    func testQuickViewsPreserveCurrentManuscriptSpread() {
        var source = BookStudioPresentation()
        source.spreadIndex = 80

        for view in BookStudioQuickView.allCases {
            let result = view.apply(to: source)
            XCTAssertEqual(result.spreadIndex, 80)
        }
    }

    func testQuickViewsPreserveBindingAndPaper() {
        var source = BookStudioPresentation()
        source.binding = .hardcover
        source.paper = .cream

        for view in BookStudioQuickView.allCases {
            let result = view.apply(to: source)
            XCTAssertEqual(result.binding, .hardcover)
            XCTAssertEqual(result.paper, .cream)
        }
    }

    func testQuickViewsPreserveLightingAndShadows() {
        var source = BookStudioPresentation()
        source.environment = .warm
        source.shadowsEnabled = false

        for view in BookStudioQuickView.allCases {
            let result = view.apply(to: source)
            XCTAssertEqual(result.environment, .warm)
            XCTAssertFalse(result.shadowsEnabled)
        }
    }

    func testQuickViewSelectionIsIdempotent() {
        for view in BookStudioQuickView.allCases {
            let first = view.apply(to: BookStudioPresentation())
            let second = view.apply(to: first)

            XCTAssertEqual(first.open, second.open)
            XCTAssertEqual(first.openAngle, second.openAngle)
            XCTAssertEqual(first.cameraPreset, second.cameraPreset)
            XCTAssertEqual(
                first.cameraFieldOfView,
                second.cameraFieldOfView
            )
            XCTAssertEqual(first.spreadIndex, second.spreadIndex)
        }
    }

    func testExistingCameraOrbitSensitivityIsPreserved() {
        var camera = BookPreviewCameraState(
            yaw: 0.5,
            pitch: 0.6,
            distance: 5
        )

        camera.orbit(deltaX: 12.5, deltaY: -4)

        XCTAssertEqual(camera.yaw, 0.6, accuracy: 0.000001)
        XCTAssertEqual(camera.pitch, 0.568, accuracy: 0.000001)
        XCTAssertEqual(camera.distance, 5, accuracy: 0.000001)
    }
}
