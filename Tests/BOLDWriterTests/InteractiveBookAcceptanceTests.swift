import AppKit
import SceneKit
import XCTest
import SwiftUI
@testable import BOLDWriter

@MainActor
final class InteractiveBookAcceptanceTests: XCTestCase {
    private func project() -> CoverProject {
        var p = CoverProject(type: .printFullWrap, width: 12.61032, height: 9.25)
        p.trimWidth = 6; p.backWidth = 6; p.trimHeight = 9
        p.spineWidth = 0.36032; p.bleed = 0.125; p.dpi = 24
        return p
    }
    private func scene(angle: Double, binding: BookBinding, count: Int = 160, spread: Int = 40, open: Bool = true) -> SCNScene {
        let visible = PhysicalBookGeometry.spread(at: spread, pageCount: count)
        return BookPreviewScene.make(project: project(), workingLayers: false, open: open, angle: angle,
            leftPage: visible.leftPage, rightPage: visible.rightPage, pageCount: count, spreadIndex: spread,
            leftTexture: nil, rightTexture: nil, margins: false, thumbMode: .off,
            leftPageSettings: PageSettings(), rightPageSettings: PageSettings(), preset: .perspective,
            revisionID: UUID(), binding: binding)
    }
    private func root(_ scene: SCNScene) throws -> SCNNode {
        try XCTUnwrap(scene.rootNode.childNode(withName: "physical-book.root", recursively: true))
    }
    private func center(_ name: String, in scene: SCNScene) throws -> SCNVector3 {
        let r = try root(scene), n = try XCTUnwrap(r.childNode(withName: name, recursively: true))
        if name == "book-shell.spine-artwork",let geometry=n.geometry {
            let b=geometry.boundingBox
            return n.convertPosition(SCNVector3((b.min.x+b.max.x)/2,(b.min.y+b.max.y)/2,(b.min.z+b.max.z)/2),to:r)
        }
        return n.convertPosition(SCNVector3Zero, to: r)
    }
    private func previewSurface(binding: BookBinding, open: Bool = true, spreadIndex: Int = 40) -> BookPreviewSceneView {
        let p = project()
        let handle = BookStudioViewportHandle()
        var presentation = BookStudioPresentation()
        presentation.binding = binding
        presentation.open = open
        presentation.openAngle = 180
        let spread = PhysicalBookGeometry.spread(at: spreadIndex, pageCount: 160)
        return BookPreviewSceneView(project: p, workingLayers: false, binding: binding, isOpen: open,
            openAngle: open ? 180 : 0, pageCount: 160, spreadIndex: spreadIndex, turnTransition: nil, turnTexture: nil,
            turnReverseTexture: nil, turnGeneration: 0, leftPage: spread.leftPage, rightPage: spread.rightPage,
            leftTexture: nil, rightTexture: nil, showMargins: false, thumbMode: .off,
            leftPageSettings: PageSettings(), rightPageSettings: PageSettings(), preset: .perspective,
            revisionID: p.id, resetGeneration: 0, focusGeneration: 0, focus: .automatic,
            zoomAction: .fit, zoomGeneration: 0, zoomDisplayScale: .constant(1), presentation: presentation,
            modelTransform: .constant(.identity), transformMode: .constant(.navigate),
            transformSpace: .constant(.local), customLights: .constant([]),
            selectedCustomLightID: .constant(nil), savedCamera: .constant(nil), selection: .constant(nil),
            viewportHandle: handle)
    }
    func testZeroOpeningIsMechanicallyClosedAndNearZeroIsContinuous() throws {
        for binding in BookBinding.allCases {
            let closed = scene(angle: 180, binding: binding, open: false)
            let zero = scene(angle: 0, binding: binding)
            let near = scene(angle: 0.0001, binding: binding)
            for name in ["book-shell.front-cover", "book-shell.back-cover"] {
                let a = try center(name,in: closed), b = try center(name,in: zero), c = try center(name,in: near)
                XCTAssertEqual(a.x,b.x,accuracy:0.000001); XCTAssertEqual(a.z,b.z,accuracy:0.000001)
                XCTAssertEqual(a.x,c.x,accuracy:0.002); XCTAssertEqual(a.z,c.z,accuracy:0.002)
            }
            XCTAssertNotNil(try root(zero).childNode(withName:"book.closed-page-block",recursively:true))
        }
    }
    func testEntireOpeningDomainHasFiniteContinuousSupportedGeometry() throws {
        for binding in BookBinding.allCases {
            var previous: [String: SCNVector3] = [:]
            var maximumPenetration = 0.0
            var penetratingSurface = ""
            for degree in 0...180 {
                try autoreleasepool {
                    let s = scene(angle: Double(degree), binding: binding)
                    let inspection = BookSceneInspection(scene: s)
                    if inspection.maximumCoverPenetration > maximumPenetration {
                        maximumPenetration = inspection.maximumCoverPenetration
                        penetratingSurface = "\(degree): " + (inspection.penetratingSurface ?? "unknown")
                    }
                    XCTAssertTrue(inspection.finite, "\(binding) \(degree)")
                    for name in ["book-shell.front-cover","book-shell.back-cover","book-shell.spine-artwork"] {
                        let point = try center(name,in:s)
                        if let last = previous[name] {
                            XCTAssertLessThan(hypot(Double(point.x-last.x),Double(point.z-last.z)),0.15,
                                "Discontinuous \(name) at \(degree) degrees")
                        }
                        previous[name] = point
                    }
                    if degree > 0 {
                        XCTAssertEqual(inspection.supports.count,2)
                        for (side,support) in inspection.supports {
                            XCTAssertGreaterThanOrEqual(support.depth,0)
                            XCTAssertGreaterThan(support.minimumGap,-0.003)
                            XCTAssertLessThan(support.maximumGap,0.04)
                            XCTAssertEqual(support.hinge[0],(side == "left" ? -1:1)*PhysicalBookGeometry(project:project()).openSpineHingeOffset(angleDegrees:Double(degree),binding:binding)*0.7,accuracy:0.00001)
                        }
                        let depth = inspection.supports.values.reduce(0) { $0+$1.depth }
                        XCTAssertEqual(depth,project().spineWidth*0.7,accuracy:0.00001)
                    }
                }
            }
            XCTAssertLessThanOrEqual(maximumPenetration,0.0001,"\(binding) \(penetratingSurface)")
        }
    }
    func testOpeningPoseConservesAngleAndReturnsDeterministicEndpoints() {
        let g = PhysicalBookGeometry(project: project())
        var seed: UInt64 = 3184081
        let samples = [0.0,9,18,36,54,72,90,108,126,144,162,171,180] + (0..<100).map { _ -> Double in
            seed = seed &* 6364136223846793005 &+ 1
            return Double(seed % 180000)/1000
        }
        for angle in samples {
            let p = g.openingPose(angleDegrees:angle)
            XCTAssertEqual(p.leftLiftDegrees+p.rightLiftDegrees,180-angle,accuracy:0.0000001)
            XCTAssertGreaterThanOrEqual(p.leftHingeDepth,0)
            XCTAssertLessThanOrEqual(p.leftHingeDepth,g.paperBlockDepth)
            XCTAssertEqual(p,g.openingPose(angleDegrees:angle))
        }
        XCTAssertEqual(g.openingPose(angleDegrees:0).leftLiftDegrees,180)
        XCTAssertEqual(g.openingPose(angleDegrees:180).leftLiftDegrees,0)
        XCTAssertEqual(g.openingPose(angleDegrees:.nan),g.openingPose(angleDegrees:180))
    }
    func testOddEvenMassesAndEveryReadingPageAreConservedAndOrdered() {
        for count in [1,2,159,160,535] {
            var pages: [Int] = []
            for index in 0...count/2 {
                let spread = PhysicalBookGeometry.spread(at:index,pageCount:count)
                pages += [spread.leftPage,spread.rightPage].compactMap { $0 }
                let masses = PhysicalBookGeometry.pageStacks(pageCount:count,spreadIndex:index,totalDepth:1.20482)
                XCTAssertGreaterThanOrEqual(masses.leftDepth,0); XCTAssertGreaterThanOrEqual(masses.rightDepth,0)
                XCTAssertEqual(masses.leftDepth+masses.rightDepth,1.20482,accuracy:0.000001)
                XCTAssertEqual(masses.turnedPages+masses.remainingPages,count)
                XCTAssertEqual(masses.turnedPages,min(count,index*2))
            }
            XCTAssertEqual(pages,Array(1...count),"No duplicate/skipped/reversed page")
            for fraction in [0.0,0.1,0.25,0.5,0.75,0.9,1] {
                let index = Int((Double(count/2)*fraction).rounded())
                let mass = PhysicalBookGeometry.pageStacks(pageCount:count,spreadIndex:index,totalDepth:0.36032)
                XCTAssertEqual(mass.leftDepth,0.36032*Double(index*2)/Double(count),accuracy:0.000001)
            }
        }
    }
    func testForwardBackwardRapidAlternatingTurnsAndBoundaryMassTransfer() {
        let g = PhysicalBookGeometry(project:project())
        for count in [159,160] {
            var state = BookPageTurnState()
            XCTAssertNil(state.begin(to:-1,maximumSpread:count/2))
            for destination in [1,2,3,2,3,2,1,0,count/4,count/2,count/2-1,count/2] {
                let from = state.spreadIndex
                guard let transition = state.begin(to:destination,maximumSpread:count/2) else { XCTFail(); continue }
                XCTAssertNil(state.begin(to:0,maximumSpread:count/2),"Active turns cannot overlap")
                for progress in stride(from:0.0,through:1.0,by:0.05) {
                    let m = g.pageTurnMassTransfer(pageCount:count,fromSpread:from,toSpread:destination,progress:progress,binding:.softcover)
                    XCTAssertEqual(m.leftDepth+m.rightDepth+m.movingSheetDepth,g.paperBlockDepth,accuracy:0.000001)
                    XCTAssertGreaterThanOrEqual(m.leftDepth,0); XCTAssertGreaterThanOrEqual(m.rightDepth,0)
                }
                XCTAssertEqual(transition.toSpread,destination); state.finish()
            }
            XCTAssertNil(state.begin(to:count/2+1,maximumSpread:count/2))
        }
    }
    func testFullyOpenHardcoverBoardsDoNotOverlapAcrossGutter() throws {
        let s = scene(angle:180,binding:.hardcover)
        let r = try root(s)
        let front = try XCTUnwrap(r.childNode(withName:"book-shell.front-cover",recursively:true))
        let back = try XCTUnwrap(r.childNode(withName:"book-shell.back-cover",recursively:true))
        let a = front.boundingBox, b = back.boundingBox
        let frontInner = front.convertPosition(SCNVector3(a.min.x,0,0),to:r)
        let backInner = back.convertPosition(SCNVector3(b.min.x,0,0),to:r)
        XCTAssertLessThanOrEqual(frontInner.x,backInner.x+0.00001)
        XCTAssertEqual(frontInner.x,-PhysicalBookGeometry(project:project()).openSpineHingeOffset(angleDegrees:180,binding:.hardcover)*0.7,accuracy:0.00001)
        XCTAssertEqual(backInner.x,PhysicalBookGeometry(project:project()).openSpineHingeOffset(angleDegrees:180,binding:.hardcover)*0.7,accuracy:0.00001)
    }

