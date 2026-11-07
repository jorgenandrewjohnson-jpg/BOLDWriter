import AppKit
import SceneKit
import SwiftUI
import XCTest
@testable import BOLDWriter

@MainActor
final class BookClosedFramingTests: XCTestCase {
    private final class CameraStore { var saved: BookSavedCamera? }
    private func surface(project: CoverProject, open: Bool, preset: BookViewPreset, reset: Int = 0,
                         store: CameraStore, handle: BookStudioViewportHandle) -> BookPreviewSceneView {
        var presentation = BookStudioPresentation()
        presentation.savedCamera = store.saved
        presentation.open = open
        presentation.binding = .hardcover
        presentation.cameraPreset = preset
        return BookPreviewSceneView(project: project, workingLayers: false, binding: .hardcover,
            isOpen: open, openAngle: 180, pageCount: 160, spreadIndex: 0,
            turnTransition: nil, turnTexture: nil, turnReverseTexture: nil, turnGeneration: 0,
            leftPage: nil, rightPage: 1, leftTexture: nil, rightTexture: nil,
            showMargins: false, thumbMode: .off, leftPageSettings: PageSettings(), rightPageSettings: PageSettings(),
            preset: preset, revisionID: project.id, resetGeneration: reset,
            focusGeneration: 0, focus: .automatic, zoomAction: .fit, zoomGeneration: 0,
            zoomDisplayScale: .constant(1), presentation: presentation, modelTransform: .constant(.identity),
            transformMode: .constant(.navigate), transformSpace: .constant(.local), customLights: .constant([]),
            selectedCustomLightID: .constant(nil), savedCamera: Binding(get: { store.saved }, set: { store.saved = $0 }),
            selection: .constant(nil), viewportHandle: handle, cameraLink: nil, isComparisonViewport: false)
    }

    func testClosedHardcoverFitsAfterReadingAndManualOrbit() throws {
        var project = CoverProject(type: .printFullWrap); project.dpi = 24
        let store = CameraStore(), handle = BookStudioViewportHandle()
        let coordinator = BookPreviewSceneView.Coordinator()
        let initial = surface(project: project, open: true, preset: .reading, store: store, handle: handle)
        let view = initial.makeInteractionView(coordinator: coordinator)
        view.setFrameSize(NSSize(width: 706, height: 536))
        view.onOrbit?(25, -10)
        view.onNavigationEnded?()
        let closed = surface(project: project, open: false, preset: .front, reset: 1, store: store, handle: handle)
        closed.updateInteractionView(view, coordinator: coordinator)
        assertFits(view)
    }

    func testClosingAfterManualZoomRefitsWithoutChangingOrbit() throws {
        var project = CoverProject(type: .printFullWrap); project.dpi = 24
        let store = CameraStore(), handle = BookStudioViewportHandle()
        let coordinator = BookPreviewSceneView.Coordinator()
        let initial = surface(project: project, open: true, preset: .perspective, store: store, handle: handle)
        let view = initial.makeInteractionView(coordinator: coordinator)
        view.setFrameSize(NSSize(width: 706, height: 536))
        view.onOrbit?(25, -10)
        view.onZoom?(0.5)
        view.onNavigationEnded?()
        let orbit = coordinator.cameraState
        let closed = surface(project: project, open: false, preset: .perspective, store: store, handle: handle)
        closed.updateInteractionView(view, coordinator: coordinator)
        XCTAssertEqual(coordinator.cameraState.yaw, orbit.yaw)
        XCTAssertEqual(coordinator.cameraState.pitch, orbit.pitch)
        XCTAssertGreaterThan(coordinator.cameraState.distance, orbit.distance)
        assertFits(view)
    }

    private func assertFits(_ view: BookPreviewInteractionView, file: StaticString = #filePath, line: UInt = #line) {
        guard let root = view.scene?.rootNode.childNode(withName: "physical-book.root", recursively: true) else {
            return XCTFail("Missing book", file: file, line: line)
        }
        let b = root.boundingBox
        for x in [b.min.x, b.max.x] { for y in [b.min.y, b.max.y] { for z in [b.min.z, b.max.z] {
            let p = view.projectPoint(root.convertPosition(SCNVector3(x,y,z), to: nil))
            XCTAssertGreaterThanOrEqual(p.x, 0, file: file, line: line)
            XCTAssertLessThanOrEqual(p.x, view.bounds.width, file: file, line: line)
            XCTAssertGreaterThanOrEqual(p.y, 0, file: file, line: line)
            XCTAssertLessThanOrEqual(p.y, view.bounds.height, file: file, line: line)
        } } }
    }
}
