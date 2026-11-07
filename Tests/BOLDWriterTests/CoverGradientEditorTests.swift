import AppKit
import XCTest
@testable import BOLDWriter

final class CoverGradientEditorTests: XCTestCase {
    private func project(_ layer:CoverLayer)->CoverProject {
        var project=CoverProject(width:1,height:1)
        project.dpi=96
        project.backgroundHex="#000000"
        project.layers=[layer]
        return project
    }

    private func rendered(_ layer:CoverLayer) throws -> Data {
        try XCTUnwrap(
            CoverArtwork
                .render(project(layer),scale:96)
                .tiffRepresentation
        )
    }

    private func sampled(
        _ data:Data,
        x:Double,
        y:Double
    ) throws -> NSColor {
        try XCTUnwrap(
            CoverEditorEngine
                .sampledColor(
                    imageData:data,
                    at:CGPoint(x:x,y:y)
                )
                .usingColorSpace(.deviceRGB)
        )
    }

    func testLegacyGradientUsesTwoColorFallback() {
        var layer=CoverLayer(
            kind:.gradient,
            name:"Legacy",
            frame:CoverRect(x:0,y:0,width:1,height:1)
        )
        layer.fillHex="#112233"
        layer.gradientEndHex="#DDEEFF"

        let stops=CoverArtwork.baseGradientStops(layer)

        XCTAssertEqual(stops.count,2)
        XCTAssertEqual(stops[0].colorHex,"#112233")
        XCTAssertEqual(stops[1].colorHex,"#DDEEFF")
    }

    func testThreeStopGradientRendersGreenCenter() throws {
        var layer=CoverLayer(
            kind:.gradient,
            name:"Three Stop",
            frame:CoverRect(x:0,y:0,width:1,height:1)
        )

        layer.gradientStops=[
            CoverGradientStop(
                colorHex:"#FF0000",
                location:0,
                opacity:1,
                midpoint:0.5
            ),
            CoverGradientStop(
                colorHex:"#00FF00",
                location:0.5,
                opacity:1,
                midpoint:0.5
            ),
            CoverGradientStop(
                colorHex:"#0000FF",
                location:1,
                opacity:1,
                midpoint:0.5
            )
        ]
        layer.gradientAngle=0

        let center=try sampled(
            rendered(layer),
            x:48,
            y:48
        )

        XCTAssertGreaterThan(
            center.greenComponent,
            center.redComponent+0.20
        )
        XCTAssertGreaterThan(
            center.greenComponent,
            center.blueComponent+0.20
        )
    }

    func testMidpointPlacesFiftyPercentColorAtRequestedLocation() {
        var layer=CoverLayer(
            kind:.gradient,
            name:"Midpoint"
        )

        layer.gradientStops=[
            CoverGradientStop(
                colorHex:"#000000",
                location:0,
                opacity:1,
                midpoint:0.25
            ),
            CoverGradientStop(
                colorHex:"#FFFFFF",
                location:1,
                opacity:1,
                midpoint:0.5
            )
        ]

        let stops=CoverArtwork.renderedGradientStops(layer)

        XCTAssertEqual(stops.count,3)
        XCTAssertEqual(
            stops[1].location,
            0.25,
            accuracy:0.000001
        )
        XCTAssertEqual(stops[1].colorHex,"#808080")
    }

    func testMidpointMovesPositionWithoutChangingHalfColor() {
        var early=CoverLayer(
            kind:.gradient,
            name:"Early"
        )

        early.gradientStops=[
            CoverGradientStop(
                colorHex:"#000000",
                location:0,
                opacity:1,
                midpoint:0.20
            ),
            CoverGradientStop(
                colorHex:"#FFFFFF",
                location:1,
                opacity:1,
                midpoint:0.5
            )
        ]

        var late=early
        late.gradientStops?[0].midpoint=0.80

        let earlyStops=CoverArtwork.renderedGradientStops(early)
        let lateStops=CoverArtwork.renderedGradientStops(late)

        XCTAssertEqual(earlyStops[1].colorHex,"#808080")
        XCTAssertEqual(lateStops[1].colorHex,"#808080")
        XCTAssertEqual(
            earlyStops[1].location,
            0.20,
            accuracy:0.000001
        )
        XCTAssertEqual(
            lateStops[1].location,
            0.80,
            accuracy:0.000001
        )
    }

    func testReverseSwapsRenderedEndpoints() {
        var layer=CoverLayer(
            kind:.gradient,
            name:"Reverse"
        )

        layer.gradientStops=[
            CoverGradientStop(
                colorHex:"#FF0000",
                location:0,
                opacity:1,
                midpoint:0.5
            ),
            CoverGradientStop(
                colorHex:"#0000FF",
                location:1,
                opacity:1,
                midpoint:0.5
            )
        ]
        layer.gradientReversed=true

        let stops=CoverArtwork.renderedGradientStops(layer)

        XCTAssertEqual(stops.first?.colorHex,"#0000FF")
        XCTAssertEqual(stops.last?.colorHex,"#FF0000")
    }

