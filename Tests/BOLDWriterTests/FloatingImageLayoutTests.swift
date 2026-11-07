import AppKit
import CryptoKit
import PDFKit
import XCTest
@testable import BOLDWriter

final class FloatingImageLayoutTests: XCTestCase {
    func testImportedWordPolygonControlsNativeTightWrapLanes() throws {
        let geometry = try PageGeometry(PageSettings())
        let source = try opaquePNG()
        let triangle = FloatingImage.WrapPolygon(edited: true, points: [
            .init(x: 10_800, y: 0), .init(x: 21_600, y: 21_600), .init(x: 0, y: 21_600)
        ])
        let image = FloatingImage(assetName: "opaque-triangle.png", imageData: source,
                                  pageIndex: 0, anchor: .page, x: 100, y: 100,
                                  width: 120, height: 120, wrapping: .tight,
                                  wrapDistance: 0, wrapPolygon: triangle)
        let paths = FloatingImageLayout.exclusionPaths(images: [image], pageIndex: 0,
                                                        geometry: geometry, columnIndex: 0,
                                                        font: NSFont.systemFont(ofSize: 12))
        XCTAssertGreaterThan(paths.count, 2)
        let first = try XCTUnwrap(paths.first?.bounds)
        let last = try XCTUnwrap(paths.last?.bounds)
        XCTAssertLessThan(first.width, last.width,
                          "The editor/PDF text lane must follow Word's edited triangle rather than the opaque source rectangle.")
        var alphaDerived = image
        alphaDerived.wrapPolygon = nil
        let generated = FloatingImageLayout.exclusionPaths(images: [alphaDerived], pageIndex: 0,
                                                            geometry: geometry, columnIndex: 0,
                                                            font: NSFont.systemFont(ofSize: 12))
        XCTAssertGreaterThan(try XCTUnwrap(generated.first?.bounds.width), first.width)
        try FloatingImage.validate([image], textLength: 0)
        let decoded = try JSONDecoder().decode(FloatingImage.self, from: JSONEncoder().encode(image))
        XCTAssertEqual(decoded.wrapPolygon, triangle)
        var malformed = image
        malformed.wrapPolygon = .init(edited: true, points: [
            .init(x: 0, y: 0), .init(x: 1_000, y: 1_000), .init(x: 2_000, y: 2_000)
        ])
        XCTAssertThrowsError(try FloatingImage.validate([malformed], textLength: 0),
                             "A zero-area polygon must not leave the editor with no text exclusion.")
        var oversized = image
        oversized.height = 20_000
        let bounded = FloatingImageLayout.exclusionPaths(images: [oversized], pageIndex: 0,
                                                          geometry: geometry, columnIndex: 0,
                                                          font: NSFont.systemFont(ofSize: 12))
        XCTAssertFalse(bounded.isEmpty)
        XCTAssertTrue(bounded.allSatisfy { $0.bounds.maxY <= geometry.contentSize.height + 48 },
                      "Out-of-page Word polygon points must not create unbounded text exclusions.")
    }

    func testWordFloatingSourceCropKeepsExactEdgesAndRejectsEmptyGeometry() throws {
        let crop = FloatingImage.SourceCrop(left: 12_000, top: 23_000, right: 34_000, bottom: 11_000)
        XCTAssertTrue(crop.hasValidGeometry)
        XCTAssertEqual(crop.sourceRect(in: CGSize(width: 200, height: 100)),
                       CGRect(x: 24, y: 11, width: 108, height: 66))
        let data = try opaquePNG()
        let image = FloatingImage(assetName: "crop.png", imageData: data,
                                  x: 24, y: 36, width: 100, height: 50,
                                  sourceCrop: crop)
        try FloatingImage.validate([image], textLength: 0)
        let restored = try JSONDecoder().decode(FloatingImage.self, from: JSONEncoder().encode(image))
        XCTAssertEqual(restored.sourceCrop, crop)
        var invalid = image
        invalid.sourceCrop = .init(left: 60_000, right: 40_000)
        XCTAssertThrowsError(try FloatingImage.validate([invalid], textLength: 0))
    }

    func testAutomaticTextFlowSwitchesBetweenSquareAndOverlayWithoutChangingGeometry() throws {
        var image = FloatingImage(assetName: "flow.png", imageData: try opaquePNG(),
                                  x: 34, y: 56, width: 140, height: 90, wrapping: .none)
        let originalID = image.id
        XCTAssertFalse(image.automaticTextFlowEnabled)

        image.setAutomaticTextFlow(true)
        XCTAssertEqual(image.wrapping, .square)
        XCTAssertTrue(image.automaticTextFlowEnabled)
        XCTAssertEqual(image.x, 34); XCTAssertEqual(image.y, 56)
        XCTAssertEqual(image.width, 140); XCTAssertEqual(image.height, 90)
        XCTAssertEqual(image.id, originalID)

        image.wrapping = .tight
        image.setAutomaticTextFlow(true)
        XCTAssertEqual(image.wrapping, .tight, "Turning on the simple switch must preserve an explicitly selected wrap mode.")
        image.setAutomaticTextFlow(false)
        XCTAssertEqual(image.wrapping, .none, "Turning the switch off restores independent overlay placement.")
        XCTAssertFalse(image.automaticTextFlowEnabled)
        XCTAssertEqual(image.x, 34); XCTAssertEqual(image.y, 56)
        XCTAssertEqual(image.width, 140); XCTAssertEqual(image.height, 90)
        XCTAssertEqual(image.id, originalID)
    }

    func testFloatingImageKeyboardMovementHasPredictableModifiersAndPreservesEditorShortcuts() {
        XCTAssertEqual(FloatingImageKeyboardMovement.delta(keyCode: 123, modifiers: []), CGPoint(x: -1, y: 0))
        XCTAssertEqual(FloatingImageKeyboardMovement.delta(keyCode: 124, modifiers: [.shift, .numericPad]), CGPoint(x: 10, y: 0))
        XCTAssertEqual(FloatingImageKeyboardMovement.delta(keyCode: 125, modifiers: [.option, .numericPad]), CGPoint(x: 0, y: 0.1))
        XCTAssertEqual(FloatingImageKeyboardMovement.delta(keyCode: 126, modifiers: [.shift, .option]), CGPoint(x: 0, y: -0.1),
                       "Option is the fine-position modifier and takes precedence over the coarse Shift increment.")
        XCTAssertNil(FloatingImageKeyboardMovement.delta(keyCode: 123, modifiers: [.command]),
                     "Command-arrow remains available to normal editor navigation.")
        XCTAssertNil(FloatingImageKeyboardMovement.delta(keyCode: 124, modifiers: [.control]))
        XCTAssertNil(FloatingImageKeyboardMovement.delta(keyCode: 36, modifiers: []))
    }

    func testExportedFloatingImagePDFTransformMatchesPageGeometry() throws {
        let settings = PageSettings()
        let geometry = try PageGeometry(settings)
        let text = NSAttributedString(string: "PDF geometry proof paragraph.",
                                      attributes: [.font: NSFont.systemFont(ofSize: 12)])
        let rotation = 27.0
        let image = FloatingImage(assetName: "geometry.png", imageData: try opaquePNG(),
                                  pageIndex: 0, anchor: .page,
                                  x: 123, y: 147, width: 84, height: 61,
                                  rotationDegrees: rotation, layer: .inFrontOfText)

        let data = try PDFExporter.data(from: text, settings: settings, floatingImages: [image])
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertEqual(pdf.pageCount, 1)
        let mediaBox = try XCTUnwrap(pdf.page(at: 0)).bounds(for: .mediaBox)
        XCTAssertEqual(mediaBox.width, geometry.size.width, accuracy: 0.01)
        XCTAssertEqual(mediaBox.height, geometry.size.height, accuracy: 0.01)

        let placements = PDFImageGeometryInspection.placements(in: pdf)
        XCTAssertEqual(placements.count, 1, "The image draw operator must expose one measurable PDF transform.")
        let placement = try XCTUnwrap(placements.first)
        XCTAssertEqual(placement.pageIndex, 0)

        let rect = CGRect(x: image.x, y: image.y, width: image.width, height: image.height)
        let rotationTransform = CGAffineTransform(translationX: rect.midX, y: rect.midY)
            .rotated(by: rotation * .pi / 180)
            .translatedBy(x: -rect.midX, y: -rect.midY)
        let expectedCorners = [CGPoint(x: rect.minX, y: rect.minY),
                               CGPoint(x: rect.maxX, y: rect.minY),
                               CGPoint(x: rect.maxX, y: rect.maxY),
                               CGPoint(x: rect.minX, y: rect.maxY)]
            .map { point -> CGPoint in
                let topOrigin = point.applying(rotationTransform)
                return CGPoint(x: topOrigin.x, y: geometry.size.height - topOrigin.y)
            }
        let expected = CGRect(x: expectedCorners.map(\.x).min()!, y: expectedCorners.map(\.y).min()!,
                              width: expectedCorners.map(\.x).max()! - expectedCorners.map(\.x).min()!,
                              height: expectedCorners.map(\.y).max()! - expectedCorners.map(\.y).min()!)
        XCTAssertEqual(placement.bounds.minX, expected.minX, accuracy: 0.25)
        XCTAssertEqual(placement.bounds.minY, expected.minY, accuracy: 0.25)
        XCTAssertEqual(placement.bounds.width, expected.width, accuracy: 0.25)
        XCTAssertEqual(placement.bounds.height, expected.height, accuracy: 0.25)
        XCTAssertTrue(try XCTUnwrap(pdf.page(at: 0)).string?.contains("PDF geometry proof paragraph") == true)
    }

