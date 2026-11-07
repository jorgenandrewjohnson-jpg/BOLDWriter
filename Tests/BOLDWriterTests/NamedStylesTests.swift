import AppKit
import XCTest
@testable import BOLDWriter

@MainActor
final class NamedStylesTests: XCTestCase {
    private func reopen(_ text: NSAttributedString, metadata: DocumentMetadata = DocumentMetadata()) throws -> BOLDWriterDocument {
        let wrapper = try BOLDWriterDocument.packageWrapper(text: text, metadata: metadata)
        return try BOLDWriterDocument(fileWrapper: wrapper, contentType: .boldWriterDocument)
    }

    func testBuiltInsAndInheritanceResolveAcrossSeveralLevels() throws {
        var styles = NamedStyleDefinition.builtIns
        let base = NamedStyleDefinition(styleID: "Brand", name: "Brand", formatting: .init(fontSize: 21, foregroundColor: "123456"))
        let middle = NamedStyleDefinition(styleID: "BrandHeading", name: "Brand Heading", basedOn: "Brand", formatting: .init(bold: true))
        let leaf = NamedStyleDefinition(styleID: "SpecialHeading", name: "Special Heading", basedOn: "BrandHeading", formatting: .init(fontSize: 26))
        styles += [base, middle, leaf]
        try NamedStyles.validate(styles)
        let value = try XCTUnwrap(NamedStyles.resolve("SpecialHeading", in: styles))
        XCTAssertEqual(value.fontSize, 26)
        XCTAssertEqual(value.bold, true)
        XCTAssertEqual(value.foregroundColor, "123456")
        XCTAssertEqual(NamedStyleDefinition.builtIns.count, 13)
    }

    func testDuplicateAndCyclicStylesFailButMissingParentIsTolerated() throws {
        let a = NamedStyleDefinition(styleID: "A", name: "A", basedOn: "B")
        let b = NamedStyleDefinition(styleID: "B", name: "B", basedOn: "A")
        XCTAssertThrowsError(try NamedStyles.validate(NamedStyleDefinition.builtIns + [a, b]))
        XCTAssertThrowsError(try NamedStyles.validate(NamedStyleDefinition.builtIns + [a, a]))
        XCTAssertNoThrow(try NamedStyles.validate(NamedStyleDefinition.builtIns + [NamedStyleDefinition(styleID: "MissingParent", name: "Missing Parent", basedOn: "Gone")] ))
    }


    func testMalformedNativeStyleDefinitionsAndRunsFailSafely() throws {
        let package = try BOLDWriterDocument.packageWrapper(text: NSAttributedString(string: "Content"), metadata: DocumentMetadata())
        func withMetadata(_ metadata: DocumentMetadata) throws -> BOLDWriterDocument {
            let copy = FileWrapper(directoryWithFileWrappers: package.fileWrappers ?? [:])
            if let old = copy.fileWrappers?["metadata.json"] { copy.removeFileWrapper(old) }
            let file = FileWrapper(regularFileWithContents: try JSONEncoder().encode(metadata))
            file.preferredFilename = "metadata.json"
            copy.addFileWrapper(file)
            return try BOLDWriterDocument(fileWrapper: copy, contentType: .boldWriterDocument)
        }
        var duplicate = DocumentMetadata()
        duplicate.namedStyles = [NamedStyleDefinition(styleID: "A", name: "A"), NamedStyleDefinition(styleID: "A", name: "Other")]
        XCTAssertThrowsError(try withMetadata(duplicate))
        var badRun = DocumentMetadata()
        badRun.namedStyles = NamedStyleDefinition.builtIns + [NamedStyleDefinition(styleID: "Custom", name: "Custom")]
        badRun.namedStyleRuns = [NamedStyleRun(styleID: "Custom", kind: .paragraph, location: Int.max, length: 2)]
        XCTAssertThrowsError(try withMetadata(badRun))
    }

