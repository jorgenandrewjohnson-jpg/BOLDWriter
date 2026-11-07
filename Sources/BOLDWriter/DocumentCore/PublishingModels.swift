import AppKit
import Foundation
import PDFKit
import ImageIO

enum PublishingTOCMode: String, Codable, CaseIterable, Identifiable {
    case printBook = "Print Book"
    case kindle = "Kindle / eBook"
    case digitalPDF = "Digital / PDF"
    var id: String { rawValue }
    var usesPageNumbers: Bool { self != .kindle }
}

enum PublishingTOCLeader: String, Codable, CaseIterable, Identifiable {
    case dots, dashes, solid, none
    var id: String { rawValue }
    var glyph: String { switch self { case .dots: "."; case .dashes: "–"; case .solid: "─"; case .none: "" } }
}

struct PublishingTOCSettings: Codable, Equatable, Identifiable {
    var fieldID: UUID
    var mode: PublishingTOCMode
    var maximumHeadingLevel: Int = 3
    var showTitle = true
    var title = "Contents"
    var suppressTopLevelPageNumbers = false
    var leader: PublishingTOCLeader = .dots
    var fontName = "Georgia"
    var fontSize = 12.0
    var boldTopLevel = true
    var indentationPerLevel = 18.0
    var lineSpacing = 3.0
    var numberAlignment = "right"
    var id: UUID { fieldID }

    init(fieldID: UUID, mode: PublishingTOCMode, maximumHeadingLevel: Int = 3) {
        self.fieldID = fieldID
        self.mode = mode
        self.maximumHeadingLevel = min(6, max(1, maximumHeadingLevel))
        if mode == .kindle { leader = .none }
    }
    static func validate(_ values:[PublishingTOCSettings]) throws {
        var ids=Set<UUID>()
        for value in values {
            guard ids.insert(value.fieldID).inserted,(1...6).contains(value.maximumHeadingLevel),value.title.utf8.count<=4096,value.fontName.utf8.count<=256,value.fontSize.isFinite,(4...200).contains(value.fontSize),value.indentationPerLevel.isFinite,(0...120).contains(value.indentationPerLevel),value.lineSpacing.isFinite,(0...36).contains(value.lineSpacing),["left","right"].contains(value.numberAlignment) else { throw WriterError.message("The document contains invalid publishing TOC settings.") }
        }
    }
}

enum CoverProjectType: String, Codable, CaseIterable, Identifiable {
    case ebookFront, printFullWrap
    var id: String { rawValue }
    var displayName: String { self == .ebookFront ? "eBook Front Cover" : "Print Full Wrap" }
}

/// Verified print provider measurements, in inches. Keep provider constants here so
/// project setup, region placement, and later physical previews share one source.
enum PrintCoverSpecification {
    static let kdpBlackAndWhiteWhitePaperCaliper = 0.002252
    static let kdpBlackAndWhiteCreamPaperCaliper = 0.0025
}

enum PrintPaperStockPreset:
    String,
    Codable,
    CaseIterable,
    Identifiable
{
    case kdpWhite = "KDP B&W — White Paper"
    case kdpCream = "KDP B&W — Cream Paper"
    case custom = "Custom Caliper"

    var id: String { rawValue }

    var caliperInches: Double? {
        switch self {
        case .kdpWhite:
            PrintCoverSpecification
                .kdpBlackAndWhiteWhitePaperCaliper
        case .kdpCream:
            PrintCoverSpecification
                .kdpBlackAndWhiteCreamPaperCaliper
        case .custom:
            nil
        }
    }

    var bookPaperTone: BookPaperTone? {
        switch self {
        case .kdpWhite:
            .white
        case .kdpCream:
            .cream
        case .custom:
            nil
        }
    }

    static func inferred(
        caliper: Double?
    ) -> Self {
        guard let caliper else {
            return .custom
        }

        if abs(
            caliper
                - PrintCoverSpecification
                    .kdpBlackAndWhiteWhitePaperCaliper
        ) < 0.0000001 {
            return .kdpWhite
        }

        if abs(
            caliper
                - PrintCoverSpecification
                    .kdpBlackAndWhiteCreamPaperCaliper
        ) < 0.0000001 {
            return .kdpCream
        }

        return .custom
    }
}

enum CoverLayerKind: String, Codable { case template, image, text, shape, paint, adjustment, gradient, group, path, smartObject }
enum CoverShapeKind: String, Codable, CaseIterable, Identifiable { case rectangle, line, ellipse; var id:String{rawValue} }
enum CoverCropMode: String, Codable { case fit, fill, free }

enum CoverSmartObjectSourceKind:
    String,
    Codable,
    Equatable
{
    case rasterImage
    case pdf
    case svg
    case psd
}

enum CoverSmartObjectStorageMode:
    String,
    Codable,
    Equatable
{
    case embedded
    case linked
}


struct CoverSmartObject:
    Codable,
    Equatable
{
    var sourceKind:
        CoverSmartObjectSourceKind

    var sourceData:
        Data

    var sourceFilename:
        String?

    var intrinsicWidth:
        Int

    var intrinsicHeight:
        Int

    var storageMode:
        CoverSmartObjectStorageMode

    var linkedBookmarkData:
        Data?

    var linkedLastKnownModificationDate:
        Date?

    var linkedLastKnownFileSize:
        Int64?

    init(
        sourceKind: CoverSmartObjectSourceKind,
        sourceData: Data,
        sourceFilename: String?,
        intrinsicWidth: Int,
        intrinsicHeight: Int,
        storageMode: CoverSmartObjectStorageMode = .embedded,
        linkedBookmarkData: Data? = nil,
        linkedLastKnownModificationDate: Date? = nil,
        linkedLastKnownFileSize: Int64? = nil
    ) {
        self.sourceKind =
            sourceKind

        self.sourceData =
            sourceData

        self.sourceFilename =
            sourceFilename

        self.intrinsicWidth =
            intrinsicWidth

        self.intrinsicHeight =
            intrinsicHeight

        self.storageMode =
            storageMode

        self.linkedBookmarkData =
            linkedBookmarkData

        self.linkedLastKnownModificationDate =
            linkedLastKnownModificationDate

        self.linkedLastKnownFileSize =
            linkedLastKnownFileSize
    }

    private enum CodingKeys:
        String,
        CodingKey
    {
        case sourceKind
        case sourceData
        case sourceFilename
        case intrinsicWidth
        case intrinsicHeight
        case storageMode
        case linkedBookmarkData
        case linkedLastKnownModificationDate
        case linkedLastKnownFileSize
    }

    init(
        from decoder: Decoder
    ) throws {
        let container =
            try decoder.container(
                keyedBy:
                    CodingKeys.self
            )

        sourceKind =
            try container.decode(
                CoverSmartObjectSourceKind.self,
                forKey:
                    .sourceKind
            )

        sourceData =
            try container.decode(
                Data.self,
                forKey:
                    .sourceData
            )

        sourceFilename =
            try container.decodeIfPresent(
                String.self,
                forKey:
                    .sourceFilename
            )

        intrinsicWidth =
            try container.decode(
                Int.self,
                forKey:
                    .intrinsicWidth
            )

        intrinsicHeight =
            try container.decode(
                Int.self,
                forKey:
                    .intrinsicHeight
            )

        storageMode =
            try container.decodeIfPresent(
                CoverSmartObjectStorageMode.self,
                forKey:
                    .storageMode
            )
            ?? .embedded

        linkedBookmarkData =
            try container.decodeIfPresent(
                Data.self,
                forKey:
                    .linkedBookmarkData
            )

        linkedLastKnownModificationDate =
            try container.decodeIfPresent(
                Date.self,
                forKey:
                    .linkedLastKnownModificationDate
            )

        linkedLastKnownFileSize =
            try container.decodeIfPresent(
                Int64.self,
                forKey:
                    .linkedLastKnownFileSize
            )
    }

    func encode(
        to encoder: Encoder
    ) throws {
        var container =
            encoder.container(
                keyedBy:
                    CodingKeys.self
            )

        try container.encode(
            sourceKind,
            forKey:
                .sourceKind
        )

        try container.encode(
            sourceData,
            forKey:
                .sourceData
        )

        try container.encodeIfPresent(
            sourceFilename,
            forKey:
                .sourceFilename
        )

        try container.encode(
            intrinsicWidth,
            forKey:
                .intrinsicWidth
        )

        try container.encode(
            intrinsicHeight,
            forKey:
                .intrinsicHeight
        )

        try container.encode(
            storageMode,
            forKey:
                .storageMode
        )

        try container.encodeIfPresent(
            linkedBookmarkData,
            forKey:
                .linkedBookmarkData
        )

        try container.encodeIfPresent(
            linkedLastKnownModificationDate,
            forKey:
                .linkedLastKnownModificationDate
        )

        try container.encodeIfPresent(
            linkedLastKnownFileSize,
            forKey:
                .linkedLastKnownFileSize
        )
    }
}

enum CoverSmartObjectValidation {
    static let maxSourceBytes =
        500_000_000

    static let maxTotalSourceBytes =
        1_000_000_000

    static let maxDimension =
        100_000

    static let maxBookmarkBytes =
        2_000_000

    static func isValid(
        _ object: CoverSmartObject
    ) -> Bool {
        guard !object.sourceData.isEmpty,
              object.sourceData.count
                <= maxSourceBytes,
              object.intrinsicWidth > 0,
              object.intrinsicHeight > 0,
              object.intrinsicWidth
                <= maxDimension,
              object.intrinsicHeight
                <= maxDimension,
              object.sourceFilename.map({
                  !$0.isEmpty
                  && $0.utf8.count <= 4096
              }) ?? true,
              object.linkedLastKnownFileSize.map({
                  $0 >= 0
              }) ?? true
        else {
            return false
        }

        switch object.storageMode {
        case .embedded:
            return object.linkedBookmarkData == nil
                && object.linkedLastKnownModificationDate == nil
                && object.linkedLastKnownFileSize == nil

        case .linked:
            guard let bookmark =
                    object.linkedBookmarkData,
                  !bookmark.isEmpty,
                  bookmark.count
                    <= maxBookmarkBytes
            else {
                return false
            }

            return true
        }
    }
}


enum CoverStrokeCap: String, Codable, Equatable, CaseIterable, Identifiable {
    case butt
    case round
    case square

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum CoverStrokeJoin: String, Codable, Equatable, CaseIterable, Identifiable {
    case miter
    case round
    case bevel

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum CoverFillRule:
    String,
    Codable,
    Equatable,
    CaseIterable,
    Identifiable
{
    case evenOdd
    case nonZero

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .evenOdd:
            return "Even-Odd"

        case .nonZero:
            return "Non-Zero"
        }
    }
}


enum CoverStrokeValidation {
    static let defaultMiterLimit = 10.0
    static let maximumMiterLimit = 1_000.0
    static let maximumDashCount = 64
    static let maximumDashValue = 1_000_000.0

    static func isValid(_ layer: CoverLayer) -> Bool {
        guard layer.strokeWidth.isFinite,
              layer.strokeWidth >= 0
        else {
            return false
        }

        let miterLimit =
            layer.strokeMiterLimit
            ?? defaultMiterLimit

        guard miterLimit.isFinite,
              miterLimit >= 1,
              miterLimit <= maximumMiterLimit
        else {
            return false
        }

        let phase =
            layer.strokeDashPhase
            ?? 0

        guard phase.isFinite,
              abs(phase) <= maximumDashValue
        else {
            return false
        }

        let pattern =
            layer.strokeDashPattern
            ?? []

        guard pattern.count <= maximumDashCount else {
            return false
        }

        return pattern.allSatisfy {
            $0.isFinite
            && $0 > 0
            && $0 <= maximumDashValue
        }
    }
}

enum CoverBlendMode: String, Codable, CaseIterable, Identifiable {
    case normal, multiply, screen, overlay, darken, lighten, colorBurn, colorDodge
    case softLight, hardLight, difference, exclusion, hue, saturation, color, luminosity
    case plusDarker, plusLighter
    var id:String{rawValue}
    var title:String {
        switch self {
        case .colorBurn:"Color Burn";case .colorDodge:"Color Dodge"
        case .softLight:"Soft Light";case .hardLight:"Hard Light"
        case .plusDarker:"Linear Burn";case .plusLighter:"Linear Dodge"
        default:rawValue.capitalized
        }
    }
    var cgBlendMode: CGBlendMode {
        switch self {
        case .normal:.normal;case .multiply:.multiply;case .screen:.screen;case .overlay:.overlay
        case .darken:.darken;case .lighten:.lighten;case .colorBurn:.colorBurn;case .colorDodge:.colorDodge
        case .softLight:.softLight;case .hardLight:.hardLight;case .difference:.difference
        case .exclusion:.exclusion;case .hue:.hue;case .saturation:.saturation;case .color:.color
        case .luminosity:.luminosity;case .plusDarker:.plusDarker;case .plusLighter:.plusLighter
        }
    }
}
enum CoverWarpPreset: String, Codable, CaseIterable, Identifiable { case arch, flag; var id:String{rawValue} }
enum CoverAdjustmentKind: String, Codable, CaseIterable, Identifiable { case brightnessContrast, exposure, levels, curves, hueSaturation, vibrance, temperatureTint, colorBalance, threshold, posterize, gradientMap, channelMixer, selectiveColor, monochrome, invert, gaussianBlur, sharpen; var id:String{rawValue} }
enum CoverFilterKind: String, Codable, CaseIterable, Identifiable { case gaussianBlur, sharpen, noiseReduction, pixelate, sepia, invert, exposure; var id:String{rawValue} }
struct CoverFilter: Codable, Equatable, Identifiable { var id=UUID();var kind:CoverFilterKind;var enabled=true;var amount=1.0 }
struct CoverDropShadow: Codable, Equatable { var colorHex="#000000";var opacity=0.45;var angle=45.0;var distance=0.08;var blur=0.08;var enabled=true }
struct CoverInnerShadow: Codable, Equatable {
    var colorHex = "#000000"
    var opacity = 0.45
    var angle = 45.0
    var distance = 0.025
    var blur = 0.035
    var enabled = true
}

struct CoverStrokeEffect: Codable, Equatable {
    var colorHex = "#000000"
    var opacity = 1.0
    var width = 0.015
    var enabled = true
}

struct CoverColorOverlay: Codable, Equatable {
    var colorHex = "#FFFFFF"
    var opacity = 1.0
    var enabled = true
}

struct CoverGradientStop: Codable, Equatable, Identifiable {
    var id = UUID()
    var colorHex = "#FFFFFF"
    var location = 0.0
    var opacity = 1.0
    var midpoint = 0.5
}

struct CoverGradientOverlay: Codable, Equatable {
    var startHex = "#000000"
    var endHex = "#FFFFFF"
    var opacity = 1.0
    var angle = 0.0
    var enabled = true
}

struct CoverOuterGlow: Codable, Equatable {
    var colorHex = "#FFFFFF"
    var opacity = 0.65
    var size = 0.04
    var enabled = true
}

struct CoverSavedSelection: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var width: Int
    var height: Int
    /// One byte per pixel, row-major. Optional on projects from earlier versions.
    var mask: Data
}

struct CoverRect: Codable, Equatable {
    var x: Double; var y: Double; var width: Double; var height: Double
    init(x: Double = 0, y: Double = 0, width: Double = 1, height: Double = 1) { self.x=x; self.y=y; self.width=width; self.height=height }
}

enum CoverPanelAnchor:
    String,
    Codable,
    CaseIterable,
    Identifiable
{
    /// Explicit canvas anchoring is distinct from a nil anchor.
    ///
    /// nil is retained for legacy projects and means that BOLD Writer may
    /// infer a physical panel from the layer's current frame when geometry
    /// changes. `.canvas` means the user explicitly chose full-wrap canvas
    /// coordinates and automatic panel inference must not occur.
    case canvas
    case back
    case spine
    case front

    var id: String { rawValue }

    var title: String {
        switch self {
        case .canvas:
            "Canvas"
        case .back:
            "Back"
        case .spine:
            "Spine"
        case .front:
            "Front"
        }
    }
}

