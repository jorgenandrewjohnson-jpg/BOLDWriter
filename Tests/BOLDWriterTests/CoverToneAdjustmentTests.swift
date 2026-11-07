import AppKit
import XCTest
@testable import BOLDWriter

final class CoverToneAdjustmentTests: XCTestCase {
    private func solidProject(
        hex:String
    ) -> CoverProject {
        var project =
            CoverProject(
                width:1,
                height:1
            )

        project.backgroundHex = hex

        var shape =
            CoverLayer(
                kind:.shape,
                name:"Solid",
                frame:
                    CoverRect(
                        x:0,
                        y:0,
                        width:1,
                        height:1
                    )
            )

        shape.fillHex = hex
        shape.strokeHex = hex
        shape.strokeWidth = 0

        project.layers = [
            shape
        ]

        return project
    }

    private func adding(
        _ kind:CoverAdjustmentKind,
        values:[String:Double],
        fillHex:String = "#FFFFFF",
        to project:CoverProject
    ) -> CoverProject {
        var copy = project

        var adjustment =
            CoverLayer(
                kind:.adjustment,
                name:kind.workspaceTitle,
                frame:CoverRect()
            )

        adjustment.adjustment = kind
        adjustment.adjustmentValues = values
        adjustment.fillHex = fillHex

        copy.layers.append(
            adjustment
        )

        return copy
    }

    private func centerColor(
        _ project:CoverProject
    ) throws -> NSColor {
        let image =
            try CoverArtwork.render(
                project,
                scale:100
            )

        let rep =
            try XCTUnwrap(
                NSBitmapImageRep(
                    data:
                        try XCTUnwrap(
                            image.tiffRepresentation
                        )
                )
            )

        return try XCTUnwrap(
            rep.colorAt(
                x:rep.pixelsWide / 2,
                y:rep.pixelsHigh / 2
            )?
            .usingColorSpace(
                .deviceRGB
            )
        )
    }

    func testLevelsControlsExposeFivePrecisionParameters() {
        let controls =
            CoverAdjustmentControl.controls(
                for:.levels
            )

        XCTAssertEqual(
            controls.map(\.key),
            [
                "inputBlack",
                "gamma",
                "inputWhite",
                "outputBlack",
                "outputWhite"
            ]
        )

        XCTAssertEqual(
            controls.map(\.initial),
            [
                0,
                1,
                1,
                0,
                1
            ]
        )
    }

    func testLevelsInputBlackCrushesDarkPixels() throws {
        let adjusted =
            try centerColor(
                adding(
                    .levels,
                    values:[
                        "inputBlack":0.45,
                        "gamma":1,
                        "inputWhite":1,
                        "outputBlack":0,
                        "outputWhite":1
                    ],
                    to:
                        solidProject(
                            hex:"#505050"
                        )
                )
            )

        XCTAssertLessThan(
            adjusted.redComponent,
            0.05
        )
    }

    func testLevelsGammaLightensMidtones() throws {
        let plain =
            try centerColor(
                solidProject(
                    hex:"#808080"
                )
            )

        let adjusted =
            try centerColor(
                adding(
                    .levels,
                    values:[
                        "inputBlack":0,
                        "gamma":2,
                        "inputWhite":1,
                        "outputBlack":0,
                        "outputWhite":1
                    ],
                    to:
                        solidProject(
                            hex:"#808080"
                        )
                )
            )

        XCTAssertGreaterThan(
            adjusted.redComponent,
            plain.redComponent + 0.12
        )
    }

    func testLevelsOutputRangeMatchesPerceptualUIValues() throws {
        let dark =
            try centerColor(
                adding(
                    .levels,
                    values:[
                        "outputBlack":0.20,
                        "outputWhite":0.80
                    ],
                    to:
                        solidProject(
                            hex:"#000000"
                        )
                )
            )

        let light =
            try centerColor(
                adding(
                    .levels,
                    values:[
                        "outputBlack":0.20,
                        "outputWhite":0.80
                    ],
                    to:
                        solidProject(
                            hex:"#FFFFFF"
                        )
                )
            )

        XCTAssertEqual(
            dark.redComponent,
            0.20,
            accuracy:0.06
        )

        XCTAssertEqual(
            light.redComponent,
            0.80,
            accuracy:0.06
        )

        XCTAssertLessThan(
            light.redComponent,
            0.86
        )
    }

