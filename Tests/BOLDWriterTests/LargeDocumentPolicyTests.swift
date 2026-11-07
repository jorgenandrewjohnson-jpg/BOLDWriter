import XCTest
@testable import BOLDWriter

final class LargeDocumentPolicyTests:
    XCTestCase
{
    func testOrdinaryDocumentKeepsNormalOpeningBehavior() {
        let length =
            LargeDocumentPolicy
                .automaticPaginationCharacterLimit
                - 1

        XCTAssertFalse(
            LargeDocumentPolicy
                .isLarge(
                    textLength:
                        length
                )
        )

        XCTAssertTrue(
            LargeDocumentPolicy
                .initialPrintLayout(
                    textLength:
                        length
                )
        )

        XCTAssertTrue(
            LargeDocumentPolicy
                .initialNavigationVisible(
                    textLength:
                        length
                )
        )

        XCTAssertTrue(
            LargeDocumentPolicy
                .allowsLiveProofing(
                    textLength:
                        length
                )
        )
    }

    func testBookScaleDocumentUsesSafeOpeningMode() {
        let length =
            LargeDocumentPolicy
                .automaticPaginationCharacterLimit

        XCTAssertTrue(
            LargeDocumentPolicy
                .isLarge(
                    textLength:
                        length
                )
        )

        XCTAssertFalse(
            LargeDocumentPolicy
                .initialPrintLayout(
                    textLength:
                        length
                )
        )

        XCTAssertFalse(
            LargeDocumentPolicy
                .initialNavigationVisible(
                    textLength:
                        length
                )
        )

        XCTAssertFalse(
            LargeDocumentPolicy
                .allowsLiveProofing(
                    textLength:
                        length
                )
        )
    }

    func testLargeDocumentDefersOutlineWhileNavigationIsHidden() {
        let length =
            LargeDocumentPolicy
                .automaticPaginationCharacterLimit
                + 2_000_000

        XCTAssertFalse(
            LargeDocumentPolicy
                .shouldBuildOutlineAutomatically(
                    textLength:
                        length,
                    navigationVisible:
                        false
                )
        )
    }

    func testLargeDocumentCanBuildOutlineWhenNavigationIsRequested() {
        let length =
            LargeDocumentPolicy
                .automaticPaginationCharacterLimit
                + 2_000_000

        XCTAssertTrue(
            LargeDocumentPolicy
                .shouldBuildOutlineAutomatically(
                    textLength:
                        length,
                    navigationVisible:
                        true
                )
        )
    }
}
