import AppKit
import CoreGraphics
import Foundation

enum PSDExporter {
    enum ExportError:
        LocalizedError
    {
        case invalidCanvas
        case tooManyLayers
        case generatedDataTooLarge
        case invalidRaster
        case integerOverflow

        var errorDescription:
            String?
        {
            switch self {
            case .invalidCanvas:
                return "The cover dimensions cannot be represented by PSD version 1."

            case .tooManyLayers:
                return "The cover contains too many layers for the PSD exporter."

            case .generatedDataTooLarge:
                return "The layered PSD would exceed BOLD Writer's safe generated-data limit."

            case .invalidRaster:
                return "A cover layer could not be rasterized for PSD export."

            case .integerOverflow:
                return "The PSD export exceeded a supported binary section size."
            }
        }
    }

    struct Channel:
        Equatable
    {
        var id:
            Int16

        var data:
            Data
    }

    struct TextTool:
        Equatable
    {
        var text:String
        var fontPostScriptName:String
        var fontFamilyName:String
        var fontSize:Double
        var red:Double
        var green:Double
        var blue:Double
        var alignment:Int
        var tracking:Double
        var leading:Double
        var underline:Bool
        var strikethrough:Bool
        var horizontalScale:Double
        var verticalScale:Double
        var baselineShift:Double
        var paragraphIndent:Double
        var paragraphSpacing:Double

        var xx:Double
        var xy:Double
        var yx:Double
        var yy:Double
        var tx:Double
        var ty:Double

        var left:Double
        var top:Double
        var right:Double
        var bottom:Double
    }

    struct SmartObjectTool:
        Equatable
    {
        var identifier:String
        var filename:String
        var sourceKind:CoverSmartObjectSourceKind
        var sourceData:Data
        var intrinsicWidth:Int
        var intrinsicHeight:Int
        var storageMode:CoverSmartObjectStorageMode
        var placedType:Int32
        var transform:[Double]
    }

    struct Layer:
        Equatable
    {
        var id:
            UUID

        var name:
            String

        var top:
            Int

        var left:
            Int

        var bottom:
            Int

        var right:
            Int

        var opacity:
            UInt8

        var visible:
            Bool

        var blendKey:
            String

        var clipping:
            UInt8

        var transparencyLocked:
            Bool

        var channels:
            [Channel]
    

        var protectionFlags: UInt32 = 0

        var sectionDividerType:
            UInt32? = nil


        var textTool:
            TextTool? = nil


        var smartObjectTool:
            SmartObjectTool? = nil
}

    struct Raster {
        var width:
            Int

        var height:
            Int

        var rgba:
            [UInt8]
    }

    static let maxDimension =
        30_000

    static let maxLayerCount =
        4_096

    static let maxCanvasPixels =
        50_000_000

    static let maxGeneratedChannelBytes =
        750_000_000

    static func export(
        _ project: CoverProject
    ) throws -> Data {
        try CoverProject.validate(
            [
                project
            ]
        )

        let width = Int(project.rasterPixelSize.width)
        let height = Int(project.rasterPixelSize.height)

        guard width > 0,
              height > 0,
              width <= maxDimension,
              height <= maxDimension
        else {
            throw ExportError.invalidCanvas
        }

        let pixelCount =
            try safeProduct(
                width,
                height
            )

        guard pixelCount <= maxCanvasPixels
        else {
            throw ExportError.generatedDataTooLarge
        }

        let hiddenGroups =
            Set(
                project.layers
                    .filter {
                        $0.kind == .group
                        && !$0.visible
                    }
                    .map(
                        \.id
                    )
            )

        let candidates =
            project.layers
                .filter {
                    $0.kind != .group
                    && $0.kind != .adjustment
                    && !$0.isReferenceLayer
                }

        guard candidates.count <= maxLayerCount,
              candidates.count <= Int(Int16.max)
        else {
            throw ExportError.tooManyLayers
        }

        var estimatedChannelBytes =
            try safeProduct(
                pixelCount,
                3
            )

        var layers:
            [Layer] = []

        layers.reserveCapacity(
            candidates.count
        )

        for (
            index,
            source
        ) in candidates.enumerated() {
            let cropped: (top:Int,left:Int,bottom:Int,right:Int,channels:[Channel])
            if let exact = importedRasterChannels(source,width:width,height:height) {
                cropped = exact
            } else {
                let image = try CoverArtwork.psdLayerImage(source,project:project)
                cropped = crop(try rgbaRaster(image:image,width:width,height:height))
            }

            estimatedChannelBytes =
                try safeSum(
                    estimatedChannelBytes,
                    try safeProduct(
                        cropped.channels
                            .first?
                            .data
                            .count
                        ?? 0,
                        cropped.channels.count
                    )
                )

            guard estimatedChannelBytes
                    <= maxGeneratedChannelBytes
            else {
                throw ExportError.generatedDataTooLarge
            }

            let parentVisible =
                source.groupID.map {
                    !hiddenGroups.contains(
                        $0
                    )
                }
                ?? true

            let effectiveVisible =
                source.visible
                && parentVisible

            let validClipping:
                Bool

            if let targetID =
                    source.clippedToLayerID,
               index > 0
            {
                let previous =
                    candidates[
                        index - 1
                    ]

                validClipping =
                    previous.id
                    == targetID
                    && previous.groupID
                    == source.groupID
            } else {
                validClipping =
                    false
            }

            layers.append(
                Layer(
                    id:
                        source.id,
                    name:
                        source.name,
                    top:
                        cropped.top,
                    left:
                        cropped.left,
                    bottom:
                        cropped.bottom,
                    right:
                        cropped.right,
                    opacity:
                        UInt8(
                            max(
                                0,
                                min(
                                    255,
                                    Int(
                                        (
                                            source.opacity
                                            * 255
                                        )
                                        .rounded()
                                    )
                                )
                            )
                        ),
                    visible:
                        effectiveVisible,
                    blendKey:
                        blendKey(
                            source.blendMode
                        ),
                    clipping:
                        validClipping
                        ? 1
                        : 0,
                    transparencyLocked:
                        source
                            .transparencyLocked
                        == true,
                    channels:
                        cropped.channels
                )
            )
        }

        for index in layers.indices {
            let source = candidates[index]
            layers[index].protectionFlags = (source.locked ? 0x80000000 : 0)
                | (source.transparencyLocked == true ? 1 : 0)
                | (source.pixelsLocked == true ? 2 : 0)
                | (source.positionLocked == true ? 4 : 0)
            layers[index].textTool =
                nativeTextTool(
                    for:
                        candidates[index],
                    canvasWidth:
                        width,
                    canvasHeight:
                        height
                )
        }

        for index
            in layers.indices
        {
            guard index
                < candidates.count
            else {
                break
            }

            layers[index].smartObjectTool =
                nativeSmartObjectTool(
                    for:
                        candidates[index],
                    canvasWidth:
                        width,
                    canvasHeight:
                        height
                )
        }

        layers =

            nativeGroupFolderLayers(

                projectLayers:

                    project.layers,

                candidates:

                    candidates,

                artworkLayers:

                    layers

            )


        guard layers.count

                <= maxLayerCount,

              layers.count

                <= Int(

                    Int16.max

                )

        else {

            throw ExportError.tooManyLayers

        }


        let compositeImage =
            try CoverArtwork
                .render(
                    project,
                    includeGuides:
                        false,
                    includeTemplate:
                        false,
                    scale:
                        project.dpi
                )

        let composite =
            try rgbaRaster(
                image:
                    compositeImage,
                width:
                    width,
                height:
                    height
            )

        return try encode(
            width:
                width,
            height:
                height,
            dpi: project.dpi,
            layers:
                layers,
            composite:
                composite
        )
    }

