import AppKit
import UniformTypeIdentifiers
import XCTest
@testable import BOLDWriter

@MainActor
final class NativeInputRoutingTests: XCTestCase {
    func testConnectedPageViewsKeepWritingToolsDisabledAfterRepagination() throws {
        _ = NSApplication.shared

        let manuscript = NSAttributedString(
            string: String(repeating: "Repagination safety line.\\n", count: 600)
        )
        let canvas = PaginatedEditor(text: manuscript)

        for zoom in [CGFloat(1), CGFloat(1.25), CGFloat(0.85)] {
            canvas.configure(
                printLayout: true,
                settings: PageSettings(),
                zoom: zoom,
                viewportWidth: 800
            )

            XCTAssertGreaterThan(canvas.pages.count, 1)
            XCTAssertEqual(canvas.firstView.string, manuscript.string)

            if #available(macOS 15.0, *) {
                XCTAssertTrue(
                    canvas.pages.allSatisfy {
                        $0.writingToolsBehavior == .none
                    }
                )
            }
        }
    }

    func testStudioPageRevealUsesConnectedViewsWithoutWritingToolsAffordance() throws {
        _ = NSApplication.shared
        let text = NSAttributedString(string: String(repeating: "Manuscript page content.\n", count: 400))
        let canvas = PaginatedEditor(text: text)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        scroll.documentView = canvas
        canvas.configure(printLayout: true, settings: PageSettings(), zoom: 1, viewportWidth: 800)
        XCTAssertGreaterThan(canvas.pages.count, 1)
        for page in [1, canvas.pages.count / 2, canvas.pages.count, 1] {
            let selection = NSRange(location: min(page * 10, text.length - 20), length: 20)
            canvas.revealPhysicalPage(page, selection: selection)
            XCTAssertEqual(canvas.firstView.selectedRange(), selection)
            XCTAssertEqual(canvas.firstView.string, text.string)
            if #available(macOS 15.0, *) {
                XCTAssertTrue(canvas.pages.allSatisfy { $0.writingToolsBehavior == .none })
            }
        }
    }

    func testContinuousHitTestingAtMultipleZooms() throws {
        _ = NSApplication.shared
        let canvas = PaginatedEditor(text: NSAttributedString(string: "Native input routing\nSecond paragraph"))
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        scroll.documentView = canvas
        for zoom in [0.5, 1.0, 2.0] {
            canvas.configure(printLayout: false, settings: PageSettings(), zoom: zoom, viewportWidth: 800)
            let point = canvas.firstView.convert(NSPoint(x: 65, y: 50), to: scroll.contentView)
            XCTAssertTrue(canvas.hitTest(point) === canvas.firstView, "zoom \(zoom), canvas \(canvas.frame), text \(canvas.firstView.frame)")
        }
    }

    func testCustomPaperAndMirroredFooterRoundTrip() throws {
        var settings = PageSettings()
        settings.paper = .custom
        settings.customPaperSize = CGSize(width: 396, height: 612)
        settings.differentOddEvenHeaderFooter = true
        settings.footerText = "Footer"
        settings.evenPageFooterText = "Footer"
        settings.footerPosition = .right
        settings.pageNumberPosition = .right
        settings.evenPageFooterPosition = .left
        settings.evenPageNumberPosition = .left
        for landscape in [false, true] {
            settings.landscape = landscape
            let data = try DOCXExporter.data(from: NSAttributedString(string: "Book text"), title: "Book", settings: settings)
            let imported = try DOCXImporter.importedDocument(from: data)
            XCTAssertEqual(imported.page.pageSize, settings.pageSize)
            XCTAssertEqual(imported.page.evenPageFooterPosition, .left)
            XCTAssertEqual(imported.page.evenPageNumberPosition, .left)
            XCTAssertEqual(imported.page.effectiveFooterPosition, .right)
            let native = try JSONDecoder().decode(PageSettings.self, from: JSONEncoder().encode(imported.page))
            XCTAssertEqual(native, imported.page)
            XCTAssertEqual(native.resolvingEvenFooter(true).effectiveFooterPosition, .left)
        }
    }

    func testComplexFieldSpansParagraphsWithoutSplitting() throws {
        let source = NSMutableAttributedString(string: "\nChapter One\nChapter Two\nChapter Three\n")
        source.addAttribute(.boldWriterField,
                            value: WordField(kind: .complex, instruction: " TOC "),
                            range: NSRange(location: 0, length: source.length))
        let data = try DOCXExporter.data(from: source, title: "Fields")
        let entry = try XCTUnwrap(DOCXPackage.entries(in: data).first { $0.path == "word/document.xml" })
        let xml = try DOCXPackage.xml(entry.data)
        for kind in ["begin", "separate", "end"] {
            XCTAssertEqual(try xml.nodes(forXPath: "//*[local-name()='fldChar' and @*[local-name()='fldCharType']='\(kind)']").count, 1)
        }
        let imported = try DOCXImporter.importedDocument(from: data)
        XCTAssertEqual(imported.text.string, source.string)
        for phrase in ["Chapter One", "Chapter Two", "Chapter Three"] {
            let index = (imported.text.string as NSString).range(of: phrase).location
            let field = imported.text.attribute(.boldWriterField, at: index, effectiveRange: nil) as? WordField
            XCTAssertEqual(field?.instruction, " TOC ")
        }
    }

    func testEditorSaveRetainsRebasedInternalLinkTargets() throws {
        let source = NSMutableAttributedString(string:"Go to Chapter")
        source.addAttribute(.link,value:"#Chapter",range:NSRange(location:0,length:5))
        let bytes = try DOCXExporter.data(from:source,title:"Links",bookmarks:[DocumentBookmark(name:"Chapter",location:6,length:7)])
        let document = try BOLDWriterDocument(fileWrapper:FileWrapper(regularFileWithContents:bytes),contentType:.docx)
        let edited = NSMutableAttributedString(attributedString:document.text)
        edited.insert(NSAttributedString(string:"New "),at:0)
        document.replaceEditedText(with:edited)
        let output = try DOCXExporter.data(from:document.text,title:"Edited",bookmarks:document.metadata.bookmarks)
        let reopened = try DOCXImporter.importedDocument(from:output)
        XCTAssertEqual(reopened.text.string,edited.string)
        XCTAssertEqual(reopened.bookmarks.first?.location,10)
        XCTAssertEqual(reopened.text.attribute(.link,at:4,effectiveRange:nil) as? String,"#Chapter")
    }

    func testFormattedTOCTabsAndLiteralNumberedParagraphsRemainTextOnDOCXReopen() throws {
        let style = NSMutableParagraphStyle()
        style.tabStops = [NSTextTab(textAlignment:.right,location:400)]
        let source = NSAttributedString(string:"Chapter One\t2\nChapter Two\t15\n1. Literal paragraph\n2. Literal paragraph\n",attributes:[.paragraphStyle:style])
        let bytes = try DOCXExporter.data(from:source,title:"Formatted manuscript")
        let xml = try DOCXPackage.xml(try XCTUnwrap(DOCXPackage.entries(in:bytes).first { $0.path == "word/document.xml" }).data)
        XCTAssertEqual(try xml.nodes(forXPath:"//*[local-name()='tbl']").count,0)
        XCTAssertEqual(try xml.nodes(forXPath:"//*[local-name()='numPr']").count,0)
        XCTAssertEqual(try DOCXImporter.importedDocument(from:bytes).text.string,source.string)
    }

    func testRealManuscriptEditorRoundTrip() throws {
        guard let path = ProcessInfo.processInfo.environment["BOLD_ACCEPTANCE_DOCX"] else {
            throw XCTSkip("Set BOLD_ACCEPTANCE_DOCX to a manuscript working copy")
        }
        _ = NSApplication.shared
        let document = try BOLDWriterDocument(fileWrapper: FileWrapper(url: URL(fileURLWithPath: path)), contentType: .docx)
        XCTAssertGreaterThan(document.text.length, 500_000)
        let canvas = PaginatedEditor(text: document.text)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        scroll.documentView = canvas
        canvas.configure(printLayout: false, settings: document.metadata.page, zoom: 1, viewportWidth: 800)
        XCTAssertTrue(canvas.hitTest(NSPoint(x: 70, y: 60)) === canvas.firstView)
        let view = canvas.firstView
        view.isEditable = true
        view.allowsUndo = true
        canvas.sharedUndoManager.groupsByEvent = false
        let original = view.string
        let phrase = "BOLD_ACCEPTANCE_20260925 "
        canvas.sharedUndoManager.beginUndoGrouping()
        view.insertText(phrase, replacementRange: NSRange(location: 0, length: 0))
        canvas.sharedUndoManager.endUndoGrouping()
        XCTAssertTrue(view.string.hasPrefix(phrase))
        canvas.sharedUndoManager.undo()
        XCTAssertTrue(view.string == original, "Undo must restore complete text")
        canvas.sharedUndoManager.redo()
        XCTAssertTrue(view.string.hasPrefix(phrase))
        // Match the app save path: synchronize edited text so bookmark/section ranges
        // are rebased, then export metadata alongside text. Text-only export omits
        // the real manuscript's internal link targets and creates dangling anchors.
        document.replaceEditedText(with:canvas.flow.storage)
        let data = try DOCXExporter.data(from:document.text,title:"Acceptance",
            settings:document.metadata.page,sections:document.metadata.sections,
            comments:document.metadata.comments,bookmarks:document.metadata.bookmarks,
            namedStyles:document.metadata.namedStyles ?? [])
        if let folder = ProcessInfo.processInfo.environment["BOLD_REAL_ACCEPTANCE_DIR"] {
            try data.write(to:URL(fileURLWithPath:folder).appendingPathComponent("editor-roundtrip.docx"))
        }
        let reopened = try BOLDWriterDocument(fileWrapper: FileWrapper(regularFileWithContents: data), contentType: .docx)
        if let folder = ProcessInfo.processInfo.environment["BOLD_REAL_ACCEPTANCE_DIR"] {
            try Data((phrase+original).utf8).write(to:URL(fileURLWithPath:folder).appendingPathComponent("editor-before.txt"))
            try Data(reopened.text.string.utf8).write(to:URL(fileURLWithPath:folder).appendingPathComponent("editor-after.txt"))
        }
        XCTAssertTrue(reopened.text.string == phrase + original, "Round trip must preserve complete text")
    }
}


