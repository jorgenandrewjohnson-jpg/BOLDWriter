import AppKit
import CoreGraphics
import XCTest
@testable import BOLDWriter

final class CoverLinkedSmartObjectTests:
    XCTestCase
{
    private func project()
        -> CoverProject
    {
        var project =
            CoverProject(
                type:
                    .ebookFront,
                width:
                    1,
                height:
                    1
            )

        project.dpi =
            72

        return project
    }

    private func png(
        width: Int = 2,
        height: Int = 2
    ) throws -> Data {
        let bitmap =
            try XCTUnwrap(
                NSBitmapImageRep(
                    bitmapDataPlanes:
                        nil,
                    pixelsWide:
                        width,
                    pixelsHigh:
                        height,
                    bitsPerSample:
                        8,
                    samplesPerPixel:
                        4,
                    hasAlpha:
                        true,
                    isPlanar:
                        false,
                    colorSpaceName:
                        .deviceRGB,
                    bytesPerRow:
                        width * 4,
                    bitsPerPixel:
                        32
                )
            )

        for y
            in 0..<height
        {
            for x
                in 0..<width
            {
                bitmap.setColor(
                    NSColor(
                        calibratedRed:
                            CGFloat(x + 1)
                            / CGFloat(
                                width + 1
                            ),
                        green:
                            CGFloat(y + 1)
                            / CGFloat(
                                height + 1
                            ),
                        blue:
                            0.4,
                        alpha:
                            1
                    ),
                    atX:
                        x,
                    y:
                        y
                )
            }
        }

        return try XCTUnwrap(
            bitmap.representation(
                using:
                    .png,
                properties:
                    [:]
            )
        )
    }

    private func pdf()
        throws -> Data
    {
        let mutable =
            NSMutableData()

        guard let consumer =
                CGDataConsumer(
                    data:
                        mutable
                )
        else {
            throw XCTSkip(
                "Could not create PDF data consumer."
            )
        }

        var mediaBox =
            CGRect(
                x:
                    0,
                y:
                    0,
                width:
                    20,
                height:
                    20
            )

        guard let context =
                CGContext(
                    consumer:
                        consumer,
                    mediaBox:
                        &mediaBox,
                    nil
                )
        else {
            throw XCTSkip(
                "Could not create PDF context."
            )
        }

        context.beginPDFPage(
            nil
        )

        context.setFillColor(
            NSColor.systemBlue
                .cgColor
        )

        context.fill(
            mediaBox
        )

        context.endPDFPage()
        context.closePDF()

        return mutable
            as Data
    }

    private func svg()
        -> Data
    {
        Data(
            """
            <svg xmlns="http://www.w3.org/2000/svg" width="20" height="10" viewBox="0 0 20 10">
              <rect width="20" height="10" fill="#336699"/>
            </svg>
            """
            .utf8
        )
    }

    private func psd()
        throws -> Data
    {
        var project =
            CoverProject(
                type:
                    .ebookFront,
                width:
                    1,
                height:
                    1
            )

        project.dpi =
            10

        var layer =
            CoverLayer(
                kind:
                    .shape,
                name:
                    "PSD Shape",
                frame:
                    CoverRect()
            )

        layer.fillHex =
            "#336699"

        project.layers =
            [
                layer
            ]

        return try PSDExporter
            .export(
                project
            )
    }

    private func temporaryURL(
        data: Data,
        extension ext: String
    ) throws -> URL {
        let url =
            FileManager.default
                .temporaryDirectory
                .appendingPathComponent(
                    "bold-linked-\(UUID().uuidString)"
                )
                .appendingPathExtension(
                    ext
                )

        try data.write(
            to:
                url,
            options:
                .atomic
        )

        return url
    }

    private func remove(
        _ url: URL
    ) {
        try? FileManager.default
            .removeItem(
                at:
                    url
            )
    }

    func testLegacyEmbeddedSmartObjectDefaultsToEmbedded() throws {
        let object =
            CoverSmartObject(
                sourceKind:
                    .rasterImage,
                sourceData:
                    try png(),
                sourceFilename:
                    "legacy.png",
                intrinsicWidth:
                    2,
                intrinsicHeight:
                    2
            )

        let encoded =
            try JSONEncoder()
                .encode(
                    object
                )

        var dictionary =
            try XCTUnwrap(
                JSONSerialization
                    .jsonObject(
                        with:
                            encoded
                    )
                    as?
                    [String: Any]
            )

        dictionary.removeValue(
            forKey:
                "storageMode"
        )

        dictionary.removeValue(
            forKey:
                "linkedBookmarkData"
        )

        dictionary.removeValue(
            forKey:
                "linkedLastKnownModificationDate"
        )

        dictionary.removeValue(
            forKey:
                "linkedLastKnownFileSize"
        )

        let legacy =
            try JSONSerialization
                .data(
                    withJSONObject:
                        dictionary
                )

        let decoded =
            try JSONDecoder()
                .decode(
                    CoverSmartObject.self,
                    from:
                        legacy
                )

        XCTAssertEqual(
            decoded.storageMode,
            .embedded
        )

        XCTAssertNil(
            decoded.linkedBookmarkData
        )

        XCTAssertEqual(
            decoded.sourceData,
            object.sourceData
        )
    }

    func testEmbeddedSmartObjectRemainsEmbedded() throws {
        let source =
            try png()

        let layer =
            try CoverEditorEngine
                .smartObjectLayerFromEmbeddedSource(
                    data:
                        source,
                    filename:
                        "embedded.png",
                    project:
                        project()
                )

        let object =
            try XCTUnwrap(
                layer.smartObject
            )

        XCTAssertEqual(
            object.storageMode,
            .embedded
        )

        XCTAssertNil(
            object.linkedBookmarkData
        )

        XCTAssertEqual(
            object.sourceData,
            source
        )
    }

    func testPlaceLinkedCreatesPersistentLinkedPayload() throws {
        let source =
            try png()

        let url =
            try temporaryURL(
                data:
                    source,
                extension:
                    "png"
            )

        defer {
            remove(
                url
            )
        }

        let layer =
            try CoverEditorEngine
                .smartObjectLayerFromLinkedSource(
                    url:
                        url,
                    project:
                        project()
                )

        let object =
            try XCTUnwrap(
                layer.smartObject
            )

        XCTAssertEqual(
            object.storageMode,
            .linked
        )

        XCTAssertEqual(
            object.sourceData,
            source
        )

        XCTAssertFalse(
            try XCTUnwrap(
                object.linkedBookmarkData
            )
            .isEmpty
        )

        XCTAssertNotNil(
            layer.imageData
        )

        XCTAssertEqual(
            object.sourceFilename,
            url.lastPathComponent
        )
    }

    func testLinkedPayloadRoundTripsThroughCodable() throws {
        let url =
            try temporaryURL(
                data:
                    try png(),
                extension:
                    "png"
            )

        defer {
            remove(
                url
            )
        }

        let layer =
            try CoverEditorEngine
                .smartObjectLayerFromLinkedSource(
                    url:
                        url,
                    project:
                        project()
                )

        let original =
            try XCTUnwrap(
                layer.smartObject
            )

        let encoded =
            try JSONEncoder()
                .encode(
                    original
                )

        let decoded =
            try JSONDecoder()
                .decode(
                    CoverSmartObject.self,
                    from:
                        encoded
                )

        XCTAssertEqual(
            decoded,
            original
        )
    }

    func testCurrentLinkedSourceStatus() throws {
        let url =
            try temporaryURL(
                data:
                    try png(),
                extension:
                    "png"
            )

        defer {
            remove(
                url
            )
        }

        let layer =
            try CoverEditorEngine
                .smartObjectLayerFromLinkedSource(
                    url:
                        url,
                    project:
                        project()
                )

        XCTAssertEqual(
            CoverEditorEngine
                .linkedSmartObjectStatus(
                    in:
                        layer
                ),
            .current
        )
    }

    func testModifiedLinkedSourceIsDetected() throws {
        let url =
            try temporaryURL(
                data:
                    try png(
                        width:
                            2,
                        height:
                            2
                    ),
                extension:
                    "png"
            )

        defer {
            remove(
                url
            )
        }

        let layer =
            try CoverEditorEngine
                .smartObjectLayerFromLinkedSource(
                    url:
                        url,
                    project:
                        project()
                )

        let changed =
            try png(
                width:
                    5,
                height:
                    3
            )

        try changed.write(
            to:
                url,
            options:
                .atomic
        )

        try FileManager.default
            .setAttributes(
                [
                    .modificationDate:
                        Date(
                            timeIntervalSinceNow:
                                30
                        )
                ],
                ofItemAtPath:
                    url.path
            )

        XCTAssertEqual(
            CoverEditorEngine
                .linkedSmartObjectStatus(
                    in:
                        layer
                ),
            .modified
        )
    }

    func testUpdateModifiedContentRefreshesFallbackAndCache() throws {
        let original =
            try png(
                width:
                    2,
                height:
                    2
            )

        let url =
            try temporaryURL(
                data:
                    original,
                extension:
                    "png"
            )

        defer {
            remove(
                url
            )
        }

        let layer =
            try CoverEditorEngine
                .smartObjectLayerFromLinkedSource(
                    url:
                        url,
                    project:
                        project()
                )

        let changed =
            try png(
                width:
                    5,
                height:
                    4
            )

        try changed.write(
            to:
                url,
            options:
                .atomic
        )

        try FileManager.default
            .setAttributes(
                [
                    .modificationDate:
                        Date(
                            timeIntervalSinceNow:
                                30
                        )
                ],
                ofItemAtPath:
                    url.path
            )

        let updated =
            try XCTUnwrap(
                try CoverEditorEngine
                    .updatingLinkedSmartObjectContents(
                        in:
                            layer
                    )
            )

        let object =
            try XCTUnwrap(
                updated.smartObject
            )

        XCTAssertEqual(
            object.sourceData,
            changed
        )

        XCTAssertEqual(
            object.intrinsicWidth,
            5
        )

        XCTAssertEqual(
            object.intrinsicHeight,
            4
        )

        XCTAssertNotNil(
            updated.imageData
        )

        XCTAssertEqual(
            CoverEditorEngine
                .linkedSmartObjectStatus(
                    in:
                        updated
                ),
            .current
        )
    }

    func testMissingLinkedSourceKeepsCachedArtwork() throws {
        let url =
            try temporaryURL(
                data:
                    try png(),
                extension:
                    "png"
            )

        var layer =
            try CoverEditorEngine
                .smartObjectLayerFromLinkedSource(
                    url:
                        url,
                    project:
                        project()
                )

        let sourceBefore =
            layer.smartObject?
                .sourceData

        let cacheBefore =
            layer.imageData

        remove(
            url
        )

        XCTAssertEqual(
            CoverEditorEngine
                .linkedSmartObjectStatus(
                    in:
                        layer
                ),
            .unavailable
        )

        XCTAssertThrowsError(
            try CoverEditorEngine
                .updatingLinkedSmartObjectContents(
                    in:
                        layer
                )
        )

        XCTAssertEqual(
            layer.smartObject?
                .sourceData,
            sourceBefore
        )

        XCTAssertEqual(
            layer.imageData,
            cacheBefore
        )

        XCTAssertNotNil(
            CoverEditorEngine
                .rasterizingSmartObject(
                    layer
                )
        )

        layer.opacity =
            0.5

        XCTAssertEqual(
            layer.smartObject?
                .sourceData,
            sourceBefore
        )
    }

    func testRelinkPreservesLayerStylingAndChangesSource() throws {
        let first =
            try temporaryURL(
                data:
                    try png(
                        width:
                            2,
                        height:
                            2
                    ),
                extension:
                    "png"
            )

        let secondData =
            try png(
                width:
                    6,
                height:
                    3
            )

        let second =
            try temporaryURL(
                data:
                    secondData,
                extension:
                    "png"
            )

        defer {
            remove(
                first
            )

            remove(
                second
            )
        }

        var layer =
            try CoverEditorEngine
                .smartObjectLayerFromLinkedSource(
                    url:
                        first,
                    project:
                        project()
                )

        layer.rotation =
            23

        layer.opacity =
            0.67

        layer.flipHorizontal =
            true

        let originalFrame =
            layer.frame

        let replacement =
            try XCTUnwrap(
                try CoverEditorEngine
                    .relinkingSmartObject(
                        in:
                            layer,
                        to:
                            second
                    )
            )

        XCTAssertEqual(
            replacement.frame,
            originalFrame
        )

        XCTAssertEqual(
            replacement.rotation,
            23
        )

        XCTAssertEqual(
            replacement.opacity,
            0.67,
            accuracy:
                0.000001
        )

        XCTAssertTrue(
            replacement.flipHorizontal
        )

        XCTAssertEqual(
            replacement.smartObject?
                .sourceData,
            secondData
        )

        XCTAssertEqual(
            replacement.smartObject?
                .sourceFilename,
            second.lastPathComponent
        )

        XCTAssertEqual(
            replacement.smartObject?
                .storageMode,
            .linked
        )
    }

    func testFailedRelinkDoesNotMutateOriginal() throws {
        let url =
            try temporaryURL(
                data:
                    try png(),
                extension:
                    "png"
            )

        defer {
            remove(
                url
            )
        }

        let layer =
            try CoverEditorEngine
                .smartObjectLayerFromLinkedSource(
                    url:
                        url,
                    project:
                        project()
                )

        let snapshot =
            layer

        let missing =
            FileManager.default
                .temporaryDirectory
                .appendingPathComponent(
                    "missing-\(UUID().uuidString).png"
                )

        XCTAssertThrowsError(
            try CoverEditorEngine
                .relinkingSmartObject(
                    in:
                        layer,
                    to:
                        missing
                )
        )

        XCTAssertEqual(
            layer,
            snapshot
        )
    }

    func testConvertLinkedToEmbeddedClearsLinkMetadata() throws {
        let url =
            try temporaryURL(
                data:
                    try png(),
                extension:
                    "png"
            )

        defer {
            remove(
                url
            )
        }

        let linked =
            try CoverEditorEngine
                .smartObjectLayerFromLinkedSource(
                    url:
                        url,
                    project:
                        project()
                )

        let source =
            linked.smartObject?
                .sourceData

        let cache =
            linked.imageData

        let embedded =
            try XCTUnwrap(
                CoverEditorEngine
                    .embeddingLinkedSmartObject(
                        in:
                            linked
                    )
            )

        XCTAssertEqual(
            embedded.smartObject?
                .storageMode,
            .embedded
        )

        XCTAssertNil(
            embedded.smartObject?
                .linkedBookmarkData
        )

        XCTAssertNil(
            embedded.smartObject?
                .linkedLastKnownModificationDate
        )

        XCTAssertNil(
            embedded.smartObject?
                .linkedLastKnownFileSize
        )

        XCTAssertEqual(
            embedded.smartObject?
                .sourceData,
            source
        )

        XCTAssertEqual(
            embedded.imageData,
            cache
        )
    }

    func testReplaceContentsRemainsEmbeddedOnly() throws {
        let original =
            try png()

        let replacement =
            try png(
                width:
                    3,
                height:
                    3
            )

        let embedded =
            try CoverEditorEngine
                .smartObjectLayerFromEmbeddedSource(
                    data:
                        original,
                    filename:
                        "embedded.png",
                    project:
                        project()
                )

        let replaced =
            try XCTUnwrap(
                try CoverEditorEngine
                    .replacingSmartObjectContents(
                        in:
                            embedded,
                        data:
                            replacement,
                        filename:
                            "replacement.png"
                    )
            )

        XCTAssertEqual(
            replaced.smartObject?
                .storageMode,
            .embedded
        )

        let url =
            try temporaryURL(
                data:
                    original,
                extension:
                    "png"
            )

        defer {
            remove(
                url
            )
        }

        let linked =
            try CoverEditorEngine
                .smartObjectLayerFromLinkedSource(
                    url:
                        url,
                    project:
                        project()
                )

        XCTAssertNil(
            try CoverEditorEngine
                .replacingSmartObjectContents(
                    in:
                        linked,
                    data:
                        replacement,
                    filename:
                        "replacement.png"
                )
        )
    }

    func testRasterizeLinkedObjectRemovesSmartObjectPayload() throws {
        let url =
            try temporaryURL(
                data:
                    try png(),
                extension:
                    "png"
            )

        let linked =
            try CoverEditorEngine
                .smartObjectLayerFromLinkedSource(
                    url:
                        url,
                    project:
                        project()
                )

        remove(
            url
        )

        let raster =
            try XCTUnwrap(
                CoverEditorEngine
                    .rasterizingSmartObject(
                        linked
                    )
            )

        XCTAssertEqual(
            raster.kind,
            .image
        )

        XCTAssertNil(
            raster.smartObject
        )

        XCTAssertNotNil(
            raster.imageData
        )
    }

    func testLinkedDuplicatePreservesExternalLinkPayload() throws {
        let url =
            try temporaryURL(
                data:
                    try png(),
                extension:
                    "png"
            )

        defer {
            remove(
                url
            )
        }

        let linked =
            try CoverEditorEngine
                .smartObjectLayerFromLinkedSource(
                    url:
                        url,
                    project:
                        project()
                )

        var copy =
            linked

        copy.id =
            UUID()

        XCTAssertNotEqual(
            copy.id,
            linked.id
        )

        XCTAssertEqual(
            copy.smartObject,
            linked.smartObject
        )
    }

    func testProjectPersistencePreservesLinkedPayload() throws {
        let url =
            try temporaryURL(
                data:
                    try png(),
                extension:
                    "png"
            )

        defer {
            remove(
                url
            )
        }

        var project =
            project()

        project.layers =
            [
                try CoverEditorEngine
                    .smartObjectLayerFromLinkedSource(
                        url:
                            url,
                        project:
                            project
                    )
            ]

        let encoded =
            try JSONEncoder()
                .encode(
                    project
                )

        let decoded =
            try JSONDecoder()
                .decode(
                    CoverProject.self,
                    from:
                        encoded
                )

        XCTAssertEqual(
            decoded.layers.first?
                .smartObject?
                .storageMode,
            .linked
        )

        XCTAssertEqual(
            decoded.layers.first?
                .smartObject?
                .sourceData,
            project.layers.first?
                .smartObject?
                .sourceData
        )
    }

    func testValidationAcceptsValidLinkedPayload() throws {
        let url =
            try temporaryURL(
                data:
                    try png(),
                extension:
                    "png"
            )

        defer {
            remove(
                url
            )
        }

        let layer =
            try CoverEditorEngine
                .smartObjectLayerFromLinkedSource(
                    url:
                        url,
                    project:
                        project()
                )

        let object =
            try XCTUnwrap(
                layer.smartObject
            )

        XCTAssertTrue(
            CoverSmartObjectValidation
                .isValid(
                    object
                )
        )
    }

    func testValidationRejectsLinkedPayloadWithoutBookmark() throws {
        var object =
            CoverSmartObject(
                sourceKind:
                    .rasterImage,
                sourceData:
                    try png(),
                sourceFilename:
                    "linked.png",
                intrinsicWidth:
                    2,
                intrinsicHeight:
                    2,
                storageMode:
                    .linked
            )

        object.linkedBookmarkData =
            nil

        XCTAssertFalse(
            CoverSmartObjectValidation
                .isValid(
                    object
                )
        )
    }

    func testValidationRejectsEmbeddedPayloadWithLinkMetadata() throws {
        var object =
            CoverSmartObject(
                sourceKind:
                    .rasterImage,
                sourceData:
                    try png(),
                sourceFilename:
                    "embedded.png",
                intrinsicWidth:
                    2,
                intrinsicHeight:
                    2
            )

        object.linkedBookmarkData =
            Data(
                [
                    1,
                    2,
                    3,
                ]
            )

        XCTAssertFalse(
            CoverSmartObjectValidation
                .isValid(
                    object
                )
        )
    }

    func testLinkedPDFSource() throws {
        let url =
            try temporaryURL(
                data:
                    try pdf(),
                extension:
                    "pdf"
            )

        defer {
            remove(
                url
            )
        }

        let layer =
            try CoverEditorEngine
                .smartObjectLayerFromLinkedSource(
                    url:
                        url,
                    project:
                        project()
                )

        XCTAssertEqual(
            layer.smartObject?
                .sourceKind,
            .pdf
        )

        XCTAssertEqual(
            layer.smartObject?
                .storageMode,
            .linked
        )

        XCTAssertNotNil(
            layer.imageData
        )
    }

    func testLinkedSVGSource() throws {
        let url =
            try temporaryURL(
                data:
                    svg(),
                extension:
                    "svg"
            )

        defer {
            remove(
                url
            )
        }

        let layer =
            try CoverEditorEngine
                .smartObjectLayerFromLinkedSource(
                    url:
                        url,
                    project:
                        project()
                )

        XCTAssertEqual(
            layer.smartObject?
                .sourceKind,
            .svg
        )

        XCTAssertEqual(
            layer.smartObject?
                .storageMode,
            .linked
        )

        XCTAssertNotNil(
            layer.imageData
        )
    }

    func testLinkedPSDSource() throws {
        let url =
            try temporaryURL(
                data:
                    try psd(),
                extension:
                    "psd"
            )

        defer {
            remove(
                url
            )
        }

        let layer =
            try CoverEditorEngine
                .smartObjectLayerFromLinkedSource(
                    url:
                        url,
                    project:
                        project()
                )

        XCTAssertEqual(
            layer.smartObject?
                .sourceKind,
            .psd
        )

        XCTAssertEqual(
            layer.smartObject?
                .storageMode,
            .linked
        )

        XCTAssertNotNil(
            layer.imageData
        )
    }

    func testBookmarkCanResolveSelectedFile() throws {
        let url =
            try temporaryURL(
                data:
                    try png(),
                extension:
                    "png"
            )

        defer {
            remove(
                url
            )
        }

        let bookmark =
            try CoverLinkedSmartObjectResource
                .bookmarkData(
                    for:
                        url
                )

        let resolved =
            try CoverLinkedSmartObjectResource
                .resolveBookmark(
                    bookmark
                )

        XCTAssertEqual(
            resolved.url
                .lastPathComponent,
            url.lastPathComponent
        )
    }

    func testRegeneratingCachePreservesLinkedMetadata() throws {
        let url =
            try temporaryURL(
                data:
                    try png(),
                extension:
                    "png"
            )

        defer {
            remove(
                url
            )
        }

        let layer =
            try CoverEditorEngine
                .smartObjectLayerFromLinkedSource(
                    url:
                        url,
                    project:
                        project()
                )

        let original =
            try XCTUnwrap(
                layer.smartObject
            )

        var withoutCache =
            layer

        withoutCache.imageData =
            nil

        let regenerated =
            try XCTUnwrap(
                try CoverEditorEngine
                    .regeneratingSmartObjectRenderCache(
                        in:
                            withoutCache
                    )
            )

        XCTAssertEqual(
            regenerated.smartObject,
            original
        )

        XCTAssertNotNil(
            regenerated.imageData
        )
    }
}
