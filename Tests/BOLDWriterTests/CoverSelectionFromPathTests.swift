import XCTest
import AppKit
@testable import BOLDWriter

final class CoverSelectionFromPathTests: XCTestCase {
    private func point(
        _ x: Double,
        _ y: Double,
        type: CoverPathAnchorType? = nil,
        inX: Double? = nil,
        inY: Double? = nil,
        outX: Double? = nil,
        outY: Double? = nil
    ) -> CoverPathPoint {
        CoverPathPoint(
            x: x,
            y: y,
            controlInX: inX,
            controlInY: inY,
            controlOutX: outX,
            controlOutY: outY,
            anchorType: type
        )
    }

    private func rectangle(
        x: Double,
        y: Double,
        width: Double,
        height: Double
    ) -> [CoverPathPoint] {
        [
            point(x, y),
            point(x + width, y),
            point(x + width, y + height),
            point(x, y + height)
        ]
    }

    private func pathLayer(
        frame: CoverRect = CoverRect(),
        contours: [[CoverPathPoint]],
        closures: [Bool]
    ) -> CoverLayer {
        var layer =
            CoverLayer(
                kind: .path,
                name: "Path",
                frame: frame
            )

        layer.pathPoints =
            contours.first

        layer.pathContours =
            contours

        layer.pathClosed =
            closures.first

        layer.pathContourClosed =
            closures

        return layer
    }

    private func rasterLayer(
        frame: CoverRect = CoverRect()
    ) -> CoverLayer {
        CoverLayer(
            kind: .paint,
            name: "Raster",
            frame: frame
        )
    }

    private func makeProject(
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
        project.layers =
            layers

        return project
    }

    private func value(
        _ mask: Data,
        width: Int,
        x: Int,
        y: Int
    ) -> UInt8 {
        mask[
            y * width + x
        ]
    }

    func testRejectsNonPathLayer() {
        let layer =
            rasterLayer()

        XCTAssertNil(
            CoverEditorEngine
                .selectionFromVectorPath(
                    layer:
                        layer,
                    project:
                        makeProject(
                            [layer]
                        ),
                    targetLayer:
                        layer,
                    width:
                        20,
                    height:
                        20
                )
        )
    }

    func testRejectsEmptyAndOpenOnlyPaths() {
        let target =
            rasterLayer()

        let empty =
            pathLayer(
                contours: [],
                closures: []
            )

        XCTAssertNil(
            CoverEditorEngine
                .selectionFromVectorPath(
                    layer:
                        empty,
                    project:
                        makeProject(
                            [
                                empty,
                                target
                            ]
                        ),
                    targetLayer:
                        target,
                    width:
                        20,
                    height:
                        20
                )
        )

        let open =
            pathLayer(
                contours: [
                    rectangle(
                        x: 0.2,
                        y: 0.2,
                        width: 0.6,
                        height: 0.6
                    )
                ],
                closures: [
                    false
                ]
            )

        XCTAssertNil(
            CoverEditorEngine
                .selectionFromVectorPath(
                    layer:
                        open,
                    project:
                        makeProject(
                            [
                                open,
                                target
                            ]
                        ),
                    targetLayer:
                        target,
                    width:
                        20,
                    height:
                        20
                )
        )
    }

    func testSingleClosedRectangleProducesExpectedRegion() throws {
        let source =
            pathLayer(
                contours: [
                    rectangle(
                        x: 0.25,
                        y: 0.25,
                        width: 0.5,
                        height: 0.5
                    )
                ],
                closures: [
                    true
                ]
            )

        let target =
            rasterLayer()

        let mask =
            try XCTUnwrap(
                CoverEditorEngine
                    .selectionFromVectorPath(
                        layer:
                            source,
                        project:
                            makeProject(
                                [
                                    source,
                                    target
                                ]
                            ),
                        targetLayer:
                            target,
                        width:
                            20,
                        height:
                            20,
                        antialias:
                            false
                    )
            )

        XCTAssertEqual(
            mask.count,
            400
        )

        XCTAssertEqual(
            value(
                mask,
                width: 20,
                x: 1,
                y: 1
            ),
            0
        )

        XCTAssertEqual(
            value(
                mask,
                width: 20,
                x: 10,
                y: 10
            ),
            255
        )
    }

