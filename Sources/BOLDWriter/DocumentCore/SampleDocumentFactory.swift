import AppKit
import Foundation

enum SampleDocumentFactory {
    static func make() -> (NSAttributedString, DocumentMetadata) {
        let result = NSMutableAttributedString()
        append("The Lantern at North Harbor\n", style: .title, to: result)
        append("An original BOLD Writer sample manuscript\n", style: .subtitle, to: result)
        result.append(NSAttributedString(attachment: harborArtwork()))
        append("\nNorth Harbor — original geometric illustration\n", style: .caption, to: result)
        append("Chapter One — A Light in the Rain\n", style: .heading1, to: result)
        append("Mara arrived before dawn, when the harbor lamps were still brighter than the sky. She carried a weathered notebook and a quiet conviction that every careful word could become a kind of shelter.\n\n", style: .normal, to: result)
        let emphasis = NSMutableAttributedString(string: "A manuscript can be both bold and humane.\n\n", attributes: [.font: WriterStyle.normal.font])
        emphasis.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 15), range: (emphasis.string as NSString).range(of: "bold"))
        emphasis.addAttribute(.font, value: WriterStyle.normal.font.withItalicTrait(), range: (emphasis.string as NSString).range(of: "humane"))
        result.append(emphasis)
        append("Questions for the Journey\n", style: .heading2, to: result)
        append("• What deserves patient attention?\n• Which argument needs clearer evidence?\n• Where should the reader pause?\n\n", style: .normal, to: result)
        append("Working Table\n", style: .heading2, to: result)
        if var table = try? WriterTable(rows: 4, columns: 3) {
            let values = [["Section", "Purpose", "Status"], ["Opening", "Establish the harbor", "Drafted"], ["Argument", "Develop the central claim", "Review"], ["Conclusion", "Return to the lantern", "Planned"]]
            table.header = true
            table.widths = [25, 50, 25]
            for row in 0..<4 { for column in 0..<3 { table.cells[row][column] = NSAttributedString(string: values[row][column], attributes: [.font: WriterStyle.defaultFont]) } }
            if let rendered = try? Tables.rendered(table) { result.append(rendered) }
            append("\n", style: .normal, to: result)
        }
        append("A Note on Revision\n", style: .heading1, to: result)
        append("Revision is not erasure; it is the practice of seeing the same idea with better light.¹ Double-click the footnote reference to edit its text.\n", style: .normal, to: result)
        let noteRange = (result.string as NSString).range(of: "¹")
        result.replaceCharacters(in: noteRange, with: Footnotes.marker(Footnote(text: "Revision lets a writer reconsider both meaning and expression.", location: noteRange.location, length: 1), number: 1))
        result.append(NSAttributedString(string: "\u{000C}"))
        append("Appendix\n", style: .heading1, to: result)
        append("This page begins after an explicit page break. The sample footer and page numbers appear in PDF export.\n", style: .normal, to: result)

        var metadata = DocumentMetadata(title: "The Lantern at North Harbor")
        metadata.page.footerText = "The Lantern at North Harbor"
        metadata.comments = [DocumentComment(text: "Consider expanding this transition in the next revision.", location: 0, length: min(28, result.length))]
        metadata.bookmarks = [DocumentBookmark(name: "Opening", location: 0)]
        metadata.notes = "Private manuscript note: keep the harbor imagery subtle. This note is not exported."
        return (result, metadata)
    }

    private static func harborArtwork() -> NSTextAttachment {
        let image = NSImage(size: NSSize(width: 360, height: 100))
        image.lockFocus()
        NSColor(calibratedRed: 0.13, green: 0.16, blue: 0.34, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 360, height: 100)).fill()
        NSColor(calibratedRed: 0.25, green: 0.50, blue: 0.67, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 360, height: 30)).fill()
        NSColor(calibratedRed: 0.95, green: 0.87, blue: 0.65, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 272, y: 58, width: 23, height: 23)).fill()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: 67, y: 25, width: 17, height: 50)).fill()
        NSColor.systemYellow.setFill()
        NSBezierPath(rect: NSRect(x: 62, y: 70, width: 27, height: 10)).fill()
        image.unlockFocus()
        let data = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        let wrapper = FileWrapper(regularFileWithContents: data)
        wrapper.preferredFilename = "north-harbor.png"
        let attachment = NSTextAttachment(fileWrapper: wrapper)
        attachment.attachmentCell = NSTextAttachmentCell(imageCell: image)
        return attachment
    }

    private static func append(_ value: String, style: WriterStyle, to result: NSMutableAttributedString) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = style.headingLevel == nil ? 7 : 10
        paragraph.lineSpacing = 2
        if value.contains("\t") {
            paragraph.tabStops = [NSTextTab(textAlignment: .left, location: 100), NSTextTab(textAlignment: .left, location: 340)]
        }
        result.append(NSAttributedString(string: value, attributes: [
            .font: style.font,
            .paragraphStyle: paragraph,
            .boldWriterStyle: style.rawValue
        ]))
    }
}
