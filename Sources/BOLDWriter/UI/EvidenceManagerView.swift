import AppKit
import SwiftUI

struct EvidenceManagerView: View {
    let manuscript: String
    let citationStyle: CitationStyle
    let onSave: ([CitationSource], [ClaimEvidence]) -> Void
    let onInsertCitation: (CitationSource) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var knowledgeLibrary = KnowledgeLibraryStore.shared
    @State private var sources: [CitationSource]
    @State private var records: [ClaimEvidence]
    @State private var selectedSourceID: UUID?
    @State private var selectedRecordID: UUID?
    @State private var sourceSearch = ""
    @State private var kind: EvidenceKind = .supporting
    @State private var quotation = ""
    @State private var location = ""
    @State private var authorNote = ""
    @State private var verification: EvidenceVerificationStatus = .unverified
    @State private var verificationReport: EvidenceSourceVerificationReport?
    @State private var libraryPassages: [EvidenceLibraryPassageOption] = []
    @State private var selectedLibraryPassageID: UUID?
    @State private var libraryMessage: String?
    @State private var libraryResolution: EvidenceLibraryReferenceResolution?
    @State private var newAuthor = ""
    @State private var newType: CitationSourceType = .book
    @State private var newTitle = ""
    @State private var newPublication = ""
    @State private var newDate = ""
    @State private var newURL = ""
    @State private var errorMessage: String?
    private let anchor: ClaimAnchor?

    init(manuscript: String, selection: NSRange, sources: [CitationSource], evidence: [ClaimEvidence], citationStyle: CitationStyle, onSave: @escaping ([CitationSource], [ClaimEvidence]) -> Void, onInsertCitation: @escaping (CitationSource) -> Void) {
        self.manuscript = manuscript
        self.citationStyle = citationStyle
        self.onSave = onSave
        self.onInsertCitation = onInsertCitation
        self.anchor = ClaimAnchor.make(text: manuscript, range: selection)
        _sources = State(initialValue: sources)
        _records = State(initialValue: evidence)
        _selectedSourceID = State(initialValue: sources.first?.id)
    }

    private var linkedRecords: [ClaimEvidence] {
        guard let anchor else { return records }
        return records.filter { $0.anchor.identifiesSameSelection(as: anchor) }
    }

