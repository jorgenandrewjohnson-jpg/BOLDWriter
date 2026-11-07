import AppKit
import SwiftUI

struct EvidenceReviewView: View {
    let manuscript: String
    let sources: [CitationSource]
    let evidence: [ClaimEvidence]
    let style: CitationStyle
    let outline: [OutlineItem]
    let onNavigateToClaim: (NSRange) -> Void
    let onAttachEvidence: (NSRange) -> Void
    let onUpdateCitations: (NSRange) -> Int

    @Environment(\.dismiss) private var dismiss
    @State private var chapterFilter = "All chapters"
    @State private var kindFilter = "All evidence types"
    @State private var verificationFilter: EvidenceReviewVerificationFilter = .all
    @State private var sourceFilter = "All sources"
    @State private var selectedClaimID: String?
    @State private var reportMessage: String?
    @State private var verifiedEvidenceIDs: Set<UUID> = []
    @State private var verificationFindingsByEvidenceID: [UUID: Set<EvidenceVerificationFinding>] = [:]
    @State private var verificationCacheLoaded = false
    @State private var citationUpdateRange: NSRange?
    @State private var showingCitationUpdateConfirmation = false

    @State private var claims: [EvidenceReviewClaim]

    init(manuscript: String, sources: [CitationSource], evidence: [ClaimEvidence], style: CitationStyle, outline: [OutlineItem], onNavigateToClaim: @escaping (NSRange) -> Void, onAttachEvidence: @escaping (NSRange) -> Void, onUpdateCitations: @escaping (NSRange) -> Int) {
        self.manuscript = manuscript
        self.sources = sources
        self.evidence = evidence
        self.style = style
        self.outline = outline
        self.onNavigateToClaim = onNavigateToClaim
        self.onAttachEvidence = onAttachEvidence
        self.onUpdateCitations = onUpdateCitations
        _claims = State(initialValue: EvidenceReviewIndex.claims(in: manuscript, evidence: evidence, sources: sources, style: style, outline: outline))
    }

