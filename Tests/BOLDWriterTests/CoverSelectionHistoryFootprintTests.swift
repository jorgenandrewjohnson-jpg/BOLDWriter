import Darwin
import XCTest
@testable import BOLDWriter

final class CoverSelectionHistoryFootprintTests: XCTestCase {
    func testSelectionHistoryEncodingAndReopenCostsAtPublishingSizes() throws {
        let sizes = [(640, 640), (1_800, 2_700), (2_804, 1_788)]
        let snapshotsPerHistory = 6

        for (width, height) in sizes {
            let baselineResidentBytes = maximumResidentBytes()
            let pixelCount = width * height
            let layerID = UUID()
            var history: [CoverProject] = []
            history.reserveCapacity(snapshotsPerHistory)

            let historyStart = Date()
            for revision in 0..<snapshotsPerHistory {
                var project = CoverProject(width: 1, height: 1)
                project.editorActiveSelectionLayerID = layerID
                project.editorActiveSelectionMask = Data((0..<pixelCount).map { pixel in
                    UInt8(((pixel + revision * 17) % 256))
                })
                history.append(project)
            }
            let historyBuildSeconds = Date().timeIntervalSince(historyStart)

            let encodeStart = Date()
            let historyData = try JSONEncoder().encode(history)
            let encodeSeconds = Date().timeIntervalSince(encodeStart)

            let reopenStart = Date()
            let reopened = try JSONDecoder().decode([CoverProject].self, from: historyData)
            let reopenSeconds = Date().timeIntervalSince(reopenStart)
            let peakResidentBytes = maximumResidentBytes()

            XCTAssertEqual(reopened.count, snapshotsPerHistory)
            XCTAssertEqual(reopened.last?.editorActiveSelectionMask, history.last?.editorActiveSelectionMask)
            XCTAssertEqual(reopened.first?.editorActiveSelectionMask?.count, pixelCount)

            print(
                "SELECTION_HISTORY_FOOTPRINT dimensions=\(width)x\(height) revisions=\(snapshotsPerHistory) " +
                "maskBytesEach=\(pixelCount) logicalHistoryMaskBytes=\(pixelCount * snapshotsPerHistory) " +
                "encodedHistoryBytes=\(historyData.count) buildSeconds=\(historyBuildSeconds) " +
                "encodeSeconds=\(encodeSeconds) reopenSeconds=\(reopenSeconds) " +
                "processPeakRSSBytes=\(peakResidentBytes) rssIncreaseSinceTestStartBytes=\(max(0, peakResidentBytes - baselineResidentBytes))"
            )
        }
    }

    private func maximumResidentBytes() -> Int {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
        return usage.ru_maxrss
    }
}
