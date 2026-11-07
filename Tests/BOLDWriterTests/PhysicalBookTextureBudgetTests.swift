import AppKit
import XCTest
@testable import BOLDWriter

final class PhysicalBookTextureBudgetTests: XCTestCase {
    private func project() -> CoverProject {
        var project = CoverProject(type:.printFullWrap,width:13.25,height:9.25)
        project.trimWidth = 6; project.backWidth = 6; project.trimHeight = 9
        project.spineWidth = 1; project.bleed = 0.125
        for (name,frame,color) in [
            ("Back",CoverRect(x:0,y:0,width:0.47,height:1),"#CC2233"),
            ("Front",CoverRect(x:0.55,y:0,width:0.45,height:1),"#22BB44"),
            ("Top stripe",CoverRect(x:0,y:0,width:1,height:0.25),"#2233DD")
        ] {
            var layer = CoverLayer(kind:.shape,name:name,frame:frame)
            layer.fillHex = color; layer.strokeWidth = 0; project.layers.append(layer)
        }
        return project
    }

    func testAuditDimensionsPreserveDPIAndPanelsShareBoundedScale() throws {
        var project = CoverProject(width:2804.0/144,height:1788.0/144); project.dpi = 144
        let plan = try XCTUnwrap(PhysicalBookCoverTextures.renderPlan(project:project,previewDPI:240))
        XCTAssertEqual(plan.panelDPI,240)
        XCTAssertEqual(plan.sourceDPI,240)
        project.canvasWidth = 100; project.canvasHeight = 100; project.dpi = 2400
        let large = try XCTUnwrap(PhysicalBookCoverTextures.renderPlan(project:project,previewDPI:360))
        let width = ceil(project.canvasWidth * large.sourceDPI)
        let height = ceil(project.canvasHeight * large.sourceDPI)
        XCTAssertLessThanOrEqual(width*height,16_000_000)
        XCTAssertLessThanOrEqual(large.panelDPI,large.sourceDPI)
        project.canvasHeight = 1
        let wide = try XCTUnwrap(PhysicalBookCoverTextures.renderPlan(project:project,previewDPI:360))
        XCTAssertLessThanOrEqual(ceil(project.canvasWidth*wide.sourceDPI),8192)
    }

    func testInvalidResolutionReturnsNoTexturesWithoutAllocating() {
        let project = project()
        for dpi in [Double.nan,Double.infinity,0,-1] {
            XCTAssertNil(PhysicalBookCoverTextures.renderPlan(project:project,previewDPI:dpi))
            let textures = PhysicalBookCoverTextures(project:project,workingLayers:false,previewDPI:dpi)
            XCTAssertNil(textures.front); XCTAssertNil(textures.spine); XCTAssertNil(textures.back)
            XCTAssertEqual(textures.estimatedMemoryCost,0)
            XCTAssertFalse(textures.edgeWarnings.isEmpty)
        }
    }

