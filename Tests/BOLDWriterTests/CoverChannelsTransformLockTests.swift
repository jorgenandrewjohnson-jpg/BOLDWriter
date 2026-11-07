import AppKit
import XCTest
@testable import BOLDWriter

final class CoverChannelsTransformLockTests: XCTestCase {
    private func sampled(
        _ data:Data
    ) throws -> NSColor {
        try XCTUnwrap(
            CoverEditorEngine
                .sampledColor(
                    imageData:data,
                    at:
                        CGPoint(
                            x:1,
                            y:1
                        )
                )
                .usingColorSpace(
                    .deviceRGB
                )
        )
    }

    func testChannelsExposeCompositeRGBAndAlpha() {
        XCTAssertEqual(
            CoverChannelPreviewKind
                .allCases
                .map(\.rawValue),
            [
                "Composite",
                "Red",
                "Green",
                "Blue",
                "Alpha"
            ]
        )
    }

    func testRGBChannelPreviewsAreOpaqueGrayscaleIntensity() throws {
        let source =
            try CoverEditorEngine
                .filledImage(
                    width:4,
                    height:4,
                    color:
                        NSColor(
                            srgbRed:1,
                            green:0.25,
                            blue:0,
                            alpha:1
                        )
                )

        let red =
            try sampled(
                CoverEditorEngine
                    .channelPreview(
                        imageData:source,
                        channel:.red
                    )
            )

        let green =
            try sampled(
                CoverEditorEngine
                    .channelPreview(
                        imageData:source,
                        channel:.green
                    )
            )

        let blue =
            try sampled(
                CoverEditorEngine
                    .channelPreview(
                        imageData:source,
                        channel:.blue
                    )
            )

        XCTAssertEqual(
            red.redComponent,
            red.greenComponent,
            accuracy:0.02
        )

        XCTAssertEqual(
            red.greenComponent,
            red.blueComponent,
            accuracy:0.02
        )

        XCTAssertGreaterThan(
            red.redComponent,
            green.redComponent + 0.5
        )

        XCTAssertGreaterThan(
            green.redComponent,
            blue.redComponent + 0.1
        )

        XCTAssertEqual(
            red.alphaComponent,
            1,
            accuracy:0.001
        )
    }

    func testAlphaChannelShowsTransparencyAsGrayscale() throws {
        let transparent =
            try CoverEditorEngine
                .transparentImage(
                    width:4,
                    height:4
                )

        let opaque =
            try CoverEditorEngine
                .filledImage(
                    width:4,
                    height:4,
                    color:.white
                )

        let transparentAlpha =
            try sampled(
                CoverEditorEngine
                    .channelPreview(
                        imageData:transparent,
                        channel:.alpha
                    )
            )

        let opaqueAlpha =
            try sampled(
                CoverEditorEngine
                    .channelPreview(
                        imageData:opaque,
                        channel:.alpha
                    )
            )

        XCTAssertLessThan(
            transparentAlpha.redComponent,
            0.05
        )

        XCTAssertGreaterThan(
            opaqueAlpha.redComponent,
            0.95
        )

        XCTAssertEqual(
            transparentAlpha.alphaComponent,
            1,
            accuracy:0.001
        )
    }

    func testCompositePreviewPreservesCompositeColor() throws {
        let source =
            try CoverEditorEngine
                .filledImage(
                    width:4,
                    height:4,
                    color:
                        NSColor(
                            srgbRed:0.15,
                            green:0.45,
                            blue:0.80,
                            alpha:1
                        )
                )

        let original =
            try sampled(
                source
            )

        let composite =
            try sampled(
                CoverEditorEngine
                    .channelPreview(
                        imageData:source,
                        channel:.composite
                    )
            )

        XCTAssertEqual(
            original.redComponent,
            composite.redComponent,
            accuracy:0.02
        )

        XCTAssertEqual(
            original.greenComponent,
            composite.greenComponent,
            accuracy:0.02
        )

        XCTAssertEqual(
            original.blueComponent,
            composite.blueComponent,
            accuracy:0.02
        )
    }

    func testChannelsVisibilityIsSessionOnlyWorkspaceState() {
        var state =
            CoverWorkspaceState()

        state.layers = false
        state.paths = false
        state.properties = false
        state.character = false
        state.paragraph = false
        state.adjustments = false
        state.historyAndSwatches = false
        state.channels = false

        XCTAssertFalse(
            state.hasPanels
        )

        state.channels = true

        XCTAssertTrue(
            state.hasPanels
        )
    }

