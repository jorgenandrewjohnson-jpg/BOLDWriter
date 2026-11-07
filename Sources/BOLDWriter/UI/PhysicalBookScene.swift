import AppKit
import PDFKit
import SceneKit
import SwiftUI

enum BookViewPreset: String, Codable, CaseIterable, Identifiable { case front = "Front", spine = "Spine", back = "Back", top = "Top", perspective = "Three-Quarter Front", threeQuarterBack = "Three-Quarter Back", reading = "Reading", underside = "Underside", headEdge = "Head Edge", footEdge = "Foot Edge", foreEdge = "Fore Edge", lowPerspective = "Low Three-Quarter"; var id: String { rawValue } }

// BOLD WRITER — shared camera resolution for native Studio commands.
// This leaves persisted camera values and existing enum cases unchanged.
extension BookViewPreset {
    private static func studioCameraKey(_ input: String) -> String {
        input
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .filter { $0.isLetter || $0.isNumber }
    }

    static var studioCameraChoices: [String] {
        allCases.map(\.rawValue)
    }

    static func fromStudioCameraInput(_ input: String) -> Self? {
        let key = studioCameraKey(input)
        guard !key.isEmpty else { return nil }

        switch key {
        case "head", "headedge", "topedge":
            return .headEdge
        case "foot", "footedge", "bottomedge":
            return .footEdge
        case "fore", "foreedge", "pageedge", "pagesedge":
            return .foreEdge
        case "low", "lowangle", "lowperspective", "lowthreequarter":
            return .lowPerspective
        case "threequarterfront", "frontthreequarter",
             "diagonalfront", "3quarterfront":
            return .perspective
        case "threequarterback", "backthreequarter",
             "diagonalback", "3quarterback":
            return .threeQuarterBack
        case "below", "bottom", "underneath":
            return .underside
        default:
            break
        }

        return allCases.first {
            studioCameraKey($0.rawValue) == key ||
            studioCameraKey(String(describing: $0)) == key
        }
    }
}

enum BookFocusTarget: String, CaseIterable, Identifiable { case automatic = "Fit", front = "Front", spine = "Spine", back = "Back", spread = "Spread", text = "Text"; var id: String { rawValue } }
enum CameraZoomAction: Equatable { case `in`, out, fit }
struct BookPreviewCameraState: Equatable {
    var yaw: Double
    var pitch: Double
    var distance: Double
    var target: SIMD3<Double> = .zero
    init(yaw: Double, pitch: Double, distance: Double, target: SIMD3<Double> = .zero) {
        self.yaw = yaw; self.pitch = pitch; self.distance = distance; self.target = target
    }
    init(saved: BookSavedCamera) {
        self.init(yaw: saved.yaw, pitch: saved.pitch, distance: saved.distance,
                  target: SIMD3(saved.targetX, saved.targetY, saved.targetZ))
    }
    var saved: BookSavedCamera {
        BookSavedCamera(yaw: yaw, pitch: pitch, distance: distance,
                        targetX: target.x, targetY: target.y, targetZ: target.z)
    }
    mutating func orbit(deltaX: Double, deltaY: Double) {
        // Reject invalid pointer movement before it can poison SceneKit.
        guard deltaX.isFinite, deltaY.isFinite,
              yaw.isFinite, pitch.isFinite else { return }

        let horizontalStep = deltaX * 0.008
        let verticalStep = deltaY * 0.008
        guard horizontalStep.isFinite, verticalStep.isFinite else { return }

        let nextYaw = yaw + horizontalStep
        let nextPitch = pitch + verticalStep
        guard nextYaw.isFinite, nextPitch.isFinite else { return }

        // Keep accumulated yaw bounded during extended book inspection.
        yaw = nextYaw.truncatingRemainder(dividingBy: 2 * Double.pi)
        pitch = min(1.52, max(-1.52, nextPitch))
    }
    mutating func zoom(by factor: Double, minimum: Double, maximum: Double) {
        guard factor.isFinite, factor > 0,
              minimum.isFinite, maximum.isFinite else { return }

        let lower = max(0.001, minimum)
        let upper = max(lower, maximum)
        let validDistance = distance.isFinite && distance > 0
            ? distance : lower
        let proposedDistance = validDistance * factor

        // Recover invalid state and clamp overflow instead of sending
        // an infinite camera distance to the renderer.
        guard proposedDistance.isFinite else {
            distance = upper
            return
        }
        distance = min(upper, max(lower, proposedDistance))
    }
    mutating func pan(deltaX: Double, deltaY: Double, viewportHeight: Double,
                      fieldOfView: Double = 34) {
        // Navigation must never create a nonfinite camera target.
        guard deltaX.isFinite, deltaY.isFinite,
              viewportHeight.isFinite, fieldOfView.isFinite,
              fieldOfView > 0, fieldOfView < 180,
              distance.isFinite, distance > 0,
              yaw.isFinite, pitch.isFinite,
              target.x.isFinite, target.y.isFinite,
              target.z.isFinite else { return }

        let unitsPerPoint = 2 * distance
            * tan(fieldOfView * .pi / 360)
            / max(1, viewportHeight)
        guard unitsPerPoint.isFinite else { return }

        let horizontalAmount = deltaX * unitsPerPoint
        let verticalAmount = deltaY * unitsPerPoint
        guard horizontalAmount.isFinite,
              verticalAmount.isFinite else { return }

        let horizontal = SIMD3(cos(yaw), 0, -sin(yaw))
        let vertical = SIMD3(
            -sin(pitch) * sin(yaw),
            cos(pitch),
            -sin(pitch) * cos(yaw)
        )

        // Commit both axes together, only if the entire result is valid.
        let nextTarget = target
            - horizontal * horizontalAmount
            - vertical * verticalAmount
        guard nextTarget.x.isFinite, nextTarget.y.isFinite,
              nextTarget.z.isFinite else { return }

        target = nextTarget
    }
}

enum BookPreviewCameraMath {
    /// Immutable world-space bounds captured while a newly built scene is
    /// still private to the main thread. SceneKit's live `boundingBox` getter
    /// traverses geometry and is unsafe to call from view-resize callbacks
    /// while page-turn actions are changing the scene graph.
    struct BoundsSnapshot {
        private let localCorners: [SIMD3<Double>]
        let minimum: SIMD3<Double>
        let maximum: SIMD3<Double>

        static func capture(modelRoot: SCNNode?) -> BoundsSnapshot? {
            guard let modelRoot else { return nil }
            SCNTransaction.lock()
            defer { SCNTransaction.unlock() }
            let bounds = modelRoot.boundingBox
            guard bounds.min.x.isFinite, bounds.min.y.isFinite, bounds.min.z.isFinite,
                  bounds.max.x.isFinite, bounds.max.y.isFinite, bounds.max.z.isFinite,
                  bounds.min.x <= bounds.max.x, bounds.min.y <= bounds.max.y,
                  bounds.min.z <= bounds.max.z else { return nil }
            let localCorners = [bounds.min.x, bounds.max.x].flatMap { x in
                [bounds.min.y, bounds.max.y].flatMap { y in
                    [bounds.min.z, bounds.max.z].map { z in SIMD3(Double(x), Double(y), Double(z)) }
                }
            }
            return BoundsSnapshot(localCorners: localCorners, applying: modelRoot.transform)
        }

        private init(localCorners: [SIMD3<Double>], applying transform: SCNMatrix4) {
            self.localCorners = localCorners
            let transformed = localCorners.map { Self.transform($0, by: transform) }
            minimum = SIMD3(transformed.map { $0.x }.min() ?? 0,
                            transformed.map { $0.y }.min() ?? 0,
                            transformed.map { $0.z }.min() ?? 0)
            maximum = SIMD3(transformed.map { $0.x }.max() ?? 0,
                            transformed.map { $0.y }.max() ?? 0,
                            transformed.map { $0.z }.max() ?? 0)
        }

        private static func transform(_ point: SIMD3<Double>, by matrix: SCNMatrix4) -> SIMD3<Double> {
            SIMD3(
                point.x * Double(matrix.m11) + point.y * Double(matrix.m21) + point.z * Double(matrix.m31) + Double(matrix.m41),
                point.x * Double(matrix.m12) + point.y * Double(matrix.m22) + point.z * Double(matrix.m32) + Double(matrix.m42),
                point.x * Double(matrix.m13) + point.y * Double(matrix.m23) + point.z * Double(matrix.m33) + Double(matrix.m43)
            )
        }

        /// Reproject the already captured local box through a changed root
        /// matrix. This preserves camera behavior for Studio transforms while
        /// avoiding another geometry or descendant traversal.
        func applying(_ transform: SCNMatrix4) -> BoundsSnapshot {
            BoundsSnapshot(localCorners: localCorners, applying: transform)
        }

        var corners: [SIMD3<Double>] {
            [minimum.x, maximum.x].flatMap { x in
                [minimum.y, maximum.y].flatMap { y in
                    [minimum.z, maximum.z].map { z in SIMD3(x, y, z) }
                }
            }
        }
    }

    static func state(project: CoverProject, open: Bool, preset: BookViewPreset, focus: BookFocusTarget) -> BookPreviewCameraState {
        let geometry = PhysicalBookGeometry(project: project), scale = 0.7
        let width = geometry.trimWidth * scale, height = geometry.trimHeight * scale
        let spread = open && (focus == .automatic || focus == .spread || focus == .text)
        let targetX: Double = (!open && focus != .spine) || (focus == .text && open) ? width / 2 : 0
        // BOLD WRITER V13 — tabletop Reading camera target
        // Match the Reading model's -90° X rotation: (0, h/2, 0) -> (0, 0, -h/2).
        let readingTabletop = open && (preset == .reading || preset == .underside || preset == .headEdge || preset == .footEdge || preset == .foreEdge || preset == .lowPerspective)
        let targetY: Double = readingTabletop ? 0 : height / 2
        let targetZ: Double = readingTabletop ? -height / 2 : 0
        let framing = spread ? max(width * 2, height) : max(width, height)
        let distance = focus == .spine ? max(1.8, height * 1.7) : max(1.8, framing * (focus == .text ? 1.2 : 2.1))
        let yaw: Double, pitch: Double
        switch focus {
        case .front: yaw = 0; pitch = 0.12
        case .spine: yaw = -.pi / 2; pitch = 0
        case .back: yaw = .pi; pitch = 0.12
        case .spread, .text: yaw = 0; pitch = 0.42
        case .automatic:
            switch preset {
            case .front: yaw = 0; pitch = 0.1
            case .spine: yaw = -.pi / 2; pitch = 0.08
            case .back: yaw = .pi; pitch = 0.1
            case .top: yaw = 0; pitch = 1.48
            case .underside: yaw = 0.22; pitch = -1.48
            // Additional true edge and low-angle inspection cameras.
            // Open books lie on the tabletop; closed books stand upright.
            case .headEdge:
                yaw = open ? .pi : 0
                pitch = open ? 0.12 : 1.48
            case .footEdge:
                yaw = 0
                pitch = open ? 0.12 : -1.48
            case .foreEdge:
                yaw = .pi / 2
                pitch = open ? 0.18 : 0.10
            case .lowPerspective:
                yaw = 0.75
                pitch = 0.24
            case .perspective: yaw = 0.75; pitch = 0.72
            case .threeQuarterBack: yaw = 2.4; pitch = 0.6
            case .reading: yaw = 0.22; pitch = 0.92
            }
        }
        return BookPreviewCameraState(yaw: yaw, pitch: pitch, distance: distance, target: SIMD3(targetX, targetY, targetZ))
    }

    /// Keep an orbiting camera outside the posed book for every yaw/pitch.
    /// Using a fixed tiny minimum let zoom enter the paper and clip the model.
    static func minimumOrbitDistance(in scene: SCNScene?, target: SIMD3<Double>) -> Double {
        SCNTransaction.lock()
        defer { SCNTransaction.unlock() }
        guard let root = scene?.rootNode.childNode(withName: "physical-book.root", recursively: true) else { return 0.35 }
        let b = root.boundingBox
        var radius = 0.0
        for x in [b.min.x, b.max.x] { for y in [b.min.y, b.max.y] { for z in [b.min.z, b.max.z] {
            let p = root.convertPosition(SCNVector3(x,y,z), to: nil)
            radius = max(radius, simd_length(SIMD3(Double(p.x),Double(p.y),Double(p.z)) - target))
        } } }
        return radius.isFinite ? max(0.35, radius + 0.1) : 0.35
    }

    static func minimumOrbitDistance(in bounds: BoundsSnapshot?, target: SIMD3<Double>) -> Double {
        guard let bounds else { return 0.35 }
        let radius = bounds.corners.reduce(0.0) { max($0, simd_length($1 - target)) }
        return radius.isFinite ? max(0.35, radius + 0.1) : 0.35
    }

    static func fitBook(_ state: BookPreviewCameraState, in scene: SCNScene?,
                           presentation: BookStudioPresentation, focus: BookFocusTarget = .automatic,
                           viewportAspect: Double) -> BookPreviewCameraState {
        guard focus == .automatic || focus == .spread,
              let root = scene?.rootNode.childNode(withName: BookStudioTransformScene.modelRootName, recursively: true)
        else { return state }
        return frame(root, from: state, fieldOfView: presentation.cameraFieldOfView, viewportAspect: viewportAspect)
    }

    static func fitBook(_ state: BookPreviewCameraState, bounds: BoundsSnapshot?,
                        presentation: BookStudioPresentation, focus: BookFocusTarget = .automatic,
                        viewportAspect: Double) -> BookPreviewCameraState {
        guard focus == .automatic || focus == .spread, let bounds else { return state }
        return frame(bounds, from: state, fieldOfView: presentation.cameraFieldOfView,
                     viewportAspect: viewportAspect)
    }

    static func frame(_ bounds: BoundsSnapshot, from current: BookPreviewCameraState,
                      fieldOfView: Double, viewportAspect: Double) -> BookPreviewCameraState {
        let corners = bounds.corners
        let minimum = bounds.minimum
        let maximum = bounds.maximum
        let tangent = tan(min(75, max(20, fieldOfView)) * .pi / 360)
        let aspect = max(0.1, viewportAspect)
        var framed = current
        framed.target = (minimum + maximum) / 2
        let right = SIMD3<Double>(cos(current.yaw), 0, -sin(current.yaw))
        let up = SIMD3<Double>(-sin(current.pitch) * sin(current.yaw), cos(current.pitch),
                               -sin(current.pitch) * cos(current.yaw))
        let towardCamera = SIMD3<Double>(cos(current.pitch) * sin(current.yaw), sin(current.pitch),
                                         cos(current.pitch) * cos(current.yaw))
        framed.distance = corners.reduce(0.35) { distance, corner in
            let relative = corner - framed.target
            let horizontal = abs(simd_dot(relative, right)) / (tangent * aspect)
            let vertical = abs(simd_dot(relative, up)) / tangent
            return max(distance, simd_dot(relative, towardCamera) + max(horizontal, vertical) * 1.12)
        }
        return framed
    }


    static func frame(_ node: SCNNode, from current: BookPreviewCameraState,
                      fieldOfView: Double, viewportAspect: Double) -> BookPreviewCameraState {
        guard let bounds = BoundsSnapshot.capture(modelRoot: node) else { return current }
        return frame(bounds, from: current, fieldOfView: fieldOfView, viewportAspect: viewportAspect)
    }
}


enum BookTransformAxis: String, CaseIterable {
    case x
    case y
    case z
    case uniform
}

struct BookTransformGizmoHandle: Equatable {
    let mode: BookTransformMode
    let axis: BookTransformAxis

    static func parse(
        nodeName: String
    ) -> BookTransformGizmoHandle? {
        let parts =
            nodeName.split(
                separator: "."
            )

        guard
            parts.count >= 3,
            parts[0]
                == "studio-transform-gizmo"
        else {
            return nil
        }

        let mode: BookTransformMode

        switch parts[1] {
        case "move":
            mode = .move

        case "rotate":
            mode = .rotate

        case "scale":
            mode = .scale

        default:
            return nil
        }

        guard
            let axis =
                BookTransformAxis(
                    rawValue:
                        String(
                            parts[2]
                        )
                )
        else {
            return nil
        }

        return BookTransformGizmoHandle(
            mode: mode,
            axis: axis
        )
    }
}

enum BookStudioTransformDragMath {
    static let movePointsPerUnit =
        100.0

    static let scalePointsPerUnit =
        100.0

    static let moveSnap =
        0.25

    static let rotateSnap =
        15.0

    static let scaleSnap =
        0.1

    static func applying(
        _ original: BookModelTransform,
        mode: BookTransformMode,
        axis: BookTransformAxis,
        amount: Double,
        space: BookTransformSpace,
        snapping: Bool,
        moveSnapStep: Double = moveSnap,
        rotateSnapStep: Double = rotateSnap,
        scaleSnapStep: Double = scaleSnap
    ) -> BookModelTransform {
        var result =
            original

        switch mode {
        case .navigate:
            return original

        case .move:
            let distance =
                snapped(
                    amount
                        / movePointsPerUnit,
                    step:
                        snapping
                        ? moveSnapStep
                        : nil
                )

            let direction =
                translationDirection(
                    axis: axis,
                    space: space,
                    transform: original
                )

            result.positionX +=
                direction.x
                * distance

            result.positionY +=
                direction.y
                * distance

            result.positionZ +=
                direction.z
                * distance

        case .rotate:
            let degrees =
                snapped(
                    amount,
                    step:
                        snapping
                        ? rotateSnapStep
                        : nil
                )

            switch axis {
            case .x:
                result.rotationX +=
                    degrees

            case .y:
                result.rotationY +=
                    degrees

            case .z:
                result.rotationZ +=
                    degrees

            case .uniform:
                return original
            }

        case .scale:
            let scaleDelta =
                snapped(
                    amount
                        / scalePointsPerUnit,
                    step:
                        snapping
                        ? scaleSnapStep
                        : nil
                )

            switch axis {
            case .x:
                result.scaleX +=
                    scaleDelta

            case .y:
                result.scaleY +=
                    scaleDelta

            case .z:
                result.scaleZ +=
                    scaleDelta

            case .uniform:
                result.scaleX +=
                    scaleDelta

                result.scaleY +=
                    scaleDelta

                result.scaleZ +=
                    scaleDelta
            }
        }

        return result.normalized
    }

    static func translationDirection(
        axis: BookTransformAxis,
        space: BookTransformSpace,
        transform: BookModelTransform
    ) -> (
        x: Double,
        y: Double,
        z: Double
    ) {
        var vector: (
            x: Double,
            y: Double,
            z: Double
        )

        switch axis {
        case .x:
            vector = (
                1,
                0,
                0
            )

        case .y:
            vector = (
                0,
                1,
                0
            )

        case .z:
            vector = (
                0,
                0,
                1
            )

        case .uniform:
            vector = (
                0,
                0,
                0
            )
        }

        guard space == .local else {
            return vector
        }

        let rx =
            transform.rotationX
            * .pi / 180

        let ry =
            transform.rotationY
            * .pi / 180

        let rz =
            transform.rotationZ
            * .pi / 180

        let cx = cos(rx)
        let sx = sin(rx)
        let cy = cos(ry)
        let sy = sin(ry)
        let cz = cos(rz)
        let sz = sin(rz)

        let x1 =
            vector.x

        let y1 =
            vector.y * cx
            - vector.z * sx

        let z1 =
            vector.y * sx
            + vector.z * cx

        let x2 =
            x1 * cy
            + z1 * sy

        let y2 =
            y1

        let z2 =
            -x1 * sy
            + z1 * cy

        let x3 =
            x2 * cz
            - y2 * sz

        let y3 =
            x2 * sz
            + y2 * cz

        return (
            x3,
            y3,
            z2
        )
    }

    private static func snapped(
        _ value: Double,
        step: Double?
    ) -> Double {
        guard
            let step,
            step > 0
        else {
            return value
        }

        return (
            value
            / step
        ).rounded()
        * step
    }
}

final class BookPreviewInteractionView: SCNView {
    // The rendered scene is one visual canvas. SceneKit's private backing-view
    // hierarchy is not a collection of manuscript/Studio controls and should
    // not be traversed by accessibility clients. Standard controls remain in
    // the surrounding SwiftUI hierarchy.
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .image }
    // Expose identity on the native canvas as well as its SwiftUI wrapper.
    // AX clients may encounter either layer after a comparison layout update.
    var isComparisonViewport = false
    override func accessibilityLabel() -> String? {
        isComparisonViewport ? "Hardcover comparison viewport" : "3D book preview"
    }
    override func accessibilityIdentifier() -> String {
        isComparisonViewport ? "bookstudio.comparison" : "bookstudio.viewport"
    }
    override func accessibilityHelp() -> String? { "Drag to orbit; scroll to zoom. Use Studio controls to open the book and turn pages." }
    override func accessibilityChildren() -> [Any]? { [] }

    var onViewportResize: ((Double) -> Void)?

    override func setFrameSize(_ newSize: NSSize) {
        let changed = frame.size != newSize
        super.setFrameSize(newSize)
        if changed, newSize.width > 0, newSize.height > 0 {
            onViewportResize?(Double(newSize.width / newSize.height))
        }
    }

    var onOrbit: ((Double, Double) -> Void)?
    var onPan: ((Double, Double, Double) -> Void)?
    var onZoom: ((Double) -> Void)?
    var onSelect: ((BookSceneComponent?) -> Void)?
    var onSelectCustomLight: ((UUID) -> Void)?
    var onSelectCamera: (() -> Void)?
    var onNavigationEnded: (() -> Void)?
    var onFrameSelection: ((SCNNode) -> Void)?
    var onTransformBegin: ((BookTransformMode, BookTransformAxis) -> Void)?
    var onTransformDrag: ((BookTransformMode, BookTransformAxis, Double, Bool) -> Void)?
    var onTransformEnded: (() -> Void)?
    var onTransformModeShortcut: ((BookTransformMode) -> Void)?
    var onToggleTransformSpace: (() -> Void)?
    var onResetTransform: (() -> Void)?
    weak var cameraNode: SCNNode? {
        didSet {
            // SCNView can retain its automatically chosen camera when its
            // scene is replaced. The editor must render through the new scene's
            // camera, not an orphaned node at an obsolete position.
            pointOfView = cameraNode
            cameraNode?.camera?.categoryBitMask = BookStudioCameraGuideScene.viewportCategoryMask
            needsDisplay = true
        }
    }

    var selectedCustomLightID: UUID? {
        didSet {
            refreshCustomLightHighlight()
        }
    }

    private var restingAntialiasing: SCNAntialiasingMode = .multisampling2X
    private var restingFrameRate = 60
    private var isNavigating = false
    func configureQuality(_ quality: BookRenderQuality) {
        restingAntialiasing = quality == .fast ? .none : quality == .balanced ? .multisampling2X : .multisampling4X
        restingFrameRate = quality == .fast ? 30 : 60
        antialiasingMode = isNavigating ? .none : restingAntialiasing
        preferredFramesPerSecond = isNavigating ? 30 : restingFrameRate
    }
    func setNavigating(_ active: Bool) {
        isNavigating = active
        antialiasingMode = active ? .none : restingAntialiasing
        preferredFramesPerSecond = active ? 30 : restingFrameRate
    }

    func releasePreviewResources() {
        SCNTransaction.lock()
        defer { SCNTransaction.unlock() }
        isPlaying = false
        scene = nil
        pointOfView = nil
        cameraNode = nil
        onViewportResize = nil
        onOrbit = nil
        onPan = nil
        onZoom = nil
        onSelect = nil
        onSelectCustomLight = nil
        onSelectCamera = nil
        onNavigationEnded = nil
        onFrameSelection = nil
        onTransformBegin = nil
        onTransformDrag = nil
        onTransformEnded = nil
        onTransformModeShortcut = nil
        onToggleTransformSpace = nil
        onResetTransform = nil
    }

    private struct ActiveTransformDrag {
        let handle: BookTransformGizmoHandle
        let screenAxisX: Double
        let screenAxisY: Double
        let rotationCenter: NSPoint
        var accumulatedAmount: Double
        var lastRotationAngle: Double?
    }

    private var lastDrag = NSPoint.zero
    private var mouseDownPoint = NSPoint.zero
    private var activeTransformDrag: ActiveTransformDrag?
    private var hoveredTransformHandle: BookTransformGizmoHandle?
    private var hoveredCustomLightID: UUID?
    private var transformTrackingArea: NSTrackingArea?
    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        if let transformTrackingArea {
            removeTrackingArea(
                transformTrackingArea
            )
        }

        super.updateTrackingAreas()

        let area =
            NSTrackingArea(
                rect: bounds,
                options: [
                    .mouseMoved,
                    .mouseEnteredAndExited,
                    .activeInKeyWindow,
                    .inVisibleRect
                ],
                owner: self,
                userInfo: nil
            )

        addTrackingArea(area)
        transformTrackingArea = area
    }

    override func mouseMoved(
        with event: NSEvent
    ) {
        let point =
            convert(
                event.locationInWindow,
                from: nil
            )

        hoveredTransformHandle =
            transformHandle(
                at: point
            )

        if hoveredTransformHandle == nil {
            hoveredCustomLightID =
                customLightID(
                    at: point
                )
        } else {
            hoveredCustomLightID =
                nil
        }

        refreshTransformHighlight()
        refreshCustomLightHighlight()
    }

    override func mouseExited(
        with event: NSEvent
    ) {
        hoveredTransformHandle =
            nil

        hoveredCustomLightID =
            nil

        refreshTransformHighlight()
        refreshCustomLightHighlight()
    }

    func refreshTransformHighlight() {
        BookStudioTransformScene
            .updateHighlight(
                in: scene,
                hovered:
                    hoveredTransformHandle,
                active:
                    activeTransformDrag?
                    .handle
            )
    }

    func refreshCustomLightHighlight() {
        BookStudioCustomLightScene
            .updateMarkerHighlight(
                in: scene,
                hovered:
                    hoveredCustomLightID,
                selected:
                    selectedCustomLightID
            )
    }
    override func mouseDown(with event: NSEvent) {
        lastDrag =
            convert(
                event.locationInWindow,
                from: nil
            )

        mouseDownPoint =
            lastDrag

        window?
            .makeFirstResponder(self)

        if let drag =
            transformDrag(
                at: lastDrag
            ) {
            activeTransformDrag =
                drag

            hoveredTransformHandle =
                drag.handle

            refreshTransformHighlight()

            setNavigating(true)

            onTransformBegin?(
                drag.handle.mode,
                drag.handle.axis
            )
        }
    }
    override func mouseDragged(with event: NSEvent) {
        let point =
            convert(
                event.locationInWindow,
                from: nil
            )

        if var drag =
            activeTransformDrag {
            setNavigating(true)

            switch drag.handle.mode {
            case .rotate:
                let angle =
                    atan2(
                        Double(
                            point.y
                            - drag.rotationCenter.y
                        ),
                        Double(
                            point.x
                            - drag.rotationCenter.x
                        )
                    )

                if let previous =
                    drag.lastRotationAngle {
                    var delta =
                        angle
                        - previous

                    while delta > .pi {
                        delta -=
                            2 * .pi
                    }

                    while delta < -.pi {
                        delta +=
                            2 * .pi
                    }

                    drag.accumulatedAmount +=
                        delta
                        * 180
                        / .pi
                }

                drag.lastRotationAngle =
                    angle

            case .move,
                 .scale:
                let dx =
                    Double(
                        point.x
                        - lastDrag.x
                    )

                let dy =
                    Double(
                        point.y
                        - lastDrag.y
                    )

                drag.accumulatedAmount +=
                    dx
                    * drag.screenAxisX
                    + dy
                    * drag.screenAxisY

            case .navigate:
                break
            }

            activeTransformDrag =
                drag

            onTransformDrag?(
                drag.handle.mode,
                drag.handle.axis,
                drag.accumulatedAmount,
                event.modifierFlags
                    .contains(.shift)
            )

            lastDrag =
                point

            return
        }

        setNavigating(true)

        let dx =
            Double(
                point.x
                - lastDrag.x
            )

        let dy =
            Double(
                lastDrag.y
                - point.y
            )

        if event.modifierFlags
            .contains(.option)
            || event.modifierFlags
            .contains(.shift) {
            onPan?(
                dx,
                dy,
                Double(bounds.height)
            )
        } else {
            onOrbit?(
                dx,
                dy
            )
        }

        lastDrag =
            point
    }
    override func rightMouseDown(with event: NSEvent) { lastDrag = convert(event.locationInWindow, from: nil); window?.makeFirstResponder(self) }
    override func rightMouseDragged(with event: NSEvent) {
        setNavigating(true)
        let point = convert(event.locationInWindow, from: nil)
        onPan?(Double(point.x - lastDrag.x), Double(lastDrag.y - point.y), Double(bounds.height))
        lastDrag = point
    }
    override func rightMouseUp(with event: NSEvent) { setNavigating(false); onNavigationEnded?() }
    override func mouseUp(with event: NSEvent) {
        setNavigating(false)

        let point =
            convert(
                event.locationInWindow,
                from: nil
            )

        if activeTransformDrag != nil {
            activeTransformDrag =
                nil

            refreshTransformHighlight()

            onTransformEnded?()

            return
        }

        onNavigationEnded?()

        guard
            hypot(
                point.x
                    - mouseDownPoint.x,
                point.y
                    - mouseDownPoint.y
            )
            < 4
        else {
            return
        }

        if cameraGuideHit(
            at: point
        ) {
            onSelectCamera?()
            return
        }

        if let customLightID =
            customLightID(
                at: point
            )
        {
            selectedCustomLightID =
                customLightID

            hoveredCustomLightID =
                customLightID

            refreshCustomLightHighlight()

            onSelectCustomLight?(
                customLightID
            )

            return
        }

        var node =
            hitTest(
                point,
                options: [.categoryBitMask: BookStudioCameraGuideScene.viewportCategoryMask]
            )
            .first?
            .node

        while let current =
            node {
            if
                let name =
                    current.name,
                let component =
                    BookSceneComponent
                    .component(
                        for: name
                    )
            {
                onSelect?(
                    component
                )

                if event.clickCount >= 2 {
                    onFrameSelection?(
                        current
                    )
                }

                return
            }

            node =
                current.parent
        }

        onSelect?(nil)
    }
    private func transformDrag(
        at point: NSPoint
    ) -> ActiveTransformDrag? {
        guard
            let handle =
                transformHandle(
                    at: point
                )
        else {
            return nil
        }

        let direction =
            projectedAxisDirection(
                axis:
                    handle.axis
            )

        let center =
            projectedGizmoCenter()

        let startAngle =
            atan2(
                Double(
                    point.y
                    - center.y
                ),
                Double(
                    point.x
                    - center.x
                )
            )

        return ActiveTransformDrag(
            handle: handle,
            screenAxisX:
                direction.x,
            screenAxisY:
                direction.y,
            rotationCenter:
                center,
            accumulatedAmount:
                0,
            lastRotationAngle:
                handle.mode
                == .rotate
                ? startAngle
                : nil
        )
    }

    private func transformHandle(
        at point: NSPoint
    ) -> BookTransformGizmoHandle? {
        let hits =
            hitTest(
                point,
                options: [.categoryBitMask: BookStudioCameraGuideScene.viewportCategoryMask]
            )

        for hit in hits {
            var node: SCNNode? =
                hit.node

            while let current =
                node {
                if
                    let name =
                        current.name,
                    let handle =
                        BookTransformGizmoHandle
                        .parse(
                            nodeName:
                                name
                        )
                {
                    return handle
                }

                node =
                    current.parent
            }
        }

        return nil
    }

    private func customLightID(
        at point: NSPoint
    ) -> UUID? {
        let hits =
            hitTest(
                point,
                options: [.categoryBitMask: BookStudioCameraGuideScene.viewportCategoryMask]
            )

        for hit in hits {
            var node: SCNNode? =
                hit.node

            while let current =
                node {
                if
                    let name =
                        current.name,
                    let id =
                        BookStudioCustomLightScene
                        .lightID(
                            fromNodeName:
                                name
                        )
                {
                    return id
                }

                node =
                    current.parent
            }
        }

        return nil
    }

    private func cameraGuideHit(
        at point: NSPoint
    ) -> Bool {
        let hits =
            hitTest(
                point,
                options: [.categoryBitMask: BookStudioCameraGuideScene.viewportCategoryMask]
            )

        for hit in hits {
            var node: SCNNode? =
                hit.node

            while let current =
                node {
                if
                    let name =
                        current.name,
                    BookStudioCameraGuideScene
                        .isGuideNode(
                            name: name
                        )
                {
                    return true
                }

                node =
                    current.parent
            }
        }

        return false
    }



    private func projectedGizmoCenter()
        -> NSPoint
    {
        guard
            let gizmo =
                scene?
                .rootNode
                .childNode(
                    withName:
                        BookStudioTransformScene
                        .gizmoRootName,
                    recursively: false
                )
        else {
            return mouseDownPoint
        }

        let world =
            gizmo.presentation
                .worldPosition

        let projected =
            projectPoint(
                world
            )

        return NSPoint(
            x: CGFloat(
                projected.x
            ),
            y: CGFloat(
                projected.y
            )
        )
    }

    private func projectedAxisDirection(
        axis: BookTransformAxis
    ) -> (
        x: Double,
        y: Double
    ) {
        if axis == .uniform {
            let diagonal =
                1
                / sqrt(2.0)

            return (
                diagonal,
                diagonal
            )
        }

        guard
            let gizmo =
                scene?
                .rootNode
                .childNode(
                    withName:
                        BookStudioTransformScene
                        .gizmoRootName,
                    recursively: false
                )
        else {
            return fallbackAxisDirection(
                axis: axis
            )
        }

        let localAxis:
            SCNVector3

        switch axis {
        case .x:
            localAxis =
                SCNVector3(
                    1,
                    0,
                    0
                )

        case .y:
            localAxis =
                SCNVector3(
                    0,
                    1,
                    0
                )

        case .z:
            localAxis =
                SCNVector3(
                    0,
                    0,
                    1
                )

        case .uniform:
            localAxis =
                SCNVector3(
                    1,
                    1,
                    0
                )
        }

        let worldOrigin =
            gizmo.presentation
                .worldPosition

        let worldAxis =
            gizmo.presentation
                .convertVector(
                    localAxis,
                    to: nil
                )

        let p0 =
            projectPoint(
                worldOrigin
            )

        let p1 =
            projectPoint(
                SCNVector3(
                    worldOrigin.x
                        + worldAxis.x,
                    worldOrigin.y
                        + worldAxis.y,
                    worldOrigin.z
                        + worldAxis.z
                )
            )

        let dx =
            Double(
                p1.x
                - p0.x
            )

        let dy =
            Double(
                p1.y
                - p0.y
            )

        let length =
            hypot(
                dx,
                dy
            )

        guard length > 0.001 else {
            return fallbackAxisDirection(
                axis: axis
            )
        }

        return (
            dx / length,
            dy / length
        )
    }

    private func fallbackAxisDirection(
        axis: BookTransformAxis
    ) -> (
        x: Double,
        y: Double
    ) {
        switch axis {
        case .x:
            return (
                1,
                0
            )

        case .y:
            return (
                0,
                1
            )

        case .z:
            let value =
                1
                / sqrt(2.0)

            return (
                value,
                value
            )

        case .uniform:
            let value =
                1
                / sqrt(2.0)

            return (
                value,
                value
            )
        }
    }

    override func keyDown(
        with event: NSEvent
    ) {
        if event.keyCode == 53 {
            onSelect?(nil)
            return
        }

        let command =
            event.modifierFlags
            .contains(.command)

        let control =
            event.modifierFlags
            .contains(.control)

        let option =
            event.modifierFlags
            .contains(.option)

        let key =
            event.charactersIgnoringModifiers?
            .lowercased()

        if command,
           key == "0"
        {
            onResetTransform?()
            return
        }

        guard
            !command,
            !control,
            !option
        else {
            super.keyDown(
                with: event
            )
            return
        }

        switch key {
        case "g":
            onTransformModeShortcut?(
                .move
            )

        case "r":
            onTransformModeShortcut?(
                .rotate
            )

        case "s":
            onTransformModeShortcut?(
                .scale
            )

        case "v":
            onTransformModeShortcut?(
                .navigate
            )

        case "l":
            onToggleTransformSpace?()

        default:
            super.keyDown(
                with: event
            )
        }
    }
    override func scrollWheel(with event: NSEvent) {
        setNavigating(true)
        onZoom?(exp(-Double(event.scrollingDeltaY) * 0.008))
        scheduleNavigationCommit()
    }
    override func magnify(with event: NSEvent) {
        setNavigating(true)
        onZoom?(exp(-Double(event.magnification)))
        scheduleNavigationCommit()
    }
    private var navigationCommit: DispatchWorkItem?
    private func scheduleNavigationCommit() {
        navigationCommit?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.setNavigating(false)
            self?.onNavigationEnded?()
        }
        navigationCommit = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: item)
    }
    func setCamera(_ state: BookPreviewCameraState, animated: Bool = false) {
        guard let cameraNode else { return }
        Self.positionCamera(cameraNode, state: state, animated: animated)
    }
    static func positionCamera(_ cameraNode: SCNNode, state: BookPreviewCameraState, animated: Bool = false) {
        // Respect callers requesting an atomic, nonanimated scene update
        // (including the native proof renderer).
        let shouldAnimate = animated && !SCNTransaction.disableActions
        SCNTransaction.begin()
        SCNTransaction.disableActions = !shouldAnimate
        SCNTransaction.animationDuration = shouldAnimate ? 0.35 : 0
        defer { SCNTransaction.commit() }
        let cp = cos(state.pitch), sp = sin(state.pitch)
        let x = state.target.x + state.distance * cp * sin(state.yaw)
        let y = state.target.y + state.distance * sp
        let z = state.target.z + state.distance * cp * cos(state.yaw)
        cameraNode.position = SCNVector3(x, y, z)
        cameraNode.look(at: SCNVector3(state.target.x, state.target.y, state.target.z), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
    }
    /// Prepare the detached camera before publishing a replacement scene to the render thread.
    /// Publishing first can expose the constructor's origin camera for a visible frame.
    func installScene(_ scene: SCNScene, state: BookPreviewCameraState,
                      projection: BookCameraProjection, fieldOfView: Double) {
        let node = scene.rootNode.childNode(withName: "preview-camera", recursively: true)
        if let node {
            Self.positionCamera(node, state: state)
            Self.configureCamera(node.camera, state: state, projection: projection, fieldOfView: fieldOfView)
        }
        SCNTransaction.lock()
        defer { SCNTransaction.unlock() }
        self.scene = scene
        cameraNode = node
    }
    func configureCamera(_ state: BookPreviewCameraState, projection: BookCameraProjection, fieldOfView: Double = 34) {
        Self.configureCamera(cameraNode?.camera, state: state, projection: projection, fieldOfView: fieldOfView)
    }
    private static func configureCamera(_ camera: SCNCamera?, state: BookPreviewCameraState,
                                        projection: BookCameraProjection, fieldOfView: Double) {
        guard let camera else { return }
        camera.projectionDirection = .vertical
        camera.fieldOfView = CGFloat(fieldOfView)
        camera.usesOrthographicProjection = projection == .orthographic
        camera.orthographicScale = 2 * state.distance * tan(Double(camera.fieldOfView) * .pi / 360)
    }
}

