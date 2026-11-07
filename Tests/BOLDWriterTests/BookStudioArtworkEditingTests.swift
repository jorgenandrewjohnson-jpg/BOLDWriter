import AppKit
import SceneKit
import XCTest
@testable import BOLDWriter

@MainActor
final class BookStudioArtworkEditingTests: XCTestCase {
    private func project() -> CoverProject {
        var p = CoverProject(type: .printFullWrap, width: 13.25, height: 9.25)
        p.trimWidth = 6; p.backWidth = 6; p.trimHeight = 9
        p.spineWidth = 1; p.bleed = 0.125
        for (name, x, color) in [("BACK", 0.02, "#183954"), ("FRONT", 0.55, "#BC6031")] {
            var fill = CoverLayer(kind: .shape, name: name + " color",
                                  frame: CoverRect(x: x, y: 0, width: 0.45, height: 1))
            fill.fillHex = color; p.layers.append(fill)
            var title = CoverLayer(kind: .text, name: name + " title",
                                   frame: CoverRect(x: x + 0.025, y: 0.2, width: 0.4, height: 0.45))
            title.text = name + "\nTHE BOOK\nA printed proof"; title.fontSize = 30
            title.colorHex = "#FFFFFF"; p.layers.append(title)
        }
        return p
    }

    func testStudioMenuArtworkUndoRedoPreservesOtherProjects() throws {
        let document = BOLDWriterDocument()
        let original = project()
        var other = project(); other.id = UUID()
        document.metadata.coverProjects = [original, other]
        let undo = UndoManager(); undo.groupsByEvent = false
        let menuActions = StudioUndoActions(manager: undo)
        var edited = original.layers[1]
        edited.text = "Changed in 3D"; edited.rotation = 12
        edited.frame.x += 0.025
        undo.beginUndoGrouping()
        try BookStudioArtworkEditing.replace(edited, projectID: original.id, in: document, undoManager: undo)
        undo.endUndoGrouping()
        XCTAssertEqual(document.metadata.coverProjects?[0].layers[1], edited)
        XCTAssertEqual(document.metadata.coverProjects?[1], other)
        let encoded = try JSONEncoder().encode(document.metadata.coverProjects)
        let reloaded = try JSONDecoder().decode([CoverProject].self, from: encoded)
        XCTAssertEqual(reloaded[0].layers[1], edited)
        document.metadata.coverProjects?[1].name = "Concurrent other project edit"
        menuActions.undo()
        XCTAssertEqual(document.metadata.coverProjects?[0].layers[1], original.layers[1])
        XCTAssertEqual(document.metadata.coverProjects?[1].name, "Concurrent other project edit")
        menuActions.redo()
        XCTAssertEqual(document.metadata.coverProjects?[0].layers[1], edited)
    }

    func testStudioArtworkRoundTripsThroughNativeDocumentAndProductionTextures() throws {
        let document = BOLDWriterDocument()
        let original = project()
        document.metadata.coverProjects = [original]
        document.metadata.activeCoverProjectID = original.id
        let before = PhysicalBookCoverTextures(project: original, workingLayers: false, previewDPI: 36)
        var edited = original.layers[3]
        edited.text = "PRINTED FROM 3D"
        edited.rotation = 8
        edited.frame.y += 0.08
        try BookStudioArtworkEditing.replace(edited, projectID: original.id, in: document, undoManager: nil)
        let shared = try XCTUnwrap(document.metadata.coverProjects?.first)
        let package = try BOLDWriterDocument.packageWrapper(text: document.text, metadata: document.metadata)
        let reopened = try BOLDWriterDocument(fileWrapper: package, contentType: .boldWriterDocument)
        let restored = try XCTUnwrap(reopened.metadata.coverProjects?.first)
        XCTAssertEqual(restored, shared)
        XCTAssertEqual(reopened.metadata.activeCoverProjectID, original.id)
        let live = PhysicalBookCoverTextures(project: shared, workingLayers: false, previewDPI: 36)
        let printed = PhysicalBookCoverTextures(project: restored, workingLayers: false, previewDPI: 36)
        XCTAssertNotEqual(try XCTUnwrap(before.front?.tiffRepresentation), try XCTUnwrap(live.front?.tiffRepresentation))
        XCTAssertEqual(try XCTUnwrap(live.front?.tiffRepresentation), try XCTUnwrap(printed.front?.tiffRepresentation))
        XCTAssertEqual(try XCTUnwrap(before.back?.tiffRepresentation), try XCTUnwrap(printed.back?.tiffRepresentation))
    }

