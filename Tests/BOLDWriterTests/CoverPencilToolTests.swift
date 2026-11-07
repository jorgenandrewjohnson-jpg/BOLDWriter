import AppKit
import XCTest
@testable import BOLDWriter

final class CoverPencilToolTests: XCTestCase {
    private func transparentPNG(
        width:Int=24,
        height:Int=12
    ) throws -> Data {
        let bitmap =
            try XCTUnwrap(
                NSBitmapImageRep(
                    bitmapDataPlanes:nil,
                    pixelsWide:width,
                    pixelsHigh:height,
                    bitsPerSample:8,
                    samplesPerPixel:4,
                    hasAlpha:true,
                    isPlanar:false,
                    colorSpaceName:.deviceRGB,
                    bytesPerRow:width * 4,
                    bitsPerPixel:32
                )
            )

        for y in 0..<height {
            for x in 0..<width {
                bitmap.setColor(
                    .clear,
                    atX:x,
                    y:y
                )
            }
        }

        return try XCTUnwrap(
            bitmap.representation(
                using:.png,
                properties:[:]
            )
        )
    }

    private func rgba(
        _ data:Data,
        x:Int,
        y:Int
    ) throws -> NSColor {
        let bitmap =
            try XCTUnwrap(
                NSBitmapImageRep(
                    data:data
                )
            )

        return try XCTUnwrap(
            bitmap.colorAt(
                x:x,
                y:y
            )?
            .usingColorSpace(
                .deviceRGB
            )
        )
    }

    private func alpha(
        _ data:Data,
        x:Int,
        y:Int
    ) throws -> Double {
        Double(
            try rgba(
                data,
                x:x,
                y:y
            )
            .alphaComponent
        )
    }

    func testPencilToolIdentity() {
        XCTAssertEqual(
            CoverEditorTool.pencil.rawValue,
            "pencil"
        )

        XCTAssertEqual(
            CoverEditorTool.pencil.title,
            "Pencil"
        )

        XCTAssertEqual(
            CoverEditorTool.pencil.symbol,
            "pencil"
        )

        XCTAssertTrue(
            CoverEditorTool.pencil.isImplemented
        )

        XCTAssertEqual(
            CoverEditorTool.pencil.options,
            .paint
        )
    }

    func testPencilSharesToolbarGroupWithBrush() throws {
        let group =
            try XCTUnwrap(
                CoverEditorTool
                    .toolbarGroups
                    .first {
                        $0.contains(
                            .brush
                        )
                    }
            )

        XCTAssertEqual(
            group,
            [
                .brush,
                .pencil,
            ]
        )
    }

    func testPencilPaintIsHardEdged() throws {
        let source =
            try transparentPNG(
                width:9,
                height:9
            )

        let result =
            try CoverEditorEngine.pencil(
                imageData:source,
                points:[
                    CGPoint(
                        x:4,
                        y:4
                    )
                ],
                color:.black,
                diameter:4,
                opacity:1,
                flow:1
            )

        XCTAssertGreaterThan(
            try alpha(
                result,
                x:5,
                y:4
            ),
            0.99
        )

        XCTAssertGreaterThan(
            try alpha(
                result,
                x:6,
                y:4
            ),
            0.99
        )

        XCTAssertLessThan(
            try alpha(
                result,
                x:7,
                y:4
            ),
            0.01
        )
    }

    func testBrushCanRemainSoftWhilePencilIsHard() throws {
        let source =
            try transparentPNG(
                width:9,
                height:9
            )

        let soft =
            try CoverEditorEngine.paint(
                imageData:source,
                points:[
                    CGPoint(
                        x:4,
                        y:4
                    )
                ],
                color:.black,
                diameter:4,
                opacity:1,
                selection:nil,
                hardness:0,
                flow:1
            )

        let pencil =
            try CoverEditorEngine.pencil(
                imageData:source,
                points:[
                    CGPoint(
                        x:4,
                        y:4
                    )
                ],
                color:.black,
                diameter:4,
                opacity:1,
                flow:1
            )

        let softAlpha =
            try alpha(
                soft,
                x:5,
                y:4
            )

        let pencilAlpha =
            try alpha(
                pencil,
                x:5,
                y:4
            )

        XCTAssertGreaterThan(
            pencilAlpha,
            0.99
        )

        XCTAssertGreaterThan(
            softAlpha,
            0
        )

        XCTAssertLessThan(
            softAlpha,
            0.8
        )
    }

