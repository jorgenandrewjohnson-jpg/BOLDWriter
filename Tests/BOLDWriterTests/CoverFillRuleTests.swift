import XCTest
import AppKit
@testable import BOLDWriter

final class CoverFillRuleTests:
    XCTestCase
{
    private func square(
        minX: Double,
        minY: Double,
        maxX: Double,
        maxY: Double,
        reversed: Bool = false
    ) -> [CoverPathPoint] {
        let points = [
            CoverPathPoint(
                x: minX,
                y: minY
            ),
            CoverPathPoint(
                x: maxX,
                y: minY
            ),
            CoverPathPoint(
                x: maxX,
                y: maxY
            ),
            CoverPathPoint(
                x: minX,
                y: maxY
            )
        ]

        if reversed {
            return Array(
                points.reversed()
            )
        }

        return points
    }

    private func compoundLayer(
        fillRule: CoverFillRule? = nil,
        innerReversed: Bool = false
    ) -> CoverLayer {
        var layer =
            CoverLayer(
                kind:
                    .path,
                name:
                    "Compound",
                frame:
                    CoverRect()
            )

        let outer =
            square(
                minX:
                    0.1,
                minY:
                    0.1,
                maxX:
                    0.9,
                maxY:
                    0.9
            )

        let inner =
            square(
                minX:
                    0.3,
                minY:
                    0.3,
                maxX:
                    0.7,
                maxY:
                    0.7,
                reversed:
                    innerReversed
            )

        layer.pathPoints =
            outer

        layer.pathContours = [
            outer,
            inner
        ]

        layer.pathClosed =
            true

        layer.pathContourClosed = [
            true,
            true
        ]

        layer.fillRule =
            fillRule

        return layer
    }

    private func displayPath(
        _ layer: CoverLayer
    ) -> NSBezierPath {
        let contours =
            CoverEditorEngine
                .vectorContours(
                    for:
                        layer
                )

        let closures =
            CoverEditorEngine
                .vectorContourClosures(
                    for:
                        layer,
                    contourCount:
                        contours.count
                )

        let path =
            CoverEditorEngine
                .vectorCompoundPath(
                    contours:
                        contours,
                    in:
                        NSRect(
                            x: 0,
                            y: 0,
                            width: 100,
                            height: 100
                        ),
                    closures:
                        closures
                )

        CoverEditorEngine
            .configureVectorFillRule(
                path,
                layer:
                    layer
            )

        return path
    }

    private func project(
        layers: [CoverLayer]
    ) -> CoverProject {
        var project =
            CoverProject(
                width: 1,
                height: 1
            )

        project.canvasWidth =
            1

        project.canvasHeight =
            1

        project.dpi =
            100

        project.layers =
            layers

        return project
    }

    private func rasterTarget() -> CoverLayer {
        CoverLayer(
            kind:
                .paint,
            name:
                "Raster",
            frame:
                CoverRect()
        )
    }

    func testFillRuleCodableRoundTrip() throws {
        for rule in CoverFillRule.allCases {
            let encoded =
                try JSONEncoder()
                    .encode(
                        rule
                    )

            let decoded =
                try JSONDecoder()
                    .decode(
                        CoverFillRule.self,
                        from:
                            encoded
                    )

            XCTAssertEqual(
                decoded,
                rule
            )
        }
    }

    func testLegacyNilResolvesToEvenOdd() {
        let layer =
            compoundLayer()

        XCTAssertNil(
            layer.fillRule
        )

        XCTAssertEqual(
            CoverEditorEngine
                .vectorFillRule(
                    for:
                        layer
                ),
            .evenOdd
        )
    }

    func testExplicitFillRulesPersist() throws {
        for rule in CoverFillRule.allCases {
            var layer =
                compoundLayer()

            layer.fillRule =
                rule

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
                decoded.fillRule,
                rule
            )
        }
    }

    func testFillRuleChangeDoesNotMutateTopology() {
        var layer =
            compoundLayer()

        let points =
            layer.pathPoints

        let contours =
            layer.pathContours

        let closed =
            layer.pathClosed

        let closures =
            layer.pathContourClosed

        layer.fillRule =
            .nonZero

        XCTAssertEqual(
            layer.pathPoints,
            points
        )

        XCTAssertEqual(
            layer.pathContours,
            contours
        )

        XCTAssertEqual(
            layer.pathClosed,
            closed
        )

        XCTAssertEqual(
            layer.pathContourClosed,
            closures
        )
    }

    func testEvenOddSameDirectionCreatesHole() {
        let layer =
            compoundLayer(
                fillRule:
                    .evenOdd
            )

        let path =
            displayPath(
                layer
            )

        XCTAssertFalse(
            path.contains(
                NSPoint(
                    x: 50,
                    y: 50
                )
            )
        )

        XCTAssertTrue(
            path.contains(
                NSPoint(
                    x: 20,
                    y: 50
                )
            )
        )
    }

    func testNonZeroSameDirectionFillsCenter() {
        let layer =
            compoundLayer(
                fillRule:
                    .nonZero
            )

        let path =
            displayPath(
                layer
            )

        XCTAssertTrue(
            path.contains(
                NSPoint(
                    x: 50,
                    y: 50
                )
            )
        )
    }

    func testEvenOddOppositeDirectionStillCreatesHole() {
        let layer =
            compoundLayer(
                fillRule:
                    .evenOdd,
                innerReversed:
                    true
            )

        XCTAssertFalse(
            displayPath(
                layer
            )
            .contains(
                NSPoint(
                    x: 50,
                    y: 50
                )
            )
        )
    }

    func testNonZeroOppositeDirectionCreatesHole() {
        let layer =
            compoundLayer(
                fillRule:
                    .nonZero,
                innerReversed:
                    true
            )

        XCTAssertFalse(
            displayPath(
                layer
            )
            .contains(
                NSPoint(
                    x: 50,
                    y: 50
                )
            )
        )
    }

    func testThreeNestedContoursAlternateUnderEvenOdd() {
        var layer =
            compoundLayer(
                fillRule:
                    .evenOdd
            )

        let third =
            square(
                minX:
                    0.4,
                minY:
                    0.4,
                maxX:
                    0.6,
                maxY:
                    0.6
            )

        layer.pathContours =
            (
                layer.pathContours
                ?? []
            )
            + [
                third
            ]

        layer.pathContourClosed = [
            true,
            true,
            true
        ]

        XCTAssertTrue(
            displayPath(
                layer
            )
            .contains(
                NSPoint(
                    x: 50,
                    y: 50
                )
            )
        )
    }

    func testThreeSameDirectionContoursStayFilledUnderNonZero() {
        var layer =
            compoundLayer(
                fillRule:
                    .nonZero
            )

        let third =
            square(
                minX:
                    0.4,
                minY:
                    0.4,
                maxX:
                    0.6,
                maxY:
                    0.6
            )

        layer.pathContours =
            (
                layer.pathContours
                ?? []
            )
            + [
                third
            ]

        layer.pathContourClosed = [
            true,
            true,
            true
        ]

        XCTAssertTrue(
            displayPath(
                layer
            )
            .contains(
                NSPoint(
                    x: 50,
                    y: 50
                )
            )
        )
    }

    func testMakeSelectionHonorsEvenOdd() throws {
        let target =
            rasterTarget()

        let layer =
            compoundLayer(
                fillRule:
                    .evenOdd
            )

        let mask =
            try XCTUnwrap(
                CoverEditorEngine
                    .selectionFromVectorPath(
                        layer:
                            layer,
                        project:
                            project(
                                layers: [
                                    target,
                                    layer
                                ]
                            ),
                        targetLayer:
                            target,
                        width:
                            100,
                        height:
                            100,
                        antialias:
                            false
                    )
            )

        XCTAssertEqual(
            mask[
                50 * 100 + 50
            ],
            0
        )

        XCTAssertEqual(
            mask[
                50 * 100 + 20
            ],
            255
        )
    }

    func testMakeSelectionHonorsNonZero() throws {
        let target =
            rasterTarget()

        let layer =
            compoundLayer(
                fillRule:
                    .nonZero
            )

        let mask =
            try XCTUnwrap(
                CoverEditorEngine
                    .selectionFromVectorPath(
                        layer:
                            layer,
                        project:
                            project(
                                layers: [
                                    target,
                                    layer
                                ]
                            ),
                        targetLayer:
                            target,
                        width:
                            100,
                        height:
                            100,
                        antialias:
                            false
                    )
            )

        XCTAssertEqual(
            mask[
                50 * 100 + 50
            ],
            255
        )
    }

    func testSelectionToPathExplicitlyUsesEvenOdd() throws {
        let selection =
            Data(
                [
                    255, 255, 255, 255, 255,
                    255,   0,   0,   0, 255,
                    255,   0,   0,   0, 255,
                    255,   0,   0,   0, 255,
                    255, 255, 255, 255, 255
                ]
            )

        let layer =
            try XCTUnwrap(
                CoverEditorEngine
                    .vectorPathLayerFromSelection(
                        selection,
                        width:
                            5,
                        height:
                            5,
                        frame:
                            CoverRect()
                    )
            )

        XCTAssertEqual(
            layer.fillRule,
            .evenOdd
        )
    }

    func testReverseContourPreservesRuleAndChangesWindingContribution() throws {
        let original =
            compoundLayer(
                fillRule:
                    .nonZero
            )

        XCTAssertTrue(
            displayPath(
                original
            )
            .contains(
                NSPoint(
                    x: 50,
                    y: 50
                )
            )
        )

        let reversed =
            try XCTUnwrap(
                CoverEditorEngine
                    .reversingVectorContour(
                        in:
                            original,
                        contourIndex:
                            1
                    )
            )

        XCTAssertEqual(
            reversed.layer.fillRule,
            .nonZero
        )

        XCTAssertFalse(
            displayPath(
                reversed.layer
            )
            .contains(
                NSPoint(
                    x: 50,
                    y: 50
                )
            )
        )
    }

    func testDuplicateContourPreservesRule() throws {
        let layer =
            compoundLayer(
                fillRule:
                    .nonZero
            )

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .duplicatingVectorContour(
                        in:
                            layer,
                        contourIndex:
                            0
                    )
            )

        XCTAssertEqual(
            result.layer.fillRule,
            .nonZero
        )
    }

    func testContourOrderingPreservesRule() throws {
        let layer =
            compoundLayer(
                fillRule:
                    .nonZero
            )

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .orderingVectorContour(
                        in:
                            layer,
                        contourIndex:
                            0,
                        move:
                            .forward
                    )
            )

        XCTAssertEqual(
            result.layer.fillRule,
            .nonZero
        )
    }

    func testCombinePreservesPrimaryFillRule() throws {
        var primary =
            compoundLayer(
                fillRule:
                    .nonZero
            )

        primary.name =
            "Primary"

        var secondary =
            compoundLayer(
                fillRule:
                    .evenOdd
            )

        secondary.id =
            UUID()

        secondary.name =
            "Secondary"

        secondary.frame =
            CoverRect(
                x: 0.05,
                y: 0.05,
                width: 0.8,
                height: 0.8
            )

        let project =
            project(
                layers: [
                    primary,
                    secondary
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
                                    primary.id,
                                    secondary.id
                                ]
                            ),
                        primaryID:
                            primary.id
                    )
            )

        XCTAssertEqual(
            combined.fillRule,
            .nonZero
        )
    }

    func testSeparateCopiesSourceFillRule() throws {
        let source =
            compoundLayer(
                fillRule:
                    .nonZero
            )

        let mutation =
            try XCTUnwrap(
                CoverEditorEngine
                    .separatingVectorPathLayer(
                        in:
                            project(
                                layers: [
                                    source
                                ]
                            ),
                        layerID:
                            source.id
                    )
            )

        XCTAssertEqual(
            mutation.layers.count,
            2
        )

        XCTAssertTrue(
            mutation.layers.allSatisfy {
                $0.fillRule == .nonZero
            }
        )
    }

    func testVectorLayerContainsHonorsFillRule() {
        let evenOdd =
            compoundLayer(
                fillRule:
                    .evenOdd
            )

        let nonZero =
            compoundLayer(
                fillRule:
                    .nonZero
            )

        let evenOddProject =
            project(
                layers: [
                    evenOdd
                ]
            )

        let nonZeroProject =
            project(
                layers: [
                    nonZero
                ]
            )

        XCTAssertFalse(
            CoverEditorEngine
                .vectorLayerContains(
                    evenOdd,
                    project:
                        evenOddProject,
                    normalizedPoint:
                        CGPoint(
                            x: 0.5,
                            y: 0.5
                        )
                )
        )

        XCTAssertTrue(
            CoverEditorEngine
                .vectorLayerContains(
                    nonZero,
                    project:
                        nonZeroProject,
                    normalizedPoint:
                        CGPoint(
                            x: 0.5,
                            y: 0.5
                        )
                )
        )
    }
}
