import AppKit
import Foundation
import XCTest
@testable import BOLDWriter

final class PSDNativeSmartObjectTests:
    XCTestCase
{
    private func pngData() throws -> Data {
        guard let rep =
                NSBitmapImageRep(
                    bitmapDataPlanes:
                        nil,
                    pixelsWide:
                        2,
                    pixelsHigh:
                        2,
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
                        0,
                    bitsPerPixel:
                        0
                ),
              let bitmap =
                rep.bitmapData
        else {
            XCTFail(
                "Could not create test bitmap."
            )

            return Data()
        }

        for index
            in stride(
                from:
                    0,
                to:
                    16,
                by:
                    4
            )
        {
            bitmap[index] =
                40

            bitmap[index + 1] =
                120

            bitmap[index + 2] =
                200

            bitmap[index + 3] =
                255
        }

        guard let png =
                rep.representation(
                    using:
                        .png,
                    properties:
                        [:]
                )
        else {
            XCTFail(
                "Could not encode test PNG."
            )

            return Data()
        }

        return png
    }

    private func smartLayer(
        sourceKind:
            CoverSmartObjectSourceKind = .rasterImage,
        storageMode:
            CoverSmartObjectStorageMode = .embedded,
        sourceFilename:
            String = "source.png",
        sourceData:
            Data,
        bookmark:
            Data? = nil
    )->CoverLayer {
        var layer =
            CoverLayer(
                kind:
                    .smartObject,
                name:
                    "Smart Object",
                frame:
                    CoverRect(
                        x:
                            0.10,
                        y:
                            0.20,
                        width:
                            0.40,
                        height:
                            0.30
                    )
            )

        layer.imageData =
            sourceData

        layer.smartObject =
            CoverSmartObject(
                sourceKind:
                    sourceKind,
                sourceData:
                    sourceData,
                sourceFilename:
                    sourceFilename,
                intrinsicWidth:
                    2,
                intrinsicHeight:
                    2,
                storageMode:
                    storageMode,
                linkedBookmarkData:
                    bookmark,
                linkedLastKnownModificationDate:
                    nil,
                linkedLastKnownFileSize:
                    storageMode == .linked
                    ? Int64(
                        sourceData.count
                      )
                    : nil
            )

        return layer
    }

    private func project(
        layers:[CoverLayer]
    )->CoverProject {
        var project =
            CoverProject()

        project.name =
            "PSD Smart Object Test"

        project.canvasWidth =
            2

        project.canvasHeight =
            2

        project.layers =
            layers

        return project
    }

    private func contains(
        _ data:Data,
        ascii:String
    )->Bool {
        data.range(
            of:
                Data(
                    ascii.utf8
                )
        )
        != nil
    }

    func testEmbeddedSmartObjectExportsPlLdAndLnk2() throws {
        let source =
            try pngData()

        let data =
            try PSDExporter.export(
                project(
                    layers:
                        [
                            smartLayer(
                                sourceData:
                                    source
                            ),
                        ]
                )
            )

        XCTAssertTrue(
            contains(
                data,
                ascii:
                    "8BIMplLd"
            )
        )

        XCTAssertTrue(
            contains(
                data,
                ascii:
                    "plcL"
            )
        )

        XCTAssertTrue(
            contains(
                data,
                ascii:
                    "8BIMlnk2"
            )
        )

        XCTAssertTrue(
            contains(
                data,
                ascii:
                    "liFD"
            )
        )
    }

    func testAuthoritativeSourceDataIsEmbeddedExactly() throws {
        let source =
            try pngData()

        let data =
            try PSDExporter.export(
                project(
                    layers:
                        [
                            smartLayer(
                                sourceData:
                                    source
                            ),
                        ]
                )
            )

        XCTAssertNotNil(
            data.range(
                of:
                    source
            )
        )
    }

    func testLinkedSmartObjectUsesCachedSourceData() throws {
        let source =
            try pngData()

        let data =
            try PSDExporter.export(
                project(
                    layers:
                        [
                            smartLayer(
                                storageMode:
                                    .linked,
                                sourceData:
                                    source,
                                bookmark:
                                    Data(
                                        "PRIVATE_BOOKMARK_BYTES"
                                            .utf8
                                    )
                            ),
                        ]
                )
            )

        XCTAssertNotNil(
            data.range(
                of:
                    source
            )
        )

        XCTAssertTrue(
            contains(
                data,
                ascii:
                    "8BIMplLd"
            )
        )
    }

    func testSecurityScopedBookmarkBytesAreNotExported() throws {
        let source =
            try pngData()

        let bookmark =
            Data(
                "BOLD_PRIVATE_SECURITY_SCOPED_BOOKMARK_DO_NOT_EXPORT"
                    .utf8
            )

        let data =
            try PSDExporter.export(
                project(
                    layers:
                        [
                            smartLayer(
                                storageMode:
                                    .linked,
                                sourceData:
                                    source,
                                bookmark:
                                    bookmark
                            ),
                        ]
                )
            )

        XCTAssertNil(
            data.range(
                of:
                    bookmark
            )
        )
    }

    func testSourcePathIsReducedToFilename() throws {
        let source =
            try pngData()

        let layer =
            smartLayer(
                sourceFilename:
                    "/private/Users/example/Secret/source.png",
                sourceData:
                    source
            )

        let tool =
            try XCTUnwrap(
                PSDExporter
                    .nativeSmartObjectTool(
                        for:
                            layer,
                        canvasWidth:
                            600,
                        canvasHeight:
                            600
                    )
            )

        XCTAssertEqual(
            tool.filename,
            "source.png"
        )

        XCTAssertFalse(
            tool.filename
                .contains(
                    "/private/"
                )
        )
    }

    func testStableIdentifierUsesLayerUUID() throws {
        let source =
            try pngData()

        let layer =
            smartLayer(
                sourceData:
                    source
            )

        let first =
            try XCTUnwrap(
                PSDExporter
                    .nativeSmartObjectTool(
                        for:
                            layer,
                        canvasWidth:
                            600,
                        canvasHeight:
                            600
                    )
            )

        let second =
            try XCTUnwrap(
                PSDExporter
                    .nativeSmartObjectTool(
                        for:
                            layer,
                        canvasWidth:
                            600,
                        canvasHeight:
                            600
                    )
            )

        XCTAssertEqual(
            first.identifier,
            second.identifier
        )

        XCTAssertEqual(
            first.identifier,
            layer.id
                .uuidString
                .lowercased()
        )
    }

    func testFrameMapsToFourCornerTransform() throws {
        let source =
            try pngData()

        let layer =
            smartLayer(
                sourceData:
                    source
            )

        let tool =
            try XCTUnwrap(
                PSDExporter
                    .nativeSmartObjectTool(
                        for:
                            layer,
                        canvasWidth:
                            1000,
                        canvasHeight:
                            1000
                    )
            )

        XCTAssertEqual(
            tool.transform.count,
            8
        )

        XCTAssertEqual(
            tool.transform[0],
            100,
            accuracy:
                0.0001
        )

        XCTAssertEqual(
            tool.transform[1],
            200,
            accuracy:
                0.0001
        )

        XCTAssertEqual(
            tool.transform[2],
            500,
            accuracy:
                0.0001
        )

        XCTAssertEqual(
            tool.transform[3],
            200,
            accuracy:
                0.0001
        )

        XCTAssertEqual(
            tool.transform[4],
            500,
            accuracy:
                0.0001
        )

        XCTAssertEqual(
            tool.transform[5],
            500,
            accuracy:
                0.0001
        )

        XCTAssertEqual(
            tool.transform[6],
            100,
            accuracy:
                0.0001
        )

        XCTAssertEqual(
            tool.transform[7],
            500,
            accuracy:
                0.0001
        )
    }

    func testRotationChangesPlacementTransform() throws {
        let source =
            try pngData()

        var layer =
            smartLayer(
                sourceData:
                    source
            )

        layer.rotation =
            30

        let tool =
            try XCTUnwrap(
                PSDExporter
                    .nativeSmartObjectTool(
                        for:
                            layer,
                        canvasWidth:
                            1000,
                        canvasHeight:
                            1000
                    )
            )

        XCTAssertNotEqual(
            tool.transform[1],
            200,
            accuracy:
                0.0001
        )
    }

    func testHorizontalFlipChangesPlacementTransform() throws {
        let source =
            try pngData()

        var layer =
            smartLayer(
                sourceData:
                    source
            )

        layer.flipHorizontal =
            true

        let tool =
            try XCTUnwrap(
                PSDExporter
                    .nativeSmartObjectTool(
                        for:
                            layer,
                        canvasWidth:
                            1000,
                        canvasHeight:
                            1000
                    )
            )

        XCTAssertGreaterThan(
            tool.transform[0],
            tool.transform[2]
        )
    }

    func testVerticalFlipChangesPlacementTransform() throws {
        let source =
            try pngData()

        var layer =
            smartLayer(
                sourceData:
                    source
            )

        layer.flipVertical =
            true

        let tool =
            try XCTUnwrap(
                PSDExporter
                    .nativeSmartObjectTool(
                        for:
                            layer,
                        canvasWidth:
                            1000,
                        canvasHeight:
                            1000
                    )
            )

        XCTAssertGreaterThan(
            tool.transform[1],
            tool.transform[7]
        )
    }

    func testSkewChangesPlacementTransform() throws {
        let source =
            try pngData()

        var layer =
            smartLayer(
                sourceData:
                    source
            )

        layer.skewX =
            0.25

        let tool =
            try XCTUnwrap(
                PSDExporter
                    .nativeSmartObjectTool(
                        for:
                            layer,
                        canvasWidth:
                            1000,
                        canvasHeight:
                            1000
                    )
            )

        XCTAssertNotEqual(
            tool.transform[0],
            100,
            accuracy:
                0.0001
        )
    }

    func testNativeSmartObjectExportIsDeterministic() throws {
        let source =
            try pngData()

        let fixed =
            project(
                layers:
                    [
                        smartLayer(
                            sourceData:
                                source
                        ),
                    ]
            )

        XCTAssertEqual(
            try PSDExporter.export(
                fixed
            ),
            try PSDExporter.export(
                fixed
            )
        )
    }

    func testLegacyRasterProjectDoesNotEmitSmartObjectMarkers() throws {
        let source =
            try pngData()

        var layer =
            CoverLayer(
                kind:
                    .image,
                name:
                    "Raster",
                frame:
                    CoverRect(
                        x:
                            0,
                        y:
                            0,
                        width:
                            1,
                        height:
                            1
                    )
            )

        layer.imageData =
            source

        let data =
            try PSDExporter.export(
                project(
                    layers:
                        [
                            layer,
                        ]
                )
            )

        XCTAssertFalse(
            contains(
                data,
                ascii:
                    "8BIMplLd"
            )
        )

        XCTAssertFalse(
            contains(
                data,
                ascii:
                    "8BIMlnk2"
            )
        )
    }

    func testNativeGroupAndSmartObjectMetadataCoexist() throws {
        let source =
            try pngData()

        let folder =
            CoverLayer(
                kind:
                    .group,
                name:
                    "Folder"
            )

        var child =
            smartLayer(
                sourceData:
                    source
            )

        child.groupID =
            folder.id

        let data =
            try PSDExporter.export(
                project(
                    layers:
                        [
                            child,
                            folder,
                        ]
                )
            )

        XCTAssertTrue(
            contains(
                data,
                ascii:
                    "8BIMlsct"
            )
        )

        XCTAssertTrue(
            contains(
                data,
                ascii:
                    "8BIMplLd"
            )
        )
    }

    func testEditableTextAndSmartObjectMetadataCoexist() throws {
        let source =
            try pngData()

        var textLayer =
            CoverLayer(
                kind:
                    .text,
                name:
                    "Editable Text",
                frame:
                    CoverRect(
                        x:
                            0.55,
                        y:
                            0.05,
                        width:
                            0.35,
                        height:
                            0.20
                    )
            )

        textLayer.text =
            "Hello"

        let data =
            try PSDExporter.export(
                project(
                    layers:
                        [
                            smartLayer(
                                sourceData:
                                    source
                            ),
                            textLayer,
                        ]
                )
            )

        XCTAssertTrue(
            contains(
                data,
                ascii:
                    "8BIMplLd"
            )
        )

        XCTAssertTrue(
            contains(
                data,
                ascii:
                    "8BIMTySh"
            )
        )
    }
}
