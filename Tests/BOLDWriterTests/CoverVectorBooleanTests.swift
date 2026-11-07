import AppKit
import XCTest
@testable import BOLDWriter

final class CoverVectorBooleanTests:XCTestCase {
    private func rectangle(
        _ name:String,
        frame:CoverRect,
        fill:String="#FFFFFF"
    )->CoverLayer {
        var layer=CoverLayer(
            kind:.path,
            name:name,
            frame:frame
        )

        layer.pathPoints=[
            CoverPathPoint(x:0,y:0),
            CoverPathPoint(x:1,y:0),
            CoverPathPoint(x:1,y:1),
            CoverPathPoint(x:0,y:1)
        ]

        layer.pathClosed=true
        layer.fillHex=fill
        layer.strokeHex=fill
        layer.strokeWidth=0

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

    private func result(
        _ operation:CoverVectorBooleanOperation,
        _ first:CoverLayer,
        _ second:CoverLayer
    ) throws -> (CoverProject,CoverLayer) {
        let source=makeProject(
            [first,second]
        )

        let output=try XCTUnwrap(
            CoverEditorEngine.booleanPathLayer(
                project:source,
                ids:Set(
                    [
                        first.id,
                        second.id
                    ]
                ),
                primaryID:first.id,
                operation:operation
            )
        )

        return (source,output)
    }

    private func contains(
        _ layer:CoverLayer,
        in project:CoverProject,
        x:Double,
        y:Double
    )->Bool {
        CoverEditorEngine.vectorLayerContains(
            layer,
            project:project,
            normalizedPoint:CGPoint(
                x:x,
                y:y
            )
        )
    }

    func testUnionProducesEditableVectorGeometry() throws {
        let a=rectangle(
            "A",
            frame:CoverRect(
                x:0,
                y:0,
                width:0.6,
                height:1
            ),
            fill:"#123456"
        )

        let b=rectangle(
            "B",
            frame:CoverRect(
                x:0.4,
                y:0,
                width:0.6,
                height:1
            )
        )

        let (source,output)=try result(
            .union,
            a,
            b
        )

        XCTAssertEqual(output.kind,.path)
        XCTAssertNil(output.imageData)
        XCTAssertTrue(output.pathClosed == true)
        XCTAssertFalse(output.pathContours?.isEmpty ?? true)
        XCTAssertEqual(output.fillHex,"#123456")

        XCTAssertTrue(
            contains(
                output,
                in:source,
                x:0.2,
                y:0.5
            )
        )

        XCTAssertTrue(
            contains(
                output,
                in:source,
                x:0.5,
                y:0.5
            )
        )

        XCTAssertTrue(
            contains(
                output,
                in:source,
                x:0.8,
                y:0.5
            )
        )
    }

    func testSubtractUsesPrimaryPathAsBase() throws {
        let a=rectangle(
            "A",
            frame:CoverRect(
                x:0,
                y:0,
                width:0.6,
                height:1
            )
        )

        let b=rectangle(
            "B",
            frame:CoverRect(
                x:0.4,
                y:0,
                width:0.6,
                height:1
            )
        )

        let (source,output)=try result(
            .subtract,
            a,
            b
        )

        XCTAssertTrue(
            contains(
                output,
                in:source,
                x:0.2,
                y:0.5
            )
        )

        XCTAssertFalse(
            contains(
                output,
                in:source,
                x:0.5,
                y:0.5
            )
        )

        XCTAssertFalse(
            contains(
                output,
                in:source,
                x:0.8,
                y:0.5
            )
        )
    }

    func testIntersectKeepsOnlySharedArea() throws {
        let a=rectangle(
            "A",
            frame:CoverRect(
                x:0,
                y:0,
                width:0.6,
                height:1
            )
        )

        let b=rectangle(
            "B",
            frame:CoverRect(
                x:0.4,
                y:0,
                width:0.6,
                height:1
            )
        )

        let (source,output)=try result(
            .intersect,
            a,
            b
        )

        XCTAssertFalse(
            contains(
                output,
                in:source,
                x:0.2,
                y:0.5
            )
        )

        XCTAssertTrue(
            contains(
                output,
                in:source,
                x:0.5,
                y:0.5
            )
        )

        XCTAssertFalse(
            contains(
                output,
                in:source,
                x:0.8,
                y:0.5
            )
        )
    }

    func testExcludeRemovesSharedArea() throws {
        let a=rectangle(
            "A",
            frame:CoverRect(
                x:0,
                y:0,
                width:0.6,
                height:1
            )
        )

        let b=rectangle(
            "B",
            frame:CoverRect(
                x:0.4,
                y:0,
                width:0.6,
                height:1
            )
        )

        let (source,output)=try result(
            .exclude,
            a,
            b
        )

        XCTAssertTrue(
            contains(
                output,
                in:source,
                x:0.2,
                y:0.5
            )
        )

        XCTAssertFalse(
            contains(
                output,
                in:source,
                x:0.5,
                y:0.5
            )
        )

        XCTAssertTrue(
            contains(
                output,
                in:source,
                x:0.8,
                y:0.5
            )
        )
    }

    func testDisjointUnionPersistsMultipleContours() throws {
        let a=rectangle(
            "A",
            frame:CoverRect(
                x:0.05,
                y:0.1,
                width:0.25,
                height:0.8
            )
        )

        let b=rectangle(
            "B",
            frame:CoverRect(
                x:0.70,
                y:0.1,
                width:0.25,
                height:0.8
            )
        )

        let (_,output)=try result(
            .union,
            a,
            b
        )

        XCTAssertGreaterThanOrEqual(
            output.pathContours?.count ?? 0,
            2
        )

        let reopened=try JSONDecoder().decode(
            CoverLayer.self,
            from:JSONEncoder().encode(output)
        )

        XCTAssertEqual(
            reopened.pathContours,
            output.pathContours
        )
    }

    func testSubtractCreatesEditableHole() throws {
        let outer=rectangle(
            "Outer",
            frame:CoverRect(
                x:0.1,
                y:0.1,
                width:0.8,
                height:0.8
            )
        )

        let inner=rectangle(
            "Inner",
            frame:CoverRect(
                x:0.4,
                y:0.4,
                width:0.2,
                height:0.2
            )
        )

        let (source,output)=try result(
            .subtract,
            outer,
            inner
        )

        XCTAssertTrue(
            contains(
                output,
                in:source,
                x:0.2,
                y:0.2
            )
        )

        XCTAssertFalse(
            contains(
                output,
                in:source,
                x:0.5,
                y:0.5
            )
        )

        XCTAssertGreaterThanOrEqual(
            output.pathContours?.count ?? 0,
            2
        )
    }

    func testRotationAndFlipBakeIntoResult() throws {
        var a=rectangle(
            "A",
            frame:CoverRect(
                x:0.1,
                y:0.2,
                width:0.35,
                height:0.6
            )
        )

        a.rotation=20
        a.flipHorizontal=true

        let b=rectangle(
            "B",
            frame:CoverRect(
                x:0.35,
                y:0.2,
                width:0.35,
                height:0.6
            )
        )

        let (_,output)=try result(
            .union,
            a,
            b
        )

        XCTAssertEqual(
            output.rotation,
            0,
            accuracy:0.000001
        )

        XCTAssertFalse(output.flipHorizontal)
        XCTAssertFalse(output.flipVertical)
        XCTAssertNil(output.skewX)
        XCTAssertNil(output.skewY)
    }

    func testOpenPathCannotBeBooleanOperand() {
        var a=rectangle(
            "A",
            frame:CoverRect(
                x:0,
                y:0,
                width:0.6,
                height:1
            )
        )

        a.pathClosed=false

        let b=rectangle(
            "B",
            frame:CoverRect(
                x:0.4,
                y:0,
                width:0.6,
                height:1
            )
        )

        let source=makeProject(
            [a,b]
        )

        XCTAssertNil(
            CoverEditorEngine.booleanPathLayer(
                project:source,
                ids:Set(
                    [
                        a.id,
                        b.id
                    ]
                ),
                primaryID:a.id,
                operation:.union
            )
        )
    }
}
