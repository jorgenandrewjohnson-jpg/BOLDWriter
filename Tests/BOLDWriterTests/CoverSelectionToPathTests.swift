import XCTest
import AppKit
@testable import BOLDWriter

final class CoverSelectionToPathTests: XCTestCase {
    private func index(
        _ x: Int,
        _ y: Int,
        width: Int
    ) -> Int {
        y * width + x
    }

    private func mask(
        width: Int,
        height: Int,
        selected: Set<Int>,
        inside: UInt8 = 255
    ) -> Data {
        var values =
            [UInt8](
                repeating: 0,
                count: width * height
            )

        for index in selected
        where index >= 0
            && index < values.count
        {
            values[index] =
                inside
        }

        return Data(values)
    }

    private func rectangleMask(
        width: Int,
        height: Int,
        minX: Int,
        minY: Int,
        maxX: Int,
        maxY: Int
    ) -> Data {
        var selected:
            Set<Int> = []

        for y in minY...maxY {
            for x in minX...maxX {
                selected.insert(
                    index(
                        x,
                        y,
                        width: width
                    )
                )
            }
        }

        return mask(
            width: width,
            height: height,
            selected: selected
        )
    }

    private func rasterLayer(
        width: Int,
        height: Int,
        frame: CoverRect = CoverRect()
    ) throws -> CoverLayer {
        var layer =
            CoverLayer(
                kind: .paint,
                name: "Raster",
                frame: frame
            )

        layer.imageData =
            try CoverEditorEngine
                .transparentImage(
                    width: width,
                    height: height
                )

        return layer
    }

    private func project(
        _ layers: [CoverLayer]
    ) -> CoverProject {
        var project =
            CoverProject(
                width: 1,
                height: 1
            )

        project.canvasWidth = 1
        project.canvasHeight = 1
        project.dpi = 40
        project.layers = layers

        return project
    }

    private func binary(
        _ data: Data
    ) -> Data {
        Data(
            data.map {
                $0 >= 128
                    ? 255
                    : 0
            }
        )
    }

    private func roundTrip(
        _ original: Data,
        width: Int,
        height: Int
    ) throws -> (
        layer: CoverLayer,
        reconstructed: Data
    ) {
        let target =
            try rasterLayer(
                width: width,
                height: height
            )

        let layer =
            try XCTUnwrap(
                CoverEditorEngine
                    .vectorPathLayerFromSelection(
                        original,
                        width: width,
                        height: height,
                        frame: target.frame
                    )
            )

        let reconstructed =
            try XCTUnwrap(
                CoverEditorEngine
                    .selectionFromVectorPath(
                        layer: layer,
                        project:
                            project(
                                [
                                    target,
                                    layer
                                ]
                            ),
                        targetLayer: target,
                        width: width,
                        height: height,
                        antialias: false
                    )
            )

        return (
            layer,
            reconstructed
        )
    }

    func testRejectsInvalidMasks() {
        XCTAssertNil(
            CoverEditorEngine
                .vectorContoursFromSelection(
                    Data(),
                    width: 4,
                    height: 4
                )
        )

        XCTAssertNil(
            CoverEditorEngine
                .vectorContoursFromSelection(
                    Data(
                        repeating: 255,
                        count: 15
                    ),
                    width: 4,
                    height: 4
                )
        )

        XCTAssertNil(
            CoverEditorEngine
                .vectorContoursFromSelection(
                    Data(
                        repeating: 127,
                        count: 16
                    ),
                    width: 4,
                    height: 4
                )
        )
    }

    func testThresholdUsesFiftyPercentCoverage() throws {
        let contours =
            try XCTUnwrap(
                CoverEditorEngine
                    .vectorContoursFromSelection(
                        Data(
                            [
                                127,
                                128,
                                255
                            ]
                        ),
                        width: 3,
                        height: 1
                    )
            )

        XCTAssertEqual(
            contours.count,
            1
        )

        XCTAssertEqual(
            contours[0].count,
            4
        )

        let xs =
            contours[0].map(\.x)

        let minX =
            try XCTUnwrap(
                xs.min()
            )

        let maxX =
            try XCTUnwrap(
                xs.max()
            )

        XCTAssertEqual(
            minX,
            1.0 / 3.0,
            accuracy: 0.000001
        )

        XCTAssertEqual(
            maxX,
            1,
            accuracy: 0.000001
        )
    }

