import AppKit
import XCTest
@testable import BOLDWriter

final class CoverAdjustmentParityTests: XCTestCase {
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
        values:[String:Double] = [:],
        fillHex:String = "#000000",
        endHex:String = "#FFFFFF",
        to project:CoverProject
    ) -> CoverProject {
        var copy = project

        var layer =
            CoverLayer(
                kind:.adjustment,
                name:kind.rawValue,
                frame:CoverRect()
            )

        layer.adjustment = kind
        layer.adjustmentValues = values
        layer.fillHex = fillHex
        layer.gradientEndHex = endHex

        copy.layers.append(
            layer
        )

        return copy
    }

    private func bitmap(
        _ project:CoverProject,
        scale:Double = 100
    ) throws -> NSBitmapImageRep {
        let image =
            try CoverArtwork.render(
                project,
                scale:scale
            )

        return try XCTUnwrap(
            NSBitmapImageRep(
                data:
                    try XCTUnwrap(
                        image.tiffRepresentation
                    )
            )
        )
    }

    private func centerColor(
        _ project:CoverProject
    ) throws -> NSColor {
        let rep =
            try bitmap(
                project
            )

        return try XCTUnwrap(
            rep.colorAt(
                x:rep.pixelsWide / 2,
                y:rep.pixelsHigh / 2
            )
        )
        .usingColorSpace(
            .deviceRGB
        )
        ?? .black
    }

    func testAdjustmentControlsExposeThresholdPosterizeAndGradientMap() {
        let threshold =
            CoverAdjustmentControl.controls(
                for:.threshold
            )

        XCTAssertEqual(
            threshold.map(\.key),
            ["threshold"]
        )

        XCTAssertEqual(
            threshold.first?.initial,
            0.5
        )

        let posterize =
            CoverAdjustmentControl.controls(
                for:.posterize
            )

        XCTAssertEqual(
            posterize.map(\.key),
            ["levels"]
        )

        XCTAssertEqual(
            posterize.first?.initial,
            6
        )

        XCTAssertTrue(
            CoverAdjustmentControl.controls(
                for:.gradientMap
            ).isEmpty
        )

        XCTAssertEqual(
            CoverAdjustmentKind.threshold.workspaceTitle,
            "Threshold"
        )

        XCTAssertEqual(
            CoverAdjustmentKind.posterize.workspaceTitle,
            "Posterize"
        )

        XCTAssertEqual(
            CoverAdjustmentKind.gradientMap.workspaceTitle,
            "Gradient Map"
        )
    }

    func testThresholdSeparatesDarkAndLightPixels() throws {
        let dark =
            try centerColor(
                adding(
                    .threshold,
                    values:[
                        "threshold":0.5
                    ],
                    to:
                        solidProject(
                            hex:"#404040"
                        )
                )
            )

        let light =
            try centerColor(
                adding(
                    .threshold,
                    values:[
                        "threshold":0.5
                    ],
                    to:
                        solidProject(
                            hex:"#C0C0C0"
                        )
                )
            )

        XCTAssertLessThan(
            dark.redComponent,
            0.08
        )

        XCTAssertGreaterThan(
            light.redComponent,
            0.92
        )
    }

    func testPosterizeReducesGradientToDiscreteLevels() throws {
        var project =
            CoverProject(
                width:1,
                height:1
            )

        var gradient =
            CoverLayer(
                kind:.gradient,
                name:"Gradient",
                frame:
                    CoverRect(
                        x:0,
                        y:0,
                        width:1,
                        height:1
                    )
            )

        gradient.fillHex = "#000000"
        gradient.gradientEndHex = "#FFFFFF"

        project.layers = [
            gradient
        ]

        let adjusted =
            adding(
                .posterize,
                values:[
                    "levels":3
                ],
                to:project
            )

        let rep =
            try bitmap(
                adjusted,
                scale:120
            )

        var values =
            Set<Int>()

        for x in stride(
            from:4,
            to:rep.pixelsWide - 4,
            by:4
        ) {
            if let color =
                rep.colorAt(
                    x:x,
                    y:rep.pixelsHigh / 2
                )?
                .usingColorSpace(
                    .deviceRGB
                )
            {
                values.insert(
                    Int(
                        (
                            color.redComponent
                            * 255
                        ).rounded()
                    )
                )
            }
        }

        XCTAssertLessThanOrEqual(
            values.count,
            5
        )

        XCTAssertGreaterThanOrEqual(
            values.count,
            2
        )
    }

    func testGradientMapMapsBlackAndWhiteToChosenColors() throws {
        let shadows =
            try centerColor(
                adding(
                    .gradientMap,
                    fillHex:"#FF0000",
                    endHex:"#0000FF",
                    to:
                        solidProject(
                            hex:"#000000"
                        )
                )
            )

        let highlights =
            try centerColor(
                adding(
                    .gradientMap,
                    fillHex:"#FF0000",
                    endHex:"#0000FF",
                    to:
                        solidProject(
                            hex:"#FFFFFF"
                        )
                )
            )

        XCTAssertGreaterThan(
            shadows.redComponent,
            0.85
        )

        XCTAssertLessThan(
            shadows.blueComponent,
            0.15
        )

        XCTAssertGreaterThan(
            highlights.blueComponent,
            0.85
        )

        XCTAssertLessThan(
            highlights.redComponent,
            0.15
        )
    }

    func testNewAdjustmentKindsPersistThroughProjectRoundTrip() throws {
        var project =
            solidProject(
                hex:"#808080"
            )

        var threshold =
            CoverLayer(
                kind:.adjustment,
                name:"Threshold"
            )

        threshold.adjustment = .threshold
        threshold.adjustmentValues = [
            "threshold":0.42
        ]

        var posterize =
            CoverLayer(
                kind:.adjustment,
                name:"Posterize"
            )

        posterize.adjustment = .posterize
        posterize.adjustmentValues = [
            "levels":7
        ]

        var gradientMap =
            CoverLayer(
                kind:.adjustment,
                name:"Gradient Map"
            )

        gradientMap.adjustment = .gradientMap
        gradientMap.fillHex = "#112233"
        gradientMap.gradientEndHex = "#DDEEFF"

        project.layers += [
            threshold,
            posterize,
            gradientMap
        ]

        let decoded =
            try JSONDecoder().decode(
                CoverProject.self,
                from:
                    JSONEncoder().encode(
                        project
                    )
            )

        XCTAssertEqual(
            decoded.layers[
                decoded.layers.count - 3
            ].adjustment,
            .threshold
        )

        XCTAssertEqual(
            decoded.layers[
                decoded.layers.count - 2
            ].adjustment,
            .posterize
        )

        let decodedMap =
            decoded.layers.last

        XCTAssertEqual(
            decodedMap?.adjustment,
            .gradientMap
        )

        XCTAssertEqual(
            decodedMap?.fillHex,
            "#112233"
        )

        XCTAssertEqual(
            decodedMap?.gradientEndHex,
            "#DDEEFF"
        )
    }

    func testAdjustmentParityKindsChangeProductionPNGExport() throws {
        var base =
            solidProject(
                hex:"#777777"
            )

        base.dpi = 72

        let cases:
            [(CoverAdjustmentKind,[String:Double],String,String)] = [
                (
                    .threshold,
                    ["threshold":0.3],
                    "#000000",
                    "#FFFFFF"
                ),
                (
                    .posterize,
                    ["levels":2],
                    "#000000",
                    "#FFFFFF"
                ),
                (
                    .gradientMap,
                    [:],
                    "#FF0000",
                    "#0000FF"
                )
            ]

        let baseline =
            try CoverArtwork.export(
                base,
                format:"png"
            )

        for item in cases {
            var adjusted =
                adding(
                    item.0,
                    values:item.1,
                    fillHex:item.2,
                    endHex:item.3,
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

    func testAllAdjustmentControlsHaveUniqueKeysAndValidDefaults() {
        for kind in
            CoverAdjustmentKind.allCases
        {
            let controls =
                CoverAdjustmentControl.controls(
                    for:kind
                )

            XCTAssertEqual(
                controls.map(\.key).count,
                Set(
                    controls.map(\.key)
                ).count
            )

            for control in controls {
                XCTAssertTrue(
                    control.range.contains(
                        control.initial
                    ),
                    "\(kind) \(control.key) default must be inside its range"
                )
            }
        }
    }
}
