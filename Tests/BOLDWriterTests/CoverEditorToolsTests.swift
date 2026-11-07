import AppKit
import XCTest
@testable import BOLDWriter

final class CoverEditorToolsTests: XCTestCase {
    private func image(_ color:NSColor = .white) throws -> Data { try CoverEditorEngine.filledImage(width:24,height:24,color:color) }

    func testRectangleLassoAndSelectionModes() {
        let rect=CoverEditorEngine.rectangleSelection(width:10,height:10,rect:CGRect(x:2,y:3,width:4,height:2))
        XCTAssertEqual(rect.filter{$0>0}.count,8)
        let lasso=CoverEditorEngine.lassoSelection(width:10,height:10,points:[CGPoint(x:1,y:1),CGPoint(x:8,y:1),CGPoint(x:8,y:8),CGPoint(x:1,y:8)])
        XCTAssertGreaterThan(lasso.filter{$0>0}.count,rect.filter{$0>0}.count)
        let merged=CoverEditorEngine.combine(rect,lasso,mode:.add)
        XCTAssertEqual(merged.filter{$0>0}.count,lasso.filter{$0>0}.count)
        XCTAssertEqual(CoverEditorEngine.inverted(rect).filter{$0>0}.count,92)
    }

    func testSelectionFeatherAndSavedSelectionPersistence() throws {
        let mask=CoverEditorEngine.rectangleSelection(width:8,height:8,rect:CGRect(x:2,y:2,width:3,height:3))
        let softened=CoverEditorEngine.feather(mask,width:8,height:8,radius:1)
        XCTAssertTrue(softened.contains{ $0 > 0 && $0 < 255 })
        var project=CoverProject();let id=CoverEditorEngine.saveSelection(mask,width:8,height:8,name:"Portrait",into:&project)
        XCTAssertEqual(CoverEditorEngine.loadSelection(try XCTUnwrap(id),from:project)?.mask,mask)
        let data=try JSONEncoder().encode(project);let reopened=try JSONDecoder().decode(CoverProject.self,from:data)
        XCTAssertEqual(reopened.savedSelections?.first?.name,"Portrait")
    }

    func testMagicWandToleranceAndNoncontiguousColorRange() throws {
        let source=try image();let red=try CoverEditorEngine.paint(imageData:source,points:[CGPoint(x:18,y:18)],color:.red,diameter:9)
        let exact=try CoverEditorEngine.colorSelection(imageData:red,sample:CGPoint(x:18,y:18),tolerance:0.03,contiguous:false)
        let loose=try CoverEditorEngine.colorSelection(imageData:red,sample:CGPoint(x:2,y:2),tolerance:0.8,contiguous:true)
        XCTAssertGreaterThan(exact.mask.filter{$0>0}.count,0)
        XCTAssertGreaterThan(loose.mask.filter{$0>0}.count,exact.mask.filter{$0>0}.count)
    }

    func testBrushPaintEraseAndSelectionMask() throws {
        let source=try image();let selection=CoverEditorEngine.rectangleSelection(width:24,height:24,rect:CGRect(x:0,y:0,width:12,height:24))
        let painted=try CoverEditorEngine.paint(imageData:source,points:[CGPoint(x:8,y:12)],color:.blue,diameter:10,selection:selection)
        XCTAssertGreaterThan(try CoverEditorEngine.sampledColor(imageData:painted,at:CGPoint(x:8,y:12)).blueComponent,0.8)
        let erased=try CoverEditorEngine.paint(imageData:painted,points:[CGPoint(x:8,y:12)],color:.black,diameter:8,erase:true)
        XCTAssertLessThan(try CoverEditorEngine.sampledColor(imageData:erased,at:CGPoint(x:8,y:12)).alphaComponent,1)
        let masked=try CoverEditorEngine.applyMask(painted,mask:selection,width:24,height:24)
        XCTAssertLessThan(try CoverEditorEngine.sampledColor(imageData:masked,at:CGPoint(x:20,y:12)).alphaComponent,0.1)
        XCTAssertEqual(try CoverEditorEngine.paint(imageData:source,points:[CGPoint(x:2,y:2)],color:.red,diameter:4,selection:Data([255])),source)
    }

