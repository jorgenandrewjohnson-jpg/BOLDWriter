import AppKit
import Combine
import SwiftUI

enum FormattingPresence: Equatable {
    case off
    case on
    case mixed

    init(_ values: [Bool]) {
        if values.allSatisfy({ $0 }) { self = .on }
        else if values.allSatisfy({ !$0 }) { self = .off }
        else { self = .mixed }
    }
}

private struct FormattingSample<Value> {
    private(set) var firstValue: Value?
    private(set) var isMixed = false
    private var hasValue = false

    mutating func observe(
        _ value: Value,
        equal: (Value, Value) -> Bool
    ) {
        guard hasValue else {
            firstValue = value
            hasValue = true
            return
        }
        guard let previousValue = firstValue else { return }
        if !equal(previousValue, value) { isMixed = true }
    }

    var uniformValue: Value? { isMixed ? nil : firstValue }

}

private extension FormattingSample where Value == Bool {
    var presence: FormattingPresence {
        guard let value = uniformValue else { return isMixed ? .mixed : .off }
        return value ? .on : .off
    }
}

@MainActor
struct EditorFormattingState: Equatable {
    var bold: FormattingPresence = .off
    var italic: FormattingPresence = .off
    var underline: FormattingPresence = .off
    var bulletList: FormattingPresence = .off
    var numberedList: FormattingPresence = .off
    var checklist: FormattingPresence = .off
    var checklistChecked: FormattingPresence = .off
    var fontFamily: String?
    var styleName: String?
    var fontSize: Double?
    var textColor: NSColor?
    var highlightColor: NSColor?
    var alignment: NSTextAlignment?
    var textDirection: NSWritingDirection?
    var lineSpacing: Double?
    var textColorIsMixed = false
    var highlightIsMixed = false
    var canUndo = false
    var canRedo = false

    static func read(from view: NSTextView, selection: NSRange) -> Self {
        var state = Self()
        state.canUndo = view.undoManager?.canUndo == true
        state.canRedo = view.undoManager?.canRedo == true
        var hasSample = false
        var bold = FormattingSample<Bool>()
        var italic = FormattingSample<Bool>()
        var underline = FormattingSample<Bool>()
        var checklist = FormattingSample<Bool>()
        var checklistChecked = FormattingSample<Bool>()
        var bulletList = FormattingSample<Bool>()
        var numberedList = FormattingSample<Bool>()
        var fontFamily = FormattingSample<String?>()
        var styleName = FormattingSample<String>()
        var fontSize = FormattingSample<Double?>()
        var textColor = FormattingSample<NSColor?>()
        var highlightColor = FormattingSample<NSColor?>()
        var alignment = FormattingSample<NSTextAlignment>()
        var textDirection = FormattingSample<NSWritingDirection>()
        var lineSpacing = FormattingSample<Double>()

        let consume: ([NSAttributedString.Key: Any]) -> Void = { attributes in
            let font = attributes[.font] as? NSFont
            let paragraph = attributes[.paragraphStyle] as? NSParagraphStyle
            let traits = font.map(NSFontManager.shared.traits(of:)) ?? []
            let isChecklist = (attributes[.boldWriterChecklist] as? Bool) == true
            let list = paragraph?.textLists.last
            let direction: NSWritingDirection
            if let bidi = attributes[.boldWriterParagraphBidi] as? Bool {
                direction = bidi ? .rightToLeft : .leftToRight
            } else {
                direction = paragraph?.baseWritingDirection ?? .natural
            }

            hasSample = true
            bold.observe(traits.contains(.boldFontMask), equal: ==)
            italic.observe(traits.contains(.italicFontMask), equal: ==)
            underline.observe((attributes[.underlineStyle] as? Int ?? 0) != 0, equal: ==)
            checklist.observe(isChecklist, equal: ==)
            checklistChecked.observe((attributes[.boldWriterChecklistChecked] as? Bool) == true, equal: ==)
            bulletList.observe(!isChecklist && list?.isOrdered == false, equal: ==)
            numberedList.observe(!isChecklist && list?.isOrdered == true, equal: ==)
            fontFamily.observe(font?.familyName ?? font?.fontName, equal: ==)
            styleName.observe(
                (attributes[.boldWriterParagraphStyle] as? WordParagraphStyle)?.name
                    ?? (attributes[.boldWriterStyle] as? String)
                    ?? "Normal",
                equal: ==
            )
            fontSize.observe(font.map { Double($0.pointSize) }, equal: ==)
            textColor.observe(attributes[.foregroundColor] as? NSColor, equal: sameColor)
            highlightColor.observe(attributes[.backgroundColor] as? NSColor, equal: sameColor)
            alignment.observe(paragraph?.alignment ?? .natural, equal: ==)
            textDirection.observe(direction, equal: ==)
            lineSpacing.observe(Double(paragraph?.lineHeightMultiple ?? 1), equal: ==)
        }

        if selection.length == 0 {
            consume(view.typingAttributes)
        } else if let storage = view.textStorage,
                  selection.location != NSNotFound,
                  selection.location <= storage.length {
            let safeLength = min(selection.length, storage.length - selection.location)
            if safeLength > 0 {
                storage.enumerateAttributes(in: NSRange(location: selection.location, length: safeLength)) {
                    attributes, _, _ in consume(attributes)
                }
            }
        }
        guard hasSample else { return state }

        state.bold = bold.presence
        state.italic = italic.presence
        state.underline = underline.presence
        state.checklist = checklist.presence
        state.checklistChecked = checklistChecked.presence
        state.bulletList = bulletList.presence
        state.numberedList = numberedList.presence
        state.fontFamily = fontFamily.uniformValue ?? nil
        state.styleName = styleName.uniformValue
        state.fontSize = fontSize.uniformValue ?? nil
        state.textColorIsMixed = textColor.isMixed
        state.textColor = textColor.uniformValue ?? nil
        state.highlightIsMixed = highlightColor.isMixed
        state.highlightColor = highlightColor.uniformValue ?? nil
        state.alignment = alignment.uniformValue
        state.textDirection = textDirection.uniformValue
        state.lineSpacing = lineSpacing.uniformValue
        return state
    }

    private static func sameColor(_ lhs: NSColor?, _ rhs: NSColor?) -> Bool {
        if lhs == nil || rhs == nil { return lhs == nil && rhs == nil }
        return lhs!.isEqual(rhs!)
    }
}

@MainActor
final class EditorController: ObservableObject {
    @Published var editingFootnote: Footnote?
    @Published var editingEndnote: Endnote?
    weak var textView: NSTextView?
    weak var document: BOLDWriterDocument?
    @Published var selection = NSRange(location: 0, length: 0)
    @Published var selectedReviewChangeID: UUID?
    @Published var selectedCommentID: UUID?
    @Published var selectedFloatingImageID: UUID?
    @Published var fontSize: Double = 15
    @Published var fontFamily: String = NSFont.systemFont(ofSize: 15).familyName ?? "System"
    @Published var textColor: NSColor = .labelColor
    @Published var selectedStyle: WriterStyle = .normal
    @Published var selectedNamedStyleName: String = "Normal"
    @Published private(set) var formatting = EditorFormattingState()
    @Published var namedStyleDefinitions: [NamedStyleDefinition] = NamedStyleDefinition.builtIns

    var trackChangesProvider:
        (@MainActor () -> Bool)?
    @Published var firstLineIndentInches: Double = 0
    @Published var hangingIndentInches: Double = 0
    @Published var paragraphSpacingBefore: Double = 0
    @Published var paragraphSpacingAfter: Double = 0
    @Published var lineHeightMultiple: Double = 1
    @Published var exactLineSpacing: Double = 0
    @Published var zoom: Double = 1

    @discardableResult
    func setZoomPercent(_ percent: Int) -> Bool {
        guard (50...200).contains(percent) else { return false }
        zoom = Double(percent) / 100
        return true
    }

    func attach(_ textView: NSTextView) { self.textView = textView; updateSelection(textView.selectedRange()) }

    private func publishIfChanged<Value: Equatable>(_ key: ReferenceWritableKeyPath<EditorController, Value>, _ value: Value) {
        if self[keyPath: key] != value { self[keyPath: key] = value }
    }

    func updateSelection(_ range: NSRange) {
        publishIfChanged(\.selection, range)
        refreshFormattingState()
        guard let textView, let storage = textView.textStorage, storage.length > 0 else { return }
        let point = min(range.location, storage.length - 1)
        if let font = storage.attribute(.font, at: point, effectiveRange: nil) as? NSFont {
            publishIfChanged(\.fontSize, font.pointSize)
            publishIfChanged(\.fontFamily, font.familyName ?? font.fontName)
        }
        if let color = storage.attribute(.foregroundColor, at: point, effectiveRange: nil) as? NSColor {
            publishIfChanged(\.textColor, color)
        }
        let paragraph = storage.attribute(.paragraphStyle, at: point, effectiveRange: nil) as? NSParagraphStyle
        let relativeFirst = (paragraph?.firstLineHeadIndent ?? 0) - (paragraph?.headIndent ?? 0)
        publishIfChanged(\.firstLineIndentInches, Double(max(0, relativeFirst)/72))
        publishIfChanged(\.hangingIndentInches, Double(max(0, -relativeFirst)/72))
        publishIfChanged(\.paragraphSpacingBefore, Double(paragraph?.paragraphSpacingBefore ?? 0))
        publishIfChanged(\.paragraphSpacingAfter, Double(paragraph?.paragraphSpacing ?? 0))
        let multiple = paragraph?.lineHeightMultiple ?? 0
        publishIfChanged(\.lineHeightMultiple, multiple > 0 ? Double(multiple) : 1)
        let exact = paragraph.map { $0.minimumLineHeight > 0 && abs($0.minimumLineHeight-$0.maximumLineHeight) < 0.01 ? Double($0.minimumLineHeight) : 0 } ?? 0
        publishIfChanged(\.exactLineSpacing, exact)
        let raw = storage.attribute(.boldWriterStyle, at: point, effectiveRange: nil) as? String
        publishIfChanged(\.selectedStyle, raw.flatMap(WriterStyle.init(rawValue:)) ?? .normal)
        let named = storage.attribute(.boldWriterParagraphStyle, at: point, effectiveRange: nil) as? WordParagraphStyle
        publishIfChanged(\.selectedNamedStyleName, named?.name ?? raw ?? "Normal")
    }

    func refreshFormattingState() {
        let next = textView.map { EditorFormattingState.read(from: $0, selection: $0.selectedRange()) } ?? EditorFormattingState()
        publishIfChanged(\.formatting, next)
    }

    @discardableResult
    func createNamedStyle(name: String, kind: NamedStyleKind = .paragraph, basedOn style: WriterStyle? = nil) -> NamedStyleDefinition? {
        do {
            let definitions = NamedStyles.mergedWithBuiltIns(namedStyleDefinitions)
            let parent = style?.wordStyleID
            let custom = try NamedStyles.create(name: name, kind: kind, basedOn: parent, in: definitions)
            namedStyleDefinitions = definitions + [custom]
            return custom
        } catch {
            return nil
        }
    }