final class BookStudioViewportHandle {
    weak var view: BookPreviewInteractionView?
    var coverProject: CoverProject?
    func releasePreviewResources() {
        view?.releasePreviewResources()
        view = nil
        coverProject = nil
    }
    func image(size: CGSize?, transparent: Bool = false, highQualityCover: Bool = false) -> NSImage? {
        guard let view, let scene = view.scene else { return nil }
        let previousBackground = scene.background.contents
        let bookRoot =
            scene.rootNode.childNode(
                withName:
                    "physical-book.root",
                recursively:
                    true
            )
        let bookWasHidden =
            bookRoot?.isHidden
        let ground = scene.rootNode.childNode(withName: "studio-ground", recursively: true)
        let groundWasHidden = ground?.isHidden
        let restoreInspection = BookInspectionScene.suspend(scene)
        defer { restoreInspection() }
        let wasExploded = scene.rootNode.value(forKey: "bookStudioExploded") as? Bool ?? false
        if wasExploded { BookStudioSceneStyling.setExploded(false, on: scene) }
        var hidden: [(SCNNode, Bool)] = []
        var replacedArtwork: [(SCNMaterial, Any?)] = []
        if highQualityCover, let coverProject {
            let textures = PhysicalBookCoverTextures(project: coverProject,
                                                     workingLayers: false,
                                                     previewDPI: 360)
            guard textures.front != nil, textures.back != nil else {
                if wasExploded { BookStudioSceneStyling.setExploded(true, on: scene) }
                return nil
            }
            for (name, image) in [
                ("book-shell.front-cover", textures.front),
                ("book-shell.back-cover", textures.back),
                ("book-shell.spine-artwork", textures.spine)
            ] {
                guard let image, let node = scene.rootNode.childNode(withName: name, recursively: true) else { continue }
                let nodes = [node] + node.childNodes
                for part in nodes {
                    for material in part.geometry?.materials ?? [] where material.diffuse.contents is NSImage {
                        replacedArtwork.append((material, material.diffuse.contents))
                        material.diffuse.contents = image
                    }
                }
            }
        }
        scene.rootNode.enumerateChildNodes { node, _ in
            if let name = node.name,
               name.hasPrefix("diagnostic.")
                    || name == "studio-selection-outline"
                    || name.hasPrefix("studio-transform-gizmo")
                    || name.hasPrefix("studio-custom-light-gizmo.")
                    || name.hasPrefix("studio-custom-light-guide.")
                    || name.hasPrefix("studio-camera-guide.") {
                hidden.append((node, node.isHidden))
                node.isHidden = true
            }
        }
        bookRoot?.isHidden =
            false

        if
            let productionHidden =
                ground?.value(
                    forKey:
                        "bookStudioProductionHidden"
                )
                as? Bool
        {
            ground?.isHidden =
                productionHidden
        }

        if transparent {
            scene.background.contents = nil
            ground?.isHidden = true
        }
        defer {
            for (material, previous) in replacedArtwork { material.diffuse.contents = previous }
            for (node, wasHidden) in hidden { node.isHidden = wasHidden }
            scene.background.contents = previousBackground
            if let bookWasHidden { bookRoot?.isHidden = bookWasHidden }
            if let groundWasHidden { ground?.isHidden = groundWasHidden }
            if wasExploded { BookStudioSceneStyling.setExploded(true, on: scene) }
        }
        guard let size else {
            if !transparent { return view.snapshot() }
            let scale = view.window?.backingScaleFactor ?? 2
            return render(scene: scene, camera: view.cameraNode,
                          size: CGSize(width: max(1, view.bounds.width * scale),
                                       height: max(1, view.bounds.height * scale)))
        }
        return render(scene: scene, camera: view.cameraNode, size: size)
    }


    func animationFrame(
        size: CGSize?,
        presentation: BookStudioPresentation,
        frameIndex: Int,
        transparent: Bool = false,
        highQualityCover: Bool = false
    ) -> NSImage? {
        guard
            let view,
            let scene =
                view.scene
        else {
            return nil
        }

        let frameTime =
            BookStudioAnimationMath
            .time(
                forFrame:
                    frameIndex,
                duration:
                    presentation
                    .animationDuration,
                fps:
                    presentation
                    .animationFPS
            )

        let bookRoot =
            scene.rootNode
            .childNode(
                withName:
                    "physical-book.root",
                recursively:
                    true
            )

        let previousBookTransform =
            bookRoot?
            .transform

        let cameraNode =
            view.cameraNode

        let previousCameraTransform =
            cameraNode?
            .transform

        defer {
            if
                let previousBookTransform
            {
                bookRoot?
                    .transform =
                    previousBookTransform
            }

            if
                let previousCameraTransform
            {
                cameraNode?
                    .transform =
                    previousCameraTransform
            }
        }

        let transform =
            BookStudioAnimationMath
            .turntableTransform(
                base:
                    presentation
                    .modelTransform,
                time:
                    frameTime,
                duration:
                    presentation
                    .animationDuration,
                enabled:
                    presentation
                    .turntableEnabled,
                turns:
                    presentation
                    .turntableTurns,
                clockwise:
                    presentation
                    .turntableClockwise
            )

        bookRoot?
            .position =
            SCNVector3(
                CGFloat(
                    transform.positionX
                ),
                CGFloat(
                    transform.positionY
                ),
                CGFloat(
                    transform.positionZ
                )
            )

        bookRoot?
            .eulerAngles =
            SCNVector3(
                CGFloat(
                    transform.rotationX
                    * .pi
                    / 180
                ),
                CGFloat(
                    transform.rotationY
                    * .pi
                    / 180
                ),
                CGFloat(
                    transform.rotationZ
                    * .pi
                    / 180
                )
            )

        bookRoot?
            .scale =
            SCNVector3(
                CGFloat(
                    transform.scaleX
                ),
                CGFloat(
                    transform.scaleY
                ),
                CGFloat(
                    transform.scaleZ
                )
            )

        if
            let camera =
                BookStudioAnimationMath
                .camera(
                    at:
                        frameTime,
                    keyframes:
                        presentation
                        .cameraKeyframes,
                    duration:
                        presentation
                        .animationDuration
                )
        {
            view.setCamera(
                BookPreviewCameraState(
                    saved:
                        camera
                )
            )
        }

        return image(
            size:
                size,
            transparent:
                transparent,
            highQualityCover:
                highQualityCover
        )
    }

    private func render(scene: SCNScene, camera: SCNNode?, size: CGSize) -> NSImage {
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = scene
        renderer.pointOfView = camera
        return renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
    }
}

/// Only inputs that change book geometry, artwork, or page diagnostics belong
/// here. Camera movement and presentation styling update the existing scene.
struct BookSceneSourceKey: Equatable {
    var project: CoverProject
    var workingLayers: Bool
    var binding: BookBinding
    var isOpen: Bool
    var openAngle: Double
    var pageCount: Int
    var spreadIndex: Int
    var turnTransition: BookPageTurnTransition?
    var leftPage: Int?
    var rightPage: Int?
    var leftTextureID: ObjectIdentifier?
    var rightTextureID: ObjectIdentifier?
    var showMargins: Bool
    var thumbMode: ThumbZoneMode
    var leftPageSettings: PageSettings
    var rightPageSettings: PageSettings
    var revisionID: UUID
}




enum BookStudioCameraGuideScene {
    // A camera must never render the solid helper surrounding its own lens.
    // External overview cameras can include this category to show the helper.
    static let cameraBodyCategory = 1 << 28
    static let viewportCategoryMask = Int(UInt32.max) ^ cameraBodyCategory
    static let rootName =
        "studio-camera-guide.root"

    static let cameraName =
        "studio-camera-guide.camera"

    static let targetName =
        "studio-camera-guide.target"

    static let frustumName =
        "studio-camera-guide.frustum"

    static func isGuideNode(
        name: String
    ) -> Bool {
        name.hasPrefix(
            "studio-camera-guide."
        )
    }

    static func apply(
        to scene: SCNScene?,
        state: BookPreviewCameraState,
        visible: Bool,
        selected: Bool
    ) {
        guard let scene else {
            return
        }

        scene.rootNode
            .childNode(
                withName:
                    rootName,
                recursively: false
            )?
            .removeFromParentNode()

        guard visible else {
            return
        }

        let cp =
            cos(
                state.pitch
            )

        let sp =
            sin(
                state.pitch
            )

        let position =
            SIMD3<Double>(
                state.target.x
                    + state.distance
                    * cp
                    * sin(
                        state.yaw
                    ),
                state.target.y
                    + state.distance
                    * sp,
                state.target.z
                    + state.distance
                    * cp
                    * cos(
                        state.yaw
                    )
            )

        let root =
            SCNNode()

        root.name =
            rootName

        let bodyGeometry =
            SCNBox(
                width: 0.24,
                height: 0.16,
                length: 0.18,
                chamferRadius: 0.025
            )

        bodyGeometry.materials = [
            material(
                selected
                ? .white
                : .systemCyan
            )
        ]

        let body =
            SCNNode(
                geometry:
                    bodyGeometry
            )

        body.name =
            cameraName
        body.categoryBitMask = cameraBodyCategory

        body.position =
            SCNVector3(
                CGFloat(position.x),
                CGFloat(position.y),
                CGFloat(position.z)
            )

        body.look(
            at:
                SCNVector3(
                    CGFloat(state.target.x),
                    CGFloat(state.target.y),
                    CGFloat(state.target.z)
                ),
            up:
                SCNVector3(
                    0,
                    1,
                    0
                ),
            localFront:
                SCNVector3(
                    0,
                    0,
                    -1
                )
        )

        body.renderingOrder =
            245

        if selected {
            body.scale =
                SCNVector3(
                    1.35,
                    1.35,
                    1.35
                )
        }

        root.addChildNode(
            body
        )

        let frustumGeometry =
            SCNPyramid(
                width: 0.34,
                height: 0.28,
                length: 0.42
            )

        let frustumMaterial =
            material(
                .systemCyan
            )

        frustumMaterial.fillMode =
            .lines

        frustumMaterial.transparency =
            0.7

        frustumGeometry.materials = [
            frustumMaterial
        ]

        let frustum =
            SCNNode(
                geometry:
                    frustumGeometry
            )

        frustum.name =
            frustumName
        frustum.categoryBitMask = cameraBodyCategory

        frustum.position =
            SCNVector3(
                0,
                0,
                -0.28
            )

        body.addChildNode(
            frustum
        )

        let targetGeometry =
            SCNSphere(
                radius: 0.07
            )

        targetGeometry.materials = [
            material(
                .systemTeal
            )
        ]

        let target =
            SCNNode(
                geometry:
                    targetGeometry
            )

        target.name =
            targetName

        target.position =
            SCNVector3(
                CGFloat(state.target.x),
                CGFloat(state.target.y),
                CGFloat(state.target.z)
            )

        target.renderingOrder =
            245

        root.addChildNode(
            target
        )

        scene.rootNode
            .addChildNode(
                root
            )
    }

    private static func material(
        _ color: NSColor
    ) -> SCNMaterial {
        let material =
            SCNMaterial()

        material.diffuse.contents =
            color

        material.emission.contents =
            color.withAlphaComponent(
                0.65
            )

        material.lightingModel =
            .constant

        material.readsFromDepthBuffer =
            false

        material.writesToDepthBuffer =
            false

        material.isDoubleSided =
            true

        return material
    }
}

enum BookStudioCustomLightScene {
    static let nodePrefix =
        "studio-custom-light."

    static let gizmoPrefix =
        "studio-custom-light-gizmo."

    static func nodeName(
        for id: UUID
    ) -> String {
        nodePrefix
            + id.uuidString
    }

    static func gizmoName(
        for id: UUID
    ) -> String {
        gizmoPrefix
            + id.uuidString
    }

    static func apply(
        to scene: SCNScene?,
        presentation: BookStudioPresentation,
        selectedCustomLightID: UUID? = nil
    ) {
        guard let scene else {
            return
        }

        let root =
            scene.rootNode

        let lights =
            presentation.customLights
            .map {
                $0.normalized
            }

        let desired =
            Set(
                lights.map {
                    nodeName(
                        for: $0.id
                    )
                }
            )

        var stale: [SCNNode] =
            []

        root.enumerateChildNodes {
            node,
            _ in

            guard
                let name =
                    node.name,
                name.hasPrefix(
                    nodePrefix
                ),
                !desired.contains(
                    name
                )
            else {
                return
            }

            stale.append(node)
        }

        stale.forEach {
            $0.removeFromParentNode()
        }

        for model in lights {
            let name =
                nodeName(
                    for: model.id
                )

            let node =
                root.childNode(
                    withName: name,
                    recursively: false
                )
                ?? makeNode(
                    model
                )

            if node.parent == nil {
                root.addChildNode(
                    node
                )
            }

            update(
                node,
                model:
                    model,
                showGuide:
                    presentation
                    .lightGuidesVisible
                    && selectedCustomLightID
                        == model.id
            )
        }
    }

    static func lightNode(
        in scene: SCNScene?,
        id: UUID
    ) -> SCNNode? {
        scene?
            .rootNode
            .childNode(
                withName:
                    nodeName(
                        for: id
                    ),
                recursively: false
            )
    }

    static func lightID(
        fromNodeName name: String
    ) -> UUID? {
        if name.hasPrefix(
            gizmoPrefix
        ) {
            return UUID(
                uuidString:
                    String(
                        name.dropFirst(
                            gizmoPrefix.count
                        )
                    )
            )
        }

        if name.hasPrefix(
            nodePrefix
        ) {
            return UUID(
                uuidString:
                    String(
                        name.dropFirst(
                            nodePrefix.count
                        )
                    )
            )
        }

        return nil
    }

    static func updateMarkerHighlight(
        in scene: SCNScene?,
        hovered: UUID?,
        selected: UUID?
    ) {
        guard let scene else {
            return
        }

        scene.rootNode
            .enumerateChildNodes {
                node,
                _ in

                guard
                    let name =
                        node.name,
                    name.hasPrefix(
                        gizmoPrefix
                    ),
                    let id =
                        lightID(
                            fromNodeName:
                                name
                        )
                else {
                    return
                }

                let isSelected =
                    id == selected

                let isHovered =
                    id == hovered

                if isSelected {
                    node.scale =
                        SCNVector3(
                            1.45,
                            1.45,
                            1.45
                        )

                    node.geometry?
                        .firstMaterial?
                        .emission
                        .contents =
                        NSColor.white

                } else if isHovered {
                    node.scale =
                        SCNVector3(
                            1.25,
                            1.25,
                            1.25
                        )

                    node.geometry?
                        .firstMaterial?
                        .emission
                        .contents =
                        NSColor.systemOrange

                } else {
                    node.scale =
                        SCNVector3(
                            1,
                            1,
                            1
                        )

                    node.geometry?
                        .firstMaterial?
                        .emission
                        .contents =
                        NSColor.systemYellow
                        .withAlphaComponent(
                            0.65
                        )
                }
            }
    }


    private static func makeNode(
        _ model: BookStudioLight
    ) -> SCNNode {
        let node =
            SCNNode()

        node.name =
            nodeName(
                for: model.id
            )

        node.light =
            SCNLight()

        let gizmo =
            SCNNode(
                geometry:
                    SCNSphere(
                        radius: 0.075
                    )
            )

        gizmo.name =
            gizmoName(
                for: model.id
            )

        gizmo.geometry?
            .firstMaterial?
            .diffuse
            .contents =
            NSColor.systemYellow

        gizmo.geometry?
            .firstMaterial?
            .emission
            .contents =
            NSColor.systemYellow
            .withAlphaComponent(
                0.65
            )

        gizmo.geometry?
            .firstMaterial?
            .lightingModel =
            .constant

        gizmo.renderingOrder =
            180

        node.addChildNode(
            gizmo
        )

        return node
    }

    private static func update(
        _ node: SCNNode,
        model: BookStudioLight,
        showGuide: Bool
    ) {
        if node.light == nil {
            node.light =
                SCNLight()
        }

        let light =
            node.light

        light?.type =
            model.type == .point
            ? .omni
            : .spot

        light?.intensity =
            CGFloat(
                model.enabled
                ? model.intensity
                : 0
            )

        light?.color =
            color(
                hex:
                    model.colorHex
            )

        light?.castsShadow =
            model.castsShadow
            && model.enabled

        light?.shadowRadius =
            5

        light?.shadowSampleCount =
            12

        light?.shadowBias =
            0.0015

        light?.attenuationStartDistance =
            CGFloat(
                max(
                    0,
                    model.range
                    * 0.05
                )
            )

        light?.attenuationEndDistance =
            CGFloat(
                model.range
            )

        light?.attenuationFalloffExponent =
            2

        if model.type == .spot {
            light?.spotInnerAngle =
                CGFloat(
                    model.spotInnerAngle
                )

            light?.spotOuterAngle =
                CGFloat(
                    model.spotOuterAngle
                )
        }

        let transform =
            model.transform.normalized

        node.position =
            SCNVector3(
                CGFloat(
                    transform.positionX
                ),
                CGFloat(
                    transform.positionY
                ),
                CGFloat(
                    transform.positionZ
                )
            )

        node.eulerAngles =
            SCNVector3(
                radians(
                    transform.rotationX
                ),
                radians(
                    transform.rotationY
                ),
                radians(
                    transform.rotationZ
                )
            )

        if
            let gizmo =
                node.childNode(
                    withName:
                        gizmoName(
                            for: model.id
                        ),
                    recursively: false
                )
        {
            gizmo.isHidden =
                !model.enabled
                || !model.editorVisible

            if model.type == .spot {
                if !gizmo.childNodes.contains(
                    where: {
                        $0.name
                        == "studio-custom-light-spot-direction"
                    }
                ) {
                    let cone =
                        SCNCone(
                            topRadius: 0,
                            bottomRadius: 0.09,
                            height: 0.24
                        )

                    cone.firstMaterial?
                        .diffuse.contents =
                        NSColor.systemOrange

                    cone.firstMaterial?
                        .emission.contents =
                        NSColor.systemOrange
                        .withAlphaComponent(
                            0.5
                        )

                    cone.firstMaterial?
                        .lightingModel =
                        .constant

                    let direction =
                        SCNNode(
                            geometry: cone
                        )

                    direction.name =
                        "studio-custom-light-spot-direction"

                    direction.eulerAngles.x =
                        -.pi / 2

                    direction.position.z =
                        -0.15

                    gizmo.addChildNode(
                        direction
                    )
                }
            } else {
                gizmo.childNode(
                    withName:
                        "studio-custom-light-spot-direction",
                    recursively: false
                )?
                .removeFromParentNode()
            }

        updateGuide(
            on: node,
            model:
                model,
            visible:
                showGuide
                && model.enabled
                && model.editorVisible
        )
        }
    }

    private static func radians(
        _ degrees: Double
    ) -> CGFloat {
        CGFloat(
            degrees
        )
        * .pi
        / 180
    }

    static func color(
        hex: String
    ) -> NSColor {
        let raw =
            hex
            .trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )
            .replacingOccurrences(
                of: "#",
                with: ""
            )

        guard
            raw.count == 6,
            let value =
                UInt64(
                    raw,
                    radix: 16
                )
        else {
            return .white
        }

        return NSColor(
            calibratedRed:
                CGFloat(
                    (
                        value >> 16
                    )
                    & 0xFF
                )
                / 255,
            green:
                CGFloat(
                    (
                        value >> 8
                    )
                    & 0xFF
                )
                / 255,
            blue:
                CGFloat(
                    value
                    & 0xFF
                )
                / 255,
            alpha: 1
        )
    }

    static let guidePrefix =
        "studio-custom-light-guide."

    private static func updateGuide(
        on node: SCNNode,
        model: BookStudioLight,
        visible: Bool
    ) {
        let stale =
            node.childNodes.filter {
                $0.name?
                    .hasPrefix(
                        guidePrefix
                    )
                    == true
            }

        stale.forEach {
            $0.removeFromParentNode()
        }

        guard visible else {
            return
        }

        if model.type == .point {
            let sphere =
                SCNSphere(
                    radius:
                        CGFloat(
                            model.range
                        )
                )

            sphere.materials = [
                guideMaterial(
                    .systemYellow
                )
            ]

            let guide =
                SCNNode(
                    geometry:
                        sphere
                )

            guide.name =
                guidePrefix
                + "range"

            guide.renderingOrder =
                150

            node.addChildNode(
                guide
            )

            return
        }

        let distance =
            max(
                0.1,
                model.range
            )

        addSpotGuide(
            to: node,
            suffix:
                "spot.outer",
            angle:
                model.spotOuterAngle,
            distance:
                distance,
            color:
                .systemOrange
        )

        addSpotGuide(
            to: node,
            suffix:
                "spot.inner",
            angle:
                model.spotInnerAngle,
            distance:
                distance,
            color:
                .systemYellow
        )
    }

    private static func addSpotGuide(
        to node: SCNNode,
        suffix: String,
        angle: Double,
        distance: Double,
        color: NSColor
    ) {
        let radius =
            tan(
                max(
                    0,
                    angle
                )
                * .pi
                / 360
            )
            * distance

        let cone =
            SCNCone(
                topRadius: 0,
                bottomRadius:
                    CGFloat(
                        max(
                            0.001,
                            radius
                        )
                    ),
                height:
                    CGFloat(
                        distance
                    )
            )

        cone.materials = [
            guideMaterial(
                color
            )
        ]

        let guide =
            SCNNode(
                geometry:
                    cone
            )

        guide.name =
            guidePrefix
            + suffix

        guide.eulerAngles.x =
            -.pi / 2

        guide.position.z =
            CGFloat(
                -distance
                / 2
            )

        guide.renderingOrder =
            150

        node.addChildNode(
            guide
        )
    }

    private static func guideMaterial(
        _ color: NSColor
    ) -> SCNMaterial {
        let material =
            SCNMaterial()

        material.diffuse.contents =
            color.withAlphaComponent(
                0.45
            )

        material.emission.contents =
            color.withAlphaComponent(
                0.45
            )

        material.lightingModel =
            .constant

        material.fillMode =
            .lines

        material.transparency =
            0.5

        material.readsFromDepthBuffer =
            false

        material.writesToDepthBuffer =
            false

        material.isDoubleSided =
            true

        return material
    }

}

enum BookStudioTransformScene {
    static let modelRootName = "physical-book.root"
    static let gizmoRootName = "studio-transform-gizmo.root"

