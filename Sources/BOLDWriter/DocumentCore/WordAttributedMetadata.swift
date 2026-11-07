import AppKit
import Foundation

extension NSAttributedString.Key {
    static let boldWriterInlineImageDisplaySize = NSAttributedString.Key("BOLDWriterInlineImageDisplaySize")
    static let boldWriterStyle = NSAttributedString.Key("com.boldwriter.style")

    static let boldWriterKeepWithNext = NSAttributedString.Key("BOLDWriterKeepWithNext")
    static let boldWriterKeepLinesTogether = NSAttributedString.Key("BOLDWriterKeepLinesTogether")
    static let boldWriterPageBreakBefore = NSAttributedString.Key("BOLDWriterPageBreakBefore")
    static let boldWriterWidowControl = NSAttributedString.Key("BOLDWriterWidowControl")
    static let boldWriterParagraphBorders = NSAttributedString.Key("BOLDWriterParagraphBorders")
    static let boldWriterParagraphShading = NSAttributedString.Key("BOLDWriterParagraphShading")
    static let boldWriterSmallCaps = NSAttributedString.Key("BOLDWriterSmallCaps")
    static let boldWriterHiddenText = NSAttributedString.Key("BOLDWriterHiddenText")
    static let boldWriterOutlineText = NSAttributedString.Key("BOLDWriterOutlineText")
    static let boldWriterShadowText = NSAttributedString.Key("BOLDWriterShadowText")
    static let boldWriterEmbossText = NSAttributedString.Key("BOLDWriterEmbossText")
    static let boldWriterImprintText = NSAttributedString.Key("BOLDWriterImprintText")
    static let boldWriterDoubleStrikethrough = NSAttributedString.Key("BOLDWriterDoubleStrikethrough")
    static let boldWriterAllCaps = NSAttributedString.Key("BOLDWriterAllCaps")
    static let boldWriterCharacterScale = NSAttributedString.Key("BOLDWriterCharacterScale")
    static let boldWriterUnderlineVariant = NSAttributedString.Key("BOLDWriterUnderlineVariant")
    static let boldWriterLanguage = NSAttributedString.Key("BOLDWriterLanguage")
    static let boldWriterWordLanguage = NSAttributedString.Key("BOLDWriterWordLanguage")
    static let boldWriterComplexScript = NSAttributedString.Key("BOLDWriterComplexScript")
    static let boldWriterKernThreshold = NSAttributedString.Key("BOLDWriterKernThreshold")
    static let boldWriterEmphasis = NSAttributedString.Key("BOLDWriterEmphasis")
    static let boldWriterSpecVanish = NSAttributedString.Key("BOLDWriterSpecVanish")
    static let boldWriterWebHidden = NSAttributedString.Key("BOLDWriterWebHidden")
    static let boldWriterRunBorder = NSAttributedString.Key("BOLDWriterRunBorder")
    static let boldWriterRunShading = NSAttributedString.Key("BOLDWriterRunShading")
    static let boldWriterHighlight = NSAttributedString.Key("BOLDWriterHighlight")
    static let boldWriterField = NSAttributedString.Key("BOLDWriterField")
    static let boldWriterWordPictureCrop = NSAttributedString.Key("BOLDWriterWordPictureCrop")
    static let boldWriterWordPictureAltText = NSAttributedString.Key("BOLDWriterWordPictureAltText")
    static let boldWriterWordVMLShape = NSAttributedString.Key("BOLDWriterWordVMLShape")
    static let boldWriterWordOpaqueDrawing = NSAttributedString.Key("BOLDWriterWordOpaqueDrawing")
    static let boldWriterParagraphBidi = NSAttributedString.Key("BOLDWriterParagraphBidi")
    static let boldWriterChecklist = NSAttributedString.Key("BOLDWriterChecklist")
    static let boldWriterChecklistChecked = NSAttributedString.Key("BOLDWriterChecklistChecked")
    static let boldWriterTextDirection = NSAttributedString.Key("BOLDWriterTextDirection")
    static let boldWriterContextualSpacing = NSAttributedString.Key("BOLDWriterContextualSpacing")
    static let boldWriterSuppressLineNumbers = NSAttributedString.Key("BOLDWriterSuppressLineNumbers")
    static let boldWriterMirrorIndents = NSAttributedString.Key("BOLDWriterMirrorIndents")
    static let boldWriterNoProof = NSAttributedString.Key("BOLDWriterNoProof")
    static let boldWriterRTL = NSAttributedString.Key("BOLDWriterRTL")
    static let boldWriterComplexScriptBold = NSAttributedString.Key("BOLDWriterComplexScriptBold")
    static let boldWriterComplexScriptItalic = NSAttributedString.Key("BOLDWriterComplexScriptItalic")
    static let boldWriterComplexScriptSize = NSAttributedString.Key("BOLDWriterComplexScriptSize")
    static let boldWriterRunFonts = NSAttributedString.Key("BOLDWriterRunFonts")
    static let boldWriterCharacterStyle = NSAttributedString.Key("BOLDWriterCharacterStyle")
    static let boldWriterParagraphStyle = NSAttributedString.Key("BOLDWriterParagraphStyle")
}