    static func nativeTextTool(
        for source:CoverLayer,
        canvasWidth:Int,
        canvasHeight:Int
    )->TextTool? {
        var layer = source
        if let reference = layer.referencePageWidth, reference > 0 {
            let factor = Double(canvasWidth) / reference
            layer.fontSize *= factor
            if layer.psdTextPixelBasis == true {
                layer.lineSpacing *= factor; layer.letterSpacing *= factor
                layer.leading = layer.leading.map { $0 * factor }
                layer.baselineShift = layer.baselineShift.map { $0 * factor }
                layer.paragraphIndent = layer.paragraphIndent.map { $0 * factor }
                layer.paragraphSpacing = layer.paragraphSpacing.map { $0 * factor }
            }
        }
        guard layer.kind == .text,
              canvasWidth > 0,
              canvasHeight > 0,
              !layer.flipHorizontal,
              !layer.flipVertical,
              abs(
                layer.skewX
                ?? 0
              ) <= 0.000_001,
              abs(
                layer.skewY
                ?? 0
              ) <= 0.000_001,
              abs(
                layer.warpAmount
                ?? 0
              ) <= 0.000_001,
              layer.maskData == nil,
              layer.dropShadow == nil,
              layer.innerShadow == nil,
              layer.strokeEffect == nil,
              layer.colorOverlay == nil,
              layer.gradientOverlay == nil,
              layer.outerGlow == nil,
              abs(
                (
                    layer.fillOpacity
                    ?? 1
                )
                - 1
              ) <= 0.000_001
        else {
            return nil
        }

        let font =
            CoverTypography
                .font(
                    for:
                        layer
                )

        let color =
            NSColor(
                hex:
                    layer.colorHex
            )
            .usingColorSpace(
                .sRGB
            )
            ?? NSColor(
                hex:
                    layer.colorHex
            )

        var red:
            CGFloat = 0

        var green:
            CGFloat = 0

        var blue:
            CGFloat = 0

        var alpha:
            CGFloat = 0

        color.getRed(
            &red,
            green:
                &green,
            blue:
                &blue,
            alpha:
                &alpha
        )

        let frameLeft =
            layer.frame.x
            * Double(
                canvasWidth
            )

        let frameTop =
            layer.frame.y
            * Double(
                canvasHeight
            )

        let frameWidth =
            layer.frame.width
            * Double(
                canvasWidth
            )

        let frameHeight =
            layer.frame.height
            * Double(
                canvasHeight
            )

        guard frameLeft.isFinite,
              frameTop.isFinite,
              frameWidth.isFinite,
              frameHeight.isFinite,
              frameWidth >= 0,
              frameHeight >= 0
        else {
            return nil
        }

        let radians =
            layer.rotation
            * .pi
            / 180

        let xx =
            cos(
                radians
            )

        let xy =
            sin(
                radians
            )

        let yx =
            -sin(
                radians
            )

        let yy =
            cos(
                radians
            )

        let centerX =
            frameWidth
            / 2

        let centerY =
            frameHeight
            / 2

        let tx =
            frameLeft
            + centerX
            - xx * centerX
            - yx * centerY

        let ty =
            frameTop
            + centerY
            - xy * centerX
            - yy * centerY

        let alignment:Int

        switch layer.alignment {
        case "right":
            alignment =
                1

        case "center":
            alignment =
                2

        case "justified":
            alignment =
                3

        default:
            alignment =
                0
        }

        let horizontalScale =
            layer.horizontalScale
            ?? 1

        let verticalScale =
            layer.verticalScale
            ?? 1

        let baselineShift =
            layer.baselineShift
            ?? 0

        let paragraphIndent =
            layer.paragraphIndent
            ?? 0

        let paragraphSpacing =
            layer.paragraphSpacing
            ?? 0

        let leading =
            (
                layer.leading
                ?? 0
            ) > 0
            ? (
                layer.leading
                ?? layer.fontSize
            )
            : Double(NSLayoutManager().defaultLineHeight(for:font))

        return TextTool(
            text:
                layer.text,
            fontPostScriptName:
                font.fontName,
            fontFamilyName:
                font.familyName
                ?? font.fontName,
            fontSize:
                layer.fontSize,
            red:
                Double(
                    red
                ),
            green:
                Double(
                    green
                ),
            blue:
                Double(
                    blue
                ),
            alignment:
                alignment,
            tracking:
                layer.letterSpacing,
            leading:
                leading,
            underline:
                layer.underline
                == true,
            strikethrough:
                layer.strikethrough
                == true,
            horizontalScale:
                horizontalScale,
            verticalScale:
                verticalScale,
            baselineShift:
                baselineShift,
            paragraphIndent:
                paragraphIndent,
            paragraphSpacing:
                paragraphSpacing,
            xx:
                xx,
            xy:
                xy,
            yx:
                yx,
            yy:
                yy,
            tx:
                tx,
            ty:
                ty,
            left:
                0,
            top:
                0,
            right:
                frameWidth,
            bottom:
                frameHeight
        )
    }

    static func typeToolData(
        _ tool:TextTool
    )->Data {
        var writer =
            PSDDescriptorWriter()

        writer.uint16(
            1
        )

        writer.double(
            tool.xx
        )

        writer.double(
            tool.xy
        )

        writer.double(
            tool.yx
        )

        writer.double(
            tool.yy
        )

        writer.double(
            tool.tx
        )

        writer.double(
            tool.ty
        )

        writer.uint16(
            50
        )

        writer.uint32(
            16
        )

        let engineData =
            textEngineData(
                tool
            )

        writer.descriptor(
            name:
                "",
            classID:
                "TxLr",
            itemCount:
                8
        ) {
            descriptor in

            descriptor.textItem(
                key:
                    "Txt ",
                value:
                    tool.text
            )

            descriptor.enumItem(
                key:
                    "textGridding",
                type:
                    "textGridding",
                value:
                    "None"
            )

            descriptor.enumItem(
                key:
                    "Ornt",
                type:
                    "Ornt",
                value:
                    "Hrzn"
            )

            descriptor.enumItem(
                key:
                    "AntA",
                type:
                    "Annt",
                value:
                    "AnCr"
            )

            descriptor.objectItem(
                key:
                    "bounds",
                classID:
                    "bounds",
                itemCount:
                    4
            ) {
                bounds in

                bounds.unitFloatItem(
                    key:
                        "Left",
                    unit:
                        "#Pxl",
                    value:
                        tool.left
                )

                bounds.unitFloatItem(
                    key:
                        "Top ",
                    unit:
                        "#Pxl",
                    value:
                        tool.top
                )

                bounds.unitFloatItem(
                    key:
                        "Rght",
                    unit:
                        "#Pxl",
                    value:
                        tool.right
                )

                bounds.unitFloatItem(
                    key:
                        "Btom",
                    unit:
                        "#Pxl",
                    value:
                        tool.bottom
                )
            }

            descriptor.objectItem(
                key:
                    "boundingBox",
                classID:
                    "boundingBox",
                itemCount:
                    4
            ) {
                bounds in

                bounds.unitFloatItem(
                    key:
                        "Left",
                    unit:
                        "#Pxl",
                    value:
                        tool.left
                )

                bounds.unitFloatItem(
                    key:
                        "Top ",
                    unit:
                        "#Pxl",
                    value:
                        tool.top
                )

                bounds.unitFloatItem(
                    key:
                        "Rght",
                    unit:
                        "#Pxl",
                    value:
                        tool.right
                )

                bounds.unitFloatItem(
                    key:
                        "Btom",
                    unit:
                        "#Pxl",
                    value:
                        tool.bottom
                )
            }

            descriptor.int32Item(
                key:
                    "TextIndex",
                value:
                    0
            )

            descriptor.dataItem(
                key:
                    "EngineData",
                value:
                    engineData
            )
        }

        writer.uint16(
            1
        )

        writer.uint32(
            16
        )

        writer.descriptor(
            name:
                "",
            classID:
                "warp",
            itemCount:
                5
        ) {
            descriptor in

            descriptor.enumItem(
                key:
                    "warpStyle",
                type:
                    "warpStyle",
                value:
                    "warpNone"
            )

            descriptor.doubleItem(
                key:
                    "warpValue",
                value:
                    0
            )

            descriptor.doubleItem(
                key:
                    "warpPerspective",
                value:
                    0
            )

            descriptor.doubleItem(
                key:
                    "warpPerspectiveOther",
                value:
                    0
            )

            descriptor.enumItem(
                key:
                    "warpRotate",
                type:
                    "Ornt",
                value:
                    "Hrzn"
            )
        }

        writer.double(
            tool.left
        )

        writer.double(
            tool.top
        )

        writer.double(
            tool.right
        )

        writer.double(
            tool.bottom
        )

        return writer.data
    }

