import AppKit
import Foundation

/// Independent manuscript artwork. Geometry is stored in physical points from
/// the page's top-left corner (or the content margin's top-left for `.margins`).
/// Inline artwork remains represented by NSTextAttachment for compatibility.
struct FloatingImage: Codable, Equatable, Identifiable {
    /// WordCraft's DOCX picture reader/writer carries a:srcRect's four
    /// hundred-thousandth edges with the picture. Ported from
    /// storytold/wordcraft@8c57b0775ce70736047db6d291ae77c53b27da7c,
    /// crates/docx/src/read/story/drawing.rs and write/story/drawing.rs
    /// (MIT OR Apache-2.0; MIT notice in Docs/ThirdParty/WordCraft-LICENSE-MIT.txt).
    /// Keeping the original integer edges avoids rounding drift on DOCX saves.
    struct SourceCrop: Codable, Equatable {
        var left: Int
        var top: Int
        var right: Int
        var bottom: Int

        init(left: Int = 0, top: Int = 0, right: Int = 0, bottom: Int = 0) {
            self.left = left; self.top = top; self.right = right; self.bottom = bottom
        }

        init(_ crop: WordPictureCrop) {
            self.init(left: crop.left, top: crop.top, right: crop.right, bottom: crop.bottom)
        }

        var isEmpty: Bool { left == 0 && top == 0 && right == 0 && bottom == 0 }
        var hasValidGeometry: Bool {
            [left, top, right, bottom].allSatisfy { (0...100_000).contains($0) }
                && left + right < 100_000 && top + bottom < 100_000
        }

        /// NSImage's source rectangle starts at the lower left, while Word's
        /// srcRect names the upper edge first.
        func sourceRect(in size: CGSize) -> CGRect {
            CGRect(x: size.width * CGFloat(left) / 100_000,
                   y: size.height * CGFloat(bottom) / 100_000,
                   width: size.width * CGFloat(100_000 - left - right) / 100_000,
                   height: size.height * CGFloat(100_000 - top - bottom) / 100_000)
        }
    }
    /// Per-edge text clearance imported from or exported to DrawingML. `nil`
    /// preserves older native documents, whose single `wrapDistance` applies
    /// uniformly to every edge.
    struct WrapDistances: Codable, Equatable {
        var top: Double
        var right: Double
        var bottom: Double
        var left: Double

        init(top: Double, right: Double, bottom: Double, left: Double) {
            self.top = top
            self.right = right
            self.bottom = bottom
            self.left = left
        }

        static func uniform(_ distance: Double) -> Self {
            Self(top: distance, right: distance, bottom: distance, left: distance)
        }

        var values: [Double] { [top, right, bottom, left] }
    }
    /// WordCraft's bounded `wp:wrapPolygon` representation, ported from
    /// storytold/wordcraft@8c57b0775ce70736047db6d291ae77c53b27da7c
    /// crates/doc/src/wrap.rs and crates/docx/src/read/story/drawing.rs.
    /// Coordinates use Word's 21,600-unit object-relative space. The MIT
    /// notice is retained in Docs/ThirdParty/WordCraft-LICENSE-MIT.txt.
    struct WrapPolygon: Codable, Equatable {
        struct Point: Codable, Equatable {
            var x: Int
            var y: Int
        }
        static let space = 21_600
        static let maximumPoints = 1_024
        static let maximumCoordinate = space * 4
        var edited: Bool
        var points: [Point]

        var isValid: Bool {
            guard (3...Self.maximumPoints).contains(points.count),
                  points.allSatisfy({
                    (-Self.maximumCoordinate...Self.maximumCoordinate).contains($0.x)
                        && (-Self.maximumCoordinate...Self.maximumCoordinate).contains($0.y)
                  }) else { return false }
            let doubledArea = points.indices.reduce(Int64(0)) { area, index in
                let first = points[index], next = points[(index + 1) % points.count]
                return area + Int64(first.x) * Int64(next.y) - Int64(next.x) * Int64(first.y)
            }
            return doubledArea != 0
        }
    }
    enum Wrapping: String, Codable, CaseIterable { case none, square, tight, through, topAndBottom }
    /// Which text lane(s) may remain beside a wrapped image. `automatic`
    /// preserves both lanes when both are readable, then favors the only
    /// readable lane; if neither is readable, text continues below the image.
    enum WrapSide: String, Codable, CaseIterable { case both, leftOnly, rightOnly, largestSide, automatic }
    enum Anchor: String, Codable, CaseIterable { case page, margins, paragraph, character }
    enum Layer: String, Codable, CaseIterable { case behindText, inFrontOfText }
    /// Optional per-axis DrawingML reference frames. Nil retains BOLD Writer's
    /// historical semantics (page/margin anchor, or text-anchor-relative offset).
    enum PositionReference: String, Codable, CaseIterable { case page, margins, anchor, paragraph, character, line }
    enum HorizontalAlignment: String, Codable, CaseIterable { case left, center, right }
    enum VerticalAlignment: String, Codable, CaseIterable { case top, center, bottom }

