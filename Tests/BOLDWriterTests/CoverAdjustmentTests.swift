import AppKit
import XCTest
@testable import BOLDWriter

final class CoverAdjustmentTests: XCTestCase {
    func testAdjustmentAndFilterStacksRemainEditableAndAffectRenderedPixels() throws {
        let source=try CoverEditorEngine.filledImage(width:32,height:32,color:NSColor(srgbRed:0.3,green:0.5,blue:0.8,alpha:1))
        var layer=try CoverArtwork.imageLayer(data:source,filename:"Source")
        layer.filters=[CoverFilter(kind:.invert,amount:1)]
        let original=layer.imageData;var p=CoverProject(width:1,height:1);p.layers=[layer]
        let image=try CoverArtwork.render(p,scale:32);let rep=try XCTUnwrap(NSBitmapImageRep(data:try XCTUnwrap(image.tiffRepresentation)));let color=try XCTUnwrap(rep.colorAt(x:16,y:16)).usingColorSpace(.deviceRGB)!
        XCTAssertGreaterThan(color.redComponent,0.6);XCTAssertEqual(layer.imageData,original)
        let roundTrip=try JSONDecoder().decode(CoverLayer.self,from:JSONEncoder().encode(layer));XCTAssertEqual(roundTrip.filters,layer.filters)
    }
}
