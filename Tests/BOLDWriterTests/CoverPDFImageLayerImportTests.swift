import AppKit
import PDFKit
import XCTest
@testable import BOLDWriter

@MainActor
final class CoverPDFImageLayerImportTests:
    XCTestCase
{
    private func temporaryPDF() throws -> Data {
        let source =
            NSImage(
                size:
                    NSSize(
                        width:
                            1200,
                        height:
                            700
                    )
            )

        source.lockFocus()

        NSColor.white.setFill()

        NSBezierPath(
            rect:
                NSRect(
                    x:
                        0,
                    y:
                        0,
                    width:
                        1200,
                    height:
                        700
                )
        )
        .fill()

        NSColor.black.setStroke()

        let border =
            NSBezierPath(
                rect:
                    NSRect(
                        x:
                            50,
                        y:
                            50,
                        width:
                            1100,
                        height:
                            600
                    )
            )

        border.lineWidth =
            6

        border.stroke()

        NSString(
            string:
                "PDF COVER ARTWORK"
        )
        .draw(
            at:
                NSPoint(
                    x:
                        390,
                    y:
                        330
                ),
            withAttributes:
                [
                    .font:
                        NSFont.boldSystemFont(
                            ofSize:
                                36
                        ),
                    .foregroundColor:
                        NSColor.black
                ]
        )

        source.unlockFocus()

        let document =
            PDFDocument()

        let page =
            try XCTUnwrap(
                PDFPage(
                    image:
                        source
                )
            )

        document.insert(
            page,
            at:
                0
        )

        let temporaryURL =
            FileManager
                .default
                .temporaryDirectory
                .appendingPathComponent(
                    UUID()
                        .uuidString
                )
                .appendingPathExtension(
                    "pdf"
                )

        defer {
            try? FileManager
                .default
                .removeItem(
                    at:
                        temporaryURL
                )
        }

        XCTAssertTrue(
            document.write(
                to:
                    temporaryURL
            )
        )

        return try Data(
            contentsOf:
                temporaryURL
        )
    }

    func testPDFCanBeImportedAsNormalCoverImageLayer()
        throws
    {
        let pdfData =
            try temporaryPDF()

        let layer =
            try CoverArtwork.imageLayer(
                data:
                    pdfData,
                filename:
                    "cover-template.pdf",
                frame:
                    CoverRect(
                        x:
                            0,
                        y:
                            0,
                        width:
                            8.5,
                        height:
                            11
                    )
            )

        XCTAssertEqual(
            layer.kind,
            .image
        )

        XCTAssertEqual(
            layer.name,
            "cover-template.pdf"
        )

        let rasterData =
            try XCTUnwrap(
                layer.imageData
            )

        let image =
            try XCTUnwrap(
                NSImage(
                    data:
                        rasterData
                )
            )

        XCTAssertGreaterThan(
            image.size.width,
            1000
        )

        XCTAssertGreaterThan(
            image.size.height,
            500
        )
    }

    func testPDFMagicBytesWorkEvenWithoutPDFExtension()
        throws
    {
        let pdfData =
            try temporaryPDF()

        XCTAssertTrue(
            pdfData.starts(
                with:
                    Data(
                        "%PDF".utf8
                    )
            )
        )

        let layer =
            try CoverArtwork.imageLayer(
                data:
                    pdfData,
                filename:
                    "cover-artwork.bin"
            )

        XCTAssertEqual(
            layer.kind,
            .image
        )

        XCTAssertNotNil(
            layer.imageData
        )

        XCTAssertNotNil(
            layer.imageData
                .flatMap(
                    NSImage.init(data:)
                )
        )
    }

    func testExistingRasterImageLayerBehaviorRemainsIntact()
        throws
    {
        let image =
            NSImage(
                size:
                    NSSize(
                        width:
                            900,
                        height:
                            600
                    )
            )

        image.lockFocus()

        NSColor.orange.setFill()

        NSBezierPath(
            rect:
                NSRect(
                    x:
                        0,
                    y:
                        0,
                    width:
                        900,
                    height:
                        600
                )
        )
        .fill()

        image.unlockFocus()

        let tiff =
            try XCTUnwrap(
                image.tiffRepresentation
            )

        let bitmap =
            try XCTUnwrap(
                NSBitmapImageRep(
                    data:
                        tiff
                )
            )

        let png =
            try XCTUnwrap(
                bitmap.representation(
                    using:
                        .png,
                    properties:
                        [:]
                )
            )

        let layer =
            try CoverArtwork.imageLayer(
                data:
                    png,
                filename:
                    "ordinary-cover.png"
            )

        XCTAssertEqual(
            layer.kind,
            .image
        )

        XCTAssertNotNil(
            layer.imageData
        )

        XCTAssertNotNil(
            layer.imageData
                .flatMap(
                    NSImage.init(data:)
                )
        )
    }
}
