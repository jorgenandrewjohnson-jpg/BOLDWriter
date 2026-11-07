import AppKit
import PDFKit
import UniformTypeIdentifiers
import XCTest
@testable import BOLDWriter

final class PDFImportTests: XCTestCase {
    func testPDFIsReadableContentType() {
        XCTAssertTrue(
            BOLDWriterDocument
                .readableContentTypes
                .contains(
                    .pdf
                )
        )
    }

    func testSuppliedPDFImportsWhenConfigured() throws {
        guard
            let path =
                ProcessInfo
                    .processInfo
                    .environment[
                        "BOLD_ACCEPTANCE_PDF"
                    ]
        else {
            throw XCTSkip(
                "Set BOLD_ACCEPTANCE_PDF"
            )
        }

        let url =
            URL(
                fileURLWithPath:
                    path
            )

        let data =
            try Data(
                contentsOf:
                    url
            )

        let pdf =
            try XCTUnwrap(
                PDFDocument(
                    data:
                        data
                )
            )

        XCTAssertGreaterThan(
            pdf.pageCount,
            0
        )

        let document =
            try BOLDWriterDocument(
                fileWrapper:
                    FileWrapper(
                        regularFileWithContents:
                            data
                    ),
                contentType:
                    .pdf
            )

        XCTAssertGreaterThan(document.text.length, 0)
    }
}


final class UniversalDocumentOpeningTests:
    XCTestCase
{
    func testReadableTypesAcceptCommonImagesAndMarkdown() {
        XCTAssertTrue(
            BOLDWriterDocument
                .supportsOpening(
                    .png
                )
        )

        XCTAssertTrue(
            BOLDWriterDocument
                .supportsOpening(
                    .jpeg
                )
        )

        XCTAssertTrue(
            BOLDWriterDocument
                .supportsOpening(
                    .gif
                )
        )

        XCTAssertTrue(
            BOLDWriterDocument
                .supportsOpening(
                    .tiff
                )
        )

        XCTAssertTrue(
            BOLDWriterDocument
                .supportsOpening(
                    .boldWriterMarkdown
                )
        )
    }

    func testImageFileOpensAsWriterDocumentAttachment() throws {
        let image =
            NSImage(
                size:
                    NSSize(
                        width:
                            60,
                        height:
                            30
                    )
            )

        image.lockFocus()

        NSColor.systemBlue
            .setFill()

        NSBezierPath(
            rect:
                NSRect(
                    x:
                        0,
                    y:
                        0,
                    width:
                        60,
                    height:
                        30
                )
        )
        .fill()

        image.unlockFocus()

        let data =
            try XCTUnwrap(
                image
                .tiffRepresentation
                .flatMap {
                    NSBitmapImageRep(
                        data:
                            $0
                    )
                }
                .flatMap {
                    $0.representation(
                        using:
                            .png,
                        properties:
                            [:]
                    )
                }
            )

        let wrapper =
            FileWrapper(
                regularFileWithContents:
                    data
            )

        wrapper.preferredFilename =
            "desktop-picture.png"

        let document =
            try BOLDWriterDocument(
                fileWrapper:
                    wrapper,
                contentType:
                    .png
            )

        var attachments =
            0

        document.text
            .enumerateAttribute(
                .attachment,
                in:
                    NSRange(
                        location:
                            0,
                        length:
                            document.text
                            .length
                    )
            ) {
                value,
                _,
                _ in

                if value is NSTextAttachment {
                    attachments +=
                        1
                }
            }

        XCTAssertEqual(
            attachments,
            1
        )
    }

    func testMarkdownExtensionRoutesToMarkdownType() {
        let type =
            BOLDWriterDocument
            .inferredContentType(
                for:
                    URL(
                        fileURLWithPath:
                            "/tmp/example.md"
                    )
            )

        XCTAssertEqual(
            type,
            .boldWriterMarkdown
        )

        XCTAssertTrue(
            BOLDWriterDocument
                .supportsOpening(
                    type
                )
        )
    }

    func testMarkdownDataOpensAsPlainText() throws {
        let source =
            "# BOLD Writer\n\nMarkdown opening works."

        let wrapper =
            FileWrapper(
                regularFileWithContents:
                    Data(
                        source.utf8
                    )
            )

        wrapper.preferredFilename =
            "example.md"

        let document =
            try BOLDWriterDocument(
                fileWrapper:
                    wrapper,
                contentType:
                    .boldWriterMarkdown
            )

        XCTAssertEqual(
            document.text.string,
            source
        )
    }
}