/// Word's distinct image title and description, retained across native saves.
final class WordPictureAltText: NSObject, NSCopying {
    let title: String
    let alternativeDescription: String

    init(title: String, alternativeDescription: String) {
        self.title = title
        self.alternativeDescription = alternativeDescription
        super.init()
    }

    func copy(with zone: NSZone? = nil) -> Any {
        WordPictureAltText(title: title, alternativeDescription: alternativeDescription)
    }
}


final class WordPictureCrop:
    NSObject,
    NSCopying
{
    let left: Int
    let top: Int
    let right: Int
    let bottom: Int

    init(
        left: Int = 0,
        top: Int = 0,
        right: Int = 0,
        bottom: Int = 0
    ) {
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom
        super.init()
    }

    func copy(
        with zone: NSZone? = nil
    ) -> Any {
        WordPictureCrop(
            left: left,
            top: top,
            right: right,
            bottom: bottom
        )
    }

    static func validEdge(
        _ value: Int
    ) -> Bool {
        (0...100_000).contains(value)
    }

    var isEmpty: Bool {
        left == 0
            && top == 0
            && right == 0
            && bottom == 0
    }

    var hasValidGeometry: Bool {
        Self.validEdge(left)
            && Self.validEdge(top)
            && Self.validEdge(right)
            && Self.validEdge(bottom)
            && left + right < 100_000
            && top + bottom < 100_000
    }

    override func isEqual(
        _ object: Any?
    ) -> Bool {
        guard
            let other = object as? WordPictureCrop
        else {
            return false
        }

        return left == other.left
            && top == other.top
            && right == other.right
            && bottom == other.bottom
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(left)
        hasher.combine(top)
        hasher.combine(right)
        hasher.combine(bottom)
        return hasher.finalize()
    }
}

final class WordStyleDependency: NSObject, NSCopying {
    enum Kind: String {
        case paragraph
        case character
    }

    let kind: Kind
    let styleID: String
    let name: String?
    let basedOn: String?
    let linkedStyleID: String?
    let nextStyleID: String?

    init(
        kind: Kind,
        styleID: String,
        name: String? = nil,
        basedOn: String? = nil,
        linkedStyleID: String? = nil,
        nextStyleID: String? = nil
    ) {
        self.kind = kind
        self.styleID = styleID
        self.name = name
        self.basedOn = basedOn
        self.linkedStyleID = linkedStyleID
        self.nextStyleID = nextStyleID
        super.init()
    }

    func copy(
        with zone: NSZone? = nil
    ) -> Any {
        WordStyleDependency(
            kind: kind,
            styleID: styleID,
            name: name,
            basedOn: basedOn,
            linkedStyleID: linkedStyleID,
            nextStyleID: nextStyleID
        )
    }

    override func isEqual(
        _ object: Any?
    ) -> Bool {
        guard
            let other =
                object as? WordStyleDependency
        else {
            return false
        }

        return kind == other.kind
            && styleID == other.styleID
            && name == other.name
            && basedOn == other.basedOn
            && linkedStyleID == other.linkedStyleID
            && nextStyleID == other.nextStyleID
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(kind.rawValue)
        hasher.combine(styleID)
        hasher.combine(name)
        hasher.combine(basedOn)
        hasher.combine(linkedStyleID)
        hasher.combine(nextStyleID)
        return hasher.finalize()
    }
}

