import AppKit
import XCTest
import SceneKit
import ImageIO
@testable import BOLDWriter

@MainActor
final class CoverPanelWorkflowTests: XCTestCase {
    func testPageEntryKeepsTypedDigitsAndEvenPageUntilExplicitNavigation() {
        var entry = BookStudioPageEntry()
        for text in ["1","10","100"] { entry.text=text; XCTAssertEqual(entry.text,text) }
        XCTAssertEqual(entry.resolvedPage(pageCount:160),100)
        entry.synchronize(spreadIndex:50,pageCount:160)
        XCTAssertEqual(entry.text,"100","Page 100 is on spread 100/101; do not rewrite it as 101")
        entry.synchronize(spreadIndex:51,pageCount:160);XCTAssertEqual(entry.text,"103")
        entry.text="invalid";XCTAssertNil(entry.resolvedPage(pageCount:160))
        entry.text="999";XCTAssertEqual(entry.resolvedPage(pageCount:160),160)
        entry.text="0";XCTAssertEqual(entry.resolvedPage(pageCount:160),1)
    }
    private func project() -> CoverProject {
        var p=CoverProject(type:.printFullWrap,width:13.25,height:9.25)
        p.backWidth=6;p.trimWidth=6;p.trimHeight=9;p.spineWidth=1;p.bleed=0.125
        p.layers=[CoverLayer(kind:.shape,name:"Artwork",frame:CoverRect(x:0.2,y:0.2,width:0.2,height:0.2))]
        return p
    }
    func testSingleArtworkAlignsToCanvasAndPanelThroughCommandEngine() throws {
        var p=project();let id=p.layers[0].id.uuidString
        for (edge,reference) in [("left","canvas"),("centerX","front"),("bottom","back")] {
            let command=try BOLDTerminalCommandParser.parse(["cover","edit","align","layerID="+id,"edge="+edge,"reference="+reference])
            try CoverProjectOperations.apply("align",to:&p,arguments:command.arguments)
            if edge=="left" {XCTAssertEqual(p.layers[0].frame.x,0)}
            if edge=="centerX" {let r=CoverWrapGeometry(project:p).frontTrim;XCTAssertEqual(p.layers[0].frame.x+p.layers[0].frame.width/2,r.x+r.width/2,accuracy:1e-10)}
            if edge=="bottom" {let r=CoverWrapGeometry(project:p).backTrim;XCTAssertEqual(p.layers[0].frame.y+p.layers[0].frame.height,r.y+r.height,accuracy:1e-10)}
        }
    }
    func testCommandAlignsRotatedArtworkByItsVisibleEdge() throws {
        var p = project()
        p.layers[0].rotation = 45
        let id = p.layers[0].id.uuidString
        let front = CoverWrapGeometry(project: p).frontTrim
        try CoverProjectOperations.apply("align", to: &p,
                                         arguments: ["layerID": id, "edge": "left", "reference": "front"])
        let layer = p.layers[0]
        let angle = Double.pi / 4
        let visibleWidth = abs(cos(angle)) * layer.frame.width
            + abs(sin(angle)) * layer.frame.height * p.canvasHeight / p.canvasWidth
        XCTAssertEqual(layer.frame.x + (layer.frame.width - visibleWidth) / 2,
                       front.x, accuracy: 0.000001)
        XCTAssertEqual(layer.rotation, 45)
        XCTAssertEqual(layer.id.uuidString, id)
    }
    func testAutoFitUsesBleedAndWrapButKeepsSpineInsideBorders() throws {
        for hardcover in [false,true] {
            var p=project()
            if hardcover { p.canvasWidth=19.469;p.canvasHeight=12.417;p.trimWidth=8.25;p.backWidth=8.25;p.trimHeight=11;p.spineWidth=1.394;p.bleed=0;p.kdpHardcoverLayout=KDPHardcoverLayout(canvasWidth:19.469,canvasHeight:12.417,trimWidth:8.25,trimHeight:11,spineWidth:1.394,pageCount:535) }
            let g=CoverWrapGeometry(project:p)
            for (panel,expected) in [("front",g.front),("back",g.back),("spine",g.spineTrim)] {
                try CoverProjectOperations.apply("fit-panel",to:&p,arguments:["layerID":p.layers[0].id.uuidString,"panel":panel])
                XCTAssertEqual(p.layers[0].frame,expected)
                XCTAssertEqual(p.layers[0].rotation,0)
            }
            XCTAssertEqual(p.canvasWidth,g.physicalWidth);XCTAssertEqual(p.canvasHeight,g.physicalHeight)
        }
    }
    func testInvalidFitAndLockedArtworkAreAtomic() throws {
        var p=project();let id=p.layers[0].id.uuidString
        for args in [["layerID":id,"panel":"unknown"],["layerID":id,"panel":"front","includeBleed":"yes"],["layerID":id,"edge":"left","reference":"selection"]] {
            let before=p
            XCTAssertThrowsError(try CoverProjectOperations.apply(args["edge"] == nil ? "fit-panel":"align",to:&p,arguments:args))
            XCTAssertEqual(p,before)
        }
        p.layers[0].positionLocked=true;let before=p
        XCTAssertThrowsError(try CoverProjectOperations.apply("fit-panel",to:&p,arguments:["layerID":id,"panel":"front"]))
        XCTAssertEqual(p,before)
    }
    func testExportedArtworkReimportsUprightFromPNGAndPDF() throws {
        var p=CoverProject(width:1,height:1);p.dpi=72
        var top=CoverLayer(kind:.shape,name:"Top",frame:CoverRect(x:0,y:0,width:1,height:0.5));top.fillHex="#FF0000";top.strokeWidth=0
        var bottom=CoverLayer(kind:.shape,name:"Bottom",frame:CoverRect(x:0,y:0.5,width:1,height:0.5));bottom.fillHex="#0000FF";bottom.strokeWidth=0
        p.layers=[top,bottom]
        for format in ["png","pdf"] {
            let bytes=try CoverArtwork.export(p,format:format)
            var q=CoverProject(width:1,height:1);q.dpi=72
            q.layers=[try CoverArtwork.imageLayer(data:bytes,filename:"cover."+format,frame:CoverRect(x:0,y:0,width:1,height:1))]
            let original=try CoverArtwork.render(p,scale:72),reopened=try CoverArtwork.render(q,scale:72)
            let a=try XCTUnwrap(NSBitmapImageRep(data:original.tiffRepresentation!)),b=try XCTUnwrap(NSBitmapImageRep(data:reopened.tiffRepresentation!))
            for (x,y) in [(18,18),(18,54),(54,18),(54,54)] {
                let c=try XCTUnwrap(a.colorAt(x:x,y:y)?.usingColorSpace(.deviceRGB)),d=try XCTUnwrap(b.colorAt(x:x,y:y)?.usingColorSpace(.deviceRGB))
                XCTAssertEqual(c.redComponent > c.blueComponent, d.redComponent > d.blueComponent, format)
                XCTAssertGreaterThan(abs(d.redComponent-d.blueComponent),0.4,format)
            }
        }
    }
    func testProductionMarginsToggleWithoutChangingFinishedArtworkOrBoardGeometry() throws {
        let p=project()
        let scene=BookPreviewScene.make(project:p,workingLayers:false,open:false,angle:0,leftPage:nil,rightPage:nil,pageCount:200,spreadIndex:0,leftTexture:nil,rightTexture:nil,margins:false,thumbMode:.off,leftPageSettings:PageSettings(),rightPageSettings:PageSettings(),preset:.perspective,revisionID:UUID())
        let front=try XCTUnwrap(scene.rootNode.childNode(withName:"book-shell.front-cover",recursively:true))
        let board=try XCTUnwrap(front.geometry)
        let before=board.boundingBox
        let guide=try XCTUnwrap(front.childNode(withName:BookProductionMarginGuides.prefix+"front",recursively:false))
        XCTAssertTrue(guide.isHidden)
        BookProductionMarginGuides.setVisible(true,in:scene.rootNode)
        XCTAssertFalse(guide.isHidden)
        XCTAssertEqual(board.boundingBox.min.x,before.min.x);XCTAssertEqual(board.boundingBox.max.y,before.max.y)
        BookProductionMarginGuides.setVisible(false,in:scene.rootNode)
        XCTAssertTrue(guide.isHidden)
        let command=try BOLDTerminalCommandParser.parse(["studio","camera","perspective","productionMargins=true"])
        XCTAssertEqual(command.arguments["productionMargins"],"true")
        XCTAssertThrowsError(try BOLDTerminalCommandParser.parse(["studio","camera","perspective","productionMargins=maybe"]))
        var presentation=BookStudioPresentation();presentation.showProductionMargins=true
        let restored=try JSONDecoder().decode(BookStudioPresentation.self,from:JSONEncoder().encode(presentation))
        XCTAssertEqual(restored.showProductionMargins,true)
        XCTAssertEqual(try JSONDecoder().decode(BookStudioPresentation.self,from:Data("{}".utf8)).showProductionMargins,nil)
    }

    func testRasterExportsRetainPrintResolutionWhenOpenedAsArtwork() throws {
        var p=project();p.dpi=300
        for format in ["png","jpg"] {
            let data=try CoverArtwork.export(p,format:format)
            let source=try XCTUnwrap(CGImageSourceCreateWithData(data as CFData,nil))
            let properties=try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any])
            XCTAssertEqual(try XCTUnwrap(properties[kCGImagePropertyDPIWidth] as? Double),300,accuracy:0.02)
            XCTAssertEqual(try XCTUnwrap(properties[kCGImagePropertyDPIHeight] as? Double),300,accuracy:0.02)
            let reopened=try CoverImport.project(data:data,filename:"cover."+format)
            XCTAssertEqual(reopened.canvasWidth,p.canvasWidth,accuracy:1/p.dpi)
            XCTAssertEqual(reopened.canvasHeight,p.canvasHeight,accuracy:1/p.dpi)
        }
    }

}
