import Foundation

enum EvidenceReviewVerificationFilter: String, CaseIterable, Identifiable {
    case all = "All verification states"
    case verified = "Verified passage"
    case unverified = "User-entered / unverified"
    case warnings = "Warnings"

    var id: String { rawValue }
}

struct EvidenceReviewClaim: Identifiable, Equatable {
    var id: String { "\(range.location):\(range.length)" }
    var text: String
    var range: NSRange
    var chapter: String
    var evidence: [ClaimEvidence]
    var unresolvedEvidence: [ClaimEvidence]
    var matchingCitationSourceIDs: Set<UUID>
    var outdatedCitationSourceIDs: Set<UUID>
    var ambiguousCitationDisplays: [String]

    var hasRecordedEvidence: Bool { !evidence.isEmpty }
}

enum EvidenceReviewIndex {
    /// Builds a mechanical coverage inventory from sentence ranges. It does not
    /// decide whether a sentence is a claim or whether evidence supports it.
    static func claims(
        in manuscript: String,
        evidence: [ClaimEvidence],
        sources: [CitationSource],
        style: CitationStyle,
        outline: [OutlineItem] = [],
        limit: Int? = nil
    ) -> [EvidenceReviewClaim] {
        let ns = manuscript as NSString
        guard ns.length > 0 else { return [] }

        var sentenceRanges: [NSRange] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.bySentences, .substringNotRequired]) { _, range, _, stop in
            let trimmed = Self.trimmedRange(range, in: ns)
            if trimmed.length > 0 { sentenceRanges.append(trimmed) }
            if let limit, sentenceRanges.count >= limit { stop.pointee = true }
        }
        if sentenceRanges.isEmpty {
            let trimmed = trimmedRange(NSRange(location: 0, length: ns.length), in: ns)
            if trimmed.length > 0 { sentenceRanges = [trimmed] }
        }

        // Bibliography entries are reference data, not author claim candidates.
        // Stop claim inventory at conventional reference-section headings so
        // inserted or imported bibliographies do not inflate uncovered counts.
        let referenceSectionStart = sentenceRanges.first { range in
            let heading = ns.substring(with: range)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: ".:"))
                .lowercased()
            return ["references", "bibliography", "works cited", "works consulted", "sources"].contains(heading)
        }.map(\.location)

        let resolved = evidence.map { item -> (ClaimEvidence, NSRange?) in
            (item, Self.resolve(item.anchor, in: ns))
        }
        var evidenceBySentence: [Int: [ClaimEvidence]] = [:]
        var unresolved: [ClaimEvidence] = []
        for (item, range) in resolved {
            guard let range,
                  let sentenceIndex = sentenceRanges.firstIndex(where: { NSLocationInRange(range.location, $0) && NSMaxRange(range) <= NSMaxRange($0) }) else {
                if limit != nil, let last = sentenceRanges.last,
                   item.anchor.utf16Location >= NSMaxRange(last) { continue }
                unresolved.append(item)
                continue
            }
            evidenceBySentence[sentenceIndex, default: []].append(item)
        }

        let chapterHeadings = outline.filter { $0.level == 1 || $0.level == 2 }.sorted { $0.range.location < $1.range.location }
        return sentenceRanges.enumerated().compactMap { index, range in
            if let referenceSectionStart, range.location >= referenceSectionStart { return nil }
            let text = ns.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !Self.isHeading(text, outline: outline, range: range) else { return nil }
            let chapter = chapterHeadings.last(where: { $0.range.location <= range.location })?.title ?? "Document"
            let attached = evidenceBySentence[index] ?? []
            let citationMatches = DocumentCitations.citedSourceResolution(in: text, sources: sources, style: style)
            return EvidenceReviewClaim(
                text: text,
                range: range,
                chapter: chapter,
                evidence: attached,
                unresolvedEvidence: [],
                matchingCitationSourceIDs: citationMatches.citedSourceIDs,
                outdatedCitationSourceIDs: citationMatches.outdatedCitationSourceIDs,
                ambiguousCitationDisplays: citationMatches.ambiguousDisplays
            )
        } + unresolved.enumerated().map { index, item in
            EvidenceReviewClaim(
                text: item.anchor.selectedText,
                range: NSRange(location: item.anchor.utf16Location, length: item.anchor.utf16Length),
                chapter: "Unresolved anchor",
                evidence: [item],
                unresolvedEvidence: [item],
                matchingCitationSourceIDs: [],
                outdatedCitationSourceIDs: [],
                ambiguousCitationDisplays: []
            )
        }
    }

    private static func resolve(_ anchor: ClaimAnchor, in text: NSString) -> NSRange? {
        if anchor.utf16Location >= 0, anchor.utf16Length >= 0,
           NSMaxRange(NSRange(location: anchor.utf16Location, length: anchor.utf16Length)) <= text.length,
           text.substring(with: NSRange(location: anchor.utf16Location, length: anchor.utf16Length)) == anchor.selectedText {
            return NSRange(location: anchor.utf16Location, length: anchor.utf16Length)
        }
        let first = text.range(of: anchor.selectedText)
        guard first.location != NSNotFound else { return nil }
        let next = text.range(of: anchor.selectedText, options: [], range: NSRange(location: NSMaxRange(first), length: text.length - NSMaxRange(first)))
        return next.location == NSNotFound ? first : nil
    }

    private static func trimmedRange(_ range: NSRange, in text: NSString) -> NSRange {
        var start = range.location
        var end = NSMaxRange(range)
        let trimmingCharacters = CharacterSet.whitespacesAndNewlines.union(.controlCharacters)
        while start < end {
            guard let scalar = UnicodeScalar(text.character(at: start)), trimmingCharacters.contains(scalar) else { break }
            start += 1
        }
        while end > start {
            guard let scalar = UnicodeScalar(text.character(at: end - 1)), trimmingCharacters.contains(scalar) else { break }
            end -= 1
        }
        return NSRange(location: start, length: end - start)
    }

    private static func isHeading(_ text: String, outline: [OutlineItem], range: NSRange) -> Bool {
        outline.contains { $0.range.location == range.location || $0.title.trimmingCharacters(in: .whitespacesAndNewlines) == text }
    }

}

