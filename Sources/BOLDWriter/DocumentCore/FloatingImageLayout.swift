import AppKit

/// TextKit exclusion geometry shared by the manuscript canvas and PDF
/// pagination. Coordinates here are local to one physical text column.
enum FloatingImageLayout {
    /// Text-anchored objects are positioned from the first layout that excludes
    /// their own wrap path. That makes the anchor marker independent of the
    /// object's self-induced reflow while preserving wraps from page/margin
    /// objects already present in that pass. Later wrapped passes keep this
    /// resolved anchor position instead of chasing the glyph around the image.
    static func applyingAnchorSnapshots(_ candidates: [FloatingImage],
                                        snapshots: [UUID: FloatingImage],
                                        pageIndex: Int) -> [FloatingImage] {
        var present = Set<UUID>()
        var result = candidates.map { candidate -> FloatingImage in
            present.insert(candidate.id)
            guard let snapshot = snapshots[candidate.id], snapshot.pageIndex == pageIndex else { return candidate }
            var stable = snapshot
            // Responsive axis alignment belongs to the current page geometry,
            // while the other text-relative axis may need the stable base-flow
            // snapshot to avoid chasing its own wrap exclusion.
            if candidate.horizontalAlignment != nil { stable.x = candidate.x }
            if candidate.verticalAlignment != nil { stable.y = candidate.y }
            return stable
        }
        for snapshot in snapshots.values where snapshot.pageIndex == pageIndex && !present.contains(snapshot.id) {
            result.append(snapshot)
        }
        return result
    }

    static func textAnchorLocation(anchor: FloatingImage.Anchor, location: Int, in text: String) -> Int {
        let nsText = text as NSString
        let boundedLocation = min(max(0, location), nsText.length)
        guard anchor == .paragraph, nsText.length > 0 else { return boundedLocation }
        // NSString.paragraphRange does not consistently treat a form-feed
        // page break as a paragraph boundary. Walk UTF-16 paragraph delimiters
        // directly so a paragraph immediately following a hard page break is
        // not rebound to the preceding physical page.
        var cursor = min(boundedLocation, nsText.length - 1)
        while cursor > 0 {
            let preceding = nsText.character(at: cursor - 1)
            if preceding == 0x000A || preceding == 0x000D || preceding == 0x000C
                || preceding == 0x2028 || preceding == 0x2029 {
                break
            }
            cursor -= 1
        }
        return cursor
    }

    /// Resolves stored text-relative offsets without changing the anchor's
    /// logical target. The returned record is a transient layout value.
    static func positionedAtAnchor(_ image: FloatingImage, pageIndex: Int, origin: CGPoint,
                                   pageContentOrigin: CGPoint = .zero,
                                   paragraphOrigin: CGPoint? = nil,
                                   pageGeometry: PageGeometry? = nil) -> FloatingImage {
        var resolved = image
        resolved.pageIndex = pageIndex
        if image.anchor == .paragraph || image.anchor == .character,
           let offsetX = image.anchorOffsetX, let offsetY = image.anchorOffsetY {
            switch image.horizontalPositionReference ?? .anchor {
            case .page: resolved.x = offsetX
            case .margins: resolved.x = Double(pageContentOrigin.x) + offsetX
            case .anchor: resolved.x = Double(origin.x) + offsetX
            case .paragraph, .line: resolved.x = Double((paragraphOrigin ?? origin).x) + offsetX
            case .character: resolved.x = Double(origin.x) + offsetX
            }
            switch image.verticalPositionReference ?? .anchor {
            case .page: resolved.y = offsetY
            case .margins: resolved.y = Double(pageContentOrigin.y) + offsetY
            case .anchor: resolved.y = Double(origin.y) + offsetY
            case .paragraph, .line: resolved.y = Double((paragraphOrigin ?? origin).y) + offsetY
            case .character: resolved.y = Double(origin.y) + offsetY
            }
        }
        if let pageGeometry {
            let physicalGeometry = pageGeometry.resolvingPhysicalPage(pageIndex + 1)
            if let alignment = image.horizontalAlignment {
                let frameOrigin: CGFloat
                let frameWidth: CGFloat
                switch image.horizontalPositionReference {
                case .margins:
                    frameOrigin = physicalGeometry.contentOrigin.x
                    frameWidth = physicalGeometry.contentSize.width
                case .page, .none:
                    frameOrigin = 0
                    frameWidth = physicalGeometry.size.width
                default:
                    frameOrigin = CGFloat(resolved.x)
                    frameWidth = 0
                }
                let pageX: CGFloat
                switch alignment {
                case .left: pageX = frameOrigin
                case .center: pageX = frameOrigin + (frameWidth - CGFloat(image.width)) / 2
                case .right: pageX = frameOrigin + frameWidth - CGFloat(image.width)
                }
                resolved.x = Double(image.anchor == .margins ? pageX - physicalGeometry.contentOrigin.x : pageX)
            }
            if let alignment = image.verticalAlignment {
                let frameOrigin: CGFloat
                let frameHeight: CGFloat
                switch image.verticalPositionReference {
                case .margins:
                    frameOrigin = physicalGeometry.contentOrigin.y
                    frameHeight = physicalGeometry.contentSize.height
                case .page, .none:
                    frameOrigin = 0
                    frameHeight = physicalGeometry.size.height
                default:
                    frameOrigin = CGFloat(resolved.y)
                    frameHeight = 0
                }
                let pageY: CGFloat
                switch alignment {
                case .top: pageY = frameOrigin
                case .center: pageY = frameOrigin + (frameHeight - CGFloat(image.height)) / 2
                case .bottom: pageY = frameOrigin + frameHeight - CGFloat(image.height)
                }
                resolved.y = Double(image.anchor == .margins ? pageY - physicalGeometry.contentOrigin.y : pageY)
            }
        }
        return resolved
    }

