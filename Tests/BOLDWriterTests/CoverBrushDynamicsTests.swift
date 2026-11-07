import AppKit
import XCTest
@testable import BOLDWriter

final class CoverBrushDynamicsTests: XCTestCase {
    func testHardnessFlowAndOpacityChangeRasterStroke() throws {
        let base=try CoverEditorEngine.filledImage(width:32,height:32,color:.white),point=CGPoint(x:16,y:16)
        let hard=try CoverEditorEngine.paint(imageData:base,points:[point],color:.black,diameter:20,hardness:1)
        let soft=try CoverEditorEngine.paint(imageData:base,points:[point],color:.black,diameter:20,hardness:0)
        let lowFlow=try CoverEditorEngine.paint(imageData:base,points:[point],color:.black,diameter:20,flow:0.2)
        let edge=CGPoint(x:24,y:16),hardEdge=try XCTUnwrap(CoverEditorEngine.sampledColor(imageData:hard,at:edge).usingColorSpace(.deviceRGB)).redComponent,softEdge=try XCTUnwrap(CoverEditorEngine.sampledColor(imageData:soft,at:edge).usingColorSpace(.deviceRGB)).redComponent
        XCTAssertLessThan(hardEdge,softEdge);XCTAssertGreaterThan(try XCTUnwrap(CoverEditorEngine.sampledColor(imageData:lowFlow,at:point).usingColorSpace(.deviceRGB)).redComponent,0.7)
    }

    func testCloneStampKeepsSourceOffsetAcrossDestinationStroke() throws {
        let base = try CoverEditorEngine.filledImage(width:40,height:32,color:.white)
        let sourceArtwork = try CoverEditorEngine.paint(
            imageData:base,
            points:[CGPoint(x:6,y:16)],
            color:.black,
            diameter:6
        )

        let cloned = try CoverEditorEngine.clone(
            imageData:sourceArtwork,
            source:CGPoint(x:6,y:16),
            destinationPoints:[CGPoint(x:18,y:16),CGPoint(x:24,y:16)],
            diameter:4,
            destinationOrigin:CGPoint(x:18,y:16)
        )

        let first = try XCTUnwrap(CoverEditorEngine.sampledColor(imageData:cloned,at:CGPoint(x:18,y:16)).usingColorSpace(.deviceRGB))
        let second = try XCTUnwrap(CoverEditorEngine.sampledColor(imageData:cloned,at:CGPoint(x:24,y:16)).usingColorSpace(.deviceRGB))
        XCTAssertLessThan(first.redComponent,0.1)
        XCTAssertGreaterThan(second.redComponent,0.9)
    }

    func testCloneStampHonorsOpacityFlowAndSelectionMask() throws {
        let base = try CoverEditorEngine.filledImage(width:32,height:32,color:.white)
        let sourceArtwork = try CoverEditorEngine.paint(
            imageData:base,
            points:[CGPoint(x:6,y:16)],
            color:.black,
            diameter:6
        )
        var selection = Data(repeating:0,count:32*32)
        selection[16*32+18] = 255

        let cloned = try CoverEditorEngine.clone(
            imageData:sourceArtwork,
            source:CGPoint(x:6,y:16),
            destinationPoints:[CGPoint(x:18,y:16)],
            diameter:8,
            opacity:0.5,
            destinationOrigin:CGPoint(x:18,y:16),
            flow:0.5,
            selection:selection
        )

        let center = try XCTUnwrap(CoverEditorEngine.sampledColor(imageData:cloned,at:CGPoint(x:18,y:16)).usingColorSpace(.deviceRGB))
        let outside = try XCTUnwrap(CoverEditorEngine.sampledColor(imageData:cloned,at:CGPoint(x:19,y:16)).usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(center.redComponent,0.7)
        XCTAssertLessThan(center.redComponent,1)
        XCTAssertGreaterThan(outside.redComponent,0.98)
    }
}
