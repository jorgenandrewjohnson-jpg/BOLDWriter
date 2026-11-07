import AppKit
import XCTest
@testable import BOLDWriter

final class CoverClippingMaskTests:XCTestCase {
    func testClippedRasterRendersOnlyInsideBaseAlphaAndTracksBaseEdits() throws {
        let red=try CoverEditorEngine.filledImage(width:16,height:16,color:.red)
        let blue=try CoverEditorEngine.filledImage(width:16,height:16,color:.blue)
        var base=try CoverArtwork.imageLayer(data:red,filename:"Base",frame:CoverRect(x:0.25,y:0.25,width:0.5,height:0.5))
        let textureID=UUID();var texture=try CoverArtwork.imageLayer(data:blue,filename:"Texture",frame:CoverRect());texture.id=textureID;texture.clippedToLayerID=base.id
        var project=CoverProject(width:1,height:1);project.canvasWidth=1;project.canvasHeight=1;project.dpi=16;project.layers=[base,texture]
        var rendered=try XCTUnwrap(CoverArtwork.render(project,scale:16).tiffRepresentation)
        XCTAssertGreaterThan(try CoverEditorEngine.sampledColor(imageData:rendered,at:CGPoint(x:8,y:8)).blueComponent,0.8)
        XCTAssertGreaterThan(try CoverEditorEngine.sampledColor(imageData:rendered,at:CGPoint(x:1,y:1)).redComponent,0.8)
        base.frame=CoverRect(x:0,y:0,width:0.25,height:0.25);project.layers[0]=base
        rendered=try XCTUnwrap(CoverArtwork.render(project,scale:16).tiffRepresentation)
        XCTAssertGreaterThan(try CoverEditorEngine.sampledColor(imageData:rendered,at:CGPoint(x:1,y:1)).blueComponent,0.8)
        XCTAssertGreaterThan(try CoverEditorEngine.sampledColor(imageData:rendered,at:CGPoint(x:8,y:8)).redComponent,0.8)
    }

    func testInvalidCrossGroupClipFailsSafelyAndValidRelationshipPersists() throws {
        var base=CoverLayer(kind:.shape,name:"base");let groupID=UUID();base.groupID=groupID
        var clip=CoverLayer(kind:.shape,name:"clip");clip.clippedToLayerID=base.id
        XCTAssertNotEqual(base.groupID,clip.groupID)
        let value=try JSONDecoder().decode(CoverLayer.self,from:JSONEncoder().encode(clip));XCTAssertEqual(value.clippedToLayerID,base.id)
        let red=try CoverEditorEngine.filledImage(width:12,height:12,color:.red),blue=try CoverEditorEngine.filledImage(width:12,height:12,color:.blue)
        base=try CoverArtwork.imageLayer(data:red,filename:"group base",frame:CoverRect(x:0.2,y:0.2,width:0.3,height:0.3));base.groupID=groupID
        clip=try CoverArtwork.imageLayer(data:blue,filename:"outside group",frame:CoverRect());clip.clippedToLayerID=base.id
        var p=CoverProject(width:1,height:1);p.dpi=12;p.layers=[base,clip]
        let output=try XCTUnwrap(CoverArtwork.render(p,scale:12).tiffRepresentation)
        XCTAssertGreaterThan(try CoverEditorEngine.sampledColor(imageData:output,at:CGPoint(x:10,y:10)).blueComponent,0.8)
    }
}