final class WordParagraphStyle: NSObject, NSCopying {
    let styleID: String
    let name: String?
    let basedOn: String?
    let linkedStyleID: String?
    let nextStyleID: String?
    let dependencies: [WordStyleDependency]

    init(
        styleID: String,
        name: String? = nil,
        basedOn: String? = nil,
        linkedStyleID: String? = nil,
        nextStyleID: String? = nil,
        dependencies: [WordStyleDependency] = []
    ) {
        self.styleID = styleID
        self.name = name
        self.basedOn = basedOn
        self.linkedStyleID = linkedStyleID
        self.nextStyleID = nextStyleID
        self.dependencies = dependencies
        super.init()
    }

    func copy(
        with zone: NSZone? = nil
    ) -> Any {
        WordParagraphStyle(
            styleID: styleID,
            name: name,
            basedOn: basedOn,
            linkedStyleID: linkedStyleID,
            nextStyleID: nextStyleID,
            dependencies: dependencies.map {
                ($0.copy() as? WordStyleDependency) ?? $0
            }
        )
    }

    override func isEqual(
        _ object: Any?
    ) -> Bool {
        guard
            let other =
                object as? WordParagraphStyle
        else {
            return false
        }

        return styleID == other.styleID
            && name == other.name
            && basedOn == other.basedOn
            && linkedStyleID == other.linkedStyleID
            && nextStyleID == other.nextStyleID
            && dependencies == other.dependencies
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(styleID)
        hasher.combine(name)
        hasher.combine(basedOn)
        hasher.combine(linkedStyleID)
        hasher.combine(nextStyleID)
        dependencies.forEach {
            hasher.combine($0)
        }
        return hasher.finalize()
    }
}

final class WordCharacterStyle: NSObject, NSCopying {
    let styleID: String
    let name: String?
    let basedOn: String?
    let linkedStyleID: String?
    let dependencies: [WordStyleDependency]

    init(
        styleID: String,
        name: String? = nil,
        basedOn: String? = nil,
        linkedStyleID: String? = nil,
        dependencies: [WordStyleDependency] = []
    ) {
        self.styleID = styleID
        self.name = name
        self.basedOn = basedOn
        self.linkedStyleID = linkedStyleID
        self.dependencies = dependencies
        super.init()
    }

    func copy(
        with zone: NSZone? = nil
    ) -> Any {
        WordCharacterStyle(
            styleID: styleID,
            name: name,
            basedOn: basedOn,
            linkedStyleID: linkedStyleID,
            dependencies: dependencies.map {
                ($0.copy() as? WordStyleDependency) ?? $0
            }
        )
    }

    override func isEqual(
        _ object: Any?
    ) -> Bool {
        guard
            let other =
                object as? WordCharacterStyle
        else {
            return false
        }

        return styleID == other.styleID
            && name == other.name
            && basedOn == other.basedOn
            && linkedStyleID == other.linkedStyleID
            && dependencies == other.dependencies
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(styleID)
        hasher.combine(name)
        hasher.combine(basedOn)
        hasher.combine(linkedStyleID)
        dependencies.forEach {
            hasher.combine($0)
        }
        return hasher.finalize()
    }
}

final class WordField: NSObject, NSCopying {
    enum Kind: String, Codable {
        case simple
        case complex
    }

    let id: UUID
    let kind: Kind
    let instruction: String
    let dirtyValue: String?
    let lockedValue: String?

    init(
        id: UUID = UUID(),
        kind: Kind,
        instruction: String,
        dirtyValue: String? = nil,
        lockedValue: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.instruction = instruction
        self.dirtyValue = dirtyValue
        self.lockedValue = lockedValue
        super.init()
    }

    func copy(
        with zone: NSZone? = nil
    ) -> Any {
        WordField(
            id: id,
            kind: kind,
            instruction: instruction,
            dirtyValue: dirtyValue,
            lockedValue: lockedValue
        )
    }

