import AppKit
import CryptoKit
import Foundation
import PDFKit

enum EvidenceKind: String, Codable, CaseIterable, Identifiable {
    case supporting = "Supporting"
    case challenging = "Challenging"
    case contextual = "Contextual / Background"
    var id: String { rawValue }
}

enum EvidenceVerificationStatus: String, Codable, CaseIterable, Identifiable {
    case unverified = "Unverified"
    case authorChecked = "Author checked"
    case independentlyVerified = "Independently verified"
    var id: String { rawValue }
}

enum EvidenceSourceAvailability: String, Codable, CaseIterable, Identifiable {
    case available = "Available"
    case missing = "Missing"
    case inaccessible = "Inaccessible"
    case remoteOnly = "Remote only"
    var id: String { rawValue }
}

enum EvidenceVerificationFinding: String, Codable, CaseIterable, Hashable, Identifiable {
    case verifiedPassage
    case userEnteredNotVerified
    case changedSource
    case missingSource
    case quotationMismatch
    case unsupportedSourceFormat
    case staleLocation
    case unresolvedClaim

    var id: String { rawValue }

    var label: String {
        switch self {
        case .verifiedPassage: "Quotation found in current source"
        case .userEnteredNotVerified: "User-entered evidence, not verified against source"
        case .changedSource: "Source changed since its fingerprint was recorded"
        case .missingSource: "Source is missing or cannot be read"
        case .quotationMismatch: "Quotation does not match the source"
        case .unsupportedSourceFormat: "Source format cannot be searched for quotations"
        case .staleLocation: "Recorded page does not contain the quotation"
        case .unresolvedClaim: "Manuscript claim anchor changed or cannot be resolved"
        }
    }
}

struct EvidenceSourceVerificationReport: Equatable {
    var findings: [EvidenceVerificationFinding]
    /// One-based only when PDF text extraction locates the exact quotation.
    var verifiedPDFPage: Int?

    var quotationWasFound: Bool { findings.contains(.verifiedPassage) }
    var assertsArgumentTruth: Bool { false }
}

struct ClaimAnchor: Codable, Equatable {
    var selectedText: String
    var utf16Location: Int
    var utf16Length: Int
    var precedingContext: String
    var followingContext: String
    var selectedTextSHA256: String

    static func make(text: String, range: NSRange) -> ClaimAnchor? {
        let nsText = text as NSString
        guard range.location != NSNotFound, range.length > 0,
              range.location <= nsText.length, range.length <= nsText.length - range.location else { return nil }
        let contextLength = 48
        let beforeStart = max(0, range.location - contextLength)
        let afterStart = NSMaxRange(range)
        let selected = nsText.substring(with: range)
        return ClaimAnchor(
            selectedText: selected,
            utf16Location: range.location,
            utf16Length: range.length,
            precedingContext: nsText.substring(with: NSRange(location: beforeStart, length: range.location - beforeStart)),
            followingContext: nsText.substring(with: NSRange(location: afterStart, length: min(contextLength, nsText.length - afterStart))),
            selectedTextSHA256: EvidenceVerification.sha256(Data(selected.utf8))
        )
    }

    func resolves(in manuscript: String) -> Bool {
        let value = manuscript as NSString
        if utf16Location <= value.length, utf16Length <= value.length - utf16Location,
           value.substring(with: NSRange(location: utf16Location, length: utf16Length)) == selectedText { return true }
        return value.range(of: selectedText).location != NSNotFound
    }

    func identifiesSameSelection(as other: ClaimAnchor) -> Bool {
        utf16Location == other.utf16Location &&
            utf16Length == other.utf16Length &&
            selectedTextSHA256 == other.selectedTextSHA256 &&
            selectedText == other.selectedText
    }
}

