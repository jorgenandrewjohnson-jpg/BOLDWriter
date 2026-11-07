import XCTest
@testable import BOLDWriter

final class CoverRulerGuideTests:XCTestCase{
    func testRulerGuideCoordinatesPersistAndDoNotChangeLayerGeometry()throws{
        var project=CoverProject(width:6,height:9);let layer=CoverLayer(kind:.shape,name:"art",frame:CoverRect(x:0.2,y:0.3,width:0.4,height:0.2));project.layers=[layer]
        project.userGuidesX=[1.25];project.userGuidesY=[4.5]
        let data=try JSONEncoder().encode(project),decoded=try JSONDecoder().decode(CoverProject.self,from:data)
        XCTAssertEqual(decoded.userGuidesX,[1.25]);XCTAssertEqual(decoded.userGuidesY,[4.5]);XCTAssertEqual(decoded.layers[0].frame,layer.frame)
        project.userGuidesX?[0]=2.75;project.userGuidesY?.remove(at:0)
        XCTAssertEqual(project.userGuidesX?[0],2.75);XCTAssertTrue(project.userGuidesY?.isEmpty == true);XCTAssertEqual(project.layers[0].frame,layer.frame)
    }
    func testSnapTargetsCanIndependentlySelectCanvasTrimCoverSpineAndLayerEdges(){
        var p=CoverProject(type:.printFullWrap,width:12,height:9);p.backWidth=5;p.spineWidth=1;p.trimWidth=5;p.bleed=0.25
        p.snapGuides=false;p.snapGrid=false;p.snapCanvasEdges=false;p.snapCanvasCenter=false;p.snapTrim=false;p.snapBleed=false;p.snapFrontCover=false;p.snapBackCover=false;p.snapSpine=false;p.snapLayerEdges=false;p.snapLayerCenters=false
        var layer=CoverLayer(kind:.shape,name:"moving",frame:CoverRect(x:0.48,y:0.3,width:0.05,height:0.1))
        p.snapCanvasCenter=true
        let canvas=CoverEditorEngine.snap(layer.frame,layerID:layer.id,project:p,displayedCanvas:CGSize(width:1200,height:900))
        XCTAssertEqual(canvas.frame.x,0.475,accuracy:0.0001)
        p.snapCanvasCenter=false;p.snapSpine=true;layer.frame.x=0.454
        let spine=CoverEditorEngine.snap(layer.frame,layerID:layer.id,project:p,displayedCanvas:CGSize(width:1200,height:900))
        XCTAssertEqual(spine.frame.x,0.4541667,accuracy:0.0001)
        layer.frame.x=0.48;let target=CoverLayer(kind:.shape,name:"target",frame:CoverRect(x:0.535,y:0.3,width:0.1,height:0.1));p.snapSpine=false;p.snapLayerEdges=true
        let other=CoverEditorEngine.snap(layer.frame,layerID:layer.id,project:p,displayedCanvas:CGSize(width:1200,height:900),otherLayers:[target])
        XCTAssertEqual(other.frame.x,0.485,accuracy:0.0001)
    }
}
