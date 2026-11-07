import AppKit
import UniformTypeIdentifiers
import XCTest
@testable import BOLDWriter

@MainActor
final class ManuscriptWorkflowTests: XCTestCase {
    func testFastXMLTraversalMatchesNamespaceIndependentXPathOrder() throws {
        let xml = try DOCXPackage.xml(Data("<x:document xmlns:x='urn:word'><x:p id='outside'/><x:body><x:p id='first'/><x:table><x:p id='nested'/></x:table><x:body><x:p id='last'/></x:body></x:body></x:document>".utf8))
        let expected = try xml.nodes(forXPath: "//*[local-name()='body']//*[local-name()='p']")
        XCTAssertEqual(DOCXPackage.bodyParagraphs(in: xml).map(\.xmlString), expected.map(\.xmlString))
        XCTAssertEqual(DOCXPackage.descendants(in: xml, named: "p").map(\.xmlString), try xml.nodes(forXPath: "//*[local-name()='p']").map(\.xmlString))
    }

    func testRealManuscriptLinksFormattingAndNativeReopen() throws {
        guard let path = ProcessInfo.processInfo.environment["BOLD_ACCEPTANCE_DOCX"] else {
            throw XCTSkip("Set BOLD_ACCEPTANCE_DOCX to the authorized manuscript proof")
        }
        let document = try BOLDWriterDocument(fileWrapper: FileWrapper(url: URL(fileURLWithPath: path)), contentType: .docx)
        XCTAssertGreaterThan(document.text.length, 500_000)
        XCTAssertEqual(document.metadata.page.pageSize.width, 396, accuracy: 0.01)
        XCTAssertEqual(document.metadata.page.pageSize.height, 612, accuracy: 0.01)
        var linkCount = 0
        document.text.enumerateAttribute(.link, in: NSRange(location: 0, length: document.text.length)) { value, _, _ in
            guard let value else { return }
            let target = (value as? URL)?.absoluteString ?? String(describing: value)
            if target.hasPrefix("#") {
                linkCount += 1
                XCTAssertNotNil(document.metadata.bookmarks.first { $0.name.caseInsensitiveCompare(String(target.dropFirst())) == .orderedSame }, target)
            }
        }
        XCTAssertEqual(linkCount, 38)
        document.text.enumerateAttribute(.strikethroughStyle, in: NSRange(location: 0, length: document.text.length)) { value, _, _ in
            XCTAssertEqual((value as? Int) ?? 0, 0)
        }
        let package = try BOLDWriterDocument.packageWrapper(text: document.text, metadata: document.metadata)
        let reopened = try BOLDWriterDocument(fileWrapper: package, contentType: .boldWriterDocument)
        XCTAssertEqual(reopened.text.string, document.text.string)
        XCTAssertEqual(reopened.metadata.bookmarks, document.metadata.bookmarks)
        XCTAssertEqual(reopened.metadata.page, document.metadata.page)
        let epub = try EPUBExporter.data(from: document.text, title: "Sample book proof", bookmarks: document.metadata.bookmarks)
        let entries = try DOCXPackage.entries(in: epub)
        let content = try XCTUnwrap(entries.first { $0.path.hasSuffix("content.xhtml") }).data
        let xhtml = try DOCXPackage.xml(content)
        let ids = Set(try xhtml.nodes(forXPath: "//@id").compactMap(\.stringValue))
        let internalLinks = try xhtml.nodes(forXPath: "//@href").compactMap(\.stringValue).filter { $0.hasPrefix("#") }
        XCTAssertGreaterThanOrEqual(internalLinks.count, 38)
        for target in internalLinks { XCTAssertTrue(ids.contains(String(target.dropFirst())), target) }
    }

    func testExplicitStrikeOffImportsAndRoundTripsWithoutLinesThroughText() throws {
        let source=NSMutableAttributedString(string:"Off On Off")
        source.addAttribute(.strikethroughStyle,value:0,range:NSRange(location:0,length:3))
        source.addAttribute(.strikethroughStyle,value:1,range:NSRange(location:4,length:2))
        source.addAttribute(.strikethroughStyle,value:0,range:NSRange(location:7,length:3))
        let bytes=try DOCXExporter.data(from:source,title:"Strike flags")
        var imported=try DOCXImporter.importedDocument(from:bytes).text
        for _ in 0..<2 {
            XCTAssertEqual(imported.string,source.string)
            XCTAssertEqual(imported.attribute(.strikethroughStyle,at:0,effectiveRange:nil) as? Int ?? 0,0)
            XCTAssertEqual(imported.attribute(.strikethroughStyle,at:4,effectiveRange:nil) as? Int,1)
            XCTAssertEqual(imported.attribute(.strikethroughStyle,at:7,effectiveRange:nil) as? Int ?? 0,0)
            imported=try DOCXImporter.importedDocument(from:DOCXExporter.data(from:imported,title:"Round trip")).text
        }
    }
    func testContinuousCanvasIncludesEntireManuscriptAndNavigatesToLastChapter() throws {
        _ = NSApplication.shared
        let source=NSAttributedString(string:String(repeating:"A paragraph in a long manuscript with enough text to fill many lines.\n",count:2000)+"FINAL CHAPTER\n")
        let canvas=PaginatedEditor(text:source)
        let scroll=NSScrollView(frame:NSRect(x:0,y:0,width:800,height:600));scroll.documentView=canvas
        canvas.configure(printLayout:false,settings:PageSettings(),zoom:1,viewportWidth:800)
        let initialHeight=canvas.frame.height
        let container=try XCTUnwrap(canvas.firstView.textContainer),manager=try XCTUnwrap(canvas.firstView.layoutManager)
        manager.ensureLayout(for:container)
        XCTAssertGreaterThan(initialHeight,6000)
        XCTAssertGreaterThanOrEqual(initialHeight,manager.usedRect(for:container).height)
        let controller=EditorController();controller.attach(canvas.firstView)
        let target=(source.string as NSString).range(of:"FINAL CHAPTER")
        controller.navigate(to:target)
        XCTAssertEqual(controller.textView?.selectedRange(),target)
        XCTAssertGreaterThan(scroll.contentView.bounds.minY,0)
        XCTAssertEqual(canvas.firstView.string,source.string)
    }
    func testClickedChapterLinkUsesSharedBookmarkNavigationEngine() {
        _ = NSApplication.shared
        let document=BOLDWriterDocument();document.replaceEditedText(with:NSAttributedString(string:"Contents\nChapter One\n"))
        let target=DocumentBookmark(name:"_TocChapter",location:9,length:11);document.metadata.bookmarks=[target]
        let view=NSTextView();view.textStorage?.setAttributedString(document.text)
        let controller=EditorController();controller.attach(view)
        let coordinator=RichTextEditor.Coordinator(document:document,controller:controller)
        XCTAssertTrue(coordinator.textView(view,clickedOnLink:"#_TocChapter",at:0))
        XCTAssertEqual(view.selectedRange(),NSRange(location:9,length:11))
        XCTAssertFalse(coordinator.textView(view,clickedOnLink:"#Missing",at:0))
    }
}