    func testTransformBoundsExcludeLockedAndPositionLockedLayers() throws {
        let movable =
            CoverLayer(
                kind:.shape,
                name:"Movable",
                frame:
                    CoverRect(
                        x:0.20,
                        y:0.25,
                        width:0.30,
                        height:0.20
                    )
            )

        var locked =
            CoverLayer(
                kind:.shape,
                name:"Locked",
                frame:
                    CoverRect(
                        x:0,
                        y:0,
                        width:1,
                        height:1
                    )
            )

        locked.locked = true

        var positionLocked =
            CoverLayer(
                kind:.shape,
                name:"Position Locked",
                frame:
                    CoverRect(
                        x:0.70,
                        y:0.70,
                        width:0.20,
                        height:0.20
                    )
            )

        positionLocked.positionLocked = true

        let layers = [
            movable,
            locked,
            positionLocked
        ]

        let ids =
            Set(
                layers.map(\.id)
            )

        XCTAssertEqual(
            CoverEditorEngine
                .transformableLayerIDs(
                    layers,
                    ids:ids
                ),
            Set([movable.id])
        )

        let bounds =
            try XCTUnwrap(
                CoverEditorEngine
                    .transformBounds(
                        layers,
                        ids:ids
                    )
            )

        XCTAssertEqual(
            bounds.minX,
            0.20,
            accuracy:0.0001
        )

        XCTAssertEqual(
            bounds.minY,
            0.25,
            accuracy:0.0001
        )

        XCTAssertEqual(
            bounds.width,
            0.30,
            accuracy:0.0001
        )

        XCTAssertEqual(
            bounds.height,
            0.20,
            accuracy:0.0001
        )
    }

    func testAlignHonorsBothLayerAndPositionLocks() {
        var movableA =
            CoverLayer(
                kind:.shape,
                name:"A",
                frame:
                    CoverRect(
                        x:0.20,
                        y:0.20,
                        width:0.10,
                        height:0.10
                    )
            )

        let movableB =
            CoverLayer(
                kind:.shape,
                name:"B",
                frame:
                    CoverRect(
                        x:0.60,
                        y:0.40,
                        width:0.10,
                        height:0.10
                    )
            )

        var positionLocked =
            CoverLayer(
                kind:.shape,
                name:"Position Locked",
                frame:
                    CoverRect(
                        x:0.85,
                        y:0.70,
                        width:0.10,
                        height:0.10
                    )
            )

        positionLocked.positionLocked = true

        var hardLocked =
            CoverLayer(
                kind:.shape,
                name:"Locked",
                frame:
                    CoverRect(
                        x:0.95,
                        y:0.80,
                        width:0.05,
                        height:0.05
                    )
            )

        hardLocked.locked = true

        let positionBefore =
            positionLocked.frame

        let lockedBefore =
            hardLocked.frame

        let ids:Set<UUID> = [
            movableA.id,
            movableB.id,
            positionLocked.id,
            hardLocked.id
        ]

        var layers = [
            movableA,
            movableB,
            positionLocked,
            hardLocked
        ]

        CoverEditorEngine.align(
            &layers,
            ids:ids,
            edge:.left,
            reference:
                CGRect(
                    x:0.10,
                    y:0,
                    width:0.80,
                    height:1
                )
        )

        XCTAssertEqual(
            layers[0].frame.x,
            0.10,
            accuracy:0.0001
        )

        XCTAssertEqual(
            layers[1].frame.x,
            0.10,
            accuracy:0.0001
        )

        XCTAssertEqual(
            layers[2].frame,
            positionBefore
        )

        XCTAssertEqual(
            layers[3].frame,
            lockedBefore
        )

        movableA = layers[0]
        XCTAssertEqual(
            movableA.id,
            layers[0].id
        )
    }

    func testDistributionIgnoresPositionLockedLayer() {
        let a =
            CoverLayer(
                kind:.shape,
                name:"A",
                frame:
                    CoverRect(
                        x:0,
                        y:0,
                        width:0.10,
                        height:0.10
                    )
            )

        var lockedMiddle =
            CoverLayer(
                kind:.shape,
                name:"Locked Middle",
                frame:
                    CoverRect(
                        x:0.20,
                        y:0,
                        width:0.10,
                        height:0.10
                    )
            )

        lockedMiddle.positionLocked = true

        let b =
            CoverLayer(
                kind:.shape,
                name:"B",
                frame:
                    CoverRect(
                        x:0.50,
                        y:0,
                        width:0.10,
                        height:0.10
                    )
            )

        let c =
            CoverLayer(
                kind:.shape,
                name:"C",
                frame:
                    CoverRect(
                        x:0.90,
                        y:0,
                        width:0.10,
                        height:0.10
                    )
            )

        let lockedBefore =
            lockedMiddle.frame

        var layers = [
            a,
            lockedMiddle,
            b,
            c
        ]

        CoverEditorEngine.distribute(
            &layers,
            ids:
                Set(
                    layers.map(\.id)
                ),
            axis:.horizontal
        )

        XCTAssertEqual(
            layers[0].frame.x,
            0,
            accuracy:0.0001
        )

        XCTAssertEqual(
            layers[1].frame,
            lockedBefore
        )

        XCTAssertEqual(
            layers[2].frame.x,
            0.45,
            accuracy:0.0001
        )

        XCTAssertEqual(
            layers[3].frame.x,
            0.90,
            accuracy:0.0001
        )
    }
}