    func testSoftcoverStockHasThicknessAndNeverBendsThroughPaperSupport() throws {
        let thickness = CGFloat(PhysicalBookGeometry(project:project()).coverThickness(for:.softcover)*0.7)
        for angle in [0.0001,9,18,45,90,135,171,180] {
            let s = scene(angle:angle,binding:.softcover)
            let r = try root(s)
            for (side,name) in [("left","front"),("right","back")] {
                let cover = try XCTUnwrap(r.childNode(withName:"book-shell.\(name)-cover",recursively:true))
                let source = try XCTUnwrap(cover.geometry?.sources(for:.vertex).first)
                let vertices = BookOpenGutterGeometry.vertices(source)
                XCTAssertEqual(vertices.count,100)
                for i in 0..<50 {
                    XCTAssertEqual(vertices[i].z-vertices[i+50].z,thickness,accuracy:0.000001)
                }
                let block = try XCTUnwrap(r.childNode(withName:"book.\(side)-page-block",recursively:true))
                let box = try XCTUnwrap(block.geometry as? SCNBox)
                let normal = block.convertVector(SCNVector3(0,0,1),to:r)
                let support = block.convertPosition(SCNVector3(0,0,-box.length/2),to:r)
                for vertex in vertices {
                    let p = cover.convertPosition(vertex,to:r)
                    let separation = (support.x-p.x)*normal.x+(support.z-p.z)*normal.z
                    XCTAssertGreaterThan(separation,0.0008,"Cover cannot penetrate paper at \(angle)")
                    XCTAssertLessThan(separation,0.026,"Unbounded cover float at \(angle)")
                }
            }
        }
    }

