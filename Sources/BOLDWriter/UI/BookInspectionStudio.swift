import AppKit
import SceneKit

/// Session-only inspection. Never encoded in a CoverProject or print output.
struct BookInspectionState: Equatable {
    var danger = false
    var anatomy = false
    var explosion = 0.0
    var transparency = 0.0
    var isolated: BookSceneComponent?
    var hidden: Set<BookSceneComponent> = []
}

enum BookPrintDangerSeverity: String, CaseIterable {
    case major = "Major", likely = "Likely", review = "Review"
    var color: NSColor {
        switch self { case .major: return .systemRed; case .likely: return .systemOrange; case .review: return .systemYellow }
    }
}

struct BookPrintDanger: Identifiable {
    let id: String
    let severity: BookPrintDangerSeverity
    let component: BookSceneComponent
    let message: String
    let correction: String

    static func inspect(project: CoverProject, binding: BookBinding, pageCount: Int, edgeIssues: [PhysicalBookCoverEdgeIssue] = []) -> [Self] {
        var result: [Self] = []
        func add(_ severity: BookPrintDangerSeverity, _ component: BookSceneComponent, _ message: String, _ correction: String) {
            result.append(Self(id: "\(component)-\(message)", severity: severity, component: component, message: message, correction: correction))
        }
        if let original = project.productionBinding, original != binding {
            add(.likely, .spine, "Artwork template: \(original.rawValue); preview construction: \(binding.rawValue).", "Match Original Cover, or create a separate cover using the target manufacturer's template. Preview does not repair wrap or hinge registration.")
        }
        if let expected = PhysicalBookDiagnostics.expectedSpineMismatch(project: project, manuscriptPages: pageCount) {
            add(.likely, .spine, String(format: "Calculated paper spine %.5f in; artwork spine %.5f in.", expected + project.spineWidth, project.spineWidth), "Review page count and paper caliper before changing production dimensions.")
        }
        for issue in PhysicalBookDiagnostics.coverImageResolutionIssues(project: project) {
            for region in issue.regions {
                let component: BookSceneComponent = region == .front ? .front : region == .back ? .back : .spine
                add(issue.severity == .low ? .likely : .review, component, issue.message, "Use a higher-resolution source or reduce its printed size.")
            }
        }
        for issue in PhysicalBookDiagnostics.coverContentSafeIssues(project: project) {
            add(.review, issue.panel == .front ? .front : .back, issue.message, "Move essential content inside the production safe area; background artwork may intentionally cross it.")
        }
        for issue in PhysicalBookDiagnostics.spineTextIssues(project: project) {
            add(.review, .spine, issue.message, "Review spine text size and fold clearance in Cover Creator.")
        }
        for issue in edgeIssues {
            add(.review, issue.panel == .front ? .front : .back, issue.message, "Extend the background through bleed and inspect the printable full wrap.")
        }
        return result
    }
}

/// Links the existing camera controllers, not a second orbit implementation.
/// Weak owners prevent a discarded comparison viewport retaining its scene.
final class BookInspectionCameraLink {
    var enabled = true
    private struct Endpoint {
        weak var owner: AnyObject?
        let receive: (BookPreviewCameraState, Bool) -> Void
    }
    private var endpoints: [ObjectIdentifier: Endpoint] = [:]
    func register(_ owner: AnyObject, receive: @escaping (BookPreviewCameraState, Bool) -> Void) {
        endpoints = endpoints.filter { $0.value.owner != nil }
        endpoints[ObjectIdentifier(owner)] = Endpoint(owner: owner, receive: receive)
    }
    func unregister(_ owner: AnyObject) {
        endpoints.removeValue(forKey: ObjectIdentifier(owner))
    }
    func send(from owner: AnyObject, state: BookPreviewCameraState, commit: Bool = false) {
        endpoints = endpoints.filter { $0.value.owner != nil }
        guard enabled else { return }
        for (key, endpoint) in endpoints where key != ObjectIdentifier(owner) { endpoint.receive(state, commit) }
    }
}