    override func isEqual(
        _ object: Any?
    ) -> Bool {
        guard
            let other =
                object as? WordField
        else {
            return false
        }

        return id == other.id
            && kind == other.kind
            && instruction == other.instruction
            && dirtyValue == other.dirtyValue
            && lockedValue == other.lockedValue
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(id)
        hasher.combine(kind.rawValue)
        hasher.combine(instruction)
        hasher.combine(dirtyValue)
        hasher.combine(lockedValue)
        return hasher.finalize()
    }
}

final class WordLanguage: NSObject, NSCopying {
    let value: String?
    let eastAsia: String?
    let bidi: String?

    init(
        value: String? = nil,
        eastAsia: String? = nil,
        bidi: String? = nil
    ) {
        self.value = value
        self.eastAsia = eastAsia
        self.bidi = bidi
        super.init()
    }

    func copy(
        with zone: NSZone? = nil
    ) -> Any {
        WordLanguage(
            value: value,
            eastAsia: eastAsia,
            bidi: bidi
        )
    }

    override func isEqual(
        _ object: Any?
    ) -> Bool {
        guard
            let other =
                object as? WordLanguage
        else {
            return false
        }

        return value == other.value
            && eastAsia == other.eastAsia
            && bidi == other.bidi
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(value)
        hasher.combine(eastAsia)
        hasher.combine(bidi)
        return hasher.finalize()
    }

    var hasExtendedMetadata: Bool {
        eastAsia != nil
            || bidi != nil
    }
}

final class WordRunFonts: NSObject, NSCopying {
    let ascii: String?
    let hAnsi: String?
    let eastAsia: String?
    let complexScript: String?
    let asciiTheme: String?
    let hAnsiTheme: String?
    let eastAsiaTheme: String?
    let complexScriptTheme: String?
    let hint: String?

    init(
        ascii: String? = nil,
        hAnsi: String? = nil,
        eastAsia: String? = nil,
        complexScript: String? = nil,
        asciiTheme: String? = nil,
        hAnsiTheme: String? = nil,
        eastAsiaTheme: String? = nil,
        complexScriptTheme: String? = nil,
        hint: String? = nil
    ) {
        self.ascii = ascii
        self.hAnsi = hAnsi
        self.eastAsia = eastAsia
        self.complexScript = complexScript
        self.asciiTheme = asciiTheme
        self.hAnsiTheme = hAnsiTheme
        self.eastAsiaTheme = eastAsiaTheme
        self.complexScriptTheme = complexScriptTheme
        self.hint = hint
        super.init()
    }

    func copy(
        with zone: NSZone? = nil
    ) -> Any {
        WordRunFonts(
            ascii: ascii,
            hAnsi: hAnsi,
            eastAsia: eastAsia,
            complexScript: complexScript,
            asciiTheme: asciiTheme,
            hAnsiTheme: hAnsiTheme,
            eastAsiaTheme: eastAsiaTheme,
            complexScriptTheme: complexScriptTheme,
            hint: hint
        )
    }

    override func isEqual(
        _ object: Any?
    ) -> Bool {
        guard
            let other =
                object as? WordRunFonts
        else {
            return false
        }

        return ascii == other.ascii
            && hAnsi == other.hAnsi
            && eastAsia == other.eastAsia
            && complexScript == other.complexScript
            && asciiTheme == other.asciiTheme
            && hAnsiTheme == other.hAnsiTheme
            && eastAsiaTheme == other.eastAsiaTheme
            && complexScriptTheme == other.complexScriptTheme
            && hint == other.hint
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(ascii)
        hasher.combine(hAnsi)
        hasher.combine(eastAsia)
        hasher.combine(complexScript)
        hasher.combine(asciiTheme)
        hasher.combine(hAnsiTheme)
        hasher.combine(eastAsiaTheme)
        hasher.combine(complexScriptTheme)
        hasher.combine(hint)
        return hasher.finalize()
    }

    var hasExtendedWordMetadata: Bool {
        eastAsia != nil
            || complexScript != nil
            || asciiTheme != nil
            || hAnsiTheme != nil
            || eastAsiaTheme != nil
            || complexScriptTheme != nil
            || hint != nil
    }
}

final class WordRunBorder: NSObject, NSCopying {
    let style: String
    let size: Int?
    let space: Int?
    let color: String?
    let themeColor: String?
    let themeTint: String?
    let themeShade: String?