    func testCurvesExposeFiveRealTonePoints() {
        let controls =
            CoverAdjustmentControl.controls(
                for:.curves
            )

        XCTAssertEqual(
            controls.map(\.key),
            [
                "curve0",
                "curve1",
                "curve2",
                "curve3",
                "curve4"
            ]
        )

        XCTAssertEqual(
            controls.map(\.initial),
            [
                0,
                0.25,
                0.50,
                0.75,
                1
            ]
        )
    }

    func testNeutralCurvePreservesMidtone() throws {
        let plain =
            try centerColor(
                solidProject(
                    hex:"#808080"
                )
            )

        let adjusted =
            try centerColor(
                adding(
                    .curves,
                    values:[
                        "curve0":0,
                        "curve1":0.25,
                        "curve2":0.50,
                        "curve3":0.75,
                        "curve4":1
                    ],
                    to:
                        solidProject(
                            hex:"#808080"
                        )
                )
            )

        XCTAssertEqual(
            adjusted.redComponent,
            plain.redComponent,
            accuracy:0.035
        )
    }

    func testCurveMidpointRaisesMidtones() throws {
        let plain =
            try centerColor(
                solidProject(
                    hex:"#808080"
                )
            )

        let adjusted =
            try centerColor(
                adding(
                    .curves,
                    values:[
                        "curve0":0,
                        "curve1":0.35,
                        "curve2":0.78,
                        "curve3":0.90,
                        "curve4":1
                    ],
                    to:
                        solidProject(
                            hex:"#808080"
                        )
                )
            )

        XCTAssertGreaterThan(
            adjusted.redComponent,
            plain.redComponent + 0.12
        )
    }

    func testCrossedCurveRequestsRemainMonotonicAcrossInputTones() throws {
        let values = [
            "curve0":0.75,
            "curve1":0.10,
            "curve2":0.20,
            "curve3":0.30,
            "curve4":1.0
        ]

        let low =
            try centerColor(
                adding(
                    .curves,
                    values:values,
                    to:
                        solidProject(
                            hex:"#202020"
                        )
                )
            )

        let mid =
            try centerColor(
                adding(
                    .curves,
                    values:values,
                    to:
                        solidProject(
                            hex:"#808080"
                        )
                )
            )

        let high =
            try centerColor(
                adding(
                    .curves,
                    values:values,
                    to:
                        solidProject(
                            hex:"#E0E0E0"
                        )
                )
            )

        XCTAssertLessThanOrEqual(
            low.redComponent,
            mid.redComponent + 0.03
        )

        XCTAssertLessThanOrEqual(
            mid.redComponent,
            high.redComponent + 0.03
        )
    }

    func testBlackWhiteControlsExposeSixColorWeights() {
        let controls =
            CoverAdjustmentControl.controls(
                for:.monochrome
            )

        XCTAssertEqual(
            controls.map(\.key),
            [
                "bwReds",
                "bwYellows",
                "bwGreens",
                "bwCyans",
                "bwBlues",
                "bwMagentas"
            ]
        )
    }

    func testBlackWhiteRedWeightControlsPureRedBrightness() throws {
        let low =
            try centerColor(
                adding(
                    .monochrome,
                    values:[
                        "bwReds":0.15
                    ],
                    to:
                        solidProject(
                            hex:"#FF0000"
                        )
                )
            )

        let high =
            try centerColor(
                adding(
                    .monochrome,
                    values:[
                        "bwReds":0.90
                    ],
                    to:
                        solidProject(
                            hex:"#FF0000"
                        )
                )
            )

        XCTAssertGreaterThan(
            high.redComponent,
            low.redComponent + 0.35
        )

        XCTAssertEqual(
            high.redComponent,
            high.greenComponent,
            accuracy:0.03
        )

        XCTAssertEqual(
            high.greenComponent,
            high.blueComponent,
            accuracy:0.03
        )
    }

