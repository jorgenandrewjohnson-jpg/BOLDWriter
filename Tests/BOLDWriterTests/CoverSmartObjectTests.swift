import XCTest
import AppKit
@testable import BOLDWriter

final class CoverSmartObjectTests:
    XCTestCase
{
    private func png(
        width: Int = 20,
        height: Int = 10,
        color: NSColor = .systemBlue
    ) throws -> Data {
        let image =
            NSImage(
                size:
                    NSSize(
                        width:
                            width,
                        height:
                            height
                    )
            )

        image.lockFocus()

        color.setFill()

        NSBezierPath(
            rect:
                NSRect(
                    x: 0,
                    y: 0,
                    width:
                        width,
                    height:
                        height
                )
        )
        .fill()

        image.unlockFocus()

        guard let tiff =
                image.tiffRepresentation,
              let bitmap =
                NSBitmapImageRep(
                    data:
                        tiff
                ),
              let data =
                bitmap.representation(
                    using:
                        .png,
                    properties:
                        [:]
                )
        else {
            throw XCTSkip(
                "Unable to create PNG fixture."
            )
        }

        return data
    }

    private func project() -> CoverProject {
        var value =
            CoverProject(
                width:
                    6,
                height:
                    9
            )

        value.dpi =
            300

        return value
    }

    private func smartLayer(
        sourceData: Data? = nil,
        filename: String = "Embedded.png"
    ) throws -> CoverLayer {
        try CoverEditorEngine
            .smartObjectLayerFromEmbeddedSource(
                data:
                    sourceData
                    ?? png(),
                filename:
                    filename,
                project:
                    project()
            )
    }

    func testSourceKindCodableRoundTrip() throws {
        let values:
            [CoverSmartObjectSourceKind] = [
                .rasterImage,
                .pdf,
                .svg,
                .psd
            ]

        for kind in values {
            let encoded =
                try JSONEncoder()
                    .encode(
                        kind
                    )

            XCTAssertEqual(
                try JSONDecoder()
                    .decode(
                        CoverSmartObjectSourceKind.self,
                        from:
                            encoded
                    ),
                kind
            )
        }
    }

    func testPayloadCodableRoundTrip() throws {
        let source =
            try png()

        let value =
            CoverSmartObject(
                sourceKind:
                    .rasterImage,
                sourceData:
                    source,
                sourceFilename:
                    "Original.png",
                intrinsicWidth:
                    20,
                intrinsicHeight:
                    10
            )

        let encoded =
            try JSONEncoder()
                .encode(
                    value
                )

        XCTAssertEqual(
            try JSONDecoder()
                .decode(
                    CoverSmartObject.self,
                    from:
                        encoded
                ),
            value
        )
    }

    func testLegacyImageLayerHasNoSmartObject() throws {
        var layer =
            CoverLayer(
                kind:
                    .image,
                name:
                    "Legacy"
            )

        layer.imageData =
            try png()

        let encoded =
            try JSONEncoder()
                .encode(
                    layer
                )

        let decoded =
            try JSONDecoder()
                .decode(
                    CoverLayer.self,
                    from:
                        encoded
                )

        XCTAssertEqual(
            decoded.kind,
            .image
        )

        XCTAssertNil(
            decoded.smartObject
        )
    }

    func testPlaceEmbeddedCreatesSmartObject() throws {
        let source =
            try png(
                width:
                    40,
                height:
                    20
            )

        let layer =
            try smartLayer(
                sourceData:
                    source,
                filename:
                    "Photo.png"
            )

        XCTAssertEqual(
            layer.kind,
            .smartObject
        )

        XCTAssertEqual(
            layer.smartObject?
                .sourceData,
            source
        )

        XCTAssertEqual(
            layer.smartObject?
                .sourceFilename,
            "Photo.png"
        )

        XCTAssertEqual(
            layer.smartObject?
                .sourceKind,
            .rasterImage
        )

        let cache =
            try XCTUnwrap(
                layer.imageData
            )

        XCTAssertNotNil(
            NSImage(
                data:
                    cache
            )
        )

        XCTAssertEqual(
            layer.cropMode,
            .fit
        )
    }

    func testPlaceEmbeddedFitsCanvasWithoutChangingSource() throws {
        let source =
            try png(
                width:
                    600,
                height:
                    300
            )

        let layer =
            try smartLayer(
                sourceData:
                    source
            )

        XCTAssertGreaterThan(
            layer.frame.width,
            0
        )

        XCTAssertGreaterThan(
            layer.frame.height,
            0
        )

        XCTAssertLessThanOrEqual(
            layer.frame.width,
            1
        )

        XCTAssertLessThanOrEqual(
            layer.frame.height,
            1
        )

        XCTAssertEqual(
            layer.smartObject?
                .sourceData,
            source
        )
    }

    func testSourceSurvivesProjectRoundTrip() throws {
        let source =
            try png(
                color:
                    .systemRed
            )

        let layer =
            try smartLayer(
                sourceData:
                    source
            )

        var value =
            project()

        value.layers = [
            layer
        ]

        let encoded =
            try JSONEncoder()
                .encode(
                    value
                )

        let decoded =
            try JSONDecoder()
                .decode(
                    CoverProject.self,
                    from:
                        encoded
                )

        XCTAssertEqual(
            decoded.layers
                .first?
                .smartObject?
                .sourceData,
            source
        )
    }

    func testValidationAcceptsValidSmartObject() throws {
        var value =
            project()

        value.layers = [
            try smartLayer()
        ]

        XCTAssertNoThrow(
            try CoverProject
                .validate(
                    [
                        value
                    ]
                )
        )
    }

    func testValidationRejectsEmptySource() throws {
        var layer =
            try smartLayer()

        layer.smartObject?
            .sourceData =
            Data()

        var value =
            project()

        value.layers = [
            layer
        ]

        XCTAssertThrowsError(
            try CoverProject
                .validate(
                    [
                        value
                    ]
                )
        )
    }

    func testValidationRejectsInvalidIntrinsicDimensions() throws {
        var layer =
            try smartLayer()

        layer.smartObject?
            .intrinsicWidth =
            0

        var value =
            project()

        value.layers = [
            layer
        ]

        XCTAssertThrowsError(
            try CoverProject
                .validate(
                    [
                        value
                    ]
                )
        )
    }

    func testValidationRejectsSmartKindWithoutPayload() throws {
        var layer =
            CoverLayer(
                kind:
                    .smartObject,
                name:
                    "Invalid"
            )

        layer.imageData =
            try png()

        var value =
            project()

        value.layers = [
            layer
        ]

        XCTAssertThrowsError(
            try CoverProject
                .validate(
                    [
                        value
                    ]
                )
        )
    }

    func testValidationRejectsPayloadOnImageLayer() throws {
        var layer =
            try smartLayer()

        layer.kind =
            .image

        var value =
            project()

        value.layers = [
            layer
        ]

        XCTAssertThrowsError(
            try CoverProject
                .validate(
                    [
                        value
                    ]
                )
        )
    }

    func testReplaceContentsPreservesOuterLayerState() throws {
        var source =
            try smartLayer(
                filename:
                    "First.png"
            )

        source.frame =
            CoverRect(
                x:
                    0.17,
                y:
                    0.23,
                width:
                    0.41,
                height:
                    0.37
            )

        source.rotation =
            31

        source.flipHorizontal =
            true

        source.flipVertical =
            true

        source.skewX =
            0.12

        source.skewY =
            -0.07

        source.opacity =
            0.67

        source.blendMode =
            .multiply

        source.maskData =
            Data(
                [
                    0,
                    255,
                    255,
                    0
                ]
            )

        source.maskEnabled =
            true

        source.clippedToLayerID =
            UUID()

        source.dropShadow =
            CoverDropShadow()

        source.innerShadow =
            CoverInnerShadow()

        source.strokeEffect =
            CoverStrokeEffect()

        source.colorOverlay =
            CoverColorOverlay()

        source.gradientOverlay =
            CoverGradientOverlay()

        source.outerGlow =
            CoverOuterGlow()

        source.filters = [
            CoverFilter(
                kind:
                    .sepia
            )
        ]

        source.warpPreset =
            .arch

        source.warpAmount =
            0.3

        let replacementBytes =
            try png(
                width:
                    30,
                height:
                    45,
                color:
                    .systemGreen
            )

        let replacement =
            try XCTUnwrap(
                CoverEditorEngine
                    .replacingSmartObjectContents(
                        in:
                            source,
                        data:
                            replacementBytes,
                        filename:
                            "Second.png"
                    )
            )

        XCTAssertEqual(
            replacement.id,
            source.id
        )

        XCTAssertEqual(
            replacement.frame,
            source.frame
        )

        XCTAssertEqual(
            replacement.rotation,
            source.rotation
        )

        XCTAssertEqual(
            replacement.flipHorizontal,
            source.flipHorizontal
        )

        XCTAssertEqual(
            replacement.flipVertical,
            source.flipVertical
        )

        XCTAssertEqual(
            replacement.skewX,
            source.skewX
        )

        XCTAssertEqual(
            replacement.skewY,
            source.skewY
        )

        XCTAssertEqual(
            replacement.opacity,
            source.opacity
        )

        XCTAssertEqual(
            replacement.blendMode,
            source.blendMode
        )

        XCTAssertEqual(
            replacement.maskData,
            source.maskData
        )

        XCTAssertEqual(
            replacement.maskEnabled,
            source.maskEnabled
        )

        XCTAssertEqual(
            replacement.clippedToLayerID,
            source.clippedToLayerID
        )

        XCTAssertEqual(
            replacement.dropShadow,
            source.dropShadow
        )

        XCTAssertEqual(
            replacement.innerShadow,
            source.innerShadow
        )

        XCTAssertEqual(
            replacement.strokeEffect,
            source.strokeEffect
        )

        XCTAssertEqual(
            replacement.colorOverlay,
            source.colorOverlay
        )

        XCTAssertEqual(
            replacement.gradientOverlay,
            source.gradientOverlay
        )

        XCTAssertEqual(
            replacement.outerGlow,
            source.outerGlow
        )

        XCTAssertEqual(
            replacement.filters,
            source.filters
        )

        XCTAssertEqual(
            replacement.warpPreset,
            source.warpPreset
        )

        XCTAssertEqual(
            replacement.warpAmount,
            source.warpAmount
        )

        XCTAssertEqual(
            replacement.smartObject?
                .sourceData,
            replacementBytes
        )

        XCTAssertEqual(
            replacement.smartObject?
                .sourceFilename,
            "Second.png"
        )

        XCTAssertNotNil(
            replacement.imageData
        )
    }

    func testRegenerateCacheUsesAuthoritativeSource() throws {
        let source =
            try png(
                width:
                    24,
                height:
                    17
            )

        var layer =
            try smartLayer(
                sourceData:
                    source
            )

        layer.imageData =
            nil

        let regenerated =
            try XCTUnwrap(
                CoverEditorEngine
                    .regeneratingSmartObjectRenderCache(
                        in:
                            layer
                    )
            )

        XCTAssertEqual(
            regenerated.smartObject?
                .sourceData,
            source
        )

        let cache =
            try XCTUnwrap(
                regenerated.imageData
            )

        XCTAssertNotNil(
            NSImage(
                data:
                    cache
            )
        )
    }

    func testRasterizeRemovesSmartPayload() throws {
        let source =
            try smartLayer()

        let raster =
            try XCTUnwrap(
                CoverEditorEngine
                    .rasterizingSmartObject(
                        source
                    )
            )

        XCTAssertEqual(
            raster.id,
            source.id
        )

        XCTAssertEqual(
            raster.kind,
            .image
        )

        XCTAssertNil(
            raster.smartObject
        )

        XCTAssertEqual(
            raster.imageData,
            source.imageData
        )

        XCTAssertEqual(
            raster.frame,
            source.frame
        )

        XCTAssertEqual(
            raster.rotation,
            source.rotation
        )
    }

    func testTransformsNeverRewriteEmbeddedSource() throws {
        let bytes =
            try png(
                width:
                    31,
                height:
                    23
            )

        var layer =
            try smartLayer(
                sourceData:
                    bytes
            )

        CoverEditorEngine.move(
            &layer,
            dx:
                0.1,
            dy:
                -0.05
        )

        CoverEditorEngine.resize(
            &layer,
            width:
                max(
                    0.1,
                    layer.frame.width
                    * 0.8
                ),
            height:
                max(
                    0.1,
                    layer.frame.height
                    * 0.7
                )
        )

        CoverEditorEngine.rotate(
            &layer,
            degrees:
                37
        )

        CoverEditorEngine.flip(
            &layer,
            horizontal:
                true
        )

        layer.skewX =
            0.15

        layer.skewY =
            -0.11

        XCTAssertEqual(
            layer.smartObject?
                .sourceData,
            bytes
        )
    }

    func testDuplicateCreatesNewUUIDAndPreservesSource() throws {
        let bytes =
            try png()

        let layer =
            try smartLayer(
                sourceData:
                    bytes
            )

        var value =
            project()

        value.layers = [
            layer
        ]

        let duplicateID =
            try XCTUnwrap(
                value.duplicateLayer(
                    layer.id
                )
            )

        XCTAssertNotEqual(
            duplicateID,
            layer.id
        )

        let duplicate =
            try XCTUnwrap(
                value.layers.first(
                    where: {
                        $0.id == duplicateID
                    }
                )
            )

        XCTAssertEqual(
            duplicate.kind,
            .smartObject
        )

        XCTAssertEqual(
            duplicate.smartObject?
                .sourceData,
            bytes
        )
    }

    func testSignatureDetectionUsesContent() {
        XCTAssertEqual(
            CoverArtwork
                .smartObjectSourceKind(
                    data:
                        Data(
                            "%PDF-1.7".utf8
                        ),
                    filename:
                        "wrong.png"
                ),
            .pdf
        )

        XCTAssertEqual(
            CoverArtwork
                .smartObjectSourceKind(
                    data:
                        Data(
                            "8BPSfake".utf8
                        ),
                    filename:
                        "wrong.jpg"
                ),
            .psd
        )

        XCTAssertEqual(
            CoverArtwork
                .smartObjectSourceKind(
                    data:
                        Data(
                            "<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>".utf8
                        ),
                    filename:
                        "vector.dat"
                ),
            .svg
        )
    }

    func testOrdinaryRasterImportRemainsImageLayer() throws {
        let layer =
            try CoverArtwork
                .imageLayer(
                    data:
                        png(),
                    filename:
                        "Normal.png"
                )

        XCTAssertEqual(
            layer.kind,
            .image
        )

        XCTAssertNil(
            layer.smartObject
        )
    }
}
