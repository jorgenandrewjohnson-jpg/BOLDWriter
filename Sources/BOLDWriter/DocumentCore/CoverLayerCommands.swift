import Foundation
import AppKit
import CryptoKit
import ImageIO

/// Structured access to the same persisted cover layers used by the native editor.
/// Frames use normalized canvas coordinates; snapshot also reports physical/pixel units.
enum CoverLayerCommands {
    struct LayerSnapshot: Codable {
        var id: UUID
        var index: Int
        var name: String
        var kind: CoverLayerKind
        var frame: CoverRect
        var frameInches: CoverRect
        var framePixels: CoverRect
        var rotation: Double
        var opacity: Double
        var visible: Bool
        var locked: Bool
        var referenceOnly: Bool
        var blendMode: CoverBlendMode
        var text: String?
        var fontName: String?
        var fontSize: Double?
        var groupID: UUID?
        var flipHorizontal: Bool?
        var flipVertical: Bool?
        var skewX: Double?
        var skewY: Double?
        var horizontalScale: Double?
        var verticalScale: Double?
        var lineSpacing: Double?
        var letterSpacing: Double?
        var alignment: String?
        var positionLocked: Bool?
        var maskEnabled: Bool?
        var maskLinked: Bool?
        var maskDensity: Double?
        var maskOffsetX: Double?
        var maskOffsetY: Double?
        var hasMask: Bool
        var hasSmartObject: Bool
        var colorHex: String
        var leading: Double?
        var underline: Bool?
        var strikethrough: Bool?
        var baselineShift: Double?
        var paragraphIndent: Double?
        var paragraphSpacing: Double?
        var referencePageWidth: Double?
        var pixelsLocked: Bool?
        var transparencyLocked: Bool?
        var imagePixelWidth: Int?
        var imagePixelHeight: Int?
        var embeddedImageSHA256: String?
        var sourceCrop: CoverRect?
        var cropMode: CoverCropMode?
        var cropOffsetX: Double?
        var cropOffsetY: Double?
        var embeddedMaskSHA256: String?
    }
    struct Snapshot: Codable {
        var projectID: UUID
        var name: String
        var canvasWidthInches: Double
        var canvasHeightInches: Double
        var dpi: Double
        var pixelWidth: Double
        var pixelHeight: Double
        var trimWidthInches: Double
        var trimHeightInches: Double
        var spineWidthInches: Double
        var coverPageCount: Int?
        var backPanel: CoverRect
        var spinePanel: CoverRect
        var frontPanel: CoverRect
        var guidesXInches: [Double]
        var guidesYInches: [Double]
        var layers: [LayerSnapshot]
        var psdImportWarnings: [String]?
    }

