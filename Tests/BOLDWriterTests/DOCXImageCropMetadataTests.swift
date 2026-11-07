import AppKit
import XCTest
@testable import BOLDWriter

final class DOCXImageCropMetadataTests:
    XCTestCase
{
    private struct Fixture {
        let data: Data
        let left: Int
        let top: Int
        let right: Int
        let bottom: Int
    }

    private func fixtures()
        throws -> [String: Fixture]
    {
        [
        "left": Fixture(
            data:
                try XCTUnwrap(
                    Data(
                        base64Encoded:
                            "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"
                    )
                ),
            left: 12000,
            top: 0,
            right: 0,
            bottom: 0
        ),
        "top": Fixture(
            data:
                try XCTUnwrap(
                    Data(
                        base64Encoded:
                            "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"
                    )
                ),
            left: 0,
            top: 23000,
            right: 0,
            bottom: 0
        ),
        "right": Fixture(
            data:
                try XCTUnwrap(
                    Data(
                        base64Encoded:
                            "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"
                    )
                ),
            left: 0,
            top: 0,
            right: 34000,
            bottom: 0
        ),
        "bottom": Fixture(
            data:
                try XCTUnwrap(
                    Data(
                        base64Encoded:
                            "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"
                    )
                ),
            left: 0,
            top: 0,
            right: 0,
            bottom: 17000
        ),
        "all": Fixture(
            data:
                try XCTUnwrap(
                    Data(
                        base64Encoded:
                            "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"
                    )
                ),
            left: 11000,
            top: 12000,
            right: 13000,
            bottom: 14000
        )
        ]
    }

    private func attachmentRange(
        in text: NSAttributedString
    ) -> NSRange? {
        var found: NSRange?

        text.enumerateAttribute(
            .attachment,
            in:
                NSRange(
                    location: 0,
                    length: text.length
                )
        ) {
            value,
            range,
            stop in

            if value is NSTextAttachment {
                found = range
                stop.pointee = true
            }
        }

        return found
    }

    private func crop(
        in text: NSAttributedString
    ) throws -> WordPictureCrop {
        let range =
            try XCTUnwrap(
                attachmentRange(
                    in: text
                )
            )

        return try XCTUnwrap(
            text.attribute(
                .boldWriterWordPictureCrop,
                at: range.location,
                effectiveRange: nil
            )
            as? WordPictureCrop
        )
    }

    private func attachment(
        in text: NSAttributedString
    ) throws -> NSTextAttachment {
        let range =
            try XCTUnwrap(
                attachmentRange(
                    in: text
                )
            )

        return try XCTUnwrap(
            text.attribute(
                .attachment,
                at: range.location,
                effectiveRange: nil
            )
            as? NSTextAttachment
        )
    }

    private func verifyCrop(
        _ crop: WordPictureCrop,
        fixture: Fixture
    ) {
        XCTAssertEqual(crop.left, fixture.left)
        XCTAssertEqual(crop.top, fixture.top)
        XCTAssertEqual(crop.right, fixture.right)
        XCTAssertEqual(crop.bottom, fixture.bottom)
    }

    private func documentXML(
        _ data: Data
    ) throws -> String {
        let directory =
            FileManager.default
                .temporaryDirectory
                .appendingPathComponent(
                    UUID().uuidString,
                    isDirectory: true
                )

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        defer {
            try? FileManager.default.removeItem(
                at: directory
            )
        }

        let file =
            directory.appendingPathComponent(
                "crop.docx"
            )

        try data.write(to: file)

        let process = Process()
        process.executableURL =
            URL(
                fileURLWithPath:
                    "/usr/bin/unzip"
            )
        process.arguments =
            [
                "-p",
                file.path,
                "word/document.xml"
            ]

        let output = Pipe()
        process.standardOutput = output

        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(
            process.terminationStatus,
            0
        )

        return String(
            data:
                output.fileHandleForReading
                    .readDataToEndOfFile(),
            encoding:
                .utf8
        )
        ?? ""
    }

    private func sourceRectTag(
        in xml: String
    ) throws -> String {
        let prefix =
            try XCTUnwrap(
                xml.range(
                    of:
                        "<a:srcRect"
                )
            )

        let remainder =
            xml[
                prefix.lowerBound...
            ]

        let end =
            try XCTUnwrap(
                remainder.firstIndex(
                    of:
                        ">"
                )
            )

        return String(
            remainder[
                ...end
            ]
        )
    }

    private func verifyXML(
        _ xml: String,
        fixture: Fixture
    ) throws {
        let tag =
            try sourceRectTag(
                in: xml
            )

        let quote =
            String(
                Character(
                    UnicodeScalar(34)
                )
            )

        func attribute(
            _ name: String,
            _ value: Int
        ) -> String {
            name
                + "="
                + quote
                + String(value)
                + quote
        }

        XCTAssertTrue(
            tag.contains(
                attribute(
                    "l",
                    fixture.left
                )
            ),
            "srcRect tag was: \(tag)"
        )

        XCTAssertTrue(
            tag.contains(
                attribute(
                    "t",
                    fixture.top
                )
            ),
            "srcRect tag was: \(tag)"
        )

        XCTAssertTrue(
            tag.contains(
                attribute(
                    "r",
                    fixture.right
                )
            ),
            "srcRect tag was: \(tag)"
        )

        XCTAssertTrue(
            tag.contains(
                attribute(
                    "b",
                    fixture.bottom
                )
            ),
            "srcRect tag was: \(tag)"
        )
    }

    func testIndependentWordImageCropRoundTripsTwice()
        throws
    {
        let originalPNG =
            try XCTUnwrap(
                Data(
                    base64Encoded:
                        "iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAIAAAAmkwkpAAAAFElEQVR4nGP4z8DAAMb//0MZBDkA+EkT7YP5CsUAAAAASUVORK5CYII="
                )
            )

        for (
            name,
            fixture
        ) in try fixtures()
            .sorted(
                by: {
                    $0.key < $1.key
                }
            )
        {
            let first =
                try DOCXImporter
                    .importedDocument(
                        from: fixture.data
                    )

            verifyCrop(
                try crop(
                    in: first.text
                ),
                fixture: fixture
            )

            let image =
                try attachment(
                    in: first.text
                )

            let source =
                try XCTUnwrap(
                    image.fileWrapper?
                        .regularFileContents
                        ?? image.contents
                )

            XCTAssertEqual(
                source,
                originalPNG
            )

            let bitmap =
                try XCTUnwrap(
                    NSBitmapImageRep(
                        data: source
                    )
                )

            XCTAssertEqual(
                bitmap.pixelsWide,
                4
            )

            XCTAssertEqual(
                bitmap.pixelsHigh,
                4
            )

            let export1 =
                try DOCXExporter.data(
                    from: first.text,
                    title: "Crop \(name) 1",
                    settings: first.page,
                    sections: first.sections
                )

            try verifyXML(
                documentXML(export1),
                fixture: fixture
            )

            let second =
                try DOCXImporter
                    .importedDocument(
                        from: export1
                    )

            verifyCrop(
                try crop(
                    in: second.text
                ),
                fixture: fixture
            )

            let export2 =
                try DOCXExporter.data(
                    from: second.text,
                    title: "Crop \(name) 2",
                    settings: second.page,
                    sections: second.sections
                )

            try verifyXML(
                documentXML(export2),
                fixture: fixture
            )

            let third =
                try DOCXImporter
                    .importedDocument(
                        from: export2
                    )

            verifyCrop(
                try crop(
                    in: third.text
                ),
                fixture: fixture
            )

            print(
                "WORD_IMAGE_CROP_ROUNDTRIP"
                + "|fixture=\(name)"
                + "|l=\(fixture.left)"
                + "|t=\(fixture.top)"
                + "|r=\(fixture.right)"
                + "|b=\(fixture.bottom)"
            )
        }
    }

    func testUncroppedWordPictureDoesNotGainSrcRect()
        throws
    {
        let data =
            try XCTUnwrap(
                Data(
                    base64Encoded:
                        "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"
                )
            )

        let imported =
            try DOCXImporter
                .importedDocument(
                    from: data
                )

        let range =
            try XCTUnwrap(
                attachmentRange(
                    in: imported.text
                )
            )

        XCTAssertNil(
            imported.text.attribute(
                .boldWriterWordPictureCrop,
                at: range.location,
                effectiveRange: nil
            )
        )

        let exported =
            try DOCXExporter.data(
                from: imported.text,
                title: "Uncropped",
                settings: imported.page,
                sections: imported.sections
            )

        XCTAssertFalse(
            try documentXML(exported)
                .contains(
                    "srcRect"
                )
        )
    }

    func testWordImageCropSurvivesRealBOLDPackageSaveReopen()
        throws
    {
        let fixture =
            try XCTUnwrap(
                try fixtures()["all"]
            )

        let imported =
            try DOCXImporter
                .importedDocument(
                    from: fixture.data
                )

        let metadata =
            DocumentMetadata(
                title:
                    "Crop Native Persistence"
            )

        let wrapper =
            try BOLDWriterDocument
                .packageWrapper(
                    text: imported.text,
                    metadata: metadata
                )

        let reopened =
            try BOLDWriterDocument(
                fileWrapper: wrapper,
                contentType: .boldWriterDocument
            )

        verifyCrop(
            try crop(
                in: reopened.text
            ),
            fixture: fixture
        )

        let exported =
            try DOCXExporter.data(
                from: reopened.text,
                title: "Native Crop",
                settings: reopened.metadata.page,
                sections: reopened.metadata.sections
            )

        try verifyXML(
            documentXML(exported),
            fixture: fixture
        )

        print(
            "WORD_IMAGE_CROP_NATIVE"
            + "|l=\(fixture.left)"
            + "|t=\(fixture.top)"
            + "|r=\(fixture.right)"
            + "|b=\(fixture.bottom)"
        )
    }
}
