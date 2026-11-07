import AppKit

/// The page views are connected AppKit text views, not independent editors:
/// TextKit shares selection, typing state, delegate, text storage, and undo history.
@MainActor
final class PaginatedEditor: NSView {
    let firstView: WritingTextView
    let flow: PageLayout
    let sharedUndoManager = UndoManager()
    private(set) var pages: [WritingTextView] = []
    private(set) var pageRanges: [NSRange] = []

    func revealPhysicalPage(
        _ pageNumber:
            Int,
        selection:
            NSRange?
    ) {
        arrange()

        guard
            !pages.isEmpty
        else {
            return
        }

        let index =
            min(
                max(
                    0,
                    pageNumber - 1
                ),
                pages.count - 1
            )

        if let selection {
            let documentLength =
                firstView.string
                    .utf16
                    .count

            let location =
                min(
                    max(
                        0,
                        selection.location
                    ),
                    documentLength
                )

            let available =
                max(
                    0,
                    documentLength
                    - location
                )

            let length =
                min(
                    max(
                        0,
                        selection.length
                    ),
                    available
                )

            firstView.setSelectedRange(
                NSRange(
                    location:
                        location,
                    length:
                        length
                )
            )
        }

        let page =
            pages[index]

        page.scrollToVisible(
            page.bounds
        )
    }

    private var columnViewsByPage:
        [[WritingTextView]] = [
            []
        ]

    // Physical pages and TextKit containers are intentionally not
    // one-to-one. Word odd/even section starts can require a real
    // physical blank page that must not consume manuscript glyphs.
    //
    // The first manuscript page always owns TextKit container 0.
    // A nil entry represents a parity-only physical blank page.
    private(set) var pageContainerIndices: [[Int]] = [
        [
            0
        ]
    ]

    var syntheticBlankPages: Set<Int> {
        Set(
            pageContainerIndices
                .indices
                .filter {
                    pageContainerIndices[
                        $0
                    ]
                    .isEmpty
                }
        )
    }

    private(set) var printLayout = false
    private(set) var editingEnabled = true
    private(set) var showsLineNumbers = false
    private(set) var geometry: PageGeometry?
    private(set) var sections: [DocumentSection] = []
    private(set) var layoutComplete = true
    private(set) var lastLayoutError: String?
    private(set) var lastBatchPageCount = 0
#if DEBUG
    private(set) var rangeRebuildPageVisitCount = 0
    private(set) var rangeRebuildCallCount = 0
    private(set) var fullScanEquivalentPageVisitCount = 0
    var forceFullRangeRebuildForTesting = false
#endif
    private(set) var floatingImages: [FloatingImage] = []
    private(set) var selectedFloatingImageID: UUID?
    /// Arrow keys control an image only after it was selected on the canvas.
    /// Inspector selection alone must not steal normal text-caret navigation.
    private var floatingImageKeyboardFocusID: UUID?
#if DEBUG
    var anchorPaginationTrace: ((String) -> Void)?
#endif
    var onFloatingImagesChange: (([FloatingImage], String) -> Bool)?
    var onSelectFloatingImage: ((UUID?) -> Void)?
    private var floatingImageCache: [UUID: NSImage] = [:]
    /// The stable, pre-self-wrap placement for text-anchored objects. This
    /// prevents an image from chasing the glyph that its own exclusion moves.
    private var resolvedAnchorSnapshots: [UUID: FloatingImage] = [:]
    private var previewFloatingImages: [FloatingImage]?
    var onLayoutFailure: ((String) -> Void)?
    var configureTextView: ((WritingTextView) -> Void)?
    var onActiveViewRehomed:
        ((WritingTextView, NSRange) -> Void)?
    private var zoom: CGFloat = 1
    private var viewportWidth: CGFloat = 600
    private var pendingPage = 0
    private var scheduled = false
    private var hasConfigured = false
    private var isArranging = false
    private var isPaginating = false
    private var editObserver: NSObjectProtocol?
    private var cachedFootnotes: [Footnote] = []
    private var footnotesNeedRefresh = true
    private let gap: CGFloat = 24
    private let edge: CGFloat = 24
    override var isFlipped: Bool { true }

    func setFloatingImages(_ images: [FloatingImage]) {
        guard !sameVisualImageRecords(floatingImages, images) else { return }
        let old = floatingImages
        floatingImages = images
        resolvedAnchorSnapshots.removeAll(keepingCapacity: true)
        floatingImageCache = Dictionary(uniqueKeysWithValues: images.compactMap { image in
            image.displayImage().map { (image.id, $0) }
        })
        if let selectedFloatingImageID, !images.contains(where: { $0.id == selectedFloatingImageID }) {
            self.selectedFloatingImageID = nil
            floatingImageKeyboardFocusID = nil
        }
        for view in pages + columnViewsByPage.flatMap({ $0 }) { view.needsDisplay = true }
        let oldByID = Dictionary(uniqueKeysWithValues: old.map { ($0.id, $0) })
        let newByID = Dictionary(uniqueKeysWithValues: images.map { ($0.id, $0) })
        let layoutChanged = Set(oldByID.keys).union(newByID.keys).contains { id in
            guard let a = oldByID[id], let b = newByID[id] else {
                return (oldByID[id].map { $0.wrapping != FloatingImage.Wrapping.none } ?? false)
                    || (newByID[id].map { $0.wrapping != FloatingImage.Wrapping.none } ?? false)
            }
            guard a.wrapping != .none || b.wrapping != .none else { return a.wrapping != b.wrapping }
            return a.pageIndex != b.pageIndex || a.anchor != b.anchor || a.anchorLocation != b.anchorLocation || a.anchorOffsetX != b.anchorOffsetX || a.anchorOffsetY != b.anchorOffsetY || a.horizontalPositionReference != b.horizontalPositionReference || a.verticalPositionReference != b.verticalPositionReference || a.horizontalAlignment != b.horizontalAlignment || a.verticalAlignment != b.verticalAlignment || a.x != b.x || a.y != b.y || a.width != b.width || a.height != b.height || a.rotationDegrees != b.rotationDegrees || a.wrapping != b.wrapping || a.wrapDistance != b.wrapDistance || a.effectiveWrapDistances != b.effectiveWrapDistances || a.effectiveWrapSide != b.effectiveWrapSide || a.sourceCrop != b.sourceCrop || a.wrapPolygon != b.wrapPolygon
        }
        if printLayout, layoutChanged { invalidate(from: 0) }
    }

    func selectFloatingImage(_ id: UUID?) {
        // RichTextEditor.updateNSView synchronizes the controller's selection
        // into the canvas on every SwiftUI update. Only publish a selection
        // change when the value actually changes; otherwise the callback
        // invalidates the same view graph that is currently being updated.
        guard selectedFloatingImageID != id else { return }
        selectedFloatingImageID = id
        if id == nil { floatingImageKeyboardFocusID = nil }
        onSelectFloatingImage?(id)
        for view in pages + columnViewsByPage.flatMap({ $0 }) { view.needsDisplay = true }
    }

    private func sameVisualImageRecords(_ lhs: [FloatingImage], _ rhs: [FloatingImage]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        let left = Dictionary(uniqueKeysWithValues: lhs.map { ($0.id, $0) })
        let right = Dictionary(uniqueKeysWithValues: rhs.map { ($0.id, $0) })
        guard left.count == right.count else { return false }
        for (id, a) in left {
            guard let b = right[id], a.assetName == b.assetName, a.imageData.count == b.imageData.count,
                  a.pageIndex == b.pageIndex, a.anchor == b.anchor, a.anchorLocation == b.anchorLocation,
                  a.anchorOffsetX == b.anchorOffsetX, a.anchorOffsetY == b.anchorOffsetY,
                  a.horizontalPositionReference == b.horizontalPositionReference,
                  a.verticalPositionReference == b.verticalPositionReference,
                  a.horizontalAlignment == b.horizontalAlignment,
                  a.verticalAlignment == b.verticalAlignment,
                  a.x == b.x, a.y == b.y, a.width == b.width, a.height == b.height,
                  a.rotationDegrees == b.rotationDegrees, a.preservesAspectRatio == b.preservesAspectRatio,
                  a.sourceCrop == b.sourceCrop, a.wrapPolygon == b.wrapPolygon,
                  a.wrapping == b.wrapping, a.wrapDistance == b.wrapDistance, a.effectiveWrapDistances == b.effectiveWrapDistances, a.effectiveWrapSide == b.effectiveWrapSide, a.layer == b.layer,
                  a.zOrder == b.zOrder, a.positionLocked == b.positionLocked else { return false }
        }
        return true
    }

    private var currentFloatingImages: [FloatingImage] { previewFloatingImages ?? floatingImages }

    private func anchorCharacterLocation(for image: FloatingImage) -> Int {
        FloatingImageLayout.textAnchorLocation(anchor: image.anchor, location: image.anchorLocation,
                                               in: flow.storage.string)
    }

    private func resolvedPageIndex(for image: FloatingImage) -> Int {
        guard image.anchor == .paragraph || image.anchor == .character else { return image.pageIndex }
        let location = anchorCharacterLocation(for: image)
        if let index = pageRanges.indices.first(where: { !isSyntheticBlankPage($0) && NSLocationInRange(location, pageRanges[$0]) }) { return index }
        return image.pageIndex
    }

    /// Returns transient, current layout geometry for an inspector or other
    /// read-only UI. The returned value never replaces the persisted anchor
    /// target or the saved image record.
    func resolvedFloatingImage(_ image: FloatingImage) -> FloatingImage? {
        guard lastLayoutError == nil else { return nil }
        let pageIndex = resolvedPageIndex(for: image)
        if image.anchor == .paragraph || image.anchor == .character {
            guard lastLayoutError == nil,
                  let target = physicalAnchorOrigin(anchor: image.anchor, location: image.anchorLocation) else { return nil }
            let pageOrigin = pages.indices.contains(target.pageIndex)
                ? pages[target.pageIndex].pageGeometry?.contentOrigin ?? .zero : .zero
            let candidate = FloatingImageLayout.positionedAtAnchor(image, pageIndex: target.pageIndex,
                                                                    origin: target.origin, pageContentOrigin: pageOrigin,
                                                                    paragraphOrigin: target.paragraphOrigin,
                                                                    pageGeometry: pages.indices.contains(target.pageIndex)
                                                                        ? pages[target.pageIndex].pageGeometry?.resolvingPhysicalPage(target.pageIndex + 1) : geometry)
            return FloatingImageLayout.applyingAnchorSnapshots([candidate], snapshots: resolvedAnchorSnapshots,
                                                               pageIndex: target.pageIndex).first
        }
        var resolved = image
        resolved.pageIndex = pageIndex
        if image.horizontalAlignment != nil || image.verticalAlignment != nil,
           pages.indices.contains(pageIndex), let pageGeometry = pages[pageIndex].pageGeometry {
            return FloatingImageLayout.positionedAtAnchor(image, pageIndex: pageIndex,
                                                           origin: .zero,
                                                           pageContentOrigin: pageGeometry.contentOrigin,
                                                           pageGeometry: pageGeometry.resolvingPhysicalPage(pageIndex + 1))
        }
        return resolved
    }

    /// Current absolute page coordinates for an image, normalized from the
    /// margin-relative storage convention when needed.
    func resolvedPageOrigin(for image: FloatingImage) -> CGPoint? {
        guard let resolved = resolvedFloatingImage(image) else { return nil }
        let marginOrigin = resolved.anchor == .margins && pages.indices.contains(resolved.pageIndex)
            ? pages[resolved.pageIndex].pageGeometry?.contentOrigin ?? .zero : .zero
        return CGPoint(x: marginOrigin.x + CGFloat(resolved.x), y: marginOrigin.y + CGFloat(resolved.y))
    }

