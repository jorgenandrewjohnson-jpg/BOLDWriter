import AppKit
import XCTest
@testable import BOLDWriter

final class CoverCropTests: XCTestCase {
    func testSourceCropIsNonDestructiveAndFinalRendererUsesIt() throws {
        let source=try CoverEditorEngine.filledImage(width:32,height:16,color:.red)
        var layer=try CoverArtwork.imageLayer(data:source,filename:"Original",frame:CoverRect(x:0,y:0,width:1,height:1));layer.sourceCrop=CoverRect(x:0.25,y:0,width:0.5,height:1)
        XCTAssertEqual(layer.imageData,source)
        var p=CoverProject(width:1,height:1);p.dpi=32;p.layers=[layer]
        XCTAssertNotNil(try CoverArtwork.render(p).tiffRepresentation)
        let decoded=try JSONDecoder().decode(CoverLayer.self,from:JSONEncoder().encode(layer));XCTAssertEqual(decoded.imageData,source);XCTAssertEqual(decoded.sourceCrop,layer.sourceCrop)
    }
}
