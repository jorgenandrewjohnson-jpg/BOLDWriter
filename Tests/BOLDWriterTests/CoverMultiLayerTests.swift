import XCTest
@testable import BOLDWriter

final class CoverMultiLayerTests: XCTestCase {
    private func visibleBounds(_ layer: CoverLayer, canvas: CGSize) -> CGRect {
        let angle = layer.rotation * .pi / 180
        let aspect = Double(canvas.height / canvas.width)
        let width = abs(cos(angle)) * layer.frame.width
            + abs(sin(angle)) * layer.frame.height * aspect
        let height = abs(sin(angle)) * layer.frame.width / aspect
            + abs(cos(angle)) * layer.frame.height
        return CGRect(x: layer.frame.x + (layer.frame.width - width) / 2,
                      y: layer.frame.y + (layer.frame.height - height) / 2,
                      width: width, height: height)
    }

    func testTransformHandlesEncloseRotatedGroupOnPhysicalCoverCanvas() throws {
        let canvas = CGSize(width: 12, height: 8)
        var rotated = CoverLayer(kind: .image, name: "Rotated front",
                                 frame: CoverRect(x: 0.2, y: 0.25, width: 0.2, height: 0.1))
        rotated.rotation = 90
        let spine = CoverLayer(kind: .text, name: "Spine lettering",
                               frame: CoverRect(x: 0.55, y: 0.2, width: 0.08, height: 0.4))
        let bounds = try XCTUnwrap(CoverEditorEngine.transformBounds(
            [rotated, spine], ids: [rotated.id, spine.id], canvasSize: canvas))
        let expected = visibleBounds(rotated, canvas: canvas)
            .union(visibleBounds(spine, canvas: canvas))
        XCTAssertEqual(bounds.minX, expected.minX, accuracy: 0.000001)
        XCTAssertEqual(bounds.minY, expected.minY, accuracy: 0.000001)
        XCTAssertEqual(bounds.width, expected.width, accuracy: 0.000001)
        XCTAssertEqual(bounds.height, expected.height, accuracy: 0.000001)
        XCTAssertLessThan(visibleBounds(rotated, canvas: canvas).minY, rotated.frame.y,
                          "A 90° image must not escape its visible transform handles.")
        var locked = spine
        locked.locked = true
        let unlockedBounds = try XCTUnwrap(CoverEditorEngine.transformBounds(
            [rotated, locked], ids: [rotated.id, locked.id], canvasSize: canvas))
        let rotatedOnly = visibleBounds(rotated, canvas: canvas)
        XCTAssertEqual(unlockedBounds.minX, rotatedOnly.minX, accuracy: 0.000001)
        XCTAssertEqual(unlockedBounds.minY, rotatedOnly.minY, accuracy: 0.000001)
        XCTAssertEqual(unlockedBounds.width, rotatedOnly.width, accuracy: 0.000001)
        XCTAssertEqual(unlockedBounds.height, rotatedOnly.height, accuracy: 0.000001)
    }

    func testRotatedAlignmentUsesVisibleBoundsOnNonSquareCover() {
        let canvas = CGSize(width: 1000, height: 500)
        var image = CoverLayer(kind: .image, name: "Rotated art",
                               frame: CoverRect(x: 0.12, y: 0.2, width: 0.1, height: 0.2))
        image.rotation = 45
        var layers = [image]
        let reference = CGRect(x: 0.55, y: 0.1, width: 0.3, height: 0.7)
        CoverEditorEngine.align(&layers, ids: [image.id], edge: .left,
                                reference: reference, canvasSize: canvas)
        XCTAssertEqual(visibleBounds(layers[0], canvas: canvas).minX, reference.minX, accuracy: 0.000001)
        CoverEditorEngine.align(&layers, ids: [image.id], edge: .bottom,
                                reference: reference, canvasSize: canvas)
        XCTAssertEqual(visibleBounds(layers[0], canvas: canvas).maxY, reference.maxY, accuracy: 0.000001)
        XCTAssertEqual(layers[0].rotation, 45)
        XCTAssertEqual(layers[0].id, image.id)
    }

