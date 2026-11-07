import Foundation
import XCTest
import AppKit
import Darwin
@testable import BOLDWriter

final class BookAuditPerformanceTests: XCTestCase {
    private func syntheticFourHundredPageText() -> String {
        let paragraphA = String(repeating: "The archive preserves careful historical testimony and gives readers context for the source record. ", count: 13)
        let paragraphB = String(repeating: "Writers compare primary witnesses, examine chronology, and distinguish quoted sources from interpretation. ", count: 13)
        return (1...400).map { chapter in
            "Chapter \(chapter): Witnesses\n\n\(paragraphA)YHWH guided the witnesses.\n\n\(paragraphB)Yeshua taught the community.\n\n"
        }.joined()
    }

    func testFourHundredPageAuditTimingAndMemoryMetric() {
        let source = syntheticFourHundredPageText()
        let rule = BOLDConsistencyRule(kind: .preferredTerm, matchText: "Yeshua", replacement: "YHVH")
        let snapshot = BOLDBookAuditAnalyzer.snapshot(from: NSAttributedString(string: source))
        let metadata = BOLDAuditMetadataSnapshot(sections: [], bookmarks: [], tableOfContents: [], footnotes: nil, rules: [rule])
        let calibrationText = String(source.prefix(10_000))
        let calibration = BOLDBookAuditAnalyzer.snapshot(from: NSAttributedString(string: calibrationText))
        let calibrationStart = ProcessInfo.processInfo.systemUptime
        XCTAssertTrue(runDashboardPipeline(calibration, metadata: metadata))
        let calibrationDuration = max(0.005, ProcessInfo.processInfo.systemUptime - calibrationStart)
        let scalingBudget = max(5.0, calibrationDuration * Double(source.utf8.count) / Double(max(1, calibrationText.utf8.count)) * 8)
        let options = XCTMeasureOptions()
        options.iterationCount = 3

        print("BOOK_AUDIT_PERF fixture=400-chapter-approx-400-page utf16=\((source as NSString).length) utf8=\(source.utf8.count)")
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()], options: options) {
            let started = ProcessInfo.processInfo.systemUptime
            let findings = try! XCTUnwrap(BOLDBookAuditAnalyzer.analyze(snapshot, metadata: metadata, shouldCancel: { false }))
            let overview = try! XCTUnwrap(BOLDBookAuditAnalyzer.overview(for: snapshot.text, shouldCancel: { false }))
            let locations = BOLDAuditLocationIndex(snapshot.text)
            XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - started, scalingBudget,
                              "Long manuscript audit regressed beyond the same-machine scaling budget")
            XCTAssertLessThanOrEqual(findings.count, 1_500)
            XCTAssertGreaterThan(overview.words, 0)
            XCTAssertEqual(locations.describe((source as NSString).length - 1).contains("UTF-16 offset"), true)
            if let last = findings.last {
                XCTAssertLessThanOrEqual(NSMaxRange(last.firstRange), (source as NSString).length)
            }
        }
    }

    private func runDashboardPipeline(_ snapshot: BOLDBookAuditSnapshot, metadata: BOLDAuditMetadataSnapshot) -> Bool {
        guard BOLDBookAuditAnalyzer.analyze(snapshot, metadata: metadata, shouldCancel: { false }) != nil,
              BOLDBookAuditAnalyzer.overview(for: snapshot.text, shouldCancel: { false }) != nil,
              BOLDAuditLocationIndex(snapshot.text, shouldCancel: { false }) != nil else { return false }
        return true
    }

    func testThousandsOfRuleFindingsAreBoundedAndNavigableAtEnd() {
        let source = String(repeating: "Yehoshua wrote the original account.\n", count: 4_000)
        let rule = BOLDConsistencyRule(kind: .preferredTerm, matchText: "Yehoshua", replacement: "Yeshua")
        let findings = BOLDConsistencyScanner().scan(source, rules: [rule], maximumFindings: 700)
        XCTAssertGreaterThan(findings.count, 0)
        XCTAssertLessThanOrEqual(findings.count, 700)
        XCTAssertLessThan(findings.count, 1_000)
        XCTAssertTrue(findings.allSatisfy { $0.category == .authorRuleViolation })
        XCTAssertLessThanOrEqual(NSMaxRange(findings.last!.firstRange), (source as NSString).length)
    }

    func testRepeatedFullAuditsDoNotRetainUnboundedScanMemory() throws {
        let source = syntheticFourHundredPageText()
        let rule = BOLDConsistencyRule(kind: .preferredTerm, matchText: "Yeshua", replacement: "YHVH")
        let snapshot = BOLDBookAuditAnalyzer.snapshot(from: NSAttributedString(string: source))
        let metadata = BOLDAuditMetadataSnapshot(sections: [], bookmarks: [], tableOfContents: [], footnotes: nil, rules: [rule])
        let initialFootprint = try XCTUnwrap(currentPhysicalFootprint())

        for _ in 0..<8 {
            autoreleasepool {
                let findings = BOLDBookAuditAnalyzer.analyze(snapshot, metadata: metadata, shouldCancel: { false })
                XCTAssertNotNil(findings)
                XCTAssertLessThanOrEqual(findings?.count ?? .max, 1_500)
            }
        }

        let finalFootprint = try XCTUnwrap(currentPhysicalFootprint())
        let growth = finalFootprint > initialFootprint ? finalFootprint - initialFootprint : 0
        let platformBudget = max(24 * 1_024 * 1_024, min(128 * 1_024 * 1_024, ProcessInfo.processInfo.physicalMemory / 128))
        print("BOOK_AUDIT_MEMORY repeatedScans=8 growthBytes=\(growth) allowedBytes=\(platformBudget)")
        XCTAssertLessThan(growth, platformBudget, "Repeated scans retained more memory than the platform-scaled audit budget")
    }

    private func currentPhysicalFootprint() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : nil
    }

    func testIncrementalRevisionUsesCurrentOffsetsAndNotPriorSnapshot() {
        let original = "Yehoshua wrote.\n\nA long unrelated note."
        let edited = "Added Unicode 📚 before the existing line.\n\n" + original
        let rule = BOLDConsistencyRule(kind: .preferredTerm, matchText: "Yehoshua", replacement: "Yeshua")
        let before = BOLDConsistencyScanner().scan(original, rules: [rule])
        let after = BOLDConsistencyScanner().scan(edited, rules: [rule])
        XCTAssertEqual(before.count, 1)
        XCTAssertEqual(after.count, 1)
        XCTAssertEqual(after[0].firstRange.location, (edited as NSString).range(of: "Yehoshua").location)
        XCTAssertNotEqual(before[0].firstRange.location, after[0].firstRange.location)
    }

    func testWriteDisposableNativeGUIFixtureWhenRequested() throws {
        guard let outputPath = ProcessInfo.processInfo.environment["BOLD_AUDIT_GUI_FIXTURE"],
              !outputPath.isEmpty else { return }

        let content = NSMutableAttributedString()
        let paragraphA = String(repeating: "The archive preserves careful historical testimony and gives readers context for the source record. ", count: 13)
        let paragraphB = String(repeating: "Writers compare primary witnesses, examine chronology, and distinguish quoted sources from interpretation. ", count: 13)
        for chapter in 1...400 {
            let heading = NSAttributedString(string: "Chapter \(chapter): Witnesses\n", attributes: [.boldWriterStyle: WriterStyle.heading1.rawValue])
            content.append(heading)
            content.append(NSAttributedString(string: "\(paragraphA)YHWH guided the witnesses.\n\n"))
            let quote = NSAttributedString(string: "Yehoshua taught the community in the source record.\n\n", attributes: [.boldWriterStyle: WriterStyle.blockQuote.rawValue])
            content.append(quote)
            content.append(NSAttributedString(string: "\(paragraphB)Yeshua taught the community.\n\n"))
            if chapter == 10 { content.append(NSAttributedString(string: "The archive preserves careful historical testimony and gives readers context for the source record.\n\n")) }
        }

        let document = BOLDWriterDocument()
        document.replaceText(with: content)
        document.metadata.title = "Synthetic 400 Chapter Book Audit"
        document.metadata.manuscriptLiveAuditEnabled = false
        document.metadata.manuscriptConsistencyRules = [
            BOLDConsistencyRule(kind: .preferredTerm, matchText: "Yeshua", replacement: "Yehoshua", explanation: "Synthetic test rule; verify each location before applying.", scope: .outsideQuotationMarks),
            BOLDConsistencyRule(kind: .capitalization, matchText: "YHWH", replacement: "YHVH", explanation: "Project spelling in original prose.", scope: .outsideQuotationMarks)
        ]

        let wrapper = try BOLDWriterDocument.packageWrapper(text: document.text, metadata: document.metadata)
        let destination = URL(fileURLWithPath: outputPath, isDirectory: true)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try wrapper.write(to: destination, options: .atomic, originalContentsURL: nil)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        print("BOOK_AUDIT_GUI_FIXTURE path=\(destination.path) utf16=\((content.string as NSString).length)")
    }
}
