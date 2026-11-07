import AppKit
import Darwin
import Foundation
import PDFKit
import XCTest
@testable import BOLDWriter

/// Opt-in, disposable, production-paginator performance matrix. Run with
/// BOLD_PERFORMANCE_MATRIX_OUTPUT=/absolute/report.json. It creates synthetic
/// explicit-page-break manuscripts; it never reads or writes author projects.
@MainActor
final class ManuscriptPerformanceMatrixTests: XCTestCase {
    private let sizes = [10, 100, 391, 500, 1_000]
    private let repetitions = 3

    func testFiveSizeManuscriptPerformanceMatrix() throws {
        guard let reportPath = ProcessInfo.processInfo.environment["BOLD_PERFORMANCE_MATRIX_OUTPUT"], !reportPath.isEmpty else {
            throw XCTSkip("Set BOLD_PERFORMANCE_MATRIX_OUTPUT to run the disposable five-size performance matrix.")
        }
        let reportURL = URL(fileURLWithPath: reportPath).standardizedFileURL
        let root = reportURL.deletingLastPathComponent().appendingPathComponent("Fixtures-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let host = ProcessInfo.processInfo.hostName
        var sizeResults: [[String: Any]] = []
        let started = ISO8601DateFormatter().string(from: Date())
        for pageCount in sizes {
            let fixtureURL = root.appendingPathComponent("Synthetic-\(pageCount)-pages.boldwriter", isDirectory: true)
            let fixture = Self.makeFixture(pages: pageCount)
            let metadata = DocumentMetadata(title: "Synthetic performance fixture \(pageCount)")
            try BOLDWriterDocument.packageWrapper(text: fixture, metadata: metadata)
                .write(to: fixtureURL, options: .atomic, originalContentsURL: nil)

            var samples: [[String: Any]] = []
            var postCloseRSS: [UInt64] = []
            for repetition in 1...repetitions {
                let rssBefore = Self.residentBytes()
                let sampler = ResidentMemorySampler()
                sampler.start()
                var timings: [String: Double] = [:]
                let pdfURL = root.appendingPathComponent("\(pageCount)-\(repetition).pdf")
                try autoreleasepool {
                    let openStart = Date()
                    let document = try BOLDWriterDocument(fileWrapper: FileWrapper(url: fixtureURL), contentType: .boldWriterDocument)
                    timings[repetition == 1 ? "firstDocumentOpenAfterFixtureCreationSeconds" : "warmDocumentOpenSeconds"] = Date().timeIntervalSince(openStart)

                    let findStart = Date()
                    let searchString = "PAGE-\(pageCount - 1)"
                    let found = (document.text.string as NSString).range(of: searchString)
                    XCTAssertNotEqual(found.location, NSNotFound)
                    let replace = NSMutableAttributedString(attributedString: document.text)
                    replace.replaceCharacters(in: found, with: "PAGE-REPLACED")
                    replace.replaceCharacters(in: NSRange(location: found.location, length: "PAGE-REPLACED".utf16.count), with: searchString)
                    XCTAssertEqual(replace.string, document.text.string)
                    timings["findReplaceRoundTripSeconds"] = Date().timeIntervalSince(findStart)

                    let editStart = Date()
                    let editStorage = NSTextStorage(attributedString: document.text)
                    let editRange = NSRange(location: 0, length: min(editStorage.length, 12))
                    let originalEdit = editStorage.attributedSubstring(from: editRange)
                    editStorage.replaceCharacters(in: editRange, with: "Edited text")
                    editStorage.replaceCharacters(in: NSRange(location: 0, length: "Edited text".utf16.count), with: originalEdit)
                    XCTAssertEqual(editStorage.string, document.text.string)
                    timings["editingRoundTripSeconds"] = Date().timeIntervalSince(editStart)

                    let saveStart = Date()
                    try BOLDWriterDocument.packageWrapper(text: document.text, metadata: document.metadata)
                        .write(to: fixtureURL, options: .atomic, originalContentsURL: fixtureURL)
                    timings["saveSeconds"] = Date().timeIntervalSince(saveStart)

                    let paginationStart = Date()
                    try autoreleasepool {
                        let pdfData = try PDFExporter.data(from: document.text, settings: document.metadata.page, sections: document.metadata.sections)
                        let productionPDF = try XCTUnwrap(PDFDocument(data: pdfData))
                        XCTAssertEqual(productionPDF.pageCount, pageCount, "Fixture page count changed for size \(pageCount)")
                        XCTAssertTrue(productionPDF.string?.contains("PAGE-0") == true)
                    }
                    timings["fullPaginationAndPDFParseSeconds"] = Date().timeIntervalSince(paginationStart)

                    let exportStart = Date()
                    _ = try ExportService.write(.pdf, document: document, to: pdfURL)
                    let reopenedPDF = try XCTUnwrap(PDFDocument(url: pdfURL))
                    XCTAssertEqual(reopenedPDF.pageCount, pageCount)
                    XCTAssertTrue(reopenedPDF.string?.contains("PAGE-\(pageCount - 1)") == true)
                    timings["PDFExportAndIndependentReopenSeconds"] = Date().timeIntervalSince(exportStart)

                    let reopenStart = Date()
                    let reopened = try BOLDWriterDocument(fileWrapper: FileWrapper(url: fixtureURL), contentType: .boldWriterDocument)
                    XCTAssertEqual(reopened.text.string, fixture.string)
                    XCTAssertEqual(reopened.metadata.title, metadata.title)
                    timings["saveReopenAndIntegrityCheckSeconds"] = Date().timeIntervalSince(reopenStart)
                }
                sampler.stop()
                let peak = sampler.peakBytes
                let afterClose = Self.residentBytes()
                postCloseRSS.append(afterClose)
                samples.append([
                    "repetition": repetition,
                    "timings": timings,
                    "rssBeforeBytes": rssBefore,
                    "rssPeakBytes": peak,
                    "rssAfterDocumentCloseBytes": afterClose,
                    "pdfBytes": (try? FileManager.default.attributesOfItem(atPath: pdfURL.path)[.size] as? NSNumber)?.intValue ?? 0
                ])
                try? FileManager.default.removeItem(at: pdfURL)
            }
            let finalOpen = try BOLDWriterDocument(fileWrapper: FileWrapper(url: fixtureURL), contentType: .boldWriterDocument)
            XCTAssertEqual(finalOpen.text.string, fixture.string)
            sizeResults.append([
                "pages": pageCount,
                "fixture": "synthetic explicit form-feed page breaks; formatted heading and body paragraphs",
                "characters": fixture.length,
                "words": DocumentAnalysis.statistics(for: fixture.string).words,
                "samples": samples,
                "timingSummarySeconds": Self.timingSummary(samples),
                "postCloseRSSMedianBytes": Self.median(postCloseRSS)
            ])
            let partial = Self.report(host: host, started: started, sizes: sizeResults)
            let bytes = try JSONSerialization.data(withJSONObject: partial, options: [.prettyPrinted, .sortedKeys])
            try FileManager.default.createDirectory(at: reportURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bytes.write(to: reportURL, options: .atomic)
            print("BOLD_PERFORMANCE_MATRIX pages=\(pageCount) repetitions=\(repetitions) rss_peak_bytes=\(samples.compactMap { $0["rssPeakBytes"] as? UInt64 }.max() ?? 0)")
        }
        XCTAssertEqual(sizeResults.compactMap { $0["pages"] as? Int }, sizes)
    }

    private static func report(host: String, started: String, sizes: [[String: Any]]) -> [String: Any] {
        [
            "startedAt": started,
            "host": host,
            "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
            "hardwareModel": hardwareModel(),
            "architecture": architecture(),
            "processorCount": ProcessInfo.processInfo.processorCount,
            "physicalMemoryBytes": ProcessInfo.processInfo.physicalMemory,
            "configuration": "XCTest Debug, production PDFExporter, three repetitions per size; all documents and exports disposable",
            "gui3DPerSize": "not measured by this XCTest; see separate native GUI acceptance for the 391-page real project",
            "sizes": sizes
        ]
    }

    private static func makeFixture(pages: Int) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let bodyFont = NSFont.systemFont(ofSize: 10)
        let headingFont = NSFont.boldSystemFont(ofSize: 15)
        for page in 0..<pages {
            if page > 0 { result.append(NSAttributedString(string: "\u{000C}", attributes: [.font: bodyFont])) }
            let heading = NSAttributedString(
                string: "CHAPTER \(page + 1) — PAGE-\(page)\n",
                attributes: [.font: headingFont, .boldWriterStyle: WriterStyle.heading2.rawValue]
            )
            result.append(heading)
            for paragraph in 0..<3 {
                let body = "Page \(page) paragraph \(paragraph). The manuscript fixture contains ordinary prose, punctuation, typographic quotation marks, and repeatable search targets. Its fixed break keeps page identity deterministic while exercising attributed-text pagination and export.\n"
                result.append(NSAttributedString(string: body, attributes: [.font: bodyFont]))
            }
        }
        return result
    }

    nonisolated private static func residentBytes() -> UInt64 {
        var info = proc_taskinfo()
        let read = proc_pidinfo(getpid(), PROC_PIDTASKINFO, 0, &info, Int32(MemoryLayout<proc_taskinfo>.size))
        return read == MemoryLayout<proc_taskinfo>.size ? UInt64(info.pti_resident_size) : 0
    }

    private static func median(_ values: [UInt64]) -> UInt64 {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    private static func timingSummary(_ samples: [[String: Any]]) -> [String: [String: Double]] {
        let keys = Set(samples.compactMap { ($0["timings"] as? [String: Double])?.keys }.flatMap { $0 })
        return Dictionary(uniqueKeysWithValues: keys.map { key in
            let values = samples.compactMap { ($0["timings"] as? [String: Double])?[key] }.sorted()
            return (key, ["median": values.isEmpty ? 0 : values[values.count / 2], "min": values.first ?? 0, "max": values.last ?? 0])
        })
    }

    private static func hardwareModel() -> String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "unavailable" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 else { return "unavailable" }
        return String(cString: bytes)
    }

    private static func architecture() -> String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "unknown"
        #endif
    }

    private final class ResidentMemorySampler {
        private let queue = DispatchQueue(label: "BOLDWriter.PerformanceMemorySampler")
        private let lock = NSLock()
        private var timer: DispatchSourceTimer?
        private var recordedPeak: UInt64 = 0
        var peakBytes: UInt64 { lock.lock(); defer { lock.unlock() }; return recordedPeak }

        func start() {
            sample()
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .now() + .milliseconds(20), repeating: .milliseconds(20))
            source.setEventHandler { [weak self] in self?.sample() }
            timer = source
            source.resume()
        }

        func stop() {
            timer?.cancel()
            timer = nil
            sample()
        }

        private func sample() {
            let current = ManuscriptPerformanceMatrixTests.residentBytes()
            lock.lock()
            recordedPeak = max(recordedPeak, current)
            lock.unlock()
        }
    }
}
