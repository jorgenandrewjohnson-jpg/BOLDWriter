import AppKit
import SceneKit
import XCTest
@testable import BOLDWriter

@MainActor
final class BookStudioTests: XCTestCase {
    private func project() -> CoverProject {
        var project = CoverProject(type: .printFullWrap)
        project.trimWidth = 6
        project.trimHeight = 9
        project.spineWidth = 0.8
        project.canvasWidth = 12.8
        return project
    }

    private func scene(_ presentation: BookStudioPresentation, open: Bool = false) -> SCNScene {
        BookPreviewScene.make(
            project: project(), workingLayers: false, open: open, angle: 180,
            leftPage: open ? 2 : nil, rightPage: open ? 3 : 1,
            pageCount: 24, spreadIndex: open ? 1 : 0,
            leftTexture: nil, rightTexture: nil,
            margins: false, thumbMode: .off,
            leftPageSettings: PageSettings(), rightPageSettings: PageSettings(),
            preset: .perspective, revisionID: UUID(), binding: presentation.binding,
            presentation: presentation
        )
    }

    func testPresentationPersistsAndOldMetadataDefaultsSafely() throws {
        var metadata = DocumentMetadata()
        var studio = BookStudioPresentation()
        studio.binding = .hardcover
        studio.finish = .gloss
        studio.paper = .cream
        studio.environment = .dark
        studio.projection = .orthographic
        studio.spreadIndex = 4
        metadata.bookStudioPresentation = studio
        let restored = try JSONDecoder().decode(DocumentMetadata.self, from: JSONEncoder().encode(metadata))
        XCTAssertEqual(restored.bookStudioPresentation, studio)

        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(metadata)) as? [String: Any])
        object.removeValue(forKey: "bookStudioPresentation")
        let legacy = try JSONDecoder().decode(DocumentMetadata.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(legacy.bookStudioPresentation)
        let partial = try JSONDecoder().decode(BookStudioPresentation.self, from: Data(#"{"finish":"Gloss"}"#.utf8))
        XCTAssertEqual(partial.finish, .gloss)
        XCTAssertEqual(partial.environment, .neutral)
        XCTAssertEqual(BookStudioPresentation(openAngle: .nan, spreadIndex: 999).normalized(pageCount: 12).spreadIndex, 6)
        XCTAssertEqual(BookStudioPresentation(openAngle: .nan).normalized(pageCount: 12).openAngle, 180)
    }

    func testNearClosedStudioAnglesSurviveSaveAndNormalizationForBothBindings() throws {
        for binding in BookBinding.allCases {
            for angle in [0.0, 5, 14, 15, 90, 180] {
                XCTAssertTrue(BookStudioPresentation.openingAngleRange.contains(angle))
                var presentation = BookStudioPresentation(binding: binding, open: true, openAngle: angle)
                presentation.cameraPreset = .reading
                let decoded = try JSONDecoder().decode(BookStudioPresentation.self,
                    from: JSONEncoder().encode(presentation))
                XCTAssertEqual(decoded.normalized(pageCount: 356).openAngle, angle)
                XCTAssertTrue(decoded.normalized(pageCount: 356).open)
            }
        }
        XCTAssertEqual(BookStudioPresentation(openAngle: -5).normalized(pageCount: 356).openAngle, 0)
        XCTAssertEqual(BookStudioPresentation(openAngle: 190).normalized(pageCount: 356).openAngle, 180)
    }

    func testReplacementSceneCameraIsReadyWhenPublished() throws {
        let view = BookPreviewInteractionView()
        var publications = 0
        let observation = view.observe(\.scene, options: [.new]) { _, change in
            guard let scene = change.newValue ?? nil,
                  let camera = scene.rootNode.childNode(withName: "preview-camera", recursively: true)
            else { return XCTFail("Published scene has no camera") }
            publications += 1
            XCTAssertGreaterThan(camera.position.z, 1, "A newly published camera must not be at the origin")
            XCTAssertEqual(camera.camera?.fieldOfView, 47)
            XCTAssertEqual(camera.camera?.usesOrthographicProjection, true)
        }
        defer { observation.invalidate() }
        for binding in BookBinding.allCases {
            for open in [false, true, false] {
                let replacement = scene(BookStudioPresentation(binding: binding), open: open)
                let state = BookPreviewCameraState(yaw: 0, pitch: 0.5, distance: 5)
                view.installScene(replacement, state: state, projection: .orthographic, fieldOfView: 47)
                XCTAssertTrue(view.pointOfView === view.cameraNode)
                XCTAssertTrue(view.cameraNode?.parent === replacement.rootNode)
            }
        }
        XCTAssertEqual(publications, BookBinding.allCases.count * 3)
    }

    func testSceneStylesActualCoverPaperLightingAndGround() throws {
        var studio = BookStudioPresentation()
        studio.binding = .hardcover
        studio.finish = .gloss
        studio.paper = .cream
        studio.environment = .dark
        studio.lighting = .dramatic
        studio.ground = .none
        studio.environmentIntensity = 1.5
        studio.lightIntensity = 0.5
        studio.shadowsEnabled = false
        let result = scene(studio)
        let root = result.rootNode
        let front = try XCTUnwrap(root.childNode(withName: "book-shell.front-cover", recursively: true))
        let artwork = try XCTUnwrap(front.childNodes.compactMap { $0.geometry?.firstMaterial }.first)
        artwork.diffuse.contents = NSImage(size: NSSize(width: 20, height: 30))
        BookStudioSceneStyling.apply(to: result, presentation: studio)
        XCTAssertEqual(artwork.roughness.contents as? CGFloat, BookCoverFinish.gloss.roughness)
        let pages = try XCTUnwrap(root.childNode(withName: "book.closed-page-block", recursively: true))
        XCTAssertEqual(pages.geometry?.materials.first?.diffuse.contents as? NSColor, BookPaperTone.cream.surfaceColor)
        XCTAssertEqual(root.childNode(withName: "studio-light.key", recursively: true)?.light?.intensity,
                       BookLightingPreset.dramatic.levels.key * 0.5)
        XCTAssertFalse(try XCTUnwrap(root.childNode(withName: "studio-light.key", recursively: true)?.light).castsShadow)
        XCTAssertEqual(result.lightingEnvironment.intensity, 0.35 * 1.5, accuracy: 0.0001)
        let environmentFaces = try XCTUnwrap(result.lightingEnvironment.contents as? NSArray)
        XCTAssertEqual(environmentFaces.count, 6)
        let reflectionFace = try XCTUnwrap(environmentFaces[4] as? NSImage)
        let reflectionPixels = try XCTUnwrap(reflectionFace.representations.first as? NSBitmapImageRep)
        XCTAssertGreaterThan(try XCTUnwrap(reflectionPixels.colorAt(x: 48, y: 70)).brightnessComponent,
                             try XCTUnwrap(reflectionPixels.colorAt(x: 0, y: 0)).brightnessComponent)
        XCTAssertTrue(try XCTUnwrap(root.childNode(withName: "studio-ground", recursively: true)).isHidden)
        XCTAssertEqual(result.background.contents as? NSColor, BookEnvironmentPreset.dark.background)
        studio.finish = .cloth
        BookStudioSceneStyling.apply(to: result, presentation: studio)
        XCTAssertNotNil(artwork.normal.contents as? NSImage)
        studio.finish = .matte
        BookStudioSceneStyling.apply(to: result, presentation: studio)
        XCTAssertNil(artwork.normal.contents)
    }

    func testReadingPaperToneReachesVisibleMassAndPrintedTextureWithoutChangingArtwork() throws {
        for binding in BookBinding.allCases {
            let pageImage = NSImage(size:NSSize(width:20,height:30))
            var studio = BookStudioPresentation()
            studio.binding = binding; studio.open = true
            let result = BookPreviewScene.make(project:project(),workingLayers:false,open:true,angle:180,
                leftPage:12,rightPage:13,pageCount:24,spreadIndex:6,leftTexture:pageImage,rightTexture:pageImage,
                margins:false,thumbMode:.off,leftPageSettings:PageSettings(),rightPageSettings:PageSettings(),
                preset:.reading,revisionID:UUID(),binding:binding,presentation:studio)
            let cover = try XCTUnwrap(result.rootNode.childNode(withName:"book-shell.front-cover",recursively:true))
            let coverColors = cover.geometry?.materials.compactMap { $0.diffuse.contents as? NSColor }
            let before = BookSceneInspection(scene:result)
            for tone in [BookPaperTone.cream,.white,.offWhite,.cream] {
                studio.paper = tone
                BookStudioSceneStyling.apply(to:result,presentation:studio)
                for side in ["left","right"] {
                    let volume = try XCTUnwrap(result.rootNode.childNode(withName:"book.\(side)-page-volume",recursively:true))
                    let materials = try XCTUnwrap(volume.geometry).materials
                    XCTAssertEqual(materials[0].diffuse.contents as? NSColor,tone.surfaceColor)
                    XCTAssertEqual(materials[2].multiply.contents as? NSColor,tone.surfaceColor)
                    XCTAssertEqual(materials[2].transparency,1)
                    let page = try XCTUnwrap(result.rootNode.childNode(withName:"book.\(side)-active-page",recursively:true))
                    let material = try XCTUnwrap(page.geometry?.materials.first)
                    XCTAssertTrue((material.diffuse.contents as? NSImage) === pageImage)
                    XCTAssertEqual(material.multiply.contents as? NSColor,tone.surfaceColor)
                }
                XCTAssertEqual(cover.geometry?.materials.compactMap { $0.diffuse.contents as? NSColor },coverColors)
                XCTAssertEqual(BookSceneInspection(scene:result).maximumCoverPenetration,before.maximumCoverPenetration)
            }
        }
    }

    func testPaperEdgeNormalTextureHasNeutralMeanAndSmallOpposingSlopes() throws {
        let bitmap = try XCTUnwrap(BookPreviewScene.pageStrataNormalImage.representations.first as? NSBitmapImageRep)
        let data = try XCTUnwrap(bitmap.bitmapData)
        var sum = 0.0, minimum = 255, maximum = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let offset = y*bitmap.bytesPerRow+x*4, red = Int(data[offset])
                minimum = min(minimum,red); maximum = max(maximum,red); sum += Double(red)
                XCTAssertEqual(data[offset+1],128)
                XCTAssertGreaterThanOrEqual(data[offset+2],253)
                XCTAssertEqual(data[offset+3],255)
            }
        }
        XCTAssertLessThan(minimum,127)
        XCTAssertGreaterThan(maximum,128)
        XCTAssertGreaterThan(minimum,110)
        XCTAssertLessThan(maximum,145)
        XCTAssertEqual(sum/Double(bitmap.pixelsWide*bitmap.pixelsHigh),127.5,accuracy:0.6)
    }

    func testSelectionUsesStableSceneNodesAndDoesNotTintArtwork() throws {
        let result = scene(BookStudioPresentation())
        let front = try XCTUnwrap(result.rootNode.childNode(withName: "book-shell.front-cover", recursively: true))
        let before = front.geometry?.materials.map { $0.diffuse.contents }
        BookStudioSceneStyling.addSelectionOutline(to: result, component: .front)
        XCTAssertNotNil(front.childNode(withName: "studio-selection-outline", recursively: false))
        XCTAssertEqual(front.geometry?.materials.count, before?.count)
        XCTAssertEqual(BookSceneComponent.component(for: "book-shell.front-cover"), .front)
        XCTAssertEqual(BookSceneComponent.component(for: "book.right-active-page"), .rightPage)
        XCTAssertNil(BookSceneComponent.component(for: "studio-selection-outline"))
    }

    func testReselectingEveryCameraPresetClearsManualOrbitForBothBindings() throws {
        for binding in BookBinding.allCases {
            for preset in BookViewPreset.allCases {
                var presentation = BookStudioPresentation()
                presentation.binding = binding
                presentation.cameraPreset = preset

                let manualCamera = BookPreviewCameraMath.state(
                    project: project(),
                    open: true,
                    preset: preset,
                    focus: .automatic
                ).saved

                presentation.savedCamera = manualCamera

                var resetGeneration = 40

                XCTAssertTrue(
                    BookStudioCameraPresetCommand.reselect(
                        preset,
                        presentation: &presentation,
                        resetGeneration: &resetGeneration
                    )
                )

                XCTAssertNil(presentation.savedCamera)
                XCTAssertEqual(presentation.cameraPreset, preset)
                XCTAssertEqual(presentation.binding, binding)
                XCTAssertEqual(resetGeneration, 41)

                presentation.savedCamera = manualCamera

                XCTAssertTrue(
                    BookStudioCameraPresetCommand.reselect(
                        preset,
                        presentation: &presentation,
                        resetGeneration: &resetGeneration
                    )
                )

                XCTAssertNil(presentation.savedCamera)
                XCTAssertEqual(resetGeneration, 42)
            }
        }
    }

    func testNativeAcceptanceReselectsActivePresetAndPreservesBinding() throws {
        for binding in BookBinding.allCases {
            for preset in BookViewPreset.allCases {
                var presentation = BookStudioPresentation()
                presentation.binding = binding
                presentation.cameraPreset = preset

                let manualCamera = BookPreviewCameraMath.state(
                    project: project(),
                    open: true,
                    preset: preset,
                    focus: .automatic
                ).saved

                presentation.savedCamera = manualCamera

                var generation = 7

                BookStudioAcceptance.selectCameraPreset(
                    preset,
                    studio: &presentation,
                    resetGeneration: &generation
                )

                XCTAssertEqual(presentation.cameraPreset, preset)
                XCTAssertEqual(presentation.binding, binding)
                XCTAssertNil(presentation.savedCamera)
                XCTAssertEqual(generation, 8)

                // Another explicit selection must work even when the
                // same camera preset is still the current value.
                presentation.savedCamera = manualCamera

                BookStudioAcceptance.selectCameraPreset(
                    preset,
                    studio: &presentation,
                    resetGeneration: &generation
                )

                XCTAssertNil(presentation.savedCamera)
                XCTAssertEqual(generation, 9)

                // A different preset uses the normal coordinator
                // presetChanged path instead of duplicating reset.
                let replacement = BookViewPreset.allCases.first {
                    $0 != preset
                }!

                BookStudioAcceptance.selectCameraPreset(
                    replacement,
                    studio: &presentation,
                    resetGeneration: &generation
                )

                XCTAssertEqual(
                    presentation.cameraPreset,
                    replacement
                )
                XCTAssertEqual(presentation.binding, binding)
                XCTAssertEqual(generation, 9)
            }
        }
    }

    func testRepeatedReadingPresetRequestsFreshCameraFraming() throws {
        var studio = BookStudioPresentation()
        studio.cameraPreset = .reading

        let manualCamera = BookPreviewCameraMath.state(
            project: project(),
            open: true,
            preset: .reading,
            focus: .automatic
        ).saved

        studio.savedCamera = manualCamera
        var resetGeneration = 12

        XCTAssertTrue(
            BookStudioCameraPresetCommand.reselect(
                .reading,
                presentation: &studio,
                resetGeneration: &resetGeneration
            )
        )
        XCTAssertNil(studio.savedCamera)
        XCTAssertEqual(studio.cameraPreset, .reading)
        XCTAssertEqual(resetGeneration, 13)

        studio.savedCamera = manualCamera

        XCTAssertTrue(
            BookStudioCameraPresetCommand.reselect(
                .reading,
                presentation: &studio,
                resetGeneration: &resetGeneration
            )
        )
        XCTAssertNil(studio.savedCamera)
        XCTAssertEqual(resetGeneration, 14)

        // A different selection remains handled by the ordinary
        // preset-change path, without a duplicate reset request.
        studio.savedCamera = manualCamera
        XCTAssertFalse(
            BookStudioCameraPresetCommand.reselect(
                .front,
                presentation: &studio,
                resetGeneration: &resetGeneration
            )
        )
        XCTAssertEqual(studio.savedCamera, manualCamera)
        XCTAssertEqual(studio.cameraPreset, .reading)
        XCTAssertEqual(resetGeneration, 14)
    }

    func testCameraPanProjectionAndPresentationPresetsAreDeterministic() throws {
        var state = BookPreviewCameraMath.state(project: project(), open: false, preset: .top, focus: .automatic)
        XCTAssertGreaterThan(state.pitch, 1.4)
        let original = state.target
        state.pan(deltaX: 35, deltaY: -20, viewportHeight: 500)
        XCTAssertNotEqual(state.target, original)
        var wideFOV = BookPreviewCameraMath.state(project: project(), open: false, preset: .top, focus: .automatic)
        wideFOV.pan(deltaX: 35, deltaY: -20, viewportHeight: 500, fieldOfView: 60)
        XCTAssertGreaterThan(abs(wideFOV.target.x - original.x), abs(state.target.x - original.x))
        let view = BookPreviewInteractionView()
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        view.cameraNode = cameraNode
        view.configureCamera(state, projection: .orthographic, fieldOfView: 42)
        XCTAssertTrue(try XCTUnwrap(cameraNode.camera).usesOrthographicProjection)
        XCTAssertGreaterThan(try XCTUnwrap(cameraNode.camera).orthographicScale, 0)
        XCTAssertEqual(try XCTUnwrap(cameraNode.camera).fieldOfView, 42)
        view.configureCamera(state, projection: .perspective)
        XCTAssertFalse(try XCTUnwrap(cameraNode.camera).usesOrthographicProjection)
        let saved = state.saved
        XCTAssertTrue(saved.isValid)
        XCTAssertEqual(BookPreviewCameraState(saved: saved), state)
        var persisted = BookStudioPresentation(savedCamera: saved)
        XCTAssertEqual(try JSONDecoder().decode(BookStudioPresentation.self, from: JSONEncoder().encode(persisted)).savedCamera, saved)
        persisted.savedCamera?.distance = .infinity
        XCTAssertNil(persisted.normalized(pageCount: 10).savedCamera)

        let library = BookStudioPreset.library.apply(to: BookStudioPresentation())
        XCTAssertTrue(library.open)
        XCTAssertEqual(library.environment, .warm)
        XCTAssertEqual(library.lighting, .library)
        XCTAssertEqual(BookStudioRenderSize.portrait1600.pixels, CGSize(width: 1600, height: 2000))
        XCTAssertEqual(BookStudioRenderSize.viewport2x.resolvedPixels(
            viewportSize: CGSize(width: 400, height: 300), backingScale: 2), CGSize(width: 1600, height: 1200))
        XCTAssertNil(BookStudioRenderDimensions(width: 6000, height: 6000))
        XCTAssertNil(BookStudioRenderDimensions(width: 100, height: 1000))
        XCTAssertEqual(BookStudioRenderSize.custom.resolvedPixels(
            viewportSize: .zero, backingScale: 2,
            customSize: BookStudioRenderDimensions(width: 3200, height: 2400)),
            CGSize(width: 3200, height: 2400))
    }

    func testSnapshotUsesRequestedPixelDimensions() throws {
        let view = BookPreviewInteractionView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        view.scene = scene(BookStudioPresentation())
        view.cameraNode = view.scene?.rootNode.childNode(withName: "preview-camera", recursively: true)
        view.setCamera(BookPreviewCameraMath.state(project: project(), open: false, preset: .front, focus: .automatic))
        let handle = BookStudioViewportHandle()
        handle.view = view
        let image = try XCTUnwrap(handle.image(size: CGSize(width: 128, height: 160)))
        let bitmap = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        XCTAssertEqual(bitmap.pixelsWide, 128)
        XCTAssertEqual(bitmap.pixelsHigh, 160)
        for format: NSBitmapImageRep.FileType in [.png, .jpeg] {
            let data = try XCTUnwrap(bitmap.representation(using: format, properties: [:]))
            let exported = try XCTUnwrap(NSBitmapImageRep(data: data))
            XCTAssertEqual(exported.pixelsWide, 128)
            XCTAssertEqual(exported.pixelsHigh, 160)
        }
    }

    func testTransparentSnapshotIsIsolatedAndRestoresScene() throws {
        let view = BookPreviewInteractionView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        view.scene = scene(BookStudioPresentation())
        view.cameraNode = view.scene?.rootNode.childNode(withName: "preview-camera", recursively: true)
        view.setCamera(BookPreviewCameraMath.state(project: project(), open: false, preset: .front, focus: .automatic))
        let handle = BookStudioViewportHandle()
        handle.view = view
        let background = view.scene?.background.contents as? NSColor
        let ground = try XCTUnwrap(view.scene?.rootNode.childNode(withName: "studio-ground", recursively: true))
        let image = try XCTUnwrap(handle.image(size: CGSize(width: 128, height: 128), transparent: true))
        let bitmap = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        XCTAssertLessThan(try XCTUnwrap(bitmap.colorAt(x: 0, y: 0)).alphaComponent, 0.05)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let decoded = try XCTUnwrap(NSBitmapImageRep(data: png))
        XCTAssertLessThan(try XCTUnwrap(decoded.colorAt(x: 0, y: 0)).alphaComponent, 0.05)
        XCTAssertEqual(view.scene?.background.contents as? NSColor, background)
        XCTAssertFalse(ground.isHidden)
    }

    func testReleasingViewportDropsSceneAndInteractionResources() {
        let view = BookPreviewInteractionView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        view.scene = scene(BookStudioPresentation())
        view.isPlaying = true
        view.onOrbit = { _, _ in }
        view.onZoom = { _ in }
        let handle = BookStudioViewportHandle()
        handle.view = view
        handle.coverProject = project()

        handle.releasePreviewResources()

        XCTAssertFalse(view.isPlaying)
        XCTAssertNil(view.scene)
        XCTAssertNil(view.pointOfView)
        XCTAssertNil(handle.view)
        XCTAssertNil(handle.coverProject)
        XCTAssertNil(view.onOrbit)
        XCTAssertNil(view.onZoom)

        // SwiftUI dismantling and parent-window teardown can both attempt to
        // retire the same preview. The synchronized release path is idempotent.
        handle.releasePreviewResources()
        XCTAssertNil(view.scene)
        XCTAssertNil(view.pointOfView)
    }

    func testHighQualityCoverRenderRestoresInteractiveArtwork() throws {
        let view = BookPreviewInteractionView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        view.scene = scene(BookStudioPresentation())
        view.cameraNode = view.scene?.rootNode.childNode(withName: "preview-camera", recursively: true)
        view.setCamera(BookPreviewCameraMath.state(project: project(), open: false, preset: .front, focus: .automatic))
        let front = try XCTUnwrap(view.scene?.rootNode.childNode(withName: "book-shell.front-cover", recursively: true))
        let material = try XCTUnwrap(front.geometry?.materials.first(where: { $0.diffuse.contents is NSImage }))
        let interactiveArtwork = try XCTUnwrap(material.diffuse.contents as? NSImage)
        let handle = BookStudioViewportHandle()
        handle.view = view
        handle.coverProject = project()
        XCTAssertNotNil(handle.image(size: CGSize(width: 128, height: 128), highQualityCover: true))
        XCTAssertTrue(material.diffuse.contents as? NSImage === interactiveArtwork)
    }

    func testPageTextureCacheReusesQualityAndInvalidatesBySource() {
        var cache = BookPageTextureCache(capacity: 3)
        let low = NSImage(size: NSSize(width: 10, height: 10))
        let high = NSImage(size: NSSize(width: 20, height: 20))
        cache.store(high, for: 2, maximumPixels: 2400)
        cache.store(low, for: 2, maximumPixels: 900)
        XCTAssertTrue(cache.image(for: 2) === high)
        XCTAssertFalse(cache.needsImage(for: 2, maximumPixels: 2400))
        cache.store(low, for: 3, maximumPixels: 900)
        cache.store(low, for: 4, maximumPixels: 900)
        cache.store(low, for: 5, maximumPixels: 900)
        XCTAssertNil(cache.image(for: 2))

        let source = cache.sourceID
        cache.reset()
        XCTAssertNotEqual(cache.sourceID, source)
        XCTAssertTrue(cache.entries.isEmpty)
        let plan = BookPageTextureCache.pagePlan(for: PhysicalBookGeometry.spread(at: 1, pageCount: 8), pageCount: 8)
        XCTAssertEqual(plan.visible, [2, 3])
        XCTAssertEqual(plan.adjacent, [1, 4])
    }

    func testDiagnosticPageTextureIdentityIsStableUntilSourceChanges() {
        let decorator = BookPageTextureDecorator()
        let first = NSImage(size: NSSize(width: 100, height: 140))
        let marked = decorator.texture(for: 2, source: first, hasIssue: true)
        XCTAssertTrue(marked === decorator.texture(for: 2, source: first, hasIssue: true))
        XCTAssertTrue(first === decorator.texture(for: 2, source: first, hasIssue: false))
        let replacement = NSImage(size: NSSize(width: 100, height: 140))
        XCTAssertFalse(marked === decorator.texture(for: 2, source: replacement, hasIssue: true))
        decorator.reset()
        XCTAssertFalse(marked === decorator.texture(for: 2, source: first, hasIssue: true))
    }

    func testCoverTextureCacheChangesOnlyWithCoverSource() {
        var source = project()
        let first = BookPreviewScene.coverTextures(project: source, workingLayers: false, revisionID: UUID())
        let manuscriptOnlyRevision = BookPreviewScene.coverTextures(project: source, workingLayers: false, revisionID: UUID())
        XCTAssertTrue(first === manuscriptOnlyRevision)
        var copiedCover = source
        copiedCover.id = UUID()
        let identicalArtwork = BookPreviewScene.coverTextures(project: copiedCover, workingLayers: false, revisionID: UUID())
        XCTAssertTrue(first === identicalArtwork, "An identity-only copy must reuse its existing raster")
        source.backgroundHex = "#224466"
        let changed = BookPreviewScene.coverTextures(project: source, workingLayers: false, revisionID: UUID())
        XCTAssertFalse(first === changed)
        let working = BookPreviewScene.coverTextures(project: source, workingLayers: true, revisionID: UUID())
        XCTAssertFalse(changed === working)
    }

    func testExplodedInspectionMovesSceneShellWithoutChangingBookDimensions() throws {
        let normal = scene(BookStudioPresentation())
        let exploded = scene(BookStudioPresentation(exploded: true))
        let front = try XCTUnwrap(normal.rootNode.childNode(withName: "book-shell.front-cover", recursively: true))
        let separatedFront = try XCTUnwrap(exploded.rootNode.childNode(withName: "book-shell.front-cover", recursively: true))
        let spine = try XCTUnwrap(normal.rootNode.childNode(withName: "book-shell.spine", recursively: true))
        let separatedSpine = try XCTUnwrap(exploded.rootNode.childNode(withName: "book-shell.spine", recursively: true))
        XCTAssertEqual(separatedFront.position.z - front.position.z, 0.20, accuracy: 0.0001)
        XCTAssertEqual(separatedSpine.position.x - spine.position.x, -0.22, accuracy: 0.0001)
        XCTAssertEqual(separatedFront.boundingBox.min.x, front.boundingBox.min.x)
        XCTAssertEqual(separatedFront.boundingBox.max.x, front.boundingBox.max.x)
        BookStudioSceneStyling.apply(to: exploded, presentation: BookStudioPresentation(exploded: true))
        XCTAssertEqual(separatedFront.position.z - front.position.z, 0.20, accuracy: 0.0001)
        BookStudioSceneStyling.apply(to: exploded, presentation: BookStudioPresentation())
        XCTAssertEqual(separatedFront.position.z, front.position.z, accuracy: 0.0001)

        BookStudioSceneStyling.setExploded(true, on: exploded)
        let view = BookPreviewInteractionView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        view.scene = exploded
        view.cameraNode = exploded.rootNode.childNode(withName: "preview-camera", recursively: true)
        view.setCamera(BookPreviewCameraMath.state(project: project(), open: false,
                                                   preset: .front, focus: .automatic))
        let handle = BookStudioViewportHandle()
        handle.view = view
        let beforeExport = separatedFront.position.z
        XCTAssertNotNil(handle.image(size: CGSize(width: 64, height: 64)))
        XCTAssertEqual(separatedFront.position.z, beforeExport, accuracy: 0.0001)
    }

    func testSceneSourceKeySeparatesGeometryFromPresentationChanges() {
        let image = NSImage(size: NSSize(width: 4, height: 4))
        let revision = UUID()
        let key = BookSceneSourceKey(project: project(), workingLayers: false, binding: .softcover,
                                     isOpen: false, openAngle: 180, pageCount: 24, spreadIndex: 0,
                                     turnTransition: nil, leftPage: nil, rightPage: 1,
                                     leftTextureID: nil, rightTextureID: ObjectIdentifier(image),
                                     showMargins: false, thumbMode: .off,
                                     leftPageSettings: PageSettings(), rightPageSettings: PageSettings(),
                                     revisionID: revision)
        XCTAssertEqual(key, key)
        var changed = key
        changed.spreadIndex = 1
        XCTAssertNotEqual(key, changed)
        changed = key
        changed.rightTextureID = ObjectIdentifier(NSImage(size: NSSize(width: 4, height: 4)))
        XCTAssertNotEqual(key, changed)
        changed = key
        changed.project.spineWidth = 1.2
        XCTAssertNotEqual(key, changed)
    }

    func testDoubleClickFramingUsesSelectedPhysicalComponentBounds() throws {
        let book = scene(BookStudioPresentation())
        let front = try XCTUnwrap(book.rootNode.childNode(withName: "book-shell.front-cover", recursively: true))
        let starting = BookPreviewCameraMath.state(project: project(), open: false,
                                                   preset: .perspective, focus: .automatic)
        let framed = BookPreviewCameraMath.frame(front, from: starting, fieldOfView: 34, viewportAspect: 1.5)
        XCTAssertEqual(framed.yaw, starting.yaw)
        XCTAssertGreaterThan(framed.distance, 0.35)
        XCTAssertLessThan(framed.distance, starting.distance)
        XCTAssertEqual(framed.target.x, Double(front.position.x), accuracy: 0.1)
        XCTAssertEqual(framed.target.y, Double(front.position.y), accuracy: 0.1)
    }

    func testInteractiveQualityDropsAndRestoresAntialiasing() {
        let view = BookPreviewInteractionView()
        view.configureQuality(.high)
        XCTAssertEqual(view.antialiasingMode, .multisampling4X)
        view.setNavigating(true)
        XCTAssertEqual(view.antialiasingMode, .none)
        XCTAssertEqual(view.preferredFramesPerSecond, 30)
        view.configureQuality(.render)
        XCTAssertEqual(view.antialiasingMode, .none)
        view.setNavigating(false)
        XCTAssertEqual(view.antialiasingMode, .multisampling4X)
        view.configureQuality(.balanced)
        XCTAssertEqual(view.antialiasingMode, .multisampling2X)
        view.configureQuality(.fast)
        XCTAssertEqual(view.antialiasingMode, .none)
    }

    func testCameraBoundsSnapshotFramesLikeStableSceneBounds() throws {
        let scene = SCNScene()
        let model = SCNNode(geometry: SCNBox(width: 11.55, height: 7.7, length: 0.9, chamferRadius: 0))
        model.name = BookStudioTransformScene.modelRootName
        model.eulerAngles = SCNVector3(-Double.pi / 2, 0.12, 0.08)
        model.position = SCNVector3(0.2, 0.4, -3.85)
        scene.rootNode.addChildNode(model)
        let snapshot = try XCTUnwrap(BookPreviewCameraMath.BoundsSnapshot.capture(modelRoot: model))
        let state = BookPreviewCameraState(yaw: 0.22, pitch: 0.92, distance: 1)
        let live = BookPreviewCameraMath.fitBook(state, in: scene,
            presentation: BookStudioPresentation(), viewportAspect: 1.5)
        let cached = BookPreviewCameraMath.fitBook(state, bounds: snapshot,
            presentation: BookStudioPresentation(), viewportAspect: 1.5)
        XCTAssertEqual(cached.target.x, live.target.x, accuracy: 0.000_001)
        XCTAssertEqual(cached.target.y, live.target.y, accuracy: 0.000_001)
        XCTAssertEqual(cached.target.z, live.target.z, accuracy: 0.000_001)
        XCTAssertEqual(cached.distance, live.distance, accuracy: 0.000_001)
    }

    func testCameraBoundsSnapshotTracksRootTransformWithoutRescanningGeometry() throws {
        let model = SCNNode(geometry: SCNBox(width: 6, height: 9, length: 0.8, chamferRadius: 0))
        let original = try XCTUnwrap(BookPreviewCameraMath.BoundsSnapshot.capture(modelRoot: model))
        model.position = SCNVector3(2.5, -1.25, 4)
        model.eulerAngles = SCNVector3(0.3, -0.6, 0.2)
        model.scale = SCNVector3(1.5, 0.75, 2)

        let transformedSnapshot = original.applying(model.transform)
        let stableSceneSnapshot = try XCTUnwrap(BookPreviewCameraMath.BoundsSnapshot.capture(modelRoot: model))
        XCTAssertEqual(transformedSnapshot.minimum.x, stableSceneSnapshot.minimum.x, accuracy: 0.000_001)
        XCTAssertEqual(transformedSnapshot.minimum.y, stableSceneSnapshot.minimum.y, accuracy: 0.000_001)
        XCTAssertEqual(transformedSnapshot.minimum.z, stableSceneSnapshot.minimum.z, accuracy: 0.000_001)
        XCTAssertEqual(transformedSnapshot.maximum.x, stableSceneSnapshot.maximum.x, accuracy: 0.000_001)
        XCTAssertEqual(transformedSnapshot.maximum.y, stableSceneSnapshot.maximum.y, accuracy: 0.000_001)
        XCTAssertEqual(transformedSnapshot.maximum.z, stableSceneSnapshot.maximum.z, accuracy: 0.000_001)

        let state = BookPreviewCameraState(yaw: 0.75, pitch: 0.72, distance: 1)
        let cached = BookPreviewCameraMath.frame(transformedSnapshot, from: state,
            fieldOfView: 34, viewportAspect: 1.2)
        let live = BookPreviewCameraMath.frame(model, from: state,
            fieldOfView: 34, viewportAspect: 1.2)
        XCTAssertEqual(cached, live)
    }

    func testCameraBoundsSnapshotRemainsUsableAfterSceneGeometryReplacementAndDisposal() throws {
        var scene: SCNScene? = SCNScene()
        var model: SCNNode? = SCNNode(geometry: SCNBox(width: 6, height: 9, length: 0.8, chamferRadius: 0))
        model?.name = BookStudioTransformScene.modelRootName
        scene?.rootNode.addChildNode(try XCTUnwrap(model))
        let firstSnapshot = try XCTUnwrap(BookPreviewCameraMath.BoundsSnapshot.capture(modelRoot: model))
        let originalWidth = firstSnapshot.maximum.x - firstSnapshot.minimum.x

        // A page transition can update/reassign live geometry. Resize and
        // zoom framing must continue from the immutable scene-generation
        // snapshot, never traversing those renderer-owned nodes again.
        model?.geometry = SCNBox(width: 18, height: 14, length: 3, chamferRadius: 0)
        let state = BookPreviewCameraState(yaw: 0.75, pitch: 0.72, distance: 2)
        let duringTransition = BookPreviewCameraMath.frame(firstSnapshot, from: state,
            fieldOfView: 34, viewportAspect: 1.4)
        XCTAssertEqual(firstSnapshot.maximum.x - firstSnapshot.minimum.x, originalWidth, accuracy: 0.000_001)
        XCTAssertGreaterThan(duringTransition.distance, 0.35)

        // Releasing the old scene must not invalidate the value used by a
        // pending AppKit resize callback.
        scene = nil
        model = nil
        let afterDisposal = BookPreviewCameraMath.frame(firstSnapshot, from: state,
            fieldOfView: 34, viewportAspect: 1.4)
        XCTAssertEqual(afterDisposal, duringTransition)

        let replacementScene = SCNScene()
        let replacementModel = SCNNode(geometry: SCNBox(width: 18, height: 14, length: 3, chamferRadius: 0))
        replacementModel.name = BookStudioTransformScene.modelRootName
        replacementScene.rootNode.addChildNode(replacementModel)
        let replacementSnapshot = try XCTUnwrap(BookPreviewCameraMath.BoundsSnapshot.capture(modelRoot: replacementModel))
        XCTAssertGreaterThan(replacementSnapshot.maximum.x - replacementSnapshot.minimum.x, originalWidth)
        XCTAssertGreaterThan(BookPreviewCameraMath.minimumOrbitDistance(in: replacementSnapshot,
            target: .zero), BookPreviewCameraMath.minimumOrbitDistance(in: firstSnapshot, target: .zero))
    }
}


