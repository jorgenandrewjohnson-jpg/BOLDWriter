import XCTest
@testable import BOLDWriter

final class CoverSelectedPathTransformTests:
    XCTestCase
{
    private func point(
        _ x: Double,
        _ y: Double,
        controlIn: (
            Double,
            Double
        )? = nil,
        controlOut: (
            Double,
            Double
        )? = nil,
        type: CoverPathAnchorType? = nil
    ) -> CoverPathPoint {
        CoverPathPoint(
            x:
                x,
            y:
                y,
            controlInX:
                controlIn?.0,
            controlInY:
                controlIn?.1,
            controlOutX:
                controlOut?.0,
            controlOutY:
                controlOut?.1,
            anchorType:
                type
        )
    }

    private func layer() -> CoverLayer {
        var layer =
            CoverLayer(
                kind:
                    .path,
                name:
                    "Transform Path",
                frame:
                    CoverRect(
                        x: 0.15,
                        y: 0.2,
                        width: 0.6,
                        height: 0.5
                    )
            )

        let first = [
            point(
                0.2,
                0.2,
                controlIn:
                    (
                        0.1,
                        0.2
                    ),
                controlOut:
                    (
                        0.3,
                        0.2
                    ),
                type:
                    .smooth
            ),
            point(
                0.8,
                0.2,
                type:
                    .corner
            ),
            point(
                0.8,
                0.8,
                type:
                    .symmetric
            ),
            point(
                0.2,
                0.8
            )
        ]

        let second = [
            point(
                0.35,
                0.35
            ),
            point(
                0.65,
                0.35
            ),
            point(
                0.5,
                0.65
            )
        ]

        layer.pathPoints =
            first

        layer.pathContours = [
            first,
            second
        ]

        layer.pathClosed =
            true

        layer.pathContourClosed = [
            true,
            false
        ]

        layer.fillRule =
            .nonZero

        layer.strokeCap =
            .round

        layer.strokeJoin =
            .bevel

        layer.strokeMiterLimit =
            7

        layer.strokeDashPattern = [
            8,
            4
        ]

        layer.strokeDashPhase =
            2

        layer.rotation =
            13

        layer.flipHorizontal =
            true

        layer.flipVertical =
            false

        return layer
    }

    private func anchor(
        _ contour: Int,
        _ point: Int
    ) -> CoverVectorAnchorIndex {
        CoverVectorAnchorIndex(
            contourIndex:
                contour,
            pointIndex:
                point
        )
    }

    func testSelectionBoundsForOneAnchor() throws {
        let bounds =
            try XCTUnwrap(
                CoverEditorEngine
                    .selectedVectorGeometryBounds(
                        in:
                            layer(),
                        selections:
                            [
                                anchor(
                                    0,
                                    2
                                )
                            ]
                    )
            )

        XCTAssertEqual(
            bounds.minX,
            0.8,
            accuracy:
                0.000001
        )

        XCTAssertEqual(
            bounds.maxX,
            0.8,
            accuracy:
                0.000001
        )

        XCTAssertEqual(
            bounds.minY,
            0.8,
            accuracy:
                0.000001
        )

        XCTAssertEqual(
            bounds.maxY,
            0.8,
            accuracy:
                0.000001
        )

        XCTAssertEqual(
            bounds.width,
            0,
            accuracy:
                0.000001
        )

        XCTAssertEqual(
            bounds.height,
            0,
            accuracy:
                0.000001
        )
    }

    func testSelectionBoundsAcrossContours() throws {
        let bounds =
            try XCTUnwrap(
                CoverEditorEngine
                    .selectedVectorGeometryBounds(
                        in:
                            layer(),
                        selections:
                            [
                                anchor(
                                    0,
                                    0
                                ),
                                anchor(
                                    1,
                                    1
                                )
                            ]
                    )
            )

        XCTAssertEqual(
            bounds.minX,
            0.2,
            accuracy:
                0.000001
        )

        XCTAssertEqual(
            bounds.maxX,
            0.65,
            accuracy:
                0.000001
        )

        XCTAssertEqual(
            bounds.minY,
            0.2,
            accuracy:
                0.000001
        )

        XCTAssertEqual(
            bounds.maxY,
            0.35,
            accuracy:
                0.000001
        )

        XCTAssertEqual(
            bounds.centerX,
            0.425,
            accuracy:
                0.000001
        )

        XCTAssertEqual(
            bounds.centerY,
            0.275,
            accuracy:
                0.000001
        )
    }

    func testSelectionBoundsRejectsInvalidIndex() {
        XCTAssertNil(
            CoverEditorEngine
                .selectedVectorGeometryBounds(
                    in:
                        layer(),
                    selections:
                        [
                            anchor(
                                9,
                                9
                            )
                        ]
                )
        )
    }

    func testContourSelectionReturnsEveryAnchor() {
        let selected =
            CoverEditorEngine
                .vectorContourAnchorSelection(
                    in:
                        layer(),
                    contourIndex:
                        1
                )

        XCTAssertEqual(
            selected,
            Set(
                [
                    anchor(
                        1,
                        0
                    ),
                    anchor(
                        1,
                        1
                    ),
                    anchor(
                        1,
                        2
                    )
                ]
            )
        )
    }

    func testContourSelectionRejectsInvalidContour() {
        XCTAssertTrue(
            CoverEditorEngine
                .vectorContourAnchorSelection(
                    in:
                        layer(),
                    contourIndex:
                        99
                )
                .isEmpty
        )
    }

    func testExistingTranslationCanMoveOutsideUnitBox() {
        let result =
            CoverEditorEngine
                .translatingVectorAnchors(
                    in:
                        layer(),
                    selections:
                        [
                            anchor(
                                0,
                                1
                            )
                        ],
                    deltaX:
                        0.5,
                    deltaY:
                        0
                )

        let contours =
            CoverEditorEngine
                .vectorContours(
                    for:
                        result
                )

        XCTAssertEqual(
            contours[0][1].x,
            1.3,
            accuracy:
                0.000001
        )
    }

    func testTranslationMovesHandlesWithAnchor() throws {
        let result =
            CoverEditorEngine
                .translatingVectorAnchors(
                    in:
                        layer(),
                    selections:
                        [
                            anchor(
                                0,
                                0
                            )
                        ],
                    deltaX:
                        0.2,
                    deltaY:
                        0.15
                )

        let point =
            CoverEditorEngine
                .vectorContours(
                    for:
                        result
                )[0][0]

        XCTAssertEqual(
            point.x,
            0.4,
            accuracy:
                0.000001
        )

        XCTAssertEqual(
            point.y,
            0.35,
            accuracy:
                0.000001
        )

        XCTAssertEqual(
            try XCTUnwrap(
                point.controlInX
            ),
            0.3,
            accuracy:
                0.000001
        )

        XCTAssertEqual(
            try XCTUnwrap(
                point.controlInY
            ),
            0.35,
            accuracy:
                0.000001
        )

        XCTAssertEqual(
            try XCTUnwrap(
                point.controlOutX
            ),
            0.5,
            accuracy:
                0.000001
        )

        XCTAssertEqual(
            try XCTUnwrap(
                point.controlOutY
            ),
            0.35,
            accuracy:
                0.000001
        )
    }

    func testTranslationRejectsNonfiniteDeltaSafely() {
        let source =
            layer()

        let result =
            CoverEditorEngine
                .translatingVectorAnchors(
                    in:
                        source,
                    selections:
                        [
                            anchor(
                                0,
                                0
                            )
                        ],
                    deltaX:
                        .nan,
                    deltaY:
                        0
                )

        XCTAssertEqual(
            result,
            source
        )
    }

    func testScaleSelectedAnchorAroundPivot() throws {
        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .scalingVectorAnchors(
                        in:
                            layer(),
                        selections:
                            [
                                anchor(
                                    0,
                                    0
                                )
                            ],
                        scaleX:
                            2,
                        scaleY:
                            0.5,
                        pivotX:
                            0.5,
                        pivotY:
                            0.5
                    )
            )

        let transformed =
            CoverEditorEngine
                .vectorContours(
                    for:
                        result
                )[0][0]

        XCTAssertEqual(
            transformed.x,
            -0.1,
            accuracy:
                0.000001
        )

        XCTAssertEqual(
            transformed.y,
            0.35,
            accuracy:
                0.000001
        )
    }

    func testScaleTransformsBezierHandlesAffinely() throws {
        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .scalingVectorAnchors(
                        in:
                            layer(),
                        selections:
                            [
                                anchor(
                                    0,
                                    0
                                )
                            ],
                        scaleX:
                            2,
                        scaleY:
                            2,
                        pivotX:
                            0,
                        pivotY:
                            0
                    )
            )

        let transformed =
            CoverEditorEngine
                .vectorContours(
                    for:
                        result
                )[0][0]

        XCTAssertEqual(
            try XCTUnwrap(
                transformed.controlInX
            ),
            0.2,
            accuracy:
                0.000001
        )

        XCTAssertEqual(
            try XCTUnwrap(
                transformed.controlInY
            ),
            0.4,
            accuracy:
                0.000001
        )

        XCTAssertEqual(
            try XCTUnwrap(
                transformed.controlOutX
            ),
            0.6,
            accuracy:
                0.000001
        )

        XCTAssertEqual(
            try XCTUnwrap(
                transformed.controlOutY
            ),
            0.4,
            accuracy:
                0.000001
        )
    }

    func testScaleLeavesUnselectedAnchorsExactlyUnchanged() throws {
        let source =
            layer()

        let original =
            CoverEditorEngine
                .vectorContours(
                    for:
                        source
                )

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .scalingVectorAnchors(
                        in:
                            source,
                        selections:
                            [
                                anchor(
                                    0,
                                    0
                                )
                            ],
                        scaleX:
                            1.5,
                        scaleY:
                            1.5,
                        pivotX:
                            0.5,
                        pivotY:
                            0.5
                    )
            )

        let transformed =
            CoverEditorEngine
                .vectorContours(
                    for:
                        result
                )

        XCTAssertEqual(
            transformed[0][1],
            original[0][1]
        )

        XCTAssertEqual(
            transformed[0][2],
            original[0][2]
        )

        XCTAssertEqual(
            transformed[0][3],
            original[0][3]
        )

        XCTAssertEqual(
            transformed[1],
            original[1]
        )
    }

    func testScaleCanSpanMultipleContours() throws {
        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .scalingVectorAnchors(
                        in:
                            layer(),
                        selections:
                            [
                                anchor(
                                    0,
                                    0
                                ),
                                anchor(
                                    1,
                                    0
                                )
                            ],
                        scaleX:
                            2,
                        scaleY:
                            1,
                        pivotX:
                            0.5,
                        pivotY:
                            0.5
                    )
            )

        let contours =
            CoverEditorEngine
                .vectorContours(
                    for:
                        result
                )

        XCTAssertEqual(
            contours[0][0].x,
            -0.1,
            accuracy:
                0.000001
        )

        XCTAssertEqual(
            contours[1][0].x,
            0.2,
            accuracy:
                0.000001
        )
    }

    func testScalePreservesAnchorTypes() throws {
        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .scalingVectorAnchors(
                        in:
                            layer(),
                        selections:
                            [
                                anchor(
                                    0,
                                    0
                                ),
                                anchor(
                                    0,
                                    1
                                ),
                                anchor(
                                    0,
                                    2
                                )
                            ],
                        scaleX:
                            1.2,
                        scaleY:
                            0.8,
                        pivotX:
                            0.5,
                        pivotY:
                            0.5
                    )
            )

        let contours =
            CoverEditorEngine
                .vectorContours(
                    for:
                        result
                )

        XCTAssertEqual(
            contours[0][0].anchorType,
            .smooth
        )

        XCTAssertEqual(
            contours[0][1].anchorType,
            .corner
        )

        XCTAssertEqual(
            contours[0][2].anchorType,
            .symmetric
        )
    }

    func testRotateSelectedAnchorNinetyDegrees() throws {
        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .rotatingVectorAnchors(
                        in:
                            layer(),
                        selections:
                            [
                                anchor(
                                    0,
                                    1
                                )
                            ],
                        degrees:
                            90,
                        pivotX:
                            0.5,
                        pivotY:
                            0.5
                    )
            )

        let point =
            CoverEditorEngine
                .vectorContours(
                    for:
                        result
                )[0][1]

        XCTAssertEqual(
            point.x,
            0.8,
            accuracy:
                0.000001
        )

        XCTAssertEqual(
            point.y,
            0.8,
            accuracy:
                0.000001
        )
    }

    func testRotateTransformsBezierHandles() throws {
        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .rotatingVectorAnchors(
                        in:
                            layer(),
                        selections:
                            [
                                anchor(
                                    0,
                                    0
                                )
                            ],
                        degrees:
                            90,
                        pivotX:
                            0.2,
                        pivotY:
                            0.2
                    )
            )

        let point =
            CoverEditorEngine
                .vectorContours(
                    for:
                        result
                )[0][0]

        XCTAssertEqual(
            try XCTUnwrap(
                point.controlInX
            ),
            0.2,
            accuracy:
                0.000001
        )

        XCTAssertEqual(
            try XCTUnwrap(
                point.controlInY
            ),
            0.1,
            accuracy:
                0.000001
        )

        XCTAssertEqual(
            try XCTUnwrap(
                point.controlOutX
            ),
            0.2,
            accuracy:
                0.000001
        )

        XCTAssertEqual(
            try XCTUnwrap(
                point.controlOutY
            ),
            0.3,
            accuracy:
                0.000001
        )
    }

    func testHorizontalFlipSelectedAnchor() throws {
        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .flippingVectorAnchors(
                        in:
                            layer(),
                        selections:
                            [
                                anchor(
                                    0,
                                    0
                                )
                            ],
                        horizontal:
                            true,
                        pivotX:
                            0.5,
                        pivotY:
                            0.5
                    )
            )

        let point =
            CoverEditorEngine
                .vectorContours(
                    for:
                        result
                )[0][0]

        XCTAssertEqual(
            point.x,
            0.8,
            accuracy:
                0.000001
        )

        XCTAssertEqual(
            point.y,
            0.2,
            accuracy:
                0.000001
        )
    }

    func testVerticalFlipSelectedAnchor() throws {
        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .flippingVectorAnchors(
                        in:
                            layer(),
                        selections:
                            [
                                anchor(
                                    0,
                                    0
                                )
                            ],
                        horizontal:
                            false,
                        pivotX:
                            0.5,
                        pivotY:
                            0.5
                    )
            )

        let point =
            CoverEditorEngine
                .vectorContours(
                    for:
                        result
                )[0][0]

        XCTAssertEqual(
            point.x,
            0.2,
            accuracy:
                0.000001
        )

        XCTAssertEqual(
            point.y,
            0.8,
            accuracy:
                0.000001
        )
    }

    func testNegativeScaleSupportsReflection() throws {
        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .scalingVectorAnchors(
                        in:
                            layer(),
                        selections:
                            [
                                anchor(
                                    0,
                                    0
                                )
                            ],
                        scaleX:
                            -1,
                        scaleY:
                            1,
                        pivotX:
                            0.5,
                        pivotY:
                            0.5
                    )
            )

        XCTAssertEqual(
            CoverEditorEngine
                .vectorContours(
                    for:
                        result
                )[0][0]
                .x,
            0.8,
            accuracy:
                0.000001
        )
    }

    func testZeroWidthSelectionScalesSafely() throws {
        var source =
            layer()

        var contours =
            CoverEditorEngine
                .vectorContours(
                    for:
                        source
                )

        contours[0][1].x =
            0.5

        contours[0][2].x =
            0.5

        source.pathContours =
            contours

        source.pathPoints =
            contours.first

        let selections:
            Set<CoverVectorAnchorIndex> = [
                anchor(
                    0,
                    1
                ),
                anchor(
                    0,
                    2
                )
            ]

        let bounds =
            try XCTUnwrap(
                CoverEditorEngine
                    .selectedVectorGeometryBounds(
                        in:
                            source,
                        selections:
                            selections
                    )
            )

        XCTAssertEqual(
            bounds.width,
            0,
            accuracy:
                0.000001
        )

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .scalingVectorAnchors(
                        in:
                            source,
                        selections:
                            selections,
                        scaleX:
                            2,
                        scaleY:
                            0.5,
                        pivotX:
                            bounds.centerX,
                        pivotY:
                            bounds.centerY
                    )
            )

        let output =
            CoverEditorEngine
                .vectorContours(
                    for:
                        result
                )

        XCTAssertEqual(
            output[0][1].x,
            0.5,
            accuracy:
                0.000001
        )

        XCTAssertEqual(
            output[0][2].x,
            0.5,
            accuracy:
                0.000001
        )
    }

    func testTransformContourZeroKeepsPathPointsMirrorSynchronized() throws {
        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .rotatingVectorAnchors(
                        in:
                            layer(),
                        selections:
                            [
                                anchor(
                                    0,
                                    0
                                ),
                                anchor(
                                    0,
                                    1
                                )
                            ],
                        degrees:
                            37,
                        pivotX:
                            0.5,
                        pivotY:
                            0.5
                    )
            )

        let contours =
            try XCTUnwrap(
                result.pathContours
            )

        XCTAssertEqual(
            result.pathPoints,
            contours.first
        )
    }

    func testTransformPreservesLayerMetadataAndClosureState() throws {
        let source =
            layer()

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .scalingVectorAnchors(
                        in:
                            source,
                        selections:
                            [
                                anchor(
                                    0,
                                    0
                                ),
                                anchor(
                                    1,
                                    0
                                )
                            ],
                        scaleX:
                            1.1,
                        scaleY:
                            0.9,
                        pivotX:
                            0.5,
                        pivotY:
                            0.5
                    )
            )

        XCTAssertEqual(
            result.frame,
            source.frame
        )

        XCTAssertEqual(
            result.rotation,
            source.rotation
        )

        XCTAssertEqual(
            result.flipHorizontal,
            source.flipHorizontal
        )

        XCTAssertEqual(
            result.flipVertical,
            source.flipVertical
        )

        XCTAssertEqual(
            result.pathClosed,
            source.pathClosed
        )

        XCTAssertEqual(
            result.pathContourClosed,
            source.pathContourClosed
        )

        XCTAssertEqual(
            result.fillRule,
            source.fillRule
        )

        XCTAssertEqual(
            result.strokeCap,
            source.strokeCap
        )

        XCTAssertEqual(
            result.strokeJoin,
            source.strokeJoin
        )

        XCTAssertEqual(
            result.strokeMiterLimit,
            source.strokeMiterLimit
        )

        XCTAssertEqual(
            result.strokeDashPattern,
            source.strokeDashPattern
        )

        XCTAssertEqual(
            result.strokeDashPhase,
            source.strokeDashPhase
        )
    }

    func testRotationLeavesLayerRotationUnchanged() throws {
        let source =
            layer()

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .rotatingVectorAnchors(
                        in:
                            source,
                        selections:
                            [
                                anchor(
                                    0,
                                    0
                                )
                            ],
                        degrees:
                            45,
                        pivotX:
                            0.5,
                        pivotY:
                            0.5
                    )
            )

        XCTAssertEqual(
            result.rotation,
            13
        )
    }

    func testFlipLeavesLayerFlipFlagsUnchanged() throws {
        let source =
            layer()

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .flippingVectorAnchors(
                        in:
                            source,
                        selections:
                            [
                                anchor(
                                    0,
                                    0
                                )
                            ],
                        horizontal:
                            true,
                        pivotX:
                            0.5,
                        pivotY:
                            0.5
                    )
            )

        XCTAssertEqual(
            result.flipHorizontal,
            source.flipHorizontal
        )

        XCTAssertEqual(
            result.flipVertical,
            source.flipVertical
        )
    }

    func testNonfiniteScaleIsRejected() {
        XCTAssertNil(
            CoverEditorEngine
                .scalingVectorAnchors(
                    in:
                        layer(),
                    selections:
                        [
                            anchor(
                                0,
                                0
                            )
                        ],
                    scaleX:
                        .nan,
                    scaleY:
                        1,
                    pivotX:
                        0.5,
                    pivotY:
                        0.5
                )
        )
    }

    func testNonfiniteRotationIsRejected() {
        XCTAssertNil(
            CoverEditorEngine
                .rotatingVectorAnchors(
                    in:
                        layer(),
                    selections:
                        [
                            anchor(
                                0,
                                0
                            )
                        ],
                    degrees:
                        .infinity,
                    pivotX:
                        0.5,
                    pivotY:
                        0.5
                )
        )
    }

    func testNonfinitePivotIsRejected() {
        XCTAssertNil(
            CoverEditorEngine
                .scalingVectorAnchors(
                    in:
                        layer(),
                    selections:
                        [
                            anchor(
                                0,
                                0
                            )
                        ],
                    scaleX:
                        1,
                    scaleY:
                        1,
                    pivotX:
                        .nan,
                    pivotY:
                        0.5
                )
        )
    }

    func testCompleteContourTransformsWithoutTouchingOtherContour() throws {
        let source =
            layer()

        let selections =
            CoverEditorEngine
                .vectorContourAnchorSelection(
                    in:
                        source,
                    contourIndex:
                        0
                )

        let original =
            CoverEditorEngine
                .vectorContours(
                    for:
                        source
                )

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .rotatingVectorAnchors(
                        in:
                            source,
                        selections:
                            selections,
                        degrees:
                            90,
                        pivotX:
                            0.5,
                        pivotY:
                            0.5
                    )
            )

        let transformed =
            CoverEditorEngine
                .vectorContours(
                    for:
                        result
                )

        XCTAssertNotEqual(
            transformed[0],
            original[0]
        )

        XCTAssertEqual(
            transformed[1],
            original[1]
        )
    }

    func testTwoCompleteContoursCanTransformTogether() throws {
        let source =
            layer()

        let first =
            CoverEditorEngine
                .vectorContourAnchorSelection(
                    in:
                        source,
                    contourIndex:
                        0
                )

        let second =
            CoverEditorEngine
                .vectorContourAnchorSelection(
                    in:
                        source,
                    contourIndex:
                        1
                )

        let selections =
            first.union(
                second
            )

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .scalingVectorAnchors(
                        in:
                            source,
                        selections:
                            selections,
                        scaleX:
                            0.75,
                        scaleY:
                            0.75,
                        pivotX:
                            0.5,
                        pivotY:
                            0.5
                    )
            )

        let original =
            CoverEditorEngine
                .vectorContours(
                    for:
                        source
                )

        let transformed =
            CoverEditorEngine
                .vectorContours(
                    for:
                        result
                )

        XCTAssertNotEqual(
            transformed[0],
            original[0]
        )

        XCTAssertNotEqual(
            transformed[1],
            original[1]
        )
    }
}
