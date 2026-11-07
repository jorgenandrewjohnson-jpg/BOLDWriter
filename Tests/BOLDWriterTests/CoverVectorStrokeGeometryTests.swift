import XCTest
import AppKit
@testable import BOLDWriter

final class CoverVectorStrokeGeometryTests: XCTestCase {
    private func pathLayer(
        closed: Bool = false
    ) -> CoverLayer {
        var layer =
            CoverLayer(
                kind: .path,
                name: "Stroke Path",
                frame:
                    CoverRect(
                        x: 0.1,
                        y: 0.1,
                        width: 0.8,
                        height: 0.8
                    )
            )

        let points = [
            CoverPathPoint(
                x: 0.1,
                y: 0.5
            ),
            CoverPathPoint(
                x: 0.5,
                y: 0.1
            ),
            CoverPathPoint(
                x: 0.9,
                y: 0.5
            )
        ]

        layer.pathPoints = points
        layer.pathContours = [points]
        layer.pathClosed = closed
        layer.pathContourClosed = [closed]
        layer.strokeWidth = 4

        return layer
    }

    func testLegacyDefaultsResolveCompatibly() {
        let geometry =
            CoverEditorEngine
                .vectorStrokeGeometry(
                    for:
                        pathLayer()
                )

        XCTAssertEqual(
            geometry.lineWidth,
            4
        )

        XCTAssertEqual(
            geometry.cap,
            .butt
        )

        XCTAssertEqual(
            geometry.join,
            .miter
        )

        XCTAssertEqual(
            geometry.miterLimit,
            10
        )

        XCTAssertEqual(
            geometry.dashPattern,
            []
        )

        XCTAssertEqual(
            geometry.dashPhase,
            0
        )
    }

    func testCapAndJoinEnumsCodableRoundTrip() throws {
        for cap in CoverStrokeCap.allCases {
            let encoded =
                try JSONEncoder()
                    .encode(cap)

            let decoded =
                try JSONDecoder()
                    .decode(
                        CoverStrokeCap.self,
                        from:
                            encoded
                    )

            XCTAssertEqual(
                decoded,
                cap
            )
        }

        for join in CoverStrokeJoin.allCases {
            let encoded =
                try JSONEncoder()
                    .encode(join)

            let decoded =
                try JSONDecoder()
                    .decode(
                        CoverStrokeJoin.self,
                        from:
                            encoded
                    )

            XCTAssertEqual(
                decoded,
                join
            )
        }
    }

    func testLegacyLayerProfessionalFieldsRemainNil() throws {
        let layer =
            pathLayer()

        let encoded =
            try JSONEncoder()
                .encode(layer)

        let decoded =
            try JSONDecoder()
                .decode(
                    CoverLayer.self,
                    from:
                        encoded
                )

        XCTAssertNil(
            decoded.strokeCap
        )

        XCTAssertNil(
            decoded.strokeJoin
        )

        XCTAssertNil(
            decoded.strokeMiterLimit
        )

        XCTAssertNil(
            decoded.strokeDashPattern
        )

        XCTAssertNil(
            decoded.strokeDashPhase
        )
    }

    func testProfessionalFieldsCodableRoundTrip() throws {
        var layer =
            pathLayer()

        layer.strokeCap =
            .square

        layer.strokeJoin =
            .bevel

        layer.strokeMiterLimit =
            6.5

        layer.strokeDashPattern = [
            8,
            4,
            2,
            4
        ]

        layer.strokeDashPhase =
            3.25

        let encoded =
            try JSONEncoder()
                .encode(layer)

        let decoded =
            try JSONDecoder()
                .decode(
                    CoverLayer.self,
                    from:
                        encoded
                )

        XCTAssertEqual(
            decoded,
            layer
        )
    }

    func testValidationAcceptsProfessionalStroke() {
        var layer =
            pathLayer()

        layer.strokeMiterLimit =
            12

        layer.strokeDashPattern = [
            10,
            4
        ]

        layer.strokeDashPhase =
            -3

        XCTAssertTrue(
            CoverStrokeValidation
                .isValid(
                    layer
                )
        )
    }

    func testValidationRejectsBadMiter() {
        var layer =
            pathLayer()

        layer.strokeMiterLimit =
            .nan

        XCTAssertFalse(
            CoverStrokeValidation.isValid(
                layer
            )
        )

        layer.strokeMiterLimit =
            0.5

        XCTAssertFalse(
            CoverStrokeValidation.isValid(
                layer
            )
        )

        layer.strokeMiterLimit =
            .infinity

        XCTAssertFalse(
            CoverStrokeValidation.isValid(
                layer
            )
        )
    }