    static func textEngineData(
        _ tool:TextTool
    )->Data {
        var data =
            Data()

        func appendASCII(
            _ string:String
        ) {
            data.append(
                contentsOf:
                    string.utf8
            )
        }

        func number(
            _ value:Double
        )->String {
            var result =
                String(
                    format:
                        "%.8f",
                    locale:
                        Locale(
                            identifier:
                                "en_US_POSIX"
                        ),
                    arguments:
                        [
                            value
                        ]
                )

            while result.contains("."),
                  result.last
                    == "0"
            {
                result.removeLast()
            }

            if result.last
                == "."
            {
                result.removeLast()
            }

            return result.isEmpty
                ? "0"
                : result
        }

        func appendEngineString(
            _ string:String
        ) {
            data.append(
                0xfe
            )

            data.append(
                0xff
            )

            for unit
                in string.utf16
            {
                let high =
                    UInt8(
                        (
                            unit
                            >> 8
                        )
                        & 0xff
                    )

                let low =
                    UInt8(
                        unit
                        & 0xff
                    )

                data.append(
                    high
                )

                if low == 0x5c
                    || low == 0x28
                    || low == 0x29
                {
                    data.append(
                        0x5c
                    )
                }

                data.append(
                    low
                )
            }
        }

        let engineText =
            tool.text
                .replacingOccurrences(
                    of:
                        "\r\n",
                    with:
                        "\r"
                )
                .replacingOccurrences(
                    of:
                        "\n",
                    with:
                        "\r"
                )

        let runLength =
            max(
                1,
                engineText
                    .utf16
                    .count
            )

        appendASCII(
            "<<\n"
        )

        appendASCII(
            "/EngineDict <<\n"
        )

        appendASCII(
            "/Editor <<\n/Text ("
        )

        appendEngineString(
            engineText
        )

        appendASCII(
            ")\n>>\n"
        )

        appendASCII(
            "/ParagraphRun <<\n"
        )

        appendASCII(
            "/RunArray [ << /ParagraphSheet << /Properties << "
        )

        appendASCII(
            "/Justification \(tool.alignment) "
        )

        appendASCII(
            "/FirstLineIndent \(number(tool.paragraphIndent)) "
        )

        appendASCII(
            "/StartIndent 0 "
        )

        appendASCII(
            "/EndIndent 0 "
        )

        appendASCII(
            "/SpaceBefore 0 "
        )

        appendASCII(
            "/SpaceAfter \(number(tool.paragraphSpacing)) "
        )

        appendASCII(
            ">> >> >> ]\n"
        )

        appendASCII(
            "/RunLengthArray [ \(runLength) ]\n"
        )

        appendASCII(
            ">>\n"
        )

        appendASCII(
            "/StyleRun <<\n"
        )

        appendASCII(
            "/RunArray [ << /StyleSheet << /StyleSheetData << "
        )

        appendASCII(
            "/Font 0 "
        )

        appendASCII(
            "/FontSize \(number(tool.fontSize)) "
        )

        appendASCII(
            "/FauxBold false "
        )

        appendASCII(
            "/FauxItalic false "
        )

        appendASCII(
            "/AutoLeading false "
        )

        appendASCII(
            "/Leading \(number(tool.leading)) "
        )

        appendASCII(
            "/HorizontalScale \(number(tool.horizontalScale)) "
        )

        appendASCII(
            "/VerticalScale \(number(tool.verticalScale)) "
        )

        appendASCII(
            "/Tracking \(number(tool.tracking)) "
        )

        appendASCII(
            "/BaselineShift \(number(tool.baselineShift)) "
        )

        appendASCII(
            "/Underline \(tool.underline ? "true" : "false") "
        )

        appendASCII(
            "/Strikethrough \(tool.strikethrough ? "true" : "false") "
        )

        appendASCII(
            "/FillColor << /Type 1 /Values [ 1 "
        )

        appendASCII(
            "\(number(tool.red)) "
        )

        appendASCII(
            "\(number(tool.green)) "
        )

        appendASCII(
            "\(number(tool.blue)) ] >> "
        )

        appendASCII(
            ">> >> >> ]\n"
        )

        appendASCII(
            "/RunLengthArray [ \(runLength) ]\n"
        )

        appendASCII(
            ">>\n"
        )

        appendASCII(
            ">>\n"
        )

        appendASCII(
            "/ResourceDict <<\n"
        )

        appendASCII(
            "/FontSet [ << "
        )

        appendASCII("/Name (")
        appendEngineString(tool.fontPostScriptName)
        appendASCII(") /FamilyName (")
        appendEngineString(tool.fontFamilyName)
        appendASCII(") ")

        appendASCII(
            "/Script 0 "
        )

        appendASCII(
            "/FontType 0 "
        )

        appendASCII(
            "/Synthetic 0 "
        )

        appendASCII(
            ">> ]\n"
        )

        appendASCII(
            ">>\n"
        )

        appendASCII(
            ">>\n"
        )

        return data
    }

