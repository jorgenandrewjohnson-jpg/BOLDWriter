import AppKit
import Foundation

enum SVGExporter {
    private static let maximumRasterLayerBytes = 100_000_000
    private static let maximumTotalRasterBytes = 250_000_000

    private struct ExportContext {
        let project: CoverProject
        let width: Double
        let height: Double

        var definitions: [String] = []
        var body: [String] = []
        var rasterBytes = 0
    }

    static func export(_ project: CoverProject) throws -> Data {
        try CoverProject.validate([project])

        guard project.canvasWidth.isFinite,
              project.canvasHeight.isFinite,
              project.canvasWidth > 0,
              project.canvasHeight > 0
        else {
            throw WriterError.message(
                "The SVG canvas dimensions are invalid."
            )
        }

        var context = ExportContext(
            project: project,
            width: project.canvasWidth,
            height: project.canvasHeight
        )

        context.body.append(
            """
            <rect id="bold-background" x="0" y="0" width="\(number(context.width))" height="\(number(context.height))" fill="\(color(project.backgroundHex, fallback: "#FFFFFF"))"/>
            """
        )

        for (index, layer) in project.layers.enumerated() where layer.referenceOnly != true {
            try appendLayer(
                layer,
                index: index,
                context: &context
            )
        }

        var output: [String] = []

        output.append(
            #"<?xml version="1.0" encoding="UTF-8"?>"#
        )

        output.append(
            """
            <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="\(number(context.width))in" height="\(number(context.height))in" viewBox="0 0 \(number(context.width)) \(number(context.height))" data-bold-project="\(xmlAttribute(project.name))">
            """
        )

        if !context.definitions.isEmpty {
            output.append("<defs>")
            output.append(contentsOf: context.definitions)
            output.append("</defs>")
        }

        output.append(contentsOf: context.body)
        output.append("</svg>")

        let string = output.joined(separator: "\n") + "\n"

        guard let data = string.data(using: .utf8) else {
            throw WriterError.message(
                "BOLD Writer could not encode SVG output as UTF-8."
            )
        }

        return data
    }

    private static func appendLayer(
        _ layer: CoverLayer,
        index: Int,
        context: inout ExportContext
    ) throws {
        if layer.kind == .group {
            context.body.append(
                """
                <g id="layer-\(index)" data-bold-kind="group" data-bold-name="\(xmlAttribute(layer.name))"></g>
                """
            )
            return
        }

        if layer.kind == .adjustment {
            context.body.append(
                """
                <!-- BOLD adjustment layer \(index): \(xmlComment(layer.name)) -->
                """
            )
            return
        }

        guard layer.frame.x.isFinite,
              layer.frame.y.isFinite,
              layer.frame.width.isFinite,
              layer.frame.height.isFinite,
              layer.frame.width >= 0,
              layer.frame.height >= 0
        else {
            throw WriterError.message(
                "A cover layer contains invalid SVG geometry."
            )
        }

        let x = layer.frame.x * context.width
        let y = layer.frame.y * context.height
        let width = layer.frame.width * context.width
        let height = layer.frame.height * context.height

        let gradientID = gradientDefinition(
            for: layer,
            index: index,
            context: &context
        )

        let maskID = try maskDefinition(
            for: layer,
            index: index,
            width: width,
            height: height,
            context: &context
        )

        let attributes = groupAttributes(
            for: layer,
            index: index,
            x: x,
            y: y,
            width: width,
            height: height,
            maskID: maskID
        )

        var contents: [String] = []

        switch layer.kind {
        case .shape:
            contents.append(
                try shapeElement(
                    layer,
                    width: width,
                    height: height,
                    gradientID: gradientID
                )
            )

        case .path:
            contents.append(
                try pathElement(
                    layer,
                    width: width,
                    height: height,
                    gradientID: gradientID
                )
            )

        case .gradient:
            let fill = gradientID.map {
                "url(#\($0))"
            } ?? color(
                layer.fillHex,
                fallback: "#FFFFFF"
            )

            contents.append(
                """
                <rect x="0" y="0" width="\(number(width))" height="\(number(height))" fill="\(fill)"/>
                """
            )

        case .text:
            contents.append(
                textElement(
                    layer,
                    width: width,
                    height: height
                )
            )

        case .image, .template:
            if let bytes = layer.imageData {
                contents.append(
                    try rasterElement(
                        bytes,
                        width: width,
                        height: height,
                        preserveAspectRatio: aspectRatio(for: layer),
                        context: &context
                    )
                )
            }

        case .paint:
            if let bytes = layer.imageData {
                contents.append(
                    try rasterElement(
                        bytes,
                        width: width,
                        height: height,
                        preserveAspectRatio: "none",
                        context: &context
                    )
                )
            }

        case .smartObject:
            if let bytes = layer.imageData {
                contents.append(
                    try rasterElement(
                        bytes,
                        width: width,
                        height: height,
                        preserveAspectRatio: aspectRatio(for: layer),
                        context: &context
                    )
                )
            } else if let bytes = layer.smartObject?.sourceData,
                      let normalized = normalizedRaster(bytes)
            {
                contents.append(
                    try rasterElement(
                        normalized.data,
                        mime: normalized.mime,
                        width: width,
                        height: height,
                        preserveAspectRatio: aspectRatio(for: layer),
                        context: &context
                    )
                )
            }

        case .group, .adjustment:
            break
        }

        context.body.append(
            """
            <g \(attributes)>
            \(contents.joined(separator: "\n"))
            </g>
            """
        )
    }