struct ClaimEvidence: Codable, Identifiable, Equatable {
    var id = UUID()
    var anchor: ClaimAnchor
    var sourceID: UUID
    var kind: EvidenceKind
    var quotation: String
    var sourceLocation: String
    var authorNote: String
    var verificationStatus: EvidenceVerificationStatus
    // JSON-encoded canonical KnowledgePassageReference. Kept opaque here so
    // this feature compiles before Codex A's source is integrated.
    var libraryPassageReference: Data? = nil
}

struct EvidenceLibraryPassageLink: Codable, Equatable {
    var documentReference: String
    var passageReference: Data
}

enum EvidenceLibraryReferenceStatus: String, Codable {
    case current, revalidated, stale, unresolved
}

struct EvidenceLibraryReferenceResolution: Codable, Equatable {
    var status: EvidenceLibraryReferenceStatus
    var verifiedLocation: String?
}

/// Narrow seam for the canonical Knowledge Library. This feature stores only
/// opaque references and does not own, index, or duplicate library documents.
@MainActor protocol EvidenceLibraryReferenceResolving {
    func passageReference(for source: CitationSource, exactQuotation: String) -> EvidenceLibraryPassageLink?
    func resolve(_ serializedReference: Data) -> EvidenceLibraryReferenceResolution
}

enum EvidenceVerification {
    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func sourceWarnings(for source: CitationSource, evidence: ClaimEvidence, manuscript: String) -> [String] {
        let report = report(for: source, evidence: evidence, manuscript: manuscript)
        return report.findings.compactMap { finding in
            switch finding {
            case .unresolvedClaim: "The manuscript passage changed or moved."
            case .missingSource: "The source file is missing."
            case .changedSource: "The source file changed since it was recorded."
            case .quotationMismatch: "The saved quotation was not found in the current source text."
            case .staleLocation: "The saved page reference does not contain the quotation."
            case .unsupportedSourceFormat: "The source format cannot be searched for quotations."
            case .userEnteredNotVerified: "The quotation or location has not been verified against a local source."
            case .verifiedPassage: nil
            }
        }
    }

    static func report(for source: CitationSource, evidence: ClaimEvidence, manuscript: String) -> EvidenceSourceVerificationReport {
        var findings = Set<EvidenceVerificationFinding>()
        var verifiedPage: Int?
        if !evidence.anchor.resolves(in: manuscript) { findings.insert(.unresolvedClaim) }
        if let path = resolvedLocalURL(for: source) {
            let startedAccess = path.startAccessingSecurityScopedResource()
            defer { if startedAccess { path.stopAccessingSecurityScopedResource() } }
            guard FileManager.default.fileExists(atPath: path.path) else {
                findings.insert(.missingSource)
                return makeReport(findings, verifiedPage)
            }
            do {
                let data = try Data(contentsOf: path, options: [.mappedIfSafe])
                if let expected = source.contentFingerprint, expected != sha256(data) { findings.insert(.changedSource) }
                let matches = try quotationMatches(in: path, quotation: evidence.quotation)
                if matches.pages.isEmpty {
                    if matches.supported { findings.insert(.quotationMismatch) }
                    else { findings.insert(.unsupportedSourceFormat) }
                } else {
                    findings.insert(.verifiedPassage)
                    verifiedPage = path.pathExtension.lowercased() == "pdf" ? matches.pages.first : nil
                    if let statedPage = pageNumber(in: evidence.sourceLocation), !matches.pages.contains(statedPage) {
                        findings.insert(.staleLocation)
                    } else if pageNumber(in: evidence.sourceLocation) == nil {
                        findings.insert(.userEnteredNotVerified)
                    }
                }
            } catch {
                findings.insert(.missingSource)
            }
        } else if !(source.url.isEmpty) {
            if URL(string: source.url)?.scheme == nil { findings.insert(.missingSource) }
            else { findings.insert(.userEnteredNotVerified) }
        } else if source.localFilePath != nil {
            findings.insert(.missingSource)
        } else if source.sourceAvailability == .inaccessible || source.sourceAvailability == .missing {
            findings.insert(.missingSource)
        } else {
            findings.insert(.userEnteredNotVerified)
        }
        return makeReport(findings, verifiedPage)
    }