final class BookStudioTransformPersistenceTests: XCTestCase {
    func testBookModelTransformRoundTripsThroughPresentation() throws {
        var presentation = BookStudioPresentation()
        presentation.transformMode = .rotate
        presentation.transformSpace = .world
        presentation.modelTransform = BookModelTransform(
            positionX: 2.5,
            positionY: -1.25,
            positionZ: 4,
            rotationX: 15,
            rotationY: 45,
            rotationZ: -30,
            scaleX: 1.5,
            scaleY: 0.75,
            scaleZ: 2
        )

        let data = try JSONEncoder().encode(presentation)
        let decoded = try JSONDecoder().decode(
            BookStudioPresentation.self,
            from: data
        )

        XCTAssertEqual(decoded.transformMode, .rotate)
        XCTAssertEqual(decoded.transformSpace, .world)
        XCTAssertEqual(decoded.modelTransform.positionX, 2.5)
        XCTAssertEqual(decoded.modelTransform.positionY, -1.25)
        XCTAssertEqual(decoded.modelTransform.positionZ, 4)
        XCTAssertEqual(decoded.modelTransform.rotationX, 15)
        XCTAssertEqual(decoded.modelTransform.rotationY, 45)
        XCTAssertEqual(decoded.modelTransform.rotationZ, -30)
        XCTAssertEqual(decoded.modelTransform.scaleX, 1.5)
        XCTAssertEqual(decoded.modelTransform.scaleY, 0.75)
        XCTAssertEqual(decoded.modelTransform.scaleZ, 2)
    }

