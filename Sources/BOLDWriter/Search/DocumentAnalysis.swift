import AppKit
import Foundation

enum LargeDocumentPolicy {
    static let automaticPaginationCharacterLimit =
        1_000_000

    static func isLarge(
        textLength: Int
    ) -> Bool {
        max(0, textLength)
            >= automaticPaginationCharacterLimit
    }

    static func initialPrintLayout(
        textLength: Int
    ) -> Bool {
        !isLarge(
            textLength:
                textLength
        )
    }

    static func initialNavigationVisible(
        textLength: Int
    ) -> Bool {
        !isLarge(
            textLength:
                textLength
        )
    }

    static func shouldBuildOutlineAutomatically(
        textLength: Int,
        navigationVisible: Bool
    ) -> Bool {
        navigationVisible
            || !isLarge(
                textLength:
                    textLength
            )
    }

    static func effectivePrintLayout(
        requested: Bool,
        textLength: Int
    ) -> Bool {
        requested
            && !isLarge(
                textLength:
                    textLength
            )
    }

    static func shouldUseViewportHitTesting(
        textLength: Int
    ) -> Bool {
        !isLarge(
            textLength:
                textLength
        )
    }

    static func allowsLiveProofing(
        textLength: Int
    ) -> Bool {
        !isLarge(
            textLength:
                textLength
        )
    }
}

enum DocumentAnalysis {
    static func statistics(for string: String, headingCount: Int = 0) -> DocumentStatistics {
        let words = string.split { $0.isWhitespace || $0.isPunctuation }.count
        let paragraphs = string.isEmpty ? 0 : string.split(separator: "\n", omittingEmptySubsequences: false).count
        return DocumentStatistics(
            words: words,
            characters: string.count,
            charactersWithoutSpaces: string.filter { !$0.isWhitespace }.count,
            paragraphs: paragraphs,
            estimatedMinutes: words == 0 ? 0 : max(1, Int(ceil(Double(words) / 225.0))),
            headings: headingCount
        )
    }

    static func outline(for text: NSAttributedString) -> [OutlineItem] {
        var items: [OutlineItem] = []
        let ns = text.string as NSString
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byParagraphs, .substringNotRequired]) { _, range, _, _ in
            guard range.length > 0 else { return }
            let visible = ns.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.union(.controlCharacters).inverted, range: range)
            guard visible.location != NSNotFound else { return }
            let point = visible.location
            var level: Int?
            var hasNamedStyle = false
            if let raw = text.attribute(.boldWriterStyle, at: point, effectiveRange: nil) as? String,
               let style = WriterStyle(rawValue: raw) {
                hasNamedStyle = true
                level = style.headingLevel
            }
            if !hasNamedStyle, let font = text.attribute(.font, at: point, effectiveRange: nil) as? NSFont,
               font.pointSize >= 17, NSFontManager.shared.traits(of: font).contains(.boldFontMask) {
                level = font.pointSize >= 23 ? 1 : font.pointSize >= 19 ? 2 : 3
            }
            if let level {
                let title = ns.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty { items.append(OutlineItem(title: title, level: level, range: range)) }
            }
        }
        return items
    }

    static func search(
        _ query: String,
        in text: String,
        matchCase: Bool = false,
        wholeWord: Bool = false,
        regularExpression: Bool = false,
        limit: Int = 1_000
    ) -> [SearchResult] {
        guard let search = try? DocumentSearch(
            query, matchCase: matchCase, wholeWord: wholeWord,
            regularExpression: regularExpression
        ) else { return [] }
        return search.results(in: text, limit: limit)
    }

    static func currentResultIndex(
        in results: [SearchResult],
        selection: NSRange
    ) -> Int? {
        results.firstIndex {
            $0.range.location == selection.location
                && $0.range.length == selection.length
        }
    }

    static func nextResult(
        in results: [SearchResult],
        selection: NSRange
    ) -> SearchResult? {
        guard !results.isEmpty else { return nil }

        if let current = currentResultIndex(
            in: results,
            selection: selection
        ) {
            return results[(current + 1) % results.count]
        }

        let location = selection.location

        return results.first {
            $0.range.location >= location
        } ?? results.first
    }

    static func previousResult(
        in results: [SearchResult],
        selection: NSRange
    ) -> SearchResult? {
        guard !results.isEmpty else { return nil }

        if let current = currentResultIndex(
            in: results,
            selection: selection
        ) {
            let index =
                current == 0
                    ? results.count - 1
                    : current - 1

            return results[index]
        }

        let location = selection.location

        return results.last {
            $0.range.location < location
        } ?? results.last
    }

    static func paragraphRange(at location: Int, in string: String) -> NSRange {
        let ns = string as NSString
        guard ns.length > 0 else { return NSRange(location: 0, length: 0) }
        return ns.paragraphRange(for: NSRange(location: min(max(0, location), ns.length - 1), length: 0))
    }

    static func sectionRange(at location: Int, in text: NSAttributedString) -> NSRange {
        let outline = outline(for: text)
        let startItem = outline.last { $0.range.location <= location }
        let start = startItem?.range.location ?? 0
        let startLevel = startItem?.level ?? 0
        let next = startItem == nil
            ? outline.first
            : outline.first { $0.range.location > start && $0.level <= startLevel }
        return NSRange(location: start, length: (next?.range.location ?? text.length) - start)
    }
}