    func testUnequalOddEvenStacksRemainOutsideBothCovers() throws {
        for binding in BookBinding.allCases {
            for count in [159,160] {
                for fraction in [0.0,0.1,0.25,0.5,0.75,0.9,1] {
                    for angle in [0.001,9,18,36,54,72,90,108,126,144,162,171,180] {
                        autoreleasepool {
                            let s = scene(angle:angle,binding:binding,count:count,spread:Int((Double(count/2)*fraction).rounded()))
                            let measured = BookSceneInspection(scene:s)
                            XCTAssertTrue(measured.finite)
                            XCTAssertLessThanOrEqual(measured.maximumCoverPenetration,0.0001,
                                "\(binding) \(count) \(fraction) \(angle): \(measured.penetratingSurface ?? "")")
                        }
                    }
                }
            }
        }
    }

    func testLiveMassTransferKeepsSupportAndDeterministicVisiblePaper() throws {
        for count in [159,160] {
            for binding in BookBinding.allCases {
                let s = scene(angle:180,binding:binding,count:count,spread:40)
                let transition = BookPageTurnTransition(fromSpread:40,toSpread:41,direction:.forward,rotation:-Double.pi)
                let r = try root(s)
                var saved: [SCNVector3] = []
                for progress in [0.0,0.25,0.5,0.75,1,0.25] {
                    BookPreviewScene.applyPageTurnMassTransfer(in:s,project:project(),pageCount:count,binding:binding,transition:transition,progress:CGFloat(progress))
                    let measured = BookSceneInspection(scene:s)
                    XCTAssertTrue(measured.finite)
                    XCTAssertLessThanOrEqual(measured.maximumCoverPenetration,0.0001)
                    for (side,support) in measured.supports {
                        XCTAssertEqual(support.hinge[0],(side == "left" ? -1:1)*PhysicalBookGeometry(project:project()).openSpineHingeOffset(angleDegrees:180,binding:binding)*0.7,accuracy:0.00001)
                        XCTAssertGreaterThan(support.minimumGap,-0.0001)
                        XCTAssertLessThan(support.maximumGap,0.002)
                    }
                    let expected = PhysicalBookGeometry(project:project()).pageTurnMassTransfer(pageCount:count,fromSpread:40,toSpread:41,progress:progress,binding:binding)
                    let actualDepth = measured.supports.values.reduce(0) { $0+$1.depth }
                    XCTAssertEqual(actualDepth+expected.movingSheetDepth*0.7,expected.totalDepth*0.7,accuracy:0.000001)
                    let volume = try XCTUnwrap(r.childNode(withName:"book.left-page-volume",recursively:true))
                    let vertices = BookOpenGutterGeometry.vertices(try XCTUnwrap(volume.geometry?.sources(for:.vertex).first))
                    if progress == 0.25 {
                        if saved.isEmpty { saved = vertices }
                        else {
                            XCTAssertEqual(saved.count,vertices.count)
                            for (a,b) in zip(saved,vertices) {
                                XCTAssertEqual(a.x,b.x,accuracy:0.00001)
                                XCTAssertEqual(a.z,b.z,accuracy:0.00001)
                            }
                        }
                    }
                }
            }
        }
    }

