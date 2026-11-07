import AppKit
import CryptoKit
import XCTest
@testable import BOLDWriter

/// Confirms a real source DOCX with unsupported first-page footer alignment is
/// rejected explicitly, without implying that its manuscript was imported.
@MainActor
final class RealManuscriptDOCXSafeRejectionAcceptanceTests: XCTestCase {
    func testDisposableLongManuscriptDOCXUnsupportedFooterIsSafelyRejected() throws {
        guard let inputPath = ProcessInfo.processInfo.environment["BOLD_QA_REAL_DOCX_COPY"],
              let reportPath = ProcessInfo.processInfo.environment["BOLD_QA_REAL_DOCX_REPORT"] else {
            throw XCTSkip("Set BOLD_QA_REAL_DOCX_COPY and BOLD_QA_REAL_DOCX_REPORT")
        }
        let inputURL = URL(fileURLWithPath: inputPath).standardizedFileURL
        let reportURL = URL(fileURLWithPath: reportPath).standardizedFileURL
        XCTAssertTrue(inputURL.path.contains("/Audit/QA/Disposable-Manuscripts/"))
        XCTAssertTrue(inputURL.lastPathComponent.contains("TEST-COPY-DO-NOT-USE-AS-ORIGINAL"))
        let sourceData = try Data(contentsOf: inputURL)
        let entries = try DOCXPackage.entries(in: sourceData)
        let parts = Dictionary(uniqueKeysWithValues: entries.map { ($0.path, $0.data) })
        let documentXML = String(decoding: try XCTUnwrap(parts["word/document.xml"]), as: UTF8.self)
        let relationships = String(decoding: try XCTUnwrap(parts["word/_rels/document.xml.rels"]), as: UTF8.self)
        let mediaHashes = entries.filter { $0.path.hasPrefix("word/media/") }
            .map { ["part": $0.path, "sha256": Self.sha256($0.data)] }
        let sectionCount = documentXML.components(separatedBy: "<w:sectPr").count - 1
        let firstPageFooterRefs = Self.attributeValues(named: "w:type", inTagsNamed: "w:footerReference", xml: documentXML)
        let footerAlignments = entries.filter { $0.path.hasPrefix("word/footer") && $0.path.hasSuffix(".xml") }
            .map { String(decoding: $0.data, as: UTF8.self) }
            .flatMap { Self.attributeValues(named: "w:val", inTagsNamed: "w:jc", xml: $0) }
            .sorted()

        var observedError = ""
        XCTAssertThrowsError(try BOLDWriterDocument(fileWrapper: FileWrapper(url: inputURL), contentType: .docx)) { error in
            observedError = String(describing: error)
        }
        XCTAssertTrue(observedError.localizedCaseInsensitiveContains("first-page footer uses a different alignment"), observedError)
        XCTAssertTrue(relationships.contains("footer"), "The source DOCX should retain footer relationships")
        XCTAssertGreaterThan(sectionCount, 0)

        let report: [String: Any] = [
            "sourceCopy": inputURL.path,
            "sourceSHA256": Self.sha256(sourceData),
            "sourceBytes": sourceData.count,
            "sourceDOCXSectionCount": sectionCount,
            "firstPageFooterReferenceTypes": firstPageFooterRefs,
            "footerParagraphAlignmentValues": footerAlignments,
            "footerRelationshipsPresent": relationships.contains("footer"),
            "mediaSHA256": mediaHashes,
            "observedImportError": observedError,
            "nativeDocumentProduced": false,
            "classification": "PARTIAL: source is safely rejected because first-page footer alignment is not representable; no content was silently discarded"
        ]
        try FileManager.default.createDirectory(at: reportURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: reportURL, options: .atomic)
        print("BOLD_QA_REAL_MANUSCRIPT_REPORT=\(reportURL.path)")
    }

    private static func attributeValues(named attribute: String, inTagsNamed tag: String, xml: String) -> [String] {
        let pattern = "<\(tag)\\b([^>]*)>"
        guard let tagRegex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsXML = xml as NSString
        return tagRegex.matches(in: xml, range: NSRange(location: 0, length: nsXML.length)).compactMap { match in
            let attrs = nsXML.substring(with: match.range(at: 1))
            guard let attributeRegex = try? NSRegularExpression(pattern: "\(attribute)=\"([^\"]+)\"") else { return nil }
            let nsAttrs = attrs as NSString
            guard let value = attributeRegex.firstMatch(in: attrs, range: NSRange(location: 0, length: nsAttrs.length)) else { return nil }
            return nsAttrs.substring(with: value.range(at: 1))
        }
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