    /// Converts an absolute page coordinate into the storage convention for
    /// the image's logical anchor. Text anchors use offsets from their resolved
    /// glyph/paragraph origin; margin anchors store offsets from the margin box.
    static func storedAxisOffset(pageCoordinate: Double, anchor: FloatingImage.Anchor,
                                 anchorOrigin: CGPoint?, geometry: PageGeometry,
                                 horizontal: Bool) -> Double? {
        switch anchor {
        case .page:
            return pageCoordinate
        case .margins:
            let origin = horizontal ? geometry.contentOrigin.x : geometry.contentOrigin.y
            return pageCoordinate - Double(origin)
        case .paragraph, .character:
            guard let anchorOrigin else { return nil }
            return pageCoordinate - Double(horizontal ? anchorOrigin.x : anchorOrigin.y)
        }
    }

    static func exclusionPaths(images: [FloatingImage], pageIndex: Int,
                               geometry: PageGeometry, columnIndex: Int,
                               font: NSFont? = nil) -> [NSBezierPath] {
        let columnX = geometry.columnOriginX(for: columnIndex)
        let minimumTextWidth = minimumUsableTextWidth(font: font, columnWidth: geometry.columnWidth)
        return images
            .filter { $0.pageIndex == pageIndex && $0.wrapping != .none }
            .sorted { $0.zOrder < $1.zOrder }
            .flatMap { image -> [NSBezierPath] in
                let isMarginRelative = image.anchor == .margins
                let x = (isMarginRelative ? geometry.contentOrigin.x + CGFloat(image.x) : CGFloat(image.x)) - columnX
                let y = (isMarginRelative ? geometry.contentOrigin.y + CGFloat(image.y) : CGFloat(image.y)) - geometry.contentOrigin.y
                let base = CGRect(x: x, y: y, width: CGFloat(image.width), height: CGFloat(image.height))
                let rotated = rotatedRect(base, degrees: image.rotationDegrees)
                let distances = image.effectiveWrapDistances
                switch image.wrapping {
                case .none: return []
                case .square:
                    let rect = readableWrapRect(rotated, distances: distances,
                                                minimumTextWidth: minimumTextWidth,
                                                columnWidth: geometry.columnWidth,
                                                side: image.effectiveWrapSide)
                    return [NSBezierPath(rect: rect)]
                case .topAndBottom:
                    return [NSBezierPath(rect: CGRect(x: 0, y: rotated.minY - CGFloat(distances.top),
                                                      width: geometry.columnWidth,
                                                      height: rotated.height + CGFloat(distances.top + distances.bottom)))]
                case .tight, .through:
                    let lineHeight = max(1, font.map { $0.ascender - $0.descender + $0.leading } ?? 12)
                    if let polygon = image.wrapPolygon, polygon.isValid {
                        return polygonContour(polygon, image: image, origin: CGPoint(x: x, y: y),
                                              center: base.center, rotationDegrees: image.rotationDegrees,
                                              distances: distances, lineHeight: lineHeight,
                                              minimumTextWidth: minimumTextWidth,
                                              columnWidth: geometry.columnWidth,
                                              columnHeight: geometry.contentSize.height,
                                              side: image.effectiveWrapSide)
                    }
                    return alphaContour(image, origin: CGPoint(x: x, y: y), center: base.center,
                                        rotationDegrees: image.rotationDegrees, distances: distances,
                                        lineHeight: lineHeight, minimumTextWidth: minimumTextWidth,
                                        columnWidth: geometry.columnWidth,
                                        side: image.effectiveWrapSide)
                }
            }
    }