    static func nativeSmartObjectTool(
        for layer:CoverLayer,
        canvasWidth:Int,
        canvasHeight:Int
    )->SmartObjectTool? {
        guard layer.kind == .smartObject,
              let object =
                layer.smartObject,
              !object.sourceData.isEmpty,
              object.sourceData.count
                <= CoverSmartObjectValidation
                    .maxSourceBytes,
              object.intrinsicWidth > 0,
              object.intrinsicHeight > 0,
              object.intrinsicWidth
                <= CoverSmartObjectValidation
                    .maxDimension,
              object.intrinsicHeight
                <= CoverSmartObjectValidation
                    .maxDimension,
              canvasWidth > 0,
              canvasHeight > 0
        else {
            return nil
        }

        let transform =
            nativeSmartObjectTransform(
                layer:
                    layer,
                canvasWidth:
                    canvasWidth,
                canvasHeight:
                    canvasHeight
            )

        guard transform.count == 8,
              transform.allSatisfy({
                  $0.isFinite
              })
        else {
            return nil
        }

        let placedType:Int32

        switch object.sourceKind {
        case .pdf,
             .svg:
            placedType =
                1

        case .rasterImage,
             .psd:
            placedType =
                2
        }

        return SmartObjectTool(
            identifier:
                layer.id
                    .uuidString
                    .lowercased(),
            filename:
                nativeSmartObjectFilename(
                    object
                ),
            sourceKind:
                object.sourceKind,
            sourceData:
                object.sourceData,
            intrinsicWidth:
                object.intrinsicWidth,
            intrinsicHeight:
                object.intrinsicHeight,
            storageMode:
                object.storageMode,
            placedType:
                placedType,
            transform:
                transform
        )
    }

    static func nativeSmartObjectFilename(
        _ object:CoverSmartObject
    )->String {
        if let sourceFilename =
                object.sourceFilename?
                    .trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    ),
           !sourceFilename.isEmpty
        {
            return (
                sourceFilename
                    as NSString
            )
            .lastPathComponent
        }

