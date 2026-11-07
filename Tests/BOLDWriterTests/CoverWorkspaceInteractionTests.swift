import XCTest
@testable import BOLDWriter

final class CoverWorkspaceInteractionTests:XCTestCase{
    func testRotatedPanAndCursorZoomAreViewportOnlyAndRoundTripCoordinates(){
        var view=CoverViewport(zoom:1.4,pan:CGPoint(x:12,y:-5),rotation:31)
        let point=CGPoint(x:120,y:80),center=CGPoint(x:240,y:180),document=view.documentPoint(for:point,center:center)
        let pan=CGSize(width:26,height:-11);view.panBy(pan);let movedPointer=CGPoint(x:point.x+pan.width,y:point.y+pan.height)
        XCTAssertEqual(view.documentPoint(for:movedPointer,center:center).x,document.x,accuracy:1e-8)
        view.zoomAt(movedPointer,center:center,factor:1.75)
        let anchored=view.viewPoint(for:document,center:center)
        XCTAssertEqual(anchored.x,movedPointer.x,accuracy:1e-6);XCTAssertEqual(anchored.y,movedPointer.y,accuracy:1e-6)
        let layer=CoverLayer(kind:.shape,name:"unchanged",frame:CoverRect(x:0.2,y:0.3,width:0.4,height:0.2))
        view.rotateBy(-17);view.reset();XCTAssertEqual(layer.frame.x,0.2);XCTAssertEqual(layer.rotation,0)
    }
    func testUnitNudgeUsesProjectCoordinatesAndLeavesLockedLayerFixed(){
        let movable=CoverLayer(kind:.shape,name:"move",frame:CoverRect(x:0.2,y:0.2,width:0.1,height:0.1))
        var locked=CoverLayer(kind:.shape,name:"locked",frame:CoverRect(x:0.5,y:0.2,width:0.1,height:0.1));locked.locked=true
        let before=locked.frame;var layers=[movable,locked]
        CoverEditorEngine.nudgeLayers(&layers,ids:Set(layers.map{$0.id}),dx:1/6,dy:0)
        XCTAssertEqual(layers[0].frame.x,0.2+1/6,accuracy:1e-8);XCTAssertEqual(layers[1].frame,before)
    }
}
