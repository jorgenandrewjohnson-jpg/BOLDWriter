import AppKit

enum NamedStyleKind: String, Codable {
    case paragraph
    case character
}

struct NamedStyleFormatting: Codable, Equatable {
    var fontFamily: String?
    var fontSize: Double?
    var bold: Bool?
    var italic: Bool?
    var underline: Bool?
    var foregroundColor: String?
    var alignment: String?
    var firstLineIndent: Double?
    var leftIndent: Double?
    var rightIndent: Double?
    var spaceBefore: Double?
    var spaceAfter: Double?
    var lineSpacing: Double?
    var keepWithNext: Bool?
    var keepLinesTogether: Bool?
    var pageBreakBefore: Bool?
    var widowControl: Bool?

    func inheriting(_ parent: NamedStyleFormatting?) -> NamedStyleFormatting {
        guard let parent else { return self }
        var result = parent
        if let fontFamily { result.fontFamily = fontFamily }
        if let fontSize { result.fontSize = fontSize }
        if let bold { result.bold = bold }
        if let italic { result.italic = italic }
        if let underline { result.underline = underline }
        if let foregroundColor { result.foregroundColor = foregroundColor }
        if let alignment { result.alignment = alignment }
        if let firstLineIndent { result.firstLineIndent = firstLineIndent }
        if let leftIndent { result.leftIndent = leftIndent }
        if let rightIndent { result.rightIndent = rightIndent }
        if let spaceBefore { result.spaceBefore = spaceBefore }
        if let spaceAfter { result.spaceAfter = spaceAfter }
        if let lineSpacing { result.lineSpacing = lineSpacing }
        if let keepWithNext { result.keepWithNext = keepWithNext }
        if let keepLinesTogether { result.keepLinesTogether = keepLinesTogether }
        if let pageBreakBefore { result.pageBreakBefore = pageBreakBefore }
        if let widowControl { result.widowControl = widowControl }
        return result
    }
}

struct NamedStyleDefinition: Codable, Equatable, Identifiable {
    var id: String { styleID }
    var styleID: String
    var name: String
    var kind: NamedStyleKind = .paragraph
    var basedOn: String?
    var nextStyleID: String?
    var linkedStyleID: String?
    var isBuiltIn = false
    var isDefault = false
    var isQuickStyle = false
    var formatting = NamedStyleFormatting()

    static let builtIns: [NamedStyleDefinition] = [
        .init(styleID: "Normal", name: "Normal", isBuiltIn: true, isDefault: true,
              formatting: .init(fontFamily: "Helvetica", fontSize: 15, spaceAfter: 7, lineSpacing: 2)),
        .init(styleID: "NoSpacing", name: "No Spacing", basedOn: "Normal", isBuiltIn: true,
              formatting: .init(spaceBefore: 0, spaceAfter: 0, lineSpacing: 0)),
        .init(styleID: "Title", name: "Title", basedOn: "Normal", isBuiltIn: true, isQuickStyle: true,
              formatting: .init(fontSize: 30, bold: true, alignment: "center", spaceAfter: 12)),
        .init(styleID: "Subtitle", name: "Subtitle", basedOn: "Normal", isBuiltIn: true, isQuickStyle: true,
              formatting: .init(fontSize: 18, alignment: "center", spaceAfter: 10)),
        .init(styleID: "Heading1", name: "Heading 1", basedOn: "Normal", nextStyleID: "Normal", isBuiltIn: true, isQuickStyle: true,
              formatting: .init(fontSize: 24, bold: true, spaceBefore: 12, spaceAfter: 10, keepWithNext: true)),
        .init(styleID: "Heading2", name: "Heading 2", basedOn: "Normal", nextStyleID: "Normal", isBuiltIn: true, isQuickStyle: true,
              formatting: .init(fontSize: 20, bold: true, spaceBefore: 10, spaceAfter: 8, keepWithNext: true)),
        .init(styleID: "Heading3", name: "Heading 3", basedOn: "Normal", nextStyleID: "Normal", isBuiltIn: true, isQuickStyle: true,
              formatting: .init(fontSize: 17, bold: true, spaceBefore: 8, spaceAfter: 6, keepWithNext: true)),
        .init(styleID: "Heading4", name: "Heading 4", basedOn: "Normal", nextStyleID: "Normal", isBuiltIn: true, isQuickStyle: true,
              formatting: .init(fontSize: 15, bold: true, spaceBefore: 7, spaceAfter: 5, keepWithNext: true)),
        .init(styleID: "Heading5", name: "Heading 5", basedOn: "Normal", nextStyleID: "Normal", isBuiltIn: true, isQuickStyle: true,
              formatting: .init(fontSize: 14, bold: true, italic: true, spaceBefore: 6, spaceAfter: 4, keepWithNext: true)),
        .init(styleID: "Heading6", name: "Heading 6", basedOn: "Normal", nextStyleID: "Normal", isBuiltIn: true, isQuickStyle: true,
              formatting: .init(fontSize: 13, bold: true, spaceBefore: 5, spaceAfter: 3, keepWithNext: true)),
        .init(styleID: "Quote", name: "Quote", basedOn: "Normal", isBuiltIn: true, isQuickStyle: true,
              formatting: .init(italic: true, leftIndent: 24, rightIndent: 24, spaceBefore: 6, spaceAfter: 6)),
        .init(styleID: "IntenseQuote", name: "Intense Quote", basedOn: "Quote", isBuiltIn: true, isQuickStyle: true,
              formatting: .init(bold: true, italic: true, foregroundColor: "404040", leftIndent: 36, rightIndent: 36, spaceBefore: 8, spaceAfter: 8)),
        .init(styleID: "Caption", name: "Caption", basedOn: "Normal", isBuiltIn: true,
              formatting: .init(fontSize: 12, spaceBefore: 4, spaceAfter: 4))
    ]
}