    func testBookModelTransformNormalizesUnsafeValues() {
        let normalized = BookModelTransform(
            positionX: .infinity,
            positionY: -100,
            positionZ: 100,
            rotationX: -1000,
            rotationY: 1000,
            rotationZ: .nan,
            scaleX: 0,
            scaleY: 100,
            scaleZ: .infinity
        ).normalized

        XCTAssertEqual(normalized.positionX, 0)
        XCTAssertEqual(normalized.positionY, -24)
        XCTAssertEqual(normalized.positionZ, 24)
        XCTAssertEqual(normalized.rotationX, -360)
        XCTAssertEqual(normalized.rotationY, 360)
        XCTAssertEqual(normalized.rotationZ, 0)
        XCTAssertEqual(normalized.scaleX, 0.1)
        XCTAssertEqual(normalized.scaleY, 10)
        XCTAssertEqual(normalized.scaleZ, 1)
    }

    func testPresentationNormalizationNormalizesModelTransform() {
        var presentation = BookStudioPresentation()
        presentation.modelTransform = BookModelTransform(
            positionX: 100,
            rotationY: 1000,
            scaleZ: 0
        )

        let normalized = presentation.normalized(pageCount: 100)

        XCTAssertEqual(normalized.modelTransform.positionX, 24)
        XCTAssertEqual(normalized.modelTransform.rotationY, 360)
        XCTAssertEqual(normalized.modelTransform.scaleZ, 0.1)
    }

