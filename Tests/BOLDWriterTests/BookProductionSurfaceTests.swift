import AppKit
import XCTest
@testable import BOLDWriter

final class BookProductionSurfaceTests:
    XCTestCase
{
    private func makeDocument(
        pageCount:
            Int = 240
    ) throws -> (
        BOLDWriterDocument,
        CoverProject
    ) {
        let document =
            BOLDWriterDocument()

        document.replaceText(
            with:
                NSAttributedString(
                    string:
                        "A production manuscript."
                )
        )

        var base =
            CoverProject(
                type:
                    .printFullWrap
            )

        base.trimWidth =
            6

        base.backWidth =
            6

        base.trimHeight =
            9

        base.bleed =
            0.125

        let project =
            try XCTUnwrap(
                PhysicalBookGeometry
                    .applyingProductionTemplate(
                        .sixByNineWhite,
                        to:
                            base,
                        pageCount:
                            pageCount
                    )
            )

        document.metadata.coverProjects =
            [
                project
            ]

        document.metadata.activeCoverProjectID =
            project.id

        return (
            document,
            project
        )
    }

    func testNavigationAppliesOneProfileAcrossManuscriptAndCover() throws {
        let (
            document,
            original
        ) =
            try makeDocument()

        var first =
            PageSettings()

        first.leftMargin =
            45

        var second =
            PageSettings()

        second.rightMargin =
            51

        document.metadata.sections =
            [
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

        BookWorkspaceNavigation(
            document:
                document
        )
        .applyProductionTemplate(
            .sixByNineCream,
            pageCount:
                320
        )

        XCTAssertEqual(
            document.metadata
                .page
                .pageSize,
            CGSize(
                width:
                    432,
                height:
                    648
            )
        )

        let sections =
            document.metadata.sections
            ?? []

        XCTAssertEqual(
            sections.count,
            2
        )

        XCTAssertEqual(
            sections[0]
                .page
                .pageSize,
            CGSize(
                width:
                    432,
                height:
                    648
            )
        )

        XCTAssertEqual(
            sections[1]
                .page
                .pageSize,
            CGSize(
                width:
                    432,
                height:
                    648
            )
        )

        XCTAssertEqual(
            sections[0]
                .page
                .leftMargin,
            45
        )

        XCTAssertEqual(
            sections[1]
                .page
                .rightMargin,
            51
        )

        let updated =
            try XCTUnwrap(
                document.metadata
                    .coverProjects?
                    .first
            )

        XCTAssertEqual(
            updated.id,
            original.id
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
            updated.spinePageCount,
            320
        )

        XCTAssertEqual(
            updated.spineWidth,
            0.8,
            accuracy:
                0.0000001
        )

        XCTAssertEqual(
            updated.trimWidth,
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
    }

    func testCustomMarksProfileManualWithoutChangingGeometryOrManuscript() throws {
        let (
            document,
            original
        ) =
            try makeDocument()

        var manuscript =
            PageSettings()

        manuscript.paper =
            .a4

        manuscript.landscape =
            true

        document.metadata.page =
            manuscript

        BookWorkspaceNavigation(
            document:
                document
        )
        .applyProductionTemplate(
            .custom,
            pageCount:
                500
        )

        XCTAssertEqual(
            document.metadata.page,
            manuscript
        )

        let updated =
            try XCTUnwrap(
                document.metadata
                    .coverProjects?
                    .first
            )

        XCTAssertEqual(
            updated.productionTemplate,
            .custom
        )

        XCTAssertEqual(
            updated.trimWidth,
            original.trimWidth
        )

        XCTAssertEqual(
            updated.trimHeight,
            original.trimHeight
        )

        XCTAssertEqual(
            updated.spineWidth,
            original.spineWidth
        )

        XCTAssertEqual(
            updated.spinePageCount,
            original.spinePageCount
        )
    }

    func testRepairCandidateUsesStoredProfileAfterProductionDrift() throws {
        let (
            document,
            _
        ) =
            try makeDocument()

        var project =
            try XCTUnwrap(
                document.metadata
                    .coverProjects?
                    .first
            )

        project.trimWidth =
            6.25

        project.spineWidth =
            0.1

        project.spinePageCount =
            100

        XCTAssertEqual(
            PhysicalBookDiagnostics
                .productionProfileRepairTemplate(
                    project:
                        project
                ),
            .sixByNineWhite
        )

        var wrongPage =
            PageSettings()

        wrongPage.paper =
            .letter

        XCTAssertTrue(
            PhysicalBookDiagnostics
                .productionProfileNeedsRepair(
                    project:
                        project,
                    manuscriptPages:
                        320,
                    pageSettings:
                        [
                            wrongPage
                        ]
                )
        )
    }

    func testRepairPredicateClearsAfterProfileIsReapplied() throws {
        let (
            document,
            _
        ) =
            try makeDocument()

        BookWorkspaceNavigation(
            document:
                document
        )
        .applyProductionTemplate(
            .sixByNineWhite,
            pageCount:
                320
        )

        let project =
            try XCTUnwrap(
                document.metadata
                    .coverProjects?
                    .first
            )

        XCTAssertFalse(
            PhysicalBookDiagnostics
                .productionProfileNeedsRepair(
                    project:
                        project,
                    manuscriptPages:
                        320,
                    pageSettings:
                        [
                            document.metadata.page
                        ]
                )
        )
    }

    func testManualCustomProjectIsNotOfferedAutomaticRepair() throws {
        let (
            document,
            _
        ) =
            try makeDocument()

        var project =
            try XCTUnwrap(
                document.metadata
                    .coverProjects?
                    .first
            )

        project.productionTemplate =
            .custom

        project.trimWidth =
            7

        project.backWidth =
            7

        project.trimHeight =
            10

        XCTAssertNil(
            PhysicalBookDiagnostics
                .productionProfileRepairTemplate(
                    project:
                        project
                )
        )

        XCTAssertFalse(
            PhysicalBookDiagnostics
                .productionProfileNeedsRepair(
                    project:
                        project,
                    manuscriptPages:
                        320,
                    pageSettings:
                        [
                            document.metadata.page
                        ]
                )
        )
    }

    func testRepairKeepsPhysicallyAnchoredFrontArtworkOnFrontPanel() throws {
        let (
            document,
            _
        ) =
            try makeDocument()

        var project =
            try XCTUnwrap(
                document.metadata
                    .coverProjects?
                    .first
            )

        let oldGeometry =
            CoverWrapGeometry(
                project:
                    project
            )

        var title =
            CoverLayer(
                kind:
                    .text,
                name:
                    "Front title",
                frame:
                    oldGeometry
                        .frontSafeArea
            )

        title.panelAnchor =
            .front

        project.layers =
            [
                title
            ]

        project.trimWidth =
            6.25

        project.backWidth =
            6.25

        document.metadata.coverProjects =
            [
                project
            ]

        BookWorkspaceNavigation(
            document:
                document
        )
        .applyProductionTemplate(
            .sixByNineWhite,
            pageCount:
                320
        )

        let repaired =
            try XCTUnwrap(
                document.metadata
                    .coverProjects?
                    .first
            )

        XCTAssertEqual(
            repaired.layers
                .first?
                .panelAnchor,
            .front
        )

        let repairedGeometry =
            CoverWrapGeometry(
                project:
                    repaired
            )

        let frame =
            try XCTUnwrap(
                repaired.layers
                    .first?
                    .frame
            )

        XCTAssertGreaterThanOrEqual(
            frame.x,
            repairedGeometry
                .front
                .x
                - 0.000001
        )

        XCTAssertLessThanOrEqual(
            frame.x
                + frame.width,
            repairedGeometry
                .front
                .x
                + repairedGeometry
                    .front
                    .width
                + 0.000001
        )
    }
}