    func testSparseBrushAndEraserDragsProduceContinuousStrokes() throws {
        let points = [CGPoint(x: 2, y: 12), CGPoint(x: 21, y: 12)]
        let painted = try CoverEditorEngine.paint(imageData: image(), points: points,
            color: .black, diameter: 4)
        let erased = try CoverEditorEngine.paint(imageData: painted, points: points,
            color: .black, diameter: 4, erase: true)
        for x in 2...21 {
            let point = CGPoint(x: x, y: 12)
            XCTAssertLessThan(try CoverEditorEngine.sampledColor(imageData: painted, at: point).redComponent, 0.1)
            XCTAssertLessThan(try CoverEditorEngine.sampledColor(imageData: erased, at: point).alphaComponent, 0.1)
        }
        XCTAssertGreaterThan(try CoverEditorEngine.sampledColor(imageData: painted, at: CGPoint(x: 12, y: 2)).redComponent, 0.9)
    }

    func testMaskBrushInterpolatesAndIgnoresOutOfBoundsStrokes() throws {
        let original = Data(repeating: 255, count: 24 * 24)
        let painted = try CoverEditorEngine.paintMask(original, width: 24, height: 24,
            points: [CGPoint(x: 2, y: 12), CGPoint(x: 21, y: 12)], diameter: 4, value: 0)
        for x in 2...21 { XCTAssertEqual(painted[12 * 24 + x], 0) }
        XCTAssertEqual(try CoverEditorEngine.paintMask(original, width: 24, height: 24,
            points: [CGPoint(x: -100, y: -100)], diameter: 4, value: 0), original)
    }

    func testCloneHealingDodgeBurnAndEyedropperArePixelOperations() throws {
        let source=try CoverEditorEngine.paint(imageData:image(),points:[CGPoint(x:6,y:6)],color:.red,diameter:7)
        let clone=try CoverEditorEngine.clone(imageData:source,source:CGPoint(x:6,y:6),destinationPoints:[CGPoint(x:17,y:17)],diameter:6)
        XCTAssertGreaterThan(try CoverEditorEngine.sampledColor(imageData:clone,at:CGPoint(x:17,y:17)).redComponent,0.7)
        let healed=try CoverEditorEngine.heal(imageData:clone,center:CGPoint(x:17,y:17),diameter:4)
        XCTAssertNotEqual(healed,clone)
        let bright=try CoverEditorEngine.dodgeBurn(imageData:source,at:[CGPoint(x:12,y:12)],diameter:12,strength:0.5,lighten:true)
        XCTAssertNotEqual(bright,source)
        XCTAssertGreaterThan(try CoverEditorEngine.sampledColor(imageData:source,at:CGPoint(x:6,y:6)).redComponent,0.7)
    }

    func testMoveResizeRotateFlipKeepSourcePixelsUntouched() throws {
        var layer=try CoverArtwork.imageLayer(data:image(),filename:"source.png")
        let source=layer.imageData
        CoverEditorEngine.move(&layer,dx:0.1,dy:0.2);CoverEditorEngine.resize(&layer,width:0.4,height:0.2,proportional:true);CoverEditorEngine.rotate(&layer,degrees:30);CoverEditorEngine.flip(&layer,horizontal:true)
        XCTAssertEqual(layer.frame.x,0.1,accuracy:0.0001);XCTAssertEqual(layer.rotation,30);XCTAssertTrue(layer.flipHorizontal);XCTAssertEqual(layer.imageData,source)
        layer.locked=true;CoverEditorEngine.move(&layer,dx:1,dy:1);XCTAssertEqual(layer.frame.x,0.1,accuracy:0.0001)
    }

    func testTransformAlignmentSnapAndEffectiveDPI() throws {
        XCTAssertEqual(CoverEditorEngine.snappedOrigin(CGPoint(x:0.405,y:0.395),size:CGSize(width:0.2,height:0.2),canvas:CGSize(width:1,height:1)),CGPoint(x:0.4,y:0.4))
        var p=CoverProject(width:2,height:2);let layer=try CoverArtwork.imageLayer(data:image(),filename:"small",frame:CoverRect(x:0,y:0,width:1,height:1));p.layers=[layer]
        XCTAssertEqual(CoverEditorEngine.effectiveDPI(layer,project:p),12)
    }

