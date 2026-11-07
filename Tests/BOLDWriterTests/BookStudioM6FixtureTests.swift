import AppKit
import Foundation
import PDFKit
import XCTest
@testable import BOLDWriter

/// Reproducible, disposable native-document fixtures for 3D Studio acceptance.
/// This test is opt-in so normal test runs never create large benchmark files.
@MainActor
final class BookStudioM6FixtureTests: XCTestCase {
    func testMeasureColdPageStrataNormalTextureInitialization() throws {
        guard ProcessInfo.processInfo.environment["BOLD_M6_PROFILE_TEXTURE"] == "1" else {
            throw XCTSkip("Set BOLD_M6_PROFILE_TEXTURE=1 to profile first-use texture construction.")
        }
        let started = ProcessInfo.processInfo.systemUptime
        let image = BookPreviewScene.pageStrataNormalImage
        let milliseconds = (ProcessInfo.processInfo.systemUptime - started) * 1_000
        XCTAssertGreaterThan(image.size.width, 0)
        print("BOLD_M6_PAGE_STRATA_NORMAL_INIT_MS=\(milliseconds)")
    }

    func testPageStrataNormalPixelsMatchTheEstablishedRenderer() throws {
        let actual = try XCTUnwrap(BookPreviewScene.pageStrataNormalImage.representations.first as? NSBitmapImageRep)
        let reference = legacyPageStrataNormalImage()
        let actualBytes = Data(bytes: actual.bitmapData!, count: actual.bytesPerRow * actual.pixelsHigh)
        let expectedBytes = Data(bytes: reference.bitmapData!, count: reference.bytesPerRow * reference.pixelsHigh)
        XCTAssertEqual(actual.pixelsWide, reference.pixelsWide)
        XCTAssertEqual(actual.pixelsHigh, reference.pixelsHigh)
        XCTAssertEqual(actualBytes, expectedBytes, "Preview normal-map pixels must remain identical to the current renderer")
    }