        switch object.sourceKind {
        case .rasterImage:
            return "SmartObject.png"

        case .pdf:
            return "SmartObject.pdf"

        case .svg:
            return "SmartObject.svg"

        case .psd:
            return "SmartObject.psd"
        }
    }

    static func nativeSmartObjectFileType(
        _ tool:SmartObjectTool
    )->String {
        let fileExtension =
            (
                tool.filename
                    as NSString
            )
            .pathExtension
            .lowercased()

        switch fileExtension {
        case "psd",
             "psb":
            return "8BPS"

        case "pdf":
            return "PDF "

        case "jpg",
             "jpeg":
            return "JPEG"

        case "tif",
             "tiff":
            return "TIFF"

        case "png":
            return "PNGf"

        case "svg":
            return "SVG "

        default:
            switch tool.sourceKind {
            case .psd:
                return "8BPS"

            case .pdf:
                return "PDF "

            case .svg:
                return "SVG "

            case .rasterImage:
                return "    "
            }
        }
    }

    static func nativeSmartObjectTransform(
        layer:CoverLayer,
        canvasWidth:Int,
        canvasHeight:Int
    )->[Double] {
        let left =
            layer.frame.x
            * Double(
                canvasWidth
            )

        let top =
            layer.frame.y
            * Double(
                canvasHeight
            )

        let width =
            layer.frame.width
            * Double(
                canvasWidth
            )

        let height =
            layer.frame.height
            * Double(
                canvasHeight
            )

        let centerX =
            left
            + width / 2

        let centerY =
            top
            + height / 2

        let radians =
            layer.rotation
            * .pi
            / 180

        let cosine =
            cos(
                radians
            )

        let sine =
            sin(
                radians
            )

        let flipX =
            layer.flipHorizontal
            ? -1.0
            : 1.0

        let flipY =
            layer.flipVertical
            ? -1.0
            : 1.0

        let skewX =
            layer.skewX
            ?? 0

        let skewY =
            layer.skewY
            ?? 0

        func placedPoint(
            _ x:Double,
            _ y:Double
        )->(
            Double,
            Double
        ) {
            var dx =
                (
                    x
                    - 0.5
                )
                * width

            var dy =
                (
                    y
                    - 0.5
                )
                * height

            dx *=
                flipX

            dy *=
                flipY

            let skewedX =
                dx
                + skewX
                * dy

            let skewedY =
                skewY
                * dx
                + dy

            let rotatedX =
                cosine
                * skewedX
                - sine
                * skewedY

            let rotatedY =
                sine
                * skewedX
                + cosine
                * skewedY

            return (
                centerX
                + rotatedX,
                centerY
                + rotatedY
            )
        }

        let topLeft =
            placedPoint(
                0,
                0
            )

        let topRight =
            placedPoint(
                1,
                0
            )

        let bottomRight =
            placedPoint(
                1,
                1
            )

        let bottomLeft =
            placedPoint(
                0,
                1
            )

        return [
            topLeft.0,
            topLeft.1,
            topRight.0,
            topRight.1,
            bottomRight.0,
            bottomRight.1,
            bottomLeft.0,
            bottomLeft.1,
        ]
    }

    static func placedLayerData(
        _ tool:SmartObjectTool
    )->Data {
        var writer =
            PSDSmartObjectBinaryWriter()

        writer.signature(
            "plcL"
        )

        writer.int32(
            3
        )

        writer.pascalString(
            tool.identifier
        )

        writer.int32(
            1
        )

        writer.int32(
            1
        )

        writer.int32(
            16
        )

        writer.int32(
            tool.placedType
        )

        for value
            in tool.transform
        {
            writer.double(
                value
            )
        }

        writer.int32(
            0
        )

        writer.int32(
            16
        )

        writer.descriptorUnicodeString(
            ""
        )

        writer.classID(
            "warp"
        )

        writer.uint32(
            0
        )

        return writer.data
    }

    static func linkedSmartObjectEntry(
        _ tool:SmartObjectTool
    )->Data {
        var writer =
            PSDSmartObjectBinaryWriter()

        writer.signature(
            "liFD"
        )

        writer.int32(
            2
        )

        writer.pascalString(
            tool.identifier
        )

        writer.unicodeStringWithNull(
            tool.filename
        )

        writer.signature(
            nativeSmartObjectFileType(
                tool
            )
        )

        writer.signature(
            "    "
        )

        writer.uint64(
            UInt64(
                tool.sourceData.count
            )
        )

        writer.uint8(
            0
        )

        writer.raw(
            tool.sourceData
        )

        return writer.data
    }

    static func linkedSmartObjectData(
        _ tools:[SmartObjectTool]
    )->Data {
        var writer =
            PSDSmartObjectBinaryWriter()

        var seen =
            Set<String>()

        for tool
            in tools
        {
            guard seen.insert(
                tool.identifier
            )
            .inserted
            else {
                continue
            }

            let entry =
                linkedSmartObjectEntry(
                    tool
                )

            writer.uint64(
                UInt64(
                    entry.count
                )
            )

            writer.raw(
                entry
            )

            while writer.data.count
                % 4
                != 0
            {
                writer.uint8(
                    0
                )
            }
        }

        return writer.data
    }

    static func smartObjectAdditionalLayerInfoBlock(
        key:String,
        payload:Data
    )->Data {
        var writer =
            PSDSmartObjectBinaryWriter()

        writer.signature(
            "8BIM"
        )

        writer.signature(
            key
        )

        writer.uint32(
            UInt32(
                payload.count
            )
        )

        writer.raw(
            payload
        )

        if payload.count
            % 2
            != 0
        {
            writer.uint8(
                0
            )
        }

        return writer.data
    }

    static func nativeGroupFolderLayers(
        projectLayers:[CoverLayer],
        candidates:[CoverLayer],
        artworkLayers:[Layer]
    )->[Layer] {
        guard candidates.count
                == artworkLayers.count,
              !artworkLayers.isEmpty
        else {
            return artworkLayers
        }

        let groups =
            Dictionary(
                projectLayers
                    .filter {
                        $0.kind == .group
                    }
                    .map {
                        (
                            $0.id,
                            $0
                        )
                    },
                uniquingKeysWith: {
                    first,
                    _ in

                    first
                }
            )

        guard !groups.isEmpty
        else {
            return artworkLayers
        }

        struct GroupRange {
            var first:Int
            var last:Int
            var group:CoverLayer
        }

        var ranges:
            [UUID:GroupRange] = [:]

        for (
            groupID,
            group
        ) in groups {
            let indexes =
                candidates
                    .indices
                    .filter {
                        candidates[
                            $0
                        ]
                        .groupID
                        == groupID
                    }

            guard let first =
                    indexes.first,
                  let last =
                    indexes.last,
                  last - first + 1
                    == indexes.count
            else {
                continue
            }

            ranges[
                groupID
            ] =
                GroupRange(
                    first:
                        first,
                    last:
                        last,
                    group:
                        group
                )
        }

        guard !ranges.isEmpty
        else {
            return artworkLayers
        }

        var output:
            [Layer] = []

        output.reserveCapacity(
            artworkLayers.count
            + ranges.count * 2
        )

        var index =
            0

        while index
                < artworkLayers.count
        {
            if let groupID =
                    candidates[
                        index
                    ]
                    .groupID,
               let range =
                    ranges[
                        groupID
                    ],
               range.first
                    == index
            {
                output.append(
                    nativeGroupEndLayer(
                        range.group
                    )
                )

                for memberIndex
                    in range.first...range.last
                {
                    output.append(
                        artworkLayers[
                            memberIndex
                        ]
                    )
                }

                output.append(
                    nativeGroupStartLayer(
                        range.group
                    )
                )

                index =
                    range.last + 1

                continue
            }

            output.append(
                artworkLayers[
                    index
                ]
            )

            index +=
                1
        }

        return output
    }

    static func nativeGroupStartLayer(
        _ group:CoverLayer
    )->Layer {
        Layer(
            id:
                group.id,
            name:
                group.name,
            top:
                0,
            left:
                0,
            bottom:
                0,
            right:
                0,
            opacity:
                255,
            visible:
                group.visible,
            blendKey:
                "norm",
            clipping:
                0,
            transparencyLocked:
                false,
            channels:
                [],
            sectionDividerType:
                1
        )
    }

    static func nativeGroupEndLayer(
        _ group:CoverLayer
    )->Layer {
        Layer(
            id:
                group.id,
            name:
                "</Layer group>",
            top:
                0,
            left:
                0,
            bottom:
                0,
            right:
                0,
            opacity:
                255,
            visible:
                group.visible,
            blendKey:
                "norm",
            clipping:
                0,
            transparencyLocked:
                false,
            channels:
                [],
            sectionDividerType:
                3
        )
    }

    static func blendKey(
        _ mode: CoverBlendMode?
    ) -> String {
        switch mode ?? .normal {
        case .normal:
            return "norm"
        case .multiply:
            return "mul "
        case .screen:
            return "scrn"
        case .overlay:
            return "over"
        case .darken:
            return "dark"
        case .lighten:
            return "lite"
        case .colorBurn:
            return "idiv"
        case .colorDodge:
            return "div "
        case .softLight:
            return "sLit"
        case .hardLight:
            return "hLit"
        case .difference:
            return "diff"
        case .exclusion:
            return "smud"
        case .hue:
            return "hue "
        case .saturation:
            return "sat "
        case .color:
            return "colr"
        case .luminosity:
            return "lum "
        case .plusDarker:
            return "lbrn"
        case .plusLighter:
            return "lddg"
        }
    }

    private static func safeProduct(
        _ lhs: Int,
        _ rhs: Int
    ) throws -> Int {
        guard lhs >= 0,
              rhs >= 0
        else {
            throw ExportError.integerOverflow
        }

        if lhs == 0 || rhs == 0 {
            return 0
        }

        guard lhs <= Int.max / rhs
        else {
            throw ExportError.integerOverflow
        }

        return lhs * rhs
    }

    private static func safeSum(
        _ lhs: Int,
        _ rhs: Int
    ) throws -> Int {
        guard lhs >= 0,
              rhs >= 0,
              lhs <= Int.max - rhs
        else {
            throw ExportError.integerOverflow
        }

        return lhs + rhs
    }

    private static func rgbaRaster(
        image: NSImage,
        width: Int,
        height: Int
    ) throws -> Raster {
        guard width > 0,
              height > 0
        else {
            throw ExportError.invalidRaster
        }

        var proposed =
            NSRect(
                origin:
                    .zero,
                size:
                    image.size
            )

        guard let cgImage =
                image.cgImage(
                    forProposedRect:
                        &proposed,
                    context:
                        nil,
                    hints:
                        nil
                )
        else {
            throw ExportError.invalidRaster
        }

        let byteCount =
            try safeProduct(
                try safeProduct(
                    width,
                    height
                ),
                4
            )

        var bytes =
            [UInt8](
                repeating:
                    0,
                count:
                    byteCount
            )

        let colorSpace =
            CGColorSpaceCreateDeviceRGB()

        let bitmapInfo =
            CGBitmapInfo.byteOrder32Big
                .union(
                    CGBitmapInfo(
                        rawValue:
                            CGImageAlphaInfo
                                .premultipliedLast
                                .rawValue
                    )
                )

        guard let context =
                CGContext(
                    data:
                        &bytes,
                    width:
                        width,
                    height:
                        height,
                    bitsPerComponent:
                        8,
                    bytesPerRow:
                        width * 4,
                    space:
                        colorSpace,
                    bitmapInfo:
                        bitmapInfo.rawValue
                )
        else {
            throw ExportError.invalidRaster
        }

        context.interpolationQuality =
            .high

        // CGImage scanlines already use top-to-bottom order. Flipping the drawing
        // context inverted PSD channel rows and disconnected raster bounds from TySh.
        context.draw(
            cgImage,
            in:
                CGRect(
                    x:
                        0,
                    y:
                        0,
                    width:
                        width,
                    height:
                        height
                )
        )

        var offset =
            0

        while offset + 3 < bytes.count {
            let alpha =
                Int(
                    bytes[
                        offset + 3
                    ]
                )

            if alpha == 0 {
                bytes[offset] = 0
                bytes[offset + 1] = 0
                bytes[offset + 2] = 0
            } else if alpha < 255 {
                for component in 0..<3 {
                    let premultiplied =
                        Int(
                            bytes[
                                offset
                                + component
                            ]
                        )

                    bytes[
                        offset
                        + component
                    ] =
                        UInt8(
                            min(
                                255,
                                (
                                    premultiplied
                                    * 255
                                    + alpha
                                    / 2
                                )
                                / alpha
                            )
                        )
                }
            }

            offset += 4
        }

        return Raster(
            width:
                width,
            height:
                height,
            rgba:
                bytes
        )
    }

    /// Preserve unmodified imported channel samples without color conversion, alpha
    /// premultiplication, cropping or resampling. Standard layer bounds remain editable.
    private static func importedRasterChannels(_ layer: CoverLayer, width:Int, height:Int)
        -> (top:Int,left:Int,bottom:Int,right:Int,channels:[Channel])? {
        guard layer.kind == .image, layer.psdRasterPixelBasis == true,
              layer.rotation == 0, !layer.flipHorizontal, !layer.flipVertical,
              (layer.skewX ?? 0) == 0, (layer.skewY ?? 0) == 0,
              layer.perspectiveCorners == nil, (layer.warpAmount ?? 0) == 0,
              layer.filters?.isEmpty != false, layer.maskData == nil,
              layer.sourceCrop == nil, layer.cropOffsetX == 0, layer.cropOffsetY == 0,
              layer.cropMode == .fill, (layer.fillOpacity ?? 1) == 1,
              layer.dropShadow == nil, layer.innerShadow == nil, layer.strokeEffect == nil,
              layer.colorOverlay == nil, layer.gradientOverlay == nil, layer.outerGlow == nil,
              let data = layer.imageData, let bitmap = NSBitmapImageRep(data:data),
              bitmap.bitsPerSample == 8, bitmap.samplesPerPixel == 4 else { return nil }
        let x = layer.frame.x * Double(width), y = layer.frame.y * Double(height)
        let w = layer.frame.width * Double(width), h = layer.frame.height * Double(height)
        guard abs(x-x.rounded()) < 0.000001, abs(y-y.rounded()) < 0.000001,
              abs(w-Double(bitmap.pixelsWide)) < 0.000001, abs(h-Double(bitmap.pixelsHigh)) < 0.000001,
              abs(x) < Double(Int32.max)/2, abs(y) < Double(Int32.max)/2 else { return nil }
        let count = bitmap.pixelsWide * bitmap.pixelsHigh
        var planes = (0..<4).map { _ in Data(capacity:count) }
        var samples = [Int](repeating:0,count:4)
        for row in 0..<bitmap.pixelsHigh { for column in 0..<bitmap.pixelsWide {
            bitmap.getPixel(&samples,atX:column,y:row)
            for c in 0..<4 { planes[c].append(UInt8(clamping:samples[c])) }
        } }
        return (Int(y.rounded()),Int(x.rounded()),Int(y.rounded())+bitmap.pixelsHigh,Int(x.rounded())+bitmap.pixelsWide,
                [Channel(id:0,data:planes[0]),Channel(id:1,data:planes[1]),Channel(id:2,data:planes[2]),Channel(id:-1,data:planes[3])])
    }

    private static func crop(
        _ raster: Raster
    ) -> (
        top: Int,
        left: Int,
        bottom: Int,
        right: Int,
        channels: [Channel]
    ) {
        var minX =
            raster.width

        var minY =
            raster.height

        var maxX =
            -1

        var maxY =
            -1

        for y in 0..<raster.height {
            for x in 0..<raster.width {
                let index =
                    (
                        y
                        * raster.width
                        + x
                    )
                    * 4

                if raster.rgba[
                    index + 3
                ] > 0 {
                    minX =
                        min(
                            minX,
                            x
                        )

                    minY =
                        min(
                            minY,
                            y
                        )

                    maxX =
                        max(
                            maxX,
                            x
                        )

                    maxY =
                        max(
                            maxY,
                            y
                        )
                }
            }
        }

        guard maxX >= minX,
              maxY >= minY
        else {
            return (
                0,
                0,
                0,
                0,
                [
                    Channel(
                        id:
                            -1,
                        data:
                            Data()
                    ),
                    Channel(
                        id:
                            0,
                        data:
                            Data()
                    ),
                    Channel(
                        id:
                            1,
                        data:
                            Data()
                    ),
                    Channel(
                        id:
                            2,
                        data:
                            Data()
                    ),
                ]
            )
        }

        let cropWidth =
            maxX - minX + 1

        let cropHeight =
            maxY - minY + 1

        let count =
            cropWidth * cropHeight

        var alpha =
            Data(
                capacity:
                    count
            )

        var red =
            Data(
                capacity:
                    count
            )

        var green =
            Data(
                capacity:
                    count
            )

        var blue =
            Data(
                capacity:
                    count
            )

        for y in minY...maxY {
            for x in minX...maxX {
                let index =
                    (
                        y
                        * raster.width
                        + x
                    )
                    * 4

                red.append(
                    raster.rgba[
                        index
                    ]
                )

                green.append(
                    raster.rgba[
                        index + 1
                    ]
                )

                blue.append(
                    raster.rgba[
                        index + 2
                    ]
                )

                alpha.append(
                    raster.rgba[
                        index + 3
                    ]
                )
            }
        }

        return (
            minY,
            minX,
            maxY + 1,
            maxX + 1,
            [
                Channel(
                    id:
                        -1,
                    data:
                        alpha
                ),
                Channel(
                    id:
                        0,
                    data:
                        red
                ),
                Channel(
                    id:
                        1,
                    data:
                        green
                ),
                Channel(
                    id:
                        2,
                    data:
                        blue
                ),
            ]
        )
    }

    private static func encode(
        width: Int,
        height: Int,
        dpi: Double,
        layers: [Layer],
        composite: Raster
    ) throws -> Data {
        var writer =
            PSDWriter()

        writer.signature(
            "8BPS"
        )

        writer.uint16(
            1
        )

        writer.zeroes(
            6
        )

        writer.uint16(
            3
        )

        writer.uint32(
            UInt32(
                height
            )
        )

        writer.uint32(
            UInt32(
                width
            )
        )

        writer.uint16(
            8
        )

        writer.uint16(
            3
        )

        writer.uint32(0) // Color mode data.
        guard dpi.isFinite, dpi > 0, dpi <= 65_535 else { throw ExportError.invalidCanvas }
        var resources = PSDWriter()
        resources.signature("8BIM")
        resources.uint16(1005) // Adobe ResolutionInfo, unsigned 16.16 pixels/inch.
        resources.uint16(0) // Empty Pascal resource name plus even-byte padding.
        resources.uint32(16)
        let resolution = UInt32((dpi * 65_536).rounded())
        for _ in 0..<2 {
            resources.uint32(resolution)
            resources.uint16(1) // Pixels per inch.
            resources.uint16(1) // Physical width/height unit: inches.
        }
        try writer.length32(resources.data)

        let layerAndMask =
            try layerAndMaskData(
                layers:
                    layers
            )

        try writer.length32(
            layerAndMask
        )

        writer.uint16(
            0
        )

        let compositePlanes =
            planarRGB(
                composite
            )

        writer.data.append(
            compositePlanes.red
        )

        writer.data.append(
            compositePlanes.green
        )

        writer.data.append(
            compositePlanes.blue
        )

        return writer.data
    }

    static func layerAndMaskData(
        layers: [Layer]
    ) throws -> Data {
        var layerInfo =
            PSDWriter()

        layerInfo.int16(
            Int16(
                layers.count
            )
        )

        for layer in layers {
            try writeLayerRecord(
                layer,
                to:
                    &layerInfo
            )
        }

        for layer in layers {
            for channel in layer.channels {
                layerInfo.uint16(
                    0
                )

                layerInfo.data.append(
                    channel.data
                )
            }
        }

        if layerInfo.data.count % 2 != 0 {
            layerInfo.uint8(
                0
            )
        }

        var output =
            PSDWriter()

        try output.length32(
            layerInfo.data
        )

        output.uint32(
            0
        )

        var smartObjectLayerAndMaskData =
            output.data

        let nativeSmartObjects =
            layers.compactMap {
                $0.smartObjectTool
            }

        if !nativeSmartObjects.isEmpty {
            smartObjectLayerAndMaskData.append(
                smartObjectAdditionalLayerInfoBlock(
                    key:
                        "lnk2",
                    payload:
                        linkedSmartObjectData(
                            nativeSmartObjects
                        )
                )
            )
        }

        return smartObjectLayerAndMaskData
    }

    private static func writeLayerRecord(
        _ layer: Layer,
        to writer: inout PSDWriter
    ) throws {
        writer.int32(
            Int32(
                layer.top
            )
        )

        writer.int32(
            Int32(
                layer.left
            )
        )

        writer.int32(
            Int32(
                layer.bottom
            )
        )

        writer.int32(
            Int32(
                layer.right
            )
        )

        writer.uint16(
            UInt16(
                layer.channels.count
            )
        )

        for channel in layer.channels {
            writer.int16(
                channel.id
            )

            let length =
                try uint32Length(
                    channel.data.count
                    + 2
                )

            writer.uint32(
                length
            )
        }

        writer.signature(
            "8BIM"
        )

        writer.signature(
            layer.blendKey
        )

        writer.uint8(
            layer.opacity
        )

        writer.uint8(
            layer.clipping
        )

        var flags:
            UInt8 =
            0x08

        if !layer.visible {
            flags |=
                0x02
        }

        if layer.transparencyLocked {
            flags |=
                0x01
        }

        writer.uint8(
            flags
        )

        writer.uint8(
            0
        )

        var extra =
            PSDWriter()

        extra.uint32(
            0
        )

        extra.uint32(
            0
        )

        extra.pascalString4(
            layer.name
        )

        extra.unicodeLayerName(
            layer.name
        )

        if layer.protectionFlags != 0 {
            var protection = PSDWriter(); protection.uint32(layer.protectionFlags)
            extra.additionalLayerInfo(key:"lspf",payload:protection.data)
        }

        if let textTool =
                layer.textTool
        {
            extra.additionalLayerInfo(
                key:
                    "TySh",
                payload:
                    typeToolData(
                        textTool
                    )
            )
        }

        if let smartObjectTool =
                layer.smartObjectTool
        {
            extra.additionalLayerInfo(
                key:
                    "plLd",
                payload:
                    placedLayerData(
                        smartObjectTool
                    )
            )
        }

        if let sectionDividerType =
                layer.sectionDividerType
        {
            extra.sectionDivider(
                sectionDividerType
            )
        }

        try writer.length32(
            extra.data
        )
    }

    private static func planarRGB(
        _ raster: Raster
    ) -> (
        red: Data,
        green: Data,
        blue: Data
    ) {
        let count =
            raster.width
            * raster.height

        var red =
            Data(
                capacity:
                    count
            )

        var green =
            Data(
                capacity:
                    count
            )

        var blue =
            Data(
                capacity:
                    count
            )

        var offset =
            0

        while offset + 3 < raster.rgba.count {
            red.append(
                raster.rgba[
                    offset
                ]
            )

            green.append(
                raster.rgba[
                    offset + 1
                ]
            )

            blue.append(
                raster.rgba[
                    offset + 2
                ]
            )

            offset += 4
        }

        return (
            red,
            green,
            blue
        )
    }

    private static func uint32Length(
        _ value: Int
    ) throws -> UInt32 {
        guard value >= 0,
              UInt64(
                value
              )
                <= UInt64(
                    UInt32.max
                )
        else {
            throw ExportError.integerOverflow
        }

        return UInt32(
            value
        )
    }
}