    func testOpenContoursAreIgnoredWhenMixedWithClosedContours() throws {
        let source =
            pathLayer(
                contours: [
                    rectangle(
                        x: 0.1,
                        y: 0.1,
                        width: 0.3,
                        height: 0.3
                    ),
                    rectangle(
                        x: 0.6,
                        y: 0.6,
                        width: 0.3,
                        height: 0.3
                    )
                ],
                closures: [
                    true,
                    false
                ]
            )

        let target =
            rasterLayer()

        let mask =
            try XCTUnwrap(
                CoverEditorEngine
                    .selectionFromVectorPath(
                        layer:
                            source,
                        project:
                            makeProject(
                                [
                                    source,
                                    target
                                ]
                            ),
                        targetLayer:
                            target,
                        width:
                            40,
                        height:
                            40,
                        antialias:
                            false
                    )
            )

        XCTAssertEqual(
            value(
                mask,
                width: 40,
                x: 8,
                y: 8
            ),
            255
        )

        XCTAssertEqual(
            value(
                mask,
                width: 40,
                x: 30,
                y: 30
            ),
            0
        )
    }

    func testTwoDisjointClosedContoursBothAppear() throws {
        let source =
            pathLayer(
                contours: [
                    rectangle(
                        x: 0.1,
                        y: 0.1,
                        width: 0.25,
                        height: 0.25
                    ),
                    rectangle(
                        x: 0.65,
                        y: 0.65,
                        width: 0.25,
                        height: 0.25
                    )
                ],
                closures: [
                    true,
                    true
                ]
            )

        let target =
            rasterLayer()

        let mask =
            try XCTUnwrap(
                CoverEditorEngine
                    .selectionFromVectorPath(
                        layer:
                            source,
                        project:
                            makeProject(
                                [
                                    source,
                                    target
                                ]
                            ),
                        targetLayer:
                            target,
                        width:
                            40,
                        height:
                            40,
                        antialias:
                            false
                    )
            )

        XCTAssertEqual(
            value(
                mask,
                width: 40,
                x: 8,
                y: 8
            ),
            255
        )

        XCTAssertEqual(
            value(
                mask,
                width: 40,
                x: 32,
                y: 32
            ),
            255
        )

        XCTAssertEqual(
            value(
                mask,
                width: 40,
                x: 20,
                y: 20
            ),
            0
        )
    }

    func testEvenOddHoleIsPreserved() throws {
        let source =
            pathLayer(
                contours: [
                    rectangle(
                        x: 0.1,
                        y: 0.1,
                        width: 0.8,
                        height: 0.8
                    ),
                    rectangle(
                        x: 0.35,
                        y: 0.35,
                        width: 0.3,
                        height: 0.3
                    )
                ],
                closures: [
                    true,
                    true
                ]
            )

        let target =
            rasterLayer()

        let mask =
            try XCTUnwrap(
                CoverEditorEngine
                    .selectionFromVectorPath(
                        layer:
                            source,
                        project:
                            makeProject(
                                [
                                    source,
                                    target
                                ]
                            ),
                        targetLayer:
                            target,
                        width:
                            40,
                        height:
                            40,
                        antialias:
                            false
                    )
            )

        XCTAssertEqual(
            value(
                mask,
                width: 40,
                x: 8,
                y: 20
            ),
            255
        )

        XCTAssertEqual(
            value(
                mask,
                width: 40,
                x: 20,
                y: 20
            ),
            0
        )
    }

    func testPathFrameOffsetAndScaleAreRespected() throws {
        let source =
            pathLayer(
                frame:
                    CoverRect(
                        x: 0.25,
                        y: 0.1,
                        width: 0.5,
                        height: 0.4
                    ),
                contours: [
                    rectangle(
                        x: 0,
                        y: 0,
                        width: 1,
                        height: 1
                    )
                ],
                closures: [
                    true
                ]
            )

        let target =
            rasterLayer()

        let mask =
            try XCTUnwrap(
                CoverEditorEngine
                    .selectionFromVectorPath(
                        layer:
                            source,
                        project:
                            makeProject(
                                [
                                    source,
                                    target
                                ]
                            ),
                        targetLayer:
                            target,
                        width:
                            40,
                        height:
                            40,
                        antialias:
                            false
                    )
            )

        XCTAssertEqual(
            value(
                mask,
                width: 40,
                x: 5,
                y: 8
            ),
            0
        )

        XCTAssertEqual(
            value(
                mask,
                width: 40,
                x: 20,
                y: 8
            ),
            255
        )

        XCTAssertEqual(
            value(
                mask,
                width: 40,
                x: 20,
                y: 30
            ),
            0
        )
    }