    func testSinglePixelProducesFourCornerContour() throws {
        let width = 3
        let height = 3

        let selection =
            mask(
                width: width,
                height: height,
                selected: [
                    index(
                        1,
                        1,
                        width: width
                    )
                ]
            )

        let contours =
            try XCTUnwrap(
                CoverEditorEngine
                    .vectorContoursFromSelection(
                        selection,
                        width: width,
                        height: height
                    )
            )

        XCTAssertEqual(
            contours.count,
            1
        )

        XCTAssertEqual(
            contours[0].count,
            4
        )

        let allCorners =
            contours[0].allSatisfy {
                point in

                point.anchorType == .corner
            }

        XCTAssertTrue(
            allCorners
        )
    }

    func testRectangleSimplifiesToFourAnchors() throws {
        let contours =
            try XCTUnwrap(
                CoverEditorEngine
                    .vectorContoursFromSelection(
                        rectangleMask(
                            width: 10,
                            height: 8,
                            minX: 2,
                            minY: 1,
                            maxX: 7,
                            maxY: 6
                        ),
                        width: 10,
                        height: 8
                    )
            )

        XCTAssertEqual(
            contours.count,
            1
        )

        XCTAssertEqual(
            contours[0].count,
            4
        )
    }

    func testHorizontalAndVerticalRunsSimplify() throws {
        let width = 8
        let height = 8

        var horizontal:
            Set<Int> = []

        for x in 1...6 {
            horizontal.insert(
                index(
                    x,
                    3,
                    width: width
                )
            )
        }

        let horizontalContours =
            try XCTUnwrap(
                CoverEditorEngine
                    .vectorContoursFromSelection(
                        mask(
                            width: width,
                            height: height,
                            selected: horizontal
                        ),
                        width: width,
                        height: height
                    )
            )

        XCTAssertEqual(
            horizontalContours[0].count,
            4
        )

        var vertical:
            Set<Int> = []

        for y in 1...6 {
            vertical.insert(
                index(
                    3,
                    y,
                    width: width
                )
            )
        }

        let verticalContours =
            try XCTUnwrap(
                CoverEditorEngine
                    .vectorContoursFromSelection(
                        mask(
                            width: width,
                            height: height,
                            selected: vertical
                        ),
                        width: width,
                        height: height
                    )
            )

        XCTAssertEqual(
            verticalContours[0].count,
            4
        )
    }

    func testDisconnectedIslandsCreateSeparateContours() throws {
        let width = 8
        let height = 8

        let contours =
            try XCTUnwrap(
                CoverEditorEngine
                    .vectorContoursFromSelection(
                        mask(
                            width: width,
                            height: height,
                            selected: [
                                index(
                                    1,
                                    1,
                                    width: width
                                ),
                                index(
                                    6,
                                    6,
                                    width: width
                                )
                            ]
                        ),
                        width: width,
                        height: height
                    )
            )

        XCTAssertEqual(
            contours.count,
            2
        )
    }

    func testDiagonalTouchingPixelsStaySeparate() throws {
        let contours =
            try XCTUnwrap(
                CoverEditorEngine
                    .vectorContoursFromSelection(
                        mask(
                            width: 2,
                            height: 2,
                            selected: [
                                index(
                                    0,
                                    0,
                                    width: 2
                                ),
                                index(
                                    1,
                                    1,
                                    width: 2
                                )
                            ]
                        ),
                        width: 2,
                        height: 2
                    )
            )

        XCTAssertEqual(
            contours.count,
            2
        )

        XCTAssertEqual(
            contours.map(\.count),
            [
                4,
                4
            ]
        )
    }

    func testDonutCreatesOuterAndHoleContours() throws {
        let width = 7
        let height = 7

        var selected:
            Set<Int> = []

        for y in 1...5 {
            for x in 1...5 {
                if x == 1
                    || x == 5
                    || y == 1
                    || y == 5
                {
                    selected.insert(
                        index(
                            x,
                            y,
                            width: width
                        )
                    )
                }
            }
        }

        let contours =
            try XCTUnwrap(
                CoverEditorEngine
                    .vectorContoursFromSelection(
                        mask(
                            width: width,
                            height: height,
                            selected: selected
                        ),
                        width: width,
                        height: height
                    )
            )

        XCTAssertEqual(
            contours.count,
            2
        )
    }

    func testCanvasEdgeSelectionStaysNormalized() throws {
        let contours =
            try XCTUnwrap(
                CoverEditorEngine
                    .vectorContoursFromSelection(
                        Data(
                            repeating: 255,
                            count: 24
                        ),
                        width: 6,
                        height: 4
                    )
            )

        XCTAssertEqual(
            contours.count,
            1
        )

        XCTAssertEqual(
            contours[0].count,
            4
        )

        let points:
            [CoverPathPoint] =
                contours[0]

        let allNormalized =
            points.allSatisfy {
                point in

                point.x >= 0
                && point.x <= 1
                && point.y >= 0
                && point.y <= 1
            }

        XCTAssertTrue(
            allNormalized
        )
    }

