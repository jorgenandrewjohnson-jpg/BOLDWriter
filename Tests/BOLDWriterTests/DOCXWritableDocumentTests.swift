import AppKit
import UniformTypeIdentifiers
import XCTest
@testable import BOLDWriter

final class DOCXWritableDocumentTests:
    XCTestCase
{
    func testDOCXIsReadableAndWritable() {
        XCTAssertTrue(
            BOLDWriterDocument
                .readableContentTypes
                .contains(
                    .docx
                )
        )

        XCTAssertTrue(
            BOLDWriterDocument
                .writableContentTypes
                .contains(
                    .docx
                )
        )
    }

    func testDOCXExporterProducesReopenableEditableContent() throws {
        let source =
            NSAttributedString(
                string:
                    "Editable Word document test."
            )

        let data =
            try DOCXExporter.data(
                from:
                    source,
                title:
                    "Editable Test"
            )

        XCTAssertFalse(
            data.isEmpty
        )

        let imported =
            try DOCXImporter
                .importedDocument(
                    from:
                        data
                )

        XCTAssertEqual(
            imported.text.string,
            source.string
        )
    }

    func testNativeFormatRemainsWritable() {
        XCTAssertTrue(
            BOLDWriterDocument
                .writableContentTypes
                .contains(
                    .boldWriterDocument
                )
        )
    }
}
