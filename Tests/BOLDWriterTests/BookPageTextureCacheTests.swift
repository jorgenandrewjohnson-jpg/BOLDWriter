import AppKit
import XCTest
@testable import BOLDWriter

final class BookPageTextureCacheTests: XCTestCase {
    private func image(width: Int = 100, height: Int = 100) -> NSImage {
        let bitmap = NSBitmapImageRep(
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
        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(bitmap)
        return image
    }

    func testCacheEvictsLeastRecentlyUsedPagesToHonorByteBudget() {
        var sizing = BookPageTextureCache(costLimitBytes: 1_000_000)
        sizing.store(image(), for: 99, maximumPixels: 900)
        let singleTextureCost = sizing.totalCostBytes
        var cache = BookPageTextureCache(capacity: 8, costLimitBytes: singleTextureCost * 2)
        cache.store(image(), for: 1, maximumPixels: 900)
        cache.store(image(), for: 2, maximumPixels: 900)
        cache.markUsed(1)
        cache.store(image(), for: 3, maximumPixels: 900)

        XCTAssertNil(cache.image(for: 2), "the least recently used page should be evicted")
        XCTAssertNotNil(cache.image(for: 1))
        XCTAssertNotNil(cache.image(for: 3))
        XCTAssertLessThanOrEqual(cache.totalCostBytes, cache.costLimitBytes)
    }

    func testHigherResolutionTextureReplacesLowerResolutionCost() {
        var cache = BookPageTextureCache(capacity: 8, costLimitBytes: 500_000)
        cache.store(image(width: 50, height: 50), for: 1, maximumPixels: 900)
        let lowResolutionCost = cache.totalCostBytes
        cache.store(image(width: 100, height: 100), for: 1, maximumPixels: 2400)

        XCTAssertGreaterThan(cache.totalCostBytes, lowResolutionCost)
        XCTAssertEqual(cache.entries[1]?.maximumPixels, 2400)
    }

    func testResetClearsRetainedTextureCostAndChangesSourceIdentity() {
        var cache = BookPageTextureCache(costLimitBytes: 500_000)
        cache.store(image(), for: 1, maximumPixels: 900)
        let previousSource = cache.sourceID

        cache.reset()

        XCTAssertTrue(cache.entries.isEmpty)
        XCTAssertEqual(cache.totalCostBytes, 0)
        XCTAssertNotEqual(cache.sourceID, previousSource)
    }
}
