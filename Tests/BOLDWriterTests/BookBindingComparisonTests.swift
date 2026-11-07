import XCTest
import SceneKit
@testable import BOLDWriter

final class BookBindingComparisonTests: XCTestCase {
    func testOriginalPaperbackIsPreservedByDefault() {
        XCTAssertEqual(
            BookBindingPreviewComparison.resolve(
                original: .softcover,
                comparison: nil,
                fallback: .hardcover
            ),
            .softcover
        )
    }

    func testOriginalHardcoverIsPreservedByDefault() {
        XCTAssertEqual(
            BookBindingPreviewComparison.resolve(
                original: .hardcover,
                comparison: nil,
                fallback: .softcover
            ),
            .hardcover
        )
    }

    func testPreviewCanShowPaperbackArtworkOnHardcover() {
        XCTAssertEqual(
            BookBindingPreviewComparison.resolve(
                original: .softcover,
                comparison: .hardcover,
                fallback: .softcover
            ),
            .hardcover
        )
        XCTAssertTrue(
            BookBindingPreviewComparison.isMismatch(
                original: .softcover,
                displayed: .hardcover
            )
        )
    }

    func testPreviewCanShowHardcoverArtworkOnPaperback() {
        XCTAssertEqual(
            BookBindingPreviewComparison.resolve(
                original: .hardcover,
                comparison: .softcover,
                fallback: .hardcover
            ),
            .softcover
        )
        XCTAssertTrue(
            BookBindingPreviewComparison.isMismatch(
                original: .hardcover,
                displayed: .softcover
            )
        )
    }

    func testSwitchingBackRestoresOriginalBinding() {
        for original in BookBinding.allCases {
            let changed: BookBinding = (
                original == .softcover ? .hardcover : .softcover
            )

            let preview = BookBindingPreviewComparison.resolve(
                original: original,
                comparison: changed,
                fallback: original
            )
            XCTAssertNotEqual(preview, original)

            let restored = BookBindingPreviewComparison.resolve(
                original: original,
                comparison: nil,
                fallback: changed
            )
            XCTAssertEqual(restored, original)
            XCTAssertFalse(
                BookBindingPreviewComparison.isMismatch(
                    original: original,
                    displayed: restored
                )
            )
        }
    }

    func testUnknownOriginalBindingUsesExistingSelection() {
        XCTAssertEqual(
            BookBindingPreviewComparison.resolve(
                original: nil,
                comparison: nil,
                fallback: .hardcover
            ),
            .hardcover
        )

        XCTAssertFalse(
            BookBindingPreviewComparison.isMismatch(
                original: nil,
                displayed: .softcover
            )
        )
    }

    func testKDPTemplatesHaveDifferentSpineTrimAndWrap() {
        let paperbackSpine = 1.205
        let hardcoverSpine = 1.394
        let paperbackTrim = 8.5
        let hardcoverTrim = 8.25
        let paperbackWidth = 18.455
        let hardcoverWidth = 19.469

        XCTAssertEqual(
            hardcoverSpine - paperbackSpine,
            0.189,
            accuracy: 0.000001
        )
        XCTAssertEqual(
            paperbackTrim - hardcoverTrim,
            0.25,
            accuracy: 0.000001
        )
        XCTAssertEqual(
            hardcoverWidth - paperbackWidth,
            1.014,
            accuracy: 0.000001
        )
    }

    func testFourWayPhysicalBindingMatrixPreservesCoverProject() throws {
        for coverBinding in BookBinding.allCases {
            var project = CoverProject(type: .printFullWrap)
            project.name = "Original cover template"
            project.productionBinding = coverBinding
            project.trimWidth = 6
            project.backWidth = 6
            project.trimHeight = 9
            project.spineWidth = 1.2

            let originalName = project.name
            let originalBinding = project.productionBinding
            let originalSpine = project.spineWidth

            for physicalBinding in BookBinding.allCases {
                let resolved = BookBindingPreviewComparison.resolve(
                    original: project.productionBinding,
                    comparison: physicalBinding,
                    fallback: .softcover
                )

                let scene = BookPreviewScene.make(
                    project: project,
                    workingLayers: false,
                    open: false,
                    angle: 0,
                    leftPage: nil,
                    rightPage: 1,
                    pageCount: 20,
                    spreadIndex: 0,
                    leftTexture: nil,
                    rightTexture: nil,
                    margins: false,
                    thumbMode: .off,
                    leftPageSettings: PageSettings(),
                    rightPageSettings: PageSettings(),
                    preset: .perspective,
                    revisionID: UUID(),
                    binding: resolved
                )

                let cover = scene.rootNode.childNode(
                    withName: "book-shell.front-cover",
                    recursively: true
                )
                XCTAssertNotNil(cover)

                let joint = scene.rootNode.childNode(
                    withName: "book-shell.front-hinge-groove",
                    recursively: true
                )

                if physicalBinding == .hardcover {
                    XCTAssertNotNil(joint)
                } else {
                    XCTAssertNil(joint)
                }

                XCTAssertEqual(
                    BookBindingPreviewComparison.isMismatch(
                        original: coverBinding,
                        displayed: resolved
                    ),
                    coverBinding != physicalBinding
                )

                // Rendering each combination cannot change the
                // original print-cover project or source layout.
                XCTAssertEqual(project.name, originalName)
                XCTAssertEqual(
                    project.productionBinding,
                    originalBinding
                )
                XCTAssertEqual(
                    project.spineWidth,
                    originalSpine
                )
            }
        }
    }
}