    func testBlackWhiteTintUsesLayerTintColor() throws {
        let neutral =
            try centerColor(
                adding(
                    .monochrome,
                    values:[
                        "blackWhiteTint":0
                    ],
                    fillHex:"#FF0000",
                    to:
                        solidProject(
                            hex:"#FFFFFF"
                        )
                )
            )

        let tinted =
            try centerColor(
                adding(
                    .monochrome,
                    values:[
                        "blackWhiteTint":1
                    ],
                    fillHex:"#FF0000",
                    to:
                        solidProject(
                            hex:"#FFFFFF"
                        )
                )
            )

        XCTAssertEqual(
            neutral.redComponent,
            neutral.greenComponent,
            accuracy:0.03
        )

        XCTAssertGreaterThan(
            tinted.redComponent,
            tinted.greenComponent + 0.60
        )

        XCTAssertGreaterThan(
            tinted.redComponent,
            tinted.blueComponent + 0.60
        )
    }

    func testToneAdjustmentsPersistThroughRoundTrip() throws {
        var project =
            solidProject(
                hex:"#808080"
            )

        var levels =
            CoverLayer(
                kind:.adjustment,
                name:"Levels"
            )

        levels.adjustment = .levels
        levels.adjustmentValues = [
            "inputBlack":0.12,
            "gamma":1.35,
            "inputWhite":0.92,
            "outputBlack":0.04,
            "outputWhite":0.96
        ]

        var curves =
            CoverLayer(
                kind:.adjustment,
                name:"Curves"
            )

        curves.adjustment = .curves
        curves.adjustmentValues = [
            "curve0":0,
            "curve1":0.18,
            "curve2":0.55,
            "curve3":0.84,
            "curve4":1
        ]

        var blackWhite =
            CoverLayer(
                kind:.adjustment,
                name:"Black & White"
            )

        blackWhite.adjustment = .monochrome
        blackWhite.fillHex = "#C7A46A"
        blackWhite.adjustmentValues = [
            "bwReds":0.5,
            "bwYellows":0.7,
            "bwGreens":0.4,
            "bwCyans":0.5,
            "bwBlues":0.25,
            "bwMagentas":0.75,
            "blackWhiteTint":1
        ]

        project.layers += [
            levels,
            curves,
            blackWhite
        ]

        let reopened =
            try JSONDecoder().decode(
                CoverProject.self,
                from:
                    JSONEncoder().encode(
                        project
                    )
            )

        XCTAssertEqual(
            reopened.layers[
                reopened.layers.count - 3
            ]
            .adjustmentValues?[
                "gamma"
            ],
            1.35
        )

        XCTAssertEqual(
            reopened.layers[
                reopened.layers.count - 2
            ]
            .adjustmentValues?[
                "curve3"
            ],
            0.84
        )

        let reopenedBlackWhite =
            try XCTUnwrap(
                reopened.layers.last
            )

        XCTAssertEqual(
            reopenedBlackWhite.adjustment,
            .monochrome
        )

        XCTAssertEqual(
            reopenedBlackWhite.fillHex,
            "#C7A46A"
        )

        XCTAssertEqual(
            reopenedBlackWhite.adjustmentValues?[
                "blackWhiteTint"
            ],
            1
        )
    }

    func testToneAdjustmentsAffectProductionPNGExport() throws {
        var base =
            solidProject(
                hex:"#777777"
            )

        base.dpi = 72

        let baseline =
            try CoverArtwork.export(
                base,
                format:"png"
            )

        let cases:
            [
                (
                    CoverAdjustmentKind,
                    [String:Double],
                    String
                )
            ] = [
                (
                    .levels,
                    [
                        "inputBlack":0.30,
                        "gamma":1.6,
                        "inputWhite":0.85,
                        "outputBlack":0.05,
                        "outputWhite":0.90
                    ],
                    "#FFFFFF"
                ),
                (
                    .curves,
                    [
                        "curve0":0,
                        "curve1":0.15,
                        "curve2":0.72,
                        "curve3":0.88,
                        "curve4":1
                    ],
                    "#FFFFFF"
                ),
                (
                    .monochrome,
                    [
                        "bwReds":0.9,
                        "bwYellows":0.2,
                        "bwGreens":0.7,
                        "bwCyans":0.3,
                        "bwBlues":0.1,
                        "bwMagentas":0.8,
                        "blackWhiteTint":1
                    ],
                    "#C07040"
                )
            ]

        for item in cases {
            var adjusted =
                adding(
                    item.0,
                    values:item.1,
                    fillHex:item.2,
                    to:base
                )

            adjusted.dpi = 72

            let output =
                try CoverArtwork.export(
                    adjusted,
                    format:"png"
                )

            XCTAssertNotEqual(
                output,
                baseline,
                "\(item.0) should affect production export"
            )
        }
    }
}