    func testCameraFramingWhilePageTurnGeometryAdvances() throws {
        for binding in BookBinding.allCases {
            let coordinator = BookPreviewSceneView.Coordinator()
            let view = previewSurface(binding: binding).makeInteractionView(coordinator: coordinator)
            view.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
            let book = try XCTUnwrap(view.scene)
            let bounds = try XCTUnwrap(coordinator.cameraBounds)
            let renderer = SCNRenderer(device: nil, options: nil)
            renderer.scene = book
            BookPreviewScene.animatePageTurn(in: book, project: project(), pageCount: 160,
                binding: binding, image: NSImage(size: NSSize(width: 60, height: 90)),
                reverseImage: nil, transition: BookPageTurnTransition(fromSpread: 40,
                    toSpread: 41, direction: .forward, rotation: -.pi))
            var camera = BookPreviewCameraState(yaw: 0.2, pitch: 0.9, distance: 10, target: .zero)
            for step in 0..<40 {
                autoreleasepool {
                    renderer.update(atTime: Double(step) / 60)
                    view.onViewportResize?(step.isMultiple(of: 2) ? 0.8 : 1.8)
                    camera = coordinator.cameraState
                    XCTAssertTrue(camera.distance.isFinite)
                    XCTAssertGreaterThan(camera.distance, 0)
                    XCTAssertTrue(camera.target.x.isFinite && camera.target.y.isFinite && camera.target.z.isFinite)
                    XCTAssertTrue(BookPreviewCameraMath.minimumOrbitDistance(in: bounds, target: camera.target).isFinite)
                }
            }
            renderer.scene = nil
            view.releasePreviewResources()
        }
    }