    func testBlendLocksAdjustmentAndGroupMetadataPersist() throws {
        var p=CoverProject();var layer=CoverLayer(kind:.adjustment,name:"Tone");layer.adjustment = .brightnessContrast;layer.adjustmentValues=["brightness":0.2,"contrast":1.1];layer.blendMode = .multiply;layer.positionLocked=true;layer.pixelsLocked=true
        let group=CoverLayer(kind:.group,name:"Artwork");layer.groupID=group.id;p.layers=[group,layer]
        let decoded=try JSONDecoder().decode(CoverProject.self,from:JSONEncoder().encode(p))
        XCTAssertEqual(decoded.layers[1].groupID,group.id);XCTAssertEqual(decoded.layers[1].blendMode,.multiply);XCTAssertEqual(decoded.layers[1].adjustment,.brightnessContrast);XCTAssertEqual(decoded.layers[1].adjustmentValues?["brightness"],0.2)
    }

    func testExtendedBlendModesChangeRenderedPixelsAndSurvivePersistence() throws {
        var project=CoverProject(width:1,height:1)
        var bottom=CoverLayer(kind:.shape,name:"Bottom")
        bottom.fillHex="#80A0C0"
        bottom.strokeWidth=0
        var top=CoverLayer(kind:.shape,name:"Top")
        top.fillHex="#C08040"
        top.strokeWidth=0
        project.layers=[bottom,top]
        func pixel(_ mode:CoverBlendMode) throws -> NSColor {
            project.layers[1].blendMode=mode
            let image=try CoverArtwork.render(project,scale:20)
            let rep=try XCTUnwrap(NSBitmapImageRep(data:try XCTUnwrap(image.tiffRepresentation)))
            return try XCTUnwrap(rep.colorAt(x:10,y:10)?.usingColorSpace(.deviceRGB))
        }
        let normal=try pixel(.normal)
        let burn=try pixel(.plusDarker)
        let dodge=try pixel(.plusLighter)
        XCTAssertNotEqual(normal.redComponent,burn.redComponent,accuracy:0.05)
        XCTAssertNotEqual(burn.blueComponent,dodge.blueComponent,accuracy:0.05)
        project.layers[1].blendMode = .softLight
        XCTAssertEqual(try JSONDecoder().decode(CoverProject.self,from:JSONEncoder().encode(project)).layers[1].blendMode,.softLight)
    }

    func testBackwardCompatibleCoverPayloadWithoutEditorExtensions() throws {
        let legacy=##"{"id":"00000000-0000-0000-0000-000000000001","name":"Legacy","type":"ebookFront","canvasWidth":6,"canvasHeight":9,"trimWidth":6,"trimHeight":9,"backWidth":6,"spineWidth":0,"bleed":0,"dpi":300,"guidesVisible":true,"gridVisible":false,"backgroundHex":"#FFFFFF","layers":[{"id":"00000000-0000-0000-0000-000000000002","kind":"text","name":"Title","frame":{"x":0.1,"y":0.2,"width":0.8,"height":0.2},"visible":true,"locked":false,"opacity":1,"rotation":0,"imageData":null,"cropMode":"fill","cropOffsetX":0,"cropOffsetY":0,"flipHorizontal":false,"flipVertical":false,"text":"Book","fontName":"Georgia","fontSize":36,"bold":false,"italic":false,"colorHex":"#202020","alignment":"center","lineSpacing":1,"letterSpacing":0,"shape":"rectangle","fillHex":"#FFFFFF","strokeHex":"#202020","strokeWidth":1}],"templateLocked":true}"##
        let project=try JSONDecoder().decode(CoverProject.self,from:Data(legacy.utf8));XCTAssertEqual(project.layers.first?.text,"Book");XCTAssertNil(project.savedSelections);XCTAssertNil(project.layers.first?.maskData)
    }