struct CoverLayer: Codable, Equatable, Identifiable {
    var id = UUID()
    var kind: CoverLayerKind
    var name: String
    var frame: CoverRect
    var visible = true
    var locked = false
    var opacity = 1.0
    var rotation = 0.0
    var imageData: Data? = nil
    var referenceOnly: Bool? = nil
    var referencePageWidth: Double? = nil
    /// Imported PSD typography is measured in pixels at referencePageWidth.
    var psdTextPixelBasis: Bool? = nil
    /// Enables lossless standard-channel re-export while the imported raster stays untransformed.
    var psdRasterPixelBasis: Bool? = nil
    var isReferenceLayer: Bool { kind == .template || referenceOnly == true }
    var smartObject: CoverSmartObject? = nil
    var cropMode: CoverCropMode = .fill
    var cropOffsetX = 0.0
    var cropOffsetY = 0.0
    var flipHorizontal = false
    var flipVertical = false
    var text = ""
    var fontName = "Georgia"
    var fontSize = 36.0
    var bold = false
    var italic = false
    var colorHex = "#202020"
    var alignment: String = "center"
    var lineSpacing = 1.0
    var letterSpacing = 0.0
    var shape: CoverShapeKind = .rectangle
    var fillHex = "#FFFFFF"
    var strokeHex = "#202020"
    var strokeWidth = 1.0
    var strokeCap: CoverStrokeCap? = nil
    var strokeJoin: CoverStrokeJoin? = nil
    var strokeMiterLimit: Double? = nil
    var strokeDashPattern: [Double]? = nil
    var strokeDashPhase: Double? = nil
    var fillRule: CoverFillRule? = nil
    // Optional editor extensions preserve decoding of projects from the original cover checkpoint.
    var blendMode: CoverBlendMode? = nil
    var fillOpacity: Double? = nil
    var positionLocked: Bool? = nil
    var pixelsLocked: Bool? = nil
    var transparencyLocked: Bool? = nil
    var groupID: UUID? = nil
    var linkSetID: UUID? = nil
    var maskData: Data? = nil
    var maskEnabled: Bool? = nil
    var maskOffsetX: Double? = nil
    var maskOffsetY: Double? = nil
    var maskDensity: Double? = nil
    var adjustment: CoverAdjustmentKind? = nil
    var adjustmentValues: [String: Double]? = nil
    var gradientEndHex: String? = nil
    var gradientRadial: Bool? = nil
    var gradientStops: [CoverGradientStop]? = nil
    var gradientAngle: Double? = nil
    var gradientCenterX: Double? = nil
    var gradientCenterY: Double? = nil
    var gradientRadius: Double? = nil
    var gradientReversed: Bool? = nil
    var skewX: Double? = nil
    var skewY: Double? = nil
    var pathPoints: [CoverPathPoint]? = nil
    var pathContours: [[CoverPathPoint]]? = nil
    var pathClosed: Bool? = nil
    var pathContourClosed: [Bool]? = nil
    var cornerRadius: Double? = nil
    var shadowRadius: Double? = nil
    var shadowOpacity: Double? = nil
    var sourceCrop: CoverRect? = nil
    var maskLinked: Bool? = nil
    var perspectiveCorners: [CoverPathPoint]? = nil
    var warpPreset: CoverWarpPreset? = nil
    var warpAmount: Double? = nil
    var filters: [CoverFilter]? = nil
    var dropShadow: CoverDropShadow? = nil
    var innerShadow: CoverInnerShadow? = nil
    var strokeEffect: CoverStrokeEffect? = nil
    var colorOverlay: CoverColorOverlay? = nil
    var gradientOverlay: CoverGradientOverlay? = nil
    var outerGlow: CoverOuterGlow? = nil
    var clippedToLayerID: UUID? = nil
    var linkSourceID: UUID? = nil
    var leading: Double? = nil
    var horizontalScale: Double? = nil
    var verticalScale: Double? = nil
    var baselineShift: Double? = nil
    var underline: Bool? = nil
    var strikethrough: Bool? = nil
    var paragraphIndent: Double? = nil
    var paragraphSpacing: Double? = nil

    // Optional physical-panel metadata keeps legacy projects decodable while
    // allowing finished front / spine / back artwork to follow real book geometry.
    var panelAnchor: CoverPanelAnchor? = nil

    init(kind: CoverLayerKind, name: String, frame: CoverRect = CoverRect()) { self.kind=kind; self.name=name; self.frame=frame }
}

enum CoverTypography {
    static let alignments = [
        "left",
        "center",
        "right",
        "justified"
    ]

    static var fontFamilies: [String] {
        let families =
            NSFontManager
                .shared
                .availableFontFamilies
                .filter {
                    !$0.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
                }

        let unique =
            Array(
                Set(families)
            )

        let sorted =
            unique.sorted {
                $0.localizedCaseInsensitiveCompare(
                    $1
                ) == .orderedAscending
            }

        return sorted.isEmpty
            ? ["Helvetica"]
            : sorted
    }

    static func font(
        for layer: CoverLayer
    ) -> NSFont {
        var font =
            NSFont(
                name: layer.fontName,
                size: layer.fontSize
            )
            ?? NSFont.systemFont(
                ofSize: layer.fontSize
            )

        if layer.bold {
            font =
                NSFontManager.shared.convert(
                    font,
                    toHaveTrait: .boldFontMask
                )
        }

        if layer.italic {
            font =
                NSFontManager.shared.convert(
                    font,
                    toHaveTrait: .italicFontMask
                )
        }

        return font
    }

    static func paragraphStyle(
        for layer: CoverLayer
    ) -> NSParagraphStyle {
        let paragraph =
            NSMutableParagraphStyle()

        switch layer.alignment {
        case "left":
            paragraph.alignment = .left
        case "right":
            paragraph.alignment = .right
        case "justified":
            paragraph.alignment = .justified
        default:
            paragraph.alignment = .center
        }

        paragraph.lineSpacing =
            CGFloat(
                max(
                    0,
                    layer.lineSpacing
                )
            )

        if let leading = layer.leading,
           leading > 0 {
            paragraph.minimumLineHeight =
                CGFloat(leading)

            paragraph.maximumLineHeight =
                CGFloat(leading)
        }

        paragraph.firstLineHeadIndent =
            CGFloat(
                layer.paragraphIndent
                ?? 0
            )

        paragraph.paragraphSpacing =
            CGFloat(
                max(
                    0,
                    layer.paragraphSpacing
                    ?? 0
                )
            )

        return paragraph
    }

    static func attributes(
        for layer: CoverLayer
    ) -> [NSAttributedString.Key: Any] {
        var attributes:
            [NSAttributedString.Key: Any] = [
                .font:
                    font(
                        for: layer
                    ),
                .foregroundColor:
                    NSColor(
                        hex: layer.colorHex
                    ),
                .paragraphStyle:
                    paragraphStyle(
                        for: layer
                    ),
                .kern:
                    layer.letterSpacing
            ]

        if layer.underline == true {
            attributes[
                .underlineStyle
            ] =
                NSUnderlineStyle
                    .single
                    .rawValue
        }

        if layer.strikethrough == true {
            attributes[
                .strikethroughStyle
            ] =
                NSUnderlineStyle
                    .single
                    .rawValue
        }

        let baseline =
            layer.baselineShift
            ?? 0

        if abs(baseline) > 0.0001 {
            attributes[
                .baselineOffset
            ] = baseline
        }

        return attributes
    }
}

enum CoverPathAnchorType: String, Codable, Equatable {
    case corner
    case smooth
    case symmetric
}

struct CoverPathPoint: Codable, Equatable {
    var x: Double
    var y: Double
    var controlInX: Double? = nil
    var controlInY: Double? = nil
    var controlOutX: Double? = nil
    var controlOutY: Double? = nil
    var anchorType: CoverPathAnchorType? = nil
}

enum BookProductionTemplate:
    String,
    Codable,
    CaseIterable,
    Identifiable
{
    case sixByNineWhite =
        "6 × 9 Softcover — White"

    case sixByNineCream =
        "6 × 9 Softcover — Cream"

    case usLetterWhite =
        "US Letter Softcover — White"

    case a4White =
        "A4 Softcover — White"

    case custom =
        "Custom"

    var id: String {
        rawValue
    }

    var paperStockPreset:
        PrintPaperStockPreset?
    {
        switch self {
        case .sixByNineWhite,
             .usLetterWhite,
             .a4White:
            .kdpWhite

        case .sixByNineCream:
            .kdpCream

        case .custom:
            nil
        }
    }

    var productionBinding:
        BookBinding?
    {
        switch self {
        case .sixByNineWhite,
             .sixByNineCream,
             .usLetterWhite,
             .a4White:
            .softcover

        case .custom:
            nil
        }
    }

    var bleedInches:
        Double?
    {
        switch self {
        case .sixByNineWhite,
             .sixByNineCream,
             .usLetterWhite,
             .a4White:
            0.125

        case .custom:
            nil
        }
    }

    var trimWidthInches:
        Double?
    {
        switch self {
        case .sixByNineWhite,
             .sixByNineCream:
            6

        case .usLetterWhite:
            612.0 / 72.0

        case .a4White:
            595.28 / 72.0

        case .custom:
            nil
        }
    }

    var trimHeightInches:
        Double?
    {
        switch self {
        case .sixByNineWhite,
             .sixByNineCream:
            9

        case .usLetterWhite:
            792.0 / 72.0

        case .a4White:
            841.89 / 72.0

        case .custom:
            nil
        }
    }

    func apply(
        to settings:
            inout PageSettings
    ) {
        switch self {
        case .sixByNineWhite,
             .sixByNineCream:
            settings.paper =
                .custom

            settings.customPaperSize =
                CGSize(
                    width:
                        432,
                    height:
                        648
                )

            settings.landscape =
                false

        case .usLetterWhite:
            settings.paper =
                .letter

            settings.customPaperSize =
                nil

            settings.landscape =
                false

        case .a4White:
            settings.paper =
                .a4

            settings.customPaperSize =
                nil

            settings.landscape =
                false

        case .custom:
            break
        }
    }

    func matches(
        _ project:
            CoverProject,
        tolerance:
            Double = 0.0001
    ) -> Bool {
        guard
            self != .custom,
            let trimWidthInches,
            let trimHeightInches,
            let bleedInches,
            let paperStockPreset,
            let productionBinding
        else {
            return false
        }

        let effectivePaperStock:
            PrintPaperStockPreset

        if let stored =
            project.paperStockPreset
        {
            effectivePaperStock =
                stored
        } else if let caliper =
            project.spineCaliperInches
        {
            effectivePaperStock =
                PrintPaperStockPreset
                    .inferred(
                        caliper:
                            caliper
                    )
        } else {
            effectivePaperStock =
                .custom
        }

        return
            abs(
                project.trimWidth
                    - trimWidthInches
            ) <= tolerance
            && abs(
                project.backWidth
                    - trimWidthInches
            ) <= tolerance
            && abs(
                project.trimHeight
                    - trimHeightInches
            ) <= tolerance
            && abs(
                project.bleed
                    - bleedInches
            ) <= tolerance
            && effectivePaperStock
                == paperStockPreset
            && (
                project.productionBinding
                ?? .softcover
            ) == productionBinding
    }

    static func inferred(
        from project:
            CoverProject
    ) -> Self {
        if project.productionTemplate
            == .custom
        {
            return .custom
        }

        if let stored =
            project.productionTemplate,
           stored.matches(
                project
           )
        {
            return stored
        }

        for candidate in [
            Self.sixByNineWhite,
            .sixByNineCream,
            .usLetterWhite,
            .a4White
        ] {
            if candidate.matches(
                project
            ) {
                return candidate
            }
        }

        return .custom
    }
}

/// Measurements read from a KDP hardcover PDF, in inches. Optional on old documents.
/// The printed case spine includes the boards; it is not the paper-stack depth.
struct KDPHardcoverLayout: Codable, Equatable {
    var canvasWidth: Double
    var canvasHeight: Double
    var trimWidth: Double
    var trimHeight: Double
    var spineWidth: Double
    var pageCount: Int

    var boardWidth: Double { trimWidth + 5 / 25.4 }
    var boardHeight: Double { trimHeight + 6 / 25.4 }
    var wrapX: Double { (canvasWidth - 2 * boardWidth - spineWidth) / 2 }
    var wrapY: Double { (canvasHeight - boardHeight) / 2 }

    func matches(_ project: CoverProject) -> Bool {
        project.type == .printFullWrap && project.productionBinding == .hardcover
        && project.canvasWidth == canvasWidth && project.canvasHeight == canvasHeight
        && project.trimWidth == trimWidth && project.backWidth == trimWidth
        && project.trimHeight == trimHeight && project.spineWidth == spineWidth
        && [canvasWidth, canvasHeight, trimWidth, trimHeight, spineWidth].allSatisfy { $0.isFinite && $0 > 0 }
        && abs(wrapX - 15 / 25.4) < 0.01 && abs(wrapY - 15 / 25.4) < 0.01
        && (76...550).contains(pageCount)
    }
}

struct CoverProject: Codable, Equatable, Identifiable {
    /// Persisted disclosure of PSD metadata the cover model could not represent.
    var psdImportWarnings: [String]? = nil
    var id = UUID()
    var name: String
    var type: CoverProjectType
    var canvasWidth: Double
    var canvasHeight: Double
    var trimWidth: Double
    var trimHeight: Double
    var backWidth: Double
    var spineWidth: Double
    var bleed: Double
    var spinePageCount: Int? = nil
    var spineCaliperInches: Double? = nil

    // Optional production metadata preserves legacy CoverProject payloads.
    var paperStockPreset: PrintPaperStockPreset? = nil
    var productionBinding: BookBinding? = nil
    var productionTemplate: BookProductionTemplate? = nil
    var kdpHardcoverLayout: KDPHardcoverLayout? = nil

    var activeKDPHardcoverLayout: KDPHardcoverLayout? {
        kdpHardcoverLayout.flatMap { $0.matches(self) ? $0 : nil }
    }

    var dpi: Double = 300
    /// Integer raster bounds used by print exports and every dimension readout.
    var rasterPixelSize: CGSize {
        CGSize(width: ceil(canvasWidth * dpi), height: ceil(canvasHeight * dpi))
    }
    var guidesVisible = true
    var gridVisible = false
    var backgroundHex = "#FFFFFF"
    var layers: [CoverLayer] = []
    var templateLocked = true
    var savedSelections: [CoverSavedSelection]? = nil
    /// The active marquee is editor state, but keeping it in the project lets
    /// cover-level undo/redo restore selection operations alongside layer edits.
    /// Optional fields preserve decoding of earlier native cover documents.
    var editorActiveSelectionMask: Data? = nil
    var editorActiveSelectionLayerID: UUID? = nil
    var editorDismissedSelectionMask: Data? = nil
    var editorDismissedSelectionLayerID: UUID? = nil
    var foregroundHex: String? = nil
    var backgroundColorHex: String? = nil
    var userGuidesX: [Double]? = nil
    var userGuidesY: [Double]? = nil
    var guidesLocked: Bool? = nil
    var snapEnabled: Bool? = nil
    var unit: String? = nil
    var gridSpacingInches: Double? = nil
    var gridSubdivisions: Int? = nil
    var pixelGridVisible: Bool? = nil
    var snapGuides: Bool? = nil
    var snapGrid: Bool? = nil
    var snapBounds: Bool? = nil
    var snapLayers: Bool? = nil
    var snapCanvasEdges: Bool? = nil
    var snapCanvasCenter: Bool? = nil
    var snapFrontCover: Bool? = nil
    var snapBackCover: Bool? = nil
    var snapSpine: Bool? = nil
    var snapFrontCoverCenter: Bool? = nil
    var snapBackCoverCenter: Bool? = nil
    var snapSpineCenter: Bool? = nil
    var snapTrim: Bool? = nil
    var snapBleed: Bool? = nil
    var snapSafeZone: Bool? = nil
    var snapLayerEdges: Bool? = nil
    var snapLayerCenters: Bool? = nil

    init(type: CoverProjectType = .ebookFront, width: Double = 6, height: Double = 9) {
        self.type=type; self.name=type.displayName
        self.canvasWidth=width; self.canvasHeight=height
        self.trimWidth=width; self.trimHeight=height; self.backWidth=width; self.spineWidth=0; self.bleed=0
    }

