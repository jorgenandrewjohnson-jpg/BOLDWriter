import AppKit
import XCTest
@testable import BOLDWriter

final class CoverArtworkEdgeOrientationTests: XCTestCase {
    func testBleedWarningsIdentifyActualTopAndBottomArtworkEdges() throws {
        for edge in [PhysicalBookCoverEdge.top, .bottom] {
            var project = CoverProject(type: .printFullWrap, width: 13.25, height: 9.25)
            project.trimWidth = 6; project.backWidth = 6; project.trimHeight = 9
            project.spineWidth = 1; project.bleed = 0.125; project.dpi = 72
            project.backgroundHex = "#2468AC"
            // Only one edge has missing bleed. Symmetric fixtures cannot detect
            // diagnostics that confuse the top and bottom of the raster.
            let bleed = project.bleed / project.canvasHeight
            var strip = CoverLayer(kind: .shape, name: "Missing bleed",
                frame: CoverRect(x: 0, y: edge == .top ? 0 : 1 - bleed,
                                 width: 1, height: bleed))
            strip.fillHex = "#FFFFFF"; strip.strokeWidth = 0
            project.layers = [strip]
            let textures = PhysicalBookCoverTextures(project: project, workingLayers: false, previewDPI: 36)
            XCTAssertEqual(textures.edgeIssues.count, 2)
            for panel in [PhysicalBookCoverPanel.front, .back] {
                XCTAssertEqual(textures.edgeIssues.filter { $0.panel == panel }.map(\.edge), [edge])
            }
        }
    }
}
