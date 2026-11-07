import AppKit
import PDFKit
import XCTest
@testable import BOLDWriter

final class WordImageCropRenderingTests:
    XCTestCase
{
    private struct ColorCounts {
        var red:
            Int = 0

        var blue:
            Int = 0
    }

    private struct CropCase {
        let name:
            String

        let crop:
            WordPictureCrop
    }

    private func cases()
        -> [CropCase]
    {
        [
            CropCase(
                name:
                    "left",
                crop:
                    WordPictureCrop(
                        left:
                            25_000
                    )
            ),
            CropCase(
                name:
                    "right",
                crop:
                    WordPictureCrop(
                        right:
                            25_000
                    )
            ),
            CropCase(
                name:
                    "top",
                crop:
                    WordPictureCrop(
                        top:
                            25_000
                    )
            ),
            CropCase(
                name:
                    "bottom",
                crop:
                    WordPictureCrop(
                        bottom:
                            25_000
                    )
            ),
            CropCase(
                name:
                    "four",
                crop:
                    WordPictureCrop(
                        left:
                            25_000,
                        top:
                            25_000,
                        right:
                            25_000,
                        bottom:
                            25_000
                    )
            )
        ]
    }

    private func sourceData(
        for name:
            String
    ) throws -> Data
    {
        let size =
            NSSize(
                width:
                    100,
                height:
                    100
            )

        let image =
            NSImage(
                size:
                    size
            )

        image.lockFocus()

        NSColor.blue.setFill()

        NSBezierPath(
            rect:
                NSRect(
                    origin:
                        .zero,
                    size:
                        size
                )
        )
        .fill()

        NSColor.red.setFill()

        switch name {
        case "left":
            NSBezierPath(
                rect:
                    NSRect(
                        x:
                            0,
                        y:
                            0,
                        width:
                            25,
                        height:
                            100
                    )
            )
            .fill()

        case "right":
            NSBezierPath(
                rect:
                    NSRect(
                        x:
                            75,
                        y:
                            0,
                        width:
                            25,
                        height:
                            100
                    )
            )
            .fill()

        case "top":
            NSBezierPath(
                rect:
                    NSRect(
                        x:
                            0,
                        y:
                            75,
                        width:
                            100,
                        height:
                            25
                    )
            )
            .fill()

        case "bottom":
            NSBezierPath(
                rect:
                    NSRect(
                        x:
                            0,
                        y:
                            0,
                        width:
                            100,
                        height:
                            25
                    )
            )
            .fill()

        case "four":
            [
                NSRect(
                    x:
                        0,
                    y:
                        0,
                    width:
                        25,
                    height:
                        100
                ),
                NSRect(
                    x:
                        75,
                    y:
                        0,
                    width:
                        25,
                    height:
                        100
                ),
                NSRect(
                    x:
                        25,
                    y:
                        0,
                    width:
                        50,
                    height:
                        25
                ),
                NSRect(
                    x:
                        25,
                    y:
                        75,
                    width:
                        50,
                    height:
                        25
                )
            ]
            .forEach {
                NSBezierPath(
                    rect:
                        $0
                )
                .fill()
            }

        default:
            XCTFail(
                "Unknown crop fixture \(name)"
            )
        }

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

        return try XCTUnwrap(
            bitmap.representation(
                using:
                    .png,
                properties:
                    [:]
            )
        )
    }

    private func attachment(
        data:
            Data,
        displaySize:
            NSSize = NSSize(
                width:
                    160,
                height:
                    80
            )
    ) throws -> NSTextAttachment
    {
        let image =
            try XCTUnwrap(
                NSImage(
                    data:
                        data
                )
            )

        image.size =
            displaySize

        let wrapper =
            FileWrapper(
                regularFileWithContents:
                    data
            )

        wrapper.preferredFilename =
            "word-crop.png"

        let result =
            NSTextAttachment(
                fileWrapper:
                    wrapper
            )

        result.attachmentCell =
            NSTextAttachmentCell(
                imageCell:
                    image
            )

        result.bounds =
            NSRect(
                origin:
                    .zero,
                size:
                    displaySize
            )

        return result
    }

    private func displayImage(
        _ attachment:
            NSTextAttachment
    ) throws -> NSImage
    {
        if let image =
            (attachment.attachmentCell
                as? NSCell)?
                .image {
            return image
        }

        return try XCTUnwrap(
            attachment.image
        )
    }

    private func bitmap(
        _ image:
            NSImage
    ) throws -> NSBitmapImageRep
    {
        try XCTUnwrap(
            image.tiffRepresentation
                .flatMap(
                    NSBitmapImageRep.init(
                        data:
                    )
                )
        )
    }

    private func counts(
        _ bitmap:
            NSBitmapImageRep
    ) -> ColorCounts
    {
        var result =
            ColorCounts()

        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard
                    let color =
                        bitmap.colorAt(
                            x:
                                x,
                            y:
                                y
                        )?
                        .usingColorSpace(
                            .deviceRGB
                        )
                else {
                    continue
                }

                let red =
                    color.redComponent

                let green =
                    color.greenComponent

                let blue =
                    color.blueComponent

                if red > 0.70,
                   red > blue * 1.8,
                   red > green * 1.8 {
                    result.red +=
                        1
                }

                if blue > 0.70,
                   blue > red * 1.8,
                   blue > green * 1.8 {
                    result.blue +=
                        1
                }
            }
        }

        return result
    }

    private func assertBlueCrop(
        _ value:
            ColorCounts,
        minimumBlue:
            Int,
        file:
            StaticString = #filePath,
        line:
            UInt = #line
    ) {
        XCTAssertGreaterThanOrEqual(
            value.blue,
            minimumBlue,
            file:
                file,
            line:
                line
        )

        XCTAssertLessThanOrEqual(
            value.red,
            max(
                30,
                value.blue / 100
            ),
            file:
                file,
            line:
                line
        )
    }

    func testSharedRendererHandlesAllWordCropEdgesNonDestructively()
        throws
    {
        for item in cases() {
            let source =
                try sourceData(
                    for:
                        item.name
                )

            let value =
                try attachment(
                    data:
                        source
                )

            let originalBounds =
                value.bounds

            let originalBytes =
                value.fileWrapper?
                    .regularFileContents

            try DOCXImages.applyWordPictureCrop(
                item.crop,
                to:
                    value
            )

            XCTAssertEqual(
                value.fileWrapper?
                    .regularFileContents,
                originalBytes
            )

            XCTAssertEqual(
                value.bounds,
                originalBounds
            )

            let rendered =
                counts(
                    try bitmap(
                        displayImage(
                            value
                        )
                    )
                )

            assertBlueCrop(
                rendered,
                minimumBlue:
                    10_000
            )

            print(
                "WORD_CROP_RENDERER"
                + "|case=\(item.name)"
                + "|blue=\(rendered.blue)"
                + "|red=\(rendered.red)"
            )
        }
    }

    @MainActor
    func testAllWordCropEdgesRenderOnScreenAndPDF()
        throws
    {
        let settings =
            PageSettings()

        for item in cases() {
            let source =
                try sourceData(
                    for:
                        item.name
                )

            let value =
                try attachment(
                    data:
                        source
                )

            let originalBounds =
                value.bounds

            let originalBytes =
                value.fileWrapper?
                    .regularFileContents

            try DOCXImages.applyWordPictureCrop(
                item.crop,
                to:
                    value
            )

            let text =
                NSMutableAttributedString(
                    string:
                        "\u{fffc}"
                )

            text.addAttributes(
                [
                    .attachment:
                        value,
                    .boldWriterWordPictureCrop:
                        item.crop
                ],
                range:
                    NSRange(
                        location:
                            0,
                        length:
                            1
                    )
            )

            let editor =
                PaginatedEditor(
                    text:
                        text
                )

            editor.configure(
                printLayout:
                    true,
                settings:
                    settings,
                zoom:
                    1,
                viewportWidth:
                    850
            )

            editor.finishPagination()

            let firstPage =
                editor.pages.first

            let page =
                try XCTUnwrap(
                    firstPage
                )

            let screenPageCount =
                editor.pages.count

            page.layoutSubtreeIfNeeded()

            let screenBitmap =
                try XCTUnwrap(
                    page.bitmapImageRepForCachingDisplay(
                        in:
                            page.bounds
                    )
                )

            page.cacheDisplay(
                in:
                    page.bounds,
                to:
                    screenBitmap
            )

            let screen =
                counts(
                    screenBitmap
                )

            let pdfData =
                try PDFExporter.data(
                    from:
                        text,
                    settings:
                        settings
                )

            let pdf =
                try XCTUnwrap(
                    PDFDocument(
                        data:
                            pdfData
                    )
                )

            let firstPDFPage =
                try XCTUnwrap(
                    pdf.page(
                        at:
                            0
                    )
                )

            let thumbnail =
                firstPDFPage.thumbnail(
                    of:
                        settings.pageSize,
                    for:
                        .mediaBox
                )

            let pdfRendered =
                counts(
                    try bitmap(
                        thumbnail
                    )
                )

            assertBlueCrop(
                screen,
                minimumBlue:
                    100
            )

            assertBlueCrop(
                pdfRendered,
                minimumBlue:
                    100
            )

            XCTAssertEqual(
                value.fileWrapper?
                    .regularFileContents,
                originalBytes
            )

            XCTAssertEqual(
                value.bounds,
                originalBounds
            )

            print(
                "WORD_CROP_SCREEN_PDF"
                + "|case=\(item.name)"
                + "|screenBlue=\(screen.blue)"
                + "|screenRed=\(screen.red)"
                + "|pdfBlue=\(pdfRendered.blue)"
                + "|pdfRed=\(pdfRendered.red)"
                + "|screenPages=\(screenPageCount)"
                + "|pdfPages=\(pdf.pageCount)"
            )
        }
    }

    func testIndependentDOCXImportAppliesVisualCrop()
        throws
    {
        let fixture =
            try XCTUnwrap(
                Data(
                    base64Encoded:
                        "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"
                )
            )

        let imported =
            try DOCXImporter
                .importedDocument(
                    from:
                        fixture
                )

        var foundAttachment:
            NSTextAttachment?

        var foundCrop:
            WordPictureCrop?

        imported.text.enumerateAttribute(
            .attachment,
            in:
                NSRange(
                    location:
                        0,
                    length:
                        imported.text.length
                )
        ) {
            value,
            range,
            stop in

            guard
                let attachment =
                    value
                    as? NSTextAttachment
            else {
                return
            }

            foundAttachment =
                attachment

            foundCrop =
                imported.text.attribute(
                    .boldWriterWordPictureCrop,
                    at:
                        range.location,
                    effectiveRange:
                        nil
                )
                as? WordPictureCrop

            stop.pointee =
                true
        }

        let attachment =
            try XCTUnwrap(
                foundAttachment
            )

        let crop =
            try XCTUnwrap(
                foundCrop
            )

        XCTAssertEqual(
            crop.left,
            25_000
        )

        XCTAssertNotNil(
            attachment.fileWrapper?
                .regularFileContents
        )

        let rendered =
            counts(
                try bitmap(
                    displayImage(
                        attachment
                    )
                )
            )

        assertBlueCrop(
            rendered,
            minimumBlue:
                5_000
        )

        print(
            "WORD_CROP_DOCX_VISUAL"
            + "|blue=\(rendered.blue)"
            + "|red=\(rendered.red)"
            + "|storedBytes=\(attachment.fileWrapper?.regularFileContents?.count ?? 0)"
        )
    }

    func testNativeBOLDReopenReappliesVisualCrop()
        throws
    {
        let source =
            try sourceData(
                for:
                    "four"
            )

        let attachment =
            try attachment(
                data:
                    source
            )

        let crop =
            WordPictureCrop(
                left:
                    25_000,
                top:
                    25_000,
                right:
                    25_000,
                bottom:
                    25_000
            )

        try DOCXImages.applyWordPictureCrop(
            crop,
            to:
                attachment
        )

        let text =
            NSMutableAttributedString(
                string:
                    "\u{fffc}"
            )

        text.addAttributes(
            [
                .attachment:
                    attachment,
                .boldWriterWordPictureCrop:
                    crop
            ],
            range:
                NSRange(
                    location:
                        0,
                    length:
                        1
                )
        )

        let package =
            try BOLDWriterDocument
                .packageWrapper(
                    text:
                        text,
                    metadata:
                        DocumentMetadata(
                            title:
                                "Native Visual Crop"
                        )
                )

        let reopened =
            try BOLDWriterDocument(
                fileWrapper:
                    package,
                contentType:
                    .boldWriterDocument
            )

        var restored:
            NSTextAttachment?

        var restoredCrop:
            WordPictureCrop?

        reopened.text.enumerateAttribute(
            .attachment,
            in:
                NSRange(
                    location:
                        0,
                    length:
                        reopened.text.length
                )
        ) {
            value,
            range,
            stop in

            guard
                let attachment =
                    value
                    as? NSTextAttachment
            else {
                return
            }

            restored =
                attachment

            restoredCrop =
                reopened.text.attribute(
                    .boldWriterWordPictureCrop,
                    at:
                        range.location,
                    effectiveRange:
                        nil
                )
                as? WordPictureCrop

            stop.pointee =
                true
        }

        let reopenedAttachment =
            try XCTUnwrap(
                restored
            )

        let reopenedCrop =
            try XCTUnwrap(
                restoredCrop
            )

        XCTAssertEqual(
            reopenedCrop.left,
            25_000
        )

        XCTAssertEqual(
            reopenedCrop.top,
            25_000
        )

        XCTAssertEqual(
            reopenedCrop.right,
            25_000
        )

        XCTAssertEqual(
            reopenedCrop.bottom,
            25_000
        )

        XCTAssertNotNil(
            reopenedAttachment.fileWrapper?
                .regularFileContents
        )

        let rendered =
            counts(
                try bitmap(
                    displayImage(
                        reopenedAttachment
                    )
                )
            )

        assertBlueCrop(
            rendered,
            minimumBlue:
                9_000
        )

        let displaySize =
            try displayImage(
                reopenedAttachment
            )
            .size

        XCTAssertGreaterThan(
            displaySize.width,
            0
        )

        XCTAssertGreaterThan(
            displaySize.height,
            0
        )

        print(
            "WORD_CROP_NATIVE_VISUAL"
            + "|blue=\(rendered.blue)"
            + "|red=\(rendered.red)"
            + "|bounds=\(reopenedAttachment.bounds)"
            + "|display=\(displaySize)"
        )
    }
}
