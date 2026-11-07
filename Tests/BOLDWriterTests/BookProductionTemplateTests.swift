import AppKit
import XCTest
@testable import BOLDWriter

final class BookProductionTemplateTests:
    XCTestCase
{
    private func assertSize(
        _ actual: CGSize,
        width: CGFloat,
        height: CGFloat,
        accuracy: CGFloat = 0.0001,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            actual.width,
            width,
            accuracy:
                accuracy,
            file:
                file,
            line:
                line
        )

        XCTAssertEqual(
            actual.height,
            height,
            accuracy:
                accuracy,
            file:
                file,
            line:
                line
        )
    }

    private func assertRect(
        _ actual: CoverRect,
        equals expected: CoverRect,
        accuracy: Double = 0.000000000001,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            actual.x,
            expected.x,
            accuracy:
                accuracy,
            file:
                file,
            line:
                line
        )

        XCTAssertEqual(
            actual.y,
            expected.y,
            accuracy:
                accuracy,
            file:
                file,
            line:
                line
        )

        XCTAssertEqual(
            actual.width,
            expected.width,
            accuracy:
                accuracy,
            file:
                file,
            line:
                line
        )

        XCTAssertEqual(
            actual.height,
            expected.height,
            accuracy:
                accuracy,
            file:
                file,
            line:
                line
        )
    }

    func testSixByNineUsesExactCustomPageSize() {
        var settings =
            PageSettings()

        settings.topMargin =
            54

        settings.bottomMargin =
            60

        BookProductionTemplate
            .sixByNineWhite
            .apply(
                to:
                    &settings
            )

        XCTAssertEqual(
            settings.paper,
            .custom
        )

        XCTAssertFalse(
            settings.landscape
        )

        assertSize(
            settings.pageSize,
            width:
                432,
            height:
                648
        )

        XCTAssertEqual(
            settings.topMargin,
            54
        )

        XCTAssertEqual(
            settings.bottomMargin,
            60
        )
    }

    func testLetterAndA4ReuseExistingPageSettings() {
        var letter =
            PageSettings()

        letter.paper =
            .a4

        letter.landscape =
            true

        BookProductionTemplate
            .usLetterWhite
            .apply(
                to:
                    &letter
            )

        XCTAssertEqual(
            letter.paper,
            .letter
        )

        XCTAssertNil(
            letter.customPaperSize
        )

        XCTAssertFalse(
            letter.landscape
        )

        assertSize(
            letter.pageSize,
            width:
                612,
            height:
                792
        )

        var a4 =
            PageSettings()

        a4.paper =
            .letter

        a4.landscape =
            true

        BookProductionTemplate
            .a4White
            .apply(
                to:
                    &a4
            )

        XCTAssertEqual(
            a4.paper,
            .a4
        )

        XCTAssertFalse(
            a4.landscape
        )

        assertSize(
            a4.pageSize,
            width:
                595.28,
            height:
                841.89
        )
    }

    func testCustomLeavesPageSettingsUntouched() {
        var settings =
            PageSettings()

        settings.paper =
            .a4

        settings.landscape =
            true

        settings.topMargin =
            31

        settings.bottomMargin =
            42

        settings.leftMargin =
            53

        settings.rightMargin =
            64

        let before =
            settings

        BookProductionTemplate
            .custom
            .apply(
                to:
                    &settings
            )

        XCTAssertEqual(
            settings,
            before
        )
    }

    func testNavigationUpdatesGlobalPageAndEverySection() {
        let document =
            BOLDWriterDocument()

        document.replaceText(
            with:
                NSAttributedString(
                    string:
                        "Chapter One"
                )
        )

        var global =
            PageSettings()

        global.leftMargin =
            48

        var first =
            PageSettings()

        first.paper =
            .letter

        first.landscape =
            true

        first.leftMargin =
            40

        var second =
            PageSettings()

        second.paper =
            .a4

        second.leftMargin =
            44

        document.metadata.page =
            global

        document.metadata.sections = [
            DocumentSection(
                location:
                    0,
                page:
                    first
            ),
            DocumentSection(
                location:
                    5,
                page:
                    second
            )
        ]

        let navigation =
            BookWorkspaceNavigation(
                document:
                    document
            )

        navigation
            .applyProductionTemplateToManuscript(
                .sixByNineCream
            )

        assertSize(
            document
                .metadata
                .page
                .pageSize,
            width:
                432,
            height:
                648
        )

        let sections =
            document.metadata.sections
            ?? []

        XCTAssertEqual(
            sections.count,
            2
        )

        for section in sections {
            assertSize(
                section.page.pageSize,
                width:
                    432,
                height:
                    648
            )

            XCTAssertFalse(
                section.page.landscape
            )
        }

        XCTAssertEqual(
            sections.first?
                .page
                .leftMargin,
            40
        )

        XCTAssertEqual(
            sections.last?
                .page
                .leftMargin,
            44
        )
    }

    func testSixByNineSynchronizesCoverAndAnchoredArtwork() throws {
        var project =
            CoverProject(
                type:
                    .printFullWrap,
                width:
                    17.55,
                height:
                    11.25
            )

        project.trimWidth =
            8.5

        project.backWidth =
            8.5

        project.trimHeight =
            11

        project.bleed =
            0.125

        project.spineWidth =
            0.3

        project.spinePageCount =
            120

        project.spineCaliperInches =
            PrintCoverSpecification
                .kdpBlackAndWhiteWhitePaperCaliper

        project.canvasWidth =
            17.55

        project.canvasHeight =
            11.25

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
                    "Front title",
                frame:
                    oldGeometry.frontSafeArea
            )

        front.panelAnchor =
            .front

        project.layers =
            [front]

        let updated =
            try XCTUnwrap(
                PhysicalBookGeometry
                    .applyingProductionTemplate(
                        .sixByNineCream,
                        to:
                            project,
                        pageCount:
                            320
                    )
            )

        XCTAssertEqual(
            updated.productionTemplate,
            .sixByNineCream
        )

        XCTAssertEqual(
            updated.paperStockPreset,
            .kdpCream
        )

        XCTAssertEqual(
            updated.productionBinding,
            .softcover
        )

        XCTAssertEqual(
            updated.trimWidth,
            6,
            accuracy:
                0.0000001
        )

        XCTAssertEqual(
            updated.backWidth,
            6,
            accuracy:
                0.0000001
        )

        XCTAssertEqual(
            updated.trimHeight,
            9,
            accuracy:
                0.0000001
        )

        XCTAssertEqual(
            updated.bleed,
            0.125,
            accuracy:
                0.0000001
        )

        XCTAssertEqual(
            updated.spinePageCount,
            320
        )

        XCTAssertEqual(
            updated.spineCaliperInches,
            PrintCoverSpecification
                .kdpBlackAndWhiteCreamPaperCaliper
        )

        XCTAssertEqual(
            updated.spineWidth,
            0.8,
            accuracy:
                0.0000001
        )

        XCTAssertEqual(
            updated.canvasWidth,
            13.05,
            accuracy:
                0.0000001
        )

        XCTAssertEqual(
            updated.canvasHeight,
            9.25,
            accuracy:
                0.0000001
        )

        let newGeometry =
            CoverWrapGeometry(
                project:
                    updated
            )

        let expectedFrontFrame =
            try XCTUnwrap(
                CoverCalculator
                    .remap(
                        oldGeometry
                            .frontSafeArea,
                        from:
                            oldGeometry
                                .front,
                        to:
                            newGeometry
                                .front
                    )
            )

        assertRect(
            updated.layers[0].frame,
            equals:
                expectedFrontFrame
        )
    }

    func testA4CoverMatchesExistingA4PageModel() throws {
        var page =
            PageSettings()

        BookProductionTemplate
            .a4White
            .apply(
                to:
                    &page
            )

        var project =
            CoverProject(
                type:
                    .printFullWrap
            )

        project.trimWidth =
            6

        project.backWidth =
            6

        project.trimHeight =
            9

        project.bleed =
            0.125

        project.spineWidth =
            0.54

        let updated =
            try XCTUnwrap(
                PhysicalBookGeometry
                    .applyingProductionTemplate(
                        .a4White,
                        to:
                            project,
                        pageCount:
                            240
                    )
            )

        XCTAssertEqual(
            updated.trimWidth * 72,
            Double(
                page.pageSize.width
            ),
            accuracy:
                0.0001
        )

        XCTAssertEqual(
            updated.trimHeight * 72,
            Double(
                page.pageSize.height
            ),
            accuracy:
                0.0001
        )
    }

    func testManualEditMakesStoredProfileDisplayAsCustom() throws {
        let project =
            CoverProject(
                type:
                    .printFullWrap
            )

        let profiled =
            try XCTUnwrap(
                PhysicalBookGeometry
                    .applyingProductionTemplate(
                        .sixByNineWhite,
                        to:
                            project,
                        pageCount:
                            240
                    )
            )

        XCTAssertEqual(
            BookProductionTemplate
                .inferred(
                    from:
                        profiled
                ),
            .sixByNineWhite
        )

        var edited =
            profiled

        edited.trimWidth =
            6.125

        XCTAssertEqual(
            BookProductionTemplate
                .inferred(
                    from:
                        edited
                ),
            .custom
        )
    }

    func testLegacyCoverWithoutProductionTemplateStillDecodes() throws {
        var project =
            CoverProject(
                type:
                    .printFullWrap
            )

        project.productionTemplate =
            .sixByNineWhite

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
                "productionTemplate"
        )

        let legacy =
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
                        legacy
                )

        XCTAssertNil(
            decoded.productionTemplate
        )
    }
}