private struct PSDSmartObjectBinaryWriter {
    var data =
        Data()

    mutating func raw(
        _ value:Data
    ) {
        data.append(
            value
        )
    }

    mutating func uint8(
        _ value:UInt8
    ) {
        data.append(
            value
        )
    }

    mutating func uint16(
        _ value:UInt16
    ) {
        var big =
            value.bigEndian

        Swift.withUnsafeBytes(
            of:
                &big
        ) {
            data.append(
                contentsOf:
                    $0
            )
        }
    }

    mutating func int32(
        _ value:Int32
    ) {
        uint32(
            UInt32(
                bitPattern:
                    value
            )
        )
    }

    mutating func uint32(
        _ value:UInt32
    ) {
        var big =
            value.bigEndian

        Swift.withUnsafeBytes(
            of:
                &big
        ) {
            data.append(
                contentsOf:
                    $0
            )
        }
    }

    mutating func uint64(
        _ value:UInt64
    ) {
        var big =
            value.bigEndian

        Swift.withUnsafeBytes(
            of:
                &big
        ) {
            data.append(
                contentsOf:
                    $0
            )
        }
    }

    mutating func double(
        _ value:Double
    ) {
        var big =
            value
                .bitPattern
                .bigEndian

        Swift.withUnsafeBytes(
            of:
                &big
        ) {
            data.append(
                contentsOf:
                    $0
            )
        }
    }

