import AppKit
import Foundation
import XCTest
@testable import BOLDWriter

@MainActor
final class NamedStylePerformanceTests: XCTestCase {
    private let styleCount = 64
    private let runCount = 5_000
    private let repetitions = 3

    func testNamedStyleCopyPreservesDependencies() throws {
        let source = WordParagraphStyle(
            styleID: "PerformanceStyle",
            name: "Performance Style",
            dependencies: [
                WordStyleDependency(kind: .paragraph, styleID: "Base", name: "Base")
            ]
        )
        let copy = try XCTUnwrap(source.copy() as? WordParagraphStyle)

        XCTAssertEqual(copy, source)
        XCTAssertEqual(copy.dependencies.map(\.styleID), ["Base"])
    }

    func testMeasureNamedStyleDocumentOpenAndAttributedCopy() throws {
        guard let outputPath = ProcessInfo.processInfo.environment["BOLD_NAMED_STYLE_PERFORMANCE_OUTPUT"],
              !outputPath.isEmpty else {
            throw XCTSkip("Set BOLD_NAMED_STYLE_PERFORMANCE_OUTPUT to run the disposable named-style performance benchmark.")
        }

        let definitions = (0..<styleCount).map { index in
            NamedStyleDefinition(styleID: "PerformanceStyle\(index)", name: "Performance Style \(index)")
        }
        let dependenciesByStyle = definitions.map { definition in
            let dependencies = definitions.filter { $0.styleID != definition.styleID }.map {
                WordStyleDependency(kind: .paragraph, styleID: $0.styleID, name: $0.name)
            }
            return WordParagraphStyle(
                styleID: definition.styleID,
                name: definition.name,
                dependencies: dependencies
            )
        }

        let text = NSMutableAttributedString(string: String(repeating: "P\n", count: runCount))
        for index in 0..<runCount {
            text.addAttribute(
                .boldWriterParagraphStyle,
                value: dependenciesByStyle[index % styleCount],
                range: NSRange(location: index * 2, length: 1)
            )
        }

        var metadata = DocumentMetadata(title: "Synthetic named-style performance fixture")
        metadata.namedStyles = definitions
        let package = try BOLDWriterDocument.packageWrapper(text: text, metadata: metadata)

        var openMilliseconds: [Double] = []
        for _ in 0..<repetitions {
            try autoreleasepool {
                let start = ProcessInfo.processInfo.systemUptime
                let reopened = try BOLDWriterDocument(fileWrapper: package, contentType: .boldWriterDocument)
                openMilliseconds.append((ProcessInfo.processInfo.systemUptime - start) * 1_000)
                XCTAssertEqual(reopened.text.string, text.string)
                XCTAssertEqual(reopened.metadata.namedStyleRuns?.count, runCount)
            }
        }

        var copyMilliseconds: [Double] = []
        for _ in 0..<repetitions {
            try autoreleasepool {
                let start = ProcessInfo.processInfo.systemUptime
                let copy = text.copy() as! NSAttributedString
                copyMilliseconds.append((ProcessInfo.processInfo.systemUptime - start) * 1_000)
                XCTAssertEqual(copy.length, text.length)
                XCTAssertEqual(copy.string, text.string)
            }
        }

        func summary(_ values: [Double]) -> [String: Double] {
            let sorted = values.sorted()
            return ["median": sorted[sorted.count / 2], "min": sorted[0], "max": sorted[sorted.count - 1]]
        }

        let result: [String: Any] = [
            "startedAt": ISO8601DateFormatter().string(from: Date()),
            "host": ProcessInfo.processInfo.hostName,
            "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
            "architecture": "arm64",
            "configuration": "XCTest Debug; synthetic native package; no user documents",
            "fixture": ["paragraphRuns": runCount, "styleDefinitions": styleCount, "characters": text.length],
            "repetitions": repetitions,
            "documentOpenMilliseconds": summary(openMilliseconds),
            "attributedTextCopyMilliseconds": summary(copyMilliseconds)
        ]
        let output = URL(fileURLWithPath: outputPath).standardizedFileURL
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: output, options: .atomic)
        print("BOLD_NAMED_STYLE_PERFORMANCE open_ms=\(summary(openMilliseconds)["median"] ?? 0) copy_ms=\(summary(copyMilliseconds)["median"] ?? 0)")
    }
}
