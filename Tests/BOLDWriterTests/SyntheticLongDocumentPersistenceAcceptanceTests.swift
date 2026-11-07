import AppKit
import CryptoKit
import Foundation
import XCTest
@testable import BOLDWriter

/// Imports deterministic synthetic RTF manuscripts, saves them as native
/// packages, and verifies text, sampled typography, and page setup after reopen.
/// No original or user-authored documents are accessed.
@MainActor
final class SyntheticLongDocumentPersistenceAcceptanceTests: XCTestCase {
    func testSyntheticLongManuscriptsSurviveNativeSaveAndReopen() throws {
        guard let fixtureRootPath = ProcessInfo.processInfo.environment["BOLD_QA_LONG_FIXTURE_ROOT"],
              let outputRootPath = ProcessInfo.processInfo.environment["BOLD_QA_LONG_OUTPUT_ROOT"] else {
            throw XCTSkip("Set BOLD_QA_LONG_FIXTURE_ROOT and BOLD_QA_LONG_OUTPUT_ROOT for disposable synthetic persistence acceptance.")
        }
        let fixtureRoot = URL(fileURLWithPath: fixtureRootPath, isDirectory: true)
        let outputRoot = URL(fileURLWithPath: outputRootPath, isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputRoot.path), "Refusing to overwrite evidence")
        try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)

        var records: [[String: Any]] = []
        for pages in [10, 100, 391, 1_000] {
            let fixture = fixtureRoot.appendingPathComponent(String(format: "synthetic-%04d-page-import.rtf", pages))
            XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.path), "Missing synthetic fixture: \(fixture.path)")
            let sourceBytes = try Data(contentsOf: fixture)
            let imported = try BOLDWriterDocument(fileWrapper: FileWrapper(url: fixture), contentType: .rtf)
            let sourceText = imported.text.string
            let utf16Length = (sourceText as NSString).length
            XCTAssertGreaterThan(utf16Length, pages * 100)
            for page in [1, max(1, pages / 2), pages] {
                XCTAssertTrue(sourceText.contains("Page marker \(page) of \(pages)."), "Page marker lost during import: \(page)/\(pages)")
            }
            XCTAssertTrue(sourceText.contains("café"))
            XCTAssertTrue(sourceText.contains("東京"))

            let headingRange = (sourceText as NSString).range(of: "Chapter 1:")
            let bodyRange = (sourceText as NSString).range(of: "A long paragraph follows:")
            XCTAssertNotEqual(headingRange.location, NSNotFound)
            XCTAssertNotEqual(bodyRange.location, NSNotFound)
            let headingFont = try XCTUnwrap(imported.text.attribute(.font, at: headingRange.location, effectiveRange: nil) as? NSFont)
            let bodyFont = try XCTUnwrap(imported.text.attribute(.font, at: bodyRange.location, effectiveRange: nil) as? NSFont)
            XCTAssertEqual(headingFont.pointSize, 15, accuracy: 0.1)
            XCTAssertEqual(bodyFont.pointSize, 11, accuracy: 0.1)

            var page = imported.metadata.page
            page.paper = .custom
            page.customPaperSize = CGSize(width: 396, height: 612)
            page.leftMargin = 48; page.rightMargin = 48
            page.topMargin = 54; page.bottomMargin = 54
            page.gutter = 12; page.mirrorMargins = true
            imported.metadata.page = page
            imported.metadata.title = "Synthetic \(pages)-page Persistence Acceptance"

            let packageURL = outputRoot.appendingPathComponent("synthetic-\(pages)-page.boldwriter", isDirectory: true)
            try BOLDWriterDocument.packageWrapper(text: imported.text, metadata: imported.metadata)
                .write(to: packageURL, options: .atomic, originalContentsURL: nil)
            let reopened = try BOLDWriterDocument(fileWrapper: FileWrapper(url: packageURL), contentType: .boldWriterDocument)
            XCTAssertEqual(reopened.text.string, sourceText, "Native save/reopen changed manuscript text at \(pages) pages")
            XCTAssertEqual(Self.sha256(Data(reopened.text.string.utf8)), Self.sha256(Data(sourceText.utf8)))
            XCTAssertEqual(reopened.metadata.title, imported.metadata.title)
            XCTAssertEqual(reopened.metadata.page, page)
            let reopenedHeadingFont = try XCTUnwrap(reopened.text.attribute(.font, at: headingRange.location, effectiveRange: nil) as? NSFont)
            let reopenedBodyFont = try XCTUnwrap(reopened.text.attribute(.font, at: bodyRange.location, effectiveRange: nil) as? NSFont)
            XCTAssertEqual(reopenedHeadingFont.fontName, headingFont.fontName)
            XCTAssertEqual(reopenedHeadingFont.pointSize, headingFont.pointSize, accuracy: 0.01)
            XCTAssertEqual(reopenedBodyFont.fontName, bodyFont.fontName)
            XCTAssertEqual(reopenedBodyFont.pointSize, bodyFont.pointSize, accuracy: 0.01)

            records.append([
                "nominalPages": pages,
                "fixture": fixture.lastPathComponent,
                "fixtureSHA256": Self.sha256(sourceBytes),
                "characterCount": sourceText.count,
                "utf16Length": utf16Length,
                "paragraphCount": sourceText.components(separatedBy: .newlines).filter { !$0.isEmpty }.count,
                "textSHA256": Self.sha256(Data(sourceText.utf8)),
                "nativePackage": packageURL.path,
                "nativeSaveReopenTextIdentical": true,
                "pageSetupPreserved": true,
                "typographySamplesPreserved": [
                    ["sample": "Chapter 1 heading", "font": headingFont.fontName, "size": headingFont.pointSize],
                    ["sample": "body paragraph", "font": bodyFont.fontName, "size": bodyFont.pointSize]
                ]
            ])
        }
        let report: [String: Any] = [
            "sourceRevision": ProcessInfo.processInfo.environment["BOLD_QA_SOURCE_REVISION"] ?? "unspecified",
            "fixtureType": "synthetic, deterministic rich-text RTF; no private author manuscripts",
            "operation": "BOLD Writer RTF importer -> native package serialization -> native package reopen",
            "results": records
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: outputRoot.appendingPathComponent("synthetic-long-document-integrity.json"), options: .atomic)
        print("BOLD_QA_LONG_DOCUMENT_REPORT=\(outputRoot.appendingPathComponent("synthetic-long-document-integrity.json").path)")
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