    private static func groupAttributes(
        for layer: CoverLayer,
        index: Int,
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        maskID: String?
    ) -> String {
        var attributes: [String] = [
            #"id="layer-\#(index)""#,
            #"data-bold-kind="\#(xmlAttribute(layer.kind.rawValue))""#,
            #"data-bold-name="\#(xmlAttribute(layer.name))""#,
            #"opacity="\#(number(layer.opacity))""#
        ]

        if !layer.visible {
            attributes.append(
                #"display="none""#
            )
        }

        if let groupID = layer.groupID {
            attributes.append(
                #"data-bold-group="\#(xmlAttribute(groupID.uuidString))""#
            )
        }

        if let linkSetID = layer.linkSetID {
            attributes.append(
                #"data-bold-link-set="\#(xmlAttribute(linkSetID.uuidString))""#
            )
        }

        if let clippedTo = layer.clippedToLayerID {
            attributes.append(
                #"data-bold-clipped-to="\#(xmlAttribute(clippedTo.uuidString))""#
            )
        }

        if let maskID {
            attributes.append(
                #"mask="url(#\#(maskID))""#
            )
        }

        if let blend = cssBlendMode(layer.blendMode) {
            attributes.append(
                #"style="mix-blend-mode:\#(blend)""#
            )
        }

        attributes.append(
            #"transform="\#(transform(for: layer, x: x, y: y, width: width, height: height))""#
        )

        return attributes.joined(separator: " ")
    }

    private static func transform(
        for layer: CoverLayer,
        x: Double,
        y: Double,
        width: Double,
        height: Double
    ) -> String {
        let cx = width / 2
        let cy = height / 2

        let flipX = layer.flipHorizontal ? -1.0 : 1.0
        let flipY = layer.flipVertical ? -1.0 : 1.0

        let skewX = layer.skewX ?? 0
        let skewY = layer.skewY ?? 0

        return [
            "translate(\(number(x)) \(number(y)))",
            "translate(\(number(cx)) \(number(cy)))",
            "rotate(\(number(layer.rotation)))",
            "matrix(1 \(number(skewY)) \(number(skewX)) 1 0 0)",
            "scale(\(number(flipX)) \(number(flipY)))",
            "translate(\(number(-cx)) \(number(-cy)))"
        ].joined(separator: " ")
    }

    private static func shapeElement(
        _ layer: CoverLayer,
        width: Double,
        height: Double,
        gradientID: String?
    ) throws -> String {
        let style = vectorStyle(
            layer,
            gradientID: gradientID
        )

        switch layer.shape {
        case .rectangle:
            let radius = max(
                0,
                min(
                    min(width, height) / 2,
                    (layer.cornerRadius ?? 0)
                        * min(width, height)
                )
            )

            return """
            <rect x="0" y="0" width="\(number(width))" height="\(number(height))" rx="\(number(radius))" ry="\(number(radius))" \(style)/>
            """

        case .ellipse:
            return """
            <ellipse cx="\(number(width / 2))" cy="\(number(height / 2))" rx="\(number(width / 2))" ry="\(number(height / 2))" \(style)/>
            """

        case .line:
            return """
            <line x1="0" y1="0" x2="\(number(width))" y2="\(number(height))" fill="none" \(strokeStyle(layer))/>
            """
        }
    }