    /// The threshold is based on physical font metrics rather than view pixels.
    /// Eight wide lowercase glyphs is a conservative minimum line measure: a
    /// narrower lane encourages TextKit to break ordinary words into fragments.
    /// Cap the threshold so a single image cannot demand more than 45% of a
    /// column and make normal side wrapping impossible on book-size pages.
    static func minimumUsableTextWidth(font: NSFont?, columnWidth: CGFloat) -> CGFloat {
        let font = font ?? NSFont.systemFont(ofSize: 12)
        let wideWordWidth = ("mmmmmmmm" as NSString).size(withAttributes: [.font: font]).width
        return min(max(font.pointSize * 5, wideWordWidth), max(0, columnWidth * 0.45))
    }

    static func representativeFont(in text: NSAttributedString, at location: Int) -> NSFont? {
        guard text.length > 0 else { return nil }
        return text.attribute(.font, at: min(max(0, location), text.length - 1), effectiveRange: nil) as? NSFont
    }

    private static func readableWrapRect(_ imageRect: CGRect, distances: FloatingImage.WrapDistances,
                                         minimumTextWidth: CGFloat,
                                         columnWidth: CGFloat,
                                         side: FloatingImage.WrapSide) -> CGRect {
        let imageMinX = imageRect.minX - CGFloat(distances.left)
        let imageMaxX = imageRect.maxX + CGFloat(distances.right)
        let minY = imageRect.minY - CGFloat(distances.top)
        let maxY = imageRect.maxY + CGFloat(distances.bottom)
        let leftWidth = max(0, min(columnWidth, imageMinX))
        let rightWidth = max(0, columnWidth - max(0, imageMaxX))
        let leftUsable = leftWidth >= minimumTextWidth
        let rightUsable = rightWidth >= minimumTextWidth
        let (keepLeft, keepRight): (Bool, Bool)
        switch side {
        case .both:
            (keepLeft, keepRight) = (leftUsable, rightUsable)
        case .leftOnly:
            (keepLeft, keepRight) = (leftUsable, false)
        case .rightOnly:
            (keepLeft, keepRight) = (false, rightUsable)
        case .largestSide:
            if leftUsable && leftWidth >= rightWidth { (keepLeft, keepRight) = (true, false) }
            else if rightUsable { (keepLeft, keepRight) = (false, true) }
            else { (keepLeft, keepRight) = (false, false) }
        case .automatic:
            if leftUsable && rightUsable { (keepLeft, keepRight) = (true, true) }
            else { (keepLeft, keepRight) = (leftUsable, rightUsable) }
        }
        var minX = keepLeft ? imageMinX : 0
        var maxX = keepRight ? imageMaxX : columnWidth
        if !keepLeft && !keepRight { minX = 0; maxX = columnWidth }
        minX = max(0, min(columnWidth, minX))
        maxX = max(minX, min(columnWidth, maxX))
        return CGRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
    }