struct EvidenceAuditSummary: Equatable {
    var claimCount: Int
    var claimsWithoutEvidence: Int
    var claimsWithOnlyUnverifiedEvidence: Int
    var challengingEvidenceCount: Int
    var unresolvedAnchorCount: Int
    var missingSourceCount: Int
    var stalePassageCount: Int
    var citationMetadataHintCount: Int
}

/// Read-only contract for future manuscript audits. Counts evidence coverage
/// and provenance warnings; it makes no claim-truth or prose-quality finding.
@MainActor enum EvidenceAuditSummaryProvider {
    static func summary(manuscript: String, evidence: [ClaimEvidence], sources: [CitationSource]) -> EvidenceAuditSummary {
        let sourceIDs = Set(sources.map(\.id))
        let claims = EvidenceReviewIndex.claims(in: manuscript, evidence: evidence, sources: sources, style: .apa)
        let sourceByID = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
        var missingSources = 0
        var stale = 0
        var unverifiedOnly = 0
        for claim in claims where !claim.evidence.isEmpty {
            if claim.evidence.allSatisfy({ $0.verificationStatus == .unverified }) { unverifiedOnly += 1 }
            for item in claim.evidence {
                guard sourceIDs.contains(item.sourceID), let source = sourceByID[item.sourceID] else { missingSources += 1; continue }
                if let path = EvidenceVerification.resolvedLocalURL(for: source), !FileManager.default.fileExists(atPath: path.path) { missingSources += 1 }
                if let reference = item.libraryPassageReference,
                   KnowledgeLibraryEvidenceAdapter().resolve(reference, exactQuotation: item.quotation, revalidateDisk: false).status == .stale { stale += 1 }
            }
        }
        let metadataHints = sources.reduce(0) { $0 + DocumentCitations.metadataHints(for: $1).count }
        return EvidenceAuditSummary(
            claimCount: claims.count,
            claimsWithoutEvidence: claims.filter { $0.evidence.isEmpty && $0.unresolvedEvidence.isEmpty }.count,
            claimsWithOnlyUnverifiedEvidence: unverifiedOnly,
            challengingEvidenceCount: evidence.filter { $0.kind == .challenging }.count,
            unresolvedAnchorCount: claims.reduce(0) { $0 + $1.unresolvedEvidence.count },
            missingSourceCount: missingSources,
            stalePassageCount: stale,
            citationMetadataHintCount: metadataHints
        )
    }
}

@MainActor enum EvidenceResearchReport {
    static let maximumClaims = 500
    static let maximumEvidenceEntries = 1_000

