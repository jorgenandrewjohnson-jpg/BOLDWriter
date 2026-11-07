import AppKit
import PDFKit
import XCTest
@testable import BOLDWriter

@MainActor
final class NativeManuscriptFormattingTests: XCTestCase {
    func testNativeListsPreserveLiteralTextOffsetsAndPaginationAcrossReopen() throws {
        for prefix in ["", "\t•\t"] {
            let string=(0..<160).map { "\(prefix)Item \($0) with enough words to exercise the printed list layout.\n" }.joined()
            let text=NSMutableAttributedString(string:string)
            let paragraph=NSMutableParagraphStyle()
            paragraph.textLists=[NSTextList(markerFormat:.disc,options:0)]
            paragraph.headIndent=36; paragraph.firstLineHeadIndent=36
            text.addAttributes([.font:NSFont.systemFont(ofSize:14),.paragraphStyle:paragraph],range:NSRange(location:0,length:text.length))
            let original=NSAttributedString(attributedString:text)
            let metadata=DocumentMetadata()
            let before=try PDFExporter.data(from:text,settings:metadata.page)
            var restored=try BOLDWriterDocument(fileWrapper:BOLDWriterDocument.packageWrapper(text:text,metadata:metadata),contentType:.boldWriterDocument)
            for _ in 0..<2 {
                XCTAssertEqual(restored.text.string,string)
                XCTAssertEqual(restored.text.length,text.length)
                let style=try XCTUnwrap(restored.text.attribute(.paragraphStyle,at:0,effectiveRange:nil) as? NSParagraphStyle)
                XCTAssertEqual(style.textLists.first?.markerFormat,.disc)
                XCTAssertEqual(style.headIndent,36)
                let after=try PDFExporter.data(from:restored.text,settings:restored.metadata.page)
                XCTAssertEqual(PDFDocument(data:after)?.pageCount,PDFDocument(data:before)?.pageCount)
                restored=try BOLDWriterDocument(fileWrapper:BOLDWriterDocument.packageWrapper(text:restored.text,metadata:restored.metadata),contentType:.boldWriterDocument)
            }
            XCTAssertTrue(text.isEqual(to:original),"Saving must not mutate the live manuscript")
        }
    }
    func testNativeDiskPackagePreservesImportedWordAndCocoaFormattingExactly() throws {
        let text = NSMutableAttributedString(string:"Title\nBody paragraph\n")
        let p = NSMutableParagraphStyle(); p.paragraphSpacing = 14; p.headIndent = 20; p.lineSpacing = 3
        text.addAttributes([.font:NSFont(name:"TimesNewRomanPS-BoldMT",size:18)!, .paragraphStyle:p,
            .foregroundColor:NSColor(calibratedRed:0.2,green:0.3,blue:0.4,alpha:1),
            .boldWriterKeepWithNext:true,.boldWriterComplexScriptSize:18.0,.boldWriterLanguage:"en-US",
            .boldWriterRunFonts:WordRunFonts(ascii:"Times New Roman",complexScript:"Arial"),
            .boldWriterParagraphShading:WordParagraphShading(value:"clear",color:nil,fill:"EEEEEE"),
            .boldWriterParagraphBorders:WordParagraphBorders(bottom:WordParagraphBorder(style:"single",size:8,space:nil,color:"333333"))],
            range:NSRange(location:0,length:text.length))
        text.addAttribute(.link,value:URL(string:"https://example.com")!,range:NSRange(location:0,length:5))
        let wrapper = try BOLDWriterDocument.packageWrapper(text:text,metadata:DocumentMetadata())
        let restored = try BOLDWriterDocument(fileWrapper:wrapper,contentType:.boldWriterDocument)
        XCTAssertTrue(restored.text.isEqual(to:text))
    }
    func testSupplementDeduplicatesRepeatedAttributesAndRejectsInvalidRangesBeforeMutation() throws {
        let text = NSMutableAttributedString(string:"abc")
        text.addAttribute(.font,value:NSFont.systemFont(ofSize:14),range:NSRange(location:0,length:3))
        text.addAttribute(.boldWriterLanguage,value:"en-US",range:NSRange(location:0,length:1))
        let supplement = try NativeManuscriptFormatting.capture(text)
        XCTAssertEqual(supplement.values.count,2)
        var bad = supplement
        bad.runs.append(.init(location:2,length:2,attributes:["NSFont":0]))
        let target = NSMutableAttributedString(attributedString:text)
        XCTAssertThrowsError(try bad.restore(into:target)); XCTAssertTrue(target.isEqual(to:text))
    }
    func testSupplementRestoresInlineImageDisplayBoundsWithoutChangingSourceBytes() throws {
        let attachment = NSTextAttachment()
        attachment.bounds = NSRect(x: 0, y: 0, width: 12, height: 18)
        attachment.contents = Data([0x42, 0x4f, 0x4c, 0x44])
        let text = NSMutableAttributedString(attributedString: NSAttributedString(attachment: attachment))
        text.addAttribute(.boldWriterInlineImageDisplaySize, value: "180,90", range: NSRange(location: 0, length: text.length))
        let sourceBytes = attachment.contents
        let supplement = try NativeManuscriptFormatting.capture(text)
        let target = NSMutableAttributedString(attributedString: text)
        target.removeAttribute(.boldWriterInlineImageDisplaySize, range: NSRange(location: 0, length: target.length))
        let restoredAttachment = try XCTUnwrap(target.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment)
        restoredAttachment.bounds = NSRect(x: 0, y: 0, width: 1, height: 1)

        try supplement.restore(into: target)

        XCTAssertEqual(restoredAttachment.bounds.size, NSSize(width: 180, height: 90))
        XCTAssertEqual(restoredAttachment.contents, sourceBytes)
    }
    func testOldNativeMetadataWithoutSupplementStillDecodes() throws {
        let data = try JSONEncoder().encode(DocumentMetadata())
        XCTAssertNil(try JSONDecoder().decode(DocumentMetadata.self,from:data).manuscriptFormatting)
    }
}
