import AppKit
import CryptoKit
import Foundation
import UniformTypeIdentifiers

enum BOLDAuditScope: String, CaseIterable, Identifiable {
    case currentDocument = "Current Document"
    case argumentReview = "Argument Review"
    case selectedLibrary = "Selected Library"
    var id: String { rawValue }
}

enum BOLDCrossDocumentConfidence: String, CaseIterable {
    case exactDuplicate = "Exact duplicate"
    case exactRuleViolation = "Exact rule violation"
    case potentialInconsistency = "Potential inconsistency"
    case reviewSuggestion = "Review suggestion"
    case unavailableSource = "Source unavailable"
}

enum BOLDCrossDocumentCategory: String, CaseIterable {
    case repeatedPassage = "Repeated passage"
    case similarArgument = "Similar argument"
    case terminology = "Terminology"
    case dateReview = "Date review"
    case nameReview = "Name review"
    case sharedSubject = "Shared subject"
    case unavailableDocument = "Unavailable document"
    case unresolvedLink = "Unresolved link"
    case argumentStructure = "Argument structure"
}

/// A compact transient description of one selected Library source. It contains
/// no indexed passage body and is only passed to a cancellable audit task.
struct BOLDCrossDocumentSourceDescriptor: Sendable {
    let id: UUID
    let title: String
    let sourceURI: String
    let fingerprint: String
    let isReference: Bool
    let status: String
    let url: URL?
}

struct BOLDCrossDocumentPassage: Sendable {
    let documentID: UUID
    let title: String
    let sourceURI: String
    let fingerprint: String
    let range: NSRange
    let excerpt: String
    let normalizedText: String
    let tokenSet: Set<String>
    let isQuoted: Bool
}

struct BOLDCrossDocumentCandidate: Sendable {
    let documentID: UUID
    let title: String
    let sourceURI: String
    let fingerprint: String
    let range: NSRange
    let category: BOLDCrossDocumentCategory
    let confidence: BOLDCrossDocumentConfidence
    let excerpt: String
    let explanation: String
    let query: String
    let ruleID: UUID?
    let isQuoted: Bool
    let comparisonDocumentID: UUID?
    let comparisonFingerprint: String?
    let comparisonRange: NSRange?
    let comparisonTitle: String?
    let comparisonExcerpt: String?
}

struct BOLDCrossDocumentSnapshotResult: Sendable {
    let passages: [BOLDCrossDocumentPassage]
    let candidates: [BOLDCrossDocumentCandidate]
    let unavailable: [BOLDCrossDocumentSourceDescriptor]
    let scannedDocumentCount: Int
    let omittedPassageCount: Int
    let cancelled: Bool
}

struct BOLDCrossDocumentFinding: Identifiable {
    let id: String
    let category: BOLDCrossDocumentCategory
    let confidence: BOLDCrossDocumentConfidence
    let primary: KnowledgeSearchResult?
    let comparison: KnowledgeSearchResult?
    let primaryTitle: String
    let primaryExcerpt: String
    let comparisonTitle: String?
    let comparisonExcerpt: String?
    let explanation: String
    let query: String
    let isQuoted: Bool
}

struct BOLDCrossDocumentAuditResult {
    let findings: [BOLDCrossDocumentFinding]
    let scannedDocumentCount: Int
    let unavailableDocumentCount: Int
    let omittedPassageCount: Int
    let staleResultCount: Int
    let elapsed: TimeInterval
}

@MainActor
protocol BOLDCrossDocumentLibraryProviding: AnyObject {
    var documents: [KnowledgeDocumentRecord] { get }
    func refreshSources() throws
    func sourceURL(for id: KnowledgeDocumentID) throws -> URL?
    func search(_ query: String, limit: Int) throws -> [KnowledgeSearchResult]
    func resolve(_ reference: KnowledgePassageReference) throws -> (KnowledgeReferenceStatus, NSRange?)
    func open(_ result: KnowledgeSearchResult, query: String) -> Bool
}

@MainActor
final class BOLDKnowledgeLibraryAuditAdapter: BOLDCrossDocumentLibraryProviding {
    private let library: KnowledgeLibraryStore
    private let openKnowledgeLibrary: () -> Void

    init(library: KnowledgeLibraryStore, openKnowledgeLibrary: @escaping () -> Void = {}) {
        self.library = library
        self.openKnowledgeLibrary = openKnowledgeLibrary
    }

    var documents: [KnowledgeDocumentRecord] { library.documents }
    func refreshSources() throws { _ = try library.search("BOLDWriterAuditProbe", limit: 1) }
    func sourceURL(for id: KnowledgeDocumentID) throws -> URL? { try library.sourceURL(for: id) }
    func search(_ query: String, limit: Int) throws -> [KnowledgeSearchResult] {
        try library.search(query, limit: limit)
    }
    func resolve(_ reference: KnowledgePassageReference) throws -> (KnowledgeReferenceStatus, NSRange?) {
        try library.resolve(reference)
    }
    func open(_ result: KnowledgeSearchResult, query: String) -> Bool {
        guard let (status, range) = try? library.resolve(result.reference),
              (status == .current || status == .revalidated), range != nil,
              let refreshed = try? library.search(query, documentID: result.document.id, limit: 1_000),
              let current = refreshed.first(where: {
                  $0.reference.passageID == result.reference.passageID
                      || ($0.reference.excerptSignature == result.reference.excerptSignature
                          && $0.reference.context == result.reference.context)
              }) else { return false }
        // A short rule token can match several nearby paragraphs. Use the
        // canonical resolved excerpt so the Library window's own search also
        // resolves to this exact passage before opening the source editor.
        library.requestNavigation(to: current.reference, quotation: current.excerpt)
        openKnowledgeLibrary()
        return true
    }
}