    func testLegacyPresentationDefaultsTransformState() throws {
        let original = BookStudioPresentation()
        let encoded = try JSONEncoder().encode(original)

        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded)
                as? [String: Any]
        )

        object.removeValue(forKey: "transformMode")
        object.removeValue(forKey: "transformSpace")
        object.removeValue(forKey: "modelTransform")

        let legacy = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )

        let decoded = try JSONDecoder().decode(
            BookStudioPresentation.self,
            from: legacy
        )

        XCTAssertEqual(decoded.transformMode, .navigate)
        XCTAssertEqual(decoded.transformSpace, .local)
        XCTAssertEqual(decoded.modelTransform, .identity)
    }
}


final class BookStudioTransformSceneTests: XCTestCase {
    private func makeScene() -> (SCNScene, SCNNode) {
        let scene = SCNScene()

        let root = SCNNode()
        root.name =
            BookStudioTransformScene.modelRootName

        let geometry = SCNBox(
            width: 2,
            height: 3,
            length: 0.5,
            chamferRadius: 0
        )

        root.addChildNode(
            SCNNode(
                geometry: geometry
            )
        )

        scene.rootNode
            .addChildNode(root)

        return (
            scene,
            root
        )
    }

    func testSceneAdapterAppliesPersistentModelTransform() {
        let (scene, root) =
            makeScene()

        var presentation =
            BookStudioPresentation()

        presentation.modelTransform =
            BookModelTransform(
                positionX: 2,
                positionY: 3,
                positionZ: -4,
                rotationX: 90,
                rotationY: 45,
                rotationZ: -30,
                scaleX: 1.5,
                scaleY: 2,
                scaleZ: 0.5
            )

        BookStudioTransformScene.apply(
            to: scene,
            presentation: presentation
        )

        XCTAssertEqual(
            root.position.x,
            2,
            accuracy: 0.0001
        )

        XCTAssertEqual(
            root.position.y,
            3,
            accuracy: 0.0001
        )

        XCTAssertEqual(
            root.position.z,
            -4,
            accuracy: 0.0001
        )

        XCTAssertEqual(
            root.eulerAngles.x,
            .pi / 2,
            accuracy: 0.0001
        )

        XCTAssertEqual(
            root.eulerAngles.y,
            .pi / 4,
            accuracy: 0.0001
        )

        XCTAssertEqual(
            root.eulerAngles.z,
            -.pi / 6,
            accuracy: 0.0001
        )

        XCTAssertEqual(
            root.scale.x,
            1.5,
            accuracy: 0.0001
        )

        XCTAssertEqual(
            root.scale.y,
            2,
            accuracy: 0.0001
        )

        XCTAssertEqual(
            root.scale.z,
            0.5,
            accuracy: 0.0001
        )
    }

    func testNavigateModeRemovesTransformGizmo() {
        let (scene, _) =
            makeScene()

        var presentation =
            BookStudioPresentation()

        presentation.transformMode =
            .move

        BookStudioTransformScene.apply(
            to: scene,
            presentation: presentation
        )

        XCTAssertNotNil(
            scene.rootNode
                .childNode(
                    withName:
                        BookStudioTransformScene
                        .gizmoRootName,
                    recursively: false
                )
        )

        presentation.transformMode =
            .navigate

        BookStudioTransformScene.apply(
            to: scene,
            presentation: presentation
        )

        XCTAssertNil(
            scene.rootNode
                .childNode(
                    withName:
                        BookStudioTransformScene
                        .gizmoRootName,
                    recursively: false
                )
        )
    }

    func testMoveModeCreatesXYZMoveHandles() {
        let (scene, _) =
            makeScene()

        var presentation =
            BookStudioPresentation()

        presentation.transformMode =
            .move

        BookStudioTransformScene.apply(
            to: scene,
            presentation: presentation
        )

        for axis in [
            "x",
            "y",
            "z"
        ] {
            XCTAssertNotNil(
                scene.rootNode
                    .childNode(
                        withName:
                            "studio-transform-gizmo.move.\(axis).handle",
                        recursively: true
                    )
            )
        }
    }

    func testRotateModeCreatesXYZRotationHandles() {
        let (scene, _) =
            makeScene()

        var presentation =
            BookStudioPresentation()

        presentation.transformMode =
            .rotate

        BookStudioTransformScene.apply(
            to: scene,
            presentation: presentation
        )

        for axis in [
            "x",
            "y",
            "z"
        ] {
            XCTAssertNotNil(
                scene.rootNode
                    .childNode(
                        withName:
                            "studio-transform-gizmo.rotate.\(axis).handle",
                        recursively: true
                    )
            )
        }
    }

    func testScaleModeCreatesXYZScaleHandles() {
        let (scene, _) =
            makeScene()

        var presentation =
            BookStudioPresentation()

        presentation.transformMode =
            .scale

        BookStudioTransformScene.apply(
            to: scene,
            presentation: presentation
        )

        for axis in [
            "x",
            "y",
            "z"
        ] {
            XCTAssertNotNil(
                scene.rootNode
                    .childNode(
                        withName:
                            "studio-transform-gizmo.scale.\(axis).handle",
                        recursively: true
                    )
            )
        }
    }

    func testLocalSpaceUsesModelRotationForGizmo() {
        let (scene, root) =
            makeScene()

        var presentation =
            BookStudioPresentation()

        presentation.transformMode =
            .move

        presentation.transformSpace =
            .local

        presentation
            .modelTransform
            .rotationY =
            45

        BookStudioTransformScene.apply(
            to: scene,
            presentation: presentation
        )

        let gizmo =
            scene.rootNode
                .childNode(
                    withName:
                        BookStudioTransformScene
                        .gizmoRootName,
                    recursively: false
                )

        XCTAssertNotNil(
            gizmo
        )

        XCTAssertEqual(
            gizmo?.eulerAngles.y ?? 0,
            root.eulerAngles.y,
            accuracy: 0.0001
        )
    }

    func testWorldSpaceKeepsGizmoWorldAligned() {
        let (scene, _) =
            makeScene()

        var presentation =
            BookStudioPresentation()

        presentation.transformMode =
            .move

        presentation.transformSpace =
            .world

        presentation
            .modelTransform
            .rotationY =
            45

        BookStudioTransformScene.apply(
            to: scene,
            presentation: presentation
        )

        let gizmo =
            scene.rootNode
                .childNode(
                    withName:
                        BookStudioTransformScene
                        .gizmoRootName,
                    recursively: false
                )

        XCTAssertNotNil(
            gizmo
        )

        XCTAssertEqual(
            gizmo?.eulerAngles.y ?? 0,
            0,
            accuracy: 0.0001
        )
    }
}


final class BookStudioTransformDragMathTests: XCTestCase {
    func testParsesMoveRotateAndScaleGizmoNames() {
        XCTAssertEqual(
            BookTransformGizmoHandle.parse(
                nodeName:
                    "studio-transform-gizmo.move.x.handle"
            ),
            BookTransformGizmoHandle(
                mode: .move,
                axis: .x
            )
        )

        XCTAssertEqual(
            BookTransformGizmoHandle.parse(
                nodeName:
                    "studio-transform-gizmo.rotate.y.handle"
            ),
            BookTransformGizmoHandle(
                mode: .rotate,
                axis: .y
            )
        )

        XCTAssertEqual(
            BookTransformGizmoHandle.parse(
                nodeName:
                    "studio-transform-gizmo.scale.z"
            ),
            BookTransformGizmoHandle(
                mode: .scale,
                axis: .z
            )
        )

        XCTAssertNil(
            BookTransformGizmoHandle.parse(
                nodeName:
                    "physical-book.root"
            )
        )
    }