    private static func pathElement(
        _ layer: CoverLayer,
        width: Double,
        height: Double,
        gradientID: String?
    ) throws -> String {
        let contours: [[CoverPathPoint]]

        if let compound = layer.pathContours,
           !compound.isEmpty
        {
            contours = compound
        } else if let points = layer.pathPoints,
                  !points.isEmpty
        {
            contours = [points]
        } else {
            return """
            <path d="" \(vectorStyle(layer, gradientID: gradientID))/>
            """
        }

        let closures: [Bool]

        if let explicit = layer.pathContourClosed,
           explicit.count == contours.count
        {
            closures = explicit
        } else {
            closures = Array(
                repeating: layer.pathClosed ?? true,
                count: contours.count
            )
        }

        var commands: [String] = []

        for (contourIndex, contour) in contours.enumerated() {
            guard let first = contour.first else {
                continue
            }

            try validate(point: first)

            commands.append(
                "M \(number(first.x * width)) \(number(first.y * height))"
            )

            if contour.count > 1 {
                for index in 1..<contour.count {
                    let previous = contour[index - 1]
                    let current = contour[index]

                    try validate(point: current)

                    commands.append(
                        segment(
                            from: previous,
                            to: current,
                            width: width,
                            height: height
                        )
                    )
                }
            }

            if closures[contourIndex] {
                if contour.count > 1,
                   let last = contour.last,
                   hasCurve(from: last, to: first)
                {
                    commands.append(
                        segment(
                            from: last,
                            to: first,
                            width: width,
                            height: height
                        )
                    )
                }

                commands.append("Z")
            }
        }

        return """
        <path d="\(xmlAttribute(commands.joined(separator: " ")))" \(vectorStyle(layer, gradientID: gradientID))/>
        """
    }

    private static func segment(
        from previous: CoverPathPoint,
        to current: CoverPathPoint,
        width: Double,
        height: Double
    ) -> String {
        if hasCurve(from: previous, to: current) {
            let c1x = (previous.controlOutX ?? previous.x) * width
            let c1y = (previous.controlOutY ?? previous.y) * height
            let c2x = (current.controlInX ?? current.x) * width
            let c2y = (current.controlInY ?? current.y) * height

            return """
            C \(number(c1x)) \(number(c1y)) \(number(c2x)) \(number(c2y)) \(number(current.x * width)) \(number(current.y * height))
            """
        }

        return """
        L \(number(current.x * width)) \(number(current.y * height))
        """
    }

    private static func hasCurve(
        from previous: CoverPathPoint,
        to current: CoverPathPoint
    ) -> Bool {
        previous.controlOutX != nil
            || previous.controlOutY != nil
            || current.controlInX != nil
            || current.controlInY != nil
    }

    private static func validate(
        point: CoverPathPoint
    ) throws {
        let values = [
            point.x,
            point.y,
            point.controlInX,
            point.controlInY,
            point.controlOutX,
            point.controlOutY
        ].compactMap { $0 }

        guard values.allSatisfy({ $0.isFinite }) else {
            throw WriterError.message(
                "A vector path contains a nonfinite SVG coordinate."
            )
        }
    }

    private static func vectorStyle(
        _ layer: CoverLayer,
        gradientID: String?
    ) -> String {
        let fill = gradientID.map {
            "url(#\($0))"
        } ?? color(
            layer.fillHex,
            fallback: "#FFFFFF"
        )

        let fillOpacity = max(
            0,
            min(
                1,
                layer.fillOpacity ?? 1
            )
        )

        return [
            #"fill="\#(fill)""#,
            #"fill-opacity="\#(number(fillOpacity))""#,
            #"fill-rule="\#(layer.fillRule == .nonZero ? "nonzero" : "evenodd")""#,
            strokeStyle(layer)
        ].joined(separator: " ")
    }

