import AppKit
import SceneKit
import XCTest
@testable import BOLDWriter

@MainActor
final class VisibleBookBindingTests: XCTestCase {
    private func scene(angle:Double,binding:BookBinding,spread:Int) -> SCNScene {
        var p=CoverProject(type:.printFullWrap,width:12.61032,height:9.25)
        p.trimWidth=6; p.backWidth=6; p.trimHeight=9; p.spineWidth=0.36032; p.dpi=24
        let pages=PhysicalBookGeometry.spread(at:spread,pageCount:160)
        return BookPreviewScene.make(project:p,workingLayers:false,open:true,angle:angle,
            leftPage:pages.leftPage,rightPage:pages.rightPage,pageCount:160,spreadIndex:spread,
            leftTexture:nil,rightTexture:nil,margins:false,thumbMode:.off,leftPageSettings:PageSettings(),
            rightPageSettings:PageSettings(),preset:.reading,revisionID:UUID(),binding:binding)
    }
    func testVisiblePaperUndersideTouchesActualCoverLiningAcrossUnequalMasses() throws {
        for binding in BookBinding.allCases {
            for angle in [9.0,45,90,106,135,180] {
                for spread in [0,40,80] {
                    let s=scene(angle:angle,binding:binding,spread:spread)
                    let root=try XCTUnwrap(s.rootNode.childNode(withName:"physical-book.root",recursively:true))
                    for (side,name,front) in [("left","front",true),("right","back",false)] {
                        guard let volume=root.childNode(withName:"book.\(side)-page-volume",recursively:true),!volume.isHidden else { continue }
                        let cover=try XCTUnwrap(root.childNode(withName:"book-shell.\(name)-cover",recursively:true))
                        let bounds=try XCTUnwrap(cover.geometry).boundingBox
                        let flex=(cover.geometry is SCNBox) ? nil:cover.geometry?.sources(for:.vertex).first.map(BookOpenGutterGeometry.vertices)
                        let points=BookOpenGutterGeometry.vertices(try XCTUnwrap(volume.geometry?.sources(for:.vertex).first))
                        var samples=0
                        for point in points.prefix(points.count/2) {
                            let p=cover.convertPosition(point,from:volume)
                            let u=(p.x-bounds.min.x)/(bounds.max.x-bounds.min.x)
                            // Outside the bound crease, visible paper must sit
                            // on the real lining, not just an invisible box.
                            guard u>0.2,u<0.8 else { continue }
                            var lining=front ? bounds.min.z:bounds.max.z
                            if let flex {
                                let at=min(24,max(0,u*24)),i=min(23,Int(at)),t=at-CGFloat(i),offset=front ? 50:0
                                lining=flex[i*2+offset].z+(flex[(i+1)*2+offset].z-flex[i*2+offset].z)*t
                            }
                            XCTAssertEqual((p.z-lining)*(front ? -1:1),0.001,accuracy:0.00002,
                                "\(binding) \(angle) \(spread) \(side)")
                            samples += 1
                        }
                        XCTAssertGreaterThan(samples,100)
                    }
                    XCTAssertLessThanOrEqual(BookSceneInspection(scene:s).maximumCoverPenetration,0.0001)
                }
            }
        }
    }
    func testVisiblePaperRetainsOpaqueDepthMaterialsWhenSupportBoxesAreHidden() throws {
        for binding in BookBinding.allCases {
            let s=scene(angle:45,binding:binding,spread:40)
            for side in ["left","right"] {
                let support=try XCTUnwrap(s.rootNode.childNode(withName:"book.\(side)-page-block",recursively:true))
                for material in try XCTUnwrap(support.geometry).materials {
                    XCTAssertEqual(material.transparency,0)
                    XCTAssertFalse(material.writesToDepthBuffer)
                }
                for name in ["page-volume","gutter-fold"] {
                    let surface=try XCTUnwrap(s.rootNode.childNode(withName:"book.\(side)-\(name)",recursively:true))
                    for material in try XCTUnwrap(surface.geometry).materials {
                        XCTAssertEqual(material.transparency,1,"\(side) \(name) must be visible")
                        XCTAssertTrue(material.readsFromDepthBuffer)
                        XCTAssertTrue(material.writesToDepthBuffer)
                    }
                }
            }
        }
    }
    func testVisibleEdgeStrataFollowPaperThicknessInsteadOfPageWidth() throws {
        let s=scene(angle:180,binding:.softcover,spread:40)
        let node=try XCTUnwrap(s.rootNode.childNode(withName:"book.right-page-volume",recursively:true))
        let geometry=try XCTUnwrap(node.geometry)
        let sources=geometry.sources(for:.texcoord)
        XCTAssertEqual(sources.count,2)
        let source=try XCTUnwrap(sources.last)
        XCTAssertEqual(source.vectorCount,1110)
        source.data.withUnsafeBytes { bytes in
            for index in 0..<source.vectorCount {
                let offset=source.dataOffset+index*source.dataStride
                let u=bytes.loadUnaligned(fromByteOffset:offset,as:Float.self)
                XCTAssertEqual(u,index < source.vectorCount/2 ? 0:1,accuracy:0.00001)
            }
        }
        for material in geometry.materials.dropFirst(2) {
            XCTAssertEqual(material.diffuse.mappingChannel,1)
            XCTAssertEqual(material.normal.mappingChannel,1)
        }
    }
    func testFullyOpenBoardsAndSpineRestTogetherOnTabletopWithoutHangingLoop() throws {
        for binding in BookBinding.allCases {
            for spread in [0,40,80] {
                let s=scene(angle:180,binding:binding,spread:spread)
                var presentation=BookStudioPresentation()
                presentation.open=true; presentation.openAngle=180; presentation.cameraPreset = .reading
                BookStudioTransformScene.apply(to:s,presentation:presentation)
                let ground=try XCTUnwrap(s.rootNode.childNode(withName:"studio-ground",recursively:true))
                for name in ["book-shell.front-cover","book-shell.back-cover","book-shell.spine-artwork"] {
                    let node=try XCTUnwrap(s.rootNode.childNode(withName:name,recursively:true))
                    let points=BookOpenGutterGeometry.surfaceVertices(try XCTUnwrap(node.geometry))
                    let lowest=try XCTUnwrap(points.map { node.convertPosition($0,to:s.rootNode).y }.min())
                    XCTAssertEqual(lowest,ground.position.y,accuracy:0.008,"\(binding) \(spread) \(name)")
                    let measured=try XCTUnwrap(BookSceneInspection(scene:s).groundSeparations[name])
                    XCTAssertEqual(measured,Double(lowest-ground.position.y),accuracy:0.00001)
                }
            }
        }
    }
    func testReadingTabletopOrientationDoesNotSnapWhenOpeningCrossesZero() throws {
        var previous: SCNVector3?
        for angle in [0.0,0.0001,1,5,10] {
            let s=scene(angle:angle,binding:.softcover,spread:40)
            var p=BookStudioPresentation(); p.open=angle>0; p.openAngle=angle; p.cameraPreset = .reading
            BookStudioTransformScene.apply(to:s,presentation:p)
            let root=try XCTUnwrap(s.rootNode.childNode(withName:"physical-book.root",recursively:true))
            let normal=root.convertVector(SCNVector3(0,0,1),to:s.rootNode)
            XCTAssertEqual(normal.y,1,accuracy:0.00001)
            if let previous { XCTAssertEqual(normal.y,previous.y,accuracy:0.00001) }
            previous=normal
        }
    }
    func testRestingOpeningKeepsBackSupportHorizontalAcrossEntireDomain() {
        var p=CoverProject(type:.printFullWrap,width:12.61032,height:9.25)
        p.trimWidth=6; p.backWidth=6; p.trimHeight=9; p.spineWidth=0.36032
        let geometry=PhysicalBookGeometry(project:p)
        for degree in 0...180 {
            let pose=geometry.openingPose(angleDegrees:Double(degree))
            XCTAssertEqual(pose.rightLiftDegrees,0,accuracy:0.00001)
            XCTAssertEqual(pose.leftLiftDegrees,180-Double(degree),accuracy:0.00001)
        }
    }
    func testBackCoverAndBindingKeepRestingContactThroughoutOpening() throws {
        for binding in BookBinding.allCases {
            for angle in [5.0,45,90,106,135,180] {
                for spread in [0,40,80] {
                    let s=scene(angle:angle,binding:binding,spread:spread)
                    var p=BookStudioPresentation(); p.open=true; p.openAngle=angle; p.cameraPreset = .reading
                    BookStudioTransformScene.apply(to:s,presentation:p)
                    let inspection=BookSceneInspection(scene:s)
                    for name in ["book-shell.back-cover","book-shell.spine-artwork"] {
                        let gap=try XCTUnwrap(inspection.groundSeparations[name])
                        XCTAssertGreaterThanOrEqual(gap,-0.0001,"\(binding) \(angle) \(spread) \(name)")
                        XCTAssertLessThanOrEqual(gap,0.008,"\(binding) \(angle) \(spread) \(name) must rest on the table")
                    }
                }
            }
        }
    }
    func testPaperbackSpineEndsJoinActualBoundPagesRatherThanRemainingOpenRibbon() throws {
        for angle in [5.0,45,90,106,135,180] {
            for spread in [0,40,80] {
                let s=scene(angle:angle,binding:.softcover,spread:spread)
                let root=try XCTUnwrap(s.rootNode.childNode(withName:"physical-book.root",recursively:true))
                let cap=try XCTUnwrap(root.childNode(withName:"book.page-block-spine-page-volume",recursively:false))
                XCTAssertEqual(BookSceneComponent.component(for:cap.name ?? ""),.pages)
                let points=BookOpenGutterGeometry.vertices(try XCTUnwrap(cap.geometry?.sources(for:.vertex).first))
                XCTAssertEqual(points.count,68); XCTAssertEqual(cap.geometry?.elements.first?.primitiveCount,64)
                var edges:[SCNVector3]=[]
                for side in ["left","right"] {
                    guard let page=root.childNode(withName:"book.\(side)-active-page",recursively:true) else { continue }
                    let p=BookOpenGutterGeometry.vertices(try XCTUnwrap(page.geometry?.sources(for:.vertex).first))
                    edges.append(page.convertPosition(p[side == "left" ? p.count-2:0],to:root))
                }
                let mean=edges.reduce(SCNVector3Zero) { SCNVector3($0.x+$1.x/CGFloat(edges.count),$0.y+$1.y/CGFloat(edges.count),$0.z+$1.z/CGFloat(edges.count)) }
                XCTAssertEqual(points[66].x,mean.x,accuracy:0.00001)
                XCTAssertEqual(points[66].z,mean.z,accuracy:0.00001)
                XCTAssertLessThanOrEqual(BookSceneInspection(scene:s).maximumCoverPenetration,0.0001)
            }
        }
        let hard=scene(angle:106,binding:.hardcover,spread:0)
        XCTAssertNil(hard.rootNode.childNode(withName:"book.page-block-spine-page-volume",recursively:true),
            "A hollow hardcover case must not acquire a paperback glue block")
    }
}
