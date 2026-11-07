import AppKit
import CryptoKit
import PDFKit
import XCTest
@testable import BOLDWriter

/// Uses only staged copies of user manuscripts. Reports hashes/counts, never text.
@MainActor
final class RealManuscriptDOCXRoundTripAcceptanceTests: XCTestCase {
    func testDisposableRealManuscriptDOCXNativeAndDOCXRoundTrip() throws {
        guard let inputPath = ProcessInfo.processInfo.environment["BOLD_QA_REAL_DOCX_COPY"],
              let nativePath = ProcessInfo.processInfo.environment["BOLD_QA_REAL_NATIVE_OUTPUT"],
              let docxPath = ProcessInfo.processInfo.environment["BOLD_QA_REAL_DOCX_OUTPUT"],
              let pdfPath = ProcessInfo.processInfo.environment["BOLD_QA_REAL_PDF_OUTPUT"],
              let reportPath = ProcessInfo.processInfo.environment["BOLD_QA_REAL_DOCX_REPORT"] else {
            throw XCTSkip("Set BOLD_QA_REAL_DOCX_COPY and isolated native, DOCX, PDF, and report output paths")
        }
        let inputURL = URL(fileURLWithPath: inputPath).standardizedFileURL
        let nativeURL = URL(fileURLWithPath: nativePath).standardizedFileURL
        let outputURL = URL(fileURLWithPath: docxPath).standardizedFileURL
        let pdfURL = URL(fileURLWithPath: pdfPath).standardizedFileURL
        let reportURL = URL(fileURLWithPath: reportPath).standardizedFileURL
        XCTAssertTrue(inputURL.path.contains("/Audit/QA/Disposable-Manuscripts/"))
        XCTAssertTrue(inputURL.lastPathComponent.contains("TEST-COPY-DO-NOT-USE-AS-ORIGINAL"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: nativeURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: pdfURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: reportURL.path))

        let sourceData = try Data(contentsOf: inputURL)
        let imported = try BOLDWriterDocument(fileWrapper: FileWrapper(url: inputURL), contentType: .docx)
        let importedText = imported.text.string
        let importedTextHash = Self.sha256(Data(importedText.utf8))
        let edited = NSMutableAttributedString(attributedString: imported.text)
        let sourceNSString = importedText as NSString
        let searchStart = sourceNSString.length / 2
        let followingParagraph = sourceNSString.range(of: "\n", options: [], range: NSRange(location: searchStart, length: sourceNSString.length - searchStart))
        let middleEditLocation = followingParagraph.location == NSNotFound ? searchStart : followingParagraph.location + 1
        let editMarkers: [(String, Int)] = [
            ("<QA-THIRD-PASS-EDIT-START>", 0),
            ("<QA-THIRD-PASS-EDIT-MIDDLE>", middleEditLocation),
            ("<QA-THIRD-PASS-EDIT-END>", sourceNSString.length)
        ]
        for (marker, location) in editMarkers.sorted(by: { $0.1 > $1.1 }) {
            edited.insert(NSAttributedString(string: marker), at: location)
        }
        let editedText = edited.string
        let editedTextHash = Self.sha256(Data(editedText.utf8))
        let editsRestoreSourceText = editMarkers.reduce(editedText) { $0.replacingOccurrences(of: $1.0, with: "") } == importedText
        let importedAttachmentHashes = Self.attachmentHashes(in: imported.text)
        let importedAttributes = Self.attributeSummary(in: imported.text)

        try BOLDWriterDocument.packageWrapper(text: edited, metadata: imported.metadata)
            .write(to: nativeURL, options: .atomic, originalContentsURL: nil)
        let reopened = try BOLDWriterDocument(fileWrapper: FileWrapper(url: nativeURL), contentType: .boldWriterDocument)
        XCTAssertTrue(editsRestoreSourceText, "The three disposable edits should be reversible without changing source text")
        XCTAssertEqual(reopened.text.string, editedText, "Native persistence must preserve beginning/middle/end edits")
        XCTAssertEqual(Self.attachmentHashes(in: reopened.text), importedAttachmentHashes, "Native persistence must preserve embedded image bytes")

        let exportedData = try ExportService.data(for: .docx, document: reopened)
        try exportedData.write(to: outputURL, options: .atomic)
        let reimported = try BOLDWriterDocument(fileWrapper: FileWrapper(url: outputURL), contentType: .docx)
        let reimportedText = reimported.text.string
        let reimportedAttachmentHashes = Self.attachmentHashes(in: reimported.text)
        XCTAssertEqual(reimportedText, editedText, "DOCX export/reimport must preserve the exact disposable manuscript text")
        XCTAssertEqual(reimportedAttachmentHashes, importedAttachmentHashes, "DOCX round trip must retain attachment bytes")

        let sourceParts = try DOCXPackage.entries(in: sourceData)
        let outputParts = try DOCXPackage.entries(in: exportedData)
        let sourceMediaHashes = sourceParts.filter { $0.path.hasPrefix("word/media/") }.map { Self.sha256($0.data) }.sorted()
        let outputMediaHashes = outputParts.filter { $0.path.hasPrefix("word/media/") }.map { Self.sha256($0.data) }.sorted()
        let pdfData = try PDFExporter.data(from: reopened.text, settings: reopened.metadata.page, sections: reopened.metadata.sections)
        try pdfData.write(to: pdfURL, options: .atomic)
        let pdf = try XCTUnwrap(PDFDocument(data: pdfData), "BOLD Writer production PDF must reopen independently through PDFKit")
        XCTAssertGreaterThan(pdf.pageCount, 0)
        XCTAssertEqual(pdf.pageCount, 356, "The preserved BLW-QA-002 acceptance input is expected to paginate to 356 pages")
        let firstPage = try XCTUnwrap(pdf.page(at: 0))
        let lastPage = try XCTUnwrap(pdf.page(at: pdf.pageCount - 1))
        let firstMediaBox: CGRect = firstPage.bounds(for: .mediaBox)
        let lastMediaBox: CGRect = lastPage.bounds(for: .mediaBox)
        XCTAssertGreaterThan(firstMediaBox.width, 0)
        XCTAssertGreaterThan(lastMediaBox.height, 0)
        let pdfTextPages = (0..<pdf.pageCount).filter { !(pdf.page(at: $0)?.string?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty ?? true) }.count
        XCTAssertGreaterThan(pdfTextPages, 0)
        let duplicatePagePattern = try NSRegularExpression(pattern: "(?i)Page\\s*Page\\s*(?:•\\s*)?\\d+")
        // Word may expose a static label in the body-extraction stream as
        // "Page I" before the footer's dynamic field. Match the final
        // separator plus digits as well as older "Page 123" output.
        let pageNumberPattern = try NSRegularExpression(pattern: "(?i)(?:Page\\s*(?:•\\s*)?|•\\s*)(\\d+)")
        let duplicatedPageLabelPages = (0..<pdf.pageCount).filter { pageIndex in
            guard let pageText = pdf.page(at: pageIndex)?.string else { return false }
            return duplicatePagePattern.firstMatch(in: pageText, range: NSRange(location: 0, length: (pageText as NSString).length)) != nil
        }.map { $0 + 1 }
        var extractedDuplicatePageNumbers: [Int?] = []
        var incorrectPageNumberPages: [Int] = []
        for pageIndex in 0..<pdf.pageCount {
            guard let pageText = pdf.page(at: pageIndex)?.string else {
                extractedDuplicatePageNumbers.append(nil)
                incorrectPageNumberPages.append(pageIndex + 1)
                continue
            }
            let range = NSRange(location: 0, length: (pageText as NSString).length)
            guard let match = pageNumberPattern.matches(in: pageText, range: range).last,
                  let numberRange = Range(match.range(at: 1), in: pageText),
                  let number = Int(pageText[numberRange]) else {
                extractedDuplicatePageNumbers.append(nil)
                incorrectPageNumberPages.append(pageIndex + 1)
                continue
            }
            extractedDuplicatePageNumbers.append(number)
            if number != pageIndex + 1 { incorrectPageNumberPages.append(pageIndex + 1) }
        }
        XCTAssertEqual(incorrectPageNumberPages, [], "Decimal page-number values must match physical page sequence 1...356")
        var pdfSelectionVerticalOutsidePages: [Int] = []
        var footerVerticalBounds: [[Double]] = []
        var rasterizedPageEdgeInkPages: [Int] = []
        var representativeFooterBottomEdgeInkPages: [Int] = []
        for pageIndex in 0..<pdf.pageCount {
            guard let page = pdf.page(at: pageIndex),
                  let pageRef = page.pageRef else {
                pdfSelectionVerticalOutsidePages.append(pageIndex + 1)
                continue
            }
            let pageText = page.string ?? ""
            let textRange = NSRange(location: 0, length: (pageText as NSString).length)
            guard let match = pageNumberPattern.matches(in: pageText, range: textRange).last,
                  let selection = page.selection(for: match.range) else {
                pdfSelectionVerticalOutsidePages.append(pageIndex + 1)
                continue
            }
            let mediaBox = page.bounds(for: .mediaBox)
            let selectionBounds = selection.bounds(for: page)
            footerVerticalBounds.append([Double(selectionBounds.minY), Double(selectionBounds.maxY)])
            // Diagnostic only: PDFKit selection geometry can map through
            // unrelated Unicode text (notably on pages 178, 230, 245 and 330).
            if selectionBounds.minY < mediaBox.minY || selectionBounds.maxY > mediaBox.maxY {
                pdfSelectionVerticalOutsidePages.append(pageIndex + 1)
            }
            let scale = 2
            let width = Int(mediaBox.width) * scale
            let height = Int(mediaBox.height) * scale
            let bytesPerRow = width * 4
            var pixels = [UInt8](repeating: 255, count: bytesPerRow * height)
            let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
                guard let context = CGContext(
                    data: buffer.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return false }
                context.setFillColor(NSColor.white.cgColor)
                context.fill(CGRect(x: 0, y: 0, width: width, height: height))
                context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
                context.drawPDFPage(pageRef)
                return true
            }
            guard rendered else {
                rasterizedPageEdgeInkPages.append(pageIndex + 1)
                continue
            }
            // Record page-edge ink as a diagnostic. This source DOCX sets
            // zero bottom margin, so some body lines can reach the trim edge;
            // that is independent of the footer's measured placement.
            let edgeRows = [0, height - 1]
            let edgeHasInk = edgeRows.contains { row in
                let range = (row * bytesPerRow)..<((row + 1) * bytesPerRow)
                return pixels[range].enumerated().contains { offset, component in
                    offset % 4 != 3 && component < 245
                }
            }
            if edgeHasInk {
                rasterizedPageEdgeInkPages.append(pageIndex + 1)
            }
            if [0, 177, 355].contains(pageIndex) {
                let physicalBottomRow = height - 1
                let range = (physicalBottomRow * bytesPerRow)..<((physicalBottomRow + 1) * bytesPerRow)
                if pixels[range].enumerated().contains(where: { offset, component in
                    offset % 4 != 3 && component < 245
                }) {
                    representativeFooterBottomEdgeInkPages.append(pageIndex + 1)
                }
            }
        }
        XCTAssertEqual(representativeFooterBottomEdgeInkPages, [], "BLW-QA-005: footer ink must be visibly clear of the physical bottom edge on pages 1, 178, and 356")
        var pdfPageBoxes: [[Double]] = []
        for pageIndex in 0..<pdf.pageCount {
            let page = try XCTUnwrap(pdf.page(at: pageIndex))
            let box = page.bounds(for: .mediaBox)
            XCTAssertEqual(box.width, 396, accuracy: 0.01, "BLW-QA-002 PDF trim width differs on physical page \(pageIndex + 1)")
            XCTAssertEqual(box.height, 612, accuracy: 0.01, "BLW-QA-002 PDF trim height differs on physical page \(pageIndex + 1)")
            pdfPageBoxes.append([Double(box.width), Double(box.height)])
        }
        let sourcePartsForFurniture = try DOCXPackage.entries(in: sourceData)
        let sourceFooterParts = sourcePartsForFurniture.filter { $0.path.hasPrefix("word/footer") && $0.path.hasSuffix(".xml") }
        let sourceFooterHasStaticPageLabel = sourceFooterParts.contains { String(decoding: $0.data, as: UTF8.self).contains("Page ") }
        let sourceFooterHasPageField = sourceFooterParts.contains { String(decoding: $0.data, as: UTF8.self).uppercased().contains("PAGE") }
        XCTAssertTrue(sourceFooterHasStaticPageLabel, "The BLW-QA-002 source must retain its static footer label")
        XCTAssertTrue(sourceFooterHasPageField, "The BLW-QA-002 source must retain its dynamic PAGE field")
        let middlePageText = pdf.page(at: pdf.pageCount / 2)?.string ?? ""
        let report: [String: Any] = [
            "sourceCopy": inputURL.path,
            "sourceSHA256": Self.sha256(sourceData),
            "sourceBytes": sourceData.count,
            "nativeOutput": nativeURL.path,
            "nativePackageSHA256": try Self.packageSHA256(nativeURL),
            "exportedDOCX": outputURL.path,
            "exportedDOCXSHA256": Self.sha256(exportedData),
            "exportedDOCXBytes": exportedData.count,
            "productionPDF": pdfURL.path,
            "productionPDFSHA256": Self.sha256(pdfData),
            "productionPDFBytes": pdfData.count,
            "productionPDFPageCount": pdf.pageCount,
            "productionPDFTextPages": pdfTextPages,
            "duplicatedPageLabelPages": duplicatedPageLabelPages,
            "extractedPageNumberValues": extractedDuplicatePageNumbers,
            "incorrectPageNumberPages": incorrectPageNumberPages,
            "pdfSelectionVerticalOutsidePagesDiagnostic": pdfSelectionVerticalOutsidePages,
            "pdfSelectionVerticalBoundsDiagnostic": footerVerticalBounds,
            "rasterizedPageEdgeInkDiagnosticPages": rasterizedPageEdgeInkPages,
            "representativeFooterBottomEdgeInkPages": representativeFooterBottomEdgeInkPages,
            "productionPDFPageMediaBoxes": pdfPageBoxes,
            "sourceFooterPartNames": sourceFooterParts.map(\.path),
            "sourceFooterHasStaticPageLabel": sourceFooterHasStaticPageLabel,
            "sourceFooterHasDynamicPAGEField": sourceFooterHasPageField,
            "sourcePageNumberStart": reopened.metadata.page.pageNumberStart ?? 1,
            "sourcePageNumberFormat": reopened.metadata.page.pageNumberFormat ?? "decimal",
            "sourceFooterTextPresentAfterNativeReopen": reopened.metadata.page.footerText.contains("Page"),
            "sourceDynamicPageNumbersPresentAfterNativeReopen": reopened.metadata.page.showsPageNumbers,
            "sourceSectionCount": reopened.metadata.sections?.count ?? 0,
            "middlePageContainsDuplicateLabel": duplicatePagePattern.firstMatch(in: middlePageText, range: NSRange(location: 0, length: (middlePageText as NSString).length)) != nil,
            "duplicatedPageLabelCount": duplicatedPageLabelPages.count,
            "productionPDFFirstMediaBoxPoints": [firstMediaBox.width, firstMediaBox.height],
            "productionPDFLastMediaBoxPoints": [lastMediaBox.width, lastMediaBox.height],
            "importedTextSHA256": importedTextHash,
            "editedTextSHA256": editedTextHash,
            "nativeReopenedTextSHA256": Self.sha256(Data(reopened.text.string.utf8)),
            "reimportedTextSHA256": Self.sha256(Data(reimportedText.utf8)),
            "textCharacterCount": imported.text.length,
            "editedTextCharacterCount": edited.length,
            "textUTF16Length": imported.text.string.utf16.count,
            "wordCount": DocumentAnalysis.statistics(for: importedText).words,
            "paragraphCount": importedText.components(separatedBy: .newlines).filter { !$0.isEmpty }.count,
            "editedAtStartMiddleAndEnd": true,
            "qaEditMarkersRemovedRestoreSourceText": editsRestoreSourceText,
            "attributeSummary": importedAttributes,
            "sourceMediaSHA256": sourceMediaHashes,
            "reimportedAttachmentSHA256": reimportedAttachmentHashes,
            "exportedMediaSHA256": outputMediaHashes,
            "nativeEditedTextExact": reopened.text.string == editedText,
            "docxEditedTextExact": reimportedText == editedText,
            "nativeAttachmentsExact": Self.attachmentHashes(in: reopened.text) == importedAttachmentHashes,
            "docxAttachmentsExact": reimportedAttachmentHashes == importedAttachmentHashes,
            "importWarning": imported.lastErrorMessage ?? "",
            "reimportWarning": reimported.lastErrorMessage ?? "",
            "sourceContentIncludedInReport": false
        ]
        try FileManager.default.createDirectory(at: reportURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: reportURL, options: .atomic)
        print("BOLD_QA_REAL_MANUSCRIPT_REPORT=\(reportURL.path)")
        XCTAssertTrue(duplicatedPageLabelPages.isEmpty, "BLW-QA-002: PDF repeats the static Page label with its dynamic PAGE field on physical pages: \(duplicatedPageLabelPages)")
    }

    private static func attachmentHashes(in text: NSAttributedString) -> [String] {
        var hashes: [String] = []
        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, _, _ in
            guard let attachment = value as? NSTextAttachment,
                  let data = attachment.fileWrapper?.regularFileContents else { return }
            hashes.append(sha256(data))
        }
        return hashes.sorted()
    }

    private static func attributeSummary(in text: NSAttributedString) -> [String: Int] {
        var fonts = Set<String>()
        var sizes = Set<String>()
        var bold = 0
        var italic = 0
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, _, _ in
            if let font = attributes[.font] as? NSFont {
                fonts.insert(font.fontName)
                sizes.insert(String(format: "%.1f", font.pointSize))
                if font.fontDescriptor.symbolicTraits.contains(.bold) { bold += 1 }
                if font.fontDescriptor.symbolicTraits.contains(.italic) { italic += 1 }
            }
        }
        return ["uniqueFonts": fonts.count, "uniqueFontSizes": sizes.count, "boldRuns": bold, "italicRuns": italic]
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func packageSHA256(_ url: URL) throws -> String {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { throw WriterError.message("Could not enumerate native package for QA hashing") }
        var entries: [(String, String)] = []
        for case let itemURL as URL in enumerator {
            guard try itemURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            let relative = String(itemURL.path.dropFirst(url.path.count + 1))
            entries.append((relative, sha256(try Data(contentsOf: itemURL))))
        }
        let canonical = entries.sorted { $0.0 < $1.0 }.map { "\($0.0)\t\($0.1)\n" }.joined()
        return sha256(Data(canonical.utf8))
    }
}
