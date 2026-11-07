import XCTest
@testable import BOLDWriter

final class CoverSelectionAdvancedTests: XCTestCase {
    func testEllipseSelectionAntialiasAndMorphologicalModification() {
        let ellipse=CoverEditorEngine.ellipseSelection(width:20,height:20,rect:CGRect(x:2,y:2,width:16,height:16))
        XCTAssertTrue(ellipse.contains{$0>0 && $0<255})
        let expanded=CoverEditorEngine.expandSelection(ellipse,width:20,height:20,radius:2),contracted=CoverEditorEngine.contractSelection(ellipse,width:20,height:20,radius:2)
        XCTAssertGreaterThan(expanded.filter{$0>0}.count,ellipse.filter{$0>0}.count);XCTAssertLessThan(contracted.filter{$0>0}.count,ellipse.filter{$0>0}.count)
        let smooth=CoverEditorEngine.smoothSelection(ellipse,width:20,height:20,radius:1);XCTAssertTrue(smooth.contains{$0>0 && $0<255})
        let border=CoverEditorEngine.borderSelection(ellipse,width:20,height:20,radius:2);XCTAssertGreaterThan(border.filter{$0>0}.count,0);XCTAssertLessThan(border.filter{$0>0}.count,ellipse.filter{$0>0}.count)
    }

    func testFractionalCombinationModesAndRGBDistance() {
        let old=Data([0,64,128,255]),new=Data([96,128,64,0])
        XCTAssertEqual(CoverEditorEngine.combine(old,new,mode:.replace),new)
        XCTAssertEqual(CoverEditorEngine.combine(old,new,mode:.add),Data([96,128,128,255]))
        XCTAssertEqual(CoverEditorEngine.combine(old,new,mode:.subtract),Data([0,0,64,255]))
        XCTAssertEqual(CoverEditorEngine.combine(old,new,mode:.intersect),Data([0,64,64,0]))
        XCTAssertEqual(CoverEditorEngine.colorDistance((0,0,0),(255,255,255)),sqrt(3*255.0*255.0),accuracy:0.0001)
    }

    func testSelectionCombinationDoesNotReusePixelsFromAnotherLayer() {
        let firstLayer = UUID()
        let secondLayer = UUID()
        let old = Data([255, 0, 64, 128])
        let next = Data([0, 64, 128, 255])

        XCTAssertEqual(
            CoverEditorEngine.applyingSelection(
                next,
                toLayer: secondLayer,
                existing: old,
                existingLayerID: firstLayer,
                mode: .add
            ),
            next
        )
        XCTAssertEqual(
            CoverEditorEngine.applyingSelection(
                next,
                toLayer: firstLayer,
                existing: old,
                existingLayerID: firstLayer,
                mode: .add
            ),
            Data([255, 64, 128, 255])
        )
    }

    func testWandToleranceIsMonotonicAndSelectionTransformIsArtworkIndependent() throws {
        let source=try CoverEditorEngine.filledImage(width:12,height:8,color:.black)
        let colored=try CoverEditorEngine.paint(imageData:source,points:[CGPoint(x:6,y:4)],color:NSColor(red:0.4,green:0.2,blue:0.1,alpha:1),diameter:5)
        let narrow=try CoverEditorEngine.colorSelection(imageData:colored,sample:CGPoint(x:6,y:4),tolerance:0.1,contiguous:false,antialias:true)
        let broad=try CoverEditorEngine.colorSelection(imageData:colored,sample:CGPoint(x:6,y:4),tolerance:0.7,contiguous:false,antialias:true)
        XCTAssertGreaterThanOrEqual(broad.mask.filter{$0>0}.count,narrow.mask.filter{$0>0}.count)
        let original=CoverEditorEngine.rectangleSelection(width:12,height:8,rect:CGRect(x:2,y:2,width:4,height:3))
        let shifted=CoverEditorEngine.transformSelection(original,width:12,height:8,translation:CGPoint(x:2,y:0))
        XCTAssertEqual(shifted.filter{$0>0}.count,original.filter{$0>0}.count)
        XCTAssertNotEqual(shifted,original)
    }

    func testMagneticLassoSearchSettingsChangeLocalAnchors() throws {
        let base=try CoverEditorEngine.filledImage(width:48,height:32,color:.black)
        let split=try CoverEditorEngine.paint(imageData:base,points:[CGPoint(x:24,y:16)],color:.white,diameter:18)
        let input=[CGPoint(x:18,y:4),CGPoint(x:18,y:28)]
        let path=CoverEditorEngine.magneticLassoPath(imageData:split,points:input,radius:10,contrast:0.7,frequency:3)
        XCTAssertGreaterThan(path.count,2)
        XCTAssertTrue(path.contains{abs($0.x-24)<10})
        let sparse=CoverEditorEngine.magneticLassoPath(imageData:split,points:input,radius:2,contrast:0.1,frequency:100)
        XCTAssertNotEqual(path,sparse)
    }