    func testSceneReplacementAndResizeDuringConsecutiveSpreadChanges() throws {
        for binding in BookBinding.allCases {
            let coordinator = BookPreviewSceneView.Coordinator()
            var surface = previewSurface(binding: binding, open: false, spreadIndex: 0)
            let view = surface.makeInteractionView(coordinator: coordinator)
            view.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
            let renderer = SCNRenderer(device: nil, options: nil)

            for (index, spread) in [1, 2, 1, 40, 80, 79, 0].enumerated() {
                let retiredScene = try XCTUnwrap(view.scene)
                renderer.scene = retiredScene
                BookPreviewScene.animatePageTurn(in: retiredScene, project: project(), pageCount: 160,
                    binding: binding, image: NSImage(size: NSSize(width: 60, height: 90)),
                    reverseImage: nil, transition: BookPageTurnTransition(fromSpread: max(0, spread - 1),
                        toSpread: spread, direction: .forward, rotation: -.pi))
                renderer.update(atTime: Double(index) / 60)

                surface = previewSurface(binding: binding, open: index.isMultiple(of: 2), spreadIndex: spread)
                surface.updateInteractionView(view, coordinator: coordinator)
                let installedScene = try XCTUnwrap(view.scene)
                XCTAssertFalse(installedScene === retiredScene, "spread change must replace the installed scene")

                // The old renderer may still hold the retired scene while the
                // view receives resize callbacks for the newly installed one.
                for aspect in [0.8, 1.8, 1.2] {
                    view.onViewportResize?(aspect)
                    XCTAssertTrue(coordinator.cameraState.distance.isFinite)
                    XCTAssertGreaterThan(coordinator.cameraState.distance, 0)
                    XCTAssertTrue(coordinator.cameraState.target.x.isFinite)
                    XCTAssertTrue(coordinator.cameraState.target.y.isFinite)
                    XCTAssertTrue(coordinator.cameraState.target.z.isFinite)
                }
                renderer.scene = nil
                renderer.scene = installedScene
            }

            renderer.scene = nil
            view.releasePreviewResources()
        }
    }

