
import Foundation

public enum BOLDConsistencyCategory: String, CaseIterable, Hashable {
    case conflictingDates
    case nameVariants
    case terminology
    case capitalization
    case duplicateParagraphs
    case repeatedArguments
    case authorRuleViolation
    case uncertainQuotation
    case emptySection
    case headingHierarchy
    case brokenCrossReference
    case unresolvedLink
    case duplicateSectionBoundary
    case unreferencedFootnote
    case malformedTableOfContents
    case sectionLengthBalance
    case argumentStructure
}

public enum BOLDAuditConfidence: String, CaseIterable {
    case confirmedStructuralDefect = "Confirmed structural defect"
    case exactRuleViolation = "Exact rule violation"
    case exactDuplicate = "Exact duplicate"
    case potentialInconsistency = "Potential inconsistency"
    case reviewSuggestion = "Review suggestion"
}

public struct BOLDConsistencyFinding: Identifiable {
    public let id: String
    public let category: BOLDConsistencyCategory
    public let explanation: String
    public let firstRange: NSRange
    public let secondRange: NSRange?
    public let confidence: Double
    public let ruleID: UUID?
    public let suggestedReplacement: String?
    public let matchedText: String?
    public let isInsideQuotationText: Bool

    public var auditConfidence: BOLDAuditConfidence {
        if category == .malformedTableOfContents && confidence < 1 {
            return .reviewSuggestion
        }
        return switch category {
        case .emptySection, .headingHierarchy, .brokenCrossReference,
             .unresolvedLink, .duplicateSectionBoundary,
             .unreferencedFootnote, .malformedTableOfContents:
            .confirmedStructuralDefect
        case .authorRuleViolation:
            .exactRuleViolation
        case .duplicateParagraphs where confidence >= 0.99:
            .exactDuplicate
        case .conflictingDates, .nameVariants, .terminology, .capitalization:
            .potentialInconsistency
        default:
            .reviewSuggestion
        }
    }

    public init(
        category: BOLDConsistencyCategory,
        explanation: String,
        firstRange: NSRange,
        secondRange: NSRange?,
        confidence: Double,
        ruleID: UUID? = nil,
        suggestedReplacement: String? = nil,
        matchedText: String? = nil,
        isInsideQuotationText: Bool = false
    ) {
        self.category = category
        self.explanation = explanation
        self.firstRange = firstRange
        self.secondRange = secondRange
        self.confidence = confidence
        self.ruleID = ruleID
        self.suggestedReplacement = suggestedReplacement
        self.matchedText = matchedText
        self.isInsideQuotationText = isInsideQuotationText
        self.id = "\(category.rawValue):\(firstRange.location):\(secondRange?.location ?? -1):\(ruleID?.uuidString ?? "")"
    }
}

/// Offline, evidence-based analysis. Findings are review candidates.
/// All ranges are UTF-16 document offsets for native text navigation.
public struct BOLDConsistencyScanner {
    private struct Paragraph {
        var exactKey: String
        var range: NSRange
        var wordCount: Int
        var unique: Set<String>
    }

    public init() {}

    private static let irrelevant: Set<String> = [
        "there", "their", "about", "which", "would",
        "could", "these", "those", "because", "should",
        "while", "where", "through", "before", "after",
        "within", "without", "under", "other", "again",
        "chapter", "section", "first", "second", "during"
    ]

    private static let wordRegex = try! NSRegularExpression(pattern: "[\\p{L}\\p{N}']+")
    private static let paragraphSeparator = try! NSRegularExpression(pattern: "\\r?\\n[ \\t]*\\r?\\n")
    private static let dateRegex = try! NSRegularExpression(
        pattern: "(?i)\\b((?:the\\s+)?[a-z][a-z -]{4,70}?)\\s+(began|ended|started|occurred|happened|died)\\s+(?:in|during)\\s+(?:(AD|CE|BC|BCE)\\s*)?(\\d{1,4})\\b"
    )
    private static let nameRegex = try! NSRegularExpression(pattern: "\\b[A-Z][a-z]{4,}(?:[- ][A-Z][a-z]{3,})?\\b")
    private static let compoundRegex = try! NSRegularExpression(pattern: "\\b[A-Za-z]{4,}[- ][A-Za-z]{4,}\\b")
    private static let capitalRegex = try! NSRegularExpression(pattern: "\\b[A-Za-z]{5,}\\b")

