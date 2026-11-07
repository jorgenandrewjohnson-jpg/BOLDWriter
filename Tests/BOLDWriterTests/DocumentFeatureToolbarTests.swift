import XCTest
@testable import BOLDWriter

final class DocumentFeatureToolbarTests: XCTestCase {
    func testEvidenceReadAloudAndAudiobookEntryPointsRemainIndependent() {
        XCTAssertEqual(DocumentFeatureEntryPoint.allCases, [.evidenceReview, .evidence, .readAloud, .audiobookStudio])
        XCTAssertEqual(DocumentFeatureEntryPoint.allCases.map(\.title), ["Evidence Review", "Evidence", "Read Aloud", "Audiobook Studio"])
        XCTAssertEqual(Set(DocumentFeatureEntryPoint.allCases.map(\.accessibilityIdentifier)).count, 4)
        XCTAssertEqual(
            DocumentFeatureEntryPoint.allCases.map(\.accessibilityIdentifier),
            [
                "document.feature.evidenceReview",
                "document.feature.evidence",
                "document.feature.readAloud",
                "document.feature.audiobookStudio"
            ]
        )
    }

    func testEachFeatureControlRoutesOnlyToItsOwnPresentationAction() {
        var calls: [DocumentFeatureEntryPoint: Int] = [:]
        let actions = DocumentFeatureActions(
            evidenceReview: { calls[.evidenceReview, default: 0] += 1 },
            evidence: { calls[.evidence, default: 0] += 1 },
            readAloud: { calls[.readAloud, default: 0] += 1 },
            audiobookStudio: { calls[.audiobookStudio, default: 0] += 1 }
        )

        for entry in DocumentFeatureEntryPoint.allCases {
            let before = calls
            actions.open(entry)
            for candidate in DocumentFeatureEntryPoint.allCases {
                let expected = before[candidate, default: 0] + (candidate == entry ? 1 : 0)
                XCTAssertEqual(calls[candidate, default: 0], expected, "Opening \(entry.title) should only route to its own action")
            }
        }
    }
}