    func testToolPaletteCoversSelectionPaintTransformAndNavigationFamilies() {
        XCTAssertTrue([CoverEditorTool.move,.rectangle,.lasso,.wand,.crop,.eyedropper,.heal,.brush,.clone,.eraser,.gradient,.dodge,.type,.pen,.path,.shape,.hand,.zoom].allSatisfy{!$0.symbol.isEmpty})
    }

    func testNewPaintLayerIsTransparentAndAdjustmentLayerChangesComposite() throws {
        let p=CoverProject(width:0.2,height:0.2);let paint=CoverEditorEngine.newPaintLayer(name:"Paint",project:p)
        let rgba=try CoverEditorEngine.sampledColor(imageData:try XCTUnwrap(paint.imageData),at:CGPoint(x:8,y:8))
        XCTAssertLessThan(rgba.alphaComponent,0.01)
        var project=CoverProject(width:1,height:1);project.backgroundHex="#D02010"
        var adjustment=CoverLayer(kind:.adjustment,name:"Mono");adjustment.adjustment = .monochrome;project.layers=[adjustment]
        let result=try CoverArtwork.render(project,scale:20);let data=try XCTUnwrap(result.tiffRepresentation);let rep=try XCTUnwrap(NSBitmapImageRep(data:data));let pixel=NSColor(cgColor:try XCTUnwrap(rep.colorAt(x:10,y:10)?.cgColor))!
        XCTAssertEqual(pixel.redComponent,pixel.greenComponent,accuracy:0.08)
        XCTAssertEqual(pixel.greenComponent,pixel.blueComponent,accuracy:0.08)
    }

    func testNonDestructiveMaskGradientAndGroupVisibilityRender() throws {
        var project=CoverProject(width:1,height:1);project.dpi=24
        var art=try CoverArtwork.imageLayer(data:image(.red),filename:"Portrait",frame:CoverRect(x:0,y:0,width:1,height:1))
        let half=Data((0..<24*24).map{$0%24<12 ? UInt8(255):UInt8(0)})
        art.maskData=try XCTUnwrap(CoverEditorEngine.encodedMask(half,width:24,height:24))
        project.layers=[art]
        let rendered=try CoverArtwork.render(project,scale:24);let rep=try XCTUnwrap(NSBitmapImageRep(data:try XCTUnwrap(rendered.tiffRepresentation)))
        let kept=try XCTUnwrap(rep.colorAt(x:5,y:12)).usingColorSpace(.deviceRGB)!,removed=try XCTUnwrap(rep.colorAt(x:18,y:12)).usingColorSpace(.deviceRGB)!
        XCTAssertGreaterThan(kept.redComponent,kept.greenComponent+0.4)
        XCTAssertGreaterThan(removed.redComponent,0.9);XCTAssertGreaterThan(removed.greenComponent,0.9);XCTAssertGreaterThan(removed.blueComponent,0.9)
        var gradient=CoverLayer(kind:.gradient,name:"Gradient",frame:CoverRect(x:0,y:0,width:1,height:1));gradient.fillHex="#000000";gradient.gradientEndHex="#FFFFFF"
        var group=CoverLayer(kind:.group,name:"Hidden",frame:CoverRect(x:0,y:0,width:1,height:1));gradient.groupID=group.id;group.visible=false
        project.layers=[group,gradient]
        XCTAssertNotEqual(try CoverArtwork.render(project).tiffRepresentation,try CoverArtwork.render(project,includeGuides:true).tiffRepresentation)
    }

