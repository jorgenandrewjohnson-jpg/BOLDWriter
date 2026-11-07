import Foundation
import PDFKit
import XCTest
@testable import BOLDWriter

final class PrintCoverPDFBoxesTests: XCTestCase {
    private func configuration(pages: Int = 300, bleed: Double = 0.125)
        throws -> BOLDPrintCoverGeometry.Result {
        try BOLDPrintCoverGeometry.calculate(
            pageCount: pages,
            trimWidthInches: 6,
            trimHeightInches: 9,
            sheetCaliperMils: 4,
            bleedInches: bleed
        )
    }

    private func withProof(
        pages: Int = 300,
        bleed: Double = 0.125,
        _ check: (PDFPage, BOLDPrintCoverGeometry.Result) throws -> Void
    ) throws {
        let config = try configuration(pages: pages, bleed: bleed)
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("bold-print-boxes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder,
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let output = folder.appendingPathComponent("Wrap Guide.pdf")
        try BOLDPrintCoverProofPDF.create(geometry: config, at: output)
        let document = try XCTUnwrap(PDFDocument(url: output))
        XCTAssertEqual(document.pageCount, 1)
        try check(XCTUnwrap(document.page(at: 0)), config)
    }

    func testTrimBoxIsInsideMediaByRequestedBleed() throws {
        try withProof { page, geometry in
            let trim = page.bounds(for: .trimBox)
            let media = page.bounds(for: .mediaBox)
            XCTAssertEqual(Double(trim.minX), 9, accuracy: 0.05)
            XCTAssertEqual(Double(trim.minY), 9, accuracy: 0.05)
            XCTAssertEqual(Double(trim.width),
                           geometry.totalCoverWidthInches * 72 - 18,
                           accuracy: 0.05)
            XCTAssertEqual(Double(trim.height), 648, accuracy: 0.05)
            XCTAssertEqual(Double(media.width), 925.2, accuracy: 0.05)
        }
    }

    func testBleedBoxIsFullSheet() throws {
        try withProof { page, _ in
            let bleed = page.bounds(for: .bleedBox)
            let media = page.bounds(for: .mediaBox)
            XCTAssertEqual(bleed.minX, media.minX, accuracy: 0.05)
            XCTAssertEqual(bleed.minY, media.minY, accuracy: 0.05)
            XCTAssertEqual(bleed.width, media.width, accuracy: 0.05)
            XCTAssertEqual(bleed.height, media.height, accuracy: 0.05)
        }
    }

    func testZeroBleedMakesTrimEqualMedia() throws {
        try withProof(bleed: 0) { page, _ in
            let trim = page.bounds(for: .trimBox)
            let media = page.bounds(for: .mediaBox)
            XCTAssertEqual(trim.width, media.width, accuracy: 0.05)
            XCTAssertEqual(trim.height, media.height, accuracy: 0.05)
            XCTAssertEqual(trim.minX, media.minX, accuracy: 0.05)
            XCTAssertEqual(trim.minY, media.minY, accuracy: 0.05)
        }
    }

    func testOddPageCountChangesTrimWidthNotBleedOffset() throws {
        try withProof(pages: 301) { page, geometry in
            let trim = page.bounds(for: .trimBox)
            XCTAssertEqual(Double(trim.minX), 9, accuracy: 0.05)
            XCTAssertEqual(Double(trim.width),
                           2 * geometry.trimWidthInches * 72
                             + geometry.spineWidthInches * 72,
                           accuracy: 0.05)
            XCTAssertEqual(geometry.sheetCount, 151)
        }
    }

    func testCropBoxDoesNotClipBleedGuide() throws {
        try withProof { page, _ in
            let crop = page.bounds(for: .cropBox)
            let media = page.bounds(for: .mediaBox)
            XCTAssertEqual(crop.width, media.width, accuracy: 0.05)
            XCTAssertEqual(crop.height, media.height, accuracy: 0.05)
        }
    }
}
