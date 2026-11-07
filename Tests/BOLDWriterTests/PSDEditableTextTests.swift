import AppKit
import Foundation
import XCTest
@testable import BOLDWriter

final class PSDEditableTextTests:
    XCTestCase
{
    private func textLayer(
        text:String="Hello",
        name:String="Text"
    )->CoverLayer {
        var layer =
            CoverLayer(
                kind:
                    .text,
                name:
                    name,
                frame:
                    CoverRect(
                        x:
                            0.10,
                        y:
                            0.20,
                        width:
                            0.50,
                        height:
                            0.25
                    )
            )

        layer.text =
            text

        layer.fontName =
            "Georgia"

        layer.fontSize =
            36

        layer.colorHex =
            "#336699"

        layer.alignment =
            "left"

        return layer
    }

    private func markerIndexes(
        _ data:Data,
        marker:[UInt8]
    )->[Int] {
        let bytes =
            [UInt8](
                data
            )

        guard !marker.isEmpty,
              bytes.count
                >= marker.count
        else {
            return []
        }

        var output:[Int] =
            []

        for index
            in 0...(bytes.count - marker.count)
        {
            if Array(
                bytes[
                    index..<(index + marker.count)
                ]
            )
            == marker
            {
                output.append(
                    index
                )
            }
        }

        return output
    }

    private func uint16(
        _ bytes:[UInt8],
        at index:Int
    )->UInt16 {
        (
            UInt16(
                bytes[index]
            )
            << 8
        )
        | UInt16(
            bytes[index + 1]
        )
    }

    private func uint32(
        _ bytes:[UInt8],
        at index:Int
    )->UInt32 {
        (
            UInt32(
                bytes[index]
            )
            << 24
        )
        | (
            UInt32(
                bytes[index + 1]
            )
            << 16
        )
        | (
            UInt32(
                bytes[index + 2]
            )
            << 8
        )
        | UInt32(
            bytes[index + 3]
        )
    }

    private func utf16BE(
        _ value:String
    )->Data {
        var output =
            Data()

        for unit
            in value.utf16
        {
            output.append(
                UInt8(
                    (
                        unit
                        >> 8
                    )
                    & 0xff
                )
            )

            output.append(
                UInt8(
                    unit
                    & 0xff
                )
            )
        }

        return output
    }

    private func psdLayer(
        textTool:PSDExporter.TextTool?
    )->PSDExporter.Layer {
        PSDExporter.Layer(
            id:
                UUID(),
            name:
                "Editable Text",
            top:
                0,
            left:
                0,
            bottom:
                100,
            right:
                200,
            opacity:
                255,
            visible:
                true,
            blendKey:
                "norm",
            clipping:
                0,
            transparencyLocked:
                false,
            channels:
                [
                    PSDExporter.Channel(
                        id:
                            -1,
                        data:
                            Data(
                                [
                                    255,
                                    255,
                                ]
                            )
                    ),
                    PSDExporter.Channel(
                        id:
                            0,
                        data:
                            Data(
                                [
                                    10,
                                    20,
                                ]
                            )
                    ),
                ],
            textTool:
                textTool
        )
    }

    func testEngineFontNamesUsePhotoshopUTF16BEStringEncoding() throws {
        let tool = try XCTUnwrap(PSDExporter.nativeTextTool(for: textLayer(), canvasWidth: 1200, canvasHeight: 1800))
        let data = PSDExporter.textEngineData(tool)
        for key in ["/Name (", "/FamilyName ("] {
            var prefix = Data(key.utf8); prefix.append(contentsOf: [0xfe, 0xff])
            XCTAssertNotNil(data.range(of: prefix), "Every engine string, including font names, requires a Unicode marker")
        }
    }

    func testSimpleTextIsRepresentable() throws {
        let layer =
            textLayer()

        let tool =
            try XCTUnwrap(
                PSDExporter
                    .nativeTextTool(
                        for:
                            layer,
                        canvasWidth:
                            1200,
                        canvasHeight:
                            1800
                    )
            )

        XCTAssertEqual(
            tool.text,
            "Hello"
        )

        XCTAssertEqual(
            tool.fontSize,
            36
        )

        XCTAssertFalse(
            tool.fontPostScriptName
                .isEmpty
        )

        XCTAssertFalse(
            tool.fontFamilyName
                .isEmpty
        )
    }

    func testUnicodeTextIsPreserved() throws {
        let layer =
            textLayer(
                text:
                    "Résumé Ω 世界"
            )

        let tool =
            try XCTUnwrap(
                PSDExporter
                    .nativeTextTool(
                        for:
                            layer,
                        canvasWidth:
                            1000,
                        canvasHeight:
                            1000
                    )
            )

        let data =
            PSDExporter
                .typeToolData(
                    tool
                )

        XCTAssertFalse(
            markerIndexes(
                data,
                marker:
                    [UInt8](
                        utf16BE(
                            "Résumé Ω 世界"
                        )
                    )
            )
            .isEmpty
        )
    }

    func testMultilineTextIsPreserved() throws {
        let layer =
            textLayer(
                text:
                    "First\nSecond"
            )

        let tool =
            try XCTUnwrap(
                PSDExporter
                    .nativeTextTool(
                        for:
                            layer,
                        canvasWidth:
                            1000,
                        canvasHeight:
                            1000
                    )
            )

        XCTAssertEqual(
            tool.text,
            "First\nSecond"
        )

        let data =
            PSDExporter
                .typeToolData(
                    tool
                )

        XCTAssertFalse(
            data.isEmpty
        )
    }

    func testTypeToolPayloadStartsWithRequiredVersions() throws {
        let tool =
            try XCTUnwrap(
                PSDExporter
                    .nativeTextTool(
                        for:
                            textLayer(),
                        canvasWidth:
                            1000,
                        canvasHeight:
                            1000
                    )
            )

        let data =
            PSDExporter
                .typeToolData(
                    tool
                )

        let bytes =
            [UInt8](
                data
            )

        XCTAssertGreaterThan(
            bytes.count,
            60
        )

        XCTAssertEqual(
            uint16(
                bytes,
                at:
                    0
            ),
            1
        )

        XCTAssertEqual(
            uint16(
                bytes,
                at:
                    50
            ),
            50
        )

        XCTAssertEqual(
            uint32(
                bytes,
                at:
                    52
            ),
            16
        )
    }

    func testTypeToolPayloadContainsEngineData() throws {
        let tool =
            try XCTUnwrap(
                PSDExporter
                    .nativeTextTool(
                        for:
                            textLayer(),
                        canvasWidth:
                            1000,
                        canvasHeight:
                            1000
                    )
            )

        let data =
            PSDExporter
                .typeToolData(
                    tool
                )

        XCTAssertFalse(
            markerIndexes(
                data,
                marker:
                    Array(
                        "EngineData".utf8
                    )
            )
            .isEmpty
        )
    }

    func testTypeToolPayloadIsDeterministic() throws {
        let tool =
            try XCTUnwrap(
                PSDExporter
                    .nativeTextTool(
                        for:
                            textLayer(),
                        canvasWidth:
                            1000,
                        canvasHeight:
                            1000
                    )
            )

        XCTAssertEqual(
            PSDExporter
                .typeToolData(
                    tool
                ),
            PSDExporter
                .typeToolData(
                    tool
                )
        )
    }

    func testLayerAndMaskDataWritesTySh() throws {
        let tool =
            try XCTUnwrap(
                PSDExporter
                    .nativeTextTool(
                        for:
                            textLayer(),
                        canvasWidth:
                            1000,
                        canvasHeight:
                            1000
                    )
            )

        let data =
            try PSDExporter
                .layerAndMaskData(
                    layers:
                        [
                            psdLayer(
                                textTool:
                                    tool
                            ),
                        ]
                )

        XCTAssertFalse(
            markerIndexes(
                data,
                marker:
                    Array(
                        "8BIMTySh".utf8
                    )
            )
            .isEmpty
        )
    }

    func testNativeTextStillCarriesRasterChannels() throws {
        let tool =
            try XCTUnwrap(
                PSDExporter
                    .nativeTextTool(
                        for:
                            textLayer(),
                        canvasWidth:
                            1000,
                        canvasHeight:
                            1000
                    )
            )

        let layer =
            psdLayer(
                textTool:
                    tool
            )

        XCTAssertEqual(
            layer.channels.count,
            2
        )

        XCTAssertFalse(
            layer.channels[0]
                .data
                .isEmpty
        )
    }

    func testUnicodeLayerNameStillWritesLuni() throws {
        let tool =
            try XCTUnwrap(
                PSDExporter
                    .nativeTextTool(
                        for:
                            textLayer(),
                        canvasWidth:
                            1000,
                        canvasHeight:
                            1000
                    )
            )

        var layer =
            psdLayer(
                textTool:
                    tool
            )

        layer.name =
            "Tëxt Ω"

        let data =
            try PSDExporter
                .layerAndMaskData(
                    layers:
                        [
                            layer,
                        ]
                )

        XCTAssertFalse(
            markerIndexes(
                data,
                marker:
                    Array(
                        "8BIMluni".utf8
                    )
            )
            .isEmpty
        )
    }

    func testAlignmentMapping() throws {
        var left =
            textLayer()

        left.alignment =
            "left"

        var right =
            textLayer()

        right.alignment =
            "right"

        var center =
            textLayer()

        center.alignment =
            "center"

        var justified =
            textLayer()

        justified.alignment =
            "justified"

        XCTAssertEqual(
            PSDExporter
                .nativeTextTool(
                    for:
                        left,
                    canvasWidth:
                        1000,
                    canvasHeight:
                        1000
                )?
                .alignment,
            0
        )

        XCTAssertEqual(
            PSDExporter
                .nativeTextTool(
                    for:
                        right,
                    canvasWidth:
                        1000,
                    canvasHeight:
                        1000
                )?
                .alignment,
            1
        )

        XCTAssertEqual(
            PSDExporter
                .nativeTextTool(
                    for:
                        center,
                    canvasWidth:
                        1000,
                    canvasHeight:
                        1000
                )?
                .alignment,
            2
        )

        XCTAssertEqual(
            PSDExporter
                .nativeTextTool(
                    for:
                        justified,
                    canvasWidth:
                        1000,
                    canvasHeight:
                        1000
                )?
                .alignment,
            3
        )
    }

    func testAdvancedTypographyMapsIntoPayload() throws {
        var layer =
            textLayer()

        layer.letterSpacing =
            4

        layer.leading =
            48

        layer.underline =
            true

        layer.strikethrough =
            true

        layer.horizontalScale =
            1.2

        layer.verticalScale =
            0.9

        layer.baselineShift =
            3

        layer.paragraphIndent =
            12

        layer.paragraphSpacing =
            8

        let tool =
            try XCTUnwrap(
                PSDExporter
                    .nativeTextTool(
                        for:
                            layer,
                        canvasWidth:
                            1000,
                        canvasHeight:
                            1000
                    )
            )

        XCTAssertEqual(
            tool.tracking,
            4
        )

        XCTAssertEqual(
            tool.leading,
            48
        )

        XCTAssertTrue(
            tool.underline
        )

        XCTAssertTrue(
            tool.strikethrough
        )

        XCTAssertEqual(
            tool.horizontalScale,
            1.2
        )

        XCTAssertEqual(
            tool.verticalScale,
            0.9
        )

        XCTAssertEqual(
            tool.baselineShift,
            3
        )

        XCTAssertEqual(
            tool.paragraphIndent,
            12
        )

        XCTAssertEqual(
            tool.paragraphSpacing,
            8
        )
    }

    func testRotationProducesTypeToolTransform() throws {
        var layer =
            textLayer()

        layer.rotation =
            30

        let tool =
            try XCTUnwrap(
                PSDExporter
                    .nativeTextTool(
                        for:
                            layer,
                        canvasWidth:
                            1000,
                        canvasHeight:
                            1000
                    )
            )

        XCTAssertNotEqual(
            tool.xy,
            0,
            accuracy:
                0.0001
        )

        XCTAssertNotEqual(
            tool.yx,
            0,
            accuracy:
                0.0001
        )
    }

    func testFrameMapsToTypeBounds() throws {
        let layer =
            textLayer()

        let tool =
            try XCTUnwrap(
                PSDExporter
                    .nativeTextTool(
                        for:
                            layer,
                        canvasWidth:
                            1000,
                        canvasHeight:
                            2000
                    )
            )

        XCTAssertEqual(
            tool.right,
            500,
            accuracy:
                0.0001
        )

        XCTAssertEqual(
            tool.bottom,
            500,
            accuracy:
                0.0001
        )
    }

    func testWarpFallsBackToRasterOnly() {
        var layer =
            textLayer()

        layer.warpAmount =
            0.25

        XCTAssertNil(
            PSDExporter
                .nativeTextTool(
                    for:
                        layer,
                    canvasWidth:
                        1000,
                    canvasHeight:
                        1000
                )
        )
    }

    func testSkewFallsBackToRasterOnly() {
        var layer =
            textLayer()

        layer.skewX =
            0.25

        XCTAssertNil(
            PSDExporter
                .nativeTextTool(
                    for:
                        layer,
                    canvasWidth:
                        1000,
                    canvasHeight:
                        1000
                )
        )
    }

    func testFlipFallsBackToRasterOnly() {
        var layer =
            textLayer()

        layer.flipHorizontal =
            true

        XCTAssertNil(
            PSDExporter
                .nativeTextTool(
                    for:
                        layer,
                    canvasWidth:
                        1000,
                    canvasHeight:
                        1000
                )
        )
    }

    func testMaskFallsBackToRasterOnly() {
        var layer =
            textLayer()

        layer.maskData =
            Data(
                [
                    0,
                ]
            )

        XCTAssertNil(
            PSDExporter
                .nativeTextTool(
                    for:
                        layer,
                    canvasWidth:
                        1000,
                    canvasHeight:
                        1000
                )
        )
    }

    func testUnsupportedFallbackDoesNotWriteTySh() throws {
        let data =
            try PSDExporter
                .layerAndMaskData(
                    layers:
                        [
                            psdLayer(
                                textTool:
                                    nil
                            ),
                        ]
                )

        XCTAssertTrue(
            markerIndexes(
                data,
                marker:
                    Array(
                        "8BIMTySh".utf8
                    )
            )
            .isEmpty
        )
    }

    func testNativeTextSurvivesNativeGroupWrapping() throws {
        let folder =
            CoverLayer(
                kind:
                    .group,
                name:
                    "Folder"
            )

        var source =
            textLayer()

        source.groupID =
            folder.id

        let tool =
            try XCTUnwrap(
                PSDExporter
                    .nativeTextTool(
                        for:
                            source,
                        canvasWidth:
                            1000,
                        canvasHeight:
                            1000
                    )
            )

        let artwork =
            psdLayer(
                textTool:
                    tool
            )

        let result =
            PSDExporter
                .nativeGroupFolderLayers(
                    projectLayers:
                        [
                            source,
                            folder,
                        ],
                    candidates:
                        [
                            source,
                        ],
                    artworkLayers:
                        [
                            artwork,
                        ]
                )

        XCTAssertEqual(
            result.count,
            3
        )

        XCTAssertEqual(
            result[0]
                .sectionDividerType,
            3
        )

        XCTAssertNotNil(
            result[1]
                .textTool
        )

        XCTAssertEqual(
            result[2]
                .sectionDividerType,
            1
        )
    }

    func testTypeToolLayerRetainsOpacityVisibilityBlendAndClipping() throws {
        let tool =
            try XCTUnwrap(
                PSDExporter
                    .nativeTextTool(
                        for:
                            textLayer(),
                        canvasWidth:
                            1000,
                        canvasHeight:
                            1000
                    )
            )

        var layer =
            psdLayer(
                textTool:
                    tool
            )

        layer.opacity =
            91

        layer.visible =
            false

        layer.blendKey =
            "mul "

        layer.clipping =
            1

        XCTAssertEqual(
            layer.opacity,
            91
        )

        XCTAssertFalse(
            layer.visible
        )

        XCTAssertEqual(
            layer.blendKey,
            "mul "
        )

        XCTAssertEqual(
            layer.clipping,
            1
        )

        XCTAssertNotNil(
            layer.textTool
        )
    }
}
