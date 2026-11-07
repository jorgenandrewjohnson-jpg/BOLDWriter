import AppKit
import Foundation

struct BOLDAuditHeading {
    var level: Int
    var range: NSRange
}

struct BOLDAuditField {
    var id: UUID
    var instruction: String
    var visibleValue: String
    var range: NSRange
}

struct BOLDAuditLink {
    var target: String
    var range: NSRange
}

/// The small, immutable payload copied from the editor before background work.
/// It contains source text once plus only semantic runs needed by the audit.
struct BOLDBookAuditSnapshot {
    var text: String
    var semanticQuoteRanges: [NSRange]
    var headings: [BOLDAuditHeading]
    var fields: [BOLDAuditField]
    var links: [BOLDAuditLink]
    var footnoteMarkers: [Footnote]?
    var footnoteError: String?
}

struct BOLDAuditMetadataSnapshot {
    var sections: [DocumentSection]
    var bookmarks: [DocumentBookmark]
    var tableOfContents: [PublishingTOCSettings]
    var footnotes: [Footnote]?
    var rules: [BOLDConsistencyRule]
}

struct BOLDAuditOverview {
    var words: Int
    var sectionCount: Int
    var shortestSectionWords: Int
    var longestSectionWords: Int
}

struct BOLDAuditLocationIndex {
    private var lineStarts = [0]
    private var paragraphStarts = [0]

    init(_ text: String) {
        self.init(text, shouldCancel: { false })!
    }

    init?(_ text: String, shouldCancel: () -> Bool) {
        let source = text as NSString
        var index = 0
        var consecutiveNewlines = 0
        while index < source.length {
            if index.isMultiple(of: 4_096) && shouldCancel() { return nil }
            let unit = source.character(at: index)
            if unit == 10 || unit == 13 {
                if unit == 13 && index + 1 < source.length && source.character(at: index + 1) == 10 {
                    index += 1
                }
                let next = index + 1
                lineStarts.append(next)
                consecutiveNewlines += 1
                if consecutiveNewlines == 2 { paragraphStarts.append(next) }
            } else if !isWhitespace(unit) {
                consecutiveNewlines = 0
            }
            index += 1
        }
    }

    func describe(_ location: Int) -> String {
        let safe = max(0, location)
        let line = upperBound(lineStarts, safe)
        let paragraph = upperBound(paragraphStarts, safe)
        return "Paragraph \(paragraph) · line \(line) · UTF-16 offset \(safe)"
    }

    private func upperBound(_ values: [Int], _ target: Int) -> Int {
        var low = 0
        var high = values.count
        while low < high {
            let middle = low + (high - low) / 2
            if values[middle] <= target { low = middle + 1 } else { high = middle }
        }
        return max(1, low)
    }

    private func isWhitespace(_ unit: unichar) -> Bool {
        guard let scalar = UnicodeScalar(unit) else { return false }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }
}

enum BOLDBookAuditAnalyzer {
    static func snapshot(from storage: NSAttributedString) -> BOLDBookAuditSnapshot {
        let source = storage.string as NSString
        let headings = semanticHeadings(in: storage)
        var fields: [BOLDAuditField] = []
        if source.length > 0 {
            storage.enumerateAttribute(.boldWriterField, in: NSRange(location: 0, length: source.length)) { value, range, _ in
                guard let field = value as? WordField else { return }
                fields.append(BOLDAuditField(
                    id: field.id,
                    instruction: field.instruction,
                    visibleValue: range.location < source.length ? source.substring(with: range) : "",
                    range: range
                ))
            }
        }

        var links: [BOLDAuditLink] = []
        if source.length > 0 {
            storage.enumerateAttribute(.link, in: NSRange(location: 0, length: source.length)) { value, range, _ in
                guard let value else { return }
                let target: String
                if let url = value as? URL { target = url.absoluteString }
                else if let url = value as? NSURL { target = url.absoluteString ?? "" }
                else { target = String(describing: value) }
                links.append(BOLDAuditLink(target: target, range: range))
            }
        }

        let markerResult = Result { try Footnotes.records(in: storage) }
        return BOLDBookAuditSnapshot(
            text: storage.string,
            semanticQuoteRanges: BOLDQuotationAnalyzer.semanticRanges(in: storage),
            headings: headings,
            fields: fields,
            links: links,
            footnoteMarkers: try? markerResult.get(),
            footnoteError: markerResult.failureDescription
        )
    }