    func applyNamedStyle(_ definition: NamedStyleDefinition) {
        guard let textView else { return }
        namedStyleDefinitions = NamedStyles.mergedWithBuiltIns(namedStyleDefinitions + [definition])
        document?.metadata.namedStyles = namedStyleDefinitions
        if definition.kind == .character {
            let range = textView.selectedRange()
            let resolved = NamedStyles.resolve(definition.styleID, in: namedStyleDefinitions) ?? definition.formatting
            let base = NSFont(name: resolved.fontFamily ?? fontFamily, size: resolved.fontSize ?? fontSize) ?? NSFont.systemFont(ofSize: resolved.fontSize ?? fontSize)
            var font = base
            if resolved.bold == true { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
            if resolved.italic == true { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
            let value = WordCharacterStyle(styleID: definition.styleID, name: definition.name, basedOn: definition.basedOn, linkedStyleID: definition.linkedStyleID)
            var attributes: [NSAttributedString.Key: Any] = [.boldWriterCharacterStyle: value, .font: font]
            if resolved.underline == true { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            if range.length == 0 { attributes.forEach { textView.typingAttributes[$0.key] = $0.value } }
            else { performUndoableMutation("Apply \(definition.name)") { $0.textStorage?.addAttributes(attributes, range: range) } }
            return
        }
        textView.typingAttributes.removeValue(forKey: .boldWriterStyle)
        let range = paragraphRange(in: textView)
        let value = WordParagraphStyle(styleID: definition.styleID, name: definition.name, basedOn: definition.basedOn, linkedStyleID: definition.linkedStyleID, nextStyleID: definition.nextStyleID)
        selectedNamedStyleName = definition.name
        let resolved = NamedStyles.resolve(definition.styleID, in: namedStyleDefinitions) ?? definition.formatting
        let baseFont = NSFont(name: resolved.fontFamily ?? fontFamily, size: resolved.fontSize ?? fontSize) ?? NSFont.systemFont(ofSize: resolved.fontSize ?? fontSize)
        var font = baseFont
        if resolved.bold == true { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
        if resolved.italic == true { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacingBefore = resolved.spaceBefore ?? 0
        paragraph.paragraphSpacing = resolved.spaceAfter ?? 0
        paragraph.lineSpacing = resolved.lineSpacing ?? 0
        paragraph.headIndent = resolved.leftIndent ?? 0
        paragraph.firstLineHeadIndent = paragraph.headIndent + (resolved.firstLineIndent ?? 0)
        paragraph.tailIndent = -(resolved.rightIndent ?? 0)
        if let alignment = resolved.alignment {
            switch alignment.lowercased() { case "center": paragraph.alignment = .center; case "right": paragraph.alignment = .right; case "justified": paragraph.alignment = .justified; default: paragraph.alignment = .left }
        }
        var applied: [NSAttributedString.Key: Any] = [.boldWriterParagraphStyle: value, .font: font, .paragraphStyle: paragraph]
        if resolved.underline == true { applied[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if let color = resolved.foregroundColor, let rgb = UInt32(color, radix: 16) {
            applied[.foregroundColor] = NSColor(calibratedRed: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: 1)
        }
        if range.length == 0 {
            textView.typingAttributes[.boldWriterParagraphStyle] = value
            applied.forEach { textView.typingAttributes[$0.key] = $0.value }
            return
        }
        performUndoableMutation("Apply \(definition.name)") { view in
            guard let storage = view.textStorage else { return }
            var spans: [(NSRange, [NSTextBlock])] = []
            storage.enumerateAttribute(.paragraphStyle, in: range) { value, subrange, _ in
                spans.append((subrange, (value as? NSParagraphStyle)?.textBlocks ?? []))
            }
            for (subrange, blocks) in spans {
                var attributes = applied
                let preservedParagraph = paragraph.mutableCopy() as! NSMutableParagraphStyle
                preservedParagraph.textBlocks = blocks
                attributes[.paragraphStyle] = preservedParagraph
                storage.addAttributes(attributes, range: subrange)
                storage.removeAttribute(.boldWriterStyle, range: subrange)
            }
        }
    }

    @discardableResult
    func updateNamedStyleFromSelection() -> Bool {
        guard let textView, let storage = textView.textStorage, storage.length > 0 else { return false }
        let location = min(textView.selectedRange().location, storage.length - 1)
        guard let appliedStyle = storage.attribute(.boldWriterParagraphStyle, at: location, effectiveRange: nil) as? WordParagraphStyle,
              let index = namedStyleDefinitions.firstIndex(where: { $0.styleID == appliedStyle.styleID }),
              !namedStyleDefinitions[index].isBuiltIn else { return false }
        var formatting = NamedStyleFormatting()
        if let font = storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont {
            formatting.fontFamily = font.familyName
            formatting.fontSize = Double(font.pointSize)
            let traits = NSFontManager.shared.traits(of: font)
            formatting.bold = traits.contains(.boldFontMask)
            formatting.italic = traits.contains(.italicFontMask)
        }
        if let color = storage.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor,
           let rgb = color.usingColorSpace(.deviceRGB) {
            formatting.foregroundColor = String(format: "%02X%02X%02X", Int(rgb.redComponent * 255), Int(rgb.greenComponent * 255), Int(rgb.blueComponent * 255))
        }
        let paragraph = storage.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
        formatting.alignment = paragraph.map { $0.alignment == .center ? "center" : ($0.alignment == .right ? "right" : ($0.alignment == .justified ? "justified" : "left")) }
        formatting.firstLineIndent = paragraph.map { Double($0.firstLineHeadIndent - $0.headIndent) }
        formatting.leftIndent = paragraph.map { Double($0.headIndent) }
        formatting.rightIndent = paragraph.map { Double(-$0.tailIndent) }
        formatting.spaceBefore = paragraph.map { Double($0.paragraphSpacingBefore) }
        formatting.spaceAfter = paragraph.map { Double($0.paragraphSpacing) }
        formatting.lineSpacing = paragraph.map { Double($0.lineSpacing) }
        namedStyleDefinitions[index].formatting = formatting
        document?.metadata.namedStyles = namedStyleDefinitions
        return true
    }

    func clearDirectFormatting() {
        guard let textView else { return }
        let selection = textView.selectedRange()
        let range = selection.length == 0 ? paragraphRange(in: textView) : selection
        guard range.length > 0 else { return }
        performUndoableMutation("Clear Direct Formatting") { view in
            guard let storage = view.textStorage else { return }
            let retained = [NSAttributedString.Key.boldWriterStyle, .boldWriterParagraphStyle, .boldWriterCharacterStyle,
                            .paragraphStyle, .attachment, .boldWriterTrackChange, .footnote, .endnote, .tableCell]
            var removals: [(NSAttributedString.Key, NSRange)] = []
            storage.enumerateAttributes(in: range) { attributes, subrange, _ in
                for key in attributes.keys where !retained.contains(key) { removals.append((key, subrange)) }
            }
            for (key, subrange) in removals { storage.removeAttribute(key, range: subrange) }
            storage.enumerateAttribute(.boldWriterStyle, in: range) { value, subrange, _ in
                let raw = value as? String
                let semantic = raw.flatMap(WriterStyle.init(rawValue:))
                let named = storage.attribute(.boldWriterParagraphStyle, at: subrange.location, effectiveRange: nil) as? WordParagraphStyle
                let id = named?.styleID ?? semantic?.wordStyleID
                guard let id, let formatting = NamedStyles.resolve(id, in: NamedStyles.mergedWithBuiltIns(namedStyleDefinitions)) else {
                    if let semantic { storage.addAttribute(.font, value: semantic.font, range: subrange) }
                    return
                }
                if let size = formatting.fontSize {
                    var font = NSFont(name: formatting.fontFamily ?? "Helvetica", size: size) ?? NSFont.systemFont(ofSize: size)
                    if formatting.bold == true { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
                    if formatting.bold == false { font = NSFontManager.shared.convert(font, toNotHaveTrait: .boldFontMask) }
                    if formatting.italic == true { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
                    if formatting.italic == false { font = NSFontManager.shared.convert(font, toNotHaveTrait: .italicFontMask) }
                    storage.addAttribute(.font, value: font, range: subrange)
                }
                if let hex = formatting.foregroundColor, let rgb = UInt32(hex, radix: 16) {
                    storage.addAttribute(.foregroundColor, value: NSColor(calibratedRed: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: 1), range: subrange)
                }
                if let underline = formatting.underline { storage.addAttribute(.underlineStyle, value: underline ? NSUnderlineStyle.single.rawValue : 0, range: subrange) }
                if let old = storage.attribute(.paragraphStyle, at: subrange.location, effectiveRange: nil) as? NSParagraphStyle {
                    let paragraph = old.mutableCopy() as! NSMutableParagraphStyle
                    if let value = formatting.spaceBefore { paragraph.paragraphSpacingBefore = value }
                    if let value = formatting.spaceAfter { paragraph.paragraphSpacing = value }
                    if let value = formatting.lineSpacing { paragraph.lineSpacing = value }
                    if let value = formatting.leftIndent { paragraph.headIndent = value }
                    if let value = formatting.firstLineIndent { paragraph.firstLineHeadIndent = paragraph.headIndent + value }
                    if let value = formatting.rightIndent { paragraph.tailIndent = -value }
                    if let alignment = formatting.alignment {
                        switch alignment.lowercased() { case "center": paragraph.alignment = .center; case "right": paragraph.alignment = .right; case "justified": paragraph.alignment = .justified; default: paragraph.alignment = .left }
                    }
                    storage.addAttribute(.paragraphStyle, value: paragraph, range: subrange)
                }
            }
        }
    }

    func addBookmark(name: String, to document: BOLDWriterDocument) throws -> DocumentBookmark {
        let safeName = DocumentBookmarks.normalizedName(name)
        guard !safeName.isEmpty else { throw WriterError.message("A bookmark name is required.") }
        guard !document.metadata.bookmarks.contains(where: { $0.name.caseInsensitiveCompare(safeName) == .orderedSame }) else {
            throw WriterError.message("A bookmark with that name already exists.")
        }
        let range = selection.length > 0 ? selection : NSRange(location: selection.location, length: 0)
        guard range.location >= 0, range.location <= document.text.length, range.length <= document.text.length - range.location else {
            throw WriterError.message("The bookmark range is outside the document.")
        }
        let bookmark = DocumentBookmark(name: safeName, location: range.location, length: range.length)
        document.metadata.bookmarks.append(bookmark)
        document.metadata.bookmarks.sort { $0.location == $1.location ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : $0.location < $1.location }
        return bookmark
    }

    func renameBookmark(id: UUID, to name: String, in document: BOLDWriterDocument) throws {
        let safe = DocumentBookmarks.normalizedName(name)
        guard !safe.isEmpty, let index = document.metadata.bookmarks.firstIndex(where: { $0.id == id }) else {
            throw WriterError.message("The bookmark could not be renamed.")
        }
        guard !document.metadata.bookmarks.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(safe) == .orderedSame }) else {
            throw WriterError.message("A bookmark with that name already exists.")
        }
        document.metadata.bookmarks[index].name = safe
    }

    func deleteBookmark(id: UUID, from document: BOLDWriterDocument) {
        document.metadata.bookmarks.removeAll { $0.id == id }
    }

    func applyHyperlink(_ destination: String, in document: BOLDWriterDocument) throws {
        guard textView != nil, selection.length > 0 else { throw WriterError.message("Select text before adding a link.") }
        let target = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        let value: Any
        if target.hasPrefix("#") {
            let name = String(target.dropFirst())
            guard document.metadata.bookmarks.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                throw WriterError.message("Choose an existing bookmark for an internal link.")
            }
            value = "#" + name
        } else {
            guard let url = URL(string: target), let scheme = url.scheme?.lowercased(),
                  ["http", "https", "mailto"].contains(scheme),
                  (scheme == "mailto" ? !url.path.isEmpty : !(url.host ?? "").isEmpty) else {
                throw WriterError.message("Enter a valid http, https, mailto, or #bookmark destination.")
            }
            value = url
        }
        performUndoableMutation("Add Hyperlink") { $0.textStorage?.addAttribute(.link, value: value, range: selection) }
    }

    func removeHyperlink() {
        guard let textView else { return }
        let range = textView.selectedRange()
        let safe = range.length > 0 ? range : NSRange(location: min(range.location, max(0, textView.textStorage?.length ?? 0)), length: range.location < (textView.textStorage?.length ?? 0) ? 1 : 0)
        guard safe.length > 0 else { return }
        performUndoableMutation("Remove Hyperlink") { $0.textStorage?.removeAttribute(.link, range: safe) }
    }

    func activateLink(in document: BOLDWriterDocument) {
        guard let textView, let storage = textView.textStorage, storage.length > 0 else { return }
        let selected = textView.selectedRange()
        let location = min(selected.location, storage.length - 1)
        let target = storage.attribute(.link, at: location, effectiveRange: nil)
        guard let target else { return }
        activateLink(target,in:document)
    }

    @discardableResult
    func activateLink(_ target: Any, in document: BOLDWriterDocument) -> Bool {
        let string = (target as? URL)?.absoluteString ?? target as? String
        guard let string else { return false }
        if string.hasPrefix("#"), let bookmark = document.metadata.bookmarks.first(where: { $0.name.caseInsensitiveCompare(String(string.dropFirst())) == .orderedSame }) {
            navigate(to: NSRange(location: bookmark.location, length: bookmark.length))
            return true
        } else if let url = URL(string: string), ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") {
            NSWorkspace.shared.open(url)
            return true
        }
        return false
    }

    func insertCrossReference(to bookmark: DocumentBookmark, pageNumber: Bool = false) {
        guard let textView else { return }
        let instruction = pageNumber ? " PAGEREF \(bookmark.name) \\h " : " REF \(bookmark.name) \\h "
        let source = document?.text.string as NSString? ?? "" as NSString
        let validRange = bookmark.location >= 0 && bookmark.length > 0 && bookmark.location <= source.length && bookmark.length <= source.length - bookmark.location
        let result = pageNumber ? "?" : (validRange ? source.substring(with: NSRange(location: bookmark.location, length: bookmark.length)) : bookmark.name)
        var attributes = textView.typingAttributes
        attributes[.boldWriterField] = WordField(kind: .simple, instruction: instruction)
        textView.insertText(NSAttributedString(string: result, attributes: attributes), replacementRange: textView.selectedRange())
    }

    func insertTableOfContents(levels: Int = 3, mode: PublishingTOCMode = .digitalPDF, title: String = "Contents", showTitle: Bool = true, leader: PublishingTOCLeader = .dots, customSettings: PublishingTOCSettings? = nil) {
        guard let textView, let document else { return }
        guard textView.isEditable,
              Self.isValid(textView.selectedRange(), length: textView.textStorage?.length ?? 0) else { return }
        let undoManager = textView.undoManager
        undoManager?.beginUndoGrouping()
        registerPublishingMetadataUndo(document: document, settings: document.metadata.publishingTOCs,
                                       bookmarks: document.metadata.bookmarks)
        defer { undoManager?.endUndoGrouping() }
        let safeLevels = min(6, max(1, levels))
        let insertion = textView.selectedRange()
        let field = WordField(kind: .complex, instruction: " TOC \\o \"1-\(safeLevels)\" \\h \\z \\u ")
        let settings = PublishingTOCSettings(fieldID: field.id, mode: mode, maximumHeadingLevel: safeLevels)
        var savedSettings = customSettings ?? settings
        savedSettings.fieldID = field.id
        savedSettings.mode = mode
        savedSettings.maximumHeadingLevel = safeLevels
        savedSettings.title = title
        savedSettings.showTitle = showTitle
        savedSettings.leader = leader
        var allSettings = document.metadata.publishingTOCs ?? []
        allSettings.removeAll { $0.fieldID == field.id }
        allSettings.append(savedSettings)
        document.metadata.publishingTOCs = allSettings
        var attributes = textView.typingAttributes
        attributes.removeValue(forKey: .boldWriterStyle)
        attributes.removeValue(forKey: .boldWriterParagraphStyle)
        attributes.removeValue(forKey: .boldWriterCharacterStyle)
        attributes.removeValue(forKey: .boldWriterField)
        attributes.removeValue(forKey: .link)
        attributes.removeValue(forKey: .footnote)
        attributes.removeValue(forKey: .endnote)
        attributes.removeValue(forKey: .boldWriterTrackChange)
        let combined = NSMutableAttributedString(string: showTitle ? "\(title)\n\n" : " ", attributes: attributes)
        combined.addAttribute(.boldWriterField, value: field, range: NSRange(location: 0, length: combined.length))
        replace(
            range: insertion,
            with: combined,
            actionName: "Insert Table of Contents",
            trackChanges: document.metadata.trackChangesEnabled ?? false
        )
        _ = updateAllFields(in: document)
    }

    /// TOC settings and generated anchors belong to the same undo group as its
    /// text. Preserve unrelated manuscript/cover metadata when undoing a TOC.
    private func registerPublishingMetadataUndo(document: BOLDWriterDocument,
                                               settings: [PublishingTOCSettings]?,
                                               bookmarks: [DocumentBookmark]) {
        textView?.undoManager?.registerUndo(withTarget: self) { target in
            target.registerPublishingMetadataUndo(document: document,
                settings: document.metadata.publishingTOCs, bookmarks: document.metadata.bookmarks)
            document.metadata.publishingTOCs = settings
            document.metadata.bookmarks = bookmarks
        }
    }

    func insertCaption(label rawLabel: String, title: String, belowSelection: Bool = false) throws {
        guard let textView, let storage = textView.textStorage, let document else { throw WriterError.message("The editor is unavailable.") }
        let label = rawLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty, label.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 _-").contains($0) }) else {
            throw WriterError.message("Caption labels must contain letters, numbers, spaces, underscores, or hyphens.")
        }
        let selected = textView.selectedRange()
        let source = storage.string as NSString
        let point = min(selected.location, source.length)
        let paragraph = source.paragraphRange(for: NSRange(location: point, length: 0))
        let start = belowSelection ? NSMaxRange(paragraph) : paragraph.location
        let sequenceIdentifier = label.split(whereSeparator: \.isWhitespace).joined()
        let field = WordField(kind: .simple, instruction: " SEQ \(sequenceIdentifier) \\* ARABIC ")
        var attributes = textView.typingAttributes
        attributes.removeValue(forKey: .boldWriterField)
        attributes.removeValue(forKey: .link)
        attributes.removeValue(forKey: .footnote)
        attributes.removeValue(forKey: .endnote)
        attributes.removeValue(forKey: .boldWriterTrackChange)
        attributes.removeValue(forKey: .boldWriterParagraphStyle)
        attributes.removeValue(forKey: .boldWriterCharacterStyle)
        attributes[.boldWriterStyle] = WriterStyle.caption.rawValue
        attributes[.boldWriterParagraphStyle] = WordParagraphStyle(styleID: "Caption", name: "Caption", basedOn: "Normal")
        attributes[.font] = WriterStyle.caption.font
        let numberAttributes = attributes.merging([.boldWriterField: field] as [NSAttributedString.Key: Any]) { _, new in new }
        let caption = NSMutableAttributedString(string: "\(label) ", attributes: attributes)
        caption.append(NSAttributedString(string: "1", attributes: numberAttributes))
        caption.append(NSAttributedString(string: title.isEmpty ? "\n" : " — \(title)\n", attributes: attributes))
        replace(
            range: NSRange(location: start, length: 0),
            with: caption,
            actionName: "Insert Caption",
            trackChanges: document.metadata.trackChangesEnabled ?? false
        )
        let bookmarkName = "BOLDCap_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        if start >= 0, start + caption.length <= storage.length {
            document.metadata.bookmarks.append(DocumentBookmark(name: bookmarkName, location: start, length: caption.length))
        }
        _ = updateAllFields(in: document)
    }

    func removeSelectedTableOfContents() {
        guard let textView, let storage = textView.textStorage, storage.length > 0 else { return }
        let point = min(textView.selectedRange().location, storage.length - 1)
        guard let field = storage.attribute(.boldWriterField, at: point, effectiveRange: nil) as? WordField,
              field.instruction.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().hasPrefix("TOC") else { return }
        var range = NSRange(location: NSNotFound, length: 0)
        _ = storage.attribute(.boldWriterField, at: point, longestEffectiveRange: &range, in: NSRange(location: 0, length: storage.length))
        guard range.location != NSNotFound, textView.isEditable, let document else { return }
        let undoManager = textView.undoManager
        undoManager?.beginUndoGrouping()
        registerPublishingMetadataUndo(document: document, settings: document.metadata.publishingTOCs,
                                       bookmarks: document.metadata.bookmarks)
        defer { undoManager?.endUndoGrouping() }
        document.metadata.publishingTOCs?.removeAll { $0.fieldID == field.id }
        replace(range: range, with: NSAttributedString(string: ""), actionName: "Remove Table of Contents",
                trackChanges: document.metadata.trackChangesEnabled ?? false)
    }

    func updateSelectedTableOfContents(settings: PublishingTOCSettings, in document: BOLDWriterDocument) {
        guard let storage=textView?.textStorage, storage.length > 0 else { return }
        let point=min(textView?.selectedRange().location ?? 0,storage.length-1)
        guard let field=storage.attribute(.boldWriterField,at:point,effectiveRange:nil) as? WordField,
              field.instruction.trimmingCharacters(in:.whitespacesAndNewlines).uppercased().hasPrefix("TOC") else { return }
        guard textView?.isEditable == true else { return }
        let undoManager = textView?.undoManager
        undoManager?.beginUndoGrouping()
        registerPublishingMetadataUndo(document: document, settings: document.metadata.publishingTOCs,
                                       bookmarks: document.metadata.bookmarks)
        defer { undoManager?.endUndoGrouping() }
        performUndoableMutation("Update Table of Contents") { _ in
            var updated=settings; updated.fieldID=field.id
            var values=document.metadata.publishingTOCs ?? []; values.removeAll{$0.fieldID == field.id}; values.append(updated); document.metadata.publishingTOCs=values
            _=updateAllFields(in:document)
        }
    }

    @discardableResult
    func ensureHeadingBookmarks(in document: BOLDWriterDocument, excluding excludedRange: NSRange? = nil) -> [DocumentBookmark] {
        guard let storage = textView?.textStorage else { return [] }
        for heading in Self.semanticHeadings(in: storage) {
            if let excludedRange, NSIntersectionRange(heading.range, excludedRange).length > 0 { continue }
            guard !document.metadata.bookmarks.contains(where: { $0.name.hasPrefix("BOLDH_") && $0.location == heading.range.location }) else { continue }
            document.metadata.bookmarks.append(DocumentBookmark(
                name: "BOLDH_" + UUID().uuidString.replacingOccurrences(of: "-", with: ""),
                location: heading.range.location,
                length: heading.range.length
            ))
        }
        return document.metadata.bookmarks.filter { $0.name.hasPrefix("BOLDH_") }
    }

    @discardableResult
    func updateCrossReferences(in document: BOLDWriterDocument) -> Int {
        updateAllFields(in: document)
    }

    @discardableResult
    func updateAllFields(in document: BOLDWriterDocument) -> Int {
        let sequenceAndTOCs = updateFieldPass(
            in: document,
            referencesOnly: false
        )
        let references = updateFieldPass(
            in: document,
            referencesOnly: true
        )

        let ordinaryUpdates =
            sequenceAndTOCs
            + references

        if ordinaryUpdates > 0 {
            textView?.didChangeText()
        }

        let pageCountUpdates =
            updateNUMPAGESFields()

        return ordinaryUpdates
            + pageCountUpdates
    }

    @discardableResult
    private func updateFieldPass(in document: BOLDWriterDocument, referencesOnly: Bool) -> Int {
        guard let textView, let storage = textView.textStorage else { return 0 }
        struct FieldValue { var range: NSRange; var field: WordField; var replacement: NSAttributedString? }
        var fields: [FieldValue] = []
        var sequences: [String: Int] = [:]
        storage.enumerateAttribute(.boldWriterField, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let field = value as? WordField else { return }
            let components = field.instruction.split(whereSeparator: \.isWhitespace).map(String.init)
            guard let command = components.first?.uppercased() else { return }
            if referencesOnly != ["REF", "PAGEREF"].contains(command) { return }
            if command == "SEQ", components.count >= 2 {
                let switches = components.filter { $0.hasPrefix("\\") }
                guard switches.allSatisfy({ ["\\r", "\\c", "\\*"].contains($0.lowercased()) }) else { return }
                if components.contains(where: { $0.lowercased() == "\\r" }),
                   !components.indices.contains(where: { index in
                       components[index].lowercased() == "\\r" && components.indices.contains(index + 1) && Int(components[index + 1]) != nil
                   }) { return }
                if let formatSwitch = components.firstIndex(where: { $0 == "\\*" }),
                   !components.indices.contains(where: { $0 == formatSwitch + 1 && ["ARABIC", "ROMAN", "roman", "ALPHABETIC", "alphabetic"].contains(components[$0]) }) { return }
                let identifier = components[1].lowercased()
                if let restart = components.firstIndex(where: { $0.lowercased() == "\\r" }), components.indices.contains(restart + 1), let value = Int(components[restart + 1]) {
                    sequences[identifier] = value
                    fields.append(FieldValue(range: range, field: field, replacement: NSAttributedString(string: Self.formatSequence(value, components: components))))
                } else if components.contains(where: { $0.lowercased() == "\\c" }) {
                    fields.append(FieldValue(range: range, field: field, replacement: NSAttributedString(string: Self.formatSequence(sequences[identifier] ?? 0, components: components))))
                } else {
                    let next = (sequences[identifier] ?? 0) + 1
                    sequences[identifier] = next
                    fields.append(FieldValue(range: range, field: field, replacement: NSAttributedString(string: Self.formatSequence(next, components: components))))
                }
            } else if command == "TOC" {
                guard Self.tocMaximumLevel(instruction: field.instruction) != nil else { return }
                fields.append(FieldValue(range: range, field: field, replacement: makeTOCResult(field: field, in: document, excluding: range)))
            } else if let target = Self.fieldTarget(field.instruction) {
                guard let bookmark = document.metadata.bookmarks.first(where: { $0.name.caseInsensitiveCompare(target.name) == .orderedSame }) else {
                    fields.append(FieldValue(range: range, field: field, replacement: NSAttributedString(string: "?")))
                    return
                }
                let value: String
                if target.page { value = pageNumber(at: bookmark.location).map(String.init) ?? "?" }
                else if bookmark.length > 0, bookmark.location <= storage.length, bookmark.length <= storage.length - bookmark.location {
                    value = (storage.string as NSString).substring(with: NSRange(location: bookmark.location, length: bookmark.length))
                } else { value = bookmark.name }
                fields.append(FieldValue(range: range, field: field, replacement: NSAttributedString(string: value)))
            }
        }
        for item in fields.reversed() {
            guard let replacement = item.replacement, item.range.location >= 0, item.range.length > 0,
                  item.range.location <= storage.length, item.range.length <= storage.length - item.range.location else { continue }
            let isTOC = item.field.instruction.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().hasPrefix("TOC")
            let attributed = isTOC
                ? NSMutableAttributedString(attributedString: replacement)
                : Self.replacementPreservingAttributes(replacement.string, from: storage, range: item.range)
            if isTOC, let font = storage.attribute(.font, at: item.range.location, effectiveRange: nil) {
                attributed.addAttribute(.font, value: font, range: NSRange(location: 0, length: attributed.length))
            }
            attributed.addAttribute(.boldWriterField, value: item.field, range: NSRange(location: 0, length: attributed.length))
            storage.replaceCharacters(in: item.range, with: attributed)
        }
        return fields.count
    }

    private func makeTOCResult(field: WordField, in document: BOLDWriterDocument, excluding excludedRange: NSRange) -> NSAttributedString {
        guard let storage = textView?.textStorage else { return NSAttributedString(string: "") }
        let settings = document.metadata.publishingTOCs?.first { $0.fieldID == field.id }
        let maximum = settings?.maximumHeadingLevel ?? Self.tocMaximumLevel(instruction: field.instruction) ?? 3
        let source = storage.string as NSString
        let result = NSMutableAttributedString(string: settings?.showTitle == true ? "\(settings?.title ?? "Contents")\n" : "")
        _ = ensureHeadingBookmarks(in: document, excluding: excludedRange)
        for heading in Self.semanticHeadings(in: storage) where heading.level <= maximum && NSIntersectionRange(heading.range, excludedRange).length == 0 {
            let visible = source.substring(with: heading.range).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !visible.isEmpty else { continue }
            let anchor: DocumentBookmark
            if let existing = document.metadata.bookmarks.first(where: { $0.name.hasPrefix("BOLDH_") && $0.location == heading.range.location }) {
                anchor = existing
            } else {
                anchor = DocumentBookmark(name: "BOLDH_" + UUID().uuidString.replacingOccurrences(of: "-", with: ""), location: heading.range.location, length: heading.range.length)
                document.metadata.bookmarks.append(anchor)
            }
            let page = settings?.mode.usesPageNumbers == false || (heading.level == 1 && settings?.suppressTopLevelPageNumbers == true) ? "" : (pageNumber(at: heading.range.location).map(String.init) ?? "?")
            let indent = max(0, heading.level - 1)
            let lead = settings?.leader.glyph ?? "."
            let font=NSFont(name:settings?.fontName ?? "Georgia",size:settings?.fontSize ?? 12) ?? NSFont.systemFont(ofSize:settings?.fontSize ?? 12)
            let leading=String(repeating:"  ",count:indent)+visible
            let widthLimit=max(100,440-Double(indent)*(settings?.indentationPerLevel ?? 14))
            let titleWidth=(leading as NSString).size(withAttributes:[.font:font]).width
            let pageWidth=(page as NSString).size(withAttributes:[.font:font]).width
            let filler=lead.isEmpty ? " " : lead
            let glyphWidth=max(1,(filler as NSString).size(withAttributes:[.font:font]).width)
            let leaderCount=page.isEmpty ? 0 : max(0,Int((widthLimit-titleWidth-pageWidth-12)/glyphWidth))
            let pageSuffix: String
            if page.isEmpty { pageSuffix="" }
            else if settings?.numberAlignment == "left" { pageSuffix="  \(page)" }
            else { pageSuffix=" " + String(repeating:filler,count:leaderCount) + " \(page)" }
            let line = NSMutableAttributedString(string: leading + pageSuffix + "\n")
            if line.length > 0 {
                line.addAttribute(.link, value: "#\(anchor.name)", range: NSRange(location: 0, length: line.length))
                let paragraph = NSMutableParagraphStyle()
                paragraph.headIndent = CGFloat(indent) * CGFloat(settings?.indentationPerLevel ?? 14)
                paragraph.lineSpacing = CGFloat(settings?.lineSpacing ?? 0)
                line.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: line.length))
                line.addAttribute(.font,value:font,range:NSRange(location:0,length:line.length))
                if heading.level == 1 && (settings?.boldTopLevel ?? false) { line.addAttribute(.font,value:NSFontManager.shared.convert(font,toHaveTrait:.boldFontMask),range:NSRange(location:0,length:line.length)) }
                result.append(line)
            }
        }
        if result.length == 0 { result.append(NSAttributedString(string:" ")) }
        return result
    }

    private static func tocMaximumLevel(instruction: String) -> Int? {
        let components = instruction.split(whereSeparator: \.isWhitespace).map(String.init)
        guard components.first?.uppercased() == "TOC" else { return nil }
        guard let rangeSwitch = components.firstIndex(where: { $0.lowercased() == "\\o" }) else { return 3 }
        guard components.indices.contains(rangeSwitch + 1) else { return nil }
        let pair = components[rangeSwitch + 1].trimmingCharacters(in: CharacterSet(charactersIn: "\"" )).split(separator: "-")
        guard pair.count == 2, let minimum = Int(pair[0]), let maximum = Int(pair[1]), (1...6).contains(minimum), (minimum...6).contains(maximum) else { return nil }
        return maximum
    }

    private struct SemanticHeading { var level: Int; var range: NSRange }

    private static func semanticHeadings(in text: NSAttributedString) -> [SemanticHeading] {
        let source = text.string as NSString
        var result: [SemanticHeading] = []
        source.enumerateSubstrings(in: NSRange(location: 0, length: source.length), options: [.byParagraphs, .substringNotRequired]) { _, range, _, _ in
            guard range.length > 0 else { return }
            let visible = source.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.union(.controlCharacters).inverted, range: range)
            guard visible.location != NSNotFound else { return }
            let point = visible.location
            let raw = text.attribute(.boldWriterStyle, at: point, effectiveRange: nil) as? String
            var level = raw.flatMap(WriterStyle.init(rawValue:))?.headingLevel
            if level == nil, let named = text.attribute(.boldWriterParagraphStyle, at: point, effectiveRange: nil) as? WordParagraphStyle {
                let id = named.styleID.lowercased().replacingOccurrences(of: " ", with: "")
                if id.hasPrefix("heading"), let value = Int(id.dropFirst("heading".count)), (1...6).contains(value) { level = value }
            }
            if let level {
                let end = NSMaxRange(range)
                var contentEnd = end
                while contentEnd > visible.location, CharacterSet.whitespacesAndNewlines.contains(UnicodeScalar(source.character(at: contentEnd - 1))!) { contentEnd -= 1 }
                if contentEnd > visible.location { result.append(SemanticHeading(level: level, range: NSRange(location: visible.location, length: contentEnd - visible.location))) }
            }
        }
        return result
    }