    func testTopRasterSelectionStoresTopDownVectorY() throws {
        let width = 4
        let height = 4

        let contours =
            try XCTUnwrap(
                CoverEditorEngine
                    .vectorContoursFromSelection(
                        mask(
                            width: width,
                            height: height,
                            selected: [
                                index(
                                    1,
                                    0,
                                    width: width
                                )
                            ]
                        ),
                        width: width,
                        height: height
                    )
            )

        let ys =
            contours[0].map(\.y)

        let minY =
            try XCTUnwrap(
                ys.min()
            )

        let maxY =
            try XCTUnwrap(
                ys.max()
            )

        XCTAssertEqual(
            minY,
            0,
            accuracy: 0.000001
        )

        XCTAssertEqual(
            maxY,
            0.25,
            accuracy: 0.000001
        )
    }

    func testLayerFactorySynchronizesMirrorsAndClosureMetadata() throws {
        let selection =
            mask(
                width: 8,
                height: 8,
                selected: [
                    index(
                        1,
                        1,
                        width: 8
                    ),
                    index(
                        6,
                        6,
                        width: 8
                    )
                ]
            )

        let frame =
            CoverRect(
                x: 0.2,
                y: 0.3,
                width: 0.4,
                height: 0.5
            )

        let layer =
            try XCTUnwrap(
                CoverEditorEngine
                    .vectorPathLayerFromSelection(
                        selection,
                        width: 8,
                        height: 8,
                        frame: frame
                    )
            )

        XCTAssertEqual(
            layer.kind,
            .path
        )

        XCTAssertEqual(
            layer.frame,
            frame
        )

        XCTAssertEqual(
            layer.pathContours?.count,
            2
        )

        XCTAssertEqual(
            layer.pathPoints,
            layer.pathContours?.first
        )

        XCTAssertEqual(
            layer.pathClosed,
            true
        )

        XCTAssertEqual(
            layer.pathContourClosed,
            [
                true,
                true
            ]
        )

        XCTAssertEqual(
            layer.rotation,
            0
        )

        XCTAssertFalse(
            layer.flipHorizontal
        )

        XCTAssertFalse(
            layer.flipVertical
        )

        XCTAssertNil(
            layer.skewX
        )

        XCTAssertNil(
            layer.skewY
        )
    }

    func testLayerFactoryCreatesUniqueIDs() throws {
        let selection =
            rectangleMask(
                width: 4,
                height: 4,
                minX: 1,
                minY: 1,
                maxX: 2,
                maxY: 2
            )

        let first =
            try XCTUnwrap(
                CoverEditorEngine
                    .vectorPathLayerFromSelection(
                        selection,
                        width: 4,
                        height: 4,
                        frame: CoverRect()
                    )
            )

        let second =
            try XCTUnwrap(
                CoverEditorEngine
                    .vectorPathLayerFromSelection(
                        selection,
                        width: 4,
                        height: 4,
                        frame: CoverRect()
                    )
            )

        XCTAssertNotEqual(
            first.id,
            second.id
        )
    }

    func testGeneratedPathSurvivesCodableRoundTrip() throws {
        let layer =
            try XCTUnwrap(
                CoverEditorEngine
                    .vectorPathLayerFromSelection(
                        rectangleMask(
                            width: 5,
                            height: 5,
                            minX: 1,
                            minY: 1,
                            maxX: 3,
                            maxY: 3
                        ),
                        width: 5,
                        height: 5,
                        frame:
                            CoverRect(
                                x: 0.1,
                                y: 0.2,
                                width: 0.7,
                                height: 0.6
                            )
                    )
            )

        let encoded =
            try JSONEncoder()
                .encode(layer)

        let decoded =
            try JSONDecoder()
                .decode(
                    CoverLayer.self,
                    from: encoded
                )

        XCTAssertEqual(
            decoded,
            layer
        )
    }