    static func semanticHeadings(in storage: NSAttributedString) -> [BOLDAuditHeading] {
        let source = storage.string as NSString
        var headings: [BOLDAuditHeading] = []
        var cursor = 0
        while cursor < source.length {
            let paragraph = source.paragraphRange(for: NSRange(location: cursor, length: 0))
            let visible = source.rangeOfCharacter(
                from: CharacterSet.whitespacesAndNewlines.union(.controlCharacters).inverted,
                range: paragraph
            )
            if visible.location != NSNotFound,
               let level = headingLevel(in: storage, at: visible.location) {
                let end = NSMaxRange(paragraph)
                var contentEnd = end
                while contentEnd > visible.location,
                      isWhitespace(source.character(at: contentEnd - 1)) {
                    contentEnd -= 1
                }
                if contentEnd > visible.location {
                    headings.append(BOLDAuditHeading(
                        level: level,
                        range: NSRange(location: visible.location, length: contentEnd - visible.location)
                    ))
                }
            }
            cursor = max(cursor + 1, NSMaxRange(paragraph))
        }

        return headings
    }

    private static func isWhitespace(_ unit: unichar) -> Bool {
        guard let scalar = UnicodeScalar(unit) else { return false }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }

    static func analyze(
        _ snapshot: BOLDBookAuditSnapshot,
        metadata: BOLDAuditMetadataSnapshot,
        shouldCancel: () -> Bool
    ) -> [BOLDConsistencyFinding]? {
        let source = snapshot.text as NSString
        guard let quote = BOLDQuotationAnalyzer.analyze(
            string: snapshot.text,
            semanticRanges: snapshot.semanticQuoteRanges,
            shouldCancel: shouldCancel
        ) else { return nil }
        guard let scanFindings = BOLDConsistencyScanner().scanCancellable(
            snapshot.text,
            rules: metadata.rules,
            quotationRanges: quote.protectedRanges,
            maximumFindings: 1_000,
            shouldCancel: shouldCancel
        ) else { return nil }

        var findings = scanFindings
        func add(_ category: BOLDConsistencyCategory, _ explanation: String, _ range: NSRange, _ confidence: Double = 1) {
            guard findings.count < 1_500 else { return }
            guard range.location >= 0, range.location <= source.length,
                  range.length >= 0, range.length <= source.length - range.location else { return }
            findings.append(BOLDConsistencyFinding(
                category: category,
                explanation: explanation,
                firstRange: range,
                secondRange: nil,
                confidence: confidence,
                isInsideQuotationText: Self.intersectsSorted(quote.protectedRanges, range)
            ))
        }

        for range in quote.uncertainRanges {
            if shouldCancel() { return nil }
            add(.uncertainQuotation, "Quotation boundaries are incomplete or mismatched. Rule matches in this span were protected from original-prose-only checks; verify source context.", range, 0.5)
        }

        var sectionBoundaries = Set<Int>()
        for section in metadata.sections {
            if shouldCancel() { return nil }
            guard !sectionBoundaries.insert(section.location).inserted else {
                add(.duplicateSectionBoundary, "Two saved section page configurations start at the same manuscript offset.", NSRange(location: section.location, length: 0))
                continue
            }
        }

        let headings = snapshot.headings.sorted { $0.range.location < $1.range.location }
        var nextTopLevelBoundary = Array(repeating: source.length, count: headings.count)
        var nextTopLevelLocation = source.length
        if !headings.isEmpty {
            for index in headings.indices.reversed() {
                nextTopLevelBoundary[index] = nextTopLevelLocation
                if headings[index].level == 1 { nextTopLevelLocation = headings[index].range.location }
            }
        }
        var previousLevel = 0
        for (index, heading) in headings.enumerated() {
            if shouldCancel() { return nil }
            if previousLevel > 0 && heading.level > previousLevel + 1 {
                add(.headingHierarchy, "Heading level skips from Heading \(previousLevel) to Heading \(heading.level). Review the outline hierarchy.", heading.range)
            }
            previousLevel = heading.level

            guard heading.level == 1 else { continue }
            let boundary = nextTopLevelBoundary[index]
            let end = min(max(heading.range.location, boundary), source.length)
            guard end > NSMaxRange(heading.range) else {
                add(.emptySection, "This top-level section has no body text before the next top-level section.", heading.range)
                continue
            }
            let body = source.substring(from: NSMaxRange(heading.range), to: end)
            let hasBody = body.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.inverted) != nil
            if !hasBody {
                add(.emptySection, "This top-level section has no body text before the next top-level section.", heading.range)
            }
        }