enum BOLDCrossDocumentSnapshotter {
    private struct DateMention {
        let documentID: UUID
        let title: String
        let sourceURI: String
        let fingerprint: String
        let range: NSRange
        let eventKey: String
        let dateKey: String
        let excerpt: String
        let query: String
    }
    private struct NameMention {
        let documentID: UUID
        let title: String
        let sourceURI: String
        let fingerprint: String
        let range: NSRange
        let spelling: String
        let excerpt: String
        let query: String
    }

    static let maximumDocuments = 100
    static let maximumPassages = 20_000
    static let maximumPassagesPerDocument = 2_000
    static let maximumPassagesPerParagraphCharacters = 1_200
    static let maximumCandidates = 8_000

    static func scan(
        sources: [BOLDCrossDocumentSourceDescriptor],
        rules: [BOLDConsistencyRule],
        shouldCancel: () -> Bool
    ) -> BOLDCrossDocumentSnapshotResult {
        var passages: [BOLDCrossDocumentPassage] = []
        var candidates: [BOLDCrossDocumentCandidate] = []
        var unavailable: [BOLDCrossDocumentSourceDescriptor] = []
        var dateMentions: [DateMention] = []
        var nameMentions: [NameMention] = []
        var scanned = 0
        var omitted = 0
        let selected = Array(sources.prefix(maximumDocuments))

        for descriptor in selected {
            if shouldCancel() {
                return BOLDCrossDocumentSnapshotResult(
                    passages: passages, candidates: candidates, unavailable: unavailable,
                    scannedDocumentCount: scanned, omittedPassageCount: omitted, cancelled: true
                )
            }
            guard !descriptor.isReference, let url = descriptor.url else {
                if descriptor.isReference { continue }
                unavailable.append(descriptor)
                continue
            }

            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url, options: [.mappedIfSafe])
                let fingerprint = sha256(data)
                guard fingerprint == descriptor.fingerprint else {
                    unavailable.append(BOLDCrossDocumentSourceDescriptor(
                        id: descriptor.id, title: descriptor.title, sourceURI: descriptor.sourceURI,
                        fingerprint: fingerprint, isReference: false, status: "changed during audit", url: url
                    ))
                    continue
                }
                let wrapper = try FileWrapper(url: url)
                let document = try BOLDWriterDocument(
                    fileWrapper: wrapper,
                    contentType: BOLDWriterDocument.inferredContentType(for: url)
                )
                let attributed = document.text
                let text = attributed.string
                let nsText = text as NSString
                dateMentions.append(contentsOf: dateMentionsIn(text, descriptor: descriptor, fingerprint: fingerprint))
                nameMentions.append(contentsOf: nameMentionsIn(text, descriptor: descriptor, fingerprint: fingerprint))
                let semantic = BOLDQuotationAnalyzer.semanticRanges(in: attributed)
                let quote = BOLDQuotationAnalyzer.analyze(string: text, semanticRanges: semantic, shouldCancel: shouldCancel)
                guard let quote else {
                    return BOLDCrossDocumentSnapshotResult(
                        passages: passages, candidates: candidates, unavailable: unavailable,
                        scannedDocumentCount: scanned, omittedPassageCount: omitted, cancelled: true
                    )
                }

                let scannedFindings = BOLDConsistencyScanner().scanCancellable(
                    text,
                    rules: rules,
                    quotationRanges: quote.protectedRanges,
                    maximumFindings: 1_000,
                    shouldCancel: shouldCancel
                )
                guard let scannedFindings else {
                    return BOLDCrossDocumentSnapshotResult(
                        passages: passages, candidates: candidates, unavailable: unavailable,
                        scannedDocumentCount: scanned, omittedPassageCount: omitted, cancelled: true
                    )
                }

                let sourcePassageStart = passages.count
                var cursor = 0
                var documentPassages = 0
                while cursor < nsText.length {
                    if cursor.isMultiple(of: 4_096) && shouldCancel() {
                        return BOLDCrossDocumentSnapshotResult(
                            passages: passages, candidates: candidates, unavailable: unavailable,
                            scannedDocumentCount: scanned, omittedPassageCount: omitted, cancelled: true
                        )
                    }
                    let paragraphRange = nsText.paragraphRange(for: NSRange(location: cursor, length: 0))
                    cursor = max(cursor + 1, NSMaxRange(paragraphRange))
                    guard paragraphRange.location < nsText.length else { continue }
                    var start = paragraphRange.location
                    var end = min(nsText.length, NSMaxRange(paragraphRange))
                    while start < end, isWhitespace(nsText.character(at: start)) { start += 1 }
                    while end > start, isWhitespace(nsText.character(at: end - 1)) { end -= 1 }
                    let range = NSRange(location: start, length: end - start)
                    guard range.length >= 48, range.length <= maximumPassagesPerParagraphCharacters,
                          documentPassages < maximumPassagesPerDocument, passages.count < maximumPassages else {
                        if range.length >= 48 { omitted += 1 }
                        continue
                    }
                    let body = nsText.substring(with: range)
                    let normalized = normalize(body)
                    let tokenSet = tokens(normalized)
                    guard tokenSet.count >= 5 else { continue }
                    passages.append(BOLDCrossDocumentPassage(
                        documentID: descriptor.id,
                        title: descriptor.title,
                        sourceURI: descriptor.sourceURI,
                        fingerprint: fingerprint,
                        range: range,
                        excerpt: excerpt(body, maximum: 260),
                        normalizedText: normalized,
                        tokenSet: tokenSet,
                        isQuoted: intersects(quote.protectedRanges, range)
                    ))
                    documentPassages += 1
                }

                let descriptorFindings = scannedFindings.prefix(maximumCandidates - candidates.count)
                for finding in descriptorFindings {
                    if shouldCancel() { break }
                    let location = finding.firstRange.location
                    guard location >= 0, location <= nsText.length else { continue }
                    let safe = NSRange(location: location, length: min(finding.firstRange.length, nsText.length - location))
                    let start = max(0, safe.location - 100)
                    let end = min(nsText.length, max(safe.location, NSMaxRange(safe)) + 160)
                    let excerpt = nsText.substring(with: NSRange(location: start, length: end - start))
                    let exactRule = finding.ruleID != nil
                    let category: BOLDCrossDocumentCategory
                    let confidence: BOLDCrossDocumentConfidence
                    switch finding.category {
                    case .authorRuleViolation, .terminology, .capitalization:
                        category = .terminology
                        confidence = exactRule ? .exactRuleViolation : .potentialInconsistency
                    case .conflictingDates:
                        category = .dateReview
                        confidence = .potentialInconsistency
                    case .nameVariants:
                        category = .nameReview
                        confidence = .potentialInconsistency
                    case .repeatedArguments:
                        category = .similarArgument
                        confidence = .reviewSuggestion
                    default:
                        continue
                    }
                    candidates.append(BOLDCrossDocumentCandidate(
                        documentID: descriptor.id, title: descriptor.title, sourceURI: descriptor.sourceURI,
                        fingerprint: fingerprint, range: safe, category: category, confidence: confidence,
                        excerpt: excerpt.trimmingCharacters(in: .whitespacesAndNewlines),
                        explanation: finding.explanation,
                        query: finding.matchedText ?? querySeed(in: excerpt),
                        ruleID: finding.ruleID,
                        isQuoted: finding.isInsideQuotationText,
                        comparisonDocumentID: nil, comparisonFingerprint: nil, comparisonRange: nil,
                        comparisonTitle: nil, comparisonExcerpt: nil
                    ))
                }

                let snapshot = BOLDBookAuditAnalyzer.snapshot(from: attributed)
                for heading in snapshot.headings.prefix(100) {
                    if candidates.count >= maximumCandidates { break }
                    let headingText = nsText.substring(with: heading.range)
                    let words = significantTokens(headingText)
                    guard words.count >= 2 else { continue }
                    candidates.append(BOLDCrossDocumentCandidate(
                        documentID: descriptor.id, title: descriptor.title, sourceURI: descriptor.sourceURI,
                        fingerprint: fingerprint, range: heading.range, category: .sharedSubject,
                        confidence: .reviewSuggestion, excerpt: headingText, explanation: "This section subject can be compared with passages in the selected Library collection.",
                        query: words.prefix(5).joined(separator: " "), ruleID: nil,
                        isQuoted: intersects(quote.protectedRanges, heading.range),
                        comparisonDocumentID: nil, comparisonFingerprint: nil, comparisonRange: nil,
                        comparisonTitle: nil, comparisonExcerpt: nil
                    ))
                }

                // The current editor's local audit already reports these conditions;
                // retain only concise structural candidates for cross-document review.
                for issue in argumentStructure(in: snapshot, text: text) {
                    guard candidates.count < maximumCandidates else { break }
                    candidates.append(BOLDCrossDocumentCandidate(
                        documentID: descriptor.id, title: descriptor.title, sourceURI: descriptor.sourceURI,
                        fingerprint: fingerprint, range: issue.range, category: .argumentStructure,
                        confidence: .reviewSuggestion,
                        excerpt: safeExcerpt(text, issue.range), explanation: issue.explanation,
                        query: querySeed(in: safeExcerpt(text, issue.range)), ruleID: nil,
                        isQuoted: intersects(quote.protectedRanges, issue.range),
                        comparisonDocumentID: nil, comparisonFingerprint: nil, comparisonRange: nil,
                        comparisonTitle: nil, comparisonExcerpt: nil
                    ))
                }
                if passages.count - sourcePassageStart >= maximumPassagesPerDocument { omitted += 1 }
                scanned += 1
            } catch {
                unavailable.append(descriptor)
            }
        }

        let duplicateGroups = Dictionary(grouping: passages, by: \.normalizedText).values
            .filter { Set($0.map(\.documentID)).count > 1 }
        for group in duplicateGroups {
            guard let seed = group.first else { continue }
            for passage in group where passage.documentID != seed.documentID {
                guard candidates.count < maximumCandidates else { break }
                candidates.append(BOLDCrossDocumentCandidate(
                    documentID: seed.documentID, title: seed.title, sourceURI: seed.sourceURI,
                    fingerprint: seed.fingerprint, range: seed.range, category: .repeatedPassage,
                    confidence: .exactDuplicate, excerpt: seed.excerpt,
                    explanation: "This paragraph has the same normalized text in multiple selected Library documents.",
                    query: String(seed.normalizedText.prefix(180)), ruleID: nil, isQuoted: seed.isQuoted,
                    comparisonDocumentID: passage.documentID, comparisonFingerprint: passage.fingerprint,
                    comparisonRange: passage.range, comparisonTitle: passage.title, comparisonExcerpt: passage.excerpt
                ))
            }
        }

        for group in Dictionary(grouping: dateMentions, by: \.eventKey).values {
            guard candidates.count < maximumCandidates else { break }
            let sorted = group.sorted { $0.range.location < $1.range.location }
            for leftIndex in sorted.indices {
                for rightIndex in sorted.index(after: leftIndex)..<sorted.endIndex {
                    let left = sorted[leftIndex], right = sorted[rightIndex]
                    guard left.documentID != right.documentID, left.dateKey != right.dateKey else { continue }
                    candidates.append(BOLDCrossDocumentCandidate(
                        documentID: left.documentID, title: left.title, sourceURI: left.sourceURI,
                        fingerprint: left.fingerprint, range: left.range, category: .dateReview,
                        confidence: .potentialInconsistency, excerpt: left.excerpt,
                        explanation: "The same event wording has different date labels in the selected sources. Review the surrounding context; this is not a finding of historical contradiction.",
                        query: left.query, ruleID: nil, isQuoted: false,
                        comparisonDocumentID: right.documentID, comparisonFingerprint: right.fingerprint,
                        comparisonRange: right.range, comparisonTitle: right.title, comparisonExcerpt: right.excerpt
                    ))
                    if candidates.count >= maximumCandidates { break }
                }
                if candidates.count >= maximumCandidates { break }
            }
        }

        let namesByPrefix = Dictionary(grouping: nameMentions, by: { String($0.spelling.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")).prefix(3)) })
        outerNames: for group in namesByPrefix.values {
            let bounded = Array(group.prefix(500))
            for leftIndex in bounded.indices {
                for rightIndex in bounded.index(after: leftIndex)..<bounded.endIndex {
                    guard candidates.count < maximumCandidates else { break outerNames }
                    let left = bounded[leftIndex], right = bounded[rightIndex]
                    guard left.documentID != right.documentID,
                          left.spelling.caseInsensitiveCompare(right.spelling) != .orderedSame,
                          abs(left.spelling.count - right.spelling.count) <= 1,
                          editDistanceAtMostOne(left.spelling, right.spelling) else { continue }
                    candidates.append(BOLDCrossDocumentCandidate(
                        documentID: left.documentID, title: left.title, sourceURI: left.sourceURI,
                        fingerprint: left.fingerprint, range: left.range, category: .nameReview,
                        confidence: .potentialInconsistency, excerpt: left.excerpt,
                        explanation: "These spellings are textually similar across selected sources. They may name different people or reflect authorial spelling choices; review context before drawing conclusions.",
                        query: left.query, ruleID: nil, isQuoted: false,
                        comparisonDocumentID: right.documentID, comparisonFingerprint: right.fingerprint,
                        comparisonRange: right.range, comparisonTitle: right.title, comparisonExcerpt: right.excerpt
                    ))
                }
            }
        }

        // Similarity candidates are bounded and require shared content words;
        // they are never reported as exact duplicates or contradictions.
        let candidatePassages = passages.filter { !$0.isQuoted && $0.tokenSet.count >= 12 }
        var compared = 0
        if candidatePassages.count > 1 {
            outer: for leftIndex in candidatePassages.indices {
                for rightIndex in candidatePassages.index(after: leftIndex)..<candidatePassages.endIndex {
                    if compared >= 20_000 || candidates.count >= maximumCandidates { break outer }
                    let left = candidatePassages[leftIndex], right = candidatePassages[rightIndex]
                    compared += 1
                    guard left.documentID != right.documentID else { continue }
                    let shared = left.tokenSet.intersection(right.tokenSet).count
                    let union = left.tokenSet.union(right.tokenSet).count
                    guard union > 0, Double(shared) / Double(union) >= 0.72 else { continue }
                    let first = left.tokenSet.sorted().prefix(5).joined(separator: " ")
                    candidates.append(BOLDCrossDocumentCandidate(
                        documentID: left.documentID, title: left.title, sourceURI: left.sourceURI,
                        fingerprint: left.fingerprint, range: left.range, category: .similarArgument,
                        confidence: .reviewSuggestion, excerpt: left.excerpt,
                        explanation: "This passage shares substantial vocabulary with a passage in another selected document. Compare their purpose before deciding whether anything should change.",
                        query: first, ruleID: nil, isQuoted: false,
                        comparisonDocumentID: right.documentID, comparisonFingerprint: right.fingerprint,
                        comparisonRange: right.range, comparisonTitle: right.title, comparisonExcerpt: right.excerpt
                    ))
                }
            }
        }

        return BOLDCrossDocumentSnapshotResult(
            passages: passages,
            candidates: candidates,
            unavailable: unavailable,
            scannedDocumentCount: scanned,
            omittedPassageCount: omitted,
            cancelled: shouldCancel()
        )
    }

    private static func argumentStructure(in snapshot: BOLDBookAuditSnapshot, text: String) -> [(range: NSRange, explanation: String)] {
        let source = text as NSString
        let words = try? NSRegularExpression(pattern: "[\\p{L}\\p{N}’'-]+")
        let headings = snapshot.headings.filter { $0.level == 1 }.sorted { $0.range.location < $1.range.location }
        guard !headings.isEmpty, let words else { return [] }
        var output: [(NSRange, String)] = []
        for index in headings.indices {
            let start = headings[index].range.location
            let end = index + 1 < headings.count ? headings[index + 1].range.location : source.length
            let section = NSRange(location: start, length: max(0, end - start))
            let count = words.numberOfMatches(in: text, range: section)
            if count >= 5_000 {
                output.append((headings[index].range, "This section is unusually long (\(count) words). Consider whether it needs division; the audit does not decide where to split it."))
            }
            if output.count >= 100 { break }
        }
        return output
    }

    private static func dateMentionsIn(
        _ text: String,
        descriptor: BOLDCrossDocumentSourceDescriptor,
        fingerprint: String
    ) -> [DateMention] {
        guard let regex = try? NSRegularExpression(pattern: "(?i)\\b((?:the\\s+)?[a-z][a-z -]{4,70}?)\\s+(began|ended|started|occurred|happened|died)\\s+(?:in|during)\\s+(?:(AD|CE|BC|BCE)\\s*)?(\\d{1,4})\\b") else { return [] }
        let source = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: source.length)).prefix(500).compactMap { match in
            guard match.numberOfRanges >= 5,
                  match.range(at: 1).location != NSNotFound,
                  match.range(at: 2).location != NSNotFound,
                  match.range(at: 4).location != NSNotFound else { return nil }
            let event = source.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            let action = source.substring(with: match.range(at: 2)).lowercased()
            let eraRange = match.range(at: 3)
            let era = eraRange.location == NSNotFound ? "" : source.substring(with: eraRange).lowercased()
            let year = source.substring(with: match.range(at: 4))
            let sentenceStart = max(0, match.range.location - 100)
            let sentenceEnd = min(source.length, NSMaxRange(match.range) + 120)
            let excerpt = source.substring(with: NSRange(location: sentenceStart, length: sentenceEnd - sentenceStart))
            let eventKey = event.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")) + " " + action
            return DateMention(
                documentID: descriptor.id, title: descriptor.title, sourceURI: descriptor.sourceURI,
                fingerprint: fingerprint, range: match.range, eventKey: eventKey,
                dateKey: era + year, excerpt: excerpt.trimmingCharacters(in: .whitespacesAndNewlines),
                query: significantTokens(event).prefix(5).joined(separator: " ")
            )
        }
    }

    private static func nameMentionsIn(
        _ text: String,
        descriptor: BOLDCrossDocumentSourceDescriptor,
        fingerprint: String
    ) -> [NameMention] {
        guard let regex = try? NSRegularExpression(pattern: "\\b[A-Z][a-z]{4,}(?:[- ][A-Z][a-z]{3,})?\\b") else { return [] }
        let source = text as NSString
        let ignored: Set<String> = ["Chapter", "Section", "There", "These", "Those", "Their", "However", "Therefore", "Historical", "Primary", "Writers", "According"]
        var seen = Set<String>()
        return regex.matches(in: text, range: NSRange(location: 0, length: source.length)).prefix(1_500).compactMap { match in
            let name = source.substring(with: match.range)
            let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            guard !ignored.contains(name), seen.insert(folded).inserted else { return nil }
            let start = max(0, match.range.location - 80)
            let end = min(source.length, NSMaxRange(match.range) + 100)
            let excerpt = source.substring(with: NSRange(location: start, length: end - start))
            return NameMention(
                documentID: descriptor.id, title: descriptor.title, sourceURI: descriptor.sourceURI,
                fingerprint: fingerprint, range: match.range, spelling: name,
                excerpt: excerpt.trimmingCharacters(in: .whitespacesAndNewlines), query: name
            )
        }
    }

    private static func editDistanceAtMostOne(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs.lowercased()), b = Array(rhs.lowercased())
        guard abs(a.count - b.count) <= 1 else { return false }
        var i = 0, j = 0, edits = 0
        while i < a.count && j < b.count {
            if a[i] == b[j] { i += 1; j += 1; continue }
            edits += 1
            if edits > 1 { return false }
            if a.count > b.count { i += 1 }
            else if b.count > a.count { j += 1 }
            else { i += 1; j += 1 }
        }
        if i < a.count || j < b.count { edits += 1 }
        return edits <= 1
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    private static func normalize(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
    private static func tokens(_ text: String) -> Set<String> {
        let stop: Set<String> = ["about", "after", "again", "also", "because", "before", "being", "could", "from", "have", "into", "more", "other", "should", "that", "their", "there", "these", "they", "this", "those", "through", "under", "were", "which", "while", "with", "would"]
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let matches = (try? NSRegularExpression(pattern: "[\\p{L}\\p{N}]{3,}"))?.matches(in: folded, range: NSRange(location: 0, length: (folded as NSString).length)) ?? []
        let ns = folded as NSString
        return Set(matches.map { ns.substring(with: $0.range) }.filter { !stop.contains($0) })
    }
    private static func significantTokens(_ text: String) -> [String] { Array(tokens(normalize(text)).sorted()) }
    private static func querySeed(in text: String) -> String { significantTokens(normalize(text)).prefix(5).joined(separator: " ") }
    private static func excerpt(_ text: String, maximum: Int) -> String {
        guard text.count > maximum else { return text }
        return String(text.prefix(maximum)) + "…"
    }
    private static func safeExcerpt(_ text: String, _ range: NSRange) -> String {
        let ns = text as NSString
        guard range.location >= 0, range.location <= ns.length else { return "" }
        let start = max(0, range.location - 100)
        let end = min(ns.length, max(range.location, NSMaxRange(range)) + 180)
        return ns.substring(with: NSRange(location: start, length: end - start))
    }
    private static func intersects(_ ranges: [NSRange], _ target: NSRange) -> Bool {
        ranges.contains { NSIntersectionRange($0, target).length > 0 }
    }
    private static func isWhitespace(_ value: unichar) -> Bool {
        guard let scalar = UnicodeScalar(value) else { return false }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }
}

