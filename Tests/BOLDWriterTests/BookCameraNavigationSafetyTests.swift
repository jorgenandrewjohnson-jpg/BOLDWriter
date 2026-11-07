import XCTest
@testable import BOLDWriter

final class BookCameraNavigationSafetyTests: XCTestCase {
    private func camera() -> BookPreviewCameraState {
        BookPreviewCameraState(yaw: 0.22, pitch: 0.92, distance: 20)
    }

    func testInvalidOrbitDoesNotChangeCamera() {
        var state = camera()
        let original = state
        state.orbit(deltaX: .nan, deltaY: 5)
        XCTAssertEqual(state, original)
        state.orbit(deltaX: 5, deltaY: .infinity)
        XCTAssertEqual(state, original)
    }

    func testRegularOrbitStillMatchesNativeGestureBehavior() {
        var state = camera()
        state.orbit(deltaX: 250, deltaY: -100)
        XCTAssertEqual(state.yaw, 2.22, accuracy: 0.00001)
        XCTAssertEqual(state.pitch, 0.12, accuracy: 0.00001)
    }

    func testExtendedOrbitKeepsYawFiniteAndBounded() {
        var state = camera()
        state.orbit(deltaX: 1e300, deltaY: -1e300)
        XCTAssertTrue(state.yaw.isFinite)
        XCTAssertLessThan(abs(state.yaw), 2 * Double.pi)
        XCTAssertEqual(state.pitch, -1.52, accuracy: 0.00001)
    }

    func testInvalidZoomInputPreservesValidDistance() {
        var state = camera()
        state.zoom(by: .infinity, minimum: 2, maximum: 30)
        XCTAssertEqual(state.distance, 20, accuracy: 0.00001)
        state.zoom(by: -2, minimum: 2, maximum: 30)
        XCTAssertEqual(state.distance, 20, accuracy: 0.00001)
    }

    func testZoomRecoversInvalidDistance() {
        var state = camera()
        state.distance = .nan
        state.zoom(by: 1.5, minimum: 2, maximum: 30)
        XCTAssertEqual(state.distance, 3, accuracy: 0.00001)
    }

    func testExtremeZoomClampsInsteadOfOverflowing() {
        var state = camera()
        state.distance = 1e300
        state.zoom(by: 1e300, minimum: 2, maximum: 30)
        XCTAssertEqual(state.distance, 30, accuracy: 0.00001)
    }

    func testInvalidPanCannotCorruptTarget() {
        var state = camera()
        let original = state.target
        state.pan(deltaX: .nan, deltaY: 5, viewportHeight: 800)
        XCTAssertEqual(state.target, original)
        state.pan(deltaX: 2, deltaY: 5, viewportHeight: .infinity)
        XCTAssertEqual(state.target, original)
        state.pan(deltaX: 2, deltaY: 5, viewportHeight: 800, fieldOfView: 180)
        XCTAssertEqual(state.target, original)
    }

    func testNormalPanStillMovesTarget() {
        var state = camera()
        let original = state.target
        state.pan(deltaX: 100, deltaY: 50, viewportHeight: 800)
        XCTAssertNotEqual(state.target, original)
        XCTAssertTrue(state.target.x.isFinite)
        XCTAssertTrue(state.target.y.isFinite)
        XCTAssertTrue(state.target.z.isFinite)
    }

    func testPanOverflowIsAtomic() {
        var state = camera()
        state.distance = 1e308
        let original = state.target
        state.pan(deltaX: 1e308, deltaY: 10, viewportHeight: 1)
        XCTAssertEqual(state.target, original)
    }
}