        let topLevel = headings.filter { $0.level == 1 }
        if topLevel.count >= 2 {
            var lengths: [(Int, NSRange)] = []
            var sectionRanges: [NSRange] = []
            for (index, heading) in topLevel.enumerated() {
                if shouldCancel() { return nil }
                let end = index + 1 < topLevel.count ? topLevel[index + 1].range.location : source.length
                let bodyStart = min(NSMaxRange(heading.range), end)
                let bodyRange = NSRange(location: bodyStart, length: end - bodyStart)
                guard let words = wordCount(source, range: bodyRange, shouldCancel: shouldCancel) else { return nil }
                lengths.append((words, heading.range))
                sectionRanges.append(bodyRange)
                if words >= 5_000 {
                    add(.argumentStructure, "This section is unusually long (\(words) words). Consider whether it needs division; the audit does not decide where to split it.", heading.range, 0.4)
                }
            }
            if let conclusionMarkers = try? NSRegularExpression(pattern: "(?i)\\b(in conclusion|therefore|thus|we conclude|I conclude)\\b") {
                for (_, range) in sectionRanges.enumerated() {
                    if shouldCancel() { return nil }
                    guard let words = wordCount(source, range: range, shouldCancel: shouldCancel), words >= 500 else { continue }
                    let matches = conclusionMarkers.matches(in: snapshot.text, range: range)
                    for marker in matches.prefix(4) {
                        guard marker.range.location - range.location < max(1_500, range.length / 5) else { continue }
                        add(.argumentStructure, "A conclusion marker appears near the start of a long section. Review whether the supporting discussion is easy to find; this is a structural prompt, not a judgment about the argument.", marker.range, 0.35)
                    }
                }
            }
            let sortedLengths = lengths.map(\.0).sorted()
            let shortest = sortedLengths.first ?? 0
            let longest = sortedLengths.last ?? 0
            if longest - shortest >= 1_200 && Double(longest) >= Double(max(1, shortest)) * 4,
               let longestSection = lengths.max(by: { $0.0 < $1.0 }) {
                add(.sectionLengthBalance, "The longest top-level section has \(longest) words and the shortest has \(shortest). Review whether the difference is intentional.", longestSection.1, 0.45)
            }
        }