    func testPencilInterpolatesFastStrokeWithoutGap() throws {
        let source =
            try transparentPNG(
                width:24,
                height:7
            )

        let result =
            try CoverEditorEngine.pencil(
                imageData:source,
                points:[
                    CGPoint(
                        x:2,
                        y:3
                    ),
                    CGPoint(
                        x:21,
                        y:3
                    )
                ],
                color:.black,
                diameter:2,
                opacity:1,
                flow:1
            )

        for x in 2...21 {
            XCTAssertGreaterThan(
                try alpha(
                    result,
                    x:x,
                    y:3
                ),
                0.95,
                "Expected continuous Pencil coverage at x=\(x)"
            )
        }
    }

    func testPencilUsesSameForegroundColorAsBrush() throws {
        let source =
            try transparentPNG(
                width:7,
                height:7
            )

        let requested =
            NSColor(
                srgbRed:0.8,
                green:0.2,
                blue:0.4,
                alpha:1
            )

        let pencil =
            try CoverEditorEngine.pencil(
                imageData:source,
                points:[
                    CGPoint(
                        x:3,
                        y:3
                    )
                ],
                color:requested,
                diameter:2,
                opacity:1,
                flow:1
            )

        let brush =
            try CoverEditorEngine.paint(
                imageData:source,
                points:[
                    CGPoint(
                        x:3,
                        y:3
                    )
                ],
                color:requested,
                diameter:2,
                opacity:1,
                selection:nil,
                hardness:1,
                flow:1
            )

        let pencilColor =
            try rgba(
                pencil,
                x:3,
                y:3
            )

        let brushColor =
            try rgba(
                brush,
                x:3,
                y:3
            )

        XCTAssertEqual(
            pencilColor.redComponent,
            brushColor.redComponent,
            accuracy:0.001
        )

        XCTAssertEqual(
            pencilColor.greenComponent,
            brushColor.greenComponent,
            accuracy:0.001
        )

        XCTAssertEqual(
            pencilColor.blueComponent,
            brushColor.blueComponent,
            accuracy:0.001
        )

        XCTAssertGreaterThan(
            pencilColor.redComponent,
            pencilColor.blueComponent
        )

        XCTAssertGreaterThan(
            pencilColor.blueComponent,
            pencilColor.greenComponent
        )
    }

    func testPencilRespectsOpacity() throws {
        let source =
            try transparentPNG(
                width:7,
                height:7
            )

        let result =
            try CoverEditorEngine.pencil(
                imageData:source,
                points:[
                    CGPoint(
                        x:3,
                        y:3
                    )
                ],
                color:.black,
                diameter:2,
                opacity:0.4,
                flow:1
            )

        XCTAssertEqual(
            try alpha(
                result,
                x:3,
                y:3
            ),
            0.4,
            accuracy:0.03
        )
    }

    func testPencilRespectsFlow() throws {
        let source =
            try transparentPNG(
                width:7,
                height:7
            )

        let result =
            try CoverEditorEngine.pencil(
                imageData:source,
                points:[
                    CGPoint(
                        x:3,
                        y:3
                    )
                ],
                color:.black,
                diameter:2,
                opacity:1,
                flow:0.25
            )

        XCTAssertEqual(
            try alpha(
                result,
                x:3,
                y:3
            ),
            0.25,
            accuracy:0.03
        )
    }