    func testSelectionCoverageControlsBrushContribution() throws {
        let base=try CoverEditorEngine.filledImage(width:16,height:16,color:.white),mask=Data(repeating:128,count:256)
        let full=try CoverEditorEngine.paint(imageData:base,points:[CGPoint(x:8,y:8)],color:.black,diameter:8,selection:Data(repeating:255,count:256))
        let half=try CoverEditorEngine.paint(imageData:base,points:[CGPoint(x:8,y:8)],color:.black,diameter:8,selection:mask)
        let fullPixel=try XCTUnwrap(CoverEditorEngine.sampledColor(imageData:full,at:CGPoint(x:8,y:8)).usingColorSpace(.deviceRGB)).redComponent,halfPixel=try XCTUnwrap(CoverEditorEngine.sampledColor(imageData:half,at:CGPoint(x:8,y:8)).usingColorSpace(.deviceRGB)).redComponent
        XCTAssertLessThan(fullPixel,halfPixel)
        XCTAssertGreaterThan(halfPixel,0.4);XCTAssertLessThan(halfPixel,0.7)
    }

    func testLinearMaskGradientHonorsDirectionOpacityAndSelection() {
        let base = Data(repeating: 0, count: 25)
        let all = CoverEditorEngine.gradientMask(
            base, width: 5, height: 5,
            start: CGPoint(x: 0, y: 2), end: CGPoint(x: 4, y: 2)
        )
        XCTAssertEqual(all[10], 0)
        XCTAssertEqual(Int(all[12]), 128)
        XCTAssertEqual(all[14], 255)
        XCTAssertEqual(all[0], 0, "Linear gradients should stay constant perpendicular to their direction")

        let reversed = CoverEditorEngine.gradientMask(
            base, width: 5, height: 5,
            start: CGPoint(x: 0, y: 2), end: CGPoint(x: 4, y: 2), reversed: true
        )
        XCTAssertEqual(reversed[10], 255)
        XCTAssertEqual(reversed[14], 0)

        let selection = Data([255, 128, 0, 255, 255]) + Data(repeating: 0, count: 20)
        let partial = CoverEditorEngine.gradientMask(
            base, width: 5, height: 5,
            start: CGPoint(x: 0, y: 0), end: CGPoint(x: 4, y: 0),
            opacity: 0.5, selection: selection
        )
        XCTAssertEqual(partial[0], 0)
        XCTAssertEqual(Int(partial[1]), 16)
        XCTAssertEqual(partial[2], 0)
        XCTAssertEqual(Int(partial[3]), 96)
        XCTAssertEqual(Int(partial[4]), 128)
        XCTAssertEqual(partial[5], 0, "Selection coverage must limit the operation to selected pixels")
    }