    var id: UUID
    var assetName: String
    /// Optional Word drawing metadata; absent in older native packages.
    var altTitle: String? = nil
    var altDescription: String? = nil
    var imageData: Data
    /// Content-addressed reference used by the native package asset store.
    /// Old packages omit this and keep their bytes inline until the next save.
    var assetDigest: String? = nil
    /// Non-destructive source crop; nil is a full uncropped image in old files.
    var sourceCrop: SourceCrop? = nil
    /// Retains an imported custom Word Tight Wrap outline through native
    /// editing. Nil continues to derive a contour from visible image pixels.
    var wrapPolygon: WrapPolygon? = nil
    var pageIndex: Int
    var anchor: Anchor
    /// UTF-16 target location for paragraph/character anchors. -1 means page-only.
    var anchorLocation: Int
    /// Physical offset from the resolved paragraph/character origin. Nil keeps
    /// the legacy page-relative interpretation for documents written before
    /// anchor-relative placement was introduced.
    var anchorOffsetX: Double? = nil
    var anchorOffsetY: Double? = nil
    var horizontalPositionReference: PositionReference? = nil
    var verticalPositionReference: PositionReference? = nil
    /// DrawingML responsive alignment is stored separately from its text
    /// anchor and offset. Nil means the corresponding axis uses an offset.
    var horizontalAlignment: HorizontalAlignment? = nil
    var verticalAlignment: VerticalAlignment? = nil
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var rotationDegrees: Double
    var preservesAspectRatio: Bool
    var wrapping: Wrapping
    /// A simple user-facing switch for automatic text reflow. Enabling it from
    /// No Wrap chooses the standard rectangular Square behavior; when another
    /// wrap mode is already selected, enabling it preserves that choice.
    var automaticTextFlowEnabled: Bool { wrapping != .none }

    mutating func setAutomaticTextFlow(_ enabled: Bool) {
        if enabled {
            if wrapping == .none { wrapping = .square }
        } else {
            wrapping = .none
        }
    }

    var wrapDistance: Double
    /// `nil` means use the legacy uniform `wrapDistance` value.
    var wrapDistances: WrapDistances? = nil
    var effectiveWrapDistances: WrapDistances { wrapDistances ?? .uniform(wrapDistance) }
    /// Optional for backwards compatibility with native files written before
    /// wrap-side controls existed. Missing values behave as `.both`.
    var wrapSide: WrapSide? = .both
    var effectiveWrapSide: WrapSide { wrapSide ?? .both }
    var layer: Layer
    var zOrder: Int
    var positionLocked: Bool

