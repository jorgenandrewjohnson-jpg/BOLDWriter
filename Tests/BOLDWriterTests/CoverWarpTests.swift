import XCTest
@testable import BOLDWriter

final class CoverWarpTests:XCTestCase{
    func testArchAndFlagProduceDistinctDeterministicSpatialOutputAndPreserveSource()throws{
        var gradient=CoverLayer(kind:.gradient,name:"gradient",frame:CoverRect());gradient.fillHex="#FF0000";gradient.gradientEndHex="#0000FF"
        let sourceData=try XCTUnwrap(CoverArtwork.render({var p=CoverProject(width:1,height:1);p.dpi=32;p.layers=[gradient];return p}(),scale:32).tiffRepresentation)
        let source=NSImage(data:sourceData)!
        let arch=CoverEditorEngine.warpedImage(source,preset:.arch,amount:0.8),flag=CoverEditorEngine.warpedImage(source,preset:.flag,amount:0.8)
        XCTAssertNotEqual(try XCTUnwrap(arch.tiffRepresentation),sourceData)
        XCTAssertNotEqual(try XCTUnwrap(flag.tiffRepresentation),sourceData)
        XCTAssertEqual(try XCTUnwrap(CoverEditorEngine.warpedImage(source,preset:.flag,amount:0.8).tiffRepresentation),try XCTUnwrap(flag.tiffRepresentation))
    }
    func testWarpPersistsAndAffectsFinalPNGButNotCanvasDimensions()throws{
        var gradient=CoverLayer(kind:.gradient,name:"gradient",frame:CoverRect());gradient.fillHex="#FF0000";gradient.gradientEndHex="#0000FF"
        let sourceData=try XCTUnwrap(CoverArtwork.render({var p=CoverProject(width:2,height:1);p.dpi=32;p.layers=[gradient];return p}(),scale:32).tiffRepresentation)
        let source=try CoverArtwork.imageLayer(data:sourceData,filename:"art",frame:CoverRect())
        var project=CoverProject(width:2,height:1);project.dpi=32;project.layers=[source]
        let baseline=try CoverArtwork.export(project,format:"png")
        project.layers[0].warpPreset = .flag;project.layers[0].warpAmount = -0.7
        let final=try CoverArtwork.export(project,format:"png")
        XCTAssertNotEqual(final,baseline);XCTAssertEqual(project.canvasWidth,2);XCTAssertEqual(project.layers[0].imageData,sourceData)
        let decoded=try JSONDecoder().decode(CoverProject.self,from:JSONEncoder().encode(project))
        XCTAssertEqual(decoded.layers[0].warpPreset,.flag);XCTAssertEqual(decoded.layers[0].warpAmount,-0.7)
    }
}