    @MainActor
    func testParagraphAnchoredEditorAndPDFImageBoundsAgreeNumerically() throws {
        var settings = PageSettings()
        settings.paper = .custom
        settings.customPaperSize = CGSize(width: 396, height: 612) // 5.5 × 8.5 in.
        settings.topMargin = 54
        settings.bottomMargin = 54
        settings.leftMargin = 54
        settings.rightMargin = 54
        let source = NSAttributedString(
            string: String(repeating: "A paragraph anchor must resolve through the production TextKit page layout. ", count: 28),
            attributes: [.font: NSFont.systemFont(ofSize: 12)])
        let anchorLocation = (source.string as NSString).range(of: "paragraph anchor").location
        let image = FloatingImage(assetName: "anchor-geometry.png", imageData: try opaquePNG(),
                                  pageIndex: 0, anchor: .page, x: 72, y: 96,
                                  width: 80, height: 56, rotationDegrees: 13,
                                  wrapping: .none, layer: .inFrontOfText)

        let canvas = PaginatedEditor(text: source)
        canvas.configure(printLayout: true, settings: settings,
                         sections: [DocumentSection(location: 0, page: settings)],
                         zoom: 1.25, viewportWidth: 920)
        canvas.finishPagination()
        XCTAssertNil(canvas.lastLayoutError)
        var anchored = image
        canvas.setAnchorOffsets(for: &anchored, anchor: .paragraph, location: anchorLocation)
        canvas.setFloatingImages([anchored])
        canvas.finishPagination()
        XCTAssertNil(canvas.lastLayoutError)

        let editorImage = try XCTUnwrap(canvas.resolvedFloatingImage(anchored))
        let editorOrigin = try XCTUnwrap(canvas.resolvedPageOrigin(for: anchored))
        XCTAssertEqual(editorImage.pageIndex, 0)

        let pdfData = try PDFExporter.data(from: source, settings: settings, floatingImages: [anchored])
        let pdf = try XCTUnwrap(PDFDocument(data: pdfData))
        XCTAssertEqual(pdf.pageCount, canvas.pages.count)
        let page = try XCTUnwrap(pdf.page(at: editorImage.pageIndex))
        let mediaBox = page.bounds(for: .mediaBox)
        XCTAssertEqual(mediaBox.width, 396, accuracy: 0.01)
        XCTAssertEqual(mediaBox.height, 612, accuracy: 0.01)

        let placement = try XCTUnwrap(PDFImageGeometryInspection.placements(in: pdf)
            .first(where: { $0.pageIndex == editorImage.pageIndex }))
        let editorRect = CGRect(x: editorOrigin.x, y: editorOrigin.y,
                                width: editorImage.width, height: editorImage.height)
        let rotation = CGAffineTransform(translationX: editorRect.midX, y: editorRect.midY)
            .rotated(by: editorImage.rotationDegrees * .pi / 180)
            .translatedBy(x: -editorRect.midX, y: -editorRect.midY)
        let pdfCorners = [CGPoint(x: editorRect.minX, y: editorRect.minY),
                          CGPoint(x: editorRect.maxX, y: editorRect.minY),
                          CGPoint(x: editorRect.maxX, y: editorRect.maxY),
                          CGPoint(x: editorRect.minX, y: editorRect.maxY)]
            .map { point -> CGPoint in
                let editorPoint = point.applying(rotation)
                return CGPoint(x: editorPoint.x, y: mediaBox.height - editorPoint.y)
            }
        let xs = pdfCorners.map { $0.x }
        let ys = pdfCorners.map { $0.y }
        let expected = CGRect(x: xs.min()!, y: ys.min()!,
                              width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        let deltas = (abs(placement.bounds.minX - expected.minX),
                      abs(placement.bounds.minY - expected.minY),
                      abs(placement.bounds.width - expected.width),
                      abs(placement.bounds.height - expected.height))
        print("PDF_GEOMETRY paragraph-anchor page=\(placement.pageIndex + 1) editor=\(editorRect) pdf=\(placement.bounds) delta_pt=\(deltas)")
        if let directory = ProcessInfo.processInfo.environment["BOLD_PDF_GEOMETRY_EVIDENCE"] {
            let root = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try pdfData.write(to: root.appendingPathComponent("paragraph-anchor-5.5x8.5.pdf"))
            let measurement: [String: Any] = [
                "page": placement.pageIndex + 1,
                "mediaBoxPoints": [mediaBox.width, mediaBox.height],
                "editorTopOriginRectPoints": [editorRect.minX, editorRect.minY, editorRect.width, editorRect.height],
                "pdfLowerOriginBoundsPoints": [placement.bounds.minX, placement.bounds.minY, placement.bounds.width, placement.bounds.height],
                "absoluteDeltasPoints": [deltas.0, deltas.1, deltas.2, deltas.3],
                "rotationDegrees": editorImage.rotationDegrees,
                "anchor": "paragraph",
                "wrap": "none"
            ]
            let bytes = try JSONSerialization.data(withJSONObject: measurement, options: [.prettyPrinted, .sortedKeys])
            try bytes.write(to: root.appendingPathComponent("paragraph-anchor-5.5x8.5-geometry.json"))
        }
        XCTAssertEqual(placement.bounds.minX, expected.minX, accuracy: 0.25)
        XCTAssertEqual(placement.bounds.minY, expected.minY, accuracy: 0.25)
        XCTAssertEqual(placement.bounds.width, expected.width, accuracy: 0.25)
        XCTAssertEqual(placement.bounds.height, expected.height, accuracy: 0.25)
        XCTAssertTrue(try XCTUnwrap(page.string).contains("paragraph anchor"))
    }

    func testPDFImageTransformMatchesPhysicalGeometryAcrossWrapPolicies() throws {
        let settings = PageSettings()
        let geometry = try PageGeometry(settings)
        let source = NSAttributedString(
            string: String(repeating: "Publishing geometry must remain physically stable around floating artwork. ", count: 36),
            attributes: [.font: NSFont.systemFont(ofSize: 12)])
        let modes: [(FloatingImage.Wrapping, FloatingImage.WrapSide)] =
            [(.none, .both)] + FloatingImage.WrapSide.allCases.flatMap { side in
                [(FloatingImage.Wrapping.square, side), (.tight, side)]
            } + [(.topAndBottom, .both)]
        for (wrapping, side) in modes {
            let imageData = wrapping == .tight ? try rgbaPNG(opaquePixels: [18, 25, 26, 33, 34, 41]) : try opaquePNG()
            let image = FloatingImage(assetName: "matrix.png", imageData: imageData,
                                      pageIndex: 0, anchor: .page, x: 94, y: 116,
                                      width: 106, height: 74, rotationDegrees: 19,
                                      wrapping: wrapping, wrapDistance: 8, wrapSide: side,
                                      layer: .behindText)
            let pdfData = try PDFExporter.data(from: source, settings: settings, floatingImages: [image])
            let pdf = try XCTUnwrap(PDFDocument(data: pdfData))
            let page = try XCTUnwrap(pdf.page(at: 0))
            let media = page.bounds(for: .mediaBox)
            XCTAssertEqual(media.width, geometry.size.width, accuracy: 0.01)
            XCTAssertEqual(media.height, geometry.size.height, accuracy: 0.01)
            let placements = PDFImageGeometryInspection.placements(in: pdf)
            XCTAssertEqual(placements.count, 1, "Expected one image draw for \(wrapping)/\(side).")
            let placement = try XCTUnwrap(placements.first)
            let rect = CGRect(x: image.x, y: image.y, width: image.width, height: image.height)
            let rotate = CGAffineTransform(translationX: rect.midX, y: rect.midY)
                .rotated(by: image.rotationDegrees * .pi / 180)
                .translatedBy(x: -rect.midX, y: -rect.midY)
            let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                           CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
                .map { point -> CGPoint in
                    let rotated = point.applying(rotate)
                    return CGPoint(x: rotated.x, y: media.height - rotated.y)
                }
            let xs = corners.map { $0.x }
            let ys = corners.map { $0.y }
            let expected = CGRect(x: xs.min()!, y: ys.min()!,
                                  width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
            XCTAssertEqual(placement.bounds.minX, expected.minX, accuracy: 0.25, "\(wrapping)/\(side)")
            XCTAssertEqual(placement.bounds.minY, expected.minY, accuracy: 0.25, "\(wrapping)/\(side)")
            XCTAssertEqual(placement.bounds.width, expected.width, accuracy: 0.25, "\(wrapping)/\(side)")
            XCTAssertEqual(placement.bounds.height, expected.height, accuracy: 0.25, "\(wrapping)/\(side)")
            print("PDF_GEOMETRY mode=\(wrapping) side=\(side) page=1 bounds=\(placement.bounds)")
        }
    }

    @MainActor
    func testProductionEditorTextLinesMatchPDFLineGeometry() throws {
        var settings = PageSettings()
        settings.paper = .custom
        settings.customPaperSize = CGSize(width: 396, height: 612)
        settings.topMargin = 54
        settings.bottomMargin = 54
        settings.leftMargin = 54
        settings.rightMargin = 54
        let source = NSAttributedString(
            string: String(repeating: "The production editor and PDF must place each readable line at the same physical position. ", count: 6),
            attributes: [.font: NSFont.systemFont(ofSize: 11)])
        let image = FloatingImage(assetName: "line-proof.png", imageData: try opaquePNG(),
                                  x: 62, y: 93, width: 82, height: 70,
                                  wrapping: .square, wrapDistance: 5,
                                  layer: .behindText)
        let canvas = PaginatedEditor(text: source)
        canvas.setFloatingImages([image])
        canvas.configure(printLayout: true, settings: settings,
                         sections: [DocumentSection(location: 0, page: settings)],
                         zoom: 1.5, viewportWidth: 1000)
        canvas.finishPagination()
        XCTAssertNil(canvas.lastLayoutError)

        let containerIndex = try XCTUnwrap(canvas.pageContainerIndices[0].first)
        let container = canvas.flow.manager.textContainers[containerIndex]
        let manager = canvas.flow.manager
        let glyphRange = manager.glyphRange(for: container)
        var editorLines: [(text: String, rect: CGRect)] = []
        var glyph = glyphRange.location
        while glyph < NSMaxRange(glyphRange) {
            var lineGlyphRange = NSRange(location: 0, length: 0)
            let lineRect = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &lineGlyphRange)
            let charRange = manager.characterRange(forGlyphRange: lineGlyphRange, actualGlyphRange: nil)
            let lineText = (source.string as NSString).substring(with: charRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !lineText.isEmpty {
                let pageOrigin = try XCTUnwrap(canvas.pages[0].pageGeometry).contentOrigin
                editorLines.append((lineText, lineRect.offsetBy(dx: pageOrigin.x, dy: pageOrigin.y)))
            }
            let next = NSMaxRange(lineGlyphRange)
            guard next > glyph else { break }
            glyph = next
        }

        let pdfData = try PDFExporter.data(from: source, settings: settings, floatingImages: [image])
        let pdf = try XCTUnwrap(PDFDocument(data: pdfData))
        let page = try XCTUnwrap(pdf.page(at: 0))
        let pageString = try XCTUnwrap(page.string)
        let wholePage = try XCTUnwrap(page.selection(for: NSRange(location: 0, length: (pageString as NSString).length)))
        let pdfLines = wholePage.selectionsByLine().compactMap { selection -> (String, CGRect)? in
            guard let line = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !line.isEmpty, !line.hasPrefix("BOLD Writer") else { return nil }
            return (line, selection.bounds(for: page))
        }
        XCTAssertEqual(editorLines.count, pdfLines.count,
                       "The editor and PDF must use the same line breaks for the wrapped paragraph.")
        for (index, editorLine) in editorLines.enumerated() where pdfLines.indices.contains(index) {
            let pdfLine = pdfLines[index]
            XCTAssertEqual(editorLine.text, pdfLine.0,
                           "Line content differs at line \(index + 1).")
            let pdfTop = page.bounds(for: .mediaBox).height - pdfLine.1.maxY
            let deltaY = abs(editorLine.rect.minY - pdfTop)
            let deltaX = abs(editorLine.rect.minX - pdfLine.1.minX)
            print("PDF_TEXT_GEOMETRY line=\(index + 1) editorTop=\(editorLine.rect.minY) pdfTop=\(pdfTop) deltaY_pt=\(deltaY) deltaX_pt=\(deltaX)")
            XCTAssertLessThanOrEqual(deltaY, 2.0, "PDF/editor line top differs by \(deltaY) pt on line \(index + 1).")
            XCTAssertLessThanOrEqual(deltaX, 2.0, "PDF/editor line start differs by \(deltaX) pt on line \(index + 1).")
        }
    }

    @MainActor
    func testMultiPageAnchoredEditorImagesMatchPDFContentStreamGeometry() throws {
        _ = NSApplication.shared
        let paragraph = "Multi-page geometry acceptance follows this anchored paragraph across physical pages.\n"
        let source = NSAttributedString(
            string: String(repeating: paragraph, count: 520),
            attributes: [.font: NSFont.systemFont(ofSize: 11)]
        )
        let base = PaginatedEditor(text: source)
        base.configure(printLayout: true, settings: PageSettings(), zoom: 1, viewportWidth: 900)
        base.finishPagination()
        XCTAssertNil(base.lastLayoutError)
        XCTAssertGreaterThanOrEqual(base.pages.count, 10,
                                    "The fixture must exercise multiple physical pages.")

        let anchors: [(paragraphNumber: Int, anchor: FloatingImage.Anchor, characterOffset: Int,
                       wrapping: FloatingImage.Wrapping, side: FloatingImage.WrapSide, layer: FloatingImage.Layer)] = [
            (24, .paragraph, 0, .square, .both, .behindText),
            (218, .character, 12, .tight, .largestSide, .inFrontOfText),
            (497, .paragraph, 0, .topAndBottom, .both, .behindText)
        ]
        var images: [FloatingImage] = []
        for (index, specification) in anchors.enumerated() {
            let baseLocation = paragraph.utf16.count * (specification.paragraphNumber - 1)
            let location = baseLocation + specification.characterOffset
            let target = try XCTUnwrap(base.physicalAnchorOrigin(anchor: specification.anchor, location: location))
            let data = specification.wrapping == .tight
                ? try rgbaPNG(opaquePixels: [18, 25, 26, 33, 34, 41])
                : try opaquePNG()
            images.append(FloatingImage(
                assetName: "multi-page-\(index).png", imageData: data,
                pageIndex: target.pageIndex, anchor: specification.anchor, anchorLocation: location,
                x: target.origin.x + 22, y: target.origin.y + 16,
                anchorOffsetX: 22, anchorOffsetY: 16,
                width: 58, height: 42, rotationDegrees: Double(index * 7),
                wrapping: specification.wrapping, wrapDistance: 5,
                wrapSide: specification.side, layer: specification.layer
            ))
        }

        let editor = PaginatedEditor(text: source)
        editor.setFloatingImages(images)
        editor.configure(printLayout: true, settings: PageSettings(), zoom: 1, viewportWidth: 900)
        editor.finishPagination()
        XCTAssertNil(editor.lastLayoutError)
        let resolved = try images.map { image -> (FloatingImage, CGRect) in
            let placed = try XCTUnwrap(editor.resolvedFloatingImage(image))
            let origin = try XCTUnwrap(editor.resolvedPageOrigin(for: image))
            return (placed, CGRect(x: origin.x, y: origin.y, width: placed.width, height: placed.height))
        }
        XCTAssertEqual(Set(resolved.map { $0.0.pageIndex }).count, resolved.count,
                       "Each image must occupy a distinct page so its PDF draw transform is unambiguous.")

        var pdfPageRanges: [NSRange] = []
        let pdfData = try PDFExporter.data(from: source, settings: PageSettings(),
                                           pageRangeSink: { pdfPageRanges = $0 }, floatingImages: images)
        let pdf = try XCTUnwrap(PDFDocument(data: pdfData))
        XCTAssertEqual(pdf.pageCount, editor.pages.count)
        XCTAssertEqual(pdfPageRanges, editor.pageRanges,
                       "Editor and PDF must allocate identical source ranges to every physical page.")
        let placements = PDFImageGeometryInspection.placements(in: pdf)
        XCTAssertEqual(placements.count, images.count)

        for (image, editorRect) in resolved {
            let expectedPage = image.pageIndex
            let placement = try XCTUnwrap(placements.first(where: { $0.pageIndex == expectedPage }))
            let page = try XCTUnwrap(pdf.page(at: expectedPage))
            let media = page.bounds(for: .mediaBox)
            let rotate = CGAffineTransform(translationX: editorRect.midX, y: editorRect.midY)
                .rotated(by: image.rotationDegrees * .pi / 180)
                .translatedBy(x: -editorRect.midX, y: -editorRect.midY)
            let corners = [CGPoint(x: editorRect.minX, y: editorRect.minY),
                           CGPoint(x: editorRect.maxX, y: editorRect.minY),
                           CGPoint(x: editorRect.maxX, y: editorRect.maxY),
                           CGPoint(x: editorRect.minX, y: editorRect.maxY)]
                .map { point -> CGPoint in
                    let rotated = point.applying(rotate)
                    return CGPoint(x: rotated.x, y: media.height - rotated.y)
                }
            let xs = corners.map(\.x), ys = corners.map(\.y)
            let expected = CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!,
                                  height: ys.max()! - ys.min()!)
            let delta = [abs(placement.bounds.minX - expected.minX),
                         abs(placement.bounds.minY - expected.minY),
                         abs(placement.bounds.width - expected.width),
                         abs(placement.bounds.height - expected.height)].max()!
            print("PDF_MULTIPAGE_GEOMETRY id=\(image.id) page=\(expectedPage + 1) anchor=\(image.anchor) wrap=\(image.wrapping) side=\(String(describing: image.wrapSide)) max_delta_pt=\(delta)")
            XCTAssertLessThanOrEqual(delta, 0.25,
                                     "Image \(image.id) on page \(expectedPage + 1) differs by \(delta) pt.")
        }
    }

    func testSquareAndTopBottomUseTextKitExclusionGeometryAndReflow() throws {
        let geometry = try PageGeometry(PageSettings())
        let image = FloatingImage(assetName: "test.png", imageData: try opaquePNG(),
                                  x: 200, y: 120, width: 180, height: 180,
                                  wrapping: .square, wrapDistance: 6)
        let paths = FloatingImageLayout.exclusionPaths(images: [image], pageIndex: 0,
                                                       geometry: geometry, columnIndex: 0)
        XCTAssertEqual(paths.count, 1)
        XCTAssertEqual(paths[0].bounds.width, 192, accuracy: 0.01)
        XCTAssertEqual(paths[0].bounds.height, 192, accuracy: 0.01)

        let text = NSAttributedString(string: String(repeating: "Text flows around artwork. ", count: 120),
                                      attributes: [.font: NSFont.systemFont(ofSize: 12)])
        let plainFlow = PageLayout(text: text)
        let plain = try plainFlow.layout(plainFlow.addContainer(size: geometry.contentSize), geometry: geometry)
        let wrappedFlow = PageLayout(text: text)
        let container = wrappedFlow.addContainer(size: geometry.contentSize)
        container.exclusionPaths = paths
        let wrapped = try wrappedFlow.layout(container, geometry: geometry)
        XCTAssertLessThan(wrapped.characters.length, plain.characters.length,
                          "The physical page's TextKit layout must reserve the image's wrapping contour.")

        var independent = image
        independent.wrapping = .none
        XCTAssertTrue(FloatingImageLayout.exclusionPaths(images: [independent], pageIndex: 0,
                                                         geometry: geometry, columnIndex: 0).isEmpty)
        let independentFlow = PageLayout(text: text)
        let independentLayout = try independentFlow.layout(independentFlow.addContainer(size: geometry.contentSize),
                                                           geometry: geometry)
        XCTAssertEqual(independentLayout.characters, plain.characters,
                       "No-wrap images must not alter line flow or page character allocation.")

        var plainPDFRanges: [NSRange] = []
        _ = try PDFExporter.data(from: text, settings: PageSettings(), pageRangeSink: { plainPDFRanges = $0 })
        var wrappedPDFRanges: [NSRange] = []
        _ = try PDFExporter.data(from: text, settings: PageSettings(), pageRangeSink: { wrappedPDFRanges = $0 },
                                 floatingImages: [image])
        XCTAssertNotEqual(wrappedPDFRanges, plainPDFRanges,
                          "PDF pagination must use the same wrapping exclusions as its TextKit page layout.")

        var topBottom = image
        topBottom.wrapping = .topAndBottom
        let fullWidth = FloatingImageLayout.exclusionPaths(images: [topBottom], pageIndex: 0,
                                                           geometry: geometry, columnIndex: 0)
        XCTAssertEqual(fullWidth.count, 1)
        XCTAssertEqual(fullWidth[0].bounds.width, geometry.columnWidth, accuracy: 0.01)
    }

    func testSquareWrapMovesTextBelowWhenBothSideLanesAreUnusable() throws {
        let geometry = try PageGeometry(PageSettings())
        let font = NSFont.systemFont(ofSize: 12)
        let minimumWidth = FloatingImageLayout.minimumUsableTextWidth(font: font,
                                                                       columnWidth: geometry.columnWidth)
        let image = FloatingImage(assetName: "wide.png", imageData: try opaquePNG(),
                                  x: 90, y: 120, width: 430, height: 150,
                                  wrapping: .square, wrapDistance: 6)
        let paths = FloatingImageLayout.exclusionPaths(images: [image], pageIndex: 0,
                                                       geometry: geometry, columnIndex: 0,
                                                       font: font)
        XCTAssertEqual(paths.count, 1)
        XCTAssertEqual(paths[0].bounds.minX, 0, accuracy: 0.01)
        XCTAssertEqual(paths[0].bounds.maxX, geometry.columnWidth, accuracy: 0.01,
                       "When both side lanes are narrower than the font-aware minimum, the whole text column must clear the image.")
        XCTAssertGreaterThan(minimumWidth, 0)

        let paragraph = String(repeating: "Acceptance placement remains readable around a floating photograph. ", count: 18)
        let text = NSAttributedString(string: paragraph, attributes: [.font: font])
        let flow = PageLayout(text: text)
        let container = flow.addContainer(size: geometry.contentSize)
        container.exclusionPaths = paths
        let result = try flow.layout(container, geometry: geometry)
        XCTAssertEqual(flow.storage.string, paragraph,
                       "Layout may reflow the paragraph but must retain every source character in order.")
        XCTAssertEqual(result.characters.length, text.length)
        var fragmentsBesideImage: [CGRect] = []
        flow.manager.enumerateLineFragments(forGlyphRange: result.glyphs) { fragment, _, _, _, _ in
            if fragment.minY < paths[0].bounds.maxY && fragment.maxY > paths[0].bounds.minY {
                fragmentsBesideImage.append(fragment)
            }
        }
        XCTAssertTrue(fragmentsBesideImage.isEmpty,
                      "Text should move below the image instead of fragmenting into a narrow side column.")
    }

    func testSquareWrapKeepsOnlyFontUsableSideLanes() throws {
        let geometry = try PageGeometry(PageSettings())
        let font = NSFont.systemFont(ofSize: 12)
        let image = FloatingImage(assetName: "edge.png", imageData: try opaquePNG(),
                                  x: 100, y: 120, width: 340, height: 150,
                                  wrapping: .square, wrapDistance: 6)
        let path = try XCTUnwrap(FloatingImageLayout.exclusionPaths(images: [image], pageIndex: 0,
                                                                    geometry: geometry, columnIndex: 0,
                                                                    font: font).first)
        XCTAssertEqual(path.bounds.minX, 0, accuracy: 0.01,
                       "The narrow left lane should close to the column edge.")
        XCTAssertLessThan(geometry.columnWidth - path.bounds.maxX,
                          geometry.columnWidth * 0.45,
                          "The opposite side should remain available when its physical measure clears the font-aware threshold.")
        XCTAssertGreaterThan(geometry.columnWidth - path.bounds.maxX,
                             FloatingImageLayout.minimumUsableTextWidth(font: font,
                                                                        columnWidth: geometry.columnWidth))

        let largeFontWidth = FloatingImageLayout.minimumUsableTextWidth(font: NSFont.systemFont(ofSize: 24),
                                                                         columnWidth: geometry.columnWidth)
        XCTAssertGreaterThan(largeFontWidth,
                             FloatingImageLayout.minimumUsableTextWidth(font: font,
                                                                        columnWidth: geometry.columnWidth),
                             "The minimum must scale with physical font metrics rather than screen zoom.")
    }

    func testSquareWrapSidePoliciesSelectReadableLanesAndFallBelowWhenNeeded() throws {
        let geometry = try PageGeometry(PageSettings())
        let font = NSFont.systemFont(ofSize: 12)
        let data = try opaquePNG()
        let both = FloatingImage(assetName: "side.png", imageData: data, x: 220, y: 100,
                                 width: 140, height: 100, wrapping: .square, wrapDistance: 6,
                                 wrapSide: .both)
        func bounds(_ side: FloatingImage.WrapSide, image: FloatingImage) throws -> CGRect {
            var candidate = image
            candidate.wrapSide = side
            return try XCTUnwrap(FloatingImageLayout.exclusionPaths(images: [candidate], pageIndex: 0,
                                                                     geometry: geometry, columnIndex: 0,
                                                                     font: font).first).bounds
        }
        let bothBounds = try bounds(.both, image: both)
        XCTAssertGreaterThan(bothBounds.minX, 0)
        XCTAssertLessThan(bothBounds.maxX, geometry.columnWidth)
        let left = try bounds(.leftOnly, image: both)
        XCTAssertGreaterThan(left.minX, 0)
        XCTAssertEqual(left.maxX, geometry.columnWidth, accuracy: 0.01)
        let right = try bounds(.rightOnly, image: both)
        XCTAssertEqual(right.minX, 0, accuracy: 0.01)
        XCTAssertLessThan(right.maxX, geometry.columnWidth)
        let automatic = try bounds(.automatic, image: both)
        XCTAssertEqual(automatic, bothBounds, "Automatic keeps both readable lanes when both are available.")

        var oneUsableSide = both
        oneUsableSide.x = 80
        oneUsableSide.width = 210
        let largest = try bounds(.largestSide, image: oneUsableSide)
        XCTAssertEqual(largest.minX, 0, accuracy: 0.01,
                       "Largest-side chooses the wider right lane when the left lane is below the readable minimum.")
        XCTAssertLessThan(largest.maxX, geometry.columnWidth)
        let autoOneSide = try bounds(.automatic, image: oneUsableSide)
        XCTAssertEqual(autoOneSide, largest)

        var noUsableSide = both
        noUsableSide.x = 100
        noUsableSide.width = Double(geometry.columnWidth - 120)
        let below = try bounds(.leftOnly, image: noUsableSide)
        XCTAssertEqual(below.minX, 0, accuracy: 0.01)
        XCTAssertEqual(below.maxX, geometry.columnWidth, accuracy: 0.01,
                       "When the requested text lane is too narrow, the image excludes the full column until text can continue below.")
    }

    func testAsymmetricTextDistancesShapeSquareAndTopBottomExclusions() throws {
        let geometry = try PageGeometry(PageSettings())
        let distances = FloatingImage.WrapDistances(top: 2, right: 12, bottom: 8, left: 4)
        var image = FloatingImage(assetName: "asymmetric.png", imageData: try opaquePNG(),
                                  x: 220, y: 100, width: 140, height: 100,
                                  wrapping: .square, wrapDistance: 2, wrapDistances: distances)

        let square = try XCTUnwrap(FloatingImageLayout.exclusionPaths(
            images: [image], pageIndex: 0, geometry: geometry, columnIndex: 0,
            font: NSFont.systemFont(ofSize: 12)
        ).first)
        let columnLocalX = CGFloat(image.x) - geometry.columnOriginX(for: 0)
        let contentLocalY = CGFloat(image.y) - geometry.contentOrigin.y
        XCTAssertEqual(square.bounds.minX, columnLocalX - 4, accuracy: 0.01)
        XCTAssertEqual(square.bounds.maxX, columnLocalX + CGFloat(image.width) + 12, accuracy: 0.01)
        XCTAssertEqual(square.bounds.minY, contentLocalY - 2, accuracy: 0.01)
        XCTAssertEqual(square.bounds.maxY, contentLocalY + CGFloat(image.height) + 8, accuracy: 0.01)

        image.wrapping = .topAndBottom
        let topBottom = try XCTUnwrap(FloatingImageLayout.exclusionPaths(
            images: [image], pageIndex: 0, geometry: geometry, columnIndex: 0
        ).first)
        XCTAssertEqual(topBottom.bounds.minX, 0, accuracy: 0.01)
        XCTAssertEqual(topBottom.bounds.width, geometry.columnWidth, accuracy: 0.01)
        XCTAssertEqual(topBottom.bounds.minY, contentLocalY - 2, accuracy: 0.01)
        XCTAssertEqual(topBottom.bounds.maxY, contentLocalY + CGFloat(image.height) + 8, accuracy: 0.01)
    }

    func testResponsiveAlignmentUsesCurrentPageGeometryAlongsideStableAnchorSnapshot() throws {
        let image = FloatingImage(assetName: "aligned-anchor.png", imageData: try opaquePNG(),
                                  anchor: .paragraph, anchorLocation: 4, x: 0, y: 0,
                                  anchorOffsetX: 0, anchorOffsetY: 12,
                                  horizontalPositionReference: .margins,
                                  verticalPositionReference: .anchor,
                                  horizontalAlignment: .center,
                                  width: 80, height: 40, wrapping: .square)
        let firstGeometry = try PageGeometry(PageSettings())
        let first = FloatingImageLayout.positionedAtAnchor(
            image, pageIndex: 0, origin: CGPoint(x: 90, y: 180),
            pageContentOrigin: firstGeometry.contentOrigin,
            paragraphOrigin: CGPoint(x: 90, y: 180), pageGeometry: firstGeometry)
        let snapshot = [image.id: first]

        var changedSettings = PageSettings()
        changedSettings.paper = .custom
        changedSettings.customPaperSize = CGSize(width: 500, height: 700)
        changedSettings.leftMargin = 80
        changedSettings.rightMargin = 60
        let changedGeometry = try PageGeometry(changedSettings)
        let candidate = FloatingImageLayout.positionedAtAnchor(
            image, pageIndex: 0, origin: CGPoint(x: 140, y: 240),
            pageContentOrigin: changedGeometry.contentOrigin,
            paragraphOrigin: CGPoint(x: 140, y: 240), pageGeometry: changedGeometry)
        let stable = try XCTUnwrap(FloatingImageLayout.applyingAnchorSnapshots(
            [candidate], snapshots: snapshot, pageIndex: 0).first)
        let expectedAlignedX = changedGeometry.contentOrigin.x
            + (changedGeometry.contentSize.width - CGFloat(image.width)) / 2
        XCTAssertEqual(stable.x, Double(expectedAlignedX), accuracy: 0.01,
                       "Responsive alignment must follow the current margin geometry, not a stale pagination snapshot.")
        XCTAssertEqual(stable.y, first.y, accuracy: 0.01,
                       "The nonaligned text-relative axis remains on the stable base-flow anchor snapshot.")
    }

    func testAsymmetricDistancesExpandIrregularTightContourWithoutClosingReadableLanes() throws {
        // A stepped, irregular silhouette: three separated horizontal runs
        // make the contour visibly different from the rectangular source box.
        let data = try rgbaPNG(opaquePixels: [18, 25, 26, 33, 34, 41])
        let geometry = try PageGeometry(PageSettings())
        let distances = FloatingImage.WrapDistances(top: 34, right: 17, bottom: 41, left: 13)
        let image = FloatingImage(assetName: "irregular-contour.png", imageData: data,
                                  x: 160, y: 120, width: 160, height: 160,
                                  wrapping: .tight, wrapSide: .both,
                                  wrapDistances: distances)
        var noDistanceImage = image
        noDistanceImage.wrapDistances = .uniform(0)
        let noDistancePaths = FloatingImageLayout.exclusionPaths(images: [noDistanceImage], pageIndex: 0,
                                                                  geometry: geometry, columnIndex: 0,
                                                                  font: NSFont.systemFont(ofSize: 12))
        let paths = FloatingImageLayout.exclusionPaths(images: [image], pageIndex: 0,
                                                       geometry: geometry, columnIndex: 0,
                                                       font: NSFont.systemFont(ofSize: 12))
        XCTAssertGreaterThan(paths.count, 0)
        let noDistanceBounds = noDistancePaths.map { $0.bounds }.reduce(CGRect.null) { $0.union($1) }
        let bounds = paths.map { $0.bounds }.reduce(CGRect.null) { $0.union($1) }
        XCTAssertLessThanOrEqual(bounds.minX, noDistanceBounds.minX - CGFloat(distances.left) + 0.01)
        XCTAssertGreaterThanOrEqual(bounds.maxX, noDistanceBounds.maxX + CGFloat(distances.right) - 0.01)
        // Vertical contour bands are snapped to overlapping line-height slabs.
        // Large independent clearances must expand both ends despite snapping.
        XCTAssertLessThan(bounds.minY, noDistanceBounds.minY - 20)
        XCTAssertGreaterThan(bounds.maxY, noDistanceBounds.maxY + 20)
        XCTAssertGreaterThan(bounds.minX, 0, "The transparent region outside this irregular contour must remain usable text space.")
        XCTAssertLessThan(bounds.maxX, geometry.columnWidth,
                          "Asymmetric clearance must not turn Tight Wrap into a full rectangular exclusion.")
    }

    func testAsymmetricWrapDistancesPersistAndLegacyScalarDecodesUniformly() throws {
        let distances = FloatingImage.WrapDistances(top: 1, right: 2, bottom: 3, left: 4)
        let image = FloatingImage(assetName: "asymmetric.png", imageData: try opaquePNG(),
                                  x: 20, y: 30, width: 40, height: 50,
                                  wrapDistance: 1, wrapDistances: distances)
        let encoded = try JSONEncoder().encode(image)
        let decoded = try JSONDecoder().decode(FloatingImage.self, from: encoded)
        XCTAssertEqual(decoded.wrapDistances, distances)

        var legacyObject = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacyObject.removeValue(forKey: "wrapDistances")
        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
        let legacy = try JSONDecoder().decode(FloatingImage.self, from: legacyData)
        XCTAssertNil(legacy.wrapDistances)
        XCTAssertEqual(legacy.effectiveWrapDistances, .uniform(legacy.wrapDistance))
    }

    func testWrapSidePersistsAndLegacyMetadataDefaultsToBoth() throws {
        var image = FloatingImage(assetName: "side.png", imageData: try opaquePNG(), x: 20, y: 20,
                                  width: 30, height: 30, wrapping: .square, wrapSide: .rightOnly)
        let encoded = try JSONEncoder().encode(image)
        let decoded = try JSONDecoder().decode(FloatingImage.self, from: encoded)
        XCTAssertEqual(decoded.effectiveWrapSide, .rightOnly)
        image.wrapSide = nil
        let legacyCompatible = try JSONDecoder().decode(FloatingImage.self, from: JSONEncoder().encode(image))
        XCTAssertEqual(legacyCompatible.effectiveWrapSide, .both)
    }

    func testTextAnchoredImagesCanSupplyPageLocalWrappingGeometry() throws {
        let geometry = try PageGeometry(PageSettings())
        let image = FloatingImage(assetName: "anchor.png", imageData: try opaquePNG(),
                                  anchor: .paragraph, anchorLocation: 42,
                                  x: 90, y: 110, width: 120, height: 100,
                                  wrapping: .square)
        let paths = FloatingImageLayout.exclusionPaths(images: [image], pageIndex: 0,
                                                       geometry: geometry, columnIndex: 0)
        XCTAssertEqual(paths.count, 1, "Once pagination resolves a text anchor onto its physical page, it must contribute the same page-local wrap geometry.")
    }

    func testAnchorOffsetsResolveAgainstPhysicalTextKitGeometry() throws {
        let geometry = try PageGeometry(PageSettings())
        let source = FloatingImage(assetName: "anchor.png", imageData: try opaquePNG(),
                                   pageIndex: 0, anchor: .character, anchorLocation: 9,
                                   x: 100, y: 100, anchorOffsetX: 18, anchorOffsetY: 24,
                                   width: 40, height: 30)
        let resolved = FloatingImageLayout.positionedAtAnchor(source, pageIndex: 3,
                                                              origin: CGPoint(x: geometry.contentOrigin.x + 50,
                                                                              y: geometry.contentOrigin.y + 80))
        XCTAssertEqual(resolved.pageIndex, 3)
        XCTAssertEqual(resolved.x, Double(geometry.contentOrigin.x + 68), accuracy: 0.001)
        XCTAssertEqual(resolved.y, Double(geometry.contentOrigin.y + 104), accuracy: 0.001)
        XCTAssertEqual(resolved.anchor, FloatingImage.Anchor.character, "Transient physical resolution must preserve the logical anchor type.")
        XCTAssertEqual(resolved.anchorLocation, 9)
        XCTAssertEqual(source.x, 100, "Resolving an anchor must not overwrite the document's stored geometry.")

        let encoded = try JSONEncoder().encode(source)
        XCTAssertEqual(try JSONDecoder().decode(FloatingImage.self, from: encoded).anchorOffsetX, 18)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "anchorOffsetX")
        legacy.removeValue(forKey: "anchorOffsetY")
        let legacyData = try JSONSerialization.data(withJSONObject: legacy)
        let reopenedLegacy = try JSONDecoder().decode(FloatingImage.self, from: legacyData)
        XCTAssertNil(reopenedLegacy.anchorOffsetX)
        XCTAssertNil(reopenedLegacy.anchorOffsetY)
    }

