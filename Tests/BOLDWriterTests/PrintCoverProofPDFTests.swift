import Foundation
import PDFKit
import XCTest

@testable import BOLDWriter

final class PrintCoverProofPDFTests: XCTestCase {
    private func geometry(
        pages: Int = 300
    ) throws -> BOLDPrintCoverGeometry.Result {
        try BOLDPrintCoverGeometry.calculate(
            pageCount: pages,
            trimWidthInches: 6,
            trimHeightInches: 9,
            sheetCaliperMils: 4,
            bleedInches: 0.125
        )
    }

    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "bold-pdf-proof-tests-\(UUID().uuidString)"
            )

        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )

        return url
    }

    func testProducesOneValidPDFPage() throws {
        let temp = try folder()

        defer {
            try? FileManager.default.removeItem(
                at: temp
            )
        }

        let file = temp.appendingPathComponent(
            "Cover Proof.pdf"
        )

        try BOLDPrintCoverProofPDF.create(
            geometry: geometry(),
            at: file
        )

        let document = try XCTUnwrap(
            PDFDocument(url: file)
        )

        XCTAssertEqual(
            document.pageCount,
            1
        )

        XCTAssertGreaterThan(
            try Data(contentsOf: file).count,
            500
        )
    }

    func testPhysicalMediaBoxMatchesGeometry() throws {
        let temp = try folder()

        defer {
            try? FileManager.default.removeItem(
                at: temp
            )
        }

        let file = temp.appendingPathComponent(
            "6x9.pdf"
        )

        try BOLDPrintCoverProofPDF.create(
            geometry: geometry(),
            at: file
        )

        let doc = try XCTUnwrap(
            PDFDocument(url: file)
        )

        let page = try XCTUnwrap(
            doc.page(at: 0)
        )

        XCTAssertEqual(
            Double(
                page.bounds(
                    for: .mediaBox
                ).width
            ),
            925.2,
            accuracy: 0.5
        )

        XCTAssertEqual(
            Double(
                page.bounds(
                    for: .mediaBox
                ).height
            ),
            666,
            accuracy: 0.5
        )
    }

    func testOddPageSpineChangesPhysicalWidth() throws {
        let temp = try folder()

        defer {
            try? FileManager.default.removeItem(
                at: temp
            )
        }

        let even = temp.appendingPathComponent(
            "even.pdf"
        )

        let odd = temp.appendingPathComponent(
            "odd.pdf"
        )

        try BOLDPrintCoverProofPDF.create(
            geometry: geometry(),
            at: even
        )

        try BOLDPrintCoverProofPDF.create(
            geometry: geometry(pages: 301),
            at: odd
        )

        let first = try XCTUnwrap(
            PDFDocument(url: even)?.page(at: 0)
        )

        let second = try XCTUnwrap(
            PDFDocument(url: odd)?.page(at: 0)
        )

        XCTAssertEqual(
            Double(
                second.bounds(
                    for: .mediaBox
                ).width
                - first.bounds(
                    for: .mediaBox
                ).width
            ),
            0.288,
            accuracy: 0.05
        )
    }

    func testRefusesToOverwriteExistingPDF() throws {
        let temp = try folder()

        defer {
            try? FileManager.default.removeItem(
                at: temp
            )
        }

        let file = temp.appendingPathComponent(
            "existing.pdf"
        )

        let sentinel = Data(
            "IMPORTANT EXISTING ARTWORK".utf8
        )

        try sentinel.write(
            to: file
        )

        XCTAssertThrowsError(
            try BOLDPrintCoverProofPDF.create(
                geometry: geometry(),
                at: file
            )
        )

        XCTAssertEqual(
            try Data(contentsOf: file),
            sentinel
        )
    }

    func testNegativeSafeInsetRejectedAndFileNotCreated() throws {
        let temp = try folder()

        defer {
            try? FileManager.default.removeItem(
                at: temp
            )
        }

        let file = temp.appendingPathComponent(
            "invalid.pdf"
        )

        XCTAssertThrowsError(
            try BOLDPrintCoverProofPDF.create(
                geometry: geometry(),
                safeInsetInches: -1,
                at: file
            )
        )

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: file.path
            )
        )
    }

    func testNonfiniteInsetRejected() throws {
        let temp = try folder()

        defer {
            try? FileManager.default.removeItem(
                at: temp
            )
        }

        for (index, inset) in [
            Double.nan,
            Double.infinity
        ].enumerated() {
            let file = temp.appendingPathComponent(
                "bad-\(index).pdf"
            )

            XCTAssertThrowsError(
                try BOLDPrintCoverProofPDF.create(
                    geometry: geometry(),
                    safeInsetInches: inset,
                    at: file
                )
            )
        }
    }

    func testMissingDestinationDirectoryDoesNotCreateIt() throws {
        let temp = try folder()

        defer {
            try? FileManager.default.removeItem(
                at: temp
            )
        }

        let missing = temp.appendingPathComponent(
            "missing"
        )

        let file = missing.appendingPathComponent(
            "proof.pdf"
        )

        XCTAssertThrowsError(
            try BOLDPrintCoverProofPDF.create(
                geometry: geometry(),
                at: file
            )
        )

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: missing.path
            )
        )
    }

    func testUnicodeDestinationAndSpineAllowance() throws {
        let temp = try folder()

        defer {
            try? FileManager.default.removeItem(
                at: temp
            )
        }

        let file = temp.appendingPathComponent(
            "Couverture résumé 日本語.pdf"
        )

        let baseline = try BOLDPrintCoverGeometry.calculate(
            pageCount: 300,
            trimWidthInches: 6,
            trimHeightInches: 9,
            sheetCaliperMils: 4,
            bleedInches: 0.125,
            spineAllowanceInches: 0.02
        )

        try BOLDPrintCoverProofPDF.create(
            geometry: baseline,
            at: file
        )

        let page = try XCTUnwrap(
            PDFDocument(url: file)?.page(at: 0)
        )

        XCTAssertEqual(
            Double(
                page.bounds(
                    for: .mediaBox
                ).width
            ),
            926.64,
            accuracy: 0.5
        )
    }
}
