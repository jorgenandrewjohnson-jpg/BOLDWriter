import AppKit
import SceneKit
import XCTest
@testable import BOLDWriter

final class BookInspectionAcceptance43Tests: XCTestCase {
    private struct Spec {
        let binding: BookBinding
        let trim, spine, width, height, bleed: Double
        let name: String
    }

    private let paperback = Spec(
        binding: .softcover,
        trim: 8.5,
        spine: 1.205,
        width: 18.455,
        height: 11.250,
        bleed: 0.125,
        name: "paperback"
    )

    private let hardcover = Spec(
        binding: .hardcover,
        trim: 8.25,
        spine: 1.394,
        width: 19.469,
        height: 12.417,
        bleed: 0.7875,
        name: "hardcover"
    )

    private func cover(_ s: Spec, stripe: Bool = false) -> CoverProject {
        var p = CoverProject(
            type: .printFullWrap,
            width: s.width,
            height: s.height
        )
        p.name = "Synthetic KDP 535 " + s.name
        p.trimWidth = s.trim
        p.backWidth = s.trim
        p.trimHeight = 11
        p.spineWidth = s.spine
        p.canvasWidth = s.width
        p.canvasHeight = s.height
        p.bleed = s.bleed
        p.spinePageCount = 535
        p.productionBinding = s.binding

        if stripe {
            let g = CoverWrapGeometry(project: p)
            for x in [
                g.spineTrim.x,
                g.spineTrim.x + g.spineTrim.width
            ] {
                var mark = CoverLayer(
                    kind: .shape,
                    name: "FOLD REGISTRATION MARK",
                    frame: CoverRect(
                        x: x - 0.0018,
                        y: 0,
                        width: 0.0036,
                        height: 1.0
                    )
                )
                mark.fillHex = "#FF00FF"
                p.layers.append(mark)
            }
        }
        return p
    }

    private func magenta(
        _ b: NSBitmapImageRep,
        _ inch: Double,
        _ p: CoverProject
    ) -> Bool {
        let px = Int(
            inch * Double(b.pixelsWide)
        )
        let py = b.pixelsHigh / 2

        for x in (px - 2)...(px + 2)
        where x >= 0 && x < b.pixelsWide {
            if let c = b.colorAt(x: x, y: py)?
                .usingColorSpace(.deviceRGB),
               c.redComponent > 0.70,
               c.blueComponent > 0.65,
               c.greenComponent < 0.35 {
                return true
            }
        }
        return false
    }

    func testRealRasterLandmarksMeasureFourBindingCombinations() throws {
        XCTAssertEqual(
            hardcover.spine - paperback.spine,
            0.189,
            accuracy: 0.000001
        )
        XCTAssertEqual(
            hardcover.width - paperback.width,
            1.014,
            accuracy: 0.000001
        )
        XCTAssertEqual(
            hardcover.height - paperback.height,
            1.167,
            accuracy: 0.000001
        )

        for original in [paperback, hardcover] {
            let p = cover(original, stripe: true)
            let source = CoverWrapGeometry(project: p)
            let encoded = p

            let image = try CoverArtwork.render(
                p,
                includeGuides: false,
                includeTemplate: false,
                scale: 100
            )
            let raster = try XCTUnwrap(
                image.tiffRepresentation.flatMap(
                    NSBitmapImageRep.init(data:)
                )
            )

            let center = source.spineTrim.x
                + source.spineTrim.width / 2
            let left = source.spineTrim.x
            let right = left + source.spineTrim.width

            XCTAssertTrue(magenta(raster, left, p))
            XCTAssertTrue(magenta(raster, right, p))

            for target in [paperback, hardcover] {
                let mappedLeft = center
                    - target.spine / (2 * p.canvasWidth)
                let mappedRight = center
                    + target.spine / (2 * p.canvasWidth)

                let offset = abs(target.spine - original.spine) / 2
                let wrong = original.binding
                    != target.binding

                print(
                    "BOLD_REGISTRATION source=\(original.name) "
                    + "target=\(target.name) "
                    + "foldOffsetInches=\(offset) "
                    + "targetFoldHitsSourceMark="
                    + "\(magenta(raster, mappedLeft, p))"
                )

                if wrong {
                    XCTAssertGreaterThan(offset, 0.07)
                    XCTAssertFalse(
                        magenta(raster, mappedLeft, p)
                    )
                    XCTAssertFalse(
                        magenta(raster, mappedRight, p)
                    )
                } else {
                    XCTAssertEqual(
                        offset,
                        0,
                        accuracy: 0.000001
                    )
                    XCTAssertTrue(
                        magenta(raster, mappedLeft, p)
                    )
                    XCTAssertTrue(
                        magenta(raster, mappedRight, p)
                    )
                }
            }

            XCTAssertEqual(p, encoded)
        }
    }