    func testValidationRejectsBadDash() {
        var layer =
            pathLayer()

        layer.strokeDashPattern = [
            8,
            0
        ]

        XCTAssertFalse(
            CoverStrokeValidation.isValid(
                layer
            )
        )

        layer.strokeDashPattern = [
            8,
            -4
        ]

        XCTAssertFalse(
            CoverStrokeValidation.isValid(
                layer
            )
        )

        layer.strokeDashPattern = [
            8,
            .infinity
        ]

        XCTAssertFalse(
            CoverStrokeValidation.isValid(
                layer
            )
        )

        layer.strokeDashPattern =
            Array(
                repeating:
                    1,
                count:
                    CoverStrokeValidation.maximumDashCount
                    + 1
            )

        XCTAssertFalse(
            CoverStrokeValidation.isValid(
                layer
            )
        )
    }

    func testValidationRejectsBadDashPhase() {
        var layer =
            pathLayer()

        layer.strokeDashPhase =
            .nan

        XCTAssertFalse(
            CoverStrokeValidation.isValid(
                layer
            )
        )

        layer.strokeDashPhase =
            .infinity

        XCTAssertFalse(
            CoverStrokeValidation.isValid(
                layer
            )
        )
    }

    func testResolvedProfessionalGeometry() {
        var layer =
            pathLayer()

        layer.strokeWidth =
            7.5

        layer.strokeCap =
            .round

        layer.strokeJoin =
            .bevel

        layer.strokeMiterLimit =
            4.25

        layer.strokeDashPattern = [
            9,
            3,
            2,
            3
        ]

        layer.strokeDashPhase =
            2.5

        let geometry =
            CoverEditorEngine
                .vectorStrokeGeometry(
                    for:
                        layer
                )

        XCTAssertEqual(
            geometry.lineWidth,
            7.5
        )

        XCTAssertEqual(
            geometry.cap,
            .round
        )

        XCTAssertEqual(
            geometry.join,
            .bevel
        )

        XCTAssertEqual(
            geometry.miterLimit,
            4.25
        )

        XCTAssertEqual(
            geometry.dashPattern,
            [
                9,
                3,
                2,
                3
            ]
        )

        XCTAssertEqual(
            geometry.dashPhase,
            2.5
        )
    }

    func testInvalidLiveValuesResolveSafely() {
        var layer =
            pathLayer()

        layer.strokeWidth =
            -10

        layer.strokeMiterLimit =
            .nan

        layer.strokeDashPattern = [
            8,
            0
        ]

        layer.strokeDashPhase =
            .infinity

        let geometry =
            CoverEditorEngine
                .vectorStrokeGeometry(
                    for:
                        layer
                )

        XCTAssertEqual(
            geometry.lineWidth,
            0
        )

        XCTAssertEqual(
            geometry.miterLimit,
            CoverStrokeValidation.defaultMiterLimit
        )

        XCTAssertEqual(
            geometry.dashPattern,
            []
        )

        XCTAssertEqual(
            geometry.dashPhase,
            0
        )
    }

    func testBezierDefaults() {
        let layer =
            pathLayer()

        let path =
            NSBezierPath()

        path.move(
            to:
                NSPoint(
                    x: 0,
                    y: 0
                )
        )

        path.line(
            to:
                NSPoint(
                    x: 100,
                    y: 0
                )
        )

        CoverEditorEngine
            .configureVectorStroke(
                path,
                layer:
                    layer
            )

        XCTAssertEqual(
            Double(
                path.lineWidth
            ),
            4,
            accuracy:
                0.000001
        )

        XCTAssertEqual(
            path.lineCapStyle,
            .butt
        )

        XCTAssertEqual(
            path.lineJoinStyle,
            .miter
        )

        XCTAssertEqual(
            Double(
                path.miterLimit
            ),
            10,
            accuracy:
                0.000001
        )
    }

    func testBezierRoundCapAndJoin() {
        var layer =
            pathLayer()

        layer.strokeCap =
            .round

        layer.strokeJoin =
            .round

        layer.strokeMiterLimit =
            3

        let path =
            NSBezierPath()

        path.move(
            to:
                NSPoint(
                    x: 0,
                    y: 0
                )
        )

        path.line(
            to:
                NSPoint(
                    x: 50,
                    y: 50
                )
        )

        CoverEditorEngine
            .configureVectorStroke(
                path,
                layer:
                    layer
            )

        XCTAssertEqual(
            path.lineCapStyle,
            .round
        )

        XCTAssertEqual(
            path.lineJoinStyle,
            .round
        )

        XCTAssertEqual(
            Double(
                path.miterLimit
            ),
            3,
            accuracy:
                0.000001
        )
    }

    func testBezierSquareCapAndBevelJoin() {
        var layer =
            pathLayer()

        layer.strokeCap =
            .square

        layer.strokeJoin =
            .bevel

        let path =
            NSBezierPath()

        CoverEditorEngine
            .configureVectorStroke(
                path,
                layer:
                    layer
            )

        XCTAssertEqual(
            path.lineCapStyle,
            .square
        )

        XCTAssertEqual(
            path.lineJoinStyle,
            .bevel
        )
    }

