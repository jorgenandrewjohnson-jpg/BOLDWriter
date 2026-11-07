import AppKit
import SceneKit
import XCTest
@testable import BOLDWriter

@MainActor
final class RestingSpineClosureTests: XCTestCase {
    func testFoldWarningsFollowOpenSpineWithoutProtrudingOrChangingMaterialWidth() throws {
        var p = CoverProject(type:.printFullWrap,width:13.05,height:9.25)
        p.trimWidth=6; p.backWidth=6; p.trimHeight=9; p.spineWidth=0.8; p.bleed=0.125; p.dpi=24
        let spine=CoverWrapGeometry(project:p).spineTrim
        var text=CoverLayer(kind:.text,name:"Unsafe spine",frame:CoverRect(x:spine.x-spine.width*0.05,y:spine.y+spine.height*0.2,width:spine.width*0.8,height:spine.height*0.6))
        text.text="UNSAFE"; p.layers=[text]
        for binding in BookBinding.allCases {
            for angle in [0.01,9,45,90,135,171,180] {
                let scene=BookPreviewScene.make(project:p,workingLayers:false,open:true,angle:angle,leftPage:80,rightPage:81,pageCount:160,spreadIndex:40,leftTexture:nil,rightTexture:nil,margins:false,thumbMode:.off,leftPageSettings:PageSettings(),rightPageSettings:PageSettings(),preset:.reading,revisionID:UUID(),binding:binding)
                let root=try XCTUnwrap(scene.rootNode.childNode(withName:"physical-book.root",recursively:true))
                let strip=try XCTUnwrap(root.childNode(withName:"book-shell.spine-artwork",recursively:true))
                XCTAssertEqual(strip.geometry?.elements.count,2)
                XCTAssertFalse(try XCTUnwrap(strip.geometry?.firstMaterial).isDoubleSided)
                XCTAssertTrue(strip.geometry?.materials[1].diffuse.contents is NSColor)
                let warnings=strip.childNodes.filter { $0.name?.hasPrefix("diagnostic.spine.")==true }
                XCTAssertEqual(warnings.count,2)
                for warning in warnings {
                    XCTAssertTrue(warning.isHidden) // Production diagnostics are opt-in.
                    let points=BookOpenGutterGeometry.vertices(try XCTUnwrap(warning.geometry?.sources(for:.vertex).first))
                    XCTAssertEqual(points.count,66)
                    for point in points {
                        let p=warning.convertPosition(point,to:root)
                        XCTAssertGreaterThanOrEqual(p.y,-0.00001)
                        XCTAssertLessThanOrEqual(p.y,6.3+0.00001)
                    }
                    let first=points
                    BookSpineWrapGeometry.update(in:root,depth:CGFloat(PhysicalBookGeometry(project:p).outerBookDepth(for:binding)*0.7))
                    let again=BookOpenGutterGeometry.vertices(try XCTUnwrap(warning.geometry?.sources(for:.vertex).first))
                    for (a,b) in zip(first,again) { XCTAssertEqual(a.x,b.x,accuracy:0.00001); XCTAssertEqual(a.z,b.z,accuracy:0.00001) }
                }
                var presentation=BookStudioPresentation(); presentation.open=true; presentation.cameraPreset = .reading
                BookStudioTransformScene.apply(to:scene,presentation:presentation)
                let floor=try XCTUnwrap(scene.rootNode.childNode(withName:"studio-ground",recursively:true)).position.y
                var minimum=CGFloat.infinity
                root.enumerateChildNodes { node,_ in
                    var ancestor: SCNNode? = node
                    while let current=ancestor,current !== root {
                        if current.isHidden { return }; ancestor=current.parent
                    }
                    guard node.name != "book.left-page-block",node.name != "book.right-page-block",
                        let geometry=node.geometry else { return }
                    for point in BookOpenGutterGeometry.surfaceVertices(geometry) {
                        minimum=min(minimum,node.convertPosition(point,to:scene.rootNode).y)
                    }
                }
                XCTAssertGreaterThanOrEqual(minimum,floor-0.0001)
                XCTAssertEqual(minimum,floor,accuracy:0.002)
                XCTAssertLessThanOrEqual(BookSceneInspection(scene:scene).maximumCoverPenetration,0.0001)
            }
        }
    }
    func testNativeViewportExposesOneAccessibleCanvasRatherThanPrivateSceneKitViews() {
        let view=BookPreviewInteractionView(frame:NSRect(x:0,y:0,width:800,height:600))
        XCTAssertTrue(view.isAccessibilityElement())
        XCTAssertEqual(view.accessibilityRole(),.image)
        XCTAssertEqual(view.accessibilityLabel(),"3D book preview")
        XCTAssertEqual(view.accessibilityChildren()?.count,0)
        XCTAssertTrue(view.accessibilityHelp()?.contains("orbit") == true)
    }
}
