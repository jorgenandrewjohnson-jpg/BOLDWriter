import AppKit
import SceneKit
import XCTest
@testable import BOLDWriter

/// The physical softcover uses a curved, segmented mesh.
/// Cover-art coordinates must remain a continuous, complete
/// rectangular image even when the physical panel bends.
final class BookCoverUVMappingTests: XCTestCase {

    private let segments = 24

    /// Read UVs using SceneKit's actual declared component layout,
    /// avoiding assumptions about Float32 versus Float64 storage.
    private func coordinates(
        from geometry: SCNGeometry,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> [SIMD2<Double>] {
        let sources = geometry.sources(for: .texcoord)

        XCTAssertEqual(
            sources.count,
            1,
            "Physical cover should have one texture-coordinate stream",
            file: file,
            line: line
        )

        let source = try XCTUnwrap(sources.first)

        XCTAssertTrue(
            source.usesFloatComponents,
            file: file,
            line: line
        )

        XCTAssertEqual(
            source.componentsPerVector,
            2,
            file: file,
            line: line
        )

        XCTAssertTrue(
            source.bytesPerComponent == 4 ||
            source.bytesPerComponent == 8,
            file: file,
            line: line
        )

        let bytesPerComponent = source.bytesPerComponent
        let stride = source.dataStride
        let firstOffset = source.dataOffset
        let raw = source.data as NSData

        guard
            source.usesFloatComponents,
            source.componentsPerVector == 2,
            bytesPerComponent == 4 || bytesPerComponent == 8,
            stride >= bytesPerComponent * 2,
            firstOffset >= 0
        else {
            throw NSError(
                domain: "BookCoverUVMappingTests",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Unsupported SceneKit UV layout"
                ]
            )
        }

        func component(at offset: Int) throws -> Double {
            guard
                offset >= 0,
                offset <= raw.length - bytesPerComponent
            else {
                throw NSError(
                    domain: "BookCoverUVMappingTests",
                    code: 2,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "UV byte offset out of bounds"
                    ]
                )
            }

            if bytesPerComponent == 4 {
                var result: Float = 0

                raw.getBytes(
                    &result,
                    range: NSRange(
                        location: offset,
                        length: 4
                    )
                )

                return Double(result)
            } else {
                var result: Double = 0

                raw.getBytes(
                    &result,
                    range: NSRange(
                        location: offset,
                        length: 8
                    )
                )

                return result
            }
        }