    func testWorldMoveUpdatesOnlySelectedAxis() {
        let transformed =
            BookStudioTransformDragMath
            .applying(
                .identity,
                mode: .move,
                axis: .x,
                amount: 100,
                space: .world,
                snapping: false
            )

        XCTAssertEqual(
            transformed.positionX,
            1,
            accuracy: 0.0001
        )

        XCTAssertEqual(
            transformed.positionY,
            0,
            accuracy: 0.0001
        )

        XCTAssertEqual(
            transformed.positionZ,
            0,
            accuracy: 0.0001
        )
    }

    func testLocalMoveUsesRotatedAxis() {
        var original =
            BookModelTransform.identity

        original.rotationY =
            90

        let transformed =
            BookStudioTransformDragMath
            .applying(
                original,
                mode: .move,
                axis: .x,
                amount: 100,
                space: .local,
                snapping: false
            )

        XCTAssertEqual(
            transformed.positionX,
            0,
            accuracy: 0.0001
        )

        XCTAssertEqual(
            transformed.positionZ,
            -1,
            accuracy: 0.0001
        )
    }

    func testMoveShiftSnapsToQuarterUnit() {
        let transformed =
            BookStudioTransformDragMath
            .applying(
                .identity,
                mode: .move,
                axis: .y,
                amount: 38,
                space: .world,
                snapping: true
            )

        XCTAssertEqual(
            transformed.positionY,
            0.5,
            accuracy: 0.0001
        )
    }

    func testRotateUsesDegreesAndShiftSnapsToFifteenDegrees() {
        let free =
            BookStudioTransformDragMath
            .applying(
                .identity,
                mode: .rotate,
                axis: .z,
                amount: 22,
                space: .local,
                snapping: false
            )

        XCTAssertEqual(
            free.rotationZ,
            22,
            accuracy: 0.0001
        )

        let snapped =
            BookStudioTransformDragMath
            .applying(
                .identity,
                mode: .rotate,
                axis: .z,
                amount: 22,
                space: .local,
                snapping: true
            )

        XCTAssertEqual(
            snapped.rotationZ,
            15,
            accuracy: 0.0001
        )
    }

    func testScaleDragUpdatesSelectedAxis() {
        let transformed =
            BookStudioTransformDragMath
            .applying(
                .identity,
                mode: .scale,
                axis: .z,
                amount: 50,
                space: .local,
                snapping: false
            )

        XCTAssertEqual(
            transformed.scaleX,
            1,
            accuracy: 0.0001
        )

        XCTAssertEqual(
            transformed.scaleY,
            1,
            accuracy: 0.0001
        )

        XCTAssertEqual(
            transformed.scaleZ,
            1.5,
            accuracy: 0.0001
        )
    }

    func testScaleShiftSnapsToTenth() {
        let transformed =
            BookStudioTransformDragMath
            .applying(
                .identity,
                mode: .scale,
                axis: .x,
                amount: 26,
                space: .local,
                snapping: true
            )

        XCTAssertEqual(
            transformed.scaleX,
            1.3,
            accuracy: 0.0001
        )
    }

    func testNavigateModeLeavesTransformUntouched() {
        var original =
            BookModelTransform.identity

        original.positionX =
            2

        let transformed =
            BookStudioTransformDragMath
            .applying(
                original,
                mode: .navigate,
                axis: .x,
                amount: 500,
                space: .world,
                snapping: false
            )

        XCTAssertEqual(
            transformed,
            original
        )
    }

    func testDragMathStillUsesTransformSafetyClamps() {
        var original =
            BookModelTransform.identity

        original.scaleX =
            9.9

        let transformed =
            BookStudioTransformDragMath
            .applying(
                original,
                mode: .scale,
                axis: .x,
                amount: 1000,
                space: .local,
                snapping: false
            )

        XCTAssertEqual(
            transformed.scaleX,
            10,
            accuracy: 0.0001
        )
    }
}


final class BookStudioTransformAffordanceTests: XCTestCase {
    func testUniformScaleHandleParses() {
        XCTAssertEqual(
            BookTransformGizmoHandle.parse(
                nodeName:
                    "studio-transform-gizmo.scale.uniform.handle"
            ),
            BookTransformGizmoHandle(
                mode: .scale,
                axis: .uniform
            )
        )
    }

    func testUniformScaleChangesAllAxes() {
        let transformed =
            BookStudioTransformDragMath
            .applying(
                .identity,
                mode: .scale,
                axis: .uniform,
                amount: 50,
                space: .local,
                snapping: false
            )

        XCTAssertEqual(
            transformed.scaleX,
            1.5,
            accuracy: 0.0001
        )

        XCTAssertEqual(
            transformed.scaleY,
            1.5,
            accuracy: 0.0001
        )

        XCTAssertEqual(
            transformed.scaleZ,
            1.5,
            accuracy: 0.0001
        )
    }

    func testCustomMoveSnapStepIsUsed() {
        let transformed =
            BookStudioTransformDragMath
            .applying(
                .identity,
                mode: .move,
                axis: .x,
                amount: 74,
                space: .world,
                snapping: true,
                moveSnapStep: 0.5
            )

        XCTAssertEqual(
            transformed.positionX,
            0.5,
            accuracy: 0.0001
        )
    }

    func testCustomRotationSnapStepIsUsed() {
        let transformed =
            BookStudioTransformDragMath
            .applying(
                .identity,
                mode: .rotate,
                axis: .y,
                amount: 28,
                space: .local,
                snapping: true,
                rotateSnapStep: 10
            )

        XCTAssertEqual(
            transformed.rotationY,
            30,
            accuracy: 0.0001
        )
    }

    func testCustomScaleSnapStepIsUsed() {
        let transformed =
            BookStudioTransformDragMath
            .applying(
                .identity,
                mode: .scale,
                axis: .uniform,
                amount: 37,
                space: .local,
                snapping: true,
                scaleSnapStep: 0.25
            )

        XCTAssertEqual(
            transformed.scaleX,
            1.25,
            accuracy: 0.0001
        )

        XCTAssertEqual(
            transformed.scaleY,
            1.25,
            accuracy: 0.0001
        )

        XCTAssertEqual(
            transformed.scaleZ,
            1.25,
            accuracy: 0.0001
        )
    }

    func testSnapSettingsRoundTripThroughPresentation() throws {
        var presentation =
            BookStudioPresentation()

        presentation.transformSnapEnabled =
            true

        presentation.moveSnapStep =
            0.5

        presentation.rotateSnapStep =
            30

        presentation.scaleSnapStep =
            0.25

        let data =
            try JSONEncoder()
            .encode(
                presentation
            )

        let decoded =
            try JSONDecoder()
            .decode(
                BookStudioPresentation.self,
                from: data
            )

        XCTAssertTrue(
            decoded.transformSnapEnabled
        )

        XCTAssertEqual(
            decoded.moveSnapStep,
            0.5,
            accuracy: 0.0001
        )

        XCTAssertEqual(
            decoded.rotateSnapStep,
            30,
            accuracy: 0.0001
        )

        XCTAssertEqual(
            decoded.scaleSnapStep,
            0.25,
            accuracy: 0.0001
        )
    }

    func testSnapSettingsNormalizeUnsafeValues() {
        var presentation =
            BookStudioPresentation()

        presentation.moveSnapStep =
            .nan

        presentation.rotateSnapStep =
            1000

        presentation.scaleSnapStep =
            0

        let normalized =
            presentation.normalized(
                pageCount: 100
            )

        XCTAssertEqual(
            normalized.moveSnapStep,
            0.25,
            accuracy: 0.0001
        )

        XCTAssertEqual(
            normalized.rotateSnapStep,
            180,
            accuracy: 0.0001
        )

        XCTAssertEqual(
            normalized.scaleSnapStep,
            0.01,
            accuracy: 0.0001
        )
    }

    func testScaleModeCreatesUniformHandle() {
        let scene =
            SCNScene()

        let root =
            SCNNode()

        root.name =
            BookStudioTransformScene
            .modelRootName

        root.addChildNode(
            SCNNode(
                geometry:
                    SCNBox(
                        width: 2,
                        height: 3,
                        length: 1,
                        chamferRadius: 0
                    )
            )
        )

        scene.rootNode
            .addChildNode(root)

        var presentation =
            BookStudioPresentation()

        presentation.transformMode =
            .scale

        BookStudioTransformScene.apply(
            to: scene,
            presentation: presentation
        )

        XCTAssertNotNil(
            scene.rootNode
                .childNode(
                    withName:
                        "studio-transform-gizmo.scale.uniform.handle",
                    recursively: true
                )
        )
    }
}


final class BookStudioCustomLightTests: XCTestCase {
    func testCustomLightsRoundTripThroughPresentation() throws {
        var presentation =
            BookStudioPresentation()

        var point =
            BookStudioLight.point(
                name:
                    "Accent Point"
            )

        point.intensity =
            1_250

        point.colorHex =
            "#FF8040"

        point.range =
            18

        point.transform.positionX =
            2

        var spot =
            BookStudioLight.spot(
                name:
                    "Cover Spot"
            )

        spot.spotInnerAngle =
            20

        spot.spotOuterAngle =
            48

        spot.transform.rotationY =
            35

        presentation.customLights = [
            point,
            spot
        ]

        let data =
            try JSONEncoder()
            .encode(
                presentation
            )

        let decoded =
            try JSONDecoder()
            .decode(
                BookStudioPresentation.self,
                from: data
            )

        XCTAssertEqual(
            decoded.customLights.count,
            2
        )

        XCTAssertEqual(
            decoded.customLights[0].name,
            "Accent Point"
        )

        XCTAssertEqual(
            decoded.customLights[0].type,
            .point
        )

        XCTAssertEqual(
            decoded.customLights[0].intensity,
            1_250,
            accuracy: 0.0001
        )

        XCTAssertEqual(
            decoded.customLights[0].colorHex,
            "#FF8040"
        )

        XCTAssertEqual(
            decoded.customLights[1].type,
            .spot
        )

        XCTAssertEqual(
            decoded.customLights[1].spotOuterAngle,
            48,
            accuracy: 0.0001
        )
    }

    func testCustomLightNormalizationClampsUnsafeValues() {
        var light =
            BookStudioLight.point()

        light.name =
            "   "

        light.intensity =
            .infinity

        light.range =
            0

        light.colorHex =
            "not-a-color"

        light.spotInnerAngle =
            200

        light.spotOuterAngle =
            300

        light.transform.positionX =
            100

        let normalized =
            light.normalized

        XCTAssertEqual(
            normalized.name,
            "Point Light"
        )

        XCTAssertEqual(
            normalized.intensity,
            800,
            accuracy: 0.0001
        )

        XCTAssertEqual(
            normalized.range,
            0.1,
            accuracy: 0.0001
        )

        XCTAssertEqual(
            normalized.colorHex,
            "#FFFFFF"
        )

        XCTAssertEqual(
            normalized.spotOuterAngle,
            179,
            accuracy: 0.0001
        )

        XCTAssertEqual(
            normalized.spotInnerAngle,
            179,
            accuracy: 0.0001
        )

        XCTAssertEqual(
            normalized.transform.positionX,
            24,
            accuracy: 0.0001
        )
    }

