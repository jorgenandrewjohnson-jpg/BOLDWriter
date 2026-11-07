import XCTest
@testable import BOLDWriter

final class PrintCoverProofInputsTests: XCTestCase {
    private func valid() -> BOLDPrintCoverProofInputs {
        var fields = BOLDPrintCoverProofInputs()
        fields.pageCount = "300"
        return fields
    }

    func testDefaultRequiresActualPageCount() {
        XCTAssertThrowsError(
            try BOLDPrintCoverProofInputs().validate()
        )
    }

    func testValidGeometrySharesProductionModel() throws {
        let result = try valid().validate()

        XCTAssertEqual(
            result.geometry.sheetCount,
            150
        )

        XCTAssertEqual(
            result.geometry.spineWidthInches,
            0.6,
            accuracy: 0.000001
        )

        XCTAssertEqual(
            result.geometry.totalCoverWidthInches,
            12.85,
            accuracy: 0.000001
        )

        XCTAssertEqual(
            result.safeInsetInches,
            0.25
        )
    }

    func testOddPageCountRoundsUp() throws {
        var fields = valid()
        fields.pageCount = "301"

        XCTAssertEqual(
            try fields.validate().geometry.sheetCount,
            151
        )
    }

    func testWhitespaceInPageCountIsAllowed() throws {
        var fields = valid()
        fields.pageCount = "  302  "

        XCTAssertEqual(
            try fields.validate().geometry.pageCount,
            302
        )
    }

    func testNaNAndInfinityNeverAccepted() {
        for invalid in [
            "nan",
            "inf",
            "-inf",
            "not-a-number"
        ] {
            var fields = valid()
            fields.caliperMils = invalid

            XCTAssertThrowsError(
                try fields.validate()
            )
        }
    }

    func testInvalidPageCountRejected() {
        for invalid in [
            "0",
            "-2",
            "1.5",
            "1000001"
        ] {
            var fields = valid()
            fields.pageCount = invalid

            XCTAssertThrowsError(
                try fields.validate()
            )
        }
    }

    func testInvalidTrimAndBleedRejected() {
        var fields = valid()
        fields.trimWidth = "0"

        XCTAssertThrowsError(
            try fields.validate()
        )

        fields = valid()
        fields.bleedInches = "-0.1"

        XCTAssertThrowsError(
            try fields.validate()
        )
    }

    func testOversizedSafeInsetRejected() {
        var fields = valid()
        fields.safeInsetInches = "3"

        XCTAssertThrowsError(
            try fields.validate()
        )
    }

    func testPrinterAllowanceChangesWidth() throws {
        var fields = valid()
        fields.spineAllowanceInches = "0.02"

        let result = try fields.validate()

        XCTAssertEqual(
            result.geometry.totalCoverWidthInches,
            12.87,
            accuracy: 0.000001
        )
    }

    func testSafeInsetCannotBeNonfiniteOrNegative() {
        for invalid in [
            "nan",
            "inf",
            "-0.1"
        ] {
            var fields = valid()
            fields.safeInsetInches = invalid

            XCTAssertThrowsError(
                try fields.validate()
            )
        }
    }
}
