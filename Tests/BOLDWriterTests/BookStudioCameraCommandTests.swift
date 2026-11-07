import XCTest
@testable import BOLDWriter

final class BookStudioCameraCommandTests: XCTestCase {
    func testAllCameraIdentifiersAndLabelsResolve() {
        XCTAssertEqual(BookViewPreset.allCases.count, 12)
        for preset in BookViewPreset.allCases {
            XCTAssertEqual(
                BookViewPreset.fromStudioCameraInput(preset.rawValue),
                preset
            )
            XCTAssertEqual(
                BookViewPreset.fromStudioCameraInput(
                    String(describing: preset)
                ),
                preset
            )
        }
    }

    func testHumanReadableNamesAndCommonAliases() {
        let cases: [(String, BookViewPreset)] = [
            ("Head Edge", .headEdge),
            ("HEAD-EDGE", .headEdge),
            ("top edge", .headEdge),
            ("foot_edge", .footEdge),
            ("bottom edge", .footEdge),
            ("fore edge", .foreEdge),
            ("page edge", .foreEdge),
            ("LOW ANGLE", .lowPerspective),
            ("low three-quarter", .lowPerspective),
            ("three quarter front", .perspective),
            ("front three quarter", .perspective),
            ("3quarterfront", .perspective),
            ("three-quarter back", .threeQuarterBack),
            ("diagonal back", .threeQuarterBack),
            ("3quarterback", .threeQuarterBack),
            ("Underneath", .underside),
            (" Reading ", .reading)
        ]

        for (name, expected) in cases {
            XCTAssertEqual(
                BookViewPreset.fromStudioCameraInput(name),
                expected,
                "Unresolved camera input: \(name)"
            )
        }
    }

    func testInvalidCameraNamesAreRejected() {
        for name in [
            "", "  ", "not-a-camera",
            "headless", "future-view", "!!!"
        ] {
            XCTAssertNil(
                BookViewPreset.fromStudioCameraInput(name)
            )
        }
    }

    func testCameraChoiceListMatchesAvailablePresets() {
        let names = BookViewPreset.studioCameraChoices
        XCTAssertEqual(names.count, 12)
        XCTAssertEqual(Set(names).count, 12)
        XCTAssertTrue(names.contains("Head Edge"))
        XCTAssertTrue(names.contains("Foot Edge"))
        XCTAssertTrue(names.contains("Fore Edge"))
        XCTAssertTrue(names.contains("Low Three-Quarter"))
        XCTAssertTrue(names.contains("Underside"))
    }
}