    mutating func signature(
        _ value:String
    ) {
        let bytes =
            Array(
                value.utf8
            )

        precondition(
            bytes.count
                == 4
        )

        data.append(
            contentsOf:
                bytes
        )
    }

    mutating func pascalString(
        _ value:String
    ) {
        let bytes =
            value
                .unicodeScalars
                .map {
                    scalar -> UInt8 in

                    scalar.value < 128
                    ? UInt8(
                        scalar.value
                      )
                    : 63
                }

        let count =
            min(
                255,
                bytes.count
            )

        uint8(
            UInt8(
                count
            )
        )

        data.append(
            contentsOf:
                bytes.prefix(
                    count
                )
        )
    }

    mutating func descriptorUnicodeString(
        _ value:String
    ) {
        let units =
            Array(
                value.utf16
            )

        uint32(
            UInt32(
                units.count
            )
        )

        for unit
            in units
        {
            uint16(
                unit
            )
        }
    }

    mutating func unicodeStringWithNull(
        _ value:String
    ) {
        let units =
            Array(
                value.utf16
            )

        uint32(
            UInt32(
                units.count
                + 1
            )
        )

        for unit
            in units
        {
            uint16(
                unit
            )
        }

        uint16(
            0
        )
    }

    mutating func classID(
        _ value:String
    ) {
        let bytes =
            Array(
                value.utf8
            )

        if bytes.count
            == 4
        {
            uint32(
                0
            )

            data.append(
                contentsOf:
                    bytes
            )
        } else {
            uint32(
                UInt32(
                    bytes.count
                )
            )

            data.append(
                contentsOf:
                    bytes
            )
        }
    }
}


private 
struct PSDDescriptorWriter {
    var data =
        Data()

    mutating func raw(
        _ bytes:Data
    ) {
        data.append(
            bytes
        )
    }

    mutating func rawASCII(
        _ value:String
    ) {
        data.append(
            contentsOf:
                value.utf8
        )
    }

    mutating func uint8(
        _ value:UInt8
    ) {
        data.append(
            value
        )
    }

    mutating func uint16(
        _ value:UInt16
    ) {
        var big =
            value.bigEndian

        Swift.withUnsafeBytes(
            of:
                &big
        ) {
            data.append(
                contentsOf:
                    $0
            )
        }
    }

    mutating func uint32(
        _ value:UInt32
    ) {
        var big =
            value.bigEndian

        Swift.withUnsafeBytes(
            of:
                &big
        ) {
            data.append(
                contentsOf:
                    $0
            )
        }
    }