@MainActor
final class PasteWithoutFormattingTests: XCTestCase {
    func testPasteWithoutFormattingUsesDestinationTypingAttributes() throws {
        _ = NSApplication.shared

        let destinationFont =
            NSFont.systemFont(
                ofSize:
                    13
            )

        let destinationColor =
            NSColor.systemBlue

        let sourceFont =
            NSFont.boldSystemFont(
                ofSize:
                    31
            )

        let sourceColor =
            NSColor.systemRed

        let canvas =
            PaginatedEditor(
                text:
                    NSAttributedString(
                        string:
                            "AB"
                    )
            )

        let view =
            canvas.firstView

        view.isEditable =
            true

        view.setSelectedRange(
            NSRange(
                location:
                    1,
                length:
                    1
            )
        )

        view.typingAttributes = [
            .font:
                destinationFont,
            .foregroundColor:
                destinationColor,
        ]

        let richSource =
            NSAttributedString(
                string:
                    "Pasted",
                attributes: [
                    .font:
                        sourceFont,
                    .foregroundColor:
                        sourceColor,
                    .underlineStyle:
                        NSUnderlineStyle
                            .single
                            .rawValue,
                ]
            )

        let richData =
            try richSource.data(
                from:
                    NSRange(
                        location:
                            0,
                        length:
                            richSource.length
                    ),
                documentAttributes: [
                    .documentType:
                        NSAttributedString
                            .DocumentType
                            .rtf
                ]
            )

        let pasteboard =
            NSPasteboard.general

        pasteboard.clearContents()

        pasteboard.declareTypes(
            [
                .rtf,
                .string,
            ],
            owner:
                nil
        )

        XCTAssertTrue(
            pasteboard.setData(
                richData,
                forType:
                    .rtf
            )
        )

        XCTAssertTrue(
            pasteboard.setString(
                "Pasted",
                forType:
                    .string
            )
        )

        let selector =
            #selector(
                WritingTextView
                    .pasteWithoutFormatting(_:)
            )