    /// Recalculates native Word NUMPAGES fields from the real,
    /// completed Print Layout pagination rather than estimating
    /// pages from text length.
    ///
    /// The field result can itself change line wrapping when its
    /// digit count changes (for example 9 -> 10). Re-run layout and
    /// replacement a few times until the visible result reaches a
    /// fixed point. A normal document stabilizes after one pass.
    @discardableResult
    private func updateNUMPAGESFields() -> Int {
        guard
            let textView,
            let storage =
                textView.textStorage
        else {
            return 0
        }

        struct PageCountFieldValue {
            var range: NSRange
            var field: WordField
            var replacement: String
        }

        var totalChanges =
            0

        // Two passes are normally enough. Four leaves margin for
        // pathological pagination exactly on a digit boundary while
        // keeping the operation strictly bounded.
        for _ in 0..<4 {
            guard
                let physicalPageCount =
                    livePhysicalPageCount()
            else {
                break
            }

            var values:
                [PageCountFieldValue] = []

            storage.enumerateAttribute(
                .boldWriterField,
                in:
                    NSRange(
                        location:
                            0,
                        length:
                            storage.length
                    )
            ) {
                value,
                range,
                _ in

                guard
                    let field =
                        value as? WordField,
                    range.length > 0
                else {
                    return
                }

                let components =
                    field
                    .instruction
                    .split(
                        whereSeparator:
                            \.isWhitespace
                    )
                    .map(
                        String.init
                    )

                guard
                    components
                        .first?
                        .uppercased()
                        == "NUMPAGES"
                else {
                    return
                }

                let replacement =
                    Self.formatSequence(
                        physicalPageCount,
                        components:
                            components
                    )

                guard
                    range.location
                        <= storage.length,
                    range.length
                        <= storage.length
                            - range.location
                else {
                    return
                }

                let current =
                    (
                        storage.string
                            as NSString
                    )
                    .substring(
                        with:
                            range
                    )

                guard
                    current
                        != replacement
                else {
                    return
                }

                values.append(
                    PageCountFieldValue(
                        range:
                            range,
                        field:
                            field,
                        replacement:
                            replacement
                    )
                )
            }

            guard
                !values.isEmpty
            else {
                break
            }

            for item
                in values.reversed() {

                guard
                    item.range.location
                        <= storage.length,
                    item.range.length
                        <= storage.length
                            - item.range.location
                else {
                    continue
                }

                let attributed =
                    Self
                    .replacementPreservingAttributes(
                        item.replacement,
                        from:
                            storage,
                        range:
                            item.range
                    )

                if attributed.length > 0 {
                    attributed.addAttribute(
                        .boldWriterField,
                        value:
                            item.field,
                        range:
                            NSRange(
                                location:
                                    0,
                                length:
                                    attributed.length
                            )
                    )
                }

                storage.replaceCharacters(
                    in:
                        item.range,
                    with:
                        attributed
                )
            }

            totalChanges +=
                values.count

            textView.didChangeText()
        }

        return totalChanges
    }

