import AppKit
import XCTest
@testable import BOLDWriter

/// Explicit opt-in fixture writer for native GUI acceptance. Set
/// BOLD_GUI_FIXTURE_PATH to a new .boldwriter package path, then run this test.
/// The fixture is disposable and contains a real production FloatingImage
/// record so GUI tests do not depend on NSOpenPanel automation.
final class FloatingImageGUIFixtureTests: XCTestCase {
    func testWriteDisposableFloatingImageDocumentForNativeGUIAcceptance() throws {
        guard let path = ProcessInfo.processInfo.environment["BOLD_GUI_FIXTURE_PATH"], !path.isEmpty else {
            throw XCTSkip("Set BOLD_GUI_FIXTURE_PATH to explicitly create a disposable GUI fixture.")
        }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        XCTAssertEqual(url.pathExtension, "boldwriter")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "Refusing to replace an existing document.")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        let paragraph = "The manuscript remains unchanged while the selected picture moves across this page. This sentence should reflow naturally around floating artwork and continue as an ordinary paragraph underneath it. "
        let text = NSMutableAttributedString(string: "Floating image keyboard acceptance.\n\n" + String(repeating: paragraph + "\n\n", count: 18))
        text.addAttribute(.font, value: NSFont.systemFont(ofSize: 15), range: NSRange(location: 0, length: text.length))
        let image = FloatingImage(assetName: "keyboard-fixture.png", imageData: try fixturePNG(),
                                  pageIndex: 0, anchor: .page, x: 108, y: 132,
                                  width: 96, height: 72, wrapping: .none)
        var metadata = DocumentMetadata()
        metadata.floatingImages = [image]
        let wrapper = try BOLDWriterDocument.packageWrapper(text: text, metadata: metadata)
        try wrapper.write(to: url, options: .atomic, originalContentsURL: nil)

        let reopened = try BOLDWriterDocument(fileWrapper: FileWrapper(url: url), contentType: .boldWriterDocument)
        XCTAssertEqual(reopened.metadata.floatingImages?.count, 1)
        XCTAssertEqual(reopened.metadata.floatingImages?.first?.id, image.id)
        XCTAssertEqual(reopened.metadata.floatingImages?.first?.imageData, image.imageData)
        XCTAssertEqual(reopened.text.string, text.string)
        print("BOLD_GUI_FIXTURE path=\(url.path) imageID=\(image.id.uuidString) x=\(image.x) y=\(image.y) width=\(image.width) height=\(image.height)")
    }

    private func fixturePNG() throws -> Data {
        let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 192, pixelsHigh: 144,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: image)
        NSColor.systemOrange.setFill()
        NSBezierPath(roundedRect: CGRect(x: 8, y: 8, width: 176, height: 128), xRadius: 18, yRadius: 18).fill()
        NSColor.systemBlue.setFill()
        NSBezierPath(ovalIn: CGRect(x: 56, y: 42, width: 80, height: 60)).fill()
        NSGraphicsContext.restoreGraphicsState()
        return try XCTUnwrap(image.representation(using: .png, properties: [:]))
    }
}