    func testBezierDashPatternAndPhaseAreAccepted() {
        var layer =
            pathLayer()

        layer.strokeDashPattern = [
            8,
            4,
            2,
            4
        ]

        layer.strokeDashPhase =
            2

        let path =
            NSBezierPath()

        CoverEditorEngine
            .configureVectorStroke(
                path,
                layer:
                    layer
            )

        XCTAssertEqual(
            CoverEditorEngine
                .vectorStrokeGeometry(
                    for:
                        layer
                )
                .dashPattern,
            [
                8,
                4,
                2,
                4
            ]
        )

        XCTAssertEqual(
            CoverEditorEngine
                .vectorStrokeGeometry(
                    for:
                        layer
                )
                .dashPhase,
            2
        )
    }

    func testStrokeConfigurationDoesNotMutateTopology() {
        var layer =
            pathLayer(
                closed:
                    true
            )

        let originalPoints =
            layer.pathPoints

        let originalContours =
            layer.pathContours

        let originalClosed =
            layer.pathClosed

        let originalClosures =
            layer.pathContourClosed

        layer.strokeCap =
            .round

        layer.strokeJoin =
            .bevel

        layer.strokeMiterLimit =
            2

        layer.strokeDashPattern = [
            6,
            3
        ]

        layer.strokeDashPhase =
            1

        let path =
            CoverEditorEngine
                .vectorCompoundPath(
                    contours:
                        CoverEditorEngine
                            .vectorContours(
                                for:
                                    layer
                            ),
                    in:
                        NSRect(
                            x: 0,
                            y: 0,
                            width: 300,
                            height: 300
                        ),
                    closures:
                        CoverEditorEngine
                            .vectorContourClosures(
                                for:
                                    layer,
                                contourCount:
                                    1
                            )
                )

        CoverEditorEngine
            .configureVectorStroke(
                path,
                layer:
                    layer
            )

        XCTAssertEqual(
            layer.pathPoints,
            originalPoints
        )

        XCTAssertEqual(
            layer.pathContours,
            originalContours
        )

        XCTAssertEqual(
            layer.pathClosed,
            originalClosed
        )

        XCTAssertEqual(
            layer.pathContourClosed,
            originalClosures
        )
    }

    func testReverseContourPreservesStrokeStyle() throws {
        var layer =
            pathLayer()

        layer.strokeCap =
            .square

        layer.strokeJoin =
            .round

        layer.strokeMiterLimit =
            5

        layer.strokeDashPattern = [
            7,
            2
        ]

        layer.strokeDashPhase =
            1.5

        let result =
            try XCTUnwrap(
                CoverEditorEngine
                    .reversingVectorContour(
                        in:
                            layer,
                        contourIndex:
                            0
                    )
            )

        XCTAssertEqual(
            result.layer.strokeCap,
            layer.strokeCap
        )

        XCTAssertEqual(
            result.layer.strokeJoin,
            layer.strokeJoin
        )

        XCTAssertEqual(
            result.layer.strokeMiterLimit,
            layer.strokeMiterLimit
        )

        XCTAssertEqual(
            result.layer.strokeDashPattern,
            layer.strokeDashPattern
        )

        XCTAssertEqual(
            result.layer.strokeDashPhase,
            layer.strokeDashPhase
        )
    }

    func testDuplicateContourPreservesStrokeStyle() throws {
        var layer =
            pathLayer()

        layer.strokeCap =
            .round

        layer.strokeJoin =
            .bevel

        layer.strokeMiterLimit =
            8

        layer.strokeDashPattern = [
            4,
            2,
            1,
            2
        ]

        layer.strokeDashPhase =
            0.5

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
            result.layer.strokeCap,
            layer.strokeCap
        )

        XCTAssertEqual(
            result.layer.strokeJoin,
            layer.strokeJoin
        )

        XCTAssertEqual(
            result.layer.strokeMiterLimit,
            layer.strokeMiterLimit
        )

        XCTAssertEqual(
            result.layer.strokeDashPattern,
            layer.strokeDashPattern
        )

        XCTAssertEqual(
            result.layer.strokeDashPhase,
            layer.strokeDashPhase
        )
    }

    func testCGContextStrokeConfigurationAcceptsProfessionalGeometry() throws {
        var layer =
            pathLayer()

        layer.strokeWidth =
            6

        layer.strokeCap =
            .round

        layer.strokeJoin =
            .bevel

        layer.strokeDashPattern = [
            8,
            4
        ]

        layer.strokeDashPhase =
            2

        let context =
            try XCTUnwrap(
                CGContext(
                    data:
                        nil,
                    width:
                        64,
                    height:
                        64,
                    bitsPerComponent:
                        8,
                    bytesPerRow:
                        64 * 4,
                    space:
                        CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo:
                        CGImageAlphaInfo
                            .premultipliedLast
                            .rawValue
                )
            )

        CoverEditorEngine
            .configureVectorStroke(
                context,
                layer:
                    layer
            )

        context.move(
            to:
                CGPoint(
                    x: 5,
                    y: 32
                )
        )

        context.addLine(
            to:
                CGPoint(
                    x: 59,
                    y: 32
                )
        )

        context.strokePath()

        XCTAssertNotNil(
            context.makeImage()
        )
    }
}
