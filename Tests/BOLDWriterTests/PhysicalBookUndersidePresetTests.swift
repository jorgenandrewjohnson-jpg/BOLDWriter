import XCTest
@testable import BOLDWriter

final class PhysicalBookUndersidePresetTests: XCTestCase {
    func testUndersidePresetShowsInCameraChoicesAndFacesUnderBook() {
        XCTAssertTrue(BookViewPreset.allCases.contains(.underside))
        XCTAssertEqual(BookViewPreset.underside.rawValue, "Underside")

        for binding in [BookBinding.softcover, .hardcover] {
            var project = CoverProject(type: .printFullWrap, width: 12.75, height: 9.25)
            project.productionBinding = binding
            let underside = BookPreviewCameraMath.state(
                project: project, open: true, preset: .underside, focus: .automatic
            )
            let reading = BookPreviewCameraMath.state(
                project: project, open: true, preset: .reading, focus: .automatic
            )
            XCTAssertEqual(underside.yaw, 0.22, accuracy: 0.00001)
            XCTAssertEqual(underside.pitch, -1.48, accuracy: 0.00001)
            XCTAssertLessThan(underside.pitch, -1.4)
            XCTAssertGreaterThan(reading.pitch, 0.8)
            XCTAssertEqual(underside.target.y, reading.target.y, accuracy: 0.00001)
            XCTAssertEqual(underside.target.z, reading.target.z, accuracy: 0.00001)
            XCTAssertGreaterThan(underside.distance, 0)
            XCTAssertTrue(underside.distance.isFinite)
        }
    }
}
