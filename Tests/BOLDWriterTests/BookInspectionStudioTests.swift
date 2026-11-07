import XCTest
import SceneKit
@testable import BOLDWriter

@MainActor
final class BookInspectionStudioTests: XCTestCase {
    func testAnatomyRestoresExactTransformsVisibilityAndSharedMaterials() throws {
        let scene = SCNScene()
        let cover = SCNNode(geometry: SCNBox(width: 2, height: 3, length: 0.1, chamferRadius: 0))
        cover.name = "book-shell.front-cover"; cover.position = SCNVector3(1, 2, 3)
        scene.rootNode.addChildNode(cover)
        let lining = SCNNode(geometry: SCNPlane(width: 2, height: 3))
        cover.addChildNode(lining)
        let geometry = try XCTUnwrap(cover.geometry)
        let material = try XCTUnwrap(geometry.firstMaterial)
        for fraction in stride(from: 0.0, through: 1.0, by: 0.05) {
            var state = BookInspectionState(); state.anatomy = true
            state.explosion = fraction; state.transparency = 0.6
            BookInspectionScene.apply(state, to: scene, issues: [])
            XCTAssertEqual(cover.position.z, 3 + CGFloat(fraction * 0.65), accuracy: 0.000001)
            XCTAssertEqual(lining.position.z, 0)
            XCTAssertTrue(cover.geometry === geometry)
            XCTAssertTrue(cover.geometry?.firstMaterial === material)
        }
        BookInspectionScene.apply(BookInspectionState(), to: scene, issues: [])
        XCTAssertEqual(cover.position.z, 3); XCTAssertEqual(cover.opacity, 1)
        XCTAssertFalse(cover.isHidden)
    }

    func testDangerOverlaysDoNotModifyMaterialsAndSuspendForExport() throws {
        let scene = SCNScene()
        let cover = SCNNode(geometry: SCNBox(width: 1, height: 2, length: 0.1, chamferRadius: 0))
        cover.name = "book-shell.front-cover"; scene.rootNode.addChildNode(cover)
        let material = try XCTUnwrap(cover.geometry?.firstMaterial)
        let issue = BookPrintDanger(id: "low-dpi", severity: .likely, component: .front, message: "100 dpi", correction: "Use 300 dpi")
        var state = BookInspectionState(); state.danger = true; state.anatomy = true; state.explosion = 1
        BookInspectionScene.apply(state, to: scene, issues: [issue])
        XCTAssertNotNil(cover.childNode(withName: "diagnostic.inspection", recursively: false))
        XCTAssertTrue(material === cover.geometry?.firstMaterial)
        let restore = BookInspectionScene.suspend(scene)
        XCTAssertEqual(cover.position.z, 0)
        XCTAssertNil(cover.childNode(withName: "diagnostic.inspection", recursively: false))
        restore()
        XCTAssertEqual(cover.position.z, 0.65, accuracy: 0.000001)
        XCTAssertNotNil(cover.childNode(withName: "diagnostic.inspection", recursively: false))
    }

    func testCameraLinkSynchronizesAndCanBeDisabledWithoutRetainingViewport() {
        let link = BookInspectionCameraLink()
        let first = NSObject()
        var second: NSObject? = NSObject()
        weak var weakSecond = second
        var received: [BookSavedCamera] = []
        link.register(second!) { state, _ in received.append(state.saved) }
        var state = BookPreviewCameraState(yaw: 0, pitch: 0.5, distance: 5)
        state.orbit(deltaX: 100, deltaY: 30)
        link.send(from: first, state: state)
        XCTAssertEqual(received, [state.saved])
        link.enabled = false; link.send(from: first, state: state)
        XCTAssertEqual(received.count, 1)
        second = nil; XCTAssertNil(weakSecond)
        link.enabled = true; link.send(from: first, state: state)
        XCTAssertEqual(received.count, 1)
    }

    func testDangerUsesCalculatedSpineNotDifferenceAsExpectedMeasurement() {
        var project = CoverProject(type: .printFullWrap, width: 13, height: 9)
        project.spineWidth = 1; project.spineCaliperInches = 0.002
        let issues = BookPrintDanger.inspect(project: project, binding: .softcover, pageCount: 400)
        XCTAssertTrue(issues.contains { $0.message.contains("0.80000 in; artwork spine 1.00000") })
    }

    func testIsolationRetainsParentOfSelectedPageAndRestoresHiddenNodes() {
        let scene = SCNScene()
        let stack = SCNNode(); stack.name = "book.left-leaves"; scene.rootNode.addChildNode(stack)
        let page = SCNNode(); page.name = "book.left-active-page"; stack.addChildNode(page)
        var state = BookInspectionState(); state.anatomy = true; state.isolated = .leftPage
        BookInspectionScene.apply(state, to: scene, issues: [])
        XCTAssertFalse(stack.isHidden); XCTAssertFalse(page.isHidden)
        state.hidden = [.leftPage]; BookInspectionScene.apply(state, to: scene, issues: [])
        XCTAssertTrue(page.isHidden)
        BookInspectionScene.apply(BookInspectionState(), to: scene, issues: [])
        XCTAssertFalse(page.isHidden)
    }
}

