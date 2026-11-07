import AppKit
import PDFKit
import XCTest
@testable import BOLDWriter

/// Produces a real PDF with BOLD Writer's production exporter for independent
/// release evidence. Set BOLD_QA_PDF_OUTPUT to retain the disposable artifact.
@MainActor
final class IndependentPublishingArtifactAcceptanceTests: XCTestCase {
    func testProductionExporterEmitsInspectibleBookTrimPDF() throws {
        guard let outputPath = ProcessInfo.processInfo.environment["BOLD_QA_PDF_OUTPUT"] else {
            throw XCTSkip("Set BOLD_QA_PDF_OUTPUT to retain the disposable production PDF and inspection report")
        }
        let output = URL(fileURLWithPath: outputPath).standardizedFileURL
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path), "Refusing to overwrite evidence")
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)

        let paragraphs = (0..<6).map { index in
            "Chapter \(index + 1) — naïve café • “quoted” text — “A careful editor checks every page.”\n\n" +
            String(repeating: "A varied paragraph with Unicode Ω, em dashes, and readable book text. ", count: 6) + "\n\n"
        }
        let baseText = paragraphs.joined(separator: "\u{000C}")
        let text = NSMutableAttributedString(string: baseText)
        let bodyFont = NSFont(name: "TimesNewRomanPSMT", size: 11) ?? NSFont.systemFont(ofSize: 11)
        text.addAttribute(.font, value: bodyFont, range: NSRange(location: 0, length: text.length))
        text.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 16), range: (baseText as NSString).range(of: "Chapter 1"))
        text.addAttribute(.font, value: NSFontManager.shared.convert(bodyFont, toHaveTrait: .italicFontMask),
                          range: (baseText as NSString).range(of: "naïve café"))
        let png = try markerPNG()
        text.append(NSAttributedString(string: "\nInline illustration: "))
        let inlineWrapper = FileWrapper(regularFileWithContents: png)
        inlineWrapper.preferredFilename = "qa-inline-marker.png"
        text.append(NSAttributedString(attachment: NSTextAttachment(fileWrapper: inlineWrapper)))
        text.append(NSAttributedString(string: "\n"))
        let source = text.string

        var settings = PageSettings()
        settings.paper = .custom
        settings.customPaperSize = CGSize(width: 396, height: 612) // 5.5 × 8.5 in
        settings.topMargin = 54; settings.bottomMargin = 54
        settings.leftMargin = 50; settings.rightMargin = 50
        settings.gutter = 12; settings.mirrorMargins = true
        settings.headerText = "Independent QA — Book Interior"
        settings.footerText = "BOLD Writer production export"
        settings.showsPageNumbers = true

        let anchorLocations = paragraphs.map { (source as NSString).range(of: String($0.prefix(14))).location }
        let wraps: [FloatingImage.Wrapping] = [.square, .tight, .topAndBottom, .none]
        let anchors: [FloatingImage.Anchor] = [.paragraph, .character, .paragraph, .character]
        let images = (0..<4).map { index in
            FloatingImage(assetName: "qa-marker-\(index).png", imageData: png, pageIndex: index,
                          anchor: anchors[index], anchorLocation: anchorLocations[index],
                          x: 246, y: 110, width: 64, height: 42,
                          rotationDegrees: index == 1 ? 7 : 0, wrapping: wraps[index],
                          wrapDistance: 8, layer: .inFrontOfText, zOrder: index)
        }
        var metadata = DocumentMetadata()
        metadata.page = settings
        metadata.title = "Independent PDF Acceptance — 5.5 × 8.5"
        metadata.floatingImages = images
        let secondSectionLocation = (source as NSString).range(of: "Chapter 4").location
        let sections = [DocumentSection(location: 0, page: settings),
                        DocumentSection(location: secondSectionLocation, page: settings, breakType: .nextPage)]

        let package = try BOLDWriterDocument.packageWrapper(text: text, metadata: metadata)
        let reopened = try BOLDWriterDocument(fileWrapper: package, contentType: .boldWriterDocument)
        XCTAssertEqual(reopened.text.string, source)
        var expectedImages = images
        for index in expectedImages.indices { expectedImages[index].assetDigest = Self.sha256(expectedImages[index].imageData) }
        XCTAssertEqual(reopened.metadata.floatingImages, expectedImages,
                       "Native package serialization may add the expected content-addressed asset digest")
        XCTAssertEqual(reopened.metadata.page.customPaperSize, CGSize(width: 396, height: 612))

        var pageLayouts: [PageSettings] = []
        let pdfData = try PDFExporter.data(from: reopened.text, settings: reopened.metadata.page,
                                           sections: sections, pageLayoutSink: { pageLayouts = $0 },
                                           floatingImages: reopened.metadata.floatingImages ?? [])
        try pdfData.write(to: output, options: .atomic)
        let pdf = try XCTUnwrap(PDFDocument(url: output), "Production PDF must reopen independently with PDFKit")
        XCTAssertGreaterThanOrEqual(pdf.pageCount, 6)
        XCTAssertEqual(pdf.pageCount, pageLayouts.count)
        for index in 0..<pdf.pageCount {
            let page = try XCTUnwrap(pdf.page(at: index))
            let box = page.bounds(for: .mediaBox)
            XCTAssertEqual(box.width, 396, accuracy: 0.5)
            XCTAssertEqual(box.height, 612, accuracy: 0.5)
        }
        let extracted = pdf.string ?? ""
        XCTAssertTrue(extracted.contains("naïve café"))
        XCTAssertTrue(extracted.contains("Chapter 6"))
        XCTAssertTrue(extracted.contains("Independent QA — Book Interior"), "Configured header must appear in output")
        XCTAssertTrue(extracted.contains("BOLD Writer production export"), "Configured footer must appear in output")
        let pageNumberFurniture = (0..<pdf.pageCount).allSatisfy { pageIndex in
            pdf.page(at: pageIndex)?.string?.contains("BOLD Writer production export \(pageIndex + 1)") == true
        }
        XCTAssertTrue(pageNumberFurniture, "Every physical page must carry its expected footer page number")
        let placements = PDFImageGeometryInspection.placements(in: pdf)
        XCTAssertGreaterThanOrEqual(placements.count, images.count + 1,
                                    "PDF must contain four floating images and the inline attachment")
        var maxImageGeometryDelta = 0.0
        for (index, image) in placements.enumerated() {
            if index == images.count { break }
            let angle = images[index].rotationDegrees * .pi / 180
            let expectedWidth = abs(cos(angle) * images[index].width) + abs(sin(angle) * images[index].height)
            let expectedHeight = abs(sin(angle) * images[index].width) + abs(cos(angle) * images[index].height)
            let expectedX = images[index].x - (expectedWidth - images[index].width) / 2
            let expectedY = 612 - images[index].y - images[index].height - (expectedHeight - images[index].height) / 2
            let deltas = [abs(Double(image.bounds.minX) - expectedX), abs(Double(image.bounds.minY) - expectedY),
                          abs(Double(image.bounds.width) - expectedWidth), abs(Double(image.bounds.height) - expectedHeight)]
            maxImageGeometryDelta = max(maxImageGeometryDelta, deltas.max() ?? 0)
            XCTAssertEqual(image.pageIndex, images[index].pageIndex)
            XCTAssertLessThanOrEqual(deltas.max() ?? .infinity, 0.05, "PDF image geometry differs from declared physical placement")
            XCTAssertGreaterThan(image.bounds.width, 0)
            XCTAssertGreaterThan(image.bounds.height, 0)
            XCTAssertGreaterThanOrEqual(image.pageIndex, 0)
            XCTAssertLessThan(image.pageIndex, pdf.pageCount)
        }
        let inlinePlacements = placements.filter {
            $0.pageIndex >= 4 && abs($0.bounds.width - 96) < 0.1 && abs($0.bounds.height - 64) < 0.1
        }
        XCTAssertFalse(inlinePlacements.isEmpty, "Inline illustration must follow the final chapter in physical page order")
        let inlineGeometryKeys = Set(inlinePlacements.map {
            "\($0.pageIndex):\(Int(($0.bounds.minX * 100).rounded())):\(Int(($0.bounds.minY * 100).rounded())):\(Int(($0.bounds.width * 100).rounded())):\(Int(($0.bounds.height * 100).rounded()))"
        })
        XCTAssertEqual(inlineGeometryKeys.count, 1, "Repeated alpha/color XObject draws must occupy one inline geometry")
        let inlinePlacement = try XCTUnwrap(inlinePlacements.first)
        let report: [String: Any] = [
            "producer": "BOLD Writer PDFExporter.data",
            "pdfPath": output.path,
            "pdfSHA256": Self.sha256(pdfData),
            "pdfBytes": pdfData.count,
            "sourceUTF16Length": text.length,
            "sourceTextSHA256": Self.sha256(Data(source.utf8)),
            "pageCount": pdf.pageCount,
            "mediaBoxesPoints": [396, 612],
            "trimInches": [5.5, 8.5],
            "extractedTextContainsUnicode": extracted.contains("naïve café"),
            "extractedTextContainsFinalChapter": extracted.contains("Chapter 6"),
            "headerFooterTextPresent": extracted.contains("BOLD Writer production export"),
            "headerTextPresent": extracted.contains("Independent QA — Book Interior"),
            "footerPageNumbersPresentOnEveryPage": pageNumberFurniture,
            "inlineImagePresent": true,
            "inlineImagePageIndex": inlinePlacement.pageIndex,
            "inlineImageRawPDFDrawOperations": inlinePlacements.count,
            "imagePlacements": placements.map { ["pageIndex": $0.pageIndex,
                                                  "x": Double($0.bounds.minX), "y": Double($0.bounds.minY),
                                                  "width": Double($0.bounds.width), "height": Double($0.bounds.height),
                                                  "rotationComponentB": Double($0.unitSquareToPDF.b)] as [String: Any] },
            "maximumImageGeometryDifferencePoints": maxImageGeometryDelta,
            "expectedImageWrapModes": wraps.map(\.rawValue),
            "expectedImageAnchors": anchors.map(\.rawValue),
            "limitations": "This test exercises the production exporter directly; GUI visual comparison remains deferred. Text extraction confirms presence, not optical fidelity."
        ]
        let reportURL = output.deletingPathExtension().appendingPathExtension("inspection.json")
        let reportData = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try reportData.write(to: reportURL, options: .atomic)
        print("BOLD_QA_PRODUCTION_PDF=\(reportURL.path)")
    }

    private func markerPNG() throws -> Data {
        let image = NSImage(size: NSSize(width: 96, height: 64))
        image.lockFocus()
        NSColor(calibratedRed: 0.15, green: 0.48, blue: 0.82, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 96, height: 64), xRadius: 8, yRadius: 8).fill()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: 34, y: 18, width: 28, height: 28)).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data
    }

    private static func sha256(_ data: Data) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/shasum")
        task.arguments = ["-a", "256"]
        let input = Pipe(), output = Pipe()
        task.standardInput = input; task.standardOutput = output
        try? task.run()
        input.fileHandleForWriting.write(data)
        try? input.fileHandleForWriting.close()
        let line = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return line.split(separator: " ").first.map(String.init) ?? ""
    }
}
