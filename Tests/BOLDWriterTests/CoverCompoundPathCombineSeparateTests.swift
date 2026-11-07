import XCTest
import Foundation
@testable import BOLDWriter

final class CoverCompoundPathCombineSeparateTests: XCTestCase {
    private func point(
        _ x: Double,
        _ y: Double = 0,
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

    private func contour(
        _ marker: Double
    ) -> [CoverPathPoint] {
        [
            point(
                0,
                0,
                type: .corner,
                outX: 0.2,
                outY: 0.1
            ),
            point(
                0.5,
                0.8,
                type: .smooth,
                inX: 0.3,
                inY: 0.7,
                outX: 0.7,
                outY: 0.9
            ),
            point(
                1,
                0,
                type: .symmetric,
                inX: 0.8,
                inY: 0.1
            )
        ].map {
            var value = $0
            value.x += marker
            return value
        }
    }

    private func pathLayer(
        _ name: String,
        frame: CoverRect,
        contours: [[CoverPathPoint]],
        closures: [Bool]
    ) -> CoverLayer {
        var layer =
            CoverLayer(
                kind: .path,
                name: name,
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

    private func makeProject(
        _ layers:[CoverLayer]
    )->CoverProject {
        var project=CoverProject(
            width:10,
            height:10
        )

        project.dpi=72
        project.backgroundHex="#000000"
        project.layers=layers

        return project
    }


    func testSeparateRejectsNonPathLayer() {
        var layer =
            CoverLayer(
                kind: .shape,
                name: "Shape"
            )

        layer.pathPoints = [
            point(0),
            point(1)
        ]

        XCTAssertNil(
            CoverEditorEngine
                .separatedVectorPathLayers(
                    from:
                        layer
                )
        )
    }

    func testSeparateRejectsSingleContourPath() {
        let layer =
            pathLayer(
                "Single",
                frame:
                    CoverRect(),
                contours: [
                    contour(0)
                ],
                closures: [
                    true
                ]
            )

        XCTAssertNil(
            CoverEditorEngine
                .separatedVectorPathLayers(
                    from:
                        layer
                )
        )
    }

    func testSeparateProducesOneLayerPerContourInOrder() throws {
        let a = contour(0)
        let b = contour(10)
        let c = contour(20)

        let layer =
            pathLayer(
                "Compound",
                frame:
                    CoverRect(
                        x: 0.1,
                        y: 0.1,
                        width: 0.8,
                        height: 0.8
                    ),
                contours: [
                    a,
                    b,
                    c
                ],
                closures: [
                    true,
                    false,
                    true
                ]
            )

        let separated =
            try XCTUnwrap(
                CoverEditorEngine
                    .separatedVectorPathLayers(
                        from:
                            layer
                    )
            )

        XCTAssertEqual(
            separated.count,
            3
        )

        XCTAssertEqual(
            separated[0].pathPoints,
            a
        )

        XCTAssertEqual(
            separated[1].pathPoints,
            b
        )

        XCTAssertEqual(
            separated[2].pathPoints,
            c
        )

        XCTAssertEqual(
            separated.map(\.name),
            [
                "Compound 1",
                "Compound 2",
                "Compound 3"
            ]
        )
    }

    func testSeparatePreservesHandlesTypesAndClosuresExactly() throws {
        let a = contour(0)
        let b = contour(10)

        let separated =
            try XCTUnwrap(
                CoverEditorEngine
                    .separatedVectorPathLayers(
                        from:
                            pathLayer(
                                "Compound",
                                frame:
                                    CoverRect(),
                                contours: [
                                    a,
                                    b
                                ],
                                closures: [
                                    true,
                                    false
                                ]
                            )
                    )
            )

        XCTAssertEqual(
            separated[0].pathPoints,
            a
        )

        XCTAssertEqual(
            separated[1].pathPoints,
            b
        )

        XCTAssertEqual(
            separated[0].pathClosed,
            true
        )

        XCTAssertEqual(
            separated[1].pathClosed,
            false
        )

        XCTAssertEqual(
            separated[0].pathContourClosed,
            [true]
        )

        XCTAssertEqual(
            separated[1].pathContourClosed,
            [false]
        )
    }

    func testSeparatePreservesFrameTransformAndStyle() throws {
        var layer =
            pathLayer(
                "Styled",
                frame:
                    CoverRect(
                        x: 0.2,
                        y: 0.3,
                        width: 0.4,
                        height: 0.5
                    ),
                contours: [
                    contour(0),
                    contour(10)
                ],
                closures: [
                    true,
                    false
                ]
            )

        layer.rotation = 37
        layer.skewX = 0.12
        layer.skewY = -0.08
        layer.flipHorizontal = true
        layer.flipVertical = true
        layer.fillHex = "#123456"
        layer.strokeHex = "#ABCDEF"
        layer.strokeWidth = 7
        layer.opacity = 0.42
        layer.blendMode = .multiply

        var shadow =
            CoverDropShadow()

        shadow.opacity = 0.31
        shadow.distance = 0.07

        layer.dropShadow =
            shadow

        let separated =
            try XCTUnwrap(
                CoverEditorEngine
                    .separatedVectorPathLayers(
                        from:
                            layer
                    )
            )

        for result in separated {
            XCTAssertEqual(
                result.frame,
                layer.frame
            )

            XCTAssertEqual(
                result.rotation,
                layer.rotation
            )

            XCTAssertEqual(
                result.skewX,
                layer.skewX
            )

            XCTAssertEqual(
                result.skewY,
                layer.skewY
            )

            XCTAssertEqual(
                result.flipHorizontal,
                layer.flipHorizontal
            )

            XCTAssertEqual(
                result.flipVertical,
                layer.flipVertical
            )

            XCTAssertEqual(
                result.fillHex,
                layer.fillHex
            )

            XCTAssertEqual(
                result.strokeHex,
                layer.strokeHex
            )

            XCTAssertEqual(
                result.strokeWidth,
                layer.strokeWidth
            )

            XCTAssertEqual(
                result.opacity,
                layer.opacity
            )

            XCTAssertEqual(
                result.blendMode,
                layer.blendMode
            )

            XCTAssertEqual(
                result.dropShadow,
                layer.dropShadow
            )
        }
    }

    func testSeparateAssignsUniqueLayerIDs() throws {
        let layer =
            pathLayer(
                "Compound",
                frame:
                    CoverRect(),
                contours: [
                    contour(0),
                    contour(10),
                    contour(20)
                ],
                closures: [
                    true,
                    false,
                    true
                ]
            )

        let separated =
            try XCTUnwrap(
                CoverEditorEngine
                    .separatedVectorPathLayers(
                        from:
                            layer
                    )
            )

        XCTAssertEqual(
            Set(
                separated.map(
                    \.id
                )
            ).count,
            separated.count
        )

        XCTAssertFalse(
            separated.contains {
                $0.id == layer.id
            }
        )
    }

    func testSeparateResultPersistsThroughCodable() throws {
        let separated =
            try XCTUnwrap(
                CoverEditorEngine
                    .separatedVectorPathLayers(
                        from:
                            pathLayer(
                                "Compound",
                                frame:
                                    CoverRect(),
                                contours: [
                                    contour(0),
                                    contour(10)
                                ],
                                closures: [
                                    true,
                                    false
                                ]
                            )
                    )
            )

        for layer in separated {
            let reopened =
                try JSONDecoder()
                    .decode(
                        CoverLayer.self,
                        from:
                            JSONEncoder()
                                .encode(
                                    layer
                                )
                    )

            XCTAssertEqual(
                reopened,
                layer
            )
        }
    }

    func testSeparateProjectMutationPreservesStackPosition() throws {
        let before =
            pathLayer(
                "Before",
                frame:
                    CoverRect(),
                contours: [
                    contour(30)
                ],
                closures: [
                    true
                ]
            )

        let compound =
            pathLayer(
                "Compound",
                frame:
                    CoverRect(),
                contours: [
                    contour(0),
                    contour(10)
                ],
                closures: [
                    true,
                    false
                ]
            )

        let after =
            pathLayer(
                "After",
                frame:
                    CoverRect(),
                contours: [
                    contour(40)
                ],
                closures: [
                    true
                ]
            )

        let source =
            makeProject(
                [
                    before,
                    compound,
                    after
                ]
            )

        let mutation =
            try XCTUnwrap(
                CoverEditorEngine
                    .separatingVectorPathLayer(
                        in:
                            source,
                        layerID:
                            compound.id
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
            mutation.project.layers[1].id,
            mutation.layers[0].id
        )

        XCTAssertEqual(
            mutation.project.layers[2].id,
            mutation.layers[1].id
        )

        XCTAssertEqual(
            mutation.project.layers[3].id,
            after.id
        )
    }

    func testCombineRejectsNonPathAndInsufficientSelections() {
        let destination =
            pathLayer(
                "Destination",
                frame:
                    CoverRect(),
                contours: [
                    contour(0)
                ],
                closures: [
                    true
                ]
            )

        var shape =
            CoverLayer(
                kind: .shape,
                name: "Shape"
            )

        shape.frame =
            CoverRect()

        let source =
            makeProject(
                [
                    destination,
                    shape
                ]
            )

        XCTAssertNil(
            CoverEditorEngine
                .combinedVectorPathLayer(
                    project:
                        source,
                    ids:
                        Set(
                            [
                                destination.id,
                                shape.id
                            ]
                        ),
                    primaryID:
                        destination.id
                )
        )

        XCTAssertNil(
            CoverEditorEngine
                .combinedVectorPathLayer(
                    project:
                        source,
                    ids:
                        Set(
                            [
                                destination.id
                            ]
                        ),
                    primaryID:
                        destination.id
                )
        )
    }

    func testCombineRejectsSkewedOperand() {
        let destination =
            pathLayer(
                "Destination",
                frame:
                    CoverRect(),
                contours: [
                    contour(0)
                ],
                closures: [
                    true
                ]
            )

        var skewed =
            pathLayer(
                "Skewed",
                frame:
                    CoverRect(
                        x: 0.2,
                        y: 0.2,
                        width: 0.4,
                        height: 0.4
                    ),
                contours: [
                    contour(10)
                ],
                closures: [
                    false
                ]
            )

        skewed.skewX = 0.2

        let source =
            makeProject(
                [
                    destination,
                    skewed
                ]
            )

        XCTAssertNil(
            CoverEditorEngine
                .combinedVectorPathLayer(
                    project:
                        source,
                    ids:
                        Set(
                            [
                                destination.id,
                                skewed.id
                            ]
                        ),
                    primaryID:
                        destination.id
                )
        )
    }

    func testCombinePreservesProjectLayerContourAndClosureOrder() throws {
        let first =
            pathLayer(
                "First",
                frame:
                    CoverRect(),
                contours: [
                    contour(0)
                ],
                closures: [
                    true
                ]
            )

        let second =
            pathLayer(
                "Second",
                frame:
                    CoverRect(),
                contours: [
                    contour(10),
                    contour(20)
                ],
                closures: [
                    false,
                    true
                ]
            )

        let source =
            makeProject(
                [
                    first,
                    second
                ]
            )

        let combined =
            try XCTUnwrap(
                CoverEditorEngine
                    .combinedVectorPathLayer(
                        project:
                            source,
                        ids:
                            Set(
                                [
                                    first.id,
                                    second.id
                                ]
                            ),
                        primaryID:
                            first.id
                    )
            )

        let contours =
            try XCTUnwrap(
                combined.pathContours
            )

        XCTAssertEqual(
            contours.count,
            3
        )

        XCTAssertEqual(
            try XCTUnwrap(
                contours[0].first
            ).x,
            0,
            accuracy:
                0.000001
        )

        XCTAssertEqual(
            try XCTUnwrap(
                contours[1].first
            ).x,
            10,
            accuracy:
                0.000001
        )

        XCTAssertEqual(
            try XCTUnwrap(
                contours[2].first
            ).x,
            20,
            accuracy:
                0.000001
        )

        XCTAssertEqual(
            combined.pathContourClosed,
            [
                true,
                false,
                true
            ]
        )
    }

    func testCombinePreservesBezierTopologyAndHandles() throws {
        let destination =
            pathLayer(
                "Destination",
                frame:
                    CoverRect(),
                contours: [
                    contour(0)
                ],
                closures: [
                    true
                ]
            )

        let sourceLayer =
            pathLayer(
                "Source",
                frame:
                    CoverRect(),
                contours: [
                    contour(10)
                ],
                closures: [
                    false
                ]
            )

        let project =
            makeProject(
                [
                    destination,
                    sourceLayer
                ]
            )

        let combined =
            try XCTUnwrap(
                CoverEditorEngine
                    .combinedVectorPathLayer(
                        project:
                            project,
                        ids:
                            Set(
                                [
                                    destination.id,
                                    sourceLayer.id
                                ]
                            ),
                        primaryID:
                            destination.id
                    )
            )

        let second =
            try XCTUnwrap(
                combined.pathContours?[1]
            )

        XCTAssertEqual(
            second[0].anchorType,
            .corner
        )

        XCTAssertEqual(
            second[1].anchorType,
            .smooth
        )

        XCTAssertEqual(
            second[2].anchorType,
            .symmetric
        )

        XCTAssertNotNil(
            second[0].controlOutX
        )

        XCTAssertNotNil(
            second[1].controlInX
        )

        XCTAssertNotNil(
            second[1].controlOutX
        )

        XCTAssertNotNil(
            second[2].controlInX
        )
    }

    func testCombinePreservesCanvasGeometryAcrossDifferentFrames() throws {
        let destination =
            pathLayer(
                "Destination",
                frame:
                    CoverRect(
                        x: 0.1,
                        y: 0.2,
                        width: 0.4,
                        height: 0.5
                    ),
                contours: [
                    [
                        point(0, 0),
                        point(1, 0),
                        point(1, 1)
                    ]
                ],
                closures: [
                    true
                ]
            )

        let sourceLayer =
            pathLayer(
                "Source",
                frame:
                    CoverRect(
                        x: 0.5,
                        y: 0.4,
                        width: 0.2,
                        height: 0.3
                    ),
                contours: [
                    [
                        point(0, 0),
                        point(1, 0),
                        point(1, 1)
                    ]
                ],
                closures: [
                    false
                ]
            )

        let project =
            makeProject(
                [
                    destination,
                    sourceLayer
                ]
            )

        let combined =
            try XCTUnwrap(
                CoverEditorEngine
                    .combinedVectorPathLayer(
                        project:
                            project,
                        ids:
                            Set(
                                [
                                    destination.id,
                                    sourceLayer.id
                                ]
                            ),
                        primaryID:
                            destination.id
                    )
            )

        let mapped =
            try XCTUnwrap(
                combined
                    .pathContours?[1]
                    .first
            )

        XCTAssertEqual(
            mapped.x,
            1.0,
            accuracy:
                0.000001
        )

        XCTAssertEqual(
            mapped.y,
            0.4,
            accuracy:
                0.000001
        )
    }

    func testCombineBakesRotationIntoEditableGeometry() throws {
        let destination =
            pathLayer(
                "Destination",
                frame:
                    CoverRect(
                        x: 0.1,
                        y: 0.1,
                        width: 0.4,
                        height: 0.4
                    ),
                contours: [
                    [
                        point(0, 0),
                        point(1, 0),
                        point(1, 1)
                    ]
                ],
                closures: [
                    true
                ]
            )

        var rotated =
            pathLayer(
                "Rotated",
                frame:
                    CoverRect(
                        x: 0.6,
                        y: 0.2,
                        width: 0.2,
                        height: 0.2
                    ),
                contours: [
                    [
                        point(0, 0),
                        point(1, 0),
                        point(1, 1)
                    ]
                ],
                closures: [
                    false
                ]
            )

        rotated.rotation = 180

        let project =
            makeProject(
                [
                    destination,
                    rotated
                ]
            )

        let combined =
            try XCTUnwrap(
                CoverEditorEngine
                    .combinedVectorPathLayer(
                        project:
                            project,
                        ids:
                            Set(
                                [
                                    destination.id,
                                    rotated.id
                                ]
                            ),
                        primaryID:
                            destination.id
                    )
            )

        let mapped =
            try XCTUnwrap(
                combined
                    .pathContours?[1]
                    .first
            )

        XCTAssertEqual(
            mapped.x,
            1.75,
            accuracy:
                0.000001
        )

        XCTAssertEqual(
            mapped.y,
            0.75,
            accuracy:
                0.000001
        )

        XCTAssertEqual(
            combined.rotation,
            0,
            accuracy:
                0.000001
        )
    }

    func testCombineBakesFlipIntoEditableGeometry() throws {
        let destination =
            pathLayer(
                "Destination",
                frame:
                    CoverRect(),
                contours: [
                    [
                        point(0, 0),
                        point(1, 0),
                        point(1, 1)
                    ]
                ],
                closures: [
                    true
                ]
            )

        var flipped =
            pathLayer(
                "Flipped",
                frame:
                    CoverRect(),
                contours: [
                    [
                        point(0, 0),
                        point(1, 0),
                        point(1, 1)
                    ]
                ],
                closures: [
                    false
                ]
            )

        flipped.flipHorizontal = true

        let project =
            makeProject(
                [
                    destination,
                    flipped
                ]
            )

        let combined =
            try XCTUnwrap(
                CoverEditorEngine
                    .combinedVectorPathLayer(
                        project:
                            project,
                        ids:
                            Set(
                                [
                                    destination.id,
                                    flipped.id
                                ]
                            ),
                        primaryID:
                            destination.id
                    )
            )

        let mapped =
            try XCTUnwrap(
                combined
                    .pathContours?[1]
                    .first
            )

        XCTAssertEqual(
            mapped.x,
            1,
            accuracy:
                0.000001
        )

        XCTAssertFalse(
            combined.flipHorizontal
        )
    }

    func testCombineUsesDestinationStyleIdentityAndFrame() throws {
        var destination =
            pathLayer(
                "Destination",
                frame:
                    CoverRect(
                        x: 0.1,
                        y: 0.1,
                        width: 0.8,
                        height: 0.8
                    ),
                contours: [
                    contour(0)
                ],
                closures: [
                    true
                ]
            )

        destination.fillHex = "#112233"
        destination.strokeHex = "#445566"
        destination.strokeWidth = 9
        destination.opacity = 0.37
        destination.blendMode = .screen

        let sourceLayer =
            pathLayer(
                "Source",
                frame:
                    CoverRect(),
                contours: [
                    contour(10)
                ],
                closures: [
                    false
                ]
            )

        let project =
            makeProject(
                [
                    destination,
                    sourceLayer
                ]
            )

        let combined =
            try XCTUnwrap(
                CoverEditorEngine
                    .combinedVectorPathLayer(
                        project:
                            project,
                        ids:
                            Set(
                                [
                                    destination.id,
                                    sourceLayer.id
                                ]
                            ),
                        primaryID:
                            destination.id
                    )
            )

        XCTAssertEqual(
            combined.id,
            destination.id
        )

        XCTAssertEqual(
            combined.name,
            destination.name
        )

        XCTAssertEqual(
            combined.frame,
            destination.frame
        )

        XCTAssertEqual(
            combined.fillHex,
            destination.fillHex
        )

        XCTAssertEqual(
            combined.strokeHex,
            destination.strokeHex
        )

        XCTAssertEqual(
            combined.strokeWidth,
            destination.strokeWidth
        )

        XCTAssertEqual(
            combined.opacity,
            destination.opacity
        )

        XCTAssertEqual(
            combined.blendMode,
            destination.blendMode
        )
    }

    func testCombineSynchronizesPathMirrors() throws {
        let destination =
            pathLayer(
                "Destination",
                frame:
                    CoverRect(),
                contours: [
                    contour(0)
                ],
                closures: [
                    false
                ]
            )

        let sourceLayer =
            pathLayer(
                "Source",
                frame:
                    CoverRect(),
                contours: [
                    contour(10)
                ],
                closures: [
                    true
                ]
            )

        let project =
            makeProject(
                [
                    destination,
                    sourceLayer
                ]
            )

        let combined =
            try XCTUnwrap(
                CoverEditorEngine
                    .combinedVectorPathLayer(
                        project:
                            project,
                        ids:
                            Set(
                                [
                                    destination.id,
                                    sourceLayer.id
                                ]
                            ),
                        primaryID:
                            destination.id
                    )
            )

        XCTAssertEqual(
            combined.pathPoints,
            combined
                .pathContours?
                .first
        )

        XCTAssertEqual(
            combined.pathClosed,
            false
        )

        XCTAssertEqual(
            combined.pathContourClosed,
            [
                false,
                true
            ]
        )
    }

    func testCombineProjectMutationRemovesOnlyExplicitSources() throws {
        let untouchedBefore =
            pathLayer(
                "Untouched Before",
                frame:
                    CoverRect(),
                contours: [
                    contour(30)
                ],
                closures: [
                    true
                ]
            )

        let sourceLayer =
            pathLayer(
                "Source",
                frame:
                    CoverRect(),
                contours: [
                    contour(10)
                ],
                closures: [
                    false
                ]
            )

        let destination =
            pathLayer(
                "Destination",
                frame:
                    CoverRect(),
                contours: [
                    contour(0)
                ],
                closures: [
                    true
                ]
            )

        let untouchedAfter =
            pathLayer(
                "Untouched After",
                frame:
                    CoverRect(),
                contours: [
                    contour(40)
                ],
                closures: [
                    false
                ]
            )

        let project =
            makeProject(
                [
                    untouchedBefore,
                    sourceLayer,
                    destination,
                    untouchedAfter
                ]
            )

        let mutation =
            try XCTUnwrap(
                CoverEditorEngine
                    .combiningVectorPathLayers(
                        in:
                            project,
                        ids:
                            Set(
                                [
                                    sourceLayer.id,
                                    destination.id
                                ]
                            ),
                        primaryID:
                            destination.id
                    )
            )

        XCTAssertEqual(
            mutation.project.layers.count,
            3
        )

        XCTAssertEqual(
            mutation.project.layers[0].id,
            untouchedBefore.id
        )

        XCTAssertEqual(
            mutation.project.layers[1].id,
            destination.id
        )

        XCTAssertEqual(
            mutation.project.layers[2].id,
            untouchedAfter.id
        )

        XCTAssertFalse(
            mutation.project.layers.contains {
                $0.id == sourceLayer.id
            }
        )
    }

    func testCombineUsesOriginalProjectLayerOrderEvenWhenPrimaryIsLater() throws {
        let first =
            pathLayer(
                "First",
                frame:
                    CoverRect(),
                contours: [
                    contour(10)
                ],
                closures: [
                    false
                ]
            )

        let primary =
            pathLayer(
                "Primary",
                frame:
                    CoverRect(),
                contours: [
                    contour(0)
                ],
                closures: [
                    true
                ]
            )

        let project =
            makeProject(
                [
                    first,
                    primary
                ]
            )

        let combined =
            try XCTUnwrap(
                CoverEditorEngine
                    .combinedVectorPathLayer(
                        project:
                            project,
                        ids:
                            Set(
                                [
                                    first.id,
                                    primary.id
                                ]
                            ),
                        primaryID:
                            primary.id
                    )
            )

        let firstCombinedPoint =
            try XCTUnwrap(
                combined
                    .pathContours?[0]
                    .first
            )

        let secondCombinedPoint =
            try XCTUnwrap(
                combined
                    .pathContours?[1]
                    .first
            )

        XCTAssertEqual(
            firstCombinedPoint.x,
            10,
            accuracy:
                0.000001
        )

        XCTAssertEqual(
            secondCombinedPoint.x,
            0,
            accuracy:
                0.000001
        )

        XCTAssertEqual(
            combined.id,
            primary.id
        )
    }

    func testCombineResultPersistsThroughCodable() throws {
        let destination =
            pathLayer(
                "Destination",
                frame:
                    CoverRect(),
                contours: [
                    contour(0)
                ],
                closures: [
                    true
                ]
            )

        let sourceLayer =
            pathLayer(
                "Source",
                frame:
                    CoverRect(),
                contours: [
                    contour(10)
                ],
                closures: [
                    false
                ]
            )

        let project =
            makeProject(
                [
                    destination,
                    sourceLayer
                ]
            )

        let combined =
            try XCTUnwrap(
                CoverEditorEngine
                    .combinedVectorPathLayer(
                        project:
                            project,
                        ids:
                            Set(
                                [
                                    destination.id,
                                    sourceLayer.id
                                ]
                            ),
                        primaryID:
                            destination.id
                    )
            )

        let reopened =
            try JSONDecoder()
                .decode(
                    CoverLayer.self,
                    from:
                        JSONEncoder()
                            .encode(
                                combined
                            )
                )

        XCTAssertEqual(
            reopened,
            combined
        )
    }
}