    func testPointLightCreatesSceneKitOmniNode() {
        let scene =
            SCNScene()

        var presentation =
            BookStudioPresentation()

        var light =
            BookStudioLight.point(
                name:
                    "Point"
            )

        light.intensity =
            1_400

        light.range =
            22

        light.transform.positionX =
            1.5

        light.transform.positionY =
            2.25

        presentation.customLights = [
            light
        ]

        BookStudioCustomLightScene.apply(
            to: scene,
            presentation: presentation
        )

        let node =
            BookStudioCustomLightScene
            .lightNode(
                in: scene,
                id: light.id
            )

        XCTAssertNotNil(node)

        XCTAssertEqual(
            node?.light?.type,
            .omni
        )

        XCTAssertEqual(
            node?.light?.intensity
                ?? 0,
            1_400,
            accuracy: 0.0001
        )

        XCTAssertEqual(
            node?.light?
                .attenuationEndDistance
                ?? 0,
            22,
            accuracy: 0.0001
        )

        XCTAssertEqual(
            node?.position.x
                ?? 0,
            1.5,
            accuracy: 0.0001
        )

        XCTAssertEqual(
            node?.position.y
                ?? 0,
            2.25,
            accuracy: 0.0001
        )
    }

    func testSpotLightCreatesSceneKitSpotNode() {
        let scene =
            SCNScene()

        var presentation =
            BookStudioPresentation()

        var light =
            BookStudioLight.spot(
                name:
                    "Spot"
            )

        light.spotInnerAngle =
            18

        light.spotOuterAngle =
            44

        light.castsShadow =
            true

        presentation.customLights = [
            light
        ]

        BookStudioCustomLightScene.apply(
            to: scene,
            presentation: presentation
        )

        let node =
            BookStudioCustomLightScene
            .lightNode(
                in: scene,
                id: light.id
            )

        XCTAssertEqual(
            node?.light?.type,
            .spot
        )

        XCTAssertEqual(
            node?.light?.spotInnerAngle
                ?? 0,
            18,
            accuracy: 0.0001
        )

        XCTAssertEqual(
            node?.light?.spotOuterAngle
                ?? 0,
            44,
            accuracy: 0.0001
        )

        XCTAssertEqual(
            node?.light?.castsShadow,
            true
        )

        XCTAssertNotNil(
            node?
                .childNode(
                    withName:
                        BookStudioCustomLightScene
                        .gizmoName(
                            for: light.id
                        ),
                    recursively: false
                )
        )
    }

    func testDisabledCustomLightHasZeroIntensityAndHiddenGizmo() {
        let scene =
            SCNScene()

        var presentation =
            BookStudioPresentation()

        var light =
            BookStudioLight.point()

        light.enabled =
            false

        light.intensity =
            2_000

        presentation.customLights = [
            light
        ]

        BookStudioCustomLightScene.apply(
            to: scene,
            presentation: presentation
        )

        let node =
            BookStudioCustomLightScene
            .lightNode(
                in: scene,
                id: light.id
            )

        XCTAssertEqual(
            node?.light?.intensity
                ?? -1,
            0,
            accuracy: 0.0001
        )

        XCTAssertEqual(
            node?
                .childNode(
                    withName:
                        BookStudioCustomLightScene
                        .gizmoName(
                            for: light.id
                        ),
                    recursively: false
                )?
                .isHidden,
            true
        )
    }

    func testRemovingCustomLightRemovesStaleSceneNode() {
        let scene =
            SCNScene()

        var presentation =
            BookStudioPresentation()

        let light =
            BookStudioLight.point()

        presentation.customLights = [
            light
        ]

        BookStudioCustomLightScene.apply(
            to: scene,
            presentation: presentation
        )

        XCTAssertNotNil(
            BookStudioCustomLightScene
                .lightNode(
                    in: scene,
                    id: light.id
                )
        )

        presentation.customLights =
            []

        BookStudioCustomLightScene.apply(
            to: scene,
            presentation: presentation
        )

        XCTAssertNil(
            BookStudioCustomLightScene
                .lightNode(
                    in: scene,
                    id: light.id
                )
        )
    }

    func testPresentationNormalizationNormalizesCustomLights() {
        var presentation =
            BookStudioPresentation()

        var light =
            BookStudioLight.point()

        light.range =
            500

        light.intensity =
            50_000

        presentation.customLights = [
            light
        ]

        let normalized =
            presentation.normalized(
                pageCount: 100
            )

        XCTAssertEqual(
            normalized.customLights[0].range,
            100,
            accuracy: 0.0001
        )

        XCTAssertEqual(
            normalized.customLights[0].intensity,
            10_000,
            accuracy: 0.0001
        )
    }
}


final class BookStudioLightViewportTransformTests: XCTestCase {
    private func makeScene()
        -> (SCNScene, SCNNode)
    {
        let scene =
            SCNScene()

        let bookRoot =
            SCNNode()

        bookRoot.name =
            BookStudioTransformScene
            .modelRootName

        bookRoot.addChildNode(
            SCNNode(
                geometry:
                    SCNBox(
                        width: 2,
                        height: 3,
                        length: 0.5,
                        chamferRadius: 0
                    )
            )
        )

        scene.rootNode
            .addChildNode(
                bookRoot
            )

        return (
            scene,
            bookRoot
        )
    }

    func testCustomLightIDParsesNodeAndMarkerNames() {
        let id =
            UUID()

        XCTAssertEqual(
            BookStudioCustomLightScene
                .lightID(
                    fromNodeName:
                        BookStudioCustomLightScene
                        .nodeName(
                            for: id
                        )
                ),
            id
        )

        XCTAssertEqual(
            BookStudioCustomLightScene
                .lightID(
                    fromNodeName:
                        BookStudioCustomLightScene
                        .gizmoName(
                            for: id
                        )
                ),
            id
        )

        XCTAssertNil(
            BookStudioCustomLightScene
                .lightID(
                    fromNodeName:
                        "studio-custom-light-spot-direction"
                )
        )
    }

    func testSelectedLightGetsMoveTransformGizmo() {
        let (scene, _) =
            makeScene()

        var presentation =
            BookStudioPresentation()

        var light =
            BookStudioLight.point()

        light.transform.positionX =
            2

        light.transform.positionY =
            3

        presentation.customLights = [
            light
        ]

        presentation.transformMode =
            .move

        BookStudioCustomLightScene.apply(
            to: scene,
            presentation: presentation
        )

        BookStudioTransformScene.apply(
            to: scene,
            presentation: presentation,
            selectedCustomLightID:
                light.id
        )

        let gizmo =
            scene.rootNode
            .childNode(
                withName:
                    BookStudioTransformScene
                    .gizmoRootName,
                recursively: false
            )

        XCTAssertNotNil(
            gizmo
        )

        XCTAssertEqual(
            gizmo?.position.x
                ?? 0,
            2,
            accuracy: 0.001
        )

        XCTAssertEqual(
            gizmo?.position.y
                ?? 0,
            3,
            accuracy: 0.001
        )

        XCTAssertNotNil(
            gizmo?
                .childNode(
                    withName:
                        "studio-transform-gizmo.move.x.handle",
                    recursively: true
                )
        )
    }

    func testSelectedLightGetsRotateTransformGizmo() {
        let (scene, _) =
            makeScene()

        var presentation =
            BookStudioPresentation()

        let light =
            BookStudioLight.spot()

        presentation.customLights = [
            light
        ]

        presentation.transformMode =
            .rotate

        BookStudioCustomLightScene.apply(
            to: scene,
            presentation: presentation
        )

        BookStudioTransformScene.apply(
            to: scene,
            presentation: presentation,
            selectedCustomLightID:
                light.id
        )

        XCTAssertNotNil(
            scene.rootNode
                .childNode(
                    withName:
                        "studio-transform-gizmo.rotate.y.handle",
                    recursively: true
                )
        )
    }

    func testScaleModeIsIgnoredForSelectedLight() {
        let (scene, _) =
            makeScene()

        var presentation =
            BookStudioPresentation()

        let light =
            BookStudioLight.point()

        presentation.customLights = [
            light
        ]

        presentation.transformMode =
            .scale

        BookStudioCustomLightScene.apply(
            to: scene,
            presentation: presentation
        )

        BookStudioTransformScene.apply(
            to: scene,
            presentation: presentation,
            selectedCustomLightID:
                light.id
        )

        XCTAssertNil(
            scene.rootNode
                .childNode(
                    withName:
                        BookStudioTransformScene
                        .gizmoRootName,
                    recursively: false
                )
        )
    }

    func testBookTransformStillAppliesWhileLightIsSelected() {
        let (scene, bookRoot) =
            makeScene()

        var presentation =
            BookStudioPresentation()

        presentation.modelTransform
            .positionX =
            4

        let light =
            BookStudioLight.point()

        presentation.customLights = [
            light
        ]

        presentation.transformMode =
            .move

        BookStudioCustomLightScene.apply(
            to: scene,
            presentation: presentation
        )

        BookStudioTransformScene.apply(
            to: scene,
            presentation: presentation,
            selectedCustomLightID:
                light.id
        )

        XCTAssertEqual(
            bookRoot.position.x,
            4,
            accuracy: 0.001
        )
    }

    func testLightMarkerSelectedHighlightChangesScale() {
        let (scene, _) =
            makeScene()

        var presentation =
            BookStudioPresentation()

        let light =
            BookStudioLight.point()

        presentation.customLights = [
            light
        ]

        BookStudioCustomLightScene.apply(
            to: scene,
            presentation: presentation
        )

        BookStudioCustomLightScene
            .updateMarkerHighlight(
                in: scene,
                hovered: nil,
                selected:
                    light.id
            )

        let marker =
            scene.rootNode
                .childNode(
                    withName:
                        BookStudioCustomLightScene
                        .gizmoName(
                            for: light.id
                        ),
                    recursively: true
                )

        XCTAssertNotNil(
            marker
        )

        XCTAssertEqual(
            marker?.scale.x
                ?? 0,
            1.45,
            accuracy: 0.001
        )
    }
}


final class BookStudioSceneEditorObjectTests: XCTestCase {
    private func makeBookScene() -> SCNScene {
        let scene = SCNScene()

        let root = SCNNode()
        root.name = BookStudioTransformScene.modelRootName

        root.addChildNode(
            SCNNode(
                geometry:
                    SCNBox(
                        width: 2,
                        height: 3,
                        length: 0.5,
                        chamferRadius: 0
                    )
            )
        )

        scene.rootNode.addChildNode(root)
        return scene
    }

    func testLightEditorVisibilityAndLockRoundTrip() throws {
        var presentation =
            BookStudioPresentation()

        var light =
            BookStudioLight.point()

        light.editorVisible = false
        light.locked = true

        presentation.customLights = [
            light
        ]

        let decoded =
            try JSONDecoder()
            .decode(
                BookStudioPresentation.self,
                from:
                    JSONEncoder()
                    .encode(
                        presentation
                    )
            )

        XCTAssertFalse(
            decoded.customLights[0].editorVisible
        )

        XCTAssertTrue(
            decoded.customLights[0].locked
        )
    }

    func testLegacyLightDefaultsEditorState() throws {
        let source =
            BookStudioLight.point()

        var object =
            try XCTUnwrap(
                JSONSerialization
                .jsonObject(
                    with:
                        JSONEncoder()
                        .encode(
                            source
                        )
                )
                as? [String: Any]
            )

        object.removeValue(
            forKey:
                "editorVisible"
        )

        object.removeValue(
            forKey:
                "locked"
        )

        let decoded =
            try JSONDecoder()
            .decode(
                BookStudioLight.self,
                from:
                    JSONSerialization
                    .data(
                        withJSONObject:
                            object
                    )
            )

        XCTAssertTrue(
            decoded.editorVisible
        )

        XCTAssertFalse(
            decoded.locked
        )
    }

