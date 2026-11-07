import XCTest
import AppKit
import SceneKit
@testable import BOLDWriter

final class PhysicalBookFlexContinuityTests: XCTestCase {
    func testOpeningAtZeroMatchesClosedStockExactly() {
        let closed = BookPreviewScene.softcoverFlexProfile(
            open: false, angleDegrees: 0
        )
        let zero = BookPreviewScene.softcoverFlexProfile(
            open: true, angleDegrees: 0
        )
        let barely = BookPreviewScene.softcoverFlexProfile(
            open: true, angleDegrees: 0.0001
        )

        XCTAssertEqual(
            zero.creaseDepth, closed.creaseDepth,
            accuracy: 0.000000001
        )
        XCTAssertEqual(
            zero.bowDepth, closed.bowDepth,
            accuracy: 0.000000001
        )
        XCTAssertEqual(
            barely.creaseDepth, closed.creaseDepth,
            accuracy: 0.000001
        )
        XCTAssertEqual(
            barely.bowDepth, closed.bowDepth,
            accuracy: 0.000001
        )
    }

    func testFullyOpenedCoverPreservesPhysicalEndpoint() {
        let full = BookPreviewScene.softcoverFlexProfile(
            open: true, angleDegrees: 180
        )
        XCTAssertEqual(
            full.creaseDepth, 0.0125,
            accuracy: 0.000000001
        )
        XCTAssertEqual(
            full.bowDepth, 0.006,
            accuracy: 0.000000001
        )
    }

    func testProgressiveElasticFlexRemainsFiniteAndBounded() {
        let values: [Double] = [
            0, 0.0001, 0.01, 0.1, 0.25, 0.5, 1, 9, 45, 90, 180
        ]

        let creaseMinimum: CGFloat = min(
            0.006, 0.006
        )
        let creaseMaximum: CGFloat = max(
            0.006, 0.0125
        )
        let bowMinimum: CGFloat = min(
            0.002, 0.002
        )
        let bowMaximum: CGFloat = max(
            0.002, 0.006
        )

        for angle in values {
            let current = BookPreviewScene.softcoverFlexProfile(
                open: true,
                angleDegrees: angle
            )
            XCTAssertTrue(current.creaseDepth.isFinite)
            XCTAssertTrue(current.bowDepth.isFinite)
            XCTAssertGreaterThanOrEqual(
                current.creaseDepth, creaseMinimum - 0.000000001
            )
            XCTAssertLessThanOrEqual(
                current.creaseDepth, creaseMaximum + 0.000000001
            )
            XCTAssertGreaterThanOrEqual(
                current.bowDepth, bowMinimum - 0.000000001
            )
            XCTAssertLessThanOrEqual(
                current.bowDepth, bowMaximum + 0.000000001
            )
        }
    }

    func testNormalAnglesPreserveOriginalPrintedStock() {
        for angle in [1.0, 9.0, 45.0, 90.0, 135.0, 180.0] {
            let value = BookPreviewScene.softcoverFlexProfile(
                open: true,
                angleDegrees: angle
            )
            let openness = CGFloat(angle / 180)
            XCTAssertEqual(
                value.creaseDepth,
                0.006 + 0.0065 * openness,
                accuracy: 0.000000001
            )
            XCTAssertEqual(
                value.bowDepth,
                0.002 + 0.004 * openness,
                accuracy: 0.000000001
            )
        }
    }

    func testInvalidFlexAnglesHaveFiniteClampedResults() {
        let zero = BookPreviewScene.softcoverFlexProfile(
            open: true, angleDegrees: 0
        )
        let maximum = BookPreviewScene.softcoverFlexProfile(
            open: true, angleDegrees: 180
        )
        for angle in [
            Double.nan, Double.infinity,
            -Double.infinity, -100
        ] {
            let profile = BookPreviewScene.softcoverFlexProfile(
                open: true, angleDegrees: angle
            )
            XCTAssertTrue(profile.creaseDepth.isFinite)
            XCTAssertTrue(profile.bowDepth.isFinite)
            XCTAssertEqual(
                profile.creaseDepth, zero.creaseDepth,
                accuracy: 0.000000001
            )
            XCTAssertEqual(
                profile.bowDepth, zero.bowDepth,
                accuracy: 0.000000001
            )
        }
        let excess = BookPreviewScene.softcoverFlexProfile(
            open: true, angleDegrees: 10000
        )
        XCTAssertEqual(
            excess.creaseDepth, maximum.creaseDepth,
            accuracy: 0.000000001
        )
        XCTAssertEqual(
            excess.bowDepth, maximum.bowDepth,
            accuracy: 0.000000001
        )
    }