    /// Returns the true number of current physical Print Layout
    /// pages. This deliberately refuses to guess when the editing
    /// view is not hosted inside a PaginatedEditor.
    private func livePhysicalPageCount()
        -> Int?
    {
        var view:
            NSView? =
                textView

        while let current =
            view {

            if let canvas =
                current
                    as? PaginatedEditor {

                canvas.finishPagination()

                guard
                    canvas.lastLayoutError
                        == nil,
                    canvas.layoutComplete,
                    !canvas.pages.isEmpty
                else {
                    return nil
                }

                return canvas
                    .pages
                    .count
            }

            view =
                current.superview
        }

        return nil
    }

    private func pageNumber(at location: Int) -> Int? {
        var view: NSView? = textView
        while let current = view {
            if let canvas = current as? PaginatedEditor { return canvas.displayPageNumber(containing: location) }
            view = current.superview
        }
        return nil
    }

    private static func fieldTarget(_ instruction: String) -> (name: String, page: Bool)? {
        let parts = instruction.split(whereSeparator: \.isWhitespace)
        guard parts.count >= 2, ["REF", "PAGEREF"].contains(parts[0].uppercased()) else { return nil }
        return (String(parts[1]), parts[0].uppercased() == "PAGEREF")
    }

    private static func formatSequence(_ value: Int, components: [String]) -> String {
        guard let formatSwitch = components.firstIndex(where: { $0 == "\\*" }), components.indices.contains(formatSwitch + 1) else { return String(value) }
        let format = components[formatSwitch + 1].uppercased()
        if format == "ROMAN", value > 0, value < 4000 {
            var remaining = value
            var result = ""
            for (number, numeral) in [(1000,"M"),(900,"CM"),(500,"D"),(400,"CD"),(100,"C"),(90,"XC"),(50,"L"),(40,"XL"),(10,"X"),(9,"IX"),(5,"V"),(4,"IV"),(1,"I")] {
                while remaining >= number { result += numeral; remaining -= number }
            }
            return components[formatSwitch + 1] == "roman" ? result.lowercased() : result
        }
        if format == "ALPHABETIC", value > 0 {
            var remaining = value
            var letters = ""
            while remaining > 0 {
                remaining -= 1
                letters = String(UnicodeScalar(65 + remaining % 26)!) + letters
                remaining /= 26
            }
            return components[formatSwitch + 1] == "alphabetic" ? letters.lowercased() : letters
        }
        return String(value)
    }

    private static func replacementPreservingAttributes(_ replacement: String, from storage: NSTextStorage, range: NSRange) -> NSMutableAttributedString {
        let result = NSMutableAttributedString(string: replacement)
        guard result.length > 0, range.length > 0 else { return result }
        let oldLast = NSMaxRange(range) - 1
        storage.enumerateAttributes(in: range) { attributes, oldRange, _ in
            let start = min(oldRange.location - range.location, result.length)
            let end = min(NSMaxRange(oldRange) - range.location, result.length)
            if end > start { result.addAttributes(attributes, range: NSRange(location: start, length: end - start)) }
        }
        let copiedLength = min(range.length, result.length)
        if copiedLength < result.length {
            let lastAttributes = storage.attributes(at: oldLast, effectiveRange: nil)
            result.addAttributes(lastAttributes, range: NSRange(location: copiedLength, length: result.length - copiedLength))
        }
        return result
    }

