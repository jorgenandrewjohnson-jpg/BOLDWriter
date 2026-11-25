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

    func testImportedFormatsCannotOverwriteTheirSourceWithANativePackage() {
        let document = BOLDWriterDocument()
        for type in [UTType.rtfd, .rtf, .pdf, .plainText, .html] {
            XCTAssertThrowsError(try document.snapshot(contentType: type)) { error in
                XCTAssertTrue(
                    error.localizedDescription.contains("cannot be saved in place"),
                    "Expected a safe-save explanation for \(type): \(error)"
                )
            }
        }
    }

    func testSupportedFormatsStillProduceSnapshots() throws {
        let document = BOLDWriterDocument()
        XCTAssertNotNil(try document.snapshot(contentType: .boldWriterDocument))
        XCTAssertNotNil(try document.snapshot(contentType: .docx))
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