    private static func strokeStyle(
        _ layer: CoverLayer
    ) -> String {
        let width = max(
            0,
            layer.strokeWidth / 72
        )

        var attributes: [String] = [
            #"stroke="\#(color(layer.strokeHex, fallback: "#202020"))""#,
            #"stroke-width="\#(number(width))""#,
            #"stroke-linecap="\#((layer.strokeCap ?? .butt).rawValue)""#,
            #"stroke-linejoin="\#((layer.strokeJoin ?? .miter).rawValue)""#,
            #"stroke-miterlimit="\#(number(layer.strokeMiterLimit ?? 4))""#
        ]

        if let dash = layer.strokeDashPattern,
           !dash.isEmpty
        {
            attributes.append(
                #"stroke-dasharray="\#(dash.map { number(max(0, $0 / 72)) }.joined(separator: " "))""#
            )
        }

        if let phase = layer.strokeDashPhase,
           phase != 0
        {
            attributes.append(
                #"stroke-dashoffset="\#(number(phase / 72))""#
            )
        }

        return attributes.joined(separator: " ")
    }

    private static func gradientDefinition(
        for layer: CoverLayer,
        index: Int,
        context: inout ExportContext
    ) -> String? {
        let hasGradient =
            layer.kind == .gradient
            || layer.gradientStops?.isEmpty == false
            || layer.gradientEndHex != nil

        guard hasGradient else {
            return nil
        }

        let id = "gradient-\(index)"

        var stops: [CoverGradientStop]

        if let existing = layer.gradientStops,
           !existing.isEmpty
        {
            stops = existing
        } else {
            var first = CoverGradientStop()
            first.colorHex = layer.fillHex
            first.location = 0
            first.opacity = 1

            var second = CoverGradientStop()
            second.colorHex = layer.gradientEndHex ?? layer.fillHex
            second.location = 1
            second.opacity = 1

            stops = [
                first,
                second
            ]
        }

        stops.sort {
            if $0.location == $1.location {
                return $0.id.uuidString
                    < $1.id.uuidString
            }

            return $0.location
                < $1.location
        }

        if layer.gradientReversed == true {
            stops = stops
                .reversed()
                .map {
                    var copy = $0
                    copy.location = 1 - copy.location
                    return copy
                }
                .sorted {
                    $0.location < $1.location
                }
        }

        let stopXML = stops.map {
            """
            <stop offset="\(number(max(0, min(1, $0.location)) * 100))%" stop-color="\(color($0.colorHex, fallback: "#FFFFFF"))" stop-opacity="\(number(max(0, min(1, $0.opacity))))"/>
            """
        }
        .joined(separator: "\n")

        if layer.gradientRadial == true {
            let cx = max(
                0,
                min(
                    1,
                    layer.gradientCenterX ?? 0.5
                )
            )

            let cy = max(
                0,
                min(
                    1,
                    layer.gradientCenterY ?? 0.5
                )
            )

            let radius = max(
                0.000001,
                min(
                    2,
                    layer.gradientRadius ?? 0.5
                )
            )

            context.definitions.append(
                """
                <radialGradient id="\(id)" cx="\(number(cx * 100))%" cy="\(number(cy * 100))%" r="\(number(radius * 100))%">
                \(stopXML)
                </radialGradient>
                """
            )
        } else {
            let radians =
                (layer.gradientAngle ?? 0)
                * Double.pi
                / 180

            let dx = cos(radians) * 0.5
            let dy = sin(radians) * 0.5

            context.definitions.append(
                """
                <linearGradient id="\(id)" x1="\(number((0.5 - dx) * 100))%" y1="\(number((0.5 - dy) * 100))%" x2="\(number((0.5 + dx) * 100))%" y2="\(number((0.5 + dy) * 100))%">
                \(stopXML)
                </linearGradient>
                """
            )
        }

        return id
    }

