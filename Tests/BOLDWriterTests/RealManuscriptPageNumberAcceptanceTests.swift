import AppKit
import CryptoKit
import PDFKit
import XCTest
@testable import BOLDWriter

/// Opt-in production PDF check for the authorized, isolated QA manuscript copy.
/// The test never writes to or modifies its DOCX input.
@MainActor
final class RealManuscriptPageNumberAcceptanceTests: XCTestCase {
    func testDisposable356PageDOCXDoesNotDuplicateFooterLabelInPDF() throws {
        guard let inputPath = ProcessInfo.processInfo.environment["BOLD_M41_PAGE_NUMBER_DOCX"],
              let outputPath = ProcessInfo.processInfo.environment["BOLD_M41_PAGE_NUMBER_PDF"] else {
            throw XCTSkip("Set BOLD_M41_PAGE_NUMBER_DOCX and BOLD_M41_PAGE_NUMBER_PDF to isolated test-copy paths")
        }

        let inputURL = URL(fileURLWithPath: inputPath).standardizedFileURL
        let outputURL = URL(fileURLWithPath: outputPath).standardizedFileURL
        XCTAssertTrue(inputURL.lastPathComponent.contains("TEST-COPY-DO-NOT-USE-AS-ORIGINAL"))
        XCTAssertTrue(inputURL.path.contains("/QA/Milestone41/"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))

        let sourceData = try Data(contentsOf: inputURL)
        let sourceHash = Self.sha256(sourceData)
        let imported = try BOLDWriterDocument(
            fileWrapper: FileWrapper(url: inputURL),
            contentType: .docx
        )
        let pdfData = try PDFExporter.data(
            from: imported.text,
            settings: imported.metadata.page,
            sections: imported.metadata.sections
        )
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try pdfData.write(to: outputURL, options: .atomic)

        let pdf = try XCTUnwrap(PDFDocument(data: pdfData))
        XCTAssertEqual(pdf.pageCount, 356, "The original QA reproduction should remain a 356-page export")
        let duplicateLabel = try NSRegularExpression(pattern: #"(?i)Page\s+Page\s*\d+"#)
        let pageLabel = try NSRegularExpression(pattern: #"(?i)Page\s+(\d+)"#)
        var duplicatePages: [Int] = []

        for pageIndex in 0..<pdf.pageCount {
            let text = try XCTUnwrap(pdf.page(at: pageIndex)?.string)
            let nsText = text as NSString
            let tailStart = max(0, nsText.length - 120)
            let tail = nsText.substring(from: tailStart)
            let tailNSString = tail as NSString
            let tailRange = NSRange(location: 0, length: tailNSString.length)
            if duplicateLabel.firstMatch(in: tail, range: tailRange) != nil {
                duplicatePages.append(pageIndex + 1)
            }
            let labels = pageLabel.matches(in: tail, range: tailRange)
            let lastLabel = try XCTUnwrap(labels.last, "Page \(pageIndex + 1) should end with a physical page label.")
            let numberRange = lastLabel.range(at: 1)
            let number = Int(tailNSString.substring(with: numberRange))
            XCTAssertEqual(number, pageIndex + 1, "PDF page \(pageIndex + 1) should show its physical page number.")
        }

        XCTAssertTrue(duplicatePages.isEmpty, "Duplicated page labels remain on pages: \(duplicatePages)")
        let firstMediaBox = try XCTUnwrap(pdf.page(at: 0)).bounds(for: .mediaBox)
        let lastMediaBox = try XCTUnwrap(pdf.page(at: pdf.pageCount - 1)).bounds(for: .mediaBox)
        XCTAssertEqual(firstMediaBox.width, 396, accuracy: 0.01)
        XCTAssertEqual(firstMediaBox.height, 612, accuracy: 0.01)
        XCTAssertEqual(lastMediaBox.width, 396, accuracy: 0.01)
        XCTAssertEqual(lastMediaBox.height, 612, accuracy: 0.01)
        XCTAssertEqual(Self.sha256(try Data(contentsOf: inputURL)), sourceHash, "PDF export must not modify the disposable DOCX source")
        print("BOLD_M41_PAGE_NUMBER_ACCEPTANCE=\(outputURL.path) pages=\(pdf.pageCount) sourceSHA256=\(sourceHash) pdfSHA256=\(Self.sha256(pdfData)) duplicateLabelPages=\(duplicatePages.count)")
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
