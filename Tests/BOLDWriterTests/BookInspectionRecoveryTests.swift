import AppKit
import SceneKit
import SwiftUI
import XCTest
@testable import BOLDWriter

@MainActor
final class BookInspectionRecoveryTests: XCTestCase {
    private final class CameraStore {
        var saved: BookSavedCamera?
    }

    private func surface(project: CoverProject, link: BookInspectionCameraLink?, secondary: Bool,
                         store: CameraStore, handle: BookStudioViewportHandle) -> BookPreviewSceneView {
        var presentation = BookStudioPresentation()
        presentation.savedCamera = store.saved
        return BookPreviewSceneView(project: project, workingLayers: false, binding: .softcover,
            isOpen: false, openAngle: 180, pageCount: 160, spreadIndex: 0,
            turnTransition: nil, turnTexture: nil, turnReverseTexture: nil, turnGeneration: 0,
            leftPage: nil, rightPage: 1, leftTexture: nil, rightTexture: nil,
            showMargins: false, thumbMode: .off, leftPageSettings: PageSettings(), rightPageSettings: PageSettings(),
            preset: .perspective, revisionID: project.id, resetGeneration: 0,
            focusGeneration: 0, focus: .automatic, zoomAction: .fit, zoomGeneration: 0,
            zoomDisplayScale: .constant(1), presentation: presentation, modelTransform: .constant(.identity),
            transformMode: .constant(.navigate), transformSpace: .constant(.local), customLights: .constant([]),
            selectedCustomLightID: .constant(nil), savedCamera: Binding(get: { store.saved }, set: { store.saved = $0 }),
            selection: .constant(nil), viewportHandle: handle, cameraLink: link, isComparisonViewport: secondary)
    }

    func testRealInteractionCallbacksSynchronizeCommitAndRemainIndependentWhenDisabled() throws {
        var project = CoverProject(type: .printFullWrap)
        project.dpi = 24
        let link = BookInspectionCameraLink()
        let a = CameraStore(), b = CameraStore()
        let ca = BookPreviewSceneView.Coordinator(), cb = BookPreviewSceneView.Coordinator()
        let sa = surface(project: project, link: link, secondary: false, store: a, handle: BookStudioViewportHandle())
        let sb = surface(project: project, link: link, secondary: true, store: b, handle: BookStudioViewportHandle())
        let va = sa.makeInteractionView(coordinator: ca), vb = sb.makeInteractionView(coordinator: cb)
        va.onOrbit?(30, 15)
        XCTAssertEqual(ca.cameraState, cb.cameraState)
        vb.onPan?(25, 10, 600)
        XCTAssertEqual(ca.cameraState, cb.cameraState)
        va.onZoom?(1.2)
        XCTAssertEqual(ca.cameraState, cb.cameraState)
        XCTAssertNil(a.saved)
        va.onNavigationEnded?()
        XCTAssertEqual(a.saved, b.saved)
        XCTAssertEqual(a.saved, ca.cameraState.saved)

        link.enabled = false
        let before = cb.cameraState
        va.onOrbit?(40, -20)
        va.onNavigationEnded?()
        XCTAssertEqual(cb.cameraState, before)
        XCTAssertNotEqual(a.saved, b.saved)
        let independent = ca.cameraState
        vb.onZoom?(1.1)
        XCTAssertEqual(ca.cameraState, independent)

        link.enabled = true
        let node = SCNNode(geometry: SCNBox(width: 1, height: 2, length: 0.2, chamferRadius: 0))
        va.scene?.rootNode.addChildNode(node)
        va.onFrameSelection?(node)
        XCTAssertEqual(ca.cameraState, cb.cameraState)
        XCTAssertEqual(a.saved, b.saved)
        XCTAssertEqual(b.saved, ca.cameraState.saved)
    }

    func testNativeIdentitySceneReuseAndExplicitLinkDetachment() throws {
        var project = CoverProject(type: .printFullWrap); project.dpi = 24
        let link = BookInspectionCameraLink(), store = CameraStore(), handle = BookStudioViewportHandle()
        let coordinator = BookPreviewSceneView.Coordinator()
        let initial = surface(project: project, link: link, secondary: false, store: store, handle: handle)
        let view = initial.makeInteractionView(coordinator: coordinator)
        let scene = try XCTUnwrap(view.scene)
        XCTAssertEqual(view.accessibilityIdentifier(), "bookstudio.viewport")
        XCTAssertEqual(view.accessibilityLabel(), "3D book preview")
        let secondary = BookPreviewInteractionView(); secondary.isComparisonViewport = true
        XCTAssertEqual(secondary.accessibilityIdentifier(), "bookstudio.comparison")
        XCTAssertEqual(secondary.accessibilityLabel(), "Hardcover comparison viewport")
        for _ in 0..<10 {
            surface(project: project, link: nil, secondary: false, store: store, handle: handle)
                .updateInteractionView(view, coordinator: coordinator)
            XCTAssertTrue(view.scene === scene)
            XCTAssertTrue(handle.view === view)
            let before = coordinator.cameraState
            link.send(from: secondary, state: BookPreviewCameraState(yaw: 1, pitch: 0.3, distance: 10))
            XCTAssertEqual(coordinator.cameraState, before)
            initial.updateInteractionView(view, coordinator: coordinator)
            XCTAssertTrue(view.scene === scene)
        }
        BookPreviewSceneView.dismantleNSView(view, coordinator: coordinator)
        let before = coordinator.cameraState
        link.send(from: secondary, state: BookPreviewCameraState(yaw: 2, pitch: 0.3, distance: 10))
        XCTAssertEqual(coordinator.cameraState, before)
    }

    func testRepeatedInspectionDoesNotAccumulateOverlaysAndRestoresOriginalHiddenState() {
        let scene = SCNScene()
        let node = SCNNode(geometry: SCNBox(width: 1, height: 2, length: 0.1, chamferRadius: 0))
        node.name = "book-shell.front-cover"; node.isHidden = true; node.opacity = 0.7
        let originalOpacity = node.opacity
        scene.rootNode.addChildNode(node)
        let issue = BookPrintDanger(id: "test", severity: .review, component: .front, message: "test", correction: "test")
        var state = BookInspectionState(); state.danger = true; state.anatomy = true
        state.explosion = 1; state.transparency = 0.8
        for _ in 0..<30 {
            BookInspectionScene.apply(state, to: scene, issues: [issue])
            XCTAssertEqual(node.childNodes.filter { $0.name == "diagnostic.inspection" }.count, 1)
        }
        BookInspectionScene.apply(BookInspectionState(), to: scene, issues: [])
        XCTAssertEqual(node.position.z, 0)
        XCTAssertEqual(node.opacity, originalOpacity)
        XCTAssertTrue(node.isHidden)
        XCTAssertTrue(node.childNodes.isEmpty)
    }

    func testUnregisterReleasesCallbackResourcesWhileOwnerIsStillAlive() {
        let link = BookInspectionCameraLink(), owner = NSObject()
        weak var released: NSObject?
        do {
            let resource = NSObject()
            released = resource
            link.register(owner) { [resource] _, _ in _ = resource.description }
        }
        XCTAssertNotNil(released)
        link.unregister(owner)
        XCTAssertNil(released)
        withExtendedLifetime(owner) {}
    }
}