    @MainActor
    func testPhysicalTextAnchorResolvesThroughPaginatedTextKitContainers() throws {
        _ = NSApplication.shared
        let text = NSAttributedString(string: String(repeating: "An anchored image follows its text.\n", count: 700),
                                      attributes: [.font: NSFont.systemFont(ofSize: 12)])
        let canvas = PaginatedEditor(text: text)
        canvas.configure(printLayout: true, settings: PageSettings(), zoom: 1, viewportWidth: 900)
        canvas.finishPagination()
        let location = (text.string as NSString).range(of: "An anchored image", options: [], range: NSRange(location: 20_000, length: (text.string as NSString).length - 20_000)).location
        let target = try XCTUnwrap(canvas.physicalAnchorOrigin(anchor: .paragraph, location: location))
        let characterTarget = try XCTUnwrap(canvas.physicalAnchorOrigin(anchor: .character, location: location + 8))
        XCTAssertGreaterThan(target.pageIndex, 0)
        XCTAssertEqual(characterTarget.pageIndex, target.pageIndex)
        XCTAssertGreaterThan(characterTarget.origin.x, target.origin.x,
                             "Character anchors resolve to the glyph position within the line, while paragraph anchors resolve to the line origin.")
        let page = try XCTUnwrap(canvas.pages.indices.contains(target.pageIndex) ? canvas.pages[target.pageIndex].pageGeometry : nil)
        XCTAssertGreaterThanOrEqual(target.origin.x, page.contentOrigin.x)
        XCTAssertGreaterThanOrEqual(target.origin.y, page.contentOrigin.y)
        XCTAssertLessThan(target.origin.y, page.contentOrigin.y + page.contentSize.height)
    }