    private var chapters: [String] { ["All chapters"] + Array(Set(claims.map(\.chapter))).sorted() }
    private var sourceOptions: [CitationSource] { sources.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending } }

    private var filteredClaims: [EvidenceReviewClaim] {
        claims.filter { claim in
            guard chapterFilter == "All chapters" || claim.chapter == chapterFilter else { return false }
            guard sourceFilter == "All sources" || claim.evidence.contains(where: { $0.sourceID.uuidString == sourceFilter }) || claim.matchingCitationSourceIDs.contains(where: { $0.uuidString == sourceFilter }) else { return false }
            if kindFilter != "All evidence types" {
                guard claim.evidence.contains(where: { $0.kind.rawValue == kindFilter }) else { return false }
            }
            switch verificationFilter {
            case .all: break
            case .verified:
                guard claim.evidence.contains(where: { verifiedEvidenceIDs.contains($0.id) }) else { return false }
            case .unverified:
                guard claim.evidence.isEmpty || claim.evidence.allSatisfy({ !verifiedEvidenceIDs.contains($0.id) }) else { return false }
            case .warnings:
                guard !claim.unresolvedEvidence.isEmpty || !claim.outdatedCitationSourceIDs.isEmpty || claim.evidence.contains(where: { record in
                    guard let source = sources.first(where: { $0.id == record.sourceID }) else { return true }
                    if let local = EvidenceVerification.resolvedLocalURL(for: source), !FileManager.default.fileExists(atPath: local.path) { return true }
                    return !(verificationFindingsByEvidenceID[record.id] ?? []).isDisjoint(with: [.changedSource, .missingSource, .quotationMismatch, .unsupportedSourceFormat, .staleLocation, .unresolvedClaim])
                }) else { return false }
            }
            return true
        }
    }

    private var selectedClaim: EvidenceReviewClaim? {
        filteredClaims.first(where: { $0.id == selectedClaimID }) ?? filteredClaims.first
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Evidence Review").font(.title2.bold())
                    Text("Review recorded evidence coverage and provenance across this document.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Export Report…", action: exportReport)
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(14)
            Divider()
            HStack(spacing: 10) {
                Picker("Chapter", selection: $chapterFilter) {
                    ForEach(chapters, id: \.self) { Text($0).tag($0) }
                }.frame(maxWidth: 210)
                Picker("Evidence type", selection: $kindFilter) {
                    Text("All evidence types").tag("All evidence types")
                    ForEach(EvidenceKind.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }.frame(maxWidth: 190)
                Picker("Verification", selection: $verificationFilter) {
                    ForEach(EvidenceReviewVerificationFilter.allCases) { Text($0.rawValue).tag($0) }
                }.frame(maxWidth: 220)
                Picker("Source", selection: $sourceFilter) {
                    Text("All sources").tag("All sources")
                    ForEach(sourceOptions) { Text($0.title.isEmpty ? "Untitled source" : $0.title).tag($0.id.uuidString) }
                }.frame(maxWidth: 190)
            }.padding(.horizontal, 14).padding(.vertical, 8)
            Divider()
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Claim inventory").font(.headline)
                        Spacer()
                        Text("\(filteredClaims.count) / \(claims.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    List(selection: $selectedClaimID) {
                        ForEach(filteredClaims) { claim in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(claim.text).lineLimit(3)
                                HStack(spacing: 6) {
                                    Text(claim.chapter)
                                    Text("·")
                                    Text(claim.unresolvedEvidence.isEmpty ? (claim.evidence.isEmpty ? "No recorded evidence" : "\(claim.evidence.count) evidence item(s)") : "Unresolved manuscript anchor")
                                }.font(.caption).foregroundStyle(claim.evidence.isEmpty ? .orange : .secondary)
                            }.tag(claim.id).padding(.vertical, 3)
                        }
                    }.listStyle(.inset)
                    Text("No recorded evidence means BOLD Writer has no attached source for this passage; it does not mean the claim is unsupported or false.")
                        .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(12).frame(width: 370)
                Divider()
                detail
            }
            if let reportMessage { Text(reportMessage).font(.caption).foregroundStyle(.secondary).padding(8) }
        }
        .frame(minWidth: 980, minHeight: 620)
        .onChange(of: filteredClaims.map(\.id)) { _, ids in
            if !ids.contains(selectedClaimID ?? "") { selectedClaimID = ids.first }
        }
        .onChange(of: selectedClaimID) { _, id in
            if let claim = filteredClaims.first(where: { $0.id == id }) { onNavigateToClaim(claim.range) }
        }
        .onChange(of: verificationFilter) { _, filter in
            if filter != .all { loadVerificationCacheIfNeeded() }
        }
        .alert("Update citation display?", isPresented: $showingCitationUpdateConfirmation) {
            Button("Update citation text", role: .destructive) {
                if let citationUpdateRange {
                    let count = onUpdateCitations(citationUpdateRange)
                    reportMessage = count > 0 ? "Updated \(count) citation(s). The manuscript edit can be undone." : "No uniquely mapped citation text was safe to update."
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("BOLD Writer will replace exact old citation display text in this passage only when it maps to one source record. The text edit is grouped for Undo.")
        }
    }

    @ViewBuilder private var detail: some View {
        if let claim = selectedClaim {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(claim.chapter.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text(claim.text).font(.title3.weight(.medium)).textSelection(.enabled)
                        }
                        Spacer()
                        Button("Go to Claim") { onNavigateToClaim(claim.range); dismiss() }
                        Button("Attach Evidence…") { onAttachEvidence(claim.range); dismiss() }
                    }
                    if !claim.outdatedCitationSourceIDs.isEmpty {
                        Label("Citation metadata changed. Existing manuscript citation text has not been rewritten.", systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                        ForEach(claim.outdatedCitationSourceIDs.sorted(by: { $0.uuidString < $1.uuidString }), id: \.self) { sourceID in
                            if let source = sources.first(where: { $0.id == sourceID }),
                               let old = source.citationDisplayHistory?[style] {
                                Text("\(old) → \(CitationFormatter.citation(for: source, style: style)) · \(source.title)")
                                    .font(.caption).textSelection(.enabled)
                            }
                        }
                        Button("Review citation text update…") {
                            citationUpdateRange = claim.range
                            showingCitationUpdateConfirmation = true
                        }
                    }
                    Divider()
                    if claim.evidence.isEmpty {
                        Label("No evidence is recorded for this passage.", systemImage: "info.circle")
                        Text("This is a coverage status only; BOLD Writer does not infer that the statement is false or unsupported.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach(claim.evidence) { item in evidenceCard(item, claim: claim) }
                    if !claim.ambiguousCitationDisplays.isEmpty {
                        Label("A displayed citation matches multiple source records: \(claim.ambiguousCitationDisplays.joined(separator: ", "))", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    if claim.matchingCitationSourceIDs.isEmpty, !claim.evidence.isEmpty {
                        Text("No unambiguous inline citation matching the selected citation style was detected in this passage.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if !claim.matchingCitationSourceIDs.isEmpty {
                        Label("Inline text matches \(claim.matchingCitationSourceIDs.count) citation source(s).", systemImage: "link")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ContentUnavailableView("No matching passages", systemImage: "line.3.horizontal.decrease.circle", description: Text("Change or clear the review filters."))
        }
    }

    @ViewBuilder private func evidenceCard(_ item: ClaimEvidence, claim: EvidenceReviewClaim) -> some View {
        let source = sources.first(where: { $0.id == item.sourceID })
        let report = source.map { EvidenceVerification.report(for: $0, evidence: item, manuscript: manuscript) }
        let libraryResolution = item.libraryPassageReference.map { KnowledgeLibraryEvidenceAdapter().resolve($0, exactQuotation: item.quotation, revalidateDisk: true) }
        let verifiedLibraryLocation = libraryResolution?.status == .current || libraryResolution?.status == .revalidated
        let displayedFindings = report?.findings.filter { !($0 == .userEnteredNotVerified && verifiedLibraryLocation) } ?? []
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.kind.rawValue).font(.headline)
                Spacer()
                Text(source?.sourceAvailability?.rawValue ?? "Availability unknown").font(.caption).foregroundStyle(.secondary)
            }
            Text(source?.title.isEmpty == false ? source!.title : "Missing or untitled source")
                .font(.subheadline.weight(.medium))
            Text("“\(item.quotation)”").textSelection(.enabled)
            Text(item.sourceLocation.isEmpty ? "No citation location recorded" : item.sourceLocation)
                .font(.caption).foregroundStyle(.secondary)
            if let report {
                ForEach(displayedFindings, id: \.self) { finding in
                    HStack {
                        Image(systemName: finding == .verifiedPassage ? "checkmark.circle" : "exclamationmark.triangle")
                        Text(finding.label)
                    }
                    .font(.caption)
                    .foregroundStyle(finding == .verifiedPassage ? Color.secondary : Color.orange)
                }
                if let page = report.verifiedPDFPage { Text("Exact quotation found on PDF page \(page). This does not verify that it supports the claim.").font(.caption).foregroundStyle(.secondary) }
                let metadataHints = source.map { DocumentCitations.metadataHints(for: $0) } ?? []
                if !metadataHints.isEmpty {
                    Text("Source metadata to review: \(metadataHints.joined(separator: "; "))")
                        .font(.caption2).foregroundStyle(.orange)
                }
            } else {
                Label("Citation source record is missing.", systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
            }
            if claim.unresolvedEvidence.contains(where: { $0.id == item.id }) {
                Label("The manuscript claim anchor is unresolved.", systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
            }
            if let libraryResolution {
                Text("Knowledge Library passage: \(libraryResolution.status.rawValue)\(libraryResolution.verifiedLocation.map { " · \($0)" } ?? "")")
                    .font(.caption).foregroundStyle(libraryResolution.status == .stale || libraryResolution.status == .unresolved ? .orange : .secondary)
            }
            HStack {
                if let source, canOpen(item, source: source, resolution: libraryResolution) {
                    Button("Open Verified Passage") { open(item, source: source) }
                } else if let source, EvidenceVerification.resolvedLocalURL(for: source) != nil || !source.url.isEmpty {
                    Button("Open Source") { _ = EvidenceVerification.open(source) }
                } else {
                    Button("Source Unavailable") {}.disabled(true)
                }
                if let uses = sources.first(where: { $0.id == item.sourceID }) {
                    let evidenceClaims = evidence.filter { $0.sourceID == uses.id }.count
                    let citedClaims = claims.filter { $0.matchingCitationSourceIDs.contains(uses.id) }.count
                    Text("Used in \(evidenceClaims) evidence association(s) and \(citedClaims) detected citation passage(s)").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(12).background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }

    private func canOpen(_ item: ClaimEvidence, source: CitationSource, resolution: EvidenceLibraryReferenceResolution?) -> Bool {
        if item.libraryPassageReference != nil { return resolution?.status == .current || resolution?.status == .revalidated }
        return EvidenceVerification.resolvedLocalURL(for: source).map { FileManager.default.fileExists(atPath: $0.path) } ?? !source.url.isEmpty
    }

    private func open(_ item: ClaimEvidence, source: CitationSource) {
        if let reference = item.libraryPassageReference {
            _ = KnowledgeLibraryEvidenceAdapter().openPassage(reference, exactQuotation: item.quotation) { message in reportMessage = message }
        } else if !EvidenceVerification.open(source) {
            reportMessage = "The source could not be opened. Verify its location or choose the file again."
        }
    }

    private func loadVerificationCacheIfNeeded() {
        guard !verificationCacheLoaded else { return }
        verificationCacheLoaded = true
        let adapter = KnowledgeLibraryEvidenceAdapter()
        var refreshedDocumentIDs = Set<KnowledgeDocumentID>()
        for item in evidence {
            guard let source = sources.first(where: { $0.id == item.sourceID }) else { continue }
            if let reference = item.libraryPassageReference {
                let documentID = (try? JSONDecoder().decode(KnowledgePassageReference.self, from: reference))?.documentID
                let shouldRefresh = documentID.map { refreshedDocumentIDs.insert($0).inserted } ?? true
                let resolution = adapter.resolve(reference, exactQuotation: item.quotation, revalidateDisk: shouldRefresh)
                switch resolution.status {
                case .current, .revalidated:
                    verifiedEvidenceIDs.insert(item.id)
                    verificationFindingsByEvidenceID[item.id] = [.verifiedPassage]
                case .stale:
                    verificationFindingsByEvidenceID[item.id] = [.staleLocation]
                case .unresolved:
                    verificationFindingsByEvidenceID[item.id] = [.missingSource]
                }
            } else {
                let report = EvidenceVerification.report(for: source, evidence: item, manuscript: manuscript)
                let invalid: Set<EvidenceVerificationFinding> = [.changedSource, .missingSource, .quotationMismatch, .unsupportedSourceFormat, .staleLocation]
                verificationFindingsByEvidenceID[item.id] = Set(report.findings)
                if report.quotationWasFound && Set(report.findings).isDisjoint(with: invalid) { verifiedEvidenceIDs.insert(item.id) }
            }
        }
    }

    private func exportReport() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "Evidence-Review.md"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let result = EvidenceResearchReport.markdown(manuscript: manuscript, evidence: evidence, sources: sources, style: style, outline: outline)
        do {
            try Data(result.utf8).write(to: url, options: .atomic)
            reportMessage = "Research report saved locally: \(url.lastPathComponent)"
        } catch { reportMessage = "Could not save report: \(error.localizedDescription)" }
    }
}