        var bookmarkValidationFailed = false
        do { try DocumentBookmarks.validate(metadata.bookmarks, textLength: source.length) }
        catch { bookmarkValidationFailed = true }
        if bookmarkValidationFailed {
            add(.brokenCrossReference, "Saved bookmark targets contain invalid, duplicate, or out-of-range values; internal references may not resolve.", NSRange(location: 0, length: min(1, source.length)))
        }
        let bookmarkNames = Set(metadata.bookmarks.map { $0.name.lowercased() })
        var fieldIDs = Set<UUID>()
        for field in snapshot.fields {
            if shouldCancel() { return nil }
            guard fieldIDs.insert(field.id).inserted else {
                add(.brokenCrossReference, "Two document fields share the same field identifier.", field.range)
                continue
            }
            let components = field.instruction.split(whereSeparator: { $0.isWhitespace })
            guard let command = components.first?.uppercased() else { continue }
            if command == "REF" || command == "PAGEREF" {
                guard components.count > 1 else {
                    add(.brokenCrossReference, "The cross-reference field has no target bookmark name.", field.range)
                    continue
                }
                let target = components[1].trimmingCharacters(in: CharacterSet(charactersIn: "\\{}\""))
                if !bookmarkNames.contains(target.lowercased()) {
                    add(.brokenCrossReference, "The \(command) field refers to ‘\(target)’, but that bookmark does not exist.", field.range)
                }
            } else if command == "TOC" {
                let settings = metadata.tableOfContents.first { $0.fieldID == field.id }
                if settings == nil, !metadata.tableOfContents.isEmpty {
                    add(.malformedTableOfContents, "This contents field has no matching saved publishing settings.", field.range)
                } else if field.visibleValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    add(.malformedTableOfContents, "This contents field currently has no visible entries. Confirm it has been refreshed from the document headings.", field.range, 0.75)
                }
            }
        }
        let fieldIDsInDocument = Set(snapshot.fields.map(\.id))
        for settings in metadata.tableOfContents where !fieldIDsInDocument.contains(settings.fieldID) {
            if shouldCancel() { return nil }
            add(.malformedTableOfContents, "Saved table-of-contents settings no longer point to a field in the manuscript.", NSRange(location: 0, length: min(1, source.length)))
        }

        for link in snapshot.links {
            if shouldCancel() { return nil }
            guard !link.target.isEmpty else {
                add(.unresolvedLink, "This document link has an empty target.", link.range)
                continue
            }
            if link.target.hasPrefix("#") {
                let name = String(link.target.dropFirst()).lowercased()
                if !bookmarkNames.contains(name) {
                    add(.unresolvedLink, "This internal link points to a missing bookmark ‘\(name)’.", link.range)
                }
            } else if let components = URLComponents(string: link.target),
                      let scheme = components.scheme?.lowercased() {
                if ["http", "https"].contains(scheme) && components.host == nil {
                    add(.unresolvedLink, "This web link has no host name.", link.range)
                }
            } else {
                add(.unresolvedLink, "This link target is not a valid absolute URL or internal bookmark.", link.range)
            }
        }

        if let error = snapshot.footnoteError {
            add(.unreferencedFootnote, "A footnote reference is malformed or has no saved footnote body: \(error)", NSRange(location: 0, length: min(1, source.length)))
        } else if let saved = metadata.footnotes, let markers = snapshot.footnoteMarkers {
            let markerIDs = Set(markers.map(\.id))
            for note in saved where !markerIDs.contains(note.id) {
                if shouldCancel() { return nil }
                add(.unreferencedFootnote, "Saved footnote body ‘\(note.id.uuidString.prefix(8))’ has no reference marker in the manuscript.", NSRange(location: min(max(0, note.location), source.length), length: 0))
            }
        }

        guard !shouldCancel() else { return nil }
        return findings.sorted {
            let left = $0.auditConfidence.sortOrder
            let right = $1.auditConfidence.sortOrder
            if left != right { return left < right }
            return $0.firstRange.location < $1.firstRange.location
        }
    }

    static func overview(for text: String, shouldCancel: () -> Bool) -> BOLDAuditOverview? {
        let source = text as NSString
        let pattern = try? NSRegularExpression(pattern: "(?i)^\\s*(chapter|part|section)\\s+[^\\n]{1,90}$")
        var sections: [Int] = []
        var count = 0
        var lineStart = 0
        var words = 0
        while lineStart < source.length {
            if lineStart.isMultiple(of: 16_384) && shouldCancel() { return nil }
            let lineRange = source.lineRange(for: NSRange(location: lineStart, length: 0))
            guard let lineWords = wordCount(source, range: lineRange, shouldCancel: shouldCancel) else { return nil }
            words += lineWords
            if pattern?.firstMatch(in: text, range: lineRange) != nil {
                sections.append(count)
                count = 0
            } else {
                count += lineWords
            }
            lineStart = max(lineStart + 1, NSMaxRange(lineRange))
        }
        sections.append(count)
        sections = sections.filter { $0 > 0 }
        guard !shouldCancel() else { return nil }
        return BOLDAuditOverview(
            words: words,
            sectionCount: sections.count,
            shortestSectionWords: sections.min() ?? 0,
            longestSectionWords: sections.max() ?? 0
        )
    }

    private static func headingLevel(in text: NSAttributedString, at location: Int) -> Int? {
        let raw = text.attribute(.boldWriterStyle, at: location, effectiveRange: nil) as? String
        if let level = raw.flatMap(WriterStyle.init(rawValue:))?.headingLevel { return level }
        if let named = text.attribute(.boldWriterParagraphStyle, at: location, effectiveRange: nil) as? WordParagraphStyle {
            let id = named.styleID.lowercased().replacingOccurrences(of: " ", with: "")
            if id.hasPrefix("heading"), let level = Int(id.dropFirst("heading".count)), (1...6).contains(level) { return level }
        }
        return nil
    }

    private static let wordRegex = try! NSRegularExpression(pattern: "[\\p{L}\\p{N}]+(?:['’][\\p{L}\\p{N}]+)*")

    private static func wordCount(_ source: NSString, range: NSRange, shouldCancel: () -> Bool = { false }) -> Int? {
        guard range.location >= 0, range.length >= 0, NSMaxRange(range) <= source.length else { return 0 }
        let value = source.substring(with: range)
        var count = 0
        var cancelled = false
        wordRegex.enumerateMatches(in: value, range: NSRange(location: 0, length: (value as NSString).length)) { _, _, stop in
            count += 1
            if count.isMultiple(of: 4_096) && shouldCancel() {
                cancelled = true
                stop.pointee = true
            }
        }
        if cancelled || shouldCancel() { return nil }
        return count
    }

    private static func intersectsSorted(_ ranges: [NSRange], _ target: NSRange) -> Bool {
        var low = 0
        var high = ranges.count
        while low < high {
            let middle = low + (high - low) / 2
            if NSMaxRange(ranges[middle]) <= target.location { low = middle + 1 }
            else { high = middle }
        }
        return low < ranges.count && ranges[low].intersects(target)
    }
}

