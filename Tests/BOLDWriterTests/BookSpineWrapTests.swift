import AppKit
import SceneKit
import XCTest
@testable import BOLDWriter

@MainActor
final class BookSpineWrapTests: XCTestCase {
    func testOpenPrintedGutterJoinsAcrossUnequalMassesWithoutChangingTrimOrBoardContact() throws {
        for binding in [BookBinding.hardcover,.softcover] {
            for angle in [160.0,180] {
                for spread in [0,1,5,10] {
                    let p=project()
                    let scene=BookPreviewScene.make(project:p,workingLayers:false,open:true,angle:angle,leftPage:spread == 0 ? nil:spread*2,rightPage:spread*2+1,pageCount:21,spreadIndex:spread,leftTexture:nil,rightTexture:nil,margins:false,thumbMode:.off,leftPageSettings:PageSettings(),rightPageSettings:PageSettings(),preset:.reading,revisionID:UUID(),binding:binding)
                    let root=try XCTUnwrap(scene.rootNode.childNode(withName:"physical-book.root",recursively:true))
                    var edges:[SCNVector3]=[]
                    let g=PhysicalBookGeometry(project:p)
                    let hingeZ=CGFloat((g.outerBookDepth(for:binding)*(-0.5)+g.coverThickness(for:binding))*0.7)
                    for side in ["left","right"] {
                        guard let page=root.childNode(withName:"book.\(side)-active-page",recursively:true) else { continue }
                        let source=try XCTUnwrap(page.geometry?.sources(for:.vertex).first)
                        let vertices=BookOpenGutterGeometry.vertices(source)
                        XCTAssertEqual(vertices.count,74)
                        let edge=vertices[side == "left" ? vertices.count-2:0]
                        let world=page.convertPosition(edge,to:root);edges.append(world)
                        XCTAssertEqual(world.x,0,accuracy:0.00001)
                        XCTAssertEqual(world.z,hingeZ+0.020,accuracy:0.00001)
                        XCTAssertEqual(Double(vertices[1].y-vertices[0].y),g.trimHeight*0.7,accuracy:0.00001)
                    }
                    if edges.count==2 { XCTAssertEqual(edges[0].z,edges[1].z,accuracy:0.00001) }
                }
            }
        }
    }
    private func project() -> CoverProject {
        var p = CoverProject(type:.printFullWrap,width:13.25,height:9.25)
        p.trimWidth = 6; p.backWidth = 6; p.trimHeight = 9; p.spineWidth = 1; p.bleed = 0.125; p.dpi = 24
        var art = CoverLayer(kind:.shape,name:"Wrap",frame:CoverRect()); art.fillHex = "#953A22"; p.layers = [art]
        return p
    }
    func testPrintedSpineRemainsVisibleAndMeetsBothCoverEdgesAcrossOpenPostures() throws {
        for binding in [BookBinding.hardcover,.softcover] {
            for (angle,preset,spread) in [(80.0,BookViewPreset.perspective,1),(160,.reading,1),(160,.reading,0),(160,.reading,10)] {
                let scene = BookPreviewScene.make(project:project(),workingLayers:false,open:true,angle:angle,
                    leftPage:spread == 0 ? nil:spread*2,rightPage:spread*2+1,pageCount:21,spreadIndex:spread,
                    leftTexture:nil,rightTexture:nil,margins:false,thumbMode:.off,
                    leftPageSettings:PageSettings(),rightPageSettings:PageSettings(),preset:preset,revisionID:UUID(),binding:binding)
                let root = try XCTUnwrap(scene.rootNode.childNode(withName:"physical-book.root",recursively:false))
                let strip = try XCTUnwrap(root.childNode(withName:"book-shell.spine-artwork",recursively:false))
                XCTAssertFalse(strip.isHidden,"Printed spine must survive opening and Reading mode")
                let mesh = try XCTUnwrap(strip.geometry)
                XCTAssertTrue(mesh.firstMaterial?.diffuse.contents is NSImage)
                XCTAssertEqual(mesh.sources(for:.vertex).first?.vectorCount,66)
                XCTAssertEqual(mesh.sources(for:.texcoord).first?.vectorCount,66)
                XCTAssertEqual(mesh.elements.first?.primitiveCount,64)
                let source = try XCTUnwrap(mesh.sources(for:.vertex).first)
                func vertex(_ n:Int) -> SCNVector3 {
                    source.data.withUnsafeBytes { bytes in
                        let at = source.dataOffset+n*source.dataStride
                        return SCNVector3(bytes.loadUnaligned(fromByteOffset:at,as:Float.self),
                                          bytes.loadUnaligned(fromByteOffset:at+4,as:Float.self),
                                          bytes.loadUnaligned(fromByteOffset:at+8,as:Float.self))
                    }
                }
                let start = vertex(0), end = vertex(64)
                var materialWidth = 0.0
                for i in 1...32 {
                    let a = vertex((i-1)*2), b = vertex(i*2)
                    materialWidth += hypot(hypot(Double(b.x-a.x),Double(b.y-a.y)),Double(b.z-a.z))
                }
                let expectedWidth = PhysicalBookGeometry(project:project()).outerBookDepth(for:binding)*0.7
                XCTAssertEqual(materialWidth,expectedWidth,accuracy:0.00001,
                    "Opening must preserve the printed spine's material width")
                let coordinates = try XCTUnwrap(mesh.sources(for:.texcoord).first)
                func u(_ n:Int) -> Float {
                    coordinates.data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset:coordinates.dataOffset+n*coordinates.dataStride,as:Float.self) }
                }
                XCTAssertEqual(u(0),0);XCTAssertEqual(u(64),1,accuracy:0.00001)
                for i in 1...32 {
                    let a=vertex((i-1)*2),b=vertex(i*2)
                    let segment=hypot(hypot(Double(b.x-a.x),Double(b.y-a.y)),Double(b.z-a.z))
                    XCTAssertEqual(Double(u(i*2)-u((i-1)*2)),segment/materialWidth,accuracy:0.00001,
                        "Spine texture coordinates must follow physical arc length")
                }
                XCTAssertLessThanOrEqual(hypot(Double(end.x-start.x),Double(end.z-start.z)),expectedWidth+0.00001,"Hinge separation cannot exceed the real printed spine width")
                for (name,first,positive) in [("book-shell.back-cover",0,false),("book-shell.front-cover",64,true)] {
                    let cover = try XCTUnwrap(root.childNode(withName:name,recursively:false)), b = cover.geometry?.boundingBox ?? cover.boundingBox
                    let expected = cover.convertPosition(SCNVector3(b.min.x,b.min.y,positive ? b.max.z+0.001:b.min.z-0.001),to:root)
                    let actual = vertex(first)
                    XCTAssertEqual(actual.x,expected.x,accuracy:0.00001)
                    XCTAssertEqual(actual.y,expected.y,accuracy:0.00001)
                    XCTAssertEqual(actual.z,expected.z,accuracy:0.00001)
                }
            }
        }
    }
    func testOpenBoardsSupportEntireStackWithoutForeEdgeGapsOrPenetration() throws {
        for binding in [BookBinding.hardcover, .softcover] {
            for angle in [20.0, 80, 160, 180] {
                for spread in [0, 1, 5, 10] {
                    let p = project()
                    let scene = BookPreviewScene.make(project: p, workingLayers: false, open: true, angle: angle,
                        leftPage: spread == 0 ? nil : spread * 2, rightPage: spread * 2 + 1, pageCount: 21, spreadIndex: spread,
                        leftTexture: nil, rightTexture: nil, margins: false, thumbMode: .off,
                        leftPageSettings: PageSettings(), rightPageSettings: PageSettings(), preset: .reading, revisionID: UUID(), binding: binding)
                    let root = try XCTUnwrap(scene.rootNode.childNode(withName: "physical-book.root", recursively: true))
                    let thickness = CGFloat(PhysicalBookGeometry(project: p).coverThickness(for: binding) * 0.7)
                    for (side, name, sign) in [("left", "book-shell.front-cover", CGFloat(-1)), ("right", "book-shell.back-cover", CGFloat(1))] {
                        let cover = try XCTUnwrap(root.childNode(withName: name, recursively: true))
                        let block = try XCTUnwrap(root.childNode(withName: "book.\(side)-page-block", recursively: true))
                        let box = try XCTUnwrap(block.geometry as? SCNBox)
                        let cn = cover.convertVector(SCNVector3(0, 0, sign), to: root)
                        let pn = block.convertVector(SCNVector3(0, 0, 1), to: root)
                        XCTAssertEqual(cn.x, pn.x, accuracy: 0.00001)
                        XCTAssertEqual(cn.z, pn.z, accuracy: 0.00001)
                        for x in [-box.width / 2, box.width / 2] {
                            let paper = block.convertPosition(SCNVector3(x, 0, -box.length / 2), to: root)
                            let local = cover.convertPosition(paper, from: root)
                            XCTAssertEqual(sign * local.z - thickness / 2, 0.001 * abs(pn.z), accuracy: 0.0025,
                                "Supporting plane must touch at both binding and fore edges")
                        }
                    }
                }
            }
        }
    }
    func testClosedPrintedSpineLiesOutsideOpaqueSpineBody() throws {
        let scene = BookPreviewScene.make(project:project(),workingLayers:false,open:false,angle:0,
            leftPage:nil,rightPage:1,pageCount:21,spreadIndex:0,leftTexture:nil,rightTexture:nil,
            margins:false,thumbMode:.off,leftPageSettings:PageSettings(),rightPageSettings:PageSettings(),
            preset:.spine,revisionID:UUID(),binding:.hardcover)
        let root = try XCTUnwrap(scene.rootNode.childNode(withName:"physical-book.root",recursively:false))
        let body = try XCTUnwrap(root.childNode(withName:"book-shell.spine",recursively:false))
        let artwork = try XCTUnwrap(root.childNode(withName:"book-shell.spine-artwork",recursively:false))
        XCTAssertFalse(artwork.isHidden)
        XCTAssertLessThan(artwork.position.x,body.position.x+body.boundingBox.min.x,
                          "Spine artwork inside its opaque case is invisible")
        XCTAssertTrue(artwork.geometry?.firstMaterial?.diffuse.contents is NSImage)
    }

}