    private static func normalize(_ text: String) -> String {
        text.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        .split(whereSeparator: { $0.isWhitespace })
        .joined(separator: " ")
    }

    private static func oneEditApart(_ a: String, _ b: String) -> Bool {
        let x = Array(a)
        let y = Array(b)

        if x == y || abs(x.count - y.count) > 1 {
            return false
        }

        var i = 0
        var j = 0
        var edits = 0

        while i < x.count && j < y.count {
            if x[i] == y[j] {
                i += 1
                j += 1
                continue
            }

            edits += 1
            if edits > 1 { return false }

            if x.count > y.count {
                i += 1
            } else if y.count > x.count {
                j += 1
            } else {
                i += 1
                j += 1
            }
        }

        return edits + x.count - i + y.count - j == 1
    }

    public func scan(
        _ document: String,
        preferredTerms: [String: [String]] = [:],
        rules: [BOLDConsistencyRule] = [],
        quotationRanges: [NSRange] = [],
        maximumFindings: Int = 300
    ) -> [BOLDConsistencyFinding] {
        scanCancellable(
            document,
            preferredTerms: preferredTerms,
            rules: rules,
            quotationRanges: quotationRanges,
            maximumFindings: maximumFindings,
            shouldCancel: { false }
        ) ?? []
    }

