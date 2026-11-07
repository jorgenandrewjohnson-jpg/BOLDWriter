import Foundation
import PDFKit

private struct Dimensions: Codable {
    let widthInches: Double
    let heightInches: Double
}

private struct Issue: Codable {
    let severity: String
    let code: String
    let page: Int?
    let message: String
}

private struct Report: Codable {
    let schemaVersion: Int
    let file: String
    let status: String
    let pageCount: Int
    let mediaInches: Dimensions?
    let trimInches: Dimensions?
    let errors: Int
    let warnings: Int
    let issues: [Issue]
}

private struct Options {
    var filePath = ""
    var trim: (Double, Double)?
    var bleedPoints: Double?
    var minimumPages = 1
    var maximumPages: Int?
    var requireEvenPages = false
    var jsonOutput = false
}

private func usage() {
    print("Usage: Scripts/bold pdf-preflight FILE.pdf [--trim WIDTHxHEIGHT] [--bleed INCHES] [--min-pages N] [--max-pages N] [--require-even-pages] [--json]")
    print("Examples: --trim 6x9 --bleed 0.125 --min-pages 2 --json")
    print("All dimensions are in inches. PDFs are inspected read-only; exit 0=pass, 2=invalid/unreadable, 3=production errors.")
}

private func parse(_ args: [String]) -> Options? {
    var result = Options()
    var cursor = 0
    while cursor < args.count {
        switch args[cursor] {
        case "--json":
            result.jsonOutput = true
            cursor += 1
        case "--trim":
            guard cursor + 1 < args.count else { return nil }
            let parts = args[cursor + 1].lowercased().split(separator: "x", omittingEmptySubsequences: false)
            guard parts.count == 2,
                  let width = Double(parts[0]), let height = Double(parts[1]),
                  width.isFinite, height.isFinite,
                  width > 0, height > 0,
                  width <= 60, height <= 60 else { return nil }
            result.trim = (width * 72, height * 72)
            cursor += 2
        case "--bleed":
            guard cursor + 1 < args.count,
                  let bleed = Double(args[cursor + 1]),
                  bleed.isFinite, bleed > 0, bleed <= 1 else { return nil }
            result.bleedPoints = bleed * 72
            cursor += 2
        case "--min-pages":
            guard cursor + 1 < args.count,
                  let count = Int(args[cursor + 1]), count > 0 else { return nil }
            result.minimumPages = count
            cursor += 2
        case "--max-pages":
            guard cursor + 1 < args.count,
                  let count = Int(args[cursor + 1]), count > 0 else { return nil }
            result.maximumPages = count
            cursor += 2
        case "--require-even-pages":
            result.requireEvenPages = true
            cursor += 1
        default:
            guard !args[cursor].hasPrefix("--"), result.filePath.isEmpty else { return nil }
            result.filePath = args[cursor]
            cursor += 1
        }
    }
    if result.filePath.isEmpty { return nil }
    if let maximum = result.maximumPages, maximum < result.minimumPages { return nil }
    return result
}

private func inches(_ points: Double) -> Double {
    points / 72
}

private func dimension(_ width: Double, _ height: Double) -> Dimensions {
    Dimensions(widthInches: inches(width), heightInches: inches(height))
}

private func emit(_ report: Report, asJSON: Bool) {
    if asJSON {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let encoded = try? encoder.encode(report),
           let text = String(data: encoded, encoding: .utf8) {
            print(text)
        } else {
            fputs("PREFLIGHT_ERROR=Unable to serialize report\n", stderr)
        }
        return
    }

    print("PREFLIGHT_PAGES=\(report.pageCount)")
    if let media = report.mediaInches {
        print(String(format: "PREFLIGHT_MEDIA_INCHES=%.3fx%.3f", media.widthInches, media.heightInches))
    }
    if let trim = report.trimInches {
        print(String(format: "PREFLIGHT_TRIM_INCHES=%.3fx%.3f", trim.widthInches, trim.heightInches))
    }
    print("PREFLIGHT_ERRORS=\(report.errors)")
    print("PREFLIGHT_WARNINGS=\(report.warnings)")
    for issue in report.issues.prefix(40) {
        let detail = issue.page.map { "page \($0): " } ?? ""
        print("PREFLIGHT_\(issue.severity.uppercased())=\(detail)\(issue.code): \(issue.message)")
    }
    print("PREFLIGHT_RESULT=\(report.status)")
}

private func failure(_ status: String, _ file: String, _ code: String, json: Bool) -> Int32 {
    let issue = Issue(severity: "error", code: code, page: nil, message: status)
    emit(Report(schemaVersion: 2, file: file, status: status, pageCount: 0,
                mediaInches: nil, trimInches: nil, errors: 1, warnings: 0,
                issues: [issue]), asJSON: json)
    return 2
}

