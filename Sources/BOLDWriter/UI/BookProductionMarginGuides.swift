import AppKit
import SceneKit

/// Production margins are diagnostic guides, never extra material on the finished book.
/// Parenting to the actual board keeps them attached through opening and orbiting.
enum BookProductionMarginGuides {
    static let prefix = "production-margin."
    static func add(to root: SCNNode, project: CoverProject, visible: Bool) {
        let wrap=CoverWrapGeometry(project:project)
        for (name,trim,outer) in [("front",wrap.frontTrim,wrap.front),("back",wrap.backTrim,wrap.back)] {
            guard let board=root.childNode(withName:"book-shell."+name+"-cover",recursively:true),trim.width>0,trim.height>0 else {continue}
            let b=board.boundingBox
            let width=Double(b.max.x-b.min.x),height=Double(b.max.y-b.min.y)
            let extraX=max(0,(outer.width/trim.width-1)*width)
            let extraY=max(0,(outer.height/trim.height-1)*height/2)
            guard extraX>0 || extraY>0 else {continue}
            let x0=b.min.x,x1=b.max.x+CGFloat(extraX),y0=b.min.y-CGFloat(extraY),y1=b.max.y+CGFloat(extraY)
            let z=b.max.z+0.003
            let vertices=[SCNVector3(x0,y0,z),SCNVector3(x1,y0,z),SCNVector3(x1,y1,z),SCNVector3(x0,y1,z)]
            let element=SCNGeometryElement(indices:[Int32(0),1,1,2,2,3,3,0],primitiveType:.line)
            let geometry=SCNGeometry(sources:[SCNGeometrySource(vertices:vertices)],elements:[element])
            let material=SCNMaterial();material.diffuse.contents=NSColor.systemOrange;material.emission.contents=NSColor.systemOrange;material.lightingModel = .constant;material.isDoubleSided=true
            geometry.materials=[material]
            let node=SCNNode(geometry:geometry);node.name=prefix+name;node.isHidden = !visible;node.castsShadow=false
            board.addChildNode(node)
        }
    }
    static func setVisible(_ visible: Bool, in root: SCNNode) {
        root.enumerateChildNodes {node,_ in if node.name?.hasPrefix(prefix)==true {node.isHidden = !visible} }
    }
}
