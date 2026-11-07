import AppKit
import XCTest
@testable import BOLDWriter

final class PrintProductionPresetTests:
    XCTestCase
{
    private func assertRect(
        _ actual: CoverRect?,
        equals expected: CoverRect,
        accuracy: Double = 0.000000000001,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let actual else {
            XCTFail(
                "Expected a cover rectangle.",
                file: file,
                line: line
            )
            return
        }

        XCTAssertEqual(
            actual.x,
            expected.x,
            accuracy: accuracy,
            file: file,
            line: line
        )

        XCTAssertEqual(
            actual.y,
            expected.y,
            accuracy: accuracy,
            file: file,
            line: line
        )

        XCTAssertEqual(
            actual.width,
            expected.width,
            accuracy: accuracy,
            file: file,
            line: line
        )

        XCTAssertEqual(
            actual.height,
            expected.height,
            accuracy: accuracy,
            file: file,
            line: line
        )
    }

    private func project(
        pages: Int = 240,
        caliper: Double = 0.0025
    ) throws -> CoverProject {
        let spine =
            try CoverCalculator.spineWidth(
                pageCount:
                    pages,
                caliperInches:
                    caliper
            )

        let dimensions =
            try CoverCalculator.fullWrap(
                backWidth:
                    6,
                frontWidth:
                    6,
                trimHeight:
                    9,
                spineWidth:
                    spine,
                bleed:
                    0.125
            )

        var project =
            CoverProject(
                type:
                    .printFullWrap,
                width:
                    dimensions
                        .totalWidthInches,
                height:
                    dimensions
                        .totalHeightInches
            )

        project.trimWidth =
            6

        project.trimHeight =
            9

        project.backWidth =
            6

        project.bleed =
            0.125

        project.spineWidth =
            spine

        project.spinePageCount =
            pages

        project.spineCaliperInches =
            caliper

        project.canvasWidth =
            dimensions
                .totalWidthInches

        project.canvasHeight =
            dimensions
                .totalHeightInches

        return project
    }

    func testProductionPaperPresetsUseVerifiedCalipers() {
        XCTAssertEqual(
            PrintPaperStockPreset
                .kdpWhite
                .caliperInches,
            PrintCoverSpecification
                .kdpBlackAndWhiteWhitePaperCaliper
        )

        XCTAssertEqual(
            PrintPaperStockPreset
                .kdpCream
                .caliperInches,
            PrintCoverSpecification
                .kdpBlackAndWhiteCreamPaperCaliper
        )

        XCTAssertNil(
            PrintPaperStockPreset
                .custom
                .caliperInches
        )

        XCTAssertEqual(
            PrintPaperStockPreset
                .inferred(
                    caliper:
                        PrintCoverSpecification
                            .kdpBlackAndWhiteWhitePaperCaliper
                ),
            .kdpWhite
        )

        XCTAssertEqual(
            PrintPaperStockPreset
                .inferred(
                    caliper:
                        PrintCoverSpecification
                            .kdpBlackAndWhiteCreamPaperCaliper
                ),
            .kdpCream
        )

        XCTAssertEqual(
            PrintPaperStockPreset
                .inferred(
                    caliper:
                        0.0031
                ),
            .custom
        )
    }

    func testProductionBindingAndPaperPresetPersist() throws {
        var project =
            try project()

        project.paperStockPreset =
            .kdpCream

        project.productionBinding =
            .hardcover

        let data =
            try JSONEncoder()
                .encode(
                    project
                )

        let decoded =
            try JSONDecoder()
                .decode(
                    CoverProject.self,
                    from:
                        data
                )

        XCTAssertEqual(
            decoded.paperStockPreset,
            .kdpCream
        )

        XCTAssertEqual(
            decoded.productionBinding,
            .hardcover
        )
    }

    func testLegacyPayloadWithoutProductionFieldsStillDecodes() throws {
        var project =
            try project()

        var layer =
            CoverLayer(
                kind:
                    .text,
                name:
                    "Front Title",
                frame:
                    CoverWrapGeometry(
                        project:
                            project
                    )
                    .frontTrim
            )

        layer.panelAnchor =
            .front

        project.layers =
            [
                layer
            ]

        project.paperStockPreset =
            .kdpCream

        project.productionBinding =
            .hardcover

        let encoded =
            try JSONEncoder()
                .encode(
                    project
                )

        var object =
            try XCTUnwrap(
                JSONSerialization
                    .jsonObject(
                        with:
                            encoded
                    )
                    as? [String: Any]
            )

        object.removeValue(
            forKey:
                "paperStockPreset"
        )

        object.removeValue(
            forKey:
                "productionBinding"
        )

        if var layers =
            object["layers"]
                as? [[String: Any]]
        {
            for index in
                layers.indices
            {
                layers[index]
                    .removeValue(
                        forKey:
                            "panelAnchor"
                    )
            }

            object["layers"] =
                layers
        }

        let legacyData =
            try JSONSerialization
                .data(
                    withJSONObject:
                        object
                )

        let decoded =
            try JSONDecoder()
                .decode(
                    CoverProject.self,
                    from:
                        legacyData
                )

        XCTAssertNil(
            decoded.paperStockPreset
        )

        XCTAssertNil(
            decoded.productionBinding
        )

        XCTAssertNil(
            decoded.layers
                .first?
                .panelAnchor
        )
    }

    func testPlacementAutomaticallyTagsPhysicalPanel() throws {
        var project =
            try project()

        let geometry =
            CoverWrapGeometry(
                project:
                    project
            )

        let data =
            try CoverEditorEngine
                .filledImage(
                    width:
                        24,
                    height:
                        24,
                    color:
                        .red
                )

        let source =
            try CoverArtwork
                .imageLayer(
                    data:
                        data,
                    filename:
                        "front.png",
                    frame:
                        CoverRect()
                )

        let front =
            CoverCalculator
                .placement(
                    source,
                    in:
                        project,
                    region:
                        geometry.frontTrim,
                    fill:
                        true
                )

        XCTAssertEqual(
            front.panelAnchor,
            .front
        )

        project.layers =
            [
                front
            ]
    }

    func testSpineGrowthKeepsArtworkOnPhysicalPanels() throws {
        var project =
            try project(
                pages:
                    240,
                caliper:
                    0.0025
            )

        let originalGeometry =
            CoverWrapGeometry(
                project:
                    project
            )

        var back =
            CoverLayer(
                kind:
                    .text,
                name:
                    "Back",
                frame:
                    originalGeometry
                        .backTrim
            )

        back.panelAnchor =
            .back

        var spine =
            CoverLayer(
                kind:
                    .text,
                name:
                    "Spine",
                frame:
                    originalGeometry
                        .spineTrim
            )

        spine.panelAnchor =
            .spine

        var front =
            CoverLayer(
                kind:
                    .text,
                name:
                    "Front",
                frame:
                    originalGeometry
                        .frontTrim
            )

        front.panelAnchor =
            .front

        let legacyFront =
            CoverLayer(
                kind:
                    .shape,
                name:
                    "Legacy front",
                frame:
                    originalGeometry
                        .frontSafeArea
            )

        let fullWrap =
            CoverLayer(
                kind:
                    .shape,
                name:
                    "Full wrap background",
                frame:
                    CoverRect(
                        x:
                            0,
                        y:
                            0,
                        width:
                            1,
                        height:
                            1
                    )
            )

        project.layers =
            [
                back,
                spine,
                front,
                legacyFront,
                fullWrap
            ]

        let synchronized =
            try XCTUnwrap(
                PhysicalBookGeometry
                    .synchronizedPrintCover(
                        project,
                        manuscriptPageCount:
                            320
                    )
            )

        let geometry =
            CoverWrapGeometry(
                project:
                    synchronized
            )

        let byName =
            Dictionary(
                uniqueKeysWithValues:
                    synchronized
                        .layers
                        .map {
                            (
                                $0.name,
                                $0
                            )
                        }
            )

        assertRect(
            byName["Back"]?.frame,
            equals:
                geometry.backTrim
        )

        assertRect(
            byName["Spine"]?.frame,
            equals:
                geometry.spineTrim
        )

        assertRect(
            byName["Front"]?.frame,
            equals:
                geometry.frontTrim
        )

        XCTAssertEqual(
            byName["Back"]?.panelAnchor,
            .back
        )

        XCTAssertEqual(
            byName["Spine"]?.panelAnchor,
            .spine
        )

        XCTAssertEqual(
            byName["Front"]?.panelAnchor,
            .front
        )

        XCTAssertEqual(
            byName["Legacy front"]?
                .panelAnchor,
            .front
        )

        assertRect(
            byName["Legacy front"]?
                .frame,
            equals:
                geometry.frontSafeArea
        )

        XCTAssertEqual(
            byName["Full wrap background"]?
                .frame,
            CoverRect(
                x:
                    0,
                y:
                    0,
                width:
                    1,
                height:
                    1
            )
        )

        XCTAssertNil(
            byName["Full wrap background"]?
                .panelAnchor
        )

        XCTAssertEqual(
            synchronized.spineWidth,
            0.8,
            accuracy:
                0.0000001
        )
    }

    func testManualResizeUsesSamePhysicalAnchoringEngine() throws {
        var project =
            try project()

        let oldGeometry =
            CoverWrapGeometry(
                project:
                    project
            )

        var front =
            CoverLayer(
                kind:
                    .text,
                name:
                    "Title",
                frame:
                    oldGeometry
                        .frontSafeArea
            )

        front.panelAnchor =
            .front

        project.layers =
            [
                front
            ]

        let resized =
            try XCTUnwrap(
                PhysicalBookGeometry
                    .resizedPrintCover(
                        project,
                        spineWidth:
                            1.1,
                        pageCount:
                            nil,
                        caliper:
                            nil
                    )
            )

        let newGeometry =
            CoverWrapGeometry(
                project:
                    resized
            )

        assertRect(
            resized.layers[0].frame,
            equals:
                newGeometry.frontSafeArea
        )

        XCTAssertEqual(
            resized.layers[0].panelAnchor,
            .front
        )

        XCTAssertNil(
            resized.spinePageCount
        )

        XCTAssertNil(
            resized.spineCaliperInches
        )
    }
}
