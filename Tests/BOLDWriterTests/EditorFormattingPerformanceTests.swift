import AppKit
import XCTest
@testable import BOLDWriter

@MainActor
final class EditorFormattingPerformanceTests: XCTestCase {
    func testLargeMixedSelectionFormattingBenchmark() {
        let runCount = 20_000
        let runLength = 8
        let content = NSMutableAttributedString(
            string: String(repeating: "x", count: runCount * runLength)
        )
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        let alternateParagraph = NSMutableParagraphStyle()
        alternateParagraph.alignment = .right
        let attributes: [[NSAttributedString.Key: Any]] = [
            [.font: NSFont.systemFont(ofSize: 12), .paragraphStyle: paragraph],
            [.font: NSFont.boldSystemFont(ofSize: 12), .paragraphStyle: alternateParagraph],
            [.font: NSFont.systemFont(ofSize: 15), .paragraphStyle: alternateParagraph],
            [.font: NSFont.boldSystemFont(ofSize: 15), .paragraphStyle: paragraph]
        ]
        for run in 0..<runCount {
            content.addAttributes(
                attributes[run % attributes.count],
                range: NSRange(location: run * runLength, length: runLength)
            )
        }

        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 500))
        view.textStorage?.setAttributedString(content)
        let selection = NSRange(location: 0, length: content.length)
        let repetitions = 7
        var durations: [Double] = []
        for _ in 0..<repetitions {
            let start = ProcessInfo.processInfo.systemUptime
            let state = EditorFormattingState.read(from: view, selection: selection)
            durations.append(ProcessInfo.processInfo.systemUptime - start)
            XCTAssertEqual(state.bold, .mixed)
            XCTAssertEqual(state.italic, .off)
            XCTAssertNil(state.fontSize)
        }
        durations.sort()
        let result: [String: Any] = [
            "benchmark": "EditorFormattingState.read",
            "attributedRuns": runCount,
            "selectionUTF16Length": content.length,
            "repetitions": repetitions,
            "medianSeconds": durations[durations.count / 2],
            "durationsSeconds": durations
        ]
        let data = try! JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print("PERFORMANCE_BENCHMARK_JSON=" + String(decoding: data, as: UTF8.self))
    }
}