    /// Returns nil when cancelled. Match enumeration checks cancellation
    /// throughout each pass so superseded manuscript revisions release their
    /// temporary indexes promptly instead of sitting behind a serial queue.
    public func scanCancellable(
        _ document: String,
        preferredTerms: [String: [String]] = [:],
        rules: [BOLDConsistencyRule] = [],
        quotationRanges: [NSRange] = [],
        maximumFindings: Int = 300,
        shouldCancel: () -> Bool
    ) -> [BOLDConsistencyFinding]? {
        guard maximumFindings > 0 && !document.isEmpty else {
            return shouldCancel() ? nil : []
        }
        guard !shouldCancel() else { return nil }

        let ns = document as NSString
        let whole = NSRange(location: 0, length: ns.length)

        var findings: [BOLDConsistencyFinding] = []
        var categoryCounts: [BOLDConsistencyCategory: Int] = [:]

        func add(
            _ category: BOLDConsistencyCategory,
            _ explanation: String,
            _ first: NSRange,
            _ second: NSRange?,
            _ confidence: Double
        ) {
            let primaryCategory = category == .authorRuleViolation || category == .duplicateParagraphs
            let categoryLimit = primaryCategory ? max(1, maximumFindings * 3 / 4) : max(50, maximumFindings / 8)
            guard categoryCounts[category, default: 0] < categoryLimit else { return }
            categoryCounts[category, default: 0] += 1

            findings.append(
                BOLDConsistencyFinding(
                    category: category,
                    explanation: explanation,
                    firstRange: first,
                    secondRange: second,
                    confidence: confidence
                )
            )
        }

        var paragraphs: [Paragraph] = []
        var start = 0

        func appendParagraph(_ range: NSRange) {
            guard range.length > 0, !shouldCancel() else { return }

            let raw = ns.substring(with: range) as NSString
            let trimSet = CharacterSet.whitespacesAndNewlines
            let visible = raw.rangeOfCharacter(from: trimSet.inverted)
            guard visible.location != NSNotFound else { return }
            let endVisible = raw.rangeOfCharacter(from: trimSet.inverted, options: .backwards)
            guard endVisible.location != NSNotFound else { return }
            let visibleRange = NSRange(location: visible.location, length: NSMaxRange(endVisible) - visible.location)
            guard visibleRange.length >= 3 else { return }
            let text = raw.substring(with: visibleRange)
            let exactKey = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            var wordCount = 0
            var unique = Set<String>()
            _ = Self.enumerateMatches(Self.wordRegex, in: text, range: NSRange(location: 0, length: (text as NSString).length), shouldCancel: shouldCancel) { match in
                wordCount += 1
                let word = Self.normalize((text as NSString).substring(with: match.range))
                if word.count > 4 && !Self.irrelevant.contains(word) { unique.insert(word) }
            }

            paragraphs.append(
                Paragraph(
                    exactKey: exactKey,
                    range: range,
                    wordCount: wordCount,
                    unique: unique
                )
            )
        }

        guard Self.enumerateMatches(Self.paragraphSeparator, in: document, range: whole, shouldCancel: shouldCancel, using: { split in
            appendParagraph(
                NSRange(
                    location: start,
                    length: split.range.location - start
                )
            )
            start = NSMaxRange(split.range)
        }) else { return nil }

        appendParagraph(
            NSRange(
                location: start,
                length: ns.length - start
            )
        )
        guard !shouldCancel() else { return nil }

        // Chronology: only compare repeated event descriptions.
        var dates: [String: (String, NSRange)] = [:]

        guard Self.enumerateMatches(Self.dateRegex, in: document, range: whole, shouldCancel: shouldCancel, using: { match in
            let event = Self.normalize(
                ns.substring(with: match.range(at: 1))
            )

            let verb = Self.normalize(
                ns.substring(with: match.range(at: 2))
            )

            let eraRange = match.range(at: 3)
            let era = eraRange.location == NSNotFound
                ? ""
                : Self.normalize(ns.substring(with: eraRange))

            let year = ns.substring(with: match.range(at: 4))
            let value = era + ":" + year
            let key = event + "|" + verb

            if let old = dates[key], old.0 != value {
                add(
                    .conflictingDates,
                    "Possible conflicting dates for \(event): \(old.0) and \(value)",
                    old.1,
                    match.range,
                    0.82
                )
            } else if dates[key] == nil {
                dates[key] = (value, match.range)
            }
        }) else { return nil }

        // Exact paragraph duplicates in linear expected time.
        var seenParagraphs: [String: NSRange] = [:]

        for paragraph in paragraphs
            where (paragraph.exactKey as NSString).length >= 24 && paragraph.wordCount >= 4 {
            if shouldCancel() { return nil }

            if let previous = seenParagraphs[paragraph.exactKey] {
                add(
                    .duplicateParagraphs,
                    "Exactly repeated paragraph",
                    previous,
                    paragraph.range,
                    0.99
                )
            } else {
                seenParagraphs[paragraph.exactKey] = paragraph.range
            }
        }

        // Near duplicates and candidate repeated arguments.
        // Bounded inverted lists prevent quadratic whole-book scans.
        var inverted: [String: [Int]] = [:]

        for (index, paragraph) in paragraphs.enumerated() {
            if shouldCancel() { return nil }
            guard paragraph.wordCount >= 28,
                  paragraph.unique.count >= 16 else {
                continue
            }

            let anchors = Array(
                paragraph.unique.sorted {
                    if $0.count == $1.count { return $0 < $1 }
                    return $0.count > $1.count
                }.prefix(14)
            )

            var candidates: Set<Int> = []

            for anchor in anchors {
                for oldIndex in inverted[anchor, default: []].suffix(16) {
                    candidates.insert(oldIndex)
                }
            }

            for previousIndex in candidates.sorted().suffix(28) {
                if shouldCancel() { return nil }
                let previous = paragraphs[previousIndex]

                guard previous.wordCount >= 28,
                      previous.unique.count >= 16,
                      previous.exactKey != paragraph.exactKey
                else { continue }

                let common = paragraph.unique
                    .intersection(previous.unique).count

                let union = paragraph.unique.count
                    + previous.unique.count - common

                guard union > 0, common >= 12 else {
                    continue
                }

                let similarity = Double(common) / Double(union)

                if similarity >= 0.78 {
                    add(
                        .duplicateParagraphs,
                        "Possible near-duplicate paragraph",
                        previous.range,
                        paragraph.range,
                        similarity
                    )
                    break
                }

                if similarity >= 0.40 {
                    add(
                        .repeatedArguments,
                        "Possible repeated argument; review shared evidence and context",
                        previous.range,
                        paragraph.range,
                        similarity
                    )
                    break
                }
            }

            for anchor in anchors {
                var list = inverted[anchor, default: []]
                list.append(index)

                if list.count > 40 {
                    list.removeFirst(list.count - 40)
                }

                inverted[anchor] = list
            }
        }

        // Conservative name variants: repeated candidate proper names,
        // bounded comparisons and a single spelling edit.
        let excluded: Set<String> = [
            "These", "Those", "There", "After", "Before",
            "While", "Their", "Chapter", "Section",
            "First", "Second", "Third", "During",
            "However", "Because"
        ]

        var names: [String: [NSRange]] = [:]

        guard Self.enumerateMatches(Self.nameRegex, in: document, range: whole, shouldCancel: shouldCancel, using: { match in
            let value = ns.substring(with: match.range)

            if !excluded.contains(value) {
                names[value, default: []].append(match.range)
            }
        }) else { return nil }

        let repeatedNames = names.keys.filter {
            names[$0, default: []].count >= 2
        }.sorted()

        if repeatedNames.count <= 500 {
            for (index, name) in repeatedNames.enumerated() {
                if shouldCancel() { return nil }
                for other in repeatedNames.dropFirst(index + 1) {
                    if name.first?.lowercased()
                        != other.first?.lowercased() {
                        continue
                    }

                    if Self.oneEditApart(
                        Self.normalize(name),
                        Self.normalize(other)
                    ) {
                        add(
                            .nameVariants,
                            "Possible name variant: \(name) / \(other)",
                            names[name]![0],
                            names[other]![0],
                            0.70
                        )
                    }
                }
            }
        }

        // Detect spacing and hyphenation variants of compounds.
        var compounds: [String: [String: [NSRange]]] = [:]

        guard Self.enumerateMatches(Self.compoundRegex, in: document, range: whole, shouldCancel: shouldCancel, using: { match in
            let phrase = ns.substring(with: match.range).lowercased()
            let key = phrase
                .replacingOccurrences(of: "-", with: "")
                .replacingOccurrences(of: " ", with: "")

            compounds[key, default: [:]][phrase, default: []]
                .append(match.range)
        }) else { return nil }

        for variants in compounds.values where variants.count > 1 {
            if shouldCancel() { return nil }
            let forms = variants.sorted { $0.key < $1.key }

            guard let first = forms.first, first.value.count >= 2 else {
                continue
            }

            for other in forms.dropFirst() where other.value.count >= 2 {
                add(
                    .terminology,
                    "Inconsistent compound term: \(first.key) / \(other.key)",
                    first.value[0],
                    other.value[0],
                    0.90
                )
            }
        }

        // Explicit preferred-term glossary, with literal matches.
        for (preferred, alternatives) in preferredTerms.sorted(
            by: { $0.key < $1.key }
        ) {
            if shouldCancel() { return nil }
            guard !preferred.isEmpty else { continue }

            let preferredRegex = try! NSRegularExpression(
                pattern: "(?<![\\p{L}\\p{N}])"
                    + NSRegularExpression.escapedPattern(for: preferred)
                    + "(?![\\p{L}\\p{N}])",
                options: [.caseInsensitive]
            )

            guard let canonical = preferredRegex.firstMatch(
                in: document,
                range: whole
            ) else { continue }

            for alternate in alternatives where !alternate.isEmpty {
                if shouldCancel() { return nil }
                let regex = try! NSRegularExpression(
                    pattern: "(?<![\\p{L}\\p{N}])"
                        + NSRegularExpression.escapedPattern(for: alternate)
                        + "(?![\\p{L}\\p{N}])",
                    options: [.caseInsensitive]
                )

                if let match = regex.firstMatch(in: document, range: whole),
                   match.range != canonical.range {
                    add(
                        .terminology,
                        "Preferred terminology: \(preferred); variant: \(alternate)",
                        canonical.range,
                        match.range,
                        0.95
                    )
                }
            }
        }

        // Author rules are literal and deterministic. UI callers provide
        // merged semantic and punctuation-based quotation spans.
        let quotedRanges = quotationRanges.isEmpty && !rules.isEmpty
            ? BOLDQuotationAnalyzer.analyze(text: NSAttributedString(string: document)).protectedRanges
            : quotationRanges
        for rule in rules where rule.enabled && !rule.matchText.isEmpty {
            if shouldCancel() { return nil }
            let escaped = NSRegularExpression.escapedPattern(for: rule.matchText)
            let pattern = rule.wholeWord
                ? "(?<![\\p{L}\\p{N}_])\(escaped)(?![\\p{L}\\p{N}_])"
                : escaped
            let options: NSRegularExpression.Options = rule.caseSensitive
                ? [] : [.caseInsensitive]
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
                continue
            }
            guard Self.enumerateMatches(regex, in: document, range: whole, shouldCancel: shouldCancel, using: { match in
                if rule.scope == .outsideQuotationMarks,
                   Self.intersectsSorted(quotedRanges, match.range) {
                    return
                }
                let description: String
                let actualText = ns.substring(with: match.range)
                if let replacement = rule.replacement {
                    if rule.kind == .preferredTerm,
                       actualText.compare(replacement, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
                        return
                    }
                    if rule.kind == .capitalization && actualText == replacement {
                        return
                    }
                }
                switch rule.kind {
                case .preferredTerm:
                    description = "Preferred terminology: use \(rule.replacement ?? "the preferred spelling")"
                case .disallowedTerm:
                    description = "Disallowed term appears in the manuscript"
                case .capitalization:
                    description = "Review capitalization of this term"
                }
                let detail = rule.explanation.isEmpty
                    ? description : "\(description). \(rule.explanation)"
                add(
                    .authorRuleViolation,
                    detail,
                    match.range,
                    nil,
                    1.0
                )
                guard let index = findings.indices.last else { return }
                findings[index] = BOLDConsistencyFinding(
                    category: .authorRuleViolation,
                    explanation: detail,
                    firstRange: match.range,
                    secondRange: nil,
                    confidence: 1.0,
                    ruleID: rule.id,
                    suggestedReplacement: rule.replacement,
                    matchedText: actualText,
                    isInsideQuotationText: Self.intersectsSorted(quotedRanges, match.range)
                )
            }) else { return nil }
        }