    @MainActor
    func testParagraphAnchorPhysicalPageAndPositionFollowLargeTextInsertion() throws {
        _ = NSApplication.shared
        let line = "The anchored photograph follows this paragraph.\n"
        let targetParagraph = "ANCHOR PARAGRAPH MUST MOVE TO A LATER PAGE.\n"
        let original = String(repeating: line, count: 90) + targetParagraph + String(repeating: line, count: 90)
        let anchorLocation = (original as NSString).range(of: targetParagraph).location
        let font = NSFont.systemFont(ofSize: 12)
        let originalCanvas = PaginatedEditor(text: NSAttributedString(string: original, attributes: [.font: font]))
        originalCanvas.configure(printLayout: true, settings: PageSettings(), zoom: 1, viewportWidth: 900)
        originalCanvas.finishPagination()
        let before = try XCTUnwrap(originalCanvas.physicalAnchorOrigin(anchor: .paragraph, location: anchorLocation))
        var image = FloatingImage(assetName: "anchored.png", imageData: try opaquePNG(),
                                  anchor: .paragraph, anchorLocation: anchorLocation,
                                  x: before.origin.x + 24, y: before.origin.y + 18,
                                  anchorOffsetX: 24, anchorOffsetY: 18, width: 80, height: 70,
                                  wrapping: .square)
        image.pageIndex = before.pageIndex

        let prefix = String(repeating: "Inserted prose above the target paragraph.\n", count: 160)
        let edited = prefix + original
        var metadata = DocumentMetadata()
        metadata.floatingImages = [image]
        metadata.rebaseTextAnchors(from: original, to: edited)
        let reopenedMetadata = try JSONDecoder().decode(DocumentMetadata.self,
                                                        from: JSONEncoder().encode(metadata))
        let savedImage = try XCTUnwrap(reopenedMetadata.floatingImages?.first)
        let editedCanvas = PaginatedEditor(text: NSAttributedString(string: edited, attributes: [.font: font]))
        editedCanvas.configure(printLayout: true, settings: PageSettings(), zoom: 1, viewportWidth: 900)
        editedCanvas.setFloatingImages([savedImage])
        editedCanvas.finishPagination()
        let after = try XCTUnwrap(editedCanvas.physicalAnchorOrigin(anchor: savedImage.anchor,
                                                                   location: savedImage.anchorLocation))
        let resolved = FloatingImageLayout.positionedAtAnchor(savedImage, pageIndex: after.pageIndex,
                                                               origin: after.origin)
        XCTAssertGreaterThan(after.pageIndex, before.pageIndex)
        XCTAssertEqual(savedImage.pageIndex, before.pageIndex,
                       "The persisted page/anchor record remains logical input; resolution is transient.")
        let inspectorGeometry = try XCTUnwrap(editedCanvas.resolvedFloatingImage(savedImage))
        XCTAssertEqual(inspectorGeometry.pageIndex, after.pageIndex,
                       "Inspector page display must use the image's actual resolved physical page.")
        XCTAssertEqual(inspectorGeometry.x, resolved.x, accuracy: 0.01)
        XCTAssertEqual(inspectorGeometry.y, resolved.y, accuracy: 0.01)
        XCTAssertEqual(savedImage.pageIndex, before.pageIndex,
                       "A read-only inspector query must not rewrite stored anchor state.")
        XCTAssertEqual(resolved.x, Double(after.origin.x) + 24, accuracy: 0.01)
        XCTAssertEqual(resolved.y, Double(after.origin.y) + 18, accuracy: 0.01)
        XCTAssertEqual(editedCanvas.flow.storage.string, edited)
        var pdfRanges: [NSRange] = []
        let pdf = try PDFExporter.data(from: NSAttributedString(string: edited, attributes: [.font: font]),
                                       settings: PageSettings(), pageRangeSink: { pdfRanges = $0 },
                                       floatingImages: [savedImage])
        XCTAssertEqual(pdfRanges, editedCanvas.pageRanges,
                       "A text-anchored wrapped image must use the same converged page allocation in PDF and the production canvas.")
        XCTAssertEqual(PDFDocument(data: pdf)?.pageCount, editedCanvas.pages.count)
    }