    /// Render the cropped source at its original pixel resolution. The model
    /// still owns the untouched source bytes and exact Word crop percentages.
    /// A cropped CGImage also keeps PDF image placement at the visible frame,
    /// so effective-DPI preflight measures the picture users actually see.
    func displayImage() -> NSImage? {
        guard let source = NSImage(data: imageData) else { return nil }
        guard let crop = sourceCrop, !crop.isEmpty else { return source }
        guard crop.hasValidGeometry,
              let pixels = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let width = pixels.width, height = pixels.height
        guard width > 0, height > 0 else { return nil }
        let x0 = min(width - 1, max(0, Int((Double(width) * Double(crop.left) / 100_000).rounded(.down))))
        let y0 = min(height - 1, max(0, Int((Double(height) * Double(crop.top) / 100_000).rounded(.down))))
        let x1 = min(width, max(x0 + 1, Int((Double(width) * Double(100_000 - crop.right) / 100_000).rounded(.up))))
        let y1 = min(height, max(y0 + 1, Int((Double(height) * Double(100_000 - crop.bottom) / 100_000).rounded(.up))))
        guard let clipped = pixels.cropping(to: CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)) else { return nil }
        return NSImage(cgImage: clipped, size: NSSize(width: clipped.width, height: clipped.height))
    }

    init(id: UUID = UUID(), assetName: String, imageData: Data, pageIndex: Int = 0,
         anchor: Anchor = .page, anchorLocation: Int = -1, x: Double, y: Double,
         anchorOffsetX: Double? = nil, anchorOffsetY: Double? = nil,
         horizontalPositionReference: PositionReference? = nil,
         verticalPositionReference: PositionReference? = nil,
         horizontalAlignment: HorizontalAlignment? = nil,
         verticalAlignment: VerticalAlignment? = nil,
         width: Double, height: Double, rotationDegrees: Double = 0,
         preservesAspectRatio: Bool = true, wrapping: Wrapping = .none,
         wrapDistance: Double = 6, wrapSide: WrapSide = .both,
         layer: Layer = .inFrontOfText, zOrder: Int = 0,
         positionLocked: Bool = false, assetDigest: String? = nil,
         wrapDistances: WrapDistances? = nil, sourceCrop: SourceCrop? = nil,
         wrapPolygon: WrapPolygon? = nil) {
        self.id = id; self.assetName = assetName; self.imageData = imageData
        self.assetDigest = assetDigest
        self.sourceCrop = sourceCrop
        self.wrapPolygon = wrapPolygon
        self.pageIndex = pageIndex; self.anchor = anchor; self.anchorLocation = anchorLocation
        self.anchorOffsetX = anchorOffsetX; self.anchorOffsetY = anchorOffsetY
        self.horizontalPositionReference = horizontalPositionReference
        self.verticalPositionReference = verticalPositionReference
        self.horizontalAlignment = horizontalAlignment
        self.verticalAlignment = verticalAlignment
        self.x = x; self.y = y; self.width = width; self.height = height
        self.rotationDegrees = rotationDegrees; self.preservesAspectRatio = preservesAspectRatio
        self.wrapping = wrapping; self.wrapDistance = wrapDistance; self.wrapDistances = wrapDistances
        self.wrapSide = wrapSide; self.layer = layer
        self.zOrder = zOrder; self.positionLocked = positionLocked
    }

    static func validate(_ images: [FloatingImage], textLength: Int) throws {
        guard images.count <= 500, Set(images.map(\.id)).count == images.count else {
            throw WriterError.message("Floating image records must have unique IDs and stay within the 500-object document limit.")
        }
        for image in images {
            guard image.pageIndex >= 0, image.anchorLocation >= -1,
                  image.anchorLocation == -1 || image.anchorLocation <= textLength,
                  [image.x, image.y, image.width, image.height, image.rotationDegrees, image.wrapDistance].allSatisfy(\.isFinite),
                  image.x >= 0, image.y >= 0, image.width > 0, image.height > 0,
                  (image.anchorOffsetX == nil) == (image.anchorOffsetY == nil),
                  [image.anchorOffsetX, image.anchorOffsetY].compactMap({ $0 }).allSatisfy({ $0.isFinite && abs($0) <= 20_000 }),
                  image.horizontalAlignment == nil || image.horizontalPositionReference == .page || image.horizontalPositionReference == .margins,
                  image.verticalAlignment == nil || image.verticalPositionReference == .page || image.verticalPositionReference == .margins,
                  image.effectiveWrapDistances.values.allSatisfy({ $0.isFinite && (0...288).contains($0) }),
                  image.width <= 20_000, image.height <= 20_000,
                  abs(image.rotationDegrees) <= 36_000, (0...288).contains(image.wrapDistance),
                  !image.assetName.isEmpty, image.imageData.count <= 100 * 1024 * 1024,
                  image.assetDigest == nil || (image.assetDigest?.count == 64 && image.assetDigest!.allSatisfy(\.isHexDigit)),
                  image.sourceCrop?.hasValidGeometry != false,
                  image.wrapPolygon?.isValid != false,
                  image.sourceCrop == nil || image.displayImage() != nil,
                  NSImage(data: image.imageData)?.isValid == true else {
                throw WriterError.message("A floating image has invalid geometry, anchor, or image data.")
            }
            if (image.anchor == .paragraph || image.anchor == .character) && image.anchorLocation < 0 {
                throw WriterError.message("Paragraph and character anchored images require a text location.")
            }
        }
    }
}

/// Deterministic keyboard movement policy for a canvas-selected floating image.
/// Shift moves 10 pt, Option moves 0.1 pt, and an unmodified arrow moves 1 pt.
/// Command/Control shortcuts are left to AppKit and the manuscript editor.
enum FloatingImageKeyboardMovement {
    static func delta(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> CGPoint? {
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)
        let allowed: NSEvent.ModifierFlags = [.shift, .option, .numericPad, .function]
        guard flags.subtracting(allowed).isEmpty else { return nil }
        let step: CGFloat = flags.contains(.option) ? 0.1 : (flags.contains(.shift) ? 10 : 1)
        switch keyCode {
        case 123: return CGPoint(x: -step, y: 0)
        case 124: return CGPoint(x: step, y: 0)
        case 125: return CGPoint(x: 0, y: step)
        case 126: return CGPoint(x: 0, y: -step)
        default: return nil
        }
    }
}