        // Capitalization candidates. Do not count ordinary sentence
        // initial uppercase words as strong evidence.
        var variants: [String: [String: [NSRange]]] = [:]

        guard Self.enumerateMatches(Self.capitalRegex, in: document, range: whole, shouldCancel: shouldCancel, using: { match in
            let value = ns.substring(with: match.range)
            let normalized = value.lowercased()

            if Self.irrelevant.contains(normalized) {
                return
            }

            var cursor = match.range.location

            while cursor > 0 {
                let previous = ns.character(at: cursor - 1)
                if previous == 32 || previous == 9 {
                    cursor -= 1
                } else {
                    break
                }
            }

            if cursor == 0 { return }

            let preceding = ns.character(at: cursor - 1)

            if preceding == 46 || preceding == 33
                || preceding == 63
                || preceding == 10
                || preceding == 13 {
                return
            }

            variants[normalized, default: [:]][value, default: []]
                .append(match.range)
        }) else { return nil }

        for forms in variants.values where forms.count > 1 {
            if shouldCancel() { return nil }
            let entries = forms.sorted { $0.key < $1.key }

            guard let first = entries.first, first.value.count >= 2 else {
                continue
            }

            for other in entries.dropFirst() where other.value.count >= 2 {
                add(
                    .capitalization,
                    "Inconsistent capitalization: \(first.key) / \(other.key)",
                    first.value[0],
                    other.value[0],
                    0.74
                )
            }
        }