    func testProjectInsertionPreservesHostAndLayerOrder() throws {
        let before =
            try rasterLayer(
                width: 4,
                height: 4
            )

        let host =
            try rasterLayer(
                width: 4,
                height: 4,
                frame:
                    CoverRect(
                        x: 0.2,
                        y: 0.25,
                        width: 0.5,
                        height: 0.4
                    )
            )

        let after =
            try rasterLayer(
                width: 4,
                height: 4
            )

        let originalHost =
            host

        let originalProject =
            project(
                [
                    before,
                    host,
                    after
                ]
            )

        let mutation =
            try XCTUnwrap(
                CoverEditorEngine
                    .insertingSelectionPathLayer(
                        in: originalProject,
                        hostLayerID: host.id,
                        selection:
                            rectangleMask(
                                width: 4,
                                height: 4,
                                minX: 1,
                                minY: 1,
                                maxX: 2,
                                maxY: 2
                            ),
                        width: 4,
                        height: 4,
                        fillHex: "#123456",
                        strokeHex: "#ABCDEF",
                        strokeWidth: 1.5
                    )
            )

        XCTAssertEqual(
            mutation.project.layers.count,
            4
        )

        XCTAssertEqual(
            mutation.project.layers[0].id,
            before.id
        )

        XCTAssertEqual(
            mutation.project.layers[1],
            originalHost
        )

        XCTAssertEqual(
            mutation.project.layers[2].id,
            mutation.layer.id
        )

        XCTAssertEqual(
            mutation.project.layers[3].id,
            after.id
        )

        XCTAssertEqual(
            mutation.layer.frame,
            host.frame
        )

        XCTAssertEqual(
            mutation.layer.fillHex,
            "#123456"
        )

        XCTAssertEqual(
            mutation.layer.strokeHex,
            "#ABCDEF"
        )

        XCTAssertEqual(
            mutation.layer.strokeWidth,
            1.5
        )

        XCTAssertEqual(
            originalProject.layers[1],
            originalHost
        )
    }

    func testProjectInsertionRejectsDimensionMismatch() throws {
        let host =
            try rasterLayer(
                width: 4,
                height: 4
            )

        XCTAssertNil(
            CoverEditorEngine
                .insertingSelectionPathLayer(
                    in:
                        project(
                            [
                                host
                            ]
                        ),
                    hostLayerID: host.id,
                    selection:
                        Data(
                            repeating: 255,
                            count: 25
                        ),
                    width: 5,
                    height: 5
                )
        )
    }

    func testRectangleRoundTripIsExact() throws {
        let width = 12
        let height = 10

        let original =
            rectangleMask(
                width: width,
                height: height,
                minX: 2,
                minY: 1,
                maxX: 8,
                maxY: 6
            )

        let result =
            try roundTrip(
                original,
                width: width,
                height: height
            )

        XCTAssertEqual(
            binary(
                result.reconstructed
            ),
            original
        )
    }

    func testDisconnectedIslandRoundTripIsExact() throws {
        let width = 10
        let height = 10

        var selected:
            Set<Int> = []

        for y in 1...3 {
            for x in 1...3 {
                selected.insert(
                    index(
                        x,
                        y,
                        width: width
                    )
                )
            }
        }

        for y in 6...8 {
            for x in 6...8 {
                selected.insert(
                    index(
                        x,
                        y,
                        width: width
                    )
                )
            }
        }

        let original =
            mask(
                width: width,
                height: height,
                selected: selected
            )

        let result =
            try roundTrip(
                original,
                width: width,
                height: height
            )

        XCTAssertEqual(
            binary(
                result.reconstructed
            ),
            original
        )
    }

    func testDonutRoundTripIsExact() throws {
        let width = 11
        let height = 11

        var selected:
            Set<Int> = []

        for y in 1...9 {
            for x in 1...9 {
                let hole =
                    x >= 4
                    && x <= 6
                    && y >= 4
                    && y <= 6

                if !hole {
                    selected.insert(
                        index(
                            x,
                            y,
                            width: width
                        )
                    )
                }
            }
        }

        let original =
            mask(
                width: width,
                height: height,
                selected: selected
            )

        let result =
            try roundTrip(
                original,
                width: width,
                height: height
            )

        XCTAssertEqual(
            result.layer.pathContours?.count,
            2
        )

        XCTAssertEqual(
            binary(
                result.reconstructed
            ),
            original
        )
    }

    func testAsymmetricTopRoundTripIsNotMirrored() throws {
        let width = 9
        let height = 9

        let original =
            rectangleMask(
                width: width,
                height: height,
                minX: 2,
                minY: 0,
                maxX: 6,
                maxY: 2
            )

        let result =
            try roundTrip(
                original,
                width: width,
                height: height
            )

        XCTAssertEqual(
            binary(
                result.reconstructed
            ),
            original
        )
    }

    func testSourceSelectionDataIsNotMutatedByTracing() throws {
        let selection =
            rectangleMask(
                width: 8,
                height: 8,
                minX: 1,
                minY: 2,
                maxX: 6,
                maxY: 5
            )

        let snapshot =
            selection

        _ =
            try XCTUnwrap(
                CoverEditorEngine
                    .vectorContoursFromSelection(
                        selection,
                        width: 8,
                        height: 8
                    )
            )

        XCTAssertEqual(
            selection,
            snapshot
        )
    }
}
