import AppKit

/// Supplemental, deduplicated attributes that RTFD drops or normalizes.
/// Only known Cocoa value classes and the application's Word formatting types decode.
struct NativeManuscriptFormatting: Codable, Equatable {
    struct Value: Codable, Hashable {
        var kind: String
        var data: Data? = nil
        var fields: [String:String]? = nil
    }
    struct Run: Codable, Equatable {
        var location: Int
        var length: Int
        var attributes: [String:Int]
    }
    var values: [Value]
    var runs: [Run]
    /// RTF synthesizes list markers when NSTextList paragraphs lack a literal
    /// prefix. Native packages restore these styles from this sidecar instead;
    /// keep their RTFD text identical so bookmarks, fields and pagination agree.
    static func textForNativeRTFD(_ text: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString:text)
        text.enumerateAttribute(.paragraphStyle,in:NSRange(location:0,length:text.length)) { value,range,_ in
            guard let style=value as? NSParagraphStyle, !style.textLists.isEmpty,
                  let copy=style.mutableCopy() as? NSMutableParagraphStyle else { return }
            copy.textLists=[]
            result.addAttribute(.paragraphStyle,value:copy,range:range)
        }
        return result
    }
    static let standard: Set<String> = [NSAttributedString.Key.font,.foregroundColor,.backgroundColor,.paragraphStyle,
        .underlineStyle,.underlineColor,.strikethroughStyle,.strikethroughColor,.superscript,.baselineOffset,
        .kern,.ligature,.link,.strokeColor,.strokeWidth,.obliqueness,.expansion,.writingDirection].map(\.rawValue).reduce(into:[]) { $0.insert($1) }

    static func capture(_ text: NSAttributedString) throws -> Self {
        var values: [Value] = [], indices: [Value:Int] = [:], runs:[Run] = []
        var failure: Error?
        text.enumerateAttributes(in:NSRange(location:0,length:text.length)) { attrs,range,stop in
            do {
                var fields:[String:Int] = [:]
                for (key,object) in attrs where standard.contains(key.rawValue) || key.rawValue.hasPrefix("BOLDWriter") {
                    guard let value = try encode(object) else { continue }
                    let index: Int
                    if let existing = indices[value] { index = existing }
                    else { index = values.count; values.append(value); indices[value] = index }
                    fields[key.rawValue] = index
                }
                if !fields.isEmpty { runs.append(Run(location:range.location,length:range.length,attributes:fields)) }
            } catch { failure = error; stop.pointee = true }
        }
        if let failure { throw failure }
        return Self(values:values,runs:runs)
    }
    func restore(into text: NSMutableAttributedString) throws {
        guard values.count <= 100_000, runs.count <= 2_000_000 else { throw CocoaError(.fileReadCorruptFile) }
        let objects = try values.map(Self.decode)
        // Validate every range and reference before applying anything.
        for run in runs {
            guard run.location >= 0,run.length >= 0,run.location <= text.length,run.length <= text.length-run.location,
                  run.attributes.allSatisfy({ key,index in (Self.standard.contains(key) || key.hasPrefix("BOLDWriter")) && objects.indices.contains(index) }) else { throw CocoaError(.fileReadCorruptFile) }
        }
        for key in Self.standard { text.removeAttribute(NSAttributedString.Key(key),range:NSRange(location:0,length:text.length)) }
        for run in runs {
            var attrs:[NSAttributedString.Key:Any] = [:]
            for (key,index) in run.attributes { attrs[NSAttributedString.Key(key)] = objects[index] }
            text.addAttributes(attrs,range:NSRange(location:run.location,length:run.length))
        }
        if runs.contains(where: { $0.attributes[NSAttributedString.Key.boldWriterInlineImageDisplaySize.rawValue] != nil }) {
            Self.restoreInlineImageDisplaySizes(in: text)
        }
    }

    /// RTFD stores the attachment's original encoded file but does not reliably
    /// persist AppKit's display bounds. Restore the physical display size from
    /// this sidecar attribute without rewriting the source image bytes.
    static func restoreInlineImageDisplaySizes(in text: NSMutableAttributedString) {
        text.enumerateAttribute(.boldWriterInlineImageDisplaySize, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard let attachment = text.attribute(.attachment, at: range.location, effectiveRange: nil) as? NSTextAttachment,
                  let raw = value as? String else { return }
            let dimensions = raw.split(separator: ",", omittingEmptySubsequences: false).compactMap { Double($0) }
            guard dimensions.count == 2, dimensions.allSatisfy({ $0.isFinite && $0 > 0 && $0 <= 20_000 }) else { return }
            let size = NSSize(width: dimensions[0], height: dimensions[1])
            attachment.bounds = NSRect(origin: .zero, size: size)
            if let bytes = attachment.fileWrapper?.regularFileContents ?? attachment.contents,
               let image = NSImage(data: bytes), image.isValid {
                image.size = size
                attachment.attachmentCell = NSTextAttachmentCell(imageCell: image)
            }
        }
    }
    private static func encode(_ object: Any) throws -> Value? {
        func fields(_ entries:[String:String?]) -> [String:String] { entries.compactMapValues { $0 } }
        switch object {
        case let v as WordRunFonts:
            return Value(kind:"fonts",fields:fields(["ascii":v.ascii,"hAnsi":v.hAnsi,"eastAsia":v.eastAsia,"complexScript":v.complexScript,"asciiTheme":v.asciiTheme,"hAnsiTheme":v.hAnsiTheme,"eastAsiaTheme":v.eastAsiaTheme,"complexScriptTheme":v.complexScriptTheme,"hint":v.hint]))
        case let v as WordLanguage:
            return Value(kind:"language",fields:fields(["value":v.value,"eastAsia":v.eastAsia,"bidi":v.bidi]))
        case let v as WordRunShading:
            return Value(kind:"runShading",fields:fields(["value":v.value,"color":v.color,"fill":v.fill,"themeColor":v.themeColor,"themeTint":v.themeTint,"themeShade":v.themeShade,"themeFill":v.themeFill,"themeFillTint":v.themeFillTint,"themeFillShade":v.themeFillShade]))
        case let v as WordParagraphShading:
            return Value(kind:"paragraphShading",fields:fields(["value":v.value,"color":v.color,"fill":v.fill]))
        case let v as WordParagraphBorders:
            var f:[String:String] = [:]
            for (name,b) in [("top",v.top),("left",v.left),("bottom",v.bottom),("right",v.right),("between",v.between)] {
                guard let b else { continue }; f[name+".style"] = b.style; f[name+".color"] = b.color
                f[name+".size"] = b.size.map(String.init); f[name+".space"] = b.space.map(String.init)
            }
            return Value(kind:"borders",fields:f)
        case is NSFont, is NSColor, is NSParagraphStyle, is NSString, is NSNumber, is NSURL, is NSArray:
            return Value(kind:"cocoa",data:try NSKeyedArchiver.archivedData(withRootObject:object,requiringSecureCoding:true))
        default: return nil // Existing dedicated field/table/attachment persistence remains responsible.
        }
    }
    private static func decode(_ value: Value) throws -> Any {
        let f = value.fields ?? [:]
        switch value.kind {
        case "fonts": return WordRunFonts(ascii:f["ascii"],hAnsi:f["hAnsi"],eastAsia:f["eastAsia"],complexScript:f["complexScript"],asciiTheme:f["asciiTheme"],hAnsiTheme:f["hAnsiTheme"],eastAsiaTheme:f["eastAsiaTheme"],complexScriptTheme:f["complexScriptTheme"],hint:f["hint"])
        case "language": return WordLanguage(value:f["value"],eastAsia:f["eastAsia"],bidi:f["bidi"])
        case "runShading": return WordRunShading(value:f["value"] ?? "clear",color:f["color"],fill:f["fill"],themeColor:f["themeColor"],themeTint:f["themeTint"],themeShade:f["themeShade"],themeFill:f["themeFill"],themeFillTint:f["themeFillTint"],themeFillShade:f["themeFillShade"])
        case "paragraphShading": return WordParagraphShading(value:f["value"] ?? "clear",color:f["color"],fill:f["fill"])
        case "borders":
            func border(_ name:String) -> WordParagraphBorder? {
                guard let style = f[name+".style"] else { return nil }
                return WordParagraphBorder(style:style,size:f[name+".size"].flatMap(Int.init),space:f[name+".space"].flatMap(Int.init),color:f[name+".color"])
            }
            return WordParagraphBorders(top:border("top"),left:border("left"),bottom:border("bottom"),right:border("right"),between:border("between"))
        case "cocoa":
            guard let data = value.data, data.count <= 1_000_000,
                  let object = try NSKeyedUnarchiver.unarchivedObject(ofClasses:[NSFont.self,NSColor.self,NSParagraphStyle.self,NSMutableParagraphStyle.self,NSTextTab.self,NSTextList.self,NSTextBlock.self,NSTextTable.self,NSTextTableBlock.self,NSString.self,NSNumber.self,NSURL.self,NSArray.self,NSDictionary.self],from:data) else { throw CocoaError(.fileReadCorruptFile) }
            return object
        default: throw CocoaError(.fileReadCorruptFile)
        }
    }
}