    func testManualCameraRecentersAndRemainsOutsideOpenedBook() throws {
        let p = project(), coordinator = BookPreviewSceneView.Coordinator(), handle = BookStudioViewportHandle()
        func surface(open: Bool) -> BookPreviewSceneView {
            var presentation = BookStudioPresentation(); presentation.open = open
            return BookPreviewSceneView(project:p,workingLayers:false,binding:.softcover,isOpen:open,openAngle:180,
                pageCount:160,spreadIndex:40,turnTransition:nil,turnTexture:nil,turnReverseTexture:nil,turnGeneration:0,
                leftPage:80,rightPage:81,leftTexture:nil,rightTexture:nil,showMargins:false,thumbMode:.off,
                leftPageSettings:PageSettings(),rightPageSettings:PageSettings(),preset:.perspective,revisionID:p.id,
                resetGeneration:0,focusGeneration:0,focus:.automatic,zoomAction:.fit,zoomGeneration:0,
                zoomDisplayScale:.constant(1),presentation:presentation,modelTransform:.constant(.identity),
                transformMode:.constant(.navigate),transformSpace:.constant(.local),customLights:.constant([]),
                selectedCustomLightID:.constant(nil),savedCamera:.constant(nil),selection:.constant(nil),viewportHandle:handle)
        }
        let view = surface(open:false).makeInteractionView(coordinator:coordinator)
        view.frame = NSRect(x:0,y:0,width:800,height:600)
        view.onOrbit?(20,10); view.onZoom?(0.1)
        let yaw = coordinator.cameraState.yaw
        surface(open:true).updateInteractionView(view,coordinator:coordinator)
        XCTAssertEqual(coordinator.cameraState.yaw,yaw,accuracy:0.000001)
        XCTAssertEqual(coordinator.cameraState.target.x,0,accuracy:0.1)
        XCTAssertGreaterThanOrEqual(coordinator.cameraState.distance,
            BookPreviewCameraMath.minimumOrbitDistance(in:view.scene,target:coordinator.cameraState.target))
    }

    func testAnimatedLeafRetainsPrintedGutterAndAvoidsBothCovers() throws {
        for count in [159,160] {
        for binding in BookBinding.allCases {
            for (from, to, direction) in [(0,1,BookPageTurnDirection.forward),(40,39,.backward),(count/2-1,count/2,.forward)] {
                SCNTransaction.begin(); SCNTransaction.disableActions = true
                let s = scene(angle:180,binding:binding,count:count,spread:from)
                let transition = BookPageTurnTransition(fromSpread:from,toSpread:to,direction:direction,
                    rotation:direction == .forward ? -.pi:.pi)
                let r = try root(s)
                let page = try XCTUnwrap(r.childNode(withName:direction == .forward ? "book.right-active-page":"book.left-active-page",recursively:true))
                let points = BookOpenGutterGeometry.vertices(try XCTUnwrap(page.geometry?.sources(for:.vertex).first))
                let expected = page.convertPosition(points[direction == .forward ? 0:points.count-2],to:r)
                BookPreviewScene.animatePageTurn(in:s,project:project(),pageCount:count,binding:binding,
                    image:NSImage(size:NSSize(width:60,height:90)),reverseImage:nil,transition:transition)
                SCNTransaction.commit(); SCNTransaction.flush()
                let renderer = SCNRenderer(device:nil,options:nil); renderer.scene = s
                do {
                    let leaf = try XCTUnwrap(r.childNode(withName:"book.turning-page-leaf",recursively:true))
                    let leafPoints = BookOpenGutterGeometry.vertices(try XCTUnwrap(leaf.geometry?.sources(for:.vertex).first))
                    for (a,b) in zip(points,leafPoints) {
                        let x = page.convertPosition(a,to:r), y = leaf.convertPosition(b,to:r)
                        XCTAssertEqual(x.x,y.x,accuracy:0.0001); XCTAssertEqual(x.z,y.z,accuracy:0.0001)
                    }
                }
                for time in [0.0,0.06,0.12,0.24,0.36,0.47] {
                    _ = renderer.snapshot(atTime:time,with:CGSize(width:64,height:64),antialiasingMode:.none)
                    let inspection = BookSceneInspection(scene:s)
                    for name in ["book-shell.front-cover","book-shell.back-cover","book-shell.spine-artwork"] {
                        let cover = try XCTUnwrap(r.childNode(withName:name,recursively:true))
                        XCTAssertEqual(cover.position.x,cover.presentation.position.x,accuracy:0.00001)
                        XCTAssertEqual(cover.position.z,cover.presentation.position.z,accuracy:0.00001)
                        XCTAssertEqual(cover.eulerAngles.y,cover.presentation.eulerAngles.y,accuracy:0.00001)
                    }
                    let gutter = try XCTUnwrap(inspection.turningGutter)
                    XCTAssertEqual(inspection.turnUsesPrintedSurfaces,true)
                    XCTAssertEqual(gutter[0],Double(expected.x),accuracy:0.0001)
                    XCTAssertEqual(gutter[2],Double(expected.z),accuracy:0.0001)
                    XCTAssertLessThanOrEqual(inspection.maximumCoverPenetration,0.0001,
                        "\(binding) \(from) \(time) \(inspection.penetratingSurface ?? "") \(inspection.penetratingPoint ?? [])")
                }
                _ = renderer.snapshot(atTime:0.6,with:CGSize(width:64,height:64),antialiasingMode:.none)
                XCTAssertNil(r.childNode(withName:"book.turning-page-leaf",recursively:true))
            }
        }
        }
    }