    static func validate(_ projects:[CoverProject]) throws {
        guard projects.count <= 8 else { throw WriterError.message("The document contains too many cover projects.") }
        var ids=Set<UUID>(); var totalImageBytes=0; var totalSmartObjectBytes=0
        for project in projects {
            let sizes=[project.canvasWidth,project.canvasHeight,project.trimWidth,project.trimHeight,project.backWidth,project.spineWidth,project.bleed,project.dpi,project.gridSpacingInches ?? 1]
            guard ids.insert(project.id).inserted, sizes.allSatisfy({$0.isFinite}), project.spinePageCount.map({$0>0}) ?? true, project.spineCaliperInches.map({$0.isFinite && $0>0}) ?? true, project.gridSpacingInches.map({$0>0}) ?? true, project.gridSubdivisions.map({(1...32).contains($0)}) ?? true, project.canvasWidth > 0, project.canvasHeight > 0, project.canvasWidth <= 100, project.canvasHeight <= 100, project.trimWidth > 0, project.trimHeight > 0, project.backWidth > 0, project.spineWidth >= 0, project.bleed >= 0, (1...2400).contains(project.dpi), project.layers.count <= 500 else { throw WriterError.message("The document contains invalid cover project metadata.") }
            var layerIDs=Set<UUID>()
            for layer in project.layers {
                let numbers=[layer.frame.x,layer.frame.y,layer.frame.width,layer.frame.height,layer.opacity,layer.rotation,layer.fontSize,layer.lineSpacing,layer.letterSpacing,layer.strokeWidth,layer.cropOffsetX,layer.cropOffsetY,layer.skewX ?? 0,layer.skewY ?? 0,layer.fillOpacity ?? 1,layer.shadowRadius ?? 0,layer.shadowOpacity ?? 0,layer.sourceCrop?.x ?? 0,layer.sourceCrop?.y ?? 0,layer.sourceCrop?.width ?? 0,layer.sourceCrop?.height ?? 0,layer.dropShadow?.opacity ?? 0,layer.dropShadow?.angle ?? 0,layer.dropShadow?.distance ?? 0,layer.dropShadow?.blur ?? 0,layer.innerShadow?.opacity ?? 0,layer.innerShadow?.angle ?? 0,layer.innerShadow?.distance ?? 0,layer.innerShadow?.blur ?? 0,layer.strokeEffect?.opacity ?? 0,layer.strokeEffect?.width ?? 0,layer.colorOverlay?.opacity ?? 0,layer.gradientOverlay?.opacity ?? 0,layer.gradientOverlay?.angle ?? 0,layer.outerGlow?.opacity ?? 0,layer.outerGlow?.size ?? 0,layer.leading ?? 0,layer.horizontalScale ?? 1,layer.verticalScale ?? 1,layer.baselineShift ?? 0,layer.paragraphIndent ?? 0,layer.paragraphSpacing ?? 0,layer.maskOffsetX ?? 0,layer.maskOffsetY ?? 0,layer.maskDensity ?? 1,layer.warpAmount ?? 0]
                let effectOpacities=[
                    layer.dropShadow?.opacity,
                    layer.innerShadow?.opacity,
                    layer.strokeEffect?.opacity,
                    layer.colorOverlay?.opacity,
                    layer.gradientOverlay?.opacity,
                    layer.outerGlow?.opacity
                ].compactMap{$0}
                let effectSizes=[
                    layer.dropShadow?.distance,
                    layer.dropShadow?.blur,
                    layer.innerShadow?.distance,
                    layer.innerShadow?.blur,
                    layer.strokeEffect?.width,
                    layer.outerGlow?.size
                ].compactMap{$0}

                guard CoverStrokeValidation.isValid(layer)
                else {
                    throw WriterError.message(
                        "A vector stroke geometry value is outside its supported range."
                    )
                }

                guard (0...1).contains(layer.maskDensity ?? 1),
                      abs(layer.maskOffsetX ?? 0)<=1,
                      abs(layer.maskOffsetY ?? 0)<=1,
                      abs(layer.warpAmount ?? 0)<=1,
                      effectOpacities.allSatisfy({(0...1).contains($0)}),
                      effectSizes.allSatisfy({$0>=0 && $0<=1})
                else {
                    throw WriterError.message(
                        "A cover mask, warp, or layer effect value is outside its supported range."
                    )
                }
                guard layerIDs.insert(layer.id).inserted, numbers.allSatisfy({$0.isFinite}), layer.frame.width >= 0, layer.frame.height >= 0, (0...1).contains(layer.opacity), abs(layer.rotation) <= 36000, layer.referencePageWidth.map({$0.isFinite && $0 > 0 && $0 <= 72000}) ?? true, layer.fontSize > 0, layer.fontSize <= 2000, layer.fontName.utf8.count <= 256, CoverTypography.alignments.contains(layer.alignment), layer.lineSpacing >= 0, layer.lineSpacing <= 2000, abs(layer.letterSpacing) <= 500, layer.leading.map({$0 >= 0 && $0 <= 4000}) ?? true, layer.horizontalScale.map({$0 >= 0.1 && $0 <= 10}) ?? true, layer.verticalScale.map({$0 >= 0.1 && $0 <= 10}) ?? true, layer.baselineShift.map({abs($0) <= 4000}) ?? true, layer.paragraphIndent.map({abs($0) <= 10000}) ?? true, layer.paragraphSpacing.map({$0 >= 0 && $0 <= 10000}) ?? true, layer.text.utf8.count <= 1_000_000, layer.name.utf8.count <= 4096 else { throw WriterError.message("The document contains invalid cover layer metadata.") }
                if let adjustmentValues=layer.adjustmentValues {
                    guard adjustmentValues.count <= 256,
                          adjustmentValues.allSatisfy({
                              $0.key.utf8.count <= 128
                              && $0.value.isFinite
                          })
                    else {
                        throw WriterError.message(
                            "The document contains invalid cover adjustment metadata."
                        )
                    }
                }
                if let data=layer.imageData { totalImageBytes += data.count; guard totalImageBytes <= 1_000_000_000 else { throw WriterError.message("Embedded cover artwork exceeds the document size limit.") }; guard NSImage(data:data) != nil else { throw WriterError.message("A cover image layer contains invalid image data.") } }

                if layer.kind == .smartObject {
                    guard let smartObject =
                            layer.smartObject,
                          CoverSmartObjectValidation
                            .isValid(
                                smartObject
                            ),
                          layer.imageData != nil
                    else {
                        throw WriterError.message(
                            "A Smart Object contains invalid embedded source data."
                        )
                    }

                    totalSmartObjectBytes +=
                        smartObject
                            .sourceData
                            .count

                    guard totalSmartObjectBytes
                            <= CoverSmartObjectValidation
                                .maxTotalSourceBytes
                    else {
                        throw WriterError.message(
                            "Embedded Smart Object sources exceed the document size limit."
                        )
                    }
                } else if layer.smartObject != nil {
                    throw WriterError.message(
                        "Only Smart Object layers may contain Smart Object source data."
                    )
                }

                if let contours=layer.pathContours {
                    let totalAnchors=contours.reduce(0){$0+$1.count}

                    guard !contours.isEmpty,
                          contours.count <= 256,
                          totalAnchors <= 100_000,
                          contours.allSatisfy({
                              !$0.isEmpty &&
                              $0.count <= 20_000 &&
                              $0.allSatisfy({
                                  $0.x.isFinite &&
                                  $0.y.isFinite &&
                                  ($0.controlInX?.isFinite ?? true) &&
                                  ($0.controlInY?.isFinite ?? true) &&
                                  ($0.controlOutX?.isFinite ?? true) &&
                                  ($0.controlOutY?.isFinite ?? true)
                              })
                          })
                    else {
                        throw WriterError.message(
                            "A cover vector path contains invalid compound contour metadata."
                        )
                    }
                }
                if let contourClosures=layer.pathContourClosed {
                    let contourCount =
                        layer.pathContours?.count
                        ?? (
                            (layer.pathPoints?.isEmpty == false)
                            ? 1
                            : 0
                        )

                    guard contourClosures.count <= 256,
                          contourClosures.count == contourCount
                    else {
                        throw WriterError.message(
                            "A cover vector path contains invalid contour closure metadata."
                        )
                    }
                }


                if let stops=layer.gradientStops {
                    var stopIDs=Set<UUID>()
                    guard (2...64).contains(stops.count),
                          stops.allSatisfy({
                              stopIDs.insert($0.id).inserted &&
                              $0.location.isFinite &&
                              (0...1).contains($0.location) &&
                              $0.opacity.isFinite &&
                              (0...1).contains($0.opacity) &&
                              $0.midpoint.isFinite &&
                              (0.05...0.95).contains($0.midpoint) &&
                              $0.colorHex.utf8.count <= 64
                          })
                    else {
                        throw WriterError.message("A cover gradient contains invalid stop metadata.")
                    }
                }

                let gradientGeometry=[
                    layer.gradientAngle,
                    layer.gradientCenterX,
                    layer.gradientCenterY,
                    layer.gradientRadius
                ].compactMap{$0}

                guard gradientGeometry.allSatisfy({$0.isFinite}),
                      layer.gradientCenterX.map({(0...1).contains($0)}) ?? true,
                      layer.gradientCenterY.map({(0...1).contains($0)}) ?? true,
                      layer.gradientRadius.map({(0.01...4).contains($0)}) ?? true,
                      layer.gradientAngle.map({abs($0)<=36000}) ?? true
                else {
                    throw WriterError.message("A cover gradient geometry value is outside its supported range.")
                }

                if let mask=layer.maskData { guard mask.count <= 100_000_000 else { throw WriterError.message("A cover layer mask exceeds the document size limit.") } }
            }
            if let selections=project.savedSelections { guard selections.count <= 100, selections.allSatisfy({$0.name.utf8.count <= 1024 && $0.width > 0 && $0.height > 0 && $0.width <= 20_000 && $0.height <= 20_000 && $0.mask.count == $0.width * $0.height}) else { throw WriterError.message("The document contains invalid saved cover selections.") } }
            let editorSelections = [
                project.editorActiveSelectionMask,
                project.editorDismissedSelectionMask
            ].compactMap { $0 }
            guard editorSelections.allSatisfy({ $0.count <= 100_000_000 }) else {
                throw WriterError.message("An active cover selection exceeds the document size limit.")
            }
        }
    }

    @discardableResult mutating func duplicateLayer(_ layerID:UUID) -> UUID? { guard var layer=layers.first(where:{$0.id==layerID}) else{return nil};layer.id=UUID();layer.name += " Copy";layer.frame.x=min(1-layer.frame.width,layer.frame.x+0.02);layer.frame.y=min(1-layer.frame.height,layer.frame.y+0.02);layers.append(layer);return layer.id }
    mutating func deleteLayer(_ layerID:UUID) { layers.removeAll{$0.id==layerID} }
    mutating func moveLayer(_ layerID:UUID,by delta:Int) { guard let index=layers.firstIndex(where:{$0.id==layerID}) else{return};layers.swapAt(index,max(0,min(layers.count-1,index+delta))) }
}

struct CoverDimensions: Equatable {
    var totalWidthInches: Double
    var totalHeightInches: Double
    var totalWidthMillimeters: Double { totalWidthInches * 25.4 }
    var totalHeightMillimeters: Double { totalHeightInches * 25.4 }
    func pixels(dpi: Double) -> (width: Int, height: Int) { (Int((totalWidthInches*dpi).rounded()), Int((totalHeightInches*dpi).rounded())) }
}

struct CoverWrapGeometry: Equatable {
    let physicalWidth: Double
    let physicalHeight: Double
    let spineWidth: Double
    let bleed: Double
    let back: CoverRect
    let spine: CoverRect
    let front: CoverRect
    let backTrim: CoverRect
    let spineTrim: CoverRect
    let frontTrim: CoverRect
    let backSafeArea: CoverRect
    let spineSafeArea: CoverRect
    let frontSafeArea: CoverRect
    let safeArea: CoverRect

    init(project: CoverProject) {
        physicalWidth = project.canvasWidth; physicalHeight = project.canvasHeight
        spineWidth = project.spineWidth; bleed = project.bleed
        let w = max(project.canvasWidth, 0.000001), h = max(project.canvasHeight, 0.000001)
        if let layout = project.activeKDPHardcoverLayout {
            let x = layout.wrapX, y = layout.wrapY
            let bw = layout.boardWidth, bh = layout.boardHeight, sw = layout.spineWidth
            func rect(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> CoverRect {
                CoverRect(x: x/w, y: y/h, width: width/w, height: height/h)
            }
            back = rect(0, 0, x+bw, h)
            spine = rect(x+bw, 0, sw, h)
            front = rect(x+bw+sw, 0, bw+x, h)
            backTrim = rect(x, y, bw, bh)
            spineTrim = rect(x+bw, y, sw, bh)
            frontTrim = rect(x+bw+sw, y, bw, bh)
            // Hinges belong to the case, but are not safe for text or logos.
            let hinge = 10 / 25.4, margin = 0.125
            backSafeArea = rect(x+margin, y+margin, bw-hinge-margin, bh-2*margin)
            spineSafeArea = rect(x+bw+0.0625, y+margin, max(0, sw-0.125), bh-2*margin)
            frontSafeArea = rect(x+bw+sw+hinge, y+margin, bw-hinge-margin, bh-2*margin)
            safeArea = frontSafeArea
            return
        }
        let b = project.bleed, backW = project.backWidth, sw = project.spineWidth, frontW = project.trimWidth
        back = CoverRect(x: 0, y: 0, width: (b + backW) / w, height: 1)
        spine = CoverRect(x: (b + backW) / w, y: 0, width: sw / w, height: 1)
        front = CoverRect(x: (b + backW + sw) / w, y: 0, width: (frontW + b) / w, height: 1)
        backTrim = CoverRect(x: b/w, y: b/h, width: backW/w, height: project.trimHeight/h)
        spineTrim = CoverRect(x: (b+backW)/w, y: b/h, width: sw/w, height: project.trimHeight/h)
        frontTrim = CoverRect(x: (b+backW+sw)/w, y: b/h, width: frontW/w, height: project.trimHeight/h)
        func normalizedSafe(_ rect:CoverRect)->CoverRect { let safe=CoverCalculator.safeRect(trim:rect);return CoverRect(x:safe.x/w,y:safe.y/h,width:safe.width/w,height:safe.height/h) }
        backSafeArea=normalizedSafe(CoverRect(x:b,y:b,width:backW,height:project.trimHeight))
        spineSafeArea=normalizedSafe(CoverRect(x:b+backW,y:b,width:sw,height:project.trimHeight))
        frontSafeArea=normalizedSafe(CoverRect(x:b+backW+sw,y:b,width:frontW,height:project.trimHeight))
        safeArea=frontSafeArea
    }
}

enum CoverResolutionQuality: String, Equatable {
    case good
    case marginal
    case low
}

enum CoverCalculator {
    static func spineWidth(pageCount: Int, caliperInches: Double) throws -> Double {
        guard pageCount > 0, caliperInches.isFinite, caliperInches > 0 else { throw WriterError.message("Enter a positive page count and paper caliper.") }
        return Double(pageCount) * caliperInches
    }
    static func fullWrap(trimWidth: Double, trimHeight: Double, spineWidth: Double, bleed: Double) throws -> CoverDimensions {
        guard [trimWidth, trimHeight, spineWidth, bleed].allSatisfy({ $0.isFinite && $0 >= 0 }), trimWidth > 0, trimHeight > 0 else { throw WriterError.message("Cover dimensions must be positive finite measurements.") }
        return CoverDimensions(totalWidthInches: trimWidth*2 + spineWidth + bleed*2, totalHeightInches: trimHeight + bleed*2)
    }
    static func fullWrap(backWidth: Double, frontWidth: Double, trimHeight: Double, spineWidth: Double, bleed: Double) throws -> CoverDimensions {
        guard [backWidth,frontWidth,trimHeight,spineWidth,bleed].allSatisfy({$0.isFinite && $0>=0}),backWidth>0,frontWidth>0,trimHeight>0 else { throw WriterError.message("Enter valid front, back, spine, height, and bleed dimensions.") }
        return CoverDimensions(totalWidthInches:backWidth+spineWidth+frontWidth+2*bleed,totalHeightInches:trimHeight+2*bleed)
    }
    static func safeRect(trim: CoverRect, fraction: Double = 0.05) -> CoverRect {
        let insetX=trim.width*fraction, insetY=trim.height*fraction
        return CoverRect(x: trim.x+insetX,y: trim.y+insetY,width: max(0,trim.width-2*insetX),height: max(0,trim.height-2*insetY))
    }
    static func resolutionQuality(
        effectiveDPI: Double,
        targetDPI: Double = 300
    ) -> CoverResolutionQuality {
        guard
            effectiveDPI.isFinite,
            targetDPI.isFinite,
            effectiveDPI > 0,
            targetDPI > 0
        else {
            return .low
        }

        if effectiveDPI >= targetDPI {
            return .good
        }

        if effectiveDPI >= targetDPI * 0.70 {
            return .marginal
        }

        return .low
    }

    static func resolutionStatus(
        effectiveDPI: Double,
        targetDPI: Double = 300
    ) -> String {
        resolutionQuality(
            effectiveDPI:
                effectiveDPI,
            targetDPI:
                targetDPI
        )
        .rawValue
        + " resolution"
    }