    /// Builds Tight Wrap exclusions from the rotated alpha contour. Minimum
    /// readable width is evaluated after rotation, and each exclusion band is
    /// at least two font line heights tall. This keeps a narrow sliver produced
    /// by a rotated contour from admitting isolated glyphs between otherwise
    /// usable text lanes. The bands still follow the silhouette vertically;
    /// they are not a rectangular Square Wrap fallback.
    /// Follow an imported Word edited outline in the native editor and PDF
    /// layout. Each line-height slab conservatively covers every polygon edge
    /// crossing it, including concave and rotated outlines; readable-lane
    /// policy remains shared with the alpha-derived contour.
    private static func polygonContour(_ polygon: FloatingImage.WrapPolygon, image: FloatingImage,
                                       origin: CGPoint, center: CGPoint, rotationDegrees: Double,
                                       distances: FloatingImage.WrapDistances, lineHeight: CGFloat,
                                       minimumTextWidth: CGFloat, columnWidth: CGFloat, columnHeight: CGFloat,
                                       side: FloatingImage.WrapSide) -> [NSBezierPath] {
        let radians = rotationDegrees * .pi / 180
        let cosine = CGFloat(cos(radians)), sine = CGFloat(sin(radians))
        let scale = CGFloat(FloatingImage.WrapPolygon.space)
        let points = polygon.points.map { point -> CGPoint in
            let x = origin.x + CGFloat(point.x) * CGFloat(image.width) / scale
            let y = origin.y + CGFloat(point.y) * CGFloat(image.height) / scale
            let dx = x - center.x, dy = y - center.y
            return CGPoint(x: center.x + dx * cosine - dy * sine,
                           y: center.y + dx * sine + dy * cosine)
        }
        guard let minimumY = points.map(\.y).min(), let maximumY = points.map(\.y).max(),
              maximumY > minimumY else { return [] }
        let step = max(1, lineHeight)
        let bandHeight = step * 2
        // TextKit never lays text thousands of points beyond this page. Word
        // permits points four image widths outside the frame, so clip scan
        // bands to the actual text column before visiting every polygon edge.
        var y = max(-bandHeight, floor((minimumY - CGFloat(distances.top)) / step) * step)
        let endY = min(columnHeight + bandHeight, maximumY + CGFloat(distances.bottom))
        var paths: [NSBezierPath] = []
        while y < endY {
            let queryMin = y - CGFloat(distances.bottom)
            let queryMax = y + bandHeight + CGFloat(distances.top)
            var xs: [CGFloat] = []
            for index in points.indices {
                let first = points[index], last = points[(index + 1) % points.count]
                let low = min(first.y, last.y), high = max(first.y, last.y)
                guard low <= queryMax && high >= queryMin else { continue }
                if abs(last.y - first.y) < 0.000001 {
                    xs.append(first.x); xs.append(last.x)
                } else {
                    let clippedLow = max(low, queryMin), clippedHigh = min(high, queryMax)
                    for crossing in [clippedLow, clippedHigh] {
                        let ratio = (crossing - first.y) / (last.y - first.y)
                        xs.append(first.x + ratio * (last.x - first.x))
                    }
                }
            }
            if let left = xs.min(), let right = xs.max() {
                let span = CGRect(x: left - CGFloat(distances.left), y: y,
                                  width: right - left + CGFloat(distances.left + distances.right),
                                  height: bandHeight)
                let exclusion = readableWrapRect(span, distances: .uniform(0),
                                                 minimumTextWidth: minimumTextWidth,
                                                 columnWidth: columnWidth, side: side)
                if exclusion.width > 0 {
                    if let previous = paths.last, abs(previous.bounds.minX - exclusion.minX) < 0.01,
                       abs(previous.bounds.maxX - exclusion.maxX) < 0.01,
                       previous.bounds.maxY >= exclusion.minY - 0.01 {
                        paths[paths.count - 1] = NSBezierPath(rect: previous.bounds.union(exclusion))
                    } else {
                        paths.append(NSBezierPath(rect: exclusion))
                    }
                }
            }
            y += step
        }
        return paths
    }

    private static func alphaContour(_ image: FloatingImage, origin: CGPoint, center: CGPoint,
                                    rotationDegrees: Double, distances: FloatingImage.WrapDistances, lineHeight: CGFloat,
                                    minimumTextWidth: CGFloat, columnWidth: CGFloat,
                                    side: FloatingImage.WrapSide) -> [NSBezierPath] {
        guard let source = image.displayImage(),
              let cgImage = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return [NSBezierPath(rect: CGRect(origin: origin, size: CGSize(width: CGFloat(image.width), height: CGFloat(image.height))))]
        }
        guard let providerData = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(providerData) else {
            let rect = rotatedRect(CGRect(origin: origin,
                                          size: CGSize(width: CGFloat(image.width), height: CGFloat(image.height))),
                                   degrees: rotationDegrees)
            return [NSBezierPath(rect: readableWrapRect(expanded(rect, by: distances), distances: .uniform(0), minimumTextWidth: minimumTextWidth,
                                                        columnWidth: columnWidth, side: side))]
        }
        let bytesPerPixel = max(1, cgImage.bitsPerPixel / 8)
        let alphaIndex: Int?
        switch cgImage.alphaInfo {
        case .alphaOnly: alphaIndex = 0
        case .first, .premultipliedFirst: alphaIndex = 0
        case .last, .premultipliedLast: alphaIndex = bytesPerPixel - 1
        case .none, .noneSkipFirst, .noneSkipLast: alphaIndex = nil
        @unknown default: alphaIndex = nil
        }
        let sampleWidth = min(512, max(1, cgImage.width))
        let sampleHeight = min(512, max(1, cgImage.height))
        let cellWidth = CGFloat(image.width) / CGFloat(sampleWidth)
        let cellHeight = CGFloat(image.height) / CGFloat(sampleHeight)
        var rotatedRuns: [CGRect] = []
        for row in 0..<sampleHeight {
            var start: Int?
            for column in 0...sampleWidth {
                let opaque: Bool
                if column < sampleWidth, let alphaIndex {
                    let pixelX = min(cgImage.width - 1, column * cgImage.width / sampleWidth)
                    let pixelY = min(cgImage.height - 1, row * cgImage.height / sampleHeight)
                    let offset = pixelY * cgImage.bytesPerRow + pixelX * bytesPerPixel + alphaIndex
                    opaque = bytes[offset] > 20
                } else { opaque = column < sampleWidth }
                if opaque, start == nil { start = column }
                if !opaque, let first = start {
                    let sourceRect = CGRect(x: origin.x + CGFloat(first) * cellWidth,
                                            y: origin.y + CGFloat(row) * cellHeight,
                                            width: CGFloat(column - first) * cellWidth,
                                            height: cellHeight)
                    let transformed = rotatedPath(NSBezierPath(rect: sourceRect), center: center,
                                                  degrees: rotationDegrees).bounds
                    rotatedRuns.append(expanded(transformed, by: distances))
                    start = nil
                }
            }
        }
        guard !rotatedRuns.isEmpty else {
            let rect = rotatedRect(CGRect(origin: origin,
                                          size: CGSize(width: CGFloat(image.width), height: CGFloat(image.height))),
                                   degrees: rotationDegrees)
            return [NSBezierPath(rect: readableWrapRect(expanded(rect, by: distances), distances: .uniform(0),
                                                        minimumTextWidth: minimumTextWidth,
                                                        columnWidth: columnWidth, side: side))]
        }