    /// Resolves a logical UTF-16 anchor to its current physical line origin.
    /// TextKit containers and page ranges are the same ones used for the
    /// manuscript layout, so zoom and viewport coordinates never enter this
    /// calculation.
    func physicalAnchorRect(anchor: FloatingImage.Anchor, location: Int) -> (pageIndex: Int, rect: CGRect, paragraphRect: CGRect)? {
        guard (anchor == .paragraph || anchor == .character), flow.storage.length > 0 else { return nil }
        let textLength = flow.storage.length
        let target = FloatingImageLayout.textAnchorLocation(anchor: anchor, location: location,
                                                             in: flow.storage.string)
        guard let pageIndex = pageRanges.indices.first(where: { !isSyntheticBlankPage($0) && NSLocationInRange(target, pageRanges[$0]) }),
              let pageGeometry = pages.indices.contains(pageIndex) ? pages[pageIndex].pageGeometry : geometry else { return nil }
        let mapped = containerIndices(forPhysicalPage: pageIndex)
        for (columnIndex, containerIndex) in mapped.enumerated() where flow.manager.textContainers.indices.contains(containerIndex) {
            let container = flow.manager.textContainers[containerIndex]
            flow.manager.ensureLayout(for: container)
            let glyphs = flow.manager.glyphRange(for: container)
            let characters = flow.manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            guard target >= characters.location && target <= NSMaxRange(characters) else { continue }
            let character = min(target, max(0, textLength - 1))
            let glyph = flow.manager.glyphIndexForCharacter(at: character)
            guard glyph < flow.manager.numberOfGlyphs else { continue }
            var effective = NSRange(location: 0, length: 0)
            let line = flow.manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &effective)
            let anchorRect = anchor == .character
                ? flow.manager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
                : line
            let dx = pageGeometry.contentOrigin.x + pageGeometry.columnOriginX(for: columnIndex)
            let dy = pageGeometry.contentOrigin.y
            let rect = anchorRect.offsetBy(dx: dx, dy: dy)
            let paragraphRect = line.offsetBy(dx: dx, dy: dy)
            return (pageIndex, rect, paragraphRect)
        }
        return nil
    }

    func physicalAnchorOrigin(anchor: FloatingImage.Anchor, location: Int) -> (pageIndex: Int, origin: CGPoint, paragraphOrigin: CGPoint)? {
        guard let resolved = physicalAnchorRect(anchor: anchor, location: location) else { return nil }
        return (resolved.pageIndex, resolved.rect.origin, resolved.paragraphRect.origin)
    }

    private func storedOffset(for image: FloatingImage, pageCoordinate: Double,
                              geometry: PageGeometry, horizontal: Bool) -> Double? {
        let textAnchored = image.anchor == .paragraph || image.anchor == .character
        let anchorOrigin = textAnchored
            ? physicalAnchorOrigin(anchor: image.anchor, location: image.anchorLocation)?.origin : nil
        return FloatingImageLayout.storedAxisOffset(pageCoordinate: pageCoordinate, anchor: image.anchor,
                                                     anchorOrigin: anchorOrigin, geometry: geometry,
                                                     horizontal: horizontal)
    }

    private func resolvedFloatingImages(forPhysicalPage pageIndex: Int,
                                        applyingSnapshots: Bool = true) -> [FloatingImage] {
        let resolved: [FloatingImage] = currentFloatingImages.compactMap { image -> FloatingImage? in
            let resolved = resolvedPageIndex(for: image)
            guard resolved == pageIndex else { return nil }
            if image.anchorOffsetX != nil, image.anchorOffsetY != nil,
               image.anchor == .paragraph || image.anchor == .character {
                // Do not fall back to the stored page while pagination has
                // not reached the logical anchor yet. Doing so can snapshot
                // the image on an earlier, temporary page and strand it
                // there after the target paragraph is eventually laid out.
                guard let target = physicalAnchorOrigin(anchor: image.anchor,
                                                        location: image.anchorLocation),
                      target.pageIndex == pageIndex else { return nil }
                let pageOrigin = pages.indices.contains(target.pageIndex)
                    ? pages[target.pageIndex].pageGeometry?.contentOrigin ?? .zero : .zero
                return FloatingImageLayout.positionedAtAnchor(image, pageIndex: target.pageIndex,
                                                               origin: target.origin, pageContentOrigin: pageOrigin,
                                                               paragraphOrigin: target.paragraphOrigin,
                                                               pageGeometry: pages.indices.contains(target.pageIndex)
                                                                   ? pages[target.pageIndex].pageGeometry?.resolvingPhysicalPage(target.pageIndex + 1) : geometry)
            }
            var copy = image
            copy.pageIndex = resolved
            if image.horizontalAlignment != nil || image.verticalAlignment != nil,
               pages.indices.contains(resolved), let pageGeometry = pages[resolved].pageGeometry {
                return FloatingImageLayout.positionedAtAnchor(image, pageIndex: resolved,
                                                               origin: .zero,
                                                               pageContentOrigin: pageGeometry.contentOrigin,
                                                               pageGeometry: pageGeometry.resolvingPhysicalPage(resolved + 1))
            }
            return copy
        }
        guard applyingSnapshots else { return resolved }
        return FloatingImageLayout.applyingAnchorSnapshots(resolved,
                                                           snapshots: resolvedAnchorSnapshots,
                                                           pageIndex: pageIndex)
    }

    private func sameResolvedFloatingImageLayout(_ lhs: [FloatingImage], _ rhs: [FloatingImage]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        let right = Dictionary(uniqueKeysWithValues: rhs.map { ($0.id, $0) })
        guard right.count == rhs.count else { return false }
        return lhs.allSatisfy { image in
            guard let other = right[image.id] else { return false }
            return image.pageIndex == other.pageIndex && abs(image.x - other.x) < 0.05 && abs(image.y - other.y) < 0.05
        }
    }

    private func initialPageImages(_ pageIndex: Int) -> [FloatingImage] {
        let pageGeometry = pages.indices.contains(pageIndex) ? pages[pageIndex].pageGeometry : geometry
        return currentFloatingImages.compactMap { image in
            guard image.pageIndex == pageIndex else { return nil }
            let textAnchored = image.anchor == .paragraph || image.anchor == .character
            guard !textAnchored || (image.anchorOffsetX == nil && image.anchorOffsetY == nil) else { return nil }
            guard (image.horizontalAlignment != nil || image.verticalAlignment != nil),
                  let pageGeometry else { return image }
            return FloatingImageLayout.positionedAtAnchor(image, pageIndex: pageIndex, origin: .zero,
                                                           pageContentOrigin: pageGeometry.contentOrigin,
                                                           pageGeometry: pageGeometry.resolvingPhysicalPage(pageIndex + 1))
        }
    }

    #if DEBUG
    private func traceAnchorPagination(iteration: Int, pageIndex: Int, pageRange: NSRange,
                                       active: [FloatingImage], candidate: [FloatingImage],
                                       decision: String, geometry: PageGeometry) {
        guard let anchorPaginationTrace else { return }
        func f(_ value: CGFloat) -> String { String(format: "%.2f", Double(value)) }
        func d(_ value: Double) -> String { String(format: "%.2f", value) }
        func imageState(_ image: FloatingImage) -> String {
            let anchor = physicalAnchorRect(anchor: image.anchor, location: image.anchorLocation)
            let glyph = anchor.map { "p\($0.pageIndex + 1):\(f($0.rect.origin.x)),\(f($0.rect.origin.y)),\(f($0.rect.width)),\(f($0.rect.height))" } ?? "unresolved"
            return "\(image.id.uuidString.prefix(8))@\(image.anchorLocation)=\(glyph) image=\(image.pageIndex + 1):\(d(image.x)),\(d(image.y)),\(d(image.width)),\(d(image.height)),r\(d(image.rotationDegrees))"
        }
        let exclusions = FloatingImageLayout.exclusionPaths(images: active, pageIndex: pageIndex,
                                                             geometry: geometry, columnIndex: 0,
                                                             font: FloatingImageLayout.representativeFont(in: flow.storage,
                                                                                                          at: pageRange.location))
            .map { "\(f($0.bounds.origin.x)),\(f($0.bounds.origin.y)),\(f($0.bounds.width)),\(f($0.bounds.height))" }
            .joined(separator: ";")
        let ranges = pageRanges.enumerated().map { "\($0.offset + 1):\($0.element.location)+\($0.element.length)" }.joined(separator: ";")
        let state = "pg\(pageIndex + 1)|range\(pageRange.location)+\(pageRange.length)|a[\(active.map(imageState).joined(separator: ";"))]|c[\(candidate.map(imageState).joined(separator: ";"))]"
        let stateID = String(state.hashValue, radix: 16)
        anchorPaginationTrace("pass=\(iteration + 1) decision=\(decision) state=\(stateID) range=\(pageRange.location)+\(pageRange.length) pages=[\(ranges)] exclusions=[\(exclusions)] active=[\(active.map(imageState).joined(separator: ";"))] candidate=[\(candidate.map(imageState).joined(separator: ";"))]")
    }
    #endif

    func setAnchorOffsets(for image: inout FloatingImage, anchor: FloatingImage.Anchor, location: Int) {
        let previousAnchor = image.anchor
        let currentImage = resolvedFloatingImage(image) ?? image
        let imagePage = currentImage.pageIndex
        guard let target = physicalAnchorOrigin(anchor: anchor, location: location) else {
            image.anchor = anchor
            image.anchorLocation = location
            image.anchorOffsetX = nil
            image.anchorOffsetY = nil
            image.horizontalPositionReference = nil
            image.verticalPositionReference = nil
            image.horizontalAlignment = nil
            image.verticalAlignment = nil
            return
        }
        let coordinateOrigin = previousAnchor == .margins && pages.indices.contains(imagePage)
            ? pages[imagePage].pageGeometry?.contentOrigin ?? .zero : .zero
        image.anchorOffsetX = currentImage.x + Double(coordinateOrigin.x - target.origin.x)
        image.anchorOffsetY = currentImage.y + Double(coordinateOrigin.y - target.origin.y)
        image.anchor = anchor
        image.anchorLocation = location
        image.pageIndex = target.pageIndex
        image.horizontalPositionReference = nil
        image.verticalPositionReference = nil
        image.horizontalAlignment = nil
        image.verticalAlignment = nil
    }

    private func localRect(for image: FloatingImage, in view: WritingTextView) -> CGRect {
        let origin = image.anchor == .margins ? view.pageGeometry?.contentOrigin ?? .zero : .zero
        return CGRect(x: origin.x + image.x, y: origin.y + image.y, width: image.width, height: image.height)
    }

    func drawFloatingImages(in view: WritingTextView, layer: FloatingImage.Layer, dirtyRect: NSRect) {
        guard printLayout, let geometry = view.pageGeometry else { return }
        let pageIndex = view.pageNumber - 1
        for image in resolvedFloatingImages(forPhysicalPage: pageIndex).filter({ $0.layer == layer }).sorted(by: { $0.zOrder < $1.zOrder }) {
            let rect = localRect(for: image, in: view)
            guard rect.intersects(dirtyRect), let source = floatingImageCache[image.id] ?? NSImage(data: image.imageData) else { continue }
            NSGraphicsContext.saveGraphicsState()
            let transform = NSAffineTransform()
            transform.translateX(by: rect.midX, yBy: rect.midY)
            transform.rotate(byDegrees: image.rotationDegrees)
            transform.translateX(by: -rect.midX, yBy: -rect.midY)
            transform.concat()
            source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
            NSGraphicsContext.restoreGraphicsState()
        }
        _ = geometry
    }

    func drawFloatingImageSelection(in view: WritingTextView) {
        guard let id = selectedFloatingImageID, printLayout,
              let image = resolvedFloatingImages(forPhysicalPage: view.pageNumber - 1).first(where: { $0.id == id }) else { return }
        let rect = localRect(for: image, in: view)
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: rect.midX, yBy: rect.midY)
        transform.rotate(byDegrees: image.rotationDegrees)
        transform.translateX(by: -rect.midX, yBy: -rect.midY)
        transform.concat()
        NSColor.controlAccentColor.setStroke()
        let outline = NSBezierPath(rect: rect.insetBy(dx: -1, dy: -1))
        outline.lineWidth = 1.5
        outline.stroke()
        for point in [NSPoint(x: rect.minX, y: rect.minY), NSPoint(x: rect.midX, y: rect.minY), NSPoint(x: rect.maxX, y: rect.minY), NSPoint(x: rect.minX, y: rect.midY), NSPoint(x: rect.maxX, y: rect.midY), NSPoint(x: rect.minX, y: rect.maxY), NSPoint(x: rect.midX, y: rect.maxY), NSPoint(x: rect.maxX, y: rect.maxY)] {
            let handle = NSBezierPath(ovalIn: NSRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8))
            NSColor.white.setFill(); handle.fill(); NSColor.controlAccentColor.setStroke(); handle.stroke()
        }
        let stem = NSBezierPath()
        stem.move(to: NSPoint(x: rect.midX, y: rect.minY))
        stem.line(to: NSPoint(x: rect.midX, y: rect.minY - 14))
        stem.lineWidth = 1
        stem.stroke()
        let rotate = NSBezierPath(ovalIn: NSRect(x: rect.midX - 5, y: rect.minY - 24, width: 10, height: 10))
        NSColor.white.setFill(); rotate.fill(); NSColor.controlAccentColor.setStroke(); rotate.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    @discardableResult
    func handleFloatingImageMouseDown(_ event: NSEvent, in view: WritingTextView) -> Bool {
        guard printLayout, view.isEditable else { return false }
        let point = view.convert(event.locationInWindow, from: nil)
        let candidates = resolvedFloatingImages(forPhysicalPage: view.pageNumber - 1).sorted { $0.zOrder > $1.zOrder }
        guard let image = candidates.first(where: {
            let rect = localRect(for: $0, in: view)
            let target = selectedFloatingImageID == $0.id ? rect.insetBy(dx: -10, dy: -22) : rect.insetBy(dx: -5, dy: -5)
            return target.contains(point)
        }) else {
            floatingImageKeyboardFocusID = nil
            if selectedFloatingImageID != nil { selectedFloatingImageID = nil; onSelectFloatingImage?(nil); view.needsDisplay = true }
            return false
        }
        selectedFloatingImageID = image.id
        floatingImageKeyboardFocusID = image.id
        onSelectFloatingImage?(image.id)
        view.needsDisplay = true
        window?.makeFirstResponder(view)
        guard !image.positionLocked else { return true }

        let original = currentFloatingImages
        let start = point
        let startRect = localRect(for: image, in: view)
        enum DragMode { case move, resize, rotate }
        let handleDistance: CGFloat = 10
        let rotationHandle = NSPoint(x: startRect.midX, y: startRect.minY - 18)
        let mode: DragMode
        if hypot(point.x - rotationHandle.x, point.y - rotationHandle.y) <= handleDistance { mode = .rotate }
        else if hypot(point.x - startRect.maxX, point.y - startRect.maxY) <= handleDistance { mode = .resize }
        else { mode = .move }
        let startAngle = atan2(point.y - startRect.midY, point.x - startRect.midX)
        var changed = false
        var actionName = "Move Image"
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp, .keyDown], until: .distantFuture, inMode: .eventTracking, dequeue: true) {
            if next.type == .keyDown, next.keyCode == 53 { previewFloatingImages = nil; view.needsDisplay = true; return true }
            if next.type == .leftMouseUp { break }
            guard next.type == .leftMouseDragged else { continue }
            let current = view.convert(next.locationInWindow, from: nil)
            let dx = current.x - start.x
            let dy = current.y - start.y
            var updated = original
            guard let idx = updated.firstIndex(where: { $0.id == image.id }) else { break }
            let marginOrigin = image.anchor == .margins ? view.pageGeometry?.contentOrigin ?? .zero : .zero
            switch mode {
            case .move:
                let horizontalWasAligned = updated[idx].horizontalAlignment != nil
                let verticalWasAligned = updated[idx].verticalAlignment != nil
                updated[idx].x = max(0, image.x + dx)
                updated[idx].y = max(0, image.y + dy)
                if let geometry = view.pageGeometry?.resolvingPhysicalPage(image.pageIndex + 1) {
                    let pageX = image.x + (image.anchor == .margins ? Double(geometry.contentOrigin.x) : 0) + Double(dx)
                    let pageY = image.y + (image.anchor == .margins ? Double(geometry.contentOrigin.y) : 0) + Double(dy)
                    if updated[idx].horizontalAlignment != nil {
                        updated[idx].anchorOffsetX = storedOffset(for: updated[idx], pageCoordinate: pageX,
                                                                 geometry: geometry, horizontal: true)
                        if updated[idx].anchor == .paragraph || updated[idx].anchor == .character {
                            updated[idx].horizontalPositionReference = .anchor
                        }
                    }
                    if updated[idx].verticalAlignment != nil {
                        updated[idx].anchorOffsetY = storedOffset(for: updated[idx], pageCoordinate: pageY,
                                                                  geometry: geometry, horizontal: false)
                        if updated[idx].anchor == .paragraph || updated[idx].anchor == .character {
                            updated[idx].verticalPositionReference = .anchor
                        }
                    }
                }
                updated[idx].horizontalAlignment = nil
                updated[idx].verticalAlignment = nil
                if let offsetX = updated[idx].anchorOffsetX, let offsetY = updated[idx].anchorOffsetY {
                    if !horizontalWasAligned { updated[idx].anchorOffsetX = offsetX + Double(dx) }
                    if !verticalWasAligned { updated[idx].anchorOffsetY = offsetY + Double(dy) }
                }
                actionName = "Move Image"
            case .resize:
                var width = max(12, CGFloat(image.width) + dx)
                var height = max(12, CGFloat(image.height) + dy)
                if image.preservesAspectRatio {
                    let scale = max(width / CGFloat(image.width), height / CGFloat(image.height))
                    width = CGFloat(image.width) * scale
                    height = CGFloat(image.height) * scale
                }
                updated[idx].width = Double(width)
                updated[idx].height = Double(height)
                actionName = "Resize Image"
            case .rotate:
                let angle = atan2(current.y - startRect.midY, current.x - startRect.midX)
                updated[idx].rotationDegrees = image.rotationDegrees + Double((angle - startAngle) * 180 / .pi)
                actionName = "Rotate Image"
            }
            if let pageGeometry = view.pageGeometry, mode != .rotate {
                updated[idx].x = min(updated[idx].x, Double(max(0, pageGeometry.size.width - marginOrigin.x - CGFloat(updated[idx].width))))
                updated[idx].y = min(updated[idx].y, Double(max(0, pageGeometry.size.height - marginOrigin.y - CGFloat(updated[idx].height))))
            }
            previewFloatingImages = updated
            changed = true
            for page in pages + columnViewsByPage.flatMap({ $0 }) { page.needsDisplay = true }
        }
        guard changed, let preview = previewFloatingImages else { previewFloatingImages = nil; return true }
        previewFloatingImages = nil
        _ = onFloatingImagesChange?(preview, actionName)
        return true
    }

    @discardableResult
    func handleFloatingImageKeyDown(_ event: NSEvent) -> Bool {
        if event.keyCode == 53, let focusedID = floatingImageKeyboardFocusID {
            floatingImageKeyboardFocusID = nil
            if selectedFloatingImageID == focusedID {
                selectedFloatingImageID = nil
                onSelectFloatingImage?(nil)
                for page in pages + columnViewsByPage.flatMap({ $0 }) { page.needsDisplay = true }
            }
            return true
        }
        guard let id = selectedFloatingImageID,
              floatingImageKeyboardFocusID == id,
              let index = floatingImages.firstIndex(where: { $0.id == id }),
              !floatingImages[index].positionLocked else { return false }
        guard let delta = FloatingImageKeyboardMovement.delta(keyCode: event.keyCode, modifiers: event.modifierFlags) else { return false }
        let dx = delta.x, dy = delta.y
        var next = floatingImages
        let resolved = resolvedFloatingImages(forPhysicalPage: resolvedPageIndex(for: next[index])).first(where: { $0.id == id }) ?? next[index]
        let horizontalWasAligned = next[index].horizontalAlignment != nil
        let verticalWasAligned = next[index].verticalAlignment != nil
        next[index].x = max(0, resolved.x + dx)
        next[index].y = max(0, resolved.y + dy)
        if pages.indices.contains(resolved.pageIndex),
           let rawGeometry = pages[resolved.pageIndex].pageGeometry {
            let geometry = rawGeometry.resolvingPhysicalPage(resolved.pageIndex + 1)
            let pageX = resolved.x + (resolved.anchor == .margins ? Double(geometry.contentOrigin.x) : 0) + dx
            let pageY = resolved.y + (resolved.anchor == .margins ? Double(geometry.contentOrigin.y) : 0) + dy
            if next[index].horizontalAlignment != nil {
                next[index].anchorOffsetX = storedOffset(for: next[index], pageCoordinate: pageX,
                                                         geometry: geometry, horizontal: true)
                if next[index].anchor == .paragraph || next[index].anchor == .character {
                    next[index].horizontalPositionReference = .anchor
                }
            }
            if next[index].verticalAlignment != nil {
                next[index].anchorOffsetY = storedOffset(for: next[index], pageCoordinate: pageY,
                                                          geometry: geometry, horizontal: false)
                if next[index].anchor == .paragraph || next[index].anchor == .character {
                    next[index].verticalPositionReference = .anchor
                }
            }
        }
        next[index].horizontalAlignment = nil
        next[index].verticalAlignment = nil
        if let offsetX = next[index].anchorOffsetX, let offsetY = next[index].anchorOffsetY {
            if !horizontalWasAligned { next[index].anchorOffsetX = offsetX + dx }
            if !verticalWasAligned { next[index].anchorOffsetY = offsetY + dy }
        }
        _ = onFloatingImagesChange?(next, "Nudge Image")
        return true
    }

    override func mouseDown(
        with event: NSEvent
    ) {
        guard !printLayout else {
            super.mouseDown(
                with:
                    event
            )
            return
        }

        guard
            firstView.isEditable,
            firstView.isSelectable
        else {
            super.mouseDown(
                with:
                    event
            )
            return
        }

        window?
            .makeFirstResponder(
                firstView
            )

        firstView.mouseDown(
            with:
                event
        )
    }

    init(text: NSAttributedString) {
        let storage = NSTextStorage(attributedString: text)
        let manager = NSLayoutManager()
        storage.addLayoutManager(manager)
        flow = PageLayout(storage: storage, manager: manager)
        let container = flow.addContainer(size: NSSize(width: 500, height: CGFloat.greatestFiniteMagnitude))
        firstView = WritingTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 600), textContainer: container)
        super.init(frame: NSRect(x: 0, y: 0, width: 600, height: 600))
        pages = [firstView]
        // The automatic macOS Writing Tools selection affordance can retain a
        // retiring connected page and abort in NSTextView.dealloc (clientView)
        // when returning from Studio. This custom multi-view editor does not
        // support that separate inline editor.
        if #available(macOS 15.0, *) { firstView.writingToolsBehavior = .none }
        firstView.sessionUndoManager = sharedUndoManager
        addSubview(firstView)
        editObserver = NotificationCenter.default.addObserver(forName: NSTextStorage.didProcessEditingNotification, object: storage, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?.textWasEdited() }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { if let editObserver { NotificationCenter.default.removeObserver(editObserver) } }

    func setEditingEnabled(
        _ enabled: Bool
    ) {
        editingEnabled =
            enabled

        for view in pages {
            view.isEditable =
                enabled

            view.isSelectable =
                true
        }

        for columns in columnViewsByPage {
            for view in columns {
                view.isEditable =
                    enabled

                view.isSelectable =
                    true
            }
        }
    }

    func setShowsInvisibleCharacters(
        _ visible: Bool
    ) {
        for view in pages {
            view.layoutManager?
                .showsInvisibleCharacters =
                visible

            view.needsDisplay =
                true
        }

        for columns in columnViewsByPage {
            for view in columns {
                view.layoutManager?
                    .showsInvisibleCharacters =
                    visible

                view.needsDisplay =
                    true
            }
        }
    }

    func setShowsLineNumbers(
        _ visible: Bool
    ) {
        showsLineNumbers =
            visible

        for view in pages {
            view.showsLineNumbers =
                visible
        }

        for columns in columnViewsByPage {
            for view in columns {
                view.showsLineNumbers =
                    visible
            }
        }
    }

    func configure(
        printLayout: Bool,
        documentLength: Int? = nil,
        settings: PageSettings,
        sections: [DocumentSection]? = nil,
        zoom: Double,
        viewportWidth: CGFloat
    ) {
        self.viewportWidth = max(1, viewportWidth)

        let effectiveDocumentLength =
            max(
                documentLength ?? 0,
                flow.storage.length
            )

        let normalizedSections =
            DocumentSection.normalized(
                sections ?? [],
                textLength:
                    flow.storage.length,
                fallbackPage:
                    settings
            )

        let printLayout =
            LargeDocumentPolicy
                .effectivePrintLayout(
                    requested:
                        printLayout,
                    textLength:
                        effectiveDocumentLength
                )

        let newZoom =
            CGFloat(
                min(
                    2.0,
                    max(
                        0.5,
                        zoom
                    )
                )
            )

        let switching =
            hasConfigured
                && self.printLayout
                    != printLayout

        let settingsChanged =
            geometry?.settings != settings

        let sectionsChanged =
            self.sections != normalizedSections

        self.sections =
            normalizedSections

        flow.sectionBreakLocations =
            Set(
                normalizedSections
                    .dropFirst()
                    .filter {
                        $0.effectiveBreakType
                            != .continuous
                    }
                    .map(
                        \.location
                    )
            )

        let selection =
            firstView.selectedRange()

        self.zoom =
            newZoom
        if !hasConfigured
            || switching
            || (
                printLayout
                    && (
                        settingsChanged
                            || sectionsChanged
                    )
            ) {
            hasConfigured = true
            if printLayout {
                do { geometry = try PageGeometry(settings) }
                catch { fail(error.localizedDescription); return }
            }
            self.printLayout = printLayout
            flow.paginated = printLayout
            if !printLayout { trimPages(to: 1); pageRanges = [] }
            for (index, view) in pages.enumerated() { configurePage(view, index: index) }
            flow.manager.invalidateLayout(forCharacterRange: NSRange(location: 0, length: flow.storage.length), actualCharacterRange: nil)
            if firstView.selectedRange()
                != selection {
                firstView.setSelectedRange(
                    selection
                )
            }
            if printLayout { invalidate(from: 0) }
        }
        arrange()
        if printLayout && !layoutComplete { paginateBatch(maxPages: 2) }
    }


    func pageSettings(
        forCharacter character: Int
    ) -> PageSettings {
        let point =
            min(
                max(
                    0,
                    character
                ),
                flow.storage.length
            )

        if let section =
            sections.last(
                where: {
                    $0.location
                        <= point
                }
            ) {

            return section.page
        }

        return geometry?.settings
            ?? PageSettings()
    }

    func pageGeometry(
        forCharacter character: Int
    ) throws -> PageGeometry {
        try PageGeometry(
            pageSettings(
                forCharacter:
                    character
            )
        )
    }
    private func section(
        forCharacter character: Int
    ) -> DocumentSection {
        let point =
            min(
                max(
                    0,
                    character
                ),
                flow.storage.length
            )

        if let section =
            sections.last(
                where: {
                    $0.location
                        <= point
                }
            ) {

            return section
        }

        return DocumentSection(
            location:
                0,
            page:
                geometry?.settings
                ?? PageSettings()
        )
    }

    private func requiresParityBlank(
        for section: DocumentSection,
        physicalPage: Int
    ) -> Bool {
        switch section.effectiveBreakType {
        case .oddPage:
            return physicalPage
                .isMultiple(
                    of: 2
                )

        case .evenPage:
            return !physicalPage
                .isMultiple(
                    of: 2
                )

        case .nextPage,
             .continuous,
             .nextColumn:
            return false
        }
    }

    private func containerIndices(
        forPhysicalPage index: Int
    ) -> [Int] {
        guard
            pageContainerIndices
                .indices
                .contains(
                    index
                )
        else {
            return []
        }

        return pageContainerIndices[
            index
        ]
    }

    private func ensureContainerCount(
        forPhysicalPage index: Int,
        geometry pageGeometry: PageGeometry
    ) throws {
        guard
            pageContainerIndices
                .indices
                .contains(
                    index
                )
        else {
            throw WriterError.message(
                "The physical page and TextKit container maps became unsynchronized."
            )
        }

        let targetCount =
            max(
                1,
                pageGeometry.columnCount
            )

        while pageContainerIndices[
            index
        ]
        .count < targetCount {

            let containerIndex =
                flow.manager
                    .textContainers
                    .count

            _ =
                flow.addColumnContainer(
                    geometry:
                        pageGeometry
                )

            pageContainerIndices[
                index
            ]
            .append(
                containerIndex
            )
        }

        while pageContainerIndices[
            index
        ]
        .count > targetCount {

            guard
                let containerIndex =
                    pageContainerIndices[
                        index
                    ]
                    .popLast(),
                containerIndex >= 0,
                containerIndex
                    < flow.manager
                        .textContainers
                        .count
            else {
                throw WriterError.message(
                    "A physical page contains an invalid TextKit container."
                )
            }

            flow.manager
                .removeTextContainer(
                    at:
                        containerIndex
                )

            for mappingIndex
                in pageContainerIndices
                    .indices {

                pageContainerIndices[
                    mappingIndex
                ] =
                    pageContainerIndices[
                        mappingIndex
                    ]
                    .map {
                        existing in

                        existing
                            > containerIndex
                            ? existing - 1
                            : existing
                    }
            }
        }


        try synchronizeColumnViews(
            forPhysicalPage:
                index,
            geometry:
                pageGeometry
        )
}

    private func writingColumnHeight(
        for view: WritingTextView,
        geometry pageGeometry: PageGeometry,
        reservedFootnoteHeight: CGFloat
    ) -> CGFloat {
        let maximum =
            max(
                1,
                pageGeometry
                    .contentSize
                    .height
                    - reservedFootnoteHeight
            )

        guard
            pageGeometry.columnCount > 1,
            let container =
                view.textContainer,
            container.containerSize.height
                .isFinite
        else {
            return maximum
        }

        return min(
            maximum,
            max(
                1,
                container
                    .containerSize
                    .height
            )
        )
    }


    private func synchronizeColumnViews(
        forPhysicalPage index: Int,
        geometry pageGeometry: PageGeometry
    ) throws {
        guard
            pages.indices.contains(index),
            pageContainerIndices.indices.contains(index)
        else {
            throw WriterError.message(
                "The physical page and column views became unsynchronized."
            )
        }

        while columnViewsByPage.count <= index {
            columnViewsByPage.append([])
        }

        let mapped =
            pageContainerIndices[index]

        let target =
            max(
                0,
                mapped.count - 1
            )

        while columnViewsByPage[index].count > target {
            columnViewsByPage[index]
                .removeLast()
                .removeFromSuperview()
        }

        while columnViewsByPage[index].count < target {
            let offset =
                columnViewsByPage[index].count + 1

            guard offset < mapped.count else {
                throw WriterError.message(
                    "A secondary column is missing its TextKit container."
                )
            }

            let containerIndex =
                mapped[offset]

            guard
                containerIndex >= 0,
                containerIndex
                    < flow.manager.textContainers.count
            else {
                throw WriterError.message(
                    "A secondary column references an invalid TextKit container."
                )
            }

            let columnView =
                makeSecondaryColumnView(
                    container:
                        flow.manager.textContainers[
                            containerIndex
                        ],
                    geometry:
                        pageGeometry
                )

            columnViewsByPage[index].append(
                columnView
            )

            addSubview(
                columnView
            )
        }
    }

    private func discardRemainingColumns(
        onPhysicalPage pageIndex: Int,
        after offset: Int
    ) throws {
        guard
            pageContainerIndices.indices.contains(
                pageIndex
            ),
            offset >= 0
        else {
            return
        }

        let mapped =
            pageContainerIndices[
                pageIndex
            ]

        guard
            offset + 1 < mapped.count
        else {
            return
        }

        let removedIndices =
            Array(
                mapped.dropFirst(
                    offset + 1
                )
            )
            .sorted(
                by: >
            )

        pageContainerIndices[
            pageIndex
        ] =
            Array(
                mapped.prefix(
                    offset + 1
                )
            )

        if columnViewsByPage.indices.contains(
            pageIndex
        ) {
            let secondaryViewsToKeep =
                max(
                    0,
                    offset
                )

            while columnViewsByPage[
                pageIndex
            ].count > secondaryViewsToKeep {

                columnViewsByPage[
                    pageIndex
                ]
                .removeLast()
                .removeFromSuperview()
            }
        }

        for containerIndex
            in removedIndices {

            guard
                containerIndex >= 0,
                containerIndex
                    < flow.manager
                        .textContainers
                        .count
            else {
                continue
            }

            flow.manager.removeTextContainer(
                at:
                    containerIndex
            )

            for mappingIndex
                in pageContainerIndices.indices {

                pageContainerIndices[
                    mappingIndex
                ] =
                    pageContainerIndices[
                        mappingIndex
                    ]
                    .map {
                        existing in

                        existing > containerIndex
                            ? existing - 1
                            : existing
                    }
            }
        }
    }

    private func applyTerminalColumnBalancing(
        pageIndex: Int,
        startCharacter: Int,
        currentSection: DocumentSection,
        geometry currentGeometry: PageGeometry,
        containerIndices: [Int],
        physicalRange: inout NSRange,
        finishedPage: inout Bool,
        reservedFootnoteHeight: CGFloat,
        hasIncomingFootnotes: Bool,
        hasOutgoingFootnotes: Bool
    ) throws {
        guard
            finishedPage,
            currentGeometry.columnCount > 1,
            containerIndices.count
                == currentGeometry.columnCount,
            reservedFootnoteHeight <= 0.5,
            !hasIncomingFootnotes,
            !hasOutgoingFootnotes,
            flow.storage.length > startCharacter,
            !flow.hasStructuralBreak(
                atEndOf:
                    physicalRange
            )
        else {
            return
        }

        let finalCharacter =
            max(
                0,
                flow.storage.length - 1
            )

        let finalSection =
            section(
                forCharacter:
                    finalCharacter
            )

        // Continuous-section column ownership remains deliberately
        // excluded. The physical page must begin in the same section
        // that owns the final document character.
        guard
            finalSection.location
                == currentSection.location
        else {
            return
        }

        let characters =
            NSRange(
                location:
                    startCharacter,
                length:
                    flow.storage.length
                        - startCharacter
            )

        guard
            let balancedHeight =
                try flow
                    .minimumBalancedColumnHeight(
                        for:
                            characters,
                        geometry:
                            currentGeometry,
                        maximumHeight:
                            currentGeometry
                                .contentSize
                                .height
                    ),
            balancedHeight.isFinite,
            balancedHeight > 0,
            balancedHeight
                < currentGeometry
                    .contentSize
                    .height
                    - 0.5
        else {
            return
        }

        for containerIndex
            in containerIndices {

            guard
                containerIndex >= 0,
                containerIndex
                    < flow.manager
                        .textContainers
                        .count
            else {
                throw WriterError.message(
                    "A balanced column references an invalid TextKit container."
                )
            }

            flow.manager
                .textContainers[
                    containerIndex
                ]
                .containerSize =
                    NSSize(
                        width:
                            currentGeometry
                                .columnWidth,
                        height:
                            balancedHeight
                    )
        }

        flow.manager.invalidateLayout(
            forCharacterRange:
                characters,
            actualCharacterRange:
                nil
        )

        var combinedCharacters:
            NSRange?

        var balancedFinished =
            false

        for containerIndex
            in containerIndices {

            let container =
                flow.manager
                    .textContainers[
                        containerIndex
                    ]

            container.exclusionPaths = FloatingImageLayout.exclusionPaths(
                images: resolvedFloatingImages(forPhysicalPage: pageIndex),
                pageIndex: pageIndex,
                geometry: currentGeometry,
                columnIndex: containerIndices.firstIndex(of: containerIndex) ?? 0,
                font: FloatingImageLayout.representativeFont(in: flow.storage, at: startCharacter)
            )

            let column =
                try flow.layout(
                    container,
                    geometry:
                        currentGeometry
                )

            if let existing =
                combinedCharacters {

                let lower =
                    min(
                        existing.location,
                        column.characters.location
                    )

                let upper =
                    max(
                        NSMaxRange(
                            existing
                        ),
                        NSMaxRange(
                            column.characters
                        )
                    )

                combinedCharacters =
                    NSRange(
                        location:
                            lower,
                        length:
                            max(
                                0,
                                upper - lower
                            )
                    )
            } else {
                combinedCharacters =
                    column.characters
            }

            if column.finished {
                balancedFinished =
                    true
                break
            }
        }

        guard
            balancedFinished,
            let combinedCharacters,
            NSMaxRange(
                combinedCharacters
            ) >= flow.storage.length
        else {
            throw WriterError.message(
                "Balanced final-column layout did not reach the end of the document."
            )
        }

        physicalRange =
            combinedCharacters

        finishedPage =
            true

        guard
            pages.indices.contains(
                pageIndex
            )
        else {
            return
        }

        pages[
            pageIndex
        ]
        .writingContentSizeOverride =
            NSSize(
                width:
                    currentGeometry
                        .columnWidth,
                height:
                    balancedHeight
            )

        if columnViewsByPage.indices.contains(
            pageIndex
        ) {
            for columnView
                in columnViewsByPage[
                    pageIndex
                ] {

                columnView
                    .writingContentSizeOverride =
                        NSSize(
                            width:
                                currentGeometry
                                    .columnWidth,
                            height:
                                balancedHeight
                        )
            }
        }
    }


    @discardableResult
    private func rebuildPhysicalPageRangesFromTextKit(
        startingAt requestedStartPage: Int = 0,
        through requestedEndPage: Int? = nil
    ) -> Int {
        guard printLayout else {
            return 0
        }

        let startPage = min(
            max(0, requestedStartPage),
            min(pageRanges.count, pageContainerIndices.count)
        )
        let endPage = min(
            pageContainerIndices.count,
            max(startPage, requestedEndPage ?? pageContainerIndices.count)
        )
#if DEBUG
        rangeRebuildCallCount += 1
        fullScanEquivalentPageVisitCount += pageContainerIndices.count
#endif
        var rebuilt = Array(pageRanges.prefix(startPage))
        rebuilt.reserveCapacity(pageContainerIndices.count)
        var lastCharacter = rebuilt.last.map(NSMaxRange) ?? 0

        for physicalIndex in startPage..<endPage {
            let containerIndices = pageContainerIndices[physicalIndex]
#if DEBUG
            rangeRebuildPageVisitCount += 1
#endif

            if containerIndices.isEmpty {
                let location =
                    physicalIndex < pageRanges.count
                    ? pageRanges[physicalIndex].location
                    : lastCharacter

                rebuilt.append(
                    NSRange(
                        location:
                            max(
                                lastCharacter,
                                location
                            ),
                        length:
                            0
                    )
                )

                continue
            }

            var combined:
                NSRange?

            for containerIndex
                in containerIndices {

                guard
                    containerIndex >= 0,
                    containerIndex
                        < flow.manager.textContainers.count
                else {
                    continue
                }

                let container =
                    flow.manager.textContainers[
                        containerIndex
                    ]

                flow.manager.ensureLayout(
                    for:
                        container
                )

                let glyphs =
                    flow.manager.glyphRange(
                        for:
                            container
                    )

                let characters =
                    flow.manager.characterRange(
                        forGlyphRange:
                            glyphs,
                        actualGlyphRange:
                            nil
                    )

                if let existing =
                    combined {

                    let start =
                        min(
                            existing.location,
                            characters.location
                        )

                    let end =
                        max(
                            NSMaxRange(
                                existing
                            ),
                            NSMaxRange(
                                characters
                            )
                        )

                    combined =
                        NSRange(
                            location:
                                start,
                            length:
                                max(
                                    0,
                                    end - start
                                )
                        )

                } else {
                    combined =
                        characters
                }
            }

            let range =
                combined
                ?? NSRange(
                    location:
                        lastCharacter,
                    length:
                        0
                )

            rebuilt.append(
                range
            )

            lastCharacter =
                NSMaxRange(
                    range
                )
        }

        if endPage < pageRanges.count {
            rebuilt.append(contentsOf: pageRanges[endPage...])
        }

        pageRanges =
            rebuilt

        return lastCharacter
    }


    private func isSyntheticBlankPage(
        _ index: Int
    ) -> Bool {
        guard
            pageContainerIndices
                .indices
                .contains(
                    index
                )
        else {
            return false
        }

        return containerIndices(
            forPhysicalPage:
                index
        )
        .isEmpty
    }

    private func renumberPhysicalPages(
        from index: Int
    ) {
        guard
            !pages.isEmpty
        else {
            return
        }

        let start =
            min(
                max(
                    0,
                    index
                ),
                pages.count
            )

        guard
            start < pages.count
        else {
            return
        }

        for pageIndex
            in start..<pages.count {

            pages[
                pageIndex
            ]
            .pageNumber =
                pageIndex + 1
        }
    }

    private func pageStartCharacter(
        for index: Int
    ) -> Int {
        guard index > 0 else {
            return 0
        }

        let previousIndex =
            index - 1

        if previousIndex < pageRanges.count {
            return min(
                flow.storage.length,
                NSMaxRange(
                    pageRanges[
                        previousIndex
                    ]
                )
            )
        }

        return min(
            flow.storage.length,
            pageRanges.last.map {
                NSMaxRange($0)
            } ?? 0
        )
    }

    private func sectionStartLocation(
        forCharacter character: Int
    ) -> Int {
        sections.last(
            where: {
                $0.location
                    <= character
            }
        )?
        .location
        ?? 0
    }

    private func sectionPageNumber(
        forPage index: Int,
        startCharacter: Int
    ) -> Int {
        guard
            index > 0
        else {
            return 1
        }

        let sectionStart =
            sectionStartLocation(
                forCharacter:
                    startCharacter
            )

        var priorPages =
            0

        for priorIndex
            in 0..<index {

            guard
                !isSyntheticBlankPage(
                    priorIndex
                )
            else {
                continue
            }

            let priorStart =
                pageStartCharacter(
                    for:
                        priorIndex
                )

            if priorStart
                >= sectionStart {

                priorPages += 1
            }
        }

        return priorPages
            + 1
    }

    private func displayedPageNumber(
        for index: Int,
        geometry: PageGeometry?,
        sectionPageNumber: Int
    ) -> Int {
        if let restart =
            geometry?
                .settings
                .pageNumberStart,
           index == 0
            || sectionPageNumber == 1 {

            return max(
                1,
                restart
            )
        }

        guard
            index > 0,
            pages.indices.contains(
                index - 1
            )
        else {
            return 1
        }

        return pages[
            index - 1
        ]
        .displayPageNumber
            + 1
    }

    private func configurePage(
        _ view: WritingTextView,
        index: Int,
        geometry pageGeometry: PageGeometry? = nil,
        sectionPageNumber: Int? = nil
    ) {
        view.floatingImageCanvas = self
        let resolvedGeometry =
            printLayout
                ? (
                    pageGeometry
                        ?? geometry
                )
                : nil

        view.pageGeometry =
            resolvedGeometry

        view.pageNumber =
            index + 1

        let resolvedSectionPageNumber =
            sectionPageNumber
            ?? 1

        view.sectionPageNumber =
            resolvedSectionPageNumber

        view.displayPageNumber =
            displayedPageNumber(
                for:
                    index,
                geometry:
                    resolvedGeometry,
                sectionPageNumber:
                    resolvedSectionPageNumber
            )

        view.isVerticallyResizable =
            !printLayout

        view.isHorizontallyResizable =
            false

        view.autoresizingMask =
            []

        view.showsLineNumbers =
            showsLineNumbers

        view.appearance =
            printLayout
                ? NSAppearance(
                    named:
                        .aqua
                )
                : nil

        view.usesAdaptiveColorMappingForDarkAppearance =
            !printLayout

        view.drawsBackground = !printLayout
        view.backgroundColor =
            printLayout
                ? .white
                : .textBackgroundColor

        view.insertionPointColor =
            printLayout
                ? .black
                : .textColor

        if printLayout,
           let resolvedGeometry {

            view.writingMargins =
                NSEdgeInsets(
                    top:
                        resolvedGeometry
                            .settings
                            .topMargin,
                    left:
                        resolvedGeometry
                            .settings
                            .leftMargin,
                    bottom:
                        resolvedGeometry
                            .settings
                            .bottomMargin,
                    right:
                        resolvedGeometry
                            .settings
                            .rightMargin
                )

        } else {
            view.writingMargins =
                NSEdgeInsets(
                    top: 42,
                    left: 52,
                    bottom: 42,
                    right: 52
                )
        }

        view.textContainer?
            .lineFragmentPadding =
                printLayout
                    ? 0
                    : 5

        view.needsDisplay =
            true
    }

    private func makeSecondaryColumnView(
        container: NSTextContainer,
        geometry pageGeometry: PageGeometry
    ) -> WritingTextView {
        let view =
            WritingTextView(
                frame:
                    NSRect(
                        origin:
                            .zero,
                        size:
                            pageGeometry.size
                    ),
                textContainer:
                    container
            )

        if #available(macOS 15.0, *) { view.writingToolsBehavior = .none }
        view.sessionUndoManager =
            sharedUndoManager

        configureTextView?(
            view
        )

        view.showsLineNumbers =
            showsLineNumbers

        view.drawsPageFurniture =
            false

        view.backgroundColor =
            .clear

        view.drawsBackground =
            false

        view.writingContentSizeOverride =
            NSSize(
                width:
                    pageGeometry
                        .columnWidth,
                height:
                    pageGeometry
                        .contentSize
                        .height
            )

        return view
    }

    private func addPage(
        geometry pageGeometry: PageGeometry,
        sectionPageNumber: Int
    ) {
        let firstContainerIndex =
            flow.manager
                .textContainers
                .count

        let firstContainer:
            NSTextContainer

        if pageGeometry.columnCount > 1 {
            firstContainer =
                flow.addColumnContainer(
                    geometry:
                        pageGeometry
                )
        } else {
            firstContainer =
                flow.addContainer(
                    size:
                        pageGeometry
                            .contentSize
                )
        }

        var mappedContainerIndices =
            [
                firstContainerIndex
            ]

        if pageGeometry.columnCount > 1 {
            for _
                in 1
                    ..<
                    pageGeometry
                        .columnCount {

                let containerIndex =
                    flow.manager
                        .textContainers
                        .count

                _ =
                    flow.addColumnContainer(
                        geometry:
                            pageGeometry
                    )

                mappedContainerIndices
                    .append(
                        containerIndex
                    )
            }
        }

        let view =
            WritingTextView(
                frame:
                    NSRect(
                        origin:
                            .zero,
                        size:
                            pageGeometry.size
                    ),
                textContainer:
                    firstContainer
            )

        if #available(macOS 15.0, *) { view.writingToolsBehavior = .none }
        view.sessionUndoManager =
            sharedUndoManager

        configureTextView?(
            view
        )

        configurePage(
            view,
            index:
                pages.count,
            geometry:
                pageGeometry,
            sectionPageNumber:
                sectionPageNumber
        )

        pages.append(
            view
        )

        pageContainerIndices.append(
            mappedContainerIndices
        )

        var secondaryViews:
            [WritingTextView] = []

        if mappedContainerIndices.count > 1 {
            for containerIndex
                in mappedContainerIndices
                    .dropFirst() {

                guard
                    containerIndex >= 0,
                    containerIndex
                        < flow.manager
                            .textContainers
                            .count
                else {
                    continue
                }

                let columnView =
                    makeSecondaryColumnView(
                        container:
                            flow.manager
                                .textContainers[
                                    containerIndex
                                ],
                        geometry:
                            pageGeometry
                    )

                secondaryViews.append(
                    columnView
                )

                addSubview(
                    columnView
                )
            }
        }

        columnViewsByPage.append(
            secondaryViews
        )

        addSubview(
            view
        )
    }

    private func ensureSyntheticBlankPage(
        at index: Int,
        character: Int,
        geometry pageGeometry: PageGeometry,
        sectionPageNumber: Int
    ) throws {
        guard
            index >= 0,
            index <= pages.count
        else {
            throw WriterError.message(
                "Invalid physical blank-page position."
            )
        }

        if index < pages.count,
           isSyntheticBlankPage(
            index
           ) {

            configurePage(
                pages[
                    index
                ],
                index:
                    index,
                geometry:
                    pageGeometry,
                sectionPageNumber:
                    sectionPageNumber
            )

            let range =
                NSRange(
                    location:
                        character,
                    length:
                        0
                )

            if index < pageRanges.count {
                pageRanges[
                    index
                ] =
                    range

            } else if index
                == pageRanges.count {

                pageRanges.append(
                    range
                )

            } else {
                throw WriterError.message(
                    "Physical-page ranges became unsynchronized."
                )
            }

            return
        }

        let blank =
            WritingTextView(
                frame:
                    NSRect(
                        origin:
                            .zero,
                        size:
                            pageGeometry.size
                    ),
                textContainer:
                    nil
            )

        blank.isEditable =
            false

        blank.isSelectable =
            false

        blank.drawsBackground =
            true

        if #available(macOS 15.0, *) {
            blank.writingToolsBehavior = .none
        }
        blank.sessionUndoManager =
            sharedUndoManager

        configurePage(
            blank,
            index:
                index,
            geometry:
                pageGeometry,
            sectionPageNumber:
                sectionPageNumber
        )

        pages.insert(
            blank,
            at:
                index
        )

        columnViewsByPage.insert(
            [],
            at:
                index
        )

        pageContainerIndices.insert(
            [],
            at:
                index
        )

        let range =
            NSRange(
                location:
                    character,
                length:
                    0
            )

        if index <= pageRanges.count {
            pageRanges.insert(
                range,
                at:
                    index
            )

        } else {
            throw WriterError.message(
                "Physical-page ranges became unsynchronized."
            )
        }

        addSubview(
            blank
        )

        renumberPhysicalPages(
            from:
                index + 1
        )
    }

    private func removeSyntheticBlankPage(
        at index: Int
    ) {
        guard
            pages.indices
                .contains(
                    index
                ),
            pageContainerIndices
                .indices
                .contains(
                    index
                ),
            pageContainerIndices[
                index
            ]
            .isEmpty
        else {
            return
        }

        let view =
            pages.remove(
                at:
                    index
            )

        view.removeFromSuperview()

        if columnViewsByPage.indices
            .contains(
                index
            ) {

            for columnView
                in columnViewsByPage.remove(
                    at:
                        index
                ) {

                columnView.removeFromSuperview()
            }
        }

        pageContainerIndices.remove(
            at:
                index
        )

        if pageRanges.indices
            .contains(
                index
            ) {

            pageRanges.remove(
                at:
                    index
            )
        }

        renumberPhysicalPages(
            from:
                index
        )
    }

    private func trimPages(
        to count: Int
    ) {
        let target =
            max(
                1,
                count
            )

        guard
            pages.count > target
        else {
            return
        }

        let removedPages =
            Array(
                pages.dropFirst(
                    target
                )
            )

        let removedColumnViews =
            columnViewsByPage
                .dropFirst(
                    target
                )
                .flatMap {
                    $0
                }

        let activeView =
            window?.firstResponder
                as? WritingTextView

        let activeWasRemoved =
            activeView.map {
                active in

                removedPages.contains(
                    where: {
                        $0 === active
                    }
                )
                || removedColumnViews.contains(
                    where: {
                        $0 === active
                    }
                )
            } ?? false

        let activeSelection =
            activeWasRemoved
                ? activeView?
                    .selectedRange()
                : nil

        while pages.count > target {
            let physicalIndex =
                pages.count - 1

            let view =
                pages.removeLast()

            view.removeFromSuperview()

            if physicalIndex
                < columnViewsByPage.count {

                for columnView
                    in columnViewsByPage
                        .removeLast() {

                    columnView.removeFromSuperview()
                }
            }

            let containerIndices:
                [Int] =
                    physicalIndex
                        < pageContainerIndices
                            .count
                    ? pageContainerIndices
                        .removeLast()
                    : []

            for containerIndex
                in containerIndices
                    .sorted(
                        by: >
                    ) {

                guard
                    containerIndex >= 0,
                    containerIndex
                        < flow.manager
                            .textContainers
                            .count
                else {
                    continue
                }

                flow.manager
                    .removeTextContainer(
                        at:
                            containerIndex
                    )

                for mappingIndex
                    in pageContainerIndices
                        .indices {

                    pageContainerIndices[
                        mappingIndex
                    ] =
                        pageContainerIndices[
                            mappingIndex
                        ]
                        .map {
                            existing in

                            existing
                                > containerIndex
                                ? existing - 1
                                : existing
                        }
                }
            }

            if physicalIndex
                < pageRanges.count {

                pageRanges.remove(
                    at:
                        physicalIndex
                )
            }
        }

        guard
            activeWasRemoved,
            let activeSelection
        else {
            return
        }

        let location =
            min(
                activeSelection.location,
                flow.storage.length
            )

        let length =
            min(
                activeSelection.length,
                flow.storage.length
                    - location
            )

        let safeSelection =
            NSRange(
                location:
                    location,
                length:
                    length
            )

        let destination =
            pageView(
                containing:
                    safeSelection.location
            )

        destination.setSelectedRange(
            safeSelection
        )

        window?.makeFirstResponder(
            destination
        )

        onActiveViewRehomed?(
            destination,
            safeSelection
        )
    }

    private func textWasEdited() {
        guard
            printLayout
        else {
            scheduleContinuousHeight()
            return
        }

        let point =
            flow.storage
                .editedRange
                .location

        let index =
            pageRanges
                .indices
                .first {
                    index in

                    guard
                        !isSyntheticBlankPage(
                            index
                        )
                    else {
                        return false
                    }

                    return NSMaxRange(
                        pageRanges[
                            index
                        ]
                    ) >= point
                }
            ?? pageContainerIndices
                .indices
                .reversed()
                .first {
                    !pageContainerIndices[
                        $0
                    ]
                    .isEmpty
                }
            ?? 0

        invalidate(
            from:
                max(
                    0,
                    index - 1
                )
        )
    }

    private func invalidate(from index: Int) {
        resolvedAnchorSnapshots = resolvedAnchorSnapshots.filter { $0.value.pageIndex < index }
        flow.resetParagraphKeepBreaks()
        footnotesNeedRefresh = true
        pendingPage = layoutComplete ? index : min(index, pendingPage)
        layoutComplete = false
        lastLayoutError = nil
        schedule()
    }

    private func schedule() {
        guard !scheduled else { return }
        scheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.scheduled = false
            if self.printLayout { self.paginateBatch() }
            else { self.arrange() }
        }
    }

    private func scheduleContinuousHeight() { schedule() }

    /// A main-run-loop slice, bounded by both page count and elapsed layout time.
    /// Layout inside a single pathological paragraph remains an AppKit operation.
    func paginateBatch(
        maxPages: Int = 8
    ) {
        guard
            printLayout,
            !layoutComplete,
            !isPaginating,
            geometry != nil
        else {
            return
        }

        isPaginating =
            true

        defer {
            isPaginating =
                false
        }

        let start =
            ProcessInfo
                .processInfo
                .systemUptime

        lastBatchPageCount =
            0

        // Initial pagination appends pages, so only the appended range needs
        // inspection. During reflow, existing later containers may be stale;
        // retain the original full rebuild semantics until that suffix has
        // been recomputed.
#if DEBUG
        let isAppendingPages = !forceFullRangeRebuildForTesting
            && pendingPage >= pageRanges.count
#else
        let isAppendingPages = pendingPage >= pageRanges.count
#endif
        let rangeRebuildStartPage = isAppendingPages
            ? min(pendingPage, pageRanges.count)
            : 0

        do {
            if footnotesNeedRefresh {
                cachedFootnotes = try Footnotes.records(in: flow.storage)
                footnotesNeedRefresh = false
            }
            while !layoutComplete
                && lastBatchPageCount
                    < maxPages {

                guard
                    pendingPage < 20_000
                else {
                    throw WriterError.message(
                        "This layout exceeds 20,000 pages. Continuous mode remains available."
                    )
                }

                let startCharacter =
                    pageStartCharacter(
                        for:
                            pendingPage
                    )

                let currentSection =
                    section(
                        forCharacter:
                            startCharacter
                    )

                let startsSection =
                    currentSection.location
                        > 0
                    && startCharacter
                        == currentSection.location

                let upcomingPhysicalPage =
                    pendingPage + 1

                if startsSection,
                   requiresParityBlank(
                    for:
                        currentSection,
                    physicalPage:
                        upcomingPhysicalPage
                   ) {

                    let previousCharacter =
                        max(
                            0,
                            startCharacter - 1
                        )

                    let blankGeometry =
                        try pageGeometry(
                            forCharacter:
                                previousCharacter
                        )
                        .resolvingPhysicalPage(
                            pendingPage + 1
                        )

                    let blankSectionPageNumber =
                        pendingPage > 0
                        && pages.indices
                            .contains(
                                pendingPage - 1
                            )
                        ? pages[
                            pendingPage - 1
                        ]
                        .sectionPageNumber
                            + 1
                        : 1

                    try ensureSyntheticBlankPage(
                        at:
                            pendingPage,
                        character:
                            startCharacter,
                        geometry:
                            blankGeometry,
                        sectionPageNumber:
                            blankSectionPageNumber
                    )

                    // A parity-only sheet has no manuscript or note drawing,
                    // but a long note's remaining text must reach the next
                    // manuscript page just as it does in PDF export.
                    if pendingPage > 0 {
                        pages[pendingPage].pageFootnotes.outgoing =
                            pages[pendingPage - 1].pageFootnotes.outgoing
                    }

                    pendingPage += 1
                    lastBatchPageCount += 1

                    if ProcessInfo
                        .processInfo
                        .systemUptime
                        - start
                        >= 0.012 {

                        break
                    }

                    continue
                }

                if pendingPage
                    < pageContainerIndices
                        .count,
                   isSyntheticBlankPage(
                    pendingPage
                   ) {

                    removeSyntheticBlankPage(
                        at:
                            pendingPage
                    )
                }

                let currentGeometry =
                    try pageGeometry(
                        forCharacter:
                            startCharacter
                    )
                    .resolvingPhysicalPage(
                        pendingPage + 1
                    )

                let currentSectionPageNumber =
                    sectionPageNumber(
                        forPage:
                            pendingPage,
                        startCharacter:
                            startCharacter
                    )

                if pendingPage
                    >= pages.count {

                    addPage(
                        geometry:
                            currentGeometry,
                        sectionPageNumber:
                            currentSectionPageNumber
                    )
                }

                try ensureContainerCount(
                    forPhysicalPage:
                        pendingPage,
                    geometry:
                        currentGeometry
                )

                guard
                    pendingPage
                        < pageContainerIndices
                            .count
                else {
                    throw WriterError.message(
                        "The physical page and TextKit container maps became unsynchronized."
                    )
                }

                let mappedContainerIndices =
                    containerIndices(
                        forPhysicalPage:
                            pendingPage
                    )

                guard
                    !mappedContainerIndices
                        .isEmpty
                else {
                    throw WriterError.message(
                        "A manuscript page has no TextKit containers."
                    )
                }

                configurePage(
                    pages[
                        pendingPage
                    ],
                    index:
                        pendingPage,
                    geometry:
                        currentGeometry,
                    sectionPageNumber:
                        currentSectionPageNumber
                )

                let incomingFootnotes = pendingPage > 0
                    ? pages[pendingPage - 1].pageFootnotes.outgoing : []
                var reservedFootnoteHeight: CGFloat = 0
                var pageFootnotes = PageFootnotePlan()
                var physicalRange = NSRange(location: startCharacter, length: 0)
                var finishedPage = false
                var converged = false
                var activePageImages = initialPageImages(pendingPage)
                var seenAnchorStates = Set<String>()

                for iteration in 0..<32 {
                    var combinedCharacters: NSRange?
                    finishedPage = false
                    let activeContainerIndices = containerIndices(forPhysicalPage: pendingPage)
                    let targetHeight = currentGeometry.contentSize.height - reservedFootnoteHeight
                    let primary = pages[pendingPage]
                    primary.reservedFootnoteHeight = reservedFootnoteHeight
                    primary.writingContentSizeOverride = NSSize(
                        width: activeContainerIndices.count > 1 ? currentGeometry.columnWidth : currentGeometry.contentSize.width,
                        height: targetHeight
                    )
                    if pendingPage < columnViewsByPage.count {
                        for columnView in columnViewsByPage[pendingPage] {
                            columnView.writingContentSizeOverride = NSSize(width: currentGeometry.columnWidth,
                                                                           height: targetHeight)
                        }
                    }

                for (
                    columnOffset,
                    containerIndex
                ) in activeContainerIndices
                    .enumerated() {

                    guard
                        containerIndex >= 0,
                        containerIndex
                            < flow.manager
                                .textContainers
                                .count
                    else {
                        throw WriterError.message(
                            "The physical page contains an invalid TextKit container."
                        )
                    }

                    let container =
                        flow.manager
                            .textContainers[
                                containerIndex
                            ]

                    container.exclusionPaths = FloatingImageLayout.exclusionPaths(
                        images: activePageImages,
                        pageIndex: pendingPage,
                        geometry: currentGeometry,
                        columnIndex: columnOffset,
                        font: FloatingImageLayout.representativeFont(in: flow.storage, at: startCharacter)
                    )

                    let targetSize =
                        activeContainerIndices
                            .count > 1
                        ? NSSize(
                            width:
                                currentGeometry
                                    .columnWidth,
                            height:
                                currentGeometry
                                    .contentSize
                                    .height - reservedFootnoteHeight
                        )
                        : NSSize(width: currentGeometry.contentSize.width,
                                 height: targetHeight)

                    if container.containerSize
                        != targetSize {

                        container.containerSize =
                            targetSize
                    }

                    let column =
                        try flow.layout(
                            container,
                            geometry:
                                currentGeometry
                        )

                    if let existing =
                        combinedCharacters {

                        let start =
                            min(
                                existing.location,
                                column
                                    .characters
                                    .location
                            )

                        let end =
                            max(
                                NSMaxRange(
                                    existing
                                ),
                                NSMaxRange(
                                    column
                                        .characters
                                )
                            )

                        combinedCharacters =
                            NSRange(
                                location:
                                    start,
                                length:
                                    max(
                                        0,
                                        end - start
                                    )
                            )

                    } else {
                        combinedCharacters =
                            column.characters
                    }

                    if columnOffset
                        < activeContainerIndices.count - 1,
                       flow.pageBreakBeforeBoundary(
                        near:
                            NSMaxRange(
                                column.characters
                            )
                       ) != nil {

                        try discardRemainingColumns(
                            onPhysicalPage:
                                pendingPage,
                            after:
                                columnOffset
                        )

                        break
                    }

                    if column.finished {
                        finishedPage =
                            true
                        break
                    }
                }

                physicalRange =
                    combinedCharacters
                    ?? NSRange(
                        location:
                            startCharacter,
                        length:
                            0
                    )

                if pageRanges.indices.contains(pendingPage) {
                    pageRanges[pendingPage] = physicalRange
                } else if pendingPage == pageRanges.count {
                    pageRanges.append(physicalRange)
                }
                let dynamicCandidateImages = resolvedFloatingImages(forPhysicalPage: pendingPage,
                                                                    applyingSnapshots: false)
                for image in dynamicCandidateImages where image.anchor == .paragraph || image.anchor == .character {
                    if image.anchorOffsetX != nil, image.anchorOffsetY != nil,
                       resolvedAnchorSnapshots[image.id] == nil {
                        resolvedAnchorSnapshots[image.id] = image
                    }
                }
                let candidateImages = FloatingImageLayout.applyingAnchorSnapshots(
                    dynamicCandidateImages,
                    snapshots: resolvedAnchorSnapshots,
                    pageIndex: pendingPage
                )
                let imagesChanged = !sameResolvedFloatingImageLayout(activePageImages, candidateImages)
                let signature = candidateImages
                        .filter { $0.anchor == .paragraph || $0.anchor == .character }
                        .sorted { $0.id.uuidString < $1.id.uuidString }
                        .map { "\($0.id.uuidString):\(Int(($0.x * 10).rounded())):\(Int(($0.y * 10).rounded()))" }
                        .joined(separator: "|")
                #if DEBUG
                let decision = imagesChanged ? (seenAnchorStates.contains(signature) ? "repeated" : "changed") : "stable"
                traceAnchorPagination(iteration: iteration, pageIndex: pendingPage, pageRange: physicalRange,
                                      active: activePageImages, candidate: candidateImages,
                                      decision: decision, geometry: currentGeometry)
                #endif
                if imagesChanged {
                    guard seenAnchorStates.insert(signature).inserted else {
                        throw WriterError.message("Text-anchored image wrapping oscillated on page \(pendingPage + 1). Pagination stopped before publishing an unstable layout.")
                    }
                    activePageImages = candidateImages
                    continue
                }
                activePageImages = candidateImages

                pageFootnotes = try PageFootnotes.plan(
                    geometry: currentGeometry,
                    references: PageFootnotes.notes(on: physicalRange, from: cachedFootnotes),
                    incoming: incomingFootnotes
                )
                if pageFootnotes.reservedHeight <= reservedFootnoteHeight + 0.5 {
                    converged = true
                    break
                }
                reservedFootnoteHeight = pageFootnotes.reservedHeight
                }
                guard converged else {
                    throw WriterError.message("Footnote pagination did not converge within 32 passes.")
                }
                pages[pendingPage].reservedFootnoteHeight = reservedFootnoteHeight
                pages[pendingPage].pageFootnotes = pageFootnotes

                let terminalBalanceContainers =
                    containerIndices(
                        forPhysicalPage:
                            pendingPage
                    )

                try applyTerminalColumnBalancing(
                    pageIndex:
                        pendingPage,
                    startCharacter:
                        startCharacter,
                    currentSection:
                        currentSection,
                    geometry:
                        currentGeometry,
                    containerIndices:
                        terminalBalanceContainers,
                    physicalRange:
                        &physicalRange,
                    finishedPage:
                        &finishedPage,
                    reservedFootnoteHeight:
                        reservedFootnoteHeight,
                    hasIncomingFootnotes:
                        !incomingFootnotes.isEmpty,
                    hasOutgoingFootnotes:
                        !pageFootnotes.outgoing.isEmpty
                )

                let justificationContainers =
                    containerIndices(
                        forPhysicalPage:
                            pendingPage
                    )

                if !justificationContainers.isEmpty,
                   reservedFootnoteHeight <= 0.5,
                   incomingFootnotes.isEmpty,
                   pageFootnotes.outgoing.isEmpty,
                   !flow.hasStructuralBreak(
                        atEndOf:
                            physicalRange
                   ) {

                    for containerIndex
                        in justificationContainers {

                        guard
                            containerIndex >= 0,
                            containerIndex
                                < flow.manager
                                    .textContainers
                                    .count
                        else {
                            throw WriterError.message(
                                "A vertically justified column references an invalid TextKit container."
                            )
                        }

                        let container =
                            flow.manager
                                .textContainers[
                                    containerIndex
                                ]

                        _ =
                            flow.applyVerticalJustification(
                                in:
                                    container,
                                geometry:
                                    currentGeometry,
                                availableHeight:
                                    min(
                                        currentGeometry
                                            .contentSize
                                            .height,
                                        container
                                            .containerSize
                                            .height
                                    ),
                                isEligiblePage:
                                    true
                            )
                    }
                }

                if pendingPage
                    < pageRanges.count {

                    pageRanges[
                        pendingPage
                    ] =
                        physicalRange

                } else if pendingPage
                    == pageRanges.count {

                    pageRanges.append(
                        physicalRange
                    )

                } else {
                    throw WriterError.message(
                        "Physical-page ranges became unsynchronized."
                    )
                }

                pendingPage += 1
                lastBatchPageCount += 1

                if finishedPage && pageFootnotes.outgoing.isEmpty {
                    layoutComplete =
                        true

                    trimPages(
                        to:
                            pendingPage
                    )
                }

                if ProcessInfo
                    .processInfo
                    .systemUptime
                    - start
                    >= 0.012 {

                    break
                }
            }

            let laidOutThrough =
                rebuildPhysicalPageRangesFromTextKit(
                    startingAt: rangeRebuildStartPage,
                    through: isAppendingPages ? pendingPage : nil
                )

            if layoutComplete
                && laidOutThrough < flow.storage.length {

                layoutComplete =
                    false

                pendingPage =
                    pages.count
            }

            arrange()

            if layoutComplete {
                reconcileActiveViewWithSelection()
            }

            if !layoutComplete {
                schedule()
            }

        } catch {
            fail(
                error.localizedDescription
            )
        }
    }

    private func reconcileActiveViewWithSelection() {
        guard
            printLayout,
            layoutComplete,
            let activeView =
                window?.firstResponder
                    as? WritingTextView,
            (
                pages.contains(
                    where: {
                        $0 === activeView
                    }
                )
                || columnViewsByPage.contains(
                    where: {
                        views in

                        views.contains(
                            where: {
                                $0 === activeView
                            }
                        )
                    }
                )
            )
        else {
            return
        }

        let activeSelection =
            activeView.selectedRange()

        let location =
            min(
                max(
                    0,
                    activeSelection.location
                ),
                flow.storage.length
            )

        let length =
            min(
                activeSelection.length,
                flow.storage.length
                    - location
            )

        let safeSelection =
            NSRange(
                location: location,
                length: length
            )

        let destination =
            pageView(
                containing:
                    safeSelection.location
            )

        if destination !== activeView {
            destination.setSelectedRange(
                safeSelection
            )

            window?.makeFirstResponder(
                destination
            )
        }

        // The first responder may already be the correct physical
        // page while EditorController is still attached to the view
        // that initiated an undo/redo snapshot restoration. Always
        // synchronize controller ownership after pagination settles,
        // even when AppKit focus itself does not need to move.
        onActiveViewRehomed?(
            destination,
            safeSelection
        )
    }

    /// Used by export comparison tests and explicit distant navigation, never on
    /// the ordinary typing path. Each iteration reuses the existing containers.
    func finishPagination() {
        while printLayout && !layoutComplete && lastLayoutError == nil {
            paginateBatch(maxPages: 32)
        }

        var laidOutThrough =
            rebuildPhysicalPageRangesFromTextKit()

        while printLayout
            && laidOutThrough < flow.storage.length
            && lastLayoutError == nil {

            layoutComplete =
                false

            pendingPage =
                pages.count

            paginateBatch(
                maxPages:
                    32
            )

            laidOutThrough =
                rebuildPhysicalPageRangesFromTextKit()
        }

        arrange()
        reconcileActiveViewWithSelection()
    }

    func fail(_ message: String) {
        lastLayoutError = message
        printLayout = false; flow.paginated = false; layoutComplete = true
        trimPages(to: 1); pageRanges = []
        configurePage(firstView, index: 0)
        arrange()
        onLayoutFailure?(message)
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        // Page dimensions are physical points, never autoresized to the viewport.
    }

    func viewportChanged(width: CGFloat) {
        viewportWidth = max(1, width)
        arrange()
    }

    private func pageVerticalBodyOffset(
        pageIndex: Int,
        geometry: PageGeometry,
        reservedFootnoteHeight: CGFloat
    ) -> CGFloat {
        guard
            pageContainerIndices.indices.contains(
                pageIndex
            )
        else {
            return 0
        }

        let usedHeight =
            pageContainerIndices[
                pageIndex
            ]
            .compactMap {
                containerIndex
                -> CGFloat? in

                guard
                    flow.manager
                        .textContainers
                        .indices
                        .contains(
                            containerIndex
                        )
                else {
                    return nil
                }

                return flow.manager
                    .usedRect(
                        for:
                            flow.manager
                                .textContainers[
                                    containerIndex
                                ]
                    )
                    .height
            }
            .max()
            ?? 0

        return geometry
            .verticalBodyOffset(
                usedHeight:
                    usedHeight,
                availableHeight:
                    max(
                        0,
                        geometry
                            .contentSize
                            .height
                            - reservedFootnoteHeight
                    )
            )
    }

    private func arrange() {
        guard !isArranging else { return }
        isArranging = true
        defer { isArranging = false }
        if printLayout,
           let geometry {

            let sizes =
                pages.map {
                    $0.pageGeometry?
                        .size
                        ?? geometry.size
                }

            let widestPage =
                sizes.map(
                    \.width
                )
                .max()
                ?? geometry
                    .size
                    .width

            let pageHeight =
                sizes.reduce(
                    CGFloat.zero
                ) {
                    partial,
                    size in

                    partial
                        + size.height
                }

            let gapHeight =
                CGFloat(
                    max(
                        0,
                        pages.count - 1
                    )
                )
                * gap

            let contentHeight =
                edge * 2
                + pageHeight
                + gapHeight

            let width =
                max(
                    viewportWidth,
                    (
                        widestPage
                        + edge * 2
                    )
                    * zoom
                )

            let height =
                contentHeight
                    * zoom

            setFrameSize(
                NSSize(
                    width:
                        width,
                    height:
                        height
                )
            )

            setBoundsSize(
                NSSize(
                    width:
                        width / zoom,
                    height:
                        height / zoom
                )
            )

            var y =
                edge

            for (
                index,
                view
            ) in pages.enumerated() {

                let size =
                    sizes[
                        index
                    ]

                let x =
                    (
                        bounds.width
                        - size.width
                    )
                    / 2

                let frame =
                    NSRect(
                        x:
                            x,
                        y:
                            y,
                        width:
                            size.width,
                        height:
                            size.height
                    )

                if view.frame
                    != frame {

                    view.frame =
                        frame
                }

                if view.bounds.size
                    != size {

                    view.setBoundsSize(
                        size
                    )
                }

                if index
                    < columnViewsByPage.count,
                   let pageGeometry =
                    view.pageGeometry,
                   !columnViewsByPage[
                    index
                   ]
                   .isEmpty {

                    view.writingContentSizeOverride =
                        NSSize(
                            width:
                                pageGeometry
                                    .columnWidth,
                            height:
                                writingColumnHeight(
                                    for:
                                        view,
                                    geometry:
                                        pageGeometry,
                                    reservedFootnoteHeight:
                                        view.reservedFootnoteHeight
                                )
                        )

                    view.writingOriginOverride =
                        NSPoint(
                            x:
                                pageGeometry
                                    .columnOriginX(
                                        for:
                                            0
                                    ),
                            y:
                                pageGeometry
                                    .contentOrigin
                                    .y
                                    + pageVerticalBodyOffset(
                                        pageIndex:
                                            index,
                                        geometry:
                                            pageGeometry,
                                        reservedFootnoteHeight:
                                            view.reservedFootnoteHeight
                                    )
                        )

                    for (
                        columnOffset,
                        columnView
                    ) in columnViewsByPage[
                        index
                    ]
                    .enumerated() {

                        let columnIndex =
                            columnOffset + 1

                        columnView.pageGeometry =
                            pageGeometry

                        columnView.pageNumber =
                            view.pageNumber

                        columnView.sectionPageNumber =
                            view.sectionPageNumber

                        columnView.displayPageNumber =
                            view.displayPageNumber

                        columnView.writingContentSizeOverride =
                            NSSize(
                                width:
                                    pageGeometry
                                        .columnWidth,
                                height:
                                    writingColumnHeight(
                                        for:
                                            columnView,
                                        geometry:
                                            pageGeometry,
                                        reservedFootnoteHeight:
                                            view.reservedFootnoteHeight
                                    )
                            )

                        columnView.writingOriginOverride =
                            NSPoint(
                                x:
                                    pageGeometry
                                        .columnOriginX(
                                            for:
                                                columnIndex
                                        ),
                                y:
                                    pageGeometry
                                        .contentOrigin
                                        .y
                                        + pageVerticalBodyOffset(
                                            pageIndex:
                                                index,
                                            geometry:
                                                pageGeometry,
                                            reservedFootnoteHeight:
                                                view.reservedFootnoteHeight
                                        )
                            )

                        if columnView.frame
                            != frame {

                            columnView.frame =
                                frame
                        }

                        if columnView.bounds.size
                            != size {

                            columnView.setBoundsSize(
                                size
                            )
                        }

                        columnView.needsDisplay =
                            true
                    }

                } else {
                    view.writingContentSizeOverride =
                        view.pageGeometry.map {
                            NSSize(width: $0.contentSize.width,
                                   height: $0.contentSize.height - view.reservedFootnoteHeight)
                        }

                    view.writingOriginOverride =
                        nil
                }

                y +=
                    size.height
                    + gap
            }

        } else {
            let width = viewportWidth / zoom
            let minHeight = max(200, (enclosingScrollView?.contentSize.height ?? 600) / zoom)
            firstView.setFrameSize(NSSize(width: width, height: max(minHeight, firstView.frame.height)))
            firstView.setBoundsSize(firstView.frame.size)
            if let container = firstView.textContainer {
                // The scroll canvas must include the complete document. A
                // viewport-only usedRect left the remaining manuscript outside
                // its scrollable bounds and prevented outline navigation.
                flow.manager.ensureLayout(for: container)
                let height = max(minHeight, flow.manager.usedRect(for: container).height + 84)
                firstView.setFrameSize(NSSize(width: width, height: height))
                firstView.setBoundsSize(firstView.frame.size)
                setFrameSize(NSSize(width: viewportWidth, height: height * zoom))
                setBoundsSize(NSSize(width: width, height: height))
                firstView.setFrameOrigin(.zero)
            }
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        (printLayout ? NSColor.underPageBackgroundColor : NSColor.textBackgroundColor).setFill()
        dirtyRect.fill()
        guard printLayout else { return }
        for view in pages where view.frame.insetBy(dx: -8, dy: -8).intersects(dirtyRect) {
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
            shadow.shadowBlurRadius = 5; shadow.shadowOffset = NSSize(width: 0, height: 2); shadow.set()
            NSColor.white.setFill(); view.frame.fill()
            NSGraphicsContext.restoreGraphicsState()
            NSColor.gray.withAlphaComponent(0.35).setStroke()
            NSBezierPath(rect: view.frame.insetBy(dx: -0.5, dy: -0.5)).stroke()
        }
    }


    private func columnView(
        onPhysicalPage pageIndex: Int,
        containing character: Int
    ) -> WritingTextView? {
        guard
            pages.indices.contains(pageIndex),
            pageContainerIndices.indices.contains(pageIndex)
        else {
            return nil
        }

        let mapped =
            pageContainerIndices[
                pageIndex
            ]

        guard !mapped.isEmpty else {
            return nil
        }

        let candidateViews =
            [pages[pageIndex]]
            + (
                columnViewsByPage.indices.contains(
                    pageIndex
                )
                ? columnViewsByPage[
                    pageIndex
                ]
                : []
            )

        for (
            offset,
            containerIndex
        ) in mapped.enumerated() {

            guard
                offset < candidateViews.count,
                containerIndex >= 0,
                containerIndex
                    < flow.manager
                        .textContainers
                        .count
            else {
                continue
            }

            let container =
                flow.manager
                    .textContainers[
                        containerIndex
                    ]

            flow.manager.ensureLayout(
                for:
                    container
            )

            let glyphRange =
                flow.manager.glyphRange(
                    for:
                        container
                )

            let characterRange =
                flow.manager.characterRange(
                    forGlyphRange:
                        glyphRange,
                    actualGlyphRange:
                        nil
                )

            if characterRange.length == 0 {
                if character
                    == characterRange.location {

                    return candidateViews[
                        offset
                    ]
                }

                continue
            }

            if character
                >= characterRange.location
                && character
                    < NSMaxRange(
                        characterRange
                    ) {

                return candidateViews[
                    offset
                ]
            }
        }

        if character
            == flow.storage.length,
           let last =
            candidateViews.last {

            return last
        }

        return nil
    }

    func pageView(
        containing character: Int
    ) -> WritingTextView {
        let point =
            min(
                max(
                    0,
                    character
                ),
                flow.storage.length
            )

        if printLayout {
            while !layoutComplete
                && (
                    pageRanges.last.map {
                        NSMaxRange(
                            $0
                        ) <= point
                    } ?? true
                ) {

                paginateBatch(
                    maxPages:
                        8
                )
            }

            if let index =
                pageRanges
                    .indices
                    .first(
                        where: {
                            index in

                            guard
                                !isSyntheticBlankPage(
                                    index
                                )
                            else {
                                return false
                            }

                            let range =
                                pageRanges[
                                    index
                                ]

                            if range.length == 0 {
                                return point
                                    == range.location
                            }

                            return point
                                >= range.location
                                && point
                                    < NSMaxRange(
                                        range
                                    )
                        }
                    ),
               index < pages.count {
                if let columnView =
                    columnView(
                        onPhysicalPage:
                            index,
                        containing:
                            point
                    ) {

                    return columnView
                }

                return pages[
                    index
                ]
            }

            if point
                == flow.storage.length {

                if let index =
                    pageContainerIndices
                        .indices
                        .reversed()
                        .first(
                            where: {
                                !pageContainerIndices[
                                    $0
                                ]
                                .isEmpty
                            }
                        ),
                   index
                    < pages.count {

                    return pages[
                        index
                    ]
                }
            }
        }

        return firstView
    }

    /// Returns the page number assigned by the live print-layout engine.
    /// Continuous layout does not expose a reliable page number.
    func displayPageNumber(containing character: Int) -> Int? {
        guard printLayout else { return nil }
        return pageView(containing: character).displayPageNumber
    }

    func visibleCharacter() -> Int {
        guard printLayout else {
            return min(flow.storage.length, firstView.characterIndexForInsertion(at: NSPoint(x: 55, y: max(42, visibleRect.minY + 42))))
        }
        let visibleY =
            max(
                0,
                visibleRect.minY
            )

        let index =
            pages.firstIndex {
                $0.frame.maxY
                    >= visibleY
            }
            ?? max(
                0,
                pages.count - 1
            )

        return index
            < pageRanges.count
            ? pageRanges[index]
                .location
            : firstView
                .selectedRange()
                .location
    }

    @discardableResult
    func reveal(
        character: Int,
        focus: Bool
    ) -> WritingTextView {
        let point =
            min(
                max(0, character),
                flow.storage.length
            )

        if printLayout {
            while !layoutComplete
                && (
                    pageRanges.last.map {
                        NSMaxRange($0) <= point
                    } ?? true
                ) {
                paginateBatch(maxPages: 8)
            }
        }

        let view =
            pageView(
                containing: point
            )

        view.scrollRangeToVisible(
            NSRange(
                location: point,
                length: 0
            )
        )

        if focus {
            window?.makeFirstResponder(
                view
            )
        }

        return view
    }
}