    private static func makeReport(_ findings: Set<EvidenceVerificationFinding>, _ page: Int?) -> EvidenceSourceVerificationReport {
        EvidenceSourceVerificationReport(findings: EvidenceVerificationFinding.allCases.filter(findings.contains), verifiedPDFPage: page)
    }

    private struct QuotationMatches { var supported: Bool; var pages: [Int] }

    private static func quotationMatches(in url: URL, quotation: String) throws -> QuotationMatches {
        guard !quotation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return QuotationMatches(supported: true, pages: []) }
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" {
            guard let pdf = PDFDocument(url: url), pdf.pageCount > 0 else { return QuotationMatches(supported: false, pages: []) }
            let pages = (0..<pdf.pageCount).compactMap { index -> Int? in
                guard let text = pdf.page(at: index)?.string, containsExactQuote(quotation, in: text) else { return nil }
                return index + 1
            }
            return QuotationMatches(supported: pdf.string != nil, pages: pages)
        }

        let text: String?
        switch ext {
        case "txt", "md", "markdown":
            text = try? String(contentsOf: url, encoding: .utf8)
        case "docx", "boldwriter":
            let wrapper = try FileWrapper(url: url)
            let type = BOLDWriterDocument.inferredContentType(for: url)
            text = try BOLDWriterDocument(fileWrapper: wrapper, contentType: type).text.string
        case "rtf", "rtfd":
            text = try? NSAttributedString(url: url, options: [:], documentAttributes: nil).string
        default:
            return QuotationMatches(supported: false, pages: [])
        }
        guard let text else { return QuotationMatches(supported: false, pages: []) }
        return QuotationMatches(supported: true, pages: containsExactQuote(quotation, in: text) ? [1] : [])
    }

    private static func containsExactQuote(_ quotation: String, in sourceText: String) -> Bool {
        func normalized(_ text: String) -> String {
            text.precomposedStringWithCanonicalMapping
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
        }
        let needle = normalized(quotation)
        return !needle.isEmpty && normalized(sourceText).range(of: needle) != nil
    }

    static func resolvedLocalURL(for source: CitationSource) -> URL? {
        if let bookmark = source.fileBookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale), !stale { return url }
        }
        guard let path = source.localFilePath, !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    private static func pageNumber(in location: String) -> Int? {
        // Do not interpret arbitrary ordinal locations such as "paragraph 1"
        // as page references. Only recognize explicit page labels.
        let pattern = #"(?i)\b(?:page|p\.|pp\.)\s*(\d+)\b"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: location, range: NSRange(location: 0, length: (location as NSString).length)),
              let numberRange = Range(match.range(at: 1), in: location) else { return nil }
        return Int(location[numberRange])
    }

    static func open(_ source: CitationSource) -> Bool {
        if let local = resolvedLocalURL(for: source) {
            guard FileManager.default.fileExists(atPath: local.path) else { return false }
            return NSWorkspace.shared.open(local)
        }
        guard let url = URL(string: source.url), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return false }
        return NSWorkspace.shared.open(url)
    }
}

enum DocumentEvidence {
    static func upsert(_ draft: ClaimEvidence, editing recordID: UUID?, in existing: [ClaimEvidence]) -> (records: [ClaimEvidence], selectedID: UUID) {
        var records = existing
        if let recordID, let index = records.firstIndex(where: { $0.id == recordID }), records[index].sourceID == draft.sourceID {
            var replacement = draft
            replacement.id = recordID
            records[index] = replacement
            return (records, recordID)
        }
        // Choosing a different source starts a separate association. The old
        // evidence and any citation text that points at its source stay intact.
        records.append(draft)
        return (records, draft.id)
    }