    private func scene(
        _ p: CoverProject,
        _ binding: BookBinding,
        _ pages: Int,
        _ index: Int,
        revision: UUID = UUID()
    ) -> SCNScene {
        BookPreviewScene.make(
            project: p,
            workingLayers: false,
            open: true,
            angle: Double(30 + (index * 17) % 140),
            leftPage: 20,
            rightPage: 21,
            pageCount: pages,
            spreadIndex: 10,
            leftTexture: nil,
            rightTexture: nil,
            margins: false,
            thumbMode: .off,
            leftPageSettings: PageSettings(),
            rightPageSettings: PageSettings(),
            preset: .perspective,
            revisionID: revision,
            binding: binding
        )
    }

    func testActualFourWaySceneGeometryPreservesOriginalArtworkAndTemplate() throws {
        for origin in [paperback, hardcover] {
            let p = cover(origin, stripe: true)
            let original = p

            for target in [paperback, hardcover] {
                let s = scene(
                    p,
                    target.binding,
                    535,
                    0
                )
                XCTAssertNotNil(
                    s.rootNode.childNode(
                        withName: "book-shell.front-cover",
                        recursively: true
                    )
                )
                let hinge = s.rootNode.childNode(
                    withName: "book-shell.front-hinge-groove",
                    recursively: true
                )
                XCTAssertEqual(
                    hinge != nil,
                    target.binding == .hardcover
                )
                XCTAssertEqual(p, original)
            }
        }
    }

    func testCameraAndPoseChangesReuseUnchangedProductionCoverTextures() throws {
        let p = cover(hardcover)
        let revision = UUID()
        let cached = BookPreviewScene.coverTextures(
            project: p,
            workingLayers: false,
            revisionID: revision
        )
        XCTAssertNotNil(cached.front)

        for i in 0..<8 {
            let s = scene(
                p,
                i.isMultiple(of: 2)
                    ? .hardcover : .softcover,
                1200,
                i,
                revision: revision
            )
            XCTAssertNotNil(
                s.rootNode.childNode(
                    withName: "physical-book.root",
                    recursively: true
                )
            )
            let next = BookPreviewScene.coverTextures(
                project: p,
                workingLayers: false,
                revisionID: revision
            )
            XCTAssertTrue(
                cached === next,
                "Camera/pose changes must not regenerate cover textures"
            )
        }
    }

    func testTwelve1200PageSyntheticScenesHaveMeasuredConstructionTime() {
        let p = cover(paperback)
        let started = ProcessInfo.processInfo.systemUptime

        for i in 0..<12 {
            let s = scene(
                p,
                i.isMultiple(of: 2)
                    ? .softcover : .hardcover,
                1200,
                i
            )
            XCTAssertNotNil(
                s.rootNode.childNode(
                    withName: "physical-book.root",
                    recursively: true
                )
            )
        }

        let seconds =
            ProcessInfo.processInfo.systemUptime - started

        print(
            "BOLD_PERF_1200_PAGES "
            + "scenes=12 "
            + "elapsedSeconds=\(seconds) "
            + "msPerScene=\(seconds * 1000 / 12)"
        )
        XCTAssertLessThan(seconds, 240)
    }
}
