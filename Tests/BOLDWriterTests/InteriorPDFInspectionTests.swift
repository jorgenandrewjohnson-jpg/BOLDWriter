import CoreGraphics
import Foundation
import PDFKit
import XCTest

@testable import BOLDWriter

final class InteriorPDFInspectionTests: XCTestCase {
    private struct Spec {
        let width: CGFloat
        let height: CGFloat
        let trim: CGRect?

        init(
            _ width: CGFloat = 432,
            _ height: CGFloat = 648,
            trim: CGRect? = nil
        ) {
            self.width = width
            self.height = height
            self.trim = trim
        }
    }

    private func tempDirectory() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "bold-interior-inspection-\(UUID().uuidString)"
            )

        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )

        return folder
    }

    private func makePDF(
        _ pages: [Spec],
        at url: URL
    ) throws {
        var firstMedia = CGRect(
            x: 0,
            y: 0,
            width: pages[0].width,
            height: pages[0].height
        )

        let context = try XCTUnwrap(
            CGContext(
                url as CFURL,
                mediaBox: &firstMedia,
                nil
            )
        )

        for spec in pages {
            var pageMedia = CGRect(
                x: 0,
                y: 0,
                width: spec.width,
                height: spec.height
            )

            var boxes: [String: NSData] = [
                kCGPDFContextMediaBox as String: NSData(
                    bytes: &pageMedia,
                    length: MemoryLayout<CGRect>.size
                )
            ]

            if var trim = spec.trim {
                boxes[kCGPDFContextTrimBox as String] = NSData(
                    bytes: &trim,
                    length: MemoryLayout<CGRect>.size
                )
            }

            context.beginPDFPage(
                boxes as CFDictionary
            )

            context.endPDFPage()
        }

        context.closePDF()
    }

    func testTwoPageInteriorReportsTrimAndPageCount() throws {
        let folder = try tempDirectory()

        defer {
            try? FileManager.default.removeItem(at: folder)
        }

        let url = folder.appendingPathComponent(
            "Manuscript.pdf"
        )

        try makePDF(
            [Spec(), Spec()],
            at: url
        )

        let result = try BOLDInteriorPDFInspection.inspect(
            url: url
        )

        XCTAssertEqual(
            result.pageCount,
            2
        )

        XCTAssertEqual(
            result.trimWidthInches,
            6,
            accuracy: 0.0001
        )

        XCTAssertEqual(
            result.trimHeightInches,
            9,
            accuracy: 0.0001
        )
    }

    func testExplicitTrimBoxOverridesBleedMediaSize() throws {
        let folder = try tempDirectory()

        defer {
            try? FileManager.default.removeItem(at: folder)
        }

        let url = folder.appendingPathComponent(
            "Bleed.pdf"
        )

        let sheet = Spec(
            450,
            666,
            trim: CGRect(
                x: 9,
                y: 9,
                width: 432,
                height: 648
            )
        )

        try makePDF(
            [sheet],
            at: url
        )

        let result = try BOLDInteriorPDFInspection.inspect(
            url: url
        )

        XCTAssertEqual(
            result.trimWidthInches,
            6,
            accuracy: 0.0001
        )

        XCTAssertEqual(
            result.trimHeightInches,
            9,
            accuracy: 0.0001
        )
    }

    func testMixedTrimSizesAreRejected() throws {
        let folder = try tempDirectory()

        defer {
            try? FileManager.default.removeItem(at: folder)
        }

        let url = folder.appendingPathComponent(
            "Mixed.pdf"
        )

        try makePDF(
            [
                Spec(),
                Spec(360, 576)
            ],
            at: url
        )

        XCTAssertThrowsError(
            try BOLDInteriorPDFInspection.inspect(
                url: url
            )
        )
    }

    func testOutsideTrimBoxIsRejected() throws {
        let folder = try tempDirectory()

        defer {
            try? FileManager.default.removeItem(at: folder)
        }

        let url = folder.appendingPathComponent(
            "Raw Invalid Trim.pdf"
        )

        // A handcrafted PDF preserves an out-of-media TrimBox.
        // CGContext may otherwise normalize invalid rectangles.
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 432 648] /TrimBox [-9 0 423 648] /Contents 4 0 R >>",
            "<< /Length 0 >>\nstream\n\nendstream"
        ]

        var contents = Data("%PDF-1.4\n".utf8)
        var offsets = [0]

        for (index, object) in objects.enumerated() {
            offsets.append(contents.count)

            contents.append(
                Data(
                    "\(index + 1) 0 obj\n\(object)\nendobj\n".utf8
                )
            )
        }

        let xrefPosition = contents.count

        contents.append(
            Data(
                "xref\n0 \(offsets.count)\n0000000000 65535 f \n".utf8
            )
        )

        for offset in offsets.dropFirst() {
            contents.append(
                Data(
                    String(
                        format: "%010d 00000 n \n",
                        offset
                    ).utf8
                )
            )
        }

        contents.append(
            Data(
                "trailer\n<< /Root 1 0 R /Size \(offsets.count) >>\nstartxref\n\(xrefPosition)\n%%EOF\n".utf8
            )
        )

        try contents.write(to: url)

        let pdf = try XCTUnwrap(
            PDFDocument(url: url)
        )

        XCTAssertEqual(pdf.pageCount, 1)

        let raw = try XCTUnwrap(
            CGPDFDocument(url as CFURL)
        )

        let rawPage = try XCTUnwrap(
            raw.page(at: 1)
        )

        let dictionary = try XCTUnwrap(
            rawPage.dictionary
        )

        var trimArray: CGPDFArrayRef?

        XCTAssertTrue(
            CGPDFDictionaryGetArray(
                dictionary,
                "TrimBox",
                &trimArray
            )
        )

        XCTAssertThrowsError(
            try BOLDInteriorPDFInspection.inspect(url: url)
        )
    }

    func testMissingAndNonPDFFilesAreRejected() throws {
        let folder = try tempDirectory()

        defer {
            try? FileManager.default.removeItem(at: folder)
        }

        XCTAssertThrowsError(
            try BOLDInteriorPDFInspection.inspect(
                url: folder.appendingPathComponent(
                    "missing.pdf"
                )
            )
        )

        let wrong = folder.appendingPathComponent(
            "Interior.txt"
        )

        try Data(
            "not a PDF".utf8
        ).write(to: wrong)

        XCTAssertThrowsError(
            try BOLDInteriorPDFInspection.inspect(
                url: wrong
            )
        )
    }

    func testMalformedPDFRejected() throws {
        let folder = try tempDirectory()

        defer {
            try? FileManager.default.removeItem(at: folder)
        }

        let url = folder.appendingPathComponent(
            "Broken.pdf"
        )

        try Data(
            "bad PDF content".utf8
        ).write(to: url)

        XCTAssertThrowsError(
            try BOLDInteriorPDFInspection.inspect(
                url: url
            )
        )
    }

    func testPopulatingInputsUsesActualPDFPageCountAndTrim() throws {
        let folder = try tempDirectory()

        defer {
            try? FileManager.default.removeItem(at: folder)
        }

        let url = folder.appendingPathComponent(
            "Interior.pdf"
        )

        try makePDF(
            [
                Spec(),
                Spec(),
                Spec()
            ],
            at: url
        )

        let inspection = try BOLDInteriorPDFInspection.inspect(
            url: url
        )

        var inputs = BOLDPrintCoverProofInputs()

        inputs.caliperMils = "4.5"
        inputs.bleedInches = "0.125"

        inputs.apply(inspection)

        XCTAssertEqual(
            inputs.pageCount,
            "3"
        )

        XCTAssertEqual(
            inputs.trimWidth,
            "6.0000"
        )

        XCTAssertEqual(
            inputs.trimHeight,
            "9.0000"
        )

        XCTAssertEqual(
            inputs.caliperMils,
            "4.5"
        )

        XCTAssertEqual(
            inputs.bleedInches,
            "0.125"
        )

        let verified = try inputs.validate()

        XCTAssertEqual(
            verified.geometry.sheetCount,
            2
        )
    }

    func testInspectionDoesNotModifySelectedPDF() throws {
        let folder = try tempDirectory()

        defer {
            try? FileManager.default.removeItem(at: folder)
        }

        let url = folder.appendingPathComponent(
            "Immutable.pdf"
        )

        try makePDF(
            [
                Spec(),
                Spec()
            ],
            at: url
        )

        let before = try Data(
            contentsOf: url
        )

        _ = try BOLDInteriorPDFInspection.inspect(
            url: url
        )

        XCTAssertEqual(
            try Data(contentsOf: url),
            before
        )
    }
}
