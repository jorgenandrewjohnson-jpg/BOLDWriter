import SceneKit
import XCTest
@testable import BOLDWriter

@MainActor
final class PhysicalReadingCoverSupportTests:
    XCTestCase
{
    private func makeScene(
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

    private func center(
        node: SCNNode,
        root: SCNNode
    ) -> SCNVector3 {
        let bounds =
            node.geometry?.boundingBox
            ?? node.boundingBox

        let local =
            SCNVector3(
                (
                    bounds.min.x
                    + bounds.max.x
                )
                / 2,
                (
                    bounds.min.y
                    + bounds.max.y
                )
                / 2,
                (
                    bounds.min.z
                    + bounds.max.z
                )
                / 2
            )

        return root.convertPosition(
            local,
            from:
                node
        )
    }

    private func verifySupport(
        binding: BookBinding,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let scene =
            makeScene(
                binding:
                    binding
            )

        let root =
            try XCTUnwrap(
                scene.rootNode.childNode(
                    withName:
                        "physical-book.root",
                    recursively:
                        true
                ),
                file:
                    file,
                line:
                    line
            )

        let front =
            try XCTUnwrap(
                root.childNode(
                    withName:
                        "book-shell.front-cover",
                    recursively:
                        true
                ),
                file:
                    file,
                line:
                    line
            )

        let back =
            try XCTUnwrap(
                root.childNode(
                    withName:
                        "book-shell.back-cover",
                    recursively:
                        true
                ),
                file:
                    file,
                line:
                    line
            )

        let leftBlock =
            try XCTUnwrap(
                root.childNode(
                    withName:
                        "book.left-page-block",
                    recursively:
                        true
                ),
                file:
                    file,
                line:
                    line
            )

        let rightBlock =
            try XCTUnwrap(
                root.childNode(
                    withName:
                        "book.right-page-block",
                    recursively:
                        true
                ),
                file:
                    file,
                line:
                    line
            )

        let leftPage =
            try XCTUnwrap(
                root.childNode(
                    withName:
                        "book.left-active-page",
                    recursively:
                        true
                ),
                file:
                    file,
                line:
                    line
            )

        let rightPage =
            try XCTUnwrap(
                root.childNode(
                    withName:
                        "book.right-active-page",
                    recursively:
                        true
                ),
                file:
                    file,
                line:
                    line
            )

        let frontCenter =
            center(
                node:
                    front,
                root:
                    root
            )

        let backCenter =
            center(
                node:
                    back,
                root:
                    root
            )

        let leftBlockCenter =
            center(
                node:
                    leftBlock,
                root:
                    root
            )

        let rightBlockCenter =
            center(
                node:
                    rightBlock,
                root:
                    root
            )

        let leftPageCenter =
            center(
                node:
                    leftPage,
                root:
                    root
            )

        let rightPageCenter =
            center(
                node:
                    rightPage,
                root:
                    root
            )

        let leftSupportGap =
            leftBlockCenter.z
            - frontCenter.z

        let rightSupportGap =
            rightBlockCenter.z
            - backCenter.z

        XCTAssertGreaterThan(
            leftSupportGap,
            0,
            "Front cover must sit beneath the left paper block.",
            file:
                file,
            line:
                line
        )

        XCTAssertGreaterThan(
            rightSupportGap,
            0,
            "Back cover must sit beneath the right paper block.",
            file:
                file,
            line:
                line
        )

        XCTAssertGreaterThan(
            leftPageCenter.z,
            frontCenter.z,
            "Left manuscript page must remain above its front cover.",
            file:
                file,
            line:
                line
        )

        XCTAssertGreaterThan(
            rightPageCenter.z,
            backCenter.z,
            "Right manuscript page must remain above its back cover.",
            file:
                file,
            line:
                line
        )

        XCTAssertLessThan(
            frontCenter.x,
            0,
            file:
                file,
            line:
                line
        )

        XCTAssertGreaterThan(
            backCenter.x,
            0,
            file:
                file,
            line:
                line
        )

        // Unequal page counts have unequal center gaps. Each cover must
        // touch its own stack's underside rather than mirror the other gap.
        let thickness = CGFloat(PhysicalBookGeometry(project: {
            var p = CoverProject(type: .printFullWrap)
            p.spineWidth = 1.20482
            return p
        }()).coverThickness(for: binding) * 0.7)
        for (cover, block, sign) in [(front, leftBlock, CGFloat(-1)), (back, rightBlock, CGFloat(1))] {
            let box = try XCTUnwrap(block.geometry as? SCNBox)
            let contact = block.convertPosition(SCNVector3(0, 0, -box.length / 2), to: root)
            let localContact = cover.convertPosition(contact,from:root)
            // Fore-edge overhang changes centers along the tangent while
            // preserving the complete supporting plane beneath the paper.
            XCTAssertEqual(sign*localContact.z-thickness/2,0.001,accuracy:0.0025)
            let bounds = cover.boundingBox
            XCTAssertGreaterThan(localContact.x,bounds.min.x)
            XCTAssertLessThan(localContact.x,bounds.max.x)
        }
    }

    func testHardcoverReadingFrontCoverSupportsLeftPaperFromBelow()
        throws
    {
        try verifySupport(
            binding:
                .hardcover
        )
    }

    func testSoftcoverReadingFrontCoverSupportsLeftPaperFromBelow()
        throws
    {
        try verifySupport(
            binding:
                .softcover
        )
    }
}
