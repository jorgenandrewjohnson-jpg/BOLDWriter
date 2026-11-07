import AppKit
import PDFKit
import XCTest
@testable import BOLDWriter

@MainActor
final class PublishingToolsTests: XCTestCase {
    func testTOCInsertionUndoRedoRestoresSettingsAndGeneratedBookmarks() throws {
        let document = BOLDWriterDocument()
        let text = NSMutableAttributedString(string: "Chapter One\nBody\n")
        text.addAttribute(.boldWriterStyle, value: WriterStyle.heading1.rawValue,
                          range: NSRange(location: 0, length: 11))
        document.replaceText(with: text)
        let controller = EditorController()
        let view = WritingTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 800))
        let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = view
        view.allowsUndo = true
        view.textStorage?.setAttributedString(text)
        controller.document = document; controller.attach(view)
        let beforeBookmarks = document.metadata.bookmarks
        view.setSelectedRange(NSRange(location: text.length, length: 0))
        controller.insertTableOfContents(mode: .kindle)
        let inserted = view.attributedString().copy() as! NSAttributedString
        let settings = document.metadata.publishingTOCs
        let bookmarks = document.metadata.bookmarks
        XCTAssertEqual(settings?.count, 1)
        XCTAssertFalse(bookmarks.isEmpty)
        let manager = try XCTUnwrap(view.undoManager)
        manager.undo()
        XCTAssertEqual(view.string, text.string)
        XCTAssertNil(document.metadata.publishingTOCs)
        XCTAssertEqual(document.metadata.bookmarks, beforeBookmarks)
        manager.redo()
        XCTAssertEqual(view.string, inserted.string)
        XCTAssertEqual(document.metadata.publishingTOCs, settings)
        XCTAssertEqual(document.metadata.bookmarks, bookmarks)
        let tocRange = (view.string as NSString).range(of: "Contents")
        view.setSelectedRange(NSRange(location: tocRange.location, length: 0))
        var updated = try XCTUnwrap(settings?.first)
        updated.title = "Changed Contents"
        controller.updateSelectedTableOfContents(settings: updated, in: document)
        XCTAssertTrue(view.string.contains("Changed Contents"))
        manager.undo()
        XCTAssertEqual(view.string, inserted.string)
        XCTAssertEqual(document.metadata.publishingTOCs, settings)
        view.setSelectedRange(NSRange(location: tocRange.location, length: 0))
        controller.removeSelectedTableOfContents()
        XCTAssertEqual(view.string, text.string)
        XCTAssertEqual(document.metadata.publishingTOCs?.count, 0)
        manager.undo()
        XCTAssertEqual(view.string, inserted.string)
        XCTAssertEqual(document.metadata.publishingTOCs, settings)
    }

    func testThreeTOCPresetsSettingsPersistOnDynamicFields() throws {
        for mode in PublishingTOCMode.allCases {
            let doc=BOLDWriterDocument()
            let heading=NSMutableAttributedString(string:"Repeat\nRepeat\n")
            heading.addAttribute(.boldWriterStyle,value:WriterStyle.heading1.rawValue,range:NSRange(location:0,length:7))
            heading.addAttribute(.boldWriterStyle,value:WriterStyle.heading2.rawValue,range:NSRange(location:7,length:7))
            doc.replaceText(with:heading)
            let controller=EditorController(); let view=WritingTextView(frame:NSRect(x:0,y:0,width:600,height:800)); view.textStorage?.setAttributedString(doc.text); controller.document=doc; controller.attach(view)
            view.setSelectedRange(NSRange(location:doc.text.length,length:0))
            controller.insertTableOfContents(levels:6,mode:mode,title:"My Contents")
            let fields=NSMutableAttributedString(); view.textStorage?.enumerateAttribute(.boldWriterField,in:NSRange(location:0,length:view.textStorage?.length ?? 0)){v,r,_ in if let f=v as? WordField, f.instruction.contains("TOC") { fields.append(NSAttributedString(string:"x",attributes:[.boldWriterField:f])) } }
            let field=try XCTUnwrap(fields.attribute(.boldWriterField,at:0,effectiveRange:nil) as? WordField)
            let settings=try XCTUnwrap(doc.metadata.publishingTOCs?.first{$0.fieldID==field.id})
            XCTAssertEqual(settings.mode,mode); XCTAssertEqual(settings.maximumHeadingLevel,6); XCTAssertEqual(settings.title,"My Contents")
            if mode == .kindle {
                XCTAssertFalse(view.string.contains("?"))
                let contents=(view.string as NSString).range(of:"My Contents")
                let target=(view.string as NSString).range(of:"Repeat",options:[],range:NSRange(location:NSMaxRange(contents),length:view.string.utf16.count-NSMaxRange(contents)))
                XCTAssertNotEqual(target.location,NSNotFound)
                XCTAssertNotNil(view.textStorage!.attribute(.link,at:target.location,effectiveRange:nil))
                let source=view.string as NSString;let line=source.lineRange(for:NSRange(location:target.location,length:0))
                XCTAssertFalse(source.substring(with:line).contains("."))
            }
            let wrapper=try BOLDWriterDocument.packageWrapper(text:view.attributedString(),metadata:doc.metadata)
            let reopened=try BOLDWriterDocument(fileWrapper:wrapper,contentType:.boldWriterDocument)
            XCTAssertEqual(reopened.metadata.publishingTOCs,doc.metadata.publishingTOCs)
            XCTAssertTrue(reopened.text.string.contains("My Contents"))
        }
    }

    func testPrintTOCUsesCurrentPaginationAndDotLeaders() throws {
        let para="Pagination is driven by the real laid out page geometry and never by a character-count estimate. "
        let body=NSMutableAttributedString(string:"First Chapter\n"+Array(repeating:para,count:240).joined(separator:"\n")+"\nSecond Chapter\n")
        let source=body.string as NSString
        body.addAttribute(.boldWriterStyle,value:WriterStyle.heading1.rawValue,range:source.range(of:"First Chapter"))
        body.addAttribute(.boldWriterStyle,value:WriterStyle.heading1.rawValue,range:source.range(of:"Second Chapter"))
        let canvas=PaginatedEditor(text:body);canvas.configure(printLayout:true,settings:PageSettings(),zoom:1,viewportWidth:850);canvas.finishPagination()
        XCTAssertGreaterThan(canvas.pages.count,1)
        let document=BOLDWriterDocument();document.replaceText(with:body)
        let controller=EditorController();controller.document=document;controller.attach(canvas.firstView)
        let secondLocation=source.range(of:"Second Chapter").location
        let expected=try XCTUnwrap(canvas.displayPageNumber(containing:secondLocation))
        canvas.firstView.setSelectedRange(NSRange(location:body.length,length:0))
        controller.insertTableOfContents(levels:1,mode:.printBook)
        let tocTitle=try XCTUnwrap(canvas.firstView.string.range(of:"Contents"))
        let tocStart=canvas.firstView.string.index(after:tocTitle.upperBound)
        let firstLine=try XCTUnwrap(canvas.firstView.string.range(of:"First Chapter",range:tocStart..<canvas.firstView.string.endIndex))
        XCTAssertTrue(String(canvas.firstView.string[firstLine.lowerBound...].prefix(60)).contains("."))
        XCTAssertTrue(canvas.firstView.string.contains("Second Chapter"))
        let secondLine=try XCTUnwrap(canvas.firstView.string.range(of:"Second Chapter",range:tocStart..<canvas.firstView.string.endIndex))
        let lineEnd=canvas.firstView.string[secondLine.lowerBound...].firstIndex(of:"\n") ?? canvas.firstView.string.endIndex
        let tail=String(canvas.firstView.string[secondLine.lowerBound..<lineEnd])
        XCTAssertTrue(tail.contains(String(expected)),"TOC page entry should use live page \(expected): \(tail)")
        XCTAssertFalse(canvas.firstView.string.contains("Second Chapter"+String(repeating:".",count:20)))
    }

    func testEPUBNavigationIsNestedLinkedEscapedAndUsesUniqueHeadingAnchors() throws {
        let text=NSMutableAttributedString(string:"A & B\nRepeated\nRepeated\n")
        text.addAttribute(.boldWriterStyle,value:WriterStyle.heading1.rawValue,range:NSRange(location:0,length:6))
        text.addAttribute(.boldWriterStyle,value:WriterStyle.heading2.rawValue,range:NSRange(location:6,length:9))
        text.addAttribute(.boldWriterStyle,value:WriterStyle.heading2.rawValue,range:NSRange(location:15,length:9))
        let settings=PublishingTOCSettings(fieldID:UUID(),mode:.kindle,maximumHeadingLevel:2)
        let data=try EPUBExporter.data(from:text,title:"Book & Title",tocSettings:[settings])
        let entries=try DOCXPackage.entries(in:data)
        let nav=String(decoding:try XCTUnwrap(entries.first{$0.path=="OEBPS/nav.xhtml"}?.data),as:UTF8.self)
        let content=String(decoding:try XCTUnwrap(entries.first{$0.path=="OEBPS/content.xhtml"}?.data),as:UTF8.self)
        XCTAssertTrue(nav.contains("epub:type=\"toc\"")); XCTAssertTrue(nav.contains("content.xhtml#bold-heading-1")); XCTAssertTrue(nav.contains("A &amp; B")); XCTAssertTrue(nav.contains("<ol><li"))
        XCTAssertTrue(content.contains("id=\"bold-heading-1\"")); XCTAssertTrue(content.contains("id=\"bold-heading-2\"")); XCTAssertTrue(content.contains("id=\"bold-heading-3\""))
    }

    func testVisibleKindleContentsAndEPUBNavigationResolveTheSameHeadingAnchor() throws {
        let text=NSMutableAttributedString(string:"A linked chapter\nChapter 1\n")
        text.addAttribute(.boldWriterStyle,value:WriterStyle.heading1.rawValue,range:NSRange(location:17,length:9))
        text.addAttribute(.link,value:"#ChapterOne",range:NSRange(location:0,length:16))
        let bookmark=DocumentBookmark(name:"ChapterOne",location:17,length:9)
        let data=try EPUBExporter.data(from:text,title:"Book",bookmarks:[bookmark],tocSettings:[PublishingTOCSettings(fieldID:UUID(),mode:.kindle,maximumHeadingLevel:1)])
        let entries=try DOCXPackage.entries(in:data)
        let nav=String(decoding:try XCTUnwrap(entries.first{$0.path=="OEBPS/nav.xhtml"}?.data),as:UTF8.self)
        let content=String(decoding:try XCTUnwrap(entries.first{$0.path=="OEBPS/content.xhtml"}?.data),as:UTF8.self)
        XCTAssertTrue(nav.contains("content.xhtml#bold-heading-1"))
        XCTAssertTrue(content.contains("href=\"#bold-heading-1\""))
        XCTAssertTrue(content.contains("A linked chapter"))
    }


    func testResolutionQualityUsesSharedEffectiveDPIThresholds() {
        XCTAssertEqual(
            CoverCalculator
                .resolutionQuality(
                    effectiveDPI:
                        300,
                    targetDPI:
                        300
                ),
            .good
        )

        XCTAssertEqual(
            CoverCalculator
                .resolutionQuality(
                    effectiveDPI:
                        299,
                    targetDPI:
                        300
                ),
            .marginal
        )

        XCTAssertEqual(
            CoverCalculator
                .resolutionQuality(
                    effectiveDPI:
                        210,
                    targetDPI:
                        300
                ),
            .marginal
        )

        XCTAssertEqual(
            CoverCalculator
                .resolutionQuality(
                    effectiveDPI:
                        209.9,
                    targetDPI:
                        300
                ),
            .low
        )

        XCTAssertEqual(
            CoverCalculator
                .resolutionQuality(
                    effectiveDPI:
                        .nan,
                    targetDPI:
                        300
                ),
            .low
        )
    }

    func testEffectiveDPIStatusMatchesLegacyPixelStatus() {
        XCTAssertEqual(
            CoverCalculator
                .resolutionStatus(
                    effectiveDPI:
                        300,
                    targetDPI:
                        300
                ),
            "good resolution"
        )

        XCTAssertEqual(
            CoverCalculator
                .resolutionStatus(
                    effectiveDPI:
                        225,
                    targetDPI:
                        300
                ),
            "marginal resolution"
        )

        XCTAssertEqual(
            CoverCalculator
                .resolutionStatus(
                    effectiveDPI:
                        150,
                    targetDPI:
                        300
                ),
            "low resolution"
        )

        XCTAssertEqual(
            CoverCalculator
                .resolutionStatus(
                    pixelWidth:
                        1800,
                    pixelHeight:
                        2700,
                    displayedWidthInches:
                        6,
                    displayedHeightInches:
                        9,
                    targetDPI:
                        300
                ),
            CoverCalculator
                .resolutionStatus(
                    effectiveDPI:
                        300,
                    targetDPI:
                        300
                )
        )
    }

    func testCoverCalculatorSpineBleedSafeZonesAndResolutionWarnings() throws {
        XCTAssertEqual(try CoverCalculator.spineWidth(pageCount:200,caliperInches:0.0025),0.5,accuracy:0.0001)
        let result=try CoverCalculator.fullWrap(trimWidth:6,trimHeight:9,spineWidth:0.5,bleed:0.125)
        XCTAssertEqual(result.totalWidthInches,12.75,accuracy:0.0001); XCTAssertEqual(result.totalHeightInches,9.25,accuracy:0.0001)
        XCTAssertEqual(result.pixels(dpi:300).width,3825)
        let safe=CoverCalculator.safeRect(trim:CoverRect(x:0,y:0,width:6,height:9))
        XCTAssertEqual(safe.x,0.3,accuracy:0.001); XCTAssertEqual(safe.width,5.4,accuracy:0.001)
        XCTAssertEqual(CoverCalculator.resolutionStatus(pixelWidth:1800,pixelHeight:2700,displayedWidthInches:6,displayedHeightInches:9),"good resolution")
        XCTAssertEqual(CoverCalculator.resolutionStatus(pixelWidth:500,pixelHeight:700,displayedWidthInches:6,displayedHeightInches:9),"low resolution")
    }

    func testKDPWhitePaper555PageRegressionAndRepresentativeCalipers() throws {
        XCTAssertEqual(PrintCoverSpecification.kdpBlackAndWhiteWhitePaperCaliper,0.002252,accuracy:0.0000000001)
        XCTAssertEqual(PrintCoverSpecification.kdpBlackAndWhiteCreamPaperCaliper,0.0025,accuracy:0.0000000001)
        XCTAssertEqual(try CoverCalculator.kdpWhitePaperSpineWidth(pageCount:100),0.2252,accuracy:0.000001)
        XCTAssertEqual(try CoverCalculator.kdpWhitePaperSpineWidth(pageCount:200),0.4504,accuracy:0.000001)
        let spine=try CoverCalculator.kdpWhitePaperSpineWidth(pageCount:555)
        XCTAssertEqual(spine,1.24986,accuracy:0.000001)
        XCTAssertEqual(CoverCalculator.inferredPageCount(spineWidth:spine,caliperInches:PrintCoverSpecification.kdpBlackAndWhiteWhitePaperCaliper),555)
        let dimensions=try CoverCalculator.fullWrap(backWidth:6,frontWidth:6,trimHeight:9,spineWidth:spine,bleed:0.125)
        XCTAssertEqual(dimensions.totalWidthInches,13.49986,accuracy:0.000001)
        XCTAssertEqual(dimensions.totalHeightInches,9.25,accuracy:0.000001)
        XCTAssertEqual(try CoverCalculator.kdpCreamPaperSpineWidth(pageCount:200),0.5,accuracy:0.000001)
    }

    func testActiveCoverProjectIdentityPersistsAndMissingIdentityFallsBack() throws {
        var ebook=CoverProject();ebook.name="Blank eBook"
        var print=CoverProject(type:.printFullWrap,width:13.49986,height:9.25);print.name="Print Full Wrap";print.spinePageCount=555;print.spineCaliperInches=PrintCoverSpecification.kdpBlackAndWhiteWhitePaperCaliper
        let document=BOLDWriterDocument();document.replaceText(with:NSAttributedString(string:"Manuscript"));document.metadata.coverProjects=[ebook,print];document.metadata.activeCoverProjectID=print.id
        let wrapper=try BOLDWriterDocument.packageWrapper(text:document.text,metadata:document.metadata)
        let reopened=try BOLDWriterDocument(fileWrapper:wrapper,contentType:.boldWriterDocument)
        XCTAssertEqual(reopened.metadata.activeCoverProjectID,print.id)
        XCTAssertEqual(reopened.metadata.coverProjects?.first{$0.id == reopened.metadata.activeCoverProjectID}?.name,"Print Full Wrap")
        XCTAssertEqual(reopened.metadata.coverProjects?.first{$0.id == print.id}?.spinePageCount,555)
        var legacy=DocumentMetadata();legacy.coverProjects=[ebook,print]
        let oldWrapper=try BOLDWriterDocument.packageWrapper(text:document.text,metadata:legacy)
        XCTAssertNoThrow(try BOLDWriterDocument(fileWrapper:oldWrapper,contentType:.boldWriterDocument))
        XCTAssertNil(try BOLDWriterDocument(fileWrapper:oldWrapper,contentType:.boldWriterDocument).metadata.activeCoverProjectID)
        var stale=DocumentMetadata();stale.coverProjects=[ebook,print];stale.activeCoverProjectID=UUID()
        XCTAssertFalse(stale.coverProjects?.contains{$0.id == stale.activeCoverProjectID} ?? true)
    }

    func testPrintRegionGeometryPlacementUndoFriendlyAndPrintPDFContent() throws {
        let red=try CoverEditorEngine.filledImage(width:64,height:64,color:.red)
        let blue=try CoverEditorEngine.filledImage(width:64,height:64,color:.blue)
        let green=try CoverEditorEngine.filledImage(width:64,height:64,color:.green)
        var p=CoverProject(type:.printFullWrap,width:13.49986,height:9.25);p.dpi=48;p.trimWidth=6;p.trimHeight=9;p.backWidth=6;p.spineWidth=1.24986;p.bleed=0.125
        let geometry=CoverWrapGeometry(project:p)
        XCTAssertEqual(geometry.backTrim.x,0.125/p.canvasWidth,accuracy:0.000001)
        XCTAssertEqual(geometry.spineTrim.width,1.24986/p.canvasWidth,accuracy:0.000001)
        XCTAssertEqual(geometry.frontTrim.x,(0.125+6+1.24986)/p.canvasWidth,accuracy:0.000001)
        XCTAssertEqual(geometry.back.x,0);XCTAssertEqual(geometry.back.height,1)
        XCTAssertEqual(geometry.front.x+geometry.front.width,1,accuracy:0.000001)
        var back=try CoverArtwork.imageLayer(data:red,filename:"back",frame:CoverRect())
        let spine=try CoverArtwork.imageLayer(data:blue,filename:"spine",frame:CoverRect())
        let front=try CoverArtwork.imageLayer(data:green,filename:"front",frame:CoverRect())
        back=CoverCalculator.placement(back,in:p,region:geometry.backTrim,fill:true)
        let placedSpine=CoverCalculator.placement(spine,in:p,region:geometry.spine,fill:true)
        let placedFront=CoverCalculator.placement(front,in:p,region:geometry.front,fill:false)
        XCTAssertEqual(placedSpine.frame,geometry.spine)
        XCTAssertEqual(placedSpine.cropMode,.fill);XCTAssertEqual(placedFront.cropMode,.fit)
        p.layers=[spine];let original=p.layers[0];var undo:[CoverProject]=[],redo:[CoverProject]=[]
        CoverProjectHistory.placeImage(project:&p,layerID:spine.id,region:geometry.spine,fill:true,undo:&undo,redo:&redo)
        XCTAssertNotEqual(p.layers[0],original)
        CoverProjectHistory.undo(project:&p,undo:&undo,redo:&redo);XCTAssertEqual(p.layers[0],original)
        CoverProjectHistory.redo(project:&p,undo:&undo,redo:&redo);XCTAssertNotEqual(p.layers[0],original)
        var guide=try CoverArtwork.imageLayer(data:green,filename:"KDP guide",frame:CoverRect());guide.kind = .template;guide.locked=true
        p.layers=[back,placedSpine,placedFront,guide]
        let document=BOLDWriterDocument();document.replaceText(with:NSAttributedString(string:"Manuscript"));document.metadata.coverProjects=[p];document.metadata.activeCoverProjectID=p.id
        let reopened=try BOLDWriterDocument(fileWrapper:BOLDWriterDocument.packageWrapper(text:document.text,metadata:document.metadata),contentType:.boldWriterDocument)
        let exportProject=try XCTUnwrap(reopened.metadata.coverProjects?.first)
        let pdf=try CoverArtwork.export(exportProject,format:"pdf")
        let pdfDocument=try XCTUnwrap(PDFDocument(data:pdf));XCTAssertEqual(pdfDocument.pageCount,1)
        let page=try XCTUnwrap(pdfDocument.page(at:0));let box=page.bounds(for:.mediaBox)
        XCTAssertEqual(box.width,13.49986*72,accuracy:0.001);XCTAssertEqual(box.height,9.25*72,accuracy:0.001)
        let preview=page.thumbnail(of:NSSize(width:540,height:370),for:.mediaBox)
        let imageData=try XCTUnwrap(preview.tiffRepresentation);let bitmap=try XCTUnwrap(NSBitmapImageRep(data:imageData))
        func sample(_ x:Double)->NSColor { bitmap.colorAt(x:Int(x*Double(bitmap.pixelsWide)),y:bitmap.pixelsHigh/2)!.usingColorSpace(.deviceRGB)! }
        XCTAssertGreaterThan(sample(0.10).redComponent,sample(0.10).blueComponent)
        XCTAssertGreaterThan(sample(0.50).blueComponent,sample(0.50).redComponent)
        XCTAssertGreaterThan(sample(0.86).greenComponent,sample(0.86).redComponent)
        XCTAssertEqual(exportProject.layers.last?.kind,.template)
        XCTAssertNotEqual(pdf,try CoverArtwork.export(exportProject,format:"pdf",proof:true))
    }

    func testCoverTemplateImageLayersPersistenceAndFinalProofExports() throws {
        let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:1200,pixelsHigh:1800,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap); NSColor.blue.setFill(); NSBezierPath(rect:NSRect(x:0,y:0,width:1200,height:1800)).fill(); NSGraphicsContext.restoreGraphicsState()
        let png=try XCTUnwrap(bitmap.representation(using:.png,properties:[:]))
        var layer=try CoverArtwork.imageLayer(data:png,filename:"art.png",frame:CoverRect(x:0.1,y:0.1,width:0.8,height:0.8));layer.rotation=12;layer.opacity=0.8;layer.flipHorizontal=true;layer.cropMode = .free
        let template=try CoverArtwork.importedTemplate(data:png,filename:"guide.png")
        let jpegTemplateData=try XCTUnwrap(bitmap.representation(using:.jpeg,properties:[:]))
        let jpegTemplate=try CoverArtwork.importedTemplate(data:jpegTemplateData,filename:"guide.jpg")
        XCTAssertEqual(jpegTemplate.kind,.template)
        var project=CoverProject(); project.layers=[layer,template]
        var text=CoverLayer(kind:.text,name:"Spine",frame:CoverRect(x:0.4,y:0.2,width:0.2,height:0.6));text.text="Title";text.rotation=90
        var shape=CoverLayer(kind:.shape,name:"Panel");shape.shape = .rectangle
        project.layers += [text,shape]
        let firstID=project.layers[0].id;let copyID=try XCTUnwrap(project.duplicateLayer(firstID));XCTAssertEqual(project.layers.last?.id,copyID);project.moveLayer(copyID,by:-1);XCTAssertEqual(project.layers[project.layers.count-2].id,copyID);project.deleteLayer(copyID);XCTAssertFalse(project.layers.contains{$0.id==copyID})
        let doc=BOLDWriterDocument();doc.replaceText(with:NSAttributedString(string:"Manuscript"));doc.metadata.coverProjects=[project]
        let wrapper=try BOLDWriterDocument.packageWrapper(text:doc.text,metadata:doc.metadata)
        let restored=try BOLDWriterDocument(fileWrapper:wrapper,contentType:.boldWriterDocument)
        let saved=try XCTUnwrap(restored.metadata.coverProjects?.first)
        XCTAssertEqual(saved,project); XCTAssertEqual(saved.layers.count,4); XCTAssertEqual(saved.layers[2].rotation,90)
        let pngOut=try CoverArtwork.export(saved,format:"png")
        let image=try XCTUnwrap(NSBitmapImageRep(data:pngOut)); XCTAssertEqual(image.pixelsWide,1800); XCTAssertEqual(image.pixelsHigh,2700)
        let jpegOut=try CoverArtwork.export(saved,format:"jpeg");let jpeg=try XCTUnwrap(NSBitmapImageRep(data:jpegOut));XCTAssertEqual(jpeg.pixelsWide,1800);XCTAssertEqual(jpeg.pixelsHigh,2700)
        let proof=try CoverArtwork.export(saved,format:"png",proof:true); XCTAssertGreaterThan(proof.count,pngOut.count/2)
        let old=DocumentMetadata(); let oldWrapper=try BOLDWriterDocument.packageWrapper(text:doc.text,metadata:old); XCTAssertNoThrow(try BOLDWriterDocument(fileWrapper:oldWrapper,contentType:.boldWriterDocument))
        var invalid=project; invalid.dpi = .nan; XCTAssertThrowsError(try CoverProject.validate([invalid]))
        var badTOC=PublishingTOCSettings(fieldID:UUID(),mode:.printBook);badTOC.maximumHeadingLevel=9;XCTAssertThrowsError(try PublishingTOCSettings.validate([badTOC]))
        let originalChildren=try XCTUnwrap(wrapper.fileWrappers)
        let metadataData=try XCTUnwrap(originalChildren["metadata.json"]?.regularFileContents)
        var metadataObject=try XCTUnwrap(JSONSerialization.jsonObject(with:metadataData) as? [String:Any]);metadataObject["coverProjects"]=[["invalid":true]]
        let corruptData=try JSONSerialization.data(withJSONObject:metadataObject)
        let corrupt=FileWrapper(directoryWithFileWrappers:["content.rtfd":try XCTUnwrap(originalChildren["content.rtfd"]),"metadata.json":FileWrapper(regularFileWithContents:corruptData)])
        XCTAssertThrowsError(try BOLDWriterDocument(fileWrapper:corrupt,contentType:.boldWriterDocument))
    }

    func testOnePagePDFTemplateAndPrintPhysicalDimensions() throws {
        var rect=CGRect(x:0,y:0,width:612,height:792);let data=NSMutableData()
        let consumer=try XCTUnwrap(CGDataConsumer(data:data as CFMutableData));let context=try XCTUnwrap(CGContext(consumer:consumer,mediaBox:&rect,nil));context.beginPDFPage(nil);context.endPDFPage();context.closePDF()
        let template=try CoverArtwork.importedTemplate(data:data as Data,filename:"template.pdf",widthInches:8.5,heightInches:11)
        XCTAssertEqual(template.kind,.template);XCTAssertTrue(template.locked)
        var project=CoverProject(type:.printFullWrap,width:13,height:9.25);project.trimWidth=6;project.trimHeight=9;project.spineWidth=0.5;project.bleed=0.125;project.layers=[template]
        let pdf=try CoverArtwork.export(project,format:"pdf")
        let page=try XCTUnwrap(PDFDocument(data:pdf)?.page(at:0));XCTAssertEqual(page.bounds(for:.mediaBox).width,13*72,accuracy:1);XCTAssertEqual(page.bounds(for:.mediaBox).height,9.25*72,accuracy:1)
    }
}
