import AppKit

/// Keeps unsupported DrawingML together with the package parts it needs. The
/// closure is deliberately small and never follows external relationships.
enum DOCXOpaqueDrawingPackage {
    private static let relationshipNamespace = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    private static let packageRelationshipNamespace = "http://schemas.openxmlformats.org/package/2006/relationships"
    private static let contentTypeNamespace = "http://schemas.openxmlformats.org/package/2006/content-types"

    static func capture(root: XMLElement, isRunChild: Bool, mainPart: String,
                        packageParts: [String: Data]) throws -> WordOpaqueDrawing {
        let drawingID = UUID()
        let copy = root.copy() as! XMLElement
        let mainRelationships = try relationships(for: mainPart, in: packageParts)
        var byID: [String: WordOpaqueRelationship] = [:]
        for relationship in mainRelationships {
            guard byID.updateValue(relationship, forKey: relationship.id) == nil else { throw invalid() }
        }
        var selected: [WordOpaqueRelationship] = []
        var references: [XMLNode] = []
        // Relationship attributes may appear on extension elements of any name.
        var stack: [XMLNode] = [copy]
        while let node = stack.popLast() {
            if let element = node as? XMLElement {
                references.append(contentsOf: (element.attributes ?? []).filter(isRelationshipReference))
            }
            stack.append(contentsOf: node.children ?? [])
        }
        let token = drawingID.uuidString.replacingOccurrences(of: "-", with: "")
        var renamed: [String: String] = [:]
        for attribute in references {
            guard let oldID = attribute.stringValue, let relation = byID[oldID] else { throw invalid() }
            let newID: String
            if let existing = renamed[oldID] { newID = existing }
            else {
                newID = "rBoldOpaque\(token)_\(renamed.count + 1)"
                renamed[oldID] = newID
                selected.append(WordOpaqueRelationship(id: newID, type: relation.type, targetPath: relation.targetPath))
            }
            attribute.stringValue = newID
        }

        let types = try contentTypes(in: packageParts)
        var queue = selected.map(\.targetPath)
        var seen = Set<String>()
        var captured: [WordOpaquePart] = []
        var totalBytes = 0
        var relationCount = selected.count
        while !queue.isEmpty {
            let path = queue.removeFirst()
            guard seen.insert(path).inserted else { continue }
            guard seen.count <= 64, let bytes = packageParts[path],
                  bytes.count <= 8 * 1024 * 1024 - totalBytes,
                  let type = types[path] ?? types[(path as NSString).pathExtension.lowercased()] else {
                throw WriterError.message("An unsupported Word drawing dependency is missing, unsafe, or oversized: \(path).")
            }
            totalBytes += bytes.count
            let nested = try relationships(for: path, in: packageParts, rejectExternal: true)
            relationCount += nested.count
            guard relationCount <= 128 else { throw invalid() }
            queue.append(contentsOf: nested.map(\.targetPath))
            captured.append(WordOpaquePart(path: path, contentType: type, data: bytes, relationships: nested))
        }
        return try WordOpaqueDrawing.validated(id: drawingID, xml: copy.xmlString,
                                               isRunChild: isRunChild, relationships: selected,
                                               parts: captured)
    }

    static func append(drawings: [WordOpaqueDrawing],
                       to parts: inout [(String, String)], media: inout [ZipEntry]) throws {
        var existingPaths = Set(parts.map(\.0)).union(media.map(\.path))
        guard drawings.isEmpty || parts.contains(where: { $0.0 == "word/_rels/document.xml.rels" }) else { throw invalid() }
        let relationshipText = parts.first(where: { $0.0 == "word/_rels/document.xml.rels" })?.1 ?? ""
        let relationshipDocument = try XMLDocument(xmlString: relationshipText.isEmpty
            ? "<Relationships/>" : relationshipText, options: [.nodeLoadExternalEntitiesNever])
        var rootIDs = Set(DOCXPackage.descendants(in: relationshipDocument, named: "Relationship")
            .compactMap { ($0 as? XMLElement)?.attribute(forName: "Id")?.stringValue })
        var additionalRoot: [String] = []
        var additionalTypes: [String] = []
        var seenDrawings = Set<UUID>()
        for drawing in drawings {
            let drawing = try WordOpaqueDrawing.validated(id: drawing.id, xml: drawing.xml,
                isRunChild: drawing.isRunChild, relationships: drawing.relationships, parts: drawing.parts)
            guard seenDrawings.insert(drawing.id).inserted else { continue }
            let prefix = "word/boldwriter-opaque/" + drawing.id.uuidString.replacingOccurrences(of: "-", with: "") + "/"
            let mapped: (String) -> String = { prefix + $0 }
            for relation in drawing.relationships {
                guard rootIDs.insert(relation.id).inserted else { throw invalid() }
                additionalRoot.append(relationshipXML(relation, target: "/" + mapped(relation.targetPath)))
            }
            for part in drawing.parts {
                let newPath = mapped(part.path)
                guard existingPaths.insert(newPath).inserted else { throw invalid() }
                media.append(ZipEntry(path: newPath, data: part.data))
                additionalTypes.append("<Override PartName=\"/\(escape(newPath))\" ContentType=\"\(escape(part.contentType))\"/>")
                if !part.relationships.isEmpty {
                    let relPath = relationshipPath(for: newPath)
                    guard existingPaths.insert(relPath).inserted else { throw invalid() }
                    let body = part.relationships.map { relationshipXML($0, target: "/" + mapped($0.targetPath)) }.joined()
                    let xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Relationships xmlns=\"\(packageRelationshipNamespace)\">\(body)</Relationships>"
                    media.append(ZipEntry(path: relPath, data: Data(xml.utf8)))
                }
            }
        }
        if !additionalRoot.isEmpty {
            guard let index = parts.firstIndex(where: { $0.0 == "word/_rels/document.xml.rels" }),
                  parts[index].1.contains("</Relationships>") else { throw invalid() }
            parts[index].1 = parts[index].1.replacingOccurrences(of: "</Relationships>",
                                        with: additionalRoot.joined() + "</Relationships>")
        }
        if !additionalTypes.isEmpty {
            guard let index = parts.firstIndex(where: { $0.0 == "[Content_Types].xml" }),
                  parts[index].1.contains("</Types>") else { throw invalid() }
            parts[index].1 = parts[index].1.replacingOccurrences(of: "</Types>", with: additionalTypes.joined() + "</Types>")
        }
    }