    func testZoomBoundKeepsCameraOutsideBothPosedBindings() throws {
        for binding in BookBinding.allCases {
            for angle in [0.0,9,45,90,135,180] {
                let s = scene(angle:angle,binding:binding)
                var camera = BookPreviewCameraMath.state(project:project(),open:angle>0,preset:.perspective,focus:.automatic)
                let minimum = BookPreviewCameraMath.minimumOrbitDistance(in:s,target:camera.target)
                XCTAssertGreaterThan(minimum,2)
                for _ in 0..<100 { camera.zoom(by:0.8,minimum:minimum,maximum:30) }
                XCTAssertEqual(camera.distance,minimum,accuracy:0.000001)
                camera.orbit(deltaX:400,deltaY:4000)
                XCTAssertLessThanOrEqual(abs(camera.pitch),1.52)
                for _ in 0..<100 { camera.zoom(by:1.25,minimum:minimum,maximum:30) }
                XCTAssertEqual(camera.distance,30)
                XCTAssertTrue(camera.saved.isValid)
            }
        }
    }

    /// Regression for the false 3.15-unit discontinuity reported
    /// by sampling the spine at a forced local Y=0.
    ///
    /// Always transform the real local bounds center into the
    /// physical-book root coordinate system.
    ///
    /// Neither binding may move its physical spine vertically
    /// away from the covers immediately after opening.
    func testSpineWorldBoundsRemainContinuousNearClosed() throws {
        func worldBoundsCenter(
            _ node: SCNNode,
            relativeTo root: SCNNode
        ) -> SIMD3<Double> {
            let box = node.boundingBox
            let localCenter = SCNVector3(
                (box.min.x + box.max.x) / 2,
                (box.min.y + box.max.y) / 2,
                (box.min.z + box.max.z) / 2
            )
            let world = node.convertPosition(localCenter, to: root)
            return SIMD3<Double>(
                Double(world.x),
                Double(world.y),
                Double(world.z)
            )
        }

        for binding in BookBinding.allCases {
            let closedScene = scene(
                angle: 180,
                binding: binding,
                open: false
            )
            let closedRoot = try root(closedScene)
            let closedSpine = try XCTUnwrap(
                closedRoot.childNode(
                    withName: "book-shell.spine-artwork",
                    recursively: true
                )
            )
            let closedCenter = worldBoundsCenter(
                closedSpine,
                relativeTo: closedRoot
            )

            for nearAngle in [0.0001, 0.01, 0.1, 1.0] {
                let openedScene = scene(
                    angle: nearAngle,
                    binding: binding
                )
                let openedRoot = try root(openedScene)
                let openedSpine = try XCTUnwrap(
                    openedRoot.childNode(
                        withName: "book-shell.spine-artwork",
                        recursively: true
                    )
                )
                let openedCenter = worldBoundsCenter(
                    openedSpine,
                    relativeTo: openedRoot
                )

                let movement = simd_length(
                    openedCenter - closedCenter
                )

                XCTAssertTrue(
                    movement.isFinite,
                    "Spine displacement must remain finite"
                )
                XCTAssertEqual(
                    openedCenter.y,
                    closedCenter.y,
                    accuracy: 0.0005,
                    "Spine must keep its physical vertical center"
                )
                XCTAssertLessThan(
                    movement,
                    0.05,
                    "Spine must remain attached near closed: \(binding), \(nearAngle)°"
                )
            }
        }
    }

}
