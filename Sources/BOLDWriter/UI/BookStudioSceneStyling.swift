import AppKit
import SceneKit

enum BookStudioSceneStyling {
    /// Only presentation values consumed by `apply` invalidate the scene's
    /// materials and environment. Camera, transform, animation, and inspector
    /// state can change frequently without requiring a full scene traversal.
    static func needsReapplication(
        from previous: BookStudioPresentation?,
        to current: BookStudioPresentation
    ) -> Bool {
        guard let previous else { return true }
        return previous.environment != current.environment
            || previous.environmentIntensity != current.environmentIntensity
            || previous.showProductionMargins != current.showProductionMargins
            || previous.lighting != current.lighting
            || previous.lightIntensity != current.lightIntensity
            || previous.shadowsEnabled != current.shadowsEnabled
            || previous.quality != current.quality
            || previous.finish != current.finish
            || previous.paper != current.paper
            || previous.ground != current.ground
            || previous.exploded != current.exploded
            || previous.open != current.open
            || previous.bookEditorVisible != current.bookEditorVisible
            || previous.groundEditorVisible != current.groundEditorVisible
    }

    private static let clothNormal: NSImage = {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        for y in 0..<64 {
            for x in 0..<64 {
                let warp = CGFloat((x % 4) - 2) * 0.005
                let weft = CGFloat((y % 4) - 2) * 0.005
                bitmap.setColor(NSColor(calibratedRed: 0.5 + warp, green: 0.5 + weft,
                                        blue: 1, alpha: 1), atX: x, y: y)
            }
        }
        let image = NSImage(size: NSSize(width: 64, height: 64))
        image.addRepresentation(bitmap)
        return image
    }()

    static func apply(to scene: SCNScene, presentation: BookStudioPresentation) {
        scene.background.contents = presentation.environment.background
        scene.lightingEnvironment.contents = BookStudioEnvironmentMap.cubeMap(for: presentation.environment)
        scene.lightingEnvironment.intensity = 0.35 * presentation.environmentIntensity

        let root = scene.rootNode
        BookProductionMarginGuides.setVisible(presentation.showProductionMargins == true, in: root)
        let levels = presentation.lighting.levels
        let openingScale: CGFloat = (presentation.open || root.childNode(withName:"physical-book.root",recursively:true)?.value(forKey:"physicalBookOpen") as? Bool == true) ? 0.65:1
        root.childNode(withName: "studio-light.ambient", recursively: true)?.light?.intensity = levels.ambient * presentation.lightIntensity * openingScale
        let key = root.childNode(withName: "studio-light.key", recursively: true)?.light
        key?.intensity = levels.key * presentation.lightIntensity * openingScale
        key?.temperature = levels.temperature
        key?.castsShadow = presentation.shadowsEnabled

        key?.shadowSampleCount = paperShadowSamples(
            for: presentation.quality,
            shadowsEnabled: presentation.shadowsEnabled
        )

        key?.shadowRadius = presentation.lighting == .dramatic ? 3 : 9
        key?.shadowColor = NSColor.black.withAlphaComponent(presentation.lighting == .dramatic ? 0.42 : 0.22)
        root.childNode(withName: "studio-light.fill", recursively: true)?.light?.intensity = levels.fill * presentation.lightIntensity * openingScale
        root.childNode(withName: "studio-light.rim", recursively: true)?.light?.intensity = levels.rim * presentation.lightIntensity * openingScale

        if let ground = root.childNode(withName: "studio-ground", recursively: true) {
            ground.isHidden = presentation.ground == .none
            ground.geometry?.firstMaterial?.diffuse.contents = presentation.ground.color ?? presentation.environment.ground
        }

        for name in ["book-shell.front-cover", "book-shell.back-cover", "book-shell.spine-artwork"] {
            guard let node = root.childNode(withName: name, recursively: true) else { continue }
            setCoverFinish(on: node, finish: presentation.finish)
            for child in node.childNodes where child.name == nil {
                setCoverFinish(on: child, finish: presentation.finish)
            }
        }

        // Style the visible paper meshes as well as the support boxes. Reading
        // mode hides those boxes, so styling only SCNBox left the actual stack
        // and printed page a different stock color. Preserve texture identity.
        root.enumerateChildNodes { node, _ in
            guard let name = node.name, name.hasPrefix("book."),
                  name.contains("page-block") || name.contains("page-volume")
                    || name.contains("page-edge-strata") || name.contains("active-page")
                    || name.contains("visible-leaf") || name.contains("gutter-fold")
            else { return }
            for material in node.geometry?.materials ?? [] {
                if material.diffuse.contents is NSColor {
                    material.diffuse.contents = presentation.paper.surfaceColor
                    material.multiply.contents = NSColor.white
                } else if material.diffuse.contents is NSImage {
                    material.multiply.contents = presentation.paper.surfaceColor
                }
            }
        }
        configurePageTextureFiltering(in: root)
        setExploded(presentation.exploded && !presentation.open, on: scene)

        if
            let bookRoot =
                scene.rootNode
                .childNode(
                    withName:
                        "physical-book.root",
                    recursively:
                        true
                )
        {
            bookRoot.isHidden =
                !presentation
                .bookEditorVisible
        }

        if
            let ground =
                scene.rootNode
                .childNode(
                    withName:
                        "studio-ground",
                    recursively:
                        true
                )
        {
            let productionHidden =
                presentation.ground
                    == .none

            ground.setValue(
                productionHidden,
                forKey:
                    "bookStudioProductionHidden"
            )

            ground.isHidden =
                productionHidden
                || !presentation
                    .groundEditorVisible
        }

    }