    private static func textElement(
        _ layer: CoverLayer,
        width: Double,
        height: Double
    ) -> String {
        let horizontalScale = max(
            0.000001,
            layer.horizontalScale ?? 1
        )

        let verticalScale = max(
            0.000001,
            layer.verticalScale ?? 1
        )

        let anchor: String
        let x: Double

        switch layer.alignment {
        case "left":
            anchor = "start"
            x = 0

        case "right":
            anchor = "end"
            x = width

        default:
            anchor = "middle"
            x = width / 2
        }

        let fontSize =
            layer.fontSize / 72

        let leading =
            (layer.leading
                ?? (
                    layer.fontSize
                    * max(
                        0.1,
                        layer.lineSpacing
                    )
                )
            )
            / 72

        let baseline =
            fontSize
            + (layer.baselineShift ?? 0)
            / 72

        let decoration: String

        switch (
            layer.underline == true,
            layer.strikethrough == true
        ) {
        case (true, true):
            decoration = "underline line-through"

        case (true, false):
            decoration = "underline"

        case (false, true):
            decoration = "line-through"

        case (false, false):
            decoration = "none"
        }

        let lines =
            layer.text.components(
                separatedBy: "\n"
            )

        var spans: [String] = []

        for (index, line) in lines.enumerated() {
            let dy =
                index == 0
                ? 0
                : leading

            spans.append(
                """
                <tspan x="\(number(x / horizontalScale))" dy="\(number(dy / verticalScale))">\(xmlText(line))</tspan>
                """
            )
        }

        return """
        <g transform="scale(\(number(horizontalScale)) \(number(verticalScale)))">
        <text x="\(number(x / horizontalScale))" y="\(number(baseline / verticalScale))" font-family="\(xmlAttribute(layer.fontName))" font-size="\(number(fontSize / verticalScale))" font-weight="\(layer.bold ? "bold" : "normal")" font-style="\(layer.italic ? "italic" : "normal")" text-anchor="\(anchor)" fill="\(color(layer.colorHex, fallback: "#202020"))" letter-spacing="\(number(layer.letterSpacing / 72 / horizontalScale))" text-decoration="\(decoration)">
        \(spans.joined(separator: "\n"))
        </text>
        </g>
        """
    }

    private static func maskDefinition(
        for layer: CoverLayer,
        index: Int,
        width: Double,
        height: Double,
        context: inout ExportContext
    ) throws -> String? {
        guard layer.maskEnabled != false,
              let bytes = layer.maskData
        else {
            return nil
        }

        let raster = try rasterData(bytes)

        try account(
            raster.data,
            context: &context
        )

        let id = "mask-\(index)"

        let density = max(
            0,
            min(
                1,
                layer.maskDensity ?? 1
            )
        )

        let offsetX =
            (layer.maskOffsetX ?? 0)
            * width

        let offsetY =
            (layer.maskOffsetY ?? 0)
            * height

        context.definitions.append(
            """
            <mask id="\(id)" maskUnits="userSpaceOnUse" x="0" y="0" width="\(number(width))" height="\(number(height))" style="mask-type:luminance">
            <image x="\(number(offsetX))" y="\(number(offsetY))" width="\(number(width))" height="\(number(height))" preserveAspectRatio="none" opacity="\(number(density))" href="data:\(raster.mime);base64,\(raster.data.base64EncodedString())"/>
            </mask>
            """
        )

        return id
    }

    private static func rasterElement(
        _ bytes: Data,
        width: Double,
        height: Double,
        preserveAspectRatio: String,
        context: inout ExportContext
    ) throws -> String {
        let raster = try rasterData(bytes)

        return try rasterElement(
            raster.data,
            mime: raster.mime,
            width: width,
            height: height,
            preserveAspectRatio: preserveAspectRatio,
            context: &context
        )
    }

    private static func rasterElement(
        _ bytes: Data,
        mime: String,
        width: Double,
        height: Double,
        preserveAspectRatio: String,
        context: inout ExportContext
    ) throws -> String {
        try account(
            bytes,
            context: &context
        )

        return """
        <image x="0" y="0" width="\(number(width))" height="\(number(height))" preserveAspectRatio="\(preserveAspectRatio)" href="data:\(mime);base64,\(bytes.base64EncodedString())"/>
        """
    }

    private static func aspectRatio(
        for layer: CoverLayer
    ) -> String {
        switch layer.cropMode {
        case .fit:
            return "xMidYMid meet"

        case .fill:
            return "xMidYMid slice"

        case .free:
            return "none"
        }
    }