    private var selectedRecord: ClaimEvidence? { records.first { $0.id == selectedRecordID } }
    private var selectedSource: CitationSource? { sources.first { $0.id == selectedSourceID } }
    private var filteredSources: [CitationSource] {
        let query = sourceSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sources }
        return sources.filter { "\($0.author) \($0.title) \($0.publisher) \($0.containerTitle) \($0.year) \($0.url)".localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Evidence").font(.title2.bold())
                    Text(anchor?.selectedText ?? "Select a passage in the manuscript before opening Evidence.")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                Button("Done") { save(); dismiss() }.keyboardShortcut(.defaultAction)
            }.padding(14)
            Divider()
            if !DocumentEvidence.duplicateSourceIDs(in: sources).isEmpty {
                Label("Possible duplicate source records are present. Review before adding another citation.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.top, 8)
            }
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Attached evidence").font(.headline)
                        Spacer()
                        Button { selectedRecordID = nil; clearDraft() } label: { Image(systemName: "plus") }.help("Add evidence")
                    }
                    if linkedRecords.isEmpty {
                        ContentUnavailableView("No Evidence", systemImage: "text.book.closed", description: Text("Add a source and attach a quotation to this claim."))
                    } else {
                        List(selection: $selectedRecordID) {
                            ForEach(linkedRecords) { record in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(sources.first { $0.id == record.sourceID }?.title ?? "Missing source")
                                        .lineLimit(1)
                                    Text("\(record.kind.rawValue) · \(record.sourceLocation)").font(.caption).foregroundStyle(.secondary)
                                }.tag(record.id)
                            }
                        }.listStyle(.inset)
                    }
                    Spacer()
                    Button(role: .destructive) { removeSelected() } label: { Label("Remove association", systemImage: "minus.circle") }
                        .disabled(selectedRecord == nil)
                }
                .padding(12).frame(width: 245)
                Divider()
                Form {
                    Section("Source") {
                        TextField("Find an existing source", text: $sourceSearch)
                        Picker("Citation source", selection: $selectedSourceID) {
                            Text("Choose a source").tag(UUID?.none)
                            ForEach(filteredSources) { source in Text(source.title.isEmpty ? "Untitled source" : source.title).tag(Optional(source.id)) }
                        }
                        HStack {
                            Picker("Type", selection: $newType) { ForEach(CitationSourceType.allCases) { Text($0.rawValue).tag($0) } }
                            TextField("Author", text: $newAuthor)
                            TextField("Title", text: $newTitle)
                        }
                        HStack {
                            TextField("Publication", text: $newPublication)
                            TextField("Publication date", text: $newDate)
                        }
                        TextField("URL (optional)", text: $newURL)
                        HStack {
                            Button("Add Source") { addSource() }.disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            Button("Choose Local File…") { chooseLocalFile() }.disabled(selectedSource == nil)
                            if let source = selectedSource, !source.url.isEmpty || source.localFilePath != nil {
                                Button("Open Source") { _ = EvidenceVerification.open(source) }
                            }
                        }
                        Button("Find Exact Passage in Knowledge Library") { findLibraryPassages() }
                            .disabled(selectedSource == nil || quotation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if !libraryPassages.isEmpty {
                            Picker("Exact source passage", selection: $selectedLibraryPassageID) {
                                Text("Choose a passage").tag(UUID?.none)
                                ForEach(libraryPassages) { passage in
                                    Text("\(passage.reference.context) · \(passage.excerpt)")
                                        .lineLimit(1).tag(Optional(passage.id))
                                }
                            }
                        }
                        if let libraryMessage { Text(libraryMessage).font(.caption).foregroundStyle(.orange) }
                    }
                    Section("Quotation and relationship") {
                        Picker("Evidence type", selection: $kind) { ForEach(EvidenceKind.allCases) { Text($0.rawValue).tag($0) } }
                        TextEditor(text: $quotation).frame(minHeight: 72).overlay(alignment: .topLeading) { if quotation.isEmpty { Text("Exact quotation from the source").foregroundStyle(.tertiary).padding(6).allowsHitTesting(false) } }
                        TextField("Page, section, timestamp, or location", text: $location)
                        TextField("Your research note", text: $authorNote)
                        Picker("Verification", selection: $verification) { ForEach(EvidenceVerificationStatus.allCases) { Text($0.rawValue).tag($0) } }
                        Button("Attach to Claim") { attach() }.disabled(anchor == nil || selectedSource == nil || quotation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if let verificationReport {
                            ForEach(verificationReport.findings) { finding in
                                Label(finding.label, systemImage: finding == .verifiedPassage ? "checkmark.seal" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(finding == .verifiedPassage ? .green : finding == .missingSource || finding == .quotationMismatch ? .red : .orange)
                            }
                            if let page = verificationReport.verifiedPDFPage {
                                Text("Verified PDF page \(page)").font(.caption).foregroundStyle(.secondary)
                            }
                            if verificationReport.quotationWasFound {
                                Text("Quotation presence does not establish that it supports the claim or that the claim is true.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if let selectedRecord, let source = sources.first(where: { $0.id == selectedRecord.sourceID }) {
                        Section {
                            Button("Insert linked \(citationStyle.rawValue) citation") { onInsertCitation(source) }
                            Text("Inserting a citation does not change the evidence verification status.").font(.caption).foregroundStyle(.secondary)
                            if selectedRecord.libraryPassageReference != nil {
                                Button("Open Linked Passage") { openLinkedPassage(selectedRecord) }
                                if let libraryResolution {
                                    Label(libraryResolution.status.rawValue.capitalized, systemImage: libraryResolution.status == .current || libraryResolution.status == .revalidated ? "checkmark.seal" : "exclamationmark.triangle.fill")
                                        .foregroundStyle(libraryResolution.status == .current || libraryResolution.status == .revalidated ? .green : .orange)
                                    if let location = libraryResolution.verifiedLocation { Text(location).font(.caption).foregroundStyle(.secondary) }
                                    if libraryResolution.status == .stale || libraryResolution.status == .unresolved {
                                        Text("The saved source passage no longer resolves. The evidence is preserved; find and attach a replacement passage explicitly.").font(.caption).foregroundStyle(.orange)
                                    }
                                }
                            }
                        }
                    }
                    if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                }.formStyle(.grouped).padding(8)
            }
        }
        .frame(width: 820, height: 650)
        .onAppear { refreshVerification() }
        .onChange(of: selectedRecordID) { _, id in
            if let item = records.first(where: { $0.id == id }) { load(item) }
            refreshVerification()
        }
        .onChange(of: quotation) { _, _ in selectedLibraryPassageID = nil; libraryPassages = [] }
        .onChange(of: selectedSourceID) { _, _ in selectedLibraryPassageID = nil; libraryPassages = [] }
        .onChange(of: records) { _, _ in refreshVerification() }
        .onChange(of: sources) { _, _ in refreshVerification() }
        .onChange(of: manuscript) { _, _ in refreshVerification() }
    }

    private func clearDraft() { quotation = ""; location = ""; authorNote = ""; kind = .supporting; verification = .unverified }
    private func load(_ item: ClaimEvidence) { selectedSourceID = item.sourceID; quotation = item.quotation; location = item.sourceLocation; authorNote = item.authorNote; kind = item.kind; verification = item.verificationStatus }

    private func refreshVerification() {
        guard let item = records.first(where: { $0.id == selectedRecordID }),
              let source = sources.first(where: { $0.id == item.sourceID }) else {
            verificationReport = nil
            return
        }
        var report = EvidenceVerification.report(for: source, evidence: item, manuscript: manuscript)
        if let reference = item.libraryPassageReference {
            libraryResolution = KnowledgeLibraryEvidenceAdapter(store: knowledgeLibrary).resolve(reference, exactQuotation: item.quotation)
            if libraryResolution?.status == .current || libraryResolution?.status == .revalidated {
                report.findings.removeAll { $0 == .userEnteredNotVerified }
            }
        } else {
            libraryResolution = nil
        }
        verificationReport = report
    }

    private func addSource() {
        let source = CitationSource(type: newType, author: newAuthor, title: newTitle, year: newDate, publisher: newPublication, containerTitle: "", url: newURL, publicationDate: newDate, verificationStatus: .unverified, sourceAvailability: newURL.isEmpty ? .inaccessible : .remoteOnly)
        sources.append(source); selectedSourceID = source.id
        newType = .book; newAuthor = ""; newTitle = ""; newPublication = ""; newDate = ""; newURL = ""
    }

    private func attach() {
        guard let anchor, let source = selectedSource else { return }
        var item = ClaimEvidence(anchor: anchor, sourceID: source.id, kind: kind, quotation: quotation, sourceLocation: location, authorNote: authorNote, verificationStatus: verification)
        if let selectedLibraryPassageID,
           let option = libraryPassages.first(where: { $0.id == selectedLibraryPassageID }) {
            do { item.libraryPassageReference = try KnowledgeLibraryEvidenceAdapter(store: knowledgeLibrary).serializedReference(for: option) }
            catch { libraryMessage = error.localizedDescription; return }
        }
        let updated = DocumentEvidence.upsert(item, editing: selectedRecordID, in: records)
        records = updated.records
        selectedRecordID = updated.selectedID
        errorMessage = nil
        onSave(sources, records)
    }

    private func findLibraryPassages() {
        guard let selectedSource else { return }
        do {
            let adapter = KnowledgeLibraryEvidenceAdapter(store: knowledgeLibrary)
            libraryPassages = try adapter.exactPassages(for: selectedSource, quotation: quotation)
            selectedLibraryPassageID = libraryPassages.count == 1 ? libraryPassages.first?.id : nil
            libraryMessage = libraryPassages.isEmpty ? "No exact passage was found for this quotation." : "Select the passage containing the exact quotation. This confirms quotation presence, not that it supports the claim."
        } catch {
            libraryPassages = []; selectedLibraryPassageID = nil; libraryMessage = error.localizedDescription
        }
    }

    private func openLinkedPassage(_ item: ClaimEvidence) {
        guard let reference = item.libraryPassageReference else { return }
        let resolution = KnowledgeLibraryEvidenceAdapter(store: knowledgeLibrary).openPassage(reference, exactQuotation: item.quotation) { message in
            libraryMessage = message
        }
        libraryResolution = resolution
        if resolution.status == .stale || resolution.status == .unresolved {
            libraryMessage = "Source passage is \(resolution.status.rawValue). The saved quotation and association remain intact."
        }
    }

    private func removeSelected() { guard let id = selectedRecordID else { return }; records.removeAll { $0.id == id }; selectedRecordID = nil; clearDraft(); onSave(sources, records) }
    private func save() { onSave(sources, records) }

    private func chooseLocalFile() {
        guard let id = selectedSourceID, let index = sources.firstIndex(where: { $0.id == id }) else { return }
        let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let startedAccess = url.startAccessingSecurityScopedResource()
            defer { if startedAccess { url.stopAccessingSecurityScopedResource() } }
            let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            let fingerprint = EvidenceVerification.sha256(try Data(contentsOf: url, options: [.mappedIfSafe]))
            sources[index].localFilePath = url.path
            sources[index].fileBookmark = bookmark
            sources[index].contentFingerprint = fingerprint
            sources[index].verificationStatus = .authorChecked
            sources[index].sourceAvailability = .available
            onSave(sources, records)
        } catch { errorMessage = "Could not record source file: \(error.localizedDescription)" }
    }
}
