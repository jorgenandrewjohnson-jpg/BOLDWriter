import AppKit
import PDFKit
import XCTest
@testable import BOLDWriter

final class BOLDScriptRuntimeTests: XCTestCase {
    @MainActor
    private final class TestTextView: NSTextView {
        let registeredUndoManager = UndoManager()
        override var undoManager: UndoManager? { registeredUndoManager }
    }
    func testParsesSupportedOperationsAndFencedJSON() throws {
        let script = try BOLDScript.parse("""
        ```json
        {"format":"bold-script","version":1,"title":"Example","target":{"scope":"document"},"operations":[
          {"type":"replaceText","find":"old","replaceWith":"new"},
          {"type":"formatText","find":"new","bold":true},
          {"type":"setParagraphStyle","paragraphPrefix":"Chapter ","style":"Heading 1"},
          {"type":"normalizeHeadings","rules":[{"paragraphPrefix":"Part ","style":"Heading 2"}]}
        ]}
        ```
        """)
        XCTAssertEqual(script.title, "Example")
        XCTAssertEqual(script.target, "document")
        XCTAssertEqual(script.operations.count, 4)
    }

    func testRejectsUnknownKeysOperationsAndUnsafeTargets() {
        let cases = [
            #"{"format":"bold-script","version":1,"target":{"scope":"document"},"operations":[{"type":"runShell","command":"rm"}]}"#,
            #"{"format":"bold-script","version":1,"target":{"scope":"document"},"surprise":true,"operations":[{"type":"replaceText","find":"a","replaceWith":"b"}]}"#,
            #"{"format":"bold-script","version":1,"target":{"scope":"selectedFiles"},"operations":[{"type":"replaceText","find":"a","replaceWith":"b"}]}"#,
            #"{"format":"bold-script","version":1,"target":{"scope":"document"},"operations":[{"type":"updateFloatingImage","imageID":"00000000-0000-0000-0000-000000000001","anchorOffsetX":2}]}"#,
            #"{"format":"bold-script","version":1,"target":{"scope":"document"},"operations":[{"type":"updateFloatingImage","imageID":"00000000-0000-0000-0000-000000000001","wrapDistances":{"top":1,"right":2,"bottom":3}}]}"#
        ]
        for source in cases { XCTAssertThrowsError(try BOLDScript.parse(source)) }
    }

    func testFloatingImageCommandsUseTheSharedDocumentRecords() throws {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = NSSize(width: 8, height: 8)
        let bytes = bitmap.representation(using: .png, properties: [:])!
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
        try bytes.write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        let source = #"{"format":"bold-script","version":1,"target":{"scope":"document"},"operations":[{"type":"insertFloatingImage","sourcePath":"\#(sourceURL.path)","page":2,"x":36,"y":48,"width":144,"height":144,"wrapping":"square","wrapDistances":{"top":1,"right":2,"bottom":3,"left":4},"layer":"behindText","anchor":"paragraph","anchorLocation":1,"anchorOffsetX":24,"anchorOffsetY":12,"lockPosition":true}]}"#
        let script = try BOLDScript.parse(source)
        let plan = try BOLDScriptEngine.plan(script, on: NSAttributedString(string: "Text\n"))
        let image = try XCTUnwrap(plan.floatingImages.first)
        XCTAssertEqual(image.pageIndex, 1)
        XCTAssertEqual(image.wrapping, .square)
        XCTAssertEqual(image.effectiveWrapDistances, .init(top: 1, right: 2, bottom: 3, left: 4))
        XCTAssertEqual(image.layer, .behindText)
        XCTAssertEqual(image.anchorOffsetX, 24)
        XCTAssertEqual(image.anchorOffsetY, 12)
        XCTAssertTrue(image.positionLocked)
        XCTAssertEqual(plan.output.string, "Text\n")
        var pageOneImage = image
        pageOneImage.pageIndex = 0
        let pdf = try PDFExporter.data(from: plan.output, settings: PageSettings(), floatingImages: [pageOneImage])
        XCTAssertEqual(PDFDocument(data: pdf)?.pageCount, 1)
        XCTAssertTrue(String(data: pdf, encoding: .isoLatin1)?.contains("/Subtype /Image") == true,
                      "PDF output should contain the floating image XObject.")
        var metadata = DocumentMetadata()
        metadata.floatingImages = plan.floatingImages
        let package = try BOLDWriterDocument.packageWrapper(text: plan.output, metadata: metadata)
        let reopened = try BOLDWriterDocument(fileWrapper: package, contentType: .boldWriterDocument)
        XCTAssertEqual(reopened.metadata.floatingImages?.first?.id, plan.floatingImages.first?.id)
        XCTAssertEqual(reopened.metadata.floatingImages?.first?.imageData, plan.floatingImages.first?.imageData)
        XCTAssertEqual(reopened.metadata.floatingImages?.first?.x, plan.floatingImages.first?.x)
        XCTAssertNotNil(reopened.metadata.floatingImages?.first?.assetDigest)
        try FloatingImage.validate(reopened.metadata.floatingImages ?? [], textLength: 5)
        var anchored = reopened.metadata
        var paragraphImage = try XCTUnwrap(anchored.floatingImages?.first)
        paragraphImage.anchor = .paragraph
        paragraphImage.anchorLocation = 2
        anchored.floatingImages = [paragraphImage]
        anchored.rebaseTextAnchors(from: "Text\n", to: "More Text\n")
        XCTAssertEqual(anchored.floatingImages?.first?.anchorLocation, 7)
        anchored.rebaseTextAnchors(from: "More Text\n", to: "\n")
        XCTAssertEqual(anchored.floatingImages?.first?.anchor, .page, "A deleted text target falls back to the preserved physical page position.")
    }

