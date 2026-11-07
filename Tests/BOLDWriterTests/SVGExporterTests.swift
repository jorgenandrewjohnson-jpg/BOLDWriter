import AppKit
import XCTest
@testable import BOLDWriter

final class SVGExporterTests: XCTestCase {
    private func project() -> CoverProject {
        var project = CoverProject(
            type: .ebookFront,
            width: 6,
            height: 9
        )

        project.name = "SVG & Vector <Test>"
        project.backgroundHex = "#FFFFFF"
        project.layers = []

        return project
    }

    private func svg(
        _ project: CoverProject
    ) throws -> String {
        let data = try SVGExporter.export(project)

        return try XCTUnwrap(
            String(
                data: data,
                encoding: .utf8
            )
        )
    }

    private func png() throws -> Data {
        let bitmap = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: 2,
                pixelsHigh: 2,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 8,
                bitsPerPixel: 32
            )
        )

        for y in 0..<2 {
            for x in 0..<2 {
                bitmap.setColor(
                    NSColor(
                        calibratedRed: 0.2,
                        green: 0.4,
                        blue: 0.8,
                        alpha: 1
                    ),
                    atX: x,
                    y: y
                )
            }
        }

        return try XCTUnwrap(
            bitmap.representation(
                using: .png,
                properties: [:]
            )
        )
    }

    func testSVGRootAndViewBox() throws {
        let output = try svg(project())

        XCTAssertTrue(
            output.contains(
                #"xmlns="http://www.w3.org/2000/svg""#
            )
        )

        XCTAssertTrue(
            output.contains(
                #"viewBox="0 0 6 9""#
            )
        )

        XCTAssertTrue(
            output.contains(
                #"width="6in""#
            )
        )

        XCTAssertTrue(
            output.contains(
                #"height="9in""#
            )
        )
    }

    func testOutputIsUTF8AndDeterministic() throws {
        var project = project()

        var layer = CoverLayer(
            kind: .shape,
            name: "Deterministic",
            frame: CoverRect(
                x: 0.1,
                y: 0.2,
                width: 0.3,
                height: 0.4
            )
        )

        layer.fillHex = "#123456"

        project.layers = [layer]

        let first = try SVGExporter.export(project)
        let second = try SVGExporter.export(project)

        XCTAssertEqual(first, second)
        XCTAssertNotNil(
            String(
                data: first,
                encoding: .utf8
            )
        )
    }

    func testRectangleExportsAsEditableRect() throws {
        var project = project()

        var layer = CoverLayer(
            kind: .shape,
            name: "Rectangle",
            frame: CoverRect(
                x: 0.1,
                y: 0.2,
                width: 0.4,
                height: 0.3
            )
        )

        layer.shape = .rectangle
        project.layers = [layer]

        let output = try svg(project)

        XCTAssertTrue(output.contains("<rect"))
        XCTAssertTrue(
            output.contains(
                #"data-bold-kind="shape""#
            )
        )
    }

    func testEllipseExportsAsEditableEllipse() throws {
        var project = project()

        var layer = CoverLayer(
            kind: .shape,
            name: "Ellipse",
            frame: CoverRect()
        )

        layer.shape = .ellipse
        project.layers = [layer]

        XCTAssertTrue(
            try svg(project)
                .contains("<ellipse")
        )
    }

    func testLineExportsAsEditableLine() throws {
        var project = project()

        var layer = CoverLayer(
            kind: .shape,
            name: "Line",
            frame: CoverRect()
        )

        layer.shape = .line
        project.layers = [layer]

        XCTAssertTrue(
            try svg(project)
                .contains("<line")
        )
    }

    func testOpenPathDoesNotEmitZ() throws {
        var project = project()

        var layer = CoverLayer(
            kind: .path,
            name: "Open",
            frame: CoverRect()
        )

        layer.pathPoints = [
            CoverPathPoint(
                x: 0,
                y: 0
            ),
            CoverPathPoint(
                x: 1,
                y: 1
            )
        ]

        layer.pathClosed = false
        project.layers = [layer]

        let output = try svg(project)

        let pathLine = try XCTUnwrap(
            output
                .split(separator: "\n")
                .first {
                    $0.contains("<path ")
                }
        )

        XCTAssertFalse(
            pathLine.contains(" Z")
        )
    }

    func testClosedPathEmitsZ() throws {
        var project = project()

        var layer = CoverLayer(
            kind: .path,
            name: "Closed",
            frame: CoverRect()
        )

        layer.pathPoints = [
            CoverPathPoint(x: 0, y: 0),
            CoverPathPoint(x: 1, y: 0),
            CoverPathPoint(x: 0.5, y: 1)
        ]

        layer.pathClosed = true
        project.layers = [layer]

        XCTAssertTrue(
            try svg(project)
                .contains(" Z")
        )
    }

    func testCompoundPathPreservesContours() throws {
        var project = project()

        var layer = CoverLayer(
            kind: .path,
            name: "Compound",
            frame: CoverRect()
        )

        layer.pathContours = [
            [
                CoverPathPoint(x: 0.1, y: 0.1),
                CoverPathPoint(x: 0.9, y: 0.1),
                CoverPathPoint(x: 0.9, y: 0.9)
            ],
            [
                CoverPathPoint(x: 0.3, y: 0.3),
                CoverPathPoint(x: 0.7, y: 0.3),
                CoverPathPoint(x: 0.5, y: 0.7)
            ]
        ]

        layer.pathContourClosed = [
            true,
            true
        ]

        project.layers = [layer]

        let output = try svg(project)

        XCTAssertGreaterThanOrEqual(
            output
                .components(
                    separatedBy: "M "
                )
                .count,
            3
        )
    }

    func testCubicHandlesEmitCCommand() throws {
        var project = project()

        var first = CoverPathPoint(
            x: 0,
            y: 0
        )

        first.controlOutX = 0.25
        first.controlOutY = 0

        var second = CoverPathPoint(
            x: 1,
            y: 1
        )

        second.controlInX = 0.75
        second.controlInY = 1

        var layer = CoverLayer(
            kind: .path,
            name: "Curve",
            frame: CoverRect()
        )

        layer.pathPoints = [
            first,
            second
        ]

        layer.pathClosed = false
        project.layers = [layer]

        XCTAssertTrue(
            try svg(project)
                .contains(" C ")
        )
    }

    func testFillRulesExport() throws {
        var project = project()

        var evenOdd = CoverLayer(
            kind: .path,
            name: "Even Odd",
            frame: CoverRect()
        )

        evenOdd.pathPoints = [
            CoverPathPoint(x: 0, y: 0),
            CoverPathPoint(x: 1, y: 0),
            CoverPathPoint(x: 1, y: 1)
        ]

        evenOdd.fillRule = .evenOdd

        var nonzero = evenOdd
        nonzero.id = UUID()
        nonzero.name = "Nonzero"
        nonzero.fillRule = .nonZero

        project.layers = [
            evenOdd,
            nonzero
        ]

        let output = try svg(project)

        XCTAssertTrue(
            output.contains(
                #"fill-rule="evenodd""#
            )
        )

        XCTAssertTrue(
            output.contains(
                #"fill-rule="nonzero""#
            )
        )
    }

    func testProfessionalStrokeGeometryExports() throws {
        var project = project()

        var layer = CoverLayer(
            kind: .shape,
            name: "Stroke",
            frame: CoverRect()
        )

        layer.strokeWidth = 7.2
        layer.strokeCap = .round
        layer.strokeJoin = .bevel
        layer.strokeMiterLimit = 8
        layer.strokeDashPattern = [
            7.2,
            3.6
        ]
        layer.strokeDashPhase = 1.8

        project.layers = [layer]

        let output = try svg(project)

        XCTAssertTrue(
            output.contains(
                #"stroke-linecap="round""#
            )
        )

        XCTAssertTrue(
            output.contains(
                #"stroke-linejoin="bevel""#
            )
        )

        XCTAssertTrue(
            output.contains(
                #"stroke-miterlimit="8""#
            )
        )

        XCTAssertTrue(
            output.contains(
                #"stroke-dasharray="0.1 0.05""#
            )
        )

        XCTAssertTrue(
            output.contains(
                #"stroke-dashoffset="0.025""#
            )
        )
    }

    func testVisibilityOpacityAndTransformsExport() throws {
        var project = project()

        var layer = CoverLayer(
            kind: .shape,
            name: "Transform",
            frame: CoverRect(
                x: 0.1,
                y: 0.2,
                width: 0.4,
                height: 0.3
            )
        )

        layer.opacity = 0.42
        layer.visible = false
        layer.rotation = 30
        layer.flipHorizontal = true
        layer.flipVertical = true
        layer.skewX = 0.2
        layer.skewY = -0.1

        project.layers = [layer]

        let output = try svg(project)

        XCTAssertTrue(
            output.contains(
                #"opacity="0.42""#
            )
        )

        XCTAssertTrue(
            output.contains(
                #"display="none""#
            )
        )

        XCTAssertTrue(
            output.contains(
                "rotate(30)"
            )
        )

        XCTAssertTrue(
            output.contains(
                "matrix(1 -0.1 0.2 1 0 0)"
            )
        )

        XCTAssertTrue(
            output.contains(
                "scale(-1 -1)"
            )
        )
    }

    func testLinearGradientExportsNatively() throws {
        var project = project()

        var layer = CoverLayer(
            kind: .gradient,
            name: "Linear",
            frame: CoverRect()
        )

        layer.fillHex = "#112233"
        layer.gradientEndHex = "#AABBCC"
        layer.gradientAngle = 45
        layer.gradientRadial = false

        project.layers = [layer]

        let output = try svg(project)

        XCTAssertTrue(
            output.contains(
                "<linearGradient"
            )
        )

        XCTAssertTrue(
            output.contains(
                #"fill="url(#gradient-0)""#
            )
        )
    }

    func testRadialGradientExportsNatively() throws {
        var project = project()

        var layer = CoverLayer(
            kind: .gradient,
            name: "Radial",
            frame: CoverRect()
        )

        layer.gradientRadial = true
        layer.gradientCenterX = 0.4
        layer.gradientCenterY = 0.6
        layer.gradientRadius = 0.7

        project.layers = [layer]

        let output = try svg(project)

        XCTAssertTrue(
            output.contains(
                "<radialGradient"
            )
        )

        XCTAssertTrue(
            output.contains(
                #"cx="40%""#
            )
        )

        XCTAssertTrue(
            output.contains(
                #"cy="60%""#
            )
        )

        XCTAssertTrue(
            output.contains(
                #"r="70%""#
            )
        )
    }

    func testTextRemainsEditableAndEscaped() throws {
        var project = project()

        var layer = CoverLayer(
            kind: .text,
            name: #"Text "Layer" & <Name>"#,
            frame: CoverRect(
                x: 0.1,
                y: 0.1,
                width: 0.8,
                height: 0.3
            )
        )

        layer.text =
            "A & B < C\nSecond > Line"

        layer.fontName =
            #"Test "Font" & Family"#

        layer.fontSize = 36
        layer.bold = true
        layer.italic = true
        layer.underline = true

        project.layers = [layer]

        let output = try svg(project)

        XCTAssertTrue(output.contains("<text "))
        XCTAssertTrue(output.contains("<tspan"))

        XCTAssertTrue(
            output.contains(
                "A &amp; B &lt; C"
            )
        )

        XCTAssertTrue(
            output.contains(
                "Second &gt; Line"
            )
        )

        XCTAssertTrue(
            output.contains(
                "&quot;Layer&quot;"
            )
        )

        XCTAssertFalse(
            output.contains(
                "A & B < C"
            )
        )
    }

    func testImageAndPaintUseIsolatedRasterFallback() throws {
        var project = project()

        var image = CoverLayer(
            kind: .image,
            name: "Raster Image",
            frame: CoverRect(
                x: 0,
                y: 0,
                width: 0.5,
                height: 0.5
            )
        )

        image.imageData = try png()

        var paint = CoverLayer(
            kind: .paint,
            name: "Paint",
            frame: CoverRect(
                x: 0.5,
                y: 0.5,
                width: 0.5,
                height: 0.5
            )
        )

        paint.imageData = try png()

        project.layers = [
            image,
            paint
        ]

        let output = try svg(project)

        XCTAssertTrue(
            output.contains(
                "data:image/png;base64,"
            )
        )

        XCTAssertTrue(
            output.contains(
                #"preserveAspectRatio="none""#
            )
        )
    }

    func testSmartObjectCurrentVisualUsesRasterFallback() throws {
        var project = project()
        let source = try png()

        let layer = try CoverEditorEngine
            .smartObjectLayerFromEmbeddedSource(
                data: source,
                filename: "smart.png",
                project: project
            )

        XCTAssertEqual(
            layer.kind,
            .smartObject
        )

        XCTAssertNotNil(
            layer.smartObject
        )

        XCTAssertNotNil(
            layer.imageData
        )

        project.layers = [
            layer
        ]

        let output = try svg(project)

        XCTAssertTrue(
            output.contains(
                #"data-bold-kind="smartObject""#
            )
        )

        XCTAssertTrue(
            output.contains(
                "data:image/png;base64,"
            )
        )
    }

    func testRasterMaskDoesNotFlattenUnrelatedVectorLayer() throws {
        var project = project()

        var masked = CoverLayer(
            kind: .shape,
            name: "Masked",
            frame: CoverRect(
                x: 0,
                y: 0,
                width: 0.5,
                height: 0.5
            )
        )

        masked.maskData = try png()
        masked.maskEnabled = true

        var vector = CoverLayer(
            kind: .shape,
            name: "Still Vector",
            frame: CoverRect(
                x: 0.5,
                y: 0.5,
                width: 0.5,
                height: 0.5
            )
        )

        vector.shape = .ellipse

        project.layers = [
            masked,
            vector
        ]

        let output = try svg(project)

        XCTAssertTrue(
            output.contains("<mask ")
        )

        XCTAssertTrue(
            output.contains("<ellipse")
        )
    }

    func testLayerOrderRemainsProjectOrder() throws {
        var project = project()

        let first = CoverLayer(
            kind: .shape,
            name: "Bottom",
            frame: CoverRect()
        )

        var second = CoverLayer(
            kind: .shape,
            name: "Top",
            frame: CoverRect()
        )

        second.shape = .ellipse

        project.layers = [
            first,
            second
        ]

        let output = try svg(project)

        let firstRange = try XCTUnwrap(
            output.range(
                of: #"id="layer-0""#
            )
        )

        let secondRange = try XCTUnwrap(
            output.range(
                of: #"id="layer-1""#
            )
        )

        XCTAssertLessThan(
            firstRange.lowerBound,
            secondRange.lowerBound
        )
    }

    func testNativeVectorDocumentIsNotFullCanvasRaster() throws {
        var project = project()

        var rectangle = CoverLayer(
            kind: .shape,
            name: "Vector Rect",
            frame: CoverRect(
                x: 0,
                y: 0,
                width: 0.5,
                height: 0.5
            )
        )

        rectangle.fillHex = "#FF0000"

        var path = CoverLayer(
            kind: .path,
            name: "Vector Path",
            frame: CoverRect(
                x: 0.5,
                y: 0.5,
                width: 0.5,
                height: 0.5
            )
        )

        path.pathPoints = [
            CoverPathPoint(
                x: 0,
                y: 0
            ),
            CoverPathPoint(
                x: 1,
                y: 1
            )
        ]

        path.pathClosed = false

        project.layers = [
            rectangle,
            path
        ]

        let output = try svg(project)

        XCTAssertTrue(output.contains("<rect"))
        XCTAssertTrue(output.contains("<path"))

        XCTAssertFalse(
            output.contains(
                #"id="full-document-raster""#
            )
        )
    }

    func testProjectAndLayerNamesAreEscaped() throws {
        var project = project()

        project.name =
            #"A "B" & <C>"#

        let layer = CoverLayer(
            kind: .shape,
            name: #"Layer "D" & <E>"#,
            frame: CoverRect()
        )

        project.layers = [layer]

        let output = try svg(project)

        XCTAssertTrue(
            output.contains(
                #"data-bold-project="A &quot;B&quot; &amp; &lt;C&gt;""#
            )
        )

        XCTAssertTrue(
            output.contains(
                #"data-bold-name="Layer &quot;D&quot; &amp; &lt;E&gt;""#
            )
        )
    }

    func testInvalidCanvasDimensionIsRejected() throws {
        var project = project()
        project.canvasWidth = .infinity

        XCTAssertThrowsError(
            try SVGExporter.export(project)
        )
    }

    func testNonfinitePathCoordinateIsRejected() throws {
        var project = project()

        var layer = CoverLayer(
            kind: .path,
            name: "Invalid",
            frame: CoverRect()
        )

        layer.pathPoints = [
            CoverPathPoint(
                x: Double.infinity,
                y: 0
            ),
            CoverPathPoint(
                x: 1,
                y: 1
            )
        ]

        project.layers = [layer]

        XCTAssertThrowsError(
            try SVGExporter.export(project)
        )
    }
}