    func testGeneratePaperbackAndHardcoverNativeFixtures() throws {
        guard let outputPath = ProcessInfo.processInfo.environment["BOLD_M6_FIXTURE_DIR"],
              outputPath.hasPrefix("/") else {
            throw XCTSkip("Set BOLD_M6_FIXTURE_DIR to a new absolute output directory.")
        }
        let output = URL(fileURLWithPath: outputPath).standardizedFileURL
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path), "Fixture output must be new and disposable")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let settings = pageSettings()
        let fixtures: [(String, NSAttributedString)] = [
            ("short", manuscript(paragraphCount: 100)),
            ("large", manuscript(paragraphCount: 3_000))
        ]
        var manifest: [String: Any] = ["source": "synthetic deterministic text and app-rendered panel artwork", "fixtures": []]
        var records: [[String: Any]] = []

        for (sizeName, text) in fixtures {
            let pdfData = try PDFExporter.data(from: text, settings: settings, sections: nil)
            let pageCount = try XCTUnwrap(PDFDocument(data: pdfData)?.pageCount)
            XCTAssertGreaterThan(pageCount, 0)
            let words = DocumentAnalysis.statistics(for: text.string).words

            for binding in [BookBinding.softcover, .hardcover] {
                let project = cover(binding: binding, pageCount: pageCount)
                var metadata = DocumentMetadata(title: "BOLD Writer M6 \(sizeName) \(binding.rawValue) fixture")
                metadata.page = settings
                metadata.coverProjects = [project]
                metadata.activeCoverProjectID = project.id
                metadata.bookStudioPresentation = BookStudioPresentation()

                let name = "\(sizeName)-\(binding.rawValue.lowercased()).boldwriter"
                let url = output.appendingPathComponent(name, isDirectory: true)
                try BOLDWriterDocument.packageWrapper(text: text, metadata: metadata)
                    .write(to: url, options: .atomic, originalContentsURL: nil)

                let reopened = try BOLDWriterDocument(fileWrapper: FileWrapper(url: url), contentType: .boldWriterDocument)
                XCTAssertEqual(reopened.text.string, text.string)
                XCTAssertEqual(reopened.metadata.coverProjects?.first?.productionBinding, binding)
                XCTAssertEqual(reopened.metadata.activeCoverProjectID, project.id)
                records.append([
                    "name": name,
                    "binding": binding.rawValue,
                    "pageCount": pageCount,
                    "wordCount": words,
                    "characterCount": text.length,
                    "coverPanels": ["back": "crimson", "spine": "gold", "front": "blue"]
                ])
            }
        }
        manifest["fixtures"] = records
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: output.appendingPathComponent("manifest.json"), options: .atomic)
    }

    func testGenerateIllustratedNativeAcceptanceFixture() throws {
        guard let outputPath = ProcessInfo.processInfo.environment["BOLD_M6_ILLUSTRATED_FIXTURE_DIR"],
              outputPath.hasPrefix("/") else {
            throw XCTSkip("Set BOLD_M6_ILLUSTRATED_FIXTURE_DIR to a new absolute output directory.")
        }
        let output = URL(fileURLWithPath: outputPath).standardizedFileURL
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 80, pixelsHigh: 80,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        for y in 0..<80 {
            for x in 0..<80 {
                bitmap.setColor(x < 40
                    ? NSColor(calibratedRed: 0.9, green: 0.1, blue: 0.1, alpha: 1)
                    : NSColor(calibratedRed: 0.1, green: 0.2, blue: 0.9, alpha: 1), atX: x, y: y)
            }
        }
        let imageData = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let wrapper = FileWrapper(regularFileWithContents: imageData)
        wrapper.preferredFilename = "illustration.png"
        let attachment = NSTextAttachment(fileWrapper: wrapper)
        let image = try XCTUnwrap(NSImage(data: imageData))
        image.size = NSSize(width: 160, height: 160)
        attachment.attachmentCell = NSTextAttachmentCell(imageCell: image)
        attachment.bounds = NSRect(x: 0, y: 0, width: 160, height: 160)
        let text = NSMutableAttributedString(string: "The Illustrated Harbor\n\n",
            attributes: [.font: NSFont.systemFont(ofSize: 10)])
        text.append(NSAttributedString(attachment: attachment))
        text.append(NSAttributedString(string: "\nFigure 1. The harbor signal.\n\n" +
            String(repeating: "A real page of manuscript text follows the harbor light. The illustration remains anchored in the first chapter.\n\n", count: 145),
            attributes: [.font: NSFont.systemFont(ofSize: 10)]))
        let settings = pageSettings()
        let pdf = try PDFExporter.data(from: text, settings: settings, sections: nil)
        let pdfDocument = try XCTUnwrap(PDFDocument(data: pdf))
        let pageCount = pdfDocument.pageCount
        XCTAssertGreaterThan(pageCount, 2)
        let firstPage = try XCTUnwrap(pdfDocument.page(at: 0))
        let pageTexture = try XCTUnwrap(PhysicalBookPreview.renderManuscriptPage(firstPage,
            maximumPixelSize: 800))
        let pageBitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(pageTexture.tiffRepresentation)))
        var redPixels = 0, bluePixels = 0
        for y in stride(from: 0, to: pageBitmap.pixelsHigh, by: 5) {
            for x in stride(from: 0, to: pageBitmap.pixelsWide, by: 5) {
                guard let pixel = pageBitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if pixel.redComponent > 0.55 && pixel.redComponent > pixel.blueComponent + 0.25 { redPixels += 1 }
                if pixel.blueComponent > 0.55 && pixel.blueComponent > pixel.redComponent + 0.25 { bluePixels += 1 }
            }
        }
        XCTAssertGreaterThan(redPixels, 25, "The 3D page texture must show the embedded red artwork")
        XCTAssertGreaterThan(bluePixels, 25, "The 3D page texture must show the embedded blue artwork")
        let project = cover(binding: .hardcover, pageCount: pageCount)
        var metadata = DocumentMetadata(title: "Disposable illustrated 3D acceptance book")
        metadata.page = settings
        metadata.coverProjects = [project]
        metadata.activeCoverProjectID = project.id
        metadata.bookStudioPresentation = BookStudioPresentation()
        let url = output.appendingPathComponent("illustrated-hardcover.boldwriter", isDirectory: true)
        try BOLDWriterDocument.packageWrapper(text: text, metadata: metadata)
            .write(to: url, options: .atomic, originalContentsURL: nil)
        let reopened = try BOLDWriterDocument(fileWrapper: FileWrapper(url: url), contentType: .boldWriterDocument)
        XCTAssertEqual(reopened.text.string, text.string)
        XCTAssertNotNil(reopened.text.attribute(.attachment, at: 24, effectiveRange: nil))
        try imageData.write(to: output.appendingPathComponent("expected-illustration.png"), options: .atomic)
        let manifest: [String: Any] = ["pageCount": pageCount, "coverID": project.id.uuidString,
            "illustrationBytes": imageData.count, "source": "synthetic disposable manuscript and editable native cover"]
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("manifest.json"), options: .atomic)
    }

    private func pageSettings() -> PageSettings {
        var settings = PageSettings()
        settings.paper = .custom
        settings.customPaperSize = CGSize(width: 396, height: 612) // 5.5 × 8.5 inches
        settings.topMargin = 42
        settings.bottomMargin = 42
        settings.leftMargin = 48
        settings.rightMargin = 48
        settings.gutter = 18
        settings.mirrorMargins = true
        return settings
    }

    private func manuscript(paragraphCount: Int) -> NSAttributedString {
        let body = "A careful writer follows the harbor light through rain and fog. Each paragraph preserves a stable rhythm for repeatable pagination and scene-texture measurements. "
        let paragraphs = (0..<paragraphCount).map { "Section \($0 + 1). " + body + "\n\n" }.joined()
        return NSAttributedString(string: paragraphs, attributes: [.font: NSFont.systemFont(ofSize: 10)])
    }

    private func legacyPageStrataNormalImage() -> NSBitmapImageRep {
        let width = 384
        let height = 96
        let source = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for x in 0..<width {
            let separator = x % 9 == 0 || x % 17 == 0 || x % 31 == 0
            let grain = CGFloat((x * 37 + x / 5) % 23) / 1100
            let base: CGFloat = separator ? 0.88 + grain : 0.94 + grain
            for y in 0..<height {
                let fiber = CGFloat((x * 7 + y * 13) % 19) / 2800
                let shade = min(0.975, max(0.72, base + fiber))
                source.setColor(NSColor(calibratedRed: shade, green: shade * 0.992,
                                        blue: shade * 0.968, alpha: 1), atX: x, y: y)
            }
        }

        let output = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let pixels = output.bitmapData!
        for y in 0..<height {
            for x in 0..<width {
                let before = source.colorAt(x: (x + width - 1) % width, y: y)!.redComponent
                let after = source.colorAt(x: (x + 1) % width, y: y)!.redComponent
                let slope = Double(before - after) * 1.5
                let length = sqrt(1 + slope * slope)
                let offset = y * output.bytesPerRow + x * 4
                pixels[offset] = UInt8(((slope / length * 0.5 + 0.5) * 255).rounded())
                pixels[offset + 1] = 128
                pixels[offset + 2] = UInt8(((1 / length * 0.5 + 0.5) * 255).rounded())
                pixels[offset + 3] = 255
            }
        }
        return output
    }

    private func cover(binding: BookBinding, pageCount: Int) -> CoverProject {
        let trimWidth = 5.5
        let trimHeight = 8.5
        let bleed = 0.125
        let caliper = 0.00225
        let spine = max(0.18, Double(pageCount) * caliper)
        var project = CoverProject(
            type: .printFullWrap,
            width: trimWidth * 2 + spine + bleed * 2,
            height: trimHeight + bleed * 2
        )
        project.name = "M6 \(binding.rawValue) synthetic full wrap"
        project.trimWidth = trimWidth
        project.trimHeight = trimHeight
        project.backWidth = trimWidth
        project.spineWidth = spine
        project.bleed = bleed
        project.spinePageCount = pageCount
        project.spineCaliperInches = caliper
        project.productionBinding = binding
        project.dpi = 180

        let mapping = CoverWrapGeometry(project: project)
        var back = CoverLayer(kind: .shape, name: "Back artwork — crimson", frame: mapping.backTrim)
        back.fillHex = "#B51F39"
        back.strokeWidth = 0
        var spineLayer = CoverLayer(kind: .shape, name: "Spine artwork — gold", frame: mapping.spineTrim)
        spineLayer.fillHex = "#E1B846"
        spineLayer.strokeWidth = 0
        var front = CoverLayer(kind: .shape, name: "Front artwork — blue", frame: mapping.frontTrim)
        front.fillHex = "#1768B2"
        front.strokeWidth = 0
        project.layers = [back, spineLayer, front]
        return project
    }
}
