import AppKit
import XCTest
@testable import BOLDWriter

final class CoverMaskEditingTests: XCTestCase {
    func testProjectHistorySnapshotPreservesSelectionAndMatchesByValue() {
        let mask = Data([0, 1, 127, 255])
        var original = CoverProject(width: 2, height: 2)
        original.editorActiveSelectionMask = mask
        original.editorDismissedSelectionMask = Data([255, 127, 1, 0])

        let snapshot = CoverProjectHistory.snapshot(original)
        XCTAssertTrue(CoverProjectHistory.matches(snapshot, project: original))
        XCTAssertEqual(snapshot.editorActiveSelectionMask, mask)
        XCTAssertEqual(snapshot.editorDismissedSelectionMask, original.editorDismissedSelectionMask)

        var edited = original
        edited.editorActiveSelectionMask = Data([255, 127, 1, 0])
        XCTAssertFalse(CoverProjectHistory.matches(snapshot, project: edited))

        var undo = [snapshot]
        var redo: [CoverProject] = []
        CoverProjectHistory.undo(project: &edited, undo: &undo, redo: &redo)
        XCTAssertEqual(edited, original)
        CoverProjectHistory.redo(project: &edited, undo: &undo, redo: &redo)
        XCTAssertEqual(edited.editorActiveSelectionMask, Data([255, 127, 1, 0]))
    }

    func testMaskPaintColorMapsBlackGrayAndWhiteToCoverage() throws {
        XCTAssertEqual(CoverEditorEngine.maskValue(for: .black), 0)
        XCTAssertEqual(CoverEditorEngine.maskValue(for: NSColor(white: 0.5, alpha: 1)), 128)
        XCTAssertEqual(CoverEditorEngine.maskValue(for: .white), 255)

        let pencil = try CoverEditorEngine.pencilMask(
            Data(repeating: 0, count: 64),
            width: 8,
            height: 8,
            points: [CGPoint(x: 4, y: 4)],
            diameter: 3,
            value: 128,
            opacity: 1,
            flow: 1
        )
        XCTAssertEqual(pencil[4 * 8 + 4], 128)
    }

    func testMaskBrushUsesOpacityFlowAndSelectionCoverage() throws {
        let width = 12
        let height = 12
        let originalMask = Data(repeating: 0, count: width * height)
        var selectionBytes = [UInt8](repeating: 0, count: width * height)
        selectionBytes[6 * width + 6] = 128
        let selection = Data(selectionBytes)

        let revealed = try CoverEditorEngine.paintMask(
            originalMask,
            width: width,
            height: height,
            points: [CGPoint(x: 6, y: 6)],
            diameter: 5,
            value: 255,
            hardness: 1,
            opacity: 0.5,
            flow: 0.5,
            selection: selection
        )

        XCTAssertEqual(revealed[6 * width + 6], 32)
        XCTAssertEqual(revealed[6 * width + 5], 0, "A zero-coverage selection pixel must remain unchanged.")
        XCTAssertNotEqual(revealed, originalMask)
    }

    func testMaskBrushConcealsWithPartialOpacityAndHardness() throws {
        let width = 12
        let height = 12
        let originalMask = Data(repeating: 255, count: width * height)
        let concealed = try CoverEditorEngine.paintMask(
            originalMask,
            width: width,
            height: height,
            points: [CGPoint(x: 6, y: 6)],
            diameter: 6,
            value: 0,
            hardness: 0,
            opacity: 0.5,
            flow: 0.5
        )

        XCTAssertEqual(concealed[6 * width + 6], 191)
        XCTAssertLessThan(concealed[6 * width + 6], concealed[6 * width + 5])
        XCTAssertLessThan(concealed[6 * width + 5], concealed[6 * width + 3])
        XCTAssertEqual(concealed[0], 255)
    }

