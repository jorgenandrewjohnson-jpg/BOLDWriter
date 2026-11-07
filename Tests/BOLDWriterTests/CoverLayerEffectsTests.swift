import AppKit
import XCTest
@testable import BOLDWriter

final class CoverLayerEffectsTests: XCTestCase {
    private func project(
        fill: String = "#202020"
    ) -> CoverProject {
        var project = CoverProject(
            width: 1,
            height: 1
        )

        project.backgroundHex = "#FFFFFF"

        var shape = CoverLayer(
            kind: .shape,
            name: "Square",
            frame: CoverRect(
                x: 0.30,
                y: 0.30,
                width: 0.40,
                height: 0.40
            )
        )

        shape.fillHex = fill
        shape.strokeHex = fill
        shape.strokeWidth = 0

        project.layers = [
            shape
        ]

        return project
    }

    private func bitmap(
        _ project: CoverProject
    ) throws -> NSBitmapImageRep {
        let image = try CoverArtwork.render(
            project,
            scale: 100
        )

        let data = try XCTUnwrap(
            image.tiffRepresentation
        )

        return try XCTUnwrap(
            NSBitmapImageRep(
                data: data
            )
        )
    }

    private func color(
        _ bitmap: NSBitmapImageRep,
        x: Int,
        y: Int
    ) throws -> NSColor {
        try XCTUnwrap(
            bitmap.colorAt(
                x: x,
                y: y
            )
        ).usingColorSpace(
            .deviceRGB
        ) ?? .black
    }

    func testAllLayerEffectsPersistThroughProjectRoundTrip() throws {
        var project = project()

        project.layers[0].dropShadow =
            CoverDropShadow(
                colorHex: "#112233",
                opacity: 0.4,
                angle: 15,
                distance: 0.03,
                blur: 0.04,
                enabled: true
            )

        project.layers[0].innerShadow =
            CoverInnerShadow(
                colorHex: "#223344",
                opacity: 0.5,
                angle: -20,
                distance: 0.02,
                blur: 0.03,
                enabled: true
            )

        project.layers[0].strokeEffect =
            CoverStrokeEffect(
                colorHex: "#334455",
                opacity: 0.6,
                width: 0.025,
                enabled: true
            )

        project.layers[0].colorOverlay =
            CoverColorOverlay(
                colorHex: "#445566",
                opacity: 0.7,
                enabled: true
            )

        project.layers[0].gradientOverlay =
            CoverGradientOverlay(
                startHex: "#556677",
                endHex: "#778899",
                opacity: 0.8,
                angle: 35,
                enabled: true
            )

        project.layers[0].outerGlow =
            CoverOuterGlow(
                colorHex: "#8899AA",
                opacity: 0.9,
                size: 0.05,
                enabled: true
            )

        let reopened = try JSONDecoder().decode(
            CoverProject.self,
            from: JSONEncoder().encode(
                project
            )
        )

        XCTAssertEqual(
            reopened.layers[0].dropShadow,
            project.layers[0].dropShadow
        )

        XCTAssertEqual(
            reopened.layers[0].innerShadow,
            project.layers[0].innerShadow
        )

        XCTAssertEqual(
            reopened.layers[0].strokeEffect,
            project.layers[0].strokeEffect
        )

        XCTAssertEqual(
            reopened.layers[0].colorOverlay,
            project.layers[0].colorOverlay
        )

        XCTAssertEqual(
            reopened.layers[0].gradientOverlay,
            project.layers[0].gradientOverlay
        )

        XCTAssertEqual(
            reopened.layers[0].outerGlow,
            project.layers[0].outerGlow
        )

        XCTAssertNoThrow(
            try CoverProject.validate(
                [reopened]
            )
        )
    }

    func testColorOverlayChangesRenderedLayerPixels() throws {
        var project = project(
            fill: "#000000"
        )

        project.layers[0].colorOverlay =
            CoverColorOverlay(
                colorHex: "#FF0000",
                opacity: 1,
                enabled: true
            )

        let bitmap = try bitmap(
            project
        )

        let center = try color(
            bitmap,
            x: 50,
            y: 50
        )

        XCTAssertGreaterThan(
            center.redComponent,
            0.85
        )

        XCTAssertLessThan(
            center.greenComponent,
            0.20
        )

        XCTAssertLessThan(
            center.blueComponent,
            0.20
        )
    }