    static func apply(
        to scene: SCNScene?,
        presentation: BookStudioPresentation,
        selectedCustomLightID: UUID? = nil
    ) {
        guard
            let scene,
            let bookRoot =
                scene.rootNode
                .childNode(
                    withName:
                        modelRootName,
                    recursively: true
                )
        else {
            return
        }

        let bookTransform =
            presentation
            .modelTransform
            .normalized

        bookRoot.position =
            SCNVector3(
                CGFloat(
                    bookTransform.positionX
                ),
                CGFloat(
                    bookTransform.positionY
                ),
                CGFloat(
                    bookTransform.positionZ
                )
            )

        // BOLD WRITER V10 — Reading tabletop base pose
        //
        // Physical book geometry is authored with the printed page normal
        // facing +Z, while the Studio floor normal is +Y. Reading mode must
        // therefore rotate the whole bound object -90° around X so an open
        // spread rests on the Studio floor instead of standing vertically.
        //
        // This is a presentation-space base orientation. The user's own
        // modelTransform.rotationX remains additive on top of it.
        let readingBaseRotationX:
            Double =
            presentation.cameraPreset == .reading
            ? -90
            : 0

        bookRoot.eulerAngles =
            SCNVector3(
                radians(
                    bookTransform.rotationX
                    + readingBaseRotationX
                ),
                radians(
                    bookTransform.rotationY
                ),
                radians(
                    bookTransform.rotationZ
                )
            )

        bookRoot.scale =
            SCNVector3(
                CGFloat(
                    bookTransform.scaleX
                ),
                CGFloat(
                    bookTransform.scaleY
                ),
                CGFloat(
                    bookTransform.scaleZ
                )
            )

        // The upright model is centered through its thickness. After laying
        // it down, that puts the lower cover below the Studio floor. Rest the
        // transformed bounds on the floor, keeping user elevation additive.
        if readingBaseRotationX != 0,
           let ground = scene.rootNode.childNode(withName: "studio-ground", recursively: true) {
            var lowestY = CGFloat.infinity
            bookRoot.enumerateChildNodes { node, _ in
                var ancestor: SCNNode? = node
                while let current = ancestor, current !== bookRoot {
                    if current.isHidden { return }
                    ancestor = current.parent
                }
                // Stack boxes are invisible support anchors. Rest actual
                // printed stock, including curved spine and case surfaces.
                guard node.name != "book.left-page-block", node.name != "book.right-page-block",
                      let geometry = node.geometry else { return }
                for vertex in BookOpenGutterGeometry.surfaceVertices(geometry) {
                    lowestY = min(lowestY,node.convertPosition(vertex,to:scene.rootNode).y)
                }
            }
            if !lowestY.isFinite { lowestY = ground.position.y }
            bookRoot.position.y += ground.position.y - lowestY + CGFloat(bookTransform.positionY)
        }

        if
            let selectedCustomLightID,
            let lightModel =
                presentation.customLights
                .first(
                    where: {
                        $0.id
                        == selectedCustomLightID
                    }
                ),
            let lightNode =
                BookStudioCustomLightScene
                .lightNode(
                    in: scene,
                    id:
                        selectedCustomLightID
                )
        {
            let transform =
                lightModel
                .transform
                .normalized

            lightNode.position =
                SCNVector3(
                    CGFloat(
                        transform.positionX
                    ),
                    CGFloat(
                        transform.positionY
                    ),
                    CGFloat(
                        transform.positionZ
                    )
                )

            lightNode.eulerAngles =
                SCNVector3(
                    radians(
                        transform.rotationX
                    ),
                    radians(
                        transform.rotationY
                    ),
                    radians(
                        transform.rotationZ
                    )
                )

            let effectiveMode:
                BookTransformMode =
                lightModel.locked
                || presentation.transformMode
                    == .scale
                ? .navigate
                : presentation.transformMode

            updateGizmo(
                in: scene,
                modelRoot:
                    lightNode,
                mode:
                    effectiveMode,
                space:
                    presentation
                    .transformSpace
            )

            return
        }

        updateGizmo(
            in: scene,
            modelRoot:
                bookRoot,
            mode:
                presentation
                .bookTransformLocked
                ? .navigate
                : presentation
                    .transformMode,
            space:
                presentation
                .transformSpace
        )
    }

    static func removeGizmo(
        from scene: SCNScene?
    ) {
        scene?.rootNode
            .childNode(
                withName: gizmoRootName,
                recursively: false
            )?
            .removeFromParentNode()
    }

    static func updateHighlight(
        in scene: SCNScene?,
        hovered: BookTransformGizmoHandle?,
        active: BookTransformGizmoHandle?
    ) {
        guard
            let gizmo =
                scene?
                .rootNode
                .childNode(
                    withName:
                        gizmoRootName,
                    recursively: false
                )
        else {
            return
        }

        gizmo.enumerateChildNodes {
            node,
            _ in

            guard
                let name =
                    node.name,
                let handle =
                    BookTransformGizmoHandle
                    .parse(
                        nodeName:
                            name
                    )
            else {
                return
            }

            let activeMatch =
                handle == active

            let hoverMatch =
                handle == hovered

            applyHighlight(
                to: node,
                active:
                    activeMatch,
                hovered:
                    hoverMatch
            )
        }
    }

    private static func applyHighlight(
        to node: SCNNode,
        active: Bool,
        hovered: Bool
    ) {
        func update(
            _ target: SCNNode
        ) {
            guard
                let geometry =
                    target.geometry
            else {
                return
            }

            for material in
                geometry.materials
            {
                let base =
                    material.diffuse
                        .contents
                    as? NSColor
                    ?? .white

                if active {
                    material.emission
                        .contents =
                        NSColor.white

                    material.multiply
                        .contents =
                        NSColor.white

                } else if hovered {
                    material.emission
                        .contents =
                        base.blended(
                            withFraction:
                                0.65,
                            of:
                                .white
                        )
                        ?? .white

                    material.multiply
                        .contents =
                        NSColor.white

                } else {
                    material.emission
                        .contents =
                        base.withAlphaComponent(
                            0.2
                        )

                    material.multiply
                        .contents =
                        NSColor.white
                }
            }
        }

        update(node)

        node.enumerateChildNodes {
            child,
            _ in

            update(child)
        }
    }


    private static func radians(
        _ degrees: Double
    ) -> CGFloat {
        CGFloat(degrees) * .pi / 180
    }

    private static func updateGizmo(
        in scene: SCNScene,
        modelRoot: SCNNode,
        mode: BookTransformMode,
        space: BookTransformSpace
    ) {
        removeGizmo(from: scene)

        guard mode != .navigate else {
            return
        }

        let gizmo = SCNNode()
        gizmo.name = gizmoRootName

        let bounds = modelRoot.boundingBox
        let center = SCNVector3(
            (bounds.min.x + bounds.max.x) / 2,
            (bounds.min.y + bounds.max.y) / 2,
            (bounds.min.z + bounds.max.z) / 2
        )

        gizmo.position = modelRoot.convertPosition(
            center,
            to: scene.rootNode
        )

        if space == .local {
            gizmo.eulerAngles = modelRoot.eulerAngles
        }

        switch mode {
        case .navigate:
            break

        case .move:
            addMoveAxes(to: gizmo)

        case .rotate:
            addRotationRings(to: gizmo)

        case .scale:
            addScaleAxes(to: gizmo)
        }

        scene.rootNode.addChildNode(gizmo)
    }

    private static func material(
        _ color: NSColor
    ) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.emission.contents =
            color.withAlphaComponent(0.2)
        material.lightingModel = .constant
        return material
    }

    private static func orientYAxis(
        _ node: SCNNode,
        axis: String
    ) {
        switch axis {
        case "x":
            node.eulerAngles.z = -.pi / 2

        case "z":
            node.eulerAngles.x = .pi / 2

        default:
            break
        }
    }

    private static func addMoveAxes(
        to gizmo: SCNNode
    ) {
        addMoveAxis(
            to: gizmo,
            axis: "x",
            color: .systemRed
        )

        addMoveAxis(
            to: gizmo,
            axis: "y",
            color: .systemGreen
        )

        addMoveAxis(
            to: gizmo,
            axis: "z",
            color: .systemBlue
        )
    }

    private static func addMoveAxis(
        to parent: SCNNode,
        axis: String,
        color: NSColor
    ) {
        let container = SCNNode()
        container.name =
            "studio-transform-gizmo.move.\(axis)"

        let shaft = SCNCylinder(
            radius: 0.018,
            height: 0.72
        )
        shaft.materials = [material(color)]

        let shaftNode = SCNNode(
            geometry: shaft
        )

        switch axis {
        case "x":
            shaftNode.position =
                SCNVector3(0.36, 0, 0)
            orientYAxis(
                shaftNode,
                axis: axis
            )

        case "z":
            shaftNode.position =
                SCNVector3(0, 0, 0.36)
            orientYAxis(
                shaftNode,
                axis: axis
            )

        default:
            shaftNode.position =
                SCNVector3(0, 0.36, 0)
        }

        container.addChildNode(
            shaftNode
        )

        let arrow = SCNCone(
            topRadius: 0,
            bottomRadius: 0.075,
            height: 0.18
        )
        arrow.materials = [material(color)]

        let handle = SCNNode(
            geometry: arrow
        )

        switch axis {
        case "x":
            handle.position =
                SCNVector3(0.81, 0, 0)
            orientYAxis(
                handle,
                axis: axis
            )

        case "z":
            handle.position =
                SCNVector3(0, 0, 0.81)
            orientYAxis(
                handle,
                axis: axis
            )

        default:
            handle.position =
                SCNVector3(0, 0.81, 0)
        }

        handle.name =
            "studio-transform-gizmo.move.\(axis).handle"

        container.addChildNode(
            handle
        )

        parent.addChildNode(
            container
        )
    }

    private static func addRotationRings(
        to gizmo: SCNNode
    ) {
        addRotationRing(
            to: gizmo,
            axis: "x",
            color: .systemRed
        )

        addRotationRing(
            to: gizmo,
            axis: "y",
            color: .systemGreen
        )

        addRotationRing(
            to: gizmo,
            axis: "z",
            color: .systemBlue
        )
    }

    private static func addRotationRing(
        to parent: SCNNode,
        axis: String,
        color: NSColor
    ) {
        let torus = SCNTorus(
            ringRadius: 0.68,
            pipeRadius: 0.018
        )

        torus.materials = [
            material(color)
        ]

        let ring = SCNNode(
            geometry: torus
        )

        ring.name =
            "studio-transform-gizmo.rotate.\(axis).handle"

        switch axis {
        case "x":
            ring.eulerAngles.z =
                .pi / 2

        case "z":
            ring.eulerAngles.x =
                .pi / 2

        default:
            break
        }

        parent.addChildNode(
            ring
        )
    }

    private static func addScaleAxes(
        to gizmo: SCNNode
    ) {
        addScaleAxis(
            to: gizmo,
            axis: "x",
            color: .systemRed
        )

        addScaleAxis(
            to: gizmo,
            axis: "y",
            color: .systemGreen
        )

        addScaleAxis(
            to: gizmo,
            axis: "z",
            color: .systemBlue
        )

        addUniformScaleHandle(
            to: gizmo
        )
    }

    private static func addUniformScaleHandle(
        to gizmo: SCNNode
    ) {
        let geometry = SCNBox(
            width: 0.16,
            height: 0.16,
            length: 0.16,
            chamferRadius: 0.025
        )

        geometry.materials = [
            material(.systemYellow)
        ]

        let handle = SCNNode(
            geometry: geometry
        )

        handle.name =
            "studio-transform-gizmo.scale.uniform.handle"

        gizmo.addChildNode(
            handle
        )
    }

    private static func addScaleAxis(
        to parent: SCNNode,
        axis: String,
        color: NSColor
    ) {
        let container = SCNNode()
        container.name =
            "studio-transform-gizmo.scale.\(axis)"

        let shaft = SCNCylinder(
            radius: 0.015,
            height: 0.68
        )

        shaft.materials = [
            material(color)
        ]

        let shaftNode = SCNNode(
            geometry: shaft
        )

        switch axis {
        case "x":
            shaftNode.position =
                SCNVector3(0.34, 0, 0)
            orientYAxis(
                shaftNode,
                axis: axis
            )

        case "z":
            shaftNode.position =
                SCNVector3(0, 0, 0.34)
            orientYAxis(
                shaftNode,
                axis: axis
            )

        default:
            shaftNode.position =
                SCNVector3(0, 0.34, 0)
        }

        container.addChildNode(
            shaftNode
        )

        let cube = SCNBox(
            width: 0.11,
            height: 0.11,
            length: 0.11,
            chamferRadius: 0.012
        )

        cube.materials = [
            material(color)
        ]

        let handle = SCNNode(
            geometry: cube
        )

        switch axis {
        case "x":
            handle.position =
                SCNVector3(0.74, 0, 0)

        case "z":
            handle.position =
                SCNVector3(0, 0, 0.74)

        default:
            handle.position =
                SCNVector3(0, 0.74, 0)
        }

        handle.name =
            "studio-transform-gizmo.scale.\(axis).handle"

        container.addChildNode(
            handle
        )

        parent.addChildNode(
            container
        )
    }
}

struct BookPreviewSceneView: NSViewRepresentable {
    let project: CoverProject; let workingLayers: Bool; let binding: BookBinding; let isOpen: Bool; let openAngle: Double
    let pageCount: Int; let spreadIndex: Int
    let turnTransition: BookPageTurnTransition?; let turnTexture: NSImage?; let turnReverseTexture: NSImage?; let turnGeneration: Int
    let leftPage: Int?; let rightPage: Int?; let leftTexture: NSImage?; let rightTexture: NSImage?
    let showMargins: Bool; let thumbMode: ThumbZoneMode; let leftPageSettings: PageSettings; let rightPageSettings: PageSettings; let preset: BookViewPreset; let revisionID: UUID; let resetGeneration: Int
    let focusGeneration: Int; let focus: BookFocusTarget; let zoomAction: CameraZoomAction; let zoomGeneration: Int; @Binding var zoomDisplayScale: Double
    let presentation: BookStudioPresentation
    @Binding var modelTransform: BookModelTransform
    @Binding var transformMode: BookTransformMode
    @Binding var transformSpace: BookTransformSpace
    @Binding var customLights: [BookStudioLight]
    @Binding var selectedCustomLightID: UUID?
    @Binding var savedCamera: BookSavedCamera?
    @Binding var selection: BookSceneComponent?
    let viewportHandle: BookStudioViewportHandle
    var inspection = BookInspectionState()
    var cameraLink: BookInspectionCameraLink? = nil
    var isComparisonViewport = false

    var sourceKey: BookSceneSourceKey {
        BookSceneSourceKey(project: project, workingLayers: workingLayers, binding: binding,
                           isOpen: isOpen, openAngle: openAngle, pageCount: pageCount,
                           spreadIndex: spreadIndex, turnTransition: turnTransition,
                           leftPage: leftPage, rightPage: rightPage,
                           leftTextureID: leftTexture.map(ObjectIdentifier.init),
                           rightTextureID: rightTexture.map(ObjectIdentifier.init),
                           showMargins: showMargins, thumbMode: thumbMode,
                           leftPageSettings: leftPageSettings, rightPageSettings: rightPageSettings,
                           revisionID: revisionID)
    }

    private func scene() -> SCNScene {
        let result = BookPreviewScene.make(project: project, workingLayers: workingLayers, open: isOpen, angle: openAngle, leftPage: leftPage, rightPage: rightPage, pageCount: pageCount, spreadIndex: spreadIndex, leftTexture: leftTexture, rightTexture: rightTexture, margins: showMargins, thumbMode: thumbMode, leftPageSettings: leftPageSettings, rightPageSettings: rightPageSettings, preset: preset, revisionID: revisionID, binding: binding, presentation: presentation)
        BookStudioSceneStyling.addSelectionOutline(to: result, component: selection)
        BookStudioCustomLightScene.apply(
            to: result,
            presentation: presentation,
            selectedCustomLightID:
                selectedCustomLightID
        )
        BookStudioTransformScene.apply(
            to: result,
            presentation: presentation,
            selectedCustomLightID:
                selectedCustomLightID
        )
        BookStudioCustomLightScene.updateMarkerHighlight(
            in: result,
            hovered: nil,
            selected:
                selectedCustomLightID
        )
        let initialCameraState =
            presentation.savedCamera
            .flatMap {
                $0.isValid
                ? BookPreviewCameraState(
                    saved: $0
                )
                : nil
            }
            ?? BookPreviewCameraMath.state(
                project: project,
                open: isOpen,
                preset: preset,
                focus: focus
            )

        BookStudioCameraGuideScene.apply(
            to: result,
            state:
                initialCameraState,
            visible:
                presentation
                .cameraEditorVisible,
            selected:
                selection
                == .camera
        )

        // BOLD_LIVE_SURFACE_FILL_INITIAL_V17D
        // SceneStyling runs after BookPreviewScene.make(), so restore the
        // V17 material fill only after all live initial styling is complete.
        BookPreviewScene.applyBookSurfaceBrightnessFill(
            root:
                result.rootNode
        )
        // BOLD_V23_REAL_LIGHT_ONLY_INITIAL — V20 emission removed; V17 + V22 only.
        // BOLD_REAL_LIVE_BOOK_LIGHTING_INITIAL_V22
        BookPreviewScene.applyRealLiveBookLightingV22(
            to:
                result
        )

        return result
    }

    private func configureInteraction(_ view: BookPreviewInteractionView, coordinator: Coordinator) {
        view.isComparisonViewport = isComparisonViewport
        if coordinator.cameraLink !== cameraLink {
            // A removed peer can remain alive until SwiftUI finishes teardown.
            // Stop delivering events immediately when its link is detached.
            coordinator.cameraLink?.unregister(view)
            coordinator.cameraLink = cameraLink
        }
        view.onViewportResize = { [weak view] aspect in
            guard let view, !coordinator.manualCamera else { return }
            coordinator.cameraState = BookPreviewCameraMath.fitBook(
                coordinator.cameraState, bounds: coordinator.cameraBounds, presentation: presentation, focus: focus,
                viewportAspect: aspect)
            view.setCamera(coordinator.cameraState)
            view.configureCamera(coordinator.cameraState, projection: presentation.projection,
                                 fieldOfView: presentation.cameraFieldOfView)
        }

        let linkedCameraBinding = _savedCamera
        let linkedProjection = presentation.projection
        let linkedFieldOfView = presentation.cameraFieldOfView
        cameraLink?.register(view) { [weak view, weak coordinator] state, commit in
            guard let view, let coordinator else { return }
            coordinator.manualCamera = true
            coordinator.cameraState = state
            view.setCamera(state)
            view.configureCamera(state, projection: linkedProjection, fieldOfView: linkedFieldOfView)
            if commit { linkedCameraBinding.wrappedValue = state.saved }
        }
        view.onOrbit = { [weak view] dx, dy in
            coordinator.manualCamera = true
            coordinator.cameraState.orbit(deltaX: dx, deltaY: dy)
            view?.setCamera(coordinator.cameraState)
            if let view { cameraLink?.send(from: view, state: coordinator.cameraState) }
            view?.configureCamera(coordinator.cameraState, projection: presentation.projection, fieldOfView: presentation.cameraFieldOfView)
        }
        view.onPan = { [weak view] dx, dy, height in
            coordinator.manualCamera = true
            coordinator.cameraState.pan(deltaX: dx, deltaY: dy, viewportHeight: height,
                                        fieldOfView: presentation.cameraFieldOfView)
            view?.setCamera(coordinator.cameraState)
            if let view { cameraLink?.send(from: view, state: coordinator.cameraState) }
        }
        view.onZoom = { [weak view] factor in
            coordinator.manualCamera = true
            coordinator.cameraState.zoom(by: factor, minimum: BookPreviewCameraMath.minimumOrbitDistance(in: coordinator.cameraBounds, target: coordinator.cameraState.target), maximum: 30)
            zoomDisplayScale = min(4, max(0.5, zoomDisplayScale / factor))
            view?.setCamera(coordinator.cameraState)
            if let view { cameraLink?.send(from: view, state: coordinator.cameraState) }
            view?.configureCamera(coordinator.cameraState, projection: presentation.projection, fieldOfView: presentation.cameraFieldOfView)
        }
        view.onSelect = {
            selection =
                $0

            selectedCustomLightID =
                nil
        }

        view.onSelectCamera = {
            selection =
                .camera

            selectedCustomLightID =
                nil
        }

        view.onSelectCustomLight = {
            id in

            selection =
                .lights

            selectedCustomLightID =
                id

            if transformMode == .scale {
                transformMode =
                    .move
            }
        }
        view.onFrameSelection = { [weak view] node in
            coordinator.manualCamera = true
            coordinator.cameraState = BookPreviewCameraMath.frame(
                node, from: coordinator.cameraState, fieldOfView: presentation.cameraFieldOfView,
                viewportAspect: Double((view?.bounds.width ?? 1) / max(1, view?.bounds.height ?? 1)))
            view?.setCamera(coordinator.cameraState, animated: true)
            view?.configureCamera(coordinator.cameraState, projection: presentation.projection,
                                  fieldOfView: presentation.cameraFieldOfView)
            savedCamera = coordinator.cameraState.saved
            if let view { cameraLink?.send(from: view, state: coordinator.cameraState, commit: true) }
        }
        view.onTransformBegin = { mode, axis in
            if
                let selectedCustomLightID,
                let index =
                    customLights
                    .firstIndex(
                        where: {
                            $0.id
                            == selectedCustomLightID
                        }
                    )
            {
                guard
                    !customLights[
                        index
                    ]
                    .locked
                else {
                    coordinator
                        .transformDragStart =
                        nil

                    return
                }

                coordinator.transformDragStart =
                    customLights[
                        index
                    ]
                    .transform
            } else {
                coordinator.transformDragStart =
                    modelTransform
            }

            coordinator.transformDragMode =
                mode

            coordinator.transformDragAxis =
                axis
        }

        view.onTransformDrag = { mode, axis, amount, snapping in
            if
                let selectedCustomLightID,
                let index =
                    customLights
                    .firstIndex(
                        where: {
                            $0.id
                            == selectedCustomLightID
                        }
                    )
            {
                guard
                    !customLights[
                        index
                    ]
                    .locked,
                    mode != .scale
                else {
                    return
                }

                let original =
                    coordinator
                    .transformDragStart
                    ?? customLights[
                        index
                    ]
                    .transform

                customLights[
                    index
                ]
                .transform =
                    BookStudioTransformDragMath
                    .applying(
                        original,
                        mode: mode,
                        axis: axis,
                        amount: amount,
                        space:
                            presentation
                            .transformSpace,
                        snapping:
                            presentation
                            .transformSnapEnabled
                            || snapping,
                        moveSnapStep:
                            presentation
                            .moveSnapStep,
                        rotateSnapStep:
                            presentation
                            .rotateSnapStep,
                        scaleSnapStep:
                            presentation
                            .scaleSnapStep
                    )
            } else {
                let original =
                    coordinator
                    .transformDragStart
                    ?? modelTransform

                modelTransform =
                    BookStudioTransformDragMath
                    .applying(
                        original,
                        mode: mode,
                        axis: axis,
                        amount: amount,
                        space:
                            presentation
                            .transformSpace,
                        snapping:
                            presentation
                            .transformSnapEnabled
                            || snapping,
                        moveSnapStep:
                            presentation
                            .moveSnapStep,
                        rotateSnapStep:
                            presentation
                            .rotateSnapStep,
                        scaleSnapStep:
                            presentation
                            .scaleSnapStep
                    )
            }
        }

        view.onTransformEnded = {
            coordinator.transformDragStart =
                nil

            coordinator.transformDragMode =
                nil

            coordinator.transformDragAxis =
                nil
        }

        view.onTransformModeShortcut = { mode in
            if
                selectedCustomLightID
                    != nil,
                mode == .scale
            {
                return
            }

            transformMode =
                mode
        }

        view.onToggleTransformSpace = {
            transformSpace =
                transformSpace == .local
                ? .world
                : .local
        }

        view.onResetTransform = {
            if
                let selectedCustomLightID,
                let index =
                    customLights
                    .firstIndex(
                        where: {
                            $0.id
                            == selectedCustomLightID
                        }
                    )
            {
                guard
                    !customLights[
                        index
                    ]
                    .locked
                else {
                    return
                }

                customLights[
                    index
                ]
                .transform =
                    .identity
            } else {
                modelTransform =
                    .identity
            }
        }

        view.onNavigationEnded = { [weak view] in
            savedCamera = coordinator.cameraState.saved
            if let view { cameraLink?.send(from: view, state: coordinator.cameraState, commit: true) }
        }
    }

    func makeNSView(context: Context) -> BookPreviewInteractionView {
        makeInteractionView(coordinator: context.coordinator)
    }
    func updateNSView(_ view: BookPreviewInteractionView, context: Context) {
        updateInteractionView(view, coordinator: context.coordinator)
    }
    static func dismantleNSView(_ view: BookPreviewInteractionView, coordinator: Coordinator) {
        coordinator.cameraLink?.unregister(view)
        coordinator.cameraLink = nil
        coordinator.viewportHandle?.releasePreviewResources()
    }
    /// Also used by the opt-in installed viewport acceptance runner.
    func makeInteractionView(coordinator: Coordinator) -> BookPreviewInteractionView {
        let view = BookPreviewInteractionView()
        let initialScene = scene()
        coordinator.cameraBounds = BookPreviewCameraMath.BoundsSnapshot.capture(
            modelRoot: initialScene.rootNode.childNode(withName: BookStudioTransformScene.modelRootName, recursively: true)
        )
        coordinator.styledPresentation = presentation
        view.selectedCustomLightID =
            selectedCustomLightID
        view.refreshCustomLightHighlight()
        view.backgroundColor = presentation.environment.background
        view.configureQuality(presentation.quality)
        viewportHandle.view = view
        viewportHandle.coverProject = project
        coordinator.turnGeneration = turnGeneration
        coordinator.sourceKey = sourceKey
        coordinator.preset = preset; coordinator.resetGeneration = resetGeneration
        coordinator.cameraState = presentation.savedCamera.flatMap { $0.isValid ? BookPreviewCameraState(saved: $0) : nil }
            ?? BookPreviewCameraMath.state(project: project, open: isOpen, preset: preset, focus: focus)
        coordinator.manualCamera = presentation.savedCamera?.isValid == true
        coordinator.lastPresentedCamera = presentation.savedCamera
        if !coordinator.manualCamera {
            coordinator.cameraState = BookPreviewCameraMath.fitBook(
                coordinator.cameraState, bounds: coordinator.cameraBounds, presentation: presentation, focus: focus,
                viewportAspect: view.bounds.height > 0 ? Double(view.bounds.width / view.bounds.height) : 4.0 / 3)
        }
        coordinator.isOpen = isOpen
        configureInteraction(view, coordinator: coordinator)
        view.installScene(initialScene, state: coordinator.cameraState,
                          projection: presentation.projection, fieldOfView: presentation.cameraFieldOfView)
        view.configureCamera(coordinator.cameraState, projection: presentation.projection, fieldOfView: presentation.cameraFieldOfView)
        BookStudioCameraGuideScene.apply(
            to: view.scene,
            state:
                coordinator
                .cameraState,
            visible:
                presentation
                .cameraEditorVisible,
            selected:
                selection
                == .camera
        )
        coordinator.inspectionIssues = BookPrintDanger.inspect(project: project, binding: binding, pageCount: pageCount, edgeIssues: BookPreviewScene.coverTextures(project: project, workingLayers: workingLayers, revisionID: revisionID).edgeIssues)
        BookInspectionScene.apply(inspection, to: initialScene, issues: coordinator.inspectionIssues)
        return view
    }
    func updateInteractionView(_ view: BookPreviewInteractionView, coordinator: Coordinator) {
        let oldState = coordinator.cameraState
        let presetChanged = coordinator.preset != preset
        let reset = coordinator.resetGeneration != resetGeneration
        let focused = coordinator.focusGeneration != focusGeneration
        let stateChanged = coordinator.isOpen != isOpen
        let zoomed = coordinator.zoomGeneration != zoomGeneration
        let effectiveSavedCamera =
            presentation
            .savedCamera

        let savedCameraChanged =
            effectiveSavedCamera?.isValid
                == true
            && effectiveSavedCamera != (cameraLink == nil ? coordinator.cameraState.saved : coordinator.lastPresentedCamera)
        let nextKey = sourceKey
        let replacingScene = coordinator.sourceKey != nextKey || view.scene == nil
        let updatedScene = replacingScene ? scene() : view.scene
        if replacingScene {
            // `scene()` applied this complete presentation while constructing
            // the replacement; record it so the next camera-only update does
            // not repeat the styling traversal.
            coordinator.styledPresentation = presentation
        }
        if !replacingScene, let current = updatedScene {
            let restyle = BookStudioSceneStyling.needsReapplication(
                from: coordinator.styledPresentation,
                to: presentation
            )
            if restyle {
                BookStudioSceneStyling.apply(to: current, presentation: presentation)
                coordinator.styledPresentation = presentation
            }
            BookStudioSceneStyling.addSelectionOutline(to: current, component: selection)
            if restyle {
                // Styling can change the diffuse surface inputs used by these
                // passes. Camera, selection, and transform updates do not.
                BookPreviewScene.applyBookSurfaceBrightnessFill(root: current.rootNode)
                BookPreviewScene.applyRealLiveBookLightingV22(to: current)
            }
        }
        BookStudioCustomLightScene.apply(
            to: updatedScene,
            presentation: presentation,
            selectedCustomLightID:
                selectedCustomLightID
        )
        BookStudioTransformScene.apply(
            to: updatedScene,
            presentation: presentation,
            selectedCustomLightID:
                selectedCustomLightID
        )
        if replacingScene {
            coordinator.cameraBounds = BookPreviewCameraMath.BoundsSnapshot.capture(
                modelRoot: updatedScene?.rootNode.childNode(withName: BookStudioTransformScene.modelRootName, recursively: true)
            )
        } else if let modelRoot = updatedScene?.rootNode.childNode(
            withName: BookStudioTransformScene.modelRootName, recursively: true
        ) {
            coordinator.cameraBounds = coordinator.cameraBounds?.applying(modelRoot.transform)
        }
        view.selectedCustomLightID =
            selectedCustomLightID
        view.backgroundColor = presentation.environment.background
        view.configureQuality(presentation.quality)
        if coordinator.turnGeneration != turnGeneration {
            if let turnTransition, let turnTexture {
                BookPreviewScene.animatePageTurn(in: updatedScene, project: project, pageCount: pageCount, binding: binding, image: turnTexture, reverseImage: turnReverseTexture, transition: turnTransition)
            }
            coordinator.turnGeneration = turnGeneration
        }
        // New scenes receive styling, surface fill, and live lights inside
        // `scene()`. Existing scenes receive them only when a style input above
        // actually changed.

        viewportHandle.view = view
        viewportHandle.coverProject = project
        if
            savedCameraChanged,
            let effectiveSavedCamera,
            effectiveSavedCamera.isValid
        {
            coordinator.cameraState =
                BookPreviewCameraState(
                    saved:
                        effectiveSavedCamera
                )

            coordinator.manualCamera =
                true
        } else if presetChanged || reset || focused || (stateChanged && !coordinator.manualCamera) {
            coordinator.cameraState = BookPreviewCameraMath.state(project: project, open: isOpen, preset: preset, focus: focus)
            if presetChanged || reset || focused { coordinator.manualCamera = false }
        }
        else { coordinator.cameraState = oldState }
        if stateChanged && coordinator.manualCamera {
            let framing = BookPreviewCameraMath.fitBook(coordinator.cameraState, bounds:coordinator.cameraBounds,
                presentation:presentation, viewportAspect:Double(view.bounds.width/max(1,view.bounds.height)))
            coordinator.cameraState.target = framing.target
            // Opening/closing changes the silhouette. Staying outside the
            // geometry alone does not keep it inside the camera frustum.
            // Preserve the orbit and any wider view, but retire a close-up
            // distance that would crop the newly selected book state.
            coordinator.cameraState.distance = max(coordinator.cameraState.distance, framing.distance)
        }
        // A previously close camera must stay outside newly opened geometry.
        let minimumDistance = BookPreviewCameraMath.minimumOrbitDistance(in:coordinator.cameraBounds,target:coordinator.cameraState.target)
        coordinator.cameraState.distance = max(coordinator.cameraState.distance,minimumDistance)
        if zoomed { coordinator.manualCamera = true; coordinator.cameraState.zoom(by: zoomAction == .in ? 0.8 : zoomAction == .out ? 1.25 : 1, minimum: BookPreviewCameraMath.minimumOrbitDistance(in: coordinator.cameraBounds, target: coordinator.cameraState.target), maximum: 30) }
        if !coordinator.manualCamera {
            coordinator.cameraState = BookPreviewCameraMath.fitBook(
                coordinator.cameraState, bounds: coordinator.cameraBounds, presentation: presentation, focus: focus,
                viewportAspect: view.bounds.height > 0 ? Double(view.bounds.width / view.bounds.height) : 4.0 / 3)
        }
        if replacingScene, let updatedScene {
            view.installScene(updatedScene, state: coordinator.cameraState,
                              projection: presentation.projection, fieldOfView: presentation.cameraFieldOfView)
            coordinator.sourceKey = nextKey
        } else {
            view.setCamera(coordinator.cameraState, animated: presetChanged || focused)
        }
        view.refreshTransformHighlight()
        view.refreshCustomLightHighlight()
        configureInteraction(view, coordinator: coordinator)
        view.configureCamera(coordinator.cameraState, projection: presentation.projection, fieldOfView: presentation.cameraFieldOfView)
        BookStudioCameraGuideScene.apply(
            to: updatedScene,
            state:
                coordinator
                .cameraState,
            visible:
                presentation
                .cameraEditorVisible,
            selected:
                selection
                == .camera
        )
        if replacingScene { coordinator.inspectionIssues = BookPrintDanger.inspect(project: project, binding: binding, pageCount: pageCount, edgeIssues: BookPreviewScene.coverTextures(project: project, workingLayers: workingLayers, revisionID: revisionID).edgeIssues) }
        if let updatedScene { BookInspectionScene.apply(inspection, to: updatedScene, issues: coordinator.inspectionIssues) }
        coordinator.lastPresentedCamera = effectiveSavedCamera
        coordinator.preset = preset; coordinator.resetGeneration = resetGeneration; coordinator.focusGeneration = focusGeneration; coordinator.zoomGeneration = zoomGeneration; coordinator.isOpen = isOpen
    }
    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator()
        coordinator.viewportHandle = viewportHandle
        return coordinator
    }
    private func applyCamera(to view: BookPreviewInteractionView, state: BookPreviewCameraState) { view.setCamera(state) }
    final class Coordinator {
        weak var cameraLink: BookInspectionCameraLink?
        weak var viewportHandle: BookStudioViewportHandle?
        var inspectionIssues: [BookPrintDanger] = []
        var lastPresentedCamera: BookSavedCamera?
        var preset: BookViewPreset = .perspective
        var resetGeneration = 0
        var focusGeneration = 0
        var zoomGeneration = 0
        var turnGeneration = 0
        var isOpen = false
        var manualCamera = false
        var sourceKey: BookSceneSourceKey?
        var styledPresentation: BookStudioPresentation?
        var cameraState = BookPreviewCameraState(
            yaw: 0,
            pitch: 0.5,
            distance: 5
        )
        var cameraBounds: BookPreviewCameraMath.BoundsSnapshot?
        var transformDragStart: BookModelTransform?
        var transformDragMode: BookTransformMode?
        var transformDragAxis: BookTransformAxis?
    }
}