    func testRadialMaskGradientAndMaskInspectionPreviews() throws {
        let radial = CoverEditorEngine.gradientMask(
            Data(repeating: 255, count: 49), width: 7, height: 7,
            start: CGPoint(x: 3, y: 3), end: CGPoint(x: 6, y: 3), radial: true
        )
        XCTAssertEqual(radial[3 * 7 + 3], 0)
        XCTAssertEqual(radial[3 * 7 + 6], 255)
        XCTAssertEqual(Int(radial[3 * 7 + 4]), 85)

        let values = Data([0, 128, 255, 64])
        let gray = try XCTUnwrap(CoverEditorEngine.maskInspectionPreview(values, width: 2, height: 2, overlay: false))
        let grayPixel = try XCTUnwrap(CoverEditorEngine.sampledColor(imageData: gray, at: CGPoint(x: 1, y: 0)).usingColorSpace(.deviceRGB))
        XCTAssertEqual(grayPixel.redComponent, 128 / 255, accuracy: 0.01)
        let overlay = try XCTUnwrap(CoverEditorEngine.maskInspectionPreview(values, width: 2, height: 2, overlay: true))
        let concealedPixel = try XCTUnwrap(CoverEditorEngine.sampledColor(imageData: overlay, at: CGPoint(x: 0, y: 0)).usingColorSpace(.deviceRGB))
        let revealedPixel = try XCTUnwrap(CoverEditorEngine.sampledColor(imageData: overlay, at: CGPoint(x: 0, y: 1)).usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(concealedPixel.alphaComponent, 0.5)
        XCTAssertEqual(revealedPixel.alphaComponent, 0, accuracy: 0.01)
    }

    func testFinalGrayscaleMaskCanvasPreviewRemainsNeutralWithActiveSelection() throws {
        let selection = Data(repeating: 255, count: 25)
        let linear = CoverEditorEngine.gradientMask(
            Data(repeating: 0, count: 25), width: 5, height: 5,
            start: CGPoint(x: 0, y: 2), end: CGPoint(x: 4, y: 2)
        )
        let radial = CoverEditorEngine.gradientMask(
            Data(repeating: 255, count: 25), width: 5, height: 5,
            start: CGPoint(x: 2, y: 2), end: CGPoint(x: 4, y: 2), radial: true
        )
        let reversed = CoverEditorEngine.gradientMask(
            Data(repeating: 0, count: 25), width: 5, height: 5,
            start: CGPoint(x: 0, y: 2), end: CGPoint(x: 4, y: 2), reversed: true
        )

        let cases: [(Data, [CGPoint])] = [
            (linear, [CGPoint(x: 0, y: 2), CGPoint(x: 2, y: 2), CGPoint(x: 4, y: 2)]),
            (radial, [CGPoint(x: 2, y: 2), CGPoint(x: 3, y: 2), CGPoint(x: 4, y: 2)]),
            (reversed, [CGPoint(x: 0, y: 2), CGPoint(x: 2, y: 2), CGPoint(x: 4, y: 2)])
        ]

        for (mask, samplePoints) in cases {
            let grayPNG = try XCTUnwrap(
                CoverEditorEngine.maskInspectionPreview(mask, width: 5, height: 5, overlay: false)
            )
            let selectionPNG = try XCTUnwrap(
                CoverEditorEngine.selectionPreview(selection, width: 5, height: 5)
            )
            let tintVisible = CoverEditorEngine.maskInspectionSelectionTintEnabled(
                maskSelected: true,
                inspectionModeActive: true
            )
            for samplePoint in samplePoints {
                let gray = try XCTUnwrap(
                    CoverEditorEngine.sampledColor(imageData: grayPNG, at: samplePoint).usingColorSpace(.deviceRGB)
                )
                let selectionTint = try XCTUnwrap(
                    CoverEditorEngine.sampledColor(imageData: selectionPNG, at: samplePoint).usingColorSpace(.deviceRGB)
                )

                // This is the final pixel produced by the canvas ZStack: inspection
                // preview first, then the active selection tint above it.
                let alpha = tintVisible ? selectionTint.alphaComponent : 0
                let displayed = [
                    selectionTint.redComponent * alpha + gray.redComponent * (1 - alpha),
                    selectionTint.greenComponent * alpha + gray.greenComponent * (1 - alpha),
                    selectionTint.blueComponent * alpha + gray.blueComponent * (1 - alpha)
                ]
                XCTAssertEqual(displayed[0], displayed[1], accuracy: 0.01, "Grayscale canvas output has a red/green channel cast at \(samplePoint).")
                XCTAssertEqual(displayed[1], displayed[2], accuracy: 0.01, "Grayscale canvas output has a green/blue channel cast at \(samplePoint).")
            }
        }
    }

    func testMaskInspectionSuppressesSelectionTintButPreservesArtworkFeedback() {
        XCTAssertFalse(CoverEditorEngine.maskInspectionSelectionTintEnabled(maskSelected: true, inspectionModeActive: true))
        XCTAssertTrue(CoverEditorEngine.maskInspectionSelectionTintEnabled(maskSelected: true, inspectionModeActive: false))
        XCTAssertTrue(CoverEditorEngine.maskInspectionSelectionTintEnabled(maskSelected: false, inspectionModeActive: true))
    }

    func testFeatherExpandAndContractPreserveAnIrregularSelection() {
        let width = 19
        let height = 15
        var bytes = [UInt8](repeating: 0, count: width * height)
        // A stepped, asymmetric polygon-like mask makes rectangular bounding-box
        // approximations visible at the notches and protrusions.
        for y in 2...11 {
            for x in 3...7 { bytes[y * width + x] = 255 }
        }
        for y in 7...10 {
            for x in 7...14 { bytes[y * width + x] = 255 }
        }
        let original = Data(bytes)
        let expanded = CoverEditorEngine.expandSelection(original, width: width, height: height, radius: 2)
        let contracted = CoverEditorEngine.contractSelection(original, width: width, height: height, radius: 1)
        let feathered = CoverEditorEngine.feather(original, width: width, height: height, radius: 2)
        func value(_ mask: Data, _ x: Int, _ y: Int) -> UInt8 { mask[y * width + x] }

        XCTAssertEqual(value(original, 4, 4), 255)
        XCTAssertEqual(value(expanded, 2, 4), 255, "Expand should follow the irregular boundary outward.")
        XCTAssertEqual(value(expanded, 13, 4), 0, "Expand must not fill unrelated areas inside the selection bounds.")
        XCTAssertEqual(value(contracted, 5, 4), 255)
        XCTAssertEqual(value(contracted, 3, 4), 0, "Contract should move the actual irregular edge inward.")
        XCTAssertGreaterThan(value(feathered, 3, 4), 0)
        XCTAssertLessThan(value(feathered, 3, 4), 255, "Feather should soften the stepped edge without deleting the selection.")
        XCTAssertEqual(value(feathered, 16, 2), 0, "Feather must not create coverage outside the edge neighborhood.")
    }
}