    func testFloatingImageScriptAlignmentDuplicationAnchorsLockAndInspection() throws {
        let firstID = UUID()
        let secondID = UUID()
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        let bytes = bitmap.representation(using: .png, properties: [:])!
        let existing = [
            FloatingImage(id: firstID, assetName: "a.png", imageData: bytes, x: 10, y: 20, width: 40, height: 30),
            FloatingImage(id: secondID, assetName: "b.png", imageData: bytes, x: 140, y: 70, width: 60, height: 50)
        ]
        let script = try BOLDScript.parse("""
        {"format":"bold-script","version":1,"target":{"scope":"document"},"operations":[{"type":"alignFloatingImages","imageIDs":["\(firstID.uuidString)","\(secondID.uuidString)"],"alignment":"left"},{"type":"duplicateFloatingImage","imageID":"\(firstID.uuidString)"},{"type":"updateFloatingImage","imageID":"\(secondID.uuidString)","anchor":"character","anchorLocation":7,"anchorOffsetX":15,"anchorOffsetY":8,"wrapDistances":{"top":1,"right":2,"bottom":3,"left":4},"wrapSide":"rightOnly","zOrder":4,"lockPosition":true},{"type":"inspectFloatingImages"}]}
        """)
        let plan = try BOLDScriptEngine.plan(script, on: NSAttributedString(string: "Long text"), floatingImages: existing)
        XCTAssertEqual(plan.floatingImages.count, 3)
        XCTAssertEqual(plan.floatingImages[0].x, 10)
        XCTAssertEqual(plan.floatingImages[1].x, 10)
        XCTAssertEqual(plan.floatingImages[1].anchor, .character)
        XCTAssertEqual(plan.floatingImages[1].anchorLocation, 7)
        XCTAssertEqual(plan.floatingImages[1].anchorOffsetX, 15)
        XCTAssertEqual(plan.floatingImages[1].anchorOffsetY, 8)
        XCTAssertEqual(plan.floatingImages[1].wrapDistance, 1)
        XCTAssertEqual(plan.floatingImages[1].effectiveWrapDistances,
                       .init(top: 1, right: 2, bottom: 3, left: 4))
        XCTAssertEqual(plan.floatingImages[1].effectiveWrapSide, .rightOnly)
        XCTAssertTrue(plan.floatingImages[1].positionLocked)
        XCTAssertFalse(plan.floatingImages[2].positionLocked)
        XCTAssertEqual(plan.imageInspection.count, 3)
        XCTAssertTrue(plan.output.string == "Long text")
    }

    @MainActor
    func testPlanReplacesTextFormatsMatchesAndNormalizesHeadingsWithoutLosingOtherAttributes() throws {
        let source = NSMutableAttributedString(string: "Chapter One\nThis  is old text.\n")
        let linkRange = (source.string as NSString).range(of: "old")
        source.addAttribute(.link, value: URL(string: "https://example.invalid")!, range: linkRange)
        let script = try BOLDScript.parse(#"{"format":"bold-script","version":1,"title":"Format chapter","target":{"scope":"document"},"operations":[{"type":"replaceText","find":"old","replaceWith":"new"},{"type":"formatText","find":"Chapter One","fontSize":18,"bold":true},{"type":"normalizeHeadings","rules":[{"paragraphPrefix":"Chapter ","style":"Heading 1"}]}]}"#)
        let plan = try BOLDScriptEngine.plan(script, on: source)
        XCTAssertEqual(plan.output.string, "Chapter One\nThis  is new text.\n")
        XCTAssertEqual(plan.totalChanges, 3)
        let newRange = (plan.output.string as NSString).range(of: "new")
        XCTAssertEqual(plan.output.attribute(.link, at: newRange.location, effectiveRange: nil) as? URL, URL(string: "https://example.invalid"))
        let heading = plan.output.attribute(.boldWriterStyle, at: 0, effectiveRange: nil) as? String
        XCTAssertEqual(heading, WriterStyle.heading1.rawValue)
        let font = plan.output.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font?.pointSize, WriterStyle.heading1.font.pointSize, "Paragraph style normalization follows the documented operation order.")
    }