        XCTAssertTrue(
            view.responds(
                to:
                    selector
            )
        )

        _ =
            view.perform(
                selector,
                with:
                    nil
            )

        XCTAssertEqual(
            view.string,
            "APasted"
        )

        let insertedRange =
            NSRange(
                location:
                    1,
                length:
                    6
            )

        view.attributedString()
            .enumerateAttributes(
                in:
                    insertedRange
            ) {
                attributes,
                _,
                _ in

                let font =
                    attributes[
                        .font
                    ] as? NSFont

                let color =
                    attributes[
                        .foregroundColor
                    ] as? NSColor

                XCTAssertEqual(
                    font?.pointSize,
                    destinationFont.pointSize
                )

                XCTAssertFalse(
                    NSFontManager.shared
                        .traits(
                            of:
                                font
                                ?? destinationFont
                        )
                        .contains(
                            .boldFontMask
                        )
                )

                XCTAssertTrue(
                    color?.isEqual(
                        destinationColor
                    )
                    == true
                )

                XCTAssertNil(
                    attributes[
                        .underlineStyle
                    ]
                )
            }
    }

    func testPasteWithoutFormattingReplacesSelectionAsPlainText() {
        _ = NSApplication.shared

        let canvas =
            PaginatedEditor(
                text:
                    NSAttributedString(
                        string:
                            "Before OLD After"
                    )
            )

        let view =
            canvas.firstView

        view.isEditable =
            true

        let oldRange =
            (view.string as NSString)
                .range(
                    of:
                        "OLD"
                )

        view.setSelectedRange(
            oldRange
        )

        view.typingAttributes = [
            .font:
                NSFont.systemFont(
                    ofSize:
                        15
                )
        ]

        let pasteboard =
            NSPasteboard.general

        pasteboard.clearContents()

        XCTAssertTrue(
            pasteboard.setString(
                "NEW",
                forType:
                    .string
            )
        )

        _ =
            view.perform(
                #selector(
                    WritingTextView
                        .pasteWithoutFormatting(_:)
                ),
                with:
                    nil
            )

        XCTAssertEqual(
            view.string,
            "Before NEW After"
        )
    }
}
