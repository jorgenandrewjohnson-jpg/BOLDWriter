import XCTest
import AppKit
@testable import BOLDWriter

@MainActor
final class CoverLayerCommandTests: XCTestCase {
    private func rasterFixture() throws -> CoverProject {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:32,pixelsHigh:24,
            bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0))
        for y in 0..<24 { for x in 0..<32 { bitmap.setColor(x < 16 ? .red : .blue,atX:x,y:y) } }
        var project = CoverProject(width:10,height:8)
        var layer = CoverLayer(kind:.image,name:"Photo")
        layer.imageData = try XCTUnwrap(bitmap.representation(using:.png,properties:[:]))
        project.layers = [layer]
        return project
    }

    func testInspectionDistinguishesNondestructiveCropWithoutChangingSourcePixels() throws {
        var project = try rasterFixture()
        let before = try JSONDecoder().decode(CoverLayerCommands.Snapshot.self,from:Data(CoverLayerCommands.inspect(project).utf8))
        try CoverProjectOperations.apply("crop",to:&project,arguments:["layerID":project.layers[0].id.uuidString,
            "x":"0.1","y":"0.2","width":"0.8","height":"0.6"])
        project.layers[0].cropMode = .fit; project.layers[0].cropOffsetX = 0.25; project.layers[0].cropOffsetY = -0.1
        let after = try JSONDecoder().decode(CoverLayerCommands.Snapshot.self,from:Data(CoverLayerCommands.inspect(project).utf8))
        XCTAssertNil(before.layers[0].sourceCrop)
        XCTAssertEqual(after.layers[0].sourceCrop,CoverRect(x:0.1,y:0.2,width:0.8,height:0.6))
        XCTAssertEqual(after.layers[0].cropMode,.fit)
        XCTAssertEqual(after.layers[0].cropOffsetX,0.25); XCTAssertEqual(after.layers[0].cropOffsetY,-0.1)
        XCTAssertEqual(after.layers[0].embeddedImageSHA256,before.layers[0].embeddedImageSHA256)
        XCTAssertEqual(after.layers[0].imagePixelWidth,32); XCTAssertEqual(after.layers[0].imagePixelHeight,24)
    }

    func testInspectionTracksMaskPixelChangesAndSurvivesPersistence() throws {
        var project = try rasterFixture()
        let id = project.layers[0].id.uuidString
        try CoverProjectOperations.apply("mask-add",to:&project,arguments:["layerID":id,"coverage":"0.25"])
        let before = try JSONDecoder().decode(CoverLayerCommands.Snapshot.self,from:Data(CoverLayerCommands.inspect(project).utf8))
        try CoverProjectOperations.apply("mask-invert",to:&project,arguments:["layerID":id])
        let inspected = try CoverLayerCommands.inspect(project)
        let after = try JSONDecoder().decode(CoverLayerCommands.Snapshot.self,from:Data(inspected.utf8))
        XCTAssertNotNil(before.layers[0].embeddedMaskSHA256)
        XCTAssertNotEqual(before.layers[0].embeddedMaskSHA256,after.layers[0].embeddedMaskSHA256)
        XCTAssertEqual(before.layers[0].embeddedImageSHA256,after.layers[0].embeddedImageSHA256)
        let restored = try JSONDecoder().decode(CoverProject.self,from:JSONEncoder().encode(project))
        XCTAssertEqual(try CoverLayerCommands.inspect(restored),inspected)
    }
    private func fixture() -> CoverProject {
        var project = CoverProject(width:10,height:8); project.dpi = 144
        var text = CoverLayer(kind:.text,name:"Title",frame:CoverRect(x:0.2,y:0.25,width:0.5,height:0.1))
        text.text = "Before"; text.opacity = 0.55
        project.layers = [text, CoverLayer(kind:.shape,name:"Shape",frame:CoverRect(x:0,y:0,width:1,height:1))]
        return project
    }

    func testInspectionIsReadOnlyAndReportsPhysicalUnitsAndOrder() throws {
        let project = fixture(), original = project
        let snapshot = try JSONDecoder().decode(CoverLayerCommands.Snapshot.self,
            from: Data(CoverLayerCommands.inspect(project).utf8))
        XCTAssertEqual(project,original)
        XCTAssertEqual(snapshot.pixelWidth,1440); XCTAssertEqual(snapshot.pixelHeight,1152)
        XCTAssertEqual(snapshot.layers.map(\.id),project.layers.map(\.id))
        XCTAssertEqual(snapshot.layers[0].frameInches.x,2)
        XCTAssertEqual(snapshot.layers[0].framePixels.y,288)
        XCTAssertEqual(snapshot.layers[0].opacity,0.55)
        XCTAssertEqual(snapshot.layers[0].text,"Before")
    }

    func testTerminalAndAIToolUseSameLayerPatchAndRoundTripPersistence() throws {
        var project = fixture()
        let action = try BOLDTerminalCommandParser.parse(["cover","update-layer",project.layers[0].id.uuidString,
            "text=After = Edited","x=0.3","opacity=0.4","rotation=90","blendMode=multiply","fontSize=42"])
        XCTAssertEqual(action.kind,.coverUpdateLayer)
        let ai = BOLDAIProjectToolCatalog.definition(for:.coverUpdateLayer)
        XCTAssertEqual(ai.workspace,.cover)
        XCTAssertTrue(ai.properties.contains { $0.name == "layerID" && $0.required })
        XCTAssertEqual(BOLDCommandSafety.classification(for:.coverUpdateLayer),.reversibleMutation)
        XCTAssertEqual(BOLDCommandSafety.classification(for:.coverInspect),.readOnly)
        XCTAssertTrue(BookAutomationSession.supported.contains(.coverUpdateLayer))
        let untouched = project.layers[1]
        try CoverLayerCommands.update(&project,arguments:action.arguments)
        XCTAssertEqual(project.layers[0].text,"After = Edited"); XCTAssertEqual(project.layers[0].frame.x,0.3)
        XCTAssertEqual(project.layers[0].rotation,90); XCTAssertEqual(project.layers[0].opacity,0.4)
        XCTAssertEqual(project.layers[1],untouched)
        XCTAssertEqual(try JSONDecoder().decode(CoverProject.self,from:JSONEncoder().encode(project)),project)
    }

    func testInvalidPatchesAreAtomicAndLocksAreHonored() throws {
        var project = fixture()
        let original = project, id = project.layers[0].id.uuidString
        for fields in [["opacity":"nan"],["width":"0"],["visible":"yes"],["blendMode":"invalid"],
                       ["name":"Changed","opacity":"2"],["unknown":"x"],["colorHex":"red"]] {
            XCTAssertThrowsError(try CoverLayerCommands.update(&project,arguments:fields.merging(["layerID":id]) { a,_ in a }))
            XCTAssertEqual(project,original)
        }
        project.layers[0].locked = true
        XCTAssertThrowsError(try CoverLayerCommands.update(&project,arguments:["layerID":id,"text":"Changed"]))
        try CoverLayerCommands.update(&project,arguments:["layerID":id,"locked":"false"])
        project.layers[0].positionLocked = true
        XCTAssertThrowsError(try CoverLayerCommands.update(&project,arguments:["layerID":id,"x":"0.4"]))
        try CoverLayerCommands.update(&project,arguments:["layerID":id,"visible":"false"])
        XCTAssertFalse(project.layers[0].visible)
        XCTAssertThrowsError(try CoverLayerCommands.update(&project,arguments:["layerID":project.layers[1].id.uuidString,"text":"Cannot flatten"] ))
        project.layers[0].referenceOnly = true
        XCTAssertThrowsError(try CoverLayerCommands.update(&project,arguments:["layerID":id,"opacity":"0.5"]))
    }

    func testAutomationSessionEditsExistingProjectAndKeepsInputFileUnchanged() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let input = root.appendingPathComponent("fixture.boldwriter")
        let document = BOLDWriterDocument(), project = fixture()
        document.metadata.coverProjects = [project]; document.metadata.activeCoverProjectID = project.id
        let wrapper = try BOLDWriterDocument.packageWrapper(text:document.text,metadata:document.metadata)
        try wrapper.write(to:input,options:.atomic,originalContentsURL:nil)
        let session = try BookAutomationSession(input:input)
        let inspect = try session.execute(BOLDTerminalCommandParser.parse(["cover","inspect"]))
        XCTAssertNotNil(inspect.values["snapshot"])
        let update = try BOLDTerminalCommandParser.parse(["cover","update-layer",project.layers[0].id.uuidString,"text=Updated by terminal"])
        let result = try session.execute(update)
        XCTAssertEqual(result.values["layerID"],project.layers[0].id.uuidString)
        XCTAssertEqual(session.document.metadata.coverProjects?[0].layers[0].text,"Updated by terminal")
        let reopened = try BookAutomationSession(input:input)
        XCTAssertEqual(reopened.document.metadata.coverProjects?[0],project)
        let saved = try BOLDWriterDocument.packageWrapper(text:session.document.text,metadata:session.document.metadata)
        let roundTrip = try BOLDWriterDocument(fileWrapper:saved,contentType:.boldWriterDocument)
        XCTAssertEqual(roundTrip.metadata.coverProjects,session.document.metadata.coverProjects)
    }

    func testParserRejectsDuplicateUnknownAndMissingFields() throws {
        let id = UUID().uuidString
        XCTAssertEqual(try BOLDTerminalCommandParser.parse(["cover","inspect"]).kind,.coverInspect)
        for command in [["cover","inspect","extra"],["cover","update-layer",id],
                        ["cover","update-layer",id,"x=0.1","x=0.2"],
                        ["cover","update-layer",id,"fake=1"]] {
            XCTAssertThrowsError(try BOLDTerminalCommandParser.parse(command))
        }
    }
}