    static func duplicateSourceIDs(in sources: [CitationSource]) -> [[UUID]] {
        let groups = Dictionary(grouping: sources) { source in
            let stableLocator = EvidenceVerification.resolvedLocalURL(for: source) != nil || !source.url.isEmpty
                ? DocumentCitations.canonicalBibliographyKey(for: source)
                : [source.author, source.title, source.year, source.publisher, source.containerTitle]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .joined(separator: "\u{1f}")
            return stableLocator
        }
        return groups.values.filter { $0.count > 1 }.map { $0.map(\.id) }
    }

    /// Only merges source records that resolve to the exact same stable local
    /// file or exact same canonical URI. Matching titles/authors are only a
    /// possible duplicate and are not sufficient identity proof.
    static func canSafelyMerge(_ first: CitationSource, _ second: CitationSource) -> Bool {
        guard CitationStyle.allCases.allSatisfy({
            CitationFormatter.citation(for: first, style: $0) == CitationFormatter.citation(for: second, style: $0)
        }) else { return false }
        if let a = EvidenceVerification.resolvedLocalURL(for: first),
           let b = EvidenceVerification.resolvedLocalURL(for: second) {
            return a.standardizedFileURL.path == b.standardizedFileURL.path
        }
        guard !first.url.isEmpty, !second.url.isEmpty,
              let a = URL(string: first.url), let b = URL(string: second.url) else { return false }
        return a.standardizedFileURL.absoluteString == b.standardizedFileURL.absoluteString
    }

    static func mergeSourceRecords(keeping keepID: UUID, removing removeID: UUID, sources: [CitationSource], evidence: [ClaimEvidence]) throws -> (sources: [CitationSource], evidence: [ClaimEvidence]) {
        guard keepID != removeID,
              let keep = sources.first(where: { $0.id == keepID }),
              let remove = sources.first(where: { $0.id == removeID }),
              canSafelyMerge(keep, remove) else {
            throw WriterError.message("These source records do not resolve to the same stable source. Merge was not performed.")
        }
        var merged = keep
        if merged.author.isEmpty { merged.author = remove.author }
        if merged.title.isEmpty { merged.title = remove.title }
        if merged.year.isEmpty { merged.year = remove.year }
        if merged.publisher.isEmpty { merged.publisher = remove.publisher }
        if merged.containerTitle.isEmpty { merged.containerTitle = remove.containerTitle }
        if merged.url.isEmpty { merged.url = remove.url }
        if merged.publicationDate == nil { merged.publicationDate = remove.publicationDate }
        if merged.sourceLocation == nil { merged.sourceLocation = remove.sourceLocation }
        if merged.quotation == nil { merged.quotation = remove.quotation }
        if merged.researchNotes == nil { merged.researchNotes = remove.researchNotes }
        if merged.localFilePath == nil { merged.localFilePath = remove.localFilePath }
        if merged.fileBookmark == nil { merged.fileBookmark = remove.fileBookmark }
        if merged.contentFingerprint == nil { merged.contentFingerprint = remove.contentFingerprint }
        if merged.verificationStatus == nil { merged.verificationStatus = remove.verificationStatus }
        if merged.sourceAvailability == nil { merged.sourceAvailability = remove.sourceAvailability }
        let updatedEvidence = evidence.map { item -> ClaimEvidence in
            var value = item
            if value.sourceID == removeID { value.sourceID = keepID }
            return value
        }
        let updatedSources = sources.compactMap { source -> CitationSource? in
            if source.id == keepID { return merged }
            return source.id == removeID ? nil : source
        }
        return (updatedSources, updatedEvidence)
    }

    static func validate(_ evidence: [ClaimEvidence], sources: [CitationSource]) throws {
        let sourceIDs = Set(sources.map(\.id))
        var ids = Set<UUID>()
        for item in evidence {
            guard ids.insert(item.id).inserted else { throw WriterError.message("The document contains duplicate evidence identifiers.") }
            guard sourceIDs.contains(item.sourceID) else { throw WriterError.message("An evidence record refers to a missing citation source.") }
            guard !item.quotation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw WriterError.message("Evidence quotations cannot be empty.") }
        }
    }
}
