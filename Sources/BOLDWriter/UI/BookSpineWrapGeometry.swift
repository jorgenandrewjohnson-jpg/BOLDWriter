import SceneKit

/// Printed binding strip joining the exterior hinge edges of the posed covers.
/// U runs from the canonical back fold to the front fold; V follows cover height.
enum BookSpineWrapGeometry {
    static func update(in root: SCNNode, depth: CGFloat) {
        guard let strip = root.childNode(withName:"book-shell.spine-artwork",recursively:false),
              let front = root.childNode(withName:"book-shell.front-cover",recursively:false),
              let back = root.childNode(withName:"book-shell.back-cover",recursively:false),
              let material = strip.geometry?.firstMaterial else { return }
        func edge(_ cover: SCNNode, exterior: CGFloat, top: Bool) -> SCNVector3 {
            let b = cover.geometry?.boundingBox ?? cover.boundingBox
            return cover.convertPosition(SCNVector3(b.min.x,top ? b.max.y:b.min.y,exterior),to:root)
        }
        func exterior(_ cover: SCNNode, front: Bool) -> CGFloat {
            let b = cover.geometry?.boundingBox ?? cover.boundingBox
            return front ? b.max.z+0.001:b.min.z-0.001
        }
        let bz = exterior(back,front:false), fz = exterior(front,front:true)
        let b0 = edge(back,exterior:bz,top:false), b1 = edge(back,exterior:bz,top:true)
        let f0 = edge(front,exterior:fz,top:false), f1 = edge(front,exterior:fz,top:true)
        let fn = front.convertVector(SCNVector3(0,0,1),to:root)
        let bn = back.convertVector(SCNVector3(0,0,-1),to:root)
        var nx = CGFloat(fn.x+bn.x), nz = CGFloat(fn.z+bn.z)
        let length = hypot(nx,nz)
        if length < 0.001 { nx = -1; nz = 0 } else { nx /= length; nz /= length }
        let segments = 32
        let backFloor = back.geometry.map { geometry in
            BookOpenGutterGeometry.surfaceVertices(geometry).map { back.convertPosition($0,to:root).z }.min()
        } ?? nil
        // Keep the true printed fold endpoints, including the small exterior
        // skin offset. The rest of the wrap cannot prop up the supporting case.
        let restingPlane = min(backFloor ?? b0.z,b0.z,f0.z)
        // Binding cloth keeps its material width as the hinges approach one
        // another. A fixed shallow bow compressed the print in open poses.
        func point(_ t: CGFloat, bow: CGFloat) -> SCNVector3 {
            let bump = 4*t*(1-t)*bow
            return SCNVector3(CGFloat(b0.x)*(1-t)+CGFloat(f0.x)*t+nx*bump,
                              CGFloat(b0.y)*(1-t)+CGFloat(f0.y)*t,
                              max(restingPlane,CGFloat(b0.z)*(1-t)+CGFloat(f0.z)*t+nz*bump))
        }
        func distance(_ a: SCNVector3, _ b: SCNVector3) -> CGFloat {
            hypot(hypot(CGFloat(a.x-b.x),CGFloat(a.y-b.y)),CGFloat(a.z-b.z))
        }
        func materialWidth(_ bow: CGFloat) -> CGFloat {
            var total: CGFloat = 0, previous = point(0,bow:bow)
            for i in 1...segments {
                let next = point(CGFloat(i)/CGFloat(segments),bow:bow)
                total += distance(previous,next); previous = next
            }
            return total
        }
        let target = max(depth,distance(b0,f0))
        var low: CGFloat = 0, high = max(target,0.002)
        let straightWidth = materialWidth(0)
        if abs(straightWidth-target) < 0.0000005 {
            high = 0
        } else {
            // Resting-plane contact removes the downward part of the bow.
            // Bracket the remaining fold before solving its conserved width.
            for _ in 0..<12 where materialWidth(high) < target { high *= 2 }
            for _ in 0..<32 {
                let middle = (low+high)/2
                if materialWidth(middle) < target { low = middle } else { high = middle }
            }
        }
        let bow = (low+high)/2, width = materialWidth(bow)
        var travelled: CGFloat = 0, previous = point(0,bow:bow)
        var vertices:[SCNVector3] = [], uv:[CGPoint] = [], indices:[UInt32] = []
        for i in 0...segments {
            let t = CGFloat(i)/CGFloat(segments), bump = 4*t*(1-t)*bow
            let next = point(t,bow:bow)
            travelled += distance(previous,next); previous = next
            for (a,b,v) in [(b0,f0,CGFloat(0)),(b1,f1,CGFloat(1))] {
                vertices.append(SCNVector3(CGFloat(a.x)*(1-t)+CGFloat(b.x)*t+nx*bump,
                                          CGFloat(a.y)*(1-t)+CGFloat(b.y)*t,
                                          next.z))
                uv.append(CGPoint(x:width > 0 ? travelled/width:t,y:v))
            }
            if i < segments {
                let n = UInt32(i*2)
                indices += [n,n+2,n+1,n+1,n+2,n+3]
            }
        }
        var reverse: [UInt32] = []
        for i in stride(from:0,to:indices.count,by:3) { reverse += [indices[i],indices[i+2],indices[i+1]] }
        let mesh = SCNGeometry(sources:[SCNGeometrySource(vertices:vertices),SCNGeometrySource(textureCoordinates:uv)],
            elements:[SCNGeometryElement(indices:indices,primitiveType:.triangles),
                SCNGeometryElement(indices:reverse,primitiveType:.triangles)])
        // The printed case is exterior artwork. Its inward face is binding
        // lining, not a second copy of the gold/title artwork visible in Reading.
        material.isDoubleSided = false
        let lining = SCNMaterial()
        lining.diffuse.contents = NSColor(calibratedRed:0.91,green:0.89,blue:0.83,alpha:1)
        lining.isDoubleSided = false; lining.lightingModel = .physicallyBased
        lining.roughness.contents = 0.96
        mesh.materials = [material,lining]
        strip.geometry = mesh; strip.transform = SCNMatrix4Identity; strip.isHidden = false
        // Paperback paper is glued to its printed spine. Close the head and
        // foot between the existing wrap and the actual bound page edges;
        // otherwise the curved wrap reads as a detached ribbon from edge views.
        root.childNode(withName:"book.page-block-spine-page-volume",recursively:false)?.removeFromParentNode()
        if !(front.geometry is SCNBox) {
            var bound: [(SCNVector3,SCNVector3)] = []
            for side in ["left","right"] {
                guard let page=root.childNode(withName:"book.\(side)-active-page",recursively:true),
                    let source=page.geometry?.sources(for:.vertex).first else { continue }
                let points=BookOpenGutterGeometry.vertices(source)
                guard points.count>=2 else { continue }
                let i=side == "left" ? points.count-2:0
                bound.append((page.convertPosition(points[i],to:root),page.convertPosition(points[i+1],to:root)))
            }
            if !bound.isEmpty {
                func mean(_ top: Bool) -> SCNVector3 {
                    let count=CGFloat(bound.count)
                    return bound.reduce(SCNVector3Zero) { sum,pair in
                        let p=top ? pair.1:pair.0
                        return SCNVector3(sum.x+p.x/count,sum.y+p.y/count,sum.z+p.z/count)
                    }
                }
                var capPoints=vertices
                capPoints += [mean(false),mean(true)]
                var caps: [UInt32] = []
                let bottomCenter=UInt32(vertices.count),topCenter=bottomCenter+1
                for i in 0..<segments {
                    let n=UInt32(i*2)
                    caps += [bottomCenter,n+2,n,topCenter,n+1,n+3]
                }
                let paper=SCNMaterial()
                paper.diffuse.contents=NSColor(calibratedRed:0.96,green:0.95,blue:0.91,alpha:1)
                paper.lightingModel = .physicallyBased; paper.roughness.contents=0.985
                paper.isDoubleSided=true
                let contacts=BookOpenGutterGeometry.contactSurfaces(in:root)
                capPoints=capPoints.map { BookOpenGutterGeometry.contact($0,root:root,covers:contacts) }
                let cap=SCNGeometry(sources:[SCNGeometrySource(vertices:capPoints)],
                    elements:[SCNGeometryElement(indices:caps,primitiveType:.triangles)])
                cap.materials=[paper]
                let node=SCNNode(geometry:cap); node.name="book.page-block-spine-page-volume"
                root.addChildNode(node)
            }
        }
        // Fold warnings were created in the closed plane's local coordinates.
        // Once that plane becomes a book-local mesh, leaving its children in
        // the old frame creates a protruding tip and corrupts resting bounds.
        for warning in strip.childNodes where warning.name?.hasPrefix("diagnostic.spine.") == true {
            let plane = warning.geometry as? SCNPlane
            let warningWidth = (warning.value(forKey:"spineWarningWidth") as? NSNumber)?.doubleValue ?? Double(plane?.width ?? 0)
            let warningHeight = (warning.value(forKey:"spineWarningHeight") as? NSNumber)?.doubleValue ?? Double(plane?.height ?? 0)
            guard warningWidth > 0, warningHeight > 0 else { continue }
            warning.setValue(warningWidth,forKey:"spineWarningWidth")
            warning.setValue(warningHeight,forKey:"spineWarningHeight")
            let fraction = min(1,CGFloat(warningWidth)/max(width,0.00001))
            let start: CGFloat = warning.name?.hasSuffix("left-fold") == true ? 0:1-fraction
            var points: [SCNVector3] = [], triangles: [UInt32] = []
            for row in 0...segments {
                let u = start + fraction*CGFloat(row)/CGFloat(segments)
                let upper = (1...segments).first { uv[$0*2].x >= u } ?? segments
                let lower = upper-1
                let blend = (u-uv[lower*2].x)/max(0.00001,uv[upper*2].x-uv[lower*2].x)
                let bottom = vertices[lower*2], top = vertices[lower*2+1]
                let centerY = (bottom.y+top.y)/2
                for edge in 0...1 {
                    let a=vertices[lower*2+edge],b=vertices[upper*2+edge]
                    points.append(SCNVector3(a.x+(b.x-a.x)*blend+nx*0.001,
                        centerY + (edge == 0 ? -1:1)*CGFloat(warningHeight)/2,
                        a.z+(b.z-a.z)*blend+nz*0.001))
                }
                if row < segments {
                    let n=UInt32(row*2); triangles += [n,n+2,n+1,n+1,n+2,n+3]
                }
            }
            let diagnostic = SCNGeometry(sources:[SCNGeometrySource(vertices:points)],
                elements:[SCNGeometryElement(indices:triangles,primitiveType:.triangles)])
            diagnostic.materials = warning.geometry?.materials ?? []
            warning.geometry = diagnostic; warning.transform = SCNMatrix4Identity
        }
        // The printed mesh replaces the closed rectangular spine in open poses.
        root.childNode(withName:"book-shell.spine",recursively:false)?.isHidden = true
    }
}