    func testSharedRasterCropsMatchExistingMappingAndCostActualBytes() throws {
        let project = project(), dpi = 24.0
        let textures = PhysicalBookCoverTextures(project:project,workingLayers:false,previewDPI:dpi)
        let plan = try XCTUnwrap(PhysicalBookCoverTextures.renderPlan(project:project,previewDPI:dpi))
        let source = try CoverArtwork.render(project,scale:plan.sourceDPI)
        let tiff = try XCTUnwrap(source.tiffRepresentation)
        let sourceCG = try XCTUnwrap(NSBitmapImageRep(data:tiff)?.cgImage)
        let geometry = CoverWrapGeometry(project:project)
        var cost = 0
        for (image,region) in [(textures.front,geometry.frontTrim),(textures.spine,geometry.spineTrim),(textures.back,geometry.backTrim)] {
            let image = try XCTUnwrap(image)
            let cg = try XCTUnwrap(image.cgImage(forProposedRect:nil,context:nil,hints:nil))
            XCTAssertEqual(cg.width,Int((region.width*project.canvasWidth*dpi).rounded()))
            XCTAssertEqual(cg.height,Int((region.height*project.canvasHeight*dpi).rounded()))
            cost += cg.bytesPerRow*cg.height
            let rect = CGRect(x:region.x*Double(sourceCG.width),y:(1-region.y-region.height)*Double(sourceCG.height),
                              width:region.width*Double(sourceCG.width),height:region.height*Double(sourceCG.height)).integral
            let cropped = try XCTUnwrap(sourceCG.cropping(to:rect))
            let context = try XCTUnwrap(CGContext(data:nil,width:cg.width,height:cg.height,bitsPerComponent:8,bytesPerRow:0,
                space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
            context.interpolationQuality = .high
            context.draw(cropped,in:CGRect(x:0,y:0,width:cg.width,height:cg.height))
            let expected = try XCTUnwrap(context.makeImage())
            XCTAssertEqual(cg.dataProvider?.data as Data?,expected.dataProvider?.data as Data?)
        }
        XCTAssertEqual(textures.estimatedMemoryCost,cost)
    }

    func testLayerCommandRebuildsFrontTextureAndPreservesBack() throws {
        var project = project()
        let before = PhysicalBookCoverTextures(project:project,workingLayers:false,previewDPI:24)
        try CoverLayerCommands.update(&project,arguments:["layerID":project.layers[1].id.uuidString,"visible":"false"])
        let after = PhysicalBookCoverTextures(project:project,workingLayers:false,previewDPI:24)
        XCTAssertNotEqual(before.front?.tiffRepresentation,after.front?.tiffRepresentation)
        XCTAssertEqual(before.back?.tiffRepresentation,after.back?.tiffRepresentation)
    }

    func testPanelCropsKeepTopAndBottomOrientationMarkersInTheCorrectCorners() throws {
        var project = CoverProject(type: .printFullWrap, width: 3.2, height: 1.2)
        project.trimWidth = 1; project.backWidth = 1; project.trimHeight = 1
        project.spineWidth = 1; project.bleed = 0.1; project.dpi = 72
        let front = CoverWrapGeometry(project: project).frontTrim
        func marker(_ name: String, x: Double, y: Double, color: String) -> CoverLayer {
            var layer = CoverLayer(kind: .shape, name: name,
                frame: CoverRect(x: front.x + x * front.width,
                                 y: front.y + y * front.height,
                                 width: 0.18 * front.width,
                                 height: 0.18 * front.height))
            layer.fillHex = color; layer.strokeWidth = 0
            return layer
        }
        // Distinct corner colors make a vertical flip or wrong panel crop
        // visible even when the panel-center color is otherwise uniform.
        project.layers = [
            marker("top-left", x: 0.04, y: 0.04, color: "#FF0000"),
            marker("bottom-left", x: 0.04, y: 0.78, color: "#00FF00"),
            marker("top-right", x: 0.78, y: 0.04, color: "#0000FF"),
            marker("bottom-right", x: 0.78, y: 0.78, color: "#FFFF00")
        ]

        let texture = try XCTUnwrap(
            PhysicalBookCoverTextures(project: project, workingLayers: false, previewDPI: 72).front
        )
        let bitmap = try XCTUnwrap(texture.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        func color(_ x: Int, _ y: Int) throws -> NSColor {
            try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
        }
        let insetX = max(1, bitmap.pixelsWide / 10)
        let insetY = max(1, bitmap.pixelsHigh / 10)
        XCTAssertGreaterThan(try color(insetX, insetY).redComponent, 0.8, "top-left marker")
        XCTAssertGreaterThan(try color(insetX, bitmap.pixelsHigh - insetY).greenComponent, 0.8, "bottom-left marker")
        XCTAssertGreaterThan(try color(bitmap.pixelsWide - insetX, insetY).blueComponent, 0.8, "top-right marker")
        XCTAssertGreaterThan(try color(bitmap.pixelsWide - insetX, bitmap.pixelsHigh - insetY).redComponent, 0.8, "bottom-right marker")
    }
}
