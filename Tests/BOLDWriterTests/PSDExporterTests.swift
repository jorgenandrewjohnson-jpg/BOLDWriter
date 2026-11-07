import XCTest
import AppKit
import ImageIO
@testable import BOLDWriter

final class PSDExporterTests:
    XCTestCase
{
    private struct ParsedLayer {
        var top: Int
        var left: Int
        var bottom: Int
        var right: Int
        var channelIDs: [Int16]
        var channelLengths: [Int]
        var blendKey: String
        var opacity: UInt8
        var clipping: UInt8
        var flags: UInt8
        var pascalName: String
        var unicodeName: String?
        var channelData: [Int16: Data]
    }

    private struct ParsedPSD {
        var version: UInt16
        var channels: UInt16
        var width: Int
        var height: Int
        var depth: UInt16
        var colorMode: UInt16
        var colorModeLength: Int
        var imageResourcesLength: Int
        var layers: [ParsedLayer]
        var compositeCompression: UInt16
        var compositeBytes: Data
    }

    private struct Reader {
        var data: Data
        var offset = 0

        mutating func byte() throws -> UInt8 {
            guard offset < data.count else {
                throw NSError(domain: "PSDTest", code: 1)
            }
            defer { offset += 1 }
            return data[offset]
        }

        mutating func uint16() throws -> UInt16 {
            let a = UInt16(try byte())
            let b = UInt16(try byte())
            return (a << 8) | b
        }

        mutating func int16() throws -> Int16 {
            Int16(bitPattern: try uint16())
        }

        mutating func uint32() throws -> UInt32 {
            let a = UInt32(try byte())
            let b = UInt32(try byte())
            let c = UInt32(try byte())
            let d = UInt32(try byte())
            return (a << 24) | (b << 16) | (c << 8) | d
        }

        mutating func int32() throws -> Int32 {
            Int32(bitPattern: try uint32())
        }

        mutating func bytes(_ count: Int) throws -> Data {
            guard count >= 0,
                  offset <= data.count - count else {
                throw NSError(domain: "PSDTest", code: 2)
            }
            let result = data.subdata(in: offset..<(offset + count))
            offset += count
            return result
        }

        mutating func skip(_ count: Int) throws {
            _ = try bytes(count)
        }

        mutating func signature() throws -> String {
            String(data: try bytes(4), encoding: .ascii) ?? ""
        }
    }

    private func png(
        width: Int = 4,
        height: Int = 4,
        color: NSColor = .systemRed,
        alpha: UInt8 = 255
    ) throws -> Data {
        guard let bitmap =
                NSBitmapImageRep(
                    bitmapDataPlanes: nil,
                    pixelsWide: width,
                    pixelsHigh: height,
                    bitsPerSample: 8,
                    samplesPerPixel: 4,
                    hasAlpha: true,
                    isPlanar: false,
                    colorSpaceName: .deviceRGB,
                    bytesPerRow: width * 4,
                    bitsPerPixel: 32
                ),
              let bytes = bitmap.bitmapData else {
            throw XCTSkip("Unable to create RGBA fixture.")
        }

        let converted = color.usingColorSpace(.deviceRGB) ?? .black
        let red = UInt8(max(0, min(255, Int((converted.redComponent * 255).rounded()))))
        let green = UInt8(max(0, min(255, Int((converted.greenComponent * 255).rounded()))))
        let blue = UInt8(max(0, min(255, Int((converted.blueComponent * 255).rounded()))))

        for index in 0..<(width * height) {
            bytes[index * 4] = red
            bytes[index * 4 + 1] = green
            bytes[index * 4 + 2] = blue
            bytes[index * 4 + 3] = alpha
        }

        guard let data =
                bitmap.representation(
                    using: .png,
                    properties: [:]
                ) else {
            throw XCTSkip("Unable to encode PNG fixture.")
        }

        return data
    }

    private func project(
        width: Double = 1,
        height: Double = 1,
        dpi: Double = 4
    ) -> CoverProject {
        var value =
            CoverProject(
                width: width,
                height: height
            )
        value.dpi = dpi
        return value
    }

    private func imageLayer(
        name: String = "Layer",
        color: NSColor = .systemRed
    ) throws -> CoverLayer {
        var layer =
            CoverLayer(
                kind: .image,
                name: name,
                frame: CoverRect(
                    x: 0,
                    y: 0,
                    width: 1,
                    height: 1
                )
            )

        layer.imageData =
            try png(
                color: color
            )

        layer.cropMode = .fill
        return layer
    }

    private func parse(
        _ data: Data
    ) throws -> ParsedPSD {
        var reader =
            Reader(
                data: data
            )

        XCTAssertEqual(
            try reader.signature(),
            "8BPS"
        )

        let version = try reader.uint16()
        _ = try reader.bytes(6)
        let channels = try reader.uint16()
        let height = Int(try reader.uint32())
        let width = Int(try reader.uint32())
        let depth = try reader.uint16()
        let colorMode = try reader.uint16()

        let colorModeLength = Int(try reader.uint32())
        try reader.skip(colorModeLength)

        let resourcesLength = Int(try reader.uint32())
        try reader.skip(resourcesLength)

        let layerMaskLength = Int(try reader.uint32())
        let layerMaskStart = reader.offset

        var layers: [ParsedLayer] = []

        if layerMaskLength > 0 {
            let layerInfoLength = Int(try reader.uint32())
            let layerInfoStart = reader.offset

            if layerInfoLength > 0 {
                let layerCount =
                    abs(
                        Int(
                            try reader.int16()
                        )
                    )

                var channelDescriptors:
                    [[(id: Int16, length: Int)]] = []

                for _ in 0..<layerCount {
                    let top = Int(try reader.int32())
                    let left = Int(try reader.int32())
                    let bottom = Int(try reader.int32())
                    let right = Int(try reader.int32())
                    let channelCount = Int(try reader.uint16())

                    var descriptors:
                        [(id: Int16, length: Int)] = []

                    for _ in 0..<channelCount {
                        descriptors.append(
                            (
                                try reader.int16(),
                                Int(
                                    try reader.uint32()
                                )
                            )
                        )
                    }

                    XCTAssertEqual(
                        try reader.signature(),
                        "8BIM"
                    )

                    let blendKey = try reader.signature()
                    let opacity = try reader.byte()
                    let clipping = try reader.byte()
                    let flags = try reader.byte()
                    _ = try reader.byte()

                    let extraLength = Int(try reader.uint32())
                    let extraStart = reader.offset

                    let maskLength = Int(try reader.uint32())
                    try reader.skip(maskLength)

                    let rangesLength = Int(try reader.uint32())
                    try reader.skip(rangesLength)

                    let pascalStart = reader.offset
                    let nameLength = Int(try reader.byte())
                    let nameData = try reader.bytes(nameLength)

                    let pascalName =
                        String(
                            data: nameData,
                            encoding: .ascii
                        )
                        ?? ""

                    while (reader.offset - pascalStart) % 4 != 0 {
                        _ = try reader.byte()
                    }

                    var unicodeName: String?

                    while reader.offset < extraStart + extraLength {
                        let signature = try reader.signature()
                        let key = try reader.signature()
                        let length = Int(try reader.uint32())
                        let blockStart = reader.offset

                        if signature == "8BIM",
                           key == "luni",
                           length >= 4 {
                            let count = Int(try reader.uint32())
                            var units: [UInt16] = []
                            units.reserveCapacity(count)

                            for _ in 0..<count {
                                units.append(
                                    try reader.uint16()
                                )
                            }

                            unicodeName =
                                String(
                                    decoding: units,
                                    as: UTF16.self
                                )
                        }

                        reader.offset = blockStart + length

                        if length % 2 != 0 {
                            reader.offset += 1
                        }
                    }

                    reader.offset = extraStart + extraLength

                    layers.append(
                        ParsedLayer(
                            top: top,
                            left: left,
                            bottom: bottom,
                            right: right,
                            channelIDs: descriptors.map(\.id),
                            channelLengths: descriptors.map(\.length),
                            blendKey: blendKey,
                            opacity: opacity,
                            clipping: clipping,
                            flags: flags,
                            pascalName: pascalName,
                            unicodeName: unicodeName,
                            channelData: [:]
                        )
                    )

                    channelDescriptors.append(descriptors)
                }

                for layerIndex in layers.indices {
                    var values: [Int16: Data] = [:]

                    for descriptor in channelDescriptors[layerIndex] {
                        XCTAssertGreaterThanOrEqual(
                            descriptor.length,
                            2
                        )

                        XCTAssertEqual(
                            try reader.uint16(),
                            0
                        )

                        values[descriptor.id] =
                            try reader.bytes(
                                descriptor.length - 2
                            )
                    }

                    layers[layerIndex].channelData = values
                }

                reader.offset =
                    layerInfoStart
                    + layerInfoLength
            }

            if reader.offset + 4 <= layerMaskStart + layerMaskLength {
                let globalMaskLength = Int(try reader.uint32())
                try reader.skip(globalMaskLength)
            }

            reader.offset =
                layerMaskStart
                + layerMaskLength
        }

        let compositeCompression = try reader.uint16()

        let compositeBytes =
            try reader.bytes(
                data.count - reader.offset
            )

        return ParsedPSD(
            version: version,
            channels: channels,
            width: width,
            height: height,
            depth: depth,
            colorMode: colorMode,
            colorModeLength: colorModeLength,
            imageResourcesLength: resourcesLength,
            layers: layers,
            compositeCompression: compositeCompression,
            compositeBytes: compositeBytes
        )
    }

    func testHeaderIsRealPSDVersionOneRGB8() throws {
        var value = project()
        value.layers = [try imageLayer()]
        let data = try PSDExporter.export(value)

        XCTAssertEqual(
            String(data: data.prefix(4), encoding: .ascii),
            "8BPS"
        )

        let parsed = try parse(data)
        XCTAssertEqual(parsed.version, 1)
        XCTAssertEqual(parsed.channels, 3)
        XCTAssertEqual(parsed.depth, 8)
        XCTAssertEqual(parsed.colorMode, 3)
    }

    func testResolutionResourcePreservesPhysicalPrintSize() throws {
        var value = project(width: 2, height: 3, dpi: 137.5)
        value.layers = [try imageLayer()]
        let data = try PSDExporter.export(value)
        // ImageIO omits PSD DPI metadata on this macOS version. Read the
        // standard resource independently instead of accepting its 72-DPI default.
        var reader = Reader(data: data, offset: 26)
        let colorLength = Int(try reader.uint32()); reader.offset += colorLength
        XCTAssertEqual(try reader.uint32(), 28)
        XCTAssertEqual(String(decoding: data[reader.offset..<(reader.offset+4)], as: UTF8.self), "8BIM")
        reader.offset += 4
        XCTAssertEqual(try reader.uint16(), 1005)
        XCTAssertEqual(try reader.uint16(), 0)
        XCTAssertEqual(try reader.uint32(), 16)
        for _ in 0..<2 {
            XCTAssertEqual(Double(try reader.uint32()) / 65_536, 137.5, accuracy: 0.0001)
            XCTAssertEqual(try reader.uint16(), 1)
            XCTAssertEqual(try reader.uint16(), 1)
        }
    }

    func testPSDCompositeImportPreservesResolutionAndPhysicalDimensions() throws {
        var value = project(width: 2, height: 3, dpi: 137.5)
        value.layers = [try imageLayer()]
        let imported = try CoverImport.project(data: PSDExporter.export(value), filename: "Proof.psd")
        XCTAssertEqual(imported.dpi, 137.5, accuracy: 0.0001)
        XCTAssertEqual(imported.canvasWidth, 2, accuracy: 0.01)
        XCTAssertEqual(imported.canvasHeight, 3, accuracy: 0.01)
        XCTAssertEqual(imported.layers.count, 1) // Explicitly a composite import.
    }

    func testPSDResolutionRejectsTruncatedAndUnequalAxisResources() throws {
        let value = project(width: 2, height: 3, dpi: 137.5)
        var data = try PSDExporter.export(value)
        XCTAssertThrowsError(try CoverImport.photoshopResolution(data: Data(data.prefix(40))))
        // Vertical fixed-point resolution starts at offset 54 in this file.
        data[54] = 0; data[55] = 150; data[56] = 0; data[57] = 0
        XCTAssertThrowsError(try CoverImport.photoshopResolution(data: data))
    }

    func testHeaderDimensionsAreBigEndianAndCorrect() throws {
        var value = project(width: 2, height: 3, dpi: 4)
        value.layers = [try imageLayer()]

        let parsed = try parse(PSDExporter.export(value))
        XCTAssertEqual(parsed.width, 8)
        XCTAssertEqual(parsed.height, 12)
    }

    func testColorModeAndImageResourceSectionsExist() throws {
        var value = project()
        value.layers = [try imageLayer()]

        let parsed = try parse(PSDExporter.export(value))
        XCTAssertEqual(parsed.colorModeLength, 0)
        XCTAssertEqual(parsed.imageResourcesLength, 28)
    }

    func testRejectsZeroDimensions() {
        var value = project()
        value.canvasWidth = 0
        XCTAssertThrowsError(try PSDExporter.export(value))
    }

    func testRejectsDimensionsOverPSDVersionOneLimit() {
        var value = project(width: 30_001, height: 1, dpi: 1)
        value.layers = []
        XCTAssertThrowsError(try PSDExporter.export(value))
    }

    func testSingleRasterLayerProducesIndependentPSDLayer() throws {
        var value = project()
        value.layers = [try imageLayer(name: "Raster")]

        let parsed = try parse(PSDExporter.export(value))
        XCTAssertEqual(parsed.layers.count, 1)
        XCTAssertEqual(parsed.layers[0].unicodeName, "Raster")
        XCTAssertEqual(parsed.layers[0].channelIDs, [-1, 0, 1, 2])
    }

    func testMultipleLayersPreserveBOLDStackingOrder() throws {
        var value = project()

        value.layers = [
            try imageLayer(name: "Bottom", color: .systemRed),
            try imageLayer(name: "Middle", color: .systemGreen),
            try imageLayer(name: "Top", color: .systemBlue),
        ]

        let parsed = try parse(PSDExporter.export(value))

        XCTAssertEqual(
            parsed.layers.compactMap(\.unicodeName),
            ["Bottom", "Middle", "Top"]
        )
    }

    func testUnicodeLayerNameUsesLuni() throws {
        var value = project()
        value.layers = [try imageLayer(name: "Título — שלום — 漢字")]

        let parsed = try parse(PSDExporter.export(value))
        XCTAssertEqual(parsed.layers[0].unicodeName, "Título — שלום — 漢字")
    }

    func testOpacityPreservedInLayerRecord() throws {
        var layer = try imageLayer()
        layer.opacity = 0.5

        var value = project()
        value.layers = [layer]

        let parsed = try parse(PSDExporter.export(value))
        XCTAssertEqual(parsed.layers[0].opacity, 128)
    }

    func testHiddenLayerSetsPhotoshopHiddenFlag() throws {
        var layer = try imageLayer()
        layer.visible = false

        var value = project()
        value.layers = [layer]

        let parsed = try parse(PSDExporter.export(value))
        XCTAssertNotEqual(parsed.layers[0].flags & 0x02, 0)
    }

    func testVisibleLayerDoesNotSetHiddenFlag() throws {
        var value = project()
        value.layers = [try imageLayer()]

        let parsed = try parse(PSDExporter.export(value))
        XCTAssertEqual(parsed.layers[0].flags & 0x02, 0)
    }

    func testTransparencyLockMapsToLayerFlag() throws {
        var layer = try imageLayer()
        layer.transparencyLocked = true

        var value = project()
        value.layers = [layer]

        let parsed = try parse(PSDExporter.export(value))
        XCTAssertNotEqual(parsed.layers[0].flags & 0x01, 0)
    }

    func testNormalBlendModeMapsToNorm() {
        XCTAssertEqual(PSDExporter.blendKey(.normal), "norm")
        XCTAssertEqual(PSDExporter.blendKey(nil), "norm")
    }

    func testCoreBlendModeMappings() {
        XCTAssertEqual(PSDExporter.blendKey(.multiply), "mul ")
        XCTAssertEqual(PSDExporter.blendKey(.screen), "scrn")
        XCTAssertEqual(PSDExporter.blendKey(.overlay), "over")
        XCTAssertEqual(PSDExporter.blendKey(.colorBurn), "idiv")
        XCTAssertEqual(PSDExporter.blendKey(.colorDodge), "div ")
        XCTAssertEqual(PSDExporter.blendKey(.softLight), "sLit")
        XCTAssertEqual(PSDExporter.blendKey(.hardLight), "hLit")
    }

    func testAllCurrentBlendModesProduceFourCharacterPSDKeys() {
        for mode in CoverBlendMode.allCases {
            XCTAssertEqual(PSDExporter.blendKey(mode).utf8.count, 4)
        }
    }

    func testLayerChannelsUseRawCompressionAndExpectedLengths() throws {
        var value = project()
        value.layers = [try imageLayer()]

        let parsed = try parse(PSDExporter.export(value))
        let layer = parsed.layers[0]

        XCTAssertEqual(layer.right - layer.left, 4)
        XCTAssertEqual(layer.bottom - layer.top, 4)
        XCTAssertEqual(layer.channelLengths, [18, 18, 18, 18])

        for data in layer.channelData.values {
            XCTAssertEqual(data.count, 16)
        }
    }

    func testTransparentAlphaIsPreserved() throws {
        var layer =
            CoverLayer(
                kind: .image,
                name: "Transparent",
                frame: CoverRect(x: 0, y: 0, width: 1, height: 1)
            )

        layer.imageData = try png(alpha: 0)

        var value = project()
        value.layers = [layer]

        let parsed = try parse(PSDExporter.export(value))

        XCTAssertEqual(parsed.layers[0].top, 0)
        XCTAssertEqual(parsed.layers[0].bottom, 0)
        XCTAssertTrue(parsed.layers[0].channelData[-1]?.isEmpty == true)
    }

    func testPaintLayerExports() throws {
        var layer = try imageLayer(name: "Paint")
        layer.kind = .paint

        var value = project()
        value.layers = [layer]

        let parsed = try parse(PSDExporter.export(value))
        XCTAssertEqual(parsed.layers[0].unicodeName, "Paint")
    }

    func testSmartObjectExportsAsRasterFallbackWithoutSourceMutation() throws {
        let source = try png(color: .systemGreen)

        let smart =
            try CoverEditorEngine.smartObjectLayerFromEmbeddedSource(
                data: source,
                filename: "Embedded.png",
                project: project()
            )

        var value = project()
        value.layers = [smart]

        let before =
            try XCTUnwrap(
                value.layers[0].smartObject?.sourceData
            )

        let parsed = try parse(PSDExporter.export(value))

        XCTAssertEqual(parsed.layers.count, 1)
        XCTAssertEqual(parsed.layers[0].unicodeName, "Embedded.png")
        XCTAssertEqual(value.layers[0].smartObject?.sourceData, before)
    }

    func testTextLayerDegradesToRasterLayer() throws {
        var text =
            CoverLayer(
                kind: .text,
                name: "Editable in BOLD",
                frame: CoverRect(x: 0.05, y: 0.05, width: 0.9, height: 0.9)
            )

        text.text = "BOLD"
        text.fontSize = 10

        var value = project(width: 2, height: 2, dpi: 20)
        value.layers = [text]

        let parsed = try parse(PSDExporter.export(value))
        XCTAssertEqual(parsed.layers.count, 1)
        XCTAssertEqual(parsed.layers[0].unicodeName, "Editable in BOLD")
    }

    func testShapeLayerDegradesToRasterLayer() throws {
        var shape =
            CoverLayer(
                kind: .shape,
                name: "Vector Rectangle",
                frame: CoverRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
            )

        shape.shape = .rectangle
        shape.fillHex = "#FF0000"

        var value = project(width: 2, height: 2, dpi: 20)
        value.layers = [shape]

        let parsed = try parse(PSDExporter.export(value))
        XCTAssertEqual(parsed.layers.count, 1)
        XCTAssertEqual(parsed.layers[0].unicodeName, "Vector Rectangle")
    }

    func testPathLayerDegradesToRasterLayer() throws {
        var path =
            CoverLayer(
                kind: .path,
                name: "Editable Path",
                frame: CoverRect(x: 0, y: 0, width: 1, height: 1)
            )

        path.pathPoints = [
            CoverPathPoint(x: 0.1, y: 0.1),
            CoverPathPoint(x: 0.9, y: 0.1),
            CoverPathPoint(x: 0.9, y: 0.9),
            CoverPathPoint(x: 0.1, y: 0.9),
        ]

        path.pathClosed = true
        path.fillHex = "#00FF00"

        var value = project(width: 2, height: 2, dpi: 20)
        value.layers = [path]

        let parsed = try parse(PSDExporter.export(value))
        XCTAssertEqual(parsed.layers.count, 1)
        XCTAssertEqual(parsed.layers[0].unicodeName, "Editable Path")
    }

    func testGradientLayerExportsAsRasterFallback() throws {
        var gradient =
            CoverLayer(
                kind: .gradient,
                name: "Gradient",
                frame: CoverRect(x: 0, y: 0, width: 1, height: 1)
            )

        gradient.fillHex = "#FF0000"
        gradient.gradientEndHex = "#0000FF"

        var value = project(width: 2, height: 2, dpi: 20)
        value.layers = [gradient]

        let parsed = try parse(PSDExporter.export(value))
        XCTAssertEqual(parsed.layers.count, 1)
        XCTAssertEqual(parsed.layers[0].unicodeName, "Gradient")
    }

    func testAdjustmentLayerIsBakedIntoCompositeNotWrittenAsNativePSDAdjustment() throws {
        var base = try imageLayer(name: "Base")
        base.frame = CoverRect()

        var adjustment =
            CoverLayer(
                kind: .adjustment,
                name: "Brightness"
            )

        adjustment.adjustment = .brightnessContrast
        adjustment.adjustmentValues = [
            "brightness": 0.25,
            "contrast": 0.1,
        ]

        var value = project()
        value.layers = [base, adjustment]

        let parsed = try parse(PSDExporter.export(value))

        XCTAssertEqual(parsed.layers.count, 1)
        XCTAssertGreaterThan(parsed.compositeBytes.count, 0)
    }

    func testGroupContainerExportsNativeFolderAndMemberLayerIsNotLost() throws {
        let groupID = UUID()

        var group =
            CoverLayer(
                kind: .group,
                name: "Folder"
            )

        group.id = groupID

        var child = try imageLayer(name: "Child")
        child.groupID = groupID

        var value = project()
        value.layers = [group, child]

        let parsed = try parse(PSDExporter.export(value))
        XCTAssertEqual(parsed.layers.count, 3)
        XCTAssertEqual(parsed.layers[2].unicodeName, "Folder")
    }

    func testHiddenGroupMakesFlattenedMemberPSDLayerHidden() throws {
        let groupID = UUID()

        var group =
            CoverLayer(
                kind: .group,
                name: "Hidden Folder"
            )

        group.id = groupID
        group.visible = false

        var child = try imageLayer(name: "Child")
        child.groupID = groupID

        var value = project()
        value.layers = [group, child]

        let parsed = try parse(PSDExporter.export(value))
        XCTAssertNotEqual(parsed.layers[0].flags & 0x02, 0)
    }

    func testValidClippingRelationshipMapsToPSDClippingByte() throws {
        let base = try imageLayer(name: "Base")

        var clipped =
            try imageLayer(
                name: "Clipped",
                color: .systemBlue
            )

        clipped.clippedToLayerID = base.id

        var value = project()
        value.layers = [base, clipped]

        let parsed = try parse(PSDExporter.export(value))
        XCTAssertEqual(parsed.layers.map(\.clipping), [0, 1])
    }

    func testMalformedClippingRelationshipDegradesToBaseLayer() throws {
        var clipped = try imageLayer(name: "Orphan")
        clipped.clippedToLayerID = UUID()

        var value = project()
        value.layers = [clipped]

        let parsed = try parse(PSDExporter.export(value))
        XCTAssertEqual(parsed.layers[0].clipping, 0)
    }

    func testMaskIsDeterministicallyBakedIntoPSDLayerRaster() throws {
        var layer = try imageLayer(name: "Masked")

        let mask =
            Data(
                repeating: 0,
                count: 16
            )

        layer.maskData =
            CoverEditorEngine.encodedMask(
                mask,
                width: 4,
                height: 4
            )

        layer.maskEnabled = true

        var value = project()
        value.layers = [layer]

        let parsed = try parse(PSDExporter.export(value))
        let alpha = parsed.layers[0].channelData[-1] ?? Data()

        XCTAssertTrue(
            alpha.isEmpty
            || alpha.allSatisfy {
                $0 == 0
            }
        )
    }

    func testFlattenedCompositeUsesRawPlanarRGB() throws {
        var value = project()
        value.layers = [try imageLayer()]

        let parsed = try parse(PSDExporter.export(value))
        XCTAssertEqual(parsed.compositeCompression, 0)

        XCTAssertEqual(
            parsed.compositeBytes.count,
            parsed.width * parsed.height * 3
        )
    }

    func testExportIsDeterministicForFixedProject() throws {
        var value = project()
        value.layers = [try imageLayer(name: "Stable")]

        XCTAssertEqual(
            try PSDExporter.export(value),
            try PSDExporter.export(value)
        )
    }

    func testExportDoesNotMutateProject() throws {
        var value = project()
        value.layers = [try imageLayer()]

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let before =
            try encoder.encode(value)

        let semanticBefore =
            try JSONDecoder()
                .decode(
                    CoverProject.self,
                    from: before
                )

        _ = try PSDExporter.export(value)

        let after =
            try encoder.encode(value)

        let semanticAfter =
            try JSONDecoder()
                .decode(
                    CoverProject.self,
                    from: after
                )

        XCTAssertEqual(
            before,
            after
        )

        XCTAssertEqual(
            semanticBefore,
            semanticAfter
        )

        XCTAssertEqual(
            value,
            semanticBefore
        )
    }

    func testCoverArtworkExportRoutesPSDToRealPSDWriter() throws {
        var value = project()
        value.layers = [try imageLayer()]

        let data =
            try CoverArtwork.export(
                value,
                format: "psd"
            )

        XCTAssertEqual(
            String(
                data: data.prefix(4),
                encoding: .ascii
            ),
            "8BPS"
        )
    }

    func testExportedPSDCanBeDecodedByCurrentMacOSPSDImportPath() throws {
        var value = project()
        value.layers = [try imageLayer(name: "Reopen")]

        let data = try PSDExporter.export(value)
        let decoded = try CoverArtwork.decodedRaster(data)

        XCTAssertEqual(decoded.width, 4)
        XCTAssertEqual(decoded.height, 4)
        XCTAssertFalse(decoded.data.isEmpty)
    }

    func testLayerBoundsCanBeSmallerThanCanvasForTransparentArtwork() throws {
        guard let bitmap =
                NSBitmapImageRep(
                    bitmapDataPlanes: nil,
                    pixelsWide: 4,
                    pixelsHigh: 4,
                    bitsPerSample: 8,
                    samplesPerPixel: 4,
                    hasAlpha: true,
                    isPlanar: false,
                    colorSpaceName: .deviceRGB,
                    bytesPerRow: 16,
                    bitsPerPixel: 32
                ),
              let bytes = bitmap.bitmapData else {
            throw XCTSkip("Unable to create sparse PNG.")
        }

        for index in 0..<64 {
            bytes[index] = 0
        }

        let pixel = (1 * 4 + 2) * 4
        bytes[pixel] = 255
        bytes[pixel + 3] = 255

        let data =
            try XCTUnwrap(
                bitmap.representation(
                    using: .png,
                    properties: [:]
                )
            )

        var layer =
            CoverLayer(
                kind: .image,
                name: "Sparse",
                frame: CoverRect()
            )

        layer.imageData = data

        var value = project()
        value.layers = [layer]

        let parsed = try parse(PSDExporter.export(value))

        XCTAssertLessThanOrEqual(
            parsed.layers[0].right
            - parsed.layers[0].left,
            4
        )

        XCTAssertLessThanOrEqual(
            parsed.layers[0].bottom
            - parsed.layers[0].top,
            4
        )

        XCTAssertGreaterThan(
            parsed.layers[0].right
            - parsed.layers[0].left,
            0
        )
    }
}