@MainActor
final class BookInspectionPhysicalSceneTests: XCTestCase {
    private func fixture(_ binding: BookBinding) -> CoverProject {
        var p = CoverProject(type: .printFullWrap)
        p.productionBinding = binding; p.spinePageCount = 535; p.dpi = 72
        p.trimHeight = 11
        if binding == .hardcover {
            p.trimWidth = 8.25; p.backWidth = 8.25; p.spineWidth = 1.394
            p.canvasWidth = 19.469; p.canvasHeight = 12.417; p.bleed = 0
            p.kdpHardcoverLayout = KDPHardcoverLayout(canvasWidth: 19.469, canvasHeight: 12.417, trimWidth: 8.25, trimHeight: 11, spineWidth: 1.394, pageCount: 535)
        } else {
            p.trimWidth = 8.5; p.backWidth = 8.5; p.spineWidth = 1.205
            p.canvasWidth = 18.455; p.canvasHeight = 11.25; p.bleed = 0.125
        }
        let g = CoverWrapGeometry(project: p)
        for (index, panel) in [g.backTrim, g.spineTrim, g.frontTrim].enumerated() {
            for corner in 0..<4 {
                var layer = CoverLayer(kind: .shape, name: "\(index)-\(corner)", frame: CoverRect(x: panel.x + Double(corner % 2) * panel.width / 2, y: panel.y + Double(corner / 2) * panel.height / 2, width: panel.width / 2, height: panel.height / 2))
                layer.fillHex = ["#FF3333", "#33DD33", "#3333FF", "#FFFF33"][(index + corner) % 4]
                layer.strokeWidth = 0; p.layers.append(layer)
            }
        }
        return p
    }

    func testFourWayRealScenesReassembleWithoutChangingSourceOrGeometry() throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        for source in BookBinding.allCases {
            let project = fixture(source)
            let original = try encoder.encode(project)
            for target in BookBinding.allCases {
                for angle in [0.0, 90, 180] {
                    for spread in [0, 133, 267] {
                        let scene = BookPreviewScene.make(project: project, workingLayers: false, open: angle > 0, angle: angle, leftPage: spread == 0 ? nil : spread * 2, rightPage: spread * 2 + 1, pageCount: 535, spreadIndex: spread, leftTexture: nil, rightTexture: nil, margins: false, thumbMode: .off, leftPageSettings: PageSettings(), rightPageSettings: PageSettings(), preset: .reading, revisionID: UUID(), binding: target)
                        var baseline: [(SCNNode, SCNMatrix4, CGFloat, Bool, SCNGeometry?)] = []
                        scene.rootNode.enumerateChildNodes { node, _ in
                            baseline.append((node, node.transform, node.opacity, node.isHidden, node.geometry))
                        }
                        var state = BookInspectionState(); state.anatomy = true; state.explosion = 0.75; state.transparency = 0.5; state.danger = true
                        let issues = BookPrintDanger.inspect(project: project, binding: target, pageCount: 535)
                        BookInspectionScene.apply(state, to: scene, issues: issues)
                        BookInspectionScene.apply(BookInspectionState(), to: scene, issues: [])
                        for (node, matrix, opacity, hidden, geometry) in baseline {
                            XCTAssertTrue(SCNMatrix4EqualToMatrix4(node.transform, matrix))
                            XCTAssertEqual(node.opacity, opacity); XCTAssertEqual(node.isHidden, hidden)
                            XCTAssertTrue(node.geometry === geometry)
                        }
                        XCTAssertEqual(try encoder.encode(project), original)
                        if let directory = ProcessInfo.processInfo.environment["BOLD_INSPECTION_PROOF_DIR"] {
                            try render(scene, project: project, source: source, target: target, angle: angle, spread: spread, directory: directory)
                        }
                    }
                }
            }
        }
    }

    private func render(_ scene: SCNScene, project: CoverProject, source: BookBinding, target: BookBinding, angle: Double, spread: Int, directory: String) throws {
        let folder = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = scene
        let camera = try XCTUnwrap(scene.rootNode.childNode(withName: "preview-camera", recursively: true))
        renderer.pointOfView = camera
        let view = BookPreviewInteractionView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        view.scene = scene; view.cameraNode = camera
        let poses: [(Double, Double)] = [(0,0.3),(.pi/2,0.3),(.pi,0.3),(3 * .pi/2,0.3),(0,1.5),(0,-1.5),(.pi/4,0.7),(-.pi/4,-0.7)]
        for (index, pose) in (poses + [(0.6, 0.6), (0.6, 0.6), (0.6, 0.6)]).enumerated() {
            if index >= poses.count {
                var inspection = BookInspectionState()
                inspection.danger = index == 8
                inspection.anatomy = index == 9
                inspection.explosion = 0.75; inspection.transparency = 0.3
                BookInspectionScene.apply(inspection, to: scene, issues: BookPrintDanger.inspect(project: project, binding: target, pageCount: 535))
            }
            var state = BookPreviewCameraMath.state(project: project, open: angle > 0, preset: .reading, focus: .automatic)
            state = BookPreviewCameraMath.fitBook(state, in: scene, presentation: BookStudioPresentation(), viewportAspect: 4.0/3)
            state.yaw = pose.0; state.pitch = pose.1
            view.setCamera(state); view.configureCamera(state, projection: .perspective)
            SCNTransaction.flush()
            let image = renderer.snapshot(atTime: 0, with: CGSize(width: 640, height: 480), antialiasingMode: .multisampling4X)
            let bitmap = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: folder.appendingPathComponent("\(source)-on-\(target)-\(Int(angle))-\(spread)-\(index).png"))
        }
    }
}