    func testInvalidDimensionsDoNotCorruptSharedCover() throws {
        let document = BOLDWriterDocument(); let original = project()
        document.metadata.coverProjects = [original]
        var edited = original.layers[0]; edited.frame.width = -1
        XCTAssertThrowsError(try BookStudioArtworkEditing.replace(edited, projectID: original.id,
                                                                  in: document, undoManager: nil))
        XCTAssertEqual(document.metadata.coverProjects, [original])
    }

    func testLiveViewportSelectsNewCameraAfterSceneRebuild() {
        let view = BookPreviewInteractionView()
        let first = SCNScene(), second = SCNScene()
        let oldCamera = SCNNode(), newCamera = SCNNode()
        oldCamera.camera = SCNCamera(); newCamera.camera = SCNCamera()
        first.rootNode.addChildNode(oldCamera); second.rootNode.addChildNode(newCamera)
        view.scene = first; view.cameraNode = oldCamera
        XCTAssertTrue(view.pointOfView === oldCamera)
        view.scene = second; view.cameraNode = newCamera
        XCTAssertTrue(view.pointOfView === newCamera)
        XCTAssertTrue(view.pointOfView?.parent === second.rootNode)
        BookStudioCameraGuideScene.apply(to: second,
            state: BookPreviewCameraState(yaw: 0, pitch: 0, distance: 5), visible: true, selected: false)
        let body = second.rootNode.childNode(withName: BookStudioCameraGuideScene.cameraName, recursively: true)!
        let frustum = second.rootNode.childNode(withName: BookStudioCameraGuideScene.frustumName, recursively: true)!
        XCTAssertEqual(newCamera.camera!.categoryBitMask & body.categoryBitMask, 0)
        XCTAssertEqual(newCamera.camera!.categoryBitMask & frustum.categoryBitMask, 0)
    }

    func testUnderlyingLeavesNeverCrossPrintedPage() throws {
        for side in [ThumbSide.left, .right] {
            let surface = BookPreviewScene.curvedPaperGeometry(width: 4.2, height: 6.3,
                insideEdge: PhysicalBookGeometry.insideEdge(side: side), valleyDepth: 0.06,
                foreEdgeCurl: 0.02, shoulderLift: 0.08)
            let active = SCNNode(geometry: surface)
            BookPreviewScene.addReadingVisibleLeafLayers(to: active, side: side, width: 4.2,
                height: 6.3, valleyDepth: 0.06, shoulderLift: 0.08, foreEdgeCurl: 0.02, binding: .softcover)
            let expected = try XCTUnwrap(surface.sources(for: .vertex).first)
            for leaf in active.childNodes {
                let actual = try XCTUnwrap(leaf.geometry?.sources(for: .vertex).first)
                XCTAssertEqual(actual.data, expected.data, "Underlying leaves follow the same gutter and curvature.")
                XCTAssertLessThan(leaf.position.z, 0)
            }
        }
    }