    func testCameraAndGuideSettingsPersist() throws {
        var presentation =
            BookStudioPresentation()

        presentation.cameraEditorVisible =
            false

        presentation.cameraEditorLocked =
            true

        presentation.lightGuidesVisible =
            false

        let decoded =
            try JSONDecoder()
            .decode(
                BookStudioPresentation.self,
                from:
                    JSONEncoder()
                    .encode(
                        presentation
                    )
            )

        XCTAssertFalse(
            decoded.cameraEditorVisible
        )

        XCTAssertTrue(
            decoded.cameraEditorLocked
        )

        XCTAssertFalse(
            decoded.lightGuidesVisible
        )
    }

    func testSelectedPointLightCreatesRangeGuide() {
        let scene =
            makeBookScene()

        var presentation =
            BookStudioPresentation()

        let light =
            BookStudioLight.point()

        presentation.customLights = [
            light
        ]

        BookStudioCustomLightScene.apply(
            to: scene,
            presentation: presentation,
            selectedCustomLightID:
                light.id
        )

        XCTAssertNotNil(
            BookStudioCustomLightScene
                .lightNode(
                    in: scene,
                    id:
                        light.id
                )?
                .childNode(
                    withName:
                        "studio-custom-light-guide.range",
                    recursively:
                        false
                )
        )
    }

    func testSelectedSpotLightCreatesConeGuides() {
        let scene =
            makeBookScene()

        var presentation =
            BookStudioPresentation()

        let light =
            BookStudioLight.spot()

        presentation.customLights = [
            light
        ]

        BookStudioCustomLightScene.apply(
            to: scene,
            presentation: presentation,
            selectedCustomLightID:
                light.id
        )

        let node =
            BookStudioCustomLightScene
            .lightNode(
                in: scene,
                id:
                    light.id
            )

        XCTAssertNotNil(
            node?
                .childNode(
                    withName:
                        "studio-custom-light-guide.spot.outer",
                    recursively:
                        false
                )
        )

        XCTAssertNotNil(
            node?
                .childNode(
                    withName:
                        "studio-custom-light-guide.spot.inner",
                    recursively:
                        false
                )
        )
    }

    func testLockedLightDoesNotCreateTransformGizmo() {
        let scene =
            makeBookScene()

        var presentation =
            BookStudioPresentation()

        var light =
            BookStudioLight.point()

        light.locked = true

        presentation.customLights = [
            light
        ]

        presentation.transformMode =
            .move

        BookStudioCustomLightScene.apply(
            to: scene,
            presentation: presentation,
            selectedCustomLightID:
                light.id
        )

        BookStudioTransformScene.apply(
            to: scene,
            presentation: presentation,
            selectedCustomLightID:
                light.id
        )

        XCTAssertNil(
            scene.rootNode
                .childNode(
                    withName:
                        BookStudioTransformScene
                        .gizmoRootName,
                    recursively:
                        false
                )
        )
    }

    func testDisabledLightStillHidesMarker() {
        let scene =
            makeBookScene()

        var presentation =
            BookStudioPresentation()

        var light =
            BookStudioLight.point()

        light.enabled = false
        light.editorVisible = true

        presentation.customLights = [
            light
        ]

        BookStudioCustomLightScene.apply(
            to: scene,
            presentation: presentation
        )

        let marker =
            BookStudioCustomLightScene
            .lightNode(
                in: scene,
                id:
                    light.id
            )?
            .childNode(
                withName:
                    BookStudioCustomLightScene
                    .gizmoName(
                        for:
                            light.id
                    ),
                recursively:
                    false
            )

        XCTAssertEqual(
            marker?.isHidden,
            true
        )
    }

    func testEditorHiddenLightHidesMarker() {
        let scene =
            makeBookScene()

        var presentation =
            BookStudioPresentation()

        var light =
            BookStudioLight.point()

        light.editorVisible = false

        presentation.customLights = [
            light
        ]

        BookStudioCustomLightScene.apply(
            to: scene,
            presentation: presentation
        )

        let marker =
            BookStudioCustomLightScene
            .lightNode(
                in: scene,
                id:
                    light.id
            )?
            .childNode(
                withName:
                    BookStudioCustomLightScene
                    .gizmoName(
                        for:
                            light.id
                    ),
                recursively:
                    false
            )

        XCTAssertEqual(
            marker?.isHidden,
            true
        )
    }

    func testDisabledSelectedLightDoesNotCreateGuide() {
        let scene =
            makeBookScene()

        var presentation =
            BookStudioPresentation()

        var light =
            BookStudioLight.point()

        light.enabled = false

        presentation.customLights = [
            light
        ]

        BookStudioCustomLightScene.apply(
            to: scene,
            presentation: presentation,
            selectedCustomLightID:
                light.id
        )

        XCTAssertNil(
            BookStudioCustomLightScene
                .lightNode(
                    in: scene,
                    id:
                        light.id
                )?
                .childNode(
                    withName:
                        "studio-custom-light-guide.range",
                    recursively:
                        false
                )
        )
    }

    func testCameraGuideCreatesCameraAndTargetObjects() {
        let scene =
            makeBookScene()

        let state =
            BookPreviewCameraState(
                yaw: 0,
                pitch: 0,
                distance: 5,
                target:
                    SIMD3<Double>(
                        1,
                        2,
                        3
                    )
            )

        BookStudioCameraGuideScene.apply(
            to: scene,
            state: state,
            visible: true,
            selected: true
        )

        let root =
            scene.rootNode
                .childNode(
                    withName:
                        BookStudioCameraGuideScene
                        .rootName,
                    recursively:
                        false
                )

        XCTAssertNotNil(
            root
        )

        let camera =
            root?
                .childNode(
                    withName:
                        BookStudioCameraGuideScene
                        .cameraName,
                    recursively:
                        false
                )

        XCTAssertNotNil(
            camera
        )

        XCTAssertEqual(
            camera?.position.x ?? 0,
            1,
            accuracy:
                0.001
        )

        XCTAssertEqual(
            camera?.position.y ?? 0,
            2,
            accuracy:
                0.001
        )

        XCTAssertEqual(
            camera?.position.z ?? 0,
            8,
            accuracy:
                0.001
        )

        XCTAssertNotNil(
            root?
                .childNode(
                    withName:
                        BookStudioCameraGuideScene
                        .targetName,
                    recursively:
                        false
                )
        )
    }

    func testHiddenCameraGuideIsRemoved() {
        let scene =
            makeBookScene()

        let state =
            BookPreviewCameraState(
                yaw: 0,
                pitch: 0,
                distance: 5
            )

        BookStudioCameraGuideScene.apply(
            to: scene,
            state: state,
            visible: true,
            selected: false
        )

        BookStudioCameraGuideScene.apply(
            to: scene,
            state: state,
            visible: false,
            selected: false
        )

        XCTAssertNil(
            scene.rootNode
                .childNode(
                    withName:
                        BookStudioCameraGuideScene
                        .rootName,
                    recursively:
                        false
                )
        )
    }
}


final class BookStudioHierarchyOutlinerTests: XCTestCase {
    private func makeScene() -> SCNScene {
        let scene =
            SCNScene()

        let book =
            SCNNode()

        book.name =
            BookStudioTransformScene
            .modelRootName

        book.addChildNode(
            SCNNode(
                geometry:
                    SCNBox(
                        width: 2,
                        height: 3,
                        length: 0.5,
                        chamferRadius: 0
                    )
            )
        )

        scene.rootNode
            .addChildNode(
                book
            )

        let ground =
            SCNNode(
                geometry:
                    SCNPlane(
                        width: 10,
                        height: 10
                    )
            )

        ground.name =
            "studio-ground"

        scene.rootNode
            .addChildNode(
                ground
            )

        return scene
    }

    func testHierarchyEditorStateRoundTrips() throws {
        var presentation =
            BookStudioPresentation()

        presentation.bookEditorVisible =
            false

        presentation.bookTransformLocked =
            true

        presentation.groundEditorVisible =
            false

        presentation.groundEditorLocked =
            true

        presentation.outlinerBookExpanded =
            false

        presentation.outlinerEnvironmentExpanded =
            false

        presentation.outlinerLightingExpanded =
            false

        presentation.outlinerCameraExpanded =
            false

        let decoded =
            try JSONDecoder()
            .decode(
                BookStudioPresentation.self,
                from:
                    JSONEncoder()
                    .encode(
                        presentation
                    )
            )

        XCTAssertFalse(
            decoded.bookEditorVisible
        )

        XCTAssertTrue(
            decoded.bookTransformLocked
        )

        XCTAssertFalse(
            decoded.groundEditorVisible
        )

        XCTAssertTrue(
            decoded.groundEditorLocked
        )

        XCTAssertFalse(
            decoded.outlinerBookExpanded
        )

        XCTAssertFalse(
            decoded.outlinerEnvironmentExpanded
        )

        XCTAssertFalse(
            decoded.outlinerLightingExpanded
        )

        XCTAssertFalse(
            decoded.outlinerCameraExpanded
        )
    }

    func testLegacyPresentationDefaultsHierarchyEditorState() throws {
        let source =
            BookStudioPresentation()

        var object =
            try XCTUnwrap(
                JSONSerialization
                .jsonObject(
                    with:
                        JSONEncoder()
                        .encode(
                            source
                        )
                )
                as? [String: Any]
            )

        [
            "bookEditorVisible",
            "bookTransformLocked",
            "groundEditorVisible",
            "groundEditorLocked",
            "outlinerBookExpanded",
            "outlinerEnvironmentExpanded",
            "outlinerLightingExpanded",
            "outlinerCameraExpanded"
        ]
        .forEach {
            object.removeValue(
                forKey:
                    $0
            )
        }

        let decoded =
            try JSONDecoder()
            .decode(
                BookStudioPresentation.self,
                from:
                    JSONSerialization
                    .data(
                        withJSONObject:
                            object
                    )
            )

        XCTAssertTrue(
            decoded.bookEditorVisible
        )

        XCTAssertFalse(
            decoded.bookTransformLocked
        )

        XCTAssertTrue(
            decoded.groundEditorVisible
        )

        XCTAssertFalse(
            decoded.groundEditorLocked
        )

        XCTAssertTrue(
            decoded.outlinerBookExpanded
        )

        XCTAssertTrue(
            decoded.outlinerEnvironmentExpanded
        )

        XCTAssertTrue(
            decoded.outlinerLightingExpanded
        )

        XCTAssertTrue(
            decoded.outlinerCameraExpanded
        )
    }

    func testLightOrderMovesStableUUIDObjects() {
        var first =
            BookStudioLight.point()

        first.name =
            "First"

        var second =
            BookStudioLight.point()

        second.name =
            "Second"

        var third =
            BookStudioLight.spot()

        third.name =
            "Third"

        let reordered =
            BookStudioLightOrder
            .moved(
                [
                    first,
                    second,
                    third
                ],
                id:
                    second.id,
                offset:
                    1
            )

        XCTAssertEqual(
            reordered.map(
                \.id
            ),
            [
                first.id,
                third.id,
                second.id
            ]
        )
    }

    func testLightOrderRefusesOutOfBoundsMove() {
        let first =
            BookStudioLight.point()

        let second =
            BookStudioLight.point()

        let original = [
            first,
            second
        ]

        XCTAssertEqual(
            BookStudioLightOrder
                .moved(
                    original,
                    id:
                        first.id,
                    offset:
                        -1
                ),
            original
        )

        XCTAssertFalse(
            BookStudioLightOrder
                .canMove(
                    original,
                    id:
                        first.id,
                    offset:
                        -1
                )
        )
    }

    func testBookLockSuppressesTransformGizmo() {
        let scene =
            makeScene()

        var presentation =
            BookStudioPresentation()

        presentation.transformMode =
            .move

        presentation.bookTransformLocked =
            true

        BookStudioTransformScene.apply(
            to: scene,
            presentation:
                presentation
        )

        XCTAssertNil(
            scene.rootNode
                .childNode(
                    withName:
                        BookStudioTransformScene
                        .gizmoRootName,
                    recursively:
                        false
                )
        )
    }