enum BookPreviewScene {
    private final class CachedCover: NSObject {
        let project: CoverProject
        let workingLayers: Bool
        let textures: PhysicalBookCoverTextures
        init(project: CoverProject, workingLayers: Bool, textures: PhysicalBookCoverTextures) {
            self.project = project; self.workingLayers = workingLayers; self.textures = textures
        }
        func matchesArtwork(_ other: CoverProject, workingLayers: Bool) -> Bool {
            guard self.workingLayers == workingLayers else { return false }
            var comparable = other
            comparable.id = project.id
            return comparable == project
        }
    }
    private static let coverCache: NSCache<NSString, CachedCover> = {
        let cache = NSCache<NSString, CachedCover>()
        cache.countLimit = 4
        cache.totalCostLimit = 96 * 1024 * 1024
        return cache
    }()
    // A copied cover can have a new project ID but identical artwork. Reuse the
    // most recent raster instead of creating a new GPU texture on every pose.
    private static let recentCoverLock = NSLock()
    private static var recentCover: CachedCover?
    private static let pageEdgeImage: NSImage = {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 256, pixelsHigh: 128,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        for x in 0..<256 {
            let fiber = (x * 29 + x / 7) % 23
            let shade: CGFloat = (x % 4 == 0 ? 0.82 : 0.93) + CGFloat(fiber) / 950
            let color = NSColor(calibratedRed: shade, green: shade * 0.99, blue: shade * 0.965, alpha: 1)
            for y in 0..<128 { bitmap.setColor(color, atX: x, y: y) }
        }
        let image = NSImage(size: NSSize(width: 256, height: 128)); image.addRepresentation(bitmap)
        return image
    }()

    private static let pageStrataImage: NSImage = {
        let width = 384
        let height = 96

        let bitmap =
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: width,
                pixelsHigh: height,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )!

        // X represents the thickness of the page block. Narrow deterministic
        // bands make individual sheet groups readable without creating
        // hundreds of SceneKit page objects.
        for x in 0..<width {
            let separator =
                x % 9 == 0
                || x % 17 == 0
                || x % 31 == 0

            let grain =
                CGFloat(
                    (x * 37 + x / 5) % 23
                )
                / 1100

            let base:
                CGFloat =
                    separator
                        ? 0.88 + grain
                        : 0.94 + grain

            for y in 0..<height {
                let fiber =
                    CGFloat(
                        (x * 7 + y * 13) % 19
                    )
                    / 2800

                let shade =
                    min(
                        0.975,
                        max(
                            0.72,
                            base + fiber
                        )
                    )

                bitmap.setColor(
                    NSColor(
                        calibratedRed: shade,
                        green: shade * 0.992,
                        blue: shade * 0.968,
                        alpha: 1
                    ),
                    atX: x,
                    y: y
                )
            }
        }

        let image =
            NSImage(
                size:
                    NSSize(
                        width: width,
                        height: height
                    )
            )

        image.addRepresentation(
            bitmap
        )