    private static func isRelationshipReference(_ attribute: XMLNode) -> Bool {
        attribute.uri == relationshipNamespace || (attribute.name ?? "").hasPrefix("r:")
            || attribute.localName == "relid" && attribute.uri == "urn:schemas-microsoft-com:office:office"
    }

    private static func relationships(for part: String, in parts: [String: Data],
                                      rejectExternal: Bool = false) throws -> [WordOpaqueRelationship] {
        guard let bytes = parts[relationshipPath(for: part)] else { return [] }
        let document = try DOCXPackage.xml(bytes)
        var result: [WordOpaqueRelationship] = []
        for node in DOCXPackage.descendants(in: document, named: "Relationship") {
            guard let element = node as? XMLElement else { throw invalid() }
            if element.attribute(forName: "TargetMode")?.stringValue == "External" {
                if rejectExternal { throw invalid() }
                continue
            }
            guard
                  let id = element.attribute(forName: "Id")?.stringValue,
                  let type = element.attribute(forName: "Type")?.stringValue,
                  let target = element.attribute(forName: "Target")?.stringValue,
                  let path = DOCXPackage.target(target, relativeTo: part),
                  safePath(path) else { throw invalid() }
            result.append(WordOpaqueRelationship(id: id, type: type, targetPath: path))
        }
        return result
    }

    private static func contentTypes(in parts: [String: Data]) throws -> [String: String] {
        guard let bytes = parts["[Content_Types].xml"] else { throw invalid() }
        let document = try DOCXPackage.xml(bytes)
        var result: [String: String] = [:]
        for node in DOCXPackage.descendants(in: document, names: ["Default", "Override"]) {
            guard let element = node as? XMLElement,
                  let type = element.attribute(forName: "ContentType")?.stringValue else { throw invalid() }
            if element.localName == "Override", let name = element.attribute(forName: "PartName")?.stringValue {
                let path = String(name.drop(while: { $0 == "/" }))
                guard safePath(path) else { throw invalid() }
                result[path] = type
            } else if let ext = element.attribute(forName: "Extension")?.stringValue {
                result[ext.lowercased()] = type
            }
        }
        return result
    }

    private static func relationshipPath(for part: String) -> String {
        let directory = (part as NSString).deletingLastPathComponent
        return (directory.isEmpty ? "" : directory + "/") + "_rels/" + (part as NSString).lastPathComponent + ".rels"
    }

    private static func relationshipXML(_ relationship: WordOpaqueRelationship, target: String) -> String {
        let encoded = target.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "/-._~abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")) ?? target
        return "<Relationship Id=\"\(escape(relationship.id))\" Type=\"\(escape(relationship.type))\" Target=\"\(escape(encoded))\"/>"
    }

    private static func safePath(_ path: String) -> Bool {
        !path.isEmpty && path.utf8.count <= 512 && DOCXPackage.target(path, relativeTo: "") == path
            && path != "[Content_Types].xml" && !path.hasSuffix(".rels")
    }

    private static func escape(_ string: String) -> String {
        string.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func invalid() -> Error {
        WriterError.message("An unsupported Word drawing has missing, unsafe, or oversized package dependencies. Import or export stopped rather than losing artwork.")
    }
}
