import XCTest
@testable import BOLDWriter

final class CoverPrintWrapBridgeTests: XCTestCase {

    func testImportedPaperbackTemplateKeepsAllArtwork() throws {
        var source = CoverProject(
            type: .ebookFront,
            width: 18.458,
            height: 11.25
        )

        source.name = "Family Book"

        let template = CoverLayer(
            kind: .template,
            name: "PAPERBACK_8.500x11.000_535_BW.pdf"
        )

        let first = CoverLayer(
            kind: .image,
            name: "photo-one.jpg",
            frame: CoverRect(
                x: 0.10,
                y: 0.15,
                width: 0.30,
                height: 0.65
            )
        )

        let second = CoverLayer(
            kind: .image,
            name: "photo-two.jpg",
            frame: CoverRect(
                x: 0.50,
                y: 0.15,
                width: 0.30,
                height: 0.65
            )
        )

        let third = CoverLayer(
            kind: .image,
            name: "photo-three.jpg",
            frame: CoverRect(
                x: 0.82,
                y: 0.15,
                width: 0.15,
                height: 0.65
            )
        )

        source.layers = [
            template,
            first,
            second,
            third
        ]

        let recovered = try XCTUnwrap(
            CoverPrintWrapBridge.promote(source)
        )

        XCTAssertEqual(recovered.type, .printFullWrap)
        XCTAssertNotEqual(recovered.id, source.id)

        XCTAssertEqual(
            recovered.canvasWidth,
            source.canvasWidth
        )

        XCTAssertEqual(
            recovered.canvasHeight,
            source.canvasHeight
        )

        XCTAssertEqual(recovered.trimWidth, 8.5)
        XCTAssertEqual(recovered.backWidth, 8.5)
        XCTAssertEqual(recovered.trimHeight, 11)
        XCTAssertEqual(recovered.bleed, 0.125, accuracy: 0.001)
        XCTAssertEqual(recovered.spineWidth, 1.208, accuracy: 0.002)

        XCTAssertEqual(recovered.layers, source.layers)

        XCTAssertEqual(
            source.type,
            .ebookFront
        )

        XCTAssertEqual(
            source.layers.count,
            4
        )

        try CoverProject.validate([source, recovered])
    }

    func testOrdinaryEbookArtworkMovesToFrontPanel() throws {
        var source = CoverProject(
            type: .ebookFront,
            width: 6,
            height: 9
        )

        let image = CoverLayer(
            kind: .image,
            name: "front.png"
        )

        source.layers = [image]

        let recovered = try XCTUnwrap(
            CoverPrintWrapBridge.promote(source)
        )

        let front = CoverWrapGeometry(
            project: recovered
        ).frontTrim

        XCTAssertEqual(recovered.type, .printFullWrap)
        XCTAssertEqual(recovered.layers.count, 1)
        XCTAssertEqual(recovered.layers[0].frame, front)
        XCTAssertEqual(source.layers[0].frame, CoverRect())

        try CoverProject.validate([source, recovered])
    }

    func testOriginalPrintWrapIsNeverReclassified() {
        var source = CoverProject(
            type: .printFullWrap,
            width: 12.79,
            height: 9.25
        )

        source.layers = [
            CoverLayer(
                kind: .image,
                name: "art.jpg"
            )
        ]

        XCTAssertNil(CoverPrintWrapBridge.promote(source))
    }

    func testEmptyCoverDoesNotCreateFakeArtwork() {
        let source = CoverProject(
            type: .ebookFront,
            width: 6,
            height: 9
        )

        XCTAssertNil(CoverPrintWrapBridge.promote(source))
    }
}