    func testGradientLineHonorsAngle() {
        let rect=CGRect(x:0,y:0,width:200,height:100)

        let horizontal=CoverArtwork.gradientLine(
            in:rect,
            angle:0
        )

        XCTAssertEqual(
            horizontal.start.y,
            50,
            accuracy:0.0001
        )
        XCTAssertEqual(
            horizontal.end.y,
            50,
            accuracy:0.0001
        )

        let vertical=CoverArtwork.gradientLine(
            in:rect,
            angle:90
        )

        XCTAssertEqual(
            vertical.start.x,
            100,
            accuracy:0.0001
        )
        XCTAssertEqual(
            vertical.end.x,
            100,
            accuracy:0.0001
        )
    }

    func testAngleChangesProductionRendering() throws {
        var horizontal=CoverLayer(
            kind:.gradient,
            name:"Angle",
            frame:CoverRect(x:0,y:0,width:1,height:1)
        )

        horizontal.gradientStops=[
            CoverGradientStop(
                colorHex:"#FF0000",
                location:0,
                opacity:1,
                midpoint:0.5
            ),
            CoverGradientStop(
                colorHex:"#0000FF",
                location:1,
                opacity:1,
                midpoint:0.5
            )
        ]
        horizontal.gradientAngle=0

        var vertical=horizontal
        vertical.gradientAngle=90

        XCTAssertNotEqual(
            try rendered(horizontal),
            try rendered(vertical)
        )
    }

    func testRadialGeometryChangesProductionRendering() throws {
        var centered=CoverLayer(
            kind:.gradient,
            name:"Radial",
            frame:CoverRect(x:0,y:0,width:1,height:1)
        )

        centered.gradientStops=[
            CoverGradientStop(
                colorHex:"#FFFFFF",
                location:0,
                opacity:1,
                midpoint:0.5
            ),
            CoverGradientStop(
                colorHex:"#000000",
                location:1,
                opacity:1,
                midpoint:0.5
            )
        ]
        centered.gradientRadial=true
        centered.gradientCenterX=0.5
        centered.gradientCenterY=0.5
        centered.gradientRadius=0.75

        var shifted=centered
        shifted.gradientCenterX=0.2
        shifted.gradientCenterY=0.25
        shifted.gradientRadius=0.35

        XCTAssertNotEqual(
            try rendered(centered),
            try rendered(shifted)
        )
    }

    func testOpacityChangesProductionRendering() throws {
        var opaque=CoverLayer(
            kind:.gradient,
            name:"Opacity",
            frame:CoverRect(x:0,y:0,width:1,height:1)
        )

        opaque.gradientStops=[
            CoverGradientStop(
                colorHex:"#FFFFFF",
                location:0,
                opacity:1,
                midpoint:0.5
            ),
            CoverGradientStop(
                colorHex:"#FFFFFF",
                location:1,
                opacity:1,
                midpoint:0.5
            )
        ]
        opaque.gradientAngle=0

        var transparent=opaque
        transparent.gradientStops?[0].opacity=0
        transparent.gradientStops?[1].opacity=0

        XCTAssertNotEqual(
            try rendered(opaque),
            try rendered(transparent)
        )
    }

    func testGradientMetadataPersists() throws {
        var layer=CoverLayer(
            kind:.gradient,
            name:"Persisted",
            frame:CoverRect(x:0,y:0,width:1,height:1)
        )

        layer.gradientStops=[
            CoverGradientStop(
                colorHex:"#102030",
                location:0,
                opacity:0.8,
                midpoint:0.30
            ),
            CoverGradientStop(
                colorHex:"#4080C0",
                location:0.45,
                opacity:0.6,
                midpoint:0.70
            ),
            CoverGradientStop(
                colorHex:"#F0E0D0",
                location:1,
                opacity:1,
                midpoint:0.5
            )
        ]
        layer.gradientRadial=true
        layer.gradientAngle=37
        layer.gradientCenterX=0.33
        layer.gradientCenterY=0.61
        layer.gradientRadius=1.25
        layer.gradientReversed=true

        let data=try JSONEncoder().encode(project(layer))
        let decoded=try JSONDecoder().decode(
            CoverProject.self,
            from:data
        )
        let reopened=try XCTUnwrap(decoded.layers.first)

        XCTAssertEqual(reopened.gradientStops,layer.gradientStops)
        XCTAssertEqual(reopened.gradientRadial,true)
        XCTAssertEqual(reopened.gradientAngle,37)
        XCTAssertEqual(reopened.gradientCenterX,0.33)
        XCTAssertEqual(reopened.gradientCenterY,0.61)
        XCTAssertEqual(reopened.gradientRadius,1.25)
        XCTAssertEqual(reopened.gradientReversed,true)
    }
}
