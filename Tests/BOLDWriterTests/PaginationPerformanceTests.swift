import AppKit
@testable import BOLDWriter
import XCTest

@MainActor
final class PaginationPerformanceTests: XCTestCase {
    func testInitialPaginationRangeVisitsScaleWithAppendedPages() {
        for expectedPageCount in [10, 100, 1_000] {
            let string = Array(
                repeating: "A stable page for measuring range-rebuild work.",
                count: expectedPageCount
            ).joined(separator: "\u{000C}")
            let text = NSAttributedString(
                string: string,
                attributes: [.font: NSFont.systemFont(ofSize: 12)]
            )
            let editor = PaginatedEditor(text: text)
            let start = ProcessInfo.processInfo.systemUptime
            editor.configure(
                printLayout: true,
                settings: PageSettings(),
                zoom: 1,
                viewportWidth: 800
            )
            var batches = 0
            while !editor.layoutComplete && editor.lastLayoutError == nil && batches < 2_000 {
                editor.paginateBatch(maxPages: 8)
                batches += 1
            }
            let elapsed = ProcessInfo.processInfo.systemUptime - start

            XCTAssertNil(editor.lastLayoutError)
            XCTAssertTrue(editor.layoutComplete)
            XCTAssertEqual(editor.pageRanges.count, expectedPageCount)
            XCTAssertEqual(editor.rangeRebuildPageVisitCount, expectedPageCount)
            print("PAGINATION_SCALE pages=\(expectedPageCount) elapsedSeconds=\(elapsed) batches=\(batches) rangePageVisits=\(editor.rangeRebuildPageVisitCount) fullScanEquivalentVisits=\(editor.fullScanEquivalentPageVisitCount)")
        }
    }

    func testInitialPaginationRebuildsRangesOnlyForNewPages() throws {
        var settings = PageSettings()
        settings.topMargin = 54
        settings.bottomMargin = 54
        settings.leftMargin = 63
        settings.rightMargin = 63

        let pageText = Array(
            repeating: "A stable page of manuscript text for pagination range measurement.",
            count: 391
        ).joined(separator: "\u{000C}")
        let text = NSAttributedString(
            string: pageText,
            attributes: [.font: NSFont.systemFont(ofSize: 12)]
        )
        func paginate(_ editor: PaginatedEditor) -> (Double, Int) {
            let start = ProcessInfo.processInfo.systemUptime
            editor.configure(
                printLayout: true,
                settings: settings,
                zoom: 1,
                viewportWidth: 800
            )
            var batches = 0
            while !editor.layoutComplete && editor.lastLayoutError == nil && batches < 2_000 {
                editor.paginateBatch(maxPages: 8)
                batches += 1
            }
            return (ProcessInfo.processInfo.systemUptime - start, batches)
        }

        let baselineEditor = PaginatedEditor(text: text)
        baselineEditor.forceFullRangeRebuildForTesting = true
        let (baselineSeconds, baselineBatches) = paginate(baselineEditor)
        XCTAssertNil(baselineEditor.lastLayoutError)
        XCTAssertTrue(baselineEditor.layoutComplete)

        let editor = PaginatedEditor(text: text)
        let (optimizedSeconds, optimizedBatches) = paginate(editor)
        XCTAssertNil(editor.lastLayoutError)
        XCTAssertTrue(editor.layoutComplete)
        XCTAssertEqual(editor.pageRanges.count, 391)
        XCTAssertEqual(editor.rangeRebuildPageVisitCount, editor.pageRanges.count)
        XCTAssertGreaterThan(editor.fullScanEquivalentPageVisitCount, editor.rangeRebuildPageVisitCount)
        XCTAssertEqual(editor.pageRanges, baselineEditor.pageRanges)
        XCTAssertEqual(editor.pageRanges.first?.location, 0)
        XCTAssertEqual(editor.pageRanges.last.map(NSMaxRange), text.length)
        for index in 1..<editor.pageRanges.count {
            XCTAssertEqual(
                editor.pageRanges[index].location,
                NSMaxRange(editor.pageRanges[index - 1]),
                "Physical page ranges should remain contiguous at index \(index)."
            )
        }

        let initialPageCount = editor.pageRanges.count
        let visitsBeforeEdit = editor.rangeRebuildPageVisitCount
        let fullScanVisitsBeforeEdit = editor.fullScanEquivalentPageVisitCount
        let originalText = editor.flow.storage.string
        let middle = editor.pageRanges[initialPageCount / 2].location + 1
        editor.flow.storage.beginEditing()
        editor.flow.storage.replaceCharacters(
            in: NSRange(location: middle, length: 1),
            with: "B"
        )
        editor.flow.storage.endEditing()

        var batches = 0
        while !editor.layoutComplete && editor.lastLayoutError == nil && batches < 2_000 {
            editor.paginateBatch(maxPages: 8)
            batches += 1
        }

        XCTAssertNil(editor.lastLayoutError)
        XCTAssertTrue(editor.layoutComplete)
        XCTAssertEqual(editor.pageRanges.count, initialPageCount)
        XCTAssertEqual(editor.flow.storage.string.count, originalText.count)
        XCTAssertEqual((editor.flow.storage.string as NSString).substring(with: NSRange(location: middle, length: 1)), "B")
        XCTAssertEqual(
            editor.rangeRebuildPageVisitCount - visitsBeforeEdit,
            editor.fullScanEquivalentPageVisitCount - fullScanVisitsBeforeEdit,
            "Reflow retains full-range rebuilding while existing later page containers may be stale."
        )
        for index in 1..<editor.pageRanges.count {
            XCTAssertEqual(
                editor.pageRanges[index].location,
                NSMaxRange(editor.pageRanges[index - 1])
            )
        }
        print("PAGINATION_PERF pages=\(initialPageCount) legacySeconds=\(baselineSeconds) incrementalSeconds=\(optimizedSeconds) legacyBatches=\(baselineBatches) incrementalBatches=\(optimizedBatches) legacyRangeVisits=\(baselineEditor.rangeRebuildPageVisitCount) incrementalRangeVisits=\(visitsBeforeEdit) incrementalFullScanEquivalentVisits=\(fullScanVisitsBeforeEdit) reflowVisits=\(editor.rangeRebuildPageVisitCount - visitsBeforeEdit) reflowFullScanEquivalentVisits=\(editor.fullScanEquivalentPageVisitCount - fullScanVisitsBeforeEdit)")
    }
}
