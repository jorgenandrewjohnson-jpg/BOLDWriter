import AppKit
import CryptoKit
import UniformTypeIdentifiers
import XCTest
@testable import BOLDWriter

/// Opt-in end-to-end model/export fixture. Artifacts are written only when the
/// caller explicitly supplies a QA-owned output directory.
final class CoverMaskMilestone4EvidenceTests: XCTestCase {
    func testDisposablePrintCoverSaveReopenAndProductionPNGExports() throws {
        guard let outputPath = ProcessInfo.processInfo.environment["BOLD_COVER_M4_EVIDENCE_DIR"] else {
            throw XCTSkip("Set BOLD_COVER_M4_EVIDENCE_DIR to generate the disposable cover project and exports.")
        }
        let output = URL(fileURLWithPath: outputPath, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let sourceImage = try makeIrregularTransparentSubject(width: 512, height: 768)
        let originalSourceHash = SHA256.hash(data: sourceImage)
        let background = try CoverEditorEngine.filledImage(
            width: 32, height: 32,
            color: NSColor(srgbRed: 0.12, green: 0.3, blue: 0.58, alpha: 1)
        )

        var backgroundLayer = try CoverArtwork.imageLayer(
            data: background, filename: "Synthetic Blue Background", frame: CoverRect()
        )
        backgroundLayer.name = "TEST COPY — Opaque Background"
        var subjectLayer = try CoverArtwork.imageLayer(
            data: sourceImage, filename: "Synthetic Irregular Subject",
            frame: CoverRect(x: 0.2, y: 0.16, width: 0.6, height: 0.68)
        )
        subjectLayer.name = "TEST COPY — Editable Mask Subject"

        let sourceWidth = 512
        let sourceHeight = 768
        var mask = Data(repeating: 255, count: sourceWidth * sourceHeight)
        mask = try CoverEditorEngine.paintMask(
            mask, width: sourceWidth, height: sourceHeight,
            points: [CGPoint(x: 256, y: 384)], diameter: 112,
            value: 0, hardness: 1, opacity: 1, flow: 1
        )
        mask = try CoverEditorEngine.paintMask(
            mask, width: sourceWidth, height: sourceHeight,
            points: [CGPoint(x: 132, y: 230)], diameter: 64,
            value: 128, hardness: 0.55, opacity: 0.8, flow: 0.7
        )
        // Reveal a small part of the concealed center with white, preserving an
        // independently identifiable three-tone mask edit in the fixture.
        mask = try CoverEditorEngine.paintMask(
            mask, width: sourceWidth, height: sourceHeight,
            points: [CGPoint(x: 256, y: 384)], diameter: 28,
            value: 255, hardness: 1, opacity: 1, flow: 1
        )
        subjectLayer.maskData = try XCTUnwrap(
            CoverEditorEngine.encodedMask(mask, width: sourceWidth, height: sourceHeight)
        )
        subjectLayer.maskEnabled = true

        var project = CoverProject(type: .ebookFront, width: 5.5, height: 8.5)
        project.name = "TEST-COPY-DO-NOT-USE-AS-ORIGINAL — Milestone 4 Mask Cover"
        project.dpi = 300
        project.backgroundHex = "#FFFFFF"
        project.layers = [backgroundLayer, subjectLayer]

        let document = BOLDWriterDocument()
        document.metadata.coverProjects = [project]
        document.metadata.activeCoverProjectID = project.id
        let nativeURL = output.appendingPathComponent(
            "TEST-COPY-DO-NOT-USE-AS-ORIGINAL-M4-Mask-Cover.boldwriter",
            isDirectory: true
        )
        try BOLDWriterDocument.packageWrapper(text: document.text, metadata: document.metadata)
            .write(to: nativeURL, options: .atomic, originalContentsURL: nil)

        let reopenedWrapper = try FileWrapper(url: nativeURL, options: .immediate)
        let reopenedDocument = try BOLDWriterDocument(
            fileWrapper: reopenedWrapper,
            contentType: try XCTUnwrap(UTType(filenameExtension: "boldwriter"))
        )
        let reopenedProject = try XCTUnwrap(reopenedDocument.metadata.coverProjects?.first)
        let reopenedSubject = try XCTUnwrap(reopenedProject.layers.last)
        XCTAssertEqual(reopenedSubject.imageData, sourceImage)
        XCTAssertEqual(SHA256.hash(data: try XCTUnwrap(reopenedSubject.imageData)), originalSourceHash)
        XCTAssertEqual(reopenedSubject.maskData, subjectLayer.maskData)
        XCTAssertEqual(
            try XCTUnwrap(CoverEditorEngine.decodedMask(
                try XCTUnwrap(reopenedSubject.maskData), width: sourceWidth, height: sourceHeight
            )),
            mask
        )
        XCTAssertEqual(reopenedProject.dpi, 300)
        XCTAssertEqual(reopenedProject.canvasWidth, 5.5)
        XCTAssertEqual(reopenedProject.canvasHeight, 8.5)

        let standardPNG = try CoverArtwork.export(reopenedProject, format: "png")
        let standardURL = output.appendingPathComponent("M4-production-regular-5.5x8.5-300dpi.png")
        try standardPNG.write(to: standardURL, options: Data.WritingOptions.atomic)

        var transparentProject = reopenedProject
        transparentProject.layers[0].visible = false
        let transparentPNG = try CoverArtwork.export(transparentProject, format: "png-transparent")
        let transparentURL = output.appendingPathComponent("M4-production-transparent-5.5x8.5-300dpi.png")
        try transparentPNG.write(to: transparentURL, options: Data.WritingOptions.atomic)

        let standardBitmap = try XCTUnwrap(NSBitmapImageRep(data: standardPNG))
        let transparentBitmap = try XCTUnwrap(NSBitmapImageRep(data: transparentPNG))
        for bitmap in [standardBitmap, transparentBitmap] {
            XCTAssertEqual(bitmap.pixelsWide, 1_650)
            XCTAssertEqual(bitmap.pixelsHigh, 2_550)
            XCTAssertEqual(bitmap.size.width, 396, accuracy: 0.1)
            XCTAssertEqual(bitmap.size.height, 612, accuracy: 0.1)
        }
        XCTAssertGreaterThan(try XCTUnwrap(standardBitmap.colorAt(x: 10, y: 10)).alphaComponent, 0.99)
        XCTAssertLessThan(try XCTUnwrap(transparentBitmap.colorAt(x: 10, y: 10)).alphaComponent, 0.01)
        XCTAssertGreaterThan(
            try XCTUnwrap(transparentBitmap.colorAt(x: 825, y: 1_275)).alphaComponent,
            0.5,
            "The transparent export must retain visible subject artwork."
        )

        let manifest: [String: Any] = [
            "sourceRevision": ProcessInfo.processInfo.environment["BOLD_WRITER_SOURCE_REVISION"] ?? "unrecorded",
            "project": nativeURL.lastPathComponent,
            "subjectSourceSHA256": originalSourceHash.map { String(format: "%02x", $0) }.joined(),
            "maskSHA256": SHA256.hash(data: mask).map { String(format: "%02x", $0) }.joined(),
            "regularPNG": ["file": standardURL.lastPathComponent, "sha256": SHA256.hash(data: standardPNG).map { String(format: "%02x", $0) }.joined(), "pixels": "1650x2550", "dpi": 300],
            "transparentPNG": ["file": transparentURL.lastPathComponent, "sha256": SHA256.hash(data: transparentPNG).map { String(format: "%02x", $0) }.joined(), "pixels": "1650x2550", "dpi": 300]
        ]
        let manifestData = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try manifestData.write(to: output.appendingPathComponent("M4-mask-export-manifest.json"), options: .atomic)
    }

    private func makeIrregularTransparentSubject(width: Int, height: Int) throws -> Data {
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw CocoaError(.fileWriteUnknown) }
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 256, y: 744))
        path.addCurve(to: CGPoint(x: 415, y: 548), control1: CGPoint(x: 420, y: 720), control2: CGPoint(x: 450, y: 620))
        path.addLine(to: CGPoint(x: 368, y: 380))
        path.addCurve(to: CGPoint(x: 342, y: 125), control1: CGPoint(x: 390, y: 260), control2: CGPoint(x: 352, y: 172))
        path.addLine(to: CGPoint(x: 256, y: 30))
        path.addLine(to: CGPoint(x: 170, y: 125))
        path.addCurve(to: CGPoint(x: 144, y: 380), control1: CGPoint(x: 134, y: 172), control2: CGPoint(x: 122, y: 260))
        path.addLine(to: CGPoint(x: 97, y: 548))
        path.addCurve(to: CGPoint(x: 256, y: 744), control1: CGPoint(x: 62, y: 620), control2: CGPoint(x: 92, y: 720))
        path.closeSubpath()
        context.addPath(path)
        context.setFillColor(NSColor(srgbRed: 0.93, green: 0.49, blue: 0.12, alpha: 1).cgColor)
        context.fillPath()
        let image = try XCTUnwrap(context.makeImage())
        return try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
    }
}
