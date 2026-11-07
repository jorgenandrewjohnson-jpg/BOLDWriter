import XCTest
import AppKit
import SceneKit
@testable import BOLDWriter

final class BookStudioPaperFilteringTests: XCTestCase {
    private func fixture() -> (
        SCNScene, SCNMaterial, SCNMaterial, SCNLight
    ) {
        let scene = SCNScene()

        let paper = SCNMaterial()
        paper.diffuse.contents = NSColor.white

        let edge = SCNMaterial()
        edge.diffuse.contents = NSImage(
            size: NSSize(width: 16, height: 16)
        )

        let geometry = SCNBox(
            width: 6,
            height: 9,
            length: 0.4,
            chamferRadius: 0
        )

        geometry.materials = [
            paper, edge, edge, edge, edge, edge
        ]

        let block = SCNNode(geometry: geometry)
        block.name = "book.closed-page-block"
        scene.rootNode.addChildNode(block)

        let keyLight = SCNLight()
        keyLight.type = .omni

        let keyNode = SCNNode()
        keyNode.name = "studio-light.key"
        keyNode.light = keyLight
        scene.rootNode.addChildNode(keyNode)

        return (scene, paper, edge, keyLight)
    }

    func testPageImageUsesMipmappedFiltering() {
        let (scene, _, edge, _) = fixture()

        let originalImage = edge.diffuse.contents as? NSImage
        XCTAssertNotNil(originalImage)

        BookStudioSceneStyling.configurePageTextureFiltering(
            in: scene.rootNode
        )

        XCTAssertTrue(
            (edge.diffuse.contents as? NSImage) === originalImage
        )
        XCTAssertEqual(edge.diffuse.minificationFilter, .linear)
        XCTAssertEqual(edge.diffuse.magnificationFilter, .linear)
        XCTAssertEqual(edge.diffuse.mipFilter, .linear)
    }

    func testExistingNormalMapIdentityAndIntensityArePreserved() {
        let (scene, _, edge, _) = fixture()

        let normal = NSImage(
            size: NSSize(width: 16, height: 16)
        )
        edge.normal.contents = normal
        edge.normal.intensity = 0.17

        BookStudioSceneStyling.configurePageTextureFiltering(
            in: scene.rootNode
        )

        XCTAssertTrue(
            (edge.normal.contents as? NSImage) === normal
        )
        XCTAssertEqual(
            edge.normal.intensity,
            0.17,
            accuracy: 0.000001
        )
        XCTAssertEqual(edge.normal.mipFilter, .linear)
    }

    func testPageFilteringDoesNotChangeColorsOrCoverArtwork() {
        let (scene, paper, edge, _) = fixture()
        let color = NSColor(
            calibratedRed: 0.9,
            green: 0.85,
            blue: 0.76,
            alpha: 1
        )

        edge.multiply.contents = color

        let coverMaterial = SCNMaterial()
        let artwork = NSImage(
            size: NSSize(width: 32, height: 32)
        )
        coverMaterial.diffuse.contents = artwork
        coverMaterial.diffuse.mipFilter = .nearest

        let cover = SCNNode(
            geometry: SCNPlane(width: 6, height: 9)
        )
        cover.name = "book-shell.front-cover"
        cover.geometry?.materials = [coverMaterial]
        scene.rootNode.addChildNode(cover)

        BookStudioSceneStyling.configurePageTextureFiltering(
            in: scene.rootNode
        )

        XCTAssertEqual(
            edge.multiply.contents as? NSColor,
            color
        )
        XCTAssertEqual(
            paper.diffuse.contents as? NSColor,
            NSColor.white
        )
        XCTAssertTrue(
            (coverMaterial.diffuse.contents as? NSImage) === artwork
        )
        XCTAssertEqual(
            coverMaterial.diffuse.mipFilter,
            .nearest
        )
    }

    func testShadowSamplesRespectQualityAndDisableState() {
        let qualities: [(BookRenderQuality, Int)] = [
            (.fast, 2),
            (.balanced, 4),
            (.high, 8),
            (.render, 16)
        ]

        for (quality, expected) in qualities {
            XCTAssertEqual(
                BookStudioSceneStyling.paperShadowSamples(
                    for: quality,
                    shadowsEnabled: true
                ),
                expected
            )

            XCTAssertEqual(
                BookStudioSceneStyling.paperShadowSamples(
                    for: quality,
                    shadowsEnabled: false
                ),
                1
            )
        }
    }

    func testStudioApplyWiresFilteringAndShadowSampling() {
        let (scene, _, edge, light) = fixture()

        var presentation = BookStudioPresentation()
        presentation.quality = .high
        presentation.shadowsEnabled = true

        BookStudioSceneStyling.apply(
            to: scene,
            presentation: presentation
        )

        XCTAssertTrue(light.castsShadow)
        XCTAssertEqual(light.shadowSampleCount, 8)
        XCTAssertEqual(edge.diffuse.mipFilter, .linear)

        presentation.quality = .render
        presentation.shadowsEnabled = false

        BookStudioSceneStyling.apply(
            to: scene,
            presentation: presentation
        )

        XCTAssertFalse(light.castsShadow)
        XCTAssertEqual(light.shadowSampleCount, 1)
        XCTAssertTrue(edge.diffuse.contents is NSImage)
    }
}