    func testRenderRealClosedLiveViewport() throws {
        guard let input = ProcessInfo.processInfo.environment["BOLD_STUDIO_REAL_DOC"],
              let output = ProcessInfo.processInfo.environment["BOLD_STUDIO_PROOF_DIR"] else {
            throw XCTSkip("Opt-in real-document live viewport proof.")
        }
        let document = try BOLDWriterDocument(fileWrapper: FileWrapper(url: URL(fileURLWithPath: input)), contentType: .boldWriterDocument)
        let project = try XCTUnwrap(document.metadata.coverProjects?.first)
        try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
        var presentation = BookStudioPresentation()
        presentation.open = false
        presentation.binding = project.productionBinding ?? .softcover
        for i in 0..<12 {
            let scene = BookPreviewScene.make(project: project, workingLayers: false, open: false, angle: 180,
                leftPage: nil, rightPage: 1, pageCount: 354, spreadIndex: 0,
                leftTexture: nil, rightTexture: nil, margins: false, thumbMode: .off,
                leftPageSettings: document.metadata.page, rightPageSettings: document.metadata.page,
                preset: .perspective, revisionID: document.revisionID, binding: presentation.binding, presentation: presentation)
            BookStudioTransformScene.apply(to: scene, presentation: presentation)
            BookStudioSceneStyling.apply(to: scene, presentation: presentation)
            let view = BookPreviewInteractionView(frame: NSRect(x: 0, y: 0, width: 1200, height: 1000))
            view.scene = scene
            view.cameraNode = scene.rootNode.childNode(withName: "preview-camera", recursively: true)
            var state = BookPreviewCameraMath.state(project: project, open: false, preset: .perspective, focus: .automatic)
            state.yaw = Double(i) * .pi / 6
            state.pitch = 0.3
            view.setCamera(state)
            view.configureCamera(state, projection: .perspective)
            let renderer = SCNRenderer(device: nil, options: nil)
            renderer.scene = scene; renderer.pointOfView = view.cameraNode
            let image = renderer.snapshot(atTime: 0, with: CGSize(width: 1200, height: 1000), antialiasingMode: .multisampling4X)
            let rep = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
            try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: output).appendingPathComponent("live-orbit-\(i).png"))
        }
    }

    /// Optional reproducible visual proof, using synthetic content only.
    func testRenderBookPostures() throws {
        guard let output = ProcessInfo.processInfo.environment["BOLD_STUDIO_PROOF_DIR"] else {
            throw XCTSkip("Set BOLD_STUDIO_PROOF_DIR to render synthetic book postures.")
        }
        try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
        let project = project()
        var metadata = DocumentMetadata()
        metadata.coverProjects = [project]; metadata.activeCoverProjectID = project.id
        let wrapper = try BOLDWriterDocument.packageWrapper(
            text: NSAttributedString(string: "A synthetic book for live artwork editing verification.\n",
                                     attributes: [.font: NSFont.systemFont(ofSize: 18)]), metadata: metadata)
        try wrapper.write(to: URL(fileURLWithPath: output).appendingPathComponent("Studio-Proof.boldwriter"),
                          options: .atomic, originalContentsURL: nil)
        let page = NSImage(size: NSSize(width: 600, height: 900), flipped: false) { rect in
            NSColor.white.setFill(); rect.fill()
            ("A REAL PAGE\n\nChapter One\n\nThe manuscript belongs inside the book.\n" as NSString).draw(
                in: NSRect(x: 65, y: 450, width: 470, height: 340),
                withAttributes: [.font: NSFont.systemFont(ofSize: 25), .foregroundColor: NSColor.black])
            return true
        }
        for (label, open, angle, preset) in [
            ("closed", false, 0.0, BookViewPreset.perspective),
            ("partial", true, 100.0, .front),
            ("reading", true, 160.0, .reading),
            ("flat", true, 180.0, .reading)
        ] {
            var presentation = BookStudioPresentation.restingOpenPreviewDefault
            presentation.cameraPreset = preset; presentation.open = open; presentation.openAngle = angle
            let scene = BookPreviewScene.make(project: project, workingLayers: false, open: open, angle: angle,
                leftPage: 200, rightPage: 201, pageCount: 400, spreadIndex: 100,
                leftTexture: page, rightTexture: page, margins: false, thumbMode: .off,
                leftPageSettings: PageSettings(), rightPageSettings: PageSettings(), preset: preset,
                revisionID: UUID(), binding: .softcover, presentation: presentation)
            let view = BookPreviewInteractionView(frame: NSRect(x: 0, y: 0, width: 1400, height: 1000))
            view.scene = scene
            view.cameraNode = scene.rootNode.childNode(withName: "preview-camera", recursively: true)
            view.setCamera(BookPreviewCameraMath.state(project: project, open: open, preset: preset, focus: .automatic))
            let handle = BookStudioViewportHandle(); handle.view = view
            let image = try XCTUnwrap(handle.image(size: CGSize(width: 1400, height: 1000)))
            let rep = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
            let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: output).appendingPathComponent(label + ".png"))
        }
    }
}
