import AppKit

enum DOCXStyleCatalog {
    static func read(from data: Data) throws -> [NamedStyleDefinition] {
        let entries = try DOCXPackage.entries(in: data)
        let parts = Dictionary(uniqueKeysWithValues: entries.map { ($0.path, $0.data) })
        var mainPart = "word/document.xml"
        if let rootData = parts["_rels/.rels"] {
            let root = try DOCXPackage.xml(rootData)
            if let relationship = try root.nodes(forXPath: "//*[local-name()='Relationship']").compactMap({ $0 as? XMLElement }).first(where: { $0.attribute(forName: "Type")?.stringValue?.hasSuffix("/officeDocument") == true }),
               relationship.attribute(forName: "TargetMode")?.stringValue != "External",
               let target = relationship.attribute(forName: "Target")?.stringValue,
               let resolved = DOCXPackage.target(target, relativeTo: "") { mainPart = resolved }
        }
        let directory = (mainPart as NSString).deletingLastPathComponent
        let relationshipsPath = (directory.isEmpty ? "" : directory + "/") + "_rels/" + (mainPart as NSString).lastPathComponent + ".rels"
        let relationshipsData: Data
        if let found = parts[relationshipsPath] { relationshipsData = found }
        else if mainPart == "word/document.xml" { return NamedStyleDefinition.builtIns }
        else { throw WriterError.message("The DOCX document relationships are missing.") }
        let relationships = try DOCXPackage.xml(relationshipsData)
        let matches = try relationships.nodes(forXPath: "//*[local-name()='Relationship']").compactMap { $0 as? XMLElement }.filter {
            $0.attribute(forName: "Type")?.stringValue?.hasSuffix("/styles") == true && $0.attribute(forName: "TargetMode")?.stringValue != "External"
        }
        guard matches.count <= 1 else { throw WriterError.message("The DOCX has ambiguous style relationships.") }
        guard let relationship = matches.first else {
            if mainPart == "word/document.xml" { return NamedStyleDefinition.builtIns }
            throw WriterError.message("The DOCX styles relationship is missing.")
        }
        guard let target = relationship.attribute(forName: "Target")?.stringValue,
              let path = DOCXPackage.target(target, relativeTo: mainPart),
              let stylesData = parts[path] else { throw WriterError.message("The DOCX styles part is missing.") }

        let document = try DOCXPackage.xml(stylesData)
        guard document.rootElement()?.localName == "styles" else { throw WriterError.message("The DOCX styles part is malformed.") }
        let nodes = try document.nodes(forXPath: "/*[local-name()='styles']/*[local-name()='style']").compactMap { $0 as? XMLElement }
        var definitions: [NamedStyleDefinition] = []
        var styleNames = Set<String>()
        var styleIDs = Set<String>()
        for node in nodes {
            guard let id = attr(node, "styleId"), !id.isEmpty else {
                throw WriterError.message("The DOCX contains a style without an identifier.")
            }
            guard styleIDs.insert(id).inserted else { throw WriterError.message("The DOCX contains duplicate style identifiers.") }
            let rawKind = attr(node, "type")?.lowercased() ?? "paragraph"
            guard rawKind == "paragraph" || rawKind == "character" else { continue }
            let kind: NamedStyleKind = rawKind == "character" ? .character : .paragraph
            let formatting = try parseFormatting(node, kind: kind)
            let name = childValue(node, "name") ?? id
            guard styleNames.insert("\(kind.rawValue):\(name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())").inserted else {
                throw WriterError.message("The DOCX contains duplicate style names.")
            }
            definitions.append(NamedStyleDefinition(
                styleID: id,
                name: name,
                kind: kind,
                basedOn: childValue(node, "basedOn"),
                nextStyleID: childValue(node, "next"),
                linkedStyleID: childValue(node, "link"),
                isBuiltIn: NamedStyleDefinition.builtIns.contains { $0.styleID == id },
                isDefault: attr(node, "default") == "1",
                isQuickStyle: node.children?.contains(where: { $0.localName == "qFormat" }) ?? false,
                formatting: formatting
            ))
        }
        try NamedStyles.validate(definitions)
        return NamedStyles.mergedWithBuiltIns(definitions)
    }