    func testGradientOverlayProducesDifferentColorsAcrossLayer() throws {
        var project = project(
            fill: "#FFFFFF"
        )

        project.layers[0].gradientOverlay =
            CoverGradientOverlay(
                startHex: "#FF0000",
                endHex: "#0000FF",
                opacity: 1,
                angle: 0,
                enabled: true
            )

        let bitmap = try bitmap(
            project
        )

        let left = try color(
            bitmap,
            x: 35,
            y: 50
        )

        let right = try color(
            bitmap,
            x: 65,
            y: 50
        )

        let difference =
            abs(
                left.redComponent -
                right.redComponent
            )
            +
            abs(
                left.blueComponent -
                right.blueComponent
            )

        XCTAssertGreaterThan(
            difference,
            0.25
        )
    }

    func testStrokeEffectExpandsBeyondOriginalLayerBounds() throws {
        var project = project(
            fill: "#000000"
        )

        project.layers[0].strokeEffect =
            CoverStrokeEffect(
                colorHex: "#FF0000",
                opacity: 1,
                width: 0.06,
                enabled: true
            )

        let bitmap = try bitmap(
            project
        )

        let outside = try color(
            bitmap,
            x: 26,
            y: 50
        )

        XCTAssertGreaterThan(
            outside.redComponent,
            outside.greenComponent + 0.20
        )
    }

    func testOuterGlowChangesProductionRendering() throws {
        let baseline = project(
            fill: "#000000"
        )

        var effected = baseline

        effected.layers[0].outerGlow =
            CoverOuterGlow(
                colorHex: "#FF0000",
                opacity: 1,
                size: 0.08,
                enabled: true
            )

        let before = try XCTUnwrap(
            try CoverArtwork.render(
                baseline,
                scale: 100
            ).tiffRepresentation
        )

        let after = try XCTUnwrap(
            try CoverArtwork.render(
                effected,
                scale: 100
            ).tiffRepresentation
        )

        XCTAssertNotEqual(
            before,
            after
        )
    }

    func testInnerShadowChangesProductionRendering() throws {
        let baseline = project(
            fill: "#FFFFFF"
        )

        var effected = baseline

        effected.layers[0].innerShadow =
            CoverInnerShadow(
                colorHex: "#000000",
                opacity: 1,
                angle: 0,
                distance: 0.04,
                blur: 0.05,
                enabled: true
            )

        let before = try XCTUnwrap(
            try CoverArtwork.render(
                baseline,
                scale: 100
            ).tiffRepresentation
        )

        let after = try XCTUnwrap(
            try CoverArtwork.render(
                effected,
                scale: 100
            ).tiffRepresentation
        )

        XCTAssertNotEqual(
            before,
            after
        )
    }

    func testExistingDropShadowStillChangesRendering() throws {
        let baseline = project(
            fill: "#000000"
        )

        var effected = baseline

        effected.layers[0].dropShadow =
            CoverDropShadow(
                colorHex: "#FF0000",
                opacity: 1,
                angle: 0,
                distance: 0.08,
                blur: 0.03,
                enabled: true
            )

        let before = try XCTUnwrap(
            try CoverArtwork.render(
                baseline,
                scale: 100
            ).tiffRepresentation
        )

        let after = try XCTUnwrap(
            try CoverArtwork.render(
                effected,
                scale: 100
            ).tiffRepresentation
        )

        XCTAssertNotEqual(
            before,
            after
        )
    }

    func testProductionPNGExportIncludesLayerEffects() throws {
        var baseline = project(
            fill: "#000000"
        )

        baseline.dpi = 72

        var effected = baseline

        effected.layers[0].colorOverlay =
            CoverColorOverlay(
                colorHex: "#00FF00",
                opacity: 1,
                enabled: true
            )

        let plain = try CoverArtwork.export(
            baseline,
            format: "png"
        )

        let withEffect = try CoverArtwork.export(
            effected,
            format: "png"
        )

        XCTAssertNotEqual(
            plain,
            withEffect
        )
    }
}
