import XCTest
@testable import BOLDWriter

final class CoverTransformTests: XCTestCase {
    func testNonDestructiveCropSkewPerspectiveAndCommonTransformsPersist() throws {
        var layer=CoverLayer(kind:.image,name:"Mockup",frame:CoverRect(x:0.2,y:0.2,width:0.5,height:0.4));layer.imageData=Data([1,2,3]);layer.sourceCrop=CoverRect(x:0.1,y:0.2,width:0.7,height:0.6);layer.skewX=0.12;layer.skewY = -0.04
        layer.perspectiveCorners=[CoverPathPoint(x:0.1,y:0),CoverPathPoint(x:0.9,y:0.08),CoverPathPoint(x:1,y:1),CoverPathPoint(x:0,y:0.9)]
        let before=layer;CoverEditorEngine.rotate(&layer,degrees:90);CoverEditorEngine.rotate(&layer,degrees:-90)
        XCTAssertEqual(layer.rotation,before.rotation);XCTAssertEqual(layer.imageData,before.imageData);XCTAssertEqual(layer.sourceCrop,before.sourceCrop);XCTAssertEqual(layer.perspectiveCorners,before.perspectiveCorners)
        let roundTrip=try JSONDecoder().decode(CoverLayer.self,from:JSONEncoder().encode(layer));XCTAssertEqual(roundTrip.skewX,0.12);XCTAssertEqual(roundTrip.sourceCrop,before.sourceCrop)
    }

    func testCropRectIsClampedToCanvasAndRejectsEmptyCrop() {
        let crop=CoverEditorEngine.cropSourceRect(layer:CoverLayer(kind:.image,name:"Photo"),canvasDrag:CGRect(x:80,y:60,width:50,height:50),canvasSize:CGSize(width:100,height:100),imagePixels:CGSize(width:400,height:300))
        XCTAssertEqual(try XCTUnwrap(crop).x,0.8,accuracy:0.00001);XCTAssertEqual(crop?.width ?? 0,0.2,accuracy:0.00001);XCTAssertEqual(crop?.height ?? 0,0.4,accuracy:0.00001)
        XCTAssertNil(CoverEditorEngine.cropSourceRect(layer:CoverLayer(kind:.image,name:"Photo"),canvasDrag:.zero,canvasSize:.zero,imagePixels:.zero))
        let offset=CoverLayer(kind:.image,name:"Offset",frame:CoverRect(x:0.25,y:0.2,width:0.5,height:0.5))
        let local=CoverEditorEngine.cropSourceRect(layer:offset,canvasDrag:CGRect(x:35,y:30,width:20,height:20),canvasSize:CGSize(width:100,height:100),imagePixels:CGSize(width:400,height:300))
        XCTAssertEqual(local?.x ?? -1,0.2,accuracy:0.0001);XCTAssertEqual(local?.y ?? -1,0.2,accuracy:0.0001);XCTAssertEqual(local?.width ?? 0,0.4,accuracy:0.0001)
    }

    func testPerspectiveMetadataChangesRenderedSourceWithoutChangingOriginalBytes() throws {
        let bytes=try CoverEditorEngine.filledImage(width:24,height:24,color:.red)
        var layer=try CoverArtwork.imageLayer(data:bytes,filename:"perspective",frame:CoverRect())
        var p=CoverProject(width:1,height:1);p.dpi=24;p.layers=[layer]
        let straight=try XCTUnwrap(CoverArtwork.render(p,scale:24).tiffRepresentation)
        layer.perspectiveCorners=[CoverPathPoint(x:0.2,y:0),CoverPathPoint(x:0.8,y:0.1),CoverPathPoint(x:1,y:1),CoverPathPoint(x:0,y:0.9)];p.layers=[layer]
        let transformed=try XCTUnwrap(CoverArtwork.render(p,scale:24).tiffRepresentation)
        XCTAssertNotEqual(transformed,straight);XCTAssertEqual(layer.imageData,bytes)
    }

    func testArchAndFlagWarpChangeRenderedPixelsButRetainSource() throws {
        var gradient=CoverLayer(kind:.gradient,name:"gradient",frame:CoverRect());gradient.fillHex="#FF0000";gradient.gradientEndHex="#0000FF"
        var fixture=CoverProject(width:1,height:1);fixture.dpi=48;fixture.layers=[gradient]
        let bytes=try XCTUnwrap(CoverArtwork.render(fixture,scale:48).tiffRepresentation)
        let source=NSImage(data:bytes)!
        let arch=CoverEditorEngine.warpedImage(source,preset:.arch,amount:0.8)
        let flag=CoverEditorEngine.warpedImage(source,preset:.flag,amount:0.8)
        XCTAssertNotEqual(try XCTUnwrap(arch.tiffRepresentation),try XCTUnwrap(source.tiffRepresentation))
        XCTAssertNotEqual(try XCTUnwrap(flag.tiffRepresentation),try XCTUnwrap(source.tiffRepresentation))
        var layer=try CoverArtwork.imageLayer(data:bytes,filename:"warp",frame:CoverRect())
        layer.warpPreset = .arch;layer.warpAmount=0.8
        var project=CoverProject(width:1,height:1);project.dpi=48;project.layers=[layer]
        XCTAssertNotEqual(try XCTUnwrap(CoverArtwork.render(project,scale:48).tiffRepresentation),try XCTUnwrap(CoverArtwork.render({var p=project;p.layers[0].warpPreset=nil;return p}(),scale:48).tiffRepresentation))
        XCTAssertEqual(layer.imageData,bytes)
    }
}