    func testRejectsUnsupportedReplacementWithinNoteReference() throws {
        let source = NSMutableAttributedString(string: "A¹B")
        source.addAttribute(.footnote, value: "note-id", range: NSRange(location: 1, length: 1))
        let script = try BOLDScript.parse(#"{"format":"bold-script","version":1,"target":{"scope":"document"},"operations":[{"type":"replaceText","find":"¹","replaceWith":"2"}]}"#)
        XCTAssertThrowsError(try BOLDScriptEngine.plan(script, on: source))
    }

    func testNoMatchesAreReportedWithoutInventingChanges() throws {
        let script = try BOLDScript.parse(#"{"format":"bold-script","version":1,"target":{"scope":"document"},"operations":[{"type":"replaceText","find":"absent","replaceWith":"present"}]}"#)
        let plan = try BOLDScriptEngine.plan(script, on: NSAttributedString(string: "unchanged"))
        XCTAssertEqual(plan.totalChanges, 0)
        XCTAssertEqual(plan.output.string, "unchanged")
    }

    func testRepeatedHeadingNormalizationBecomesIdempotent() throws {
        let script = try BOLDScript.parse(#"{"format":"bold-script","version":1,"target":{"scope":"document"},"operations":[{"type":"normalizeHeadings","rules":[{"paragraphPrefix":"Chapter ","style":"Heading 1"}]}]}"#)
        let first = try BOLDScriptEngine.plan(script, on: NSAttributedString(string: "Chapter One\nBody\n"))
        let repeated = try BOLDScriptEngine.plan(script, on: first.output)
        XCTAssertEqual(first.totalChanges, 1)
        XCTAssertEqual(repeated.totalChanges, 0)
        XCTAssertTrue(repeated.output.isEqual(to: first.output))
    }

    @MainActor
    func testApprovedPlanIsOneUndoableEditorMutation() throws {
        let view = TestTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
        view.isRichText = true
        view.allowsUndo = true
        view.registeredUndoManager.groupsByEvent = false
        view.textStorage?.setAttributedString(NSAttributedString(string: "Chapter One\nold text\n"))
        let editor = EditorController()
        editor.attach(view)
        let script = try BOLDScript.parse(#"{"format":"bold-script","version":1,"title":"One change","target":{"scope":"document"},"operations":[{"type":"replaceText","find":"old","replaceWith":"new"},{"type":"setParagraphStyle","paragraphPrefix":"Chapter ","style":"Heading 1"}]}"#)
        let plan = try BOLDScriptEngine.plan(script, on: view.attributedString())

        XCTAssertTrue(editor.applyBOLDScriptPlan(plan, title: script.title))
        XCTAssertEqual(view.string, "Chapter One\nnew text\n")
        XCTAssertEqual(view.undoManager?.canUndo, true)
        view.undoManager?.undo()
        XCTAssertEqual(view.string, "Chapter One\nold text\n")
        XCTAssertNil(view.textStorage?.attribute(.boldWriterStyle, at: 0, effectiveRange: nil))
    }

    @MainActor
    func testDisposable207538WordManuscriptFormatsAndReopensWithoutTextLoss() throws {
        var paragraphs: [String] = []
        paragraphs.reserveCapacity(782)
        for chapter in 1...391 {
            paragraphs.append("Chapter \(chapter)")
            let words = chapter <= 308 ? 529 : 528
            paragraphs.append(Array(repeating: "The word endures", count: words / 3).joined(separator: " ") + (words % 3 == 1 ? " wisdom" : ""))
        }
        let original = paragraphs.joined(separator: "\n") + "\n"
        XCTAssertEqual(original.split(whereSeparator: \.isWhitespace).count, 207_538)
        let source = NSAttributedString(string: original, attributes: [.font: NSFont.systemFont(ofSize: 11)])
        let script = try BOLDScript.parse(#"{"format":"bold-script","version":1,"title":"Format 391 chapter manuscript","target":{"scope":"document"},"operations":[{"type":"normalizeHeadings","rules":[{"paragraphPrefix":"Chapter ","style":"Heading 1"}]}]}"#)
        let plan = try BOLDScriptEngine.plan(script, on: source)
        XCTAssertEqual(plan.totalChanges, 391)
        XCTAssertEqual(plan.output.string, original, "Formatting-only automation must preserve every character.")
        let expectedStyles = (1...391).map { chapter in
            let range = (plan.output.string as NSString).range(of: "Chapter \(chapter)\n")
            return plan.output.attribute(.boldWriterStyle, at: range.location, effectiveRange: nil) as? String
        }
        XCTAssertTrue(expectedStyles.allSatisfy { $0 == WriterStyle.heading1.rawValue })

        var metadata = DocumentMetadata()
        let cover = CoverProject(type: .ebookFront)
        metadata.coverProjects = [cover]
        let package = try BOLDWriterDocument.packageWrapper(text: plan.output, metadata: metadata)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BOLDScript-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Disposable-391-Chapter.boldwriter", isDirectory: true)
        try package.write(to: url, options: .atomic, originalContentsURL: nil)
        let reopened = try BOLDWriterDocument(fileWrapper: FileWrapper(url: url), contentType: .boldWriterDocument)
        XCTAssertEqual(reopened.text.string, original)
        XCTAssertEqual(reopened.metadata.coverProjects, [cover])
        XCTAssertEqual(reopened.metadata.styleRuns.filter { $0.style == .heading1 }.count, 391)
    }
}
