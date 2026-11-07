# 3D Book Studio architecture

## Existing foundation at 9bbd71f

- `PhysicalBookPreview` owns transient preview state and derives the selected print-wrap `CoverProject` from document metadata. `PDFExporter` paginates the real manuscript, then `PDFPage` supplies the visible spread textures and diagnostics.
- `PhysicalBookGeometry` maps trim, spine, binding thickness, page stacks, recto/verso spreads, and gutter coordinates. The common gutter is X=0.
- `PhysicalBookCoverTextures` renders the production cover path and crops real front, back, and spine art. At the starting HEAD, `BookPreviewScene` cached these results by project and document revision.
- `BookPreviewScene.make` builds one SceneKit scene with stable names for covers, spine, page blocks, active pages, camera, lights, and ground. It already uses physically based materials, a flexible paperback cover, hardcover joints, curved active pages, and a page-turn leaf.
- `BookPreviewSceneView` bridges SwiftUI to `SCNView`. Its existing interaction is drag orbit, scroll zoom, and fixed camera focus presets. It rebuilds the scene when SwiftUI updates.
- `PhysicalBookPreview` caches visible PDF page images plus a few recent images, but `renderPages` currently rasterizes visible pages synchronously.

## Studio extension

- Keep the existing renderer and real publishing inputs. Add one small presentation model for material, paper, environment, lighting, camera projection, render quality, and selected component.
- Presentation choices change only visualization. Production cover artwork, PDF export, manuscript text, and trim geometry remain authoritative.
- Keep presentation and committed camera pose in optional native metadata. Selection remains transient. Old documents decode without the new key, and omitted future presentation fields receive defaults.
- The central viewport, compact scene tree, and right inspector share the same presentation state. Scene node names map to selectable logical components.
- `SCNView` and `SCNRenderer` render the same scene state for interactive preview and still-image export. Quality presets control antialiasing and render size; no second 3D engine is introduced.
- `BookPageTextureCache` keeps a bounded, source-scoped set of rasterized manuscript pages with a pixel-quality level. Visible pages get a quick raster, then a worker opens its own PDF document for a sharper raster. Neighboring pages preload. A source UUID rejects stale work after manuscript regeneration.
- Diagnostic page marks now have a small identity-preserving cache, so an unrelated inspector update does not recreate the page texture or invalidate the live scene.
- The cover cache now compares the actual `CoverProject` before reuse. Manuscript-only revisions retain cover textures, while changed art invalidates them.
- `BookSceneSourceKey` distinguishes geometry/artwork/page changes from presentation changes. The SwiftUI bridge reuses its `SCNScene` for material, light, camera, and selection edits; source changes still rebuild it. Exploded positioning and selection outlines are reversible when styling the live scene.
- Still-image export can isolate the book on transparent PNG, accepts validated custom sizes up to 24 megapixels, and temporarily substitutes a 360 DPI production-path cover raster for sharper artwork. The interactive art and scene background are restored after rendering.
- Mockup export temporarily collapses the exploded inspection pose, hides diagnostic nodes, and uses the print-result cover texture even when the viewport shows working layers. None of those temporary changes persist in the live scene.
- Double-clicking a named physical component frames its transformed bounds. Pan distance follows the selected camera field of view.
- Six small procedural cube maps now add broad softbox reflections to physically based cover materials. They are generated locally and cached by environment preset; no third-party HDR assets are bundled.
- During orbit, pan, scroll, or pinch, the viewport temporarily uses the fast antialiasing/frame-rate setting and restores the selected quality at the end of navigation. Export remains at four-sample antialiasing.

## Milestone limits

- SceneKit's existing page-turn leaf remains the intermediate animation; full deforming-paper simulation and accurate collision across every open angle need a substantially more complex constrained mesh.
- The environment presets use procedural studio cube maps and native lights. Photographic HDR panoramas remain deferred until licensed assets and color-management validation are available.
- Transparent exports hide the studio surface and background for the snapshot, then restore the live scene. Alpha is tested at an empty corner; a full edge-fringe/color-management comparison across GPUs remains unmeasured.
- Cover artwork export is capped at a 360 DPI temporary texture to bound memory. A very large custom output can still upscale that texture.
- USD/OBJ/DAE props and decals are deferred because their presentation-only document ownership, sandbox access, and lifetime need a separate import design. They are not necessary to inspect the production book.
- Generic CAD modeling, cloud publishing, collaboration, ecommerce, AR/VR, and a no-code interaction builder do not serve the native book inspection milestone.

## Reference limits

The local Vectary audit records the public Studio page, not its authenticated editor. Camera, material, environment, and scene-panel behavior here follows book visualization needs and SceneKit capabilities, not claims about Vectary internals. SceneKit supports a node hierarchy, physically based materials and lighting environments, perspective/orthographic cameras, and view snapshots; see [SceneKit](https://developer.apple.com/documentation/scenekit), [SCNCamera](https://developer.apple.com/documentation/scenekit/scncamera), and [SCNView.snapshot](https://developer.apple.com/documentation/scenekit/scnview/snapshot()).
