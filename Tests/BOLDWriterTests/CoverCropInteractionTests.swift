import XCTest
@testable import BOLDWriter

final class CoverCropInteractionTests:XCTestCase{
    func testInteractiveCropSelectionComposesOnExistingSourceCropWithoutChangingFrameOrPixels()throws{
        let bytes=try CoverEditorEngine.filledImage(width:20,height:20,color:.green)
        var layer=try CoverArtwork.imageLayer(data:bytes,filename:"crop",frame:CoverRect(x:0.1,y:0.2,width:0.7,height:0.6))
        layer.sourceCrop=CoverRect(x:0.1,y:0.1,width:0.8,height:0.8)
        let selected=try XCTUnwrap(CoverEditorEngine.cropSourceRect(layer:layer,canvasDrag:CGRect(x:30,y:30,width:20,height:20),canvasSize:CGSize(width:100,height:100),imagePixels:CGSize(width:20,height:20)))
        let composed=CoverEditorEngine.composeCrop(existing:layer.sourceCrop,selection:selected)
        XCTAssertEqual(composed.x,0.3285714,accuracy:0.0001);XCTAssertEqual(composed.y,0.2333333,accuracy:0.0001)
        XCTAssertEqual(composed.width,0.2285714,accuracy:0.0001);XCTAssertEqual(composed.height,0.2666667,accuracy:0.0001)
        XCTAssertEqual(layer.frame,CoverRect(x:0.1,y:0.2,width:0.7,height:0.6));XCTAssertEqual(layer.imageData,bytes)
    }
    func testCropStraighteningUsesLayerRotationMetadataNotSourcePixelReplacement()throws{
        let bytes=try CoverEditorEngine.filledImage(width:12,height:12,color:.yellow)
        var layer=try CoverArtwork.imageLayer(data:bytes,filename:"straighten");layer.rotation = -2.5
        XCTAssertEqual(layer.rotation,-2.5);XCTAssertEqual(layer.imageData,bytes)
    }
}
