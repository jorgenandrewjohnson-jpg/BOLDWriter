import AppKit
import XCTest
@testable import BOLDWriter

final class CoverTypographyPanelTests: XCTestCase {
    func testCanvasPreviewPreservesExportTextWrappingAndNormalizedInkBounds() throws {
        var project = CoverProject(type: .ebookFront, width: 6, height: 9)
        var layer = CoverLayer(kind: .text, name: "Title", frame: CoverRect(x: 0.1, y: 0.1, width: 0.8, height: 0.3))
        layer.text = "A BEAUTIFUL\nSAMPLE BOOK"
        layer.fontName = "Baskerville-Bold"; layer.fontSize = 90; layer.colorHex = "#000000"
        project.layers = [layer]; project.backgroundHex = "#FFFFFF"
        func inkBounds(scale: Double) throws -> CGRect {
            let image = try CoverArtwork.render(project, scale: scale)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
            var minX = bitmap.pixelsWide, minY = bitmap.pixelsHigh, maxX = -1, maxY = -1
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), color.redComponent < 0.4 else { continue }
                    minX = min(minX, x); minY = min(minY, y); maxX = max(maxX, x); maxY = max(maxY, y)
                }
            }
            XCTAssertGreaterThan(maxX, minX); XCTAssertGreaterThan(maxY, minY)
            return CGRect(x: Double(minX) / Double(bitmap.pixelsWide), y: Double(minY) / Double(bitmap.pixelsHigh),
                          width: Double(maxX-minX) / Double(bitmap.pixelsWide), height: Double(maxY-minY) / Double(bitmap.pixelsHigh))
        }
        let exported = try inkBounds(scale: 100), preview = try inkBounds(scale: 30)
        XCTAssertEqual(preview.minX, exported.minX, accuracy: 0.015)
        XCTAssertEqual(preview.minY, exported.minY, accuracy: 0.015)
        XCTAssertEqual(preview.width, exported.width, accuracy: 0.015)
        XCTAssertEqual(preview.height, exported.height, accuracy: 0.015)
    }

    private func textLayer() -> CoverLayer {
        var layer =
            CoverLayer(
                kind: .text,
                name: "Typography",
                frame:
                    CoverRect(
                        x: 0.10,
                        y: 0.20,
                        width: 0.80,
                        height: 0.45
                    )
            )

        layer.text =
            "BOLD Writer\nTypography"

        layer.fontName =
            NSFont.systemFont(
                ofSize: 24
            ).familyName
            ?? "Helvetica"

        layer.fontSize = 24
        layer.colorHex = "#202020"

        return layer
    }

    func testCharacterAttributesUseExistingCoverLayerTypography() throws {
        var layer = textLayer()

        layer.bold = true
        layer.italic = true
        layer.underline = true
        layer.strikethrough = true
        layer.letterSpacing = 2.5
        layer.baselineShift = 4

        let attributes =
            CoverTypography.attributes(
                for: layer
            )

        let font =
            try XCTUnwrap(
                attributes[.font]
                as? NSFont
            )

        let traits =
            NSFontManager.shared.traits(
                of: font
            )

        XCTAssertTrue(
            traits.contains(
                .boldFontMask
            )
        )

        XCTAssertTrue(
            traits.contains(
                .italicFontMask
            )
        )

        XCTAssertEqual(
            attributes[
                .underlineStyle
            ] as? Int,
            NSUnderlineStyle.single.rawValue
        )

        XCTAssertEqual(
            attributes[
                .strikethroughStyle
            ] as? Int,
            NSUnderlineStyle.single.rawValue
        )

        let baseline =
            try XCTUnwrap(
                (
                    attributes[
                        .baselineOffset
                    ] as? NSNumber
                )?.doubleValue
            )

        XCTAssertEqual(
            baseline,
            4,
            accuracy: 0.001
        )

        let kern =
            try XCTUnwrap(
                (
                    attributes[
                        .kern
                    ] as? NSNumber
                )?.doubleValue
            )

        XCTAssertEqual(
            kern,
            2.5,
            accuracy: 0.001
        )
    }

    func testParagraphStyleSupportsJustificationLeadingIndentAndSpacing() throws {
        var layer = textLayer()

        layer.alignment = "justified"
        layer.lineSpacing = 3
        layer.leading = 32
        layer.paragraphIndent = 12
        layer.paragraphSpacing = 9

        let paragraph =
            try XCTUnwrap(
                CoverTypography
                    .attributes(
                        for: layer
                    )[
                        .paragraphStyle
                    ]
                as? NSParagraphStyle
            )

        XCTAssertEqual(
            paragraph.alignment,
            .justified
        )

        XCTAssertEqual(
            paragraph.lineSpacing,
            3,
            accuracy: 0.001
        )

        XCTAssertEqual(
            paragraph.minimumLineHeight,
            32,
            accuracy: 0.001
        )

        XCTAssertEqual(
            paragraph.maximumLineHeight,
            32,
            accuracy: 0.001
        )

        XCTAssertEqual(
            paragraph.firstLineHeadIndent,
            12,
            accuracy: 0.001
        )

        XCTAssertEqual(
            paragraph.paragraphSpacing,
            9,
            accuracy: 0.001
        )
    }

    func testTypographyFieldsPersistThroughCoverProjectRoundTrip() throws {
        var project =
            CoverProject(
                width: 6,
                height: 9
            )

        var layer = textLayer()

        layer.leading = 31
        layer.horizontalScale = 1.25
        layer.verticalScale = 0.90
        layer.baselineShift = 3
        layer.underline = true
        layer.strikethrough = true
        layer.paragraphIndent = 14
        layer.paragraphSpacing = 11
        layer.alignment = "justified"

        project.layers = [
            layer
        ]

        let reopened =
            try JSONDecoder().decode(
                CoverProject.self,
                from:
                    JSONEncoder().encode(
                        project
                    )
            )

        let result =
            try XCTUnwrap(
                reopened.layers.first
            )

        XCTAssertEqual(
            result.leading,
            31
        )

        XCTAssertEqual(
            result.horizontalScale,
            1.25
        )

        XCTAssertEqual(
            result.verticalScale,
            0.90
        )

        XCTAssertEqual(
            result.baselineShift,
            3
        )

        XCTAssertEqual(
            result.underline,
            true
        )

        XCTAssertEqual(
            result.strikethrough,
            true
        )

        XCTAssertEqual(
            result.paragraphIndent,
            14
        )

        XCTAssertEqual(
            result.paragraphSpacing,
            11
        )

        XCTAssertEqual(
            result.alignment,
            "justified"
        )

        XCTAssertNoThrow(
            try CoverProject.validate(
                [reopened]
            )
        )
    }

    func testFontFamilySourceUsesInstalledMacFonts() {
        let families =
            CoverTypography.fontFamilies

        XCTAssertFalse(
            families.isEmpty
        )

        XCTAssertEqual(
            families,
            Array(
                Set(families)
            ).sorted {
                $0.localizedCaseInsensitiveCompare(
                    $1
                ) == .orderedAscending
            }
        )
    }

    func testCharacterAndParagraphPanelsAreSessionOnlyWorkspaceState() {
        var workspace =
            CoverWorkspaceState()

        XCTAssertFalse(
            workspace.character
        )

        XCTAssertFalse(
            workspace.paragraph
        )

        workspace.layers = false
        workspace.paths = false
        workspace.properties = false
        workspace.adjustments = false
        workspace.historyAndSwatches = false
        workspace.character = true
        workspace.paragraph = false

        XCTAssertTrue(
            workspace.hasPanels
        )

        workspace.character = false
        workspace.paragraph = true

        XCTAssertTrue(
            workspace.hasPanels
        )

        workspace.paragraph = false

        XCTAssertFalse(
            workspace.hasPanels
        )
    }

    func testTypographyChangesProductionRendering() throws {
        var baseline =
            CoverProject(
                width: 2,
                height: 2
            )

        baseline.backgroundHex =
            "#FFFFFF"

        baseline.layers = [
            textLayer()
        ]

        var formatted =
            baseline

        formatted.layers[0].italic = true
        formatted.layers[0].underline = true
        formatted.layers[0].letterSpacing = 5
        formatted.layers[0].horizontalScale = 1.30
        formatted.layers[0].verticalScale = 0.85
        formatted.layers[0].baselineShift = 3
        formatted.layers[0].paragraphSpacing = 8

        let plain =
            try XCTUnwrap(
                try CoverArtwork.render(
                    baseline,
                    scale: 120
                )
                .tiffRepresentation
            )

        let styled =
            try XCTUnwrap(
                try CoverArtwork.render(
                    formatted,
                    scale: 120
                )
                .tiffRepresentation
            )

        XCTAssertNotEqual(
            plain,
            styled
        )
    }

    func testAllSupportedParagraphAlignmentsProduceNativeAlignment() {
        let expected:
            [String: NSTextAlignment] = [
                "left": .left,
                "center": .center,
                "right": .right,
                "justified": .justified
            ]

        for alignment in
            CoverTypography.alignments
        {
            var layer =
                textLayer()

            layer.alignment =
                alignment

            let expectedAlignment =
                expected[
                    alignment
                ]

            XCTAssertEqual(
                CoverTypography
                    .paragraphStyle(
                        for: layer
                    )
                    .alignment,
                expectedAlignment
            )
        }
    }
}
