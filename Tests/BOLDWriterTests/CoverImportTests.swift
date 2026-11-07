import XCTest
import AppKit
import ImageIO
import SceneKit
import UniformTypeIdentifiers
@testable import BOLDWriter

final class CoverImportTests: XCTestCase {
    private func fixture(_ type: UTType = .png, width: Int = 60, height: Int = 30,
                         alpha: Double = 1, orientation: Int = 1) throws -> Data {
        let bitmap=try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:width,pixelsHigh:height,
            bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0))
        for y in 0..<height { for x in 0..<width { bitmap.setColor(NSColor(deviceRed:1,green:0,blue:0,alpha:alpha),atX:x,y:y) } }
        let output=NSMutableData()
        let destination=try XCTUnwrap(CGImageDestinationCreateWithData(output,type.identifier as CFString,1,nil))
        CGImageDestinationAddImage(destination,try XCTUnwrap(bitmap.cgImage),[kCGImagePropertyOrientation:orientation] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func solidPNG(width: Int, height: Int, color: NSColor) throws -> Data {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        for y in 0..<height { for x in 0..<width { bitmap.setColor(color, atX: x, y: y) } }
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }

    func testPNGJPEGAndTIFFPlacementDecodeSelectionAndCanvasPixels() throws {
        for type in [UTType.png,.jpeg,.tiff] {
            var project=CoverProject(width:2,height:3); project.dpi=100
            let layer=try CoverImport.layer(data:fixture(type),filename:"image",template:false,project:project)
            let bitmap=try XCTUnwrap(NSBitmapImageRep(data:try XCTUnwrap(layer.imageData)))
            XCTAssertEqual(bitmap.pixelsWide,60); XCTAssertEqual(bitmap.pixelsHigh,30)
            XCTAssertEqual(layer.frame.width,0.3,accuracy:0.0001)
            XCTAssertEqual(layer.frame.height,0.1,accuracy:0.0001)
            XCTAssertEqual(layer.frame.x,0.35,accuracy:0.0001)
            XCTAssertEqual(layer.frame.y,0.45,accuracy:0.0001)
            var undo:[CoverProject]=[], redo:[CoverProject]=[], selected:UUID?, ids=Set<UUID>()
            try CoverImport.apply(layer,project:&project,undo:&undo,redo:&redo,selectedID:&selected,selectedIDs:&ids)
            XCTAssertEqual(project.layers,[layer]); XCTAssertEqual(selected,layer.id); XCTAssertEqual(ids,[layer.id])
            let rendered=try XCTUnwrap(NSBitmapImageRep(data:CoverArtwork.export(project,format:"png")))
            let center=try XCTUnwrap(rendered.colorAt(x:100,y:150)?.usingColorSpace(.deviceRGB))
            XCTAssertGreaterThan(center.redComponent,0.9); XCTAssertLessThan(center.greenComponent,0.25)
        }
    }

    @MainActor
    func testReplaceImageKeepsEditableGeometryCropMaskAndNativePersistence() throws {
        let red = try fixture()
        let blue = try solidPNG(width: 60, height: 30,
            color: NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1))
        var project = CoverProject(width: 2, height: 3)
        project.dpi = 72
        var layer = CoverLayer(kind: .image, name: "Cover photograph", frame: CoverRect(x: 0.1, y: 0.2, width: 0.7, height: 0.6))
        layer.imageData = red
        layer.rotation = 13
        layer.opacity = 0.85
        layer.cropMode = .free
        layer.sourceCrop = CoverRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
        layer.maskData = try solidPNG(width: 8, height: 8,
            color: NSColor(deviceRed: 1, green: 1, blue: 1, alpha: 1))
        layer.maskEnabled = true
        layer.psdRasterPixelBasis = true
        project.layers = [layer]
        let replacement = try CoverEditorEngine.replacingImageContents(in: layer, data: blue)
        XCTAssertEqual(replacement.id, layer.id)
        XCTAssertEqual(replacement.name, layer.name)
        XCTAssertEqual(replacement.frame, layer.frame)
        XCTAssertEqual(replacement.rotation, layer.rotation)
        XCTAssertEqual(replacement.opacity, layer.opacity)
        XCTAssertEqual(replacement.sourceCrop, layer.sourceCrop)
        XCTAssertEqual(replacement.maskData, layer.maskData)
        XCTAssertEqual(replacement.maskEnabled, layer.maskEnabled)
        XCTAssertNil(replacement.psdRasterPixelBasis)
        XCTAssertNotEqual(replacement.imageData, layer.imageData)
        var undo = [CoverProjectHistory.snapshot(project)], redo: [CoverProject] = []
        project.layers[0] = replacement
        CoverProjectHistory.undo(project: &project, undo: &undo, redo: &redo)
        XCTAssertEqual(project.layers[0].imageData, red)
        CoverProjectHistory.redo(project: &project, undo: &undo, redo: &redo)
        XCTAssertEqual(project.layers[0], replacement)
        let rendered = try XCTUnwrap(NSBitmapImageRep(data: CoverArtwork.export(project, format: "png")))
        let center = try XCTUnwrap(rendered.colorAt(x: rendered.pixelsWide / 2,
            y: rendered.pixelsHigh / 2)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(center.blueComponent, 0.8)
        XCTAssertLessThan(center.redComponent, 0.3)
        var metadata = DocumentMetadata(title: "Disposable cover replacement")
        metadata.coverProjects = [project]
        metadata.activeCoverProjectID = project.id
        let wrapper = try BOLDWriterDocument.packageWrapper(text: NSAttributedString(string: "Cover proof"), metadata: metadata)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Replace-Cover-\(UUID().uuidString).boldwriter", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: url) }
        try wrapper.write(to: url, options: .atomic, originalContentsURL: nil)
        let reopened = try BOLDWriterDocument(fileWrapper: FileWrapper(url: url), contentType: .boldWriterDocument)
        XCTAssertEqual(reopened.metadata.coverProjects?.first?.layers.first, replacement)
        var locked = layer
        locked.locked = true
        XCTAssertThrowsError(try CoverEditorEngine.replacingImageContents(in: locked, data: blue))
        XCTAssertThrowsError(try CoverEditorEngine.replacingImageContents(in: layer, data: Data([0, 1, 2])))
        XCTAssertEqual(layer.imageData, red)
    }

    func testOpeningPhotoshopCompositeCreatesPixelMatchedEditableCover() throws {
        let photoshop=UTType(importedAs:"com.adobe.photoshop-image",conformingTo:.image)
        guard Set(CGImageSourceCopyTypeIdentifiers() as! [String]).contains(photoshop.identifier),
              Set(CGImageDestinationCopyTypeIdentifiers() as! [String]).contains(photoshop.identifier) else {
            throw XCTSkip("This macOS installation has no Photoshop ImageIO codec")
        }
        let png=try fixture()
        let pngSource=try XCTUnwrap(CGImageSourceCreateWithData(png as CFData,nil))
        let image=try XCTUnwrap(CGImageSourceCreateImageAtIndex(pngSource,0,nil))
        let bytes=NSMutableData()
        let destination=try XCTUnwrap(CGImageDestinationCreateWithData(bytes,photoshop.identifier as CFString,1,nil))
        CGImageDestinationAddImage(destination,image,
            [kCGImagePropertyDPIWidth:200,kCGImagePropertyDPIHeight:200] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        XCTAssertTrue(CoverImport.imageTypes.contains { $0.preferredFilenameExtension == "psd" })
        let project=try CoverImport.project(data:bytes as Data,filename:"cover.psd")
        XCTAssertEqual(project.name,"cover")
        XCTAssertEqual(project.dpi,200,accuracy:0.001)
        XCTAssertEqual(project.canvasWidth,0.3,accuracy:0.001)
        XCTAssertEqual(project.canvasHeight,0.15,accuracy:0.001)
        XCTAssertEqual(project.layers.count,1)
        XCTAssertEqual(project.layers[0].frame,CoverRect())
        XCTAssertEqual(project.layers[0].kind,.image)
        XCTAssertTrue(try XCTUnwrap(project.layers[0].imageData).starts(with:Data([0x89,0x50,0x4E,0x47])))
        let exported=try XCTUnwrap(NSBitmapImageRep(data:CoverArtwork.export(project,format:"png")))
        XCTAssertEqual(exported.pixelsWide,60)
        XCTAssertEqual(exported.pixelsHigh,30)
        let reopened=try JSONDecoder().decode(CoverProject.self,from:JSONEncoder().encode(project))
        XCTAssertEqual(reopened,project)
        let template=try CoverImport.project(data:bytes as Data,filename:"printer.psd",asTemplate:true)
        XCTAssertEqual(template.type,.printFullWrap)
        XCTAssertEqual(template.canvasWidth,project.canvasWidth,accuracy:0.001)
        XCTAssertEqual(template.canvasHeight,project.canvasHeight,accuracy:0.001)
        XCTAssertEqual(template.layers[0].kind,.template)
        XCTAssertEqual(template.layers[0].frame,CoverRect())
        XCTAssertTrue(template.layers[0].locked)
        let production=try XCTUnwrap(NSBitmapImageRep(data:CoverArtwork.export(template,format:"png")))
        let proof=try XCTUnwrap(NSBitmapImageRep(data:CoverArtwork.export(template,format:"png",proof:true)))
        let white=try XCTUnwrap(production.colorAt(x:30,y:15)?.usingColorSpace(.deviceRGB))
        let red=try XCTUnwrap(proof.colorAt(x:30,y:15)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(white.greenComponent,0.9)
        XCTAssertLessThan(red.greenComponent,white.greenComponent)
    }

    func testAdvertisedHEICDecoderAndRasterTemplateFormats() throws {
        let encoders=Set(CGImageDestinationCopyTypeIdentifiers() as! [String])
        for type in CoverImport.imageTypes where encoders.contains(type.identifier) {
            let data=try fixture(type)
            if PSDImporter.recognizes(data) {
                XCTAssertThrowsError(try CoverImport.layer(data:data,filename:"fixture.psd",template:false,project:CoverProject()))
                XCTAssertFalse(try CoverImport.project(data:data,filename:"fixture.psd").layers.isEmpty)
                continue
            }
            let layer=try CoverImport.layer(data:data,filename:"fixture",template:false,project:CoverProject())
            XCTAssertNotNil(NSImage(data:try XCTUnwrap(layer.imageData)))
        }
        for type in [UTType.png,.jpeg,.tiff] {
            let layer=try CoverImport.layer(data:fixture(type),filename:"guide",template:true,project:CoverProject())
            XCTAssertEqual(layer.kind,.template)
            XCTAssertEqual(layer.frame.width*6,0.2,accuracy:0.0001)
            XCTAssertEqual(layer.frame.height*9,0.1,accuracy:0.0001)
        }
    }

    func testLargeImageFitsWithoutStretchAndSmallImageIsNotUpscaled() throws {
        let project=CoverProject(width:1,height:2)
        let layer=try CoverImport.layer(data:fixture(width:600,height:300),filename:"wide.png",template:false,project:project)
        XCTAssertEqual(layer.frame.width,1,accuracy:0.0001)
        XCTAssertEqual(layer.frame.height,0.25,accuracy:0.0001)
        XCTAssertEqual(layer.frame.y,0.375,accuracy:0.0001)
    }

    func testAlphaAndEXIFPortraitOrientation() throws {
        let transparent=try CoverImport.layer(data:fixture(alpha:0.25),filename:"alpha.png",template:false,project:CoverProject())
        let bitmap=try XCTUnwrap(NSBitmapImageRep(data:try XCTUnwrap(transparent.imageData)))
        XCTAssertEqual(try XCTUnwrap(bitmap.colorAt(x:0,y:0)).alphaComponent,0.25,accuracy:0.01)
        let portrait=try CoverImport.layer(data:fixture(.jpeg,orientation:6),filename:"portrait.jpg",template:false,project:CoverProject())
        let upright=try XCTUnwrap(NSBitmapImageRep(data:try XCTUnwrap(portrait.imageData)))
        XCTAssertEqual(upright.pixelsWide,30); XCTAssertEqual(upright.pixelsHigh,60)
        XCTAssertEqual(portrait.frame.width*6/(portrait.frame.height*9),0.5,accuracy:0.001)
    }

    func testImageAndRasterTemplateEmbeddedPackagePersistenceAndUndoRedo() throws {
        for template in [false,true] {
            var project=CoverProject(); project.layers=[CoverLayer(kind:.text,name:"Existing title")]
            let before=project
            let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".png")
            try fixture().write(to:url)
            let layer=try CoverImport.layer(from:url,template:template,project:project)
            try FileManager.default.removeItem(at:url)
            var undo:[CoverProject]=[], redo:[CoverProject]=[], selected:UUID?, ids=Set<UUID>()
            try CoverImport.apply(layer,project:&project,undo:&undo,redo:&redo,selectedID:&selected,selectedIDs:&ids)
            XCTAssertEqual(undo,[before]); XCTAssertEqual(project.layers.first,before.layers.first)
            XCTAssertEqual(project.canvasWidth,before.canvasWidth); XCTAssertEqual(project.canvasHeight,before.canvasHeight)
            XCTAssertEqual(layer.kind,template ? .template : .image)
            XCTAssertEqual(layer.locked,template)
            let imported=project
            CoverProjectHistory.undo(project:&project,undo:&undo,redo:&redo)
            XCTAssertEqual(project,before)
            CoverProjectHistory.redo(project:&project,undo:&undo,redo:&redo)
            XCTAssertEqual(project,imported)
            let doc=BOLDWriterDocument(); doc.metadata.coverProjects=[project]
            let wrapper=try BOLDWriterDocument.packageWrapper(text:doc.text,metadata:doc.metadata)
            let reopened=try BOLDWriterDocument(fileWrapper:wrapper,contentType:.boldWriterDocument)
            XCTAssertEqual(reopened.metadata.coverProjects,[project])
            XCTAssertNotNil(NSImage(data:try XCTUnwrap(reopened.metadata.coverProjects?.first?.layers.last?.imageData)))
        }
    }

    func testPDFTemplateFirstPageGeometryVisibleReferenceAndProofOnlyExport() throws {
        var box=CGRect(x:0,y:0,width:144,height:72)
        let bytes=NSMutableData()
        let context=try XCTUnwrap(CGContext(consumer:try XCTUnwrap(CGDataConsumer(data:bytes)),mediaBox:&box,nil))
        context.beginPDFPage(nil); context.setFillColor(NSColor.red.cgColor); context.fill(box); context.endPDFPage()
        context.beginPDFPage(nil); context.setFillColor(NSColor.blue.cgColor); context.fill(box); context.endPDFPage(); context.closePDF()
        var project=CoverProject(width:1,height:2); project.dpi=100
        let layer=try CoverImport.layer(data:bytes as Data,filename:"template.pdf",template:true,project:project)
        XCTAssertEqual(layer.frame,CoverRect(x:0,y:0.375,width:1,height:0.25))
        XCTAssertEqual(layer.opacity,0.45); XCTAssertTrue(layer.locked)
        project.layers=[layer]
        let canvas=try CoverArtwork.render(project,includeTemplate:true,scale:100)
        let bitmap=try XCTUnwrap(NSBitmapImageRep(data:try XCTUnwrap(canvas.tiffRepresentation)))
        let color=try XCTUnwrap(bitmap.colorAt(x:bitmap.pixelsWide/2,y:bitmap.pixelsHigh/2)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(color.redComponent,0.9); XCTAssertLessThan(color.greenComponent,0.8)
        let exported=try XCTUnwrap(NSBitmapImageRep(data:CoverArtwork.export(project,format:"png")))
        XCTAssertGreaterThan(try XCTUnwrap(exported.colorAt(x:50,y:100)).greenComponent,0.9)
        let restored=try JSONDecoder().decode(CoverProject.self,from:JSONEncoder().encode(project))
        XCTAssertEqual(restored,project)
    }

    func testCorruptMissingAndInvalidImportsDoNotMutateProjectOrHistory() throws {
        var project=CoverProject(); project.layers=[CoverLayer(kind:.text,name:"Keep")]
        let before=project
        var undo:[CoverProject]=[], redo=[project], selected:UUID?, ids=Set<UUID>()
        for name in ["bad.png","bad.jpg","bad.pdf"] {
            for template in [false,true] {
                XCTAssertThrowsError(try CoverImport.layer(data:Data("broken".utf8),filename:name,template:template,project:project))
            }
        }
        XCTAssertThrowsError(try CoverImport.layer(from:URL(fileURLWithPath:"/nonexistent/cover.png"),template:false,project:project))
        var invalid=CoverLayer(kind:.image,name:"invalid"); invalid.imageData=Data([0])
        XCTAssertThrowsError(try CoverImport.apply(invalid,project:&project,undo:&undo,redo:&redo,selectedID:&selected,selectedIDs:&ids))
        XCTAssertEqual(project,before); XCTAssertTrue(undo.isEmpty); XCTAssertEqual(redo,[before]); XCTAssertNil(selected)
    }
}

@MainActor
final class KDPHardcoverImportTests: XCTestCase {
    private func template(width: Double = 1402) throws -> Data {
        var box=CGRect(x:0,y:0,width:width,height:894)
        let bytes=NSMutableData()
        let context=try XCTUnwrap(CGContext(consumer:try XCTUnwrap(CGDataConsumer(data:bytes)),mediaBox:&box,nil))
        context.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current=NSGraphicsContext(cgContext:context,flipped:false)
        let text="Hardcover Book\nCover Template - Left to Right\nBlue Dashed Line = Spine Fold\n8.25\" x 11\" Book\n19.469\" x 12.417\" Overall Dimensions\nSpine Width 1.394\"\n535 Pages"
        (text as NSString).draw(in:CGRect(x:30,y:30,width:800,height:700),withAttributes:[.font:NSFont.systemFont(ofSize:18)])
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage(); context.closePDF()
        return bytes as Data
    }

    private func check(_ project: CoverProject) throws {
        XCTAssertEqual(project.type,.printFullWrap)
        XCTAssertEqual(project.trimWidth,8.25)
        XCTAssertEqual(project.trimHeight,11)
        XCTAssertEqual(project.spineWidth,1.394)
        XCTAssertEqual(project.spinePageCount,535)
        XCTAssertEqual(project.productionBinding,.hardcover)
        XCTAssertEqual(project.layers.first?.kind,.group)
        XCTAssertTrue(project.layers.allSatisfy(\.isReferenceLayer))
        XCTAssertTrue(project.layers.contains { $0.kind == .text && $0.text.contains("Hardcover") })
        XCTAssertNotNil(project.activeKDPHardcoverLayout)
        let wrap=CoverWrapGeometry(project:project)
        XCTAssertEqual(wrap.frontTrim.width*project.canvasWidth,8.25+5/25.4,accuracy:0.000001)
        XCTAssertEqual(wrap.frontTrim.height*project.canvasHeight,11+6/25.4,accuracy:0.000001)
        XCTAssertEqual(wrap.spineTrim.width*project.canvasWidth,1.394,accuracy:0.000001)
        XCTAssertEqual(wrap.backTrim.x*project.canvasWidth,15/25.4,accuracy:0.001)
        XCTAssertEqual(wrap.frontTrim.x,wrap.spineTrim.x+wrap.spineTrim.width,accuracy:0.000001)
        let physical=PhysicalBookGeometry(project:project)
        XCTAssertEqual(physical.cover,wrap)
        XCTAssertEqual(physical.outerBookDepth(for:.hardcover),1.394,accuracy:0.000001)
        XCTAssertNil(PhysicalBookGeometry.synchronizedPrintCover(project,manuscriptPageCount:354))
        let decoded=try JSONDecoder().decode(CoverProject.self,from:JSONEncoder().encode(project))
        XCTAssertEqual(decoded,project)
        var resized=project; resized.canvasWidth += 1
        XCTAssertNil(resized.activeKDPHardcoverLayout)
    }

    func testRenamedTemplateOpensWithMeasuredCaseAndStableThreeDGeometry() throws {
        try check(CoverImport.project(data:template(),filename:"renamed.pdf"))
        XCTAssertThrowsError(try CoverImport.project(data:template(width:1000),filename:"scaled.pdf",asTemplate:true))
    }

    func testFullWrapArtworkIsCenteredAndReferencesStayOutOfProduction() throws {
        var project = try CoverImport.project(data: template(), filename: "template.pdf")
        let bytes = try CoverEditorEngine.filledImage(width: 160, height: 100, color: .blue)
        let layer = try CoverImport.layer(data: bytes, filename: "wrap.png", template: false, project: project)
        XCTAssertEqual(layer.frame, CoverRect())
        XCTAssertEqual(layer.cropMode, .fit)
        var undo: [CoverProject] = [], redo: [CoverProject] = []
        var selected: UUID?, selectedIDs: Set<UUID> = []
        try CoverImport.apply(layer, project: &project, undo: &undo, redo: &redo,
            selectedID: &selected, selectedIDs: &selectedIDs)
        XCTAssertEqual(project.layers.first?.id, layer.id)
        var withoutReferences = project
        withoutReferences.layers.removeAll { $0.isReferenceLayer }
        let actual = try CoverArtwork.render(project, scale: 36)
        let expected = try CoverArtwork.render(withoutReferences, scale: 36)
        XCTAssertEqual(actual.tiffRepresentation, expected.tiffRepresentation)
    }

    func testOrdinaryPDFCanOpenAsArtworkAtPhysicalSize() throws {
        var box=CGRect(x:0,y:0,width:144,height:72)
        let bytes=NSMutableData()
        let context=try XCTUnwrap(CGContext(consumer:try XCTUnwrap(CGDataConsumer(data:bytes)),mediaBox:&box,nil))
        context.beginPDFPage(nil); context.setFillColor(NSColor.red.cgColor); context.fill(box)
        context.endPDFPage(); context.closePDF()
        let project=try CoverImport.project(data:bytes as Data,filename:"artwork.pdf")
        XCTAssertEqual(project.canvasWidth,2); XCTAssertEqual(project.canvasHeight,1)
        XCTAssertEqual(project.layers.first?.kind,.image)
        XCTAssertNotNil(project.layers.first?.imageData)
        let layer=try CoverImport.layer(data:bytes as Data,filename:"artwork.pdf",template:false,project:CoverProject(width:4,height:4))
        XCTAssertEqual(layer.frame.width,0.5)
        XCTAssertEqual(layer.frame.height,0.25)

    }

    func testSuppliedKDPTemplateAcceptance() throws {
        guard let path=ProcessInfo.processInfo.environment["BOLD_KDP_TEMPLATE_PDF"] else {
            throw XCTSkip("Set BOLD_KDP_TEMPLATE_PDF for an explicitly authorized real PDF.")
        }
        let project=try CoverImport.project(from:URL(fileURLWithPath:path),asTemplate:true)
        try check(project)
        XCTAssertGreaterThan(project.layers.filter { $0.kind == .path }.count, 5)
        XCTAssertGreaterThan(project.layers.filter { $0.kind == .text }.count, 20)
        if let output=ProcessInfo.processInfo.environment["BOLD_KDP_PROOF_DIR"] {
            let directory=URL(fileURLWithPath:output)
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            let rendered=try CoverArtwork.render(project,includeTemplate:true,scale:72)
            let bitmap=try XCTUnwrap(NSBitmapImageRep(data:try XCTUnwrap(rendered.tiffRepresentation)))
            try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:directory.appendingPathComponent("editable-template.png"))
        }
        if let art=ProcessInfo.processInfo.environment["BOLD_KDP_ARTWORK"],
           let output=ProcessInfo.processInfo.environment["BOLD_KDP_PROOF_DIR"] {
            var proof=project
            var layer=try CoverImport.layer(from:URL(fileURLWithPath:art),template:false,project:proof)
            // Fit the artwork width without changing its aspect ratio.
            let image=try CoverArtwork.decodedRaster(try XCTUnwrap(layer.imageData))
            let height=Double(image.height)/Double(image.width)*proof.canvasWidth/proof.canvasHeight
            layer.frame=CoverRect(x:0,y:(1-height)/2,width:1,height:height)
            proof.layers.append(layer)
            let document=BOLDWriterDocument()
            document.metadata.coverProjects=[proof]
            document.metadata.activeCoverProjectID=proof.id
            layer.name="Shared artwork edited from 3D"
            try BookStudioArtworkEditing.replace(layer,projectID:proof.id,in:document,undoManager:nil)
            proof=try XCTUnwrap(document.metadata.coverProjects?.first)
            XCTAssertEqual(proof.activeKDPHardcoverLayout,project.activeKDPHardcoverLayout)
            XCTAssertEqual(proof.layers.last?.name,layer.name)
            let folder=URL(fileURLWithPath:output)
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            let package=try BOLDWriterDocument.packageWrapper(text:document.text,metadata:document.metadata)
            try package.write(to:folder.appendingPathComponent("Measured-Hardcover.boldwriter"),options:.atomic,originalContentsURL:nil)
            let reopened=try BOLDWriterDocument(fileWrapper:package,contentType:.boldWriterDocument)
            XCTAssertEqual(reopened.metadata.coverProjects?.first,proof)
            var presentation=BookStudioPresentation()
            presentation.binding = .hardcover
            for (name,preset) in [("front",BookViewPreset.perspective),("back",.back)] {
                let scene=BookPreviewScene.make(project:proof,workingLayers:false,open:false,angle:0,
                    leftPage:nil,rightPage:1,pageCount:535,spreadIndex:0,leftTexture:nil,rightTexture:nil,
                    margins:false,thumbMode:.off,leftPageSettings:PageSettings(),rightPageSettings:PageSettings(),
                    preset:preset,revisionID:UUID(),binding:.hardcover,presentation:presentation)
                scene.rootNode.enumerateChildNodes { node, _ in
                    if node.name?.hasPrefix("diagnostic.") == true { XCTAssertTrue(node.isHidden) }
                }
                BookStudioSceneStyling.apply(to:scene,presentation:presentation)
                let view=BookPreviewInteractionView(frame:NSRect(x:0,y:0,width:1200,height:1000))
                view.scene=scene
                view.cameraNode=scene.rootNode.childNode(withName:"preview-camera",recursively:true)
                let state=BookPreviewCameraMath.state(project:proof,open:false,preset:preset,focus:.automatic)
                view.setCamera(state); view.configureCamera(state,projection:.perspective)
                let renderer=SCNRenderer(device:nil,options:nil)
                renderer.scene=scene; renderer.pointOfView=view.cameraNode
                let image=renderer.snapshot(atTime:0,with:CGSize(width:1200,height:1000),antialiasingMode:.multisampling4X)
                let bitmap=try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
                try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:folder.appendingPathComponent(name+".png"))
            }
        }
        // Production export must never bake the printer's reference labels into artwork.
        var small=project; small.dpi=30
        let exported=try CoverArtwork.export(small,format:"png")
        let bitmap=try XCTUnwrap(NSBitmapImageRep(data:exported))
        let color=try XCTUnwrap(bitmap.colorAt(x:bitmap.pixelsWide/2,y:bitmap.pixelsHigh/2)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(color.redComponent,0.99)
        XCTAssertGreaterThan(color.greenComponent,0.99)
        XCTAssertGreaterThan(color.blueComponent,0.99)
    }
}