        // Use overlapping line-height slabs. A TextKit line that straddles a
        // contour edge must see the union of the nearby silhouette, otherwise
        // a rotated edge can create a sub-word lane that is narrower than the
        // width checked for the source scanline.
        let totalBounds = rotatedRuns.reduce(CGRect.null) { $0.union($1) }
        let step = max(1, lineHeight)
        let bandHeight = step * 2
        var y = floor(totalBounds.minY / step) * step
        var paths: [NSBezierPath] = []
        let orderedRuns = rotatedRuns.sorted { $0.minY < $1.minY }
        var runCursor = 0
        var activeRuns: [CGRect] = []
        while y < totalBounds.maxY {
            let slab = CGRect(x: 0, y: y, width: columnWidth, height: bandHeight)
            activeRuns.removeAll { $0.maxY <= slab.minY }
            while runCursor < orderedRuns.count, orderedRuns[runCursor].minY < slab.maxY {
                activeRuns.append(orderedRuns[runCursor])
                runCursor += 1
            }
            let intersecting = activeRuns.filter { $0.intersects(slab) }
            if let left = intersecting.map(\.minX).min(), let right = intersecting.map(\.maxX).max() {
                let shapeSpan = CGRect(x: left, y: y, width: max(0, right - left), height: bandHeight)
                let exclusion = readableWrapRect(shapeSpan, distances: .uniform(0),
                                                 minimumTextWidth: minimumTextWidth,
                                                 columnWidth: columnWidth, side: side)
                if exclusion.width > 0, exclusion.height > 0 {
                    if let previous = paths.last, abs(previous.bounds.minX - exclusion.minX) < 0.01,
                       abs(previous.bounds.maxX - exclusion.maxX) < 0.01,
                       previous.bounds.maxY >= exclusion.minY - 0.01 {
                        let combined = previous.bounds.union(exclusion)
                        paths[paths.count - 1] = NSBezierPath(rect: combined)
                    } else {
                        paths.append(NSBezierPath(rect: exclusion))
                    }
                }
            }
            y += step
        }
        return paths
    }

    private static func rotatedRect(_ rect: CGRect, degrees: Double) -> CGRect {
        let path = rotatedPath(NSBezierPath(rect: rect), center: rect.center, degrees: degrees)
        return path.bounds
    }

    private static func expanded(_ rect: CGRect, by distances: FloatingImage.WrapDistances) -> CGRect {
        CGRect(x: rect.minX - CGFloat(distances.left),
               y: rect.minY - CGFloat(distances.top),
               width: rect.width + CGFloat(distances.left + distances.right),
               height: rect.height + CGFloat(distances.top + distances.bottom))
    }

    private static func rotatedPath(_ path: NSBezierPath, center: CGPoint, degrees: Double) -> NSBezierPath {
        guard degrees.truncatingRemainder(dividingBy: 360) != 0 else { return path }
        let result = path.copy() as! NSBezierPath
        var transform = AffineTransform.identity
        transform.translate(x: center.x, y: center.y)
        transform.rotate(byDegrees: degrees)
        transform.translate(x: -center.x, y: -center.y)
        result.transform(using: transform)
        return result
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