        return image
    }()

    // Tangent-space normals encode direction, not the beige diffuse color.
    // Derive a restrained thickness-direction slope from the existing strata;
    // the neutral direction is (0.5, 0.5, 1), with no invented along-edge slope.
    static let pageStrataNormalImage: NSImage = {
        let source = pageStrataImage.representations.first as! NSBitmapImageRep
        let width = source.pixelsWide, height = source.pixelsHigh
        let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:width,pixelsHigh:height,
            bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,
            colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        let pixels = bitmap.bitmapData!
        let sourcePixels = source.bitmapData!
        for y in 0..<height {
            let sourceRow = y * source.bytesPerRow
            for x in 0..<width {
                // The source is an 8-bit device-RGB bitmap created just above.
                // Read its red channel directly instead of asking AppKit to
                // construct and convert an NSColor for every neighboring pixel.
                let beforeX = (x + width - 1) % width
                let afterX = (x + 1) % width
                let before = Double(sourcePixels[sourceRow + beforeX * 4]) / 255
                let after = Double(sourcePixels[sourceRow + afterX * 4]) / 255
                let slope = Double(before-after)*1.5
                let length = sqrt(1+slope*slope)
                let offset = y*bitmap.bytesPerRow+x*4
                pixels[offset] = UInt8(((slope/length*0.5+0.5)*255).rounded())
                pixels[offset+1] = 128
                pixels[offset+2] = UInt8(((1/length*0.5+0.5)*255).rounded())
                pixels[offset+3] = 255
            }
        }
        let image = NSImage(size:NSSize(width:width,height:height))
        image.addRepresentation(bitmap)
        return image
    }()

    static func coverTextures(project: CoverProject, workingLayers: Bool, revisionID: UUID) -> PhysicalBookCoverTextures {
        _ = revisionID // Kept for the existing caller interface; only cover changes invalidate artwork.
        let key = "\(project.id.uuidString)-\(workingLayers)" as NSString
        if let cached = coverCache.object(forKey: key), cached.project == project {
            recentCoverLock.lock(); recentCover = cached; recentCoverLock.unlock()
            return cached.textures
        }
        recentCoverLock.lock()
        let equivalent = recentCover?.matchesArtwork(project, workingLayers: workingLayers) == true
            ? recentCover?.textures : nil
        recentCoverLock.unlock()
        if let equivalent { return equivalent }
        let rendered = PhysicalBookCoverTextures(project: project, workingLayers: workingLayers, previewDPI: 240)
        let cached = CachedCover(project: project, workingLayers: workingLayers, textures: rendered)
        coverCache.setObject(cached, forKey: key,
                             cost: rendered.estimatedMemoryCost)
        recentCoverLock.lock(); recentCover = cached; recentCoverLock.unlock()
        return rendered
    }

    static func addResolutionIssueBadge(
        to node: SCNNode,
        name: String,
        exteriorFacesPositiveZ: Bool
    ) {
        guard
            node.childNode(
                withName:
                    name,
                recursively: false
            )
            == nil
        else {
            return
        }

        let bounds =
            node.boundingBox

        let width =
            max(
                CGFloat(0.001),
                CGFloat(
                    bounds.max.x
                    - bounds.min.x
                )
            )

        let height =
            max(
                CGFloat(0.001),
                CGFloat(
                    bounds.max.y
                    - bounds.min.y
                )
            )

        let badgeWidth =
            max(
                CGFloat(0.10),
                min(
                    width * 0.42,
                    CGFloat(1.40)
                )
            )

        let badgeHeight =
            max(
                CGFloat(0.035),
                min(
                    height * 0.025,
                    CGFloat(0.10)
                )
            )

        let plane =
            SCNPlane(
                width:
                    badgeWidth,
                height:
                    badgeHeight
            )

        let material =
            SCNMaterial()

        material.diffuse.contents =
            NSColor.systemRed
                .withAlphaComponent(
                    0.78
                )

        material.emission.contents =
            NSColor.systemRed
                .withAlphaComponent(
                    0.18
                )

        material.lightingModel =
            .physicallyBased

        material.roughness.contents =
            0.86

        material.metalness.contents =
            0

        material.isDoubleSided =
            true

        plane.materials = [
            material
        ]

        let badge =
            SCNNode(
                geometry:
                    plane
            )

        badge.name =
            name

        let z:
            CGFloat =
                exteriorFacesPositiveZ
                    ? CGFloat(
                        bounds.max.z
                    )
                        + 0.005
                    : CGFloat(
                        bounds.min.z
                    )
                        - 0.005

        badge.position =
            SCNVector3(
                CGFloat(
                    (
                        bounds.min.x
                        + bounds.max.x
                    )
                    / 2
                ),
                CGFloat(
                    bounds.max.y
                )
                    - badgeHeight
                    * 1.4,
                z
            )

        badge.renderingOrder =
            103

        node.addChildNode(
            badge
        )
    }

    static func addCoverSafeZoneIssueOverlays(
        to coverNode: SCNNode,
        panel: PhysicalBookCoverPanel,
        exteriorFacesPositiveZ: Bool,
        issues: [PhysicalBookCoverSafeIssue]
    ) {
        let matching =
            issues.filter {
                $0.panel == panel
            }

        guard !matching.isEmpty else {
            return
        }

        let bounds =
            coverNode.boundingBox

        let width =
            max(
                CGFloat(0.001),
                CGFloat(
                    bounds.max.x
                    - bounds.min.x
                )
            )

        let height =
            max(
                CGFloat(0.001),
                CGFloat(
                    bounds.max.y
                    - bounds.min.y
                )
            )

        let strip =
            max(
                CGFloat(0.016),
                min(
                    width,
                    height
                )
                * 0.014
            )

        let exteriorZ:
            CGFloat =
                exteriorFacesPositiveZ
                    ? CGFloat(bounds.max.z)
                        + 0.004
                    : CGFloat(bounds.min.z)
                        - 0.004

        let edges =
            Set(
                matching.map(
                    \.edge
                )
            )

        for edge in edges {
            let plane:
                SCNPlane

            let position:
                SCNVector3

            switch edge {
            case .top:
                plane =
                    SCNPlane(
                        width: width,
                        height: strip
                    )

                position =
                    SCNVector3(
                        CGFloat(
                            (
                                bounds.min.x
                                + bounds.max.x
                            )
                            / 2
                        ),
                        CGFloat(bounds.max.y)
                            - strip / 2,
                        exteriorZ
                    )

            case .bottom:
                plane =
                    SCNPlane(
                        width: width,
                        height: strip
                    )

                position =
                    SCNVector3(
                        CGFloat(
                            (
                                bounds.min.x
                                + bounds.max.x
                            )
                            / 2
                        ),
                        CGFloat(bounds.min.y)
                            + strip / 2,
                        exteriorZ
                    )

            case .outer,
                 .spineSide:
                plane =
                    SCNPlane(
                        width: strip,
                        height: height
                    )

                let useMaximumX:
                    Bool

                switch (
                    panel,
                    edge
                ) {
                case (.front, .outer),
                     (.back, .spineSide):
                    useMaximumX =
                        true

                default:
                    useMaximumX =
                        false
                }

                let x =
                    useMaximumX
                        ? CGFloat(bounds.max.x)
                            - strip / 2
                        : CGFloat(bounds.min.x)
                            + strip / 2

                position =
                    SCNVector3(
                        x,
                        CGFloat(
                            (
                                bounds.min.y
                                + bounds.max.y
                            )
                            / 2
                        ),
                        exteriorZ
                    )
            }

            let material =
                SCNMaterial()

            material.diffuse.contents =
                NSColor.systemYellow
                    .withAlphaComponent(
                        0.70
                    )

            material.emission.contents =
                NSColor.systemYellow
                    .withAlphaComponent(
                        0.12
                    )

            material.lightingModel =
                .physicallyBased

            material.roughness.contents =
                0.88

            material.metalness.contents =
                0

            material.isDoubleSided =
                true

            plane.materials = [
                material
            ]

            let node =
                SCNNode(
                    geometry:
                        plane
                )

            node.name =
                "diagnostic.cover."
                + panel.rawValue
                + ".safe."
                + edge.rawValue

            node.position =
                position

            node.renderingOrder =
                102

            coverNode.addChildNode(
                node
            )
        }
    }

    static func addCoverEdgeIssueOverlays(
        to coverNode: SCNNode,
        panel: PhysicalBookCoverPanel,
        exteriorFacesPositiveZ: Bool,
        issues: [PhysicalBookCoverEdgeIssue]
    ) {
        let matching =
            issues.filter {
                $0.panel == panel
            }

        guard !matching.isEmpty else {
            return
        }

        let bounds =
            coverNode.boundingBox

        let width =
            max(
                CGFloat(0.001),
                CGFloat(
                    bounds.max.x
                    - bounds.min.x
                )
            )

        let height =
            max(
                CGFloat(0.001),
                CGFloat(
                    bounds.max.y
                    - bounds.min.y
                )
            )

        let strip =
            max(
                CGFloat(0.020),
                min(
                    width,
                    height
                )
                * 0.018
            )

        let exteriorZ:
            CGFloat =
                exteriorFacesPositiveZ
                    ? CGFloat(bounds.max.z)
                        + 0.003
                    : CGFloat(bounds.min.z)
                        - 0.003

        for issue in matching {
            let plane:
                SCNPlane

            let position:
                SCNVector3

            switch issue.edge {
            case .outer:
                plane =
                    SCNPlane(
                        width: strip,
                        height: height
                    )

                let x:
                    CGFloat =
                        panel == .front
                            ? CGFloat(
                                bounds.max.x
                            )
                                - strip / 2
                            : CGFloat(
                                bounds.min.x
                            )
                                + strip / 2

                position =
                    SCNVector3(
                        x,
                        CGFloat(
                            (
                                bounds.min.y
                                + bounds.max.y
                            )
                            / 2
                        ),
                        exteriorZ
                    )

            case .top:
                plane =
                    SCNPlane(
                        width: width,
                        height: strip
                    )

                position =
                    SCNVector3(
                        CGFloat(
                            (
                                bounds.min.x
                                + bounds.max.x
                            )
                            / 2
                        ),
                        CGFloat(
                            bounds.max.y
                        )
                            - strip / 2,
                        exteriorZ
                    )

            case .bottom:
                plane =
                    SCNPlane(
                        width: width,
                        height: strip
                    )

                position =
                    SCNVector3(
                        CGFloat(
                            (
                                bounds.min.x
                                + bounds.max.x
                            )
                            / 2
                        ),
                        CGFloat(
                            bounds.min.y
                        )
                            + strip / 2,
                        exteriorZ
                    )
            }

            let material =
                SCNMaterial()

            material.diffuse.contents =
                NSColor.systemOrange
                    .withAlphaComponent(
                        0.72
                    )

            material.emission.contents =
                NSColor.systemOrange
                    .withAlphaComponent(
                        0.16
                    )

            material.lightingModel =
                .physicallyBased

            material.roughness.contents =
                0.86

            material.metalness.contents =
                0

            material.isDoubleSided =
                true

            plane.materials = [
                material
            ]

            let node =
                SCNNode(
                    geometry: plane
                )

            node.name =
                "diagnostic.cover."
                + panel.rawValue
                + "."
                + issue.edge.rawValue

            node.position =
                position

            node.renderingOrder =
                100

            coverNode.addChildNode(
                node
            )
        }
    }

    static func softcoverFlexProfile(
        open: Bool,
        angleDegrees: Double
    ) -> (creaseDepth: CGFloat, bowDepth: CGFloat) {
        let closedCrease: CGFloat = 0.006
        let closedBow: CGFloat = 0.002

        guard open else {
            return (
                creaseDepth: closedCrease,
                bowDepth: closedBow
            )
        }

        let safeAngle = angleDegrees.isFinite ? angleDegrees : 0
        let clampedAngle = min(180, max(0, safeAngle))
        let openness = CGFloat(clampedAngle / 180)

        // Keep the previously verified printed-stock curvature for
        // all normal opening angles and the original 180-degree pose.
        let nominalCrease: CGFloat =
            0.006 + 0.0065 * openness
        let nominalBow: CGFloat =
            0.002 + 0.004 * openness

        // Ease only the first half degree. This removes the jump
        // between closed stock and barely open stock, without
        // changing normal-angle surface geometry or contact.
        let reveal = CGFloat(min(1, clampedAngle / 0.5))
        let transition = reveal * reveal * (3 - 2 * reveal)

        return (
            creaseDepth:
                closedCrease
                + (nominalCrease - closedCrease) * transition,
            bowDepth:
                closedBow
                + (nominalBow - closedBow) * transition
        )
    }

    static func flexibleCoverGeometry(
        width: CGFloat,
        height: CGFloat,
        insideEdge: ThumbSide,
        creaseDepth: CGFloat,
        bowDepth: CGFloat,
        depthDirection: CGFloat = 1,
        thickness: CGFloat = 0
    ) -> SCNGeometry {
        // Preserve the established UV and contact topology.
        let segments = 24

        var vertices: [SCNVector3] = []
        vertices.reserveCapacity((segments + 1) * 2)

        var textureCoordinates: [CGPoint] = []
        textureCoordinates.reserveCapacity((segments + 1) * 2)

        for segment in 0...segments {
            let u = CGFloat(segment) / CGFloat(segments)

            let distanceFromSpine =
                insideEdge == .left
                    ? u
                    : 1 - u

            // The scored paperback hinge is concentrated close to the spine.
            // Farther across the cover the stock relaxes into a broad bow.
            let creaseReach = max(
                CGFloat.zero,
                1 - distanceFromSpine / 0.20
            )

            let crease =
                -creaseDepth
                * creaseReach
                * creaseReach

            let broadBow =
                bowDepth
                * CGFloat(
                    sin(
                        Double.pi
                        * Double(distanceFromSpine)
                    )
                )

            // Flex away from the paper support plane. A sign-changing bow
            // put the paperback score line through its page block.
            let localZ = (crease - broadBow) * depthDirection

            let x =
                -width / 2
                + width * u

            vertices.append(
                SCNVector3(
                    x,
                    -height / 2,
                    localZ
                )
            )

            vertices.append(
                SCNVector3(
                    x,
                    height / 2,
                    localZ
                )
            )

            textureCoordinates.append(
                CGPoint(
                    x: u,
                    y: 1
                )
            )

            textureCoordinates.append(
                CGPoint(
                    x: u,
                    y: 0
                )
            )
        }

        var indices: [Int32] = []
        indices.reserveCapacity(segments * 6)

        for segment in 0..<segments {
            let lower = Int32(segment * 2)
            let next = lower + 2

            indices.append(
                contentsOf: [
                    lower,
                    next,
                    next + 1,
                    lower,
                    next + 1,
                    lower + 1
                ]
            )
        }

        let faceCount = vertices.count
        var edges: [Int32] = []
        if thickness > 0 {
            let surface = vertices
            vertices = surface.map { SCNVector3($0.x,$0.y,$0.z + thickness/2) }
                + surface.map { SCNVector3($0.x,$0.y,$0.z - thickness/2) }
            textureCoordinates += textureCoordinates
            for i in 0..<segments {
                for pair in [(i*2,(i+1)*2), (i*2+1,(i+1)*2+1)] {
                    let a = Int32(pair.0), b = Int32(pair.1), offset = Int32(faceCount)
                    edges += [a,a+offset,b,b,a+offset,b+offset]
                }
            }
            for pair in [(0,1),(faceCount-2,faceCount-1)] {
                let a = Int32(pair.0), b = Int32(pair.1), offset = Int32(faceCount)
                edges += [a,b,a+offset,b,b+offset,a+offset]
            }
        }

        let source =
            SCNGeometrySource(
                vertices: vertices
            )

        let uv =
            SCNGeometrySource(
                textureCoordinates:
                    textureCoordinates
            )

        let front =
            SCNGeometryElement(
                indices: indices,
                primitiveType: .triangles
            )

        var backIndices: [Int32] = []
        backIndices.reserveCapacity(indices.count)

        for index in stride(
            from: 0,
            to: indices.count,
            by: 3
        ) {
            backIndices.append(
                contentsOf: [
                    indices[index] + (thickness > 0 ? Int32(faceCount) : 0),
                    indices[index + 2] + (thickness > 0 ? Int32(faceCount) : 0),
                    indices[index + 1] + (thickness > 0 ? Int32(faceCount) : 0)
                ]
            )
        }

        let back =
            SCNGeometryElement(
                indices: backIndices,
                primitiveType: .triangles
            )

        return SCNGeometry(
            sources: [
                source,
                uv
            ],
            elements: [
                front,
                back
            ] + (edges.isEmpty ? [] : [SCNGeometryElement(indices:edges,primitiveType:.triangles)])
        )
    }

    static func pageStackSwellOffset(
        distanceFromGutter: CGFloat
    ) -> CGFloat {
        let distance =
            min(
                1,
                max(
                    0,
                    distanceFromGutter
                )
            )

        // A real bound block does not remain ruler-flat when opened.
        // The sheet pack sits slightly low at the binding, rises into
        // a broad shoulder, then relaxes toward the fore edge.
        let gutterValley =
            -0.00115
            * pow(
                1 - distance,
                7
            )

        let shoulder =
            0.00215
            * sin(
                .pi
                * min(
                    1,
                    distance * 1.18
                )
            )
            * pow(
                1 - distance * 0.48,
                2
            )

        let foreEdgeLift =
            0.00055
            * pow(
                distance,
                8
            )

        return
            gutterValley
            + shoulder
            + foreEdgeLift
    }

    static func pageStackSwellGeometry(
        width: CGFloat,
        height: CGFloat,
        insideEdge: ThumbSide
    ) -> SCNGeometry {
        let segments = 20

        var vertices:
            [SCNVector3] = []

        vertices.reserveCapacity(
            (segments + 1) * 2
        )

        var textureCoordinates:
            [CGPoint] = []

        textureCoordinates.reserveCapacity(
            (segments + 1) * 2
        )

        for segment in 0...segments {
            let u =
                CGFloat(segment)
                / CGFloat(segments)

            let distanceFromGutter =
                insideEdge == .left
                    ? u
                    : 1 - u

            let z =
                pageStackSwellOffset(
                    distanceFromGutter:
                        distanceFromGutter
                )

            let x =
                -width / 2
                + width * u

            vertices.append(
                SCNVector3(
                    x,
                    -height / 2,
                    z
                )
            )

            vertices.append(
                SCNVector3(
                    x,
                    height / 2,
                    z
                )
            )

            textureCoordinates.append(
                CGPoint(
                    x: u,
                    y: 1
                )
            )

            textureCoordinates.append(
                CGPoint(
                    x: u,
                    y: 0
                )
            )
        }

        var indices:
            [Int32] = []

        indices.reserveCapacity(
            segments * 6
        )

        for segment in 0..<segments {
            let lower =
                Int32(
                    segment * 2
                )

            let next =
                lower + 2

            indices.append(
                contentsOf: [
                    lower,
                    next,
                    next + 1,
                    lower,
                    next + 1,
                    lower + 1
                ]
            )
        }

        let source =
            SCNGeometrySource(
                vertices: vertices
            )

        let uv =
            SCNGeometrySource(
                textureCoordinates:
                    textureCoordinates
            )

        let element =
            SCNGeometryElement(
                indices: indices,
                primitiveType:
                    .triangles
            )

        return
            SCNGeometry(
                sources: [
                    source,
                    uv
                ],
                elements: [
                    element
                ]
            )
    }

    static func pageStackBodyOffset(
        distanceFromGutter: CGFloat,
        binding: BookBinding,
        fullness: CGFloat
    ) -> CGFloat {
        let distance =
            min(
                1,
                max(
                    0,
                    distanceFromGutter
                )
            )

        let safeFullness =
            min(
                1,
                max(
                    0,
                    fullness
                )
            )

        let massStrength =
            CGFloat(
                sqrt(
                    Double(
                        max(
                            0.04,
                            safeFullness
                        )
                    )
                )
            )

        // Bound books form their strongest depression immediately beside the
        // sewing/glue line. The deformation then rises into a broad shoulder.
        let gutterDepth =
            (
                binding == .hardcover
                ? CGFloat(0.034)
                : CGFloat(0.050)
            )
            * (
                0.66
                + 0.34
                * massStrength
            )

        let shoulderHeight =
            (
                binding == .hardcover
                ? CGFloat(0.050)
                : CGFloat(0.074)
            )
            * (
                0.60
                + 0.40
                * massStrength
            )

        let foreEdgeLift =
            (
                binding == .hardcover
                ? CGFloat(0.009)
                : CGFloat(0.015)
            )
            * (
                0.58
                + 0.42
                * massStrength
            )

        let gutter =
            -gutterDepth
            * pow(
                1
                - distance,
                5
            )

        // Broad shoulder rather than a single triangular fold.
        let shoulderPhase =
            min(
                1,
                distance
                / 0.92
            )

        let shoulder =
            shoulderHeight
            * sin(
                .pi
                * shoulderPhase
            )
            * (
                1
                - 0.18
                * distance
            )

        // A restrained outer lift prevents the fore edge from terminating as
        // a mathematically flat wall.
        let foreEdge =
            foreEdgeLift
            * pow(
                distance,
                7
            )

        return
            gutter
            + shoulder
            + foreEdge
    }

    static func pageStackLongitudinalOffset(
        verticalPosition: CGFloat,
        distanceFromGutter: CGFloat,
        binding: BookBinding,
        fullness: CGFloat
    ) -> CGFloat {
        let v =
            min(
                1,
                max(
                    0,
                    verticalPosition
                )
            )

        let distance =
            min(
                1,
                max(
                    0,
                    distanceFromGutter
                )
            )

        let safeFullness =
            min(
                1,
                max(
                    0,
                    fullness
                )
            )

        // Zero at the head/tail and strongest through the middle of the page.
        // Squaring the sine keeps the result smooth and restrained.
        let centerWeight =
            pow(
                sin(
                    .pi
                    * v
                ),
                2
            )

        let flexibility =
            binding == .hardcover
            ? CGFloat(0.006)
            : CGFloat(0.011)

        let fullnessStrength =
            CGFloat(
                sqrt(
                    Double(
                        max(
                            0.05,
                            safeFullness
                        )
                    )
                )
            )

        // The longitudinal crown is intentionally weakest right at the gutter
        // and most readable through the page body / fore edge.
        let acrossPageWeight =
            0.18
            + 0.82
            * pow(
                distance,
                0.70
            )

        return
            flexibility
            * centerWeight
            * acrossPageWeight
            * (
                0.55
                + 0.45
                * fullnessStrength
            )
    }

    static func pageGutterFoldDepth(
        binding: BookBinding,
        fullness: CGFloat
    ) -> CGFloat {
        let safeFullness =
            min(
                1,
                max(
                    0,
                    fullness
                )
            )

        let strength =
            CGFloat(
                sqrt(
                    Double(
                        max(
                            0.05,
                            safeFullness
                        )
                    )
                )
            )

        return
            (
                binding == .hardcover
                ? CGFloat(0.018)
                : CGFloat(0.027)
            )
            * (
                0.70
                + 0.30
                * strength
            )
    }

    static func pageGutterFoldGeometry(
        width: CGFloat,
        height: CGFloat,
        depth: CGFloat,
        insideEdge: ThumbSide,
        binding: BookBinding,
        fullness: CGFloat
    ) -> SCNGeometry {
        // BOLD_NARROW_GUTTER_V19 — measured page hinges already meet;
        // keep only a narrow physical crease instead of two 0.30-unit
        // blank overlays covering the printed inner-page surfaces.
        let xSegments =
            12

        let ySegments =
            14

        let stripWidth =
            min(
                width * 0.020,
                CGFloat(0.08)
            )

        let rowWidth =
            xSegments
            + 1

        var vertices:
            [SCNVector3] =
                []

        var textureCoordinates:
            [CGPoint] =
                []

        vertices.reserveCapacity(
            rowWidth
            * (
                ySegments
                + 1
            )
        )

        textureCoordinates.reserveCapacity(
            rowWidth
            * (
                ySegments
                + 1
            )
        )

        let foldDepth =
            pageGutterFoldDepth(
                binding:
                    binding,
                fullness:
                    fullness
            )

        let safeDepth =
            max(
                CGFloat(0.002),
                depth
            )

        for ySegment in
            0...ySegments
        {
            let v =
                CGFloat(
                    ySegment
                )
                / CGFloat(
                    ySegments
                )

            let y =
                -height / 2
                + height
                * v

            for xSegment in
                0...xSegments
            {
                let t =
                    CGFloat(
                        xSegment
                    )
                    / CGFloat(
                        xSegments
                    )

                let physicalDistance =
                    stripWidth
                    * t

                let pageFraction =
                    min(
                        CGFloat(1),
                        physicalDistance
                        / max(
                            width,
                            CGFloat(0.001)
                        )
                    )

                let x:
                    CGFloat

                if insideEdge == .left {
                    x =
                        width / 2
                        - physicalDistance
                } else {
                    x =
                        -width / 2
                        + physicalDistance
                }

                let bodyOffset =
                    pageStackBodyOffset(
                        distanceFromGutter:
                            pageFraction,
                        binding:
                            binding,
                        fullness:
                            fullness
                    )

                let longitudinal =
                    pageStackLongitudinalOffset(
                        verticalPosition:
                            v,
                        distanceFromGutter:
                            pageFraction,
                        binding:
                            binding,
                        fullness:
                            fullness
                    )

                // Strongest at the exact binding and rapidly blends into the
                // broader page-block shoulder.
                let localCrease =
                    -foldDepth
                    * pow(
                        1
                        - t,
                        2.35
                    )

                let z =
                    bodyOffset
                    + longitudinal
                    + safeDepth / 2
                    + localCrease

                vertices.append(
                    SCNVector3(
                        x,
                        y,
                        z
                    )
                )

                textureCoordinates.append(
                    CGPoint(
                        x:
                            t,
                        y:
                            1 - v
                    )
                )
            }
        }

        func index(
            x:
                Int,
            y:
                Int
        ) -> Int32 {
            Int32(
                y
                * rowWidth
                + x
            )
        }

        var indices:
            [Int32] =
                []

        indices.reserveCapacity(
            xSegments
            * ySegments
            * 6
        )

        for y in
            0..<ySegments
        {
            for x in
                0..<xSegments
            {
                let i00 =
                    index(
                        x:
                            x,
                        y:
                            y
                    )

                let i10 =
                    index(
                        x:
                            x + 1,
                        y:
                            y
                    )

                let i01 =
                    index(
                        x:
                            x,
                        y:
                            y + 1
                    )

                let i11 =
                    index(
                        x:
                            x + 1,
                        y:
                            y + 1
                    )

                indices.append(
                    contentsOf:
                        [
                            i00,
                            i10,
                            i11,
                            i00,
                            i11,
                            i01
                        ]
                )
            }
        }

        return SCNGeometry(
            sources:
                [
                    SCNGeometrySource(
                        vertices:
                            vertices
                    ),
                    SCNGeometrySource(
                        textureCoordinates:
                            textureCoordinates
                    )
                ],
            elements:
                [
                    SCNGeometryElement(
                        indices:
                            indices,
                        primitiveType:
                            .triangles
                    )
                ]
        )
    }

    static func pageEndpaperGeometry(
        width: CGFloat,
        height: CGFloat,
        depth: CGFloat,
        insideEdge: ThumbSide,
        binding: BookBinding,
        fullness: CGFloat
    ) -> SCNGeometry {
        let xSegments =
            28

        let ySegments =
            10

        let horizontalOverhang:
            CGFloat =
                binding == .hardcover
                ? 0.050
                : 0

        let verticalOverhang:
            CGFloat =
                binding == .hardcover
                ? 0.050
                : 0

        let renderedWidth =
            width
            + 2
            * horizontalOverhang

        let renderedHeight =
            height
            + 2
            * verticalOverhang

        let rowWidth =
            xSegments
            + 1

        let safeDepth =
            max(
                CGFloat(0.002),
                depth
            )

        var vertices:
            [SCNVector3] =
                []

        var textureCoordinates:
            [CGPoint] =
                []

        vertices.reserveCapacity(
            rowWidth
            * (
                ySegments
                + 1
            )
        )

        textureCoordinates.reserveCapacity(
            rowWidth
            * (
                ySegments
                + 1
            )
        )

        for ySegment in
            0...ySegments
        {
            let v =
                CGFloat(ySegment)
                / CGFloat(ySegments)

            let y =
                -renderedHeight / 2
                + renderedHeight
                * v

            // Longitudinal paper shaping is evaluated against the real trim
            // region, then clamped through the small pastedown overhang.
            let trimV =
                min(
                    1,
                    max(
                        0,
                        (
                            y
                            + height / 2
                        )
                        / max(
                            height,
                            CGFloat(0.001)
                        )
                    )
                )

            for xSegment in
                0...xSegments
            {
                let u =
                    CGFloat(xSegment)
                    / CGFloat(xSegments)

                let x =
                    -renderedWidth / 2
                    + renderedWidth
                    * u
                    + (insideEdge == .left ? -horizontalOverhang : horizontalOverhang)

                let trimU =
                    min(
                        1,
                        max(
                            0,
                            (
                                x
                                + width / 2
                            )
                            / max(
                                width,
                                CGFloat(0.001)
                            )
                        )
                    )

                let distanceFromGutter =
                    insideEdge == .left
                    ? trimU
                    : 1 - trimU

                let bodyOffset =
                    pageStackBodyOffset(
                        distanceFromGutter:
                            distanceFromGutter,
                        binding:
                            binding,
                        fullness:
                            fullness
                    )

                let longitudinal =
                    pageStackLongitudinalOffset(
                        verticalPosition:
                            trimV,
                        distanceFromGutter:
                            distanceFromGutter,
                        binding:
                            binding,
                        fullness:
                            fullness
                    )

                // The endpaper follows the underside of the real paper body.
                // A tiny extra separation avoids z-fighting while still
                // looking physically pasted to the block.
                let z =
                    bodyOffset
                    + longitudinal
                    - safeDepth / 2
                    - (
                        binding == .hardcover
                        ? CGFloat(0.0050)
                        : CGFloat(0.0035)
                    )

                vertices.append(
                    SCNVector3(
                        x,
                        y,
                        z
                    )
                )

                textureCoordinates.append(
                    CGPoint(
                        x:
                            u,
                        y:
                            1 - v
                    )
                )
            }
        }

        func index(
            x:
                Int,
            y:
                Int
        ) -> Int32 {
            Int32(
                y
                * rowWidth
                + x
            )
        }

        var indices:
            [Int32] =
                []

        indices.reserveCapacity(
            xSegments
            * ySegments
            * 6
        )

        for y in
            0..<ySegments
        {
            for x in
                0..<xSegments
            {
                let i00 =
                    index(
                        x:
                            x,
                        y:
                            y
                    )

                let i10 =
                    index(
                        x:
                            x + 1,
                        y:
                            y
                    )

                let i01 =
                    index(
                        x:
                            x,
                        y:
                            y + 1
                    )

                let i11 =
                    index(
                        x:
                            x + 1,
                        y:
                            y + 1
                    )

                indices.append(
                    contentsOf:
                        [
                            i00,
                            i10,
                            i11,
                            i00,
                            i11,
                            i01
                        ]
                )
            }
        }

        return SCNGeometry(
            sources:
                [
                    SCNGeometrySource(
                        vertices:
                            vertices
                    ),
                    SCNGeometrySource(
                        textureCoordinates:
                            textureCoordinates
                    )
                ],
            elements:
                [
                    SCNGeometryElement(
                        indices:
                            indices,
                        primitiveType:
                            .triangles
                    )
                ]
        )
    }

    static func curvedPageStackVolumeGeometry(
        width: CGFloat,
        height: CGFloat,
        depth: CGFloat,
        insideEdge: ThumbSide,
        binding: BookBinding,
        fullness: CGFloat
    ) -> SCNGeometry {
        let xSegments =
            36

        let ySegments =
            14

        let safeDepth =
            max(
                CGFloat(0.002),
                depth
            )

        let rowWidth =
            xSegments
            + 1

        let gridCount =
            rowWidth
            * (
                ySegments
                + 1
            )

        var vertices:
            [SCNVector3] =
                []

        var textureCoordinates:
            [CGPoint] =
                []

        vertices.reserveCapacity(
            gridCount
            * 2
        )

        textureCoordinates.reserveCapacity(
            gridCount
            * 2
        )

        // Build the bottom and top surfaces as two matching 2D lattices.
        //
        // The entire paper block bends through X and Y while maintaining
        // constant physical stack depth between the two surfaces.
        for surface in
            0...1
        {
            let depthSign:
                CGFloat =
                    surface == 0
                    ? -0.5
                    : 0.5

            for ySegment in
                0...ySegments
            {
                let v =
                    CGFloat(
                        ySegment
                    )
                    / CGFloat(
                        ySegments
                    )

                let y =
                    -height / 2
                    + height
                    * v

                for xSegment in
                    0...xSegments
                {
                    let u =
                        CGFloat(
                            xSegment
                        )
                        / CGFloat(
                            xSegments
                        )

                    let distanceFromGutter =
                        insideEdge == .left
                        ? u
                        : 1 - u

                    let crossSection =
                        pageStackBodyOffset(
                            distanceFromGutter:
                                distanceFromGutter,
                            binding:
                                binding,
                            fullness:
                                fullness
                        )

                    let longitudinal =
                        pageStackLongitudinalOffset(
                            verticalPosition:
                                v,
                            distanceFromGutter:
                                distanceFromGutter,
                            binding:
                                binding,
                            fullness:
                                fullness
                        )

                    let x =
                        -width / 2
                        + width
                        * u

                    let z =
                        crossSection
                        + longitudinal
                        + safeDepth
                        * depthSign

                    vertices.append(
                        SCNVector3(
                            x,
                            y,
                            z
                        )
                    )

                    textureCoordinates.append(
                        CGPoint(
                            x:
                                u,
                            y:
                                1 - v
                        )
                    )
                }
            }
        }

        func bottomIndex(
            x:
                Int,
            y:
                Int
        ) -> Int32 {
            Int32(
                y
                * rowWidth
                + x
            )
        }

        func topIndex(
            x:
                Int,
            y:
                Int
        ) -> Int32 {
            Int32(
                gridCount
                + y
                * rowWidth
                + x
            )
        }

        var topIndices:
            [Int32] =
                []

        var bottomIndices:
            [Int32] =
                []

        var headIndices:
            [Int32] =
                []

        var tailIndices:
            [Int32] =
                []

        var gutterIndices:
            [Int32] =
                []

        var foreIndices:
            [Int32] =
                []

        topIndices.reserveCapacity(
            xSegments
            * ySegments
            * 6
        )

        bottomIndices.reserveCapacity(
            xSegments
            * ySegments
            * 6
        )

        for y in
            0..<ySegments
        {
            for x in
                0..<xSegments
            {
                let t00 =
                    topIndex(
                        x:
                            x,
                        y:
                            y
                    )

                let t10 =
                    topIndex(
                        x:
                            x + 1,
                        y:
                            y
                    )

                let t01 =
                    topIndex(
                        x:
                            x,
                        y:
                            y + 1
                    )

                let t11 =
                    topIndex(
                        x:
                            x + 1,
                        y:
                            y + 1
                    )

                topIndices.append(
                    contentsOf:
                        [
                            t00,
                            t10,
                            t11,
                            t00,
                            t11,
                            t01
                        ]
                )

                let b00 =
                    bottomIndex(
                        x:
                            x,
                        y:
                            y
                    )

                let b10 =
                    bottomIndex(
                        x:
                            x + 1,
                        y:
                            y
                    )

                let b01 =
                    bottomIndex(
                        x:
                            x,
                        y:
                            y + 1
                    )

                let b11 =
                    bottomIndex(
                        x:
                            x + 1,
                        y:
                            y + 1
                    )

                bottomIndices.append(
                    contentsOf:
                        [
                            b00,
                            b11,
                            b10,
                            b00,
                            b01,
                            b11
                        ]
                )
            }
        }

        // Head / tail walls.
        for x in
            0..<xSegments
        {
            let bottomTail0 =
                bottomIndex(
                    x:
                        x,
                    y:
                        0
                )

            let bottomTail1 =
                bottomIndex(
                    x:
                        x + 1,
                    y:
                        0
                )

            let topTail0 =
                topIndex(
                    x:
                        x,
                    y:
                        0
                )

            let topTail1 =
                topIndex(
                    x:
                        x + 1,
                    y:
                        0
                )

            tailIndices.append(
                contentsOf:
                    [
                        bottomTail0,
                        bottomTail1,
                        topTail1,
                        bottomTail0,
                        topTail1,
                        topTail0
                    ]
            )

            let bottomHead0 =
                bottomIndex(
                    x:
                        x,
                    y:
                        ySegments
                )

            let bottomHead1 =
                bottomIndex(
                    x:
                        x + 1,
                    y:
                        ySegments
                )

            let topHead0 =
                topIndex(
                    x:
                        x,
                    y:
                        ySegments
                )

            let topHead1 =
                topIndex(
                    x:
                        x + 1,
                    y:
                        ySegments
                )

            headIndices.append(
                contentsOf:
                    [
                        bottomHead0,
                        topHead1,
                        bottomHead1,
                        bottomHead0,
                        topHead0,
                        topHead1
                    ]
            )
        }

        let gutterX =
            insideEdge == .left
            ? 0
            : xSegments

        let foreX =
            insideEdge == .left
            ? xSegments
            : 0

        // Gutter and fore-edge walls now follow the longitudinal page shape,
        // instead of being two perfectly flat rectangles.
        for y in
            0..<ySegments
        {
            let gb0 =
                bottomIndex(
                    x:
                        gutterX,
                    y:
                        y
                )

            let gb1 =
                bottomIndex(
                    x:
                        gutterX,
                    y:
                        y + 1
                )

            let gt0 =
                topIndex(
                    x:
                        gutterX,
                    y:
                        y
                )

            let gt1 =
                topIndex(
                    x:
                        gutterX,
                    y:
                        y + 1
                )

            gutterIndices.append(
                contentsOf:
                    [
                        gb0,
                        gt1,
                        gb1,
                        gb0,
                        gt0,
                        gt1
                    ]
            )

            let fb0 =
                bottomIndex(
                    x:
                        foreX,
                    y:
                        y
                )

            let fb1 =
                bottomIndex(
                    x:
                        foreX,
                    y:
                        y + 1
                )

            let ft0 =
                topIndex(
                    x:
                        foreX,
                    y:
                        y
                )

            let ft1 =
                topIndex(
                    x:
                        foreX,
                    y:
                        y + 1
                )

            foreIndices.append(
                contentsOf:
                    [
                        fb0,
                        fb1,
                        ft1,
                        fb0,
                        ft1,
                        ft0
                    ]
            )
        }

        let vertexSource =
            SCNGeometrySource(
                vertices:
                    vertices
            )

        let textureSource =
            SCNGeometrySource(
                textureCoordinates:
                    textureCoordinates
            )

        // The active manuscript page is already the visible upper sheet.
        //
        // This physical volume exists to supply the paper mass beneath that
        // sheet: bottom, head, tail, gutter and fore edge. Rendering another
        // broad curved top surface causes the two page skins to intersect and
        // lets the volume break through the manuscript page.
        //
        // Preserve geometry element 0 so the established six-element material
        // ordering remains stable, but give that duplicate top region no
        // triangles.
        topIndices.removeAll(
            keepingCapacity:
                false
        )

        let elements =
            [
                SCNGeometryElement(
                    indices:
                        topIndices,
                    primitiveType:
                        .triangles
                ),
                SCNGeometryElement(
                    indices:
                        bottomIndices,
                    primitiveType:
                        .triangles
                ),
                SCNGeometryElement(
                    indices:
                        headIndices,
                    primitiveType:
                        .triangles
                ),
                SCNGeometryElement(
                    indices:
                        tailIndices,
                    primitiveType:
                        .triangles
                ),
                SCNGeometryElement(
                    indices:
                        gutterIndices,
                    primitiveType:
                        .triangles
                ),
                SCNGeometryElement(
                    indices:
                        foreIndices,
                    primitiveType:
                        .triangles
                )
            ]

        return SCNGeometry(
            sources:
                [
                    vertexSource,
                    textureSource,
                    // Edge grain follows sheet thickness, not page width.
                    // Shared face UVs gave head/foot edges vertical bars and
                    // identical coordinates on their lower and upper vertices.
                    SCNGeometrySource(textureCoordinates: vertices.indices.map { index in
                        let grid=index % gridCount
                        return CGPoint(x: index < gridCount ? 0:1,
                            y: CGFloat(grid % rowWidth)/CGFloat(xSegments)
                                + CGFloat(grid / rowWidth)/CGFloat(ySegments))
                    })
                ],
            elements:
                elements
        )
    }

    static func pageEdgeProfileGeometry(
        height: CGFloat
    ) -> SCNGeometry {
        // Normalized visible paper-block fore edge.
        //
        // Local X: -0.5 ... +0.5 across aggregate page-stack thickness.
        // Local Y: full trim height.
        // Local Z: normalized outward bow.
        //
        // updatePageEdgeFan scales X to the LIVE authoritative stack depth
        // and Z to the existing binding/fullness fan envelope.
        let segments =
            32

        var vertices:
            [SCNVector3] =
                []

        var textureCoordinates:
            [CGPoint] =
                []

        vertices.reserveCapacity(
            (segments + 1)
            * 2
        )

        textureCoordinates.reserveCapacity(
            (segments + 1)
            * 2
        )

        for segment in
            0...segments
        {
            let u =
                CGFloat(
                    segment
                )
                / CGFloat(
                    segments
                )

            let centered =
                2
                * u
                - 1

            let bulk =
                max(
                    0,
                    1
                    - centered
                    * centered
                )

            let micro =
                sin(
                    .pi
                    * 4
                    * u
                )
                * 0.055
                * bulk

            let normalizedBow =
                max(
                    0,
                    bulk
                    + micro
                )

            let x =
                u
                - 0.5

            vertices.append(
                SCNVector3(
                    x,
                    -height / 2,
                    normalizedBow
                )
            )

            vertices.append(
                SCNVector3(
                    x,
                    height / 2,
                    normalizedBow
                )
            )

            textureCoordinates.append(
                CGPoint(
                    x:
                        u,
                    y:
                        1
                )
            )

            textureCoordinates.append(
                CGPoint(
                    x:
                        u,
                    y:
                        0
                )
            )
        }

        var indices:
            [Int32] =
                []

        indices.reserveCapacity(
            segments
            * 6
        )

        for segment in
            0..<segments
        {
            let lower =
                Int32(
                    segment
                    * 2
                )

            let next =
                lower
                + 2

            indices.append(
                contentsOf:
                    [
                        lower,
                        next,
                        next + 1,
                        lower,
                        next + 1,
                        lower + 1
                    ]
            )
        }

        let verticesSource =
            SCNGeometrySource(
                vertices:
                    vertices
            )

        let textureSource =
            SCNGeometrySource(
                textureCoordinates:
                    textureCoordinates
            )

        let element =
            SCNGeometryElement(
                indices:
                    indices,
                primitiveType:
                    .triangles
            )

        return SCNGeometry(
            sources:
                [
                    verticesSource,
                    textureSource
                ],
            elements:
                [
                    element
                ]
        )
    }

    static func addReadingVisibleLeafLayers(
        to activePage: SCNNode,
        side: ThumbSide,
        width: CGFloat,
        height: CGFloat,
        valleyDepth: CGFloat,
        shoulderLift: CGFloat,
        foreEdgeCurl: CGFloat,
        binding: BookBinding
    ) {
        let layerCount =
            binding == .hardcover
            ? 5
            : 7

        let sideName =
            side == .left
            ? "left"
            : "right"

        for layerIndex in
            1...layerCount
        {
            let layerFraction =
                CGFloat(layerIndex)
                / CGFloat(layerCount)

            // Every underlying leaf follows the manuscript's exact profile.
            // Independent curvature crossed the printed face near the gutter.
            let geometry =
                curvedPaperGeometry(
                    width:
                        width,
                    height:
                        height,
                    insideEdge:
                        PhysicalBookGeometry.insideEdge(side: side),
                    valleyDepth:
                        valleyDepth,
                    foreEdgeCurl:
                        foreEdgeCurl,
                    shoulderLift:
                        shoulderLift
                )

            let material =
                SCNMaterial()

            let toneShift =
                CGFloat(layerIndex % 3)
                * 0.006

            material.diffuse.contents =
                NSColor(
                    calibratedRed:
                        0.968
                        - toneShift,
                    green:
                        0.953
                        - toneShift
                        * 0.70,
                    blue:
                        0.910
                        - toneShift
                        * 0.45,
                    alpha:
                        1
                )

            material.lightingModel =
                .physicallyBased

            material.roughness.contents =
                0.965
                + 0.003
                * layerFraction

            material.metalness.contents =
                0

            material.isDoubleSided =
                true

            geometry.materials = [
                material
            ]

            let layer =
                SCNNode(
                    geometry:
                        geometry
                )

            layer.name =
                "book."
                + sideName
                + "-visible-leaf-"
                + String(layerIndex)

            layer.position.z =
                -CGFloat(layerIndex)
                * (
                    binding == .hardcover
                    ? 0.0020
                    : 0.00235
                )

            let direction:
                CGFloat =
                    layerIndex % 2 == 0
                    ? 1
                    : -1

            layer.position.x =
                direction
                * CGFloat(layerIndex % 3)
                * (
                    binding == .hardcover
                    ? 0.00055
                    : 0.00085
                )

            layer.position.y =
                direction
                * CGFloat((layerIndex + 1) % 3)
                * (
                    binding == .hardcover
                    ? 0.00035
                    : 0.00055
                )

            layer.castsShadow =
                true

            layer.renderingOrder =
                -layerIndex

            activePage.addChildNode(
                layer
            )
        }
    }

    /// Match each cover to its own paper stack, including unequal early/late
    /// spreads. Mirroring the other stack's center gap moved a cover through
    /// the manuscript whenever the stacks had different thicknesses.
    static func alignOpenCoverSupports(root: SCNNode, thickness: CGFloat) {
        for (coverName, blockName, faceSign) in [
            ("book-shell.front-cover", "book.left-page-block", CGFloat(-1)),
            ("book-shell.back-cover", "book.right-page-block", CGFloat(1))
        ] {
            guard let cover = root.childNode(withName: coverName, recursively: true),
                  let block = root.childNode(withName: blockName, recursively: true),
                  let box = block.geometry as? SCNBox else { continue }
            // Matching only centers leaves the rigid board crossing its own
            // stack at one edge. Its supporting face must share the stack normal.
            let normal = block.convertVector(SCNVector3(0, 0, 1), to: root)
            cover.eulerAngles.y = atan2(faceSign * normal.x, faceSign * normal.z)
            let paperContact = block.convertPosition(SCNVector3(0, 0, -box.length / 2), to: root)
            let coverContact = cover.convertPosition(SCNVector3(0, 0, faceSign * thickness / 2), to: root)
            cover.position.x += paperContact.x - coverContact.x - normal.x * 0.001
            cover.position.z += paperContact.z - coverContact.z - normal.z * 0.001
        }
    }


    // BOLD_BOOK_SURFACE_FILL_V17
    //
    // The Studio can be visually light while a physically-based book material
    // still becomes too dark because its base texture is almost entirely
    // dependent on incident SceneKit lighting. Use a restrained copy of each
    // visible printed surface as emission/self-fill. This preserves the exact
    // diffuse texture and UV transform, keeps real shadows, and prevents the
    // cover/manuscript from being crushed toward black.
    static func applyBookSurfaceBrightnessFill(
        root: SCNNode
    ) {
        root.enumerateChildNodes {
            node,
            _ in

            guard
                let rawName =
                    node.name
            else {
                return
            }

            let name =
                rawName
                .lowercased()

            let isArtwork =
                name.contains(
                    "artwork"
                )
                && (
                    name.contains(
                        "book-shell"
                    )
                    || name.contains(
                        "cover"
                    )
                    || name.contains(
                        "spine"
                    )
                )

            let isPrintedPage =
                name.contains(
                    "active-page"
                )

            let isVisibleLeaf =
                name.contains(
                    "visible-leaf"
                )
                || name.contains(
                    "endpaper"
                )

            guard
                isArtwork
                || isPrintedPage
                || isVisibleLeaf
            else {
                return
            }

            let fillStrength:
                CGFloat

            if isArtwork {
                fillStrength =
                    0.34
            } else if isPrintedPage {
                fillStrength =
                    0.18
            } else {
                fillStrength =
                    0.08
            }

            guard
                let materials =
                    node.geometry?
                    .materials,
                !materials.isEmpty
            else {
                return
            }

            for material in
                materials
            {
                guard
                    let baseContents =
                        material
                        .diffuse
                        .contents
                else {
                    continue
                }

                material
                    .emission
                    .contents =
                    baseContents

                material
                    .emission
                    .intensity =
                    fillStrength

                // Emission must use the exact same cover/page UV mapping.
                // Otherwise transformed cover artwork would be doubled with
                // a differently-oriented self-lit copy.
                material
                    .emission
                    .contentsTransform =
                    material
                    .diffuse
                    .contentsTransform

                material
                    .emission
                    .mappingChannel =
                    material
                    .diffuse
                    .mappingChannel

                material
                    .emission
                    .wrapS =
                    material
                    .diffuse
                    .wrapS

                material
                    .emission
                    .wrapT =
                    material
                    .diffuse
                    .wrapT

                material
                    .emission
                    .minificationFilter =
                    material
                    .diffuse
                    .minificationFilter

                material
                    .emission
                    .magnificationFilter =
                    material
                    .diffuse
                    .magnificationFilter

                material
                    .emission
                    .mipFilter =
                    material
                    .diffuse
                    .mipFilter
            }
        }
    }

    // BOLD_LIVE_BOOK_BRIGHTNESS_V20
    //
    // Live 3D Studio needs a stronger surface fill than export because its
    // interactive SceneKit lighting/styling path is darker. This helper is
    // intentionally called ONLY from the live SwiftUI SceneKit wrapper.
    // Automation/export continues using the restrained V17 values.
    static func applyLiveBookBrightnessV20(
        root:
            SCNNode
    ) {
        root.enumerateChildNodes {
            node,
            _ in

            guard
                let rawName =
                    node.name
            else {
                return
            }

            let name =
                rawName
                .lowercased()

            let isArtwork =
                name.contains(
                    "artwork"
                )
                && (
                    name.contains(
                        "book-shell"
                    )
                    || name.contains(
                        "cover"
                    )
                    || name.contains(
                        "spine"
                    )
                )

            let isPrintedPage =
                name.contains(
                    "active-page"
                )

            let isVisibleLeaf =
                name.contains(
                    "visible-leaf"
                )
                || name.contains(
                    "endpaper"
                )

            let isPaperMass =
                name.contains(
                    "page-block"
                )
                || name.contains(
                    "page-volume"
                )
                || name.contains(
                    "gutter-fold"
                )

            let isCoverBody =
                name.contains(
                    "book-shell"
                )
                && !isArtwork

            let liveIntensity:
                CGFloat

            if isArtwork {
                liveIntensity =
                    0.85
            } else if isPrintedPage {
                liveIntensity =
                    0.42
            } else if isVisibleLeaf {
                liveIntensity =
                    0.22
            } else if isPaperMass {
                liveIntensity =
                    0.12
            } else if isCoverBody {
                liveIntensity =
                    0.18
            } else {
                return
            }

            guard
                let materials =
                    node.geometry?
                    .materials
            else {
                return
            }

            for material in materials {
                guard
                    let diffuseContents =
                        material
                        .diffuse
                        .contents
                else {
                    continue
                }

                material
                    .emission
                    .contents =
                    diffuseContents

                material
                    .emission
                    .contentsTransform =
                    material
                    .diffuse
                    .contentsTransform

                material
                    .emission
                    .mappingChannel =
                    material
                    .diffuse
                    .mappingChannel

                material
                    .emission
                    .wrapS =
                    material
                    .diffuse
                    .wrapS

                material
                    .emission
                    .wrapT =
                    material
                    .diffuse
                    .wrapT

                material
                    .emission
                    .minificationFilter =
                    material
                    .diffuse
                    .minificationFilter

                material
                    .emission
                    .magnificationFilter =
                    material
                    .diffuse
                    .magnificationFilter

                material
                    .emission
                    .mipFilter =
                    material
                    .diffuse
                    .mipFilter

                material
                    .emission
                    .intensity =
                    liveIntensity
            }
        }
    }

    // BOLD_REAL_LIVE_BOOK_LIGHTING_V22
    //
    // V10 changed Reading into a tabletop presentation. The live viewport now
    // needs a book-specific product-light rig aimed at that presentation.
    // These lights use a dedicated category bit so they lift the physical book
    // without bleaching the Studio floor or the rest of the scene.
    static func applyRealLiveBookLightingV22(
        to scene:
            SCNScene
    ) {
        let bookMask =
            1 << 20

        guard
            let bookRoot =
                scene
                .rootNode
                .childNode(
                    withName:
                        "physical-book.root",
                    recursively:
                        true
                )
        else {
            return
        }

        let exposureScale: CGFloat = (bookRoot.value(forKey:"physicalBookOpen") as? Bool == true) ? 0.5:1

        bookRoot.categoryBitMask =
            bookRoot.categoryBitMask
            | bookMask

        bookRoot.enumerateChildNodes {
            node,
            _ in

            node.categoryBitMask =
                node.categoryBitMask
                | bookMask
        }

        func configuredLight(
            named name:
                String,
            type:
                SCNLight.LightType,
            intensity:
                CGFloat
        ) -> SCNNode {
            let node:
                SCNNode

            if let existing =
                scene
                .rootNode
                .childNode(
                    withName:
                        name,
                    recursively:
                        true
                )
            {
                node =
                    existing
            } else {
                node =
                    SCNNode()

                node.name =
                    name
            }

            if node.light == nil {
                node.light =
                    SCNLight()
            }

            node.light?.type =
                type

            node.light?.intensity =
                intensity * exposureScale

            node.light?.color =
                NSColor.white

            node.light?.temperature =
                5_700

            node.light?.castsShadow =
                false

            node.light?.categoryBitMask =
                bookMask

            return node
        }

        let ambient =
            configuredLight(
                named:
                    "studio-light.live-book-ambient-v22",
                type:
                    .ambient,
                intensity:
                    60
            )

        if ambient.parent == nil {
            scene
                .rootNode
                .addChildNode(
                    ambient
                )
        }

        let overhead =
            configuredLight(
                named:
                    "studio-light.live-book-overhead-v22",
                type:
                    .directional,
                intensity:
                    180
            )

        overhead.eulerAngles =
            SCNVector3(
                -Float.pi / 2,
                0,
                0
            )

        if overhead.parent == nil {
            scene
                .rootNode
                .addChildNode(
                    overhead
                )
        }

        if let camera =
            scene
            .rootNode
            .childNode(
                withName:
                    "preview-camera",
                recursively:
                    true
            )
        {
            let frontFill:
                SCNNode

            if let existing =
                camera
                .childNode(
                    withName:
                        "studio-light.live-book-camera-fill-v22",
                    recursively:
                        false
                )
            {
                frontFill =
                    existing
            } else {
                frontFill =
                    SCNNode()

                frontFill.name =
                    "studio-light.live-book-camera-fill-v22"

                camera.addChildNode(
                    frontFill
                )
            }

            if frontFill.light == nil {
                frontFill.light =
                    SCNLight()
            }

            frontFill.light?.type =
                .directional

            frontFill.light?.intensity =
                240 * exposureScale

            frontFill.light?.color =
                NSColor.white

            frontFill.light?.temperature =
                5_900

            frontFill.light?.castsShadow =
                false

            frontFill.light?.categoryBitMask =
                bookMask

            frontFill.eulerAngles =
                SCNVector3(
                    0.08,
                    -0.10,
                    0
                )
        }

        // Keep the live Reading workspace visually light. This intentionally
        // affects only the interactive Studio helper path, not normal export.
        scene.background.contents =
            NSColor(
                calibratedWhite:
                    0.84,
                alpha:
                    1
            )

        if
            let ground =
                scene
                .rootNode
                .childNode(
                    withName:
                        "studio-ground",
                    recursively:
                        true
                ),
            let material =
                ground
                .geometry?
                .firstMaterial
        {
            material.diffuse.contents =
                NSColor(
                    calibratedWhite:
                        0.80,
                    alpha:
                        1
                )
        }
    }



    /// Page faces move along their stack's rotated normal, not world Z. Using
    /// independent world-Z offsets made the manuscript float away from the
    /// page block as the opening angle approached a closed book.
    /// Keep both paper assemblies bound to the same hinge after support/contact
    /// corrections. Matching board centers alone lets the right hinge wander
    /// when its pivot is rotated, stretching a one-inch spine into a wide panel.
    static func alignOpenBindingEdges(root: SCNNode, hingeZ: CGFloat, leftHingeZ: CGFloat? = nil, openingProgress: CGFloat = 1, hingeOffset: CGFloat = 0) {
        for (side,edgeSign) in [("left",CGFloat(1)),("right",CGFloat(-1))] {
            guard let block = root.childNode(withName:"book.\(side)-page-block",recursively:true),
                  let box = block.geometry as? SCNBox,
                  let cover = root.childNode(withName:side == "left" ? "book-shell.front-cover":"book-shell.back-cover",recursively:false) else { continue }
            let edge = block.convertPosition(SCNVector3(edgeSign*box.width/2,0,-box.length/2),to:root)
            let targetZ = side == "left" ? (leftHingeZ ?? hingeZ) : hingeZ
            let dx = -edgeSign*hingeOffset-edge.x, dz = targetZ-edge.z
            if side == "left", let assembly = block.parent, assembly !== root {
                assembly.position.x += dx; assembly.position.z += dz
            } else {
                block.position.x += dx; block.position.z += dz
                if let page = root.childNode(withName:"book.right-active-page",recursively:false) {
                    page.position.x += dx; page.position.z += dz
                }
            }
            cover.position.x += dx; cover.position.z += dz
            // Case overhang belongs at the fore edge of an open board. Leaving
            // both inner overhangs across X=0 made rigid boards overlap in the
            // fully open rest pose. Slide along the support plane, preserving
            // its normal contact and the canonical paper binding origin.
            let bounds = cover.geometry?.boundingBox ?? cover.boundingBox
            let overhang = max(0, (bounds.max.x - bounds.min.x - box.width) / 2)
            let u = min(1, max(0, openingProgress * 2))
            let tangent = cover.convertVector(SCNVector3(overhang * u*u*(3-2*u),0,0), to: root)
            cover.position.x += tangent.x; cover.position.z += tangent.z
        }
    }

    static func alignOpenPrintedSurfaces(root: SCNNode) {
        for side in ["left", "right"] {
            guard let page = root.childNode(withName: "book.\(side)-active-page", recursively: true),
                  let block = root.childNode(withName: "book.\(side)-page-block", recursively: true),
                  let box = block.geometry as? SCNBox,
                  let parent = page.parent, block.parent === parent else { continue }
            let normal = block.convertVector(SCNVector3(0, 0, box.length / 2 + 0.004), to: parent)
            page.pivot = block.pivot
            page.eulerAngles = block.eulerAngles
            page.position = SCNVector3(block.position.x + normal.x,
                                      block.position.y + normal.y,
                                      block.position.z + normal.z)
        }
    }

    static func alignReadingBackCoverToRightPageBlock(
        root: SCNNode
    ) {
        guard
            let backCover =
                root.childNode(
                    withName:
                        "book-shell.back-cover",
                    recursively:
                        true
                ),
            let rightPageBlock =
                root.childNode(
                    withName:
                        "book.right-page-block",
                    recursively:
                        true
                ),
            backCover.parent === root
        else {
            return
        }

        let coverBounds =
            backCover.geometry?.boundingBox
            ?? backCover.boundingBox

        let pageBounds =
            rightPageBlock.geometry?.boundingBox
            ?? rightPageBlock.boundingBox

        let coverCenterY:
            CGFloat =
                (
                    coverBounds.min.y
                    + coverBounds.max.y
                )
                / 2

        let coverCenterZ:
            CGFloat =
                (
                    coverBounds.min.z
                    + coverBounds.max.z
                )
                / 2

        let pageCenterY:
            CGFloat =
                (
                    pageBounds.min.y
                    + pageBounds.max.y
                )
                / 2

        let pageCenterZ:
            CGFloat =
                (
                    pageBounds.min.z
                    + pageBounds.max.z
                )
                / 2

        let coverNegative =
            backCover.convertPosition(
                SCNVector3(
                    coverBounds.min.x,
                    coverCenterY,
                    coverCenterZ
                ),
                to:
                    root
            )

        let coverPositive =
            backCover.convertPosition(
                SCNVector3(
                    coverBounds.max.x,
                    coverCenterY,
                    coverCenterZ
                ),
                to:
                    root
            )

        let pageNegative =
            rightPageBlock.convertPosition(
                SCNVector3(
                    pageBounds.min.x,
                    pageCenterY,
                    pageCenterZ
                ),
                to:
                    root
            )

        let pagePositive =
            rightPageBlock.convertPosition(
                SCNVector3(
                    pageBounds.max.x,
                    pageCenterY,
                    pageCenterZ
                ),
                to:
                    root
            )

        let coverInnerX:
            CGFloat =
                abs(
                    coverNegative.x
                )
                <= abs(
                    coverPositive.x
                )
                ? coverNegative.x
                : coverPositive.x

        let pageInnerX:
            CGFloat =
                abs(
                    pageNegative.x
                )
                <= abs(
                    pagePositive.x
                )
                ? pageNegative.x
                : pagePositive.x

        let coverWidth:
            CGFloat =
                max(
                    0,
                    coverBounds.max.x
                    - coverBounds.min.x
                )

        let pageWidth:
            CGFloat =
                max(
                    0,
                    pageBounds.max.x
                    - pageBounds.min.x
                )

        let localOverhang:
            CGFloat =
                max(
                    0,
                    (
                        coverWidth
                        - pageWidth
                    )
                    / 2
                )

        let coverLocalCenter =
            SCNVector3(
                (
                    coverBounds.min.x
                    + coverBounds.max.x
                )
                / 2,
                coverCenterY,
                coverCenterZ
            )

        let coverCenterRoot =
            backCover.convertPosition(
                coverLocalCenter,
                to:
                    root
            )

        let coverXAxisRoot =
            backCover.convertPosition(
                SCNVector3(
                    coverLocalCenter.x + 1,
                    coverLocalCenter.y,
                    coverLocalCenter.z
                ),
                to:
                    root
            )

        let xProjection:
            CGFloat =
                abs(
                    coverXAxisRoot.x
                    - coverCenterRoot.x
                )

        let targetInnerX:
            CGFloat =
                pageInnerX
                - localOverhang
                * xProjection

        let correctionX:
            CGFloat =
                targetInnerX
                - coverInnerX

        backCover.position.x +=
            correctionX

        backCover.setValue(
            NSNumber(
                value:
                    Double(
                        correctionX
                    )
            ),
            forKey:
                "bookReadingBackCoverAlignmentX"
        )

        backCover.setValue(
            NSNumber(
                value:
                    Double(
                        targetInnerX
                    )
            ),
            forKey:
                "bookReadingBackCoverTargetInnerX"
        )
    }

    static func make(project: CoverProject, workingLayers: Bool, open requestedOpen: Bool, angle requestedAngle: Double, leftPage: Int?, rightPage: Int?, pageCount: Int, spreadIndex: Int, leftTexture: NSImage?, rightTexture: NSImage?, margins: Bool, thumbMode: ThumbZoneMode, leftPageSettings: PageSettings, rightPageSettings: PageSettings, preset: BookViewPreset, revisionID: UUID, binding: BookBinding = .softcover, presentation: BookStudioPresentation = BookStudioPresentation()) -> SCNScene {
        let safeAngle = requestedAngle.isFinite ? min(180, max(0, requestedAngle)) : 180
        let open = requestedOpen && safeAngle > 0
        let openingProgress = open ? safeAngle / 180 : 0
        // BOLD_WRITER_V25_TRUE_CLOSED_SCENE
        //
        // Closed is an absolute physical state. A stale slider value or
        // automation angle must never leave the boards partly open.
        let angle =
            open
            ? safeAngle
            : 0

        let scene = SCNScene(); let sceneRoot = scene.rootNode
        let root = SCNNode(); root.name = "physical-book.root"; root.setValue(open,forKey:"physicalBookOpen"); sceneRoot.addChildNode(root)

        // Changing the camera must not replace the physical book geometry.
        // Every open view uses the same curved, bound page assembly.
        let readingPhysicalPreview = open

        let readingPageCurveScale:
            CGFloat =
                readingPhysicalPreview
                ? (
                    binding == .hardcover
                    ? 3.2
                    : 4.2
                )
                : 1

        let readingPageValleyFloor:
            CGFloat =
                readingPhysicalPreview
                ? (
                    binding == .hardcover
                    ? 0.030 * openingProgress
                    : 0.042 * openingProgress
                )
                : 0

        let readingPageShoulderFloor:
            CGFloat =
                readingPhysicalPreview
                ? (
                    binding == .hardcover
                    ? 0.046 * openingProgress
                    : 0.064 * openingProgress
                )
                : 0

        let readingForeEdgeFloor:
            CGFloat =
                readingPhysicalPreview
                ? (
                    binding == .hardcover
                    ? 0.010 * openingProgress
                    : 0.016 * openingProgress
                )
                : 0

        let leftLeaves = SCNNode(); leftLeaves.name = "book.left-leaves"; root.addChildNode(leftLeaves)
        let geometry = PhysicalBookGeometry(project: project), scale: Double = 0.7
        // BOLD_KDP_SCENE_DEPTH_V24B
        let width =
            CGFloat(
                geometry.trimWidth
                * scale
            )
        let height =
            CGFloat(
                geometry.trimHeight
                * scale
            )
        let thick =
            CGFloat(
                geometry
                .outerBookDepth(
                    for:
                        binding
                )
                * scale
            )
        // BOLD_WRITER_V27B_KDP_CASE_SCENE
        let coverHorizontalOverhang =
            CGFloat(
                geometry
                    .coverHorizontalOverhang(
                        for:
                            binding
                    )
                * scale
            )

        let coverVerticalOverhang =
            CGFloat(
                geometry
                    .coverVerticalOverhang(
                        for:
                            binding
                    )
                * scale
            )

        let hardcoverHingeChannel =
            CGFloat(
                geometry
                    .hardcoverHingeChannelWidth(
                        for:
                            binding
                    )
                * scale
            )

        let textures = coverTextures(project: project, workingLayers: workingLayers, revisionID: revisionID)
        let stock = geometry.coverThickness(for: binding)
        let pose =
            geometry.physicalPose(
                open:
                    open,
                angleDegrees:
                    angle,
                pageCount:
                    pageCount,
                spreadIndex:
                    spreadIndex,
                binding:
                    binding
            )

        let stacks =
            pose.stacks
        if thick > 0 {
            let blockDepth =
                max(
                    0.001,
                    CGFloat(
                        geometry
                        .pageBlockDepth(
                            for:
                                binding
                        )
                        * scale
                    )
                )
            let paperMaterial = SCNMaterial()
            paperMaterial.diffuse.contents =
                NSColor(
                    calibratedRed: 0.955,
                    green: 0.948,
                    blue: 0.925,
                    alpha: 1
                )
            paperMaterial.lightingModel = .physicallyBased
            paperMaterial.roughness.contents = 0.94
            paperMaterial.metalness.contents = 0
            paperMaterial.diffuse.minificationFilter = .linear
            paperMaterial.diffuse.magnificationFilter = .linear
            paperMaterial.diffuse.mipFilter = .linear

            let edgeMaterial = SCNMaterial()
            edgeMaterial.diffuse.contents = pageEdgeImage
            edgeMaterial.lightingModel = .physicallyBased
            edgeMaterial.roughness.contents = 0.97
            edgeMaterial.metalness.contents = 0
            edgeMaterial.diffuse.minificationFilter = .linear
            edgeMaterial.diffuse.magnificationFilter = .linear

            func addPaperEdgeStrata(
                to blockNode: SCNNode,
                side: ThumbSide,
                blockWidth: CGFloat,
                blockHeight: CGFloat,
                blockDepth: CGFloat,
                name: String
            ) {
                guard blockDepth > 0.001 else {
                    return
                }

                let strata =
                    SCNPlane(
                        width:
                            max(
                                0.002,
                                blockDepth
                            ),
                        height:
                            blockHeight
                    )

                let material =
                    SCNMaterial()

                material.diffuse.contents =
                    pageStrataImage

                material.lightingModel =
                    .physicallyBased

                material.roughness.contents =
                    0.97

                material.metalness.contents =
                    0

                material.isDoubleSided =
                    false

                material.diffuse.wrapS =
                    .repeat

                material.diffuse.wrapT =
                    .repeat

                material.diffuse.minificationFilter =
                    .linear

                material.diffuse.magnificationFilter =
                    .linear

                material.diffuse.mipFilter =
                    .linear

                strata.materials = [
                    material
                ]

                let detail =
                    SCNNode(
                        geometry: strata
                    )

                detail.name =
                    name

                let outsideX =
                    side == .left
                        ? -blockWidth / 2 - 0.0012
                        : blockWidth / 2 + 0.0012

                detail.position =
                    SCNVector3(
                        outsideX,
                        0,
                        0
                    )

                detail.eulerAngles.y =
                    side == .left
                        ? -.pi / 2
                        : .pi / 2

                if name == "book.left-page-edge-strata"
                    || name == "book.right-page-edge-strata"
                {
                    let profileGeometry =
                        pageEdgeProfileGeometry(
                            height:
                                blockHeight
                        )

                    let profileMaterial =
                        material.copy()
                        as! SCNMaterial

                    profileMaterial.isDoubleSided =
                        true

                    profileGeometry.materials = [
                        profileMaterial
                    ]

                    let profile =
                        SCNNode(
                            geometry:
                                profileGeometry
                        )

                    profile.name =
                        name
                        + ".profile"

                    profile.scale =
                        SCNVector3(
                            max(
                                0.002,
                                blockDepth
                            ),
                            1,
                            0.001
                        )

                    // detail already owns the left/right ±90° rotation.
                    // Positive local Z therefore points toward the physical
                    // outside edge on both sides of the open book.
                    profile.position.z =
                        0.000_35

                    profile.renderingOrder =
                        2

                    detail.addChildNode(
                        profile
                    )
                }

                blockNode.addChildNode(
                    detail
                )

                // The head and tail reveal the same sheet stack as the fore
                // edge. Map the texture's narrow bands across Z, the actual
                // thickness axis, so they do not look like lines across a page.
                func cap(atTop: Bool) -> SCNNode {
                    let y = (atTop ? 1 : -1) * (blockHeight / 2 + 0.002)
                    let vertices = [
                        SCNVector3(-blockWidth / 2, 0, -blockDepth / 2),
                        SCNVector3(blockWidth / 2, 0, -blockDepth / 2),
                        SCNVector3(blockWidth / 2, 0, blockDepth / 2),
                        SCNVector3(-blockWidth / 2, 0, blockDepth / 2)
                    ]
                    let uv = [
                        CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 1),
                        CGPoint(x: 1, y: 1), CGPoint(x: 1, y: 0)
                    ]
                    let indices: [Int32] = atTop
                        ? [0, 2, 1, 0, 3, 2]
                        : [0, 1, 2, 0, 2, 3]
                    let geometry = SCNGeometry(
                        sources: [SCNGeometrySource(vertices: vertices),
                                  SCNGeometrySource(textureCoordinates: uv)],
                        elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
                    )
                    geometry.materials = [material]
                    let node = SCNNode(geometry: geometry)
                    node.name = name + (atTop ? ".head" : ".tail")
                    node.position.y = y
                    return node
                }

                blockNode.addChildNode(cap(atTop: true))
                blockNode.addChildNode(cap(atTop: false))
            }

            if open {
                func stack(_ depth: Double, centerX: CGFloat, centerZ: CGFloat) {
                    let isEmptyPhysicalStack =
                        depth <= 0.0001

                    let blockWidth = width
                    let blockHeight = height

                    // Keep a real transform/contact anchor even when this side
                    // contains zero pages. SceneKit gets a tiny stable box,
                    // while the node itself is hidden so no fake page is drawn.
                    let blockDepth =
                        max(
                            CGFloat(
                                depth * scale
                            ),
                            CGFloat(0.0001)
                        )

                    let block =
                        SCNBox(
                            width: blockWidth,
                            height: blockHeight,
                            length: blockDepth,
                            chamferRadius: 0.004
                        )

                    // The support box is hidden in Reading, but its paper
                    // materials are also the prototypes for the visible stack.
                    // Give the box its own copies before changing transparency
                    // and depth writes; otherwise the rendered paper disappears.
                    block.materials = [
                        paperMaterial,
                        edgeMaterial,
                        paperMaterial,
                        edgeMaterial,
                        edgeMaterial,
                        edgeMaterial
                    ].map { $0.copy() as! SCNMaterial }

                    if readingPhysicalPreview {
                        // Keep the box as authoritative geometry while
                        // removing the rectangular slab from the rendered
                        // Reading silhouette. Child paper surfaces stay visible.
                        for material in
                            block.materials
                        {
                            material.transparency =
                                0

                            material.writesToDepthBuffer =
                                false

                            material.readsFromDepthBuffer =
                                false
                        }
                    }


                    let node =
                        SCNNode(
                            geometry: block
                        )

                    let side:
                        ThumbSide =
                            centerX < 0
                                ? .left
                                : .right

                    node.name =
                        side == .left
                            ? "book.left-page-block"
                            : "book.right-page-block"

                    node.position =
                        SCNVector3(
                            centerX,
                            height / 2,
                            centerZ
                        )

                    // Empty edge stacks exist only as physical support anchors.
                    // Hiding the parent suppresses all decorative child geometry.
                    node.isHidden =
                        isEmptyPhysicalStack

                    let swellGeometry =
                        pageStackSwellGeometry(
                            width:
                                blockWidth,
                            height:
                                blockHeight,
                            insideEdge:
                                PhysicalBookGeometry
                                    .insideEdge(
                                        side:
                                            side
                                    )
                        )

                    let swellMaterial =
                        SCNMaterial()

                    swellMaterial.diffuse.contents =
                        NSColor(
                            calibratedRed: 0.945,
                            green: 0.935,
                            blue: 0.905,
                            alpha: 1
                        )

                    swellMaterial.lightingModel =
                        .physicallyBased

                    swellMaterial.roughness.contents =
                        0.965

                    swellMaterial.metalness.contents =
                        0

                    swellMaterial.isDoubleSided =
                        false

                    swellGeometry.materials = [
                        swellMaterial
                    ]

                    let swellNode =
                        SCNNode(
                            geometry:
                                swellGeometry
                        )

                    swellNode.name =
                        side == .left
                            ? "book.left-page-stack-swell"
                            : "book.right-page-stack-swell"

                    // The active manuscript page already sits 0.004 above
                    // the mathematical stack surface. Keep the physical
                    // swell under that face so no print texture is hidden.
                    swellNode.position =
                        SCNVector3(
                            0,
                            0,
                            blockDepth / 2
                                + 0.00145
                        )

                                        let readingStackSwellScale:
                        CGFloat =
                            readingPhysicalPreview
                            ? (
                                binding == .hardcover
                                ? 11
                                : 15
                            )
                            : 1

                    swellNode.scale.z =
                        readingStackSwellScale

node.addChildNode(
                        swellNode
                    )

                                        if readingPhysicalPreview {
                        let totalVisibleDepth =
                            max(
                                CGFloat(0.002),
                                CGFloat(
                                    geometry
                                    .pageBlockDepth(
                                        for:
                                            binding
                                    )
                                    * scale
                                )
                            )

                        let visibleFullness =
                            min(
                                CGFloat(1),
                                max(
                                    CGFloat(0),
                                    block.length
                                    / totalVisibleDepth
                                )
                            )

                        let volumeGeometry =
                            curvedPageStackVolumeGeometry(
                                width:
                                    block.width,
                                height:
                                    block.height,
                                depth:
                                    block.length,
                                insideEdge:
                                    side,
                                binding:
                                    binding,
                                fullness:
                                    visibleFullness
                            )

                        let volumePaperMaterial =
                            paperMaterial.copy()
                            as! SCNMaterial

                        volumePaperMaterial.diffuse.contents =
                            NSColor(
                                calibratedRed:
                                    0.970,
                                green:
                                    0.952,
                                blue:
                                    0.905,
                                alpha:
                                    1
                            )

                        volumePaperMaterial.lightingModel =
                            .physicallyBased

                        volumePaperMaterial.roughness.contents =
                            0.96

                        volumePaperMaterial.metalness.contents =
                            0

                        volumePaperMaterial.isDoubleSided =
                            true

                        let volumeEdgeMaterial =
                            volumePaperMaterial.copy()
                            as! SCNMaterial

                        volumeEdgeMaterial.diffuse.contents =
                            pageStrataImage
                        volumeEdgeMaterial.diffuse.mappingChannel = 1

                        volumeEdgeMaterial.diffuse.wrapS =
                            .repeat

                        volumeEdgeMaterial.diffuse.wrapT =
                            .repeat

                        volumeEdgeMaterial.diffuse.minificationFilter =
                            .linear

                        volumeEdgeMaterial.diffuse.magnificationFilter =
                            .linear

                        volumeEdgeMaterial.diffuse.mipFilter =
                            .linear

                        volumeEdgeMaterial.roughness.contents =
                            0.985

                        // Small real tangent-space slopes give sheet bands
                        // depth without tilting the entire edge's lighting.
                        volumeEdgeMaterial.normal.contents =
                            pageStrataNormalImage
                        volumeEdgeMaterial.normal.mappingChannel = 1

                        volumeEdgeMaterial.normal.wrapS =
                            .repeat

                        volumeEdgeMaterial.normal.wrapT =
                            .repeat

                        volumeEdgeMaterial.normal.minificationFilter =
                            .linear

                        volumeEdgeMaterial.normal.magnificationFilter =
                            .linear

                        volumeEdgeMaterial.normal.mipFilter =
                            .linear

                        volumeEdgeMaterial.normal.intensity =
                            0.16

                        // Element order:
                        // top, bottom, head, tail, gutter, fore.
                        volumeGeometry.materials = [
                            volumePaperMaterial,
                            volumePaperMaterial,
                            volumeEdgeMaterial,
                            volumeEdgeMaterial,
                            volumeEdgeMaterial,
                            volumeEdgeMaterial
                        ]

                        let visibleVolume =
                            SCNNode(
                                geometry:
                                    volumeGeometry
                            )

                        visibleVolume.name =
                            side == .left
                            ? "book.left-page-volume"
                            : "book.right-page-volume"

                        visibleVolume.position.z =
                            -0.006

                        visibleVolume.castsShadow =
                            true

                        visibleVolume.renderingOrder =
                            0

                        node.addChildNode(
                            visibleVolume
                        )

                        let endpaperGeometry =
                            pageEndpaperGeometry(
                                width:
                                    block.width,
                                height:
                                    block.height,
                                depth:
                                    block.length,
                                insideEdge:
                                    side,
                                binding:
                                    binding,
                                fullness:
                                    visibleFullness
                            )

                        let endpaperMaterial =
                            SCNMaterial()

                        endpaperMaterial.diffuse.contents =
                            NSColor(
                                calibratedRed:
                                    binding == .hardcover
                                    ? 0.895
                                    : 0.925,
                                green:
                                    binding == .hardcover
                                    ? 0.870
                                    : 0.905,
                                blue:
                                    binding == .hardcover
                                    ? 0.805
                                    : 0.850,
                                alpha:
                                    1
                            )

                        endpaperMaterial.lightingModel =
                            .physicallyBased

                        endpaperMaterial.roughness.contents =
                            0.985

                        endpaperMaterial.metalness.contents =
                            0

                        endpaperMaterial.isDoubleSided =
                            true

                        endpaperGeometry.materials = [
                            endpaperMaterial
                        ]

                        let endpaper =
                            SCNNode(
                                geometry:
                                    endpaperGeometry
                            )

                        endpaper.name =
                            side == .left
                            ? "book.left-endpaper"
                            : "book.right-endpaper"

                        endpaper.position.z =
                            -0.005

                        endpaper.castsShadow =
                            true

                        endpaper.renderingOrder =
                            -4

                        node.addChildNode(
                            endpaper
                        )

                        let gutterFoldGeometry =
                            pageGutterFoldGeometry(
                                width:
                                    block.width,
                                height:
                                    block.height,
                                depth:
                                    block.length,
                                insideEdge:
                                    side,
                                binding:
                                    binding,
                                fullness:
                                    visibleFullness
                            )

                        let gutterFoldMaterial =
                            paperMaterial.copy()
                            as! SCNMaterial

                        gutterFoldMaterial.diffuse.contents =
                            NSColor(
                                calibratedRed:
                                    0.910,
                                green:
                                    0.892,
                                blue:
                                    0.842,
                                alpha:
                                    1
                            )

                        gutterFoldMaterial.lightingModel =
                            .physicallyBased

                        gutterFoldMaterial.roughness.contents =
                            0.975

                        gutterFoldMaterial.metalness.contents =
                            0

                        gutterFoldMaterial.isDoubleSided =
                            true

                        gutterFoldGeometry.materials = [
                            gutterFoldMaterial
                        ]

                        let gutterFold =
                            SCNNode(
                                geometry:
                                    gutterFoldGeometry
                            )

                        gutterFold.name =
                            side == .left
                            ? "book.left-gutter-fold"
                            : "book.right-gutter-fold"

                        // Match the visible page body's local depth offset.
                        gutterFold.position.z =
                            -0.005

                        gutterFold.castsShadow =
                            true

                        gutterFold.renderingOrder =
                            3

                        node.addChildNode(
                            gutterFold
                        )

                        // The complete curved page body replaces the old
                        // disconnected upper swell skin in Reading mode.
                        swellNode.isHidden =
                            true
                    }

addPaperEdgeStrata(
                        to: node,
                        side: side,
                        blockWidth: blockWidth,
                        blockHeight: blockHeight,
                        blockDepth: blockDepth,
                        name:
                            side == .left
                                ? "book.left-page-edge-strata"
                                : "book.right-page-edge-strata"
                    )

                    updatePageEdgeFan(
                        blockNode:
                            node,
                        side:
                            side,
                        depth:
                            blockDepth,
                        totalDepth:
                            CGFloat(
                                geometry
                                .pageBlockDepth(
                                    for:
                                        binding
                                )
                                * scale
                            ),
                        binding:
                            binding
                    )

                    (
                        side == .left
                            ? leftLeaves
                            : root
                    )
                    .addChildNode(
                        node
                    )
                }
                stack(stacks.leftDepth, centerX: CGFloat(PhysicalBookGeometry.scenePageOriginX(pageWidth: geometry.trimWidth, side: .left)) * CGFloat(scale),
                      centerZ: CGFloat(geometry.stackCenterZ(side: .left, pageCount: pageCount, spreadIndex: spreadIndex, binding: binding) * scale))
                stack(stacks.rightDepth, centerX: CGFloat(PhysicalBookGeometry.scenePageOriginX(pageWidth: geometry.trimWidth, side: .right)) * CGFloat(scale),
                      centerZ: CGFloat(geometry.stackCenterZ(side: .right, pageCount: pageCount, spreadIndex: spreadIndex, binding: binding) * scale))
            } else {
                let block =
                    SCNBox(
                        width: width,
                        height: height,
                        length: blockDepth,
                        chamferRadius: 0.006
                    )

                block.materials = [
                    paperMaterial,
                    edgeMaterial,
                    paperMaterial,
                    edgeMaterial,
                    edgeMaterial,
                    edgeMaterial
                ]

                let pages =
                    SCNNode(
                        geometry: block
                    )

                pages.name =
                    "book.closed-page-block"

                pages.position =
                    SCNVector3(
                        width / 2,
                        height / 2,
                        0
                    )

                addPaperEdgeStrata(
                    to: pages,
                    side: .right,
                    blockWidth: width,
                    blockHeight: height,
                    blockDepth: blockDepth,
                    name:
                        "book.closed-page-edge-strata"
                )

                root.addChildNode(
                    pages
                )
            }
        }
        let coverDepth = CGFloat(stock * scale)
        func shell(_ image: NSImage?, front: Bool) -> SCNNode {
            let node: SCNNode

            let artwork = SCNMaterial()
            artwork.diffuse.contents =
                image ?? NSColor.darkGray
            artwork.isDoubleSided = false
            artwork.lightingModel = .physicallyBased
            artwork.roughness.contents = 0.82
            artwork.metalness.contents = 0
            artwork.diffuse.minificationFilter = .linear
            artwork.diffuse.magnificationFilter = .linear
            artwork.diffuse.mipFilter = .linear

            let vertical =
                front
                    ? BookTextureVerticalTransform.frontCover
                    : BookTextureVerticalTransform.backCover

            var artworkUV = SCNMatrix4Identity

            // The back exterior faces the opposite direction from the front.
            // Compensate its U coordinate so canonical back artwork remains
            // readable left-to-right when viewed from outside the closed book.
            if front == false && binding == .softcover {
                artworkUV.m11 = -1
                artworkUV.m41 = 1
            }

            artworkUV.m22 = CGFloat(vertical.scale)
            artworkUV.m42 = CGFloat(vertical.offset)
            artwork.diffuse.contentsTransform = artworkUV

            let lining = SCNMaterial()
            lining.diffuse.contents =
                NSColor(
                    calibratedRed: 0.89,
                    green: 0.86,
                    blue: 0.78,
                    alpha: 1
                )
            lining.isDoubleSided = false
            lining.lightingModel = .physicallyBased
            lining.roughness.contents = 0.94
            lining.metalness.contents = 0

            if binding == .softcover {
                let profile =
                    softcoverFlexProfile(
                        open: open,
                        angleDegrees: angle
                    )

                let flexible =
                    flexibleCoverGeometry(
                        width: width + 2 * coverHorizontalOverhang,
                        height: height + 2 * coverVerticalOverhang,
                        insideEdge: .left,
                        creaseDepth:
                            profile.creaseDepth,
                        bowDepth:
                            profile.bowDepth,
                        depthDirection:
                            front ? -1 : 1,
                        thickness: coverDepth
                    )

                // Front cover exterior faces +Z. Back cover exterior faces -Z.
                // Swap the two materials rather than duplicating flat artwork
                // planes so the printed cover itself follows the flexible mesh.
                flexible.materials =
                    front
                        ? [
                            artwork,
                            lining,
                            lining
                        ]
                        : [
                            lining,
                            artwork,
                            lining
                        ]

                node = SCNNode(
                    geometry: flexible
                )

                node.name =
                    front
                        ? "book-shell.front-cover"
                        : "book-shell.back-cover"

                node.setValue(
                    true,
                    forKey:
                        "physicalBookFlexibleCover"
                )
            } else {
                let box =
                    SCNBox(
                        width: width + 2 * coverHorizontalOverhang,
                        height: height + 2 * coverVerticalOverhang,
                        length: coverDepth,
                        chamferRadius: 0.008
                    )

                box.firstMaterial?.diffuse.contents =
                    NSColor(
                        calibratedWhite: 0.18,
                        alpha: 1
                    )

                box.firstMaterial?.roughness.contents =
                    0.78

                node = SCNNode(
                    geometry: box
                )

                node.name =
                    front
                        ? "book-shell.front-cover"
                        : "book-shell.back-cover"

                let plane =
                    SCNPlane(
                        width: width + 2 * coverHorizontalOverhang,
                        height: height + 2 * coverVerticalOverhang
                    )

                plane.materials = [
                    artwork
                ]

                let artworkNode =
                    SCNNode(
                        geometry: plane
                    )

                artworkNode.position.z =
                    front
                        ? coverDepth / 2 + 0.001
                        : -coverDepth / 2 - 0.001

                artworkNode.eulerAngles.y =
                    front
                        ? 0
                        : .pi

                node.addChildNode(
                    artworkNode
                )

                let interior =
                    SCNPlane(
                        width: width + 2 * coverHorizontalOverhang,
                        height: height + 2 * coverVerticalOverhang
                    )

                let rigidLining =
                    SCNMaterial()

                rigidLining.diffuse.contents =
                    NSColor(
                        calibratedRed: 0.89,
                        green: 0.86,
                        blue: 0.78,
                        alpha: 1
                    )

                rigidLining.isDoubleSided = true
                rigidLining.lightingModel = .physicallyBased
                rigidLining.roughness.contents = 0.94

                interior.materials = [
                    rigidLining
                ]

                let interiorNode =
                    SCNNode(
                        geometry: interior
                    )

                interiorNode.position.z =
                    front
                        ? -coverDepth / 2 - 0.001
                        : coverDepth / 2 + 0.001

                interiorNode.eulerAngles.y =
                    front
                        ? .pi
                        : 0

                node.addChildNode(
                    interiorNode
                )

                node.setValue(
                    false,
                    forKey:
                        "physicalBookFlexibleCover"
                )
            }

            node.position.x =
                width / 2

            if front {
                node.position.y =
                    height / 2

                node.position.z =
                    thick / 2
                    - coverDepth / 2
            } else {
                node.position.y =
                    height / 2

                node.position.z =
                    -thick / 2
                    + coverDepth / 2
            }

            return node
        }
        func addHardcoverJointDetails(
            to cover: SCNNode,
            front: Bool
        ) {
            guard binding == .hardcover else {
                return
            }

            let outerWidth = width + 2 * coverHorizontalOverhang
            let outerHeight = height + 2 * coverVerticalOverhang

            let jointWidth =
                max(
                    CGFloat(0.045 * scale),
                    min(
                        CGFloat(0.105 * scale),
                        outerWidth * 0.020
                    )
                )

            let grooveWidth =
                max(
                    CGFloat(0.010),
                    jointWidth * 0.20
                )

            let exteriorZ =
                front
                    ? coverDepth / 2 + 0.0016
                    : -coverDepth / 2 - 0.0016

            // A case-bound hardcover keeps a rigid board, but the covering
            // material forms a narrow flexible joint beside the spine.
            let jointPlane =
                SCNPlane(
                    width: jointWidth,
                    height: outerHeight
                )

            let jointMaterial =
                SCNMaterial()

            jointMaterial.diffuse.contents =
                NSColor(
                    calibratedWhite: 0.13,
                    alpha: 1
                )

            jointMaterial.lightingModel =
                .physicallyBased

            jointMaterial.roughness.contents =
                0.94

            jointMaterial.metalness.contents =
                0

            jointMaterial.isDoubleSided =
                false

            jointPlane.materials = [
                jointMaterial
            ]

            let jointNode =
                SCNNode(
                    geometry: jointPlane
                )

            jointNode.name =
                front
                    ? "book-shell.front-joint"
                    : "book-shell.back-joint"

            jointNode.position =
                SCNVector3(
                    -outerWidth / 2
                    + jointWidth / 2,
                    0,
                    exteriorZ
                )

            if !front {
                jointNode.eulerAngles.y = .pi
            }

            cover.addChildNode(
                jointNode
            )

            // A darker narrow score line just outside the joint gives the
            // rigid board its characteristic case-bound hinge groove.
            let groovePlane =
                SCNPlane(
                    width: grooveWidth,
                    height: outerHeight * 0.985
                )

            let grooveMaterial =
                SCNMaterial()

            grooveMaterial.diffuse.contents =
                NSColor(
                    calibratedWhite: 0.045,
                    alpha: 1
                )

            grooveMaterial.lightingModel =
                .physicallyBased

            grooveMaterial.roughness.contents =
                0.98

            grooveMaterial.metalness.contents =
                0

            grooveMaterial.isDoubleSided =
                false

            groovePlane.materials = [
                grooveMaterial
            ]

            let grooveNode =
                SCNNode(
                    geometry: groovePlane
                )

            grooveNode.name =
                front
                    ? "book-shell.front-hinge-groove"
                    : "book-shell.back-hinge-groove"

            grooveNode.position =
                SCNVector3(
                    -outerWidth / 2
                    + jointWidth
                    + grooveWidth / 2,
                    0,
                    front
                        ? exteriorZ + 0.0004
                        : exteriorZ - 0.0004
                )

            if !front {
                grooveNode.eulerAngles.y = .pi
            }

            cover.addChildNode(
                grooveNode
            )
        }

        let back =
            shell(
                textures.back,
                front: false
            )

        addHardcoverJointDetails(
            to: back,
            front: false
        )

        root.addChildNode(
            back
        )

        let front =
            shell(
                textures.front,
                front: true
            )

        addHardcoverJointDetails(
            to: front,
            front: true
        )
        // The front cover is part of the persistent physical shell. Opening
        // the book changes its pose; it must never remove the cover node.
        root.addChildNode(front)

        if !workingLayers && !textures.edgeIssues.isEmpty {
            if let backCover =
                root.childNode(
                    withName:
                        "book-shell.back-cover",
                    recursively: true
                ) {

                addCoverEdgeIssueOverlays(
                    to: backCover,
                    panel: .back,
                    exteriorFacesPositiveZ: false,
                    issues: textures.edgeIssues
                )
            }

            if let frontCover =
                root.childNode(
                    withName:
                        "book-shell.front-cover",
                    recursively: true
                ) {

                addCoverEdgeIssueOverlays(
                    to: frontCover,
                    panel: .front,
                    exteriorFacesPositiveZ: true,
                    issues: textures.edgeIssues
                )
            }
        }

        if !workingLayers {
            let resolutionIssues =
                PhysicalBookDiagnostics
                    .coverImageResolutionIssues(
                        project: project
                    )

            let affectedRegions =
                Set(
                    resolutionIssues
                        .flatMap(
                            \.regions
                        )
                )

            if affectedRegions
                .contains(
                    .back
                ),
               let backCover =
                    root.childNode(
                        withName:
                            "book-shell.back-cover",
                        recursively: true
                    ) {

                addResolutionIssueBadge(
                    to: backCover,
                    name:
                        "diagnostic.cover.back.resolution",
                    exteriorFacesPositiveZ:
                        false
                )
            }

            if affectedRegions
                .contains(
                    .front
                ),
               let frontCover =
                    root.childNode(
                        withName:
                            "book-shell.front-cover",
                        recursively: true
                    ) {

                addResolutionIssueBadge(
                    to: frontCover,
                    name:
                        "diagnostic.cover.front.resolution",
                    exteriorFacesPositiveZ:
                        true
                )
            }

            if affectedRegions
                .contains(
                    .spine
                ),
               let spineArtwork =
                    root.childNode(
                        withName:
                            "book-shell.spine-artwork",
                        recursively: true
                    ) {

                addResolutionIssueBadge(
                    to: spineArtwork,
                    name:
                        "diagnostic.spine.resolution",
                    exteriorFacesPositiveZ:
                        true
                )
            }
        }

        if !workingLayers {
            let safeIssues =
                PhysicalBookDiagnostics
                    .coverContentSafeIssues(
                        project: project
                    )

            if !safeIssues.isEmpty {
                if let backCover =
                    root.childNode(
                        withName:
                            "book-shell.back-cover",
                        recursively: true
                    ) {

                    addCoverSafeZoneIssueOverlays(
                        to: backCover,
                        panel: .back,
                        exteriorFacesPositiveZ: false,
                        issues: safeIssues
                    )
                }

                if let frontCover =
                    root.childNode(
                        withName:
                            "book-shell.front-cover",
                        recursively: true
                    ) {

                    addCoverSafeZoneIssueOverlays(
                        to: frontCover,
                        panel: .front,
                        exteriorFacesPositiveZ: true,
                        issues: safeIssues
                    )
                }
            }
        }


        if open {
            // The rear board remains under the right stack. The front board
            // swings around the common spine to support the turned left stack.
            let silhouette =
                geometry.openSilhouette(
                    open:
                        true,
                    angleDegrees:
                        angle,
                    pageCount:
                        pageCount,
                    spreadIndex:
                        spreadIndex,
                    binding:
                        binding
                )
            let support =
                geometry.stackSupportPose(
                    open:
                        true,
                    angleDegrees:
                        angle,
                    pageCount:
                        pageCount,
                    spreadIndex:
                        spreadIndex,
                    binding:
                        binding
                )

            let opening = geometry.openingPose(angleDegrees: angle)
            let leftBaseLiftDegrees = opening.leftLiftDegrees
            let rightBaseLiftDegrees = opening.rightLiftDegrees

            let supportedFrontAngle =
                max(
                    0,
                    min(
                        180,
                        180
                        - leftBaseLiftDegrees
                        - support.leftCoverLiftDegrees
                    )
                )

            // Cover and leaves share the same gutter hinge. Computing the
            // center from the actual cover rotation avoids a floating board
            // when the opening is split between the two sides.
            let frontLift = CGFloat((180 - supportedFrontAngle) * .pi / 180)
            front.position = SCNVector3(
                -width / 2 * cos(frontLift),
                height / 2,
                -thick / 2 + coverDepth / 2 + width / 2 * sin(frontLift)
            )

            front.eulerAngles.y =
                CGFloat(
                    -supportedFrontAngle
                    * .pi
                    / 180
                )
            let leftPageX = -width
            let rightPageX: CGFloat = 0
            let leftSurface = CGFloat((geometry.stackCenterZ(side: .left, pageCount: pageCount, spreadIndex: spreadIndex, binding: binding) + stacks.leftDepth / 2) * scale) + 0.004
            let rightSurface = CGFloat((geometry.stackCenterZ(side: .right, pageCount: pageCount, spreadIndex: spreadIndex, binding: binding) + stacks.rightDepth / 2) * scale) + 0.004

            // BOLD WRITER V11 — visible bound-paper profile
        //
        // Reading uses the real curved manuscript mesh, but the original
        // displacement values were calibrated for the upright inspection
        // presentation. Once V10 correctly laid the book onto the Studio
        // surface, that deformation became visually too shallow.
        //
        // Keep the physical hinge untouched and amplify only the visible
        // paper profile: strongest around the bound shoulder/gutter and
        // restrained at the free fore edge.
        let readingValleyGain:
            CGFloat =
            readingPhysicalPreview
            ? (
                binding == .hardcover
                ? 1.7200
                : 1.8800
            )
            : 1

        let readingShoulderGain:
            CGFloat =
            readingPhysicalPreview
            ? (
                binding == .hardcover
                ? 1.9600
                : 2.2000
            )
            : 1

        let readingForeEdgeGain:
            CGFloat =
            readingPhysicalPreview
            ? (
                binding == .hardcover
                ? 1.3200
                : 1.5200
            )
            : 1

        let visualPageValley =
            (
                max(
                                    CGFloat(
                                        silhouette.pageValleyDepth
                                        * scale
                                    )
                                    * readingPageCurveScale,
                                    readingPageValleyFloor
                                )
            )
            * readingValleyGain
let visualLeftShoulder =
            (
                max(
                                    CGFloat(
                                        silhouette.leftShoulderDepth
                                        * scale
                                    )
                                    * readingPageCurveScale,
                                    readingPageShoulderFloor
                                )
            )
            * readingShoulderGain
let visualRightShoulder =
            (
                max(
                                    CGFloat(
                                        silhouette.rightShoulderDepth
                                        * scale
                                    )
                                    * readingPageCurveScale,
                                    readingPageShoulderFloor
                                )
            )
            * readingShoulderGain
let visualLeftForeEdge =
            (
                max(
                                    CGFloat(
                                        silhouette.leftForeEdgeLift
                                        * scale
                                    )
                                    * readingPageCurveScale,
                                    readingForeEdgeFloor
                                )
            )
            * readingForeEdgeGain
let visualRightForeEdge =
            (
                max(
                                    CGFloat(
                                        silhouette.rightForeEdgeLift
                                        * scale
                                    )
                                    * readingPageCurveScale,
                                    readingForeEdgeFloor
                                )
            )
            * readingForeEdgeGain
addInteriorPage(
                leftLeaves,
                image:
                    leftTexture,
                isManuscriptPage:
                    leftPage != nil,
                pageNumber:
                    leftPage ?? 2,
                x:
                    leftPageX,
                width:
                    width,
                height:
                    height,
                z:
                    0,
                settings:
                    leftPageSettings,
                margins:
                    margins,
                side:
                    .left,
                thumbMode:
                    thumbMode,
                surfaceY:
                    leftSurface,
                valleyDepth:
                    visualPageValley,
                shoulderLift:
                    visualLeftShoulder,
                foreEdgeCurl:
                    visualLeftForeEdge
            )
            addInteriorPage(
                root,
                image:
                    rightTexture,
                isManuscriptPage:
                    rightPage != nil,
                pageNumber:
                    rightPage ?? 1,
                x:
                    rightPageX,
                width:
                    width,
                height:
                    height,
                z:
                    0,
                settings:
                    rightPageSettings,
                margins:
                    margins,
                side:
                    .right,
                thumbMode:
                    thumbMode,
                surfaceY:
                    rightSurface,
                valleyDepth:
                    visualPageValley,
                shoulderLift:
                    visualRightShoulder,
                foreEdgeCurl:
                    visualRightForeEdge
            )
            if readingPhysicalPreview {
                if let leftActivePage =
                    root
                    .childNode(
                        withName:
                            "book.left-active-page",
                        recursively:
                            true
                    )
                {
                    addReadingVisibleLeafLayers(
                        to:
                            leftActivePage,
                        side:
                            .left,
                        width:
                            width,
                        height:
                            height,
                        valleyDepth:
                            visualPageValley,
                        shoulderLift:
                            visualLeftShoulder,
                        foreEdgeCurl:
                            visualLeftForeEdge,
                        binding:
                            binding
                    )
                }

                if let rightActivePage =
                    root
                    .childNode(
                        withName:
                            "book.right-active-page",
                        recursively:
                            true
                    )
                {
                    addReadingVisibleLeafLayers(
                        to:
                            rightActivePage,
                        side:
                            .right,
                        width:
                            width,
                        height:
                            height,
                        valleyDepth:
                            visualPageValley,
                        shoulderLift:
                            visualRightShoulder,
                        foreEdgeCurl:
                            visualRightForeEdge,
                        binding:
                            binding
                    )
                }
            }

            let openHingeZ = -thick / 2 + coverDepth / 2
            let hingeZ = openHingeZ
            for child in leftLeaves.childNodes { child.position.z -= openHingeZ }
            leftLeaves.position.z = hingeZ
            leftLeaves.eulerAngles.y =
                CGFloat(
                    leftBaseLiftDegrees
                    * .pi
                    / 180
                )

            let leftLift =
                CGFloat(
                    silhouette.leftStackLiftDegrees
                    * .pi
                    / 180
                )

            let rightLift =
                CGFloat(
                    silhouette.rightStackLiftDegrees
                    * .pi
                    / 180
                )

            let backLift =
                CGFloat(
                    support.rightCoverLiftDegrees
                    * .pi
                    / 180
                )

            let leftInnerEdge =
                width / 2

            let rightInnerEdge =
                -width / 2

            for child in
                leftLeaves.childNodes
            {
                guard
                    child.name
                        == "book.left-page-block"
                    || child.name
                        == "book.left-active-page"
                else {
                    continue
                }

                child.pivot =
                    SCNMatrix4MakeTranslation(
                        leftInnerEdge,
                        0,
                        0
                    )

                // The local paper mesh is centered around x=0 while the
                // pivot is already its bound inner edge. The node position
                // therefore represents the world hinge location. Keep that
                // hinge on the common gutter instead of applying the old
                // half-page center offset a second time.
                child.position.x =
                    0

                child.eulerAngles.y +=
                    leftLift
            }

            for name in [
                "book.right-page-block",
                "book.right-active-page"
            ] {
                guard
                    let child =
                        root.childNode(
                            withName:
                                name,
                            recursively:
                                false
                        )
                else {
                    continue
                }

                child.pivot =
                    SCNMatrix4MakeTranslation(
                        rightInnerEdge,
                        0,
                        0
                    )

                child.position.x =
                    0

                child.eulerAngles.y -=
                    CGFloat(
                        rightBaseLiftDegrees
                        * .pi
                        / 180
                    )
                    + rightLift
            }

            back.pivot =
                SCNMatrix4MakeTranslation(
                    rightInnerEdge,
                    0,
                    0
                )

            back.eulerAngles.y =
                -CGFloat(
                    rightBaseLiftDegrees
                    * .pi
                    / 180
                )
                - backLift
        }
        if thick > 0 {
            let spine = SCNBox(width: CGFloat(coverDepth), height: height + 2 * coverVerticalOverhang, length: thick, chamferRadius: 0.012)
            spine.firstMaterial?.diffuse.contents = NSColor(calibratedWhite: 0.18, alpha: 1); spine.firstMaterial?.roughness.contents = 0.72
            let spineNode =
                SCNNode(
                    geometry:
                        spine
                )
            spineNode.name =
                "book-shell.spine"
            // V27B — KDP case spine sits OUTSIDE the text block.
            // Its inner face terminates exactly on x == 0.
            spineNode.position =
                SCNVector3(
                    -coverDepth / 2,
                    height / 2,
                    0
                )
            spineNode.isHidden =
                readingPhysicalPreview
            root.addChildNode(
                spineNode
            )

            // V27B — physical 10 mm case hinge channels.
            if
                binding == .hardcover,
                !readingPhysicalPreview,
                hardcoverHingeChannel > 0
            {
                let boardDepth =
                    CGFloat(
                        geometry
                            .coverThickness(
                                for:
                                    .hardcover
                            )
                        * scale
                    )

                let channelWidth =
                    max(
                        CGFloat(0.018),
                        boardDepth * 0.22
                    )

                let channelDepth =
                    max(
                        CGFloat(0.003),
                        boardDepth * 0.035
                    )

                let channelHeight =
                    height
                    + 2
                    * coverVerticalOverhang

                func makeCaseHingeChannel(
                    name: String,
                    z: CGFloat
                ) -> SCNNode
                {
                    let groove =
                        SCNBox(
                            width:
                                channelWidth,
                            height:
                                channelHeight * 0.985,
                            length:
                                channelDepth,
                            chamferRadius:
                                channelDepth / 2
                        )

                    let material =
                        SCNMaterial()

                    material.lightingModel =
                        .physicallyBased

                    material.diffuse.contents =
                        NSColor(
                            calibratedWhite:
                                0.18,
                            alpha:
                                0.28
                        )

                    material.roughness.contents =
                        0.95

                    groove.materials = [
                        material
                    ]

                    let node =
                        SCNNode(
                            geometry:
                                groove
                        )

                    node.name =
                        name

                    node.position =
                        SCNVector3(
                            hardcoverHingeChannel,
                            height / 2,
                            z
                        )

                    node.castsShadow =
                        true

                    node.renderingOrder =
                        8

                    return node
                }

                root.addChildNode(
                    makeCaseHingeChannel(
                        name:
                            "book-shell.front-hinge-channel",
                        z:
                            thick / 2
                            + channelDepth / 2
                            + 0.0005
                    )
                )

                root.addChildNode(
                    makeCaseHingeChannel(
                        name:
                            "book-shell.back-hinge-channel",
                        z:
                            -thick / 2
                            - channelDepth / 2
                            - 0.0005
                    )
                )
            }

            let spinePanel = SCNPlane(width: thick, height: height + 2 * coverVerticalOverhang)
            let spineMaterial = SCNMaterial(); spineMaterial.diffuse.contents = textures.spine ?? NSColor.darkGray; spineMaterial.isDoubleSided = true; spineMaterial.roughness.contents = 0.72
            let spineUV = BookTextureVerticalTransform.spine
            var spineTextureTransform = SCNMatrix4Identity; spineTextureTransform.m22 = CGFloat(spineUV.scale); spineTextureTransform.m42 = CGFloat(spineUV.offset)
            spineMaterial.diffuse.contentsTransform = spineTextureTransform
            spineMaterial.diffuse.minificationFilter = .linear; spineMaterial.diffuse.magnificationFilter = .linear; spineMaterial.diffuse.mipFilter = .linear
            spinePanel.materials = [spineMaterial]
        let spineArtwork = SCNNode(geometry: spinePanel)
        spineArtwork.name =
            "book-shell.spine-artwork"

            spineArtwork.position = SCNVector3(-coverDepth - 0.001, height / 2, 0)
            spineArtwork.eulerAngles.y = -.pi / 2
            spineArtwork.isHidden =
                readingPhysicalPreview

            root.addChildNode(spineArtwork)

        if !workingLayers {
            let spineTextIssues =
                PhysicalBookDiagnostics
                    .spineTextIssues(
                        project: project
                    )

            if !spineTextIssues.isEmpty {
                let warningWidth =
                    max(
                        CGFloat(0.012),
                        min(
                            CGFloat(0.030),
                            thick * 0.08
                        )
                    )

                func addSpineFoldWarning(
                    name: String,
                    x: CGFloat
                ) {
                    let plane =
                        SCNPlane(
                            width:
                                warningWidth,
                            height:
                                height
                        )

                    let material =
                        SCNMaterial()

                    material.diffuse.contents =
                        NSColor.systemOrange
                            .withAlphaComponent(
                                0.72
                            )

                    material.emission.contents =
                        NSColor.systemOrange
                            .withAlphaComponent(
                                0.14
                            )

                    material.lightingModel =
                        .physicallyBased

                    material.roughness.contents =
                        0.88

                    material.metalness.contents =
                        0

                    material.isDoubleSided =
                        true

                    plane.materials = [
                        material
                    ]

                    let warning =
                        SCNNode(
                            geometry:
                                plane
                        )

                    warning.name =
                        name

                    warning.position =
                        SCNVector3(
                            x,
                            0,
                            0.003
                        )

                    warning.renderingOrder =
                        101

                    spineArtwork
                        .addChildNode(
                            warning
                        )
                }

                addSpineFoldWarning(
                    name:
                        "diagnostic.spine.left-fold",
                    x:
                        -thick / 2
                        + warningWidth / 2
                )

                addSpineFoldWarning(
                    name:
                        "diagnostic.spine.right-fold",
                    x:
                        thick / 2
                        - warningWidth / 2
                )
            }
        }

        }
        let ambient =
            SCNNode()

        ambient.name =
            "studio-light.ambient"

        ambient.light =
            SCNLight()

        ambient.light?.type =
            .ambient

        ambient.light?.intensity =
            235

        ambient.light?.color =
            NSColor(
                calibratedWhite: 0.94,
                alpha: 1
            )

        sceneRoot.addChildNode(
            ambient
        )

        let keyLight =
            SCNNode()

        keyLight.name =
            "studio-light.key"

        keyLight.light =
            SCNLight()

        keyLight.light?.type =
            .directional

        keyLight.light?.intensity =
            920

        keyLight.light?.temperature =
            5_500

        keyLight.light?.castsShadow =
            true

        keyLight.light?.shadowRadius =
            7

        keyLight.light?.shadowSampleCount =
            16

        keyLight.light?.shadowBias =
            0.0015

        keyLight.light?.shadowColor =
            NSColor.black
                .withAlphaComponent(
                    0.24
                )

        keyLight.eulerAngles =
            SCNVector3(
                -0.72,
                0.55,
                0.24
            )

        sceneRoot.addChildNode(
            keyLight
        )

        let fillLight =
            SCNNode()

        fillLight.name =
            "studio-light.fill"

        fillLight.light =
            SCNLight()

        fillLight.light?.type =
            .directional

        fillLight.light?.intensity =
            340

        fillLight.light?.temperature =
            6_200

        fillLight.light?.castsShadow =
            false

        fillLight.eulerAngles =
            SCNVector3(
                -0.35,
                -1.05,
                -0.28
            )

        sceneRoot.addChildNode(
            fillLight
        )

        let rimLight =
            SCNNode()

        rimLight.name =
            "studio-light.rim"

        rimLight.light =
            SCNLight()

        rimLight.light?.type =
            .directional

        rimLight.light?.intensity =
            275

        rimLight.light?.temperature =
            6_700

        rimLight.light?.castsShadow =
            false

        rimLight.eulerAngles =
            SCNVector3(
                -0.48,
                2.35,
                0.18
            )

        sceneRoot.addChildNode(
            rimLight
        )

        let ground =
            SCNPlane(
                width:
                    max(
                        12,
                        width * 4.8
                    ),
                height:
                    max(
                        12,
                        height * 4.0
                    )
            )

        let groundMaterial =
            SCNMaterial()

        groundMaterial.diffuse.contents =
            NSColor(
                calibratedWhite: 0.915,
                alpha: 1
            )

        groundMaterial.lightingModel =
            .physicallyBased

        groundMaterial.roughness.contents =
            1.0

        groundMaterial.metalness.contents =
            0

        groundMaterial.isDoubleSided =
            false

        ground.materials = [
            groundMaterial
        ]

        let groundNode =
            SCNNode(
                geometry: ground
            )

        groundNode.name =
            "studio-ground"

        groundNode.eulerAngles.x =
            -.pi / 2

        groundNode.position =
            SCNVector3(
                0,
                -0.025,
                0
            )

        sceneRoot.addChildNode(
            groundNode
        )

        let cameraNode = SCNNode()
        cameraNode.name = "preview-camera"
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 34
        cameraNode.camera?.zNear = 0.01
        cameraNode.camera?.zFar = 100
        sceneRoot.addChildNode(cameraNode)
        BookStudioSceneStyling.apply(to: scene, presentation: presentation)

        if readingPhysicalPreview {
            // BOLD_BRIGHT_STUDIO_V14: brighter neutral Reading studio.
            // BOLD_BALANCED_LIGHT_V15: balanced light preserves white UI without clipping paper.
            // BOLD reading-preview product lighting V3.
            //
            // Use the Studio's existing light rig instead of stacking extra
            // high-intensity lights on top of it. Tonal separation comes from
            // controlled exposure plus screen-space ambient occlusion.
            cameraNode.camera?.wantsHDR =
                true

            cameraNode.camera?.wantsExposureAdaptation = false
            cameraNode.camera?.exposureOffset =
                -0.45

            cameraNode.camera?.averageGray =
                0.18

            cameraNode.camera?.whitePoint =
                1.0

            // SceneKit SSAO strengthens the gutter, page-to-block contact,
            // cover-to-page relationship and page-stack depth without adding
            // enough illumination to clip the manuscript texture.
            cameraNode.camera?.screenSpaceAmbientOcclusionIntensity =
                1.10

            cameraNode.camera?.screenSpaceAmbientOcclusionRadius =
                0.18

            cameraNode.camera?.screenSpaceAmbientOcclusionBias =
                0.008

            cameraNode.camera?.screenSpaceAmbientOcclusionDepthThreshold =
                0.32

            cameraNode.camera?.screenSpaceAmbientOcclusionNormalThreshold =
                0.28

            scene.background.contents =
                NSColor(
                    calibratedWhite:
                        0.945,
                    alpha:
                        1
                )

            scene.lightingEnvironment.intensity =
                0.35 * presentation.environmentIntensity

            if let material =
                ground.materials.first
            {
                material.diffuse.contents =
                    NSColor(
                        calibratedWhite:
                            0.885,
                        alpha:
                            1
                    )

                material.lightingModel =
                    .physicallyBased

                material.roughness.contents =
                    0.96

                material.metalness.contents =
                    0
            }
        }
                if readingPhysicalPreview {
            // The right physical support anchor also survives the final
            // spread, so back-cover placement may use it consistently.
            alignReadingBackCoverToRightPageBlock(
                root:
                    root
            )
            // Page-block support anchors now remain present on zero-depth
            // edge stacks, so the same physical cover-contact correction works
            // for first, middle, and final spreads.
            alignOpenCoverSupports(root: root, thickness: coverDepth)
            alignOpenPrintedSurfaces(root: root)
            alignOpenBindingEdges(root: root, hingeZ: -thick/2 + coverDepth,
                leftHingeZ: -thick/2 + coverDepth + CGFloat(geometry.openingPose(angleDegrees: angle).leftHingeDepth * scale), openingProgress: CGFloat(openingProgress),
                hingeOffset: CGFloat(geometry.openSpineHingeOffset(angleDegrees:angle,binding:binding)*scale))
            BookOpenGutterGeometry.update(in:root,hingeZ:-thick/2+coverDepth,angle:angle)
        }

