import XCTest
@testable import BOLDWriter

final class BookInspectionCameraPresetTests: XCTestCase {
    private func project(_ binding: BookBinding) -> CoverProject {
        var project = CoverProject(type: .printFullWrap)
        project.trimWidth = 6
        project.backWidth = 6
        project.trimHeight = 9
        project.spineWidth = 1.2
        project.productionBinding = binding
        return project
    }

    func testFourNewInspectionPresetsAreVisibleAndCodable() throws {
        let values: [BookViewPreset] = [
            .headEdge, .footEdge, .foreEdge, .lowPerspective
        ]
        XCTAssertEqual(BookViewPreset.allCases.count, 12)
        XCTAssertEqual(Set(values.map(\.rawValue)).count, 4)
        XCTAssertEqual(values.map(\.rawValue), [
            "Head Edge", "Foot Edge",
            "Fore Edge", "Low Three-Quarter"
        ])
        for value in values {
            let encoded = try JSONEncoder().encode(value)
            XCTAssertEqual(
                try JSONDecoder().decode(BookViewPreset.self, from: encoded),
                value
            )
        }
    }

    func testOpenBookInspectionDirectionsForBothBindings() {
        let expected: [(BookViewPreset, Double, Double)] = [
            (.headEdge, .pi, 0.12),
            (.footEdge, 0, 0.12),
            (.foreEdge, .pi / 2, 0.18),
            (.lowPerspective, 0.75, 0.24)
        ]
        for binding in [BookBinding.softcover, .hardcover] {
            for (preset, expectedYaw, expectedPitch) in expected {
                let state = BookPreviewCameraMath.state(
                    project: project(binding),
                    open: true,
                    preset: preset,
                    focus: .automatic
                )
                XCTAssertEqual(state.yaw, expectedYaw, accuracy: 0.000001)
                XCTAssertEqual(state.pitch, expectedPitch, accuracy: 0.000001)
                XCTAssertEqual(state.target.y, 0, accuracy: 0.000001)
                XCTAssertEqual(state.target.z, -3.15, accuracy: 0.000001)
                XCTAssertTrue(state.distance.isFinite)
                XCTAssertGreaterThan(state.distance, 0)
            }
        }
    }

    func testClosedBookHeadAndFootLookFromOppositeElevations() {
        for binding in [BookBinding.softcover, .hardcover] {
            let head = BookPreviewCameraMath.state(
                project: project(binding),
                open: false, preset: .headEdge, focus: .automatic
            )
            let foot = BookPreviewCameraMath.state(
                project: project(binding),
                open: false, preset: .footEdge, focus: .automatic
            )
            XCTAssertEqual(head.pitch, 1.48, accuracy: 0.000001)
            XCTAssertEqual(foot.pitch, -1.48, accuracy: 0.000001)
            XCTAssertEqual(head.target.y, 3.15, accuracy: 0.000001)
            XCTAssertEqual(foot.target.y, 3.15, accuracy: 0.000001)
            XCTAssertEqual(head.target.z, 0, accuracy: 0.000001)
            XCTAssertEqual(foot.target.z, 0, accuracy: 0.000001)
        }
    }
}