    mutating func int32(
        _ value:Int32
    ) {
        var big =
            UInt32(
                bitPattern:
                    value
            )
            .bigEndian

        Swift.withUnsafeBytes(
            of:
                &big
        ) {
            data.append(
                contentsOf:
                    $0
            )
        }
    }

    mutating func double(
        _ value:Double
    ) {
        var big =
            value
                .bitPattern
                .bigEndian

        Swift.withUnsafeBytes(
            of:
                &big
        ) {
            data.append(
                contentsOf:
                    $0
            )
        }
    }

    mutating func unicode(
        _ value:String
    ) {
        let units =
            Array(
                value.utf16
            )

        uint32(
            UInt32(
                units.count
            )
        )

        for unit
            in units
        {
            uint16(
                unit
            )
        }
    }

    mutating func classID(
        _ value:String
    ) {
        let bytes =
            Array(
                value.utf8
            )

        if bytes.count
            == 4
        {
            uint32(
                0
            )

            data.append(
                contentsOf:
                    bytes
            )
        } else {
            uint32(
                UInt32(
                    bytes.count
                )
            )

            data.append(
                contentsOf:
                    bytes
            )
        }
    }

    mutating func typeCode(
        _ value:String
    ) {
        let bytes =
            Array(
                value.utf8
            )

        precondition(
            bytes.count == 4
        )

        data.append(
            contentsOf:
                bytes
        )
    }

    mutating func descriptor(
        name:String,
        classID:String,
        itemCount:Int,
        body:
            (
                inout PSDDescriptorWriter
            )->Void
    ) {
        unicode(
            name
        )

        self.classID(
            classID
        )

        uint32(
            UInt32(
                itemCount
            )
        )

        body(
            &self
        )
    }

    mutating func textItem(
        key:String,
        value:String
    ) {
        classID(
            key
        )

        typeCode(
            "TEXT"
        )

        unicode(
            value
        )
    }

    mutating func enumItem(
        key:String,
        type:String,
        value:String
    ) {
        classID(
            key
        )

        typeCode(
            "enum"
        )

        classID(
            type
        )

        classID(
            value
        )
    }

    mutating func int32Item(
        key:String,
        value:Int32
    ) {
        classID(
            key
        )

        typeCode(
            "long"
        )

        int32(
            value
        )
    }

    mutating func doubleItem(
        key:String,
        value:Double
    ) {
        classID(
            key
        )

        typeCode(
            "doub"
        )

        double(
            value
        )
    }

    mutating func unitFloatItem(
        key:String,
        unit:String,
        value:Double
    ) {
        classID(
            key
        )

        typeCode(
            "UntF"
        )

        typeCode(
            unit
        )

        double(
            value
        )
    }

    mutating func objectItem(
        key:String,
        classID:String,
        itemCount:Int,
        body:
            (
                inout PSDDescriptorWriter
            )->Void
    ) {
        self.classID(
            key
        )

        typeCode(
            "Objc"
        )

        descriptor(
            name:
                "",
            classID:
                classID,
            itemCount:
                itemCount,
            body:
                body
        )
    }

    mutating func dataItem(
        key:String,
        value:Data
    ) {
        classID(
            key
        )

        typeCode(
            "tdta"
        )

        uint32(
            UInt32(
                value.count
            )
        )

        raw(
            value
        )
    }
}

struct PSDWriter {
    var data =
        Data()

    mutating func uint8(
        _ value: UInt8
    ) {
        data.append(
            value
        )
    }

    mutating func zeroes(
        _ count: Int
    ) {
        guard count > 0
        else {
            return
        }

        data.append(
            Data(
                repeating:
                    0,
                count:
                    count
            )
        )
    }

    mutating func uint16(
        _ value: UInt16
    ) {
        uint8(
            UInt8(
                (
                    value
                    >> 8
                )
                & 0xFF
            )
        )

        uint8(
            UInt8(
                value
                & 0xFF
            )
        )
    }

    mutating func int16(
        _ value: Int16
    ) {
        uint16(
            UInt16(
                bitPattern:
                    value
            )
        )
    }

    mutating func uint32(
        _ value: UInt32
    ) {
        uint8(
            UInt8(
                (
                    value
                    >> 24
                )
                & 0xFF
            )
        )

        uint8(
            UInt8(
                (
                    value
                    >> 16
                )
                & 0xFF
            )
        )

        uint8(
            UInt8(
                (
                    value
                    >> 8
                )
                & 0xFF
            )
        )

        uint8(
            UInt8(
                value
                & 0xFF
            )
        )
    }

    mutating func int32(
        _ value: Int32
    ) {
        uint32(
            UInt32(
                bitPattern:
                    value
            )
        )
    }

    mutating func signature(
        _ value: String
    ) {
        let bytes =
            Array(
                value.utf8
            )

        precondition(
            bytes.count == 4
        )

        data.append(
            contentsOf:
                bytes
        )
    }

    mutating func length32(
        _ payload: Data
    ) throws {
        guard UInt64(
            payload.count
        )
            <= UInt64(
                UInt32.max
            )
        else {
            throw PSDExporter
                .ExportError
                .integerOverflow
        }

        uint32(
            UInt32(
                payload.count
            )
        )

        data.append(
            payload
        )
    }

    mutating func pascalString4(
        _ value: String
    ) {
        let ascii =
            value.unicodeScalars
                .map {
                    scalar -> UInt8
                    in

                    if scalar.value >= 32,
                       scalar.value <= 126
                    {
                        return UInt8(
                            scalar.value
                        )
                    }

                    return UInt8(
                        ascii:
                            "?"
                    )
                }

        let bytes =
            Array(
                ascii.prefix(
                    255
                )
            )

        let start =
            data.count

        uint8(
            UInt8(
                bytes.count
            )
        )

        data.append(
            contentsOf:
                bytes
        )

        while (
            data.count
            - start
        )
            % 4
            != 0
        {
            uint8(
                0
            )
        }
    }

    mutating func unicodeLayerName(
        _ value: String
    ) {
        let units =
            Array(
                value.utf16
            )

        var payload =
            PSDWriter()

        payload.uint32(
            UInt32(
                min(
                    units.count,
                    Int(
                        UInt32.max
                    )
                )
            )
        )

        for unit in units {
            payload.uint16(
                unit
            )
        }

        signature(
            "8BIM"
        )

        signature(
            "luni"
        )

        uint32(
            UInt32(
                payload.data.count
            )
        )

        data.append(
            payload.data
        )

        if payload.data.count % 2 != 0 {
            uint8(
                0
            )
        }
    }

    mutating func sectionDivider(
        _ type:UInt32
    ) {
        signature(
            "8BIM"
        )

        signature(
            "lsct"
        )

        uint32(
            4
        )

        uint32(
            type
        )
    }


    mutating func additionalLayerInfo(
        key:String,
        payload:Data
    ) {
        precondition(
            key.utf8.count
            == 4
        )

        precondition(
            payload.count
            <= Int(
                UInt32.max
            )
        )

        signature(
            "8BIM"
        )

        signature(
            key
        )

        uint32(
            UInt32(
                payload.count
            )
        )

        data.append(
            payload
        )

        if payload.count
            % 2
            != 0
        {
            uint8(
                0
            )
        }
    }

}