@MainActor
final class BOLDCrossDocumentAuditCoordinator {
    private let library: BOLDCrossDocumentLibraryProviding
    private let maximumQueries = 240
    private let maximumFindings = 1_500

    init(library: BOLDCrossDocumentLibraryProviding) { self.library = library }

    func run(
        selectedDocumentIDs: Set<UUID>,
        rules: [BOLDConsistencyRule],
        cancellation: BOLDAuditCancellationToken
    ) async -> BOLDCrossDocumentAuditResult? {
        let started = ProcessInfo.processInfo.systemUptime
        guard !cancellation.isCancelled, !selectedDocumentIDs.isEmpty else { return nil }
        // The canonical search API refreshes source fingerprints before returning
        // results. This one bounded probe makes the following source snapshot use
        // the current committed Library records.
        _ = try? library.refreshSources()
        let selectedRecords = library.documents.filter { selectedDocumentIDs.contains($0.id.rawValue) }
        let descriptors: [BOLDCrossDocumentSourceDescriptor] = selectedRecords.map { record in
            let url = record.isReference ? nil : (try? library.sourceURL(for: record.id)) ?? nil
            return BOLDCrossDocumentSourceDescriptor(
                id: record.id.rawValue, title: record.title, sourceURI: record.sourceURI,
                fingerprint: record.fingerprint, isReference: record.isReference,
                status: record.status.rawValue, url: url
            )
        }
        let worker = Task.detached(priority: .userInitiated) {
            BOLDCrossDocumentSnapshotter.scan(sources: descriptors, rules: rules) {
                cancellation.isCancelled || Task.isCancelled
            }
        }
        let snapshot = await worker.value
        guard !snapshot.cancelled, !cancellation.isCancelled else { return nil }

        let selectedIDs = selectedDocumentIDs
        let descriptorByID = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.id, $0) })
        let candidateGroups = Dictionary(grouping: snapshot.candidates.filter { !$0.query.isEmpty }, by: \.query)
        let queries = Array(candidateGroups.keys.sorted().prefix(maximumQueries))
        var resultsByQuery: [String: [KnowledgeSearchResult]] = [:]
        var staleCount = 0

        for (index, query) in queries.enumerated() {
            if cancellation.isCancelled { return nil }
            do {
                let matches = try library.search(query, limit: 1_000).filter {
                    selectedIDs.contains($0.document.id.rawValue)
                }
                var verified: [KnowledgeSearchResult] = []
                verified.reserveCapacity(min(matches.count, 1_000))
                for result in matches {
                    if cancellation.isCancelled { return nil }
                    guard let descriptor = descriptorByID[result.document.id.rawValue],
                          result.reference.fingerprint == descriptor.fingerprint else {
                        staleCount += 1
                        continue
                    }
                    let (status, range) = try library.resolve(result.reference)
                    guard (status == .current || status == .revalidated), range != nil else {
                        staleCount += 1
                        continue
                    }
                    verified.append(result)
                }
                resultsByQuery[query] = verified
            } catch {
                resultsByQuery[query] = []
            }
            // Store.search is synchronous and bounded. Yield between queries so
            // filtering, cancellation, and typing remain schedulable.
            if index.isMultiple(of: 2) { await Task.yield() }
        }
        guard !cancellation.isCancelled else { return nil }

        var findings: [BOLDCrossDocumentFinding] = []
        var emitted = Set<String>()
        for candidate in snapshot.candidates.prefix(maximumFindings * 4) {
            if cancellation.isCancelled { return nil }
            guard let matches = resultsByQuery[candidate.query] else { continue }
            let first = matches.first { result in
                result.document.id.rawValue == candidate.documentID
                    && contains(result.reference.utf16Range, candidate.range)
                    && result.reference.fingerprint == candidate.fingerprint
            }
            guard let first else { continue }

            if let otherID = candidate.comparisonDocumentID,
               let otherRange = candidate.comparisonRange,
               let otherFingerprint = candidate.comparisonFingerprint {
                guard let second = matches.first(where: {
                    $0.document.id.rawValue == otherID
                        && contains($0.reference.utf16Range, otherRange)
                        && $0.reference.fingerprint == otherFingerprint
                }) else { continue }
                let pairKey = [first.reference.passageID.uuidString, second.reference.passageID.uuidString].sorted().joined(separator: ":") + ":" + candidate.category.rawValue
                guard emitted.insert(pairKey).inserted else { continue }
                findings.append(makeFinding(candidate, primary: first, comparison: second))
                continue
            }

            if candidate.category == .dateReview || candidate.category == .nameReview || candidate.category == .sharedSubject {
                for second in matches where second.document.id.rawValue != candidate.documentID {
                    let pairKey = [first.reference.passageID.uuidString, second.reference.passageID.uuidString].sorted().joined(separator: ":") + ":" + candidate.category.rawValue
                    guard emitted.insert(pairKey).inserted else { continue }
                    findings.append(makeFinding(candidate, primary: first, comparison: second))
                    if findings.count >= maximumFindings { break }
                }
            } else {
                let key = first.reference.passageID.uuidString + ":" + candidate.category.rawValue + ":" + (candidate.ruleID?.uuidString ?? "")
                guard emitted.insert(key).inserted else { continue }
                findings.append(makeFinding(candidate, primary: first, comparison: nil))
            }
            if findings.count >= maximumFindings { break }
        }

        for unavailable in snapshot.unavailable {
            guard findings.count < maximumFindings else { break }
            let key = unavailable.id.uuidString + ":unavailable"
            guard emitted.insert(key).inserted else { continue }
            findings.append(BOLDCrossDocumentFinding(
                id: key, category: .unavailableDocument, confidence: .unavailableSource,
                primary: nil, comparison: nil, primaryTitle: unavailable.title,
                primaryExcerpt: unavailable.sourceURI, comparisonTitle: nil, comparisonExcerpt: nil,
                explanation: "This selected source could not be read at its recorded fingerprint. Its prior passage offsets were not used.",
                query: "", isQuoted: false
            ))
        }

        // Rule scans also cover Library reference notes that have no local
        // source URL to enumerate. Excerpts are rechecked with the same literal
        // scanner; no replacement is offered from this cross-document view.
        for rule in rules where rule.enabled {
            if cancellation.isCancelled { return nil }
            do {
                let matches = try library.search(rule.matchText, limit: 1_000).filter {
                    selectedIDs.contains($0.document.id.rawValue)
                }
                for result in matches {
                    if cancellation.isCancelled { return nil }
                    let literalFindings = BOLDConsistencyScanner().scan(
                        result.excerpt, rules: [rule], maximumFindings: 100
                    ).filter { $0.ruleID == rule.id }
                    guard let literal = literalFindings.first else { continue }
                    let stableKey = result.reference.passageID.uuidString + ":rule:" + rule.id.uuidString
                    guard emitted.insert(stableKey).inserted else { continue }
                    let (status, range) = try library.resolve(result.reference)
                    guard (status == .current || status == .revalidated), range != nil else {
                        staleCount += 1
                        continue
                    }
                    findings.append(BOLDCrossDocumentFinding(
                        id: stableKey, category: .terminology, confidence: .exactRuleViolation,
                        primary: result, comparison: nil, primaryTitle: result.document.title,
                        primaryExcerpt: result.excerpt, comparisonTitle: nil, comparisonExcerpt: nil,
                        explanation: rule.scope == .outsideQuotationMarks
                            ? "Exact preferred-term rule match in a Library excerpt. Imported quote metadata may be unavailable; inspect the source before making any change."
                            : (rule.explanation.isEmpty ? "Exact literal match for the saved project rule." : rule.explanation),
                        query: rule.matchText, isQuoted: literal.isInsideQuotationText
                    ))
                    if findings.count >= maximumFindings { break }
                }
            } catch { continue }
        }

        return BOLDCrossDocumentAuditResult(
            findings: findings,
            scannedDocumentCount: snapshot.scannedDocumentCount,
            unavailableDocumentCount: snapshot.unavailable.count,
            omittedPassageCount: snapshot.omittedPassageCount
                + max(0, snapshot.candidates.count - maximumQueries - maximumFindings),
            staleResultCount: staleCount,
            elapsed: ProcessInfo.processInfo.systemUptime - started
        )
    }

    private func makeFinding(
        _ candidate: BOLDCrossDocumentCandidate,
        primary: KnowledgeSearchResult,
        comparison: KnowledgeSearchResult?
    ) -> BOLDCrossDocumentFinding {
        let id = [primary.reference.passageID.uuidString, comparison?.reference.passageID.uuidString ?? "", candidate.category.rawValue, candidate.ruleID?.uuidString ?? ""].joined(separator: ":")
        return BOLDCrossDocumentFinding(
            id: id, category: candidate.category, confidence: candidate.confidence,
            primary: primary, comparison: comparison,
            primaryTitle: primary.document.title, primaryExcerpt: primary.excerpt,
            comparisonTitle: comparison?.document.title, comparisonExcerpt: comparison?.excerpt,
            explanation: candidate.explanation, query: candidate.query, isQuoted: candidate.isQuoted
        )
    }

    private func contains(_ container: NSRange, _ value: NSRange) -> Bool {
        guard container.location >= 0, value.location >= 0 else { return false }
        return value.location >= container.location && NSMaxRange(value) <= NSMaxRange(container)
    }
}