    static func resolutionStatus(
        pixelWidth: Int,
        pixelHeight: Int,
        displayedWidthInches: Double,
        displayedHeightInches: Double,
        targetDPI: Double = 300
    ) -> String {
        guard
            pixelWidth > 0,
            pixelHeight > 0,
            displayedWidthInches > 0,
            displayedHeightInches > 0
        else {
            return resolutionStatus(
                effectiveDPI:
                    0,
                targetDPI:
                    targetDPI
            )
        }

        let effectiveDPI =
            min(
                Double(
                    pixelWidth
                )
                    / displayedWidthInches,
                Double(
                    pixelHeight
                )
                    / displayedHeightInches
            )

        return resolutionStatus(
            effectiveDPI:
                effectiveDPI,
            targetDPI:
                targetDPI
        )
    }

    static func kdpWhitePaperSpineWidth(pageCount: Int) throws -> Double {
        try spineWidth(pageCount: pageCount, caliperInches: PrintCoverSpecification.kdpBlackAndWhiteWhitePaperCaliper)
    }

    static func kdpCreamPaperSpineWidth(pageCount: Int) throws -> Double {
        try spineWidth(pageCount: pageCount, caliperInches: PrintCoverSpecification.kdpBlackAndWhiteCreamPaperCaliper)
    }

    static func inferredPageCount(spineWidth:Double,caliperInches:Double)->Int {
        guard spineWidth.isFinite,spineWidth>0,caliperInches.isFinite,caliperInches>0 else{return 240}
        return max(1,Int((spineWidth/caliperInches).rounded()))
    }

    static func panelRegion(
        _ anchor: CoverPanelAnchor,
        geometry: CoverWrapGeometry
    ) -> CoverRect {
        switch anchor {
        case .canvas:
            CoverRect(
                x: 0,
                y: 0,
                width: 1,
                height: 1
            )
        case .back:
            geometry.back
        case .spine:
            geometry.spine
        case .front:
            geometry.front
        }
    }

    static func inferredPanelAnchor(
        for frame: CoverRect,
        in project: CoverProject
    ) -> CoverPanelAnchor? {
        guard
            project.type == .printFullWrap
        else {
            return nil
        }

        let geometry =
            CoverWrapGeometry(
                project:
                    project
            )

        let epsilon =
            0.0000001

        func contains(
            _ region: CoverRect,
            _ candidate: CoverRect
        ) -> Bool {
            guard
                region.width > epsilon,
                region.height > epsilon,
                candidate.width >= 0,
                candidate.height >= 0
            else {
                return false
            }

            return
                candidate.x
                    >= region.x - epsilon
                && candidate.y
                    >= region.y - epsilon
                && candidate.x
                    + candidate.width
                    <= region.x
                        + region.width
                        + epsilon
                && candidate.y
                    + candidate.height
                    <= region.y
                        + region.height
                        + epsilon
        }

        for anchor in [
            CoverPanelAnchor.spine,
            .back,
            .front
        ] {
            if contains(
                panelRegion(
                    anchor,
                    geometry:
                        geometry
                ),
                frame
            ) {
                return anchor
            }
        }

        return nil
    }

    static func remap(
        _ frame: CoverRect,
        from oldRegion: CoverRect,
        to newRegion: CoverRect
    ) -> CoverRect? {
        guard
            oldRegion.width > 0.0000001,
            oldRegion.height > 0.0000001,
            newRegion.width > 0.0000001,
            newRegion.height > 0.0000001
        else {
            return nil
        }

        let localX =
            (
                frame.x
                - oldRegion.x
            )
            / oldRegion.width

        let localY =
            (
                frame.y
                - oldRegion.y
            )
            / oldRegion.height

        let localWidth =
            frame.width
            / oldRegion.width

        let localHeight =
            frame.height
            / oldRegion.height

        return CoverRect(
            x:
                newRegion.x
                + localX
                    * newRegion.width,
            y:
                newRegion.y
                + localY
                    * newRegion.height,
            width:
                localWidth
                * newRegion.width,
            height:
                localHeight
                * newRegion.height
        )
    }

    static func reanchoredLayers(
        from oldProject: CoverProject,
        to newProject: CoverProject
    ) -> [CoverLayer] {
        guard
            oldProject.type == .printFullWrap,
            newProject.type == .printFullWrap
        else {
            return newProject.layers
        }

        let oldGeometry =
            CoverWrapGeometry(
                project:
                    oldProject
            )

        let newGeometry =
            CoverWrapGeometry(
                project:
                    newProject
            )

        return newProject.layers.map {
            source in

            guard
                !source.isReferenceLayer,
                source.kind != .group,
                source.kind != .adjustment
            else {
                return source
            }

            let anchor =
                source.panelAnchor
                ?? inferredPanelAnchor(
                    for:
                        source.frame,
                    in:
                        oldProject
                )

            guard let anchor else {
                return source
            }

            let oldRegion =
                panelRegion(
                    anchor,
                    geometry:
                        oldGeometry
                )

            let newRegion =
                panelRegion(
                    anchor,
                    geometry:
                        newGeometry
                )

            guard
                let frame =
                    remap(
                        source.frame,
                        from:
                            oldRegion,
                        to:
                            newRegion
                    )
            else {
                return source
            }

            var layer =
                source

            layer.frame =
                frame

            layer.panelAnchor =
                anchor

            return layer
        }
    }

    static func placement(_ layer: CoverLayer, in project: CoverProject, region: CoverRect, fill: Bool) -> CoverLayer {
        var placed = layer
        guard let data = layer.imageData, let image = NSImage(data: data), image.size.width > 0, image.size.height > 0 else { return placed }
        guard region.width > 0,region.height > 0,project.canvasWidth > 0,project.canvasHeight > 0 else{return placed}
        // The layer frame defines the clipping viewport. The established renderer
        // implements Fit/Fill within it, so keeping the frame on the physical
        // region prevents large Fill artwork from spilling into adjacent panels.
        placed.frame = region
        placed.cropMode = fill ? .fill : .fit
        placed.sourceCrop = nil; placed.cropOffsetX = 0; placed.cropOffsetY = 0
        placed.panelAnchor =
            inferredPanelAnchor(
                for:
                    region,
                in:
                    project
            )
        return placed
    }
}

enum CoverArtwork {
    // Reuse immutable source images across opacity, placement and Undo/Redo
    // renders. The full-wrap cache remains responsible for composed artwork.
    private static let sourceImages: NSCache<NSData, NSImage> = {
        let cache = NSCache<NSData, NSImage>()
        cache.countLimit = 8
        cache.totalCostLimit = 512 * 1024 * 1024
        return cache
    }()

    static func sourceImage(data: Data) -> NSImage? {
        let key = data as NSData
        if Thread.isMainThread, let cached = sourceImages.object(forKey:key) { return cached }
        // Decode the complete raster before returning it. NSImage(data:) keeps
        // an ImageIO provider that can fault much later during a canvas redraw;
        // holding the Data alive avoids dangling storage but does not prevent
        // the provider failure observed after repeated 3D texture rendering.
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString:Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0,
              let cgImage = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [kCGImageSourceCreateThumbnailFromImageAlways: true,
                 kCGImageSourceCreateThumbnailWithTransform: true,
                 kCGImageSourceShouldCache: true,
                 kCGImageSourceShouldCacheImmediately: true,
                 kCGImageSourceThumbnailMaxPixelSize: max(width, height)] as CFDictionary
              ),
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete else { return nil }
        let image = NSImage(cgImage:cgImage, size:NSSize(width:cgImage.width, height:cgImage.height))
        if Thread.isMainThread {
            let (pixels,overflow) = cgImage.width.multipliedReportingOverflow(by:cgImage.height)
            let bytesPerPixel = cgImage.bitsPerPixel > 32 ? 8 : 4
            let (cost,costOverflow) = pixels.multipliedReportingOverflow(by:bytesPerPixel)
            if !overflow, !costOverflow, cost > 0, cost <= sourceImages.totalCostLimit {
                sourceImages.setObject(image,forKey:key,cost:cost)
            }
        }
        return image
    }

    static func importedTemplate(data: Data, filename: String, widthInches: Double? = nil, heightInches: Double? = nil) throws -> CoverLayer {
        let bytes: Data
        let width: Double, height: Double
        if filename.lowercased().hasSuffix(".pdf")
            || data.starts(
                with:
                    Data(
                        "%PDF".utf8
                    )
            )
        {
            guard let pdf=PDFDocument(data:data), !pdf.isLocked, let page=pdf.page(at:0) else {
                throw WriterError.message("The PDF cover template has no readable first page or is password protected.")
            }
            let bounds=page.bounds(for:.mediaBox)
            guard bounds.width.isFinite, bounds.height.isFinite, bounds.width>0, bounds.height>0,
                  bounds.width<=7200, bounds.height<=7200 else {
                throw WriterError.message("The PDF template page has invalid dimensions.")
            }
            // PDFKit handles page rotation and media-box origins. Rasterize the established
            // first-page reference format, retaining its physical dimensions for placement.
            let rotated=abs(page.rotation % 180) == 90
            width=(rotated ? bounds.height : bounds.width)/72
            height=(rotated ? bounds.width : bounds.height)/72
            let resolution=min(300,4096/max(width,height))
            let image=page.thumbnail(of:NSSize(width:width*resolution,height:height*resolution),for:.mediaBox)
            guard let tiff=image.tiffRepresentation, let bitmap=NSBitmapImageRep(data:tiff),
                  let png=bitmap.representation(using:.png,properties:[:]) else {
                throw WriterError.message("The PDF template could not be rendered.")
            }
            bytes=png
        } else {
            let raster=try decodedRaster(data)
            bytes=raster.data; width=Double(raster.width)/300; height=Double(raster.height)/300
        }
        var layer=CoverLayer(kind:.template,name:filename,frame:CoverRect(x:0,y:0,width:widthInches ?? width,height:heightInches ?? height))
        layer.imageData=bytes; layer.locked=true; layer.opacity=0.45
        return layer
    }

    static func imageLayer(data: Data, filename: String, frame: CoverRect = CoverRect()) throws -> CoverLayer {
        let bytes: Data

        if filename.lowercased().hasSuffix(".pdf")
            || data.starts(
                with:
                    Data(
                        "%PDF".utf8
                    )
            )
        {
            // Cover Creator already has a verified high-resolution PDF
            // rasterization path for template layers. Reuse that exact path
            // when a PDF is placed as ordinary cover artwork instead of
            // incorrectly sending PDF bytes into the raster-only decoder.
            let rasterizedPDF =
                try importedTemplate(
                    data:
                        data,
                    filename:
                        filename.lowercased().hasSuffix(".pdf")
                        ? filename
                        : filename + ".pdf"
                )

            guard
                let rasterizedData =
                    rasterizedPDF.imageData
            else {
                throw WriterError.message(
                    "The PDF cover artwork could not be rendered."
                )
            }

            bytes =
                rasterizedData
        } else {
            let decoded =
                try decodedRaster(
                    data
                )

            bytes =
                decoded.data
        }

        var layer =
            CoverLayer(
                kind:
                    .image,
                name:
                    filename,
                frame:
                    frame
            )

        layer.imageData =
            bytes

        return layer
    }

    static func smartObjectSourceKind(
        data: Data,
        filename: String
    ) -> CoverSmartObjectSourceKind {
        if data.starts(
            with:
                Data(
                    "%PDF".utf8
                )
        ) {
            return .pdf
        }

        if data.starts(
            with:
                Data(
                    "8BPS".utf8
                )
        ) {
            return .psd
        }

        if let prefix =
            String(
                data:
                    data.prefix(
                        8192
                    ),
                encoding:
                    .utf8
            )?
            .lowercased(),
           prefix.contains(
                "<svg"
           )
        {
            return .svg
        }

        return .rasterImage
    }

    static func smartObjectPreview(
        data: Data,
        filename: String
    ) throws -> (
        data: Data,
        width: Int,
        height: Int,
        sourceKind:
            CoverSmartObjectSourceKind
    ) {
        let sourceKind =
            smartObjectSourceKind(
                data:
                    data,
                filename:
                    filename
            )

        switch sourceKind {
        case .rasterImage,
             .psd:
            let decoded =
                try decodedRaster(
                    data
                )

            return (
                decoded.data,
                decoded.width,
                decoded.height,
                sourceKind
            )

        case .pdf:
            guard let pdf =
                    PDFDocument(
                        data:
                            data
                    ),
                  !pdf.isLocked,
                  let page =
                    pdf.page(
                        at:
                            0
                    )
            else {
                throw WriterError.message(
                    "The embedded PDF has no readable first page or is password protected."
                )
            }

            let bounds =
                page.bounds(
                    for:
                        .mediaBox
                )

            guard bounds.width.isFinite,
                  bounds.height.isFinite,
                  bounds.width > 0,
                  bounds.height > 0,
                  bounds.width <= 72_000,
                  bounds.height <= 72_000
            else {
                throw WriterError.message(
                    "The embedded PDF has invalid page dimensions."
                )
            }

            let longest =
                max(
                    bounds.width,
                    bounds.height
                )

            let previewScale =
                min(
                    4,
                    4096
                    / max(
                        1,
                        longest
                    )
                )

            let target =
                NSSize(
                    width:
                        max(
                            1,
                            bounds.width
                            * previewScale
                        ),
                    height:
                        max(
                            1,
                            bounds.height
                            * previewScale
                        )
                )

            let image =
                page.thumbnail(
                    of:
                        target,
                    for:
                        .mediaBox
                )

            guard let tiff =
                    image.tiffRepresentation,
                  let bitmap =
                    NSBitmapImageRep(
                        data:
                            tiff
                    ),
                  bitmap.pixelsWide > 0,
                  bitmap.pixelsHigh > 0,
                  let png =
                    bitmap.representation(
                        using:
                            .png,
                        properties:
                            [:]
                    )
            else {
                throw WriterError.message(
                    "The embedded PDF could not be rendered."
                )
            }

            return (
                png,
                bitmap.pixelsWide,
                bitmap.pixelsHigh,
                sourceKind
            )

        case .svg:
            guard let image =
                    NSImage(
                        data:
                            data
                    ),
                  image.size.width.isFinite,
                  image.size.height.isFinite,
                  image.size.width > 0,
                  image.size.height > 0
            else {
                throw WriterError.message(
                    "This SVG cannot be rendered by the current macOS image decoder."
                )
            }

            let longest =
                max(
                    image.size.width,
                    image.size.height
                )

            let previewScale =
                min(
                    1,
                    4096
                    / max(
                        1,
                        longest
                    )
                )

            let target =
                NSSize(
                    width:
                        max(
                            1,
                            image.size.width
                            * previewScale
                        ),
                    height:
                        max(
                            1,
                            image.size.height
                            * previewScale
                        )
                )

            let rendered =
                NSImage(
                    size:
                        target
                )

            rendered.lockFocus()

            image.draw(
                in:
                    NSRect(
                        origin:
                            .zero,
                        size:
                            target
                    ),
                from:
                    .zero,
                operation:
                    .copy,
                fraction:
                    1
            )

            rendered.unlockFocus()

            guard let tiff =
                    rendered.tiffRepresentation,
                  let bitmap =
                    NSBitmapImageRep(
                        data:
                            tiff
                    ),
                  bitmap.pixelsWide > 0,
                  bitmap.pixelsHigh > 0,
                  let png =
                    bitmap.representation(
                        using:
                            .png,
                        properties:
                            [:]
                    )
            else {
                throw WriterError.message(
                    "The SVG Smart Object preview could not be created."
                )
            }

            return (
                png,
                bitmap.pixelsWide,
                bitmap.pixelsHigh,
                sourceKind
            )
        }
    }