    func testMaskPaintingPreservesSourcePixelsAndNativeRoundTrip() throws {
        let source = try CoverEditorEngine.filledImage(
            width: 16,
            height: 16,
            color: NSColor(srgbRed: 0.2, green: 0.55, blue: 0.85, alpha: 1)
        )
        let originalMask = Data(repeating: 255, count: 16 * 16)
        let editedMask = try CoverEditorEngine.paintMask(
            originalMask,
            width: 16,
            height: 16,
            points: [CGPoint(x: 8, y: 8)],
            diameter: 7,
            value: 0,
            hardness: 0.75,
            opacity: 0.8,
            flow: 0.6
        )

        var layer = try CoverArtwork.imageLayer(data: source, filename: "Mask Source")
        let originalMaskPNG = try XCTUnwrap(CoverEditorEngine.encodedMask(originalMask, width: 16, height: 16))
        let editedMaskPNG = try XCTUnwrap(CoverEditorEngine.encodedMask(editedMask, width: 16, height: 16))
        layer.maskData = originalMaskPNG
        layer.maskEnabled = true
        var project = CoverProject(width: 1, height: 1)
        project.dpi = 16
        project.layers = [layer]
        var undo = [project]
        var redo: [CoverProject] = []
        project.layers[0].maskData = editedMaskPNG

        CoverProjectHistory.undo(project: &project, undo: &undo, redo: &redo)
        XCTAssertEqual(project.layers.first?.maskData, originalMaskPNG)
        CoverProjectHistory.redo(project: &project, undo: &undo, redo: &redo)
        XCTAssertEqual(project.layers.first?.maskData, editedMaskPNG)

        let document = BOLDWriterDocument()
        document.metadata.coverProjects = [project]
        document.metadata.activeCoverProjectID = project.id
        let package = try BOLDWriterDocument.packageWrapper(text: document.text, metadata: document.metadata)
        let reopenedDocument = try BOLDWriterDocument(
            fileWrapper: package,
            contentType: .boldWriterDocument
        )
        let restored = try XCTUnwrap(reopenedDocument.metadata.coverProjects?.first)
        let restoredLayer = try XCTUnwrap(restored.layers.first)
        XCTAssertEqual(restoredLayer.imageData, source)
        XCTAssertEqual(
            try XCTUnwrap(CoverEditorEngine.decodedMask(try XCTUnwrap(restoredLayer.maskData), width: 16, height: 16)),
            editedMask
        )

        let rendered = try CoverArtwork.export(restored, format: "png-transparent")
        let renderedPixels = try XCTUnwrap(NSBitmapImageRep(data: rendered))
        XCTAssertLessThan(try XCTUnwrap(renderedPixels.colorAt(x: 8, y: 8)).alphaComponent, 1)
        XCTAssertGreaterThan(try XCTUnwrap(renderedPixels.colorAt(x: 0, y: 0)).alphaComponent, 0.99)
    }

