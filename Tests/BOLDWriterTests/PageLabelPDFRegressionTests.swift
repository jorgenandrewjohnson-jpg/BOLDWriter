import AppKit
import CryptoKit
import PDFKit
import XCTest
@testable import BOLDWriter

/// Deterministic synthetic counterpart to BLW-QA-002's 356-page source-copy test.
@MainActor
final class PageLabelPDFRegressionTests: XCTestCase {
    func testImportedStaticPageFooterAndDynamicFieldRenderOncePerPage() throws {
        let markers = [
            "QA_PAGE_LABEL_FIRST Ω — first-page text",
            "QA_PAGE_LABEL_MIDDLE — middle-page text",
            "QA_PAGE_LABEL_FINAL — final-page text"
        ]
        let inputText = NSAttributedString(
            string: markers.joined(separator: "\u{000C}"),
            attributes: [.font: NSFont.systemFont(ofSize: 12)]
        )
        var settings = PageSettings(customPaperSize: CGSize(width: 396, height: 612))
        settings.topMargin = 54
        settings.bottomMargin = 54
        settings.leftMargin = 45
        settings.rightMargin = 45
        settings.headerText = ""
        settings.footerText = "Page"
        settings.footerPosition = .center
        settings.pageNumberPosition = .center
        settings.showsPageNumbers = true
        settings.differentOddEvenHeaderFooter = true
        settings.evenPageFooterText = "Page"
        settings.evenPageFooterPosition = .center
        settings.evenPageNumberPosition = .center

        let exportedDOCX = try DOCXExporter.data(from: inputText, title: "QA page-label reproduction", settings: settings)
        var packageEntries = try DOCXPackage.entries(in: exportedDOCX)
        let simpleField = #"<w:fldSimple w:instr=" PAGE "><w:r><w:t>1</w:t></w:r></w:fldSimple>"#
        let complexField = #"<w:r><w:fldChar w:fldCharType="begin"/></w:r><w:r><w:instrText xml:space="preserve"> PAGE </w:instrText></w:r><w:r><w:fldChar w:fldCharType="separate"/></w:r><w:r><w:t>1</w:t></w:r><w:r><w:fldChar w:fldCharType="end"/></w:r>"#
        var patchedFooterCount = 0
        for index in packageEntries.indices where packageEntries[index].path.hasPrefix("word/footer") && packageEntries[index].path.hasSuffix(".xml") {
            var xml = String(decoding: packageEntries[index].data, as: UTF8.self)
            guard xml.contains(simpleField) else { continue }
            xml = xml.replacingOccurrences(of: "<w:t xml:space=\"preserve\">Page   •   </w:t>", with: "<w:t xml:space=\"preserve\">Page </w:t>")
            xml = xml.replacingOccurrences(of: simpleField, with: complexField)
            packageEntries[index].data = Data(xml.utf8)
            patchedFooterCount += 1
        }
        XCTAssertGreaterThan(patchedFooterCount, 0, "The deterministic DOCX must include at least one footer PAGE field to patch")
        let sourceDOCX = ZipArchiveWriter.archive(packageEntries)
        if let path = ProcessInfo.processInfo.environment["BOLD_QA_PAGE_LABEL_DOCX_OUTPUT"] {
            try sourceDOCX.write(to: URL(fileURLWithPath: path), options: .atomic)
        }
        let entries = try DOCXPackage.entries(in: sourceDOCX)
        let footerParts = try entries.filter { $0.path.hasPrefix("word/footer") && $0.path.hasSuffix(".xml") }.map { entry -> (String, String, String) in
            let xml = try DOCXPackage.xml(entry.data)
            let staticText = try xml.nodes(forXPath: "//*[local-name()='t']").compactMap(\.stringValue).joined()
            let instructions = try xml.nodes(forXPath: "//*[local-name()='instrText']").compactMap(\.stringValue).joined()
            return (staticText, instructions, String(decoding: entry.data, as: UTF8.self))
        }
        let staticText = footerParts.map(\.0).joined()
        let fieldInstructions = footerParts.map(\.1).joined()
        let footerSource = footerParts.map(\.2).joined()
        XCTAssertTrue(staticText.contains("Page"), "The fixture must contain a static Page label.")
        XCTAssertTrue((fieldInstructions + footerSource).uppercased().contains("PAGE"), "The fixture must contain a real PAGE field.")

        let imported = try DOCXImporter.importedDocument(from: sourceDOCX)
        XCTAssertTrue(imported.page.showsPageNumbers)
        XCTAssertEqual(imported.page.footerText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), "Page")
        let native = BOLDWriterDocument()
        native.replaceText(with: imported.text)
        native.metadata.page = imported.page
        native.metadata.sections = imported.sections
        let package = try BOLDWriterDocument.packageWrapper(text: native.text, metadata: native.metadata)
        let reopened = try BOLDWriterDocument(fileWrapper: package, contentType: .boldWriterDocument)
        XCTAssertEqual(reopened.metadata.page, imported.page)
        XCTAssertEqual(reopened.text.string, imported.text.string)
        let pdfData = try PDFExporter.data(from: reopened.text, settings: reopened.metadata.page, sections: reopened.metadata.sections)
        let pdf = try XCTUnwrap(PDFDocument(data: pdfData), "The production PDF must reopen through PDFKit")
        XCTAssertEqual(pdf.pageCount, markers.count)

        let duplicate = try NSRegularExpression(pattern: "(?i)Page\\s*Page\\s*(?:•\\s*)?\\d+")
        var pageEvidence: [[String: Any]] = []
        var duplicateLabelPages: [Int] = []
        for index in 0..<pdf.pageCount {
            let page = try XCTUnwrap(pdf.page(at: index))
            let text = page.string ?? ""
            let range = NSRange(location: 0, length: (text as NSString).length)
            let duplicates = duplicate.numberOfMatches(in: text, range: range)
            let mediaBox = page.bounds(for: .mediaBox)
            XCTAssertEqual(mediaBox.width, 612, accuracy: 0.01)
            XCTAssertEqual(mediaBox.height, 792, accuracy: 0.01)
            XCTAssertTrue(text.contains(markers[index]), "Page \(index + 1) must retain its expected marker")
            if duplicates > 0 { duplicateLabelPages.append(index + 1) }
            pageEvidence.append(["page": index + 1, "duplicateLabelMatches": duplicates, "pageText": text, "mediaBoxPoints": [mediaBox.width, mediaBox.height], "expectedMarkerPresent": text.contains(markers[index])])
        }

        if let path = ProcessInfo.processInfo.environment["BOLD_QA_PAGE_LABEL_PDF_OUTPUT"] {
            try pdfData.write(to: URL(fileURLWithPath: path), options: .atomic)
        }
        if let path = ProcessInfo.processInfo.environment["BOLD_QA_PAGE_LABEL_REPORT"] {
            let report: [String: Any] = ["synthetic": true, "sourceDOCXSHA256": Self.sha256(sourceDOCX), "productionPDFSHA256": Self.sha256(pdfData), "pageCount": pdf.pageCount, "duplicateLabelPages": duplicateLabelPages, "footerStaticLabel": "Page", "dynamicField": "PAGE", "pages": pageEvidence]
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        }

        XCTAssertTrue(duplicateLabelPages.isEmpty,
                      "BLW-QA-002: static Page label duplicated with the PAGE field on pages \(duplicateLabelPages)")
    }

    private static func sha256(_ data: Data) -> String {
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