    static func markdown(manuscript: String, evidence: [ClaimEvidence], sources: [CitationSource], style: CitationStyle, outline: [OutlineItem] = []) -> String {
        let claims = EvidenceReviewIndex.claims(in: manuscript, evidence: evidence, sources: sources, style: style, outline: outline, limit: maximumClaims + 1)
        let isLimited = claims.count > maximumClaims
        let boundedClaims = Array(claims.prefix(maximumClaims))
        var lines = ["# Research and Evidence Review", "", "Generated locally by BOLD Writer. Coverage and quotation checks do not determine whether a claim is true or whether a source genuinely supports it.", "", "- Claims/passages inventoried: \(isLimited ? "at least \(claims.count)" : "\(claims.count)")", "- Claims/passages without recorded evidence in this report: \(boundedClaims.filter { $0.evidence.isEmpty }.count)", "- Challenging evidence associations in the document: \(evidence.filter { $0.kind == .challenging }.count)", "- Citation style setting: \(style.rawValue) (citation-format support is limited to the current BOLD Writer formatter)", ""]
        let sourceByID = Dictionary(sources.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var refreshedDocumentIDs = Set<KnowledgeDocumentID>()
        var remainingEvidence = maximumEvidenceEntries
        var emittedEvidence = 0
        for claim in boundedClaims {
            lines.append("## \(claim.chapter) — \(claim.text)")
            lines.append("")
            if !claim.outdatedCitationSourceIDs.isEmpty {
                lines.append("Citation status: display is out of date for source metadata. Manuscript text was left unchanged until author action.")
            } else if !claim.ambiguousCitationDisplays.isEmpty {
                lines.append("Citation status: ambiguous inline display(s): \(claim.ambiguousCitationDisplays.joined(separator: ", ")).")
            } else if claim.matchingCitationSourceIDs.isEmpty {
                lines.append("Citation status: no unambiguous formatted citation detected in this passage.")
            } else {
                lines.append("Citation status: \(claim.matchingCitationSourceIDs.count) source record(s) match the current formatted citation text.")
            }
            lines.append("")
            if claim.evidence.isEmpty { lines.append("No evidence recorded in BOLD Writer. This is not a finding that the passage is false or unsupported.") }
            for item in claim.evidence.prefix(remainingEvidence) {
                remainingEvidence -= 1
                emittedEvidence += 1
                guard let source = sourceByID[item.sourceID] else {
                    lines.append("- **\(item.kind.rawValue)** — Missing source record `\(item.sourceID.uuidString)`; quotation: “\(item.quotation)”")
                    continue
                }
                let report = EvidenceVerification.report(for: source, evidence: item, manuscript: manuscript)
                var findings = report.findings
                var libraryStatus: EvidenceLibraryReferenceStatus?
                if let reference = item.libraryPassageReference {
                    let documentID = (try? JSONDecoder().decode(KnowledgePassageReference.self, from: reference))?.documentID
                    let refresh = documentID.map { refreshedDocumentIDs.insert($0).inserted } ?? true
                    let resolved = KnowledgeLibraryEvidenceAdapter().resolve(reference, exactQuotation: item.quotation, revalidateDisk: refresh)
                    libraryStatus = resolved.status
                    if resolved.status == .current || resolved.status == .revalidated {
                        findings.removeAll { $0 == .userEnteredNotVerified }
                    }
                }
                let status = findings.map(\.label).joined(separator: "; ").ifEmpty("User-entered evidence, not verified")
                let location = item.sourceLocation.isEmpty ? "Location not recorded" : item.sourceLocation
                lines.append("- **\(item.kind.rawValue)** — \(source.title.isEmpty ? "Untitled source" : source.title) (`\(source.id.uuidString)`), \(location). Verification: \(status). Quotation: “\(item.quotation)”")
                if item.libraryPassageReference != nil {
                    lines.append("  - Knowledge Library passage: \(libraryStatus?.rawValue ?? "unresolved")")
                }
                if !item.authorNote.isEmpty { lines.append("  - Research note: \(item.authorNote)") }
            }
            lines.append("")
        }
        let citationResolution = DocumentCitations.citedSourceResolution(in: manuscript, sources: sources, style: style)
        lines.append("## Citation and source record review")
        lines.append("")
        lines.append("- Source records: \(sources.count)")
        lines.append("- Unambiguously detected cited sources: \(citationResolution.citedSourceIDs.count)")
        lines.append("- Citation displays needing author refresh: \(citationResolution.outdatedCitationSourceIDs.count)")
        if !citationResolution.ambiguousDisplays.isEmpty { lines.append("- Ambiguous inline citation displays: \(citationResolution.ambiguousDisplays.joined(separator: ", "))") }
        for source in sources {
            let warnings = DocumentCitations.metadataHints(for: source)
            let pathExists = EvidenceVerification.resolvedLocalURL(for: source).map { FileManager.default.fileExists(atPath: $0.path) }
            let availability = pathExists == false ? "Missing local source" : source.sourceAvailability?.rawValue ?? "Availability unknown"
            let warningText = warnings.isEmpty ? "No basic metadata hints" : warnings.joined(separator: "; ")
            lines.append("- `\(source.id.uuidString)` — \(source.title.isEmpty ? "Untitled source" : source.title); \(availability); \(warningText)")
        }
        if isLimited { lines.append("\n> Limited output: report capped at \(maximumClaims) entries. At least one additional passage was omitted; the manuscript was not fully listed in this report.") }
        if evidence.count > emittedEvidence { lines.append("> Limited output: omitted \(evidence.count - emittedEvidence) evidence associations beyond the \(maximumEvidenceEntries)-entry report limit.") }
        return lines.joined(separator: "\n")
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