    @MainActor
    func testInspectorDoesNotInventPhysicalPageAfterPaginationFailure() throws {
        _ = NSApplication.shared
        let text = NSAttributedString(string: String(repeating: "An anchored image follows this paragraph.\n", count: 80),
                                      attributes: [.font: NSFont.systemFont(ofSize: 12)])
        let canvas = PaginatedEditor(text: text)
        canvas.configure(printLayout: true, settings: PageSettings(), zoom: 1, viewportWidth: 900)
        canvas.finishPagination()
        let image = FloatingImage(assetName: "anchor.png", imageData: try opaquePNG(),
                                  anchor: .paragraph, anchorLocation: 1, x: 12, y: 18,
                                  anchorOffsetX: 12, anchorOffsetY: 18, width: 40, height: 40)
        XCTAssertNotNil(canvas.resolvedFloatingImage(image))

        canvas.fail("Synthetic pagination failure for inspector regression.")

        XCTAssertEqual(canvas.lastLayoutError, "Synthetic pagination failure for inspector regression.")
        XCTAssertNil(canvas.resolvedFloatingImage(image),
                     "The inspector must report unresolved physical page geometry instead of falling back to stale pageIndex.")
        XCTAssertEqual(image.pageIndex, 0, "Failure reporting must not mutate the stored image record.")
    }

    @MainActor
    func testCharacterAnchoredSquareWrapAtDocumentStartHasBoundedStableLayout() throws {
        _ = NSApplication.shared
        let prose = "The selected character stays associated with this manuscript paragraph.\n"
        let text = NSAttributedString(string: String(repeating: prose, count: 80),
                                      attributes: [.font: NSFont.systemFont(ofSize: 12)])
        let canvas = PaginatedEditor(text: text)
        canvas.configure(printLayout: true, settings: PageSettings(), zoom: 1, viewportWidth: 900)
        canvas.finishPagination()
        var trace: [String] = []
        canvas.anchorPaginationTrace = { trace.append($0) }
        let image = FloatingImage(assetName: "start-anchor.png", imageData: try opaquePNG(),
                                  pageIndex: 0, anchor: .character, anchorLocation: 0,
                                  x: 72, y: 72, anchorOffsetX: 0, anchorOffsetY: 0,
                                  width: 128, height: 128, wrapping: .square)
        canvas.setFloatingImages([image])
        canvas.finishPagination()

        XCTAssertNil(canvas.lastLayoutError, "Anchor layout trace:\n\(trace.joined(separator: "\n"))")
        XCTAssertTrue(canvas.layoutComplete)
        XCTAssertEqual(canvas.flow.storage.string, text.string)
        XCTAssertEqual(canvas.pageRanges.first?.location, 0)
        XCTAssertEqual(canvas.pageRanges.last.map(NSMaxRange), text.length)
        XCTAssertLessThanOrEqual(trace.count, 32, "Anchor pagination must remain bounded.")
        XCTAssertFalse(trace.contains(where: { $0.contains("decision=repeated") }), trace.joined(separator: "\n"))
        XCTAssertTrue(trace.last?.contains("decision=stable") == true, trace.joined(separator: "\n"))
        var pdfRanges: [NSRange] = []
        let pdf = try PDFExporter.data(from: text, settings: PageSettings(),
                                       pageRangeSink: { pdfRanges = $0 }, floatingImages: [image])
        XCTAssertEqual(PDFDocument(data: pdf)?.pageCount, canvas.pages.count)
        XCTAssertEqual(pdfRanges, canvas.pageRanges,
                       "The PDF must use the same pre-self-wrap anchor snapshot and final page allocation.")
    }

    @MainActor
    func testCharacterAnchoredImageWrapModesConvergeInCanvasAndPDF() throws {
        _ = NSApplication.shared
        let font = NSFont.systemFont(ofSize: 12)
        let text = NSAttributedString(string: String(repeating: "Unicode 😀 text stays in its paragraph and wraps predictably.\n", count: 90),
                                      attributes: [.font: font])
        for wrapping: FloatingImage.Wrapping in [.none, .square, .tight, .through, .topAndBottom] {
            let canvas = PaginatedEditor(text: text)
            canvas.configure(printLayout: true, settings: PageSettings(), zoom: 1, viewportWidth: 900)
            canvas.finishPagination()
            let image = FloatingImage(assetName: "anchor-\(wrapping.rawValue).png",
                                      imageData: try rgbaPNG(opaquePixels: [27]),
                                      pageIndex: 0, anchor: .character, anchorLocation: 2,
                                      x: 0, y: 18, anchorOffsetX: 0, anchorOffsetY: 18,
                                      width: 100, height: 100, wrapping: wrapping)
            canvas.setFloatingImages([image])
            canvas.finishPagination()
            XCTAssertNil(canvas.lastLayoutError, "\(wrapping) canvas layout failed: \(canvas.lastLayoutError ?? "")")
            XCTAssertTrue(canvas.layoutComplete)
            XCTAssertEqual(canvas.flow.storage.string, text.string)
            var ranges: [NSRange] = []
            let pdf = try PDFExporter.data(from: text, settings: PageSettings(), pageRangeSink: { ranges = $0 },
                                           floatingImages: [image])
            XCTAssertEqual(PDFDocument(data: pdf)?.pageCount, canvas.pages.count, "\(wrapping)")
            XCTAssertEqual(ranges, canvas.pageRanges, "\(wrapping) must share page allocation")
        }
    }

    func testCharacterAnchorRebaseUsesUTF16WithSurrogatePairs() {
        var metadata = DocumentMetadata()
        let original = "Before 😀 anchor target after"
        let location = (original as NSString).range(of: "anchor").location + 2
        metadata.floatingImages = [FloatingImage(assetName: "unicode.png", imageData: Data([1]),
                                                  anchor: .character, anchorLocation: location,
                                                  x: 1, y: 2, anchorOffsetX: 5, anchorOffsetY: 6,
                                                  width: 3, height: 4)]
        let inserted = "📝 prefix " + original
        metadata.rebaseTextAnchors(from: original, to: inserted)
        XCTAssertEqual(metadata.floatingImages?.first?.anchorLocation,
                       location + ("📝 prefix " as NSString).length)
        XCTAssertEqual(metadata.floatingImages?.first?.anchorOffsetX, 5)
    }

    func testParagraphAnchorImmediatelyAfterHardPageBreakStaysWithFollowingParagraph() {
        let text = "First page paragraph\n\n\u{000C}Chapter 2 paragraph after a page break.\n\nThird paragraph."
        let chapterLocation = (text as NSString).range(of: "Chapter 2").location
        XCTAssertEqual(FloatingImageLayout.textAnchorLocation(anchor: .paragraph,
                                                               location: chapterLocation + 4,
                                                               in: text),
                       chapterLocation,
                       "A form-feed page break must not rebind the following paragraph to the preceding page.")
    }

    func testTightWrapUsesAlphaContourRatherThanSquareBounds() throws {
        let data = try rgbaPNG(opaquePixels: [27])
        let geometry = try PageGeometry(PageSettings())
        let image = FloatingImage(assetName: "alpha.png", imageData: data,
                                  x: 72, y: 72, width: 160, height: 160,
                                  wrapping: .tight, wrapDistance: 2)
        let paths = FloatingImageLayout.exclusionPaths(images: [image], pageIndex: 0,
                                                       geometry: geometry, columnIndex: 0)
        XCTAssertFalse(paths.isEmpty)
        XCTAssertLessThan(paths.map(\.bounds).reduce(CGRect.null) { $0.union($1) }.width, 100,
                          "A small opaque island should not create a rectangular image-width exclusion.")
    }

