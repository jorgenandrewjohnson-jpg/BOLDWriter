import XCTest
@testable import BOLDWriter

final class LargeDocumentLiveSafetyTests:
    XCTestCase
{
    func testLargeDocumentOverridesRequestedPrintLayout() {
        XCTAssertFalse(
            LargeDocumentPolicy
                .effectivePrintLayout(
                    requested:
                        true,
                    textLength:
                        LargeDocumentPolicy
                            .automaticPaginationCharacterLimit
                )
        )
    }

    func testLargeDocumentDisablesViewportHitTesting() {
        XCTAssertFalse(
            LargeDocumentPolicy
                .shouldUseViewportHitTesting(
                    textLength:
                        LargeDocumentPolicy
                            .automaticPaginationCharacterLimit
                )
        )
    }

    func testNormalDocumentRetainsRequestedPrintLayout() {
        XCTAssertTrue(
            LargeDocumentPolicy
                .effectivePrintLayout(
                    requested:
                        true,
                    textLength:
                        50_000
                )
        )

        XCTAssertFalse(
            LargeDocumentPolicy
                .effectivePrintLayout(
                    requested:
                        false,
                    textLength:
                        50_000
                )
        )
    }

    func testNormalDocumentMayUseViewportHitTesting() {
        XCTAssertTrue(
            LargeDocumentPolicy
                .shouldUseViewportHitTesting(
                    textLength:
                        50_000
                )
        )
    }
}
