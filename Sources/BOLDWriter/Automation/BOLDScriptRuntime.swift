import AppKit
import Foundation

/// BOLD Script v1 is data, never executable source. Unknown keys and operations
/// are rejected before a plan can reach the document editor.
struct BOLDScript: Equatable {
    enum FloatingImageAlignment: String { case left, center, right, top, middle, bottom }
    enum Operation: Equatable {
        case replaceText(find: String, with: String)
        case formatText(find: String, fontFamily: String?, fontSize: Double?, bold: Bool?, italic: Bool?)
        case setParagraphStyle(prefix: String, style: WriterStyle)
        case normalizeHeadings(rules: [(prefix: String, style: WriterStyle)])
        case insertFloatingImage(FloatingImage)
        case updateFloatingImage(id: UUID, page: Int?, x: Double?, y: Double?, width: Double?, height: Double?, rotation: Double?, wrapping: FloatingImage.Wrapping?, wrapDistance: Double?, wrapDistances: FloatingImage.WrapDistances?, wrapSide: FloatingImage.WrapSide?, layer: FloatingImage.Layer?, anchor: FloatingImage.Anchor?, anchorLocation: Int?, anchorOffsetX: Double?, anchorOffsetY: Double?, preservesAspect: Bool?, zOrder: Int?, locked: Bool?)
        case duplicateFloatingImage(id: UUID, x: Double?, y: Double?)
        case alignFloatingImages(ids: [UUID], alignment: FloatingImageAlignment)
        case inspectFloatingImages(ids: [UUID]?)

        static func == (lhs: Operation, rhs: Operation) -> Bool {
            switch (lhs, rhs) {
            case let (.replaceText(af, aw), .replaceText(bf, bw)): af == bf && aw == bw
            case let (.formatText(af, aff, afs, ab, ai), .formatText(bf, bff, bfs, bb, bi)):
                af == bf && aff == bff && afs == bfs && ab == bb && ai == bi
            case let (.setParagraphStyle(ap, as_), .setParagraphStyle(bp, bs)): ap == bp && as_ == bs
            case let (.normalizeHeadings(a), .normalizeHeadings(b)):
                a.map { $0.prefix + "\u{0}" + $0.style.rawValue } == b.map { $0.prefix + "\u{0}" + $0.style.rawValue }
            case let (.insertFloatingImage(a), .insertFloatingImage(b)): a == b
            case let (.updateFloatingImage(ai, ap, ax, ay, aw, ah, ar, awr, awd, awds, aws, al, aa, aal, aox, aoy, apa, azo, ak), .updateFloatingImage(bi, bp, bx, by, bw, bh, br, bwr, bwd, bwds, bws, bl, ba, bal, box, boy, bpa, bzo, bk)):
                ai == bi && ap == bp && ax == bx && ay == by && aw == bw && ah == bh && ar == br && awr == bwr && awd == bwd && awds == bwds && aws == bws && al == bl && aa == ba && aal == bal && aox == box && aoy == boy && apa == bpa && azo == bzo && ak == bk
            case let (.duplicateFloatingImage(ai, ax, ay), .duplicateFloatingImage(bi, bx, by)): ai == bi && ax == bx && ay == by
            case let (.alignFloatingImages(ai, aa), .alignFloatingImages(bi, ba)): ai == bi && aa == ba
            case let (.inspectFloatingImages(ai), .inspectFloatingImages(bi)): ai == bi
            default: false
            }
        }
    }

    let title: String
    let target: String
    let documentRevision: UUID?
    let operations: [Operation]

