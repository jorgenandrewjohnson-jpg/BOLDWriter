import XCTest
@testable import BOLDWriter

final class BookProductionSyncTests: XCTestCase {
    func testCaliperLinkedCoverTracksCurrentManuscriptPagination() throws {
        var project =
            CoverProject(
                type: .printFullWrap,
                width: 12.85,
                height: 9.25
            )

        project.trimWidth = 6
        project.backWidth = 6
        project.trimHeight = 9
        project.bleed = 0.125
        project.spinePageCount = 240
        project.spineCaliperInches = 0.0025
        project.spineWidth = 0.6
        project.canvasWidth = 12.85
        project.canvasHeight = 9.25

        let originalID = project.id

        let synchronized =
            try XCTUnwrap(
                PhysicalBookGeometry
                    .synchronizedPrintCover(
                        project,
                        manuscriptPageCount: 320
                    )
            )

        XCTAssertEqual(
            synchronized.id,
            originalID
        )

        XCTAssertEqual(
            synchronized.spinePageCount,
            320
        )

        XCTAssertEqual(
            synchronized.spineCaliperInches,
            0.0025
        )

        XCTAssertEqual(
            synchronized.spineWidth,
            0.8,
            accuracy: 0.0000001
        )

        XCTAssertEqual(
            synchronized.canvasWidth,
            13.05,
            accuracy: 0.0000001
        )

        XCTAssertEqual(
            synchronized.canvasHeight,
            9.25,
            accuracy: 0.0000001
        )
    }

    func testAlreadySynchronizedCoverDoesNotRewriteMetadata() {
        var project =
            CoverProject(
                type: .printFullWrap,
                width: 13.05,
                height: 9.25
            )

        project.trimWidth = 6
        project.backWidth = 6
        project.trimHeight = 9
        project.bleed = 0.125
        project.spinePageCount = 320
        project.spineCaliperInches = 0.0025
        project.spineWidth = 0.8
        project.canvasWidth = 13.05
        project.canvasHeight = 9.25

        XCTAssertNil(
            PhysicalBookGeometry
                .synchronizedPrintCover(
                    project,
                    manuscriptPageCount: 320
                )
        )
    }

    func testConvertedPaperbackDoesNotReapplyPageCountFromSourceTemplateName() throws {
        var project = CoverProject(
            type: .printFullWrap,
            width: 12.45482,
            height: 8.75
        )
        project.name = "CASE_LAMINATE_8.250x11.000_535_BW_WHITE_en_US — KDP Paperback 356 pages"
        project.trimWidth = 5.5
        project.backWidth = 5.5
        project.trimHeight = 8.5
        project.bleed = 0.125
        project.productionBinding = .softcover
        project.paperStockPreset = .kdpWhite
        project.productionTemplate = .custom
        project.spineCaliperInches = 0.002252
        project.spinePageCount = 356
        project.spineWidth = 1.20482
        project.canvasWidth = 12.45482
        project.canvasHeight = 8.75

        let synchronized = try XCTUnwrap(
            PhysicalBookGeometry.synchronizedPrintCover(
                project,
                manuscriptPageCount: 356
            )
        )

        XCTAssertEqual(synchronized.spinePageCount, 356)
        XCTAssertEqual(synchronized.spineWidth, 0.801712, accuracy: 0.0000001)
        XCTAssertEqual(synchronized.canvasWidth, 12.051712, accuracy: 0.0000001)
        XCTAssertEqual(synchronized.trimWidth, 5.5)
        XCTAssertEqual(synchronized.trimHeight, 8.5)
    }

    func testManualSpineRemainsManual() {
        var project =
            CoverProject(
                type: .printFullWrap,
                width: 12.95,
                height: 9.25
            )

        project.trimWidth = 6
        project.backWidth = 6
        project.trimHeight = 9
        project.bleed = 0.125
        project.spineWidth = 0.7
        project.spinePageCount = nil
        project.spineCaliperInches = nil

        XCTAssertNil(
            PhysicalBookGeometry
                .synchronizedPrintCover(
                    project,
                    manuscriptPageCount: 500
                )
        )
    }

    func testEbookCoverIsNeverChangedByPrintPagination() {
        var project =
            CoverProject(
                type: .ebookFront,
                width: 6,
                height: 9
            )

        project.spinePageCount = 200
        project.spineCaliperInches = 0.0025

        XCTAssertNil(
            PhysicalBookGeometry
                .synchronizedPrintCover(
                    project,
                    manuscriptPageCount: 400
                )
        )
    }

    func testPaperbackConversionCreatesNonDestructiveFinalPaginationWrap() throws {
        var source = CoverProject(type: .printFullWrap, width: 19.469, height: 12.417)
        source.name = "Legacy hardcover reference"
        source.productionBinding = .hardcover
        source.trimWidth = 8.25
        source.backWidth = 8.25
        source.trimHeight = 11
        source.spineWidth = 1.394
        source.spinePageCount = 535
        source.kdpHardcoverLayout = KDPHardcoverLayout(
            canvasWidth: 19.469, canvasHeight: 12.417,
            trimWidth: 8.25, trimHeight: 11,
            spineWidth: 1.394, pageCount: 535
        )
        let image = CoverLayer(kind: .image, name: "Original photo", frame: CoverRect(x: 0.7, y: 0.1, width: 0.25, height: 0.8))
        var photo = image
        photo.imageData = Data([1, 2, 3, 4])
        source.layers = [photo]
        let original = source

        let paperback = try XCTUnwrap(PhysicalBookGeometry.adaptingArtworkToKDPPaperback(
            source,
            pageCount: 356,
            trimWidth: 5.5,
            trimHeight: 8.5,
            paperStock: .kdpWhite
        ))

        XCTAssertEqual(source, original, "Conversion must leave the obsolete source template untouched")
        XCTAssertNotEqual(paperback.id, source.id)
        XCTAssertNil(paperback.activeKDPHardcoverLayout)
        XCTAssertEqual(paperback.productionBinding, .softcover)
        XCTAssertEqual(paperback.spinePageCount, 356)
        XCTAssertEqual(paperback.spineWidth, 0.801712, accuracy: 0.000001)
        XCTAssertEqual(paperback.canvasWidth, 12.051712, accuracy: 0.000001)
        XCTAssertEqual(paperback.canvasHeight, 8.75, accuracy: 0.000001)
        XCTAssertEqual(paperback.layers.first?.imageData, photo.imageData)
    }
}
