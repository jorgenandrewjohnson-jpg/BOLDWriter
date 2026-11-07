import SceneKit

/// The printed leaves and visible paper mass share one bound gutter. Rigid
/// stack tops otherwise leave a step equal to the unequal page masses.
enum BookOpenGutterGeometry {
    static func update(in root: SCNNode, hingeZ: CGFloat, angle: Double) {
        let progress = CGFloat(min(1,max(0,(angle-90)/70)))
        let covers = contactSurfaces(in:root)
        func pastedLining(_ world: SCNVector3, side: String) -> SCNVector3 {
            guard let (cover,front,points) = covers.first(where: { $0.1 == (side == "left") }) else { return world }
            let b = cover.geometry?.boundingBox ?? cover.boundingBox
            var p = cover.convertPosition(world,from:root)
            var lining = front ? b.min.z:b.max.z
            if let points, points.count == 100 {
                let u=min(24,max(0,(p.x-b.min.x)/(b.max.x-b.min.x)*24))
                let i=min(23,Int(u)),t=u-CGFloat(i),offset=front ? 50:0
                lining=points[i*2+offset].z+(points[(i+1)*2+offset].z-points[i*2+offset].z)*t
            }
            p.z=lining+(front ? -0.001:0.001)
            return cover.convertPosition(p,to:root)
        }
        func contact(_ point: SCNVector3) -> SCNVector3 {
            Self.contact(point,root:root,covers:covers)
        }
        for side in ["left","right"] {
            guard let block = root.childNode(withName:"book.\(side)-page-block",recursively:true),
                  let box = block.geometry as? SCNBox else { continue }
            let page = root.childNode(withName:"book.\(side)-active-page",recursively:true)
            var delta = SCNVector3Zero
            if let page, let source = page.geometry?.sources(for:.vertex).first {
                let points = vertices(source)
                if let edge = (side == "left" ? points.max(by:{$0.x < $1.x}):points.min(by:{$0.x < $1.x})) {
                    let gutter = page.convertPosition(edge,to:root)
                    delta = SCNVector3(-gutter.x,0,hingeZ+0.020-gutter.z)
                }
            }
            var profile: [SCNVector3] = []
            func deform(_ node: SCNNode, sheet: Bool) {
                guard let geometry = node.geometry, let source = geometry.sources(for:.vertex).first else { return }
                // Fore-edge strata are planar decals outside the gutter's
                // influence; keep their plane geometry and original placement.
                if !sheet, geometry is SCNPlane { return }
                let original = vertices(source)
                let result = original.enumerated().map { index, point -> SCNVector3 in
                    let local = block.convertPosition(point,from:node)
                    let distance = side == "left" ? box.width/2-local.x:local.x+box.width/2
                    let span = max(box.width*0.32,box.length*2)
                    let t = min(1,max(0,distance/span))
                    let weight = (1-t)*(1-t)*(1+2*t)*progress
                    let fraction = sheet ? CGFloat(1):min(1,max(0,(local.z+box.length/2)/max(box.length,0.0001)))
                    var world = node.convertPosition(point,to:root)
                    world.x += delta.x*weight*fraction
                    world.z += delta.z*weight*fraction
                    // Supporting board contact is authoritative. Thin sheets
                    // must not be pulled through it by the gutter depression.
                    var posed = block.convertPosition(world,from:root)
                    posed.z = max(posed.z,-box.length/2+0.001)
                    world = block.convertPosition(posed,to:root)
                    if !sheet, !profile.isEmpty {
                        let posed = block.convertPosition(world,from:root)
                        var topZ = profile.last!.z
                        if posed.x <= profile[0].x { topZ = profile[0].z }
                        else {
                            for i in 1..<profile.count where posed.x <= profile[i].x {
                                let a=profile[i-1],b=profile[i]
                                let u=(posed.x-a.x)/max(b.x-a.x,0.00001)
                                topZ=a.z+(b.z-a.z)*u;break
                            }
                        }
                        let upper = block.convertPosition(SCNVector3(posed.x,posed.y,topZ),to:root)
                        var constrained = block.convertPosition(world,from:root)
                        let upperLocal = block.convertPosition(upper,from:root)
                        constrained.z = max(-box.length/2+0.001,min(constrained.z,upperLocal.z-0.002))
                        if node.name?.contains("endpaper") == true { constrained.z = -box.length/2+0.001 }
                        world = block.convertPosition(constrained,to:root)
                    }
                    if !sheet, node.name?.contains("endpaper") == true {
                        var pasted = block.convertPosition(world,from:root)
                        pasted.z = -box.length/2+0.001
                        world = block.convertPosition(pasted,to:root)
                    }
                    // The visible paper underside and pasted lining share the
                    // actual stock surface. The old bowed lower lattice could
                    // float even while its invisible support box touched.
                    let bottom = node.name?.contains("page-volume") == true && index < original.count/2
                    if bottom || node.name?.contains("endpaper") == true {
                        world = pastedLining(world,side:side)
                    }
                    return node.convertPosition(contact(world),from:root)
                }
                let mesh = SCNGeometry(sources:[SCNGeometrySource(vertices:result)]+geometry.sources.filter{$0.semantic != .vertex && $0.semantic != .normal},elements:geometry.elements)
                mesh.materials=geometry.materials;node.geometry=mesh
            }
            if let page { deform(page,sheet:true) }
            if let page, let source = page.geometry?.sources(for:.vertex).first {
                let points=vertices(source)
                profile=stride(from:0,to:points.count,by:2).map { block.convertPosition(points[$0],from:page) }.sorted{$0.x < $1.x}
            }
            page?.enumerateChildNodes { node,_ in
                if node.name?.contains("visible-leaf") == true { deform(node,sheet:true) }
            }
            block.enumerateChildNodes { node,_ in deform(node,sheet:false) }
        }
    }
    static func contactSurfaces(in root: SCNNode) -> [(SCNNode,Bool,[SCNVector3]?)] {
        return ["front","back"].compactMap { name -> (SCNNode,Bool,[SCNVector3]?)? in
            guard let node = root.childNode(withName:"book-shell.\(name)-cover",recursively:true) else { return nil }
            let points = (node.geometry as? SCNBox) == nil
                ? node.geometry?.sources(for:.vertex).first.map(vertices) : nil
            return (node,name == "front",points)
        }
    }
    static func contact(_ worldPoint: SCNVector3, root: SCNNode, covers: [(SCNNode,Bool,[SCNVector3]?)]) -> SCNVector3 {
            var world = worldPoint
            // Each manuscript/volume vertex belongs inside the posed boards.
            // Project onto their lining faces, including the opposite board;
            // own-stack clipping alone lets a thick stack pierce the other
            // cover during an acute opening. Both faces use cover-local normals.
            for _ in 0..<12 {
                var changed = false
                for (cover,front,points) in covers {
                    let b = cover.geometry?.boundingBox ?? cover.boundingBox
                    var p = cover.convertPosition(world,from:root)
                    guard p.x > b.min.x, p.x < b.max.x,
                          p.y >= b.min.y, p.y <= b.max.y else { continue }
                    var lining = front ? b.min.z : b.max.z
                    if let points, points.count == 100 {
                        let u = min(24,max(0,(p.x-b.min.x)/(b.max.x-b.min.x)*24))
                        let i = min(23,Int(u)), t = u-CGFloat(i), offset = front ? 50:0
                        lining = points[i*2+offset].z + (points[(i+1)*2+offset].z-points[i*2+offset].z)*t
                    }
                    if front && p.z > lining-0.001 {
                        p.z = lining-0.001; changed = true
                    } else if !front && p.z < lining+0.001 {
                        p.z = lining+0.001; changed = true
                    } else { continue }
                    world = cover.convertPosition(p,to:root)
                }
                if !changed { break }
            }
            return world
        }

