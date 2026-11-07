import XCTest
@testable import BOLDWriter

final class CoverTransformInteractionTests:XCTestCase{
    func testCornerEdgeAndCenterScalePreserveMultiLayerRelativeGeometry(){
        let a=CoverLayer(kind:.shape,name:"a",frame:CoverRect(x:0.1,y:0.2,width:0.2,height:0.2))
        let b=CoverLayer(kind:.text,name:"b",frame:CoverRect(x:0.5,y:0.4,width:0.2,height:0.2))
        var layers=[a,b];let ids=Set(layers.map{$0.id}),bounds=CGRect(x:0.1,y:0.2,width:0.6,height:0.4)
        CoverEditorEngine.scaleLayers(&layers,ids:ids,around:CGPoint(x:bounds.minX,y:bounds.minY),scaleX:2,scaleY:2)
        XCTAssertEqual(layers[0].frame.width,0.4,accuracy:1e-8);XCTAssertEqual(layers[1].frame.x,0.9,accuracy:1e-8)
        XCTAssertEqual((layers[1].frame.x-layers[0].frame.x)/layers[0].frame.width,2,accuracy:1e-8)
        CoverEditorEngine.scaleLayers(&layers,ids:ids,around:CGPoint(x:0.5,y:0.5),scaleX:0.5,scaleY:1)
        XCTAssertEqual(layers[0].frame.x+layers[0].frame.width/2,0.4,accuracy:1e-8)
    }
    func testPerspectiveAndWarpMetadataAreUndoableThroughProjectSnapshots()throws{
        let bytes=try CoverEditorEngine.filledImage(width:16,height:16,color:.blue)
        var image=try CoverArtwork.imageLayer(data:bytes,filename:"source");let before=image
        image.warpPreset = .flag;image.warpAmount = -0.45;image.perspectiveCorners=[CoverPathPoint(x:0.1,y:0),CoverPathPoint(x:0.9,y:0.1),CoverPathPoint(x:1,y:1),CoverPathPoint(x:0,y:0.9)]
        let reopened=try JSONDecoder().decode(CoverLayer.self,from:JSONEncoder().encode(image))
        XCTAssertEqual(reopened.warpPreset,.flag);XCTAssertEqual(reopened.warpAmount,-0.45);XCTAssertEqual(reopened.imageData,before.imageData)
    }
    func testRotateLayersRotatesGroupGeometryAroundSelectionCenter(){
        let a=CoverLayer(kind:.shape,name:"a",frame:CoverRect(x:0.1,y:0.4,width:0.2,height:0.2)),b=CoverLayer(kind:.shape,name:"b",frame:CoverRect(x:0.7,y:0.4,width:0.2,height:0.2));var layers=[a,b]
        CoverEditorEngine.rotateLayers(&layers,ids:Set(layers.map{$0.id}),around:CGPoint(x:0.5,y:0.5),degrees:90)
        XCTAssertEqual(layers[0].frame.y+layers[0].frame.height/2,0.2,accuracy:0.0001);XCTAssertEqual(layers[1].frame.y+layers[1].frame.height/2,0.8,accuracy:0.0001)
        XCTAssertEqual(layers[0].rotation,90);XCTAssertEqual(layers[1].rotation,90)
    }
}
