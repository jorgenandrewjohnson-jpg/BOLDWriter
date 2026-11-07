import AppKit
import XCTest
@testable import BOLDWriter

final class CoverBlurSharpenToolTests: XCTestCase {
    private func image(
        value: CGFloat = 1,
        alpha: CGFloat = 1,
        width: Int = 32,
        height: Int = 32
    ) throws -> Data {
        try CoverEditorEngine.filledImage(
            width:width,
            height:height,
            color:NSColor(calibratedWhite:value,alpha:alpha)
        )
    }

    private func sample(
        _ data:Data,
        _ x:CGFloat,
        _ y:CGFloat
    ) throws -> NSColor {
        try CoverEditorEngine.sampledColor(
            imageData:data,
            at:CGPoint(x:x,y:y)
        ).usingColorSpace(.deviceRGB) ?? .black
    }

    private func marked(
        _ base:Data,
        point:CGPoint,
        value:CGFloat
    ) throws -> Data {
        try CoverEditorEngine.paint(
            imageData:base,
            points:[point],
            color:NSColor(calibratedWhite:value,alpha:1),
            diameter:1,
            hardness:1
        )
    }

    func testBlurChangesHighFrequencyPixel() throws {
        let p=CGPoint(x:16,y:16)
        let source=try marked(image(),point:p,value:0)
        let before=try sample(source,16,16).redComponent
        let result=try CoverEditorEngine.blurSharpen(
            imageData:source,
            at:[p],
            diameter:12,
            strength:1,
            sharpen:false
        )
        XCTAssertGreaterThan(try sample(result,16,16).redComponent,before)
    }

    func testBlurLeavesOutsideBrushUnchanged() throws {
        let p=CGPoint(x:16,y:16)
        let source=try marked(image(),point:p,value:0)
        let result=try CoverEditorEngine.blurSharpen(
            imageData:source,
            at:[p],
            diameter:8,
            strength:1,
            sharpen:false
        )
        XCTAssertEqual(
            try sample(source,1,1).redComponent,
            try sample(result,1,1).redComponent,
            accuracy:0.001
        )
    }

    func testSharpenIncreasesLocalContrast() throws {
        let p=CGPoint(x:16,y:16)
        let source=try marked(image(value:0.5),point:p,value:0.68)
        let before=try sample(source,16,16).redComponent
        let result=try CoverEditorEngine.blurSharpen(
            imageData:source,
            at:[p],
            diameter:10,
            strength:1,
            sharpen:true
        )
        XCTAssertGreaterThan(try sample(result,16,16).redComponent,before)
    }

    func testZeroAndNegativeStrengthAreNoOp() throws {
        let source=try marked(image(),point:CGPoint(x:16,y:16),value:0)
        XCTAssertEqual(
            try CoverEditorEngine.blurSharpen(
                imageData:source,
                at:[CGPoint(x:16,y:16)],
                diameter:12,
                strength:0,
                sharpen:false
            ),
            source
        )
        XCTAssertEqual(
            try CoverEditorEngine.blurSharpen(
                imageData:source,
                at:[CGPoint(x:16,y:16)],
                diameter:12,
                strength:-2,
                sharpen:true
            ),
            source
        )
    }

    func testStrengthAboveOneClamps() throws {
        let p=CGPoint(x:16,y:16)
        let source=try marked(image(),point:p,value:0)
        let one=try CoverEditorEngine.blurSharpen(
            imageData:source,
            at:[p],
            diameter:12,
            strength:1,
            sharpen:false
        )
        let high=try CoverEditorEngine.blurSharpen(
            imageData:source,
            at:[p],
            diameter:12,
            strength:9,
            sharpen:false
        )
        XCTAssertEqual(one,high)
    }

    func testInvalidDiameterReturnsOriginal() throws {
        let source=try image()
        XCTAssertEqual(
            try CoverEditorEngine.blurSharpen(
                imageData:source,
                at:[CGPoint(x:10,y:10)],
                diameter:0,
                strength:1,
                sharpen:false
            ),
            source
        )
        XCTAssertEqual(
            try CoverEditorEngine.blurSharpen(
                imageData:source,
                at:[CGPoint(x:10,y:10)],
                diameter:Double.infinity,
                strength:1,
                sharpen:false
            ),
            source
        )
    }

    func testNonfinitePointIsIgnoredSafely() throws {
        let source=try image()
        XCTAssertEqual(
            try CoverEditorEngine.blurSharpen(
                imageData:source,
                at:[CGPoint(x:CGFloat.infinity,y:10)],
                diameter:12,
                strength:1,
                sharpen:false
            ),
            source
        )
    }

    func testInvalidSelectionDimensionsReturnOriginal() throws {
        let source=try image()
        XCTAssertEqual(
            try CoverEditorEngine.blurSharpen(
                imageData:source,
                at:[CGPoint(x:16,y:16)],
                diameter:12,
                strength:1,
                sharpen:false,
                selection:Data([255])
            ),
            source
        )
    }

    func testSelectionConstrainsBlur() throws {
        let width=32
        let p=CGPoint(x:16,y:16)
        let source=try marked(image(),point:p,value:0)
        var mask=Data(repeating:0,count:width*width)
        mask[16*width+16]=255
        let result=try CoverEditorEngine.blurSharpen(
            imageData:source,
            at:[p],
            diameter:12,
            strength:1,
            sharpen:false,
            selection:mask
        )
        XCTAssertGreaterThan(
            try sample(result,16,16).redComponent,
            try sample(source,16,16).redComponent
        )
        XCTAssertEqual(
            try sample(result,17,16).redComponent,
            try sample(source,17,16).redComponent,
            accuracy:0.001
        )
    }