extension BOLDAuditConfidence {
    var sortOrder: Int {
        switch self {
        case .confirmedStructuralDefect: 0
        case .exactRuleViolation: 1
        case .exactDuplicate: 2
        case .potentialInconsistency: 3
        case .reviewSuggestion: 4
        }
    }
}

enum BOLDAuditReportExporter {
    static func markdown(
        title: String,
        text: String,
        findings: [BOLDConsistencyFinding],
        ignoredCount: Int,
        maximumFindings: Int = 250,
        generatedAt: Date = Date()
    ) -> String {
        let index = BOLDAuditLocationIndex(text)
        let source = text as NSString
        let prioritized = findings.sorted {
            if $0.auditConfidence.sortOrder != $1.auditConfidence.sortOrder {
                return $0.auditConfidence.sortOrder < $1.auditConfidence.sortOrder
            }
            return ($0.secondRange ?? $0.firstRange).location < ($1.secondRange ?? $1.firstRange).location
        }
        let included = Array(prioritized.prefix(max(0, maximumFindings)))
        let formatter = ISO8601DateFormatter()
        var lines = [
            "# Book Audit — \(title)",
            "",
            "Generated locally: \(formatter.string(from: generatedAt))",
            "Findings available: \(findings.count) · Included: \(included.count) · Omitted: \(max(0, findings.count - included.count)) · Ignored: \(ignoredCount)",
            "",
            "Potential dates, names, and similar arguments are review suggestions, not established contradictions.",
            "Citation target checks are unavailable when citation text has no structured source identifier. Pagination-dependent heading checks are omitted unless a verified page map is supplied.",
            ""
        ]
        for (offset, finding) in included.enumerated() {
            let location = finding.secondRange ?? finding.firstRange
            let safe = NSRange(location: max(0, min(location.location, source.length)), length: 0)
            let start = max(0, safe.location - 40)
            let end = min(source.length, max(safe.location, NSMaxRange(location)) + 60)
            let excerpt = source.substring(with: NSRange(location: start, length: end - start))
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            lines.append("## \(offset + 1). \(finding.auditConfidence.rawValue): \(finding.category.rawValue)")
            lines.append("")
            lines.append("- Location: \(index.describe(location.location))")
            lines.append("- Why flagged: \(finding.explanation)")
            lines.append("- Excerpt: `\(excerpt)`")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}

private extension NSString {
    func substring(from start: Int, to end: Int) -> String {
        guard start >= 0, start <= end, end <= length else { return "" }
        return substring(with: NSRange(location: start, length: end - start))
    }
}

private extension Result where Failure == Error {
    var failureDescription: String? {
        if case .failure(let error) = self { return error.localizedDescription }
        return nil
    }
}
