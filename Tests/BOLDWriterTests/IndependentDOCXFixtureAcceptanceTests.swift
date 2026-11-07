import AppKit
import CryptoKit
import XCTest
@testable import BOLDWriter

/// Imports the on-disk independent DrawingML fixture through BOLD Writer's
/// actual document importer, then proves native persistence and safe re-export.
@MainActor
final class IndependentDOCXFixtureAcceptanceTests: XCTestCase {
    func testIndependentDiskFloatingAnchorFixtureImportNativeReopenAndExport() throws {
        guard let fixturePath = ProcessInfo.processInfo.environment["BOLD_QA_DOCX_FIXTURE"] else {
            throw XCTSkip("Set BOLD_QA_DOCX_FIXTURE to import the retained independent DrawingML package")
        }
        guard let reportPath = ProcessInfo.processInfo.environment["BOLD_QA_DOCX_REPORT"] else {
            throw XCTSkip("Set BOLD_QA_DOCX_REPORT to retain interoperability evidence")
        }
        let fixture = URL(fileURLWithPath: fixturePath).standardizedFileURL
        let reportURL = URL(fileURLWithPath: reportPath).standardizedFileURL
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: reportURL.path), "Refusing to overwrite evidence")

        let sourceBytes = try Data(contentsOf: fixture)
        let sourceEntries = try DOCXPackage.entries(in: sourceBytes)
        let sourceParts = Dictionary(uniqueKeysWithValues: sourceEntries.map { ($0.path, $0.data) })
        let sourceXML = String(decoding: try XCTUnwrap(sourceParts["word/document.xml"]), as: UTF8.self)
        let sourceRelationships = String(decoding: try XCTUnwrap(sourceParts["word/_rels/document.xml.rels"]), as: UTF8.self)
        let sourceImage = try XCTUnwrap(sourceParts["word/media/floating.png"])
        let sourceImageHash = Self.sha256(sourceImage)
        XCTAssertTrue(sourceXML.contains("<wp:anchor"))
        XCTAssertTrue(sourceXML.contains("<wp:wrapSquare"))
        XCTAssertTrue(sourceRelationships.contains("floating.png"))

        let imported = try BOLDWriterDocument(fileWrapper: FileWrapper(url: fixture), contentType: .docx)
        XCTAssertTrue(imported.text.string.contains("Before anchor"))
        XCTAssertTrue(imported.text.string.contains("After anchor"))
        XCTAssertNotNil(imported.lastErrorMessage, "Unsupported floating placement must be explicitly reported")
        XCTAssertTrue(imported.lastErrorMessage?.localizedCaseInsensitiveContains("unsupported") == true)
        var attachments: [NSTextAttachment] = []
        imported.text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: imported.text.length)) { value, _, _ in
            if let attachment = value as? NSTextAttachment { attachments.append(attachment) }
        }
        XCTAssertEqual(attachments.count, 1)
        let importedImage = try XCTUnwrap(attachments.first?.fileWrapper?.regularFileContents)
        XCTAssertEqual(Self.sha256(importedImage), sourceImageHash, "Importer must preserve exact original image bytes")

        let native = try BOLDWriterDocument.packageWrapper(text: imported.text, metadata: imported.metadata)
        let reopened = try BOLDWriterDocument(fileWrapper: native, contentType: .boldWriterDocument)
        XCTAssertEqual(reopened.text.string, imported.text.string)
        var reopenedAttachments: [NSTextAttachment] = []
        reopened.text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: reopened.text.length)) { value, _, _ in
            if let attachment = value as? NSTextAttachment { reopenedAttachments.append(attachment) }
        }
        XCTAssertEqual(reopenedAttachments.count, 1)
        XCTAssertEqual(Self.sha256(try XCTUnwrap(reopenedAttachments.first?.fileWrapper?.regularFileContents)), sourceImageHash)

        let exported = try ExportService.data(for: .docx, document: reopened)
        let exportedEntries = try DOCXPackage.entries(in: exported)
        let exportedParts = Dictionary(uniqueKeysWithValues: exportedEntries.map { ($0.path, $0.data) })
        let exportedXML = String(decoding: try XCTUnwrap(exportedParts["word/document.xml"]), as: UTF8.self)
        XCTAssertTrue(exportedXML.contains("<wp:inline"))
        XCTAssertFalse(exportedXML.contains("<wp:anchor"), "Exporter must not claim unsupported floating round-trip fidelity")
        let exportedImage = try XCTUnwrap(exportedEntries.first(where: { $0.path.hasPrefix("word/media/") })?.data)
        XCTAssertEqual(Self.sha256(exportedImage), sourceImageHash)

        let report: [String: Any] = [
            "sourceFixture": fixture.path,
            "sourceFixtureSHA256": Self.sha256(sourceBytes),
            "sourceDrawingType": "wp:anchor",
            "sourceWrapping": "wp:wrapSquare",
            "sourceImageSHA256": sourceImageHash,
            "sourceRelationship": "word/_rels/document.xml.rels -> word/media/floating.png",
            "importedImageSHA256": Self.sha256(importedImage),
            "importWarning": imported.lastErrorMessage ?? "",
            "nativeReopenTextPreserved": reopened.text.string == imported.text.string,
            "nativeReopenImageSHA256": Self.sha256(try XCTUnwrap(reopenedAttachments.first?.fileWrapper?.regularFileContents)),
            "exportedImageSHA256": Self.sha256(exportedImage),
            "exportedDrawingType": "wp:inline",
            "floatingPositionRoundTrip": false,
            "classification": "safe-degradation interoperability gap; content/image preserved while position/wrapping are not"
        ]
        try FileManager.default.createDirectory(at: reportURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: reportURL, options: .atomic)
        print("BOLD_QA_DOCX_FIXTURE_REPORT=\(reportURL.path)")
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
