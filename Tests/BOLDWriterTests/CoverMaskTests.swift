import AppKit
import AppKit
import XCTest
@testable import BOLDWriter

final class CoverMaskTests:XCTestCase {
    func testDisabledMaskDensityOffsetInvertAndApplyHaveDeterministicPixels() throws {
        let blue=try CoverEditorEngine.filledImage(width:8,height:8,color:.blue)
        let half=Data((0..<64).map{$0<32 ? UInt8(255):UInt8(0)})
        var layer=try CoverArtwork.imageLayer(data:blue,filename:"Blue",frame:CoverRect())
        layer.maskData=CoverEditorEngine.encodedMask(Data(repeating:0,count:64),width:8,height:8)
        XCTAssertNotNil(layer.maskData)
        let direct=try CoverEditorEngine.applyRasterMask(blue,maskImageData:try XCTUnwrap(layer.maskData))
        XCTAssertLessThan(try CoverEditorEngine.sampledColor(imageData:direct,at:CGPoint(x:3,y:3)).blueComponent,0.1)
        let whiteMask=try XCTUnwrap(CoverEditorEngine.encodedMask(Data(repeating:255,count:64),width:8,height:8))
        let partial=try CoverEditorEngine.applyRasterMask(blue,maskImageData:whiteMask,density:0.5)
        XCTAssertEqual(try CoverEditorEngine.sampledColor(imageData:partial,at:CGPoint(x:3,y:3)).alphaComponent,0.5,accuracy:0.04)
        var project=CoverProject(width:1,height:1);project.canvasWidth=1;project.canvasHeight=1;project.dpi=8;project.layers=[layer]
        let masked=try XCTUnwrap(CoverArtwork.render(project,scale:8).tiffRepresentation)
        XCTAssertGreaterThan(try CoverEditorEngine.sampledColor(imageData:masked,at:CGPoint(x:3,y:3)).redComponent,0.9)
        project.layers[0].maskEnabled=false
        XCTAssertEqual(project.layers[0].imageData,blue)
        let unmasked=try XCTUnwrap(CoverArtwork.render(project,scale:8).tiffRepresentation)
        XCTAssertGreaterThan(try CoverEditorEngine.sampledColor(imageData:unmasked,at:CGPoint(x:3,y:3)).blueComponent,0.9)
        let full=Data(repeating:255,count:64)
        XCTAssertEqual(CoverEditorEngine.inverted(full),Data(repeating:0,count:64))
        let shifted=CoverEditorEngine.offsetMask(full,width:8,height:8,dx:2,dy:1)
        XCTAssertEqual(shifted[0],0);XCTAssertEqual(shifted[10],255)
        XCTAssertEqual(CoverEditorEngine.refineMask(full,width:8,height:8,density:0.5)[0],128)
        let applied=try CoverEditorEngine.applyMask(blue,mask:half,width:8,height:8)
        XCTAssertEqual(try CoverEditorEngine.sampledColor(imageData:applied,at:CGPoint(x:1,y:1)).alphaComponent,1,accuracy:0.01)
        XCTAssertEqual(try CoverEditorEngine.sampledColor(imageData:applied,at:CGPoint(x:6,y:6)).alphaComponent,0,accuracy:0.01)
    }

    func testMaskLinkDensityAndEnabledStatePersistAndOldPayloadDecodes() throws {
        var layer=CoverLayer(kind:.image,name:"mask",frame:CoverRect());layer.maskData=Data([1,2]);layer.maskEnabled=false;layer.maskLinked=false;layer.maskOffsetX=0.2;layer.maskDensity=0.75
        let data=try JSONEncoder().encode(layer);let reopened=try JSONDecoder().decode(CoverLayer.self,from:data)
        XCTAssertFalse(try XCTUnwrap(reopened.maskEnabled));XCTAssertFalse(try XCTUnwrap(reopened.maskLinked));XCTAssertEqual(reopened.maskOffsetX,0.2);XCTAssertEqual(reopened.maskDensity,0.75)
        var object=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(CoverProject())) as? [String:Any])
        for key in ["snapGuides","snapGrid","snapBounds","snapLayers","warpPreset","warpAmount"]{object.removeValue(forKey:key)}
        XCTAssertNoThrow(try JSONDecoder().decode(CoverProject.self,from:JSONSerialization.data(withJSONObject:object)))
    }

    func testMaskCompositingPreservesExistingSourceTransparency() throws {
        var sourceBytes = Data(count: 8)
        let sourceImage = try XCTUnwrap(sourceBytes.withUnsafeMutableBytes { storage -> CGImage? in
            guard let context = CGContext(
                data: storage.baseAddress, width: 2, height: 1,
                bitsPerComponent: 8, bytesPerRow: 8,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            context.setFillColor(NSColor(srgbRed: 0.86, green: 0.12, blue: 0.16, alpha: 0.5).cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
            context.setFillColor(NSColor(srgbRed: 0.1, green: 0.4, blue: 0.9, alpha: 1).cgColor)
            context.fill(CGRect(x: 1, y: 0, width: 1, height: 1))
            return context.makeImage()
        })
        let sourceBitmap = NSBitmapImageRep(cgImage: sourceImage)
        let sourcePNG = try XCTUnwrap(sourceBitmap.representation(using: .png, properties: [:]))
        let opaqueMask = try XCTUnwrap(
            CoverEditorEngine.encodedMask(Data(repeating: 255, count: 2), width: 2, height: 1)
        )

        let originalAlpha = try CoverEditorEngine.sampledColor(
            imageData: sourcePNG, at: CGPoint(x: 0, y: 0)
        ).alphaComponent
        XCTAssertEqual(originalAlpha, 0.5, accuracy: 0.02,
                       "The source fixture must contain a half-transparent pixel.")

        let maskedPNG = try CoverEditorEngine.applyRasterMask(
            sourcePNG, maskImageData: opaqueMask
        )
        let maskedAlpha = try CoverEditorEngine.sampledColor(
            imageData: maskedPNG, at: CGPoint(x: 0, y: 0)
        ).alphaComponent
        XCTAssertEqual(maskedAlpha, 0.5, accuracy: 0.02,
                       "A white raster mask must preserve source alpha rather than make it opaque.")
    }
}
