import AppKit

/// A small, source-scoped cache for the pages that can appear around a spread.
/// The raster size is tracked so a quick thumbnail never replaces a final page.
struct BookPageTextureCache {
    struct Entry {
        let image: NSImage
        let maximumPixels: Int
        let estimatedBytes: Int
    }

    private(set) var sourceID = UUID()
    private(set) var entries: [Int: Entry] = [:]
    private var recent: [Int] = []
    private(set) var totalCostBytes = 0
    let capacity: Int
    let costLimitBytes: Int

    init(capacity: Int = 8, costLimitBytes: Int = 96 * 1024 * 1024) {
        self.capacity = max(2, capacity)
        self.costLimitBytes = max(1, costLimitBytes)
    }

    mutating func reset() {
        sourceID = UUID()
        entries.removeAll(keepingCapacity: true)
        recent.removeAll(keepingCapacity: true)
        totalCostBytes = 0
    }

    func image(for page: Int) -> NSImage? { entries[page]?.image }

    func needsImage(for page: Int, maximumPixels: Int) -> Bool {
        (entries[page]?.maximumPixels ?? 0) < maximumPixels
    }

    mutating func markUsed(_ page: Int) {
        guard entries[page] != nil else { return }
        recent.removeAll { $0 == page }
        recent.append(page)
    }

    mutating func store(_ image: NSImage, for page: Int, maximumPixels: Int) {
        guard page > 0, maximumPixels > 0 else { return }
        if maximumPixels >= (entries[page]?.maximumPixels ?? 0) {
            let cost = Self.estimatedByteCost(of: image)
            if let old = entries[page] {
                totalCostBytes = max(0, totalCostBytes - old.estimatedBytes)
            }
            entries[page] = Entry(image: image, maximumPixels: maximumPixels, estimatedBytes: cost)
            totalCostBytes = totalCostBytes.addingReportingOverflow(cost).overflow
                ? Int.max
                : totalCostBytes + cost
        }
        recent.removeAll { $0 == page }
        recent.append(page)
        while recent.count > capacity || totalCostBytes > costLimitBytes {
            let removed = recent.removeFirst()
            if let entry = entries.removeValue(forKey: removed) {
                totalCostBytes = max(0, totalCostBytes - entry.estimatedBytes)
            }
        }
    }

    private static func estimatedByteCost(of image: NSImage) -> Int {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            let width = max(1, Int(image.size.width.rounded(.up)))
            let height = max(1, Int(image.size.height.rounded(.up)))
            let (pixels, pixelOverflow) = width.multipliedReportingOverflow(by: height)
            let (bytes, byteOverflow) = pixels.multipliedReportingOverflow(by: 4)
            return pixelOverflow || byteOverflow ? Int.max : bytes
        }
        let (bytes, overflow) = cgImage.bytesPerRow.multipliedReportingOverflow(by: cgImage.height)
        return overflow ? Int.max : bytes
    }

    static func pagePlan(for spread: BookSpread, pageCount: Int) -> (visible: [Int], adjacent: [Int]) {
        let visible = [spread.leftPage, spread.rightPage].compactMap { $0 }
        let adjacent = [spread.index * 2 - 1, spread.index * 2 + 2]
            .filter { $0 > 0 && $0 <= pageCount && !visible.contains($0) }
        return (visible, adjacent)
    }
}

/// Keeps diagnostic marks stable across SwiftUI body evaluations. Without this,
/// an affected page gets a new NSImage identity on each inspector update and
/// needlessly invalidates the SceneKit page material.
final class BookPageTextureDecorator {
    private struct Entry {
        let source: NSImage
        let marked: NSImage
    }
    private var entries: [Int: Entry] = [:]

    func reset() { entries.removeAll(keepingCapacity: true) }

    func texture(for page: Int, source: NSImage, hasIssue: Bool) -> NSImage {
        guard hasIssue else { return source }
        if let entry = entries[page], entry.source === source { return entry.marked }
        let marked = PhysicalBookPreview.interiorResolutionTexture(source, hasIssue: true)
        entries[page] = Entry(source: source, marked: marked)
        if entries.count > 4 {
            for oldPage in entries.keys.sorted() where oldPage != page {
                entries.removeValue(forKey: oldPage)
                if entries.count <= 4 { break }
            }
        }
        return marked
    }
}
