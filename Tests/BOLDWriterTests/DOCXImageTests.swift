import AppKit
import PDFKit
import UniformTypeIdentifiers
import XCTest
@testable import BOLDWriter

@MainActor
final class DOCXImageTests: XCTestCase {
    private let w = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    private let r = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"

    private func artwork(width: Int, height: Int, type: NSBitmapImageRep.FileType = .png) throws -> Data {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                                  bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false,
                                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        for y in 0..<height {
            for x in 0..<width { bitmap.setColor(x < width / 2 ? NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1) : NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1), atX: x, y: y) }
        }
        return try XCTUnwrap(bitmap.representation(using: type, properties: [:]))
    }

    private func transparentDiamond() throws -> Data {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 48, pixelsHigh: 48,
                                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        for y in 0..<48 {
            for x in 0..<48 {
                let inside = abs(x - 24) + abs(y - 24) <= 21
                bitmap.setColor(inside ? NSColor(deviceRed: 0.1, green: 0.4, blue: 0.8, alpha: 1) : NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 0), atX: x, y: y)
            }
        }
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }

    private func attachments(_ text: NSAttributedString) -> [(NSRange, NSTextAttachment)] {
        var result: [(NSRange, NSTextAttachment)] = []
        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            if let attachment = value as? NSTextAttachment { result.append((range, attachment)) }
        }
        return result
    }

    private func sourceAttachment(data: Data, name: String, size: NSSize) throws -> NSTextAttachment {
        let wrapper = FileWrapper(regularFileWithContents: data)
        wrapper.preferredFilename = name
        let attachment = NSTextAttachment(fileWrapper: wrapper)
        let image = try XCTUnwrap(NSImage(data: data))
        image.size = size
        attachment.attachmentCell = NSTextAttachmentCell(imageCell: image)
        attachment.bounds = NSRect(origin: .zero, size: size)
        return attachment
    }

    private func original() throws -> BOLDWriterDocument {
        let text = NSMutableAttributedString(string: "An Illustrated Walk\nBefore the first image. ", attributes: [.font: NSFont.systemFont(ofSize: 15)])
        text.addAttributes([.boldWriterStyle: WriterStyle.heading1.rawValue, .font: WriterStyle.heading1.font], range: NSRange(location: 0, length: 19))
        text.append(NSAttributedString(attachment: try sourceAttachment(data: artwork(width: 40, height: 20), name: "wide.png", size: NSSize(width: 160, height: 80))))
        text.append(NSAttributedString(string: " Text between the images.\n", attributes: [.font: NSFont(name: "Helvetica-Bold", size: 15)!]))
        text.append(NSAttributedString(attachment: try sourceAttachment(data: artwork(width: 20, height: 40, type: .jpeg), name: "tall.jpg", size: NSSize(width: 60, height: 120))))
        text.append(NSAttributedString(string: "\nAfter both images.", attributes: [.font: NSFont.systemFont(ofSize: 15), .underlineStyle: NSUnderlineStyle.single.rawValue]))
        text.addAttribute(.link, value: URL(string: "https://example.com/walk")!, range: (text.string as NSString).range(of: "images."))
        let document = BOLDWriterDocument()
        document.replaceText(with: text)
        return document
    }

    private func reopen(_ data: Data) throws -> BOLDWriterDocument {
        try BOLDWriterDocument(fileWrapper: FileWrapper(regularFileWithContents: data), contentType: .docx)
    }

    func testEditorInsertedImageSurvivesNativeAndDOCXRoundTrips() throws {
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 500))
        view.isRichText = true
        view.textStorage?.setAttributedString(NSAttributedString(string: "Illustration"))
        view.setSelectedRange(NSRange(location: 12, length: 0))
        let editor = EditorController()
        editor.attach(view)
        try editor.insertImage(data: artwork(width: 40, height: 20), name: "figure.png", maximumWidth: 80)

        let document = BOLDWriterDocument()
        document.replaceText(with: view.attributedString())
        let native = try BOLDWriterDocument.packageWrapper(text: document.text, metadata: document.metadata)
        let reopenedNative = try BOLDWriterDocument(fileWrapper: native, contentType: .boldWriterDocument)
        XCTAssertEqual(attachments(reopenedNative.text).count, 1)

        let docx = try ExportService.data(for: .docx, document: reopenedNative)
        let reopenedDOCX = try reopen(docx)
        XCTAssertEqual(attachments(reopenedDOCX.text).count, 1)
        let width = try XCTUnwrap(attachments(reopenedDOCX.text)[0].1.attachmentCell?.cellSize().width)
        XCTAssertEqual(width, 40, accuracy: 0.5)
    }

    func testOriginalTwoImageDocumentExportAndReopenThroughBOLDWriter() throws {
        let document = try original()
        let data = try ExportService.data(for: .docx, document: document)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".docx")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let reopened = try reopen(Data(contentsOf: url))
        XCTAssertNil(reopened.lastErrorMessage, "Faithful inline DOCX pictures should not raise an anchored-layout warning.")
        XCTAssertEqual(reopened.text.string.trimmingCharacters(in: .newlines), document.text.string)
        let before = attachments(document.text), after = attachments(reopened.text)
        XCTAssertEqual(after.count, 2)
        for (original, imported) in zip(before, after) {
            XCTAssertEqual(original.0.location, imported.0.location)
            let originalBitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(original.1.fileWrapper?.regularFileContents)))
            let importedBitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(imported.1.fileWrapper?.regularFileContents)))
            XCTAssertEqual(originalBitmap.pixelsWide, importedBitmap.pixelsWide)
            XCTAssertEqual(originalBitmap.pixelsHigh, importedBitmap.pixelsHigh)
            for x in [0, originalBitmap.pixelsWide - 1] {
                let beforeColor = try XCTUnwrap(originalBitmap.colorAt(x: x, y: 0)?.usingColorSpace(.deviceRGB))
                let afterColor = try XCTUnwrap(importedBitmap.colorAt(x: x, y: 0)?.usingColorSpace(.deviceRGB))
                XCTAssertEqual(beforeColor.redComponent, afterColor.redComponent, accuracy: 0.01)
                XCTAssertEqual(beforeColor.blueComponent, afterColor.blueComponent, accuracy: 0.01)
            }
            XCTAssertEqual(original.1.attachmentCell?.cellSize(), imported.1.attachmentCell?.cellSize())
        }
        let between = (reopened.text.string as NSString).range(of: "Text between")
        let font = try XCTUnwrap(reopened.text.attribute(.font, at: between.location, effectiveRange: nil) as? NSFont)
        XCTAssertEqual(font.pointSize, 15)
        // Preserve the existing AppKit text-import behavior, including formatting,
        // independently of the new image recovery pass.
        let native = try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.officeOpenXML], documentAttributes: nil)
        let nativeRange = (native.string as NSString).range(of: "Text between")
        XCTAssertEqual(font, native.attribute(.font, at: nativeRange.location, effectiveRange: nil) as? NSFont)
        let afterText = (reopened.text.string as NSString).range(of: "After both")
        XCTAssertEqual(reopened.text.attribute(.underlineStyle, at: afterText.location, effectiveRange: nil) as? Int, 1)
        let heading = try XCTUnwrap(reopened.text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertEqual(heading.pointSize, WriterStyle.heading1.font.pointSize)
        // The recovered attachments must also survive the ordinary native save path.
        let package = try BOLDWriterDocument.packageWrapper(text: reopened.text, metadata: reopened.metadata)
        let saved = try BOLDWriterDocument(fileWrapper: package, contentType: .boldWriterDocument)
        XCTAssertEqual(attachments(saved.text).count, 2)
        let secondExport = try ExportService.data(for: .docx, document: saved)
        let twice = try reopen(secondExport)
        for (expected, actual) in zip(after, attachments(twice.text)) {
            let expectedSize = try XCTUnwrap(expected.1.attachmentCell?.cellSize())
            let actualSize = try XCTUnwrap(actual.1.attachmentCell?.cellSize())
            XCTAssertEqual(expectedSize.width, actualSize.width, accuracy: 0.2)
            XCTAssertEqual(expectedSize.height, actualSize.height, accuracy: 0.2)
        }
    }

    func testExportPackageHasMatchingMediaRelationshipsContentTypesAndDimensions() throws {
        let document = try original()
        let parts = Dictionary(uniqueKeysWithValues: try DOCXPackage.entries(in: ExportService.data(for: .docx, document: document)).map { ($0.path, $0.data) })
        let body = try DOCXPackage.xml(XCTUnwrap(parts["word/document.xml"]))
        let rels = try DOCXPackage.xml(XCTUnwrap(parts["word/_rels/document.xml.rels"]))
        let types = try DOCXPackage.xml(XCTUnwrap(parts["[Content_Types].xml"]))
        let images = try rels.nodes(forXPath: "//*[local-name()='Relationship' and contains(@Type, '/image')]")
        XCTAssertEqual(images.count, 2)
        XCTAssertEqual(parts["word/media/image1.png"], attachments(document.text)[0].1.fileWrapper?.regularFileContents)
        XCTAssertEqual(parts["word/media/image2.jpg"], attachments(document.text)[1].1.fileWrapper?.regularFileContents)
        let allIDs = try rels.nodes(forXPath: "//@Id").compactMap(\.stringValue)
        XCTAssertEqual(Set(allIDs).count, allIDs.count)
        let references = try body.nodes(forXPath: "//*[local-name()='blip']/@*[local-name()='embed']").compactMap(\.stringValue)
        for case let image as XMLElement in images {
            XCTAssertTrue(references.contains(try XCTUnwrap(image.attribute(forName: "Id")?.stringValue)))
            let target = try XCTUnwrap(image.attribute(forName: "Target")?.stringValue)
            let bytes = try XCTUnwrap(parts["word/" + target])
            XCTAssertTrue(NSImage(data: bytes)?.isValid == true)
            let ext = (target as NSString).pathExtension
            XCTAssertEqual(try types.nodes(forXPath: "//*[local-name()='Default' and @Extension='\(ext)']").count, 1)
        }
        XCTAssertEqual(try body.nodes(forXPath: "//*[local-name()='extent']/@cx").compactMap(\.stringValue), ["2032000", "762000"])
        XCTAssertEqual(try body.nodes(forXPath: "//*[local-name()='extent']/@cy").compactMap(\.stringValue), ["1016000", "1524000"])
        XCTAssertTrue(body.rootElement()?.stringValue?.contains("Before the first image.") == true)
        XCTAssertEqual(try body.nodes(forXPath: "//*[local-name()='pStyle' and @*[local-name()='val']='Heading1']").count, 1)
        // Independently exercise Apple's reader on the actual exported package.
        let native = try NSAttributedString(data: ExportService.data(for: .docx, document: document), options: [.documentType: NSAttributedString.DocumentType.officeOpenXML], documentAttributes: nil)
        XCTAssertTrue(native.string.contains("After both images."))
    }

    private func drawing(id: String = "photo", extent: String = "<d:extent cx='1524000' cy='762000'/>", anchor: Bool = false) -> String {
        let kind = anchor ? "anchor" : "inline"
        return "<w:drawing><d:\(kind) xmlns:d='http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing'>\(extent)<d:docPr id='1' name='Photo'/><a:graphic xmlns:a='http://schemas.openxmlformats.org/drawingml/2006/main'><a:graphicData uri='http://schemas.openxmlformats.org/drawingml/2006/picture'><p:pic xmlns:p='http://schemas.openxmlformats.org/drawingml/2006/picture'><p:blipFill><a:blip r:embed='\(id)'/></p:blipFill></p:pic></a:graphicData></a:graphic></d:\(kind)></w:drawing>"
    }

    /// Authored independently of DOCXExporter, with nonstandard namespace prefixes,
    /// percent-encoded relationship paths, and a shared image part used twice.
    private func fixture(markup: String, media: Data?, target: String = "media/test%20image.png", external: Bool = false) -> [ZipEntry] {
        let document = "<w:document xmlns:w='\(w)' xmlns:r='\(r)'><w:body><w:p><w:r><w:t>Before </w:t>\(markup)<w:t> between </w:t>\(drawing())<w:t> after</w:t></w:r></w:p></w:body></w:document>"
        var entries = [
            ZipEntry(path: "[Content_Types].xml", data: Data("<Types xmlns='http://schemas.openxmlformats.org/package/2006/content-types'><Default Extension='rels' ContentType='application/vnd.openxmlformats-package.relationships+xml'/><Default Extension='xml' ContentType='application/xml'/><Default Extension='png' ContentType='image/png'/><Override PartName='/word/document.xml' ContentType='application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml'/></Types>".utf8)),
            ZipEntry(path: "_rels/.rels", data: Data("<Relationships xmlns='http://schemas.openxmlformats.org/package/2006/relationships'><Relationship Id='main' Type='\(r)/officeDocument' Target='word/document.xml'/></Relationships>".utf8)),
            ZipEntry(path: "word/document.xml", data: Data(document.utf8)),
            ZipEntry(path: "word/_rels/document.xml.rels", data: Data("<Relationships xmlns='http://schemas.openxmlformats.org/package/2006/relationships'><Relationship Id='photo' Type='\(r)/image' Target='\(target)'\(external ? " TargetMode='External'" : "")/></Relationships>".utf8))
        ]
        if let media { entries.append(ZipEntry(path: "word/media/test image.png", data: media)) }
        return entries
    }

    private func vectorDrawingFixture(relationshipBacked: Bool = false,
                                      includeDependency: Bool = false) throws -> Data {
        let base = try DOCXExporter.data(from: NSAttributedString(string: "Before After"), title: "Drawing fixture")
        var entries = try DOCXPackage.entries(in: base)
        let index = try XCTUnwrap(entries.firstIndex { $0.path == "word/document.xml" })
        let graphic = relationshipBacked
            ? "<c:chart xmlns:c='http://schemas.openxmlformats.org/drawingml/2006/chart' xmlns:z='\(r)' z:id='rChart1'/>"
            : "<wps:wsp xmlns:wps='http://schemas.microsoft.com/office/word/2010/wordprocessingShape'><wps:spPr><a:prstGeom prst='star5'><a:avLst/></a:prstGeom></wps:spPr></wps:wsp>"
        let shape = "<w:drawing><wp:inline xmlns:wp='http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing'><wp:extent cx='1270000' cy='635000'/><wp:docPr id='7' name='Vector Seal'/><a:graphic xmlns:a='http://schemas.openxmlformats.org/drawingml/2006/main'><a:graphicData uri='http://schemas.microsoft.com/office/word/2010/wordprocessingShape'>\(graphic)</a:graphicData></a:graphic></wp:inline></w:drawing>"
        let original = String(decoding: entries[index].data, as: UTF8.self)
        XCTAssertTrue(original.contains("Before After"))
        let modified = original.replacingOccurrences(of: "Before After", with: "Before </w:t>\(shape)<w:t> After")
        entries[index].data = Data(modified.utf8)
        if relationshipBacked && includeDependency {
            let relIndex = try XCTUnwrap(entries.firstIndex { $0.path == "word/_rels/document.xml.rels" })
            let relation = "<Relationship Id='rChart1' Type='\(r)/chart' Target='charts/chart1.xml'/>"
            let rels = String(decoding: entries[relIndex].data, as: UTF8.self)
            entries[relIndex].data = Data(rels.replacingOccurrences(of: "</Relationships>", with: relation + "</Relationships>").utf8)
            let typeIndex = try XCTUnwrap(entries.firstIndex { $0.path == "[Content_Types].xml" })
            let types = String(decoding: entries[typeIndex].data, as: UTF8.self)
            entries[typeIndex].data = Data(types.replacingOccurrences(of: "</Types>", with:
                "<Override PartName='/word/charts/chart1.xml' ContentType='application/vnd.openxmlformats-officedocument.drawingml.chart+xml'/><Override PartName='/word/embeddings/data.xlsx' ContentType='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'/></Types>").utf8)
            entries.append(ZipEntry(path: "word/charts/chart1.xml", data: Data("<c:chartSpace xmlns:c='http://schemas.openxmlformats.org/drawingml/2006/chart' xmlns:r='\(r)'><c:externalData r:id='rWorkbook'/></c:chartSpace>".utf8)))
            entries.append(ZipEntry(path: "word/charts/_rels/chart1.xml.rels", data: Data("<Relationships xmlns='http://schemas.openxmlformats.org/package/2006/relationships'><Relationship Id='rWorkbook' Type='\(r)/package' Target='../embeddings/data.xlsx'/></Relationships>".utf8)))
            entries.append(ZipEntry(path: "word/embeddings/data.xlsx", data: Data([0x50, 0x4b, 0x03, 0x04, 0x42, 0x57])))
        }
        return ZipArchiveWriter.archive(entries)
    }

    func testUnsupportedVectorDrawingSurvivesNativeSaveAndDOCXRoundTrip() throws {
        let original = try vectorDrawingFixture()
        let imported = try reopen(original)
        let marker = (imported.text.string as NSString).range(of: WordOpaqueDrawing.markerText)
        XCTAssertNotEqual(marker.location, NSNotFound)
        let first = try XCTUnwrap(imported.text.attribute(.boldWriterWordOpaqueDrawing,
                                                          at: marker.location, effectiveRange: nil) as? WordOpaqueDrawing)
        XCTAssertTrue(first.xml.contains("prst='star5'") || first.xml.contains("prst=\"star5\""))

        let edited = NSMutableAttributedString(attributedString: imported.text)
        edited.append(NSAttributedString(string: " Chapter ending."))
        imported.replaceText(with: edited)
        let native = try BOLDWriterDocument.packageWrapper(text: imported.text, metadata: imported.metadata)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Opaque-Drawing-\(UUID().uuidString).boldwriter", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: url) }
        try native.write(to: url, options: .atomic, originalContentsURL: nil)
        let reopened = try BOLDWriterDocument(fileWrapper: FileWrapper(url: url), contentType: .boldWriterDocument)
        let reopenedRange = (reopened.text.string as NSString).range(of: WordOpaqueDrawing.markerText)
        XCTAssertNotEqual(reopenedRange.location, NSNotFound)
        let restored = try XCTUnwrap(reopened.text.attribute(.boldWriterWordOpaqueDrawing,
                                                             at: reopenedRange.location, effectiveRange: nil) as? WordOpaqueDrawing)
        XCTAssertEqual(restored.xml, first.xml)
        XCTAssertTrue(reopened.text.string.contains("Chapter ending."))

        let exported = try ExportService.data(for: .docx, document: reopened)
        let parts = Dictionary(uniqueKeysWithValues: try DOCXPackage.entries(in: exported).map { ($0.path, $0.data) })
        let body = try DOCXPackage.xml(XCTUnwrap(parts["word/document.xml"]))
        XCTAssertEqual(try body.nodes(forXPath: "//*[local-name()='docPr']/@name").compactMap(\.stringValue), ["Vector Seal"])
        XCTAssertEqual(try body.nodes(forXPath: "//*[local-name()='extent']/@cx").compactMap(\.stringValue), ["1270000"])
        XCTAssertEqual(try body.nodes(forXPath: "//*[local-name()='prstGeom']/@prst").compactMap(\.stringValue), ["star5"])
        XCTAssertTrue(body.rootElement()?.stringValue?.contains("Chapter ending.") == true)
        let reimported = try reopen(exported)
        XCTAssertNotEqual((reimported.text.string as NSString).range(of: WordOpaqueDrawing.markerText).location, NSNotFound)
        XCTAssertTrue(reimported.text.string.contains("Chapter ending."))
    }

    func testRelationshipBackedUnsupportedDrawingWithMissingPartFailsClosed() throws {
        let original = try vectorDrawingFixture(relationshipBacked: true)
        XCTAssertThrowsError(try reopen(original)) { error in
            XCTAssertTrue(error.localizedDescription.contains("missing, unsafe, or oversized"))
        }
    }

    func testRelationshipBackedChartAndNestedWorkbookSurviveNativeAndDOCXRoundTrip() throws {
        let original = try vectorDrawingFixture(relationshipBacked: true, includeDependency: true)
        let imported = try reopen(original)
        let marker = (imported.text.string as NSString).range(of: WordOpaqueDrawing.markerText)
        XCTAssertNotEqual(marker.location, NSNotFound)
        let first = try XCTUnwrap(imported.text.attribute(.boldWriterWordOpaqueDrawing,
            at: marker.location, effectiveRange: nil) as? WordOpaqueDrawing)
        XCTAssertEqual(first.parts.count, 2)
        XCTAssertEqual(first.relationships.count, 1)
        let edited = NSMutableAttributedString(attributedString: imported.text)
        edited.append(NSAttributedString(string: " Revised manuscript."))
        imported.replaceText(with: edited)
        let native = try BOLDWriterDocument.packageWrapper(text: imported.text, metadata: imported.metadata)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Opaque-Chart-\(UUID().uuidString).boldwriter", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: url) }
        try native.write(to: url, options: .atomic, originalContentsURL: nil)
        let reopened = try BOLDWriterDocument(fileWrapper: FileWrapper(url: url), contentType: .boldWriterDocument)
        let restored = try XCTUnwrap(reopened.text.attribute(.boldWriterWordOpaqueDrawing,
            at: marker.location, effectiveRange: nil) as? WordOpaqueDrawing)
        XCTAssertEqual(restored.parts, first.parts)
        XCTAssertEqual(restored.relationships, first.relationships)
        XCTAssertTrue(reopened.text.string.contains("Revised manuscript."))
        let exported = try ExportService.data(for: .docx, document: reopened)
        let entries = try DOCXPackage.entries(in: exported)
        let paths = Set(entries.map(\.path))
        XCTAssertEqual(paths.count, entries.count)
        let map = Dictionary(uniqueKeysWithValues: entries.map { ($0.path, $0.data) })
        let prefix = "word/boldwriter-opaque/" + first.id.uuidString.replacingOccurrences(of: "-", with: "") + "/"
        XCTAssertEqual(map[prefix + "word/embeddings/data.xlsx"], first.parts.first(where: { $0.path.hasSuffix("data.xlsx") })?.data)
        XCTAssertNotNil(map[prefix + "word/charts/chart1.xml"])
        XCTAssertNotNil(map[prefix + "word/charts/_rels/chart1.xml.rels"])
        let contentTypes = try DOCXPackage.xml(XCTUnwrap(map["[Content_Types].xml"]))
        XCTAssertTrue(try contentTypes.nodes(forXPath: "//*[local-name()='Override' and contains(@PartName, 'chart1.xml')]").count == 1)
        let reimported = try reopen(exported)
        let reMarker = (reimported.text.string as NSString).range(of: WordOpaqueDrawing.markerText)
        let second = try XCTUnwrap(reimported.text.attribute(.boldWriterWordOpaqueDrawing,
            at: reMarker.location, effectiveRange: nil) as? WordOpaqueDrawing)
        XCTAssertEqual(second.parts.count, 2)
        XCTAssertTrue(reimported.text.string.contains("Revised manuscript."))
    }

    func testTwoDrawingsSharingSourceRelationshipGetDistinctExportRelationships() throws {
        var entries = try DOCXPackage.entries(in: vectorDrawingFixture(relationshipBacked: true, includeDependency: true))
        let index = try XCTUnwrap(entries.firstIndex { $0.path == "word/document.xml" })
        let original = String(decoding: entries[index].data, as: UTF8.self)
        let drawing = try XCTUnwrap(original.range(of: "<w:drawing>"))
        let ending = try XCTUnwrap(original.range(of: "</w:drawing>"))
        let fragment = String(original[drawing.lowerBound..<ending.upperBound])
        entries[index].data = Data(original.replacingOccurrences(of: " After", with: " After </w:t>\(fragment)<w:t> Tail").utf8)
        let imported = try reopen(ZipArchiveWriter.archive(entries))
        var drawings: [WordOpaqueDrawing] = []
        imported.text.enumerateAttribute(.boldWriterWordOpaqueDrawing,
            in: NSRange(location: 0, length: imported.text.length)) { value, _, _ in
            if let drawing = value as? WordOpaqueDrawing { drawings.append(drawing) }
        }
        XCTAssertEqual(drawings.count, 2)
        XCTAssertNotEqual(drawings[0].relationships.first?.id, drawings[1].relationships.first?.id)
        let exported = try ExportService.data(for: .docx, document: imported)
        let map = Dictionary(uniqueKeysWithValues: try DOCXPackage.entries(in: exported).map { ($0.path, $0.data) })
        let rels = try DOCXPackage.xml(XCTUnwrap(map["word/_rels/document.xml.rels"]))
        let exportedIDs = Set(try rels.nodes(forXPath: "//*[local-name()='Relationship']/@Id").compactMap(\.stringValue))
        XCTAssertTrue(exportedIDs.contains(drawings[0].relationships[0].id))
        XCTAssertTrue(exportedIDs.contains(drawings[1].relationships[0].id))
        XCTAssertEqual(try DOCXPackage.entries(in: exported).filter { $0.path.hasSuffix("data.xlsx") }.count, 2)
        let reimported = try reopen(exported)
        XCTAssertEqual(reimported.text.string.components(separatedBy: WordOpaqueDrawing.markerText).count - 1, 2)
    }

    func testDiagramWithFourRelationshipsAndNestedPayloadSurvives() throws {
        var entries = try DOCXPackage.entries(in: vectorDrawingFixture(relationshipBacked: true, includeDependency: true))
        let documentIndex = try XCTUnwrap(entries.firstIndex { $0.path == "word/document.xml" })
        let document = String(decoding: entries[documentIndex].data, as: UTF8.self)
        let diagram = "<dgm:relIds xmlns:dgm='http://schemas.openxmlformats.org/drawingml/2006/diagram' xmlns:z='\(r)' z:dm='rChart1' z:lo='rLayout' z:qs='rStyle' z:cs='rColors'/>"
        let expression = try NSRegularExpression(pattern: #"<c:chart[^>]*/>"#)
        entries[documentIndex].data = Data(expression.stringByReplacingMatches(in: document,
            range: NSRange(document.startIndex..., in: document), withTemplate: diagram).utf8)
        let relIndex = try XCTUnwrap(entries.firstIndex { $0.path == "word/_rels/document.xml.rels" })
        let rels = String(decoding: entries[relIndex].data, as: UTF8.self)
        let extra = ["Layout", "Style", "Colors"].map { name in
            "<Relationship Id='r\(name)' Type='\(r)/diagram\(name)' Target='diagrams/\(name.lowercased())1.xml'/>"
        }.joined()
        entries[relIndex].data = Data(rels.replacingOccurrences(of: "</Relationships>", with: extra + "</Relationships>").utf8)
        let chartIndex = try XCTUnwrap(entries.firstIndex { $0.path == "word/charts/chart1.xml" })
        entries[chartIndex].data = Data("<dgm:dataModel xmlns:dgm='http://schemas.openxmlformats.org/drawingml/2006/diagram'/>".utf8)
        for name in ["layout", "style", "colors"] {
            entries.append(ZipEntry(path: "word/diagrams/\(name)1.xml", data: Data("<dgm:\(name) xmlns:dgm='http://schemas.openxmlformats.org/drawingml/2006/diagram'/>".utf8)))
        }
        let typeIndex = try XCTUnwrap(entries.firstIndex { $0.path == "[Content_Types].xml" })
        let types = String(decoding: entries[typeIndex].data, as: UTF8.self)
        let typeOverrides = ["layout", "style", "colors"].map { name in
            "<Override PartName='/word/diagrams/\(name)1.xml' ContentType='application/vnd.openxmlformats-officedocument.drawingml.diagram\(name)+xml'/>"
        }.joined()
        entries[typeIndex].data = Data(types.replacingOccurrences(of: "</Types>", with: typeOverrides + "</Types>").utf8)
        let imported = try reopen(ZipArchiveWriter.archive(entries))
        let marker = (imported.text.string as NSString).range(of: WordOpaqueDrawing.markerText)
        let drawing = try XCTUnwrap(imported.text.attribute(.boldWriterWordOpaqueDrawing,
            at: marker.location, effectiveRange: nil) as? WordOpaqueDrawing)
        XCTAssertEqual(drawing.relationships.count, 4)
        XCTAssertEqual(drawing.parts.count, 5)
        let exported = try ExportService.data(for: .docx, document: imported)
        let reimported = try reopen(exported)
        let restored = try XCTUnwrap(reimported.text.attribute(.boldWriterWordOpaqueDrawing,
            at: marker.location, effectiveRange: nil) as? WordOpaqueDrawing)
        XCTAssertEqual(restored.relationships.count, 4)
        XCTAssertEqual(restored.parts.count, 5)
        XCTAssertEqual(Set(restored.parts.map(\.data)), Set(drawing.parts.map(\.data)))
    }

    func testOpaqueChartRejectsExternalAndEscapingTargets() throws {
        let original = try DOCXPackage.entries(in: vectorDrawingFixture(relationshipBacked: true, includeDependency: true))
        for replacement in ["Target='https://example.invalid/chart.xml' TargetMode='External'",
                            "Target='../../outside.xml'"] {
            var entries = original
            let index = try XCTUnwrap(entries.firstIndex { $0.path == "word/_rels/document.xml.rels" })
            let rels = String(decoding: entries[index].data, as: UTF8.self)
            entries[index].data = Data(rels.replacingOccurrences(of: "Target='charts/chart1.xml'", with: replacement).utf8)
            XCTAssertThrowsError(try reopen(ZipArchiveWriter.archive(entries)))
        }
    }

    func testWordPictureTitleAndDescriptionSurviveNativeAndDOCXRoundTrips() throws {
        let marked = drawing().replacingOccurrences(
            of: "<d:docPr id='1' name='Photo'/>",
            with: "<d:docPr id='1' name='Photo' title='Cover &amp; title' descr='Illustration &amp; caption'/>"
        )
        let originalBytes = try artwork(width: 24, height: 12)
        let imported = try reopen(ZipArchiveWriter.archive(fixture(markup: marked, media: originalBytes)))
        let first = try XCTUnwrap(attachments(imported.text).first)
        let importedAlt = try XCTUnwrap(imported.text.attribute(.boldWriterWordPictureAltText, at: first.0.location, effectiveRange: nil) as? WordPictureAltText)
        XCTAssertEqual(importedAlt.title, "Cover & title")
        XCTAssertEqual(importedAlt.alternativeDescription, "Illustration & caption")
        XCTAssertEqual(first.1.fileWrapper?.regularFileContents, originalBytes)

        let native = try BOLDWriterDocument.packageWrapper(text: imported.text, metadata: imported.metadata)
        let reopened = try BOLDWriterDocument(fileWrapper: native, contentType: .boldWriterDocument)
        let reopenedFirst = try XCTUnwrap(attachments(reopened.text).first)
        let nativeAlt = try XCTUnwrap(reopened.text.attribute(.boldWriterWordPictureAltText, at: reopenedFirst.0.location, effectiveRange: nil) as? WordPictureAltText)
        XCTAssertEqual(nativeAlt.title, importedAlt.title)
        XCTAssertEqual(nativeAlt.alternativeDescription, importedAlt.alternativeDescription)

        let exported = try ExportService.data(for: .docx, document: reopened)
        let parts = Dictionary(uniqueKeysWithValues: try DOCXPackage.entries(in: exported).map { ($0.path, $0.data) })
        let documentXML = String(decoding: try XCTUnwrap(parts["word/document.xml"]), as: UTF8.self)
        XCTAssertTrue(documentXML.contains("title=\"Cover &amp; title\""))
        XCTAssertTrue(documentXML.contains("descr=\"Illustration &amp; caption\""))
        let exportedFirst = try XCTUnwrap(attachments(try reopen(exported).text).first)
        XCTAssertEqual(exportedFirst.1.fileWrapper?.regularFileContents, originalBytes)
    }

    func testImportsIndependentCompressedDOCXWithSharedInlineImagesInOrder() throws {
        let entries = fixture(markup: drawing(), media: try artwork(width: 24, height: 12))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for entry in entries {
            let url = directory.appendingPathComponent(entry.path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try entry.data.write(to: url)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = directory
        process.arguments = ["-q", "-r", "compressed.docx", "[Content_Types].xml", "_rels", "word"]
        try process.run(); process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        let data = try Data(contentsOf: directory.appendingPathComponent("compressed.docx"))
        XCTAssertEqual(data[8], 8, "Independent fixture must exercise ZIP deflate")
        let imported = try reopen(data)
        XCTAssertEqual(imported.text.string.trimmingCharacters(in: .newlines), "Before \u{fffc} between \u{fffc} after")
        let images = attachments(imported.text)
        XCTAssertEqual(images.count, 2)
        XCTAssertEqual(images.map { $0.1.attachmentCell?.cellSize() }, [NSSize(width: 120, height: 60), NSSize(width: 120, height: 60)])
    }

    func testRecoverableAlternateContentFallbackIsImportedOnlyOnce() throws {
        let fallback = "<mc:AlternateContent xmlns:mc='http://schemas.openxmlformats.org/markup-compatibility/2006'><mc:Choice Requires='a'>\(drawing(id: "unsupported"))</mc:Choice><mc:Fallback><w:pict><v:shape xmlns:v='urn:schemas-microsoft-com:vml' style='width:2in;height:1in'><v:imagedata r:id='photo'/></v:shape></w:pict></mc:Fallback></mc:AlternateContent>"
        let imported = try reopen(ZipArchiveWriter.archive(fixture(markup: fallback, media: artwork(width: 24, height: 12))))
        XCTAssertEqual(attachments(imported.text).count, 2)
        XCTAssertEqual(attachments(imported.text).first?.1.attachmentCell?.cellSize(), NSSize(width: 144, height: 72))
        XCTAssertEqual(imported.text.string.trimmingCharacters(in: .newlines), "Before \u{fffc} between \u{fffc} after")
    }

    func testFloatingDrawingMLPageAndMarginAxesRoundTripThroughNativeModel() throws {
        let source = try artwork(width: 32, height: 16, type: .jpeg)
        let text = NSAttributedString(string: "Alpha beta\nSecond paragraph", attributes: [.font: NSFont.systemFont(ofSize: 12)])
        var image = FloatingImage(assetName: "author-photo.jpg", imageData: source,
                                  anchor: .paragraph, anchorLocation: 5,
                                  x: 24, y: 36, anchorOffsetX: 24, anchorOffsetY: 36,
                                  horizontalPositionReference: .page,
                                  verticalPositionReference: .margins,
                                  width: 72, height: 36, rotationDegrees: 12,
                                  wrapping: .topAndBottom, wrapDistance: 9,
                                  layer: .behindText, zOrder: 7)
        image.altTitle = "Author & portrait"
        image.altDescription = "Portrait of the author"
        let characterImage = FloatingImage(assetName: "character-figure.png", imageData: try artwork(width: 16, height: 8),
                                           anchor: .character, anchorLocation: 15,
                                           x: 3, y: 4, anchorOffsetX: 3, anchorOffsetY: 4,
                                           horizontalPositionReference: .anchor,
                                           verticalPositionReference: .anchor,
                                           width: 32, height: 16, wrapping: .square,
                                           wrapDistance: 4, wrapSide: .rightOnly, zOrder: 8)
        let exported = try DOCXExporter.data(from: text, title: "Anchored", floatingImages: [image, characterImage])
        let parts = Dictionary(uniqueKeysWithValues: try DOCXPackage.entries(in: exported).map { ($0.path, $0.data) })
        let xml = String(decoding: try XCTUnwrap(parts["word/document.xml"]), as: UTF8.self)
        XCTAssertTrue(xml.contains("title=\"Author &amp; portrait\""))
        XCTAssertTrue(xml.contains("descr=\"Portrait of the author\""))
        XCTAssertTrue(xml.contains("<wp:anchor"))
        XCTAssertTrue(xml.contains("relativeFrom=\"page\""))
        XCTAssertTrue(xml.contains("relativeFrom=\"margin\""))
        XCTAssertTrue(xml.contains("<wp:wrapTopAndBottom"))
        XCTAssertTrue(xml.contains("behindDoc=\"1\""))
        XCTAssertTrue(xml.contains("rot=\"720000\""))
        XCTAssertTrue(xml.contains("distT=\"114300\""))
        XCTAssertTrue(xml.contains("relativeFrom=\"character\""))
        XCTAssertTrue(xml.contains("wrapText=\"right\""))
        XCTAssertEqual(parts["word/media/floating1.jpg"], source)
        XCTAssertNotNil(parts["word/media/floating2.png"])

        let reopened = try reopen(exported)
        XCTAssertEqual(reopened.text.string, text.string)
        let returnedImages = try XCTUnwrap(reopened.metadata.floatingImages)
        XCTAssertEqual(returnedImages.count, 2)
        let returned = returnedImages[0]
        XCTAssertEqual(returned.anchor, .paragraph)
        XCTAssertEqual(returned.anchorLocation, 5)
        XCTAssertEqual(returned.horizontalPositionReference, .page)
        XCTAssertEqual(returned.verticalPositionReference, .margins)
        XCTAssertEqual(try XCTUnwrap(returned.anchorOffsetX), 24, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(returned.anchorOffsetY), 36, accuracy: 0.01)
        XCTAssertEqual(returned.rotationDegrees, 12, accuracy: 0.01)
        XCTAssertEqual(returned.wrapping, .topAndBottom)
        XCTAssertEqual(returned.wrapDistance, 9, accuracy: 0.01)
        XCTAssertEqual(returned.layer, .behindText)
        XCTAssertEqual(returned.zOrder, 7)
        XCTAssertEqual(returned.imageData, source)
        let returnedCharacter = returnedImages[1]
        XCTAssertEqual(returnedCharacter.anchor, .character)
        XCTAssertEqual(returnedCharacter.anchorLocation, 15)
        XCTAssertEqual(returnedCharacter.wrapSide, .rightOnly)
        XCTAssertEqual(returnedCharacter.horizontalPositionReference, .character)
        XCTAssertEqual(returnedCharacter.verticalPositionReference, .paragraph)
        let physical = FloatingImageLayout.positionedAtAnchor(returned, pageIndex: 4,
                                                               origin: CGPoint(x: 100, y: 200),
                                                               pageContentOrigin: CGPoint(x: 30, y: 40))
        XCTAssertEqual(physical.x, 24, accuracy: 0.01, "Page-relative X must remain relative to the page even though the object follows a paragraph.")
        XCTAssertEqual(physical.y, 76, accuracy: 0.01, "Margin-relative Y must include the physical content origin.")

        let nativePackage = try BOLDWriterDocument.packageWrapper(text: reopened.text, metadata: reopened.metadata)
        let nativeReopened = try BOLDWriterDocument(fileWrapper: nativePackage, contentType: .boldWriterDocument)
        let nativeImage = try XCTUnwrap(nativeReopened.metadata.floatingImages?.first)
        XCTAssertEqual(nativeImage.altTitle, image.altTitle)
        XCTAssertEqual(nativeImage.altDescription, image.altDescription)
        XCTAssertEqual(nativeImage.horizontalPositionReference, .page)
        XCTAssertEqual(nativeImage.verticalPositionReference, .margins)
        XCTAssertEqual(nativeImage.imageData, source)

        let insertedText = "Inserted chapter lead.\n"
        let editedText = NSAttributedString(string: insertedText + nativeReopened.text.string,
                                            attributes: [.font: NSFont.systemFont(ofSize: 12)])
        var editedMetadata = nativeReopened.metadata
        editedMetadata.rebaseTextAnchors(from: nativeReopened.text.string, to: editedText.string)
        XCTAssertEqual(editedMetadata.floatingImages?.first?.anchorLocation,
                       nativeImage.anchorLocation + (insertedText as NSString).length)
        XCTAssertEqual(editedMetadata.floatingImages?.first?.horizontalPositionReference, .page)
        let canvas = PaginatedEditor(text: editedText)
        canvas.configure(printLayout: true, settings: nativeReopened.metadata.page, zoom: 1, viewportWidth: 900)
        canvas.setFloatingImages(editedMetadata.floatingImages ?? [])
        canvas.finishPagination()
        let resolved = try XCTUnwrap(canvas.resolvedFloatingImage(try XCTUnwrap(editedMetadata.floatingImages?.first)))
        XCTAssertEqual(resolved.pageIndex, 0)
        XCTAssertEqual(resolved.x, 24, accuracy: 0.01)
        XCTAssertEqual(resolved.y, Double(canvas.pages[0].pageGeometry?.contentOrigin.y ?? 0) + 36, accuracy: 0.01)
        let pdf = try PDFExporter.data(from: editedText, settings: nativeReopened.metadata.page,
                                       sections: nativeReopened.metadata.sections,
                                       floatingImages: editedMetadata.floatingImages ?? [])
        XCTAssertGreaterThan(try XCTUnwrap(PDFDocument(data: pdf)).pageCount, 0)
    }

    func testAlphaDerivedTightWrapExportsDrawingMLPolygonAndRoundTrips() throws {
        let source = try transparentDiamond()
        let text = NSAttributedString(string: "Tight contour paragraph")
        let image = FloatingImage(assetName: "diamond.png", imageData: source,
                                  anchor: .paragraph, anchorLocation: 6,
                                  x: 18, y: 24, anchorOffsetX: 18, anchorOffsetY: 24,
                                  width: 72, height: 72, wrapping: .tight,
                                  wrapDistance: 6, wrapSide: .largestSide,
                                  sourceCrop: .init(left: 25_000, top: 10_000))
        let data = try DOCXExporter.data(from: text, title: "Tight", floatingImages: [image])
        let entries = try DOCXPackage.entries(in: data)
        let documentXML = String(decoding: try XCTUnwrap(entries.first { $0.path == "word/document.xml" }?.data), as: UTF8.self)
        XCTAssertTrue(documentXML.contains("<wp:wrapTight"))
        XCTAssertTrue(documentXML.contains("<wp:wrapPolygon"))
        XCTAssertTrue(documentXML.contains("<a:srcRect l=\"25000\" t=\"10000\" r=\"0\" b=\"0\"/>"))
        XCTAssertGreaterThan(documentXML.components(separatedBy: "<wp:lineTo").count, 10)
        XCTAssertEqual(entries.first { $0.path == "word/media/floating1.png" }?.data, source)

        var uncropped = image
        uncropped.sourceCrop = nil
        let fullData = try DOCXExporter.data(from: text, title: "Uncropped", floatingImages: [uncropped])
        let fullXML = String(decoding: try XCTUnwrap(DOCXPackage.entries(in: fullData)
            .first { $0.path == "word/document.xml" }?.data), as: UTF8.self)
        func polygon(_ xml: String) -> String? {
            xml.components(separatedBy: "<wp:wrapPolygon").dropFirst().first?
                .components(separatedBy: "</wp:wrapPolygon>").first
        }
        XCTAssertNotEqual(polygon(documentXML), polygon(fullXML),
                          "Tight Wrap's contour must follow the cropped pixels, not the hidden source area.")

        let reopened = try reopen(data)
        XCTAssertEqual(reopened.metadata.floatingImages?.first?.wrapping, .tight)
        XCTAssertEqual(reopened.metadata.floatingImages?.first?.imageData, source)
        XCTAssertEqual(reopened.metadata.floatingImages?.first?.sourceCrop, image.sourceCrop)
        XCTAssertNotNil(reopened.metadata.floatingImages?.first?.wrapPolygon,
                        "The generated DrawingML polygon must remain available after DOCX import.")
        XCTAssertFalse(reopened.lastErrorMessage?.localizedCaseInsensitiveContains("polygon") == true)
    }

    func testEditedWordTightWrapPolygonSurvivesNativeSaveTextEditAndDOCXReimport() throws {
        let source = try artwork(width: 24, height: 12)
        let contour = FloatingImage.WrapPolygon(edited: true, points: [
            .init(x: 1_000, y: 1_000), .init(x: 19_000, y: 1_000),
            .init(x: 12_000, y: 20_000), .init(x: 2_000, y: 18_000)
        ])
        let image = FloatingImage(assetName: "edited-outline.png", imageData: source,
                                  anchor: .paragraph, anchorLocation: 6,
                                  x: 18, y: 24, anchorOffsetX: 18, anchorOffsetY: 24,
                                  width: 72, height: 36, wrapping: .tight,
                                  wrapSide: .largestSide, wrapPolygon: contour)
        let original = try DOCXExporter.data(from: NSAttributedString(string: "Before and after"),
                                             title: "Edited contour", floatingImages: [image])
        let imported = try reopen(original)
        let recovered = try XCTUnwrap(imported.metadata.floatingImages?.first)
        XCTAssertEqual(recovered.wrapPolygon, contour)
        XCTAssertEqual(recovered.imageData, source)
        let native = try BOLDWriterDocument.packageWrapper(text: imported.text, metadata: imported.metadata)
        let reopened = try BOLDWriterDocument(fileWrapper: native, contentType: .boldWriterDocument)
        var metadata = reopened.metadata
        let editedText = NSMutableAttributedString(string: "New opening. ")
        editedText.append(reopened.text)
        metadata.rebaseTextAnchors(from: reopened.text.string, to: editedText.string)
        XCTAssertEqual(metadata.floatingImages?.first?.wrapPolygon, contour)
        let editedDocument = BOLDWriterDocument()
        editedDocument.replaceText(with: editedText)
        editedDocument.metadata = metadata
        let exported = try ExportService.data(for: .docx, document: editedDocument)
        let documentXML = String(decoding: try XCTUnwrap(DOCXPackage.entries(in: exported)
            .first { $0.path == "word/document.xml" }?.data), as: UTF8.self)
        XCTAssertTrue(documentXML.contains("<wp:wrapPolygon edited=\"1\">"))
        XCTAssertTrue(documentXML.contains("<wp:start x=\"1000\" y=\"1000\"/>"))
        XCTAssertTrue(documentXML.contains("<wp:lineTo x=\"12000\" y=\"20000\"/>"))
        let final = try reopen(exported)
        XCTAssertTrue(final.text.string.contains("New opening."))
        XCTAssertEqual(final.metadata.floatingImages?.first?.wrapPolygon, contour)
        XCTAssertEqual(final.metadata.floatingImages?.first?.imageData, source)
    }

    func testWordThroughWrapKeepsAnchorPolygonAndArtworkAcrossNativeAndDOCX() throws {
        let source = try transparentDiamond()
        let outline = FloatingImage.WrapPolygon(edited: true, points: [
            .init(x: 0, y: 0), .init(x: 21_600, y: 0),
            .init(x: 21_600, y: 21_600), .init(x: 0, y: 21_600)
        ])
        let image = FloatingImage(assetName: "through.png", imageData: source,
                                  anchor: .paragraph, anchorLocation: 7,
                                  x: 40, y: 60, anchorOffsetX: 40, anchorOffsetY: 60,
                                  width: 96, height: 96, wrapping: .through,
                                  wrapSide: .rightOnly, wrapPolygon: outline)
        let word = try DOCXExporter.data(from: NSAttributedString(string: "Opening text"),
                                         title: "Through wrapping", floatingImages: [image])
        let imported = try reopen(word)
        let saved = try BOLDWriterDocument.packageWrapper(text: imported.text, metadata: imported.metadata)
        let native = try BOLDWriterDocument(fileWrapper: saved, contentType: .boldWriterDocument)
        let recovered = try XCTUnwrap(native.metadata.floatingImages?.first)
        XCTAssertEqual(recovered.anchor, .paragraph)
        XCTAssertEqual(recovered.wrapping, .through)
        XCTAssertEqual(recovered.wrapSide, .rightOnly)
        XCTAssertEqual(recovered.wrapPolygon, outline)
        XCTAssertEqual(recovered.imageData, source)
        XCTAssertTrue(imported.lastErrorMessage?.contains("conservatively keeps text out") == true)
        let exported = try ExportService.data(for: .docx, document: native)
        let xml = String(decoding: try XCTUnwrap(DOCXPackage.entries(in: exported)
            .first { $0.path == "word/document.xml" }?.data), as: UTF8.self)
        XCTAssertTrue(xml.contains("<wp:wrapThrough wrapText=\"right\">"))
        XCTAssertTrue(xml.contains("<wp:wrapPolygon edited=\"1\">"))
        let returned = try reopen(exported)
        XCTAssertEqual(returned.metadata.floatingImages?.first?.wrapping, .through)
        XCTAssertEqual(returned.metadata.floatingImages?.first?.wrapPolygon, outline)
        XCTAssertEqual(returned.metadata.floatingImages?.first?.imageData, source)
    }

    func testPageFloatingImageExportsWhenManuscriptIsEmpty() throws {
        let source = try artwork(width: 16, height: 8, type: .jpeg)
        let image = FloatingImage(assetName: "blank-page.jpg", imageData: source,
                                  pageIndex: 0, anchor: .page, x: 48, y: 72,
                                  width: 64, height: 32, wrapping: .none)
        let data = try DOCXExporter.data(from: NSAttributedString(string: ""), title: "Artwork only", floatingImages: [image])
        let entries = try DOCXPackage.entries(in: data)
        let xml = String(decoding: try XCTUnwrap(entries.first { $0.path == "word/document.xml" }?.data), as: UTF8.self)
        XCTAssertTrue(xml.contains("<w:p><w:pPr></w:pPr><w:r><w:drawing><wp:anchor"))
        let reopened = try reopen(data)
        XCTAssertEqual(reopened.text.length, 0)
        XCTAssertEqual(reopened.metadata.floatingImages?.first?.x, 48)
        XCTAssertEqual(reopened.metadata.floatingImages?.first?.y, 72)
    }

    func testDuplicateImageRelationshipIdentifiersFailExplicitly() throws {
        var entries = fixture(markup: drawing(), media: try artwork(width: 24, height: 12))
        let relationshipIndex = try XCTUnwrap(entries.firstIndex { $0.path == "word/_rels/document.xml.rels" })
        let duplicate = "<Relationships xmlns='\(r)'><Relationship Id='photo' Type='\(r)/image' Target='media/test%20image.png'/><Relationship Id='photo' Type='\(r)/image' Target='media/test%20image.png'/></Relationships>"
        entries[relationshipIndex].data = Data(duplicate.utf8)
        XCTAssertThrowsError(try reopen(ZipArchiveWriter.archive(entries))) { error in
            XCTAssertTrue(error.localizedDescription.localizedCaseInsensitiveContains("duplicate image relationship"))
        }
    }

    func testMissingOrInvalidDimensionsFallBackToNaturalAspectRatioAndAnchorsStayInOrder() throws {
        for extent in ["", "<d:extent cx='-10' cy='0'/>", "<d:extent cx='NaN' cy='Infinity'/>"] {
            let imported = try reopen(ZipArchiveWriter.archive(fixture(markup: drawing(extent: extent, anchor: true), media: artwork(width: 24, height: 12))))
            let size = try XCTUnwrap(attachments(imported.text).first?.1.attachmentCell?.cellSize())
            XCTAssertEqual(size.width / size.height, 2, accuracy: 0.01)
            XCTAssertEqual(attachments(imported.text).count, 2)
            XCTAssertTrue(imported.text.string.hasPrefix("Before \u{fffc} between"))
            XCTAssertTrue(imported.lastErrorMessage?.localizedCaseInsensitiveContains("retained inline") == true,
                          "The importer must disclose unsupported anchor conversion.")
        }
    }

    func testMissingUnsupportedExternalAndEscapingImageTargetsFailWithoutSilentLoss() throws {
        for entries in [
            fixture(markup: drawing(), media: nil),
            fixture(markup: drawing(), media: Data("unsupported metafile".utf8)),
            fixture(markup: drawing(), media: nil, target: "https://example.com/photo.png", external: true),
            fixture(markup: drawing(), media: nil, target: "../../outside.png")
        ] {
            XCTAssertThrowsError(try reopen(ZipArchiveWriter.archive(entries))) { error in
                XCTAssertTrue(error.localizedDescription.contains("image"))
            }
        }
    }

    func testAdjacentRepeatedAttachmentsAndCellOnlyImagesExportWithoutLoss() throws {
        let image = try XCTUnwrap(NSImage(data: artwork(width: 30, height: 10)))
        image.size = NSSize(width: 90, height: 30)
        let attachment = NSTextAttachment()
        attachment.attachmentCell = NSTextAttachmentCell(imageCell: image)
        let text = NSMutableAttributedString(string: "\u{fffc}\u{fffc}", attributes: [.attachment: attachment])
        text.append(NSAttributedString(string: "Tail"))
        let data = try DOCXExporter.data(from: text, title: "Cell Images")
        let reopened = try reopen(data)
        XCTAssertTrue(reopened.text.string.hasPrefix("\u{fffc}\u{fffc}Tail"))
        XCTAssertEqual(attachments(reopened.text).count, 2)
        XCTAssertEqual(attachments(reopened.text).map { $0.1.attachmentCell?.cellSize() }, [image.size, image.size])
    }

    func testTIFFConvertsToPNGAndOrphanAttachmentFailsExport() throws {
        let tiff = try artwork(width: 20, height: 10, type: .tiff)
        let attachment = try XCTUnwrap(DOCXImages.attachment(data: tiff, name: "art.tiff", size: NSSize(width: 80, height: 40)))
        let data = try DOCXExporter.data(from: NSAttributedString(attachment: attachment), title: "TIFF")
        let parts = try DOCXPackage.entries(in: data)
        XCTAssertTrue(parts.contains { $0.path == "word/media/image1.png" && NSImage(data: $0.data)?.isValid == true })
        XCTAssertEqual(attachments(try reopen(data).text).first?.1.attachmentCell?.cellSize(), NSSize(width: 80, height: 40))
        XCTAssertThrowsError(try DOCXExporter.data(from: NSAttributedString(string: "Text\u{fffc}"), title: "Missing attachment"))
    }

    func testCorruptArchiveFailsGracefully() throws {
        var data = ZipArchiveWriter.archive(fixture(markup: drawing(), media: try artwork(width: 20, height: 10)))
        let image = try XCTUnwrap(data.range(of: Data([0x89, 0x50, 0x4e, 0x47])))
        data[image.lowerBound] = 0
        XCTAssertThrowsError(try reopen(data))
        XCTAssertThrowsError(try reopen(Data(data.prefix(20))))
    }
}

// MARK: - Independent Word floating DrawingML compatibility

extension DOCXImageTests {
    @MainActor
    func testIndependentWordFloatingAnchorImageImportsWithoutSilentLoss()
        throws
    {
        let bitmap =
            try XCTUnwrap(
                NSBitmapImageRep(
                    bitmapDataPlanes: nil,
                    pixelsWide: 4,
                    pixelsHigh: 2,
                    bitsPerSample: 8,
                    samplesPerPixel: 4,
                    hasAlpha: true,
                    isPlanar: false,
                    colorSpaceName: .deviceRGB,
                    bytesPerRow: 0,
                    bitsPerPixel: 0
                )
            )

        for y in 0..<2 {
            for x in 0..<4 {
                bitmap.setColor(x < 2
                    ? NSColor(calibratedRed: 0.9, green: 0.1, blue: 0.1, alpha: 1)
                    : NSColor(calibratedRed: 0.1, green: 0.2, blue: 0.9, alpha: 1), atX: x, y: y)
            }
        }

        let png =
            try XCTUnwrap(
                bitmap.representation(
                    using: .png,
                    properties: [:]
                )
            )

        let contentTypes =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
              <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
              <Default Extension="xml" ContentType="application/xml"/>
              <Default Extension="png" ContentType="image/png"/>
              <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
            </Types>
            """

        let rootRelationships =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
              <Relationship
                Id="rId1"
                Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument"
                Target="word/document.xml"/>
            </Relationships>
            """

        let documentRelationships =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
              <Relationship
                Id="rIdImage1"
                Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image"
                Target="media/floating.png"/>
            </Relationships>
            """

        // Independent Word-style wp:anchor with paragraph-relative geometry.
        let documentXML =
            """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <w:document
              xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
              xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
              xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
              xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
              xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">
              <w:body>
                <w:p>
                  <w:r>
                    <w:t>Before</w:t>
                  </w:r>
                  <w:r>
                    <w:drawing>
                      <wp:anchor
                        distT="12700"
                        distB="38100"
                        distL="50800"
                        distR="25400"
                        simplePos="0"
                        relativeHeight="251658240"
                        behindDoc="0"
                        locked="0"
                        layoutInCell="1"
                        allowOverlap="1">
                        <wp:simplePos x="0" y="0"/>
                        <wp:positionH relativeFrom="paragraph">
                          <wp:posOffset>127000</wp:posOffset>
                        </wp:positionH>
                        <wp:positionV relativeFrom="paragraph">
                          <wp:posOffset>254000</wp:posOffset>
                        </wp:positionV>
                        <wp:extent
                          cx="1270000"
                          cy="635000"/>
                        <wp:effectExtent
                          l="0"
                          t="0"
                          r="0"
                          b="0"/>
                        <wp:wrapSquare wrapText="bothSides"/>
                        <wp:docPr
                          id="1"
                          name="Floating Picture 1"/>
                        <wp:cNvGraphicFramePr>
                          <a:graphicFrameLocks noChangeAspect="1"/>
                        </wp:cNvGraphicFramePr>
                        <a:graphic>
                          <a:graphicData
                            uri="http://schemas.openxmlformats.org/drawingml/2006/picture">
                            <pic:pic>
                              <pic:nvPicPr>
                                <pic:cNvPr
                                  id="1"
                                  name="floating.png"/>
                                <pic:cNvPicPr/>
                              </pic:nvPicPr>
                              <pic:blipFill>
                                <a:blip r:embed="rIdImage1"/>
                                <a:srcRect l="50000" t="0" r="0" b="0"/>
                                <a:stretch>
                                  <a:fillRect/>
                                </a:stretch>
                              </pic:blipFill>
                              <pic:spPr>
                                <a:xfrm rot="1800000">
                                  <a:off x="0" y="0"/>
                                  <a:ext
                                    cx="1270000"
                                    cy="635000"/>
                                </a:xfrm>
                                <a:prstGeom prst="rect">
                                  <a:avLst/>
                                </a:prstGeom>
                              </pic:spPr>
                            </pic:pic>
                          </a:graphicData>
                        </a:graphic>
                      </wp:anchor>
                    </w:drawing>
                  </w:r>
                  <w:r>
                    <w:t>After</w:t>
                  </w:r>
                </w:p>
                <w:sectPr>
                  <w:pgSz
                    w:w="12240"
                    w:h="15840"/>
                  <w:pgMar
                    w:top="1440"
                    w:right="1440"
                    w:bottom="1440"
                    w:left="1440"
                    w:header="720"
                    w:footer="720"
                    w:gutter="0"/>
                </w:sectPr>
              </w:body>
            </w:document>
            """

        let package =
            ZipArchiveWriter.archive(
                [
                    ZipEntry(
                        path: "[Content_Types].xml",
                        data: Data(
                            contentTypes.utf8
                        )
                    ),
                    ZipEntry(
                        path: "_rels/.rels",
                        data: Data(
                            rootRelationships.utf8
                        )
                    ),
                    ZipEntry(
                        path: "word/document.xml",
                        data: Data(
                            documentXML.utf8
                        )
                    ),
                    ZipEntry(
                        path: "word/_rels/document.xml.rels",
                        data: Data(
                            documentRelationships.utf8
                        )
                    ),
                    ZipEntry(
                        path: "word/media/floating.png",
                        data: png
                    ),
                ]
            )

        let directory =
            FileManager
                .default
                .temporaryDirectory
                .appendingPathComponent(
                    "BOLDWriter-Word-Floating-Anchor-\(UUID().uuidString)",
                    isDirectory: true
                )

        try FileManager
            .default
            .createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )

        defer {
            try? FileManager
                .default
                .removeItem(
                    at: directory
                )
        }

        let url =
            directory
                .appendingPathComponent(
                    "Independent-Word-Floating-Anchor.docx"
                )

        try package.write(
            to: url,
            options: .atomic
        )

        let imported =
            try BOLDWriterDocument(
                fileWrapper:
                    FileWrapper(
                        url: url
                    ),
                contentType: .docx
            )

        XCTAssertTrue(
            imported.text.string.contains(
                "Before"
            )
        )

        XCTAssertTrue(
            imported.text.string.contains(
                "After"
            )
        )

        let floating = try XCTUnwrap(imported.metadata.floatingImages?.first)
        XCTAssertTrue(imported.text.string.contains("Before"))
        XCTAssertTrue(imported.text.string.contains("After"))
        XCTAssertFalse(imported.text.string.contains("\u{fffc}"))
        XCTAssertEqual(floating.anchor, .paragraph)
        XCTAssertEqual(floating.anchorOffsetX ?? -1, 10, accuracy: 0.01)
        XCTAssertEqual(floating.anchorOffsetY ?? -1, 20, accuracy: 0.01)
        XCTAssertEqual(floating.width, 100, accuracy: 0.5)
        XCTAssertEqual(floating.height, 50, accuracy: 0.5)
        XCTAssertEqual(floating.rotationDegrees, 30, accuracy: 0.01)
        XCTAssertEqual(floating.wrapping, .square)
        XCTAssertEqual(floating.effectiveWrapDistances, .init(top: 1, right: 2, bottom: 3, left: 4))
        XCTAssertEqual(floating.imageData, png, "The imported source bytes must remain unchanged.")
        XCTAssertEqual(floating.sourceCrop, .init(left: 50_000), "Word's floating source crop must stay editable and anchored.")
        let displayPixels = try XCTUnwrap(floating.displayImage()?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        XCTAssertEqual(displayPixels.width, 2, "Preview and Tight Wrap must use only the visible source pixels.")
        XCTAssertEqual(displayPixels.height, 2)
        let displayBitmap = NSBitmapImageRep(cgImage: displayPixels)
        let shownColor = try XCTUnwrap(displayBitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(shownColor.blueComponent, shownColor.redComponent + 0.25)
        XCTAssertNil(imported.lastErrorMessage)

        let reexported = try ExportService.data(for: .docx, document: imported)
        let entries = try DOCXPackage.entries(in: reexported)
        let documentPart = try XCTUnwrap(entries.first { $0.path == "word/document.xml" })
        let reexportedXML = try XCTUnwrap(String(data: documentPart.data, encoding: .utf8))
        XCTAssertTrue(reexportedXML.contains("<wp:anchor"))
        XCTAssertTrue(reexportedXML.contains("<wp:wrapSquare"))
        XCTAssertTrue(reexportedXML.contains("relativeFrom=\"paragraph\""))
        XCTAssertTrue(reexportedXML.contains("rot=\"1800000\""))
        XCTAssertTrue(reexportedXML.contains("distT=\"12700\""))
        XCTAssertTrue(reexportedXML.contains("distR=\"25400\""))
        XCTAssertTrue(reexportedXML.contains("distB=\"38100\""))
        XCTAssertTrue(reexportedXML.contains("distL=\"50800\""))
        XCTAssertTrue(reexportedXML.contains("<a:srcRect l=\"50000\" t=\"0\" r=\"0\" b=\"0\"/>"))
        let media = entries.filter { $0.path.hasPrefix("word/media/") }
        XCTAssertEqual(media.count, 1)
        XCTAssertEqual(media[0].data, png)

        let roundTripped = try reopen(reexported)
        let roundTrippedImage = try XCTUnwrap(roundTripped.metadata.floatingImages?.first)
        XCTAssertEqual(roundTrippedImage.anchor, floating.anchor)
        XCTAssertEqual(roundTrippedImage.anchorOffsetX, floating.anchorOffsetX)
        XCTAssertEqual(roundTrippedImage.anchorOffsetY, floating.anchorOffsetY)
        XCTAssertEqual(roundTrippedImage.wrapping, floating.wrapping)
        XCTAssertEqual(roundTrippedImage.effectiveWrapDistances, floating.effectiveWrapDistances)
        XCTAssertEqual(roundTrippedImage.imageData, png)
        XCTAssertEqual(roundTrippedImage.sourceCrop, floating.sourceCrop)
        XCTAssertEqual(roundTrippedImage.anchorLocation, floating.anchorLocation)
        XCTAssertLessThanOrEqual(roundTrippedImage.anchorLocation, roundTripped.text.length)

        let nativePackage = try BOLDWriterDocument.packageWrapper(
            text: roundTripped.text,
            metadata: roundTripped.metadata
        )
        let nativeURL = directory.appendingPathComponent("Imported-Word-Anchor.boldwriter")
        try nativePackage.write(to: nativeURL, options: .atomic, originalContentsURL: nil)
        let nativeReopened = try BOLDWriterDocument(
            fileWrapper: FileWrapper(url: nativeURL),
            contentType: .boldWriterDocument
        )
        var editedMetadata = nativeReopened.metadata
        let insertedText = "Inserted before the Word anchor.\n"
        let editedText = NSMutableAttributedString(string: insertedText)
        editedText.append(nativeReopened.text)
        editedMetadata.rebaseTextAnchors(from: nativeReopened.text.string, to: editedText.string)
        let persistedImage = try XCTUnwrap(editedMetadata.floatingImages?.first)
        XCTAssertEqual(persistedImage.anchorLocation, floating.anchorLocation + (insertedText as NSString).length)
        XCTAssertEqual(persistedImage.imageData, png)
        XCTAssertEqual(persistedImage.sourceCrop, floating.sourceCrop)

        let canvas = PaginatedEditor(text: editedText)
        canvas.configure(
            printLayout: true,
            settings: nativeReopened.metadata.page,
            sections: nativeReopened.metadata.sections,
            zoom: 1,
            viewportWidth: 900
        )
        canvas.setFloatingImages(editedMetadata.floatingImages ?? [])
        canvas.finishPagination()
        XCTAssertNil(canvas.lastLayoutError)
        let placed = try XCTUnwrap(canvas.resolvedFloatingImage(persistedImage))
        let editorOrigin = try XCTUnwrap(canvas.resolvedPageOrigin(for: persistedImage))
        var pageRanges: [NSRange] = []
        let pdfData = try PDFExporter.data(
            from: editedText,
            settings: nativeReopened.metadata.page,
            sections: nativeReopened.metadata.sections,
            pageRangeSink: { pageRanges = $0 },
            floatingImages: editedMetadata.floatingImages ?? []
        )
        let pdf = try XCTUnwrap(PDFDocument(data: pdfData))
        XCTAssertEqual(pdf.pageCount, canvas.pages.count)
        XCTAssertEqual(pageRanges, canvas.pageRanges)
        let placement = try XCTUnwrap(
            PDFImageGeometryInspection.placements(in: pdf).first
        )
        XCTAssertEqual(placement.pageIndex, placed.pageIndex)
        let page = try XCTUnwrap(pdf.page(at: placement.pageIndex))
        let mediaBox = page.bounds(for: .mediaBox)
        let editorRect = CGRect(
            x: editorOrigin.x,
            y: editorOrigin.y,
            width: placed.width,
            height: placed.height
        )
        let rotation = CGAffineTransform(translationX: editorRect.midX, y: editorRect.midY)
            .rotated(by: placed.rotationDegrees * .pi / 180)
            .translatedBy(x: -editorRect.midX, y: -editorRect.midY)
        let pdfCorners = [
            CGPoint(x: editorRect.minX, y: editorRect.minY),
            CGPoint(x: editorRect.maxX, y: editorRect.minY),
            CGPoint(x: editorRect.maxX, y: editorRect.maxY),
            CGPoint(x: editorRect.minX, y: editorRect.maxY)
        ].map { point -> CGPoint in
            let editorPoint = point.applying(rotation)
            return CGPoint(x: editorPoint.x, y: mediaBox.height - editorPoint.y)
        }
        let xs = pdfCorners.map(\.x)
        let ys = pdfCorners.map(\.y)
        let expectedBounds = CGRect(
            x: xs.min()!,
            y: ys.min()!,
            width: xs.max()! - xs.min()!,
            height: ys.max()! - ys.min()!
        )
        XCTAssertEqual(placement.bounds.minX, expectedBounds.minX, accuracy: 0.25)
        XCTAssertEqual(placement.bounds.minY, expectedBounds.minY, accuracy: 0.25)
        XCTAssertEqual(placement.bounds.width, expectedBounds.width, accuracy: 0.25)
        XCTAssertEqual(placement.bounds.height, expectedBounds.height, accuracy: 0.25)
        let pageRaster = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(page.thumbnail(
            of: CGSize(width: 900, height: 1200), for: .mediaBox).tiffRepresentation)))
        var bluePixels = 0, redPixels = 0
        for y in stride(from: 0, to: pageRaster.pixelsHigh, by: 3) {
            for x in stride(from: 0, to: pageRaster.pixelsWide, by: 3) {
                guard let color = pageRaster.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.blueComponent > 0.55 && color.blueComponent > color.redComponent + 0.25 { bluePixels += 1 }
                if color.redComponent > 0.55 && color.redComponent > color.blueComponent + 0.25 { redPixels += 1 }
            }
        }
        XCTAssertGreaterThan(bluePixels, 100, "The native/PDF rendering must show the retained blue half of the cropped floating image.")
        XCTAssertLessThan(redPixels, bluePixels / 20, "The removed red half must not reappear in the production PDF.")
        XCTAssertEqual(try XCTUnwrap(nativeReopened.metadata.floatingImages?.first).imageData, png)
        XCTAssertEqual(try XCTUnwrap(nativeReopened.metadata.floatingImages?.first).effectiveWrapDistances,
                       .init(top: 1, right: 2, bottom: 3, left: 4))
    }

    @MainActor
    func testWordPageAndMarginAlignmentRoundTripsAndTracksPageGeometry() throws {
        let sourceImage = try artwork(width: 24, height: 12)
        let sourceText = NSAttributedString(string: "Aligned figure anchor paragraph.",
                                            attributes: [.font: NSFont.systemFont(ofSize: 12)])
        let horizontalOptions: [(String, FloatingImage.PositionReference, FloatingImage.HorizontalAlignment)] = [
            ("page", .page, .left), ("page", .page, .center), ("page", .page, .right),
            ("margin", .margins, .left), ("margin", .margins, .center), ("margin", .margins, .right)
        ]
        let verticalOptions: [(String, FloatingImage.PositionReference, FloatingImage.VerticalAlignment)] = [
            ("page", .page, .top), ("page", .page, .center), ("page", .page, .bottom),
            ("margin", .margins, .top), ("margin", .margins, .center), ("margin", .margins, .bottom)
        ]

        var geometryPDFCase: FloatingImage?
        for (hWordRef, hReference, hAlignment) in horizontalOptions {
            for (vWordRef, vReference, vAlignment) in verticalOptions {
                let offsetImage = FloatingImage(assetName: "alignment.png", imageData: sourceImage,
                                                anchor: .paragraph, anchorLocation: 8,
                                                x: 0, y: 0, anchorOffsetX: 0, anchorOffsetY: 0,
                                                horizontalPositionReference: hReference,
                                                verticalPositionReference: vReference,
                                                width: 48, height: 24, wrapping: .square,
                                                wrapDistances: .init(top: 1, right: 2, bottom: 3, left: 4))
                let offsetDOCX = try DOCXExporter.data(from: sourceText, title: "Alignment", floatingImages: [offsetImage])
                var entries = try DOCXPackage.entries(in: offsetDOCX)
                let documentIndex = try XCTUnwrap(entries.firstIndex(where: { $0.path == "word/document.xml" }))
                var xml = String(decoding: entries[documentIndex].data, as: UTF8.self)
                let oldH = "<wp:positionH relativeFrom=\"\(hWordRef)\"><wp:posOffset>0</wp:posOffset></wp:positionH>"
                let oldV = "<wp:positionV relativeFrom=\"\(vWordRef)\"><wp:posOffset>0</wp:posOffset></wp:positionV>"
                XCTAssertTrue(xml.contains(oldH), "Fixture must contain its horizontal offset form before converting it to Word alignment.")
                XCTAssertTrue(xml.contains(oldV), "Fixture must contain its vertical offset form before converting it to Word alignment.")
                xml = xml.replacingOccurrences(of: oldH,
                                               with: "<wp:positionH relativeFrom=\"\(hWordRef)\"><wp:align>\(hAlignment.rawValue)</wp:align></wp:positionH>")
                xml = xml.replacingOccurrences(of: oldV,
                                               with: "<wp:positionV relativeFrom=\"\(vWordRef)\"><wp:align>\(vAlignment.rawValue)</wp:align></wp:positionV>")
                entries[documentIndex].data = Data(xml.utf8)
                let wordAlignedDOCX = ZipArchiveWriter.archive(entries)

                let imported = try reopen(wordAlignedDOCX)
                let importedImage = try XCTUnwrap(imported.metadata.floatingImages?.first)
                XCTAssertEqual(importedImage.horizontalAlignment, hAlignment)
                XCTAssertEqual(importedImage.verticalAlignment, vAlignment)
                XCTAssertEqual(importedImage.horizontalPositionReference, hReference)
                XCTAssertEqual(importedImage.verticalPositionReference, vReference)
                XCTAssertEqual(importedImage.imageData, sourceImage)

                let native = try BOLDWriterDocument.packageWrapper(text: imported.text, metadata: imported.metadata)
                let nativeReopened = try BOLDWriterDocument(fileWrapper: native, contentType: .boldWriterDocument)
                let savedImage = try XCTUnwrap(nativeReopened.metadata.floatingImages?.first)
                XCTAssertEqual(savedImage.horizontalAlignment, hAlignment)
                XCTAssertEqual(savedImage.verticalAlignment, vAlignment)
                XCTAssertEqual(savedImage.imageData, sourceImage)

                let defaultGeometry = try PageGeometry(nativeReopened.metadata.page)
                let firstPlacement = FloatingImageLayout.positionedAtAnchor(
                    savedImage, pageIndex: 0, origin: CGPoint(x: 90, y: 180),
                    pageContentOrigin: defaultGeometry.contentOrigin,
                    paragraphOrigin: CGPoint(x: 90, y: 180), pageGeometry: defaultGeometry)
                let hFrameOrigin = hReference == .margins ? defaultGeometry.contentOrigin.x : 0
                let hFrameWidth = hReference == .margins ? defaultGeometry.contentSize.width : defaultGeometry.size.width
                let vFrameOrigin = vReference == .margins ? defaultGeometry.contentOrigin.y : 0
                let vFrameHeight = vReference == .margins ? defaultGeometry.contentSize.height : defaultGeometry.size.height
                XCTAssertEqual(firstPlacement.x, Double(horizontalPosition(hAlignment, origin: hFrameOrigin, length: hFrameWidth, size: 48)), accuracy: 0.01)
                XCTAssertEqual(firstPlacement.y, Double(verticalPosition(vAlignment, origin: vFrameOrigin, length: vFrameHeight, size: 24)), accuracy: 0.01)

                var changedPage = nativeReopened.metadata.page
                changedPage.paper = .custom
                changedPage.customPaperSize = CGSize(width: 500, height: 700)
                changedPage.leftMargin = 90
                changedPage.rightMargin = 80
                changedPage.topMargin = 84
                changedPage.bottomMargin = 96
                let changedGeometry = try PageGeometry(changedPage)
                let changedPlacement = FloatingImageLayout.positionedAtAnchor(
                    savedImage, pageIndex: 0, origin: CGPoint(x: 150, y: 240),
                    pageContentOrigin: changedGeometry.contentOrigin,
                    paragraphOrigin: CGPoint(x: 150, y: 240), pageGeometry: changedGeometry)
                let changedHOrigin = hReference == .margins ? changedGeometry.contentOrigin.x : 0
                let changedHWidth = hReference == .margins ? changedGeometry.contentSize.width : changedGeometry.size.width
                let changedVOrigin = vReference == .margins ? changedGeometry.contentOrigin.y : 0
                let changedVHeight = vReference == .margins ? changedGeometry.contentSize.height : changedGeometry.size.height
                XCTAssertEqual(changedPlacement.x, Double(horizontalPosition(hAlignment, origin: changedHOrigin, length: changedHWidth, size: 48)), accuracy: 0.01)
                XCTAssertEqual(changedPlacement.y, Double(verticalPosition(vAlignment, origin: changedVOrigin, length: changedVHeight, size: 24)), accuracy: 0.01)

                let exported = try DOCXExporter.data(from: nativeReopened.text, title: "Aligned round trip",
                                                      floatingImages: [savedImage])
                let exportedParts = try DOCXPackage.entries(in: exported)
                let exportedXML = String(decoding: try XCTUnwrap(exportedParts.first(where: { $0.path == "word/document.xml" })?.data), as: UTF8.self)
                XCTAssertTrue(exportedXML.contains("<wp:positionH relativeFrom=\"\(hWordRef)\"><wp:align>\(hAlignment.rawValue)</wp:align></wp:positionH>"))
                XCTAssertTrue(exportedXML.contains("<wp:positionV relativeFrom=\"\(vWordRef)\"><wp:align>\(vAlignment.rawValue)</wp:align></wp:positionV>"))
                let returned = try reopen(exported)
                let returnedImage = try XCTUnwrap(returned.metadata.floatingImages?.first)
                XCTAssertEqual(returnedImage.horizontalAlignment, hAlignment)
                XCTAssertEqual(returnedImage.verticalAlignment, vAlignment)
                XCTAssertEqual(returnedImage.imageData, sourceImage)
                if hAlignment == .center && hReference == .margins && vAlignment == .bottom && vReference == .page {
                    geometryPDFCase = savedImage
                }
            }
        }

        // The PDF exporter must consume the same page-relative placement as the editor.
        let alignedImage = try XCTUnwrap(geometryPDFCase)
        let metadataDocument = BOLDWriterDocument()
        metadataDocument.replaceText(with: sourceText)
        metadataDocument.updateFloatingImages([alignedImage])
        let canvas = PaginatedEditor(text: metadataDocument.text)
        canvas.configure(printLayout: true, settings: metadataDocument.metadata.page,
                         zoom: 1, viewportWidth: 820)
        canvas.setFloatingImages([alignedImage])
        canvas.finishPagination()
        XCTAssertNil(canvas.lastLayoutError)
        let editorImage = try XCTUnwrap(canvas.resolvedFloatingImage(alignedImage))
        let editorPosition = try XCTUnwrap(canvas.resolvedPageOrigin(for: alignedImage))
        let pdfData = try PDFExporter.data(from: metadataDocument.text, settings: metadataDocument.metadata.page,
                                           floatingImages: [alignedImage])
        let pdf = try XCTUnwrap(PDFDocument(data: pdfData))
        let placement = try XCTUnwrap(PDFImageGeometryInspection.placements(in: pdf).first)
        XCTAssertEqual(placement.pageIndex, editorImage.pageIndex)
        XCTAssertEqual(placement.bounds.minX, editorPosition.x, accuracy: 0.25)
        XCTAssertEqual(placement.bounds.maxX, editorPosition.x + editorImage.width, accuracy: 0.25)
        XCTAssertEqual(placement.bounds.minY, pdf.page(at: placement.pageIndex)!.bounds(for: .mediaBox).height - editorPosition.y - editorImage.height, accuracy: 0.25)
        XCTAssertEqual(placement.bounds.maxY, pdf.page(at: placement.pageIndex)!.bounds(for: .mediaBox).height - editorPosition.y, accuracy: 0.25)
    }

    @MainActor
    func testPageAndMarginAlignedImagesUseSharedCanvasAndPDFGeometry() throws {
        let sourceImage = try artwork(width: 24, height: 12)
        let text = NSAttributedString(string: String(repeating: "Aligned artwork follows the page and margin frame. ", count: 8),
                                      attributes: [.font: NSFont.systemFont(ofSize: 12)])
        let images = [
            FloatingImage(assetName: "page-aligned.png", imageData: sourceImage,
                          pageIndex: 0, anchor: .page, x: 0, y: 0,
                          horizontalPositionReference: .page,
                          verticalPositionReference: .page,
                          horizontalAlignment: .center, verticalAlignment: .bottom,
                          width: 54, height: 27, wrapping: .square),
            FloatingImage(assetName: "margin-aligned.png", imageData: sourceImage,
                          pageIndex: 0, anchor: .margins, x: 0, y: 0,
                          horizontalPositionReference: .margins,
                          verticalPositionReference: .margins,
                          horizontalAlignment: .right, verticalAlignment: .center,
                          width: 42, height: 21, wrapping: .none, zOrder: 1)
        ]
        let document = BOLDWriterDocument()
        document.replaceText(with: text)
        document.updateFloatingImages(images)
        var settings = document.metadata.page
        settings.paper = .custom
        settings.customPaperSize = CGSize(width: 396, height: 612)
        settings.leftMargin = 36
        settings.rightMargin = 42
        settings.topMargin = 48
        settings.bottomMargin = 54
        document.metadata.page = settings
        let nativeData = try BOLDWriterDocument.packageWrapper(text: document.text, metadata: document.metadata)
        let reopened = try BOLDWriterDocument(fileWrapper: nativeData, contentType: .boldWriterDocument)
        let persistedImages = try XCTUnwrap(reopened.metadata.floatingImages)
        XCTAssertEqual(persistedImages.map(\.horizontalAlignment), images.map(\.horizontalAlignment))
        XCTAssertEqual(persistedImages.map(\.verticalAlignment), images.map(\.verticalAlignment))
        XCTAssertEqual(persistedImages.map(\.imageData), images.map(\.imageData))

        let canvas = PaginatedEditor(text: reopened.text)
        canvas.configure(printLayout: true, settings: settings, zoom: 1, viewportWidth: 820)
        canvas.setFloatingImages(persistedImages)
        canvas.finishPagination()
        XCTAssertNil(canvas.lastLayoutError)
        let geometry = try PageGeometry(settings).resolvingPhysicalPage(1)
        let expected: [CGPoint] = [
            CGPoint(x: (geometry.size.width - 54) / 2, y: geometry.size.height - 27),
            CGPoint(x: geometry.contentOrigin.x + geometry.contentSize.width - 42,
                    y: geometry.contentOrigin.y + (geometry.contentSize.height - 21) / 2)
        ]
        for (index, image) in persistedImages.enumerated() {
            let resolved = try XCTUnwrap(canvas.resolvedFloatingImage(image))
            let editorOrigin = try XCTUnwrap(canvas.resolvedPageOrigin(for: image))
            XCTAssertEqual(editorOrigin.x, expected[index].x, accuracy: 0.01)
            XCTAssertEqual(editorOrigin.y, expected[index].y, accuracy: 0.01)
            XCTAssertEqual(resolved.pageIndex, 0)
        }

        let pdfData = try PDFExporter.data(from: reopened.text, settings: settings, floatingImages: persistedImages)
        let pdf = try XCTUnwrap(PDFDocument(data: pdfData))
        let placements = PDFImageGeometryInspection.placements(in: pdf)
        XCTAssertEqual(placements.count, images.count)
        for (index, origin) in expected.enumerated() {
            let placement = try XCTUnwrap(placements.first { abs($0.bounds.width - persistedImages[index].width) < 0.1 })
            let pageHeight = pdf.page(at: placement.pageIndex)!.bounds(for: PDFDisplayBox.mediaBox).height
            XCTAssertEqual(placement.pageIndex, 0)
            XCTAssertEqual(placement.bounds.minX, origin.x, accuracy: 0.25)
            XCTAssertEqual(placement.bounds.minY, pageHeight - origin.y - persistedImages[index].height, accuracy: 0.25)
        }
    }

    func testUnsupportedAlignedReferenceIsRetainedInlineWithSpecificWarning() throws {
        let sourceImage = try artwork(width: 24, height: 12)
        let image = FloatingImage(assetName: "unsupported-alignment.png", imageData: sourceImage,
                                  anchor: .paragraph, anchorLocation: 1,
                                  x: 0, y: 0, anchorOffsetX: 0, anchorOffsetY: 0,
                                  horizontalPositionReference: .paragraph,
                                  verticalPositionReference: .page,
                                  width: 48, height: 24)
        let data = try DOCXExporter.data(from: NSAttributedString(string: "Anchor paragraph"),
                                         title: "Unsupported alignment", floatingImages: [image])
        var entries = try DOCXPackage.entries(in: data)
        let documentIndex = try XCTUnwrap(entries.firstIndex(where: { $0.path == "word/document.xml" }))
        var xml = String(decoding: entries[documentIndex].data, as: UTF8.self)
        let offset = "<wp:positionH relativeFrom=\"paragraph\"><wp:posOffset>0</wp:posOffset></wp:positionH>"
        XCTAssertTrue(xml.contains(offset))
        xml = xml.replacingOccurrences(of: offset,
                                       with: "<wp:positionH relativeFrom=\"paragraph\"><wp:align>center</wp:align></wp:positionH>")
        entries[documentIndex].data = Data(xml.utf8)
        let imported = try reopen(ZipArchiveWriter.archive(entries))
        XCTAssertTrue(imported.metadata.floatingImages?.isEmpty ?? true)
        XCTAssertEqual(attachments(imported.text).count, 1,
                       "Unsupported alignment must preserve the picture inline instead of losing the relationship/media.")
        XCTAssertTrue(imported.lastErrorMessage?.localizedCaseInsensitiveContains("only for left/center/right") == true)

        var invalidNative = image
        invalidNative.horizontalAlignment = .center
        XCTAssertThrowsError(try DOCXExporter.data(from: NSAttributedString(string: "Anchor"),
                                                   title: "Refuse unsupported alignment", floatingImages: [invalidNative]))
    }

    private func horizontalPosition(_ alignment: FloatingImage.HorizontalAlignment, origin: CGFloat, length: CGFloat, size: CGFloat) -> CGFloat {
        switch alignment { case .left: return origin; case .center: return origin + (length - size) / 2; case .right: return origin + length - size }
    }

    private func verticalPosition(_ alignment: FloatingImage.VerticalAlignment, origin: CGFloat, length: CGFloat, size: CGFloat) -> CGFloat {
        switch alignment { case .top: return origin; case .center: return origin + (length - size) / 2; case .bottom: return origin + length - size }
    }
}
