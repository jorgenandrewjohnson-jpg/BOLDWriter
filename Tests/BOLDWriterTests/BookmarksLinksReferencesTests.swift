import AppKit
import XCTest
@testable import BOLDWriter

@MainActor
final class BookmarksLinksReferencesTests: XCTestCase {
    private func reopen(_ text: NSAttributedString, metadata: DocumentMetadata) throws -> BOLDWriterDocument {
        let wrapper = try BOLDWriterDocument.packageWrapper(text: text, metadata: metadata)
        return try BOLDWriterDocument(fileWrapper: wrapper, contentType: .boldWriterDocument)
    }

    func testBookmarkRangesRebaseAndNativePersistence() throws {
        let document = BOLDWriterDocument()
        document.replaceText(with: NSAttributedString(string: "before target after"))
        let bookmark = DocumentBookmark(name: "Target", location: 7, length: 6)
        document.metadata.bookmarks = [bookmark]

        document.replaceEditedText(with: NSAttributedString(string: "new before target after"))
        XCTAssertEqual(document.metadata.bookmarks.first?.location, 11)
        document.replaceEditedText(with: NSAttributedString(string: "new before taXXrget after"))
        XCTAssertEqual(document.metadata.bookmarks.first?.length, 8)

        let restored = try reopen(document.text, metadata: document.metadata)
        XCTAssertEqual(restored.metadata.bookmarks, document.metadata.bookmarks)
        XCTAssertEqual(restored.metadata.bookmarks.first?.id, bookmark.id)
    }

    func testBookmarkDOCXRoundTripAndInternalHyperlink() throws {
        let text = NSMutableAttributedString(string: "Go to Target")
        text.addAttribute(.link, value: "#Chapter", range: NSRange(location: 0, length: 5))
        let bookmark = DocumentBookmark(name: "Chapter", location: 6, length: 6)
        let data = try DOCXExporter.data(from: text, title: "Links", bookmarks: [bookmark])
        let wrapper = FileWrapper(regularFileWithContents: data)
        wrapper.preferredFilename = "Links.docx"
        let imported = try BOLDWriterDocument(fileWrapper: wrapper, contentType: .docx)

        XCTAssertEqual(imported.metadata.bookmarks.map(\.name), ["Chapter"])
        XCTAssertEqual(imported.metadata.bookmarks.first?.length, 6)
        XCTAssertEqual(imported.text.attribute(.link, at: 0, effectiveRange: nil) as? String, "#Chapter")
    }

    func testReferencedGeneratedBookmarkSurvivesImportEditAndDOCXReopen() throws {
        let text = NSMutableAttributedString(string:"Go to Target")
        text.addAttribute(.link,value:"#Chapter",range:NSRange(location:0,length:5))
        let bytes = try DOCXExporter.data(from:text,title:"Generated",bookmarks:[DocumentBookmark(name:"Chapter",location:6,length:6)])
        let entries = try DOCXPackage.entries(in:bytes).map { entry -> ZipEntry in
            guard entry.path == "word/document.xml" else { return entry }
            let xml = String(decoding:entry.data,as:UTF8.self).replacingOccurrences(of:"Chapter",with:"_GeneratedHeading")
            return ZipEntry(path:entry.path,data:Data(xml.utf8))
        }
        let imported = try BOLDWriterDocument(fileWrapper:FileWrapper(regularFileWithContents:ZipArchiveWriter.archive(entries)),contentType:.docx)
        XCTAssertEqual(imported.metadata.bookmarks.count,1)
        XCTAssertEqual(imported.text.attribute(.link, at: 0, effectiveRange: nil) as? String,
                       "#" + (imported.metadata.bookmarks.first?.name ?? ""),
                       "Imported links must resolve before any export repairs their names")
        let changed = NSMutableAttributedString(attributedString:imported.text)
        changed.insert(NSAttributedString(string:"New "),at:0)
        imported.replaceEditedText(with:changed)
        let output = try DOCXExporter.data(from:imported.text,title:"Reopened",bookmarks:imported.metadata.bookmarks)
        let reopened = try DOCXImporter.importedDocument(from:output)
        XCTAssertEqual(reopened.text.string,changed.string)
        XCTAssertEqual(reopened.bookmarks.first?.location,10)
        XCTAssertEqual(reopened.text.attribute(.link,at:4,effectiveRange:nil) as? String,"#BOLD__GeneratedHeading")
    }

