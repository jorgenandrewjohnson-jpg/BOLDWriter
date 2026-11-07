import AppKit
import XCTest
@testable import BOLDWriter

final class CoverRetouchingTests: XCTestCase {
    func testLocalHealingReplacesSmallDarkBlemishOnUniformLightBackground() throws {
        let white=try CoverEditorEngine.filledImage(width:40,height:40,color:.white),blemish=try CoverEditorEngine.paint(imageData:white,points:[CGPoint(x:20,y:20)],color:.black,diameter:6)
        let cleaned=try CoverEditorEngine.heal(imageData:blemish,center:CGPoint(x:20,y:20),diameter:8)
        XCTAssertGreaterThan(try XCTUnwrap(CoverEditorEngine.sampledColor(imageData:cleaned,at:CGPoint(x:20,y:20)).usingColorSpace(.deviceRGB)).redComponent,0.8)
    }

    func testBurnDarkensWhileDodgeLightens() throws {
        let gray=try CoverEditorEngine.filledImage(width:24,height:24,color:NSColor(white:0.55,alpha:1)),point=CGPoint(x:12,y:12)
        let light=try CoverEditorEngine.dodgeBurn(imageData:gray,at:[point],diameter:10,strength:0.3,lighten:true),dark=try CoverEditorEngine.dodgeBurn(imageData:gray,at:[point],diameter:10,strength:0.3,lighten:false)
        XCTAssertGreaterThan(try XCTUnwrap(CoverEditorEngine.sampledColor(imageData:light,at:point).usingColorSpace(.deviceRGB)).redComponent,0.55)
        XCTAssertLessThan(try XCTUnwrap(CoverEditorEngine.sampledColor(imageData:dark,at:point).usingColorSpace(.deviceRGB)).redComponent,0.55)
    }
}