    init(
        style: String,
        size: Int?,
        space: Int?,
        color: String?,
        themeColor: String? = nil,
        themeTint: String? = nil,
        themeShade: String? = nil
    ) {
        self.style = style
        self.size = size
        self.space = space
        self.color = color
        self.themeColor = themeColor
        self.themeTint = themeTint
        self.themeShade = themeShade
        super.init()
    }

    func copy(
        with zone: NSZone? = nil
    ) -> Any {
        WordRunBorder(
            style: style,
            size: size,
            space: space,
            color: color,
            themeColor: themeColor,
            themeTint: themeTint,
            themeShade: themeShade
        )
    }

    override func isEqual(
        _ object: Any?
    ) -> Bool {
        guard
            let other =
                object as? WordRunBorder
        else {
            return false
        }

        return style.lowercased() == other.style.lowercased()
            && size == other.size
            && space == other.space
            && color?.lowercased() == other.color?.lowercased()
            && themeColor?.lowercased() == other.themeColor?.lowercased()
            && themeTint?.lowercased() == other.themeTint?.lowercased()
            && themeShade?.lowercased() == other.themeShade?.lowercased()
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(style.lowercased())
        hasher.combine(size)
        hasher.combine(space)
        hasher.combine(color?.lowercased())
        hasher.combine(themeColor?.lowercased())
        hasher.combine(themeTint?.lowercased())
        hasher.combine(themeShade?.lowercased())
        return hasher.finalize()
    }
}

final class WordRunShading: NSObject, NSCopying {
    let value: String
    let color: String?
    let fill: String?
    let themeColor: String?
    let themeTint: String?
    let themeShade: String?
    let themeFill: String?
    let themeFillTint: String?
    let themeFillShade: String?

    init(
        value: String,
        color: String?,
        fill: String?,
        themeColor: String? = nil,
        themeTint: String? = nil,
        themeShade: String? = nil,
        themeFill: String? = nil,
        themeFillTint: String? = nil,
        themeFillShade: String? = nil
    ) {
        self.value = value
        self.color = color
        self.fill = fill
        self.themeColor = themeColor
        self.themeTint = themeTint
        self.themeShade = themeShade
        self.themeFill = themeFill
        self.themeFillTint = themeFillTint
        self.themeFillShade = themeFillShade
        super.init()
    }

    func copy(
        with zone: NSZone? = nil
    ) -> Any {
        WordRunShading(
            value: value,
            color: color,
            fill: fill,
            themeColor: themeColor,
            themeTint: themeTint,
            themeShade: themeShade,
            themeFill: themeFill,
            themeFillTint: themeFillTint,
            themeFillShade: themeFillShade
        )
    }

    override func isEqual(
        _ object: Any?
    ) -> Bool {
        guard
            let other =
                object as? WordRunShading
        else {
            return false
        }

        return value.lowercased() == other.value.lowercased()
            && color?.lowercased() == other.color?.lowercased()
            && fill?.lowercased() == other.fill?.lowercased()
            && themeColor?.lowercased() == other.themeColor?.lowercased()
            && themeTint?.lowercased() == other.themeTint?.lowercased()
            && themeShade?.lowercased() == other.themeShade?.lowercased()
            && themeFill?.lowercased() == other.themeFill?.lowercased()
            && themeFillTint?.lowercased() == other.themeFillTint?.lowercased()
            && themeFillShade?.lowercased() == other.themeFillShade?.lowercased()
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(value.lowercased())
        hasher.combine(color?.lowercased())
        hasher.combine(fill?.lowercased())
        hasher.combine(themeColor?.lowercased())
        hasher.combine(themeTint?.lowercased())
        hasher.combine(themeShade?.lowercased())
        hasher.combine(themeFill?.lowercased())
        hasher.combine(themeFillTint?.lowercased())
        hasher.combine(themeFillShade?.lowercased())
        return hasher.finalize()
    }
}

final class WordParagraphBorder: NSObject, NSCopying {
    let style: String
    let size: Int?
    let space: Int?
    let color: String?

    init(
        style: String,
        size: Int?,
        space: Int?,
        color: String?
    ) {
        self.style = style
        self.size = size
        self.space = space
        self.color = color
        super.init()
    }