    // Decode eagerly, and bake EXIF orientation into pixels for every existing renderer/editor.
    static func decodedRaster(_ data: Data) throws -> (data: Data, width: Int, height: Int) {
        guard let source=CGImageSourceCreateWithData(data as CFData,nil),
              let raw=CGImageSourceCreateImageAtIndex(source,0,[kCGImageSourceShouldCacheImmediately:true] as CFDictionary),
              CGImageSourceGetStatusAtIndex(source,0) == .statusComplete else {
            throw WriterError.message("The image is unsupported, incomplete, or corrupt. Choose a readable PNG, JPEG, HEIC, HEIF, TIFF, or PSD image.")
        }
        let properties=CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any]
        let orientation=(properties?[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let isPhotoshop=data.starts(with:Data("8BPS".utf8))
        if orientation == 1 && !isPhotoshop { return (data,raw.width,raw.height) }
        if isPhotoshop {
            guard let png=NSBitmapImageRep(cgImage:raw).representation(using:.png,properties:[:]) else {
                throw WriterError.message("The Photoshop composite could not be rendered.")
            }
            return (png,raw.width,raw.height)
        }
        let options: [CFString:Any] = [kCGImageSourceCreateThumbnailFromImageAlways:true,
            kCGImageSourceCreateThumbnailWithTransform:true,
            kCGImageSourceThumbnailMaxPixelSize:max(raw.width,raw.height)]
        guard let upright=CGImageSourceCreateThumbnailAtIndex(source,0,options as CFDictionary),
              let png=NSBitmapImageRep(cgImage:upright).representation(using:.png,properties:[:]) else {
            throw WriterError.message("The image orientation could not be decoded.")
        }
        return (png,upright.width,upright.height)
    }

    static func render(_ project: CoverProject, includeGuides: Bool = false, includeTemplate: Bool = false, scale: Double = 1, transparentCanvas: Bool = false) throws -> NSImage {
        guard project.canvasWidth.isFinite, project.canvasHeight.isFinite, project.canvasWidth > 0, project.canvasHeight > 0, project.canvasWidth*project.dpi < 100_000, project.canvasHeight*project.dpi < 100_000 else { throw WriterError.message("Cover dimensions exceed the safe rendering limit.") }
        let size=NSSize(width:project.canvasWidth*scale,height:project.canvasHeight*scale)
        guard size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0,
              size.width <= 100_000_000, size.height <= 100_000_000 else {
            throw WriterError.message("Cover dimensions exceed the safe rendering limit.")
        }
        let width = Int(size.width.rounded(.up)), height = Int(size.height.rounded(.up))
        guard width > 0, height > 0, width <= 100_000_000 / height,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw WriterError.message("Cover dimensions exceed the safe rendering limit.")
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        defer { NSGraphicsContext.restoreGraphicsState() }
        if !transparentCanvas {
            NSColor(hex:project.backgroundHex).setFill()
            NSBezierPath(rect:NSRect(origin:.zero,size:size)).fill()
        }
        let hiddenGroups=Set(project.layers.filter{$0.kind == .group && !$0.visible}.map{$0.id})
        let byID=Dictionary(project.layers.map{($0.id,$0)},uniquingKeysWith:{first,_ in first})
        for layer in project.layers where layer.visible && (includeTemplate || !layer.isReferenceLayer) && (layer.groupID.map{!hiddenGroups.contains($0)} ?? true) {
            if layer.kind == .adjustment { applyAdjustment(layer,to:context,size:size); continue }
            // Persisted typography/strokes use production raster units. Draw
            // in that canonical space at every preview/export resolution so
            // wrapping and glyph placement cannot change with canvas zoom.
            let drawingSize = project.rasterPixelSize
            context.saveGState()
            context.scaleBy(x: size.width / drawingSize.width, y: size.height / drawingSize.height)
            if let baseID=layer.clippedToLayerID,let base=byID[baseID],base.groupID==layer.groupID,base.visible {
                drawClipped(layer,to:base,in:drawingSize)
            } else { draw(layer, in:drawingSize) }
            context.restoreGState()
        }
        if includeGuides && project.guidesVisible { drawGuides(project, in:size) }
        guard let raster = context.makeImage() else { throw CocoaError(.fileReadCorruptFile) }
        return NSImage(cgImage: raster, size: size)
    }

    static func psdLayerImage(
        _ source: CoverLayer,
        project: CoverProject
    ) throws -> NSImage {
        let pixelWidth = Int(project.rasterPixelSize.width)
        let pixelHeight = Int(project.rasterPixelSize.height)

        guard pixelWidth > 0,
              pixelHeight > 0,
              pixelWidth <= 30_000,
              pixelHeight <= 30_000
        else {
            throw WriterError.message(
                "The cover dimensions exceed PSD version 1 limits."
            )
        }

        var layer =
            source

        layer.visible =
            true

        layer.opacity =
            1

        layer.blendMode =
            .normal

        layer.clippedToLayerID =
            nil

        layer.groupID =
            nil

        let size =
            NSSize(
                width:
                    pixelWidth,
                height:
                    pixelHeight
            )

        let image =
            NSImage(
                size:
                    size
            )

        image.lockFocus()

        if let context =
            NSGraphicsContext.current?
                .cgContext
        {
            context.clear(
                CGRect(
                    origin:
                        .zero,
                    size:
                        size
                )
            )
        }

        draw(
            layer,
            in:
                size
        )

        image.unlockFocus()

        return image
    }
    static func export(_ project: CoverProject, format: String, proof: Bool = false) throws -> Data {
        let type=format.lowercased()
        if type == "svg" { return try SVGExporter.export(project) }
        if type == "psd" { return try PSDExporter.export(project) }
        // Flatten every print PDF through the same compositor used by the
        // cover editor. The old per-layer vector path clipped photographs in
        // PDF viewers and could retain source pixels far above 300 DPI.
        let image=try render(
            project,
            includeGuides:proof,
            includeTemplate:proof,
            scale:project.dpi,
            transparentCanvas:type == "png-transparent" && !proof
        )
        if type == "pdf" {
            let data=NSMutableData(); var box=CGRect(origin:.zero,size:NSSize(width:project.canvasWidth*72,height:project.canvasHeight*72))
            guard let consumer=CGDataConsumer(data:data as CFMutableData), let context=CGContext(consumer:consumer,mediaBox:&box,nil) else { throw CocoaError(.fileWriteUnknown) }
            guard let raster=image.cgImage(forProposedRect:nil,context:nil,hints:nil) else { throw CocoaError(.fileReadCorruptFile) }
            context.interpolationQuality = .high
            context.beginPDFPage(nil); context.draw(raster,in:box); context.endPDFPage(); context.closePDF(); return data as Data
        }
        guard let tiff=image.tiffRepresentation, let bitmap=NSBitmapImageRep(data:tiff) else { throw CocoaError(.fileWriteUnknown) }
        // Raster dimensions are ceil-rounded; retain print DPI rather than AppKit's 72-DPI default.
        bitmap.size = NSSize(width:Double(bitmap.pixelsWide)*72/project.dpi,
                             height:Double(bitmap.pixelsHigh)*72/project.dpi)
        if type == "jpg" || type == "jpeg" { guard let data=bitmap.representation(using:.jpeg,properties:[.compressionFactor:0.92]) else { throw CocoaError(.fileWriteUnknown) }; return data }
        guard let data=bitmap.representation(using:.png,properties:[:]) else { throw CocoaError(.fileWriteUnknown) }; return data
    }

    private static func vectorPDF(_ project:CoverProject,proof:Bool)throws->Data {
        let data=NSMutableData();var box=CGRect(x:0,y:0,width:project.canvasWidth*72,height:project.canvasHeight*72)
        guard let consumer=CGDataConsumer(data:data as CFMutableData),let context=CGContext(consumer:consumer,mediaBox:&box,nil) else{throw CocoaError(.fileWriteUnknown)}
        context.beginPDFPage(nil)
        let graphics=NSGraphicsContext(cgContext:context,flipped:false)
        NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=graphics
        let size=NSSize(width:box.width,height:box.height)
        NSColor(hex:project.backgroundHex).setFill();NSBezierPath(rect:NSRect(origin:.zero,size:size)).fill()
        let hiddenGroups=Set(project.layers.filter{$0.kind == .group && !$0.visible}.map{$0.id})
        let byID=Dictionary(project.layers.map{($0.id,$0)},uniquingKeysWith:{first,_ in first})
        for layer in project.layers where layer.visible && (proof || !layer.isReferenceLayer) && (layer.groupID.map{!hiddenGroups.contains($0)} ?? true) {
            if layer.kind != .adjustment,let baseID=layer.clippedToLayerID,let base=byID[baseID],base.groupID==layer.groupID,base.visible { drawClipped(layer,to:base,in:size) }
            else { draw(layer,in:size) }
        }
        if proof && project.guidesVisible { drawGuides(project,in:size) }
        NSGraphicsContext.restoreGraphicsState();context.endPDFPage();context.closePDF()
        return data as Data
    }

    private static func hasAdvancedEffects(
        _ layer: CoverLayer
    ) -> Bool {
        layer.innerShadow?.enabled == true ||
        layer.strokeEffect?.enabled == true ||
        layer.colorOverlay?.enabled == true ||
        layer.gradientOverlay?.enabled == true ||
        layer.outerGlow?.enabled == true
    }

    private static func effectSourceCGImage(
        _ layer: CoverLayer,
        canvas: NSSize
    ) -> CGImage? {
        var sourceLayer = layer
        sourceLayer.opacity = 1
        sourceLayer.blendMode = .normal
        sourceLayer.dropShadow = nil
        sourceLayer.innerShadow = nil
        sourceLayer.strokeEffect = nil
        sourceLayer.colorOverlay = nil
        sourceLayer.gradientOverlay = nil
        sourceLayer.outerGlow = nil

        let image = NSImage(
            size: canvas
        )

        image.lockFocus()

        NSColor.clear.setFill()
        NSBezierPath(
            rect: NSRect(
                origin: .zero,
                size: canvas
            )
        ).fill()

        drawBase(
            sourceLayer,
            in: canvas
        )

        image.unlockFocus()

        guard
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(
                data: tiff
            )
        else {
            return nil
        }

        return bitmap.cgImage
    }

    private static func effectColorComponents(
        _ hex: String
    ) -> (
        CGFloat,
        CGFloat,
        CGFloat
    ) {
        let color =
            NSColor(
                hex: hex
            ).usingColorSpace(
                .deviceRGB
            ) ?? .black

        return (
            color.redComponent,
            color.greenComponent,
            color.blueComponent
        )
    }

    private static func colorizedEffectMask(
        _ mask: CIImage,
        colorHex: String,
        opacity: Double
    ) -> CIImage {
        let (
            red,
            green,
            blue
        ) = effectColorComponents(
            colorHex
        )

        return mask.applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputRVector":
                    CIVector(
                        x: 0,
                        y: 0,
                        z: 0,
                        w: 0
                    ),
                "inputGVector":
                    CIVector(
                        x: 0,
                        y: 0,
                        z: 0,
                        w: 0
                    ),
                "inputBVector":
                    CIVector(
                        x: 0,
                        y: 0,
                        z: 0,
                        w: 0
                    ),
                "inputAVector":
                    CIVector(
                        x: 0,
                        y: 0,
                        z: 0,
                        w: CGFloat(
                            max(
                                0,
                                min(
                                    1,
                                    opacity
                                )
                            )
                        )
                    ),
                "inputBiasVector":
                    CIVector(
                        x: red,
                        y: green,
                        z: blue,
                        w: 0
                    )
            ]
        )
    }

    private static func effectNSImage(
        _ image: CIImage,
        extent: CGRect,
        size: NSSize
    ) -> NSImage? {
        let context = CIContext(
            options: nil
        )

        guard let cgImage = context.createCGImage(
            image.cropped(
                to: extent
            ),
            from: extent
        ) else {
            return nil
        }

        return NSImage(
            cgImage: cgImage,
            size: size
        )
    }

    private static func drawEffectImage(
        _ image: NSImage,
        for layer: CoverLayer,
        in canvas: NSSize
    ) {
        guard let context =
            NSGraphicsContext.current?.cgContext
        else {
            return
        }

        context.saveGState()
        defer {
            context.restoreGState()
        }

        context.setAlpha(
            CGFloat(
                layer.opacity
            )
        )

        context.setBlendMode(
            (
                layer.blendMode ??
                .normal
            ).cgBlendMode
        )

        image.draw(
            in: NSRect(
                origin: .zero,
                size: canvas
            ),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
    }

    private static func strokeEffectImage(
        source: CIImage,
        effect: CoverStrokeEffect,
        canvas: NSSize
    ) -> NSImage? {
        let radius = max(
            0,
            effect.width *
            Double(
                canvas.width
            )
        )

        let expanded =
            radius > 0.0001
            ? source.applyingFilter(
                "CIMorphologyMaximum",
                parameters: [
                    kCIInputRadiusKey:
                        radius
                ]
            )
            : source

        let colored = colorizedEffectMask(
            expanded,
            colorHex: effect.colorHex,
            opacity: effect.opacity
        )

        return effectNSImage(
            colored,
            extent: source.extent,
            size: canvas
        )
    }

    private static func outerGlowImage(
        source: CIImage,
        effect: CoverOuterGlow,
        canvas: NSSize
    ) -> NSImage? {
        let radius = max(
            0,
            effect.size *
            Double(
                canvas.width
            )
        )

        let blurred =
            radius > 0.0001
            ? source
                .clampedToExtent()
                .applyingFilter(
                    "CIGaussianBlur",
                    parameters: [
                        kCIInputRadiusKey:
                            radius
                    ]
                )
                .cropped(
                    to: source.extent
                )
            : source

        let colored = colorizedEffectMask(
            blurred,
            colorHex: effect.colorHex,
            opacity: effect.opacity
        )

        return effectNSImage(
            colored,
            extent: source.extent,
            size: canvas
        )
    }

    private static func colorOverlayImage(
        source: CIImage,
        effect: CoverColorOverlay,
        canvas: NSSize
    ) -> NSImage? {
        let colored = colorizedEffectMask(
            source,
            colorHex: effect.colorHex,
            opacity: effect.opacity
        )

        return effectNSImage(
            colored,
            extent: source.extent,
            size: canvas
        )
    }

    private static func gradientOverlayImage(
        source: CIImage,
        effect: CoverGradientOverlay,
        canvas: NSSize
    ) -> NSImage? {
        let extent = source.extent
        let radians =
            effect.angle *
            .pi /
            180

        let center = CGPoint(
            x: extent.midX,
            y: extent.midY
        )

        let radius = max(
            extent.width,
            extent.height
        ) / 2

        let dx =
            cos(
                radians
            ) *
            radius

        let dy =
            sin(
                radians
            ) *
            radius

        let startColor =
            NSColor(
                hex: effect.startHex
            ).usingColorSpace(
                .deviceRGB
            ) ?? .black

        let endColor =
            NSColor(
                hex: effect.endHex
            ).usingColorSpace(
                .deviceRGB
            ) ?? .white

        let alpha = CGFloat(
            max(
                0,
                min(
                    1,
                    effect.opacity
                )
            )
        )

        guard
            let gradient = CIFilter(
                name:
                    "CILinearGradient",
                parameters: [
                    "inputPoint0":
                        CIVector(
                            x:
                                center.x -
                                dx,
                            y:
                                center.y -
                                dy
                        ),
                    "inputPoint1":
                        CIVector(
                            x:
                                center.x +
                                dx,
                            y:
                                center.y +
                                dy
                        ),
                    "inputColor0":
                        CIColor(
                            red:
                                startColor.redComponent,
                            green:
                                startColor.greenComponent,
                            blue:
                                startColor.blueComponent,
                            alpha:
                                alpha
                        ),
                    "inputColor1":
                        CIColor(
                            red:
                                endColor.redComponent,
                            green:
                                endColor.greenComponent,
                            blue:
                                endColor.blueComponent,
                            alpha:
                                alpha
                        )
                ]
            )?.outputImage?
                .cropped(
                    to: extent
                )
        else {
            return nil
        }

        let clear = CIImage(
            color:
                CIColor(
                    red: 0,
                    green: 0,
                    blue: 0,
                    alpha: 0
                )
        ).cropped(
            to: extent
        )

        guard
            let masked = CIFilter(
                name:
                    "CIBlendWithAlphaMask",
                parameters: [
                    kCIInputImageKey:
                        gradient,
                    kCIInputBackgroundImageKey:
                        clear,
                    kCIInputMaskImageKey:
                        source
                ]
            )?.outputImage
        else {
            return nil
        }

        return effectNSImage(
            masked,
            extent: extent,
            size: canvas
        )
    }

    private static func innerShadowImage(
        source: CIImage,
        effect: CoverInnerShadow,
        canvas: NSSize
    ) -> NSImage? {
        let extent = source.extent
        let radius = max(
            0,
            effect.blur *
            Double(
                canvas.width
            )
        )

        let radians =
            effect.angle *
            .pi /
            180

        let distance =
            effect.distance *
            Double(
                canvas.width
            )

        var shifted = source

        if radius > 0.0001 {
            shifted =
                shifted
                    .clampedToExtent()
                    .applyingFilter(
                        "CIGaussianBlur",
                        parameters: [
                            kCIInputRadiusKey:
                                radius
                        ]
                    )
        }

        shifted =
            shifted
                .transformed(
                    by:
                        CGAffineTransform(
                            translationX:
                                cos(
                                    radians
                                ) *
                                distance,
                            y:
                                sin(
                                    radians
                                ) *
                                distance
                        )
                )
                .cropped(
                    to: extent
                )

        let inverse = shifted.applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputRVector":
                    CIVector(
                        x: 0,
                        y: 0,
                        z: 0,
                        w: 0
                    ),
                "inputGVector":
                    CIVector(
                        x: 0,
                        y: 0,
                        z: 0,
                        w: 0
                    ),
                "inputBVector":
                    CIVector(
                        x: 0,
                        y: 0,
                        z: 0,
                        w: 0
                    ),
                "inputAVector":
                    CIVector(
                        x: 0,
                        y: 0,
                        z: 0,
                        w: -1
                    ),
                "inputBiasVector":
                    CIVector(
                        x: 1,
                        y: 1,
                        z: 1,
                        w: 1
                    )
            ]
        )

        guard
            let innerMask = CIFilter(
                name:
                    "CIMultiplyCompositing",
                parameters: [
                    kCIInputImageKey:
                        inverse,
                    kCIInputBackgroundImageKey:
                        source
                ]
            )?.outputImage?
                .cropped(
                    to: extent
                )
        else {
            return nil
        }

        let colored = colorizedEffectMask(
            innerMask,
            colorHex: effect.colorHex,
            opacity: effect.opacity
        )

        return effectNSImage(
            colored,
            extent: extent,
            size: canvas
        )
    }

    private static func draw(
        _ layer: CoverLayer,
        in canvas: NSSize
    ) {
        guard hasAdvancedEffects(
            layer
        ) else {
            drawBase(
                layer,
                in: canvas
            )
            return
        }

        guard
            let sourceCG =
                effectSourceCGImage(
                    layer,
                    canvas: canvas
                )
        else {
            drawBase(
                layer,
                in: canvas
            )
            return
        }

        let source = CIImage(
            cgImage: sourceCG
        )

        if
            let glow =
                layer.outerGlow,
            glow.enabled,
            let image =
                outerGlowImage(
                    source: source,
                    effect: glow,
                    canvas: canvas
                )
        {
            drawEffectImage(
                image,
                for: layer,
                in: canvas
            )
        }

        if
            let stroke =
                layer.strokeEffect,
            stroke.enabled,
            let image =
                strokeEffectImage(
                    source: source,
                    effect: stroke,
                    canvas: canvas
                )
        {
            drawEffectImage(
                image,
                for: layer,
                in: canvas
            )
        }

        drawBase(
            layer,
            in: canvas
        )

        if
            let overlay =
                layer.colorOverlay,
            overlay.enabled,
            let image =
                colorOverlayImage(
                    source: source,
                    effect: overlay,
                    canvas: canvas
                )
        {
            drawEffectImage(
                image,
                for: layer,
                in: canvas
            )
        }

        if
            let gradient =
                layer.gradientOverlay,
            gradient.enabled,
            let image =
                gradientOverlayImage(
                    source: source,
                    effect: gradient,
                    canvas: canvas
                )
        {
            drawEffectImage(
                image,
                for: layer,
                in: canvas
            )
        }

        if
            let shadow =
                layer.innerShadow,
            shadow.enabled,
            let image =
                innerShadowImage(
                    source: source,
                    effect: shadow,
                    canvas: canvas
                )
        {
            drawEffectImage(
                image,
                for: layer,
                in: canvas
            )
        }
    }

    static func baseGradientStops(
        _ layer:CoverLayer
    )->[CoverGradientStop] {
        if let stops=layer.gradientStops?
            .filter({
                $0.location.isFinite &&
                $0.opacity.isFinite &&
                $0.midpoint.isFinite
            })
            .sorted(by:{$0.location<$1.location}),
           stops.count>=2
        {
            return stops
        }

        return [
            CoverGradientStop(
                colorHex:layer.fillHex,
                location:0,
                opacity:1,
                midpoint:0.5
            ),
            CoverGradientStop(
                colorHex:layer.gradientEndHex ?? "#FFFFFF",
                location:1,
                opacity:1,
                midpoint:0.5
            )
        ]
    }

    private static func interpolatedGradientStop(
        _ first:CoverGradientStop,
        _ second:CoverGradientStop,
        colorFraction:Double,
        locationFraction:Double
    )->CoverGradientStop {
        let a=NSColor(hex:first.colorHex).usingColorSpace(.deviceRGB) ?? .black
        let b=NSColor(hex:second.colorHex).usingColorSpace(.deviceRGB) ?? .white
        let colorMix=max(0,min(1,colorFraction))
        let positionMix=max(0,min(1,locationFraction))

        func byte(_ value:CGFloat)->Int {
            Int(
                (
                    max(
                        0,
                        min(1,value)
                    ) * 255
                ).rounded()
            )
        }

        let red =
            a.redComponent +
            (b.redComponent-a.redComponent) *
            colorMix

        let green =
            a.greenComponent +
            (b.greenComponent-a.greenComponent) *
            colorMix

        let blue =
            a.blueComponent +
            (b.blueComponent-a.blueComponent) *
            colorMix

        let hex=String(
            format:"#%02X%02X%02X",
            byte(red),
            byte(green),
            byte(blue)
        )

        return CoverGradientStop(
            colorHex:hex,
            location:
                first.location +
                (second.location-first.location) *
                positionMix,
            opacity:
                first.opacity +
                (second.opacity-first.opacity) *
                colorMix,
            midpoint:0.5
        )
    }

    static func renderedGradientStops(
        _ layer:CoverLayer
    )->[CoverGradientStop] {
        let base=baseGradientStops(layer)

        guard base.count>=2 else {
            return base
        }

        var expanded:[CoverGradientStop]=[]

        for index in base.indices {
            let current=base[index]
            expanded.append(current)

            guard index<base.count-1 else {
                continue
            }

            let next=base[index+1]

            let midpoint=max(
                0.05,
                min(
                    0.95,
                    current.midpoint
                )
            )

            expanded.append(
                interpolatedGradientStop(
                    current,
                    next,
                    colorFraction:0.5,
                    locationFraction:midpoint
                )
            )
        }

        if layer.gradientReversed == true {
            return expanded
                .map {
                    var copy=$0
                    copy.location=1-copy.location
                    return copy
                }
                .sorted(by:{$0.location<$1.location})
        }

        return expanded.sorted(by:{$0.location<$1.location})
    }

    static func gradientLine(
        in rect:CGRect,
        angle:Double
    )->(start:CGPoint,end:CGPoint) {
        let radians=angle * .pi / 180
        let dx=cos(radians)
        let dy=sin(radians)

        let half =
            abs(CGFloat(dx))*rect.width/2 +
            abs(CGFloat(dy))*rect.height/2

        let center=CGPoint(
            x:rect.midX,
            y:rect.midY
        )

        return (
            CGPoint(
                x:center.x-CGFloat(dx)*half,
                y:center.y-CGFloat(dy)*half
            ),
            CGPoint(
                x:center.x+CGFloat(dx)*half,
                y:center.y+CGFloat(dy)*half
            )
        )
    }

    private static func drawGradientLayer(
        _ layer:CoverLayer,
        in local:CGRect,
        context:CGContext
    ) {
        let modern =
            layer.gradientStops != nil ||
            layer.gradientAngle != nil ||
            layer.gradientCenterX != nil ||
            layer.gradientCenterY != nil ||
            layer.gradientRadius != nil ||
            layer.gradientReversed != nil

        if !modern {
            let a=NSColor(hex:layer.fillHex).cgColor
            let b=NSColor(hex:layer.gradientEndHex ?? "#FFFFFF").cgColor

            if let gradient=CGGradient(
                colorsSpace:CGColorSpaceCreateDeviceRGB(),
                colors:[a,b] as CFArray,
                locations:[0,1]
            ) {
                if layer.gradientRadial == true {
                    context.drawRadialGradient(
                        gradient,
                        startCenter:CGPoint(
                            x:local.minX,
                            y:local.minY
                        ),
                        startRadius:0,
                        endCenter:CGPoint(
                            x:local.midX,
                            y:local.midY
                        ),
                        endRadius:max(
                            local.width,
                            local.height
                        ),
                        options:[.drawsAfterEndLocation]
                    )
                } else {
                    context.drawLinearGradient(
                        gradient,
                        start:CGPoint(
                            x:local.minX,
                            y:local.midY
                        ),
                        end:CGPoint(
                            x:local.maxX,
                            y:local.midY
                        ),
                        options:[.drawsAfterEndLocation]
                    )
                }
            }
            return
        }

        let stops=renderedGradientStops(layer)

        let colors=stops.map {
            NSColor(hex:$0.colorHex)
                .withAlphaComponent(
                    max(
                        0,
                        min(
                            1,
                            $0.opacity
                        )
                    )
                )
                .cgColor
        }

        let locations=stops.map {
            CGFloat(
                max(
                    0,
                    min(
                        1,
                        $0.location
                    )
                )
            )
        }

        guard let gradient=CGGradient(
            colorsSpace:CGColorSpaceCreateDeviceRGB(),
            colors:colors as CFArray,
            locations:locations
        ) else {
            return
        }

        if layer.gradientRadial == true {
            let center=CGPoint(
                x:
                    local.minX +
                    local.width *
                    CGFloat(layer.gradientCenterX ?? 0.5),
                y:
                    local.minY +
                    local.height *
                    CGFloat(layer.gradientCenterY ?? 0.5)
            )

            let radius =
                max(
                    0.01,
                    CGFloat(layer.gradientRadius ?? 0.75)
                ) *
                max(
                    local.width,
                    local.height
                )

            context.drawRadialGradient(
                gradient,
                startCenter:center,
                startRadius:0,
                endCenter:center,
                endRadius:radius,
                options:[
                    .drawsBeforeStartLocation,
                    .drawsAfterEndLocation
                ]
            )
        } else {
            let line=gradientLine(
                in:local,
                angle:layer.gradientAngle ?? 0
            )

            context.drawLinearGradient(
                gradient,
                start:line.start,
                end:line.end,
                options:[
                    .drawsBeforeStartLocation,
                    .drawsAfterEndLocation
                ]
            )
        }
    }

    private static func drawBase(_ source: CoverLayer, in canvas: NSSize) {
        var layer = source
        if let pageWidth = layer.referencePageWidth, pageWidth.isFinite, pageWidth > 0 {
            let factor = canvas.width / pageWidth
            layer.fontSize *= factor
            if layer.psdTextPixelBasis == true {
                layer.lineSpacing *= factor; layer.letterSpacing *= factor
                layer.leading = layer.leading.map { $0 * factor }
                layer.baselineShift = layer.baselineShift.map { $0 * factor }
                layer.paragraphIndent = layer.paragraphIndent.map { $0 * factor }
                layer.paragraphSpacing = layer.paragraphSpacing.map { $0 * factor }
            }
            layer.strokeWidth *= factor
            layer.strokeDashPattern = layer.strokeDashPattern?.map { $0 * factor }
            layer.strokeDashPhase = layer.strokeDashPhase.map { $0 * factor }
        }
        let rect=NSRect(x:layer.frame.x*canvas.width,y:(1-layer.frame.y-layer.frame.height)*canvas.height,width:layer.frame.width*canvas.width,height:layer.frame.height*canvas.height)
        NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
        let context=NSGraphicsContext.current!.cgContext; context.setAlpha(CGFloat(layer.opacity * (layer.fillOpacity ?? 1)))
        context.setBlendMode((layer.blendMode ?? .normal).cgBlendMode)
        if let shadow=layer.dropShadow,shadow.enabled{let radians=shadow.angle * .pi/180;let color=NSColor(hex:shadow.colorHex).withAlphaComponent(shadow.opacity);context.setShadow(offset:CGSize(width:cos(radians)*shadow.distance*canvas.width,height:sin(radians)*shadow.distance*canvas.height),blur:shadow.blur*canvas.width,color:color.cgColor)}
        context.translateBy(x:rect.midX,y:rect.midY); context.rotate(by:layer.rotation * .pi/180);context.concatenate(CGAffineTransform(a:1,b:layer.skewY ?? 0,c:layer.skewX ?? 0,d:1,tx:0,ty:0));context.scaleBy(x:layer.flipHorizontal ? -1:1,y:layer.flipVertical ? -1:1)
        let local=NSRect(x:-rect.width/2,y:-rect.height/2,width:rect.width,height:rect.height)
        switch layer.kind {
        case .image, .template, .paint, .smartObject:
            if let data=layer.imageData, let image=processedImage(data:data,layer:layer) {
                let target=NSRect(x:local.minX,y:local.minY,width:local.width,height:local.height)
                let sourceSize=image.size
                let source:NSRect
                var destination=target
                if let crop=layer.sourceCrop { source=NSRect(x:crop.x*sourceSize.width,y:(1-crop.y-crop.height)*sourceSize.height,width:crop.width*sourceSize.width,height:crop.height*sourceSize.height) }
                else if layer.cropMode == .fit {
                    let factor=min(target.width/sourceSize.width,target.height/sourceSize.height)
                    destination=NSRect(x:target.midX-sourceSize.width*factor/2,y:target.midY-sourceSize.height*factor/2,width:sourceSize.width*factor,height:sourceSize.height*factor)
                    source = NSRect(origin:.zero,size:sourceSize)
                } else if layer.cropMode == .fill {
                    let sourceAspect=sourceSize.width/sourceSize.height, targetAspect=target.width/target.height
                    if sourceAspect > targetAspect { let width=sourceSize.height*targetAspect; source=NSRect(x:(sourceSize.width-width)/2 + layer.cropOffsetX*sourceSize.width,y:0,width:width,height:sourceSize.height) }
                    else { let height=sourceSize.width/targetAspect; source=NSRect(x:0,y:(sourceSize.height-height)/2 + layer.cropOffsetY*sourceSize.height,width:sourceSize.width,height:height) }
                } else { source=NSRect(x:max(0,layer.cropOffsetX)*sourceSize.width,y:max(0,layer.cropOffsetY)*sourceSize.height,width:sourceSize.width*(1-min(0.9,abs(layer.cropOffsetX))),height:sourceSize.height*(1-min(0.9,abs(layer.cropOffsetY)))) }
                // NSImage.draw sets its own compositing operation and fraction.
                // Composite its pixels as a group so the layer's CG opacity and
                // blend mode apply once when the group is drawn onto the canvas.
                context.beginTransparencyLayer(auxiliaryInfo:nil)
                image.draw(in:destination,from:source,operation:.sourceOver,fraction:1,respectFlipped:false,hints:nil)
                context.endTransparencyLayer()
            }
        case .text:
            let attributed =
                NSAttributedString(
                    string: layer.text,
                    attributes:
                        CoverTypography.attributes(
                            for: layer
                        )
                )

            if layer.referenceOnly == true {
                // PDF lines have explicit positions, not paragraph containers.
                // AppKit's paragraph wrapping can otherwise drop the last words
                // when font advances differ slightly from embedded PDF metrics.
                let measured = attributed.size()
                let xScale = local.width / max(1, measured.width)
                context.saveGState()
                context.scaleBy(x: xScale, y: 1)
                attributed.draw(at: NSPoint(x: local.minX / xScale,
                                             y: local.maxY - measured.height))
                context.restoreGState()
                break
            }

            let horizontalScale =
                max(
                    0.1,
                    layer.horizontalScale
                    ?? 1
                )

            let verticalScale =
                max(
                    0.1,
                    layer.verticalScale
                    ?? 1
                )

            context.saveGState()

            context.scaleBy(
                x: CGFloat(horizontalScale),
                y: CGFloat(verticalScale)
            )

            let textRect =
                NSRect(
                    x:
                        local.minX
                        /
                        CGFloat(horizontalScale),
                    y:
                        local.minY
                        /
                        CGFloat(verticalScale),
                    width:
                        local.width
                        /
                        CGFloat(horizontalScale),
                    height:
                        local.height
                        /
                        CGFloat(verticalScale)
                )

            attributed.draw(
                in: textRect
            )

            context.restoreGState()
        case .shape:
            let path=NSBezierPath()
            if layer.shape == .ellipse { path.appendOval(in:local) }
            else if layer.shape == .line { path.move(to:NSPoint(x:local.minX,y:local.midY)); path.line(to:NSPoint(x:local.maxX,y:local.midY)) }
            else { path.appendRect(local) }
            NSColor(hex:layer.fillHex).setFill(); path.fill(); NSColor(hex:layer.strokeHex).setStroke(); CoverEditorEngine.configureVectorStroke(path,layer:layer); path.stroke()
        case .gradient:
            drawGradientLayer(
                layer,
                in:local,
                context:context
            )
        case .adjustment, .group:
            break
        case .path:
            let contours=CoverEditorEngine.vectorContours(
                for:layer
            )

            guard !contours.isEmpty else {
                break
            }

            let closures =
                CoverEditorEngine.vectorContourClosures(
                    for:layer,
                    contourCount:contours.count
                )

            let path=CoverEditorEngine.vectorCompoundPath(
                contours:contours,
                in:local,
                closures:closures
            )

            let closedContours =
                contours.enumerated().compactMap {
                    pair -> [CoverPathPoint]? in

                    let index = pair.offset

                    guard closures.indices.contains(index),
                          closures[index]
                    else {
                        return nil
                    }

                    return pair.element
                }

            if !closedContours.isEmpty {
                let fillPath =
                    CoverEditorEngine.vectorCompoundPath(
                        contours:closedContours,
                        in:local,
                        closed:true
                    )

                NSColor(hex:layer.fillHex).setFill()
                CoverEditorEngine.configureVectorFillRule(
                    fillPath,
                    layer:
                        layer
                )
                fillPath.fill()
            }

            NSColor(hex:layer.strokeHex).setStroke()
            CoverEditorEngine.configureVectorStroke(path,layer:layer)
            path.stroke()
        }
    }
    private static func drawClipped(_ layer:CoverLayer,to base:CoverLayer,in size:NSSize){
        guard let layerImage=isolatedImage(layer,size:size),let baseImage=isolatedImage(base,size:size),let layerTIFF=layerImage.tiffRepresentation,let baseTIFF=baseImage.tiffRepresentation,let layerRep=NSBitmapImageRep(data:layerTIFF),let baseRep=NSBitmapImageRep(data:baseTIFF),let layerCG=layerRep.cgImage,let baseCG=baseRep.cgImage else{return}
        let source=CIImage(cgImage:layerCG),baseCI=CIImage(cgImage:baseCG),extent=source.extent
        let alpha=baseCI.applyingFilter("CIColorMatrix",parameters:["inputRVector":CIVector(x:0,y:0,z:0,w:1),"inputGVector":CIVector(x:0,y:0,z:0,w:1),"inputBVector":CIVector(x:0,y:0,z:0,w:1),"inputAVector":CIVector(x:0,y:0,z:0,w:1)])
        let blend=CIFilter(name:"CIBlendWithAlphaMask");blend?.setValue(source,forKey:kCIInputImageKey);blend?.setValue(CIImage(color:.clear).cropped(to:extent),forKey:kCIInputBackgroundImageKey);blend?.setValue(alpha,forKey:kCIInputMaskImageKey)
        guard let output=blend?.outputImage,let rendered=CIContext(options:nil).createCGImage(output.cropped(to:extent),from:extent) else{return}
        NSImage(cgImage:rendered,size:size).draw(in:NSRect(origin:.zero,size:size),from:.zero,operation:.sourceOver,fraction:1)
    }
    private static func isolatedImage(_ layer:CoverLayer,size:NSSize)->NSImage?{let image=NSImage(size:size);image.lockFocus();NSColor.clear.setFill();NSBezierPath(rect:NSRect(origin:.zero,size:size)).fill();draw(layer,in:size);image.unlockFocus();return image}
    private static func channelMixerParameters(
        _ values:[String:Double]
    ) -> [String:Any] {
        let preserveLuminosity =
            (
                values["preserveLuminosity"]
                ?? 1
            ) >= 0.5

        func coefficients(
            _ red:Double,
            _ green:Double,
            _ blue:Double
        ) -> (
            Double,
            Double,
            Double
        ) {
            guard preserveLuminosity else {
                return (
                    red,
                    green,
                    blue
                )
            }

            let total =
                red
                + green
                + blue

            guard abs(total) > 0.000001 else {
                return (
                    red,
                    green,
                    blue
                )
            }

            return (
                red / total,
                green / total,
                blue / total
            )
        }

        let redOutput =
            coefficients(
                values["redRed"] ?? 1,
                values["redGreen"] ?? 0,
                values["redBlue"] ?? 0
            )

        let greenOutput =
            coefficients(
                values["greenRed"] ?? 0,
                values["greenGreen"] ?? 1,
                values["greenBlue"] ?? 0
            )

        let blueOutput =
            coefficients(
                values["blueRed"] ?? 0,
                values["blueGreen"] ?? 0,
                values["blueBlue"] ?? 1
            )

        return [
            "inputRVector":
                CIVector(
                    x:redOutput.0,
                    y:redOutput.1,
                    z:redOutput.2,
                    w:0
                ),
            "inputGVector":
                CIVector(
                    x:greenOutput.0,
                    y:greenOutput.1,
                    z:greenOutput.2,
                    w:0
                ),
            "inputBVector":
                CIVector(
                    x:blueOutput.0,
                    y:blueOutput.1,
                    z:blueOutput.2,
                    w:0
                ),
            "inputAVector":
                CIVector(
                    x:0,
                    y:0,
                    z:0,
                    w:1
                ),
            "inputBiasVector":
                CIVector(
                    x:
                        (
                            values["redConstant"]
                            ?? 0
                        )
                        * 0.5,
                    y:
                        (
                            values["greenConstant"]
                            ?? 0
                        )
                        * 0.5,
                    z:
                        (
                            values["blueConstant"]
                            ?? 0
                        )
                        * 0.5,
                    w:0
                )
        ]
    }

    private static func adjustmentClampedUnit(
        _ value:Double
    ) -> Double {
        min(
            1,
            max(
                0,
                value
            )
        )
    }

    private static func selectiveColorWeight(
        target:String,
        red:Double,
        green:Double,
        blue:Double
    ) -> Double {
        let maximum =
            max(
                red,
                max(
                    green,
                    blue
                )
            )

        let minimum =
            min(
                red,
                min(
                    green,
                    blue
                )
            )

        let chroma =
            maximum
            - minimum

        let denominator =
            max(
                0.000001,
                chroma
            )

        switch target {
        case "reds":
            return adjustmentClampedUnit(
                (
                    red
                    - max(
                        green,
                        blue
                    )
                )
                / denominator
            )

        case "yellows":
            return adjustmentClampedUnit(
                (
                    min(
                        red,
                        green
                    )
                    - blue
                )
                / denominator
            )

        case "greens":
            return adjustmentClampedUnit(
                (
                    green
                    - max(
                        red,
                        blue
                    )
                )
                / denominator
            )

        case "cyans":
            return adjustmentClampedUnit(
                (
                    min(
                        green,
                        blue
                    )
                    - red
                )
                / denominator
            )

        case "blues":
            return adjustmentClampedUnit(
                (
                    blue
                    - max(
                        red,
                        green
                    )
                )
                / denominator
            )

        case "magentas":
            return adjustmentClampedUnit(
                (
                    min(
                        red,
                        blue
                    )
                    - green
                )
                / denominator
            )

        case "whites":
            return adjustmentClampedUnit(
                (
                    minimum
                    - 0.50
                )
                / 0.50
            )

        case "blacks":
            return adjustmentClampedUnit(
                (
                    0.50
                    - maximum
                )
                / 0.50
            )

        case "neutrals":
            let luminance =
                red * 0.2126
                + green * 0.7152
                + blue * 0.0722

            let midpoint =
                adjustmentClampedUnit(
                    1
                    - abs(
                        luminance
                        - 0.5
                    )
                    * 2
                )

            let white =
                adjustmentClampedUnit(
                    (
                        minimum
                        - 0.50
                    )
                    / 0.50
                )

            let black =
                adjustmentClampedUnit(
                    (
                        0.50
                        - maximum
                    )
                    / 0.50
                )

            return adjustmentClampedUnit(
                midpoint
                * (
                    1
                    - max(
                        white,
                        black
                    )
                )
            )

        default:
            return 0
        }
    }

    private static func selectiveColorChannel(
        _ value:Double,
        ink:Double,
        weight:Double,
        relative:Bool
    ) -> Double {
        let amount =
            min(
                1,
                max(
                    -1,
                    ink
                )
            )

        if amount >= 0 {
            let basis =
                relative
                ? value
                : 1

            return adjustmentClampedUnit(
                value
                - amount
                * weight
                * basis
                * 0.75
            )
        }

        let basis =
            relative
            ? (
                1
                - value
            )
            : 1

        return adjustmentClampedUnit(
            value
            + (
                -amount
            )
            * weight
            * basis
            * 0.75
        )
    }

    private static func selectiveColorPixel(
        red:Double,
        green:Double,
        blue:Double,
        values:[String:Double]
    ) -> (
        Double,
        Double,
        Double
    ) {
        var outputRed =
            adjustmentClampedUnit(
                red
            )

        var outputGreen =
            adjustmentClampedUnit(
                green
            )

        var outputBlue =
            adjustmentClampedUnit(
                blue
            )

        let relative =
            (
                values["selectiveRelative"]
                ?? 1
            ) >= 0.5

        let targets = [
            "reds",
            "yellows",
            "greens",
            "cyans",
            "blues",
            "magentas",
            "whites",
            "neutrals",
            "blacks"
        ]

        for target in targets {
            let weight =
                selectiveColorWeight(
                    target:target,
                    red:red,
                    green:green,
                    blue:blue
                )

            guard weight > 0.000001 else {
                continue
            }

            outputRed =
                selectiveColorChannel(
                    outputRed,
                    ink:
                        values[
                            "\(target)Cyan"
                        ]
                        ?? 0,
                    weight:weight,
                    relative:relative
                )

            outputGreen =
                selectiveColorChannel(
                    outputGreen,
                    ink:
                        values[
                            "\(target)Magenta"
                        ]
                        ?? 0,
                    weight:weight,
                    relative:relative
                )

            outputBlue =
                selectiveColorChannel(
                    outputBlue,
                    ink:
                        values[
                            "\(target)Yellow"
                        ]
                        ?? 0,
                    weight:weight,
                    relative:relative
                )

            let black =
                min(
                    1,
                    max(
                        -1,
                        values[
                            "\(target)Black"
                        ]
                        ?? 0
                    )
                )

            if black >= 0 {
                let factor =
                    max(
                        0,
                        1
                        - black
                        * weight
                    )

                outputRed =
                    adjustmentClampedUnit(
                        outputRed
                        * factor
                    )

                outputGreen =
                    adjustmentClampedUnit(
                        outputGreen
                        * factor
                    )

                outputBlue =
                    adjustmentClampedUnit(
                        outputBlue
                        * factor
                    )
            } else {
                let lift =
                    min(
                        1,
                        (
                            -black
                        )
                        * weight
                    )

                outputRed =
                    adjustmentClampedUnit(
                        outputRed
                        + (
                            1
                            - outputRed
                        )
                        * lift
                    )

                outputGreen =
                    adjustmentClampedUnit(
                        outputGreen
                        + (
                            1
                            - outputGreen
                        )
                        * lift
                    )

                outputBlue =
                    adjustmentClampedUnit(
                        outputBlue
                        + (
                            1
                            - outputBlue
                        )
                        * lift
                    )
            }
        }

        return (
            outputRed,
            outputGreen,
            outputBlue
        )
    }

    private static func selectiveColorCubeData(
        _ values:[String:Double],
        dimension:Int = 32
    ) -> Data {
        let side =
            max(
                2,
                dimension
            )

        let denominator =
            Double(
                side
                - 1
            )

        var cube =
            [Float](
                repeating:0,
                count:
                    side
                    * side
                    * side
                    * 4
            )

        var offset = 0

        for blueIndex in 0..<side {
            let blue =
                Double(
                    blueIndex
                )
                / denominator

            for greenIndex in 0..<side {
                let green =
                    Double(
                        greenIndex
                    )
                    / denominator

                for redIndex in 0..<side {
                    let red =
                        Double(
                            redIndex
                        )
                        / denominator

                    let result =
                        selectiveColorPixel(
                            red:red,
                            green:green,
                            blue:blue,
                            values:values
                        )

                    cube[offset] =
                        Float(
                            result.0
                        )

                    cube[offset + 1] =
                        Float(
                            result.1
                        )

                    cube[offset + 2] =
                        Float(
                            result.2
                        )

                    cube[offset + 3] = 1

                    offset += 4
                }
            }
        }

        return cube.withUnsafeBytes {
            Data(
                $0
            )
        }
    }

    private static func adjustmentSRGBToLinear(
        _ value:Double
    ) -> Double {
        let value =
            adjustmentClampedUnit(
                value
            )

        if value <= 0.04045 {
            return value / 12.92
        }

        return pow(
            (
                value + 0.055
            )
            / 1.055,
            2.4
        )
    }

    private static func adjustmentLinearToSRGB(
        _ value:Double
    ) -> Double {
        let value =
            adjustmentClampedUnit(
                value
            )

        if value <= 0.0031308 {
            return value * 12.92
        }

        return adjustmentClampedUnit(
            1.055
            * pow(
                value,
                1 / 2.4
            )
            - 0.055
        )
    }

    private static func adjustmentSafeLevels(
        _ values:[String:Double]
    ) -> (
        inputBlack:Double,
        gamma:Double,
        inputWhite:Double,
        outputBlack:Double,
        outputWhite:Double
    ) {
        let inputBlack =
            adjustmentClampedUnit(
                values["inputBlack"]
                ?? 0
            )

        let requestedInputWhite =
            adjustmentClampedUnit(
                values["inputWhite"]
                ?? 1
            )

        let inputWhite =
            min(
                1,
                max(
                    inputBlack + 0.001,
                    requestedInputWhite
                )
            )

        let gamma =
            min(
                10,
                max(
                    0.1,
                    values["gamma"]
                    ?? 1
                )
            )

        let outputBlack =
            adjustmentClampedUnit(
                values["outputBlack"]
                ?? 0
            )

        let outputWhite =
            min(
                1,
                max(
                    outputBlack,
                    adjustmentClampedUnit(
                        values["outputWhite"]
                        ?? 1
                    )
                )
            )

        return (
            inputBlack,
            gamma,
            inputWhite,
            outputBlack,
            outputWhite
        )
    }

    private static func adjustmentLevelValue(
        _ linearValue:Double,
        levels:(
            inputBlack:Double,
            gamma:Double,
            inputWhite:Double,
            outputBlack:Double,
            outputWhite:Double
        )
    ) -> Double {
        let perceptualValue =
            adjustmentLinearToSRGB(
                linearValue
            )

        let normalized =
            adjustmentClampedUnit(
                (
                    perceptualValue
                    - levels.inputBlack
                )
                / max(
                    0.001,
                    levels.inputWhite
                    - levels.inputBlack
                )
            )

        let corrected =
            pow(
                normalized,
                1 / levels.gamma
            )

        let perceptualOutput =
            adjustmentClampedUnit(
                levels.outputBlack
                + corrected
                * (
                    levels.outputWhite
                    - levels.outputBlack
                )
            )

        return adjustmentSRGBToLinear(
            perceptualOutput
        )
    }

    private static func levelsCubeData(
        _ values:[String:Double],
        dimension:Int = 32
    ) -> Data {
        let side =
            max(
                2,
                dimension
            )

        let levels =
            adjustmentSafeLevels(
                values
            )

        let denominator =
            Double(
                side - 1
            )

        var cube =
            [Float](
                repeating:0,
                count:
                    side
                    * side
                    * side
                    * 4
            )

        var offset = 0

        for blueIndex in 0..<side {
            let blue =
                adjustmentLevelValue(
                    Double(blueIndex)
                    / denominator,
                    levels:levels
                )

            for greenIndex in 0..<side {
                let green =
                    adjustmentLevelValue(
                        Double(greenIndex)
                        / denominator,
                        levels:levels
                    )

                for redIndex in 0..<side {
                    let red =
                        adjustmentLevelValue(
                            Double(redIndex)
                            / denominator,
                            levels:levels
                        )

                    cube[offset] =
                        Float(red)

                    cube[offset + 1] =
                        Float(green)

                    cube[offset + 2] =
                        Float(blue)

                    cube[offset + 3] = 1

                    offset += 4
                }
            }
        }

        return cube.withUnsafeBytes {
            Data($0)
        }
    }

    private static func monotonicCurveValues(
        _ values:[String:Double]
    ) -> [Double] {
        let requested = [
            values["curve0"] ?? 0,
            values["curve1"] ?? 0.25,
            values["curve2"] ?? 0.50,
            values["curve3"] ?? 0.75,
            values["curve4"] ?? 1
        ]
        .map {
            adjustmentClampedUnit($0)
        }

        var result =
            [Double]()

        result.reserveCapacity(5)

        var floor = 0.0

        for value in requested {
            let next =
                max(
                    floor,
                    value
                )

            result.append(next)
            floor = next
        }

        return result
    }

    private static func toneCurveParameters(
        _ values:[String:Double]
    ) -> [String:Any] {
        let curve =
            monotonicCurveValues(
                values
            )

        return [
            "inputPoint0":
                CIVector(
                    x:0,
                    y:curve[0]
                ),
            "inputPoint1":
                CIVector(
                    x:0.25,
                    y:curve[1]
                ),
            "inputPoint2":
                CIVector(
                    x:0.50,
                    y:curve[2]
                ),
            "inputPoint3":
                CIVector(
                    x:0.75,
                    y:curve[3]
                ),
            "inputPoint4":
                CIVector(
                    x:1,
                    y:curve[4]
                )
        ]
    }

    private static func blackWhiteGray(
        red:Double,
        green:Double,
        blue:Double,
        values:[String:Double]
    ) -> Double {
        let maximum =
            max(
                red,
                max(
                    green,
                    blue
                )
            )

        let minimum =
            min(
                red,
                min(
                    green,
                    blue
                )
            )

        let chroma =
            maximum - minimum

        let saturation =
            maximum > 0.000001
            ? chroma / maximum
            : 0

        let baseLuminance =
            red * 0.2126
            + green * 0.7152
            + blue * 0.0722

        guard saturation > 0.000001 else {
            return adjustmentClampedUnit(
                baseLuminance
            )
        }

        let targets = [
            (
                "reds",
                values["bwReds"]
                ?? 0.40
            ),
            (
                "yellows",
                values["bwYellows"]
                ?? 0.60
            ),
            (
                "greens",
                values["bwGreens"]
                ?? 0.40
            ),
            (
                "cyans",
                values["bwCyans"]
                ?? 0.60
            ),
            (
                "blues",
                values["bwBlues"]
                ?? 0.20
            ),
            (
                "magentas",
                values["bwMagentas"]
                ?? 0.80
            )
        ]

        var weighted = 0.0
        var total = 0.0

        for (
            target,
            control
        ) in targets {
            let weight =
                selectiveColorWeight(
                    target:target,
                    red:red,
                    green:green,
                    blue:blue
                )

            weighted +=
                weight * control

            total += weight
        }

        guard total > 0.000001 else {
            return adjustmentClampedUnit(
                baseLuminance
            )
        }

        let hueGray =
            adjustmentClampedUnit(
                weighted / total
            )

        return adjustmentClampedUnit(
            baseLuminance
            * (
                1 - saturation
            )
            + hueGray
            * saturation
        )
    }

    private static func blackWhiteCubeData(
        _ values:[String:Double],
        tintHex:String,
        dimension:Int = 32
    ) -> Data {
        let side =
            max(
                2,
                dimension
            )

        let denominator =
            Double(
                side - 1
            )

        let tintEnabled =
            (
                values["blackWhiteTint"]
                ?? 0
            ) >= 0.5

        let (
            tintRed,
            tintGreen,
            tintBlue
        ) =
            effectColorComponents(
                tintHex
            )

        var cube =
            [Float](
                repeating:0,
                count:
                    side
                    * side
                    * side
                    * 4
            )

        var offset = 0

        for blueIndex in 0..<side {
            let blue =
                Double(
                    blueIndex
                )
                / denominator

            for greenIndex in 0..<side {
                let green =
                    Double(
                        greenIndex
                    )
                    / denominator

                for redIndex in 0..<side {
                    let red =
                        Double(
                            redIndex
                        )
                        / denominator

                    let gray =
                        blackWhiteGray(
                            red:red,
                            green:green,
                            blue:blue,
                            values:values
                        )

                    if tintEnabled {
                        cube[offset] =
                            Float(
                                gray
                                * Double(tintRed)
                            )

                        cube[offset + 1] =
                            Float(
                                gray
                                * Double(tintGreen)
                            )

                        cube[offset + 2] =
                            Float(
                                gray
                                * Double(tintBlue)
                            )
                    } else {
                        cube[offset] =
                            Float(gray)

                        cube[offset + 1] =
                            Float(gray)

                        cube[offset + 2] =
                            Float(gray)
                    }

                    cube[offset + 3] = 1

                    offset += 4
                }
            }
        }

        return cube.withUnsafeBytes {
            Data($0)
        }
    }

    private static func adjustmentCIColor(
        _ hex: String
    ) -> CIColor {
        let (
            red,
            green,
            blue
        ) = effectColorComponents(
            hex
        )

        return CIColor(
            red: red,
            green: green,
            blue: blue,
            alpha: 1
        )
    }

    private static func processedImage(data:Data,layer:CoverLayer)->NSImage? {
        guard let image=sourceImage(data:data) else{return nil}
        guard layer.adjustment != nil || layer.maskData != nil || layer.perspectiveCorners != nil || layer.warpPreset != nil || layer.filters?.contains(where:{$0.enabled}) == true else{return image}
        guard let tiff=image.tiffRepresentation,let bitmap=NSBitmapImageRep(data:tiff),let cg=bitmap.cgImage else{return image}
        var ci=CIImage(cgImage:cg)
        if let preset=layer.warpPreset,abs(layer.warpAmount ?? 0)>0.0001 {
            let warped=CoverEditorEngine.warpedImage(NSImage(cgImage:cg,size:image.size),preset:preset,amount:layer.warpAmount ?? 0)
            if let warpedTIFF=warped.tiffRepresentation,let warpedRep=NSBitmapImageRep(data:warpedTIFF),let warpedCG=warpedRep.cgImage { ci=CIImage(cgImage:warpedCG) }
        }
        if let corners=layer.perspectiveCorners,corners.count==4 {let e=ci.extent;func point(_ p:CoverPathPoint)->CIVector{CIVector(x:e.minX+p.x*e.width,y:e.minY+(1-p.y)*e.height)};ci=ci.applyingFilter("CIPerspectiveTransform",parameters:["inputTopLeft":point(corners[0]),"inputTopRight":point(corners[1]),"inputBottomRight":point(corners[2]),"inputBottomLeft":point(corners[3])]).cropped(to:e)}
        if let adjustment=layer.adjustment {
            let values=layer.adjustmentValues ?? [:]
            let name:String; var parameters:[String:Any]=[kCIInputImageKey:ci]
            switch adjustment {
            case .brightnessContrast: name="CIColorControls";parameters[kCIInputBrightnessKey]=values["brightness"] ?? 0;parameters[kCIInputContrastKey]=values["contrast"] ?? 1
            case .exposure: name="CIExposureAdjust";parameters[kCIInputEVKey]=values["exposure"] ?? 0
            case .levels: name="CIColorCube";parameters["inputCubeDimension"]=32;parameters["inputCubeData"]=levelsCubeData(values)
            case .curves: name="CIToneCurve";parameters.merge(toneCurveParameters(values)){_,new in new}
            case .hueSaturation: name="CIColorControls";parameters[kCIInputSaturationKey]=values["saturation"] ?? 1;parameters[kCIInputBrightnessKey]=values["brightness"] ?? 0
            case .vibrance: name="CIVibrance";parameters["inputAmount"]=values["amount"] ?? 0.5
            case .temperatureTint: name="CITemperatureAndTint";parameters["inputNeutral"]=CIVector(x:6500,y:0);parameters["inputTargetNeutral"]=CIVector(x:6500+(values["temperature"] ?? 0)*1500,y:(values["tint"] ?? 0)*100)
            case .colorBalance: name="CIColorMatrix";parameters["inputBiasVector"]=CIVector(x:(values["cyanRed"] ?? 0)*0.5,y:(values["magentaGreen"] ?? 0)*0.5,z:(values["yellowBlue"] ?? 0)*0.5,w:0)
            case .threshold: name="CIColorThreshold";parameters["inputThreshold"]=values["threshold"] ?? 0.5
            case .posterize: name="CIColorPosterize";parameters["inputLevels"]=max(2,min(30,values["levels"] ?? 6))
            case .gradientMap: name="CIFalseColor";parameters["inputColor0"]=adjustmentCIColor(layer.fillHex);parameters["inputColor1"]=adjustmentCIColor(layer.gradientEndHex ?? "#FFFFFF")
            case .channelMixer: name="CIColorMatrix";parameters.merge(channelMixerParameters(values)){_,new in new}
            case .selectiveColor: name="CIColorCube";parameters["inputCubeDimension"]=32;parameters["inputCubeData"]=selectiveColorCubeData(values)
            case .monochrome: name="CIColorCube";parameters["inputCubeDimension"]=32;parameters["inputCubeData"]=blackWhiteCubeData(values,tintHex:layer.fillHex)
            case .invert: name="CIColorInvert"
            case .gaussianBlur: name="CIGaussianBlur";parameters[kCIInputRadiusKey]=values["radius"] ?? 3
            case .sharpen: name="CISharpenLuminance";parameters[kCIInputSharpnessKey]=values["amount"] ?? 0.4
            }
            if let filter=CIFilter(name:name,parameters:parameters),let output=filter.outputImage { ci=output.cropped(to:ci.extent) }
        }
        for item in layer.filters ?? [] where item.enabled {let name:String;var values:[String:Any]=[kCIInputImageKey:ci];switch item.kind{case .gaussianBlur:name="CIGaussianBlur";values[kCIInputRadiusKey]=item.amount*12;case .sharpen:name="CISharpenLuminance";values[kCIInputSharpnessKey]=item.amount;case .noiseReduction:name="CINoiseReduction";values["inputNoiseLevel"]=item.amount*0.1;values["inputSharpness"]=0.4;case .pixelate:name="CIPixellate";values[kCIInputScaleKey]=max(2,item.amount*24);case .sepia:name="CISepiaTone";values[kCIInputIntensityKey]=item.amount;case .invert:name="CIColorInvert";case .exposure:name="CIExposureAdjust";values[kCIInputEVKey]=item.amount*2};if let f=CIFilter(name:name,parameters:values),let output=f.outputImage{ci=output.cropped(to:ci.extent)}}
        let context=CIContext(options:nil);guard let result=context.createCGImage(ci,from:ci.extent) else{return image};let rendered=NSImage(cgImage:result,size:image.size)
        if layer.maskEnabled != false,let maskData=layer.maskData,let tiff=rendered.tiffRepresentation,let masked=try? CoverEditorEngine.applyRasterMask(tiff,maskImageData:maskData,density:layer.maskDensity ?? 1,offsetX:layer.maskOffsetX ?? 0,offsetY:layer.maskOffsetY ?? 0){return NSImage(data:masked) ?? rendered}
        return rendered
    }
    private static func applyAdjustment(_ layer:CoverLayer,to context:CGContext,size:NSSize){
        guard let kind=layer.adjustment,let current=context.makeImage() else{return}
        let source=CIImage(cgImage:current), extent=CIImage(cgImage:current).extent
        var name="CIColorControls",parameters:[String:Any]=[kCIInputImageKey:source]
        let v=layer.adjustmentValues ?? [:]
        switch kind {
        case .brightnessContrast:parameters[kCIInputBrightnessKey]=v["brightness"] ?? 0;parameters[kCIInputContrastKey]=v["contrast"] ?? 1
        case .exposure:name="CIExposureAdjust";parameters[kCIInputEVKey]=v["exposure"] ?? 0
        case .levels:name="CIColorCube";parameters["inputCubeDimension"]=32;parameters["inputCubeData"]=levelsCubeData(v)
        case .curves:name="CIToneCurve";parameters.merge(toneCurveParameters(v)){_,new in new}
        case .hueSaturation:parameters[kCIInputSaturationKey]=v["saturation"] ?? 1
        case .vibrance:name="CIVibrance";parameters["inputAmount"]=v["amount"] ?? 0.5
        case .temperatureTint:name="CITemperatureAndTint";parameters["inputNeutral"]=CIVector(x:6500,y:0);parameters["inputTargetNeutral"]=CIVector(x:6500+(v["temperature"] ?? 0)*1500,y:(v["tint"] ?? 0)*100)
        case .colorBalance:name="CIColorMatrix";parameters["inputBiasVector"]=CIVector(x:(v["cyanRed"] ?? 0)*0.5,y:(v["magentaGreen"] ?? 0)*0.5,z:(v["yellowBlue"] ?? 0)*0.5,w:0)
        case .threshold:name="CIColorThreshold";parameters["inputThreshold"]=v["threshold"] ?? 0.5
        case .posterize:name="CIColorPosterize";parameters["inputLevels"]=max(2,min(30,v["levels"] ?? 6))
        case .gradientMap:name="CIFalseColor";parameters["inputColor0"]=adjustmentCIColor(layer.fillHex);parameters["inputColor1"]=adjustmentCIColor(layer.gradientEndHex ?? "#FFFFFF")
        case .channelMixer:name="CIColorMatrix";parameters.merge(channelMixerParameters(v)){_,new in new}
        case .selectiveColor:name="CIColorCube";parameters["inputCubeDimension"]=32;parameters["inputCubeData"]=selectiveColorCubeData(v)
        case .monochrome:name="CIColorCube";parameters["inputCubeDimension"]=32;parameters["inputCubeData"]=blackWhiteCubeData(v,tintHex:layer.fillHex)
        case .invert:name="CIColorInvert"
        case .gaussianBlur:name="CIGaussianBlur";parameters[kCIInputRadiusKey]=v["radius"] ?? 3
        case .sharpen:name="CISharpenLuminance";parameters[kCIInputSharpnessKey]=v["amount"] ?? 0.4
        }
        guard let filter=CIFilter(name:name,parameters:parameters),let output=filter.outputImage,let result=CIContext(options:nil).createCGImage(output.cropped(to:extent),from:extent) else{return}
        context.saveGState();context.setBlendMode(.copy);context.setAlpha(CGFloat(layer.opacity));context.draw(result,in:CGRect(origin:.zero,size:size));context.restoreGState()
    }
    private static func drawGuides(_ p: CoverProject,in size:NSSize) {
        let sx=size.width/p.canvasWidth, sy=size.height/p.canvasHeight
        let trim=NSRect(x:p.bleed*sx,y:p.bleed*sy,width:(p.canvasWidth-2*p.bleed)*sx,height:(p.canvasHeight-2*p.bleed)*sy)
        NSColor.systemRed.withAlphaComponent(0.75).setStroke(); let path=NSBezierPath(); path.lineWidth=0.7; path.appendRect(trim); path.stroke()
        let safePath=NSBezierPath(); safePath.setLineDash([3,3],count:2,phase:0)
        if p.type == .printFullWrap {
            let left=(p.bleed+p.backWidth)*sx; let right=(p.bleed+p.backWidth+p.spineWidth)*sx
            path.move(to:NSPoint(x:left,y:0));path.line(to:NSPoint(x:left,y:size.height));path.move(to:NSPoint(x:right,y:0));path.line(to:NSPoint(x:right,y:size.height));path.stroke()
            for panel in [NSRect(x:p.bleed*sx,y:p.bleed*sy,width:p.backWidth*sx,height:trim.height),NSRect(x:left,y:p.bleed*sy,width:p.spineWidth*sx,height:trim.height),NSRect(x:right,y:p.bleed*sy,width:p.trimWidth*sx,height:trim.height)] { let inset=min(panel.width,panel.height)*0.05; safePath.appendRect(panel.insetBy(dx:inset,dy:inset)) }
            NSColor.systemGreen.withAlphaComponent(0.35).setStroke();let mid=NSBezierPath();mid.move(to:NSPoint(x:trim.midX,y:0));mid.line(to:NSPoint(x:trim.midX,y:size.height));mid.move(to:NSPoint(x:0,y:trim.midY));mid.line(to:NSPoint(x:size.width,y:trim.midY));mid.stroke()
        } else { let inset=min(trim.width,trim.height)*0.05; safePath.appendRect(trim.insetBy(dx:inset,dy:inset)) }
        NSColor.systemBlue.withAlphaComponent(0.65).setStroke(); safePath.stroke()
        if p.gridVisible { NSColor.gray.withAlphaComponent(0.25).setStroke();let grid=NSBezierPath();grid.lineWidth=0.35;for n in 1..<10 { let x=size.width*Double(n)/10;let y=size.height*Double(n)/10;grid.move(to:NSPoint(x:x,y:0));grid.line(to:NSPoint(x:x,y:size.height));grid.move(to:NSPoint(x:0,y:y));grid.line(to:NSPoint(x:size.width,y:y)) };grid.stroke() }
    }
}

extension NSColor {
    convenience init(hex: String) { let v=hex.trimmingCharacters(in:CharacterSet(charactersIn:"#")); let n=UInt64(v,radix:16) ?? 0xFFFFFF; self.init(srgbRed:CGFloat((n>>16)&255)/255,green:CGFloat((n>>8)&255)/255,blue:CGFloat(n&255)/255,alpha:1) }
    var hexRGB:String{let c=usingColorSpace(.sRGB) ?? .black;return String(format:"#%02X%02X%02X",Int((c.redComponent*255).rounded()),Int((c.greenComponent*255).rounded()),Int((c.blueComponent*255).rounded()))}
}