    func testPencilRespectsSelectionCoverage() throws {
        let width = 9
        let height = 9

        let source =
            try transparentPNG(
                width:width,
                height:height
            )

        var selection =
            Data(
                repeating:0,
                count:width * height
            )

        selection[
            4 * width + 4
        ] = 128

        let result =
            try CoverEditorEngine.pencil(
                imageData:source,
                points:[
                    CGPoint(
                        x:4,
                        y:4
                    )
                ],
                color:.black,
                diameter:4,
                opacity:1,
                selection:selection,
                flow:1
            )

        XCTAssertEqual(
            try alpha(
                result,
                x:4,
                y:4
            ),
            Double(128) / 255,
            accuracy:0.03
        )

        XCTAssertLessThan(
            try alpha(
                result,
                x:5,
                y:4
            ),
            0.01
        )
    }

    func testPencilMaskIsHardEdged() throws {
        let width = 9
        let height = 9

        let mask =
            Data(
                repeating:255,
                count:width * height
            )

        let result =
            try CoverEditorEngine.pencilMask(
                mask,
                width:width,
                height:height,
                points:[
                    CGPoint(
                        x:4,
                        y:4
                    )
                ],
                diameter:4,
                value:0,
                flow:1
            )

        XCTAssertEqual(
            result[
                4 * width + 6
            ],
            0
        )

        XCTAssertEqual(
            result[
                4 * width + 7
            ],
            255
        )
    }

    func testPencilMaskInterpolatesStroke() throws {
        let width = 24
        let height = 7

        let mask =
            Data(
                repeating:255,
                count:width * height
            )

        let result =
            try CoverEditorEngine.pencilMask(
                mask,
                width:width,
                height:height,
                points:[
                    CGPoint(
                        x:2,
                        y:3
                    ),
                    CGPoint(
                        x:21,
                        y:3
                    )
                ],
                diameter:2,
                value:0,
                flow:1
            )

        for x in 2...21 {
            XCTAssertEqual(
                result[
                    3 * width + x
                ],
                0,
                "Expected continuous Pencil mask coverage at x=\(x)"
            )
        }
    }

    func testImageAndPaintLayersAllowDirectPencil() {
        let image =
            CoverLayer(
                kind:.image,
                name:"Image",
                frame:CoverRect()
            )

        let paint =
            CoverLayer(
                kind:.paint,
                name:"Paint",
                frame:CoverRect()
            )

        XCTAssertTrue(
            CoverEditorEngine.canPencilPaint(
                image
            )
        )

        XCTAssertTrue(
            CoverEditorEngine.canPencilPaint(
                paint
            )
        )
    }

    func testSmartObjectRejectsDirectPencilArtworkMutation() {
        let smart =
            CoverLayer(
                kind:.smartObject,
                name:"Smart",
                frame:CoverRect()
            )

        XCTAssertFalse(
            CoverEditorEngine.canPencilPaint(
                smart
            )
        )

        XCTAssertTrue(
            CoverEditorEngine.canPencilPaint(
                smart,
                quickMask:true
            )
        )

        XCTAssertTrue(
            CoverEditorEngine.canPencilPaint(
                smart,
                maskSelected:true
            )
        )
    }

    func testLockedLayerRejectsPencil() {
        var layer =
            CoverLayer(
                kind:.image,
                name:"Locked",
                frame:CoverRect()
            )

        layer.locked = true

        XCTAssertFalse(
            CoverEditorEngine.canPencilPaint(
                layer
            )
        )

        XCTAssertFalse(
            CoverEditorEngine.canPencilPaint(
                layer,
                quickMask:true
            )
        )
    }

    func testPixelLockedLayerRejectsDirectPencilButAllowsMask() {
        var layer =
            CoverLayer(
                kind:.image,
                name:"Pixel Locked",
                frame:CoverRect()
            )

        layer.pixelsLocked = true

        XCTAssertFalse(
            CoverEditorEngine.canPencilPaint(
                layer
            )
        )

        XCTAssertTrue(
            CoverEditorEngine.canPencilPaint(
                layer,
                maskSelected:true
            )
        )
    }
}