    func copy(
        with zone: NSZone? = nil
    ) -> Any {
        WordParagraphBorder(
            style:
                style,
            size:
                size,
            space:
                space,
            color:
                color
        )
    }

    override func isEqual(
        _ object: Any?
    ) -> Bool {
        guard
            let other =
                object as? WordParagraphBorder
        else {
            return false
        }

        return style == other.style
            && size == other.size
            && space == other.space
            && color == other.color
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(style)
        hasher.combine(size)
        hasher.combine(space)
        hasher.combine(color)
        return hasher.finalize()
    }
}

final class WordParagraphShading: NSObject, NSCopying {
    let value: String
    let color: String?
    let fill: String?

    init(
        value: String,
        color: String?,
        fill: String?
    ) {
        self.value = value
        self.color = color
        self.fill = fill
        super.init()
    }

    func copy(
        with zone: NSZone? = nil
    ) -> Any {
        WordParagraphShading(
            value:
                value,
            color:
                color,
            fill:
                fill
        )
    }

    override func isEqual(
        _ object: Any?
    ) -> Bool {
        guard
            let other =
                object as? WordParagraphShading
        else {
            return false
        }

        return value.lowercased()
                == other.value.lowercased()
            && color?.lowercased()
                == other.color?.lowercased()
            && fill?.lowercased()
                == other.fill?.lowercased()
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(value.lowercased())
        hasher.combine(color?.lowercased())
        hasher.combine(fill?.lowercased())
        return hasher.finalize()
    }
}

final class WordParagraphBorders: NSObject, NSCopying {
    let top: WordParagraphBorder?
    let left: WordParagraphBorder?
    let bottom: WordParagraphBorder?
    let right: WordParagraphBorder?
    let between: WordParagraphBorder?

    init(
        top: WordParagraphBorder? = nil,
        left: WordParagraphBorder? = nil,
        bottom: WordParagraphBorder? = nil,
        right: WordParagraphBorder? = nil,
        between: WordParagraphBorder? = nil
    ) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
        self.between = between
        super.init()
    }

    var isEmpty: Bool {
        top == nil
            && left == nil
            && bottom == nil
            && right == nil
            && between == nil
    }

    func copy(
        with zone: NSZone? = nil
    ) -> Any {
        WordParagraphBorders(
            top:
                top?.copy(
                    with:
                        zone
                ) as? WordParagraphBorder,
            left:
                left?.copy(
                    with:
                        zone
                ) as? WordParagraphBorder,
            bottom:
                bottom?.copy(
                    with:
                        zone
                ) as? WordParagraphBorder,
            right:
                right?.copy(
                    with:
                        zone
                ) as? WordParagraphBorder,
            between:
                between?.copy(
                    with:
                        zone
                ) as? WordParagraphBorder
        )
    }

    override func isEqual(
        _ object: Any?
    ) -> Bool {
        guard
            let other =
                object as? WordParagraphBorders
        else {
            return false
        }

        return top == other.top
            && left == other.left
            && bottom == other.bottom
            && right == other.right
            && between == other.between
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(top)
        hasher.combine(left)
        hasher.combine(bottom)
        hasher.combine(right)
        hasher.combine(between)
        return hasher.finalize()
    }
}


struct WordOpaqueRelationship: Codable, Equatable {
    let id: String
    let type: String
    let targetPath: String
}

struct WordOpaquePart: Codable, Equatable {
    let path: String
    let contentType: String
    let data: Data
    let relationships: [WordOpaqueRelationship]
}

/// A Word drawing that the native canvas cannot edit. The original element and
/// bounded internal package dependency closure are retained for DOCX export.
final class WordOpaqueDrawing: NSObject, NSCopying {
    static let markerText = "[Word drawing preserved for DOCX export]"
    let id: UUID
    let xml: String
    let isRunChild: Bool
    let relationships: [WordOpaqueRelationship]
    let parts: [WordOpaquePart]

    init(id: UUID = UUID(), xml: String, isRunChild: Bool,
         relationships: [WordOpaqueRelationship] = [], parts: [WordOpaquePart] = []) {
        self.id = id
        self.xml = xml
        self.isRunChild = isRunChild
        self.relationships = relationships
        self.parts = parts
        super.init()
    }