        guard !shouldCancel() else { return nil }
        let prioritized = findings.sorted {
            if $0.auditConfidence.sortOrder != $1.auditConfidence.sortOrder {
                return $0.auditConfidence.sortOrder < $1.auditConfidence.sortOrder
            }
            if $0.firstRange.location == $1.firstRange.location {
                return $0.category.rawValue < $1.category.rawValue
            }
            return $0.firstRange.location < $1.firstRange.location
        }
        return Array(prioritized.prefix(maximumFindings))
    }

    private static func enumerateMatches(
        _ regex: NSRegularExpression,
        in text: String,
        range: NSRange,
        shouldCancel: () -> Bool,
        using body: (NSTextCheckingResult) -> Void
    ) -> Bool {
        var cancelled = false
        regex.enumerateMatches(in: text, range: range) { match, _, stop in
            if shouldCancel() {
                cancelled = true
                stop.pointee = true
                return
            }
            if let match { body(match) }
        }
        return !cancelled && !shouldCancel()
    }

    private static func intersectsSorted(_ ranges: [NSRange], _ match: NSRange) -> Bool {
        var low = 0
        var high = ranges.count
        while low < high {
            let middle = low + (high - low) / 2
            if NSMaxRange(ranges[middle]) <= match.location { low = middle + 1 }
            else { high = middle }
        }
        return low < ranges.count && ranges[low].intersects(match)
    }
}
