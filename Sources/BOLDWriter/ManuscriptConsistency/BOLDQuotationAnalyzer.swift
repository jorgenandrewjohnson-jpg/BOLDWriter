import AppKit
import Foundation

struct BOLDQuotationAnalysis {
    var protectedRanges: [NSRange]
    var uncertainRanges: [NSRange]
}

/// Identifies quotation context from native paragraph styles first, then from
/// balanced Unicode quote pairs. Unclosed or mismatched quotes are protected
/// through their local span and reported as uncertain instead of being treated
/// as ordinary author prose.
enum BOLDQuotationAnalyzer {
    private static let matchingOpeners: [unichar: unichar] = [0x201D: 0x201C, 0x2019: 0x2018, 0x00BB: 0x00AB, 0x203A: 0x2039]
    static func analyze(text: NSAttributedString) -> BOLDQuotationAnalysis {
        analyze(string: text.string, semanticRanges: semanticRanges(in: text)) ?? BOLDQuotationAnalysis(protectedRanges: [], uncertainRanges: [])
    }

    static func semanticRanges(in text: NSAttributedString) -> [NSRange] {
        let source = text.string as NSString
        guard source.length > 0 else { return [] }
        var ranges: [NSRange] = []
        var cursor = 0
        while cursor < source.length {
            let paragraph = source.paragraphRange(for: NSRange(location: cursor, length: 0))
            let visible = source.rangeOfCharacter(
                from: CharacterSet.whitespacesAndNewlines.union(.controlCharacters).inverted,
                range: paragraph
            )
            if visible.location != NSNotFound {
                let raw = text.attribute(.boldWriterStyle, at: visible.location, effectiveRange: nil) as? String
                let directStyle = raw.flatMap(WriterStyle.init(rawValue:))
                let named = text.attribute(.boldWriterParagraphStyle, at: visible.location, effectiveRange: nil) as? WordParagraphStyle
                let namedID = named?.styleID.lowercased().replacingOccurrences(of: " ", with: "")
                let quoteStyle = directStyle.map { [.quote, .intenseQuote, .blockQuote].contains($0) } == true
                    || ["quote", "intensequote", "blockquote", "scripturequote"].contains(namedID ?? "")
                if quoteStyle { ranges.append(paragraph) }
            }
            let next = NSMaxRange(paragraph)
            cursor = next > cursor ? next : cursor + 1
        }
        return merged(ranges, limit: source.length)
    }

    static func analyze(
        string: String,
        semanticRanges: [NSRange] = [],
        shouldCancel: () -> Bool = { false }
    ) -> BOLDQuotationAnalysis? {
        let source = string as NSString
        guard source.length > 0 else {
            return shouldCancel() ? nil : BOLDQuotationAnalysis(protectedRanges: [], uncertainRanges: [])
        }

        var protected = semanticRanges
        var uncertain: [NSRange] = []

        struct OpenQuote {
            var opener: unichar
            var closer: unichar
            var location: Int
        }

        var stack: [OpenQuote] = []
        var index = 0
        while index < source.length {
            if index.isMultiple(of: 4_096) && shouldCancel() { return nil }
            let value = source.character(at: index)
            let expectedCloser: unichar?
            switch value {
            case 0x201C: expectedCloser = 0x201D // “ ”
            case 0x2018: expectedCloser = 0x2019 // ‘ ’
            case 0x00AB: expectedCloser = 0x00BB // « »
            case 0x2039: expectedCloser = 0x203A // ‹ ›
            default: expectedCloser = nil
            }

            if let expectedCloser {
                stack.append(OpenQuote(opener: value, closer: expectedCloser, location: index))
                index += 1
                continue
            }

            if value == 0x0022 { // Straight double quotes may nest in curly quotes.
                if stack.last?.closer == value, let opened = stack.popLast() {
                    protected.append(NSRange(location: opened.location, length: index - opened.location + 1))
                } else {
                    stack.append(OpenQuote(opener: value, closer: value, location: index))
                }
                index += 1
                continue
            }

            if value == 0x0027 { // Straight single quote, excluding apostrophes.
                if isApostrophe(in: source, at: index) {
                    index += 1
                    continue
                }
                if stack.last?.closer == value, let opened = stack.popLast() {
                    protected.append(NSRange(location: opened.location, length: index - opened.location + 1))
                } else {
                    stack.append(OpenQuote(opener: value, closer: value, location: index))
                }
                index += 1
                continue
            }

            if let opener = matchingOpeners[value] {
                if stack.last?.opener == opener, let opened = stack.popLast() {
                    protected.append(NSRange(location: opened.location, length: index - opened.location + 1))
                } else if value == 0x2019 && isApostrophe(in: source, at: index) {
                    // Curly apostrophes in contractions and possessives are not quotes.
                } else {
                    let ambiguous = NSRange(location: index, length: 1)
                    protected.append(ambiguous)
                    uncertain.append(ambiguous)
                }
            } else if let last = stack.last, value == last.closer, let opened = stack.popLast() {
                protected.append(NSRange(location: opened.location, length: index - opened.location + 1))
            }
            index += 1
        }

        if let earliest = stack.map(\.location).min() {
            let range = NSRange(location: earliest, length: source.length - earliest)
            protected.append(range)
            uncertain.append(range)
        }

        guard !shouldCancel() else { return nil }
        return BOLDQuotationAnalysis(
            protectedRanges: merged(protected, limit: source.length),
            uncertainRanges: merged(uncertain, limit: source.length)
        )
    }

    private static func isApostrophe(in source: NSString, at index: Int) -> Bool {
        guard index > 0 else { return false }
        let previous = source.character(at: index - 1)
        return isLetterOrNumber(previous)
    }

    private static func isLetterOrNumber(_ unit: unichar) -> Bool {
        guard let scalar = UnicodeScalar(unit) else { return false }
        return CharacterSet.alphanumerics.contains(scalar)
    }

    private static func merged(_ ranges: [NSRange], limit: Int) -> [NSRange] {
        let sorted = ranges
            .filter { $0.location != NSNotFound && $0.location >= 0 && $0.length > 0 && $0.location < limit }
            .map { NSRange(location: $0.location, length: min($0.length, limit - $0.location)) }
            .sorted { $0.location < $1.location }

        var result: [NSRange] = []
        for range in sorted {
            if let last = result.last, NSMaxRange(range) <= NSMaxRange(last) {
                continue
            }
            if let last = result.last, range.location <= NSMaxRange(last) {
                result[result.count - 1].length = NSMaxRange(range) - last.location
            } else {
                result.append(range)
            }
        }
        return result
    }
}

extension NSRange {
    func intersects(_ other: NSRange) -> Bool {
        location < NSMaxRange(other) && other.location < NSMaxRange(self)
    }
}
