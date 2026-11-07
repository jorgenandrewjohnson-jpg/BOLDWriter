import AppKit
import XCTest
@testable import BOLDWriter

final class CoverChannelSelectiveTests: XCTestCase {
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
                scale:96
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

    func testChannelMixerControlsUseIdentityDefaults() {
        let controls =
            CoverAdjustmentControl.controls(
                for:.channelMixer
            )

        XCTAssertEqual(
            controls.map(\.key),
            [
                "redRed",
                "redGreen",
                "redBlue",
                "redConstant",
                "greenRed",
                "greenGreen",
                "greenBlue",
                "greenConstant",
                "blueRed",
                "blueGreen",
                "blueBlue",
                "blueConstant"
            ]
        )

        let defaults =
            Dictionary(
                uniqueKeysWithValues:
                    controls.map {
                        (
                            $0.key,
                            $0.initial
                        )
                    }
            )

        XCTAssertEqual(defaults["redRed"],1)
        XCTAssertEqual(defaults["greenGreen"],1)
        XCTAssertEqual(defaults["blueBlue"],1)
        XCTAssertEqual(defaults["redGreen"],0)
        XCTAssertEqual(defaults["blueConstant"],0)

        XCTAssertEqual(
            CoverAdjustmentKind.channelMixer.workspaceTitle,
            "Channel Mixer"
        )
    }

    func testChannelMixerCanSwapRedIntoBlueOutput() throws {
        let project =
            adding(
                .channelMixer,
                values:[
                    "redRed":0,
                    "redGreen":0,
                    "redBlue":1,
                    "greenRed":0,
                    "greenGreen":1,
                    "greenBlue":0,
                    "blueRed":1,
                    "blueGreen":0,
                    "blueBlue":0,
                    "preserveLuminosity":0
                ],
                to:
                    solidProject(
                        hex:"#FF0000"
                    )
            )

        let color =
            try centerColor(
                project
            )

        XCTAssertGreaterThan(
            color.blueComponent,
            0.85
        )

        XCTAssertLessThan(
            color.redComponent,
            0.15
        )
    }

    func testChannelMixerRowsDriveTheirOwnOutputChannels() throws {
        let redFromBlue =
            try centerColor(
                adding(
                    .channelMixer,
                    values:[
                        "redRed":0,
                        "redGreen":0,
                        "redBlue":1,
                        "greenRed":0,
                        "greenGreen":0,
                        "greenBlue":0,
                        "blueRed":0,
                        "blueGreen":0,
                        "blueBlue":0,
                        "preserveLuminosity":0
                    ],
                    to:
                        solidProject(
                            hex:"#0000FF"
                        )
                )
            )

        XCTAssertGreaterThan(
            redFromBlue.redComponent,
            0.85
        )

        XCTAssertLessThan(
            redFromBlue.blueComponent,
            0.15
        )
    }

    func testChannelMixerIdentityPreservesColor() throws {
        let plain =
            try centerColor(
                solidProject(
                    hex:"#336699"
                )
            )

        let mixed =
            try centerColor(
                adding(
                    .channelMixer,
                    values:[
                        "preserveLuminosity":1
                    ],
                    to:
                        solidProject(
                            hex:"#336699"
                        )
                )
            )

        XCTAssertEqual(
            plain.redComponent,
            mixed.redComponent,
            accuracy:0.02
        )

        XCTAssertEqual(
            plain.greenComponent,
            mixed.greenComponent,
            accuracy:0.02
        )

        XCTAssertEqual(
            plain.blueComponent,
            mixed.blueComponent,
            accuracy:0.02
        )
    }

    func testSelectiveColorExposesNineTargetRangesWithCMYKControls() {
        XCTAssertEqual(
            CoverSelectiveColor.targets,
            [
                "reds",
                "yellows",
                "greens",
                "cyans",
                "blues",
                "magentas",
                "whites",
                "neutrals",
                "blacks"
            ]
        )

        for target in
            CoverSelectiveColor.targets
        {
            let controls =
                CoverSelectiveColor.controls(
                    for:target
                )

            XCTAssertEqual(
                controls.map(\.key),
                [
                    "\(target)Cyan",
                    "\(target)Magenta",
                    "\(target)Yellow",
                    "\(target)Black"
                ]
            )

            XCTAssertTrue(
                controls.allSatisfy {
                    $0.initial == 0
                    && $0.range == -1...1
                }
            )
        }

        XCTAssertTrue(
            CoverAdjustmentControl.controls(
                for:.selectiveColor
            ).isEmpty
        )

        XCTAssertEqual(
            CoverAdjustmentKind.selectiveColor.workspaceTitle,
            "Selective Color"
        )
    }

    func testSelectiveColorRedCyanTargetsRedPixels() throws {
        let plain =
            try centerColor(
                solidProject(
                    hex:"#FF0000"
                )
            )

        let adjusted =
            try centerColor(
                adding(
                    .selectiveColor,
                    values:[
                        "redsCyan":1,
                        "selectiveRelative":0
                    ],
                    to:
                        solidProject(
                            hex:"#FF0000"
                        )
                )
            )

        // The canvas now has an explicit sRGB profile. Device-RGB gamma
        // conversion is display-dependent; assert a substantial reduction,
        // alongside the unchanged non-target channels below.
        XCTAssertLessThan(
            adjusted.redComponent,
            plain.redComponent - 0.35
        )

        XCTAssertLessThan(
            adjusted.greenComponent,
            0.08
        )

        XCTAssertLessThan(
            adjusted.blueComponent,
            0.08
        )
    }

