import SceneKit

/// Measurements of the actual production scene, in book-local scene units
/// (0.7 units per inch). Does not construct or substitute physical geometry.
struct BookSceneInspection: Codable {
    struct Support: Codable {
        var hinge: [Double]
        var coverHinge: [Double]
        var center: [Double]
        var depth: Double
        var minimumGap: Double
        var maximumGap: Double
    }
    var supports: [String: Support] = [:]
    var finite = true
    var vertexCount = 0
    var spineCenter: [Double]?
    var maximumCoverPenetration = 0.0
    var penetratingSurface: String?
    var penetratingPoint: [Double]?
    var turningGutter: [Double]?
    var turnUsesPrintedSurfaces: Bool?
    var boardHinges: [String: [Double]] = [:]
    var closedPageCenter: [Double]?
    var closedPageDepth: Double?
    /// Actual rendered surfaces relative to the Studio floor, in world units.
    /// Zero means resting contact; a positive value is physical clearance.
    var groundSeparations: [String: Double] = [:]

    init(scene: SCNScene?) {
        guard let root = scene?.rootNode.childNode(withName: "physical-book.root", recursively: true) else {
            finite = false; return
        }
        func array(_ p: SCNVector3) -> [Double] { [Double(p.x), Double(p.y), Double(p.z)] }
        if let world=scene?.rootNode,
           let ground=world.childNode(withName:"studio-ground",recursively:true) {
            for name in ["book-shell.front-cover","book-shell.back-cover","book-shell.spine-artwork",
                         "book.left-page-volume","book.right-page-volume"] {
                guard let node=root.childNode(withName:name,recursively:true),!node.isHidden,
                      let geometry=node.geometry else { continue }
                if let low=BookOpenGutterGeometry.surfaceVertices(geometry).map({ node.convertPosition($0,to:world).y }).min() {
                    groundSeparations[name]=Double(low-ground.position.y)
                }
            }
        }
        root.enumerateChildNodes { node, _ in
            let values = array(node.position) + array(node.scale) + array(node.eulerAngles)
            finite = finite && values.allSatisfy(\.isFinite)
            guard let source = node.geometry?.sources(for: .vertex).first else { return }
            for vertex in BookOpenGutterGeometry.vertices(source) {
                vertexCount += 1
                finite = finite && array(node.convertPosition(vertex, to: root)).allSatisfy(\.isFinite)
            }
        }
        if let spine = root.childNode(withName: "book-shell.spine-artwork", recursively: true) {
            let b = spine.boundingBox
            spineCenter = array(spine.convertPosition(SCNVector3((b.min.x+b.max.x)/2,
                (b.min.y+b.max.y)/2, (b.min.z+b.max.z)/2), to: root))
        }
        if let block = root.childNode(withName:"book.closed-page-block",recursively:true), let box = block.geometry as? SCNBox {
            closedPageCenter = array(block.convertPosition(SCNVector3Zero,to:root))
            closedPageDepth = Double(box.length)
        }
        let covers = ["front","back"].compactMap { name -> SCNNode? in
            guard let cover = root.childNode(withName:"book-shell.\(name)-cover",recursively:true) else { return nil }
            let b = cover.geometry?.boundingBox ?? cover.boundingBox
            boardHinges[name] = array(cover.convertPosition(SCNVector3(b.min.x,0,0),to:root))
            return cover
        }
        // Inspect printed sheets and visible paper meshes, not the invisible
        // rectangular stack anchors. Report maximum vertex penetration into
        // either physical board/stock volume, including the opposite cover.
        root.enumerateChildNodes { node, _ in
            let name = node.name ?? ""
            guard name.contains("active-page") || name.contains("page-volume")
                || name.contains("visible-leaf") || name.contains("endpaper") || name == "book.turning-page-leaf" else { return }
            guard !node.isHidden, let source = node.geometry?.sources(for:.vertex).first else { return }
            var measuredVertices = BookOpenGutterGeometry.vertices(source)
            let turning = name == "book.turning-page-leaf"
            if turning, let morpher = node.morpher {
                let targets = morpher.targets.compactMap { $0.sources(for:.vertex).first.map(BookOpenGutterGeometry.vertices) }
                let weights = (0..<targets.count).map { CGFloat(morpher.weight(forTargetAt:$0)) }
                let baseWeight = max(0,1-weights.reduce(0,+))
                measuredVertices = measuredVertices.enumerated().map { index, point in
                    var p = SCNVector3(point.x*baseWeight,point.y*baseWeight,point.z*baseWeight)
                    for (target,weight) in zip(targets,weights) where target.indices.contains(index) {
                        p.x += target[index].x*weight; p.y += target[index].y*weight; p.z += target[index].z*weight
                    }
                    return p
                }
                let i = (node.position.x > 0) ? 0:measuredVertices.count-2
                turningGutter = array(node.presentation.convertPosition(measuredVertices[i],to:root.presentation))
                turnUsesPrintedSurfaces = node.parent?.value(forKey:"bookTurnUsesPrintedSurfaces") as? Bool
            }
            for cover in covers {
                let b = cover.geometry?.boundingBox ?? cover.boundingBox
                let flex = (cover.geometry as? SCNBox) == nil
                    ? cover.geometry?.sources(for:.vertex).first.map(BookOpenGutterGeometry.vertices) : nil
                for vertex in measuredVertices {
                    let p: SCNVector3
                    if turning {
                        // Cover nodes remain static during a leaf turn. First
                        // resolve the animated leaf in the common book frame;
                        // mixing presentation nodes from different branches
                        // can use stale SceneKit world-transform caches.
                        let bookPoint = node.presentation.convertPosition(vertex,to:root.presentation)
                        p = cover.convertPosition(bookPoint,from:root)
                    } else { p = cover.convertPosition(vertex,from:node) }
                    guard p.x > b.min.x, p.x < b.max.x, p.y > b.min.y, p.y < b.max.y else { continue }
                    var lower = b.min.z, upper = b.max.z
                    if let flex, flex.count == 100 {
                        let u = min(24,max(0,CGFloat((p.x-b.min.x)/(b.max.x-b.min.x))*24))
                        let i = min(23,Int(u)), t = u-CGFloat(i)
                        upper = flex[i*2].z + (flex[(i+1)*2].z-flex[i*2].z)*t
                        lower = flex[i*2+50].z + (flex[(i+1)*2+50].z-flex[i*2+50].z)*t
                    }
                    var penetration = Double(min(p.z-lower,upper-p.z))
                    if let box = cover.geometry as? SCNBox {
                        // Rounded board corners must be measured as rounded
                        // stock, not an infinite plane or an opaque AABB.
                        let radius = Double(min(box.chamferRadius,box.length/2))
                        let q = SIMD3(abs(Double(p.x-(b.min.x+b.max.x)/2))-Double((b.max.x-b.min.x)/2)+radius,
                            abs(Double(p.y-(b.min.y+b.max.y)/2))-Double((b.max.y-b.min.y)/2)+radius,
                            abs(Double(p.z-(b.min.z+b.max.z)/2))-Double((b.max.z-b.min.z)/2)+radius)
                        let outside = simd_length(simd_max(q,SIMD3(repeating:0)))
                        penetration = radius - outside - min(max(q.x,max(q.y,q.z)),0)
                    }
                    if penetration > maximumCoverPenetration {
                        maximumCoverPenetration = penetration
                        penetratingSurface = name + " → " + (cover.name ?? "cover")
                        penetratingPoint = array(p)
                    }
                }
            }
        }
        for (side, name, edge, face) in [("left", "front", CGFloat(1), CGFloat(-1)),
                                        ("right", "back", CGFloat(-1), CGFloat(1))] {
            guard let block = root.childNode(withName: "book.\(side)-page-block", recursively: true),
                  let box = block.geometry as? SCNBox,
                  let cover = root.childNode(withName: "book-shell.\(name)-cover", recursively: true) else { continue }
            let b = cover.geometry?.boundingBox ?? cover.boundingBox
            let coverFace = face < 0 ? b.min.z : b.max.z
            let normal = block.convertVector(SCNVector3(0, 0, 1), to: root)
            let norm = sqrt(Double(normal.x*normal.x + normal.y*normal.y + normal.z*normal.z))
            let plane = cover.convertPosition(SCNVector3(0, 0, coverFace), to: root)
            var gaps: [Double] = []
            for t in [-0.5, -0.25, 0, 0.25, 0.5] {
                let p = block.convertPosition(SCNVector3(CGFloat(t)*box.width, 0, -box.length/2), to: root)
                gaps.append(Double((p.x-plane.x)*normal.x + (p.y-plane.y)*normal.y + (p.z-plane.z)*normal.z) / max(norm, 0.000001))
            }
            let hinge = block.convertPosition(SCNVector3(edge*box.width/2, 0, -box.length/2), to: root)
            // Front is flipped in its open support pose; both case folds are
            // the canonical local negative-X edge. Overhang is included here.
            let coverHinge = cover.convertPosition(SCNVector3(b.min.x, 0, coverFace), to: root)
            supports[side] = Support(hinge: array(hinge), coverHinge: array(coverHinge),
                center: array(block.convertPosition(SCNVector3Zero, to: root)), depth: Double(box.length),
                minimumGap: gaps.min() ?? 0, maximumGap: gaps.max() ?? 0)
        }
    }
}