    // BOLD WRITER — page-stock texture filtering.
    // Existing image, normal and paper-tone contents stay unchanged.
    static func configurePageTextureFiltering(in root: SCNNode) {
        let pageNames = [
            "book.left-page-block",
            "book.right-page-block",
            "book.closed-page-block",
            "book.left-page-fan",
            "book.right-page-fan",
            "book.left-active-page",
            "book.right-active-page"
        ]

        func configure(_ node: SCNNode) {
            for material in node.geometry?.materials ?? [] {
                guard material.diffuse.contents is NSImage else {
                    continue
                }

                material.diffuse.minificationFilter = .linear
                material.diffuse.magnificationFilter = .linear
                material.diffuse.mipFilter = .linear

                // Never replace an existing directional normal map.
                // Only improve sampling when the normal exists.
                if material.normal.contents != nil {
                    material.normal.minificationFilter = .linear
                    material.normal.magnificationFilter = .linear
                    material.normal.mipFilter = .linear
                }
            }
        }

        for name in pageNames {
            guard let node = root.childNode(
                withName: name,
                recursively: true
            ) else {
                continue
            }

            configure(node)

            node.enumerateChildNodes { child, _ in
                configure(child)
            }
        }
    }

    // Adaptive key-light sampling without changing shadow tint,
    // shadow radius, environment lighting or material colors.
    static func paperShadowSamples(
        for quality: BookRenderQuality,
        shadowsEnabled: Bool
    ) -> Int {
        guard shadowsEnabled else {
            return 1
        }

        switch quality {
        case .fast:
            return 2
        case .balanced:
            return 4
        case .high:
            return 8
        case .render:
            return 16
        }
    }

    static func setExploded(_ enabled: Bool, on scene: SCNScene) {
        let root = scene.rootNode
        let wasExploded = root.value(forKey: "bookStudioExploded") as? Bool ?? false
        guard wasExploded != enabled else { return }
        let direction: CGFloat = enabled ? 1 : -1
        root.childNode(withName: "book-shell.front-cover", recursively: true)?.position.z += 0.20 * direction
        root.childNode(withName: "book-shell.back-cover", recursively: true)?.position.z -= 0.20 * direction
        root.childNode(withName: "book-shell.spine", recursively: true)?.position.x -= 0.22 * direction
        root.childNode(withName: "book-shell.spine-artwork", recursively: true)?.position.x -= 0.22 * direction
        root.setValue(enabled, forKey: "bookStudioExploded")
    }

    private static func setCoverFinish(on node: SCNNode, finish: BookCoverFinish) {
        for material in node.geometry?.materials ?? [] where material.diffuse.contents is NSImage {
            material.lightingModel = .physicallyBased
            material.roughness.contents = finish.roughness
            material.metalness.contents = 0
            material.diffuse.minificationFilter = .linear
            material.diffuse.magnificationFilter = .linear
            material.diffuse.mipFilter = .linear
            if finish == .cloth {
                material.normal.contents = clothNormal
                material.normal.intensity = 0.15
                material.normal.wrapS = .repeat
                material.normal.wrapT = .repeat
            } else {
                material.normal.contents = nil
            }
        }
    }

    static func highlightedNode(in scene: SCNScene, component: BookSceneComponent?) -> SCNNode? {
        guard let component else { return nil }
        let names: [BookSceneComponent: [String]] = [
            .front: ["book-shell.front-cover"], .back: ["book-shell.back-cover"],
            .spine: ["book-shell.spine"], .pages: ["book.right-page-block", "book.closed-page-block", "book.left-page-block"],
            .leftPage: ["book.left-active-page"], .rightPage: ["book.right-active-page"]
        ]
        for name in names[component] ?? [] {
            if let node = scene.rootNode.childNode(withName: name, recursively: true) { return node }
        }
        return nil
    }

    static func addSelectionOutline(to scene: SCNScene, component: BookSceneComponent?) {
        var oldOutlines: [SCNNode] = []
        scene.rootNode.enumerateChildNodes { node, _ in
            if node.name == "studio-selection-outline" { oldOutlines.append(node) }
        }
        oldOutlines.forEach { $0.removeFromParentNode() }
        guard let node = highlightedNode(in: scene, component: component), node.geometry != nil else { return }
        let bounds = node.boundingBox
        let width = CGFloat(bounds.max.x - bounds.min.x)
        let height = CGFloat(bounds.max.y - bounds.min.y)
        let depth = CGFloat(bounds.max.z - bounds.min.z)
        let outline = SCNBox(width: max(0.02, width + 0.025),
                             height: max(0.02, height + 0.025),
                             length: max(0.02, depth + 0.025), chamferRadius: 0)
        let material = SCNMaterial()
        material.diffuse.contents = NSColor.systemOrange
        material.emission.contents = NSColor.systemOrange.withAlphaComponent(0.4)
        material.lightingModel = .constant
        material.fillMode = .lines
        material.isDoubleSided = true
        outline.materials = Array(repeating: material, count: 6)
        let highlight = SCNNode(geometry: outline)
        highlight.name = "studio-selection-outline"
        highlight.position = SCNVector3((bounds.min.x + bounds.max.x) / 2,
                                       (bounds.min.y + bounds.max.y) / 2,
                                       (bounds.min.z + bounds.max.z) / 2)
        highlight.renderingOrder = 200
        node.addChildNode(highlight)
    }
}
