import AppKit
import SceneKit
import XCTest
@testable import BOLDWriter

/// Tests the printed pixels after the production materials and camera have
/// rendered them, rather than inferring artwork orientation from UV arrays.
@MainActor
final class BookArtworkProjectionTests: XCTestCase {
    private let colors = ["#FF0000", "#00FF00", "#0000FF", "#FFFF00"]

    private func fixture(hardcover: Bool) -> CoverProject {
        var p = CoverProject(type: .printFullWrap, width: 13.25, height: 9.25)
        p.trimWidth = 6; p.backWidth = 6; p.trimHeight = 9
        p.spineWidth = 1; p.bleed = 0.125; p.dpi = 72
        if hardcover {
            // Use the measured case layout, not a paperback wrap with its
            // binding flag changed. This fixture is entirely synthetic.
            p.canvasWidth = 19.469; p.canvasHeight = 12.417
            p.trimWidth = 8.25; p.backWidth = 8.25; p.trimHeight = 11
            p.spineWidth = 1.394; p.bleed = 0
            p.kdpHardcoverLayout = KDPHardcoverLayout(canvasWidth: 19.469,
                canvasHeight: 12.417, trimWidth: 8.25, trimHeight: 11,
                spineWidth: 1.394, pageCount: 535)
        }
        p.productionBinding = hardcover ? .hardcover : .softcover
        let g = CoverWrapGeometry(project: p)
        for (panel, region) in [g.frontTrim, g.backTrim, g.spineTrim].enumerated() {
            for corner in 0..<4 {
                var layer = CoverLayer(kind: .shape, name: "Panel \(panel) corner \(corner)",
                    frame: CoverRect(x: region.x + Double(corner % 2) * region.width / 2,
                                     y: region.y + Double(corner / 2) * region.height / 2,
                                     width: region.width / 2, height: region.height / 2))
                layer.fillHex = colors[(corner + panel) % 4]
                layer.strokeWidth = 0
                p.layers.append(layer)
            }
        }
        return p
    }

    private func colorIndex(_ color: NSColor) -> Int? {
        guard let c = color.usingColorSpace(.deviceRGB) else { return nil }
        let r = c.redComponent, g = c.greenComponent, b = c.blueComponent
        if r > 0.25 && g < r * 0.4 && b < r * 0.4 { return 0 }
        if g > 0.25 && r < g * 0.4 && b < g * 0.4 { return 1 }
        if b > 0.25 && r < b * 0.4 && g < b * 0.4 { return 2 }
        if min(r, g) > 0.25 && b < min(r, g) * 0.4 { return 3 }
        return nil
    }

    func testRenderedFrontBackAndSpineKeepDistinctCornerOrientation() throws {
        for hardcover in [false, true] {
            let project = fixture(hardcover: hardcover)
            let binding: BookBinding = hardcover ? .hardcover : .softcover
            for (panel, preset) in [BookViewPreset.front, .back, .spine].enumerated() {
                let scene = BookPreviewScene.make(project: project, workingLayers: false,
                    open: false, angle: 0, leftPage: nil, rightPage: 1,
                    pageCount: 535, spreadIndex: 0, leftTexture: nil, rightTexture: nil,
                    margins: false, thumbMode: .off, leftPageSettings: PageSettings(),
                    rightPageSettings: PageSettings(), preset: preset,
                    revisionID: UUID(), binding: binding)
                let view = BookPreviewInteractionView(frame: NSRect(x: 0, y: 0, width: 640, height: 640))
                view.scene = scene
                view.cameraNode = scene.rootNode.childNode(withName: "preview-camera", recursively: true)
                let state = BookPreviewCameraMath.state(project: project, open: false,
                                                       preset: preset, focus: .automatic)
                view.setCamera(state)
                view.configureCamera(state, projection: .perspective)
                SCNTransaction.flush()
                let renderer = SCNRenderer(device: nil, options: nil)
                renderer.scene = scene; renderer.pointOfView = view.cameraNode
                let image = renderer.snapshot(atTime: 0, with: CGSize(width: 640, height: 640),
                                              antialiasingMode: .multisampling4X)
                let bitmap = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
                if let directory = ProcessInfo.processInfo.environment["BOLD_ARTWORK_PROOF_DIR"] {
                    let url = URL(fileURLWithPath: directory)
                    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                    try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                        .write(to: url.appendingPathComponent("\(binding)-\(preset).png"))
                }
                var sums = [(Double, Double, Int)](repeating: (0, 0, 0), count: 4)
                for y in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
                    for x in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
                        if let c = bitmap.colorAt(x: x, y: y), let i = colorIndex(c) {
                            sums[i].0 += Double(x); sums[i].1 += Double(y); sums[i].2 += 1
                        }
                    }
                }
                let label = "\(binding) \(preset)"
                let centers = try (0..<4).map { corner -> CGPoint in
                    let s = sums[(corner + panel) % 4]
                    XCTAssertGreaterThan(s.2, 20, "Missing corner \(corner): \(label)")
                    guard s.2 > 0 else { throw NSError(domain: label, code: corner) }
                    return CGPoint(x: s.0 / Double(s.2), y: s.1 / Double(s.2))
                }
                XCTAssertLessThan(centers[0].x, centers[1].x, label)
                XCTAssertLessThan(centers[2].x, centers[3].x, label)
                XCTAssertLessThan(centers[0].y, centers[2].y, label)
                XCTAssertLessThan(centers[1].y, centers[3].y, label)
            }
        }
    }

}