    func testMalformedDOCXStylesAndDuplicateIDsFailSafely() throws {
        func package(stylesXML: String) throws -> Data {
            ZipArchiveWriter.archive([
                ZipEntry(path: "word/document.xml", data: Data("<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:body><w:p><w:r><w:t>safe</w:t></w:r></w:p></w:body></w:document>".utf8)),
                ZipEntry(path: "word/_rels/document.xml.rels", data: Data("<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"s\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/></Relationships>".utf8)),
                ZipEntry(path: "word/styles.xml", data: Data(stylesXML.utf8))
            ])
        }
        let duplicate = "<w:styles xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:style w:type=\"paragraph\" w:styleId=\"X\"><w:name w:val=\"X\"/></w:style><w:style w:type=\"paragraph\" w:styleId=\"X\"><w:name w:val=\"Y\"/></w:style></w:styles>"
        XCTAssertThrowsError(try DOCXStyleCatalog.read(from: package(stylesXML: duplicate)))
        let cycle = "<w:styles xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:style w:type=\"paragraph\" w:styleId=\"X\"><w:name w:val=\"X\"/><w:basedOn w:val=\"Y\"/></w:style><w:style w:type=\"paragraph\" w:styleId=\"Y\"><w:name w:val=\"Y\"/><w:basedOn w:val=\"X\"/></w:style></w:styles>"
        XCTAssertThrowsError(try DOCXStyleCatalog.read(from: package(stylesXML: cycle)))
        XCTAssertThrowsError(try DOCXStyleCatalog.read(from: package(stylesXML: "<w:styles")))
    }

    func testNativePersistenceKeepsCustomStyleDefinitionIdentityAndRuns() throws {
        let custom = NamedStyleDefinition(styleID: "LegalHeading", name: "Legal Heading", basedOn: "Heading1", formatting: .init(fontSize: 22, bold: true))
        let text = NSMutableAttributedString(string: "A heading\nbody", attributes: [.font: NSFont.systemFont(ofSize: 15)])
        text.addAttribute(.boldWriterParagraphStyle, value: WordParagraphStyle(styleID: custom.styleID, name: custom.name, basedOn: custom.basedOn), range: NSRange(location: 0, length: 10))
        text.addAttribute(.boldWriterCharacterStyle, value: WordCharacterStyle(styleID: "Emphasis", name: "Emphasis"), range: NSRange(location: 2, length: 4))
        var metadata = DocumentMetadata()
        metadata.namedStyles = NamedStyleDefinition.builtIns + [custom, NamedStyleDefinition(styleID: "Emphasis", name: "Emphasis", kind: .character, formatting: .init(italic: true))]
        let restored = try reopen(text, metadata: metadata)
        XCTAssertEqual(restored.metadata.namedStyles?.first(where: { $0.styleID == custom.styleID })?.basedOn, "Heading1")
        XCTAssertEqual((restored.text.attribute(.boldWriterParagraphStyle, at: 0, effectiveRange: nil) as? WordParagraphStyle)?.styleID, custom.styleID)
        XCTAssertEqual((restored.text.attribute(.boldWriterCharacterStyle, at: 3, effectiveRange: nil) as? WordCharacterStyle)?.styleID, "Emphasis")
    }

    func testNativeStyleRestorePreservesOrderedDependenciesAndReusesImmutableValues() throws {
        let paragraph = NamedStyleDefinition(styleID: "Paragraph", name: "Paragraph")
        let character = NamedStyleDefinition(styleID: "Character", name: "Character", kind: .character)
        let other = NamedStyleDefinition(styleID: "Other", name: "Other")
        let text = NSMutableAttributedString(string: "A\nB\nC\n", attributes: [.font: NSFont.systemFont(ofSize: 15)])
        for location in [0, 4] {
            text.addAttribute(
                .boldWriterParagraphStyle,
                value: WordParagraphStyle(styleID: paragraph.styleID, name: paragraph.name),
                range: NSRange(location: location, length: 1)
            )
        }
        text.addAttribute(
            .boldWriterCharacterStyle,
            value: WordCharacterStyle(styleID: character.styleID, name: character.name),
            range: NSRange(location: 2, length: 1)
        )
        var metadata = DocumentMetadata()
        metadata.namedStyles = [paragraph, character, other]

        let restored = try reopen(text, metadata: metadata)
        let firstParagraph = try XCTUnwrap(restored.text.attribute(.boldWriterParagraphStyle, at: 0, effectiveRange: nil) as? WordParagraphStyle)
        let secondParagraph = try XCTUnwrap(restored.text.attribute(.boldWriterParagraphStyle, at: 4, effectiveRange: nil) as? WordParagraphStyle)
        let restoredCharacter = try XCTUnwrap(restored.text.attribute(.boldWriterCharacterStyle, at: 2, effectiveRange: nil) as? WordCharacterStyle)
        let restoredDefinitions = try XCTUnwrap(restored.metadata.namedStyles)
        let paragraphDependencies = restoredDefinitions.filter { $0.styleID != paragraph.styleID }
        let characterDependencies = restoredDefinitions.filter { $0.styleID != character.styleID }

        XCTAssertTrue(firstParagraph === secondParagraph)
        XCTAssertEqual(firstParagraph.dependencies.map(\.styleID), paragraphDependencies.map(\.styleID))
        XCTAssertEqual(firstParagraph.dependencies.map(\.kind.rawValue), paragraphDependencies.map { $0.kind == .character ? "character" : "paragraph" })
        XCTAssertEqual(restoredCharacter.dependencies.map(\.styleID), characterDependencies.map(\.styleID))
        XCTAssertEqual(restoredCharacter.dependencies.map(\.kind.rawValue), characterDependencies.map { $0.kind == .character ? "character" : "paragraph" })
    }

    func testDOCXExportsNamedStylesAndReimportsTheirDefinitionsAndAppliedIdentity() throws {
        let custom = NamedStyleDefinition(styleID: "LegalHeading", name: "Legal Heading", basedOn: "Heading1", formatting: .init(fontSize: 22, bold: true, spaceAfter: 9))
        let text = NSMutableAttributedString(string: "Heading\n", attributes: [.font: NSFont.systemFont(ofSize: 22), .boldWriterParagraphStyle: WordParagraphStyle(styleID: custom.styleID, name: custom.name, basedOn: custom.basedOn)])
        let data = try DOCXExporter.data(from: text, title: "Styles", namedStyles: NamedStyleDefinition.builtIns + [custom])
        let styles = try DOCXStyleCatalog.read(from: data)
        XCTAssertEqual(styles.first(where: { $0.styleID == custom.styleID })?.basedOn, "Heading1")
        XCTAssertEqual(styles.first(where: { $0.styleID == custom.styleID })?.name, "Legal Heading")
        XCTAssertEqual(styles.first(where: { $0.styleID == custom.styleID })?.formatting.fontSize, 22)
        let wrapper = FileWrapper(regularFileWithContents: data)
        wrapper.preferredFilename = "Styles.docx"
        let imported = try BOLDWriterDocument(fileWrapper: wrapper, contentType: .docx)
        XCTAssertEqual((imported.text.attribute(.boldWriterParagraphStyle, at: 0, effectiveRange: nil) as? WordParagraphStyle)?.styleID, custom.styleID)
    }

    func testApplyingSemanticStylePreservesFootnoteEndnoteCommentAndTrackedMetadata() throws {
        let text = NSMutableAttributedString(string: "Footnote1 Endnote1 Comment tracked", attributes: [.font: NSFont.systemFont(ofSize: 15)])
        var metadata = DocumentMetadata()
        let footnote = Footnote(text: "note", location: 8, length: 1)
        let endnote = Endnote(text: "end", location: 17, length: 1)
        text.addAttribute(.footnote, value: Footnotes.payload(footnote), range: NSRange(location: 8, length: 1))
        text.addAttribute(.endnote, value: Endnotes.payload(endnote), range: NSRange(location: 17, length: 1))
        metadata.comments = [DocumentComment(text: "comment", location: 25, length: 7)]
        text.addAttribute(.boldWriterTrackChange, value: TrackChanges.marker(id: UUID(), kind: .insertion), range: NSRange(location: 28, length: 6))
        let before = try reopen(text, metadata: metadata)
        XCTAssertEqual(try Footnotes.records(in: before.text).count, 1)
        XCTAssertEqual(try Endnotes.records(in: before.text).count, 1)
        XCTAssertEqual(before.metadata.comments.count, 1)
        XCTAssertEqual(before.metadata.trackedChanges?.count, 1)
    }

    func testBuiltInHeadingsRetainSemanticIdentityThroughNativeAndDOCX() throws {
        let text = NSMutableAttributedString(string: "One\nTwo\nThree\n", attributes: [.font: NSFont.systemFont(ofSize: 15)])
        for (location, style) in [(0, WriterStyle.heading1), (4, .heading2), (8, .heading3)] {
            text.addAttribute(.boldWriterStyle, value: style.rawValue, range: NSRange(location: location, length: 4))
        }
        let native = try reopen(text)
        XCTAssertEqual(native.text.attribute(.boldWriterStyle, at: 0, effectiveRange: nil) as? String, WriterStyle.heading1.rawValue)
        XCTAssertEqual(native.text.attribute(.boldWriterStyle, at: 4, effectiveRange: nil) as? String, WriterStyle.heading2.rawValue)
        XCTAssertEqual(native.text.attribute(.boldWriterStyle, at: 8, effectiveRange: nil) as? String, WriterStyle.heading3.rawValue)
        let docx = try DOCXExporter.data(from: native.text, title: "Headings", namedStyles: native.metadata.namedStyles ?? [])
        let wrapper = FileWrapper(regularFileWithContents: docx); wrapper.preferredFilename = "Headings.docx"
        let imported = try BOLDWriterDocument(fileWrapper: wrapper, contentType: .docx)
        XCTAssertEqual(imported.text.attribute(.boldWriterStyle, at: 0, effectiveRange: nil) as? String, WriterStyle.heading1.rawValue)
        XCTAssertEqual(imported.text.attribute(.boldWriterStyle, at: 4, effectiveRange: nil) as? String, WriterStyle.heading2.rawValue)
        XCTAssertEqual(imported.text.attribute(.boldWriterStyle, at: 8, effectiveRange: nil) as? String, WriterStyle.heading3.rawValue)
    }

    func testDirectOverrideAndClearFormattingKeepNamedStyleIdentity() throws {
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        view.textStorage?.setAttributedString(NSAttributedString(string: "Styled word\n", attributes: [.font: NSFont.systemFont(ofSize: 15)]))
        let editor = EditorController(); editor.attach(view)
        view.setSelectedRange(NSRange(location: 0, length: 12))
        editor.applyStyle(.heading1)
        let word = (view.string as NSString).range(of: "word")
        view.setSelectedRange(word)
        editor.toggleTrait(.italicFontMask)
        XCTAssertEqual(view.textStorage?.attribute(.boldWriterStyle, at: 0, effectiveRange: nil) as? String, WriterStyle.heading1.rawValue)
        editor.clearDirectFormatting()
        XCTAssertEqual(view.textStorage?.attribute(.boldWriterStyle, at: 0, effectiveRange: nil) as? String, WriterStyle.heading1.rawValue)
        let font = try XCTUnwrap(view.textStorage?.attribute(.font, at: word.location, effectiveRange: nil) as? NSFont)
        XCTAssertFalse(NSFontManager.shared.traits(of: font).contains(.italicFontMask))
    }

    func testCustomStyleCanBeCreatedAndUpdatedFromSelection() throws {
        let document = BOLDWriterDocument()
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        view.textStorage?.setAttributedString(NSAttributedString(string: "Custom text\n", attributes: [.font: NSFont.systemFont(ofSize: 15)]))
        let editor = EditorController(); editor.attach(view); editor.document = document
        view.setSelectedRange(NSRange(location: 0, length: 12))
        let custom = try XCTUnwrap(editor.createNamedStyle(name: "Research Note", basedOn: .normal))
        editor.applyNamedStyle(custom)
        view.setSelectedRange(NSRange(location: 0, length: 6))
        editor.setFontSize(19)
        XCTAssertTrue(editor.updateNamedStyleFromSelection())
        XCTAssertEqual(document.metadata.namedStyles?.first(where: { $0.styleID == custom.styleID })?.formatting.fontSize, 19)
        XCTAssertEqual((view.textStorage?.attribute(.boldWriterParagraphStyle, at: 0, effectiveRange: nil) as? WordParagraphStyle)?.styleID, custom.styleID)
    }

    func testCustomCharacterStylePersistsAndExportsAsRunStyle() throws {
        let document = BOLDWriterDocument()
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        view.textStorage?.setAttributedString(NSAttributedString(string: "Emphasis here", attributes: [.font: NSFont.systemFont(ofSize: 15)]))
        let editor = EditorController(); editor.attach(view); editor.document = document
        view.setSelectedRange(NSRange(location: 0, length: 8))
        let style = try XCTUnwrap(editor.createNamedStyle(name: "Research Emphasis", kind: .character))
        editor.applyNamedStyle(style)
        let restored = try reopen(view.attributedString(), metadata: document.metadata)
        XCTAssertEqual((restored.text.attribute(.boldWriterCharacterStyle, at: 2, effectiveRange: nil) as? WordCharacterStyle)?.styleID, style.styleID)
        let data = try DOCXExporter.data(from: restored.text, title: "Character Style", namedStyles: restored.metadata.namedStyles ?? [])
        let catalog = try DOCXStyleCatalog.read(from: data)
        XCTAssertEqual(catalog.first(where: { $0.styleID == style.styleID })?.kind, .character)
    }
}
