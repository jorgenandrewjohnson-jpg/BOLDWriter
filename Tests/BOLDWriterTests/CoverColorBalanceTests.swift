import AppKit
import XCTest
@testable import BOLDWriter

final class CoverColorBalanceTests: XCTestCase {
    private func project(
        values: [String: Double]? = nil
    ) -> CoverProject {
        var project =
            CoverProject(
                width: 1,
                height: 1
            )

        project.backgroundHex =
            "#808080"

        var artwork =
            CoverLayer(
                kind: .shape,
                name: "Neutral Gray",
                frame:
                    CoverRect(
                        x: 0,
                        y: 0,
                        width: 1,
                        height: 1
                    )
            )

        artwork.fillHex =
            "#808080"

        artwork.strokeHex =
            "#808080"

        artwork.strokeWidth = 0

        project.layers = [
            artwork
        ]

        if let values {
            var adjustment =
                CoverLayer(
                    kind: .adjustment,
                    name: "Color Balance",
                    frame: CoverRect()
                )

            adjustment.adjustment =
                .colorBalance

            adjustment.adjustmentValues =
                values

            project.layers.append(
                adjustment
            )
        }

        return project
    }

    private func bitmap(
        _ project: CoverProject
    ) throws -> NSBitmapImageRep {
        let image =
            try CoverArtwork.render(
                project,
                scale: 100
            )

        let data =
            try XCTUnwrap(
                image.tiffRepresentation
            )

        return try XCTUnwrap(
            NSBitmapImageRep(
                data: data
            )
        )
    }

    private func centerColor(
        _ project: CoverProject
    ) throws -> NSColor {
        let bitmap =
            try bitmap(
                project
            )

        let color =
            try XCTUnwrap(
                bitmap.colorAt(
                    x: 50,
                    y: 50
                )
            )

        return color.usingColorSpace(
            .deviceRGB
        )
        ?? color
    }

    func testColorBalanceControlsExposeThreeNeutralAxes() {
        let controls =
            CoverAdjustmentControl.controls(
                for: .colorBalance
            )

        XCTAssertEqual(
            controls.map(\.key),
            [
                "cyanRed",
                "magentaGreen",
                "yellowBlue"
            ]
        )

        XCTAssertEqual(
            controls.map(\.initial),
            [
                0,
                0,
                0
            ]
        )

        XCTAssertEqual(
            CoverAdjustmentKind
                .colorBalance
                .workspaceTitle,
            "Color Balance"
        )
    }

    func testPositiveCyanRedMovesNeutralGrayTowardRed() throws {
        let color =
            try centerColor(
                project(
                    values: [
                        "cyanRed": 0.55,
                        "magentaGreen": 0,
                        "yellowBlue": 0
                    ]
                )
            )

        XCTAssertGreaterThan(
            color.redComponent,
            color.greenComponent + 0.15
        )

        XCTAssertGreaterThan(
            color.redComponent,
            color.blueComponent + 0.15
        )
    }

    func testNegativeCyanRedMovesNeutralGrayTowardCyan() throws {
        let color =
            try centerColor(
                project(
                    values: [
                        "cyanRed": -0.45,
                        "magentaGreen": 0,
                        "yellowBlue": 0
                    ]
                )
            )

        XCTAssertLessThan(
            color.redComponent + 0.15,
            color.greenComponent
        )

        XCTAssertLessThan(
            color.redComponent + 0.15,
            color.blueComponent
        )
    }

    func testAllThreeColorBalanceAxesAffectDistinctChannels() throws {
        let red =
            try centerColor(
                project(
                    values: [
                        "cyanRed": 0.4
                    ]
                )
            )

        let green =
            try centerColor(
                project(
                    values: [
                        "magentaGreen": 0.4
                    ]
                )
            )

        let blue =
            try centerColor(
                project(
                    values: [
                        "yellowBlue": 0.4
                    ]
                )
            )

        XCTAssertGreaterThan(
            red.redComponent,
            red.greenComponent
        )

        XCTAssertGreaterThan(
            green.greenComponent,
            green.redComponent
        )

        XCTAssertGreaterThan(
            blue.blueComponent,
            blue.redComponent
        )
    }

    func testColorBalancePersistsThroughProjectRoundTrip() throws {
        let original =
            project(
                values: [
                    "cyanRed": 0.25,
                    "magentaGreen": -0.30,
                    "yellowBlue": 0.15
                ]
            )

        let reopened =
            try JSONDecoder().decode(
                CoverProject.self,
                from:
                    JSONEncoder().encode(
                        original
                    )
            )

        let adjustment =
            try XCTUnwrap(
                reopened.layers.last
            )

        XCTAssertEqual(
            adjustment.adjustment,
            .colorBalance
        )

        XCTAssertEqual(
            adjustment.adjustmentValues?[
                "cyanRed"
            ],
            0.25
        )

        XCTAssertEqual(
            adjustment.adjustmentValues?[
                "magentaGreen"
            ],
            -0.30
        )

        XCTAssertEqual(
            adjustment.adjustmentValues?[
                "yellowBlue"
            ],
            0.15
        )
    }

    func testColorBalanceChangesProductionPNGExport() throws {
        var plain =
            project()

        plain.dpi = 72

        var balanced =
            project(
                values: [
                    "cyanRed": 0.5,
                    "magentaGreen": -0.15,
                    "yellowBlue": 0.25
                ]
            )

        balanced.dpi = 72

        let plainPNG =
            try CoverArtwork.export(
                plain,
                format: "png"
            )

        let balancedPNG =
            try CoverArtwork.export(
                balanced,
                format: "png"
            )

        XCTAssertNotEqual(
            plainPNG,
            balancedPNG
        )
    }

    func testNeutralColorBalanceLeavesRenderedPixelsEquivalent() throws {
        let plain =
            try centerColor(
                project()
            )

        let neutral =
            try centerColor(
                project(
                    values: [
                        "cyanRed": 0,
                        "magentaGreen": 0,
                        "yellowBlue": 0
                    ]
                )
            )

        XCTAssertEqual(
            plain.redComponent,
            neutral.redComponent,
            accuracy: 0.02
        )

        XCTAssertEqual(
            plain.greenComponent,
            neutral.greenComponent,
            accuracy: 0.02
        )

        XCTAssertEqual(
            plain.blueComponent,
            neutral.blueComponent,
            accuracy: 0.02
        )
    }
}