/// A compiled query shared by navigation and replacement, so regex options and
/// UTF-16 offsets are identical in every Find and Replace operation.
struct DocumentSearch {
    let regularExpression: Bool
    private let expression: NSRegularExpression?

    init(
        _ query: String,
        matchCase: Bool = false,
        wholeWord: Bool = false,
        regularExpression: Bool = false
    ) throws {
        self.regularExpression = regularExpression
        guard !query.isEmpty else { expression = nil; return }
        let pattern = regularExpression ? query : NSRegularExpression.escapedPattern(for: query)
        // Unicode-aware boundaries retain combining marks and avoid treating
        // punctuation at the ends of literal queries as word characters.
        let bounded = wholeWord
            ? "(?<![\\p{L}\\p{M}\\p{N}_])(?:\(pattern))(?![\\p{L}\\p{M}\\p{N}_])"
            : pattern
        expression = try NSRegularExpression(
            pattern: bounded, options: matchCase ? [] : [.caseInsensitive]
        )
    }

    func results(in text: String, limit: Int = 1_000) -> [SearchResult] {
        guard let expression, limit > 0 else { return [] }
        let source = text as NSString
        var results: [SearchResult] = []
        expression.enumerateMatches(in: text, range: NSRange(location: 0, length: source.length)) { match, _, stop in
            guard let match else { return }
            results.append(Self.result(for: match.range, in: source))
            if results.count >= limit { stop.pointee = true }
        }
        return results
    }

    /// Navigation searches the whole manuscript even when the sidebar only
    /// displays a bounded list. Enumeration stops once the next match is found.
    func navigationResult(in text: String, selection: NSRange, previous: Bool = false) -> SearchResult? {
        guard let expression else { return nil }
        let source = text as NSString
        var first: NSRange?
        var last: NSRange?
        var target: NSRange?
        expression.enumerateMatches(in: text, range: NSRange(location: 0, length: source.length)) { match, _, stop in
            guard let range = match?.range else { return }
            if first == nil { first = range }
            last = range
            if previous {
                if range.location < selection.location {
                    target = range
                } else if target != nil {
                    stop.pointee = true
                }
            } else if range.location >= selection.location, range != selection {
                target = range
                stop.pointee = true
            }
        }
        guard let range = target ?? (previous ? last : first) else { return nil }
        return Self.result(for: range, in: source)
    }

    private static func result(for range: NSRange, in source: NSString) -> SearchResult {
        let start = max(0, range.location - 45)
        let end = min(source.length, NSMaxRange(range) + 70)
        // Keep emoji and combining characters intact at snippet boundaries.
        let contextRange = source.rangeOfComposedCharacterSequences(
            for: NSRange(location: start, length: end - start)
        )
        let context = source.substring(with: contextRange)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        return SearchResult(range: range, context: context)
    }

    func replacement(in text: String, range: NSRange, with template: String) -> SearchReplacement? {
        guard let expression else { return nil }
        var replacement: SearchReplacement?
        expression.enumerateMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length)) { match, _, stop in
            guard let match else { return }
            if match.range == range {
                replacement = SearchReplacement(
                    range: range,
                    text: regularExpression
                        ? expression.replacementString(for: match, in: text, offset: 0, template: template)
                        : template
                )
            }
            if match.range.location >= range.location { stop.pointee = true }
        }
        return replacement
    }

    func replacements(in text: String, with template: String, limit: Int = Int.max) -> [SearchReplacement] {
        guard let expression, limit > 0 else { return [] }
        var replacements: [SearchReplacement] = []
        expression.enumerateMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length)) { match, _, stop in
            guard let match else { return }
            let replacement = regularExpression
                ? expression.replacementString(for: match, in: text, offset: 0, template: template)
                : template
            replacements.append(SearchReplacement(range: match.range, text: replacement))
            if replacements.count >= limit { stop.pointee = true }
        }
        return replacements
    }
}

struct SearchReplacement: Equatable {
    var range: NSRange
    var text: String
}
