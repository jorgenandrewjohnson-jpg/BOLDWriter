import SceneKit
import XCTest
@testable import BOLDWriter

@MainActor
final class PhysicalPageVolumeSurfaceTests:
    XCTestCase
{
    private func makeReadingScene(
        binding: BookBinding
    ) -> SCNScene {
        var project =
            CoverProject(
                type:
                    .printFullWrap
            )

        project.trimWidth =
            8.5

        project.backWidth =
            8.5

        project.trimHeight =
            11

        project.spineWidth =
            1.20482

        let pageCount =
            535

        let spread =
            PhysicalBookGeometry
            .naturalReadingSpread(
                pageCount:
                    pageCount
            )

        let presentation =
            BookStudioPresentation
            .restingOpenPreviewDefault

        return BookPreviewScene.make(
            project:
                project,
            workingLayers:
                false,
            open:
                true,
            angle:
                presentation.openAngle,
            leftPage:
                spread * 2,
            rightPage:
                spread * 2 + 1,
            pageCount:
                pageCount,
            spreadIndex:
                spread,
            leftTexture:
                nil,
            rightTexture:
                nil,
            margins:
                false,
            thumbMode:
                .off,
            leftPageSettings:
                PageSettings(),
            rightPageSettings:
                PageSettings(),
            preset:
                .reading,
            revisionID:
                UUID(),
            binding:
                binding,
            presentation:
                presentation
        )
    }

    private func verifyVolume(
        _ name: String,
        scene: SCNScene,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let volume =
            try XCTUnwrap(
                scene.rootNode.childNode(
                    withName:
                        name,
                    recursively:
                        true
                ),
                file:
                    file,
                line:
                    line
            )

        let geometry =
            try XCTUnwrap(
                volume.geometry,
                file:
                    file,
                line:
                    line
            )

        XCTAssertEqual(
            geometry.elements.count,
            6,
            "Keep six stable page-volume surface slots.",
            file:
                file,
            line:
                line
        )

        XCTAssertEqual(
            geometry.elements[0].primitiveCount,
            0,
            "The page volume must not draw a second broad TOP page skin.",
            file:
                file,
            line:
                line
        )

        let regionNames = [
            "bottom",
            "head",
            "tail",
            "gutter",
            "fore"
        ]

        for index in 1..<6 {
            XCTAssertGreaterThan(
                geometry.elements[index].primitiveCount,
                0,
                "Physical \(regionNames[index - 1]) geometry must remain.",
                file:
                    file,
                line:
                    line
            )
        }
    }

    func testHardcoverReadingVolumesKeepEdgesButNotDuplicateTop()
        throws
    {
        let scene =
            makeReadingScene(
                binding:
                    .hardcover
            )

        try verifyVolume(
            "book.left-page-volume",
            scene:
                scene
        )

        try verifyVolume(
            "book.right-page-volume",
            scene:
                scene
        )
    }

    func testSoftcoverReadingVolumesKeepEdgesButNotDuplicateTop()
        throws
    {
        let scene =
            makeReadingScene(
                binding:
                    .softcover
            )

        try verifyVolume(
            "book.left-page-volume",
            scene:
                scene
        )

        try verifyVolume(
            "book.right-page-volume",
            scene:
                scene
        )
    }
}
