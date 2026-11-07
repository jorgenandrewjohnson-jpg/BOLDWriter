import AppKit
import XCTest
@testable import BOLDWriter

final class CoverWorkspaceLayoutTests: XCTestCase {
    func testToolGroupsContainEveryImplementedToolExactlyOnce() {
        let tools = CoverEditorTool.toolbarGroups.flatMap { $0 }
        XCTAssertEqual(Set(tools), Set(CoverEditorTool.allCases.filter(\.isImplemented)))
        XCTAssertEqual(tools.count, Set(tools).count)
        XCTAssertTrue(CoverEditorTool.toolbarGroups.contains([.rectangle, .ellipse]))
        XCTAssertTrue(CoverEditorTool.toolbarGroups.contains([.clone, .heal]))
        XCTAssertTrue(tools.contains(.pen))
        XCTAssertTrue(tools.contains(.path))
        XCTAssertTrue(CoverEditorTool.toolbarGroups.contains([.pen, .path]))
    }

    func testContextualOptionsMatchActiveTool() {
        for tool in [CoverEditorTool.rectangle, .ellipse, .lasso, .wand] {
            XCTAssertEqual(tool.options, .selection)
        }
        for tool in [CoverEditorTool.brush, .eraser, .clone, .heal, .dodge, .burn] {
            XCTAssertEqual(tool.options, .paint)
        }
        XCTAssertEqual(CoverEditorTool.move.options, .move)
        XCTAssertEqual(CoverEditorTool.crop.options, .crop)
        XCTAssertEqual(CoverEditorTool.rotateView.options, .navigation)
        XCTAssertEqual(CoverEditorTool.eyedropper.options, .color)
        for tool in [CoverEditorTool.gradient, .type, .shape] {
            XCTAssertEqual(tool.options, .color)
        }
    }

    func testPanelVisibilityAndPropertiesContextAreSessionOnly() throws {
        var project = CoverProject()
        var layer = CoverLayer(kind:.image,name:"Artwork",frame:CoverRect(x:0.1,y:0.2,width:0.7,height:0.6))
        layer.rotation = 12
        layer.maskData = Data([0,255])
        project.layers = [layer]
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let original = try encoder.encode(project)
        var workspace = CoverWorkspaceState()
        XCTAssertTrue(workspace.toolbar && workspace.rightDock && workspace.hasPanels)
        XCTAssertTrue(workspace.paths)
        XCTAssertEqual(workspace.propertiesTarget(layer:nil,maskSelected:true), .document)
        XCTAssertEqual(workspace.propertiesTarget(layer:layer,maskSelected:false), .layer)
        XCTAssertEqual(workspace.propertiesTarget(layer:layer,maskSelected:true), .mask)
        workspace.rightDock = false
        workspace.layers = false
        workspace.paths = false
        workspace.properties = false
        workspace.adjustments = false
        workspace.historyAndSwatches = false
        workspace.toolbar = false
        workspace.rulers = false
        XCTAssertFalse(workspace.hasPanels)
        workspace.rightDock = true
        workspace.layers = true
        XCTAssertTrue(workspace.hasPanels)
        let decoded = try JSONDecoder().decode(CoverProject.self,from:original)
        XCTAssertEqual(try encoder.encode(decoded),original)
        XCTAssertEqual(decoded.layers[0].frame,layer.frame)
        XCTAssertEqual(decoded.layers[0].rotation,12)
        XCTAssertEqual(try encoder.encode(project),original)
        layer.maskData = nil
        XCTAssertEqual(workspace.propertiesTarget(layer:layer,maskSelected:true), .layer)
    }

    func testSelectionCommandEnablement() {
        var commands = CoverCommandAvailability(hasLayer:false,hasImage:false,hasSelection:false,hasDismissedSelection:false)
        XCTAssertFalse(commands.canMask)
        XCTAssertFalse(commands.canReselect)
        commands.hasSelection = true
        XCTAssertFalse(commands.canMask)
        commands.hasImage = true
        XCTAssertTrue(commands.canMask)
        commands.hasDismissedSelection = true
        XCTAssertTrue(commands.canReselect)
    }

    func testAdjustmentPanelExposureBindingChangesRenderedArtworkWithoutChangingSource() throws {
        let source = try CoverEditorEngine.filledImage(width:16,height:16,color:NSColor(srgbRed:0.2,green:0.3,blue:0.4,alpha:1))
        let artwork = try CoverArtwork.imageLayer(data:source,filename:"Source",frame:CoverRect())
        var adjustment = CoverLayer(kind:.adjustment,name:"Exposure",frame:CoverRect())
        adjustment.adjustment = .exposure
        let control = try XCTUnwrap(CoverAdjustmentControl.controls(for:.exposure).first)
        adjustment.adjustmentValues = [control.key:control.initial]
        var project = CoverProject(width:1,height:1)
        project.layers = [artwork,adjustment]
        func red(_ project:CoverProject) throws -> CGFloat {
            let image = try CoverArtwork.render(project,scale:16)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data:try XCTUnwrap(image.tiffRepresentation)))
            return try XCTUnwrap(bitmap.colorAt(x:8,y:8)?.usingColorSpace(.deviceRGB)).redComponent
        }
        let before = try red(project)
        project.layers[1].adjustmentValues?[control.key] = 1
        XCTAssertGreaterThan(try red(project),before + 0.05)
        XCTAssertEqual(project.layers[0].imageData,source)
        XCTAssertEqual(project.layers[0].frame,artwork.frame)
    }

    func testAdjustmentControlsUseRendererParameterKeysAndValidDefaults() {
        XCTAssertEqual(CoverAdjustmentControl.controls(for:.exposure).map(\.key),["exposure"])
        XCTAssertEqual(CoverAdjustmentControl.controls(for:.curves).map(\.key),["curve0","curve1","curve2","curve3","curve4"])
        XCTAssertEqual(CoverAdjustmentControl.controls(for:.gaussianBlur).map(\.key),["radius"])
        XCTAssertEqual(CoverAdjustmentControl.controls(for:.temperatureTint).map(\.key),["temperature","tint"])
        for kind in CoverAdjustmentKind.allCases {
            let controls = CoverAdjustmentControl.controls(for:kind)
            XCTAssertEqual(controls.count,Set(controls.map(\.key)).count)
            for control in controls { XCTAssertTrue(control.range.contains(control.initial)) }
        }
        XCTAssertTrue(CoverAdjustmentControl.controls(for:.invert).isEmpty)
    }

    func testAdjustmentControlValuesAreBoundedAndHaveStableResetDefaults() {
        let exposure = CoverAdjustmentControl.controls(for:.exposure)[0]
        XCTAssertEqual(exposure.clamped(2.5), 2.5)
        XCTAssertEqual(exposure.clamped(99), exposure.range.upperBound)
        XCTAssertEqual(exposure.clamped(-99), exposure.range.lowerBound)
        XCTAssertEqual(exposure.clamped(.infinity), exposure.initial)

        let curves = CoverAdjustmentControl.controls(for:.curves)
        XCTAssertEqual(curves.map { $0.clamped($0.initial) }, curves.map(\.initial))

        let selective = CoverSelectiveColor.controls(for:"blues")
        XCTAssertEqual(selective.map(\.key), ["bluesCyan", "bluesMagenta", "bluesYellow", "bluesBlack"])
        XCTAssertTrue(selective.allSatisfy { $0.range.contains($0.initial) })
    }
}