    private static func parseFormatting(_ style: XMLElement, kind: NamedStyleKind) throws -> NamedStyleFormatting {
        let pPr = try style.nodes(forXPath: "./*[local-name()='pPr']").first as? XMLElement
        let rPr = try style.nodes(forXPath: "./*[local-name()='rPr']").first as? XMLElement
        let fonts = try rPr?.nodes(forXPath: "./*[local-name()='rFonts']").first as? XMLElement
        let sizes = try rPr?.nodes(forXPath: "./*[local-name()='sz']").first as? XMLElement
        let colors = try rPr?.nodes(forXPath: "./*[local-name()='color']").first as? XMLElement
        let underlineNode = try rPr?.nodes(forXPath: "./*[local-name()='u']").first as? XMLElement
        let ind = try pPr?.nodes(forXPath: "./*[local-name()='ind']").first as? XMLElement
        let spacing = try pPr?.nodes(forXPath: "./*[local-name()='spacing']").first as? XMLElement
        let alignNode = try pPr?.nodes(forXPath: "./*[local-name()='jc']").first as? XMLElement
        func number(_ element: XMLElement?, _ key: String, scale: Double = 1) throws -> Double? {
            guard let raw = attr(element, key) else { return nil }
            guard let value = Double(raw), value.isFinite, abs(value) <= 2_000_000 else {
                throw WriterError.message("The DOCX contains an invalid style measurement.")
            }
            return value * scale
        }
        let pointSize = try number(sizes, "val", scale: 0.5)
        guard pointSize == nil || (pointSize! >= 1 && pointSize! <= 1000) else {
            throw WriterError.message("The DOCX contains an invalid style font size.")
        }
        let align: String?
        switch attr(alignNode, "val")?.lowercased() {
        case "left": align = "left"
        case "center": align = "center"
        case "right": align = "right"
        case "both", "distribute": align = "justified"
        case .some: align = nil
        case .none: align = nil
        }
        let color = attr(colors, "val").flatMap { $0.count == 6 && UInt32($0, radix: 16) != nil ? $0.uppercased() : nil }
        return NamedStyleFormatting(
            fontFamily: attr(fonts, "ascii") ?? attr(fonts, "hAnsi"),
            fontSize: pointSize,
            bold: try toggle(rPr, "b"),
            italic: try toggle(rPr, "i"),
            underline: attr(underlineNode, "val") == "none" ? false : (underlineNode == nil ? nil : true),
            foregroundColor: color,
            alignment: kind == .paragraph ? align : nil,
            firstLineIndent: kind == .paragraph ? try number(ind, "firstLine", scale: 1 / 20) : nil,
            leftIndent: kind == .paragraph ? try number(ind, "left", scale: 1 / 20) : nil,
            rightIndent: kind == .paragraph ? try number(ind, "right", scale: 1 / 20) : nil,
            spaceBefore: kind == .paragraph ? try number(spacing, "before", scale: 1 / 20) : nil,
            spaceAfter: kind == .paragraph ? try number(spacing, "after", scale: 1 / 20) : nil,
            lineSpacing: kind == .paragraph ? try number(spacing, "line", scale: 1 / 240) : nil,
            keepWithNext: kind == .paragraph ? try presence(pPr, "keepNext") : nil,
            keepLinesTogether: kind == .paragraph ? try presence(pPr, "keepLines") : nil,
            pageBreakBefore: kind == .paragraph ? try presence(pPr, "pageBreakBefore") : nil,
            widowControl: kind == .paragraph ? try presence(pPr, "widowControl") : nil
        )
    }

    private static func toggle(_ parent: XMLElement?, _ name: String) throws -> Bool? {
        guard let node = try parent?.nodes(forXPath: "./*[local-name()='\(name)']").first as? XMLElement else { return nil }
        switch attr(node, "val")?.lowercased() {
        case nil, "1", "true", "on": return true
        case "0", "false", "off": return false
        default: throw WriterError.message("The DOCX contains an invalid style toggle.")
        }
    }

    private static func presence(_ parent: XMLElement?, _ name: String) throws -> Bool? {
        guard let node = try parent?.nodes(forXPath: "./*[local-name()='\(name)']").first as? XMLElement else { return nil }
        switch attr(node, "val")?.lowercased() {
        case nil, "1", "true", "on": return true
        case "0", "false", "off": return false
        default: throw WriterError.message("The DOCX contains an invalid paragraph style property.")
        }
    }

    private static func attr(_ element: XMLElement?, _ name: String) -> String? {
        element?.attributes?.first { $0.localName == name || $0.name == name || $0.name == "w:" + name }?.stringValue
    }

    private static func childValue(_ element: XMLElement, _ name: String) -> String? {
        (try? element.nodes(forXPath: "./*[local-name()='\(name)']").first as? XMLElement).flatMap { attr($0, "val") }
    }
}