    func testManyBookmarkExportsKeepUniqueTargetsWithoutRecursiveNameExpansion() throws {
        let text = NSMutableAttributedString(string:String(repeating:"x ",count:48))
        let bookmarks = (0..<48).map { i in DocumentBookmark(name:"Heading_"+String(i),location:i*2,length:1) }
        for i in 0..<48 { text.addAttribute(.link,value:"#Heading_"+String(i),range:NSRange(location:i*2,length:1)) }
        let bytes = try DOCXExporter.data(from:text,title:"Many headings",bookmarks:bookmarks)
        let reopened = try DOCXImporter.importedDocument(from:bytes)
        XCTAssertEqual(reopened.bookmarks.count,48)
        XCTAssertEqual(Set(reopened.bookmarks.map(\.name)),Set(bookmarks.map(\.name)))
        XCTAssertEqual(reopened.text.string,text.string)
    }

    func testNativeCrossReferenceFieldPersistsAndUpdatesTargetText() throws {
        let document = BOLDWriterDocument()
        document.replaceText(with: NSAttributedString(string: "Alpha reference"))
        let target = DocumentBookmark(name: "Heading", location: 0, length: 5)
        document.metadata.bookmarks = [target]
        let field = WordField(kind: .simple, instruction: " REF Heading \\h ")
        let text = NSMutableAttributedString(attributedString: document.text)
        text.addAttribute(.boldWriterField, value: field, range: NSRange(location: 6, length: 9))
        document.replaceText(with: text)

        let restored = try reopen(document.text, metadata: document.metadata)
        let persisted = try XCTUnwrap(restored.text.attribute(.boldWriterField, at: 6, effectiveRange: nil) as? WordField)
        XCTAssertEqual(persisted.instruction, field.instruction)
        XCTAssertEqual(persisted.id, field.id)

        let controller = EditorController()
        let view = WritingTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        view.textStorage?.setAttributedString(restored.text)
        controller.attach(view)
        let updated = controller.updateCrossReferences(in: restored)
        XCTAssertEqual(updated, 1)
        XCTAssertEqual((view.textStorage?.string as NSString?)?.substring(with: NSRange(location: 6, length: 5)), "Alpha")
        XCTAssertNotNil(view.textStorage?.attribute(.boldWriterField, at: 6, effectiveRange: nil) as? WordField)
    }

    func testHyperlinkMutationPreservesOtherInlineMetadata() throws {
        let document = BOLDWriterDocument()
        document.replaceText(with: NSAttributedString(string: "linked text"))
        let field = WordField(kind: .simple, instruction: " REF Destination ")
        let storage = NSMutableAttributedString(attributedString: document.text)
        storage.addAttribute(.boldWriterField, value: field, range: NSRange(location: 0, length: 6))
        storage.addAttribute(.boldWriterCharacterStyle, value: WordCharacterStyle(styleID: "Emphasis"), range: NSRange(location: 0, length: 6))
        document.replaceText(with: storage)
        let controller = EditorController()
        let view = WritingTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        view.textStorage?.setAttributedString(document.text)
        controller.attach(view)
        view.setSelectedRange(NSRange(location: 0, length: 6))
        controller.updateSelection(NSRange(location: 0, length: 6))

        try controller.applyHyperlink("https://example.com", in: document)
        XCTAssertNotNil(view.textStorage?.attribute(.boldWriterField, at: 0, effectiveRange: nil) as? WordField)
        XCTAssertNotNil(view.textStorage?.attribute(.boldWriterCharacterStyle, at: 0, effectiveRange: nil) as? WordCharacterStyle)
        view.setSelectedRange(NSRange(location: 0, length: 6))
        controller.updateSelection(NSRange(location: 0, length: 6))
        controller.removeHyperlink()
        XCTAssertNil(view.textStorage?.attribute(.link, at: 0, effectiveRange: nil))
        XCTAssertNotNil(view.textStorage?.attribute(.boldWriterField, at: 0, effectiveRange: nil) as? WordField)
        XCTAssertNotNil(view.textStorage?.attribute(.boldWriterCharacterStyle, at: 0, effectiveRange: nil) as? WordCharacterStyle)
    }

    func testMalformedBookmarkMetadataFailsSafely() throws {
        let text = NSAttributedString(string: "short")
        var metadata = DocumentMetadata()
        metadata.bookmarks = [DocumentBookmark(name: "Same", location: 0), DocumentBookmark(name: "same", location: 1)]
        XCTAssertThrowsError(try BOLDWriterDocument.packageWrapper(text: text, metadata: metadata))
        metadata.bookmarks = [DocumentBookmark(name: "OutOfBounds", location: 4, length: 2)]
        XCTAssertThrowsError(try BOLDWriterDocument.packageWrapper(text: text, metadata: metadata))
    }
}