    /// SceneKit primitives expose a normalized unit mesh through sources,
    /// while their renderer uses the requested dimensions. Contact/resting
    /// measurements must use those dimensions instead of a phantom unit slab.
    static func surfaceVertices(_ geometry: SCNGeometry) -> [SCNVector3] {
        let b=geometry.boundingBox
        if geometry is SCNPlane {
            return [SCNVector3(b.min.x,b.min.y,0),SCNVector3(b.max.x,b.min.y,0),
                SCNVector3(b.min.x,b.max.y,0),SCNVector3(b.max.x,b.max.y,0)]
        }
        if geometry is SCNBox {
            return [b.min.x,b.max.x].flatMap { x in
                [b.min.y,b.max.y].flatMap { y in
                    [b.min.z,b.max.z].map { z in SCNVector3(x,y,z) }
                }
            }
        }
        return geometry.sources(for:.vertex).first.map(vertices) ?? []
    }

    static func vertices(_ source: SCNGeometrySource) -> [SCNVector3] {
        source.data.withUnsafeBytes { bytes in
            (0..<source.vectorCount).map { n in
                let at=source.dataOffset+n*source.dataStride
                return SCNVector3(bytes.loadUnaligned(fromByteOffset:at,as:Float.self),bytes.loadUnaligned(fromByteOffset:at+4,as:Float.self),bytes.loadUnaligned(fromByteOffset:at+8,as:Float.self))
            }
        }
    }
}
