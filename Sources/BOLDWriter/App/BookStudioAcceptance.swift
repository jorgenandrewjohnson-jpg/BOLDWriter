#if !APP_STORE
import AppKit
import CryptoKit
import Darwin
import SceneKit
import SwiftUI

/// Opt-in proof-only acceptance of the production native viewport, including its
/// coordinator/update path and mouse handlers. No global event injection or
/// active user window control; outputs must be new and inputs remain read-only.
@MainActor
enum BookStudioAcceptance {
    // An explicit acceptance preset request represents a real
    // camera-menu command, including selection of the current preset.
    // The camera-reset generation must advance for same-value
    // selections or the coordinator will preserve its manual orbit.
    static func selectCameraPreset(
        _ preset: BookViewPreset,
        studio: inout BookStudioPresentation,
        resetGeneration: inout Int
    ) {
        if !BookStudioCameraPresetCommand.reselect(
            preset,
            presentation: &studio,
            resetGeneration: &resetGeneration
        ) {
            studio.cameraPreset = preset
        }
    }

    struct Step: Codable {
        var name: String
        var preset: String?
        var binding: BookBinding?
        var open: Bool?
        var angle: Double?
        var spread: Int?
        var spreadFraction: Double?
        var drag: [Double]?
        var zoom: Double?
        var reset: Bool?
        var commands: [[String]]?
        var leaveViewport: Bool?
        var capture: Bool?
        var turn: Int?
        var ground: BookGroundPreset?
        var paper: BookPaperTone?
    }
    struct Request: Codable { var input: String; var outputDirectory: String; var steps: [Step] }
    struct Frame: Codable {
        var name: String; var sha256: String; var camera: BookSavedCamera
        var open: Bool; var angle: Double; var spread: Int; var binding: BookBinding
        var nodes: [String: [Double]]; var textureBytes: Int
        var pageEdges: [String: [Double]]
        var inspection: BookSceneInspection
        var pageCount: Int
        var leftPage: Int?
        var rightPage: Int?
        var residentBytes: UInt64
        var livePreviousScenes: Int
        var livePreviousTextures: Int
        var livePreviousImages: Int
        var livePreviousViews: Int
        var textureMilliseconds: Double
        var sceneConstructionMilliseconds: Double
        var navigationMilliseconds: Double
        var updateMilliseconds: Double
        var snapshotMilliseconds: Double
        var panelHashes: [String: String]
        var turnFrames: [String: [Double]]
        var turnSnapshotMilliseconds: [String: Double]
    }
    private final class Controls {
        var zoomScale = 1.0
        var model = BookModelTransform.identity
        var mode = BookTransformMode.navigate
        var space = BookTransformSpace.local
        var lights: [BookStudioLight] = []
        var lightID: UUID?
        var camera: BookSavedCamera?
        var selection: BookSceneComponent?
        func binding<T>(_ key: ReferenceWritableKeyPath<Controls, T>) -> Binding<T> {
            Binding(get: { self[keyPath: key] }, set: { self[keyPath: key] = $0 })
        }
    }
    private final class WeakResource<T: AnyObject> {
        weak var value: T?
        init(_ value: T) { self.value = value }
    }
    private static func residentBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { p in
            p.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.resident_size) : 0
    }
    static func run(requestURL: URL) throws {
        let request = try JSONDecoder().decode(Request.self, from: Data(contentsOf: requestURL))
        guard request.steps.count > 0, request.steps.count <= 500,
              request.input.hasPrefix("/"), request.outputDirectory.hasPrefix("/") else {
            throw WriterError.message("Acceptance requires absolute proof paths and 1...500 steps.")
        }
        let output = URL(fileURLWithPath: request.outputDirectory).resolvingSymlinksInPath().standardizedFileURL
        guard !FileManager.default.fileExists(atPath: output.path) else {
            throw WriterError.message("Acceptance output must be a new directory.")
        }
        let session = try BookAutomationSession(input: URL(fileURLWithPath: request.input))
        guard output != session.input, !output.path.hasPrefix(session.input.path + "/") else {
            throw WriterError.message("Acceptance evidence must be outside the input proof package.")
        }
        guard var project = session.document.metadata.coverProjects?.first(where: { $0.id == session.selectedProjectID }),
              project.type == .printFullWrap else { throw WriterError.message("Acceptance requires a full-wrap proof project.") }
        let (pdf, _, pages) = try session.pagination()
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let controls = Controls(), handle = BookStudioViewportHandle()
        var coordinator = BookPreviewSceneView.Coordinator()
        var view: BookPreviewInteractionView?
        var studio = session.document.metadata.bookStudioPresentation ?? BookStudioPresentation()
        studio.modelTransform = .identity; studio.exploded = false
        studio.cameraEditorVisible = false; studio.lightGuidesVisible = false
        var resetGeneration = 0, records: [Frame] = []
        let revision = UUID()
        var scenes: [WeakResource<SCNScene>] = []
        var texturesSeen: [WeakResource<PhysicalBookCoverTextures>] = []
        var imagesSeen: [WeakResource<NSImage>] = []
        var viewsSeen: [WeakResource<BookPreviewInteractionView>] = []
        var currentImageIDs: Set<ObjectIdentifier> = []
        var turns = BookPageTurnState()
        // Page image identity remains stable between poses, like the GUI cache.
        var pageImages: [Int: NSImage] = [:]
        func texture(_ n: Int?) -> NSImage? {
            guard let n else { return nil }
            if let cached = pageImages[n] { return cached }
            guard let page = pdf.page(at: n - 1),
                  let image = PhysicalBookPreview.renderManuscriptPage(page, maximumPixelSize: 1600) else { return nil }
            pageImages[n] = image
            if pageImages.count > 6 { pageImages = pageImages.filter { abs($0.key - n) <= 2 } }
            return image
        }
        for step in request.steps {
            try autoreleasepool {
                guard !step.name.isEmpty, step.name.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else {
                    throw WriterError.message("Use a simple unique acceptance step name.")
                }
                guard !records.contains(where: { $0.name == step.name }) else { throw WriterError.message("Duplicate step name.") }
                if step.leaveViewport == true {
                    // Mirror the production NSView dismantle path. Clearing only
                    // `scene` leaves SceneKit callbacks, camera state and
                    // viewport closures alive on the discarded view until ARC
                    // retirement, which distorts repeated open/close memory
                    // measurements and does not model a real workspace exit.
                    handle.releasePreviewResources()
                    view = nil
                    coordinator = BookPreviewSceneView.Coordinator()
                }
                for command in step.commands ?? [] {
                    let action = try BOLDTerminalCommandParser.parse(command)
                    guard BookAutomationSession.supported.contains(action.kind),
                          [.coverUpdateLayer, .coverEdit, .applicationUndo, .applicationRedo].contains(action.kind) else {
                        throw WriterError.message("Viewport proof edits must use supported cover/Undo/Redo commands.")
                    }
                    _ = try session.execute(action)
                }
                guard let updated = session.document.metadata.coverProjects?.first(where: { $0.id == project.id }) else {
                    throw WriterError.message("Proof cover disappeared.")
                }
                project = updated
                if let raw = step.preset {
                    guard let preset = BookViewPreset.allCases.first(where: { $0.rawValue == raw || String(describing: $0) == raw }) else {
                        throw WriterError.message("Unknown acceptance camera preset.")
                    }
                    selectCameraPreset(
                        preset,
                        studio: &studio,
                        resetGeneration: &resetGeneration
                    )
                    controls.camera = nil
                }
                if let binding = step.binding { studio.binding = binding }
                if let ground = step.ground { studio.ground = ground }
                if let paper = step.paper { studio.paper = paper }
                if let open = step.open { studio.open = open }
                if let angle = step.angle {
                    guard angle.isFinite, (0...180).contains(angle) else { throw WriterError.message("Invalid opening angle.") }
                    studio.openAngle = angle
                }
                if let fraction = step.spreadFraction {
                    guard fraction.isFinite, (0...1).contains(fraction) else { throw WriterError.message("Invalid page-state fraction.") }
                    studio.spreadIndex = Int((Double(pdf.pageCount/2)*fraction).rounded())
                }
                if let spread = step.spread {
                    guard (0...pdf.pageCount / 2).contains(spread) else { throw WriterError.message("Invalid manuscript spread.") }
                    studio.spreadIndex = spread
                }
                if step.reset == true { controls.camera = nil; resetGeneration += 1 }
                studio.savedCamera = controls.camera
                func page(_ n: Int?) -> PageSettings {
                    guard let n, pages.indices.contains(n - 1) else { return session.document.metadata.page }
                    return pages[n - 1]
                }
                var transition: BookPageTurnTransition?
                if let delta = step.turn {
                    guard [-1,1].contains(delta) else { throw WriterError.message("Turn must be -1 or 1.") }
                    turns.jump(to: studio.spreadIndex, maximumSpread: pdf.pageCount / 2)
                    transition = turns.begin(to: studio.spreadIndex + delta, maximumSpread: pdf.pageCount / 2)
                    studio.spreadIndex = turns.spreadIndex
                    studio.open = true; studio.openAngle = 180
                }
                let faces = transition.map { PhysicalBookGeometry.pageTurnFaces(direction: $0.direction,
                    fromSpread: $0.fromSpread, toSpread: $0.toSpread, pageCount: pdf.pageCount) }
                let visible = PhysicalBookGeometry.spread(at: studio.spreadIndex, pageCount: pdf.pageCount)
                let displayed = PhysicalBookGeometry.spread(at: transition?.fromSpread ?? studio.spreadIndex, pageCount: pdf.pageCount)
                let textureStart = ProcessInfo.processInfo.systemUptime
                let textures = BookPreviewScene.coverTextures(project:project,workingLayers:false,revisionID:revision)
                let textureMilliseconds = (ProcessInfo.processInfo.systemUptime-textureStart)*1000
                let updateStart = ProcessInfo.processInfo.systemUptime
                @MainActor func makeSurface(displayed: BookSpread, transition: BookPageTurnTransition?) -> BookPreviewSceneView {
                    BookPreviewSceneView(project: project, workingLayers: false, binding: studio.binding,
                    isOpen: studio.open, openAngle: studio.openAngle, pageCount: pdf.pageCount, spreadIndex: studio.spreadIndex,
                    turnTransition: transition, turnTexture: texture(faces?.front), turnReverseTexture: texture(faces?.reverse), turnGeneration: records.count + 1,
                    leftPage: displayed.leftPage, rightPage: displayed.rightPage, leftTexture: texture(displayed.leftPage), rightTexture: texture(displayed.rightPage),
                    showMargins: false, thumbMode: .off, leftPageSettings: page(displayed.leftPage), rightPageSettings: page(displayed.rightPage),
                    preset: studio.cameraPreset, revisionID: revision, resetGeneration: resetGeneration,
                    focusGeneration: 0, focus: .automatic, zoomAction: .fit, zoomGeneration: 0,
                    zoomDisplayScale: controls.binding(\.zoomScale), presentation: studio,
                    modelTransform: controls.binding(\.model), transformMode: controls.binding(\.mode), transformSpace: controls.binding(\.space),
                    customLights: controls.binding(\.lights), selectedCustomLightID: controls.binding(\.lightID),
                    savedCamera: controls.binding(\.camera), selection: controls.binding(\.selection), viewportHandle: handle)
                }
                let surface = makeSurface(displayed: displayed, transition: transition)
                // Capture the settled pose, not the 350ms camera transition.
                SCNTransaction.begin(); SCNTransaction.disableActions = true
                var sceneConstructionMilliseconds = 0.0
                if let view { surface.updateInteractionView(view, coordinator: coordinator) }
                else {
                    let constructionStart = ProcessInfo.processInfo.systemUptime
                    view = surface.makeInteractionView(coordinator: coordinator)
                    sceneConstructionMilliseconds = (ProcessInfo.processInfo.systemUptime - constructionStart) * 1000
                    view?.frame = NSRect(x: 0, y: 0, width: 1600, height: 1200)
                }
                SCNTransaction.commit(); SCNTransaction.flush()
                let updateMilliseconds = (ProcessInfo.processInfo.systemUptime - updateStart) * 1000
                guard let view else { throw WriterError.message("Native viewport was not created.") }
                let navigationStart = ProcessInfo.processInfo.systemUptime
                if let drag = step.drag {
                    guard drag.count == 2, drag.allSatisfy({ $0.isFinite && abs($0) <= 2000 }) else { throw WriterError.message("Invalid viewport drag.") }
                    let start = CGPoint(x: 800, y: 600), end = CGPoint(x: 800 + drag[0], y: 600 + drag[1])
                    for (type, point) in [(NSEvent.EventType.leftMouseDown, start), (.leftMouseDragged, end)] {
                        guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                            windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1) else { throw WriterError.message("Mouse acceptance event failed.") }
                        if type == .leftMouseDown { view.mouseDown(with: event) } else { view.mouseDragged(with: event) }
                    }
                    view.onNavigationEnded?(); view.setNavigating(false)
                }
                if let zoom = step.zoom {
                    guard zoom.isFinite, (0.1...10).contains(zoom) else { throw WriterError.message("Invalid zoom factor.") }
                    view.onZoom?(zoom); view.onNavigationEnded?(); view.setNavigating(false)
                }
                let navigationMilliseconds = (ProcessInfo.processInfo.systemUptime-navigationStart)*1000
                var turnFrames: [String: [Double]] = [:]
                var turnSnapshotMilliseconds: [String: Double] = [:]
                if transition != nil, let scene = view.scene {
                    // One native renderer advances the production SceneKit
                    // actions, including its custom mass-transfer callback.
                    let renderer = SCNRenderer(device: nil, options: nil)
                    renderer.scene = scene; renderer.pointOfView = view.cameraNode
                    for t in [0.0,0.12,0.24,0.36,0.48,0.60] {
                        let turnSnapshotStart = ProcessInfo.processInfo.systemUptime
                        let turnImage = renderer.snapshot(atTime: t, with: CGSize(width:800,height:600), antialiasingMode:.none)
                        turnSnapshotMilliseconds[String(t)] = (ProcessInfo.processInfo.systemUptime - turnSnapshotStart) * 1000
                        if step.capture != false, let tiff = turnImage.tiffRepresentation,
                           let bitmap = NSBitmapImageRep(data:tiff), let bytes = bitmap.representation(using:.png,properties:[:]) {
                            try bytes.write(to:output.appendingPathComponent(step.name + "-motion-" + String(t) + ".png"),options:.atomic)
                        }
                        let pivot = scene.rootNode.childNode(withName: "book.turning-page-pivot", recursively: true)
                        var values = pivot.map { [Double($0.presentation.eulerAngles.y), Double($0.presentation.position.z)] } ?? []
                        if !values.isEmpty {
                            let measured = BookSceneInspection(scene:scene)
                            values += [measured.supports["left"]?.depth ?? 0, measured.supports["right"]?.depth ?? 0,
                                measured.maximumCoverPenetration] + (measured.turningGutter ?? []) + [measured.turnUsesPrintedSurfaces == true ? 1:0]
                        }
                        turnFrames[String(t)] = values
                    }
                    // The GUI retains source faces through the animation,
                    // then publishes warmed destination faces when it ends.
                    let settledSurface = makeSurface(displayed: visible, transition: nil)
                    SCNTransaction.begin(); SCNTransaction.disableActions = true
                    settledSurface.updateInteractionView(view, coordinator: coordinator)
                    SCNTransaction.commit(); SCNTransaction.flush()
                }
                var nodes: [String: [Double]] = [:]
                var pageEdges: [String: [Double]] = [:]
                let root = view.scene?.rootNode.childNode(withName: "physical-book.root", recursively: true)
                for side in ["left", "right"] {
                    guard let root, let page = root.childNode(withName:"book.\(side)-active-page",recursively:true),
                          let source = page.geometry?.sources(for:.vertex).first else { continue }
                    let index = side == "left" ? source.vectorCount-2:0
                    let p = source.data.withUnsafeBytes { bytes -> SCNVector3 in
                        let at = source.dataOffset+index*source.dataStride
                        return SCNVector3(bytes.loadUnaligned(fromByteOffset:at,as:Float.self),bytes.loadUnaligned(fromByteOffset:at+4,as:Float.self),bytes.loadUnaligned(fromByteOffset:at+8,as:Float.self))
                    }
                    let world = page.convertPosition(p,to:root)
                    pageEdges[side] = [Double(world.x),Double(world.y),Double(world.z)]
                }
                for name in ["book-shell.front-cover", "book-shell.back-cover", "book-shell.spine-artwork", "book.left-page-block", "book.right-page-block"] {
                    guard let node = root?.childNode(withName: name, recursively: true), let root else { continue }
                    let b = node.boundingBox
                    var points: [Double] = []
                    for x in [b.min.x, b.max.x] { for z in [b.min.z, b.max.z] {
                        let p = node.convertPosition(SCNVector3(x, 0, z), to: root)
                        points += [Double(p.x), Double(p.y), Double(p.z)]
                    } }
                    nodes[name] = points

                    // BOLD Writer native acceptance instrumentation:
                    // Retain the legacy four-point sample above.
                    // Record ALL eight local bounding-box corners
                    // transformed into the physical-book root space.
                    //
                    // The old sample forced local Y to zero, which
                    // can misidentify a coordinate-origin change
                    // as a detached physical spine.
                    var worldBounds8: [Double] = []
                    for x in [b.min.x, b.max.x] {
                        for y in [b.min.y, b.max.y] {
                            for z in [b.min.z, b.max.z] {
                                let corner = node.convertPosition(
                                    SCNVector3(x, y, z),
                                    to: root
                                )
                                worldBounds8 += [
                                    Double(corner.x),
                                    Double(corner.y),
                                    Double(corner.z)
                                ]
                            }
                        }
                    }
                    nodes[name + ".worldBounds8"] = worldBounds8

                }
                let snapshotStart = ProcessInfo.processInfo.systemUptime
                guard let image = handle.image(size: CGSize(width: 1600, height: 1200)),
                      let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
                      let data = bitmap.representation(using: .png, properties: [:]) else { throw WriterError.message("Native viewport frame failed.") }
                if step.capture != false { try data.write(to: output.appendingPathComponent(step.name + ".png"), options: .atomic) }
                let snapshotMilliseconds = (ProcessInfo.processInfo.systemUptime - snapshotStart) * 1000
                func hash(_ image: NSImage?) -> String? {
                    guard let cg = image?.cgImage(forProposedRect: nil, context: nil, hints: nil),
                          let data = cg.dataProvider?.data as Data? else { return nil }
                    return SHA256.hash(data: data).map { String(format:"%02x",$0) }.joined()
                }
                let panelHashes = ["front": hash(textures.front),"spine": hash(textures.spine),"back": hash(textures.back)].compactMapValues { $0 }
                let panelImages = [textures.front,textures.spine,textures.back].compactMap { $0 }
                currentImageIDs = Set(panelImages.map(ObjectIdentifier.init))
                for image in panelImages where !imagesSeen.contains(where: { $0.value === image }) { imagesSeen.append(WeakResource(image)) }
                if !viewsSeen.contains(where: { $0.value === view }) { viewsSeen.append(WeakResource(view)) }
                let previousScenes = scenes.filter { $0.value != nil && $0.value !== view.scene }.count
                let previousTextures = texturesSeen.filter { $0.value != nil && $0.value !== textures }.count
                if let scene = view.scene, !scenes.contains(where: { $0.value === scene }) { scenes.append(WeakResource(scene)) }
                if !texturesSeen.contains(where: { $0.value === textures }) { texturesSeen.append(WeakResource(textures)) }
                records.append(Frame(name: step.name, sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
                    camera: coordinator.cameraState.saved, open: studio.open, angle: studio.openAngle,
                    spread: studio.spreadIndex, binding: studio.binding, nodes: nodes, textureBytes: textures.estimatedMemoryCost,pageEdges:pageEdges,
                    inspection: BookSceneInspection(scene: view.scene), pageCount: pdf.pageCount,
                    leftPage: visible.leftPage, rightPage: visible.rightPage, residentBytes: residentBytes(),
                    livePreviousScenes: previousScenes, livePreviousTextures: previousTextures,
                    livePreviousImages: 0, livePreviousViews: 0,
                    textureMilliseconds: textureMilliseconds,
                    sceneConstructionMilliseconds: sceneConstructionMilliseconds,
                    navigationMilliseconds: navigationMilliseconds,
                    updateMilliseconds: updateMilliseconds, snapshotMilliseconds: snapshotMilliseconds,
                    panelHashes: panelHashes, turnFrames: turnFrames,
                    turnSnapshotMilliseconds: turnSnapshotMilliseconds))
            }
            turns.finish()
            // Real GUI visits yield the main run loop between workspaces.
            // Drain deferred AppKit/Metal retirement after the autorelease pool,
            // rather than measuring only temporary snapshot/raster allocations.
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
            records[records.count - 1].residentBytes = residentBytes()
            records[records.count - 1].livePreviousImages = imagesSeen.filter {
                guard let image = $0.value else { return false }; return !currentImageIDs.contains(ObjectIdentifier(image))
            }.count
            records[records.count - 1].livePreviousViews = viewsSeen.filter { $0.value != nil && $0.value !== view }.count
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(records).write(to: output.appendingPathComponent("frames.json"), options: .atomic)
        print("BOLD_STUDIO_ACCEPTANCE_OUTPUT=" + output.path)
    }
}
#endif