    func toggleTrait(_ trait: NSFontTraitMask) {
        guard let textView else { return }
        defer { refreshFormattingState() }
        if textView.selectedRange().length == 0 {
            let font = textView.typingAttributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: CGFloat(fontSize))
            textView.typingAttributes[.font] = toggledFont(font, trait: trait)
            return
        }
        var allHaveTrait = true
        textView.textStorage?.enumerateAttribute(.font, in: textView.selectedRange()) { value, _, _ in
            let font = value as? NSFont ?? NSFont.systemFont(ofSize: CGFloat(fontSize))
            if !NSFontManager.shared.traits(of: font).contains(trait) { allHaveTrait = false }
        }
        performUndoableMutation("Format Font") { view in
            view.textStorage?.enumerateAttribute(.font, in: view.selectedRange()) { value, range, _ in
                let font = value as? NSFont ?? NSFont.systemFont(ofSize: CGFloat(self.fontSize))
                let converted = allHaveTrait
                    ? NSFontManager.shared.convert(font, toNotHaveTrait: trait)
                    : NSFontManager.shared.convert(font, toHaveTrait: trait)
                view.textStorage?.addAttribute(.font, value: converted, range: range)
            }
        }
    }

    private func toggledFont(_ font: NSFont, trait: NSFontTraitMask) -> NSFont {
        let manager = NSFontManager.shared
        return manager.traits(of: font).contains(trait) ? manager.convert(font, toNotHaveTrait: trait) : manager.convert(font, toHaveTrait: trait)
    }

    func toggleUnderline() { toggleIntegerAttribute(.underlineStyle, enabledValue: NSUnderlineStyle.single.rawValue, name: "Underline") }
    func toggleStrikethrough() { toggleIntegerAttribute(.strikethroughStyle, enabledValue: NSUnderlineStyle.single.rawValue, name: "Strikethrough") }

    private func toggleIntegerAttribute(_ key: NSAttributedString.Key, enabledValue: Int, name: String) {
        guard let textView else { return }
        defer { refreshFormattingState() }
        let range = textView.selectedRange()
        if range.length == 0 {
            let current = textView.typingAttributes[key] as? Int ?? 0
            textView.typingAttributes[key] = current == 0 ? enabledValue : 0
            return
        }
        var allEnabled = true
        textView.textStorage?.enumerateAttribute(key, in: range) { value, _, _ in
            if (value as? Int ?? 0) == 0 { allEnabled = false }
        }
        performUndoableMutation(name) { $0.textStorage?.addAttribute(key, value: allEnabled ? 0 : enabledValue, range: range) }
    }

    func setFontSize(_ size: Double) {
        guard let textView, size >= 6, size <= 144 else { return }
        defer { refreshFormattingState() }
        fontSize = size
        if textView.selectedRange().length == 0 {
            let current = textView.typingAttributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: CGFloat(size))
            textView.typingAttributes[.font] = NSFont(descriptor: current.fontDescriptor, size: CGFloat(size)) ?? current
            return
        }
        performUndoableMutation("Font Size") { view in
            view.textStorage?.enumerateAttribute(.font, in: view.selectedRange()) { value, range, _ in
                let font = value as? NSFont ?? NSFont.systemFont(ofSize: CGFloat(size))
                view.textStorage?.addAttribute(.font, value: NSFont(descriptor: font.fontDescriptor, size: CGFloat(size)) ?? font, range: range)
            }
        }
    }

    func setFontFamily(_ family: String) {
        guard let textView else { return }
        defer { refreshFormattingState() }
        fontFamily = family

        if textView.selectedRange().length == 0 {
            let current = textView.typingAttributes[.font] as? NSFont
                ?? NSFont.systemFont(ofSize: CGFloat(fontSize))
            textView.typingAttributes[.font] = NSFontManager.shared.convert(current, toFamily: family)
            return
        }

        performUndoableMutation("Font Family") { view in
            guard let storage = view.textStorage else { return }
            let range = view.selectedRange()

            storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
                let current = value as? NSFont
                    ?? NSFont.systemFont(ofSize: CGFloat(self.fontSize))
                let converted = NSFontManager.shared.convert(current, toFamily: family)
                storage.addAttribute(.font, value: converted, range: subrange)
            }
        }
    }

    func setTextColor(_ color: NSColor) {
        textColor = color
        applyAttribute(.foregroundColor, value: color, name: "Text Color")
    }
    func setHighlight(_ color: NSColor) {
        defer { refreshFormattingState() }
        guard color == .clear else {
            applyAttribute(.backgroundColor, value: color, name: "Highlight")
            return
        }
        guard let textView else { return }
        if textView.selectedRange().length == 0 {
            textView.typingAttributes.removeValue(forKey: .backgroundColor)
            return
        }
        performUndoableMutation("Remove Highlight") {
            $0.textStorage?.removeAttribute(.backgroundColor, range: $0.selectedRange())
        }
    }

    private func applyAttribute(_ key: NSAttributedString.Key, value: Any, name: String) {
        guard let textView else { return }
        defer { refreshFormattingState() }
        if textView.selectedRange().length == 0 { textView.typingAttributes[key] = value; return }
        performUndoableMutation(name) { $0.textStorage?.addAttribute(key, value: value, range: $0.selectedRange()) }
    }

    func setAlignment(_ alignment: NSTextAlignment) {
        guard let textView else { return }
        defer { refreshFormattingState() }
        let range = paragraphRange(in: textView)
        if range.length == 0 {
            let paragraph = (textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            paragraph.alignment = alignment
            textView.typingAttributes[.paragraphStyle] = paragraph
            return
        }
        performUndoableMutation("Paragraph Alignment") { view in
            view.textStorage?.enumerateAttribute(.paragraphStyle, in: range) { value, subrange, _ in
                let paragraph = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
                paragraph.alignment = alignment
                view.textStorage?.addAttribute(.paragraphStyle, value: paragraph, range: subrange)
            }
        }
    }

    func setTextDirection(_ direction: NSWritingDirection) {
        guard direction == .leftToRight || direction == .rightToLeft, let textView else { return }
        defer { refreshFormattingState() }
        let isRightToLeft = direction == .rightToLeft
        let range = paragraphRange(in: textView)
        if range.length == 0 {
            var attributes = textView.typingAttributes
            let paragraph = (attributes[.paragraphStyle] as? NSParagraphStyle)?
                .mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            paragraph.baseWritingDirection = direction
            attributes[.paragraphStyle] = paragraph
            attributes[.boldWriterParagraphBidi] = isRightToLeft
            textView.typingAttributes = attributes
            return
        }
        performUndoableMutation("Text Direction") { view in
            guard let storage = view.textStorage else { return }
            var spans: [(NSRange, NSParagraphStyle?)] = []
            storage.enumerateAttribute(.paragraphStyle, in: range) { value, subrange, _ in
                spans.append((subrange, value as? NSParagraphStyle))
            }
            for (subrange, existing) in spans {
                let paragraph = existing?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
                paragraph.baseWritingDirection = direction
                storage.addAttribute(.paragraphStyle, value: paragraph, range: subrange)
            }
            storage.addAttribute(.boldWriterParagraphBidi, value: isRightToLeft, range: range)
        }
    }

    func increaseIndent() {
        changeIndent(by: 36)
    }

    func decreaseIndent() {
        changeIndent(by: -36)
    }

    private func changeIndent(by amount: CGFloat) {
        mutateParagraphStyle(amount > 0 ? "Increase Indent" : "Decrease Indent") { paragraph in
            let oldHead = paragraph.headIndent
            let newHead = max(0, oldHead + amount)
            let actualChange = newHead - oldHead

            paragraph.headIndent = newHead
            paragraph.firstLineHeadIndent = max(
                0,
                paragraph.firstLineHeadIndent + actualChange
            )
        }
    }

    func setLineHeightMultiple(_ multiple: CGFloat) {
        guard multiple >= 0.8, multiple <= 3 else { return }

        lineHeightMultiple = Double(multiple)
        exactLineSpacing = 0

        mutateParagraphStyle("Line Spacing") { paragraph in
            paragraph.minimumLineHeight = 0
            paragraph.maximumLineHeight = 0
            paragraph.lineHeightMultiple = multiple
        }
    }

    func setExactLineSpacing(_ points: Double) {
        guard points >= 6, points <= 144 else { return }

        exactLineSpacing = points

        mutateParagraphStyle("Exact Line Spacing") { paragraph in
            paragraph.lineHeightMultiple = 0
            paragraph.minimumLineHeight = CGFloat(points)
            paragraph.maximumLineHeight = CGFloat(points)
        }
    }

    func setParagraphSpacingBefore(_ points: Double) {
        guard points >= 0, points <= 144 else { return }

        paragraphSpacingBefore = points

        mutateParagraphStyle("Space Before Paragraph") { paragraph in
            paragraph.paragraphSpacingBefore = CGFloat(points)
        }
    }

    func setParagraphSpacing(_ points: CGFloat) {
        guard points >= 0, points <= 144 else { return }

        paragraphSpacingAfter = Double(points)

        mutateParagraphStyle("Space After Paragraph") { paragraph in
            paragraph.paragraphSpacing = points
        }
    }

    func setFirstLineIndentInches(_ inches: Double) {
        guard inches >= 0, inches <= 3 else { return }

        firstLineIndentInches = inches
        hangingIndentInches = 0

        mutateParagraphStyle("First Line Indent") { paragraph in
            paragraph.firstLineHeadIndent =
                paragraph.headIndent + CGFloat(inches * 72)
        }
    }

    func setHangingIndentInches(_ inches: Double) {
        guard inches >= 0, inches <= 3 else { return }

        hangingIndentInches = inches
        firstLineIndentInches = 0

        mutateParagraphStyle("Hanging Indent") { paragraph in
            paragraph.firstLineHeadIndent =
                paragraph.headIndent - CGFloat(inches * 72)
        }
    }

    func clearSpecialIndent() {
        firstLineIndentInches = 0
        hangingIndentInches = 0

        mutateParagraphStyle("Clear Special Indent") { paragraph in
            paragraph.firstLineHeadIndent = paragraph.headIndent
        }
    }

    private func mutateParagraphStyle(
        _ name: String,
        mutation: (NSMutableParagraphStyle) -> Void
    ) {
        guard let textView else { return }
        defer { refreshFormattingState() }

        let range = paragraphRange(in: textView)

        if range.length == 0 {
            let paragraph =
                (textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?
                    .mutableCopy() as? NSMutableParagraphStyle
                ?? NSMutableParagraphStyle()

            mutation(paragraph)
            textView.typingAttributes[.paragraphStyle] = paragraph
            return
        }

        performUndoableMutation(name) { view in
            guard let storage = view.textStorage else { return }

            storage.enumerateAttribute(.paragraphStyle, in: range) { value, subrange, _ in
                let paragraph =
                    (value as? NSParagraphStyle)?
                        .mutableCopy() as? NSMutableParagraphStyle
                    ?? NSMutableParagraphStyle()

                mutation(paragraph)
                storage.addAttribute(.paragraphStyle, value: paragraph, range: subrange)
            }
        }
    }

    func toggleBulletList() {
        toggleList(ordered: false)
    }

    func toggleNumberedList() {
        toggleList(ordered: true)
    }

    func toggleChecklist() {
        guard let textView else { return }
        defer { refreshFormattingState() }

        let range = paragraphRange(in: textView)

        if range.length == 0 {
            var attributes = textView.typingAttributes
            let enabled =
                (attributes[.boldWriterChecklist] as? Bool)
                == true

            let paragraph =
                (attributes[.paragraphStyle] as? NSParagraphStyle)?
                    .mutableCopy()
                    as? NSMutableParagraphStyle
                ?? NSMutableParagraphStyle()

            if enabled {
                paragraph.textLists = []
                attributes.removeValue(
                    forKey:
                        .boldWriterChecklist
                )
                attributes.removeValue(
                    forKey:
                        .boldWriterChecklistChecked
                )
            } else {
                let list =
                    NSTextList(
                        markerFormat:
                            .box,
                        options:
                            0
                    )

                paragraph.textLists = [list]
                paragraph.headIndent =
                    max(
                        paragraph.headIndent,
                        36
                    )
                paragraph.firstLineHeadIndent =
                    min(
                        paragraph.firstLineHeadIndent,
                        18
                    )

                attributes[.boldWriterChecklist] =
                    true
                attributes[.boldWriterChecklistChecked] =
                    false
            }

            attributes[.paragraphStyle] =
                paragraph
            textView.typingAttributes =
                attributes
            return
        }

        var allChecklist = true

        textView.textStorage?
            .enumerateAttribute(
                .boldWriterChecklist,
                in:
                    range
            ) {
                value,
                _,
                _ in

                if (value as? Bool) != true {
                    allChecklist = false
                }
            }

        performUndoableMutation(
            "Checklist"
        ) { view in
            guard
                let storage =
                    view.textStorage
            else {
                return
            }

            var spans:
                [
                    (
                        NSRange,
                        NSParagraphStyle?
                    )
                ] =
                []

            storage.enumerateAttribute(
                .paragraphStyle,
                in:
                    range
            ) {
                value,
                subrange,
                _ in

                spans.append(
                    (
                        subrange,
                        value as? NSParagraphStyle
                    )
                )
            }

            let list =
                allChecklist
                    ? nil
                    : NSTextList(
                        markerFormat:
                            .box,
                        options:
                            0
                    )

            for (
                subrange,
                existing
            ) in spans {
                let paragraph =
                    existing?
                        .mutableCopy()
                        as? NSMutableParagraphStyle
                    ?? NSMutableParagraphStyle()

                if let list {
                    paragraph.textLists =
                        [list]
                    paragraph.headIndent =
                        max(
                            paragraph.headIndent,
                            36
                        )
                    paragraph.firstLineHeadIndent =
                        min(
                            paragraph.firstLineHeadIndent,
                            18
                        )
                } else {
                    paragraph.textLists =
                        []
                }

                storage.addAttribute(
                    .paragraphStyle,
                    value:
                        paragraph,
                    range:
                        subrange
                )
            }

            if allChecklist {
                storage.removeAttribute(
                    .boldWriterChecklist,
                    range:
                        range
                )
                storage.removeAttribute(
                    .boldWriterChecklistChecked,
                    range:
                        range
                )
            } else {
                storage.addAttribute(
                    .boldWriterChecklist,
                    value:
                        true,
                    range:
                        range
                )
                storage.addAttribute(
                    .boldWriterChecklistChecked,
                    value:
                        false,
                    range:
                        range
                )
            }
        }
    }

    func toggleChecklistItem() {
        guard let textView else { return }
        defer { refreshFormattingState() }

        let range = paragraphRange(in: textView)

        if range.length == 0 {
            var attributes =
                textView.typingAttributes

            guard
                (attributes[.boldWriterChecklist] as? Bool)
                    == true
            else {
                return
            }

            let checked =
                !(
                    (attributes[.boldWriterChecklistChecked] as? Bool)
                    ?? false
                )

            let paragraph =
                (attributes[.paragraphStyle] as? NSParagraphStyle)?
                    .mutableCopy()
                    as? NSMutableParagraphStyle
                ?? NSMutableParagraphStyle()

            paragraph.textLists =
                [
                    NSTextList(
                        markerFormat:
                            checked
                                ? .check
                                : .box,
                        options:
                            0
                    )
                ]

            attributes[.paragraphStyle] =
                paragraph
            attributes[.boldWriterChecklistChecked] =
                checked

            textView.typingAttributes =
                attributes
            return
        }

        guard
            let storage =
                textView.textStorage
        else {
            return
        }

        var allChecklist = true
        var allChecked = true

        storage.enumerateAttribute(
            .boldWriterChecklist,
            in:
                range
        ) {
            value,
            _,
            _ in

            if (value as? Bool) != true {
                allChecklist = false
            }
        }

        guard allChecklist else {
            return
        }

        storage.enumerateAttribute(
            .boldWriterChecklistChecked,
            in:
                range
        ) {
            value,
            _,
            _ in

            if (value as? Bool) != true {
                allChecked = false
            }
        }

        let checked =
            !allChecked

        performUndoableMutation(
            checked
                ? "Check Checklist Item"
                : "Uncheck Checklist Item"
        ) { view in
            guard
                let storage =
                    view.textStorage
            else {
                return
            }

            var spans:
                [
                    (
                        NSRange,
                        NSParagraphStyle?
                    )
                ] =
                []

            storage.enumerateAttribute(
                .paragraphStyle,
                in:
                    range
            ) {
                value,
                subrange,
                _ in

                spans.append(
                    (
                        subrange,
                        value as? NSParagraphStyle
                    )
                )
            }

            let list =
                NSTextList(
                    markerFormat:
                        checked
                            ? .check
                            : .box,
                    options:
                        0
                )

            for (
                subrange,
                existing
            ) in spans {
                let paragraph =
                    existing?
                        .mutableCopy()
                        as? NSMutableParagraphStyle
                    ?? NSMutableParagraphStyle()

                paragraph.textLists =
                    [list]

                storage.addAttribute(
                    .paragraphStyle,
                    value:
                        paragraph,
                    range:
                        subrange
                )
            }

            storage.addAttribute(
                .boldWriterChecklist,
                value:
                    true,
                range:
                    range
            )

            storage.addAttribute(
                .boldWriterChecklistChecked,
                value:
                    checked,
                range:
                    range
            )
        }
    }

    private func toggleList(ordered: Bool) {
        guard let textView else { return }
        defer { refreshFormattingState() }

        let range = paragraphRange(in: textView)
        let name = ordered ? "Numbered List" : "Bullet List"

        if range.length == 0 {
            let current =
                (textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?
                    .mutableCopy() as? NSMutableParagraphStyle
                ?? NSMutableParagraphStyle()

            let isChecklist =
                (textView.typingAttributes[.boldWriterChecklist] as? Bool)
                == true
            let alreadyMatching =
                !isChecklist
                    && current.textLists.last?.isOrdered == ordered

            if alreadyMatching {
                current.textLists = []
            } else {
                let list = NSTextList(
                    markerFormat: ordered ? .decimal : .disc,
                    options: 0
                )
                list.startingItemNumber = 1
                current.textLists = [list]
            }

            var attributes =
                textView.typingAttributes
            attributes[.paragraphStyle] =
                current
            attributes.removeValue(
                forKey:
                    .boldWriterChecklist
            )
            attributes.removeValue(
                forKey:
                    .boldWriterChecklistChecked
            )
            textView.typingAttributes =
                attributes
            return
        }

        var allMatching = true

        textView.textStorage?.enumerateAttribute(
            .boldWriterChecklist,
            in:
                range
        ) {
            value,
            _,
            _ in

            if (value as? Bool) == true {
                allMatching = false
            }
        }

        textView.textStorage?.enumerateAttribute(
            .paragraphStyle,
            in: range
        ) { value, _, _ in
            let style = value as? NSParagraphStyle
            if style?.textLists.last?.isOrdered != ordered {
                allMatching = false
            }
        }

        let list: NSTextList? = {
            guard !allMatching else { return nil }

            let created = NSTextList(
                markerFormat: ordered ? .decimal : .disc,
                options: 0
            )
            created.startingItemNumber = 1
            return created
        }()

        performUndoableMutation(name) { view in
            guard let storage = view.textStorage else { return }

            var spans: [(NSRange, NSParagraphStyle?)] = []

            storage.enumerateAttribute(
                .paragraphStyle,
                in: range
            ) { value, subrange, _ in
                spans.append((subrange, value as? NSParagraphStyle))
            }

            for (subrange, existing) in spans {
                let paragraph =
                    existing?.mutableCopy() as? NSMutableParagraphStyle
                    ?? NSMutableParagraphStyle()

                if let list {
                    paragraph.textLists = [list]

                    // Give native lists Word-like hanging indentation while
                    // preserving any deeper indent already applied by the user.
                    paragraph.headIndent = max(paragraph.headIndent, 36)
                    paragraph.firstLineHeadIndent = min(
                        paragraph.firstLineHeadIndent,
                        18
                    )
                } else {
                    paragraph.textLists = []
                }

                storage.addAttribute(
                    .paragraphStyle,
                    value: paragraph,
                    range: subrange
                )

                storage.removeAttribute(
                    .boldWriterChecklist,
                    range: subrange
                )

                storage.removeAttribute(
                    .boldWriterChecklistChecked,
                    range: subrange
                )
            }
        }
    }

    func applyStyle(_ style: WriterStyle) {
        guard let textView else { return }
        selectedStyle = style
        selectedNamedStyleName = style.rawValue
        let range = paragraphRange(in: textView)
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = style == .noSpacing ? 0 : (style.headingLevel == nil ? 7 : 10)
        paragraph.paragraphSpacingBefore = style.headingLevel == nil ? 0 : 8
        paragraph.lineSpacing = style == .normal ? 2 : (style == .noSpacing ? 0 : 1)
        if [.blockQuote, .quote, .intenseQuote].contains(style) {
            let inset: CGFloat = style == .intenseQuote ? 42 : 36
            paragraph.headIndent = inset
            paragraph.firstLineHeadIndent = inset
            paragraph.tailIndent = -inset
        }
        let definitions = NamedStyles.mergedWithBuiltIns(namedStyleDefinitions)
        let resolved = NamedStyles.resolve(style.wordStyleID, in: definitions)
        let actualFont: NSFont = {
            guard let resolved, let size = resolved.fontSize else { return style.font }
            var font = NSFont(name: resolved.fontFamily ?? style.font.familyName ?? "Helvetica", size: size) ?? style.font.withSize(size)
            if resolved.bold == true { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
            if resolved.italic == true { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
            return font
        }()
        if let resolved {
            paragraph.paragraphSpacingBefore = resolved.spaceBefore ?? paragraph.paragraphSpacingBefore
            paragraph.paragraphSpacing = resolved.spaceAfter ?? paragraph.paragraphSpacing
            paragraph.lineSpacing = resolved.lineSpacing ?? paragraph.lineSpacing
            paragraph.headIndent = resolved.leftIndent ?? paragraph.headIndent
            paragraph.firstLineHeadIndent = (resolved.leftIndent ?? 0) + (resolved.firstLineIndent ?? 0)
            paragraph.tailIndent = resolved.rightIndent.map { -$0 } ?? paragraph.tailIndent
            if let alignment = resolved.alignment {
                switch alignment.lowercased() {
                case "center": paragraph.alignment = .center
                case "right": paragraph.alignment = .right
                case "justified": paragraph.alignment = .justified
                default: paragraph.alignment = .left
                }
            }
        }
        var attributes: [NSAttributedString.Key: Any] = [.font: actualFont, .paragraphStyle: paragraph, .boldWriterStyle: style.rawValue]
        if let hex = resolved?.foregroundColor, let value = UInt32(hex, radix: 16) {
            attributes[.foregroundColor] = NSColor(calibratedRed: CGFloat((value >> 16) & 0xff) / 255, green: CGFloat((value >> 8) & 0xff) / 255, blue: CGFloat(value & 0xff) / 255, alpha: 1)
        }
        if range.length == 0 {
            textView.typingAttributes.removeValue(forKey: .boldWriterParagraphStyle)
            attributes.forEach { textView.typingAttributes[$0.key] = $0.value }
            return
        }
        performUndoableMutation("Apply \(style.rawValue)") { view in
            guard let storage = view.textStorage else { return }
            var spans: [(NSRange, [NSTextBlock])] = []
            storage.enumerateAttribute(.paragraphStyle, in: range) { value, subrange, _ in
                spans.append((subrange, (value as? NSParagraphStyle)?.textBlocks ?? []))
            }
            for (subrange, blocks) in spans {
                var applied = attributes
                let copy = paragraph.mutableCopy() as! NSMutableParagraphStyle
                copy.textBlocks = blocks; applied[.paragraphStyle] = copy
                storage.addAttributes(applied, range: subrange)
                storage.removeAttribute(.boldWriterParagraphStyle, range: subrange)
            }
        }
    }


    func insertFootnote(
        text: String = "",
        trackChanges: Bool = false
    ) {
        guard
            let view = textView
        else {
            return
        }

        let location =
            view.selectedRange()
                .location

        let note =
            Footnote(
                text: text,
                location: location,
                length: 1
            )

        replace(
            range:
                NSRange(
                    location: location,
                    length: 0
                ),
            with:
                Footnotes.marker(
                    note,
                    number: 1
                ),
            actionName:
                "Insert Footnote",
            trackChanges:
                trackChanges
        )

        editingFootnote = note

        clearFootnoteTypingAttributes()
        clearEndnoteTypingAttributes()
    }

    func editSelectedFootnote() {
        guard let view = textView, let notes = try? Footnotes.records(in: view.attributedString()) else { return }
        editingFootnote = notes.first { NSLocationInRange(view.selectedRange().location, NSRange(location: $0.location, length: $0.length)) }
    }

    func updateFootnote(
        id: UUID,
        text: String,
        trackChanges: Bool = false
    ) {
        guard
            let view = textView,
            let notes =
                try? Footnotes.records(
                    in:
                        view.attributedString()
                ),
            let note =
                notes.first(
                    where: {
                        $0.id == id
                    }
                ),
            note.text != text
        else {
            return
        }

        performUndoableMutation(
            "Edit Footnote"
        ) { view in
            guard
                let storage =
                    view.textStorage
            else {
                return
            }

            var updated = note
            updated.text = text

            if trackChanges {
                if updated
                    .bodyChangeOriginalText == nil {
                    updated
                        .bodyChangeOriginalText =
                        note.text

                    updated.bodyChangeID =
                        UUID()

                    updated
                        .bodyChangeAuthor =
                        NSFullUserName()

                    updated.bodyChangeDate =
                        Date()
                }

                if text ==
                    updated
                        .bodyChangeOriginalText {
                    updated
                        .bodyChangeOriginalText =
                        nil

                    updated.bodyChangeID =
                        nil

                    updated
                        .bodyChangeAuthor =
                        nil

                    updated.bodyChangeDate =
                        nil
                }
            } else {
                updated
                    .bodyChangeOriginalText =
                    nil

                updated.bodyChangeID =
                    nil

                updated
                    .bodyChangeAuthor =
                    nil

                updated.bodyChangeDate =
                    nil
            }

            storage.addAttribute(
                .footnote,
                value:
                    Footnotes.payload(
                        updated
                    ),
                range:
                    NSRange(
                        location:
                            note.location,
                        length:
                            note.length
                    )
            )
        }

        refreshTrackChangeDisplay()
    }

    func deleteFootnote(
        id: UUID,
        trackChanges: Bool = false
    ) {
        guard
            let view = textView,
            let notes =
                try? Footnotes.records(
                    in:
                        view.attributedString()
                ),
            let note =
                notes.first(
                    where: {
                        $0.id == id
                    }
                )
        else {
            return
        }

        replace(
            range:
                NSRange(
                    location:
                        note.location,
                    length:
                        note.length
                ),
            with:
                NSAttributedString(
                    string: ""
                ),
            actionName:
                "Delete Footnote",
            trackChanges:
                trackChanges
        )
    }

    func normalizeFootnotes() {
        guard let view = textView, let storage = view.textStorage,
              let notes = try? Footnotes.records(in: storage), !notes.isEmpty else { return }
        let selected = view.selectedRange()
        func shifted(_ point: Int) -> Int {
            var offset = 0
            for (index, note) in notes.enumerated() {
                let length = String(index + 1).utf16.count
                if point >= note.location + note.length { offset += length - note.length }
                else if point > note.location { return note.location + offset + min(point - note.location, length) }
            }
            return point + offset
        }
        let start = shifted(selected.location), end = shifted(NSMaxRange(selected))
        try? Footnotes.renumber(storage)
        view.setSelectedRange(NSRange(location: min(start, storage.length), length: max(0, min(end, storage.length) - min(start, storage.length))))
    }

    func clearFootnoteTypingAttributes() {
        guard let view = textView, view.typingAttributes[.footnote] != nil else { return }
        view.typingAttributes.removeValue(forKey: .footnote)
        view.typingAttributes.removeValue(forKey: .superscript)
        view.typingAttributes[.font] = WriterStyle.defaultFont
    }

    func insertEndnote(
        text: String = "",
        trackChanges: Bool = false
    ) {
        guard
            let view = textView
        else {
            return
        }

        let location =
            view.selectedRange()
                .location

        let note =
            Endnote(
                text: text,
                location: location,
                length: 1
            )

        replace(
            range:
                NSRange(
                    location: location,
                    length: 0
                ),
            with:
                Endnotes.marker(
                    note,
                    number: 1
                ),
            actionName:
                "Insert Endnote",
            trackChanges:
                trackChanges
        )

        editingEndnote = note

        clearEndnoteTypingAttributes()
    }

    func editSelectedEndnote() {
        guard let view = textView, let notes = try? Endnotes.records(in: view.attributedString()) else { return }
        editingEndnote = notes.first { NSLocationInRange(view.selectedRange().location, NSRange(location: $0.location, length: $0.length)) }
    }

    func updateEndnote(
        id: UUID,
        text: String,
        trackChanges: Bool = false
    ) {
        guard
            let view = textView,
            let notes =
                try? Endnotes.records(
                    in:
                        view.attributedString()
                ),
            let note =
                notes.first(
                    where: {
                        $0.id == id
                    }
                ),
            note.text != text
        else {
            return
        }

        performUndoableMutation(
            "Edit Endnote"
        ) { view in
            guard
                let storage =
                    view.textStorage
            else {
                return
            }

            var updated = note
            updated.text = text

            if trackChanges {
                if updated
                    .bodyChangeOriginalText == nil {
                    updated
                        .bodyChangeOriginalText =
                        note.text

                    updated.bodyChangeID =
                        UUID()

                    updated
                        .bodyChangeAuthor =
                        NSFullUserName()

                    updated.bodyChangeDate =
                        Date()
                }

                if text ==
                    updated
                        .bodyChangeOriginalText {
                    updated
                        .bodyChangeOriginalText =
                        nil

                    updated.bodyChangeID =
                        nil

                    updated
                        .bodyChangeAuthor =
                        nil

                    updated.bodyChangeDate =
                        nil
                }
            } else {
                updated
                    .bodyChangeOriginalText =
                    nil

                updated.bodyChangeID =
                    nil

                updated
                    .bodyChangeAuthor =
                    nil

                updated.bodyChangeDate =
                    nil
            }

            storage.addAttribute(
                .endnote,
                value:
                    Endnotes.payload(
                        updated
                    ),
                range:
                    NSRange(
                        location:
                            note.location,
                        length:
                            note.length
                    )
            )
        }

        refreshTrackChangeDisplay()
    }

    func deleteEndnote(
        id: UUID,
        trackChanges: Bool = false
    ) {
        guard
            let view = textView,
            let notes =
                try? Endnotes.records(
                    in:
                        view.attributedString()
                ),
            let note =
                notes.first(
                    where: {
                        $0.id == id
                    }
                )
        else {
            return
        }

        replace(
            range:
                NSRange(
                    location:
                        note.location,
                    length:
                        note.length
                ),
            with:
                NSAttributedString(
                    string: ""
                ),
            actionName:
                "Delete Endnote",
            trackChanges:
                trackChanges
        )
    }

    func normalizeEndnotes() {
        guard let view = textView, let storage = view.textStorage,
              let notes = try? Endnotes.records(in: storage), !notes.isEmpty else { return }
        let selected = view.selectedRange()
        func shifted(_ point: Int) -> Int {
            var offset = 0
            for (index, note) in notes.enumerated() {
                let length = String(index + 1).utf16.count
                if point >= note.location + note.length { offset += length - note.length }
                else if point > note.location { return note.location + offset + min(point - note.location, length) }
            }
            return point + offset
        }
        let start = shifted(selected.location), end = shifted(NSMaxRange(selected))
        try? Endnotes.renumber(storage)
        view.setSelectedRange(NSRange(location: min(start, storage.length), length: max(0, min(end, storage.length) - min(start, storage.length))))
    }

    func clearEndnoteTypingAttributes() {
        guard let view = textView, view.typingAttributes[.endnote] != nil else { return }
        view.typingAttributes.removeValue(forKey: .endnote)
        view.typingAttributes.removeValue(forKey: .superscript)
        view.typingAttributes[.font] = WriterStyle.defaultFont
    }

    func insertPageBreak() { textView?.insertText("\u{000C}", replacementRange: textView?.selectedRange() ?? NSRange(location: 0, length: 0)) }
    func insertHorizontalRule() { textView?.insertText("\n────────────────────────────\n", replacementRange: textView?.selectedRange() ?? NSRange(location: 0, length: 0)) }

    func insertEquationText(
        _ text: String
    ) {
        guard
            !text.isEmpty,
            let textView
        else {
            return
        }

        textView.insertText(
            text,
            replacementRange:
                textView.selectedRange()
        )
    }

    func navigate(
        to range: NSRange
    ) {
        guard
            let textView,
            Self.isValid(
                range,
                length:
                    textView.textStorage?
                        .length ?? 0
            )
        else {
            return
        }

        if let canvas =
            textView.superview
                as? PaginatedEditor {

            let destination =
                canvas.reveal(
                    character:
                        range.location,
                    focus: false
                )

            destination.setSelectedRange(
                range
            )

            attach(
                destination
            )

            destination
                .scrollRangeToVisible(
                    range
                )

            destination.window?
                .makeFirstResponder(
                    destination
                )

            return
        }

        textView.setSelectedRange(
            range
        )

        updateSelection(
            range
        )

        textView.scrollRangeToVisible(
            range
        )

        textView.window?
            .makeFirstResponder(
                textView
            )
    }

    @discardableResult
    func applyManuscriptReplacement(
        _ replacement: String,
        in range: NSRange,
        expectedText: String
    ) -> Bool {
        guard let textView, textView.isEditable, let storage = textView.textStorage,
              Self.isValid(range, length: storage.length),
              (storage.string as NSString).substring(with: range) == expectedText else {
            return false
        }
        let expectedDocument = (storage.string as NSString)
            .replacingCharacters(in: range, with: replacement)
        let tracksChanges = document?.metadata.trackChangesEnabled ?? false
        let attributed = Self.replacementPreservingAttributes(
            replacement,
            from: storage,
            range: range
        )
        replace(
            range: range,
            with: attributed,
            actionName: "Apply Book Audit Correction",
            trackChanges: tracksChanges
        )
        return storage.string == expectedDocument || tracksChanges
    }

    @discardableResult
    func addComment(text: String, author: String = NSFullUserName(), to document: BOLDWriterDocument) throws -> DocumentComment {
        let current = selection
        guard current.location >= 0, current.length >= 0,
              current.location <= document.text.length,
              current.length <= document.text.length - current.location,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WriterError.message("Select valid document text and enter a comment.")
        }
        let comment = DocumentComment(text: text, author: author, location: current.location, length: current.length)
        var comments = document.metadata.comments
        comments.append(comment)
        try DocumentComments.validate(comments, textLength: document.text.length)
        document.metadata.comments = comments
        selectedCommentID = comment.id
        return comment
    }

    func editComment(id: UUID, text: String, in document: BOLDWriterDocument) throws {
        guard let index = document.metadata.comments.firstIndex(where: { $0.id == id }),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        document.metadata.comments[index].text = text
        selectedCommentID = id
    }

    func deleteComment(id: UUID, in document: BOLDWriterDocument) {
        document.metadata.comments.removeAll { $0.id == id }
        if selectedCommentID == id { selectedCommentID = nil }
    }

    func selectComment(id: UUID, in document: BOLDWriterDocument) {
        guard let comment = document.metadata.comments.first(where: { $0.id == id }) else { return }
        selectedCommentID = id
        navigate(to: NSRange(location: comment.location, length: comment.length))
    }

    func navigateComment(previous: Bool, in document: BOLDWriterDocument) {
        let comments = document.metadata.comments.sorted {
            $0.location == $1.location ? $0.id.uuidString < $1.id.uuidString : $0.location < $1.location
        }
        guard !comments.isEmpty else { return }
        let target: DocumentComment?
        if previous {
            target = comments.last(where: { $0.location < selection.location }) ?? comments.last
        } else {
            target = comments.first(where: { $0.location > selection.location }) ?? comments.first
        }
        if let target { selectComment(id: target.id, in: document) }
    }

    func replace(
        range: NSRange,
        with attributed: NSAttributedString,
        actionName: String,
        trackChanges: Bool = false
    ) {
        guard
            let textView,
            textView.isEditable,
            let storage = textView.textStorage,
            Self.isValid(
                range,
                length: storage.length
            )
        else {
            return
        }

        let safeRange =
            NoteReferences.editingRange(
                range,
                in: storage
            )

        if handleTableEdit(
            range: safeRange,
            replacement: attributed,
            trackChanges: trackChanges
        ) {
            return
        }

        if trackChanges,
           safeRange == range {
            _ = trackTextEdit(
                range: safeRange,
                replacement: attributed,
                actionName:
                    actionName
            )
            return
        }

        performUndoableMutation(
            actionName
        ) { view in
            storage.replaceCharacters(
                in: safeRange,
                with: attributed
            )

            view.setSelectedRange(
                NSRange(
                    location: safeRange.location,
                    length: attributed.length
                )
            )
        }
    }

    func insertImage(data: Data, name: String, maximumWidth: CGFloat) throws {
        guard let textView, textView.isEditable else {
            throw WriterError.message("The document is not editable.")
        }
        guard let image = NSImage(data: data), image.isValid,
              DOCXImages.validSize(image.size) else {
            throw WriterError.message("The selected file is not a readable image.")
        }
        let scale = min(1, max(1, maximumWidth) / image.size.width)
        let displaySize = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        guard let attachment = DOCXImages.attachment(data: data, name: name, size: displaySize) else {
            throw WriterError.message("The selected image could not be inserted.")
        }
        let inserted = NSMutableAttributedString(attachment: attachment)
        inserted.addAttribute(.boldWriterInlineImageDisplaySize,
                              value: "\(displaySize.width),\(displaySize.height)" as NSString,
                              range: NSRange(location: 0, length: inserted.length))
        replace(
            range: textView.selectedRange(),
            with: inserted,
            actionName: "Insert Image",
            trackChanges: document?.metadata.trackChangesEnabled ?? false
        )
    }

    func replaceAll(
        _ ranges: [NSRange],
        with replacement: String,
        trackChanges: Bool = false
    ) {
        replaceMatches(
            ranges.map { SearchReplacement(range: $0, text: replacement) },
            trackChanges: trackChanges
        )
    }

    /// Commits a fully validated BOLD Script preview as one native Undo action.
    /// The candidate is built before entering this method, so rejected plans
    /// cannot leave partial edits in the NSTextStorage.
    @discardableResult
    func applyBOLDScriptPlan(_ plan: BOLDScriptPlan, title: String) -> Bool {
        guard let view = textView, view.isEditable,
              let storage = view.textStorage else { return false }
        let document = self.document
        let textChanged = !storage.isEqual(to: plan.output)
        let plannedImages: [FloatingImage]? = plan.floatingImages.isEmpty ? nil : plan.floatingImages
        let imagesChanged = document.map { $0.metadata.floatingImages != plannedImages } ?? false
        guard textChanged || imagesChanged, !imagesChanged || document != nil else { return false }
        do { _ = try Tables.records(in: plan.output) }
        catch { return false }
        do { try FloatingImage.validate(plan.floatingImages, textLength: plan.output.length) }
        catch { return false }
        let undo = view.undoManager
        undo?.beginUndoGrouping()
        if textChanged {
            performUndoableMutation("BOLD Script: \(title)") { $0.textStorage?.setAttributedString(plan.output) }
        }
        if imagesChanged, let document {
            registerFloatingImagesUndo(document: document, undoManager: undo)
            document.updateFloatingImages(plannedImages)
        }
        undo?.setActionName("BOLD Script: \(title)")
        undo?.endUndoGrouping()
        view.didChangeText()
        return true
    }

    private func registerFloatingImagesUndo(document: BOLDWriterDocument, undoManager: UndoManager?) {
        let previous = document.metadata.floatingImages
        undoManager?.registerUndo(withTarget: self) { target in
            guard let document = target.document else { return }
            target.registerFloatingImagesUndo(document: document, undoManager: undoManager)
            document.updateFloatingImages(previous)
        }
    }

    @discardableResult
    func setFloatingImages(_ images: [FloatingImage], in document: BOLDWriterDocument, actionName: String) -> Bool {
        do { try FloatingImage.validate(images, textLength: document.text.length) }
        catch { document.lastErrorMessage = error.localizedDescription; return false }
        let next: [FloatingImage]? = images.isEmpty ? nil : images
        guard document.metadata.floatingImages != next else { return true }
        let manager = textView?.undoManager
        registerFloatingImagesUndo(document: document, undoManager: manager)
        document.updateFloatingImages(next)
        manager?.setActionName(actionName)
        return true
    }

    @discardableResult
    func insertFloatingImage(data: Data, assetName: String) -> Bool {
        guard let document, let view = textView, let image = NSImage(data: data), let size = image.representations.first.map({ NSSize(width: $0.pixelsWide, height: $0.pixelsHigh) }) else { return false }
        let scale = min(1, 216 / max(size.width, size.height))
        let width = max(1, size.width * scale)
        let height = max(1, size.height * scale)
        let pageIndex = max(0, (view as? WritingTextView).map { $0.pageNumber - 1 } ?? 0)
        var images = document.metadata.floatingImages ?? []
        let imageRecord = FloatingImage(assetName: assetName, imageData: data, pageIndex: pageIndex,
                                        anchor: .page, x: 72, y: 72, width: width, height: height,
                                        zOrder: (images.map(\.zOrder).max() ?? -1) + 1)
        images.append(imageRecord)
        guard setFloatingImages(images, in: document, actionName: "Insert Floating Image") else { return false }
        selectedFloatingImageID = imageRecord.id
        return true
    }

    @discardableResult
    func convertSelectedInlineImageToFloating() -> Bool {
        guard let document, let view = textView, let storage = view.textStorage else { return false }
        let selection = view.selectedRange()
        guard selection.location < storage.length else { return false }
        var attachmentIndex: Int?
        var attachment: NSTextAttachment?
        storage.enumerateAttribute(.attachment, in: selection.length > 0 ? selection : NSRange(location: selection.location, length: 1)) { value, range, stop in
            if let found = value as? NSTextAttachment { attachment = found; attachmentIndex = range.location; stop.pointee = true }
        }
        guard let attachment, let attachmentIndex,
              let bytes = attachment.fileWrapper?.regularFileContents ?? attachment.contents,
              let source = NSImage(data: bytes) else { return false }
        let bounds = attachment.bounds
        let sourceSize = bounds.size.width > 0 && bounds.size.height > 0 ? bounds.size : source.size
        guard sourceSize.width > 0, sourceSize.height > 0 else { return false }
        let factor = min(1, 216 / max(sourceSize.width, sourceSize.height))
        let pageIndex = max(0, (view as? WritingTextView).map { $0.pageNumber - 1 } ?? 0)
        let imageRecord = FloatingImage(assetName: attachment.fileWrapper?.preferredFilename ?? "Inline image",
                                       imageData: bytes, pageIndex: pageIndex, anchor: .page,
                                       x: 72, y: 72, width: Double(sourceSize.width * factor), height: Double(sourceSize.height * factor),
                                       zOrder: (document.metadata.floatingImages?.map(\.zOrder).max() ?? -1) + 1)
        var images = document.metadata.floatingImages ?? []
        images.append(imageRecord)
        guard let manager = view.undoManager else { return false }
        manager.beginUndoGrouping()
        guard setFloatingImages(images, in: document, actionName: "Convert Picture to Floating") else { manager.endUndoGrouping(); return false }
        performUndoableMutation("Convert Picture to Floating") { textView in
            textView.textStorage?.deleteCharacters(in: NSRange(location: attachmentIndex, length: 1))
            textView.setSelectedRange(NSRange(location: min(attachmentIndex, textView.textStorage?.length ?? 0), length: 0))
        }
        manager.setActionName("Convert Picture to Floating")
        manager.endUndoGrouping()
        selectedFloatingImageID = imageRecord.id
        return true
    }

    @discardableResult
    func convertFloatingImageToInline(_ id: UUID) -> Bool {
        guard let document, let view = textView, let storage = view.textStorage,
              let image = document.metadata.floatingImages?.first(where: { $0.id == id }),
              let manager = view.undoManager else { return false }
        let attachment = NSTextAttachment(fileWrapper: FileWrapper(regularFileWithContents: image.imageData))
        guard let source = NSImage(data: image.imageData) else { return false }
        source.size = NSSize(width: image.width, height: image.height)
        attachment.attachmentCell = NSTextAttachmentCell(imageCell: source)
        attachment.bounds = NSRect(x: 0, y: 0, width: image.width, height: image.height)
        let inline = NSMutableAttributedString(attachment: attachment)
        inline.addAttribute(.boldWriterInlineImageDisplaySize,
                            value: "\(image.width),\(image.height)" as NSString,
                            range: NSRange(location: 0, length: inline.length))
        let location = min(view.selectedRange().location, storage.length)
        var images = document.metadata.floatingImages ?? []
        images.removeAll { $0.id == id }
        manager.beginUndoGrouping()
        guard setFloatingImages(images, in: document, actionName: "Convert Floating Image to Inline") else { manager.endUndoGrouping(); return false }
        performUndoableMutation("Convert Floating Image to Inline") { textView in
            textView.textStorage?.insert(inline, at: location)
            textView.setSelectedRange(NSRange(location: location + 1, length: 0))
        }
        manager.setActionName("Convert Floating Image to Inline")
        manager.endUndoGrouping()
        selectedFloatingImageID = nil
        return true
    }

    /// Apply precomputed replacements from right to left in one undo group.
    /// Each match inherits its own formatting, including regex capture edits.
    @discardableResult
    func replaceMatches(
        _ replacements: [SearchReplacement],
        trackChanges: Bool = false,
        actionName: String = "Replace All"
    ) -> Bool {
        guard let view = textView, view.isEditable,
              let storage = view.textStorage,
              !replacements.isEmpty,
              replacements.allSatisfy({ Self.isValid($0.range, length: storage.length) }) else {
            return false
        }

        let ordered = replacements.sorted { $0.range.location < $1.range.location }
        for index in ordered.indices.dropFirst() {
            let previous = ordered[index - 1].range
            let current = ordered[index].range
            guard NSMaxRange(previous) <= current.location,
                  previous != current else { return false }
        }

        guard let safeRanges = try? NoteReferences.editingRanges(ordered.map(\.range), in: storage) else { return false }
        var normalized: [SearchReplacement] = []
        for (replacement, range) in zip(ordered, safeRanges) {
            normalized.append(SearchReplacement(range: range, text: replacement.text))
        }
        normalized.sort { lhs, rhs in
            if lhs.range.location == rhs.range.location {
                return lhs.range.length > rhs.range.length
            }
            return lhs.range.location < rhs.range.location
        }
        var expanded: [SearchReplacement] = []
        for replacement in normalized {
            let safe = replacement.range
            if let last = expanded.last, NSIntersectionRange(last.range, safe).length > 0 {
                // Two matches inside the same note reference must not create
                // two copies of a note. Conflicting capture edits are rejected.
                guard last.text == replacement.text else { return false }
                expanded[expanded.count - 1].range = NSUnionRange(last.range, safe)
            } else {
                if let last = expanded.last {
                    // Moving an insertion outside a numbered reference can
                    // collide with another edit. Reject the whole batch.
                    guard NSMaxRange(last.range) <= safe.location,
                          last.range.location != safe.location else { return false }
                }
                expanded.append(replacement)
            }
        }

        let candidate = NSMutableAttributedString(attributedString: storage)
        let prepared = expanded.map { replacement in
            (replacement.range, NSAttributedString(
                string: replacement.text,
                attributes: replacementAttributes(at: replacement.range.location, in: storage, fallback: view.typingAttributes)
            ))
        }
        for (range, replacement) in prepared.reversed() {
            candidate.replaceCharacters(in: range, with: replacement)
        }
        // Never consume only part of a table boundary.
        do { _ = try Tables.records(in: candidate) }
        catch { return false }

        if trackChanges {
            let undoManager = view.undoManager
            let openedUndoGroup = (undoManager?.groupingLevel ?? 0) == 0
            if openedUndoGroup { undoManager?.beginUndoGrouping() }
            defer {
                undoManager?.setActionName(actionName)
                if openedUndoGroup { undoManager?.endUndoGrouping() }
            }
            for (range, replacement) in prepared.reversed() {
                guard trackTextEdit(range: range, replacement: replacement, actionName: actionName) else { return false }
            }
        } else {
            performUndoableMutation(actionName) { view in
                view.textStorage?.setAttributedString(candidate)
                if actionName == "Replace", let first = prepared.first {
                    view.setSelectedRange(NSRange(location: first.0.location, length: first.1.length))
                }
            }
        }
        return true
    }

    private func replacementAttributes(
        at location: Int,
        in text: NSAttributedString,
        fallback: [NSAttributedString.Key: Any]
    ) -> [NSAttributedString.Key: Any] {
        var attributes = location < text.length
            ? text.attributes(at: location, effectiveRange: nil)
            : fallback
        let hadFootnote = attributes.removeValue(forKey: .footnote) != nil
        let hadEndnote = attributes.removeValue(forKey: .endnote) != nil
        if hadFootnote || hadEndnote { attributes.removeValue(forKey: .superscript) }
        attributes.removeValue(forKey: .attachment)
        attributes.removeValue(forKey: .boldWriterWordPictureCrop)
        return attributes
    }

    private static func isValid(_ range: NSRange, length: Int) -> Bool {
        range.location >= 0 && range.length >= 0 && range.location <= length && range.length <= length - range.location
    }

    private func paragraphRange(in textView: NSTextView) -> NSRange {
        guard !textView.string.isEmpty else { return NSRange(location: 0, length: 0) }
        return (textView.string as NSString).paragraphRange(for: textView.selectedRange())
    }

    private func isFormattingMutation(
        _ name: String
    ) -> Bool {
        switch name {
        case "Format Font",
             "Underline",
             "Strikethrough",
             "Font Size",
             "Font Family",
             "Text Color",
             "Highlight",
             "Paragraph Alignment",
             "Increase Indent",
             "Decrease Indent",
             "Line Spacing",
             "Exact Line Spacing",
             "Space Before Paragraph",
             "Space After Paragraph",
             "First Line Indent",
             "Hanging Indent",
             "Clear Special Indent",
             "Bullet List",
             "Numbered List":
            return true

        default:
            // applyStyle() is the only EditorController mutation
            // currently named "Apply <style>".
            return name.hasPrefix(
                "Apply "
            )
        }
    }

    @discardableResult
    private func convertFormattingMutationToRevisionPairs(
        name: String,
        before: NSAttributedString,
        selection: NSRange,
        in view: NSTextView
    ) -> Bool {
        guard
            isFormattingMutation(name),
            trackChangesProvider?() == true,
            let storage = view.textStorage
        else {
            return false
        }

        let after =
            view.attributedString()
                .copy()
                as! NSAttributedString

        // Formatting tracking is intentionally limited to
        // character-preserving mutations. Text edits continue
        // through trackTextEdit().
        guard
            before.length == after.length,
            before.string == after.string,
            before.length > 0
        else {
            return false
        }

        let full =
            NSRange(
                location: 0,
                length:
                    before.length
            )

        var changedRanges:
            [NSRange] = []

        var location = 0

        while location < before.length {
            var beforeRange =
                NSRange()

            var afterRange =
                NSRange()

            let beforeAttributes =
                before.attributes(
                    at:
                        location,
                    longestEffectiveRange:
                        &beforeRange,
                    in:
                        full
                )

            let afterAttributes =
                after.attributes(
                    at:
                        location,
                    longestEffectiveRange:
                        &afterRange,
                    in:
                        full
                )

            var next =
                min(
                    NSMaxRange(
                        beforeRange
                    ),
                    NSMaxRange(
                        afterRange
                    )
                )

            if next <= location {
                next =
                    location + 1
            }

            let changed =
                !(beforeAttributes as NSDictionary)
                    .isEqual(
                        afterAttributes
                            as NSDictionary
                    )

            if changed {
                let piece =
                    NSRange(
                        location:
                            location,
                        length:
                            next - location
                    )

                if let last =
                    changedRanges.last,
                   NSMaxRange(last)
                    == piece.location {
                    changedRanges[
                        changedRanges.count - 1
                    ] =
                        NSRange(
                            location:
                                last.location,
                            length:
                                last.length
                                + piece.length
                        )
                } else {
                    changedRanges.append(
                        piece
                    )
                }
            }

            location =
                next
        }

        guard
            !changedRanges.isEmpty
        else {
            return false
        }

        let existingChanges =
            TrackChanges.records(
                in:
                    before
            )

        let notes =
            (
                try? Footnotes.records(
                    in:
                        before
                )
            ) ?? []

        let cells =
            (
                try? Tables.records(
                    in:
                        before
                )
            ) ?? []

        func overlaps(
            _ lhs: NSRange,
            _ rhs: NSRange
        ) -> Bool {
            NSIntersectionRange(
                lhs,
                rhs
            )
            .length > 0
        }

        func containsAttachment(
            _ range: NSRange
        ) -> Bool {
            var found =
                false

            before.enumerateAttribute(
                .attachment,
                in:
                    range
            ) {
                value,
                _,
                stop in

                if value != nil {
                    found =
                        true

                    stop.pointee =
                        true
                }
            }

            return found
        }

        let eligible =
            changedRanges.filter {
                range in

                // Formatting a pending insertion simply updates
                // that pending content. Do not nest revisions.
                guard
                    !existingChanges
                        .contains(
                            where: {
                                overlaps(
                                    range,
                                    NSRange(
                                        location:
                                            $0.location,
                                        length:
                                            $0.length
                                    )
                                )
                            }
                        )
                else {
                    return false
                }

                // Structured atomic content must not be duplicated
                // into a formatting pair.
                guard
                    !notes.contains(
                        where: {
                            overlaps(
                                range,
                                NSRange(
                                    location:
                                        $0.location,
                                    length:
                                        $0.length
                                )
                            )
                        }
                    ),
                    !cells.contains(
                        where: {
                            overlaps(
                                range,
                                NSRange(
                                    location:
                                        $0.location,
                                    length:
                                        $0.length
                                )
                            )
                        }
                    ),
                    !containsAttachment(
                        range
                    )
                else {
                    return false
                }

                return true
            }

        guard
            !eligible.isEmpty
        else {
            return false
        }

        let author =
            NSFullUserName()

        let date =
            Date()

        var trackedRanges:
            [NSRange] = []

        // Work right-to-left so original coordinates remain valid.
        for range in eligible.reversed() {
            let original =
                NSMutableAttributedString(
                    attributedString:
                        before
                            .attributedSubstring(
                                from:
                                    range
                            )
                )

            let proposed =
                NSMutableAttributedString(
                    attributedString:
                        after
                            .attributedSubstring(
                                from:
                                    range
                            )
                )

            guard
                !original.isEqual(
                    to:
                        proposed
                )
            else {
                continue
            }

            let revisionID =
                UUID()

            original.addAttribute(
                .boldWriterTrackChange,
                value:
                    TrackChanges.marker(
                        id:
                            revisionID,
                        kind:
                            .deletion,
                        author:
                            author,
                        date:
                            date
                    ),
                range:
                    NSRange(
                        location: 0,
                        length:
                            original.length
                    )
            )

            proposed.addAttribute(
                .boldWriterTrackChange,
                value:
                    TrackChanges.marker(
                        id:
                            revisionID,
                        kind:
                            .insertion,
                        author:
                            author,
                        date:
                            date
                    ),
                range:
                    NSRange(
                        location: 0,
                        length:
                            proposed.length
                    )
            )

            let pair =
                NSMutableAttributedString()

            pair.append(
                original
            )

            pair.append(
                proposed
            )

            storage.replaceCharacters(
                in:
                    range,
                with:
                    pair
            )

            trackedRanges.append(
                range
            )
        }

        guard
            !trackedRanges.isEmpty
        else {
            return false
        }

        // Keep the user's caret/selection on the proposed copy.
        let sorted =
            trackedRanges.sorted {
                $0.location
                    < $1.location
            }

        func mappedPosition(
            _ rawPosition: Int
        ) -> Int {
            var shift = 0

            for range in sorted {
                if rawPosition
                    < range.location {
                    break
                }

                if rawPosition
                    <= NSMaxRange(
                        range
                    ) {
                    return min(
                        rawPosition
                            + shift
                            + range.length,
                        storage.length
                    )
                }

                shift +=
                    range.length
            }

            return min(
                rawPosition
                    + shift,
                storage.length
            )
        }

        let mappedStart =
            mappedPosition(
                selection.location
            )

        let mappedEnd =
            mappedPosition(
                NSMaxRange(
                    selection
                )
            )

        view.setSelectedRange(
            NSRange(
                location:
                    mappedStart,
                length:
                    max(
                        0,
                        mappedEnd
                            - mappedStart
                    )
            )
        )

        return true
    }

    func performUndoableMutation(_ name: String, _ mutation: (NSTextView) -> Void) {
        guard let textView else { return }

        let before =
            textView
                .attributedString()
                .copy()
                as! NSAttributedString

        let selected =
            textView.selectedRange()

        let selectedReviewID =
            selectedReviewChangeID

        mutation(textView)

        let trackedFormatting =
            convertFormattingMutationToRevisionPairs(
                name:
                    name,
                before:
                    before,
                selection:
                    selected,
                in:
                    textView
            )

        normalizeFootnotes()
        normalizeEndnotes()

        guard
            !before.isEqual(
                to:
                    textView.attributedString()
            )
        else {
            return
        }

        let undoManager =
            textView.undoManager

        let openedUndoGroup =
            (undoManager?.groupingLevel
                ?? 0) == 0

        if openedUndoGroup {
            undoManager?
                .beginUndoGrouping()
        }

        undoManager?
            .registerUndo(
                withTarget: self
            ) {
                target in

                target.restore(
                    before,
                    selection:
                        selected,
                    reviewChangeID:
                        selectedReviewID,
                    actionName:
                        name
                )
            }

        undoManager?
            .setActionName(
                name
            )

        if openedUndoGroup {
            undoManager?
                .endUndoGrouping()
        }

        textView.didChangeText()

        updateSelection(
            textView.selectedRange()
        )

        if trackedFormatting {
            refreshTrackChangeDisplay()
        }
    }

    private func restore(
        _ snapshot: NSAttributedString,
        selection: NSRange,
        reviewChangeID: UUID?,
        actionName: String
    ) {
        guard let textView else {
            return
        }

        let inverse =
            textView
                .attributedString()
                .copy()
                as! NSAttributedString

        let inverseSelection =
            textView.selectedRange()

        let inverseReviewChangeID =
            selectedReviewChangeID

        textView.undoManager?
            .registerUndo(
                withTarget: self
            ) {
                target in

                target.restore(
                    inverse,
                    selection:
                        inverseSelection,
                    reviewChangeID:
                        inverseReviewChangeID,
                    actionName:
                        actionName
                )
            }

        textView.textStorage?
            .setAttributedString(
                snapshot
            )

        let location =
            min(
                selection.location,
                snapshot.length
            )

        let length =
            min(
                selection.length,
                snapshot.length
                    - location
            )

        textView.setSelectedRange(
            NSRange(
                location:
                    location,
                length:
                    length
            )
        )

        if let reviewChangeID,
           TrackChanges.reviewItems(
                in: snapshot
           )
           .contains(
                where: {
                    $0.id
                        == reviewChangeID
                }
           ) {
            selectedReviewChangeID =
                reviewChangeID
        } else {
            selectedReviewChangeID =
                nil
        }

        textView.undoManager?
            .setActionName(
                actionName
            )

        textView.didChangeText()

        updateSelection(
            textView.selectedRange()
        )

        refreshTrackChangeDisplay()
    }
}