    func testUnlockedBookStillCreatesTransformGizmo() {
        let scene =
            makeScene()

        var presentation =
            BookStudioPresentation()

        presentation.transformMode =
            .move

        presentation.bookTransformLocked =
            false

        BookStudioTransformScene.apply(
            to: scene,
            presentation:
                presentation
        )

        XCTAssertNotNil(
            scene.rootNode
                .childNode(
                    withName:
                        BookStudioTransformScene
                        .gizmoRootName,
                    recursively:
                        false
                )
        )
    }
}


final class BookStudioAnimationFoundationTests: XCTestCase {
    private func camera(
        yaw: Double,
        pitch: Double = 0,
        distance: Double = 5,
        targetX: Double = 0,
        targetY: Double = 0,
        targetZ: Double = 0
    ) -> BookSavedCamera {
        BookSavedCamera(
            yaw:
                yaw,
            pitch:
                pitch,
            distance:
                distance,
            targetX:
                targetX,
            targetY:
                targetY,
            targetZ:
                targetZ
        )
    }

    func testAnimationSettingsRoundTrip() throws {
        var presentation =
            BookStudioPresentation()

        presentation.animationDuration =
            12.5

        presentation.animationFPS =
            24

        presentation.animationLoop =
            false

        presentation.animationPlayhead =
            3.25

        presentation.turntableEnabled =
            true

        presentation.turntableTurns =
            2.5

        presentation.turntableClockwise =
            false

        presentation.cameraKeyframes = [
            BookStudioCameraKeyframe(
                time:
                    0,
                camera:
                    camera(
                        yaw:
                            0
                    )
            ),
            BookStudioCameraKeyframe(
                time:
                    12.5,
                camera:
                    camera(
                        yaw:
                            .pi
                    )
            )
        ]

        let decoded =
            try JSONDecoder()
            .decode(
                BookStudioPresentation.self,
                from:
                    JSONEncoder()
                    .encode(
                        presentation
                    )
            )

        XCTAssertEqual(
            decoded.animationDuration,
            12.5,
            accuracy:
                0.0001
        )

        XCTAssertEqual(
            decoded.animationFPS,
            24
        )

        XCTAssertFalse(
            decoded.animationLoop
        )

        XCTAssertEqual(
            decoded.animationPlayhead,
            3.25,
            accuracy:
                0.0001
        )

        XCTAssertTrue(
            decoded.turntableEnabled
        )

        XCTAssertEqual(
            decoded.turntableTurns,
            2.5,
            accuracy:
                0.0001
        )

        XCTAssertFalse(
            decoded.turntableClockwise
        )

        XCTAssertEqual(
            decoded.cameraKeyframes.count,
            2
        )
    }

    func testLegacyPresentationDefaultsAnimationState() throws {
        let source =
            BookStudioPresentation()

        var object =
            try XCTUnwrap(
                JSONSerialization
                .jsonObject(
                    with:
                        JSONEncoder()
                        .encode(
                            source
                        )
                )
                as? [String: Any]
            )

        [
            "animationDuration",
            "animationFPS",
            "animationLoop",
            "animationPlayhead",
            "turntableEnabled",
            "turntableTurns",
            "turntableClockwise",
            "cameraKeyframes"
        ]
        .forEach {
            object.removeValue(
                forKey:
                    $0
            )
        }

        let decoded =
            try JSONDecoder()
            .decode(
                BookStudioPresentation.self,
                from:
                    JSONSerialization
                    .data(
                        withJSONObject:
                            object
                    )
            )

        XCTAssertEqual(
            decoded.animationDuration,
            6,
            accuracy:
                0.0001
        )

        XCTAssertEqual(
            decoded.animationFPS,
            30
        )

        XCTAssertTrue(
            decoded.animationLoop
        )

        XCTAssertEqual(
            decoded.animationPlayhead,
            0,
            accuracy:
                0.0001
        )

        XCTAssertFalse(
            decoded.turntableEnabled
        )

        XCTAssertEqual(
            decoded.turntableTurns,
            1,
            accuracy:
                0.0001
        )

        XCTAssertTrue(
            decoded.turntableClockwise
        )

        XCTAssertTrue(
            decoded.cameraKeyframes
                .isEmpty
        )
    }

    func testCameraInterpolationIsLinearForPositionPitchAndDistance() {
        let start =
            camera(
                yaw:
                    0,
                pitch:
                    0.2,
                distance:
                    4,
                targetX:
                    1,
                targetY:
                    2,
                targetZ:
                    3
            )

        let end =
            camera(
                yaw:
                    1,
                pitch:
                    0.6,
                distance:
                    8,
                targetX:
                    5,
                targetY:
                    6,
                targetZ:
                    7
            )

        let result =
            BookStudioAnimationMath
            .interpolate(
                from:
                    start,
                to:
                    end,
                amount:
                    0.5
            )

        XCTAssertEqual(
            result.pitch,
            0.4,
            accuracy:
                0.0001
        )

        XCTAssertEqual(
            result.distance,
            6,
            accuracy:
                0.0001
        )

        XCTAssertEqual(
            result.targetX,
            3,
            accuracy:
                0.0001
        )

        XCTAssertEqual(
            result.targetY,
            4,
            accuracy:
                0.0001
        )

        XCTAssertEqual(
            result.targetZ,
            5,
            accuracy:
                0.0001
        )
    }

    func testYawInterpolationUsesShortestPath() {
        let degrees =
            Double.pi
            / 180

        let start =
            camera(
                yaw:
                    170
                    * degrees
            )

        let end =
            camera(
                yaw:
                    -170
                    * degrees
            )

        let result =
            BookStudioAnimationMath
            .interpolate(
                from:
                    start,
                to:
                    end,
                amount:
                    0.5
            )

        XCTAssertEqual(
            abs(
                result.yaw
            ),
            .pi,
            accuracy:
                0.0001
        )
    }

    func testCameraTimelineClampsBeforeAndAfterKeyframes() {
        let first =
            camera(
                yaw:
                    0,
                distance:
                    4
            )

        let last =
            camera(
                yaw:
                    1,
                distance:
                    8
            )

        let keyframes = [
            BookStudioCameraKeyframe(
                time:
                    2,
                camera:
                    first
            ),
            BookStudioCameraKeyframe(
                time:
                    4,
                camera:
                    last
            )
        ]

        XCTAssertEqual(
            BookStudioAnimationMath
                .camera(
                    at:
                        0,
                    keyframes:
                        keyframes,
                    duration:
                        6
                ),
            first
        )

        XCTAssertEqual(
            BookStudioAnimationMath
                .camera(
                    at:
                        6,
                    keyframes:
                        keyframes,
                    duration:
                        6
                ),
            last
        )
    }

    func testTurntableTransformLeavesStoredBaseUntouched() {
        let base =
            BookModelTransform(
                positionX:
                    1,
                rotationY:
                    15,
                scaleX:
                    1.2,
                scaleY:
                    1.2,
                scaleZ:
                    1.2
            )

        let animated =
            BookStudioAnimationMath
            .turntableTransform(
                base:
                    base,
                time:
                    1.5,
                duration:
                    6,
                enabled:
                    true,
                turns:
                    1,
                clockwise:
                    true
            )

        XCTAssertEqual(
            base.rotationY,
            15,
            accuracy:
                0.0001
        )

        XCTAssertEqual(
            animated.rotationY,
            105,
            accuracy:
                0.0001
        )

        XCTAssertEqual(
            animated.positionX,
            1,
            accuracy:
                0.0001
        )
    }

    func testFramePlanMapsIndexDirectlyToTime() {
        XCTAssertEqual(
            BookStudioAnimationMath
                .frameCount(
                    duration:
                        2,
                    fps:
                        10
                ),
            21
        )

        XCTAssertEqual(
            BookStudioAnimationMath
                .time(
                    forFrame:
                        0,
                    duration:
                        2,
                    fps:
                        10
                ),
            0,
            accuracy:
                0.0001
        )

        XCTAssertEqual(
            BookStudioAnimationMath
                .time(
                    forFrame:
                        10,
                    duration:
                        2,
                    fps:
                        10
                ),
            1,
            accuracy:
                0.0001
        )

        XCTAssertEqual(
            BookStudioAnimationMath
                .time(
                    forFrame:
                        20,
                    duration:
                        2,
                    fps:
                        10
                ),
            2,
            accuracy:
                0.0001
        )
    }

    func testCameraKeyframeOrderSwapsTimelineTimesButKeepsUUIDs() throws {
        let first =
            BookStudioCameraKeyframe(
                time:
                    0,
                camera:
                    camera(
                        yaw:
                            0
                    )
            )

        let second =
            BookStudioCameraKeyframe(
                time:
                    2,
                camera:
                    camera(
                        yaw:
                            1
                    )
            )

        let third =
            BookStudioCameraKeyframe(
                time:
                    4,
                camera:
                    camera(
                        yaw:
                            2
                    )
            )

        let moved =
            BookStudioCameraKeyframeOrder
            .moved(
                [
                    first,
                    second,
                    third
                ],
                id:
                    second.id,
                offset:
                    1
            )

        XCTAssertEqual(
            Set(
                moved.map(
                    \.id
                )
            ),
            Set(
                [
                    first.id,
                    second.id,
                    third.id
                ]
            )
        )

        let movedSecond =
            try XCTUnwrap(
                moved.first {
                    $0.id
                    == second.id
                }
            )

        XCTAssertEqual(
            movedSecond.time,
            4,
            accuracy:
                0.0001
        )
    }
}


final class BookStudioAnimationExportPlanTests:
    XCTestCase
{
    func testPNGSequenceUsesDeterministicFrameCount() {
        let plan =
            BookStudioAnimationExportPlan(
                duration:
                    2,
                fps:
                    10
            )

        XCTAssertEqual(
            plan.frameCount,
            21
        )

        XCTAssertEqual(
            plan.time(
                forFrame:
                    10
            ),
            1,
            accuracy:
                0.0001
        )

        XCTAssertEqual(
            plan.time(
                forFrame:
                    20
            ),
            2,
            accuracy:
                0.0001
        )
    }

    func testPNGFrameNamesAreOneBasedAndZeroPadded() {
        let plan =
            BookStudioAnimationExportPlan(
                duration:
                    2,
                fps:
                    10
            )

        XCTAssertEqual(
            plan.pngFileName(
                forFrame:
                    0
            ),
            "frame-000001.png"
        )

        XCTAssertEqual(
            plan.pngFileName(
                forFrame:
                    20
            ),
            "frame-000021.png"
        )
    }

    func testGIFDelayIsExactInverseOfFPS() {
        let plan =
            BookStudioAnimationExportPlan(
                duration:
                    3,
                fps:
                    24
            )

        XCTAssertEqual(
            plan.gifFrameDelay,
            1.0 / 24.0,
            accuracy:
                0.000_000_1
        )
    }

    func testExportPlanClampsUnsafeFPSAndDuration() {
        let plan =
            BookStudioAnimationExportPlan(
                duration:
                    0,
                fps:
                    0
            )

        XCTAssertEqual(
            plan.duration,
            0.25,
            accuracy:
                0.0001
        )

        XCTAssertEqual(
            plan.fps,
            1
        )

        XCTAssertEqual(
            plan.frameCount,
            BookStudioAnimationMath
                .frameCount(
                    duration:
                        0.25,
                    fps:
                        1
                )
        )
    }

    func testAnimationExportFormatsRemainStable() {
        XCTAssertEqual(
            BookStudioAnimationExportFormat
                .pngSequence
                .rawValue,
            "PNG Sequence"
        )

        XCTAssertEqual(
            BookStudioAnimationExportFormat
                .gif
                .rawValue,
            "Animated GIF"
        )

        XCTAssertEqual(
            BookStudioAnimationExportFormat
                .allCases
                .count,
            2
        )
    }
}