    static func inspect(_ project: CoverProject) throws -> String {
        func scaled(_ frame: CoverRect, _ scale: Double) -> CoverRect {
            CoverRect(x: frame.x * project.canvasWidth * scale,
                      y: frame.y * project.canvasHeight * scale,
                      width: frame.width * project.canvasWidth * scale,
                      height: frame.height * project.canvasHeight * scale)
        }
        let layers = project.layers.enumerated().map { index, layer in
            // Inspection needs dimensions, not a decoded full-resolution bitmap.
            let properties = layer.imageData.flatMap {
                CGImageSourceCreateWithData($0 as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
            }.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }
            let imageHash = layer.imageData.map { SHA256.hash(data:$0).map { String(format:"%02x",$0) }.joined() }
            return LayerSnapshot(id: layer.id, index: index, name: layer.name, kind: layer.kind,
                frame: layer.frame, frameInches: scaled(layer.frame, 1),
                framePixels: CoverRect(x:layer.frame.x * project.rasterPixelSize.width, y:layer.frame.y * project.rasterPixelSize.height, width:layer.frame.width * project.rasterPixelSize.width, height:layer.frame.height * project.rasterPixelSize.height), rotation: layer.rotation,
                opacity: layer.opacity, visible: layer.visible, locked: layer.locked,
                referenceOnly: layer.isReferenceLayer, blendMode: layer.blendMode ?? .normal,
                text: layer.kind == .text ? layer.text : nil,
                fontName: layer.kind == .text ? layer.fontName : nil,
                fontSize: layer.kind == .text ? layer.fontSize : nil,
                groupID: layer.groupID,
                flipHorizontal: layer.flipHorizontal, flipVertical: layer.flipVertical,
                skewX: layer.skewX, skewY: layer.skewY, horizontalScale: layer.horizontalScale,
                verticalScale: layer.verticalScale, lineSpacing: layer.lineSpacing,
                letterSpacing: layer.letterSpacing, alignment: layer.alignment, positionLocked: layer.positionLocked,
                maskEnabled: layer.maskEnabled, maskLinked: layer.maskLinked, maskDensity: layer.maskDensity,
                maskOffsetX: layer.maskOffsetX, maskOffsetY: layer.maskOffsetY, hasMask: layer.maskData != nil,
                hasSmartObject: layer.smartObject != nil,
                colorHex:layer.colorHex, leading:layer.leading, underline:layer.underline,
                strikethrough:layer.strikethrough, baselineShift:layer.baselineShift,
                paragraphIndent:layer.paragraphIndent, paragraphSpacing:layer.paragraphSpacing,
                referencePageWidth:layer.referencePageWidth, pixelsLocked:layer.pixelsLocked,
                transparencyLocked:layer.transparencyLocked,
                imagePixelWidth:(properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
                imagePixelHeight:(properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
                embeddedImageSHA256:imageHash, sourceCrop:layer.sourceCrop,
                cropMode:layer.cropMode, cropOffsetX:layer.cropOffsetX, cropOffsetY:layer.cropOffsetY,
                embeddedMaskSHA256:layer.maskData.map { SHA256.hash(data:$0).map { String(format:"%02x",$0) }.joined() })
        }
        let wrap = CoverWrapGeometry(project:project)
        let snapshot = Snapshot(projectID: project.id, name: project.name,
            canvasWidthInches: project.canvasWidth, canvasHeightInches: project.canvasHeight,
            dpi: project.dpi, pixelWidth: project.rasterPixelSize.width,
            pixelHeight: project.rasterPixelSize.height,
            trimWidthInches:project.trimWidth,trimHeightInches:project.trimHeight,
            spineWidthInches:project.spineWidth,coverPageCount:project.spinePageCount,
            backPanel:wrap.backTrim,spinePanel:wrap.spineTrim,frontPanel:wrap.frontTrim,
            guidesXInches: project.userGuidesX ?? [], guidesYInches: project.userGuidesY ?? [], layers: layers, psdImportWarnings: project.psdImportWarnings)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(snapshot), as: UTF8.self)
    }

    static let editableFields = ["name", "text", "x", "y", "width", "height", "rotation",
                                 "opacity", "visible", "locked", "blendMode", "fontName", "fontSize", "colorHex", "flipHorizontal", "flipVertical", "skewX", "skewY", "horizontalScale", "verticalScale", "lineSpacing", "letterSpacing", "alignment", "maskEnabled", "maskLinked", "maskDensity", "maskOffsetX", "maskOffsetY", "positionLocked"]

    /// Validate the whole patch before replacing a layer. A rejected action changes nothing.
    static func update(_ project: inout CoverProject, arguments: [String: String]) throws -> UUID {
        guard let rawID = arguments["layerID"], let id = UUID(uuidString: rawID),
              let index = project.layers.firstIndex(where: { $0.id == id }) else {
            throw WriterError.message("Use an existing layerID from cover inspect.")
        }
        let fields = arguments.filter { $0.key != "layerID" }
        guard !fields.isEmpty, Set(fields.keys).isSubset(of: Set(editableFields)) else {
            throw WriterError.message("Provide supported layer fields: \(editableFields.joined(separator: ", ")).")
        }
        var layer = project.layers[index]
        if layer.isReferenceLayer && project.templateLocked {
            throw WriterError.message("Unlock the template in Cover Creator before editing its reference layers.")
        }
        if layer.locked && !(fields.count == 1 && fields["locked"] == "false") {
            throw WriterError.message("Unlock the layer with locked=false before editing it.")
        }
        let geometry = Set(["x", "y", "width", "height", "rotation", "flipHorizontal", "flipVertical", "skewX", "skewY"])
        if layer.positionLocked == true && !geometry.isDisjoint(with: fields.keys) {
            throw WriterError.message("This layer's position is locked.")
        }
        func number(_ key: String, _ range: ClosedRange<Double>) throws -> Double? {
            guard let value = fields[key] else { return nil }
            guard let value = Double(value), value.isFinite, range.contains(value) else {
                throw WriterError.message("\(key) must be a finite number in \(range).")
            }
            return value
        }
        func boolean(_ key: String) throws -> Bool? {
            guard let value = fields[key] else { return nil }
            guard value == "true" || value == "false" else {
                throw WriterError.message("\(key) must be true or false.")
            }
            return value == "true"
        }
        if let value = fields["name"] {
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, value.count <= 512 else {
                throw WriterError.message("Use a layer name of 1 to 512 characters.")
            }
            layer.name = value
        }
        let textFields = Set(["text", "fontName", "fontSize", "colorHex", "horizontalScale", "verticalScale", "lineSpacing", "letterSpacing", "alignment"])
        if !textFields.isDisjoint(with: fields.keys) && layer.kind != .text {
            throw WriterError.message("Text properties require an editable text layer.")
        }
        if let value = fields["text"] { layer.text = value }
        if let value = fields["fontName"] {
            guard !value.isEmpty, value.count <= 256 else { throw WriterError.message("Use a nonempty font name.") }
            layer.fontName = value
        }
        if let value = try number("fontSize", 1...500) { layer.fontSize = value }
        if let value = fields["colorHex"] {
            guard value.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil else {
                throw WriterError.message("Use a #RRGGBB text color.")
            }
            layer.colorHex = value
        }
        if let value = try number("x", -4...4) { layer.frame.x = value }
        if let value = try number("y", -4...4) { layer.frame.y = value }
        if let value = try number("width", 0.000001...4) { layer.frame.width = value }
        if let value = try number("height", 0.000001...4) { layer.frame.height = value }
        if let value = try number("rotation", -360...360) { layer.rotation = value }
        if let value = try number("opacity", 0...1) { layer.opacity = value }
        if let value = try boolean("flipHorizontal") { layer.flipHorizontal = value }
        if let value = try boolean("flipVertical") { layer.flipVertical = value }
        if let value = try boolean("positionLocked") { layer.positionLocked = value }
        if let value = try number("skewX", -80...80) { layer.skewX = value }
        if let value = try number("skewY", -80...80) { layer.skewY = value }
        if let value = try number("horizontalScale", 0.1...10) { layer.horizontalScale = value }
        if let value = try number("verticalScale", 0.1...10) { layer.verticalScale = value }
        if let value = try number("lineSpacing", 0...2000) { layer.lineSpacing = value }
        if let value = try number("letterSpacing", -500...500) { layer.letterSpacing = value }
        if let value = fields["alignment"] {
            guard CoverTypography.alignments.contains(value) else { throw WriterError.message("Unsupported text alignment.") }
            layer.alignment = value
        }
        let maskFields = Set(["maskEnabled","maskLinked","maskDensity","maskOffsetX","maskOffsetY"])
        if !maskFields.isDisjoint(with:fields.keys), layer.maskData == nil { throw WriterError.message("The layer has no mask to edit.") }
        if let value = try boolean("maskEnabled") { layer.maskEnabled = value }
        if let value = try boolean("maskLinked") { layer.maskLinked = value }
        if let value = try number("maskDensity",0...1) { layer.maskDensity = value }
        if let value = try number("maskOffsetX",-1...1) { layer.maskOffsetX = value }
        if let value = try number("maskOffsetY",-1...1) { layer.maskOffsetY = value }
        if let value = try boolean("visible") { layer.visible = value }
        if let value = try boolean("locked") { layer.locked = value }
        if let value = fields["blendMode"] {
            guard let blend = CoverBlendMode(rawValue: value) else {
                throw WriterError.message("Use a supported blend mode: \(CoverBlendMode.allCases.map(\.rawValue).joined(separator: ", ")).")
            }
            layer.blendMode = blend
        }
        var updated = project
        updated.layers[index] = layer
        try CoverProject.validate([updated])
        try CoverProjectOperations.replace(layer, in: &project)
        return id
    }
}