/// Inspection offsets are always relative to exact assembled node transforms.
/// Geometry, UVs and shared artwork materials are never mutated.
enum BookInspectionScene {
    private final class Active: NSObject {
        let state: BookInspectionState
        let issues: [BookPrintDanger]
        init(_ state: BookInspectionState, _ issues: [BookPrintDanger]) { self.state = state; self.issues = issues }
    }
    static func suspend(_ scene: SCNScene) -> () -> Void {
        guard let active = scene.rootNode.value(forKey: "inspectionActive") as? Active else { return {} }
        apply(BookInspectionState(), to: scene, issues: [])
        return { apply(active.state, to: scene, issues: active.issues) }
    }

    private final class Original: NSObject {
        let position: SCNVector3
        let opacity: CGFloat
        let hidden: Bool
        init(_ node: SCNNode) { position = node.position; opacity = node.opacity; hidden = node.isHidden }
    }
    static func component(_ name: String) -> BookSceneComponent? {
        if name.hasPrefix("book-shell.front") { return .front }
        if name.hasPrefix("book-shell.back") { return .back }
        if name.hasPrefix("book-shell.spine") { return .spine }
        if name == "book.left-active-page" { return .leftPage }
        if name == "book.right-active-page" { return .rightPage }
        if name.hasPrefix("book.") { return .pages }
        return nil
    }
    static func apply(_ state: BookInspectionState, to scene: SCNScene, issues: [BookPrintDanger]) {
        scene.rootNode.setValue(Active(state, issues), forKey: "inspectionActive")
        var overlays: [SCNNode] = []
        scene.rootNode.enumerateChildNodes { node, _ in
            if node.name == "diagnostic.inspection" { overlays.append(node) }
        }
        overlays.forEach { $0.removeFromParentNode() }
        scene.rootNode.enumerateChildNodes { node, _ in
            guard let name = node.name, let part = component(name) else { return }
            let original: Original
            if let stored = node.value(forKey: "inspectionOriginal") as? Original { original = stored }
            else {
                original = Original(node)
                if state.anatomy { node.setValue(original, forKey: "inspectionOriginal") }
            }
            node.position = original.position; node.opacity = original.opacity; node.isHidden = original.hidden
            if !state.anatomy { node.setValue(nil, forKey: "inspectionOriginal") }
            if state.anatomy {
                var containsSelection = false
                if let isolated = state.isolated {
                    node.enumerateChildNodes { child, stop in
                        if child.name.flatMap(component) == isolated { containsSelection = true; stop.pointee = true }
                    }
                }
                node.isHidden = original.hidden || state.hidden.contains(part) || (state.isolated != nil && state.isolated != part && !containsSelection)
                // Only move the outermost named component: children inherit the
                // offset, so lining, artwork and boards remain registered.
                if node.parent?.name.flatMap(component) != part {
                    let amount = state.explosion.isFinite ? min(1, max(0, state.explosion)) : 0
                    switch part {
                    case .front: node.position.z += CGFloat(amount * 0.65)
                    case .back: node.position.z -= CGFloat(amount * 0.65)
                    case .spine: node.position.x -= CGFloat(amount * 0.65)
                    case .leftPage: node.position.y += CGFloat(amount * 0.35)
                    case .rightPage: node.position.y += CGFloat(amount * 0.45)
                    default: break
                    }
                }
                let transparency = state.transparency.isFinite ? min(0.85, max(0, state.transparency)) : 0
                if node.parent?.name.flatMap(component) != part { node.opacity = original.opacity * (1 - transparency) }
            }
            guard state.danger, node.geometry != nil,
                  let issue = issues.first(where: { $0.component == part }),
                  node.parent?.name.flatMap(component) != part else { return }
            // A separate wire overlay follows the actual physical mesh. It is
            // diagnostic-only and is excluded by the existing export filter.
            let overlay = SCNNode(geometry: node.geometry?.copy() as? SCNGeometry)
            overlay.name = "diagnostic.inspection"
            let material = SCNMaterial()
            material.diffuse.contents = issue.severity.color
            material.emission.contents = issue.severity.color
            material.lightingModel = .constant; material.fillMode = .lines
            material.isDoubleSided = true; material.readsFromDepthBuffer = false
            material.writesToDepthBuffer = false
            overlay.geometry?.materials = [material]; overlay.renderingOrder = 100
            node.addChildNode(overlay)
        }
    }
}