    func testTargetFrameCoordinatesAreRespected() throws {
        let frame =
            CoverRect(
                x: 0.5,
                y: 0.25,
                width: 0.25,
                height: 0.5
            )

        let source =
            pathLayer(
                frame:
                    frame,
                contours: [
                    rectangle(
                        x: 0,
                        y: 0,
                        width: 1,
                        height: 1
                    )
                ],
                closures: [
                    true
                ]
            )

        let target =
            rasterLayer(
                frame:
                    frame
            )

        let mask =
            try XCTUnwrap(
                CoverEditorEngine
                    .selectionFromVectorPath(
                        layer:
                            source,
                        project:
                            makeProject(
                                [
                                    source,
                                    target
                                ]
                            ),
                        targetLayer:
                            target,
                        width:
                            20,
                        height:
                            20,
                        antialias:
                            false
                    )
            )

        XCTAssertEqual(
            value(
                mask,
                width: 20,
                x: 10,
                y: 10
            ),
            255
        )
    }

    func testRotationIsRespected() throws {
        var source =
            pathLayer(
                contours: [
                    rectangle(
                        x: 0,
                        y: 0,
                        width: 0.3,
                        height: 0.3
                    )
                ],
                closures: [
                    true
                ]
            )

        source.rotation = 180

        let target =
            rasterLayer()

        let mask =
            try XCTUnwrap(
                CoverEditorEngine
                    .selectionFromVectorPath(
                        layer:
                            source,
                        project:
                            makeProject(
                                [
                                    source,
                                    target
                                ]
                            ),
                        targetLayer:
                            target,
                        width:
                            40,
                        height:
                            40,
                        antialias:
                            false
                    )
            )

        XCTAssertEqual(
            value(
                mask,
                width: 40,
                x: 4,
                y: 4
            ),
            0
        )

        XCTAssertEqual(
            value(
                mask,
                width: 40,
                x: 34,
                y: 34
            ),
            255
        )
    }

    func testHorizontalFlipIsRespected() throws {
        var source =
            pathLayer(
                contours: [
                    rectangle(
                        x: 0,
                        y: 0.25,
                        width: 0.25,
                        height: 0.5
                    )
                ],
                closures: [
                    true
                ]
            )

        source.flipHorizontal = true

        let target =
            rasterLayer()

        let mask =
            try XCTUnwrap(
                CoverEditorEngine
                    .selectionFromVectorPath(
                        layer:
                            source,
                        project:
                            makeProject(
                                [
                                    source,
                                    target
                                ]
                            ),
                        targetLayer:
                            target,
                        width:
                            40,
                        height:
                            40,
                        antialias:
                            false
                    )
            )

        XCTAssertEqual(
            value(
                mask,
                width: 40,
                x: 4,
                y: 20
            ),
            0
        )

        XCTAssertEqual(
            value(
                mask,
                width: 40,
                x: 34,
                y: 20
            ),
            255
        )
    }

    func testVerticalFlipIsRespected() throws {
        var source =
            pathLayer(
                contours: [
                    rectangle(
                        x: 0.25,
                        y: 0,
                        width: 0.5,
                        height: 0.25
                    )
                ],
                closures: [
                    true
                ]
            )

        source.flipVertical = true

        let target =
            rasterLayer()

        let mask =
            try XCTUnwrap(
                CoverEditorEngine
                    .selectionFromVectorPath(
                        layer:
                            source,
                        project:
                            makeProject(
                                [
                                    source,
                                    target
                                ]
                            ),
                        targetLayer:
                            target,
                        width:
                            40,
                        height:
                            40,
                        antialias:
                            false
                    )
            )

        XCTAssertEqual(
            value(
                mask,
                width: 40,
                x: 20,
                y: 4
            ),
            0
        )

        XCTAssertEqual(
            value(
                mask,
                width: 40,
                x: 20,
                y: 34
            ),
            255
        )
    }