    @MainActor
    func testRotatedTightWrapBookFixtureDoesNotCreateUnreadableTextFragments() throws {
        _ = NSApplication.shared
        let paragraphs = (0..<6).map { index in
            "Chapter \(index + 1) — naïve café • “quoted” text — “A careful editor checks every page.”\n\n" +
            String(repeating: "A varied paragraph with Unicode Ω, em dashes, and readable book text. ", count: 6) + "\n\n"
        }
        let baseText = paragraphs.joined(separator: "\u{000C}")
        let text = NSMutableAttributedString(string: baseText)
        let bodyFont = NSFont(name: "TimesNewRomanPSMT", size: 11) ?? NSFont.systemFont(ofSize: 11)
        text.addAttribute(.font, value: bodyFont, range: NSRange(location: 0, length: text.length))
        text.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 16),
                          range: (baseText as NSString).range(of: "Chapter 1"))
        text.addAttribute(.font, value: NSFontManager.shared.convert(bodyFont, toHaveTrait: .italicFontMask),
                          range: (baseText as NSString).range(of: "naïve café"))
        let png = try rotatedTightFixturePNG()
        text.append(NSAttributedString(string: "\nInline illustration: "))
        let inlineWrapper = FileWrapper(regularFileWithContents: png)
        inlineWrapper.preferredFilename = "qa-inline-marker.png"
        text.append(NSAttributedString(attachment: NSTextAttachment(fileWrapper: inlineWrapper)))
        text.append(NSAttributedString(string: "\n"))
        let source = text.string

        var settings = PageSettings()
        settings.paper = .custom
        settings.customPaperSize = CGSize(width: 396, height: 612)
        settings.topMargin = 54; settings.bottomMargin = 54
        settings.leftMargin = 50; settings.rightMargin = 50
        settings.gutter = 12; settings.mirrorMargins = true
        settings.headerText = "Independent QA — Book Interior"
        settings.footerText = "BOLD Writer production export"
        settings.showsPageNumbers = true

        let anchorLocations = paragraphs.map {
            (source as NSString).range(of: String($0.prefix(14))).location
        }
        let wraps: [FloatingImage.Wrapping] = [.square, .tight, .topAndBottom, .none]
        let anchors: [FloatingImage.Anchor] = [.paragraph, .character, .paragraph, .character]
        let images = (0..<4).map { index in
            FloatingImage(assetName: "qa-marker-\(index).png", imageData: png, pageIndex: index,
                          anchor: anchors[index], anchorLocation: anchorLocations[index],
                          x: 246, y: 110, width: 64, height: 42,
                          rotationDegrees: index == 1 ? 7 : 0, wrapping: wraps[index],
                          wrapDistance: 8, layer: .inFrontOfText, zOrder: index)
        }
        let chapterFour = (baseText as NSString).range(of: "Chapter 4").location
        let sections = [DocumentSection(location: 0, page: settings),
                        DocumentSection(location: chapterFour, page: settings, breakType: .nextPage)]

        let editor = PaginatedEditor(text: text)
        editor.configure(printLayout: true, settings: settings, sections: sections,
                         zoom: 1, viewportWidth: 900)
        editor.finishPagination()
        editor.setFloatingImages(images)
        editor.finishPagination()
        XCTAssertNil(editor.lastLayoutError)
        XCTAssertEqual(editor.flow.storage.string, source)
        let editorPageGeometry = try XCTUnwrap(editor.pages[1].pageGeometry)
        let editorResolvedImage = try XCTUnwrap(editor.resolvedFloatingImage(images[1]))
        let editorExclusions = FloatingImageLayout.exclusionPaths(
            images: [editorResolvedImage], pageIndex: 1, geometry: editorPageGeometry,
            columnIndex: 0,
            font: FloatingImageLayout.representativeFont(in: text,
                                                          at: editor.pageRanges[1].location))
        let manager = editor.flow.manager
        let secondPage = try XCTUnwrap(editor.pageContainerIndices.indices.contains(1)
                                       ? editor.pageContainerIndices[1] : nil)
        let actualEditorExclusions = secondPage.compactMap { index -> [CGRect]? in
            guard manager.textContainers.indices.contains(index) else { return nil }
            return manager.textContainers[index].exclusionPaths.map(\.bounds)
        }.flatMap { $0 }
        XCTAssertEqual(editorResolvedImage.pageIndex, 1)
        XCTAssertEqual(editor.resolvedFloatingImage(images[2])?.pageIndex, 2,
                       "The Top and Bottom image after the next hard page break must remain on page 3.")
        XCTAssertEqual(actualEditorExclusions, editorExclusions.map(\.bounds),
                       "A following page's object must not leak a full-width exclusion onto this page.")
        let pageOrigin = try XCTUnwrap(editor.pages[1].pageGeometry).contentOrigin
        var editorLines: [(text: String, top: CGFloat, x: CGFloat)] = []
        var editorLineRects: [CGRect] = []
        for containerIndex in secondPage where manager.textContainers.indices.contains(containerIndex) {
            let container = manager.textContainers[containerIndex]
            let glyphRange = manager.glyphRange(for: container)
            guard glyphRange.location != NSNotFound else { continue }
            var glyph = glyphRange.location
            while glyph < NSMaxRange(glyphRange) {
                var lineGlyphs = NSRange(location: 0, length: 0)
                let rect = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &lineGlyphs)
                let chars = manager.characterRange(forGlyphRange: lineGlyphs, actualGlyphRange: nil)
                let value = (baseText as NSString).substring(with: chars)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty {
                    editorLines.append((text: value, top: rect.minY + pageOrigin.y, x: rect.minX + pageOrigin.x))
                    editorLineRects.append(rect.offsetBy(dx: pageOrigin.x, dy: pageOrigin.y))
                }
                let next = NSMaxRange(lineGlyphs)
                guard next > glyph else { break }
                glyph = next
            }
        }

        var pdfPageRanges: [NSRange] = []
        let pdfData = try PDFExporter.data(from: text, settings: settings, sections: sections,
                                           pageRangeSink: { pdfPageRanges = $0 },
                                           floatingImages: images)
        XCTAssertEqual(pdfPageRanges, editor.pageRanges)
        let pdf = try XCTUnwrap(PDFDocument(data: pdfData))
        XCTAssertEqual(pdf.pageCount, 6)
        XCTAssertEqual(editor.pages.count, pdf.pageCount)
        let page = try XCTUnwrap(pdf.page(at: 1))
        let pageText = try XCTUnwrap(page.string)
        let allText = try XCTUnwrap(page.selection(for: NSRange(location: 0, length: (pageText as NSString).length)))
        let lineSelections = allText.selectionsByLine().compactMap { selection -> (String, CGRect)? in
            guard let value = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty,
                  !value.hasPrefix("Independent QA"), !value.hasPrefix("BOLD Writer") else { return nil }
            return (value, selection.bounds(for: page))
        }
        let mediaHeight = page.bounds(for: .mediaBox).height
        let pdfLineRects = lineSelections.map { _, rect in
            CGRect(x: rect.minX, y: mediaHeight - rect.maxY, width: rect.width, height: rect.height)
        }
        let sourceWords = Set(baseText.lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { $0.count > 1 })
        var orderedLines: [(text: String, top: CGFloat, x: CGFloat)] = []
        for (value, rect) in lineSelections {
            orderedLines.append((text: value, top: mediaHeight - rect.maxY, x: rect.minX))
        }
        func splitWords(in lines: [(text: String, top: CGFloat, x: CGFloat)]) -> [String] {
            var sorted = lines
            sorted.sort { lhs, rhs in
                if abs(lhs.top - rhs.top) <= 2 { return lhs.x < rhs.x }
                return lhs.top < rhs.top
            }
            var result: [String] = []
            guard sorted.count > 1 else { return result }
            for index in 0..<(sorted.count - 1) {
                let current = sorted[index]
                let next = sorted[index + 1]
                let left = current.text.lowercased().filter { $0.isLetter }
                let right = next.text.lowercased().filter { $0.isLetter }
                guard !left.isEmpty, !right.isEmpty else { continue }
                for suffixLength in 1...min(12, left.count) {
                    for prefixLength in 1...min(12, right.count) {
                        let splitWord = String(left.suffix(suffixLength) + right.prefix(prefixLength))
                        if sourceWords.contains(splitWord) {
                            result.append("\(splitWord) between y=\(current.top) and y=\(next.top)")
                        }
                    }
                }
            }
            return result
        }
        let editorWordSplits = splitWords(in: editorLines)
        let pdfWordSplits = splitWords(in: orderedLines)
        XCTAssertTrue(editorWordSplits.isEmpty,
                      "The manuscript editor must not split ordinary words around rotated Tight Wrap: \(editorWordSplits)")
        XCTAssertTrue(pdfWordSplits.isEmpty,
                      "The production PDF must not split ordinary words around rotated Tight Wrap: \(pdfWordSplits)")
        XCTAssertEqual(editorLines.map(\.text), orderedLines.map(\.text),
                       "The editor and production PDF must emit the same page-2 line content.")
        var maximumLinePositionDelta = 0.0
        for (editorLine, pdfLine) in zip(editorLines, orderedLines) {
            let delta = max(abs(Double(editorLine.top - pdfLine.top)),
                            abs(Double(editorLine.x - pdfLine.x)))
            maximumLinePositionDelta = max(maximumLinePositionDelta, delta)
        }
        XCTAssertLessThanOrEqual(maximumLinePositionDelta, 2,
                                 "Editor and PDF line positions must agree within 2 physical points.")
        let tightImage = images[1]
        let tightAngle = tightImage.rotationDegrees * .pi / 180
        let tightBoundsWidth = abs(cos(tightAngle) * tightImage.width) + abs(sin(tightAngle) * tightImage.height)
        let tightBoundsHeight = abs(sin(tightAngle) * tightImage.width) + abs(cos(tightAngle) * tightImage.height)
        let tightImageBounds = CGRect(x: tightImage.x - (tightBoundsWidth - tightImage.width) / 2,
                                      y: tightImage.y - (tightBoundsHeight - tightImage.height) / 2,
                                      width: tightBoundsWidth, height: tightBoundsHeight)
        let editorTextOverlapsImage = editorLineRects.filter { $0.intersects(tightImageBounds) }
        let pdfImageBounds = CGRect(x: tightImageBounds.minX,
                                    y: mediaHeight - tightImageBounds.maxY,
                                    width: tightImageBounds.width, height: tightImageBounds.height)
        let pdfTextOverlapsImage = pdfLineRects.filter { $0.intersects(pdfImageBounds) }
        XCTAssertTrue(editorTextOverlapsImage.isEmpty,
                      "Editor line fragments must not intrude into the rotated image bounds: \(editorTextOverlapsImage)")
        XCTAssertTrue(pdfTextOverlapsImage.isEmpty,
                      "PDF text line bounds must not intrude into the rotated image bounds: \(pdfTextOverlapsImage)")
        let placements = PDFImageGeometryInspection.placements(in: pdf)
        XCTAssertGreaterThanOrEqual(placements.count, images.count + 1,
                                    "All four floating images and the inline attachment must survive the fixture export.")
        var maximumImageGeometryDelta = 0.0
        for (index, expectedImage) in images.enumerated() {
            let placement = try XCTUnwrap(placements.first(where: { $0.pageIndex == index }))
            let angle = expectedImage.rotationDegrees * .pi / 180
            let width = abs(cos(angle) * expectedImage.width) + abs(sin(angle) * expectedImage.height)
            let height = abs(sin(angle) * expectedImage.width) + abs(cos(angle) * expectedImage.height)
            let expected = CGRect(x: expectedImage.x - (width - expectedImage.width) / 2,
                                  y: 612 - expectedImage.y - expectedImage.height - (height - expectedImage.height) / 2,
                                  width: width, height: height)
            let delta = [abs(placement.bounds.minX - expected.minX),
                         abs(placement.bounds.minY - expected.minY),
                         abs(placement.bounds.width - expected.width),
                         abs(placement.bounds.height - expected.height)].max() ?? .infinity
            maximumImageGeometryDelta = max(maximumImageGeometryDelta, delta)
        }
        XCTAssertLessThanOrEqual(maximumImageGeometryDelta, 0.05,
                                 "The wrap repair must preserve accurate floating-image transforms.")
        XCTAssertEqual(pdf.string?.filter { $0 == "Ω" }.count,
                       source.filter { $0 == "Ω" }.count,
                       "Wrapping must preserve every source character.")
        func normalizedText(_ value: String) -> String {
            var body = value.replacingOccurrences(of: "Independent QA — Book Interior", with: "")
            for pageNumber in 1...pdf.pageCount {
                body = body.replacingOccurrences(of: "BOLD Writer production export \(pageNumber)", with: "")
            }
            return String(body.unicodeScalars.filter {
                !CharacterSet.whitespacesAndNewlines.contains($0) && $0.value != 0xFFFC
            })
        }
        XCTAssertEqual(normalizedText(pdf.string ?? ""), normalizedText(source),
                       "Independent PDF extraction must preserve all non-whitespace source characters.")
        print("TIGHT_WRAP_ACCEPTANCE pages=\(pdf.pageCount) editor_pdf_page2_lines=\(editorLines.count) word_splits=\(pdfWordSplits.count) max_line_delta_pt=\(maximumLinePositionDelta) max_image_delta_pt=\(maximumImageGeometryDelta)")
        if let output = ProcessInfo.processInfo.environment["BOLD_M36_TIGHT_WRAP_EVIDENCE"] {
            let directory = URL(fileURLWithPath: output, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try pdfData.write(to: directory.appendingPathComponent("BOLDWriter-production-interior-fixed.pdf"),
                              options: .atomic)
            try png.write(to: directory.appendingPathComponent("tight-wrap-source-artwork.png"), options: .atomic)
            let summary: [String: Any] = [
                "sourceTextSHA256": Self.sha256(Data(source.utf8)),
                "pdfSHA256": Self.sha256(pdfData),
                "sourceImageSHA256": Self.sha256(png),
                "pageCount": pdf.pageCount,
                "mediaBoxPoints": [396, 612],
                "wrapModes": wraps.map(\.rawValue),
                "anchors": anchors.map(\.rawValue),
                "rotationDegrees": images.map(\.rotationDegrees),
                "editorPage2LineFragments": editorLines.map { ["text": $0.text, "top": $0.top, "x": $0.x] as [String: Any] },
                "pdfPage2LineFragments": orderedLines.map { ["text": $0.text, "top": $0.top, "x": $0.x] as [String: Any] },
                "editorAndPDFPage2LineContentMatch": editorLines.map(\.text) == orderedLines.map(\.text),
                "maximumEditorPDFLinePositionDeltaPoints": maximumLinePositionDelta,
                "editorTextImageOverlaps": editorTextOverlapsImage.count,
                "pdfTextImageOverlaps": pdfTextOverlapsImage.count,
                "wordSplits": pdfWordSplits,
                "maximumImageGeometryDifferencePoints": maximumImageGeometryDelta
            ]
            let report = try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys])
            try report.write(to: directory.appendingPathComponent("tight-wrap-fixed-inspection.json"), options: .atomic)
        }
        if let path = ProcessInfo.processInfo.environment["BOLD_M36_TIGHT_WRAP_NATIVE_FIXTURE"] {
            let url = URL(fileURLWithPath: path).standardizedFileURL
            XCTAssertEqual(url.pathExtension, "boldwriter")
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path),
                           "Refusing to overwrite any existing native document.")
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            var metadata = DocumentMetadata()
            metadata.title = "TEST-COPY-DO-NOT-USE-AS-ORIGINAL — Tight Wrap Repair"
            metadata.page = settings
            metadata.sections = sections
            metadata.floatingImages = images
            let package = try BOLDWriterDocument.packageWrapper(text: text, metadata: metadata)
            try package.write(to: url, options: .atomic, originalContentsURL: nil)
            let reopened = try BOLDWriterDocument(fileWrapper: FileWrapper(url: url),
                                                  contentType: .boldWriterDocument)
            XCTAssertEqual(reopened.text.string, source)
            XCTAssertEqual(reopened.metadata.floatingImages?.map(\.wrapping), wraps)
            XCTAssertEqual(reopened.metadata.floatingImages?.map(\.rotationDegrees), images.map(\.rotationDegrees))
            XCTAssertEqual(reopened.metadata.floatingImages?.map(\.imageData), images.map(\.imageData),
                           "Native save/reopen must preserve the source Tight Wrap artwork bytes.")
            print("TIGHT_WRAP_NATIVE_FIXTURE path=\(url.path) textSHA256=\(Self.sha256(Data(source.utf8)))")
        }
    }

    @MainActor
    func testProductionCanvasNoWrapPreservesPageRangesAndWrapReflowsText() throws {
        _ = NSApplication.shared
        let text = NSAttributedString(string: String(repeating: "A full line of manuscript text for image wrapping.\n", count: 120),
                                      attributes: [.font: NSFont.systemFont(ofSize: 12)])
        let canvas = PaginatedEditor(text: text)
        canvas.configure(printLayout: true, settings: PageSettings(), zoom: 1, viewportWidth: 900)
        canvas.finishPagination()
        let originalRanges = canvas.pageRanges
        let originalLines = lineFragmentBounds(in: canvas)
        let data = try opaquePNG()
        var image = FloatingImage(assetName: "canvas.png", imageData: data, pageIndex: 0,
                                  x: 85, y: 90, width: 180, height: 160, wrapping: .none)
        canvas.setFloatingImages([image])
        canvas.finishPagination()
        XCTAssertEqual(canvas.pageRanges, originalRanges, "No-wrap insertion must leave production canvas page allocation untouched.")
        XCTAssertEqual(lineFragmentBounds(in: canvas), originalLines, "No-wrap insertion must leave onscreen line geometry untouched.")
        image.x = 210
        image.y = 140
        canvas.setFloatingImages([image])
        canvas.finishPagination()
        XCTAssertEqual(canvas.pageRanges, originalRanges, "Moving a no-wrap image must not reflow manuscript characters or pages.")
        XCTAssertEqual(lineFragmentBounds(in: canvas), originalLines, "Moving a no-wrap image must preserve every text line's physical bounds.")

        image.wrapping = .square
        canvas.setFloatingImages([image])
        canvas.finishPagination()
        XCTAssertNotEqual(canvas.pageRanges, originalRanges, "A wrapped image must reflow the production manuscript TextKit containers.")
        XCTAssertEqual(canvas.flow.storage.string, text.string, "Wrapping can move glyphs, but must preserve source characters exactly.")
        var exportedPageRanges: [NSRange] = []
        _ = try PDFExporter.data(from: text, settings: PageSettings(),
                                 pageRangeSink: { exportedPageRanges = $0 },
                                 floatingImages: [image])
        XCTAssertEqual(exportedPageRanges, canvas.pageRanges,
                       "The production canvas and PDF must allocate the same manuscript characters to each physical page.")
    }

    @MainActor
    func testEveryWrapSideUsesIdenticalCanvasAndPDFPageAllocation() throws {
        _ = NSApplication.shared
        let text = NSAttributedString(string: String(repeating: "Readable manuscript words surround the photograph. ", count: 150),
                                      attributes: [.font: NSFont.systemFont(ofSize: 12)])
        for side in FloatingImage.WrapSide.allCases {
            let image = FloatingImage(assetName: "wrap-side.png", imageData: try opaquePNG(),
                                      pageIndex: 0, x: 205, y: 95, width: 155, height: 130,
                                      wrapping: .square, wrapDistance: 9, wrapSide: side)
            let canvas = PaginatedEditor(text: text)
            canvas.configure(printLayout: true, settings: PageSettings(), zoom: 1, viewportWidth: 900)
            canvas.setFloatingImages([image])
            canvas.finishPagination()
            var pdfRanges: [NSRange] = []
            let pdf = try PDFExporter.data(from: text, settings: PageSettings(),
                                           pageRangeSink: { pdfRanges = $0 }, floatingImages: [image])
            XCTAssertEqual(canvas.pageRanges, pdfRanges, "Canvas and PDF must allocate the same text ranges for wrap side \(side).")
            XCTAssertEqual(PDFDocument(data: pdf)?.pageCount, canvas.pages.count)
            XCTAssertEqual(canvas.flow.storage.string, text.string)
        }
    }

    @MainActor
    private func lineFragmentBounds(in canvas: PaginatedEditor) -> [CGRect] {
        let manager = canvas.flow.manager
        var result: [CGRect] = []
        for containerIndex in canvas.pageContainerIndices.flatMap({ $0 }) where manager.textContainers.indices.contains(containerIndex) {
            let container = manager.textContainers[containerIndex]
            let range = manager.glyphRange(for: container)
            guard range.location != NSNotFound, range.length > 0 else { continue }
            manager.enumerateLineFragments(forGlyphRange: range) { _, usedRect, _, _, _ in result.append(usedRect) }
        }
        return result
    }

    @MainActor
    func testProductionPageViewRendersFloatingImageAtPageCoordinates() throws {
        _ = NSApplication.shared
        let canvas = PaginatedEditor(text: NSAttributedString(string: "Canvas image drawing\n"))
        canvas.configure(printLayout: true, settings: PageSettings(), zoom: 1, viewportWidth: 900)
        canvas.finishPagination()
        let bytes = try opaquePNG()
        canvas.setFloatingImages([FloatingImage(assetName: "red.png", imageData: bytes, pageIndex: 0,
                                                x: 90, y: 120, width: 80, height: 80)])
        let page = canvas.firstView
        let bitmap = try XCTUnwrap(page.bitmapImageRepForCachingDisplay(in: page.bounds))
        page.cacheDisplay(in: page.bounds, to: bitmap)
        let center = try XCTUnwrap(bitmap.colorAt(x: 130, y: 160)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(center.redComponent, 0.8)
        XCTAssertLessThan(center.greenComponent, 0.2)
        XCTAssertLessThan(center.blueComponent, 0.2)
    }

    @MainActor
    func testCanvasSelectionSynchronizationDoesNotRepublishUnchangedSelection() throws {
        _ = NSApplication.shared
        let canvas = PaginatedEditor(text: NSAttributedString(string: "Selection update regression"))
        let selectionID = UUID()
        var publishedSelections: [UUID?] = []
        canvas.onSelectFloatingImage = { publishedSelections.append($0) }

        // SwiftUI calls this during makeNSView and subsequent updateNSView
        // passes, including passes caused by unrelated editor state changes.
        canvas.selectFloatingImage(nil)
        canvas.selectFloatingImage(nil)
        canvas.selectFloatingImage(selectionID)
        canvas.selectFloatingImage(selectionID)
        canvas.selectFloatingImage(selectionID)

        XCTAssertEqual(publishedSelections.count, 1,
                       "A representable update must not publish the same selected image back into its observed controller repeatedly.")
        XCTAssertEqual(publishedSelections.first!, selectionID)
    }

    @MainActor
    func testFloatingImageDocumentMutationUsesUndoAndRedo() throws {
        _ = NSApplication.shared
        let document = BOLDWriterDocument()
        document.text = NSAttributedString(string: "Undo image placement")
        let canvas = PaginatedEditor(text: document.text)
        canvas.firstView.sessionUndoManager = UndoManager()
        let editor = EditorController()
        editor.document = document
        editor.attach(canvas.firstView)
        let image = FloatingImage(assetName: "undo.png", imageData: try opaquePNG(), x: 30, y: 40, width: 80, height: 80)
        XCTAssertTrue(editor.setFloatingImages([image], in: document, actionName: "Insert Image"))
        XCTAssertEqual(document.metadata.floatingImages?.first?.id, image.id)
        canvas.firstView.undoManager?.undo()
        XCTAssertTrue(document.metadata.floatingImages?.isEmpty ?? true)
        canvas.firstView.undoManager?.redo()
        XCTAssertEqual(document.metadata.floatingImages?.first?.id, image.id)
    }

    @MainActor
    func testTextUndoRemainsTheNextActionAfterPassiveAnchoredImageReflow() throws {
        _ = NSApplication.shared
        let anchorParagraph = "THE ANCHOR PARAGRAPH STAYS INTACT.\n"
        let original = NSAttributedString(
            string: String(repeating: "Earlier paragraph.\n", count: 80) + anchorParagraph +
                String(repeating: "Later paragraph.\n", count: 40),
            attributes: [.font: NSFont.systemFont(ofSize: 12)]
        )
        let anchorLocation = (original.string as NSString).range(of: anchorParagraph).location
        let document = BOLDWriterDocument()
        document.text = original
        let image = FloatingImage(assetName: "anchored.png", imageData: try opaquePNG(),
                                  anchor: .paragraph, anchorLocation: anchorLocation,
                                  x: 24, y: 18,
                                  anchorOffsetX: 24, anchorOffsetY: 18,
                                  width: 80, height: 70, wrapping: .square)
        document.metadata.floatingImages = [image]
        let canvas = PaginatedEditor(text: original)
        let undoManager = UndoManager()
        canvas.firstView.sessionUndoManager = undoManager
        canvas.configure(printLayout: true, settings: PageSettings(), zoom: 1, viewportWidth: 900)
        canvas.setFloatingImages([image])
        canvas.finishPagination()
        let editor = EditorController()
        editor.document = document
        editor.attach(canvas.firstView)

        let deletionLength = (original.string as NSString).range(of: anchorParagraph).location
        editor.performUndoableMutation("Delete Preceding Paragraphs") { view in
            view.textStorage?.deleteCharacters(in: NSRange(location: 0, length: deletionLength))
        }
        document.replaceEditedText(with: canvas.firstView.attributedString())
        let rebasedImages = document.metadata.floatingImages ?? []
        canvas.setFloatingImages(rebasedImages)
        canvas.finishPagination()

        XCTAssertEqual(undoManager.undoActionName, "Delete Preceding Paragraphs")
        XCTAssertEqual(rebasedImages.first?.anchorLocation, 0)
        XCTAssertEqual(rebasedImages.first?.anchor, .paragraph)
        XCTAssertNotNil(canvas.resolvedFloatingImage(try XCTUnwrap(rebasedImages.first)))

        undoManager.undo()
        document.replaceEditedText(with: canvas.firstView.attributedString())
        canvas.setFloatingImages(document.metadata.floatingImages ?? [])
        canvas.finishPagination()

        XCTAssertEqual(canvas.firstView.string, original.string,
                       "The first Undo after editing must restore every deleted manuscript character.")
        XCTAssertEqual(document.metadata.floatingImages?.first?.anchor, .paragraph)
        XCTAssertEqual(document.metadata.floatingImages?.first?.anchorLocation, anchorLocation,
                       "Passive reflow must not become a separate image Undo or leave the anchor rebased after text Undo.")
        XCTAssertEqual(canvas.resolvedFloatingImage(try XCTUnwrap(document.metadata.floatingImages?.first))?.anchorLocation,
                       anchorLocation)
    }

    func testParagraphAndCharacterAnchorsRebaseAcrossLargeInsertionsAndDeletedTargets() {
        var metadata = DocumentMetadata()
        let oldText = String(repeating: "Prose before.\n", count: 5000) + "ANCHOR TARGET\n" + String(repeating: "Prose after.\n", count: 5000)
        let anchor = (oldText as NSString).range(of: "ANCHOR TARGET").location
        metadata.floatingImages = [
            FloatingImage(assetName: "p.png", imageData: Data([1]), anchor: .paragraph, anchorLocation: anchor,
                          x: 10, y: 20, width: 30, height: 40),
            FloatingImage(assetName: "c.png", imageData: Data([1]), anchor: .character, anchorLocation: anchor + 3,
                          x: 10, y: 20, width: 30, height: 40)
        ]
        let inserted = String(repeating: "Large inserted prefix.\n", count: 1200) + oldText
        metadata.rebaseTextAnchors(from: oldText, to: inserted)
        XCTAssertEqual(metadata.floatingImages?[0].anchorLocation, anchor + (inserted as NSString).length - (oldText as NSString).length)
        XCTAssertEqual(metadata.floatingImages?[1].anchorLocation, anchor + 3 + (inserted as NSString).length - (oldText as NSString).length)

        let targetAfterInsert = (inserted as NSString).range(of: "ANCHOR TARGET")
        let deleted = (inserted as NSString).replacingCharacters(in: targetAfterInsert, with: "")
        metadata.rebaseTextAnchors(from: inserted, to: deleted)
        XCTAssertEqual(metadata.floatingImages?[0].anchor, .page)
        XCTAssertEqual(metadata.floatingImages?[1].anchor, .page)
    }

    @MainActor
    func testFloatingImageAssetsAreDeduplicatedOutsideMetadataAndReopenFor10_50_100Images() throws {
        let bytes = try opaquePNG()
        for count in [10, 50, 100] {
            let document = BOLDWriterDocument()
            document.text = NSAttributedString(string: "Asset integrity fixture\n")
            document.metadata.floatingImages = (0..<count).map { index in
                FloatingImage(assetName: "shared.png", imageData: bytes, pageIndex: index,
                              x: 20, y: 30, width: 50, height: 50, zOrder: index)
            }
            let wrapper = try BOLDWriterDocument.packageWrapper(text: document.text, metadata: document.metadata)
            let children = try XCTUnwrap(wrapper.fileWrappers)
            let metadata = try XCTUnwrap(children["metadata.json"]?.regularFileContents)
            let storedMetadata = try JSONDecoder().decode(DocumentMetadata.self, from: metadata)
            XCTAssertTrue(storedMetadata.floatingImages?.allSatisfy { $0.imageData.isEmpty && $0.assetDigest?.count == 64 } == true,
                          "Native metadata should contain asset digests instead of embedded image bytes.")
            XCTAssertEqual(children["floating-images"]?.fileWrappers?.count, 1, "Identical source bytes should be stored once.")
            let reopened = try BOLDWriterDocument(fileWrapper: wrapper, contentType: .boldWriterDocument)
            XCTAssertEqual(reopened.metadata.floatingImages?.count, count)
            XCTAssertTrue(reopened.metadata.floatingImages?.allSatisfy { $0.imageData == bytes && $0.assetDigest != nil } == true)
            XCTAssertEqual(wrapper.serializedRepresentation?.count, try BOLDWriterDocument.packageWrapper(text: reopened.text, metadata: reopened.metadata).serializedRepresentation?.count)
            let packageBytes = try XCTUnwrap(wrapper.serializedRepresentation).count
            let assetBytes = children["floating-images"]?.fileWrappers?.values.reduce(0) { $0 + ($1.regularFileContents?.count ?? 0) } ?? 0
            print("FLOATING_IMAGE_ASSET_SIZE count=\(count) metadata_bytes=\(metadata.count) unique_asset_bytes=\(assetBytes) package_bytes=\(packageBytes)")
        }

        let source = BOLDWriterDocument()
        source.metadata.floatingImages = [FloatingImage(assetName: "legacy.png", imageData: bytes, x: 10, y: 10, width: 40, height: 40)]
        let current = try BOLDWriterDocument.packageWrapper(text: source.text, metadata: source.metadata)
        var legacyChildren = try XCTUnwrap(current.fileWrappers)
        var legacyMetadata = try JSONDecoder().decode(DocumentMetadata.self, from: try XCTUnwrap(legacyChildren["metadata.json"]?.regularFileContents))
        legacyMetadata.floatingImages?[0].imageData = bytes
        legacyMetadata.floatingImages?[0].assetDigest = nil
        legacyChildren["metadata.json"] = FileWrapper(regularFileWithContents: try JSONEncoder().encode(legacyMetadata))
        legacyChildren.removeValue(forKey: "floating-images")
        let migrated = try BOLDWriterDocument(fileWrapper: FileWrapper(directoryWithFileWrappers: legacyChildren), contentType: .boldWriterDocument)
        XCTAssertEqual(migrated.metadata.floatingImages?.first?.imageData, bytes)
        XCTAssertNil(migrated.metadata.floatingImages?.first?.assetDigest)
        let migratedSave = try BOLDWriterDocument.packageWrapper(text: migrated.text, metadata: migrated.metadata)
        XCTAssertEqual(migratedSave.fileWrappers?["floating-images"]?.fileWrappers?.count, 1)
    }

    @MainActor
    func testDOCXExportPreservesSupportedPageAnchoredFloatingPlacement() throws {
        let document = BOLDWriterDocument()
        document.text = NSAttributedString(string: "Floating image anchor\n")
        document.metadata.floatingImages = [
            FloatingImage(assetName: "image.png", imageData: try opaquePNG(), x: 72, y: 72, width: 120, height: 120)
        ]
        let data = try ExportService.data(for: .docx, document: document)
        let entries = try DOCXPackage.entries(in: data)
        let parts = Dictionary(uniqueKeysWithValues: entries.map { ($0.path, $0.data) })
        let xml = try DOCXPackage.xml(try XCTUnwrap(parts["word/document.xml"]))
        XCTAssertEqual(try xml.nodes(forXPath: "//*[local-name()='anchor']").count, 1)
        XCTAssertEqual(try xml.nodes(forXPath: "//*[local-name()='inline']").count, 0)
        XCTAssertEqual(try xml.nodes(forXPath: "//*[local-name()='positionH']/*[local-name()='posOffset']/text()")
            .compactMap(\.stringValue), ["914400"])
        XCTAssertEqual(try xml.nodes(forXPath: "//*[local-name()='positionV']/*[local-name()='posOffset']/text()")
            .compactMap(\.stringValue), ["914400"])
        XCTAssertEqual(parts["word/media/floating1.png"], document.metadata.floatingImages?.first?.imageData)
    }

    @MainActor
    func testAtomicCrashRecoveryCheckpointReopensAndConsumesMatchingSnapshot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let document = BOLDWriterDocument()
        document.text = NSAttributedString(string: "Saved manuscript\n")
        document.metadata.floatingImages = [
            FloatingImage(assetName: "image.png", imageData: try opaquePNG(), x: 72, y: 72, width: 120, height: 120)
        ]
        let checkpoint = try FloatingImageRecovery.save(text: document.text, metadata: document.metadata, root: root)
        XCTAssertTrue(FileManager.default.fileExists(atPath: checkpoint.path))

        var reopenedText = document.text.copy() as! NSAttributedString
        var reopenedMetadata = document.metadata
        XCTAssertTrue(try FloatingImageRecovery.restore(text: &reopenedText, metadata: &reopenedMetadata, root: root))
        XCTAssertEqual(reopenedText.string, "Saved manuscript\n")
        XCTAssertEqual(reopenedMetadata.floatingImages?.first?.imageData, document.metadata.floatingImages?.first?.imageData)
        XCTAssertEqual(reopenedMetadata.floatingImages?.first?.id, document.metadata.floatingImages?.first?.id)
        XCTAssertEqual(reopenedMetadata.floatingImages?.first?.x, document.metadata.floatingImages?.first?.x)
        XCTAssertFalse(FileManager.default.fileExists(atPath: checkpoint.path), "A restored checkpoint is consumed to prevent repeated recovery prompts.")
    }

    private func opaquePNG() throws -> Data {
        try rgbaPNG(opaquePixels: Set(0..<64))
    }

    private func rotatedTightFixturePNG() throws -> Data {
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

    private func rgbaPNG(opaquePixels: Set<Int>) throws -> Data {
        var pixels = [UInt8](repeating: 0, count: 8 * 8 * 4)
        for index in opaquePixels {
            let offset = index * 4
            pixels[offset] = 255
            pixels[offset + 3] = 255
        }
        let data = pixels.withUnsafeBytes { Data($0) }
        let provider = CGDataProvider(data: data as CFData)!
        let image = CGImage(width: 8, height: 8, bitsPerComponent: 8, bitsPerPixel: 32,
                            bytesPerRow: 32, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false,
                            intent: .defaultIntent)!
        return try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
