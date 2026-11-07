import XCTest
@testable import BOLDWriter

final class BookProofNavigationTests: XCTestCase {
    func testStalePDFKitNotificationCannotCancelProgrammaticJump() {
        var state = ProofPageNavigationState(requestedPage: 391)

        XCTAssertFalse(state.shouldPublishVisiblePage(4))
        XCTAssertEqual(state.requestedPage, 391)

        XCTAssertTrue(state.shouldPublishVisiblePage(391))
        XCTAssertNil(state.requestedPage)
        XCTAssertTrue(state.shouldPublishVisiblePage(196))
    }

    func testOrdinaryVisiblePageChangesArePublishedWhenNoJumpIsPending() {
        var state = ProofPageNavigationState()

        XCTAssertTrue(state.shouldPublishVisiblePage(1))
        XCTAssertTrue(state.shouldPublishVisiblePage(196))
    }
}