    static func parse(_ source: String) throws -> BOLDScript {
        let cleaned = extractJSON(source)
        guard let data = cleaned.data(using: .utf8),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BOLDScriptError("Script must contain one BOLD Script JSON object.")
        }
        try keys(root, allowed: ["format", "version", "title", "target", "preconditions", "operations"], where: "script")
        guard root["format"] as? String == "bold-script" else { throw BOLDScriptError("format must be \"bold-script\".") }
        guard let version = root["version"] as? Int, version == 1 else { throw BOLDScriptError("Only BOLD Script version 1 is supported.") }
        guard let targetObject = root["target"] as? [String: Any] else { throw BOLDScriptError("target must be an object.") }
        try keys(targetObject, allowed: ["scope"], where: "target")
        guard let target = targetObject["scope"] as? String, target == "document" else {
            throw BOLDScriptError("Version 1 currently supports target.scope = \"document\" only.")
        }
        var revision: UUID?
        if let preconditions = root["preconditions"] {
            guard let object = preconditions as? [String: Any] else { throw BOLDScriptError("preconditions must be an object.") }
            try keys(object, allowed: ["documentRevision"], where: "preconditions")
            if let value = object["documentRevision"] {
                guard let string = value as? String, let uuid = UUID(uuidString: string) else { throw BOLDScriptError("preconditions.documentRevision must be a UUID string.") }
                revision = uuid
            }
        }
        guard let values = root["operations"] as? [[String: Any]], !values.isEmpty else {
            throw BOLDScriptError("operations must contain at least one supported operation.")
        }
        guard values.count <= 100 else { throw BOLDScriptError("A script may contain at most 100 operations.") }
        let operations = try values.map(parseOperation)
        let title = (root["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return BOLDScript(title: (title?.isEmpty == false ? title! : "BOLD Script"), target: target, documentRevision: revision, operations: operations)
    }

    private static func parseOperation(_ value: [String: Any]) throws -> Operation {
        guard let type = value["type"] as? String else { throw BOLDScriptError("Every operation needs a string type.") }
        switch type {
        case "replaceText":
            try keys(value, allowed: ["type", "find", "replaceWith"], where: "replaceText")
            guard let find = value["find"] as? String, !find.isEmpty, let replacement = value["replaceWith"] as? String else {
                throw BOLDScriptError("replaceText needs a non-empty find and a string replaceWith.")
            }
            return .replaceText(find: find, with: replacement)
        case "formatText":
            try keys(value, allowed: ["type", "find", "fontFamily", "fontSize", "bold", "italic"], where: "formatText")
            guard let find = value["find"] as? String, !find.isEmpty else { throw BOLDScriptError("formatText needs a non-empty exact find string.") }
            let size = value["fontSize"] as? Double
            if value["fontSize"] != nil && (size == nil || !size!.isFinite || !(6...288).contains(size!)) { throw BOLDScriptError("fontSize must be between 6 and 288 points.") }
            let family = value["fontFamily"] as? String
            if value["fontFamily"] != nil && (family?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) { throw BOLDScriptError("fontFamily must be a non-empty string.") }
            guard value["bold"] == nil || value["bold"] is Bool,
                  value["italic"] == nil || value["italic"] is Bool,
                  family != nil || size != nil || value["bold"] != nil || value["italic"] != nil else {
                throw BOLDScriptError("formatText needs at least one supported formatting attribute.")
            }
            return .formatText(find: find, fontFamily: family, fontSize: size, bold: value["bold"] as? Bool, italic: value["italic"] as? Bool)
        case "setParagraphStyle":
            try keys(value, allowed: ["type", "paragraphPrefix", "style"], where: "setParagraphStyle")
            guard let prefix = value["paragraphPrefix"] as? String, !prefix.isEmpty,
                  let name = value["style"] as? String, let style = WriterStyle(rawValue: name) else {
                throw BOLDScriptError("setParagraphStyle needs a paragraphPrefix and a supported style name.")
            }
            return .setParagraphStyle(prefix: prefix, style: style)
        case "normalizeHeadings":
            try keys(value, allowed: ["type", "rules"], where: "normalizeHeadings")
            guard let rules = value["rules"] as? [[String: Any]], !rules.isEmpty, rules.count <= 20 else { throw BOLDScriptError("normalizeHeadings needs 1–20 rules.") }
            let parsed: [(prefix: String, style: WriterStyle)] = try rules.map { rule in
                try keys(rule, allowed: ["paragraphPrefix", "style"], where: "normalizeHeadings rule")
                guard let prefix = rule["paragraphPrefix"] as? String, !prefix.isEmpty,
                      let name = rule["style"] as? String, let style = WriterStyle(rawValue: name), style.headingLevel != nil else {
                    throw BOLDScriptError("Each heading rule needs a non-empty paragraphPrefix and Heading 1–6 style.")
                }
                return (prefix, style)
            }
            return .normalizeHeadings(rules: parsed)
        case "insertFloatingImage":
            try keys(value, allowed: ["type", "sourcePath", "page", "x", "y", "width", "height", "rotation", "wrapping", "wrapDistance", "wrapDistances", "wrapSide", "layer", "anchor", "anchorLocation", "anchorOffsetX", "anchorOffsetY", "preservesAspectRatio", "lockPosition"], where: "insertFloatingImage")
            guard let path = value["sourcePath"] as? String, path.hasPrefix("/"),
                  let page = value["page"] as? Int, page >= 1,
                  let x = value["x"] as? Double, let y = value["y"] as? Double,
                  let width = value["width"] as? Double, let height = value["height"] as? Double,
                  let bytes = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let image = NSImage(data: bytes), image.isValid else {
                throw BOLDScriptError("insertFloatingImage needs an absolute readable image sourcePath, 1-based page, and finite x, y, width, and height values.")
            }
            let wrapping = (value["wrapping"] as? String).flatMap(FloatingImage.Wrapping.init(rawValue:)) ?? .none
            let wrapSide = (value["wrapSide"] as? String).flatMap(FloatingImage.WrapSide.init(rawValue:)) ?? .both
            let layer = (value["layer"] as? String).flatMap(FloatingImage.Layer.init(rawValue:)) ?? .inFrontOfText
            let anchor = (value["anchor"] as? String).flatMap(FloatingImage.Anchor.init(rawValue:)) ?? .page
            let anchorLocation = value["anchorLocation"] as? Int ?? -1
            let wrapDistance = value["wrapDistance"] as? Double ?? 6
            let wrapDistances = try parseWrapDistances(value["wrapDistances"])
            let anchorOffsetX = value["anchorOffsetX"] as? Double
            let anchorOffsetY = value["anchorOffsetY"] as? Double
            guard value["wrapping"] == nil || (value["wrapping"] as? String).flatMap(FloatingImage.Wrapping.init(rawValue:)) != nil,
                  value["wrapSide"] == nil || (value["wrapSide"] as? String).flatMap(FloatingImage.WrapSide.init(rawValue:)) != nil,
                  value["layer"] == nil || (value["layer"] as? String).flatMap(FloatingImage.Layer.init(rawValue:)) != nil,
                  value["anchor"] == nil || (value["anchor"] as? String).flatMap(FloatingImage.Anchor.init(rawValue:)) != nil,
                  value["anchorLocation"] == nil || (value["anchorLocation"] as? Int).map({ $0 >= 0 }) == true,
                  value["wrapDistance"] == nil || (wrapDistance.isFinite && (0...288).contains(wrapDistance)),
                  !(value["wrapDistance"] != nil && wrapDistances != nil),
                  [anchorOffsetX, anchorOffsetY].compactMap({ $0 }).allSatisfy({ $0.isFinite && abs($0) <= 20_000 }),
                  (anchorOffsetX == nil) == (anchorOffsetY == nil),
                  value["preservesAspectRatio"] == nil || value["preservesAspectRatio"] is Bool,
                  value["rotation"] == nil || (value["rotation"] as? Double)?.isFinite == true,
                  value["lockPosition"] == nil || value["lockPosition"] is Bool else {
                throw BOLDScriptError("insertFloatingImage contains an unsupported or invalid property.")
            }
            let rotation = value["rotation"] as? Double ?? 0
            let locked = value["lockPosition"] as? Bool ?? false
            guard (anchor == .paragraph || anchor == .character) ? anchorLocation >= 0 : true else {
                throw BOLDScriptError("Paragraph and character anchors require anchorLocation.")
            }
            let item = FloatingImage(assetName: URL(fileURLWithPath: path).lastPathComponent, imageData: bytes,
                                     pageIndex: page - 1, anchor: anchor, anchorLocation: anchorLocation, x: x, y: y,
                                     anchorOffsetX: anchorOffsetX, anchorOffsetY: anchorOffsetY, width: width, height: height,
                                     rotationDegrees: rotation, preservesAspectRatio: value["preservesAspectRatio"] as? Bool ?? true,
                                     wrapping: wrapping, wrapDistance: wrapDistances?.top ?? wrapDistance, wrapSide: wrapSide, layer: layer,
                                     positionLocked: locked, wrapDistances: wrapDistances)
            return .insertFloatingImage(item)
        case "updateFloatingImage":
            try keys(value, allowed: ["type", "imageID", "page", "x", "y", "width", "height", "rotation", "wrapping", "wrapDistance", "wrapDistances", "wrapSide", "layer", "anchor", "anchorLocation", "anchorOffsetX", "anchorOffsetY", "preservesAspectRatio", "zOrder", "lockPosition"], where: "updateFloatingImage")
            guard let rawID = value["imageID"] as? String, let id = UUID(uuidString: rawID) else { throw BOLDScriptError("updateFloatingImage needs a valid imageID.") }
            func number(_ key: String) -> Double? { value[key] as? Double }
            let wrapping = (value["wrapping"] as? String).flatMap(FloatingImage.Wrapping.init(rawValue:))
            let layer = (value["layer"] as? String).flatMap(FloatingImage.Layer.init(rawValue:))
            let anchor = (value["anchor"] as? String).flatMap(FloatingImage.Anchor.init(rawValue:))
            let page = value["page"] as? Int
            let anchorLocation = value["anchorLocation"] as? Int
            let anchorOffsetX = number("anchorOffsetX")
            let anchorOffsetY = number("anchorOffsetY")
            let wrapDistance = number("wrapDistance")
            let wrapDistances = try parseWrapDistances(value["wrapDistances"])
            let wrapSide = (value["wrapSide"] as? String).flatMap(FloatingImage.WrapSide.init(rawValue:))
            let preservesAspect = value["preservesAspectRatio"] as? Bool
            let zOrder = value["zOrder"] as? Int
            guard value["wrapping"] == nil || wrapping != nil, value["layer"] == nil || layer != nil,
                  value["wrapSide"] == nil || wrapSide != nil,
                  value["anchor"] == nil || anchor != nil,
                  page == nil || page! >= 1,
                  anchorLocation == nil || anchorLocation! >= 0,
                  [anchorOffsetX, anchorOffsetY].compactMap({ $0 }).allSatisfy({ $0.isFinite && abs($0) <= 20_000 }),
                  (anchorOffsetX == nil) == (anchorOffsetY == nil),
                  value["wrapDistance"] == nil || wrapDistance.map({ $0.isFinite && (0...288).contains($0) }) == true,
                  !(wrapDistance != nil && wrapDistances != nil),
                  value["preservesAspectRatio"] == nil || preservesAspect != nil,
                  value["zOrder"] == nil || zOrder != nil,
                  ["x", "y", "width", "height", "rotation"].allSatisfy({ value[$0] == nil || number($0)?.isFinite == true }),
                  ["page", "x", "y", "width", "height", "rotation", "wrapping", "wrapDistance", "wrapDistances", "wrapSide", "layer", "anchor", "anchorLocation", "anchorOffsetX", "anchorOffsetY", "preservesAspectRatio", "zOrder", "lockPosition"].contains(where: { value[$0] != nil }),
                  value["lockPosition"] == nil || value["lockPosition"] is Bool else { throw BOLDScriptError("updateFloatingImage contains an unsupported or invalid property.") }
            return .updateFloatingImage(id: id, page: page, x: number("x"), y: number("y"), width: number("width"), height: number("height"), rotation: number("rotation"), wrapping: wrapping, wrapDistance: wrapDistance, wrapDistances: wrapDistances, wrapSide: wrapSide, layer: layer, anchor: anchor, anchorLocation: anchorLocation, anchorOffsetX: anchorOffsetX, anchorOffsetY: anchorOffsetY, preservesAspect: preservesAspect, zOrder: zOrder, locked: value["lockPosition"] as? Bool)
        case "duplicateFloatingImage":
            try keys(value, allowed: ["type", "imageID", "x", "y"], where: "duplicateFloatingImage")
            guard let rawID = value["imageID"] as? String, let id = UUID(uuidString: rawID),
                  ["x", "y"].allSatisfy({ value[$0] == nil || (value[$0] as? Double)?.isFinite == true }) else { throw BOLDScriptError("duplicateFloatingImage needs a valid imageID and finite optional position.") }
            return .duplicateFloatingImage(id: id, x: value["x"] as? Double, y: value["y"] as? Double)
        case "alignFloatingImages":
            try keys(value, allowed: ["type", "imageIDs", "alignment"], where: "alignFloatingImages")
            guard let rawIDs = value["imageIDs"] as? [String], rawIDs.count >= 2,
                  let ids = Optional(rawIDs.compactMap(UUID.init(uuidString:))), ids.count == rawIDs.count, Set(ids).count == ids.count,
                  let rawAlignment = value["alignment"] as? String, let alignment = FloatingImageAlignment(rawValue: rawAlignment) else { throw BOLDScriptError("alignFloatingImages requires at least two unique imageIDs and left, center, right, top, middle, or bottom alignment.") }
            return .alignFloatingImages(ids: ids, alignment: alignment)
        case "inspectFloatingImages":
            try keys(value, allowed: ["type", "imageIDs"], where: "inspectFloatingImages")
            guard value["imageIDs"] == nil || value["imageIDs"] is [String] else { throw BOLDScriptError("inspectFloatingImages imageIDs must be an array of UUID strings.") }
            let ids = (value["imageIDs"] as? [String])?.compactMap(UUID.init(uuidString:))
            guard ids == nil || ids!.count == (value["imageIDs"] as? [String])?.count else { throw BOLDScriptError("inspectFloatingImages contains an invalid UUID.") }
            return .inspectFloatingImages(ids: ids)
        default: throw BOLDScriptError("Unsupported operation type: \(type). No changes were made.")
        }
    }

    private static func keys(_ object: [String: Any], allowed: Set<String>, where context: String) throws {
        if let unknown = object.keys.first(where: { !allowed.contains($0) }) { throw BOLDScriptError("Unsupported key \"\(unknown)\" in \(context). No changes were made.") }
    }

    private static func parseWrapDistances(_ value: Any?) throws -> FloatingImage.WrapDistances? {
        guard let value else { return nil }
        guard let object = value as? [String: Any] else {
            throw BOLDScriptError("wrapDistances must be an object containing top, right, bottom, and left point values.")
        }
        try keys(object, allowed: ["top", "right", "bottom", "left"], where: "wrapDistances")
        guard let top = object["top"] as? Double,
              let right = object["right"] as? Double,
              let bottom = object["bottom"] as? Double,
              let left = object["left"] as? Double,
              [top, right, bottom, left].allSatisfy({ $0.isFinite && (0...288).contains($0) }) else {
            throw BOLDScriptError("wrapDistances requires finite top, right, bottom, and left values from 0 to 288 points.")
        }
        return FloatingImage.WrapDistances(top: top, right: right, bottom: bottom, left: left)
    }

    private static func extractJSON(_ source: String) -> String {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```"), let firstNewline = trimmed.firstIndex(of: "\n"), let closing = trimmed.range(of: "```", options: .backwards), closing.lowerBound > firstNewline else { return trimmed }
        return String(trimmed[trimmed.index(after: firstNewline)..<closing.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct BOLDScriptError: LocalizedError, Equatable {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct BOLDScriptChange: Equatable {
    let operation: String
    let affectedParagraphs: Int
    let affectedMatches: Int
}

struct BOLDScriptPlan {
    let output: NSAttributedString
    let floatingImages: [FloatingImage]
    let changes: [BOLDScriptChange]
    var imageInspection: [FloatingImage] = []
    var totalChanges: Int { changes.reduce(0) { $0 + $1.affectedMatches } }
}

enum BOLDScriptEngine {
    static func plan(_ script: BOLDScript, on source: NSAttributedString, floatingImages existingImages: [FloatingImage] = []) throws -> BOLDScriptPlan {
        let output = NSMutableAttributedString(attributedString: source)
        var floatingImages = existingImages
        var changes: [BOLDScriptChange] = []
        var imageInspection: [FloatingImage] = []
        for operation in script.operations {
            switch operation {
            case let .replaceText(find, replacement):
                let ns = output.string as NSString
                let ranges = exactMatches(find, in: output.string).filter { ns.substring(with: $0) != replacement }
                guard let safe = try? NoteReferences.editingRanges(ranges, in: output), safe == ranges else {
                    throw BOLDScriptError("A replacement intersects a protected note reference. No changes were made.")
                }
                for range in ranges.reversed() {
                    var attributes = range.location < output.length ? output.attributes(at: range.location, effectiveRange: nil) : [:]
                    attributes.removeValue(forKey: .attachment)
                    attributes.removeValue(forKey: .footnote)
                    attributes.removeValue(forKey: .endnote)
                    attributes.removeValue(forKey: .boldWriterWordPictureCrop)
                    output.replaceCharacters(in: range, with: NSAttributedString(string: replacement, attributes: attributes))
                }
                changes.append(BOLDScriptChange(operation: "Replace ‘\(find)’", affectedParagraphs: paragraphCount(ranges, in: source.string), affectedMatches: ranges.count))
            case let .formatText(find, family, size, bold, italic):
                let ranges = exactMatches(find, in: output.string)
                if let family, NSFont(name: family, size: size ?? NSFont.systemFontSize) == nil {
                    throw BOLDScriptError("Font family \"\(family)\" is not available on this Mac. No changes were made.")
                }
                var changedMatches = 0
                var changedRanges: [NSRange] = []
                for range in ranges {
                    var fonts: [(NSRange, NSFont)] = []
                    var changed = false
                    output.enumerateAttribute(.font, in: range) { value, subrange, _ in
                        let old = value as? NSFont ?? .systemFont(ofSize: NSFont.systemFontSize)
                        var font = family.flatMap { NSFont(name: $0, size: size ?? old.pointSize) } ?? old.withSize(size ?? old.pointSize)
                        if let bold {
                            font = bold
                                ? NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
                                : NSFontManager.shared.convert(font, toNotHaveTrait: .boldFontMask)
                        }
                        if let italic {
                            font = italic
                                ? NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
                                : NSFontManager.shared.convert(font, toNotHaveTrait: .italicFontMask)
                        }
                        if !font.isEqual(old) { changed = true; fonts.append((subrange, font)) }
                    }
                    for (subrange, font) in fonts { output.addAttribute(.font, value: font, range: subrange) }
                    if changed { changedMatches += 1; changedRanges.append(range) }
                }
                changes.append(BOLDScriptChange(operation: "Format ‘\(find)’", affectedParagraphs: paragraphCount(changedRanges, in: output.string), affectedMatches: changedMatches))
            case let .setParagraphStyle(prefix, style):
                let count = applyParagraphStyle(prefix: prefix, style: style, to: output)
                changes.append(BOLDScriptChange(operation: "Apply \(style.rawValue) to paragraphs starting ‘\(prefix)’", affectedParagraphs: count, affectedMatches: count))
            case let .normalizeHeadings(rules):
                var count = 0
                for rule in rules { count += applyParagraphStyle(prefix: rule.prefix, style: rule.style, to: output) }
                changes.append(BOLDScriptChange(operation: "Normalize chapter headings", affectedParagraphs: count, affectedMatches: count))
            case let .insertFloatingImage(image):
                guard !floatingImages.contains(where: { $0.id == image.id }) else { throw BOLDScriptError("Image ID already exists. No changes were made.") }
                var placed = image
                placed.zOrder = (floatingImages.map(\.zOrder).max() ?? -1) + 1
                floatingImages.append(placed)
                changes.append(BOLDScriptChange(operation: "Insert floating image ‘\(image.assetName)’ (ID \(image.id.uuidString))", affectedParagraphs: 0, affectedMatches: 1))
            case let .updateFloatingImage(id, page, x, y, width, height, rotation, wrapping, wrapDistance, wrapDistances, wrapSide, layer, anchor, anchorLocation, anchorOffsetX, anchorOffsetY, preservesAspect, zOrder, locked):
                guard let index = floatingImages.firstIndex(where: { $0.id == id }) else { throw BOLDScriptError("Image \(id) was not found. No changes were made.") }
                guard !floatingImages[index].positionLocked || (locked == false) else { throw BOLDScriptError("Image position is locked. Unlock it before changing its placement.") }
                if let page { floatingImages[index].pageIndex = page - 1 }
                if let x { floatingImages[index].x = x }; if let y { floatingImages[index].y = y }
                if let width { floatingImages[index].width = width }; if let height { floatingImages[index].height = height }
                if let rotation { floatingImages[index].rotationDegrees = rotation }
                if let wrapDistance {
                    floatingImages[index].wrapDistance = wrapDistance
                    floatingImages[index].wrapDistances = .uniform(wrapDistance)
                }
                if let wrapDistances {
                    floatingImages[index].wrapDistances = wrapDistances
                    floatingImages[index].wrapDistance = wrapDistances.top
                }
                if let wrapSide { floatingImages[index].wrapSide = wrapSide }
                if let wrapping { floatingImages[index].wrapping = wrapping }; if let layer { floatingImages[index].layer = layer }
                if let anchor {
                    floatingImages[index].anchor = anchor
                    if anchor != .paragraph && anchor != .character && anchorOffsetX == nil && anchorOffsetY == nil {
                        floatingImages[index].anchorOffsetX = nil
                        floatingImages[index].anchorOffsetY = nil
                    }
                }
                if let anchorLocation { floatingImages[index].anchorLocation = anchorLocation }
                if let anchorOffsetX { floatingImages[index].anchorOffsetX = anchorOffsetX }
                if let anchorOffsetY { floatingImages[index].anchorOffsetY = anchorOffsetY }
                if let preservesAspect { floatingImages[index].preservesAspectRatio = preservesAspect }
                if let zOrder { floatingImages[index].zOrder = zOrder }
                if let locked { floatingImages[index].positionLocked = locked }
                changes.append(BOLDScriptChange(operation: "Update floating image \(id)", affectedParagraphs: 0, affectedMatches: 1))
            case let .duplicateFloatingImage(id, x, y):
                guard let original = floatingImages.first(where: { $0.id == id }) else { throw BOLDScriptError("Image \(id) was not found. No changes were made.") }
                var copy = original
                copy.id = UUID()
                copy.x = x ?? original.x + 18
                copy.y = y ?? original.y + 18
                copy.zOrder = (floatingImages.map(\.zOrder).max() ?? -1) + 1
                copy.positionLocked = false
                floatingImages.append(copy)
                changes.append(BOLDScriptChange(operation: "Duplicate floating image \(id)", affectedParagraphs: 0, affectedMatches: 1))
            case let .alignFloatingImages(ids, alignment):
                guard ids.count >= 2, Set(ids).count == ids.count,
                      ids.allSatisfy({ id in floatingImages.contains(where: { $0.id == id }) }) else {
                    throw BOLDScriptError("alignFloatingImages needs at least two distinct, known images. No changes were made.")
                }
                let selected = floatingImages.filter { ids.contains($0.id) }
                guard !selected.contains(where: \.positionLocked) else { throw BOLDScriptError("alignFloatingImages includes a position-locked image. Unlock it first.") }
                guard Set(selected.map(\.pageIndex)).count == 1,
                      Set(selected.map(\.anchor)).count == 1 else {
                    throw BOLDScriptError("alignFloatingImages needs images on the same page with the same anchor coordinate system.")
                }
                let minX = selected.map(\.x).min() ?? 0
                let maxX = selected.map { $0.x + $0.width }.max() ?? 0
                let minY = selected.map(\.y).min() ?? 0
                let maxY = selected.map { $0.y + $0.height }.max() ?? 0
                let centerX = selected.map { $0.x + $0.width / 2 }.reduce(0, +) / Double(selected.count)
                let centerY = selected.map { $0.y + $0.height / 2 }.reduce(0, +) / Double(selected.count)
                for index in floatingImages.indices where ids.contains(floatingImages[index].id) {
                    switch alignment {
                    case .left: floatingImages[index].x = minX
                    case .center: floatingImages[index].x = centerX - floatingImages[index].width / 2
                    case .right: floatingImages[index].x = maxX - floatingImages[index].width
                    case .top: floatingImages[index].y = minY
                    case .middle: floatingImages[index].y = centerY - floatingImages[index].height / 2
                    case .bottom: floatingImages[index].y = maxY - floatingImages[index].height
                    }
                }
                changes.append(BOLDScriptChange(operation: "Align \(ids.count) floating images \(alignment.rawValue)", affectedParagraphs: 0, affectedMatches: ids.count))
            case let .inspectFloatingImages(ids):
                let matches = floatingImages.filter { ids == nil || ids!.contains($0.id) }
                guard ids == nil || matches.count == ids!.count else { throw BOLDScriptError("inspectFloatingImages references an unknown image.") }
                imageInspection = matches.sorted { $0.zOrder < $1.zOrder }
            }
        }
        do { _ = try Tables.records(in: output) }
        catch { throw BOLDScriptError("The planned edits would damage a table boundary. No changes were made.") }
        do { try FloatingImage.validate(floatingImages, textLength: output.length) }
        catch { throw BOLDScriptError("The planned image layout is invalid: \(error.localizedDescription)") }
        return BOLDScriptPlan(output: output, floatingImages: floatingImages, changes: changes, imageInspection: imageInspection)
    }

    private static func exactMatches(_ needle: String, in text: String) -> [NSRange] {
        guard !needle.isEmpty else { return [] }
        let value = text as NSString
        var ranges: [NSRange] = []
        var cursor = 0
        while cursor <= value.length {
            let range = value.range(of: needle, options: [], range: NSRange(location: cursor, length: value.length - cursor))
            if range.location == NSNotFound { break }
            ranges.append(range)
            cursor = NSMaxRange(range)
        }
        return ranges
    }

    private static func paragraphCount(_ ranges: [NSRange], in text: String) -> Int {
        let ns = text as NSString
        return Set(ranges.map { ns.paragraphRange(for: $0).location }).count
    }

    private static func applyParagraphStyle(prefix: String, style: WriterStyle, to text: NSMutableAttributedString) -> Int {
        let ns = text.string as NSString
        guard ns.length > 0 else { return 0 }
        var location = 0
        var appliedRanges: [NSRange] = []
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = style.headingLevel == nil ? 7 : 10
        paragraph.paragraphSpacingBefore = style.headingLevel == nil ? 0 : 8
        paragraph.lineSpacing = style == .normal ? 2 : 1
        while location < ns.length {
            let range = ns.paragraphRange(for: NSRange(location: location, length: 0))
            let value = ns.substring(with: range).trimmingCharacters(in: .newlines)
            if value.hasPrefix(prefix) {
                let copy = paragraph.mutableCopy() as! NSMutableParagraphStyle
                if let existing = text.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle { copy.textBlocks = existing.textBlocks }
                let currentParagraph = text.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
                let currentStyle = text.attribute(.boldWriterStyle, at: range.location, effectiveRange: nil) as? String
                let currentFont = text.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
                let currentNamed = text.attribute(.boldWriterParagraphStyle, at: range.location, effectiveRange: nil)
                let sameParagraph = currentParagraph.map {
                    $0.paragraphSpacing == copy.paragraphSpacing
                        && $0.paragraphSpacingBefore == copy.paragraphSpacingBefore
                        && $0.lineSpacing == copy.lineSpacing
                        && $0.headIndent == copy.headIndent
                        && $0.firstLineHeadIndent == copy.firstLineHeadIndent
                        && $0.tailIndent == copy.tailIndent
                        && $0.alignment == copy.alignment
                } ?? false
                if currentStyle == style.rawValue,
                   currentFont?.isEqual(style.font) == true,
                   sameParagraph,
                   currentNamed == nil {
                    location = NSMaxRange(range)
                    continue
                }
                text.addAttributes([.font: style.font, .paragraphStyle: copy, .boldWriterStyle: style.rawValue], range: range)
                text.removeAttribute(.boldWriterParagraphStyle, range: range)
                appliedRanges.append(range)
            }
            location = NSMaxRange(range)
        }
        return paragraphCount(appliedRanges, in: text.string)
    }
}