    private static func account(
        _ data: Data,
        context: inout ExportContext
    ) throws {
        guard data.count <= maximumRasterLayerBytes else {
            throw WriterError.message(
                "An SVG raster fallback exceeds BOLD Writer's safe layer-size limit."
            )
        }

        let result =
            context.rasterBytes
            .addingReportingOverflow(
                data.count
            )

        guard !result.overflow,
              result.partialValue
                <= maximumTotalRasterBytes
        else {
            throw WriterError.message(
                "The SVG contains too much embedded raster fallback data."
            )
        }

        context.rasterBytes =
            result.partialValue
    }

    private static func rasterData(
        _ bytes: Data
    ) throws -> (
        mime: String,
        data: Data
    ) {
        if let normalized = normalizedRaster(bytes) {
            return normalized
        }

        throw WriterError.message(
            "An SVG raster fallback could not be encoded."
        )
    }

    private static func normalizedRaster(
        _ bytes: Data
    ) -> (
        mime: String,
        data: Data
    )? {
        if bytes.starts(
            with: [
                0x89,
                0x50,
                0x4E,
                0x47,
                0x0D,
                0x0A,
                0x1A,
                0x0A
            ]
        ) {
            return (
                "image/png",
                bytes
            )
        }

        if bytes.starts(
            with: [
                0xFF,
                0xD8,
                0xFF
            ]
        ) {
            return (
                "image/jpeg",
                bytes
            )
        }

        guard let image = NSImage(data: bytes),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(
                using: .png,
                properties: [:]
              )
        else {
            return nil
        }

        return (
            "image/png",
            png
        )
    }

    private static func cssBlendMode(
        _ mode: CoverBlendMode?
    ) -> String? {
        guard let mode else {
            return nil
        }

        switch mode {
        case .normal:
            return nil
        case .multiply:
            return "multiply"
        case .screen:
            return "screen"
        case .overlay:
            return "overlay"
        case .darken:
            return "darken"
        case .lighten:
            return "lighten"
        case .colorBurn:
            return "color-burn"
        case .colorDodge:
            return "color-dodge"
        case .softLight:
            return "soft-light"
        case .hardLight:
            return "hard-light"
        case .difference:
            return "difference"
        case .exclusion:
            return "exclusion"
        case .hue:
            return "hue"
        case .saturation:
            return "saturation"
        case .color:
            return "color"
        case .luminosity:
            return "luminosity"
        case .plusDarker:
            return "darken"
        case .plusLighter:
            return "lighten"
        }
    }

    private static func color(
        _ value: String,
        fallback: String
    ) -> String {
        let trimmed =
            value.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        if trimmed.range(
            of: #"^#[0-9A-Fa-f]{6}$"#,
            options: .regularExpression
        ) != nil {
            return trimmed.uppercased()
        }

        return fallback
    }

    private static func number(
        _ value: Double
    ) -> String {
        guard value.isFinite else {
            return "0"
        }

        let safe =
            abs(value) < 0.0000005
            ? 0
            : value

        var result = String(
            format: "%.6f",
            locale: Locale(
                identifier: "en_US_POSIX"
            ),
            safe
        )

        while result.contains("."),
              result.hasSuffix("0")
        {
            result.removeLast()
        }

        if result.hasSuffix(".") {
            result.removeLast()
        }

        return result == "-0"
            ? "0"
            : result
    }

    private static func xmlText(
        _ value: String
    ) -> String {
        value
            .replacingOccurrences(
                of: "&",
                with: "&amp;"
            )
            .replacingOccurrences(
                of: "<",
                with: "&lt;"
            )
            .replacingOccurrences(
                of: ">",
                with: "&gt;"
            )
    }

    private static func xmlAttribute(
        _ value: String
    ) -> String {
        xmlText(value)
            .replacingOccurrences(
                of: "\"",
                with: "&quot;"
            )
            .replacingOccurrences(
                of: "'",
                with: "&apos;"
            )
    }

    private static func xmlComment(
        _ value: String
    ) -> String {
        value
            .replacingOccurrences(
                of: "--",
                with: "—"
            )
            .replacingOccurrences(
                of: "<",
                with: "‹"
            )
            .replacingOccurrences(
                of: ">",
                with: "›"
            )
    }
}