private func run() -> Int32 {
    let args = Array(CommandLine.arguments.dropFirst())
    if args.count == 1 && (args[0] == "--help" || args[0] == "-h") {
        usage()
        return 0
    }

    guard let options = parse(args) else {
        if !args.contains("--json") { usage() }
        return failure("INVALID_ARGUMENTS", "", "ARGUMENTS", json: args.contains("--json"))
    }

    let url = URL(fileURLWithPath: options.filePath).standardizedFileURL
    guard url.pathExtension.lowercased() == "pdf",
          FileManager.default.fileExists(atPath: url.path),
          let document = PDFDocument(url: url),
          !document.isLocked, document.pageCount > 0 else {
        return failure("UNREADABLE_PDF", url.path, "UNREADABLE_PDF", json: options.jsonOutput)
    }

    var issues: [Issue] = []
    var firstMedia: (Double, Double)?
    var firstTrim: (Double, Double)?
    let tolerance = 0.5

    func add(_ severity: String, _ code: String, _ message: String, page: Int? = nil) {
        issues.append(Issue(severity: severity, code: code, page: page, message: message))
    }

    for index in 0..<document.pageCount {
        let number = index + 1
        guard let page = document.page(at: index) else {
            add("error", "MISSING_PAGE", "PDF page cannot be opened", page: number)
            continue
        }

        let media = page.bounds(for: .mediaBox)
        let trim = page.bounds(for: .trimBox)
        let mediaW = Double(media.width), mediaH = Double(media.height)
        let trimW = Double(trim.width), trimH = Double(trim.height)
        let dimensions = [
            mediaW, mediaH, trimW, trimH,
            Double(media.minX), Double(media.minY),
            Double(trim.minX), Double(trim.minY)
        ]

        guard dimensions.allSatisfy({ $0.isFinite }),
              mediaW > 0, mediaH > 0 else {
            add("error", "INVALID_MEDIA_BOX", "Invalid MediaBox", page: number)
            continue
        }

        guard trimW > 0, trimH > 0 else {
            add("error", "INVALID_TRIM_BOX", "Invalid TrimBox", page: number)
            continue
        }

        if let previous = firstMedia {
            if abs(mediaW - previous.0) > tolerance || abs(mediaH - previous.1) > tolerance {
                add("error", "MIXED_MEDIA_SIZE", "Inconsistent MediaBox size", page: number)
            }
        } else {
            firstMedia = (mediaW, mediaH)
        }

        if let previous = firstTrim {
            if abs(trimW - previous.0) > tolerance || abs(trimH - previous.1) > tolerance {
                add("error", "MIXED_TRIM_SIZE", "Inconsistent TrimBox size", page: number)
            }
        } else {
            firstTrim = (trimW, trimH)
        }

        if let target = options.trim {
            if abs(trimW - target.0) > tolerance || abs(trimH - target.1) > tolerance {
                add("error", "TRIM_MISMATCH", "TrimBox does not match requested trim", page: number)
            }
        }

        let margins = [
            Double(trim.minX - media.minX),
            Double(trim.minY - media.minY),
            Double(media.maxX - trim.maxX),
            Double(media.maxY - trim.maxY)
        ]

        if margins.contains(where: { $0 < -tolerance }) {
            add("error", "TRIM_OUTSIDE_MEDIA", "TrimBox extends outside MediaBox", page: number)
        }

        if let bleed = options.bleedPoints {
            let sides = ["left", "bottom", "right", "top"]
            for (side, margin) in zip(sides, margins) where margin < bleed - tolerance {
                add(
                    "error",
                    "BLEED_INSUFFICIENT",
                    "Insufficient \(side) bleed: \(String(format: "%.3f", inches(margin))) inches",
                    page: number
                )
            }
        }

        if page.rotation % 360 != 0 {
            add("warning", "ROTATED_PAGE", "Nonzero page rotation \(page.rotation)", page: number)
        }
    }

    if document.pageCount < options.minimumPages {
        add("error", "PAGE_COUNT_BELOW_MIN", "Page count below --min-pages")
    }

    if let maximum = options.maximumPages, document.pageCount > maximum {
        add("error", "PAGE_COUNT_ABOVE_MAX", "Page count above --max-pages")
    }

    if options.requireEvenPages && document.pageCount % 2 != 0 {
        add("error", "ODD_PAGE_COUNT", "Odd page count with --require-even-pages")
    }

    let errorCount = issues.filter { $0.severity == "error" }.count
    let warningCount = issues.filter { $0.severity == "warning" }.count
    let status = errorCount == 0 ? "PASS" : "FAIL"

    let report = Report(
        schemaVersion: 2,
        file: url.path,
        status: status,
        pageCount: document.pageCount,
        mediaInches: firstMedia.map { dimension($0.0, $0.1) },
        trimInches: firstTrim.map { dimension($0.0, $0.1) },
        errors: errorCount,
        warnings: warningCount,
        issues: issues
    )

    emit(report, asJSON: options.jsonOutput)
    return errorCount == 0 ? 0 : 3
}

exit(run())