    func testFlexibleCoverRetainsVerifiedUVTopology() {
        for side in [ThumbSide.left, .right] {
            let geometry = BookPreviewScene.flexibleCoverGeometry(
                width: 6,
                height: 9,
                insideEdge: side,
                creaseDepth: 0.012,
                bowDepth: 0.006
            )
            XCTAssertEqual(
                geometry.sources(for: .vertex).first?.vectorCount,
                50
            )
            XCTAssertGreaterThan(
                geometry.elements.count, 0
            )
        }
    }

    func testExtremeSpreadIndexCannotOverflowPageMass() {
        let stacks = PhysicalBookGeometry.pageStacks(
            pageCount: 401,
            spreadIndex: Int.max,
            totalDepth: 0.8
        )
        XCTAssertEqual(stacks.turnedPages, 401)
        XCTAssertEqual(stacks.remainingPages, 0)
        XCTAssertEqual(stacks.leftDepth, 0.8, accuracy: 0.00001)
        XCTAssertEqual(stacks.rightDepth, 0, accuracy: 0.00001)
    }

    func testNormalPageMassDistributionIsUnchanged() {
        let first = PhysicalBookGeometry.pageStacks(
            pageCount: 200, spreadIndex: 0, totalDepth: 0.8
        )
        let middle = PhysicalBookGeometry.pageStacks(
            pageCount: 200, spreadIndex: 50, totalDepth: 0.8
        )
        let last = PhysicalBookGeometry.pageStacks(
            pageCount: 200, spreadIndex: 100, totalDepth: 0.8
        )
        XCTAssertEqual(first.turnedPages, 0)
        XCTAssertEqual(middle.turnedPages, 100)
        XCTAssertEqual(last.turnedPages, 200)
        XCTAssertEqual(middle.leftDepth, 0.4, accuracy: 0.00001)
        XCTAssertEqual(middle.rightDepth, 0.4, accuracy: 0.00001)
    }

    func testInvalidCoverHingeAnglesRemainFinite() {
        var project = CoverProject(type: .printFullWrap)
        project.trimWidth = 6
        project.backWidth = 6
        project.trimHeight = 9
        project.spineWidth = 0.8

        let geometry = PhysicalBookGeometry(project: project)
        let zero = geometry.openedFrontCoverCenter(
            angleDegrees: 0
        )

        for angle in [
            Double.nan, Double.infinity, -Double.infinity
        ] {
            let value = geometry.openedFrontCoverCenter(
                angleDegrees: angle
            )
            XCTAssertTrue(value.x.isFinite)
            XCTAssertTrue(value.y.isFinite)
            XCTAssertEqual(value.x, zero.x, accuracy: 0.00001)
            XCTAssertEqual(value.y, zero.y, accuracy: 0.00001)
        }
    }

    func testInvalidPageDepthCannotCreateNonfinitePaperMass() {
        for depth in [
            Double.nan,
            Double.infinity,
            -Double.infinity,
            -100
        ] {
            let stacks = PhysicalBookGeometry.pageStacks(
                pageCount: 401,
                spreadIndex: 100,
                totalDepth: depth
            )
            XCTAssertTrue(stacks.leftDepth.isFinite)
            XCTAssertTrue(stacks.rightDepth.isFinite)
            XCTAssertEqual(stacks.leftDepth, 0, accuracy: 0.000001)
            XCTAssertEqual(stacks.rightDepth, 0, accuracy: 0.000001)
        }
    }
}
