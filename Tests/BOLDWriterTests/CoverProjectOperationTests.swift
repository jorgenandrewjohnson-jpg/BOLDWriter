import AppKit
import XCTest
@testable import BOLDWriter

@MainActor
final class CoverProjectOperationTests: XCTestCase {
    func testCoverProjectCapacityIsEnforcedForConversionsAndImports() {
        XCTAssertTrue(CoverProjectOperations.canAppendProject(existingCount: 0, hasOpenedProject: false))
        XCTAssertTrue(CoverProjectOperations.canAppendProject(existingCount: 7, hasOpenedProject: true))
        XCTAssertFalse(CoverProjectOperations.canAppendProject(existingCount: 8, hasOpenedProject: true))
        XCTAssertFalse(CoverProjectOperations.canAppendProject(existingCount: 9, hasOpenedProject: true))
    }

    private func fixture() -> CoverProject {
        var p = CoverProject(width:10,height:5)
        p.layers = [CoverLayer(kind:.shape,name:"A",frame:CoverRect(x:0.65,y:0.4,width:0.1,height:0.2)),
                    CoverLayer(kind:.text,name:"B",frame:CoverRect(x:0.25,y:0.4,width:0.1,height:0.2))]
        return p
    }
    func testRasterDimensionReadoutMatchesActualExportWithoutChangingPhysicalSize() throws {
        var p = CoverProject(width: 1.003, height: 1.007)
        p.dpi = 144
        let original = p
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: CoverArtwork.export(p, format: "png")))
        let snapshot = try JSONDecoder().decode(CoverLayerCommands.Snapshot.self, from: Data(CoverLayerCommands.inspect(p).utf8))
        XCTAssertEqual(p.rasterPixelSize, CGSize(width: 145, height: 146))
        XCTAssertEqual(Double(bitmap.pixelsWide), p.rasterPixelSize.width)
        XCTAssertEqual(Double(bitmap.pixelsHigh), p.rasterPixelSize.height)
        XCTAssertEqual(snapshot.pixelWidth, p.rasterPixelSize.width)
        XCTAssertEqual(snapshot.pixelHeight, p.rasterPixelSize.height)
        let psd = try CoverArtwork.export(p, format: "psd")
        func uint32(_ offset: Int) -> Int {
            psd[offset..<(offset + 4)].reduce(0) { ($0 << 8) | Int($1) }
        }
        XCTAssertEqual(uint32(14), bitmap.pixelsHigh)
        XCTAssertEqual(uint32(18), bitmap.pixelsWide)
        let rasterLayer = CoverLayer(kind: .shape, name: "Bounds", frame: CoverRect())
        let layerImage = try CoverArtwork.psdLayerImage(rasterLayer, project: p)
        let layerBitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(layerImage.cgImage(forProposedRect: nil, context: nil, hints: nil)))
        XCTAssertEqual(layerBitmap.pixelsWide, bitmap.pixelsWide)
        XCTAssertEqual(layerBitmap.pixelsHigh, bitmap.pixelsHigh)
        XCTAssertEqual(p, original)
    }
    func testRotationUsesPhysicalCanvasDistancesAndKeepsLayerSize() throws {
        var p = fixture(); let original = p.layers[0].frame
        try CoverProjectOperations.apply("rotate",to:&p,arguments:["layerID":p.layers[0].id.uuidString,"degrees":"90","pivotX":"0.5","pivotY":"0.5"])
        XCTAssertEqual(p.layers[0].frame.x,0.45,accuracy:0.00001)
        XCTAssertEqual(p.layers[0].frame.y,0.8,accuracy:0.00001)
        XCTAssertEqual(p.layers[0].frame.width,original.width)
        XCTAssertEqual(p.layers[0].rotation,90)
    }
    func testCanvasResizePreservesArtworkPhysicalDimensionsAndGuideAlignment() throws {
        var p = fixture(); p.userGuidesX = [2,7]; p.userGuidesY = [1]
        let f = p.layers[0].frame
        try CoverProjectOperations.apply("canvas-resize",to:&p,arguments:["width":"12","height":"7"])
        XCTAssertEqual(p.layers[0].frame.width*12,f.width*10,accuracy:0.00001)
        XCTAssertEqual(p.layers[0].frame.x*12,f.x*10+1,accuracy:0.00001)
        XCTAssertEqual(p.userGuidesX,[3,8]); XCTAssertEqual(p.userGuidesY,[2])
        XCTAssertEqual(p.trimWidth,12)
        XCTAssertEqual(try JSONDecoder().decode(CoverProject.self,from:JSONEncoder().encode(p)),p)
    }
    func testOperationsRejectUnknownArgumentsAndRemainAtomic() throws {
        var p = fixture(); let original = p
        for (op,args) in [("move",["dx":"0.1","dy":"nan"]),
                          ("scale",["scaleX":"0"]),("rotate",["degrees":"90","degreess":"10"]),
                          ("crop",["x":"0","y":"0","width":"1","height":"1"])] {
            XCTAssertThrowsError(try CoverProjectOperations.apply(op,to:&p,arguments:args.merging(["layerID":p.layers[0].id.uuidString]) { a,_ in a }))
            XCTAssertEqual(p,original)
        }
        p.layers[0].positionLocked = true
        XCTAssertThrowsError(try CoverProjectOperations.apply("move",to:&p,arguments:["layerID":p.layers[0].id.uuidString,"dx":"1","dy":"1"]))
    }
    func testGroupingUngroupingAndDeleteKeepMembershipValid() throws {
        var p = fixture(); let ids = p.layers.map(\.id)
        let group = try XCTUnwrap(CoverProjectOperations.apply("group",to:&p,arguments:["layerIDs":ids.map(\.uuidString).joined(separator:","),"name":"Title group"]).first)
        XCTAssertTrue(p.layers.prefix(2).allSatisfy { $0.groupID == group })
        let before = p.layers[0].frame
        try CoverProjectOperations.apply("move",to:&p,arguments:["layerID":group.uuidString,"dx":"0.1","dy":"0.2"])
        XCTAssertEqual(p.layers[0].frame.x,before.x+0.1,accuracy:0.00001)
        XCTAssertEqual(p.layers[0].frame.y,before.y+0.2,accuracy:0.00001)
        XCTAssertThrowsError(try CoverProjectOperations.apply("delete",to:&p,arguments:["layerID":group.uuidString]))
        try CoverProjectOperations.apply("ungroup",to:&p,arguments:["layerID":group.uuidString])
        XCTAssertEqual(p.layers.map(\.id),ids); XCTAssertTrue(p.layers.allSatisfy { $0.groupID == nil })
    }
    func testMaskBakeMatchesDensityOffsetAndDisabledRendering() throws {
        let data = try CoverEditorEngine.filledImage(width:8,height:8,color:.blue)
        for disabled in [false,true] {
            var p = fixture(); p.layers = [try CoverArtwork.imageLayer(data:data,filename:"Blue",frame:CoverRect())]
            let id = p.layers[0].id.uuidString
            try CoverProjectOperations.apply("mask-add",to:&p,arguments:["layerID":id])
            p.layers[0].maskDensity = 0.5; p.layers[0].maskOffsetX = 0.25; p.layers[0].maskEnabled = !disabled
            let expected = disabled ? data : try CoverEditorEngine.applyRasterMask(data,maskImageData:try XCTUnwrap(p.layers[0].maskData),density:0.5,offsetX:0.25)
            try CoverProjectOperations.apply("mask-apply",to:&p,arguments:["layerID":id])
            XCTAssertEqual(p.layers[0].imageData,expected); XCTAssertNil(p.layers[0].maskData)
        }
    }
    func testAdvancedLayerFieldsAreInspectableAndInvalidPatchesAreAtomic() throws {
        var p = fixture(); let id = p.layers[1].id.uuidString
        try CoverLayerCommands.update(&p,arguments:["layerID":id,"horizontalScale":"1.2","verticalScale":"0.8","flipHorizontal":"true","letterSpacing":"2"])
        let snapshot = try JSONDecoder().decode(CoverLayerCommands.Snapshot.self,from:Data(CoverLayerCommands.inspect(p).utf8))
        XCTAssertEqual(snapshot.spineWidthInches,p.spineWidth)
        XCTAssertEqual(snapshot.frontPanel,CoverWrapGeometry(project:p).frontTrim)
        XCTAssertEqual(snapshot.layers[1].horizontalScale,1.2)
        XCTAssertEqual(snapshot.layers[1].flipHorizontal,true)
        XCTAssertEqual(snapshot.layers[1].letterSpacing,2)
        let before = p
        XCTAssertThrowsError(try CoverLayerCommands.update(&p,arguments:["layerID":id,"name":"Bad patch","maskDensity":"0.5"]))
        XCTAssertEqual(p,before)
        XCTAssertThrowsError(try CoverLayerCommands.update(&p,arguments:["layerID":id,"verticalScale":"nan"]))
        XCTAssertEqual(p,before)
    }
    func testRasterOpacityAndBlendAffectFlatCoverAndAll3DPanels() throws {
        let data = try CoverEditorEngine.filledImage(width:8,height:8,color:.red)
        var p = CoverProject(type:.printFullWrap,width:3,height:1)
        p.trimWidth=1; p.backWidth=1; p.trimHeight=1; p.spineWidth=1; p.bleed=0; p.dpi=24
        p.backgroundHex="#FFFFFF"
        p.layers=[try CoverArtwork.imageLayer(data:data,filename:"Raster",frame:CoverRect(x:0,y:0,width:1,height:1))]
        func pixel(_ image:NSImage) throws -> NSColor {
            let bitmap = NSBitmapImageRep(cgImage:try XCTUnwrap(image.cgImage(forProposedRect:nil,context:nil,hints:nil)))
            return try XCTUnwrap(bitmap.colorAt(x:bitmap.pixelsWide/2,y:bitmap.pixelsHigh/2)?.usingColorSpace(.sRGB))
        }
        p.layers[0].opacity=0.5
        let normal = try pixel(CoverArtwork.render(p,scale:24))
        var vector = p
        var shape = CoverLayer(kind:.shape,name:"Equivalent red",frame:p.layers[0].frame)
        shape.fillHex="#FF0000"; shape.opacity=0.5; vector.layers=[shape]
        let expected = try pixel(CoverArtwork.render(vector,scale:24))
        XCTAssertEqual(normal.redComponent,expected.redComponent,accuracy:0.02)
        XCTAssertEqual(normal.greenComponent,expected.greenComponent,accuracy:0.02)
        XCTAssertGreaterThan(normal.greenComponent,0.4,"Half-opacity raster must reveal the white background")
        for image in [PhysicalBookCoverTextures(project:p,workingLayers:false,previewDPI:24).front,
                      PhysicalBookCoverTextures(project:p,workingLayers:false,previewDPI:24).spine,
                      PhysicalBookCoverTextures(project:p,workingLayers:false,previewDPI:24).back] {
            let panel = try pixel(XCTUnwrap(image))
            XCTAssertEqual(panel.redComponent,normal.redComponent,accuracy:0.01)
            XCTAssertEqual(panel.greenComponent,normal.greenComponent,accuracy:0.01)
        }
        p.backgroundHex="#00FFFF"
        p.layers[0].opacity=1; p.layers[0].blendMode = .multiply
        let multiply = try pixel(CoverArtwork.render(p,scale:24))
        XCTAssertEqual(multiply.redComponent,0,accuracy:0.02)
        XCTAssertEqual(multiply.greenComponent,0,accuracy:0.02)
        XCTAssertLessThan(multiply.redComponent,normal.redComponent)
    }

    func testAutomationInspectDoesNotMutateMetadataAndUndoRedoShareTransactions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let url = root.appendingPathComponent("proof.boldwriter"), doc = BOLDWriterDocument(), p = fixture()
        doc.metadata.coverProjects = [p]; doc.metadata.activeCoverProjectID = p.id
        try BOLDWriterDocument.packageWrapper(text:doc.text,metadata:doc.metadata).write(to:url,options:.atomic,originalContentsURL:nil)
        let session = try BookAutomationSession(input:url)
        let metadata = session.document.metadata
        _ = try session.execute(BOLDTerminalCommandParser.parse(["cover","inspect"]))
        XCTAssertEqual(session.document.metadata,metadata)
        _ = try session.execute(BOLDTerminalCommandParser.parse(["cover","edit","move","layerID="+p.layers[0].id.uuidString,"dx=0.1","dy=0.2"]))
        let edited = session.document.metadata.coverProjects
        _ = try session.execute(BOLDTerminalCommandParser.parse(["undo"]))
        XCTAssertEqual(session.document.metadata.coverProjects,[p])
        _ = try session.execute(BOLDTerminalCommandParser.parse(["redo"]))
        XCTAssertEqual(session.document.metadata.coverProjects,edited)
    }
}