    func testPartialSelectionScalesInfluence() throws {
        let width=32
        let p=CGPoint(x:16,y:16)
        let source=try marked(image(),point:p,value:0)
        let index=16*width+16
        var half=Data(repeating:0,count:width*width)
        var full=half
        half[index]=128
        full[index]=255

        let halfResult=try CoverEditorEngine.blurSharpen(
            imageData:source,
            at:[p],
            diameter:12,
            strength:1,
            sharpen:false,
            selection:half
        )
        let fullResult=try CoverEditorEngine.blurSharpen(
            imageData:source,
            at:[p],
            diameter:12,
            strength:1,
            sharpen:false,
            selection:full
        )

        XCTAssertGreaterThan(
            try sample(fullResult,16,16).redComponent,
            try sample(halfResult,16,16).redComponent
        )
    }

    func testFlowControlsInfluence() throws {
        let p=CGPoint(x:16,y:16)
        let source=try marked(image(),point:p,value:0)
        let low=try CoverEditorEngine.blurSharpen(
            imageData:source,
            at:[p],
            diameter:12,
            strength:1,
            sharpen:false,
            hardness:1,
            flow:0.2
        )
        let full=try CoverEditorEngine.blurSharpen(
            imageData:source,
            at:[p],
            diameter:12,
            strength:1,
            sharpen:false,
            hardness:1,
            flow:1
        )
        XCTAssertGreaterThan(
            try sample(full,16,16).redComponent,
            try sample(low,16,16).redComponent
        )
    }

    func testHardnessControlsEdgeInfluence() throws {
        let center=CGPoint(x:16,y:16)
        let source=try marked(image(),point:CGPoint(x:21,y:16),value:0)

        let soft=try CoverEditorEngine.blurSharpen(
            imageData:source,
            at:[center],
            diameter:12,
            strength:1,
            sharpen:false,
            hardness:0,
            flow:1
        )

        let hard=try CoverEditorEngine.blurSharpen(
            imageData:source,
            at:[center],
            diameter:12,
            strength:1,
            sharpen:false,
            hardness:1,
            flow:1
        )

        XCTAssertGreaterThan(
            try sample(hard,21,16).redComponent,
            try sample(soft,21,16).redComponent
        )
    }

    func testBlurPreservesAlpha() throws {
        let source=try image(value:0.5,alpha:0.45)
        let before=try sample(source,16,16).alphaComponent
        let result=try CoverEditorEngine.blurSharpen(
            imageData:source,
            at:[CGPoint(x:16,y:16)],
            diameter:12,
            strength:1,
            sharpen:false
        )
        XCTAssertEqual(
            try sample(result,16,16).alphaComponent,
            before,
            accuracy:0.01
        )
    }

    func testSharpenPreservesAlpha() throws {
        let source=try image(value:0.5,alpha:0.4)
        let before=try sample(source,16,16).alphaComponent
        let result=try CoverEditorEngine.blurSharpen(
            imageData:source,
            at:[CGPoint(x:16,y:16)],
            diameter:12,
            strength:1,
            sharpen:true
        )
        XCTAssertEqual(
            try sample(result,16,16).alphaComponent,
            before,
            accuracy:0.01
        )
    }

    func testMultiplePointsAreDeterministic() throws {
        let source=try marked(image(),point:CGPoint(x:16,y:16),value:0)
        let points=[
            CGPoint(x:15,y:16),
            CGPoint(x:16,y:16),
            CGPoint(x:17,y:16)
        ]

        let a=try CoverEditorEngine.blurSharpen(
            imageData:source,
            at:points,
            diameter:10,
            strength:0.6,
            sharpen:false,
            hardness:0.7,
            flow:0.5
        )

        let b=try CoverEditorEngine.blurSharpen(
            imageData:source,
            at:points,
            diameter:10,
            strength:0.6,
            sharpen:false,
            hardness:0.7,
            flow:0.5
        )

        XCTAssertEqual(a,b)
    }

    func testToolsAreImplementedAndNamed() {
        XCTAssertTrue(CoverEditorTool.blur.isImplemented)
        XCTAssertTrue(CoverEditorTool.sharpen.isImplemented)
        XCTAssertEqual(CoverEditorTool.blur.title,"Blur")
        XCTAssertEqual(CoverEditorTool.sharpen.title,"Sharpen")
        XCTAssertFalse(CoverEditorTool.blur.symbol.isEmpty)
        XCTAssertFalse(CoverEditorTool.sharpen.symbol.isEmpty)
    }

    func testToolsUsePaintOptions() {
        XCTAssertEqual(CoverEditorTool.blur.options,.paint)
        XCTAssertEqual(CoverEditorTool.sharpen.options,.paint)
    }

    func testToolbarContainsBlurSharpenPair() {
        XCTAssertTrue(
            CoverEditorTool.toolbarGroups.contains([.blur,.sharpen])
        )
    }

    func testExistingWholeLayerBlurSharpenRemainAvailable() {
        XCTAssertTrue(CoverAdjustmentKind.allCases.contains(.gaussianBlur))
        XCTAssertTrue(CoverAdjustmentKind.allCases.contains(.sharpen))
        XCTAssertTrue(CoverFilterKind.allCases.contains(.gaussianBlur))
        XCTAssertTrue(CoverFilterKind.allCases.contains(.sharpen))
    }
}