enum BOLDCrossDocumentReportExporter {
    static func markdown(
        title: String,
        findings: [BOLDCrossDocumentFinding],
        scannedDocumentCount: Int,
        omittedCount: Int,
        staleCount: Int,
        maximumFindings: Int = 250
    ) -> String {
        let prioritized = findings.sorted {
            let left = confidenceOrder($0.confidence), right = confidenceOrder($1.confidence)
            if left != right { return left < right }
            return $0.primaryTitle.localizedCaseInsensitiveCompare($1.primaryTitle) == .orderedAscending
        }
        let included = Array(prioritized.prefix(max(0, maximumFindings)))
        var lines = [
            "# Cross-Document Book Audit — \(title)", "",
            "Sources scanned: \(scannedDocumentCount) · Findings: \(findings.count) · Included: \(included.count) · Omitted: \(max(0, findings.count - included.count) + omittedCount) · Stale references rejected: \(staleCount)", "",
            "Date, name, and argument similarities are review candidates, not factual contradictions.",
            "Indexed sources are read-only. Finding a match does not change any manuscript.", ""
        ]
        for (index, finding) in included.enumerated() {
            lines += [
                "## \(index + 1). \(finding.category.rawValue) — \(finding.confidence.rawValue)", "",
                "- Source: \(finding.primaryTitle)",
                "- Canonical document ID: \(finding.primary?.document.id.rawValue.uuidString ?? "unavailable")",
                "- Passage ID: \(finding.primary?.reference.passageID.uuidString ?? "unavailable")",
                "- Location: \(finding.primary?.reference.context ?? "unavailable") · UTF-16 offset \(finding.primary?.reference.utf16Range.location.description ?? "unavailable")",
                "- Fingerprint: \(finding.primary?.reference.fingerprint ?? "unavailable")",
                "- Why flagged: \(finding.explanation)",
                "- Excerpt: `\(escape(finding.primaryExcerpt))`"
            ]
            if let comparison = finding.comparison {
                lines += [
                    "- Compared source: \(comparison.document.title)",
                    "- Compared canonical passage: \(comparison.reference.passageID.uuidString)",
                    "- Compared location: \(comparison.reference.context) · UTF-16 offset \(comparison.reference.utf16Range.location)",
                    "- Compared excerpt: `\(escape(comparison.excerpt))`"
                ]
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private static func confidenceOrder(_ value: BOLDCrossDocumentConfidence) -> Int {
        switch value {
        case .exactRuleViolation, .exactDuplicate: 0
        case .potentialInconsistency: 1
        case .unavailableSource: 2
        case .reviewSuggestion: 3
        }
    }
    private static func escape(_ value: String) -> String {
        String(value.prefix(260)).replacingOccurrences(of: "`", with: "'").replacingOccurrences(of: "\n", with: " ")
    }
}

enum BOLDAuditEvidenceSignal: String, CaseIterable, Sendable {
    case claimWithoutEvidence
    case onlyUnverifiedEvidence
    case referencedSourceUnavailable
    case sourceCitationUnresolved
    case evidenceRecordStale
    case internalLinkUnverified
}

struct BOLDAuditEvidenceSummary: Sendable, Equatable {
    let documentID: UUID
    let claimID: UUID?
    let signal: BOLDAuditEvidenceSignal
    let explanation: String
}

/// Codex B has not yet committed a project-wide read-only evidence summary API.
/// M3 depends on this seam and keeps the UI explicitly pending until that API is
/// available. Tests can exercise the display model without inventing evidence.
@MainActor
protocol BOLDAuditEvidenceSummaryProviding {
    var integrationAvailable: Bool { get }
    func summaries(for documentIDs: Set<UUID>) async -> [BOLDAuditEvidenceSummary]
}