        return try (0..<source.vectorCount).map { index in
            let offset = firstOffset + index * stride

            return SIMD2<Double>(
                try component(at: offset),
                try component(at: offset + bytesPerComponent)
            )
        }
    }

    private func makeCover(
        insideEdge: ThumbSide,
        thickness: CGFloat,
        direction: CGFloat
    ) -> SCNGeometry {
        BookPreviewScene.flexibleCoverGeometry(
            width: 6,
            height: 9,
            insideEdge: insideEdge,
            creaseDepth: 0.075,
            bowDepth: 0.10,
            depthDirection: direction,
            thickness: thickness
        )
    }

    func testCurvedCoverKeepsFullUnstretchedUVGrid() throws {
        // Exercise each physical hinge side and both bow directions.
        for edge in [ThumbSide.left, .right] {
            for direction: CGFloat in [-1, 1] {
                let geometry = makeCover(
                    insideEdge: edge,
                    thickness: 0,
                    direction: direction
                )

                let uv = try coordinates(from: geometry)

                XCTAssertEqual(
                    uv.count,
                    (segments + 1) * 2
                )

                for segment in 0...segments {
                    let top = uv[segment * 2]
                    let bottom = uv[segment * 2 + 1]
                    let expectedU =
                        Double(segment) / Double(segments)

                    XCTAssertTrue(top.x.isFinite)
                    XCTAssertTrue(top.y.isFinite)
                    XCTAssertTrue(bottom.x.isFinite)
                    XCTAssertTrue(bottom.y.isFinite)

                    XCTAssertEqual(
                        top.x,
                        expectedU,
                        accuracy: 0.00001
                    )

                    XCTAssertEqual(
                        bottom.x,
                        expectedU,
                        accuracy: 0.00001
                    )

                    XCTAssertEqual(
                        top.y,
                        1,
                        accuracy: 0.00001
                    )

                    XCTAssertEqual(
                        bottom.y,
                        0,
                        accuracy: 0.00001
                    )

                    if segment > 0 {
                        let previous = uv[(segment - 1) * 2]

                        XCTAssertEqual(
                            top.x - previous.x,
                            1.0 / Double(segments),
                            accuracy: 0.00001,
                            "Unexpected horizontal artwork distortion"
                        )
                    }
                }
            }
        }
    }

    func testCoverThicknessPreservesValidUVRangeAndTopology()
        throws
    {
        for edge in [ThumbSide.left, .right] {
            for direction: CGFloat in [-1, 1] {
                for thickness: CGFloat in [0.04, 0.12] {
                    let geometry = makeCover(
                        insideEdge: edge,
                        thickness: thickness,
                        direction: direction
                    )

                    let uv = try coordinates(from: geometry)

                    XCTAssertEqual(
                        uv.count,
                        (segments + 1) * 4
                    )

                    let vertices = try XCTUnwrap(
                        geometry.sources(for: .vertex).first
                    )

                    XCTAssertEqual(
                        vertices.vectorCount,
                        uv.count,
                        "Vertex and UV topology diverged"
                    )

                    XCTAssertFalse(geometry.elements.isEmpty)

                    for coordinate in uv {
                        XCTAssertTrue(coordinate.x.isFinite)
                        XCTAssertTrue(coordinate.y.isFinite)

                        XCTAssertGreaterThanOrEqual(
                            coordinate.x,
                            -0.00001
                        )

                        XCTAssertLessThanOrEqual(
                            coordinate.x,
                            1.00001
                        )

                        XCTAssertGreaterThanOrEqual(
                            coordinate.y,
                            -0.00001
                        )

                        XCTAssertLessThanOrEqual(
                            coordinate.y,
                            1.00001
                        )
                    }
                }
            }
        }
    }

    func testCoverMeshBoundsRemainFiniteForAllHingeDirections()
        throws
    {
        for edge in [ThumbSide.left, .right] {
            for direction: CGFloat in [-1, 1] {
                for thickness: CGFloat in [0, 0.08] {
                    let geometry = makeCover(
                        insideEdge: edge,
                        thickness: thickness,
                        direction: direction
                    )

                    let box = geometry.boundingBox

                    for component in [
                        box.min.x, box.min.y, box.min.z,
                        box.max.x, box.max.y, box.max.z
                    ] {
                        XCTAssertTrue(
                            component.isFinite,
                            "Physical cover contains invalid geometry"
                        )
                    }

                    XCTAssertGreaterThan(
                        box.max.x - box.min.x,
                        5.5
                    )

                    XCTAssertGreaterThan(
                        box.max.y - box.min.y,
                        8.5
                    )

                    XCTAssertGreaterThan(
                        geometry.geometrySourcesCountForUVReview,
                        0
                    )
                }
            }
        }
    }

    // MARK: - Physical triangle and artwork-mapping validation

    /// Read the actual SceneKit triangle index buffer.
    ///
    /// Tests must inspect the geometry produced by the renderer,
    /// rather than reconstructing its expected indices independently.
    private func triangleIndices(
        from element: SCNGeometryElement
    ) throws -> [[Int]] {
        XCTAssertEqual(
            element.primitiveType,
            .triangles,
            "Cover artwork must use triangle geometry"
        )

        let bytesPerIndex = element.bytesPerIndex

        guard [1, 2, 4, 8].contains(bytesPerIndex) else {
            XCTFail("Unsupported SceneKit triangle index width")
            return []
        }

        let indexCount = element.primitiveCount * 3
        let bytes = [UInt8](element.data)

        guard
            indexCount > 0,
            bytes.count >= indexCount * bytesPerIndex
        else {
            XCTFail("Triangle index buffer is incomplete")
            return []
        }

        var decoded: [Int] = []
        decoded.reserveCapacity(indexCount)

        for index in 0..<indexCount {
            let offset = index * bytesPerIndex
            var value: UInt64 = 0

            for byte in 0..<bytesPerIndex {
                value |=
                    UInt64(bytes[offset + byte])
                    << (byte * 8)
            }

            guard let integer = Int(exactly: value) else {
                XCTFail("Triangle index exceeds Int range")
                return []
            }

            decoded.append(integer)
        }

        return stride(
            from: 0,
            to: decoded.count,
            by: 3
        ).map { position in
            Array(decoded[position..<(position + 3)])
        }
    }

    /// Verify that the actual triangles cover every strip of
    /// the artwork exactly once, without missing, overlapping,
    /// degenerate, reversed, or misplaced UV triangles.
    ///
    /// `vertexOffset` is zero for the front face and equal to
    /// the first face's vertex count for a thick cover's back.
    private func verifyTiledArtworkSurface(
        geometry: SCNGeometry,
        element: SCNGeometryElement,
        vertexOffset: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let uv = try coordinates(
            from: geometry,
            file: file,
            line: line
        )

        let triangles = try triangleIndices(from: element)

        XCTAssertEqual(
            triangles.count,
            segments * 2,
            "Each physical cover strip must contain two triangles",
            file: file,
            line: line
        )

        guard triangles.count == segments * 2 else {
            return
        }

        let verticesPerFace = (segments + 1) * 2

        XCTAssertGreaterThanOrEqual(
            uv.count,
            vertexOffset + verticesPerFace,
            file: file,
            line: line
        )

        guard uv.count >= vertexOffset + verticesPerFace else {
            return
        }

        var triangleCounts = Array(
            repeating: 0,
            count: segments
        )

        var stripAreas = Array(
            repeating: 0.0,
            count: segments
        )

        var totalArea = 0.0
        var winding: Double?

        for triangle in triangles {
            XCTAssertEqual(
                triangle.count,
                3,
                file: file,
                line: line
            )

            guard triangle.count == 3 else {
                continue
            }

            let indices = triangle

            guard indices.allSatisfy({
                $0 >= vertexOffset &&
                $0 < vertexOffset + verticesPerFace
            }) else {
                XCTFail(
                    "Artwork triangle references another surface",
                    file: file,
                    line: line
                )
                continue
            }

            XCTAssertEqual(
                Set(indices).count,
                3,
                "Triangle contains duplicate vertex indices",
                file: file,
                line: line
            )

            let relative = indices.map {
                $0 - vertexOffset
            }

            let columns = relative.map { $0 / 2 }

            guard let firstColumn = columns.min(),
                  let finalColumn = columns.max()
            else {
                continue
            }

            XCTAssertEqual(
                finalColumn - firstColumn,
                1,
                "Triangle spans more than one UV strip",
                file: file,
                line: line
            )

            guard
                firstColumn >= 0,
                firstColumn < segments,
                finalColumn == firstColumn + 1
            else {
                XCTFail(
                    "Triangle references an invalid artwork strip",
                    file: file,
                    line: line
                )
                continue
            }

            let allowedVertices = Set([
                vertexOffset + firstColumn * 2,
                vertexOffset + firstColumn * 2 + 1,
                vertexOffset + (firstColumn + 1) * 2,
                vertexOffset + (firstColumn + 1) * 2 + 1
            ])

            XCTAssertTrue(
                Set(indices).isSubset(of: allowedVertices),
                "Triangle crosses an unexpected artwork boundary",
                file: file,
                line: line
            )

            let a = uv[indices[0]]
            let b = uv[indices[1]]
            let c = uv[indices[2]]

            let signedDoubleArea =
                (b.x - a.x) * (c.y - a.y)
                - (b.y - a.y) * (c.x - a.x)

            XCTAssertTrue(
                signedDoubleArea.isFinite,
                "Invalid mapped triangle area",
                file: file,
                line: line
            )

            XCTAssertGreaterThan(
                abs(signedDoubleArea),
                0.000001,
                "Artwork contains a collapsed triangle",
                file: file,
                line: line
            )

            if let winding {
                XCTAssertGreaterThan(
                    signedDoubleArea * winding,
                    0,
                    "A physical cover face reverses artwork winding",
                    file: file,
                    line: line
                )
            } else if abs(signedDoubleArea) > 0.000001 {
                winding = signedDoubleArea
            }

            let area = abs(signedDoubleArea) / 2

            triangleCounts[firstColumn] += 1
            stripAreas[firstColumn] += area
            totalArea += area
        }

        for strip in 0..<segments {
            XCTAssertEqual(
                triangleCounts[strip],
                2,
                "UV strip \(strip) is missing or duplicated",
                file: file,
                line: line
            )

            XCTAssertEqual(
                stripAreas[strip],
                1.0 / Double(segments),
                accuracy: 0.00001,
                "UV strip \(strip) covers the wrong artwork area",
                file: file,
                line: line
            )
        }

        XCTAssertEqual(
            totalArea,
            1.0,
            accuracy: 0.00001,
            "Triangles must cover the entire unit-square artwork",
            file: file,
            line: line
        )
    }

    func testPhysicalCoverTrianglesTileEveryUVStripExactly()
        throws
    {
        for edge in [ThumbSide.left, .right] {
            for direction: CGFloat in [-1, 1] {
                for thickness: CGFloat in [0, 0.04, 0.12] {
                    let geometry = makeCover(
                        insideEdge: edge,
                        thickness: thickness,
                        direction: direction
                    )

                    let front = try XCTUnwrap(
                        geometry.elements.first
                    )

                    try verifyTiledArtworkSurface(
                        geometry: geometry,
                        element: front,
                        vertexOffset: 0
                    )
                }
            }
        }
    }

    func testThickCoverBackFaceUsesCompleteIndependentUVTopology()
        throws
    {
        for edge in [ThumbSide.left, .right] {
            for direction: CGFloat in [-1, 1] {
                for thickness: CGFloat in [0.04, 0.12] {
                    let geometry = makeCover(
                        insideEdge: edge,
                        thickness: thickness,
                        direction: direction
                    )

                    XCTAssertGreaterThanOrEqual(
                        geometry.elements.count,
                        2,
                        "Thick covers require separate front/back faces"
                    )

                    guard geometry.elements.count >= 2 else {
                        continue
                    }

                    let verticesPerFace = (segments + 1) * 2

                    let uv = try coordinates(from: geometry)

                    XCTAssertEqual(
                        uv.count,
                        verticesPerFace * 2
                    )

                    guard uv.count == verticesPerFace * 2 else {
                        continue
                    }

                    for index in 0..<verticesPerFace {
                        XCTAssertEqual(
                            uv[index].x,
                            uv[index + verticesPerFace].x,
                            accuracy: 0.000001,
                            "Artwork U moved between cover faces"
                        )

                        XCTAssertEqual(
                            uv[index].y,
                            uv[index + verticesPerFace].y,
                            accuracy: 0.000001,
                            "Artwork V moved between cover faces"
                        )
                    }

                    try verifyTiledArtworkSurface(
                        geometry: geometry,
                        element: geometry.elements[0],
                        vertexOffset: 0
                    )

                    try verifyTiledArtworkSurface(
                        geometry: geometry,
                        element: geometry.elements[1],
                        vertexOffset: verticesPerFace
                    )
                }
            }
        }
    }

    func testCoverArtworkCoordinatesAreInvariantAcrossPhysicalBending()
        throws
    {
        let reference = try coordinates(
            from: makeCover(
                insideEdge: .left,
                thickness: 0,
                direction: 1
            )
        )

        let verticesPerFace = (segments + 1) * 2

        XCTAssertEqual(reference.count, verticesPerFace)

        guard reference.count == verticesPerFace else {
            return
        }

        for edge in [ThumbSide.left, .right] {
            for direction: CGFloat in [-1, 1] {
                for thickness: CGFloat in [0, 0.04, 0.12] {
                    let geometry = makeCover(
                        insideEdge: edge,
                        thickness: thickness,
                        direction: direction
                    )

                    let actual = try coordinates(from: geometry)

                    XCTAssertGreaterThanOrEqual(
                        actual.count,
                        verticesPerFace
                    )

                    guard actual.count >= verticesPerFace else {
                        continue
                    }

                    for index in 0..<verticesPerFace {
                        XCTAssertEqual(
                            actual[index].x,
                            reference[index].x,
                            accuracy: 0.000001,
                            "Physical bending shifted artwork U"
                        )

                        XCTAssertEqual(
                            actual[index].y,
                            reference[index].y,
                            accuracy: 0.000001,
                            "Physical bending shifted artwork V"
                        )
                    }
                }
            }
        }
    }

}

// Keep the geometry-source existence check separate from
// SceneKit's actual underlying vertex/UV data representation.
private extension SCNGeometry {
    var geometrySourcesCountForUVReview: Int {
        sources(for: .vertex).count
    }
}