    func testBezierHandlesUseCorrectYConventionAndAntialiasing() throws {
        let curved = [
            point(
                0.5,
                0.1,
                type: .smooth,
                inX: 0.28,
                inY: 0.1,
                outX: 0.72,
                outY: 0.1
            ),
            point(
                0.9,
                0.5,
                type: .smooth,
                inX: 0.9,
                inY: 0.28,
                outX: 0.9,
                outY: 0.72
            ),
            point(
                0.5,
                0.9,
                type: .smooth,
                inX: 0.72,
                inY: 0.9,
                outX: 0.28,
                outY: 0.9
            ),
            point(
                0.1,
                0.5,
                type: .smooth,
                inX: 0.1,
                inY: 0.72,
                outX: 0.1,
                outY: 0.28
            )
        ]

        let source =
            pathLayer(
                contours: [
                    curved
                ],
                closures: [
                    true
                ]
            )

        let target =
            rasterLayer()

        let mask =
            try XCTUnwrap(
                CoverEditorEngine
                    .selectionFromVectorPath(
                        layer:
                            source,
                        project:
                            makeProject(
                                [
                                    source,
                                    target
                                ]
                            ),
                        targetLayer:
                            target,
                        width:
                            31,
                        height:
                            31,
                        antialias:
                            true
                    )
            )

        XCTAssertEqual(
            value(
                mask,
                width: 31,
                x: 15,
                y: 15
            ),
            255
        )

        XCTAssertTrue(
            mask.contains {
                $0 > 0
                && $0 < 255
            }
        )
    }

    func testSourcePathRemainsUnchanged() throws {
        var source =
            pathLayer(
                frame:
                    CoverRect(
                        x: 0.2,
                        y: 0.1,
                        width: 0.6,
                        height: 0.7
                    ),
                contours: [
                    [
                        point(
                            0,
                            0,
                            type: .corner,
                            outX: 0.2,
                            outY: 0.1
                        ),
                        point(
                            1,
                            0,
                            type: .smooth,
                            inX: 0.8,
                            inY: 0.1,
                            outX: 1,
                            outY: 0.3
                        ),
                        point(
                            1,
                            1,
                            type: .symmetric,
                            inX: 0.8,
                            inY: 0.9
                        ),
                        point(
                            0,
                            1,
                            type: .corner
                        )
                    ]
                ],
                closures: [
                    true
                ]
            )

        source.rotation = 17
        source.flipHorizontal = true

        let snapshot =
            source

        let target =
            rasterLayer()

        _ =
            try XCTUnwrap(
                CoverEditorEngine
                    .selectionFromVectorPath(
                        layer:
                            source,
                        project:
                            makeProject(
                                [
                                    source,
                                    target
                                ]
                            ),
                        targetLayer:
                            target,
                        width:
                            30,
                        height:
                            30
                    )
            )

        XCTAssertEqual(
            source,
            snapshot
        )

        XCTAssertEqual(
            source.pathPoints,
            snapshot.pathPoints
        )

        XCTAssertEqual(
            source.pathContourClosed,
            snapshot.pathContourClosed
        )
    }

    func testReplaceSelectionSemanticsStillUseCanonicalCombine() throws {
        let source =
            pathLayer(
                contours: [
                    rectangle(
                        x: 0.25,
                        y: 0.25,
                        width: 0.5,
                        height: 0.5
                    )
                ],
                closures: [
                    true
                ]
            )

        let target =
            rasterLayer()

        let mask =
            try XCTUnwrap(
                CoverEditorEngine
                    .selectionFromVectorPath(
                        layer:
                            source,
                        project:
                            makeProject(
                                [
                                    source,
                                    target
                                ]
                            ),
                        targetLayer:
                            target,
                        width:
                            20,
                        height:
                            20
                    )
            )

        let old =
            Data(
                repeating:
                    255,
                count:
                    mask.count
            )

        XCTAssertEqual(
            CoverEditorEngine
                .combine(
                    old,
                    mask,
                    mode:
                        .replace
                ),
            mask
        )
    }