struct NamedStyleRun: Codable, Equatable {
    var styleID: String
    var kind: NamedStyleKind
    var location: Int
    var length: Int
}

enum NamedStyles {
    static func create(name: String, kind: NamedStyleKind, basedOn: String? = nil,
                       formatting: NamedStyleFormatting = NamedStyleFormatting(),
                       in existing: [NamedStyleDefinition]) throws -> NamedStyleDefinition {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw WriterError.message("A style name is required.") }
        let id = stableID(for: trimmed)
        let candidate = NamedStyleDefinition(styleID: id, name: trimmed, kind: kind, basedOn: basedOn, formatting: formatting)
        try validate(existing + [candidate])
        return candidate
    }

    static func stableID(for name: String) -> String {
        let pieces = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        let base = pieces.map(String.init).joined()
        return base.isEmpty ? "CustomStyle" : base
    }

    static func mergedWithBuiltIns(_ styles: [NamedStyleDefinition]) -> [NamedStyleDefinition] {
        var byID = Dictionary(NamedStyleDefinition.builtIns.map { ($0.styleID, $0) }, uniquingKeysWith: { first, _ in first })
        for style in styles { byID[style.styleID] = style }
        return byID.values.sorted { $0.styleID < $1.styleID }
    }

    static func decodeDefinitions(_ styles: [NamedStyleDefinition]?) throws -> [NamedStyleDefinition] {
        guard let styles else { return mergedWithBuiltIns([]) }
        try validate(styles)
        return mergedWithBuiltIns(styles)
    }

    static func validateRuns(_ runs: [NamedStyleRun], styles: [NamedStyleDefinition], textLength: Int) throws {
        let definitions = Dictionary(styles.map { ($0.styleID, $0) }, uniquingKeysWith: { first, _ in first })
        for run in runs {
            guard run.location >= 0, run.length > 0, run.location <= textLength,
                  run.length <= textLength - run.location,
                  definitions[run.styleID]?.kind == run.kind else {
                throw WriterError.message("The document contains malformed named style runs.")
            }
        }
    }

    static func validate(_ styles: [NamedStyleDefinition]) throws {
        var ids = Set<String>(), names = Set<String>()
        let map = Dictionary(styles.map { ($0.styleID, $0) }, uniquingKeysWith: { first, _ in first })
        guard map.count == styles.count else { throw WriterError.message("The document contains duplicate named style IDs.") }
        for style in styles {
            let name = style.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !style.styleID.isEmpty, !name.isEmpty,
                  ids.insert(style.styleID).inserted,
                  names.insert("\(style.kind.rawValue):\(name.lowercased())").inserted,
                  finite(style.formatting),
                  style.basedOn.map({ map[$0].map { $0.kind == style.kind } ?? true }) ?? true else {
                throw WriterError.message("The document contains invalid or duplicate named styles.")
            }
        }
        var visiting = Set<String>(), visited = Set<String>()
        func visit(_ id: String) throws {
            if visited.contains(id) { return }
            guard visiting.insert(id).inserted else { throw WriterError.message("The document contains a cycle in named style inheritance.") }
            if let parent = map[id]?.basedOn, map[parent] != nil { try visit(parent) }
            visiting.remove(id)
            visited.insert(id)
        }
        for id in map.keys { try visit(id) }
    }

    static func resolve(_ id: String, in styles: [NamedStyleDefinition]) -> NamedStyleFormatting? {
        let map = Dictionary(styles.map { ($0.styleID, $0) }, uniquingKeysWith: { first, _ in first })
        var visited = Set<String>()
        func walk(_ styleID: String) -> NamedStyleFormatting? {
            guard visited.insert(styleID).inserted, let style = map[styleID] else { return nil }
            let inherited = style.basedOn.flatMap { walk($0) }
            return style.formatting.inheriting(inherited)
        }
        return walk(id)
    }

    private static func finite(_ f: NamedStyleFormatting) -> Bool {
        [f.fontSize, f.firstLineIndent, f.leftIndent, f.rightIndent, f.spaceBefore, f.spaceAfter, f.lineSpacing]
            .compactMap { $0 }.allSatisfy { $0.isFinite && abs($0) <= 100_000 }
    }
}