// The printed binding remains attached to both cover hinges as the book opens.
if open { BookSpineWrapGeometry.update(in:root,depth:thick) }

BookProductionMarginGuides.add(to: root, project: project, visible: presentation.showProductionMargins == true)

// BOLD_BOOK_SURFACE_FILL_V17: final material pass after all live page/cover updates.
applyBookSurfaceBrightnessFill(
    root:
        root
)

// Diagnostics remain available with guides, but are not printed book surfaces.
// In particular, low-resolution badges must not appear as red strips in proofs.
root.enumerateChildNodes { node, _ in
    if node.name?.hasPrefix("diagnostic.") == true {
        node.isHidden = !margins
    }
}
return scene
    }

    static func pageTurnMorphWeights(progress: CGFloat) -> (peak: CGFloat, landing: CGFloat) {
        let progress = min(1, max(0, progress))

        if progress <= 0.5 {
            return (
                peak: progress / 0.5,
                landing: 0
            )
        }

        return (
            peak: max(0, (1 - progress) / 0.5),
            landing: min(1, (progress - 0.5) / 0.5)
        )
    }

    static let pageFanRibbonCount =
        12

    static let pageFanMicroVariation:
        [CGFloat] =
        [
            0.00,
            0.17,
            -0.11,
            0.08,
            -0.15,
            0.12,
            -0.05,
            0.14,
            -0.09,
            0.06,
            -0.13,
            0.03
        ]

    static func pageFanEnvelope(
        binding: BookBinding,
        fullness: CGFloat,
        blockWidth: CGFloat,
        totalDepth: CGFloat
    ) -> (
        x: CGFloat,
        z: CGFloat,
        tilt: CGFloat
    ) {
        let safeFullness =
            min(
                1,
                max(
                    0,
                    fullness
                )
            )

        let strength =
            CGFloat(
                sqrt(
                    Double(
                        safeFullness
                    )
                )
            )

        let x =
            blockWidth
            * (
                binding == .hardcover
                ? 0.0030
                : 0.0060
            )
            * strength

        let z =
            totalDepth
            * (
                binding == .hardcover
                ? 0.026
                : 0.050
            )
            * strength

        let tiltDegrees:
            CGFloat =
            binding == .hardcover
            ? 0.32
            : 0.70

        return (
            x:
                x,
            z:
                z,
            tilt:
                tiltDegrees
                * .pi
                / 180
                * strength
        )
    }

    static func updatePageEdgeFan(
        blockNode: SCNNode,
        side: ThumbSide,
        depth: CGFloat,
        totalDepth: CGFloat,
        binding: BookBinding
    ) {
        guard
            let box =
                blockNode.geometry
                as? SCNBox
        else {
            return
        }

        let groupName =
            side == .left
            ? "book.left-page-fan"
            : "book.right-page-fan"

        let prefix =
            side == .left
            ? "book.left-page-fan."
            : "book.right-page-fan."

        let fanGroup:
            SCNNode

        if let existing =
            blockNode.childNode(
                withName:
                    groupName,
                recursively:
                    false
            )
        {
            fanGroup =
                existing
        } else {
            let group =
                SCNNode()

            group.name =
                groupName

            blockNode.addChildNode(
                group
            )

            fanGroup =
                group
        }

        while
            fanGroup.childNodes.count
            < pageFanRibbonCount
        {
            let index =
                fanGroup.childNodes.count

            let plane =
                SCNPlane(
                    width:
                        0.001,
                    height:
                        max(
                            0.001,
                            box.height
                            * 0.992
                        )
                )

            let material =
                SCNMaterial()

            let shade =
                0.82
                + CGFloat(
                    index % 5
                )
                * 0.022

            material.diffuse.contents =
                NSColor(
                    calibratedRed:
                        shade,
                    green:
                        shade
                        * 0.995,
                    blue:
                        shade
                        * 0.965,
                    alpha:
                        0.92
                )

            material.lightingModel =
                .physicallyBased

            material.roughness.contents =
                0.985

            material.metalness.contents =
                0

            material.isDoubleSided =
                true

            plane.materials =
                [
                    material
                ]

            let node =
                SCNNode(
                    geometry:
                        plane
                )

            let suffix =
                index < 10
                ? "0\(index)"
                : "\(index)"

            node.name =
                prefix
                + suffix

            fanGroup.addChildNode(
                node
            )
        }

        while
            fanGroup.childNodes.count
            > pageFanRibbonCount
        {
            fanGroup
                .childNodes
                .last?
                .removeFromParentNode()
        }

        let safeTotal =
            max(
                0.000_1,
                totalDepth
            )

        let fullness =
            min(
                1,
                max(
                    0,
                    depth
                    / safeTotal
                )
            )

        let visible =
            depth
            > max(
                0.000_12,
                safeTotal
                * 0.003
            )

        fanGroup.isHidden =
            !visible

        let envelope =
            pageFanEnvelope(
                binding:
                    binding,
                fullness:
                    fullness,
                blockWidth:
                    box.width,
                totalDepth:
                    safeTotal
            )

        let profileName =
            side == .left
            ? "book.left-page-edge-strata.profile"
            : "book.right-page-edge-strata.profile"

        if let profile =
            blockNode
            .childNode(
                withName:
                    profileName,
                recursively:
                    true
            )
        {
            let pageEdgeProfileBow =
                max(
                    CGFloat(
                        0.000_8
                    ),
                    envelope.z
                    * (
                        binding == .hardcover
                        ? 0.42
                        : 0.55
                    )
                )

            profile.scale =
                SCNVector3(
                    max(
                        0.002,
                        depth
                    ),
                    1,
                    pageEdgeProfileBow
                )

            profile.isHidden =
                depth
                <= 0.001
        }


        let pageVolumeName =
            side == .left
            ? "book.left-page-volume"
            : "book.right-page-volume"

        if let pageVolume =
            blockNode
            .childNode(
                withName:
                    pageVolumeName,
                recursively:
                    false
            )
        {
            let volumeFullness =
                min(
                    CGFloat(1),
                    max(
                        CGFloat(0),
                        depth
                        / safeTotal
                    )
                )

            let existingMaterials =
                pageVolume
                .geometry?
                .materials
                ?? []

            let newVolumeGeometry =
                curvedPageStackVolumeGeometry(
                    width:
                        box.width,
                    height:
                        box.height,
                    depth:
                        max(
                            CGFloat(0.002),
                            depth
                        ),
                    insideEdge:
                        side,
                    binding:
                        binding,
                    fullness:
                        volumeFullness
                )

            newVolumeGeometry.materials =
                existingMaterials

            pageVolume.geometry =
                newVolumeGeometry

            pageVolume.isHidden =
                depth
                <= 0.001
        }

        let endpaperName =
            side == .left
            ? "book.left-endpaper"
            : "book.right-endpaper"

        if let endpaper =
            blockNode
            .childNode(
                withName:
                    endpaperName,
                recursively:
                    false
            )
        {
            let endpaperFullness =
                min(
                    CGFloat(1),
                    max(
                        CGFloat(0),
                        depth
                        / safeTotal
                    )
                )

            let existingMaterials =
                endpaper
                .geometry?
                .materials
                ?? []

            let newEndpaperGeometry =
                pageEndpaperGeometry(
                    width:
                        box.width,
                    height:
                        box.height,
                    depth:
                        max(
                            CGFloat(0.002),
                            depth
                        ),
                    insideEdge:
                        side,
                    binding:
                        binding,
                    fullness:
                        endpaperFullness
                )

            newEndpaperGeometry.materials =
                existingMaterials

            endpaper.geometry =
                newEndpaperGeometry

            endpaper.isHidden =
                depth
                <= 0.001
        }

        let gutterFoldName =
            side == .left
            ? "book.left-gutter-fold"
            : "book.right-gutter-fold"

        if let gutterFold =
            blockNode
            .childNode(
                withName:
                    gutterFoldName,
                recursively:
                    false
            )
        {
            let foldFullness =
                min(
                    CGFloat(1),
                    max(
                        CGFloat(0),
                        depth
                        / safeTotal
                    )
                )

            let existingMaterials =
                gutterFold
                .geometry?
                .materials
                ?? []

            let newFoldGeometry =
                pageGutterFoldGeometry(
                    width:
                        box.width,
                    height:
                        box.height,
                    depth:
                        max(
                            CGFloat(0.002),
                            depth
                        ),
                    insideEdge:
                        side,
                    binding:
                        binding,
                    fullness:
                        foldFullness
                )

            newFoldGeometry.materials =
                existingMaterials

            gutterFold.geometry =
                newFoldGeometry

            gutterFold.isHidden =
                depth
                <= 0.001
        }

        let outerX =
            side == .left
            ? -box.width / 2
            : box.width / 2

        let outward:
            CGFloat =
            side == .left
            ? -1
            : 1

        let denominator =
            CGFloat(
                max(
                    1,
                    pageFanRibbonCount - 1
                )
            )

        let ribbonWidth =
            max(
                0.000_45,
                min(
                    safeTotal
                    * 0.012,
                    max(
                        0.000_45,
                        depth
                        / CGFloat(
                            max(
                                8,
                                pageFanRibbonCount
                                * 2
                            )
                        )
                    )
                )
            )

        for index in
            0..<pageFanRibbonCount
        {
            let node =
                fanGroup
                .childNodes[
                    index
                ]

            guard
                let plane =
                    node.geometry
                    as? SCNPlane
            else {
                continue
            }

            plane.width =
                ribbonWidth

            plane.height =
                max(
                    0.001,
                    box.height
                    * 0.992
                )

            let normalized =
                CGFloat(
                    index
                )
                / denominator

            let centered =
                normalized
                - 0.5

            let distance =
                min(
                    1,
                    abs(
                        centered
                    )
                    * 2
                )

            let outerCurve =
                CGFloat(
                    pow(
                        Double(
                            distance
                        ),
                        1.55
                    )
                )

            let shoulder =
                sin(
                    normalized
                    * .pi
                )

            let micro =
                pageFanMicroVariation[
                    index
                    % pageFanMicroVariation.count
                ]

            let xOffset =
                outward
                * envelope.x
                * (
                    outerCurve
                    * 0.82
                    + abs(
                        micro
                    )
                    * 0.18
                )

            let zOffset =
                depth
                * centered
                + envelope.z
                * (
                    micro
                    * 0.70
                    + (
                        shoulder
                        - 0.5
                    )
                    * 0.16
                )

            let tilt =
                outward
                * envelope.tilt
                * (
                    centered
                    * 1.6
                    + micro
                    * 0.24
                )

            node.position =
                SCNVector3(
                    outerX
                    + outward
                    * 0.000_55
                    + xOffset,
                    0,
                    zOffset
                )

            node.eulerAngles =
                SCNVector3(
                    0,
                    .pi / 2
                    + tilt,
                    0
                )

            node.opacity =
                0.48
                + 0.38
                * shoulder

            node.isHidden =
                !visible
        }
    }

    static func applyPageTurnMassTransfer(
        in scene: SCNScene?,
        project: CoverProject,
        pageCount: Int,
        binding: BookBinding,
        transition: BookPageTurnTransition,
        progress: CGFloat
    ) {
        guard
            let scene,
            let root =
                scene.rootNode
                .childNode(
                    withName:
                        "physical-book.root",
                    recursively:
                        false
                )
        else {
            return
        }

        let geometry =
            PhysicalBookGeometry(
                project:
                    project
            )

        let scale =
            0.7

        let transfer =
            geometry
            .pageTurnMassTransfer(
                pageCount:
                    pageCount,
                fromSpread:
                    transition
                    .fromSpread,
                toSpread:
                    transition
                    .toSpread,
                progress:
                    Double(
                        progress
                    ),
                binding:
                    binding
            )

        let leftLeaves =
            root.childNode(
                withName:
                    "book.left-leaves",
                recursively:
                    false
            )

        func existingBlock(
            side:
                ThumbSide
        ) -> SCNNode? {
            if side == .left {
                return leftLeaves?
                    .childNode(
                        withName:
                            "book.left-page-block",
                        recursively:
                            false
                    )
            }

            return root.childNode(
                withName:
                    "book.right-page-block",
                recursively:
                    false
            )
        }

        func makeTransientBlock(
            side:
                ThumbSide
        ) -> SCNNode? {
            if let existing =
                existingBlock(
                    side:
                        side
                )
            {
                return existing
            }

            let opposite:
                ThumbSide =
                side == .left
                ? .right
                : .left

            guard
                let source =
                    existingBlock(
                        side:
                            opposite
                    ),
                let sourceBox =
                    source.geometry
                    as? SCNBox
            else {
                return nil
            }

            let box =
                SCNBox(
                    width:
                        sourceBox.width,
                    height:
                        sourceBox.height,
                    length:
                        sourceBox.length,
                    chamferRadius:
                        sourceBox.chamferRadius
                )

            box.materials =
                sourceBox.materials

            let node =
                SCNNode(
                    geometry:
                        box
                )

            node.name =
                side == .left
                ? "book.left-page-block"
                : "book.right-page-block"

            node.position =
                SCNVector3(
                    0,
                    CGFloat(
                        geometry.trimHeight
                        * scale
                        / 2
                    ),
                    0
                )

            let innerEdge =
                side == .left
                ? CGFloat(
                    geometry.trimWidth
                    * scale
                    / 2
                )
                : -CGFloat(
                    geometry.trimWidth
                    * scale
                    / 2
                )

            node.pivot =
                SCNMatrix4MakeTranslation(
                    innerEdge,
                    0,
                    0
                )

            let silhouette =
                geometry
                .openSilhouette(
                    open:
                        true,
                    angleDegrees:
                        180,
                    pageCount:
                        pageCount,
                    spreadIndex:
                        transition.fromSpread,
                    binding:
                        binding
                )

            node.eulerAngles.y =
                side == .left
                ? CGFloat(
                    silhouette.leftStackLiftDegrees
                    * .pi
                    / 180
                )
                : -CGFloat(
                    silhouette.rightStackLiftDegrees
                    * .pi
                    / 180
                )

            if side == .left {
                leftLeaves?
                    .addChildNode(
                        node
                    )
            } else {
                root.addChildNode(
                    node
                )
            }

            return node
        }

        let leftBlock =
            makeTransientBlock(
                side:
                    .left
            )

        let rightBlock =
            makeTransientBlock(
                side:
                    .right
            )

        func updateBlock(
            _ node:
                SCNNode?,
            side:
                ThumbSide,
            depth:
                Double
        ) {
            guard
                let node,
                let box =
                    node.geometry
                    as? SCNBox
            else {
                return
            }

            let renderedDepth =
                CGFloat(
                    max(
                        0.000_1,
                        depth
                        * scale
                    )
                )

            let oldDepth = box.length
            let bottom = node.convertPosition(SCNVector3(0,0,-oldDepth/2),to:root)
            box.length = renderedDepth
            // Grow/shrink along the actual stack normal. Reassigning world Z
            // moved the bound bottom and separated paper from its support.
            if let parent = node.parent {
                let desired = parent.convertPosition(bottom,from:root)
                let actual = node.convertPosition(SCNVector3(0,0,-renderedDepth/2),to:parent)
                node.position.x += desired.x-actual.x
                node.position.y += desired.y-actual.y
                node.position.z += desired.z-actual.z
            }
            let baseDepth = (node.value(forKey:"bookTurnBaseDepth") as? NSNumber)?.doubleValue ?? Double(oldDepth)
            node.setValue(NSNumber(value:baseDepth),forKey:"bookTurnBaseDepth")
            if baseDepth > 0 {
                let ratio = renderedDepth/CGFloat(baseDepth)
                for child in node.childNodes where child.name?.contains("page-volume") == true
                    || child.name?.contains("endpaper") == true || child.name?.contains("gutter-fold") == true {
                    let basePosition = (child.value(forKey:"bookTurnBasePositionZ") as? NSNumber)?.doubleValue ?? Double(child.position.z)
                    let baseScale = (child.value(forKey:"bookTurnBaseScaleZ") as? NSNumber)?.doubleValue ?? Double(child.scale.z)
                    let baseGeometry = child.value(forKey:"bookTurnBaseGeometry") as? SCNGeometry ?? child.geometry
                    child.setValue(NSNumber(value:basePosition),forKey:"bookTurnBasePositionZ")
                    child.setValue(NSNumber(value:baseScale),forKey:"bookTurnBaseScaleZ")
                    child.setValue(baseGeometry,forKey:"bookTurnBaseGeometry")
                    child.geometry = baseGeometry
                    child.position.z = (CGFloat(basePosition)+CGFloat(baseDepth)/2)*ratio-renderedDepth/2
                    child.scale.z = CGFloat(baseScale)*ratio
                }
            }

            let strataName =
                side == .left
                ? "book.left-page-edge-strata"
                : "book.right-page-edge-strata"

            if let strata =
                node.childNode(
                    withName:
                        strataName,
                    recursively:
                        false
                )?
                .geometry
                as? SCNPlane
            {
                strata.width =
                    max(
                        0.002,
                        renderedDepth
                    )
            }

            let swellName =
                side == .left
                ? "book.left-page-stack-swell"
                : "book.right-page-stack-swell"

            if let swell =
                node.childNode(
                    withName:
                        swellName,
                    recursively:
                        false
                )
            {
                swell.position.z =
                    renderedDepth
                    / 2
                    + 0.00145
            }

            updatePageEdgeFan(
                blockNode:
                    node,
                side:
                    side,
                depth:
                    renderedDepth,
                totalDepth:
                    CGFloat(
                        transfer.totalDepth
                        * scale
                    ),
                binding:
                    binding
            )
}

        updateBlock(
            leftBlock,
            side:
                .left,
            depth:
                transfer.leftDepth
        )

        updateBlock(
            rightBlock,
            side:
                .right,
            depth:
                transfer.rightDepth
        )

        // Printed faces and the visible volume follow the same physical
        // normal/contact constraints throughout the production turn action.
        for side in ["left","right"] {
            guard let page = root.childNode(withName:"book.\(side)-active-page",recursively:true) else { continue }
            for node in [page] + page.childNodes {
                let base = node.value(forKey:"bookTurnBaseGeometry") as? SCNGeometry ?? node.geometry
                node.setValue(base,forKey:"bookTurnBaseGeometry"); node.geometry = base
            }
        }
        alignOpenPrintedSurfaces(root: root)
        let hingeZ = CGFloat(geometry.pageBlockNearZ(for:binding)*scale)
        BookOpenGutterGeometry.update(in:root,hingeZ:hingeZ,angle:180)
    }

    static func animatePageTurn(in scene: SCNScene?, project: CoverProject, pageCount: Int, binding: BookBinding = .softcover, image: NSImage, reverseImage: NSImage?, transition: BookPageTurnTransition) {
        guard let scene, let root = scene.rootNode.childNode(withName:"physical-book.root",recursively:true) else { return }

        let geometry = PhysicalBookGeometry(project: project), scale = 0.7
        let width = CGFloat(geometry.trimWidth * scale)
        let height = CGFloat(geometry.trimHeight * scale)

        let turnSide: ThumbSide =
            transition.direction == .forward ? .right : .left

        let insideEdge: ThumbSide =
            transition.direction == .forward ? .left : .right

        let landingSide: ThumbSide =
            turnSide == .left ? .right : .left

        let sourceSilhouette =
            geometry.openSilhouette(
                open:
                    true,
                angleDegrees:
                    180,
                pageCount:
                    pageCount,
                spreadIndex:
                    transition.fromSpread,
                binding:
                    binding
            )

        let destinationSilhouette =
            geometry.openSilhouette(
                open:
                    true,
                angleDegrees:
                    180,
                pageCount:
                    pageCount,
                spreadIndex:
                    transition.toSpread,
                binding:
                    binding
            )

        let sourceShoulder =
            turnSide == .left
            ? sourceSilhouette.leftShoulderDepth
            : sourceSilhouette.rightShoulderDepth

        let sourceForeEdge =
            turnSide == .left
            ? sourceSilhouette.leftForeEdgeLift
            : sourceSilhouette.rightForeEdgeLift

        let destinationShoulder =
            landingSide == .left
            ? destinationSilhouette.leftShoulderDepth
            : destinationSilhouette.rightShoulderDepth

        let destinationForeEdge =
            landingSide == .left
            ? destinationSilhouette.leftForeEdgeLift
            : destinationSilhouette.rightForeEdgeLift

        // Restore the source mass before measuring its printed sheet. The GUI
        // warms destination textures while its visible spread is still source.
        applyPageTurnMassTransfer(in:scene,project:project,pageCount:pageCount,binding:binding,transition:transition,progress:0)
        func posedPage(_ side: ThumbSide, in root: SCNNode) -> (points:[SCNVector3], gutter:SCNVector3)? {
            let name = side == .left ? "book.left-active-page":"book.right-active-page"
            guard let node = root.childNode(withName:name,recursively:true),
                  let source = node.geometry?.sources(for:.vertex).first else { return nil }
            let points = BookOpenGutterGeometry.vertices(source).map { node.convertPosition($0,to:root) }
            guard points.count == 74 else { return nil }
            return (points,points[side == .left ? points.count-2:0])
        }
        let sourcePose = posedPage(turnSide,in:root)
        let destination = PhysicalBookGeometry.spread(at:transition.toSpread,pageCount:pageCount)
        // Use the existing deterministic renderer for the landing surface,
        // including its gutter and two-board contact constraints. Cover crops
        // come from the shared cache; this does not rasterize artwork again.
        let landingScene = make(project:project,workingLayers:false,open:true,angle:180,
            leftPage:destination.leftPage,rightPage:destination.rightPage,pageCount:pageCount,spreadIndex:transition.toSpread,
            leftTexture:nil,rightTexture:nil,margins:false,thumbMode:.off,leftPageSettings:PageSettings(),
            rightPageSettings:PageSettings(),preset:.perspective,revisionID:project.id,binding:binding)
        let landingRoot = landingScene.rootNode.childNode(withName:"physical-book.root",recursively:true)
        let landingPose = landingRoot.flatMap { posedPage(landingSide,in:$0) }
        let bindingZ = sourcePose?.gutter.z ?? CGFloat(geometry.pageBlockNearZ(for:binding)*scale)+0.020
        let landingBindingZ = landingPose?.gutter.z ?? bindingZ
        let relativeX = transition.direction == .forward ? width/2 : -width/2

        func posedMesh(_ base: SCNGeometry, points: [SCNVector3], landing: Bool) -> SCNGeometry {
            let ordered: [SCNVector3]
            if landing {
                ordered = stride(from:points.count-2,through:0,by:-2).flatMap { [points[$0],points[$0+1]] }
            } else { ordered = points }
            let vertices = ordered.map { p -> SCNVector3 in
                let x = landing ? -p.x:p.x
                let z = landing ? -(p.z-landingBindingZ):p.z-bindingZ
                return SCNVector3(x-relativeX,p.y-height/2,z)
            }
            return SCNGeometry(sources:[SCNGeometrySource(vertices:vertices)]
                + base.sources.filter { $0.semantic != .vertex && $0.semantic != .normal },elements:base.elements)
        }
        let pivot = SCNNode()
        pivot.name = "book.turning-page-pivot"
        pivot.position = SCNVector3(
            0,
            height / 2,
            bindingZ
        )

        // Begin with a restrained bend at the bound edge.
        var sheet = curvedPaperGeometry(
            width:
                width,
            height:
                height,
            insideEdge:
                insideEdge,
            valleyDepth:
                CGFloat(
                    sourceSilhouette.pageValleyDepth
                    * scale
                ),
            foreEdgeCurl:
                CGFloat(
                    sourceForeEdge
                    * scale
                ),
            shoulderLift:
                CGFloat(
                    sourceShoulder
                    * scale
                )
        )

        if let sourcePose { sheet = posedMesh(sheet,points:sourcePose.points,landing:false) }

        // During the middle of the flip the fore edge rises much more
        // aggressively, reproducing the rolling curl of a flexible sheet.
        let peakCurl = curvedPaperGeometry(
            width: width,
            height: height,
            insideEdge: insideEdge,
            valleyDepth: 0,
            foreEdgeCurl: 0.30
        )

        // As the leaf reaches the opposite stack it relaxes again instead
        // of remaining frozen in the maximum-curl shape.
        var landingCurl = curvedPaperGeometry(
            width:
                width,
            height:
                height,
            insideEdge:
                insideEdge,
            valleyDepth:
                CGFloat(
                    destinationSilhouette.pageValleyDepth
                    * scale
                ),
            foreEdgeCurl:
                CGFloat(
                    destinationForeEdge
                    * scale
                ),
            shoulderLift:
                CGFloat(
                    destinationShoulder
                    * scale
                )
        )

        if let landingPose { landingCurl = posedMesh(landingCurl,points:landingPose.points,landing:true) }
        pivot.setValue(sourcePose != nil && landingPose != nil,forKey:"bookTurnUsesPrintedSurfaces")

        let material = SCNMaterial()
        material.diffuse.contents = image
        material.isDoubleSided = false
        material.lightingModel = .physicallyBased
        material.roughness.contents = 0.9
        material.diffuse.minificationFilter = .linear
        material.diffuse.magnificationFilter = .linear
        material.diffuse.mipFilter = .linear

        let reverseMaterial = SCNMaterial()

        // Never leave the reverse side without printable content. When an
        // adjacent manuscript face is unavailable, retain the source image
        // instead of exposing an untextured/blank SceneKit face.
        reverseMaterial.diffuse.contents = reverseImage ?? image
        reverseMaterial.isDoubleSided = false
        reverseMaterial.lightingModel = .physicallyBased
        reverseMaterial.roughness.contents = 0.9
        reverseMaterial.diffuse.minificationFilter = .linear
        reverseMaterial.diffuse.magnificationFilter = .linear
        reverseMaterial.diffuse.mipFilter = .linear

        var reverseUV = SCNMatrix4Identity
        reverseUV.m11 = -1
        reverseUV.m41 = 1
        reverseMaterial.diffuse.contentsTransform = reverseUV

        sheet.materials = [material, reverseMaterial]

        let leaf = SCNNode(geometry: sheet)
        leaf.name = "book.turning-page-leaf"

        let morpher = SCNMorpher()
        morpher.calculationMode = .normalized
        morpher.targets = [
            peakCurl,
            landingCurl
        ]

        leaf.morpher = morpher

        leaf.position = SCNVector3(
            relativeX,
            0,
            0
        )

        pivot.addChildNode(leaf)

        scene.rootNode
            .childNode(
                withName: "physical-book.root",
                recursively: false
            )?
            .addChildNode(pivot)

        let duration: TimeInterval = 0.48

        let turn = SCNAction.rotateBy(
            x: 0,
            y: transition.rotation,
            z: 0,
            duration: duration
        )

        turn.timingMode = .easeInEaseOut

        let settle = SCNAction.move(
            to: SCNVector3(
                0,
                height / 2,
                landingBindingZ
            ),
            duration: duration
        )

        settle.timingMode = .easeInEaseOut

        let deform = SCNAction.customAction(
            duration: duration
        ) { _, elapsed in
            let progress =
                min(
                    CGFloat(1),
                    max(
                        CGFloat(0),
                        elapsed / CGFloat(duration)
                    )
                )

            let weights =
                pageTurnMorphWeights(
                    progress: progress
                )

            morpher.setWeight(
                weights.peak,
                forTargetAt: 0
            )

            morpher.setWeight(
                weights.landing,
                forTargetAt: 1
            )

            applyPageTurnMassTransfer(
                in:
                    scene,
                project:
                    project,
                pageCount:
                    pageCount,
                binding:
                    binding,
                transition:
                    transition,
                progress:
                    progress
            )
        }

        deform.timingMode = .easeInEaseOut

        pivot.runAction(
            .sequence([
                .group([
                    turn,
                    settle,
                    deform
                ]),
                .removeFromParentNode()
            ])
        )
    }

    private static func addInteriorPage(_ root: SCNNode, image: NSImage?, isManuscriptPage: Bool, pageNumber: Int, x: CGFloat, width: CGFloat, height: CGFloat, z: CGFloat, settings: PageSettings, margins: Bool, side: ThumbSide, thumbMode: ThumbZoneMode, surfaceY: CGFloat, valleyDepth: CGFloat = 0.012, shoulderLift: CGFloat = 0, foreEdgeCurl: CGFloat = 0.003) {
        // An empty stack exposes the cover's own lining. A separate sheet here
        // would float above an inside cover at the first or final spread.
        guard isManuscriptPage else { return }
        let paperShape = curvedPaperGeometry(
            width:
                width,
            height:
                height,
            insideEdge:
                PhysicalBookGeometry
                .insideEdge(
                    side:
                        side
                ),
            valleyDepth:
                valleyDepth,
            foreEdgeCurl:
                foreEdgeCurl,
            shoulderLift:
                shoulderLift
        )

        // The printed manuscript face must itself follow the physical paper
        // surface. Previously the PDF texture lived on a perfectly flat
        // SCNPlane while a separate unprinted curved mesh sat underneath it,
        // so the visible page remained flat even though curved geometry
        // existed in the scene.
        let paperColor = NSColor(calibratedRed: 0.93, green: 0.915, blue: 0.875, alpha: 1)

        let paper = SCNMaterial()
        paper.diffuse.contents = image ?? paperColor
        paper.isDoubleSided = false
        paper.lightingModel = .physicallyBased
        paper.roughness.contents = 0.94
        paper.metalness.contents = 0
        paper.diffuse.minificationFilter = .linear
        paper.diffuse.magnificationFilter = .linear
        paper.diffuse.mipFilter = .linear

        let reversePaper = SCNMaterial()
        reversePaper.diffuse.contents = paperColor
        reversePaper.isDoubleSided = false
        reversePaper.lightingModel = .physicallyBased
        reversePaper.roughness.contents = 0.96
        reversePaper.metalness.contents = 0

        paperShape.materials = [paper, reversePaper]

        let page = SCNNode(geometry: paperShape)
        page.name = side == .left ? "book.left-active-page" : "book.right-active-page"
        page.position = SCNVector3(x + width / 2, height / 2, surfaceY)
        root.addChildNode(page)
        guard isManuscriptPage, margins || thumbMode != .off else { return }
        let pageWidthIn = Double(width / 0.7), pageHeightIn = Double(height / 0.7)
        if margins {
            // Draw the margins that the PDF exporter actually used; diagnostics
            // separately identify an unmirrored facing-page setup.
            let left = CGFloat(settings.leftMargin / 72) * 0.7, right = CGFloat(settings.rightMargin / 72) * 0.7
            let top = CGFloat(settings.topMargin / 72) * 0.7, bottom = CGFloat(settings.bottomMargin / 72) * 0.7
            let safe = SCNPlane(width: max(0.001, width - left - right), height: max(0.001, height - top - bottom)); safe.firstMaterial?.diffuse.contents = NSColor.systemBlue.withAlphaComponent(0.09); safe.firstMaterial?.isDoubleSided = true
            let centerX = x + width / 2 + (left - right) / 2
            let node = SCNNode(geometry: safe); node.position = SCNVector3(centerX, height/2, surfaceY + 0.01); root.addChildNode(node)
        }
        if thumbMode != .off {
            let depth = thumbMode == .standard ? 0.65 : 0.4
            let zone = PhysicalBookGeometry.thumbZone(pageWidth: pageWidthIn, pageHeight: pageHeightIn, depth: depth, side: side, mode: thumbMode)
            let panel = SCNPlane(width: CGFloat(zone.width) * 0.7, height: height); panel.firstMaterial?.diffuse.contents = NSColor.systemOrange.withAlphaComponent(0.2); panel.firstMaterial?.isDoubleSided = true
            let localX = side == .left ? -width/2 + CGFloat(zone.width) * 0.7/2 : width/2 - CGFloat(zone.width) * 0.7/2
            let node = SCNNode(geometry: panel); node.position = SCNVector3(x + width/2 + localX, height/2, surfaceY + 0.015); root.addChildNode(node)
        }
        _ = pageHeightIn
    }

    static func curvedPaperGeometry(width: CGFloat, height: CGFloat, insideEdge: ThumbSide,
                                    valleyDepth: CGFloat, foreEdgeCurl: CGFloat,
                                    shoulderLift: CGFloat = 0) -> SCNGeometry {
        let segments = 36
        var vertices: [SCNVector3] = []; vertices.reserveCapacity((segments + 1) * 2)
        var textureCoordinates: [CGPoint] = []; textureCoordinates.reserveCapacity((segments + 1) * 2)
        for segment in 0...segments {
            let u = CGFloat(segment) / CGFloat(segments)
            let distanceFromGutter = insideEdge == .left ? u : 1 - u
            let valley =
                -valleyDepth
                * pow(
                    1
                    - distanceFromGutter,
                    4
                )

            let shoulderPhase =
                min(
                    1,
                    distanceFromGutter
                    / 0.82
                )

            let shoulderFade =
                max(
                    0,
                    1
                    - distanceFromGutter
                    / 1.10
                )

            let shoulder =
                shoulderLift
                * sin(
                    shoulderPhase
                    * .pi
                )
                * shoulderFade

            let foreEdge =
                foreEdgeCurl
                * pow(
                    distanceFromGutter,
                    8
                )

            let localY =
                valley
                + shoulder
                + foreEdge
            let x = -width / 2 + width * u
            vertices.append(SCNVector3(x, -height / 2, localY))
            vertices.append(SCNVector3(x, height / 2, localY))
            textureCoordinates.append(CGPoint(x: u, y: 1)); textureCoordinates.append(CGPoint(x: u, y: 0))
        }
        var indices: [Int32] = []; indices.reserveCapacity(segments * 6)
        for segment in 0..<segments {
            let lower = Int32(segment * 2), next = lower + 2
            indices.append(contentsOf: [lower, next, next + 1, lower, next + 1, lower + 1])
        }
        let source = SCNGeometrySource(vertices: vertices)
        let uv = SCNGeometrySource(textureCoordinates: textureCoordinates)
        let front = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        var backIndices: [Int32] = []; backIndices.reserveCapacity(indices.count)
        for index in stride(from: 0, to: indices.count, by: 3) {
            backIndices.append(contentsOf: [indices[index], indices[index + 2], indices[index + 1]])
        }
        let back = SCNGeometryElement(indices: backIndices, primitiveType: .triangles)
        return SCNGeometry(sources: [source, uv], elements: [front, back])
    }
}
