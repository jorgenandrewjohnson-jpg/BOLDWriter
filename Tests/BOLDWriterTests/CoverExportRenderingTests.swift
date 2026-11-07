import AppKit
import XCTest
@testable import BOLDWriter

final class CoverExportRenderingTests:XCTestCase {
    func testFinalExportRendersClipAndOmitsTemplateAndGuideOverlays() throws {
        let red=try CoverEditorEngine.filledImage(width:16,height:16,color:.red),blue=try CoverEditorEngine.filledImage(width:16,height:16,color:.blue),yellow=try CoverEditorEngine.filledImage(width:16,height:16,color:.yellow)
        let base=try CoverArtwork.imageLayer(data:red,filename:"base",frame:CoverRect(x:0.25,y:0.25,width:0.5,height:0.5))
        var clip=try CoverArtwork.imageLayer(data:blue,filename:"clipped",frame:CoverRect());clip.clippedToLayerID=base.id
        var template=try CoverArtwork.imageLayer(data:yellow,filename:"template",frame:CoverRect());template.kind = .template
        var p=CoverProject(width:1,height:1);p.dpi=16;p.backgroundHex="#FFFFFF";p.layers=[base,clip,template];p.userGuidesX=[0.5];p.guidesVisible=true
        let final=try CoverArtwork.export(p,format:"png");let proof=try CoverArtwork.export(p,format:"png",proof:true)
        XCTAssertGreaterThan(try CoverEditorEngine.sampledColor(imageData:final,at:CGPoint(x:8,y:8)).blueComponent,0.7)
        let finalBackground=try CoverEditorEngine.sampledColor(imageData:final,at:CGPoint(x:1,y:1));XCTAssertGreaterThan(finalBackground.redComponent,0.9);XCTAssertGreaterThan(finalBackground.greenComponent,0.9);XCTAssertGreaterThan(finalBackground.blueComponent,0.9)
        XCTAssertNotEqual(proof,final)
        XCTAssertEqual(template.imageData,yellow);XCTAssertEqual(base.imageData,red)
    }

    func testTransparentPNGExportPreservesRasterMaskAlpha() throws {
        let red = try CoverEditorEngine.filledImage(width: 16, height: 16, color: .red)
        var layer = try CoverArtwork.imageLayer(
            data: red,
            filename: "masked subject",
            frame: CoverRect()
        )
        let mask = CoverEditorEngine.rectangleSelection(
            width: 16,
            height: 16,
            rect: CGRect(x: 0, y: 0, width: 8, height: 16)
        )
        layer.maskData = try XCTUnwrap(
            CoverEditorEngine.encodedMask(mask, width: 16, height: 16)
        )
        var project = CoverProject(width: 1, height: 1)
        project.dpi = 16
        project.backgroundHex = "#FFFFFF"
        project.layers = [layer]

        let opaqueData = try CoverArtwork.export(project, format: "png")
        let transparentData = try CoverArtwork.export(project, format: "png-transparent")
        let opaque = try XCTUnwrap(NSBitmapImageRep(data: opaqueData))
        let transparent = try XCTUnwrap(NSBitmapImageRep(data: transparentData))

        XCTAssertEqual(transparent.pixelsWide, 16)
        XCTAssertEqual(transparent.pixelsHigh, 16)
        let kept = try XCTUnwrap(transparent.colorAt(x: 4, y: 8))
            .usingColorSpace(.deviceRGB)
        let maskedOut = try XCTUnwrap(transparent.colorAt(x: 12, y: 8))
            .usingColorSpace(.deviceRGB)
        let opaqueBackground = try XCTUnwrap(opaque.colorAt(x: 12, y: 8))
            .usingColorSpace(.deviceRGB)

        XCTAssertGreaterThan(try XCTUnwrap(kept).redComponent, 0.9)
        XCTAssertGreaterThan(try XCTUnwrap(kept).alphaComponent, 0.9)
        XCTAssertLessThan(try XCTUnwrap(maskedOut).alphaComponent, 0.05)
        XCTAssertGreaterThan(try XCTUnwrap(opaqueBackground).alphaComponent, 0.9)
    }
}