    func testGradientMaskUndoNativeRoundTripAndTransparentExport() throws {
        let width = 180
        let height = 270
        let source = try CoverEditorEngine.filledImage(width: width, height: height, color: .systemBlue)
        let originalSource = source
        let originalMask = Data(repeating: 255, count: width * height)
        let editedMask = CoverEditorEngine.gradientMask(
            originalMask,
            width: width,
            height: height,
            start: CGPoint(x: 0, y: Double(height / 2)),
            end: CGPoint(x: Double(width - 1), y: Double(height / 2)),
            opacity: 1
        )
        let centerY = height / 2
        XCTAssertEqual(editedMask[centerY * width], 0)
        XCTAssertEqual(editedMask[centerY * width + width - 1], 255)

        var layer = try CoverArtwork.imageLayer(data: source, filename: "Gradient mask source", frame: CoverRect())
        let beforePNG = try XCTUnwrap(CoverEditorEngine.encodedMask(originalMask, width: width, height: height))
        let afterPNG = try XCTUnwrap(CoverEditorEngine.encodedMask(editedMask, width: width, height: height))
        layer.maskData = beforePNG
        var project = CoverProject(width: 1.8, height: 2.7)
        project.dpi = 100
        project.layers = [layer]
        var undo = [project]
        var redo: [CoverProject] = []
        project.layers[0].maskData = afterPNG

        CoverProjectHistory.undo(project: &project, undo: &undo, redo: &redo)
        XCTAssertEqual(project.layers[0].maskData, beforePNG)
        CoverProjectHistory.redo(project: &project, undo: &undo, redo: &redo)
        XCTAssertEqual(project.layers[0].maskData, afterPNG)
        XCTAssertEqual(project.layers[0].imageData, originalSource, "Gradient editing must never change the imported source raster.")

        let document = BOLDWriterDocument()
        document.metadata.coverProjects = [project]
        document.metadata.activeCoverProjectID = project.id
        let package = try BOLDWriterDocument.packageWrapper(text: document.text, metadata: document.metadata)
        let reopened = try BOLDWriterDocument(fileWrapper: package, contentType: .boldWriterDocument)
        let restored = try XCTUnwrap(reopened.metadata.coverProjects?.first)
        XCTAssertEqual(restored.layers[0].imageData, originalSource)
        XCTAssertEqual(
            try XCTUnwrap(CoverEditorEngine.decodedMask(try XCTUnwrap(restored.layers[0].maskData), width: width, height: height)),
            editedMask
        )

        let transparentPNG = try CoverArtwork.export(restored, format: "png-transparent")
        let output = try XCTUnwrap(NSBitmapImageRep(data: transparentPNG))
        XCTAssertEqual(output.pixelsWide, width)
        XCTAssertEqual(output.pixelsHigh, height)
        let leftAlpha = try XCTUnwrap(output.colorAt(x: 0, y: centerY)).alphaComponent
        let rightAlpha = try XCTUnwrap(output.colorAt(x: width - 1, y: centerY)).alphaComponent
        let middleAlpha = try XCTUnwrap(output.colorAt(x: width / 2, y: centerY)).alphaComponent
        XCTAssertLessThan(leftAlpha, 0.01)
        XCTAssertEqual(rightAlpha, 1, accuracy: 0.01)
        XCTAssertEqual(middleAlpha, Double(editedMask[centerY * width + width / 2]) / 255, accuracy: 0.03)

        let opaquePNG = try CoverArtwork.export(restored, format: "png")
        let opaqueOutput = try XCTUnwrap(NSBitmapImageRep(data: opaquePNG))
        XCTAssertEqual(opaqueOutput.pixelsWide, width)
        XCTAssertEqual(opaqueOutput.pixelsHigh, height)
        for y in 0..<height {
            for x in 0..<width {
                XCTAssertEqual(try XCTUnwrap(opaqueOutput.colorAt(x: x, y: y)).alphaComponent, 1, accuracy: 0.01)
            }
        }
        XCTAssertEqual(restored.layers[0].imageData, originalSource, "Regular export must preserve the imported source raster in the editable project.")

        if let fixturePath = ProcessInfo.processInfo.environment["BOLDWRITER_M5_FIXTURE_DIR"] {
            let directory = URL(fileURLWithPath: fixturePath, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try source.write(to: directory.appendingPathComponent("gradient-mask-source.png"), options: .atomic)
            try beforePNG.write(to: directory.appendingPathComponent("gradient-mask-before.png"), options: .atomic)
            try afterPNG.write(to: directory.appendingPathComponent("gradient-mask-after.png"), options: .atomic)
            try transparentPNG.write(to: directory.appendingPathComponent("gradient-mask-transparent-export.png"), options: .atomic)
            try opaquePNG.write(to: directory.appendingPathComponent("gradient-mask-regular-export.png"), options: .atomic)
            try package.write(to: directory.appendingPathComponent("gradient-mask-editable.boldwriter"), options: .atomic, originalContentsURL: nil)
        }
    }

    func testPublishingResolutionGradientMaskPersistsAndExportsAtFullSize() throws {
        let width = 1_800
        let height = 2_700
        let source = try CoverEditorEngine.filledImage(
            width: width,
            height: height,
            color: NSColor(srgbRed: 0.2, green: 0.48, blue: 0.82, alpha: 1)
        )
        let originalSource = source
        let originalMask = Data(repeating: 255, count: width * height)
        let editedMask = CoverEditorEngine.gradientMask(
            originalMask,
            width: width,
            height: height,
            start: CGPoint(x: 0, y: height / 2),
            end: CGPoint(x: width - 1, y: height / 2)
        )
        XCTAssertEqual(editedMask.count, width * height)
        XCTAssertEqual(editedMask[height / 2 * width], 0)
        XCTAssertEqual(editedMask[height / 2 * width + width / 2], 128)
        XCTAssertEqual(editedMask[height / 2 * width + width - 1], 255)

        var layer = try CoverArtwork.imageLayer(data: source, filename: "1800x2700 gradient fixture")
        layer.maskData = try XCTUnwrap(CoverEditorEngine.encodedMask(editedMask, width: width, height: height))
        var project = CoverProject(width: 18, height: 27)
        project.dpi = 100
        project.layers = [layer]

        let document = BOLDWriterDocument()
        document.metadata.coverProjects = [project]
        document.metadata.activeCoverProjectID = project.id
        let package = try BOLDWriterDocument.packageWrapper(text: document.text, metadata: document.metadata)
        let reopened = try BOLDWriterDocument(fileWrapper: package, contentType: .boldWriterDocument)
        let restored = try XCTUnwrap(reopened.metadata.coverProjects?.first)
        XCTAssertEqual(restored.layers[0].imageData, originalSource)
        XCTAssertEqual(
            try XCTUnwrap(
                CoverEditorEngine.decodedMask(
                    try XCTUnwrap(restored.layers[0].maskData),
                    width: width,
                    height: height
                )
            ),
            editedMask
        )

        let exported = try CoverArtwork.export(restored, format: "png-transparent")
        let pixels = try XCTUnwrap(NSBitmapImageRep(data: exported))
        XCTAssertEqual(pixels.pixelsWide, width)
        XCTAssertEqual(pixels.pixelsHigh, height)
        XCTAssertLessThan(try XCTUnwrap(pixels.colorAt(x: 0, y: height / 2)).alphaComponent, 0.01)
        XCTAssertEqual(
            try XCTUnwrap(pixels.colorAt(x: width - 1, y: height / 2)).alphaComponent,
            1,
            accuracy: 0.01
        )
    }
}