    func testGeneratedMaskUsesExistingSelectionPreviewPipeline() throws {
        let source =
            pathLayer(
                contours: [
                    rectangle(
                        x: 0.2,
                        y: 0.1,
                        width: 0.6,
                        height: 0.4
                    )
                ],
                closures: [
                    true
                ]
            )

        let target =
            rasterLayer()

        let mask =
            try XCTUnwrap(
                CoverEditorEngine
                    .selectionFromVectorPath(
                        layer:
                            source,
                        project:
                            makeProject(
                                [
                                    source,
                                    target
                                ]
                            ),
                        targetLayer:
                            target,
                        width:
                            24,
                        height:
                            24
                    )
            )

        let preview =
            try XCTUnwrap(
                CoverEditorEngine
                    .selectionPreview(
                        mask,
                        width:
                            24,
                        height:
                            24
                    )
            )

        XCTAssertFalse(
            preview.isEmpty
        )

        XCTAssertNotNil(
            NSImage(
                data:
                    preview
            )
        )
    }

    func testRejectsSkewedSourceAndTransformedRasterTarget() {
        var source =
            pathLayer(
                contours: [
                    rectangle(
                        x: 0.2,
                        y: 0.2,
                        width: 0.6,
                        height: 0.6
                    )
                ],
                closures: [
                    true
                ]
            )

        let target =
            rasterLayer()

        source.skewX = 0.2

        XCTAssertNil(
            CoverEditorEngine
                .selectionFromVectorPath(
                    layer:
                        source,
                    project:
                        makeProject(
                            [
                                source,
                                target
                            ]
                        ),
                    targetLayer:
                        target,
                    width:
                        20,
                    height:
                        20
                )
        )

        source.skewX = nil

        var rotatedTarget =
            target

        rotatedTarget.rotation = 10

        XCTAssertNil(
            CoverEditorEngine
                .selectionFromVectorPath(
                    layer:
                        source,
                    project:
                        makeProject(
                            [
                                source,
                                rotatedTarget
                            ]
                        ),
                    targetLayer:
                        rotatedTarget,
                    width:
                        20,
                    height:
                        20
                )
        )
    }

    func testAsymmetricYPositionIsNotVerticallyMirrored() throws {
        let source =
            pathLayer(
                contours: [
                    rectangle(
                        x: 0.2,
                        y: 0.05,
                        width: 0.3,
                        height: 0.2
                    )
                ],
                closures: [
                    true
                ]
            )

        let target =
            rasterLayer()

        let mask =
            try XCTUnwrap(
                CoverEditorEngine
                    .selectionFromVectorPath(
                        layer:
                            source,
                        project:
                            makeProject(
                                [
                                    source,
                                    target
                                ]
                            ),
                        targetLayer:
                            target,
                        width:
                            40,
                        height:
                            40,
                        antialias:
                            false
                    )
            )

        XCTAssertEqual(
            value(
                mask,
                width: 40,
                x: 12,
                y: 5
            ),
            255
        )

        XCTAssertEqual(
            value(
                mask,
                width: 40,
                x: 12,
                y: 35
            ),
            0
        )
    }

    func testVerticalBezierControlIsNotDoubleInverted() throws {
        let contour = [
            point(
                0.2,
                0.1,
                type: .smooth,
                outX: 0.5,
                outY: 0.1
            ),
            point(
                0.8,
                0.5,
                type: .smooth,
                inX: 0.8,
                inY: 0.2,
                outX: 0.8,
                outY: 0.8
            ),
            point(
                0.2,
                0.9,
                type: .smooth,
                inX: 0.5,
                inY: 0.9
            )
        ]

        let source =
            pathLayer(
                contours: [
                    contour
                ],
                closures: [
                    true
                ]
            )

        let snapshot =
            source

        let target =
            rasterLayer()

        let mask =
            try XCTUnwrap(
                CoverEditorEngine
                    .selectionFromVectorPath(
                        layer:
                            source,
                        project:
                            makeProject(
                                [
                                    source,
                                    target
                                ]
                            ),
                        targetLayer:
                            target,
                        width:
                            50,
                        height:
                            50,
                        antialias:
                            true
                    )
            )

        XCTAssertTrue(
            mask.contains {
                $0 > 0
            }
        )

        XCTAssertEqual(
            source,
            snapshot
        )
    }
}