    static func validated(id: UUID = UUID(), xml: String, isRunChild: Bool,
                          relationships: [WordOpaqueRelationship] = [],
                          parts: [WordOpaquePart] = []) throws -> WordOpaqueDrawing {
        guard xml.utf8.count <= 262_144,
              !xml.contains("<!DOCTYPE"), !xml.contains("<!ENTITY") else {
            throw WriterError.message("An unsupported Word drawing exceeds the safe preservation limit or contains an XML entity.")
        }
        let document = try XMLDocument(xmlString: xml, options: [.nodeLoadExternalEntitiesNever])
        let relationshipNamespace = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
        var referencedIDs: [String] = []
        for node in try document.nodes(forXPath: "//*") {
            guard let element = node as? XMLElement else { continue }
            for attribute in element.attributes ?? [] {
                if attribute.uri == relationshipNamespace || (attribute.name ?? "").hasPrefix("r:")
                    || attribute.localName == "relid" && attribute.uri == "urn:schemas-microsoft-com:office:office" {
                    if let value = attribute.stringValue { referencedIDs.append(value) }
                }
            }
        }
        let partPaths = Set(parts.map(\.path))
        let allRelationships = relationships + parts.flatMap(\.relationships)
        let safePath: (String) -> Bool = { path in
            !path.isEmpty && path.utf8.count <= 512
                && DOCXPackage.target(path, relativeTo: "") == path
                && path != "[Content_Types].xml" && !path.hasSuffix(".rels")
        }
        let safeField: (String) -> Bool = { value in
            !value.isEmpty && value.utf8.count <= 512
                && !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
                && !value.contains("\"") && !value.contains("<") && !value.contains(">")
        }
        guard let name = document.rootElement()?.localName,
              ["drawing", "pict", "AlternateContent"].contains(name),
              Set(referencedIDs) == Set(relationships.map(\.id)),
              relationships.count <= 64, parts.count <= 64,
              parts.reduce(0, { $0 + $1.data.count }) <= 8 * 1024 * 1024,
              allRelationships.count <= 128,
              Set(parts.map(\.path)).count == parts.count,
              Set(relationships.map(\.id)).count == relationships.count,
              parts.allSatisfy({ safePath($0.path) && safeField($0.contentType)
                  && Set($0.relationships.map(\.id)).count == $0.relationships.count }),
              allRelationships.allSatisfy({ safeField($0.id) && safeField($0.type)
                  && safePath($0.targetPath) && partPaths.contains($0.targetPath) }) else {
            throw WriterError.message("An unsupported Word drawing has missing, unsafe, or oversized package dependencies. Import or export stopped rather than losing artwork.")
        }
        return WordOpaqueDrawing(id: id, xml: xml, isRunChild: isRunChild,
                                 relationships: relationships, parts: parts)
    }

    func copy(with zone: NSZone? = nil) -> Any {
        WordOpaqueDrawing(id: id, xml: xml, isRunChild: isRunChild,
                          relationships: relationships, parts: parts)
    }
}

final class WordVMLShape:
    NSObject,
    NSCopying
{
    let shapeKind: String
    let shapeID: String?
    let style: String?
    let fillColor: String?
    let strokeColor: String?
    let strokeWeight: String?
    let textBoxInset: String?

    init(
        shapeKind: String,
        shapeID: String? = nil,
        style: String? = nil,
        fillColor: String? = nil,
        strokeColor: String? = nil,
        strokeWeight: String? = nil,
        textBoxInset: String? = nil
    ) {
        self.shapeKind = shapeKind
        self.shapeID = shapeID
        self.style = style
        self.fillColor = fillColor
        self.strokeColor = strokeColor
        self.strokeWeight = strokeWeight
        self.textBoxInset = textBoxInset
        super.init()
    }

    var isSupportedTextShape: Bool {
        ["rect", "roundrect", "oval"]
            .contains(shapeKind.lowercased())
    }

    func copy(
        with zone: NSZone? = nil
    ) -> Any {
        WordVMLShape(
            shapeKind: shapeKind,
            shapeID: shapeID,
            style: style,
            fillColor: fillColor,
            strokeColor: strokeColor,
            strokeWeight: strokeWeight,
            textBoxInset: textBoxInset
        )
    }
}