    func testSafeRectangleMathAndColorSwatchHexRoundTrip() {
        let safe=CoverCalculator.safeRect(trim:CoverRect(x:0.1,y:0.1,width:0.8,height:0.6),fraction:0.1)
        XCTAssertEqual(safe.x,0.18,accuracy:0.0001);XCTAssertEqual(safe.height,0.48,accuracy:0.0001)
        XCTAssertEqual(NSColor(hex:"#3467AB").hexRGB,"#3467AB")
    }
    func testSafeZoneRectsMatchProductionGeometryForNonSquareCover() {
        var project =
            CoverProject()

        project.type =
            .printFullWrap

        project.trimWidth =
            6

        project.backWidth =
            6

        project.trimHeight =
            9

        project.spineWidth =
            0.8

        project.bleed =
            0.125

        project.canvasWidth =
            12.0 + 0.8 + 0.25

        project.canvasHeight =
            9.25

        let geometry =
            CoverWrapGeometry(
                project:
                    project
            )

        let safeZones =
            CoverEditorEngine
                .safeZoneRects(
                    project:
                        project
                )

        XCTAssertEqual(
            safeZones.count,
            3
        )

        XCTAssertEqual(
            safeZones[0],
            geometry.backSafeArea
        )

        XCTAssertEqual(
            safeZones[1],
            geometry.spineSafeArea
        )

        XCTAssertEqual(
            safeZones[2],
            geometry.frontSafeArea
        )

        let frontSafe =
            safeZones[2]

        let frontTrim =
            geometry.frontTrim

        let horizontalInsetInches =
            (
                frontSafe.x
                - frontTrim.x
            )
            * project.canvasWidth

        let verticalInsetInches =
            (
                frontSafe.y
                - frontTrim.y
            )
            * project.canvasHeight

        XCTAssertEqual(
            horizontalInsetInches,
            0.30,
            accuracy:
                0.000001
        )

        XCTAssertEqual(
            verticalInsetInches,
            0.45,
            accuracy:
                0.000001
        )

        XCTAssertNotEqual(
            horizontalInsetInches,
            verticalInsetInches,
            "A 6 × 9 inch trim must use 5% of width horizontally and 5% of height vertically, not one min-dimension inset."
        )
    }

    func testSafeZoneSnapUsesProductionSafeRectEdges() throws {
        var project =
            CoverProject()

        project.type =
            .printFullWrap

        project.trimWidth =
            6

        project.backWidth =
            6

        project.trimHeight =
            9

        project.spineWidth =
            0.8

        project.bleed =
            0.125

        project.canvasWidth =
            13.05

        project.canvasHeight =
            9.25

        project.snapEnabled =
            true

        project.snapCanvasEdges =
            false

        project.snapCanvasCenter =
            false

        project.snapBleed =
            false

        project.snapTrim =
            false

        project.snapBackCover =
            false

        project.snapBackCoverCenter =
            false

        project.snapFrontCover =
            false

        project.snapFrontCoverCenter =
            false

        project.snapSpine =
            false

        project.snapSpineCenter =
            false

        project.snapGuides =
            false

        project.snapGrid =
            false

        project.snapLayers =
            false

        project.snapLayerEdges =
            false

        project.snapLayerCenters =
            false

        project.snapSafeZone =
            true

        let safeZones =
            CoverEditorEngine
                .safeZoneRects(
                    project:
                        project
                )

        let frontSafe =
            try XCTUnwrap(
                safeZones.last
            )

        let input =
            CoverRect(
                x:
                    frontSafe.x
                    + 0.003,
                y:
                    frontSafe.y
                    + 0.003,
                width:
                    0.10,
                height:
                    0.10
            )

        let snapped =
            CoverEditorEngine
                .snap(
                    input,
                    layerID:
                        nil,
                    project:
                        project,
                    displayedCanvas:
                        CGSize(
                            width:
                                1000,
                            height:
                                1000
                        ),
                    thresholdPoints:
                        8
                )
                .frame

        XCTAssertEqual(
            snapped.x,
            frontSafe.x,
            accuracy:
                0.000001
        )

        XCTAssertEqual(
            snapped.y,
            frontSafe.y,
            accuracy:
                0.000001
        )
    }

    func testEbookSafeZoneUsesIndependentFivePercentInsets() throws {
        var project =
            CoverProject()

        project.type =
            .ebookFront

        project.trimWidth =
            6

        project.trimHeight =
            9

        project.bleed =
            0

        project.canvasWidth =
            6

        project.canvasHeight =
            9

        let safe =
            try XCTUnwrap(
                CoverEditorEngine
                    .safeZoneRects(
                        project:
                            project
                    )
                    .first
            )

        XCTAssertEqual(
            safe.x
                * project.canvasWidth,
            0.30,
            accuracy:
                0.000001
        )

        XCTAssertEqual(
            safe.y
                * project.canvasHeight,
            0.45,
            accuracy:
                0.000001
        )
    }

}
