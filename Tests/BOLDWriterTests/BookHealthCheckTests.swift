import AppKit
import CoreText
import PDFKit
import XCTest
@testable import BOLDWriter

final class BookHealthCheckTests: XCTestCase {
    @MainActor
    func testAutomationPaginationKeepsCroppedFloatingArtworkFromNativeDocument() throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ))
        for y in 0..<8 {
            for x in 0..<8 {
                bitmap.setColor(x < 4 ? .red : .blue, atX: x, y: y)
            }
        }
        let source = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let image = FloatingImage(
            assetName: "cropped-artwork.png", imageData: source,
            x: 72, y: 144, width: 72, height: 72,
            sourceCrop: .init(left: 50_000)
        )
        var metadata = DocumentMetadata(title: "Automation floating artwork")
        metadata.floatingImages = [image]
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Automation-Floating-\(UUID().uuidString).boldwriter", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: url) }
        try BOLDWriterDocument.packageWrapper(
            text: NSAttributedString(string: "A page with cropped floating artwork"), metadata: metadata
        ).write(to: url, options: .atomic, originalContentsURL: nil)

        let session = try BookAutomationSession(input: url)
        XCTAssertEqual(session.document.metadata.floatingImages?.first?.imageData, source)
        XCTAssertEqual(session.document.metadata.floatingImages?.first?.sourceCrop, image.sourceCrop)
        let (pdf, bytes, pages) = try session.pagination()
        XCTAssertEqual(pdf.pageCount, 1)
        XCTAssertEqual(pages.count, 1)
        let placement = try XCTUnwrap(PDFImageResolutionPreflight.placements(in: bytes).first,
                                     "The automation PDF must contain the imported floating image.")
        XCTAssertEqual(placement.pageNumber, 1)
        XCTAssertEqual(placement.pixelWidth, 4, "Only the visible blue half should be rasterized.")
        XCTAssertEqual(placement.pixelHeight, 8)
    }

    func testProductionPreflightPDFIncludesFloatingManuscriptArtwork() throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 16,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ))
        for y in 0..<16 {
            for x in 0..<16 { bitmap.setColor(NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1), atX: x, y: y) }
        }
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let image = FloatingImage(assetName: "preflight-artwork.png", imageData: png,
                                  x: 36, y: 36, width: 72, height: 72)
        let text = NSAttributedString(string: "Book page with floating illustration")
        let production = try BookHealthReport.productionPDF(
            from: text, settings: PageSettings(), sections: [], floatingImages: [image]
        )
        XCTAssertEqual(production.pageSettings.count, 1)
        let provider = try XCTUnwrap(CGDataProvider(data: production.data as CFData))
        let pdf = try XCTUnwrap(CGPDFDocument(provider))
        let page = try XCTUnwrap(pdf.page(at: 1))
        var resources: CGPDFDictionaryRef?
        XCTAssertTrue(CGPDFDictionaryGetDictionary(try XCTUnwrap(page.dictionary), "Resources", &resources))
        var xObjects: CGPDFDictionaryRef?
        XCTAssertTrue(CGPDFDictionaryGetDictionary(try XCTUnwrap(resources), "XObject", &xObjects))
        XCTAssertGreaterThan(CGPDFDictionaryGetCount(try XCTUnwrap(xObjects)), 0)
        let pdfKitDocument = try XCTUnwrap(PDFDocument(data: production.data))
        let rendered = try XCTUnwrap(pdfKitDocument.page(at: 0)?
            .thumbnail(of: NSSize(width: 612, height: 792), for: .mediaBox).tiffRepresentation)
        let pixels = try XCTUnwrap(NSBitmapImageRep(data: rendered))
        var redPixels = 0
        for y in 0..<pixels.pixelsHigh {
            for x in 0..<pixels.pixelsWide {
                guard let color = pixels.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.redComponent > 0.7 && color.greenComponent < 0.4 && color.blueComponent < 0.4 {
                    redPixels += 1
                }
            }
        }
        XCTAssertGreaterThan(redPixels, 100, "The actual PDF page raster must show manuscript artwork for the 3D page texture.")
        let report = BookHealthReport.evaluate(pdfData: production.data,
                                              pageSettings: production.pageSettings, coverProjects: [],
                                              documentText: text, pageRanges: production.pageRanges)
        XCTAssertEqual(report.productionPDFData, production.data)
        let placement = try XCTUnwrap(PDFImageResolutionPreflight.placements(in: production.data).first)
        XCTAssertEqual(placement.pageNumber, 1)
        XCTAssertEqual(placement.pixelWidth, 16)
        XCTAssertEqual(placement.pixelHeight, 16)
        XCTAssertEqual(placement.minimumDPI, 16, accuracy: 0.5)
        XCTAssertTrue(report.findings.contains {
            $0.title == "Review image resolution" && $0.location == "Manuscript page 1"
                && $0.detail.contains("16 × 16")
        })
    }

    func testImageResolutionPreflightUsesPlacedSizeAndDoesNotWarnForAdequatePixels() throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 180, pixelsHigh: 180,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ))
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let image = FloatingImage(assetName: "print-proof.png", imageData: png,
                                  x: 36, y: 36, width: 72, height: 72)
        let production = try BookHealthReport.productionPDF(
            from: NSAttributedString(string: "Higher-resolution image"),
            settings: PageSettings(), sections: [], floatingImages: [image]
        )
        let placement = try XCTUnwrap(PDFImageResolutionPreflight.placements(in: production.data).first)
        XCTAssertEqual(placement.minimumDPI, 180, accuracy: 0.5)
        let report = BookHealthReport.evaluate(pdfData: production.data,
                                              pageSettings: production.pageSettings, coverProjects: [])
        XCTAssertTrue(report.findings.contains { $0.id == "manuscript.pdf.image-resolution-summary" })
        XCTAssertFalse(report.findings.contains { $0.title == "Review image resolution" })
    }

    func testImageResolutionPreflightFollowsNestedPDFFormTransform() throws {
        let pageContent = "/Fm1 Do"
        let formContent = "q 72 0 0 72 0 0 cm /Im1 Do Q"
        let pixels = String(repeating: "0", count: 100)
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /XObject << /Fm1 4 0 R >> >> /Contents 6 0 R >>",
            "<< /Type /XObject /Subtype /Form /BBox [0 0 72 72] /Matrix [2 0 0 2 0 0] /Resources << /XObject << /Im1 5 0 R >> >> /Length \(formContent.utf8.count) >>\nstream\n\(formContent)\nendstream",
            "<< /Type /XObject /Subtype /Image /Width 10 /Height 10 /BitsPerComponent 8 /ColorSpace /DeviceGray /Length 100 >>\nstream\n\(pixels)\nendstream",
            "<< /Length \(pageContent.utf8.count) >>\nstream\n\(pageContent)\nendstream"
        ]
        var pdf = "%PDF-1.4\n"
        var offsets = [0]
        for (index, object) in objects.enumerated() {
            offsets.append(pdf.utf8.count)
            pdf += "\(index + 1) 0 obj\n\(object)\nendobj\n"
        }
        let xref = pdf.utf8.count
        pdf += "xref\n0 7\n0000000000 65535 f \n"
        for offset in offsets.dropFirst() { pdf += String(format: "%010d 00000 n \n", offset) }
        pdf += "trailer\n<< /Size 7 /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        let data = Data(pdf.utf8)
        XCTAssertEqual(PDFDocument(data: data)?.pageCount, 1)
        let placement = try XCTUnwrap(PDFImageResolutionPreflight.placements(in: data).first)
        XCTAssertEqual(placement.pixelWidth, 10)
        XCTAssertEqual(placement.displayedWidthPoints, 144, accuracy: 0.01)
        XCTAssertEqual(placement.minimumDPI, 5, accuracy: 0.01)
    }

    func testProductionPreflightFindsFontInsideNestedPDFForm() throws {
        let pageContent = "/Fm1 Do"
        let outerContent = "/Fm2 Do"
        let innerContent = "BT /F2 12 Tf 10 10 Td (Nested proof) Tj ET"
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /XObject << /Fm1 4 0 R >> >> /Contents 7 0 R >>",
            "<< /Type /XObject /Subtype /Form /BBox [0 0 200 200] /Resources << /XObject << /Fm2 5 0 R >> >> /Length \(outerContent.utf8.count) >>\nstream\n\(outerContent)\nendstream",
            "<< /Type /XObject /Subtype /Form /BBox [0 0 200 200] /Resources << /Font << /F2 6 0 R >> >> /Length \(innerContent.utf8.count) >>\nstream\n\(innerContent)\nendstream",
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
            "<< /Length \(pageContent.utf8.count) >>\nstream\n\(pageContent)\nendstream"
        ]
        var pdf = "%PDF-1.4\n"
        var offsets = [0]
        for (index, object) in objects.enumerated() {
            offsets.append(pdf.utf8.count)
            pdf += "\(index + 1) 0 obj\n\(object)\nendobj\n"
        }
        let xref = pdf.utf8.count
        pdf += "xref\n0 8\n0000000000 65535 f \n"
        for offset in offsets.dropFirst() { pdf += String(format: "%010d 00000 n \n", offset) }
        pdf += "trailer\n<< /Size 8 /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        let data = Data(pdf.utf8)
        XCTAssertEqual(PDFDocument(data: data)?.pageCount, 1)
        XCTAssertEqual(PDFFontPreflight.unembeddedPageFonts(in: data),
                       [PDFFontEmbeddingIssue(pageNumber: 1, fontName: "Helvetica")])
        let report = BookHealthReport.evaluate(pdfData: data, pageSettings: [PageSettings()], coverProjects: [])
        XCTAssertTrue(report.findings.contains { $0.title == "PDF font is not embedded" && $0.detail.contains("Helvetica") })
    }

    func testProductionPreflightReportsUnembeddedPDFFontAtItsPage() throws {
        let content = "BT /F1 12 Tf 72 720 Td (Proof) Tj ET"
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
            "<< /Length \(content.utf8.count) >>\nstream\n\(content)\nendstream"
        ]
        var pdf = "%PDF-1.4\n"
        var offsets = [0]
        for (index, object) in objects.enumerated() {
            offsets.append(pdf.utf8.count)
            pdf += "\(index + 1) 0 obj\n\(object)\nendobj\n"
        }
        let xref = pdf.utf8.count
        pdf += "xref\n0 6\n0000000000 65535 f \n"
        for offset in offsets.dropFirst() { pdf += String(format: "%010d 00000 n \n", offset) }
        pdf += "trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        let data = Data(pdf.utf8)
        XCTAssertEqual(PDFDocument(data: data)?.pageCount, 1)
        XCTAssertEqual(PDFFontPreflight.unembeddedPageFonts(in: data),
                       [PDFFontEmbeddingIssue(pageNumber: 1, fontName: "Helvetica")])
        var settings = PageSettings()
        settings.customPaperSize = CGSize(width: 612, height: 792)
        let report = BookHealthReport.evaluate(pdfData: data, pageSettings: [settings], coverProjects: [])
        XCTAssertTrue(report.findings.contains { $0.title == "PDF font is not embedded" && $0.location == "Manuscript page 1" })
    }

    func testProductionPaginationPreservesSourceFieldResultsAndText() throws {
        let source = NSMutableAttributedString(string: "Contents: stale result")
        let range = NSRange(location: 10, length: source.length - 10)
        let field = WordField(kind: .simple, instruction: "PAGEREF MissingHeading \\h")
        source.addAttribute(.boldWriterField, value: field, range: range)
        let originalString = source.string
        let originalField = try XCTUnwrap(source.attribute(.boldWriterField, at: range.location, effectiveRange: nil) as? WordField)

        let production = try BookHealthReport.productionPDF(
            from: source,
            settings: PageSettings(),
            sections: []
        )

        XCTAssertGreaterThan(production.data.count, 0)
        XCTAssertEqual(source.string, originalString)
        XCTAssertEqual(
            source.attribute(.boldWriterField, at: range.location, effectiveRange: nil) as? WordField,
            originalField
        )
    }

    func testOrphanHeadingWarningRequiresVerifiedPageMap() {
        let text = NSMutableAttributedString(string: "Chapter One\nBody starts here.")
        let heading = (text.string as NSString).range(of: "Chapter One")
        text.addAttribute(.boldWriterStyle, value: WriterStyle.heading1.rawValue, range: heading)
        let split = NSRange(location: 12, length: text.length - 12)
        let findings = BookHealthReport.paginationHeadingFindings(
            documentText: text,
            pageRanges: [NSRange(location: 0, length: 12), split]
        )
        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings.first?.severity, .warning)
        XCTAssertEqual(findings.first?.location, "Manuscript page 1")
        XCTAssertTrue(BookHealthReport.paginationHeadingFindings(documentText: text, pageRanges: []).isEmpty)
    }

    func testReadOnlyPublishingInspectionPreservesNativePackageAndUndoHistory() throws {
        let text = NSMutableAttributedString(string: "Chapter One\nSee Chapter One, page 1.\nFootnote marker .\nEndnote marker .\n")
        text.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 16), range: NSRange(location: 0, length: 12))
        let fieldRange = (text.string as NSString).range(of: "page 1")
        text.addAttribute(.boldWriterField, value: WordField(kind: .simple, instruction: "PAGEREF ChapterOne \\h"), range: fieldRange)
        for (token, body, kind) in [("Footnote marker .", "Footnote body", true), ("Endnote marker .", "Endnote body", false)] {
            let tokenRange = (text.string as NSString).range(of: token)
            let markerRange = NSRange(location: NSMaxRange(tokenRange) - 1, length: 1)
            if kind {
                text.replaceCharacters(in: markerRange, with: Footnotes.marker(Footnote(text: body, location: markerRange.location, length: 1), number: 1))
            } else {
                text.replaceCharacters(in: markerRange, with: Endnotes.marker(Endnote(text: body, location: markerRange.location, length: 1), number: 1))
            }
        }
        let image = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 32,
            pixelsHigh: 32,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let imageData = try XCTUnwrap(image.representation(using: .png, properties: [:]))
        var paperback = CoverProject(type: .printFullWrap, width: 13, height: 9)
        paperback.name = "Paperback cover"
        var photo = CoverLayer(kind: .image, name: "Original photograph", frame: CoverRect(x: 0.55, y: 0.05, width: 0.4, height: 0.9))
        photo.imageData = imageData
        paperback.layers = [photo]
        var hardcover = paperback
        hardcover.id = UUID()
        hardcover.name = "Hardcover cover"
        var metadata = DocumentMetadata(title: "Read-only acceptance")
        metadata.notes = "Keep this author note intact."
        metadata.bookmarks = [DocumentBookmark(name: "ChapterOne", location: 0, length: 12)]
        metadata.comments = [DocumentComment(text: "Author comment", location: 0, length: 12)]
        metadata.coverProjects = [paperback, hardcover]
        metadata.activeCoverProjectID = paperback.id
        metadata.bookStudioPresentation = BookStudioPresentation()

        let initial = try BOLDWriterDocument.packageWrapper(text: text, metadata: metadata)
        let document = try BOLDWriterDocument(fileWrapper: initial, contentType: .boldWriterDocument)
        let baseline = try BOLDWriterDocument.packageWrapper(text: document.text, metadata: document.metadata)
        let beforeMetadata = try XCTUnwrap(baseline.fileWrappers?["metadata.json"]?.regularFileContents)
        let stateText = document.text.copy() as! NSAttributedString
        let stateMetadata = document.metadata
        let undo = UndoManager()
        let undoTarget = NSObject()
        undo.registerUndo(withTarget: undoTarget) { _ in }
        let canUndoBefore = undo.canUndo
        let canRedoBefore = undo.canRedo

        let production = try BookHealthReport.productionPDF(
            from: document.text,
            settings: document.metadata.page,
            sections: document.metadata.sections ?? []
        )
        let health = BookHealthReport.evaluate(
            pdfData: production.data,
            pageSettings: production.pageSettings,
            coverProjects: document.metadata.coverProjects ?? [],
            documentText: document.text,
            pageRanges: production.pageRanges,
            bookmarks: document.metadata.bookmarks
        )
        XCTAssertGreaterThan(health.pageCount, 0)
        XCTAssertEqual(PDFDocument(data: try XCTUnwrap(health.productionPDFData))?.pageCount, health.pageCount)
        _ = PhysicalBookDiagnostics.publishingPreflight(
            project: paperback,
            manuscriptPageCount: health.pageCount,
            pageSettings: production.pageSettings
        )
        _ = PhysicalBookCoverTextures(project: paperback, workingLayers: false, previewDPI: 36)
        _ = BookPreviewScene.make(
            project: paperback,
            workingLayers: false,
            open: true,
            angle: 35,
            leftPage: 0,
            rightPage: 1,
            pageCount: health.pageCount,
            spreadIndex: 0,
            leftTexture: nil,
            rightTexture: nil,
            margins: false,
            thumbMode: .off,
            leftPageSettings: PageSettings(),
            rightPageSettings: PageSettings(),
            preset: .reading,
            revisionID: UUID(),
            binding: .softcover
        )

        XCTAssertTrue(document.text.isEqual(to: stateText))
        XCTAssertEqual(document.metadata, stateMetadata)
        XCTAssertEqual(undo.canUndo, canUndoBefore)
        XCTAssertEqual(undo.canRedo, canRedoBefore)
        let after = try BOLDWriterDocument.packageWrapper(text: document.text, metadata: document.metadata)
        let afterMetadata = try XCTUnwrap(after.fileWrappers?["metadata.json"]?.regularFileContents)
        var baselineObject = try XCTUnwrap(JSONSerialization.jsonObject(with: beforeMetadata) as? [String: Any])
        var afterObject = try XCTUnwrap(JSONSerialization.jsonObject(with: afterMetadata) as? [String: Any])
        // NSKeyedArchiver may encode equivalent Cocoa attributes with distinct
        // archive byte ordering; compare author metadata exactly and verify the
        // restored attributed text below.
        baselineObject.removeValue(forKey: "manuscriptFormatting")
        afterObject.removeValue(forKey: "manuscriptFormatting")
        XCTAssertTrue(NSDictionary(dictionary: baselineObject).isEqual(to: afterObject))
        XCTAssertNotNil(after.fileWrappers?["content.rtfd"]?.serializedRepresentation)

        let savedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BOLD-ReadOnly-\(UUID().uuidString).boldwriter", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: savedURL) }
        try after.write(to: savedURL, options: .atomic, originalContentsURL: nil)
        let reopened = try BOLDWriterDocument(fileWrapper: FileWrapper(url: savedURL), contentType: .boldWriterDocument)
        XCTAssertTrue(reopened.text.isEqual(to: stateText))
        XCTAssertEqual(reopened.metadata.title, stateMetadata.title)
        XCTAssertEqual(reopened.metadata.notes, stateMetadata.notes)
        XCTAssertEqual(reopened.metadata.bookmarks, stateMetadata.bookmarks)
        XCTAssertEqual(reopened.metadata.comments, stateMetadata.comments)
        XCTAssertEqual(reopened.metadata.coverProjects, stateMetadata.coverProjects)
        XCTAssertEqual(reopened.metadata.footnotes, stateMetadata.footnotes)
        XCTAssertEqual(reopened.metadata.endnotes, stateMetadata.endnotes)
        XCTAssertEqual(reopened.metadata.fields, stateMetadata.fields)
    }

    func testInvalidLegacyTemplateRemainsNotReadyAndNamesTheMismatch() throws {
        var project = CoverProject(type: .printFullWrap, width: 19.469, height: 12.417)
        project.name = "Legacy 535-page template"
        project.productionBinding = .hardcover
        project.trimWidth = 8.25
        project.backWidth = 8.25
        project.trimHeight = 11
        project.spineWidth = 1.394
        project.spinePageCount = 535
        project.kdpHardcoverLayout = KDPHardcoverLayout(
            canvasWidth: 19.469, canvasHeight: 12.417,
            trimWidth: 8.25, trimHeight: 11,
            spineWidth: 1.394, pageCount: 535
        )

        var page = PageSettings()
        page.customPaperSize = CGSize(width: 396, height: 612)
        var pageLayouts: [PageSettings] = []
        let data = try PDFExporter.data(from: NSAttributedString(string: "A test page."), settings: page, pageLayoutSink: { pageLayouts = $0 })
        let result = BookHealthReport.evaluate(
            pdfData: data,
            pageSettings: pageLayouts,
            coverProjects: [project]
        )

        XCTAssertEqual(result.pageCount, 1)
        XCTAssertEqual(result.status, .notReady)
        XCTAssertTrue(result.findings.contains {
            $0.severity == .error
                && $0.location == "Legacy 535-page template"
                && $0.detail.contains("535 pages")
                && $0.detail.contains("1")
        })
        XCTAssertTrue(result.findings.contains { $0.id == "cover.profile.missing.softcover" })
    }

    func testUnreadablePDFCannotBeMarkedReady() {
        let result = BookHealthReport.evaluate(pdfData: Data("not a PDF".utf8), pageSettings: [], coverProjects: [])
        XCTAssertEqual(result.status, .notReady)
        XCTAssertTrue(result.findings.contains { $0.id == "manuscript.pdf.invalid" && $0.severity == .error })
    }

    func testSuccessfulPDFWithoutBothPrintProfilesIsReviewNotReady() throws {
        let page = PageSettings()
        var pageLayouts: [PageSettings] = []
        let data = try PDFExporter.data(from: NSAttributedString(string: "A test page."), settings: page, pageLayoutSink: { pageLayouts = $0 })
        let result = BookHealthReport.evaluate(pdfData: data, pageSettings: pageLayouts, coverProjects: [])

        XCTAssertEqual(result.pageCount, 1)
        XCTAssertEqual(result.status, .review)
        XCTAssertTrue(result.findings.contains { $0.id == "manuscript.pages" })
        XCTAssertTrue(result.findings.contains { $0.id == "manuscript.trim" })
        XCTAssertEqual(result.productionPDFData, data)
        XCTAssertEqual(result.pageSettings.count, result.pageCount)
        XCTAssertTrue(result.findings.contains { $0.id == "cover.profile.missing.softcover" })
        XCTAssertTrue(result.findings.contains { $0.id == "cover.profile.missing.hardcover" })
    }

    func testBrokenCrossReferenceIsAnActionableManuscriptError() throws {
        let text = NSMutableAttributedString(string: "See section")
        let field = WordField(kind: .simple, instruction: "REF MissingHeading \\h")
        text.addAttribute(.boldWriterField, value: field, range: NSRange(location: 0, length: text.length))
        let page = PageSettings()
        var layouts: [PageSettings] = []
        var ranges: [NSRange] = []
        let pdf = try PDFExporter.data(
            from: text,
            settings: page,
            pageLayoutSink: { layouts = $0 },
            pageRangeSink: { ranges = $0 }
        )

        let result = BookHealthReport.evaluate(
            pdfData: pdf,
            pageSettings: layouts,
            coverProjects: [],
            documentText: text,
            pageRanges: ranges
        )
        let finding = result.findings.first { $0.id == "manuscript.cross-reference.\(field.id.uuidString)" }
        XCTAssertEqual(result.status, .notReady)
        XCTAssertEqual(finding?.severity, .error)
        XCTAssertEqual(finding?.location, "Manuscript page 1")
        XCTAssertTrue(finding?.detail.contains("MissingHeading") == true)
    }

    func testValidHundredPagePaperbackAndHardcoverProfilesCanBeReady() throws {
        let pageCount = 100
        let trimWidth = 5.5
        let trimHeight = 8.5
        var settings = PageSettings()
        settings.paper = .custom
        settings.customPaperSize = CGSize(width: 396, height: 612)
        let pages = Array(repeating: settings, count: pageCount)
        let pdf = try proofPDF(pageCount: pageCount, size: settings.pageSize)

        let original = CoverProject(type: .printFullWrap, width: 12, height: 9)
        let paperback = try XCTUnwrap(PhysicalBookGeometry.adaptingArtworkToKDPPaperback(
            original,
            pageCount: pageCount,
            trimWidth: trimWidth,
            trimHeight: trimHeight,
            paperStock: .kdpWhite
        ))
        var hardcover = original
        hardcover.name = "Hardcover"
        let spine = 0.3
        let boardWidth = trimWidth + 5 / 25.4
        let boardHeight = trimHeight + 6 / 25.4
        let wrap = 15 / 25.4
        let layout = KDPHardcoverLayout(
            canvasWidth: 2 * boardWidth + spine + 2 * wrap,
            canvasHeight: boardHeight + 2 * wrap,
            trimWidth: trimWidth,
            trimHeight: trimHeight,
            spineWidth: spine,
            pageCount: pageCount
        )
        hardcover.canvasWidth = layout.canvasWidth
        hardcover.canvasHeight = layout.canvasHeight
        hardcover.trimWidth = trimWidth
        hardcover.backWidth = trimWidth
        hardcover.trimHeight = trimHeight
        hardcover.spineWidth = spine
        hardcover.spinePageCount = pageCount
        hardcover.paperStockPreset = .kdpWhite
        hardcover.productionBinding = .hardcover
        hardcover.productionTemplate = .custom
        hardcover.kdpHardcoverLayout = layout

        var missingReference = CoverLayer(
            kind: .template,
            name: "Missing legacy image reference",
            frame: CoverRect(x: 0, y: 0, width: 1, height: 1)
        )
        missingReference.referenceOnly = true
        var paperbackWithReference = paperback
        paperbackWithReference.layers = [missingReference]
        var hardcoverWithReference = hardcover
        missingReference.id = UUID()
        hardcoverWithReference.layers = [missingReference]

        let result = BookHealthReport.evaluate(
            pdfData: pdf,
            pageSettings: pages,
            coverProjects: [paperbackWithReference, hardcoverWithReference]
        )
        XCTAssertEqual(result.status, .review, result.findings.map(\.detail).joined(separator: "\n"))
        XCTAssertEqual(result.pageCount, pageCount)
        XCTAssertFalse(result.findings.contains { $0.severity == .error })
        XCTAssertFalse(result.findings.contains { $0.id.hasPrefix("cover.profile.missing") })
        XCTAssertTrue(result.findings.contains {
            $0.severity == .warning && $0.detail.contains("Missing legacy image reference")
                && $0.detail.contains("not included in print")
        })

        var missingProductionArtwork = CoverLayer(
            kind: .image,
            name: "Missing front photograph",
            frame: CoverRect(x: 0.55, y: 0.05, width: 0.4, height: 0.9)
        )
        missingProductionArtwork.referenceOnly = false
        var invalidProductionCover = paperback
        invalidProductionCover.layers = [missingProductionArtwork]
        let blocked = PhysicalBookDiagnostics.publishingPreflight(
            project: invalidProductionCover,
            manuscriptPageCount: pageCount,
            pageSettings: pages
        )
        XCTAssertEqual(blocked.status, .notReady)
        XCTAssertTrue(blocked.errors.contains { $0.contains("Missing front photograph") })
    }

    private func proofPDF(pageCount: Int, size: CGSize) throws -> Data {
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: size)
        let consumer = try XCTUnwrap(CGDataConsumer(data: data as CFMutableData))
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
        let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        for index in 0..<pageCount {
            context.beginPDFPage(nil)
            let line = CTLineCreateWithAttributedString(NSAttributedString(
                string: "Proof page \(index + 1)",
                attributes: [.font: font]
            ))
            context.textPosition = CGPoint(x: 36, y: 36)
            CTLineDraw(line, context)
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }
}