    func testDistributionEvenlySpacesRotatedVisibleArtwork() {
        let canvas = CGSize(width: 1000, height: 500)
        var layers = [
            CoverLayer(kind: .shape, name: "A", frame: CoverRect(x: 0.1, y: 0.2, width: 0.1, height: 0.2)),
            CoverLayer(kind: .shape, name: "B", frame: CoverRect(x: 0.4, y: 0.2, width: 0.12, height: 0.15)),
            CoverLayer(kind: .shape, name: "C", frame: CoverRect(x: 0.8, y: 0.2, width: 0.1, height: 0.2))
        ]
        layers[0].rotation = 45
        layers[1].rotation = 30
        let firstBefore = visibleBounds(layers[0], canvas: canvas).minX
        let lastBefore = visibleBounds(layers[2], canvas: canvas).maxX
        CoverEditorEngine.distribute(&layers, ids: Set(layers.map(\.id)), axis: .horizontal,
                                     canvasSize: canvas)
        let bounds = layers.map { visibleBounds($0, canvas: canvas) }
        XCTAssertEqual(bounds[0].minX, firstBefore, accuracy: 0.000001)
        XCTAssertEqual(bounds[2].maxX, lastBefore, accuracy: 0.000001)
        XCTAssertEqual(bounds[1].minX - bounds[0].maxX,
                       bounds[2].minX - bounds[1].maxX, accuracy: 0.000001)
        XCTAssertEqual(layers.map(\.rotation), [45, 30, 0])
    }

    func testMultiLayerMoveAndAlignmentPreserveRelativeGeometryAndIDs() {
        var a=CoverLayer(kind:.shape,name:"A",frame:CoverRect(x:0.1,y:0.1,width:0.1,height:0.1)),b=CoverLayer(kind:.text,name:"B",frame:CoverRect(x:0.4,y:0.3,width:0.2,height:0.1))
        let ids:Set<UUID>=[a.id,b.id];var layers=[a,b];CoverEditorEngine.moveLayers(&layers,ids:ids,dx:0.05,dy:0.1)
        XCTAssertEqual(layers[1].frame.x-layers[0].frame.x,0.3,accuracy:0.0001);XCTAssertEqual(layers[0].frame.y,0.2,accuracy:0.0001)
        CoverEditorEngine.align(&layers,ids:ids,edge:.centerX)
        XCTAssertEqual(layers[0].frame.x+layers[0].frame.width/2,layers[1].frame.x+layers[1].frame.width/2,accuracy:0.0001)
        XCTAssertEqual(layers.map(\.id),[a.id,b.id])
        a.locked=true;layers=[a,b];CoverEditorEngine.moveLayers(&layers,ids:ids,dx:0.2,dy:0.2);XCTAssertEqual(layers[0].frame.x,a.frame.x)
    }

    func testDistributionEvenlySpacesThreeLayerBounds() {
        var layers=[CoverLayer(kind:.shape,name:"A",frame:CoverRect(x:0,y:0,width:0.1,height:0.1)),CoverLayer(kind:.shape,name:"B",frame:CoverRect(x:0.3,y:0,width:0.2,height:0.1)),CoverLayer(kind:.shape,name:"C",frame:CoverRect(x:0.8,y:0,width:0.1,height:0.1))]
        let ids=Set(layers.map(\.id));CoverEditorEngine.distribute(&layers,ids:ids,axis:.horizontal)
        XCTAssertEqual(layers[0].frame.x,0,accuracy:0.0001);XCTAssertEqual(layers[1].frame.x,0.35,accuracy:0.0001);XCTAssertEqual(layers[2].frame.x,0.8,accuracy:0.0001)
    }
}