    func testSelectiveColorBlueRangeDoesNotMeaningfullyAlterPureRed() throws {
        let plain =
            try centerColor(
                solidProject(
                    hex:"#FF0000"
                )
            )

        let adjusted =
            try centerColor(
                adding(
                    .selectiveColor,
                    values:[
                        "bluesCyan":1,
                        "bluesMagenta":1,
                        "bluesYellow":1,
                        "bluesBlack":1,
                        "selectiveRelative":0
                    ],
                    to:
                        solidProject(
                            hex:"#FF0000"
                        )
                )
            )

        XCTAssertEqual(
            adjusted.redComponent,
            plain.redComponent,
            accuracy:0.04
        )

        XCTAssertEqual(
            adjusted.greenComponent,
            plain.greenComponent,
            accuracy:0.04
        )

        XCTAssertEqual(
            adjusted.blueComponent,
            plain.blueComponent,
            accuracy:0.04
        )
    }

    func testSelectiveColorBlackControlStronglyDarkensTargetRange() throws {
        let plain =
            try centerColor(
                solidProject(
                    hex:"#00FF00"
                )
            )

        let adjusted =
            try centerColor(
                adding(
                    .selectiveColor,
                    values:[
                        "greensBlack":0.8,
                        "selectiveRelative":1
                    ],
                    to:
                        solidProject(
                            hex:"#00FF00"
                        )
                )
            )

        XCTAssertLessThan(
            adjusted.greenComponent,
            plain.greenComponent - 0.35
        )

        XCTAssertLessThan(
            adjusted.greenComponent,
            0.62
        )
    }

    func testSelectiveColorNegativeBlackLightensTargetRange() throws {
        let plain =
            try centerColor(
                solidProject(
                    hex:"#008000"
                )
            )

        let adjusted =
            try centerColor(
                adding(
                    .selectiveColor,
                    values:[
                        "greensBlack":-0.7,
                        "selectiveRelative":1
                    ],
                    to:
                        solidProject(
                            hex:"#008000"
                        )
                )
            )

        XCTAssertGreaterThan(
            adjusted.greenComponent,
            plain.greenComponent + 0.15
        )
    }

    func testChannelMixerAndSelectiveColorPersistThroughRoundTrip() throws {
        var project =
            solidProject(
                hex:"#808080"
            )

        var channel =
            CoverLayer(
                kind:.adjustment,
                name:"Channel Mixer"
            )

        channel.adjustment =
            .channelMixer

        channel.adjustmentValues = [
            "redRed":0.8,
            "redGreen":0.2,
            "greenGreen":1,
            "blueBlue":1,
            "preserveLuminosity":1
        ]

        var selective =
            CoverLayer(
                kind:.adjustment,
                name:"Selective Color"
            )

        selective.adjustment =
            .selectiveColor

        selective.adjustmentValues = [
            "redsCyan":0.25,
            "redsBlack":-0.10,
            "neutralsYellow":0.15,
            "selectiveRelative":1
        ]

        project.layers += [
            channel,
            selective
        ]

        let reopened =
            try JSONDecoder().decode(
                CoverProject.self,
                from:
                    JSONEncoder().encode(
                        project
                    )
            )

        let channelResult =
            reopened.layers[
                reopened.layers.count - 2
            ]

        let selectiveResult =
            try XCTUnwrap(
                reopened.layers.last
            )

        XCTAssertEqual(
            channelResult.adjustment,
            .channelMixer
        )

        XCTAssertEqual(
            channelResult.adjustmentValues?[
                "redGreen"
            ],
            0.2
        )

        XCTAssertEqual(
            selectiveResult.adjustment,
            .selectiveColor
        )

        XCTAssertEqual(
            selectiveResult.adjustmentValues?[
                "redsCyan"
            ],
            0.25
        )

        XCTAssertEqual(
            selectiveResult.adjustmentValues?[
                "neutralsYellow"
            ],
            0.15
        )
    }

    func testChannelMixerAndSelectiveColorAffectProductionPNGExport() throws {
        var base =
            solidProject(
                hex:"#CC3366"
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
                    [String:Double]
                )
            ] = [
                (
                    .channelMixer,
                    [
                        "redRed":0,
                        "redGreen":0,
                        "redBlue":1,
                        "greenGreen":1,
                        "blueRed":1,
                        "blueBlue":0,
                        "preserveLuminosity":0
                    ]
                ),
                (
                    .selectiveColor,
                    [
                        "redsCyan":0.8,
                        "redsBlack":0.3,
                        "selectiveRelative":0
                    ]
                )
            ]

        for item in cases {
            var adjusted =
                adding(
                    item.0,
                    values:item.1,
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

    func testAllAdjustmentControlsRemainUniqueAndValid() {
        for kind in
            CoverAdjustmentKind.allCases
        {
            let controls =
                CoverAdjustmentControl.controls(
                    for:kind
                )

            XCTAssertEqual(
                controls.count,
                Set(
                    controls.map(\.key)
                ).count
            )

            for control in controls {
                XCTAssertTrue(
                    control.range.contains(
                        control.initial
                    )
                )
            }
        }
    }
}
