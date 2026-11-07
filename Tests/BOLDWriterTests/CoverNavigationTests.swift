import XCTest
@testable import BOLDWriter

final class CoverNavigationTests: XCTestCase {
    func testPanZoomRotateAndResetAreViewportOnlyOperations() {
        var viewport=CoverViewport();let layer=CoverLayer(kind:.shape,name:"Cover Art",frame:CoverRect(x:0.2,y:0.3,width:0.4,height:0.5));let original=layer
        viewport.panBy(CGSize(width:34,height:-12));viewport.zoomAt(CGPoint(x:100,y:80),factor:2)
        XCTAssertEqual(viewport.zoom,2);XCTAssertEqual(viewport.pan.x,-32,accuracy:0.001);XCTAssertEqual(viewport.pan.y,-104,accuracy:0.001)
        viewport.rotateBy(22);XCTAssertEqual(viewport.rotation,22);XCTAssertEqual(layer,original)
        viewport.reset();XCTAssertEqual(viewport,CoverViewport());XCTAssertEqual(layer.frame.width,0.4)
    }

    func testZoomBoundsAndSelectionFitKeepDocumentDimensionsIndependent() {
        var viewport=CoverViewport(zoom:1.5);viewport.zoomAt(.zero,factor:100)
        XCTAssertEqual(viewport.zoom,8);viewport.zoomAt(.zero,factor:0.001);XCTAssertEqual(viewport.zoom,0.1)
        viewport.fitSelection(CGRect(x:20,y:10,width:40,height:20),viewport:CGSize(width:200,height:100))
        XCTAssertEqual(viewport.zoom,5);XCTAssertEqual(viewport.pan,CGPoint(x:-100,y:-50))
        let cover=CoverProject(type:.printFullWrap,width:12.79,height:9.25);XCTAssertEqual(cover.canvasWidth,12.79)
    }

    func testCursorAnchoredZoomAndRotatedCoordinateConversionsRoundTrip() {
        var viewport=CoverViewport(zoom:2,pan:CGPoint(x:15,y:-7),rotation:27)
        let center=CGPoint(x:300,y:200),cursor=CGPoint(x:188,y:142),doc=viewport.documentPoint(for:cursor,center:center)
        let stationary=viewport.viewPoint(for:doc,center:center)
        viewport.zoomAt(cursor,center:center,factor:1.5)
        XCTAssertEqual(viewport.viewPoint(for:doc,center:center).x,stationary.x,accuracy:0.0001)
        XCTAssertEqual(viewport.viewPoint(for:doc,center:center).y,stationary.y,accuracy:0.0001)
    }

    func testDocumentCanvasCoordinatesRoundTripAtEditingZoomLevelsAndPanOffsets() {
        let center = CGPoint(x: 512, y: 384)
        let pointer = CGPoint(x: 271.25, y: 612.75)
        let panOffsets = [CGPoint.zero, CGPoint(x: 83, y: -47)]

        for zoom in [0.25, 0.5, 1.0, 2.0, 5.0] {
            for pan in panOffsets {
                let viewport = CoverViewport(zoom: zoom, pan: pan, rotation: 0)
                let documentPoint = viewport.documentPoint(for: pointer, center: center)
                let restoredPointer = viewport.viewPoint(for: documentPoint, center: center)

                XCTAssertEqual(restoredPointer.x, pointer.x, accuracy: 0.0001,
                               "Pointer X must remain aligned at zoom \(zoom), pan \(pan).")
                XCTAssertEqual(restoredPointer.y, pointer.y, accuracy: 0.0001,
                               "Pointer Y must remain aligned at zoom \(zoom), pan \(pan).")
            }
        }
    }
}
