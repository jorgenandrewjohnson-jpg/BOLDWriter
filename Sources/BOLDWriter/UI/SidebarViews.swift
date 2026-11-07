import AppKit
import CryptoKit
import SwiftUI
import UniformTypeIdentifiers

enum LeftSidebarTab: String, CaseIterable, Identifiable {
    case outline = "Outline", search = "Search", bookmarks = "Bookmarks", comments = "Comments"
    var id: String { rawValue }
}

struct LeftSidebarView: View {
    @ObservedObject var document: BOLDWriterDocument
    @ObservedObject var editor: EditorController
    var outline: [OutlineItem]
    @Binding var tab: LeftSidebarTab
    var searchFocusRequest: UUID? = nil
    @FocusState private var searchFieldFocused: Bool
    @State private var query = ""
    @State private var replacement = ""
    @State private var matchCase = false
    @State private var wholeWord = false
    @State private var regex = false

    @State private var results: [SearchResult] = []
    @State private var hasMoreResults = false
    @State private var searchError: String?

    private var search: DocumentSearch? {
        try? DocumentSearch(query, matchCase: matchCase, wholeWord: wholeWord, regularExpression: regex)
    }

    private var canReplace: Bool {
        !results.isEmpty && editor.textView?.isEditable == true && searchError == nil
    }

    private func refreshSearch() {
        guard tab == .search else { return }
        do {
            let search = try DocumentSearch(query, matchCase: matchCase, wholeWord: wholeWord, regularExpression: regex)
            let found = search.results(in: document.text.string, limit: 1_001)
            hasMoreResults = found.count > 1_000
            results = Array(found.prefix(1_000))
            searchError = nil
        } catch {
            results = []
            hasMoreResults = false
            searchError = "Invalid regular expression: \(error.localizedDescription)"
        }
    }

    private var currentResultIndex: Int? {
        DocumentAnalysis.currentResultIndex(
            in: results,
            selection: editor.selection
        )
    }

    private var resultPositionLabel: String {
        guard !results.isEmpty else {
            return query.isEmpty ? "" : "No results"
        }

        if hasMoreResults { return "Showing first 1,000 results" }
        if let currentResultIndex {
            return "\(currentResultIndex + 1) of \(results.count)"
        }

        return "\(results.count) result\(results.count == 1 ? "" : "s")"
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Navigation", selection: $tab) {
                ForEach(LeftSidebarTab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
            .padding(10)
            Divider()
            switch tab {
            case .outline: outlineList
            case .search: searchView
            case .bookmarks: bookmarkList
            case .comments: commentList
            }
        }
        .frame(width: 240)
        .background(.regularMaterial)
        .onAppear { refreshSearch() }
        .onChange(of: tab) { _, _ in refreshSearch() }
        .onChange(of: query) { _, _ in refreshSearch() }
        .onChange(of: matchCase) { _, _ in refreshSearch() }
        .onChange(of: wholeWord) { _, _ in refreshSearch() }
        .onChange(of: regex) { _, _ in refreshSearch() }
        .onChange(of: document.revisionID) { _, _ in refreshSearch() }
    }

    private var outlineList: some View {
        Group {
            if outline.isEmpty {
                ContentUnavailableView("No Headings", systemImage: "list.bullet.indent", description: Text("Apply a heading style to build the manuscript outline."))
            } else {
                List(outline) { item in
                    Button { editor.navigate(to: item.range) } label: {
                        Text(item.title).lineLimit(2).padding(.leading, CGFloat(item.level - 1) * 12)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Go to \(item.title)")
                }
            }
        }
    }

    private var searchView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                TextField(
                    "Find in document",
                    text: $query
                )
                .textFieldStyle(.roundedBorder)
                .focused($searchFieldFocused)
                .task(id: searchFocusRequest) {
                    // A newly opened sidebar must finish mounting before
                    // AppKit can move focus from the document/title field.
                    // Cancellation prevents a closed sidebar stealing focus.
                    searchFieldFocused = false
                    do { try await Task.sleep(for: .milliseconds(50)) }
                    catch { return }
                    searchFieldFocused = true
                }
                .accessibilityIdentifier(
                    "boldwriter.search.find"
                )
                .accessibilityLabel(
                    "Find in document"
                )
                .onSubmit {
                    findNext()
                }

                Button {
                    findPrevious()
                } label: {
                    Image(systemName: "chevron.up")
                }
                .help("Previous result")
                .disabled(results.isEmpty)

                Button {
                    findNext()
                } label: {
                    Image(systemName: "chevron.down")
                }
                .help("Next result")
                .disabled(results.isEmpty)
            }
            .padding([.horizontal, .top], 10)

            TextField("Replace with", text: $replacement)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("boldwriter.search.replace")
                .accessibilityLabel("Replace with")
                .help(regex ? "Use $1, $2, … for captured groups; $0 for the entire match" : "Replacement text")
                .padding(.horizontal, 10)

            HStack(spacing: 6) {
                Button("Replace") { replaceCurrent() }
                    .accessibilityIdentifier("boldwriter.search.replaceCurrent")
                    .disabled(!canReplace)
                Button("Replace All") { replaceAll() }
                    .accessibilityIdentifier("boldwriter.search.replaceAll")
                    .disabled(!canReplace)
                    .help("Replace every match in the document, including results beyond the displayed list")
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)

            HStack(spacing: 6) {
                Toggle("Case", isOn: $matchCase)
                    .help("Match case")

                Toggle("Word", isOn: $wholeWord)
                    .help("Whole word only")

                Toggle("Regex", isOn: $regex)
                    .help("Regular expression")

                Spacer()
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .padding(.horizontal, 10)

            if let searchError {
                Text(searchError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("boldwriter.search.error")
                    .padding(.horizontal, 10)
            } else if !query.isEmpty {
                HStack {
                    Text(resultPositionLabel)
                        .font(.caption)
                        .foregroundStyle(
                            results.isEmpty
                                ? .red
                                : .secondary
                        )

                    Spacer()

                    if let currentResultIndex {
                        Text(
                            "Character "
                            + String(
                                results[currentResultIndex]
                                    .range.location + 1
                            )
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 10)
            }

            List(results) { result in
                Button {
                    editor.navigate(to: result.range)
                } label: {
                    VStack(
                        alignment: .leading,
                        spacing: 3
                    ) {
                        Text(result.context)
                            .lineLimit(3)

                        HStack {
                            Text(
                                "Character "
                                + String(result.range.location + 1)
                            )

                            if editor.selection == result.range {
                                Spacer()

                                Image(
                                    systemName:
                                        "arrow.right.circle.fill"
                                )
                                .accessibilityLabel(
                                    "Current result"
                                )
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var bookmarkList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Bookmarks").font(.headline)
                Spacer()
                Button { addBookmark() } label: { Image(systemName: "plus") }.help("Add bookmark at cursor")
            }.padding(10)
            List {
                ForEach(document.metadata.bookmarks) { bookmark in
                    HStack {
                        Button { editor.navigate(to: NSRange(location: bookmark.location, length: bookmark.length)) } label: {
                            Label(bookmark.name, systemImage: "bookmark").lineLimit(1)
                        }.buttonStyle(.plain)
                        Spacer(minLength: 2)
                        Button {
                            if let name = CommentPrompt.show(title: "Rename Bookmark", initialText: bookmark.name, confirmTitle: "Rename") {
                                do { try editor.renameBookmark(id: bookmark.id, to: name, in: document) }
                                catch { document.lastErrorMessage = error.localizedDescription }
                            }
                        } label: { Image(systemName: "pencil") }.buttonStyle(.borderless).help("Rename bookmark")
                        Button(role: .destructive) { editor.deleteBookmark(id: bookmark.id, from: document) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless).help("Delete bookmark")
                    }
                }
            }
        }
    }

    private var commentList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Comments").font(.headline)
                Spacer()
                Button { addComment() } label: { Image(systemName: "plus.bubble") }.help("Comment on selection")
            }.padding(10)
            List {
                ForEach(document.metadata.comments) { comment in
                    HStack(alignment: .top, spacing: 5) {
                        Button { editor.selectComment(id: comment.id, in: document) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(comment.text).lineLimit(3)
                                Text("\(comment.author) · \(comment.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(5)
                            .background(editor.selectedCommentID == comment.id ? Color.accentColor.opacity(0.14) : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                        }.buttonStyle(.plain)
                        Button { editComment(comment) } label: { Image(systemName: "pencil") }
                            .buttonStyle(.borderless).help("Edit comment")
                        Button(role: .destructive) { editor.deleteComment(id: comment.id, in: document) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless).help("Delete comment")
                    }
                }
            }
            if document.metadata.comments.isEmpty {
                ContentUnavailableView("No Comments", systemImage: "text.bubble", description: Text("Select text and choose New Comment to add a review note."))
            }
        }
    }

    private func addBookmark() {
        let suggested = "Bookmark\(document.metadata.bookmarks.count + 1)"
        guard let name = CommentPrompt.show(title: "Add Bookmark", initialText: suggested, confirmTitle: "Add") else { return }
        do { _ = try editor.addBookmark(name: name, to: document) }
        catch { document.lastErrorMessage = error.localizedDescription }
    }

    private func findNext() {
        guard let result = search?.navigationResult(in: document.text.string, selection: editor.selection) else { return }
        editor.navigate(to: result.range)
    }

    private func findPrevious() {
        guard let result = search?.navigationResult(in: document.text.string, selection: editor.selection, previous: true) else { return }
        editor.navigate(to: result.range)
    }

    private func replaceCurrent() {
        guard canReplace, let search else { return }
        let selected = search.replacement(in: document.text.string, range: editor.selection, with: replacement)
        let target = selected.map { SearchResult(range: $0.range, context: "") }
            ?? search.navigationResult(in: document.text.string, selection: editor.selection)
        guard let target,
              let replacement = search.replacement(in: document.text.string, range: target.range, with: replacement) else { return }
        if !editor.replaceMatches(
            [replacement],
            trackChanges: document.metadata.trackChangesEnabled ?? false,
            actionName: "Replace"
        ) {
            document.lastErrorMessage = "This replacement would damage a table or protected reference. The document was not changed."
            return
        }
        refreshSearch()
        // Advance past inserted text so a replacement containing the query
        // does not repeatedly replace its own output.
        let cursor = NSRange(location: NSMaxRange(editor.selection), length: 0)
        if let next = search.navigationResult(in: document.text.string, selection: cursor) {
            editor.navigate(to: next.range)
        }
    }

    private func replaceAll() {
        guard canReplace, let search else { return }
        let all = search.replacements(in: document.text.string, with: replacement)
        if !editor.replaceMatches(all, trackChanges: document.metadata.trackChangesEnabled ?? false) {
            document.lastErrorMessage = "These replacements would damage a table or protected reference. The document was not changed."
        }
        refreshSearch()
    }

    private func addComment() {
        if let text = CommentPrompt.show(title: "New Comment", confirmTitle: "Add Comment") {
            do { _ = try editor.addComment(text: text, to: document) }
            catch { document.lastErrorMessage = error.localizedDescription }
        }
    }

    private func editComment(_ comment: DocumentComment) {
        if let text = CommentPrompt.show(title: "Edit Comment", initialText: comment.text, confirmTitle: "Save") {
            do { try editor.editComment(id: comment.id, text: text, in: document) }
            catch { document.lastErrorMessage = error.localizedDescription }
        }
    }
}

enum RightSidebarTab: String, CaseIterable, Identifiable {
    case assistant = "AI", inspector = "Inspector", revisions = "History"
    var id: String { rawValue }
}

struct RightSidebarView: View {
    @ObservedObject var document: BOLDWriterDocument
    @ObservedObject var editor: EditorController
    @ObservedObject var ai: AIManager
    @ObservedObject var manuscriptAI: ManuscriptAssistantModel
    var statistics: DocumentStatistics
    @Binding var tab: RightSidebarTab

    var body: some View {
        VStack(spacing: 0) {
            Picker("Inspector", selection: $tab) {
                ForEach(RightSidebarTab.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).padding(10)
            Divider()
            switch tab {
            case .assistant: ManuscriptAssistantView(document: document, editor: editor, model: manuscriptAI, editManager: ai)
            case .inspector:
                InspectorView(
                    document: document,
                    editor: editor,
                    statistics: statistics
                )
            case .revisions:
                RevisionHistoryView(
                    document: document,
                    editor: editor
                )
            }
        }
        .frame(width: 300)
        .background(.regularMaterial)
    }
}

struct ManuscriptAssistantView: View {
    @ObservedObject var document: BOLDWriterDocument
    @ObservedObject var editor: EditorController
    @ObservedObject var model: ManuscriptAssistantModel
    @ObservedObject var editManager: AIManager
    @ObservedObject private var library = KnowledgeLibraryStore.shared
    @State private var showPrecisionEditing = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Manuscript Assistant", systemImage: "sparkles").font(.headline)
                Spacer()
                Button(showPrecisionEditing ? "Research" : "Precision Edit") { showPrecisionEditing.toggle() }
                    .buttonStyle(.borderless)
            }.padding(12)
            Divider()
            if showPrecisionEditing {
                AIAssistantView(document: document, editor: editor, ai: editManager)
            } else {
                researchContent
            }
        }
        .onDisappear { model.cancel() }
    }

    private var researchContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 11) {
                Text("Search passages locally, then review exactly what will be sent before asking OpenAI.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Search scope", selection: $model.scope) {
                    ForEach(ManuscriptSearchScope.allCases) { Text($0.rawValue).tag($0) }
                }.accessibilityLabel("Manuscript assistant search scope")
                if model.scope == .selectedLibraryDocument {
                    Picker("Library document", selection: $model.selectedDocumentID) {
                        Text("Choose a document").tag(KnowledgeDocumentID?.none)
                        ForEach(library.documents) { item in Text(item.title).tag(Optional(item.id)) }
                    }
                }
                TextField("Ask about an argument, chapter, or source…", text: $model.question, axis: .vertical)
                    .lineLimit(2...5).textFieldStyle(.roundedBorder)
                    .onSubmit { model.search(document: document, editor: editor) }
                HStack {
                    Button { model.search(document: document, editor: editor) } label: {
                        if model.isSearching { ProgressView().controlSize(.small) } else { Label("Find Passages", systemImage: "magnifyingglass") }
                    }.buttonStyle(.borderedProminent).disabled(model.isSearching || model.question.isEmpty || (model.scope == .selectedLibraryDocument && model.selectedDocumentID == nil))
                    if model.isSearching || model.isSending {
                        Button("Cancel") { model.cancel() }.buttonStyle(.borderless)
                    }
                }
                if !model.scopeSummary.isEmpty { Text(model.scopeSummary).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled) }
                if model.pendingApproval {
                    GroupBox("Review before remote send") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("OpenAI is a remote service. Sending transfers the question and these manuscript or research excerpts off this Mac.")
                                .font(.caption).foregroundStyle(.orange)
                            Text("Question: \(model.question)").font(.caption.bold()).textSelection(.enabled)
                            ForEach(model.evidence) { item in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(item.title) · \(item.location)").font(.caption.bold())
                                    Text(item.excerpt).font(.caption).lineLimit(5).textSelection(.enabled)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                            HStack {
                                Button("Back") { model.dismissApproval() }
                                Spacer()
                                Button("Send to OpenAI") { model.sendApproved(document: document) }
                                    .buttonStyle(.borderedProminent).disabled(model.isSending)
                            }
                        }
                    }
                }
                if let answer = model.answer {
                    GroupBox("Answer") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(answer.claims) { claim in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(claim.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                    ForEach(model.evidence.filter { claim.sourceIDs.contains($0.id) }) { source in evidenceCard(source) }
                                }.padding(.vertical, 3)
                            }
                            if !answer.uncertainClaims.isEmpty {
                                Text("Uncertain or insufficiently supported").font(.caption.bold()).foregroundStyle(.orange)
                                ForEach(answer.uncertainClaims, id: \.self) { Text("• \($0)").font(.caption).foregroundStyle(.secondary) }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else if !model.evidence.isEmpty && !model.pendingApproval {
                    Text("Retrieved passages").font(.headline)
                    ForEach(model.evidence) { evidenceCard($0) }
                    Button("Review excerpts and ask OpenAI") { model.prepareRemoteSend(document: document) }
                        .buttonStyle(.borderedProminent)
                }
                if let error = model.errorMessage { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
                Text("No source text is sent during local search. Answers cite only passages in the reviewed list.")
                    .font(.caption2).foregroundStyle(.secondary)
            }.padding(12)
        }
    }

    @ViewBuilder private func evidenceCard(_ item: ManuscriptEvidence) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.title).font(.caption.bold()).lineLimit(1)
                Spacer(minLength: 4)
                Text(item.verification).font(.caption2).foregroundStyle(item.verification == "current" || item.verification == "current revision" ? .green : .secondary)
            }
            Text(item.location).font(.caption2).foregroundStyle(.secondary)
            Text(item.excerpt).font(.caption).lineLimit(6).textSelection(.enabled)
            Text(canonicalReference(for: item)).font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary).textSelection(.enabled).lineLimit(2)
            Button("Open Source") { open(item) }.buttonStyle(.link).font(.caption)
        }
        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 7))
    }

    private func canonicalReference(for item: ManuscriptEvidence) -> String {
        switch item.origin {
        case .liveManuscript(let revision, let range):
            return "Live revision \(revision.uuidString) · UTF-16 \(range.location):\(range.length)"
        case .knowledgeLibrary(let reference):
            return "Library \(reference.documentID.rawValue.uuidString) · Passage \(reference.passageID.uuidString) · \(reference.sourceURI)"
        }
    }

    private func open(_ item: ManuscriptEvidence) {
        switch item.origin {
        case .liveManuscript(let revision, let range):
            guard revision == document.revisionID else { model.errorMessage = "This manuscript changed after retrieval. Search again before navigating."; return }
            editor.navigate(to: range)
        case .knowledgeLibrary(let reference):
            do {
                let (status, resolvedRange) = try library.resolve(reference)
                guard (status == .current || status == .revalidated), let resolvedRange,
                      let record = library.documents.first(where: { $0.id == reference.documentID }),
                      !record.isReference,
                      let url = try library.sourceURL(for: reference.documentID) else {
                    model.errorMessage = "This source is missing or changed. Search again to refresh the citation."; return
                }
                let scoped = url.startAccessingSecurityScopedResource()
                guard let data = try? Data(contentsOf: url), Self.sha256(data) == record.fingerprint else {
                    if scoped { url.stopAccessingSecurityScopedResource() }
                    try library.refresh(documentID: record.id)
                    model.errorMessage = "This source changed after retrieval. Its old passage location was rejected; search again for the updated reference."
                    return
                }
                NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
                    if scoped { url.stopAccessingSecurityScopedResource() }
                    if let error {
                        Task { @MainActor in model.errorMessage = error.localizedDescription }
                        return
                    }
                    NotificationCenter.default.post(name: .knowledgeLibraryNavigate, object: nil, userInfo: [
                        "location": resolvedRange.location,
                        "length": resolvedRange.length,
                        "fingerprint": record.fingerprint,
                        "source": record.sourceURI
                    ])
                }
            } catch { model.errorMessage = error.localizedDescription }
        }
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

struct AIAssistantView: View {
    @ObservedObject var document: BOLDWriterDocument
    @ObservedObject var editor: EditorController
    @ObservedObject var ai: AIManager
    @State private var showRemoteEditPreview = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Label("Optional, preview-first editing", systemImage: "sparkles").font(.headline)
                Text("Only the chosen scope is sent when you run a command. Ordinary writing remains local.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Scope", selection: $ai.scope) {
                    ForEach(AIContextScope.allCases) { Text($0.rawValue).tag($0) }
                }
                .accessibilityLabel("AI document scope")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())]) {
                    ForEach(["Proofread", "Rewrite", "Shorten", "Clarify", "Preserve Voice", "Summarize"], id: \.self) { action in
                        Button(action) { ai.command = action + " this text." }.buttonStyle(.bordered)
                    }
                }
                TextEditor(text: $ai.command).frame(minHeight: 90).overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                Button {
                    showRemoteEditPreview = true
                } label: {
                    if ai.isWorking { ProgressView().controlSize(.small) } else { Label("Review Text to Send", systemImage: "eye") }
                }
                .buttonStyle(.borderedProminent).disabled(ai.isWorking || ai.command.isEmpty)

                if showRemoteEditPreview {
                    let context = ai.makeContext(document: document, editor: editor)
                    GroupBox("Remote request preview") {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Provider: OpenAI (remote). Sending transfers the question, writing preferences, outline, and the text below off this Mac.")
                                .font(.caption).foregroundStyle(.orange)
                            Text("Instruction: \(ai.command)").font(.caption.bold()).textSelection(.enabled)
                            DisclosureGroup("Writing preferences and outline included") {
                                Text("Preferences: \(context.instructions.isEmpty ? "None" : context.instructions)").font(.caption).textSelection(.enabled)
                                Text("Outline: \(context.outline.prefix(80).joined(separator: " · "))").font(.caption).textSelection(.enabled)
                            }.font(.caption)
                            Text("Scope: \(context.scope.rawValue) · \(context.text.count) characters").font(.caption.bold())
                            ScrollView { Text(context.text).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                                .frame(maxHeight: 150).padding(6).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 5))
                            HStack {
                                Button("Cancel") { showRemoteEditPreview = false }
                                Spacer()
                                Button("Send to OpenAI") {
                                    showRemoteEditPreview = false
                                    Task { await ai.requestProposal(document: document, editor: editor) }
                                }.buttonStyle(.borderedProminent)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if let proposal = ai.proposal {
                    Divider()
                    Text(proposal.summary).font(.headline)
                    GroupBox("Removed") { Text(proposal.originalText).strikethrough().foregroundStyle(.red).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    GroupBox("Added") { Text(proposal.replacementText).foregroundStyle(.green).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    HStack {
                        Button("Reject") { ai.rejectProposal() }
                        Button("Apply") {
                            do { try ai.applyProposal(document: document, editor: editor) }
                            catch { ai.errorMessage = error.localizedDescription }
                        }.buttonStyle(.borderedProminent)
                    }
                }
                Text(ai.status).font(.caption).foregroundStyle(.secondary)
                if let error = ai.errorMessage { Text(error).font(.caption).foregroundStyle(.red) }
                SettingsLink { Label("Configure AI", systemImage: "gear") }
            }.padding(14)
        }
    }
}

struct InspectorView: View {
    @ObservedObject var document: BOLDWriterDocument
    @ObservedObject var editor: EditorController
    var statistics: DocumentStatistics

    private let pointsPerInch = 72.0

    private var normalizedSections: [DocumentSection]? {
        guard let sections = document.metadata.sections,
              !sections.isEmpty
        else {
            return nil
        }

        return DocumentSection.normalized(
            sections,
            textLength: document.text.length,
            fallbackPage: document.metadata.page
        )
    }

    private var activeSectionIndex: Int? {
        guard let sections = normalizedSections,
              !sections.isEmpty
        else {
            return nil
        }

        let location =
            min(
                max(0, editor.selection.location),
                document.text.length
            )

        return sections.lastIndex {
            $0.location <= location
        } ?? 0
    }

    private var activePageSettings: PageSettings {
        guard let sections = normalizedSections,
              let index = activeSectionIndex,
              sections.indices.contains(index)
        else {
            return document.metadata.page
        }

        return sections[index].page
    }

    private var activePrintCoverForProductionProfile:
        CoverProject?
    {
        let projects =
            document.metadata.coverProjects
            ?? []

        if let activeID =
            document.metadata.activeCoverProjectID,
           let active =
            projects.first(
                where: {
                    $0.id == activeID
                        && $0.type
                            == .printFullWrap
                }
            )
        {
            return active
        }

        return projects.first {
            $0.type
                == .printFullWrap
        }
    }

    private var productionTemplateBinding:
        Binding<BookProductionTemplate>
    {
        Binding(
            get: {
                guard
                    let project =
                        activePrintCoverForProductionProfile
                else {
                    return .custom
                }

                return BookProductionTemplate
                    .inferred(
                        from:
                            project
                    )
            },
            set: {
                template in

                BookWorkspaceNavigation(
                    document:
                        document
                )
                .applyProductionTemplate(
                    template
                )
            }
        )
    }

    private var activeSectionDescription: String? {
        guard let sections = normalizedSections,
              let index = activeSectionIndex,
              sections.indices.contains(index)
        else {
            return nil
        }

        return "Editing section \(index + 1) of \(sections.count)"
    }

    private func updateActivePageSettings(
        _ mutate: (inout PageSettings) -> Void
    ) {
        guard let sections = normalizedSections,
              let index = activeSectionIndex,
              sections.indices.contains(index)
        else {
            mutate(&document.metadata.page)
            return
        }

        var updated = sections
        mutate(&updated[index].page)

        document.metadata.sections =
            DocumentSection.normalized(
                updated,
                textLength: document.text.length,
                fallbackPage: document.metadata.page
            )

        if index == 0 {
            document.metadata.page = updated[index].page
        }
    }

    private func pageBinding<Value>(
        _ keyPath: WritableKeyPath<PageSettings, Value>
    ) -> Binding<Value> {
        Binding(
            get: {
                activePageSettings[keyPath: keyPath]
            },
            set: { value in
                updateActivePageSettings {
                    $0[keyPath: keyPath] = value
                }
            }
        )
    }

    private func marginBinding(
        _ keyPath: WritableKeyPath<PageSettings, Double>
    ) -> Binding<Double> {
        Binding(
            get: {
                activePageSettings[keyPath: keyPath] / pointsPerInch
            },
            set: { inches in
                let safe = min(2.0, max(0.25, inches))
                updateActivePageSettings {
                    $0[keyPath: keyPath] =
                        safe * pointsPerInch
                }
            }
        )
    }

    private var headerTextBinding: Binding<String> {
        Binding(
            get: {
                activePageSettings.headerText ?? ""
            },
            set: { value in
                updateActivePageSettings {
                    $0.headerText = value
                }
            }
        )
    }

    private var headerPositionBinding:
        Binding<PageSettings.HorizontalPosition> {
        Binding(
            get: {
                activePageSettings.effectiveHeaderPosition
            },
            set: { value in
                updateActivePageSettings {
                    $0.headerPosition = value
                }
            }
        )
    }

    private var footerPositionBinding:
        Binding<PageSettings.HorizontalPosition> {
        Binding(
            get: {
                activePageSettings.effectiveFooterPosition
            },
            set: { value in
                updateActivePageSettings {
                    $0.footerPosition = value
                }
            }
        )
    }

    private var pageNumberPositionBinding:
        Binding<PageSettings.HorizontalPosition> {
        Binding(
            get: {
                activePageSettings.effectivePageNumberPosition
            },
            set: { value in
                updateActivePageSettings {
                    $0.pageNumberPosition = value
                }
            }
        )
    }

    private var columnCountBinding:
        Binding<Int> {
        Binding(
            get: {
                activePageSettings
                    .effectiveColumnCount
            },
            set: { value in
                updateActivePageSettings {
                    $0.columnCount =
                        min(
                            12,
                            max(
                                1,
                                value
                            )
                        )
                }
            }
        )
    }

    private var columnSpacingBinding:
        Binding<Double> {
        Binding(
            get: {
                activePageSettings
                    .effectiveColumnSpacing
                    / pointsPerInch
            },
            set: { value in
                updateActivePageSettings {
                    $0.columnSpacing =
                        min(
                            2,
                            max(
                                0,
                                value
                            )
                        )
                        * pointsPerInch
                }
            }
        )
    }

    private var columnWidthDescription:
        String {
        let settings =
            activePageSettings

        let printableWidth =
            max(
                0,
                settings.pageSize.width
                    - settings.leftMargin
                    - settings.rightMargin
            )

        let count =
            settings.effectiveColumnCount

        let totalSpacing =
            settings.effectiveColumnSpacing
            * Double(
                max(
                    0,
                    count - 1
                )
            )

        let width =
            max(
                0,
                (
                    printableWidth
                    - totalSpacing
                )
                / Double(
                    count
                )
            )
            / pointsPerInch

        return "Each column: "
            + width.formatted(
                .number.precision(
                    .fractionLength(
                        2
                    )
                )
            )
            + " in"
    }

    private var pageNumberRestartBinding:
        Binding<Bool> {
        Binding(
            get: {
                activePageSettings
                    .pageNumberStart
                    != nil
            },
            set: { enabled in
                updateActivePageSettings {
                    if enabled {
                        $0.pageNumberStart =
                            max(
                                1,
                                $0.pageNumberStart
                                ?? 1
                            )

                    } else {
                        $0.pageNumberStart =
                            nil
                    }
                }
            }
        )
    }

    private var pageNumberStartBinding:
        Binding<Int> {
        Binding(
            get: {
                max(
                    1,
                    activePageSettings
                        .pageNumberStart
                    ?? 1
                )
            },
            set: { value in
                updateActivePageSettings {
                    $0.pageNumberStart =
                        min(
                            999_999,
                            max(
                                1,
                                value
                            )
                        )
                }
            }
        )
    }

    private var pageNumberFormatBinding:
        Binding<PageSettings.PageNumberFormat> {
        Binding(
            get: {
                activePageSettings
                    .effectivePageNumberFormat
            },
            set: { value in
                updateActivePageSettings {
                    $0.pageNumberFormat =
                        value.rawValue
                }
            }
        )
    }

    private var suppressFirstPageBinding: Binding<Bool> {
        Binding(
            get: {
                activePageSettings.hidesHeaderFooterOnFirstPage
            },
            set: { value in
                updateActivePageSettings {
                    $0.suppressFirstPageHeaderFooter = value
                }
            }
        )
    }

    private var distinctFirstPageBinding: Binding<Bool> {
        Binding(
            get: {
                activePageSettings.hasDistinctFirstPageHeaderFooter
            },
            set: { enabled in
                updateActivePageSettings { page in
                    if enabled {
                        page.firstPageHeaderText =
                            page.effectiveHeaderText
                        page.firstPageFooterText =
                            page.footerText
                        page.suppressFirstPageHeaderFooter =
                            false
                    } else {
                        page.firstPageHeaderText = nil
                        page.firstPageFooterText = nil
                    }
                }
            }
        )
    }

    private var firstPageHeaderTextBinding: Binding<String> {
        Binding(
            get: {
                activePageSettings.effectiveFirstPageHeaderText
            },
            set: { value in
                updateActivePageSettings {
                    $0.firstPageHeaderText = value
                }
            }
        )
    }

    private var firstPageFooterTextBinding: Binding<String> {
        Binding(
            get: {
                activePageSettings.effectiveFirstPageFooterText
            },
            set: { value in
                updateActivePageSettings {
                    $0.firstPageFooterText = value
                }
            }
        )
    }

    private func applyMargins(
        top: Double,
        bottom: Double,
        left: Double,
        right: Double
    ) {
        updateActivePageSettings {
            $0.topMargin = top * pointsPerInch
            $0.bottomMargin = bottom * pointsPerInch
            $0.leftMargin = left * pointsPerInch
            $0.rightMargin = right * pointsPerInch
        }
    }

    private var printableAreaDescription: String {
        let settings = activePageSettings

        let width = max(
            0,
            settings.pageSize.width
                - settings.leftMargin
                - settings.rightMargin
        ) / pointsPerInch

        let height = max(
            0,
            settings.pageSize.height
                - settings.topMargin
                - settings.bottomMargin
        ) / pointsPerInch

        return "Printable area: "
            + width.formatted(
                .number.precision(.fractionLength(2))
            )
            + " × "
            + height.formatted(
                .number.precision(.fractionLength(2))
            )
            + " in"
    }

    @ViewBuilder
    private func marginEditor(
        _ title: String,
        _ keyPath: WritableKeyPath<PageSettings, Double>
    ) -> some View {
        HStack {
            Text(title)
            Spacer()

            TextField(
                title,
                value: marginBinding(keyPath),
                format: .number.precision(.fractionLength(3))
            )
            .labelsHidden()
            .multilineTextAlignment(.trailing)
            .frame(width: 58)

            Text("in")
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .leading)

            Stepper(
                "",
                value: marginBinding(keyPath),
                in: 0.25...2.0,
                step: 0.125
            )
            .labelsHidden()
        }
    }

    var body: some View {
        Form {
            Section("Floating Image") {
                FloatingImageInspector(document: document, editor: editor)
            }
            Section("Document") {
                TextField("Title", text: $document.metadata.title)
                LabeledContent("Words", value: statistics.words.formatted())
                LabeledContent("Characters", value: statistics.characters.formatted())
                LabeledContent("No spaces", value: statistics.charactersWithoutSpaces.formatted())
                LabeledContent("Paragraphs", value: statistics.paragraphs.formatted())
                LabeledContent("Reading time", value: "\(statistics.estimatedMinutes) min")
                LabeledContent("Headings", value: statistics.headings.formatted())
                LabeledContent("Comments", value: document.metadata.comments.count.formatted())
            }
            Section("Page Setup") {
                Picker(
                    "Production profile",
                    selection:
                        productionTemplateBinding
                ) {
                    ForEach(
                        BookProductionTemplate
                            .allCases
                    ) {
                        template in

                        Text(
                            template.rawValue
                        )
                        .tag(
                            template
                        )
                    }
                }
                .disabled(
                    activePrintCoverForProductionProfile
                        == nil
                )

                if activePrintCoverForProductionProfile
                    == nil
                {
                    Text(
                        "Create or select a Print Full Wrap cover to synchronize a production profile across Manuscript, Cover Creator, and 3D Studio."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Text(
                        "Production profiles apply one trim across every manuscript section and synchronize the active print cover, paper stock, binding, and 3D book."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if let activeSectionDescription {
                    Label(
                        activeSectionDescription,
                        systemImage: "doc.text"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Picker(
                    "Paper",
                    selection: pageBinding(\.paper)
                ) {
                    ForEach(
                        PageSettings.Paper.allCases.filter {
                            $0 != .custom || activePageSettings.customPaperSize != nil
                        },
                        id: \.self
                    ) {
                        Text($0.rawValue).tag($0)
                    }
                }

                Picker(
                    "Orientation",
                    selection: pageBinding(\.landscape)
                ) {
                    Text("Portrait").tag(false)
                    Text("Landscape").tag(true)
                }
                .pickerStyle(.segmented)

                Menu {
                    Button("Normal — 1″ all sides") {
                        applyMargins(
                            top: 1,
                            bottom: 1,
                            left: 1,
                            right: 1
                        )
                    }

                    Button("Narrow — 0.5″ all sides") {
                        applyMargins(
                            top: 0.5,
                            bottom: 0.5,
                            left: 0.5,
                            right: 0.5
                        )
                    }

                    Button("Wide — 1″ top/bottom, 2″ left/right") {
                        applyMargins(
                            top: 1,
                            bottom: 1,
                            left: 2,
                            right: 2
                        )
                    }
                } label: {
                    Label(
                        "Margin Presets",
                        systemImage: "rectangle.inset.filled"
                    )
                }

                DisclosureGroup("Custom Margins") {
                    VStack(spacing: 8) {
                        marginEditor(
                            "Top",
                            \.topMargin
                        )

                        marginEditor(
                            "Bottom",
                            \.bottomMargin
                        )

                        marginEditor(
                            "Left",
                            \.leftMargin
                        )

                        marginEditor(
                            "Right",
                            \.rightMargin
                        )
                    }
                    .padding(.top, 4)
                }

                Text(printableAreaDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Margins can be set from 0.25″ to 2.00″. BOLD Writer stores them internally as typographic points for accurate PDF and DOCX output.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                DisclosureGroup("Columns") {
                    VStack(
                        alignment:
                            .leading,
                        spacing:
                            10
                    ) {
                        Stepper(
                            "Columns: \(activePageSettings.effectiveColumnCount)",
                            value:
                                columnCountBinding,
                            in:
                                1...12
                        )

                        if activePageSettings
                            .effectiveColumnCount > 1 {

                            HStack {
                                Text(
                                    "Spacing"
                                )

                                Spacer()

                                TextField(
                                    "Spacing",
                                    value:
                                        columnSpacingBinding,
                                    format:
                                        .number.precision(
                                            .fractionLength(
                                                2
                                            )
                                        )
                                )
                                .labelsHidden()
                                .multilineTextAlignment(
                                    .trailing
                                )
                                .frame(
                                    width:
                                        58
                                )

                                Text(
                                    "in"
                                )
                                .foregroundStyle(
                                    .secondary
                                )
                                .frame(
                                    width:
                                        18,
                                    alignment:
                                        .leading
                                )

                                Stepper(
                                    "",
                                    value:
                                        columnSpacingBinding,
                                    in:
                                        0...2,
                                    step:
                                        0.125
                                )
                                .labelsHidden()
                            }

                            Text(
                                columnWidthDescription
                            )
                            .font(
                                .caption
                            )
                            .foregroundStyle(
                                .secondary
                            )
                        }

                        Text(
                            "Column settings apply to the active section and are preserved in Microsoft Word DOCX files."
                        )
                        .font(
                            .caption
                        )
                        .foregroundStyle(
                            .secondary
                        )
                    }
                    .padding(
                        .top,
                        4
                    )
                }

                DisclosureGroup("Header & Footer") {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField(
                            "Header text",
                            text: headerTextBinding
                        )

                        Picker(
                            "Header position",
                            selection: headerPositionBinding
                        ) {
                            ForEach(
                                PageSettings.HorizontalPosition.allCases
                            ) {
                                Text($0.rawValue).tag($0)
                            }
                        }
                        .pickerStyle(.segmented)

                        Divider()

                        TextField(
                            "Footer text",
                            text: pageBinding(\.footerText)
                        )

                        Picker(
                            "Footer position",
                            selection: footerPositionBinding
                        ) {
                            ForEach(
                                PageSettings.HorizontalPosition.allCases
                            ) {
                                Text($0.rawValue).tag($0)
                            }
                        }
                        .pickerStyle(.segmented)

                        Divider()

                        Toggle(
                            "Show page numbers",
                            isOn: pageBinding(\.showsPageNumbers)
                        )

                        if activePageSettings.showsPageNumbers {
                            Picker(
                                "Page number position",
                                selection: pageNumberPositionBinding
                            ) {
                                ForEach(
                                    PageSettings.HorizontalPosition.allCases
                                ) {
                                    Text($0.rawValue).tag($0)
                                }
                            }
                            .pickerStyle(.segmented)

                            Picker(
                                "Number format",
                                selection:
                                    pageNumberFormatBinding
                            ) {
                                ForEach(
                                    PageSettings.PageNumberFormat.allCases
                                ) {
                                    Text(
                                        $0.displayName
                                    )
                                    .tag(
                                        $0
                                    )
                                }
                            }

                            Toggle(
                                "Restart numbering in this section",
                                isOn:
                                    pageNumberRestartBinding
                            )

                            if activePageSettings
                                .pageNumberStart
                                != nil {

                                Stepper(
                                    "Start at \(activePageSettings.pageNumberStart ?? 1)",
                                    value:
                                        pageNumberStartBinding,
                                    in:
                                        1...999_999
                                )
                            }
                        }

                        Toggle(
                            "Hide header/footer on first page",
                            isOn: suppressFirstPageBinding
                        )
                        .disabled(
                            activePageSettings
                                .hasDistinctFirstPageHeaderFooter
                        )

                        Toggle(
                            "Different first-page header/footer",
                            isOn: distinctFirstPageBinding
                        )
                        .disabled(
                            activePageSettings
                                .hidesHeaderFooterOnFirstPage
                        )

                        if activePageSettings
                            .hasDistinctFirstPageHeaderFooter {
                            TextField(
                                "First-page header text",
                                text: firstPageHeaderTextBinding
                            )

                            TextField(
                                "First-page footer text",
                                text: firstPageFooterTextBinding
                            )

                            Text(
                                "First-page text uses the same header, footer, and page-number positions as the rest of the section."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        Text(
                            "Headers and footers appear in Print Layout and PDF using the same page renderer."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
            }
            Section("Manuscript Notes (not exported)") {
                TextEditor(text: $document.metadata.notes).frame(minHeight: 120)
            }
        }.formStyle(.grouped)
    }
}

private struct FloatingImageInspector: View {
    @ObservedObject var document: BOLDWriterDocument
    @ObservedObject var editor: EditorController

    private var images: [FloatingImage] { document.metadata.floatingImages ?? [] }
    private var selected: FloatingImage? { images.first { $0.id == editor.selectedFloatingImageID } }
    private var canvas: PaginatedEditor? { (editor.textView as? WritingTextView)?.floatingImageCanvas }
    private var selectedIsTextAnchored: Bool {
        selected?.anchor == .paragraph || selected?.anchor == .character
    }
    private var resolvedSelected: FloatingImage? {
        guard let selected else { return nil }
        guard let canvas else { return selected }
        return canvas.resolvedFloatingImage(selected)
    }
    private var canConvertInline: Bool {
        guard let view = editor.textView, let storage = view.textStorage,
              view.selectedRange().location < storage.length else { return false }
        return storage.attribute(.attachment, at: view.selectedRange().location, effectiveRange: nil) is NSTextAttachment
    }

    private func update(_ mutation: (inout FloatingImage) -> Void, action: String = "Edit Image Layout") {
        guard let selected, let index = images.firstIndex(where: { $0.id == selected.id }) else { return }
        var next = images
        mutation(&next[index])
        _ = editor.setFloatingImages(next, in: document, actionName: action)
    }

    private func valueBinding(_ keyPath: WritableKeyPath<FloatingImage, Double>) -> Binding<Double> {
        Binding(get: { selected?[keyPath: keyPath] ?? 0 }, set: { value in update { $0[keyPath: keyPath] = value } })
    }

    private func wrapDistanceBinding(_ keyPath: WritableKeyPath<FloatingImage.WrapDistances, Double>) -> Binding<Double> {
        Binding(get: { selected?.effectiveWrapDistances[keyPath: keyPath] ?? 0 }, set: { value in
            update {
                var distances = $0.effectiveWrapDistances
                distances[keyPath: keyPath] = value
                $0.wrapDistances = distances
                $0.wrapDistance = distances.top
            }
        })
    }

    private func cropPercentBinding(_ keyPath: WritableKeyPath<FloatingImage.SourceCrop, Int>) -> Binding<Double> {
        Binding(get: { Double((selected?.sourceCrop ?? .init())[keyPath: keyPath]) / 1_000 }, set: { value in
            guard value.isFinite else { return }
            update({ image in
                var crop = image.sourceCrop ?? .init()
                crop[keyPath: keyPath] = Int((min(99.999, max(0, value)) * 1_000).rounded())
                guard crop.hasValidGeometry else { return }
                image.sourceCrop = crop.isEmpty ? nil : crop
            }, action: "Crop Floating Image")
        })
    }

    private func storePhysicalPageCoordinate(_ coordinate: Double, in image: inout FloatingImage,
                                             canvas: PaginatedEditor, horizontal: Bool) {
        guard let resolved = canvas.resolvedFloatingImage(image),
              canvas.pages.indices.contains(resolved.pageIndex),
              let geometry = canvas.pages[resolved.pageIndex].pageGeometry else { return }
        if image.anchor == .paragraph || image.anchor == .character {
            guard let target = canvas.physicalAnchorOrigin(anchor: image.anchor,
                                                           location: image.anchorLocation) else { return }
            let anchorCoordinate = horizontal ? target.origin.x : target.origin.y
            if horizontal {
                image.anchorOffsetX = coordinate - Double(anchorCoordinate)
                image.horizontalPositionReference = .anchor
                image.horizontalAlignment = nil
                if image.anchorOffsetY == nil { image.anchorOffsetY = 0 }
            } else {
                image.anchorOffsetY = coordinate - Double(anchorCoordinate)
                image.verticalPositionReference = .anchor
                image.verticalAlignment = nil
                if image.anchorOffsetX == nil { image.anchorOffsetX = 0 }
            }
        } else if let stored = FloatingImageLayout.storedAxisOffset(pageCoordinate: coordinate,
                                                                     anchor: image.anchor,
                                                                     anchorOrigin: nil,
                                                                     geometry: geometry,
                                                                     horizontal: horizontal) {
            if horizontal { image.x = stored; image.horizontalAlignment = nil }
            else { image.y = stored; image.verticalAlignment = nil }
        }
    }

    private func positionBinding(horizontal: Bool) -> Binding<Double> {
        Binding<Double>(get: { positionValue(horizontal: horizontal) },
                        set: { setPositionValue($0, horizontal: horizontal) })
    }

    private func positionValue(horizontal: Bool) -> Double {
        guard let selected else { return 0 }
        let isAligned = horizontal ? selected.horizontalAlignment != nil : selected.verticalAlignment != nil
        if isAligned, let canvas, let resolved = resolvedSelected,
           let pagePosition = canvas.resolvedPageOrigin(for: resolved) {
            let reference = horizontal ? selected.horizontalPositionReference : selected.verticalPositionReference
            if reference == .margins,
               canvas.pages.indices.contains(resolved.pageIndex),
               let geometry = canvas.pages[resolved.pageIndex].pageGeometry {
                return horizontal ? pagePosition.x - geometry.contentOrigin.x : pagePosition.y - geometry.contentOrigin.y
            }
            return horizontal ? pagePosition.x : pagePosition.y
        }
        if selected.anchor == .paragraph || selected.anchor == .character {
            let stored = horizontal ? selected.anchorOffsetX : selected.anchorOffsetY
            if let stored { return stored }
            guard let canvas,
                  let target = canvas.physicalAnchorOrigin(anchor: selected.anchor, location: selected.anchorLocation),
                  let resolved = resolvedSelected else { return horizontal ? selected.x : selected.y }
            return horizontal ? resolved.x - Double(target.origin.x) : resolved.y - Double(target.origin.y)
        }
        return horizontal ? selected.x : selected.y
    }

    private func setPositionValue(_ value: Double, horizontal: Bool) {
        guard let selected, let index = images.firstIndex(where: { $0.id == selected.id }) else { return }
        var next = images
        var image = next[index]
        let axisAlignment = horizontal ? image.horizontalAlignment != nil : image.verticalAlignment != nil
        if axisAlignment {
            guard let canvas, let resolved = canvas.resolvedFloatingImage(image),
                  canvas.pages.indices.contains(resolved.pageIndex),
                  let geometry = canvas.pages[resolved.pageIndex].pageGeometry else { return }
            let reference = horizontal ? image.horizontalPositionReference : image.verticalPositionReference
            let frameOrigin = reference == .margins
                ? (horizontal ? geometry.contentOrigin.x : geometry.contentOrigin.y) : 0
            storePhysicalPageCoordinate(value + Double(frameOrigin), in: &image,
                                        canvas: canvas, horizontal: horizontal)
        } else if image.anchor == .paragraph || image.anchor == .character {
            let currentX: Double
            let currentY: Double
            if let canvas,
               let target = canvas.physicalAnchorOrigin(anchor: image.anchor, location: image.anchorLocation),
               let resolved = canvas.resolvedFloatingImage(image) {
                currentX = image.anchorOffsetX ?? (resolved.x - Double(target.origin.x))
                currentY = image.anchorOffsetY ?? (resolved.y - Double(target.origin.y))
            } else {
                currentX = image.anchorOffsetX ?? image.x
                currentY = image.anchorOffsetY ?? image.y
            }
            image.anchorOffsetX = horizontal ? value : currentX
            image.anchorOffsetY = horizontal ? currentY : value
            if horizontal { image.horizontalAlignment = nil }
            else { image.verticalAlignment = nil }
        } else if horizontal {
            image.x = value
            image.horizontalAlignment = nil
        } else {
            image.y = value
            image.verticalAlignment = nil
        }
        next[index] = image
        _ = editor.setFloatingImages(next, in: document, actionName: "Edit Image Layout")
    }

    private func alignmentChoiceBinding(horizontal: Bool) -> Binding<String> {
        Binding(get: {
            guard let selected else { return "offset" }
            let reference = horizontal ? selected.horizontalPositionReference : selected.verticalPositionReference
            if horizontal, let alignment = selected.horizontalAlignment {
                return "\((reference == .margins) ? "margins" : "page"):" + alignment.rawValue
            }
            if !horizontal, let alignment = selected.verticalAlignment {
                return "\((reference == .margins) ? "margins" : "page"):" + alignment.rawValue
            }
            return "offset"
        }, set: { choice in
            update { image in
                if choice == "offset" {
                    guard let canvas, let resolved = canvas.resolvedFloatingImage(image),
                          let pagePosition = canvas.resolvedPageOrigin(for: resolved) else { return }
                    storePhysicalPageCoordinate(horizontal ? pagePosition.x : pagePosition.y,
                                                in: &image, canvas: canvas, horizontal: horizontal)
                } else {
                    let pieces = choice.split(separator: ":", maxSplits: 1).map(String.init)
                    guard pieces.count == 2 else { return }
                    let reference: FloatingImage.PositionReference = pieces[0] == "margins" ? .margins : .page
                    if horizontal, let alignment = FloatingImage.HorizontalAlignment(rawValue: pieces[1]) {
                        image.horizontalPositionReference = reference
                        image.horizontalAlignment = alignment
                        image.anchorOffsetX = 0
                        if image.anchorOffsetY == nil { image.anchorOffsetY = 0 }
                    } else if !horizontal, let alignment = FloatingImage.VerticalAlignment(rawValue: pieces[1]) {
                        image.verticalPositionReference = reference
                        image.verticalAlignment = alignment
                        image.anchorOffsetY = 0
                        if image.anchorOffsetX == nil { image.anchorOffsetX = 0 }
                    }
                }
            }
        })
    }

    private func valueBinding<Value>(_ keyPath: WritableKeyPath<FloatingImage, Value>) -> Binding<Value> where Value: Equatable {
        Binding(get: { selected?[keyPath: keyPath] ?? images.first![keyPath: keyPath] }, set: { value in update { $0[keyPath: keyPath] = value } })
    }

    private func sizeBinding(_ keyPath: WritableKeyPath<FloatingImage, Double>) -> Binding<Double> {
        Binding(get: { selected?[keyPath: keyPath] ?? 1 }, set: { value in
            update { image in
                let safe = max(1, value)
                if keyPath == \.width, image.preservesAspectRatio, image.width > 0 { image.height = safe * image.height / image.width }
                if keyPath == \.height, image.preservesAspectRatio, image.height > 0 { image.width = safe * image.width / image.height }
                image[keyPath: keyPath] = safe
            }
        })
    }

    private func setAnchor(_ anchor: FloatingImage.Anchor) {
        update { image in
            if anchor == .paragraph || anchor == .character {
                (editor.textView as? WritingTextView)?.floatingImageCanvas?.setAnchorOffsets(
                    for: &image,
                    anchor: anchor,
                    location: editor.selection.location
                )
            } else {
                image.anchor = anchor
                image.anchorOffsetX = nil
                image.anchorOffsetY = nil
                image.horizontalPositionReference = nil
                image.verticalPositionReference = nil
                image.horizontalAlignment = nil
                image.verticalAlignment = nil
            }
        }
    }

    private func stepZOrder(_ forward: Bool) {
        guard let selected else { return }
        var ordered = images.sorted { $0.zOrder < $1.zOrder }
        guard let index = ordered.firstIndex(where: { $0.id == selected.id }) else { return }
        let neighbor = forward ? index + 1 : index - 1
        guard ordered.indices.contains(neighbor) else { return }
        ordered.swapAt(index, neighbor)
        var next = images
        for (rank, item) in ordered.enumerated() {
            if let i = next.firstIndex(where: { $0.id == item.id }) { next[i].zOrder = rank }
        }
        _ = editor.setFloatingImages(next, in: document, actionName: forward ? "Bring Image Forward" : "Send Image Backward")
    }

    private func duplicateSelected() {
        guard let selected else { return }
        var copy = selected
        copy.id = UUID()
        copy.x += 18
        copy.y += 18
        copy.zOrder = (images.map(\.zOrder).max() ?? -1) + 1
        copy.positionLocked = false
        var next = images
        next.append(copy)
        guard editor.setFloatingImages(next, in: document, actionName: "Duplicate Image") else { return }
        editor.selectedFloatingImageID = copy.id
    }

    private func reorder(_ toEnd: Bool) {
        guard let selected else { return }
        var next = images
        var ordered = next.sorted { $0.zOrder < $1.zOrder }
        guard let index = ordered.firstIndex(where: { $0.id == selected.id }) else { return }
        let item = ordered.remove(at: index)
        ordered.insert(item, at: toEnd ? ordered.count : 0)
        for (rank, element) in ordered.enumerated() {
            if let actual = next.firstIndex(where: { $0.id == element.id }) { next[actual].zOrder = rank }
        }
        _ = editor.setFloatingImages(next, in: document, actionName: toEnd ? "Bring Image to Front" : "Send Image to Back")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Insert Floating Image…", systemImage: "photo.badge.plus") {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.image]
                panel.allowsMultipleSelection = false
                guard panel.runModal() == .OK, let url = panel.url,
                      let data = try? Data(contentsOf: url) else { return }
                _ = editor.insertFloatingImage(data: data, assetName: url.lastPathComponent)
            }
            .accessibilityIdentifier("insertFloatingImage")
            Button("Convert Selected Inline Picture to Floating", systemImage: "arrow.up.left.and.arrow.down.right") {
                _ = editor.convertSelectedInlineImageToFloating()
            }
            .disabled(!canConvertInline)

            if !images.isEmpty {
                Picker("Image", selection: Binding(get: { editor.selectedFloatingImageID }, set: { editor.selectedFloatingImageID = $0 })) {
                    Text("Choose image").tag(Optional<UUID>.none)
                    ForEach(images) { item in Text(item.assetName).tag(Optional(item.id)) }
                }
            }

            if images.isEmpty {
                Text("No floating images. Existing inline pictures remain in the text flow.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if let selected {
                Text(selected.assetName).font(.caption).lineLimit(1)
                Toggle("Automatic text flow", isOn: Binding(
                    get: { selected.automaticTextFlowEnabled },
                    set: { enabled in update { $0.setAutomaticTextFlow(enabled) } }
                ))
                .help("When on, manuscript text flows around the image. When off, the image overlays the page without changing text layout.")
                .accessibilityIdentifier("floatingImageAutomaticTextFlow")
                Text("Click the image on the page to use arrow keys: 1 pt · Shift 10 pt · Option 0.1 pt · Escape returns to text editing.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .accessibilityIdentifier("floatingImageKeyboardHelp")
                HStack {
                    TextField(selected.horizontalAlignment == nil && selectedIsTextAnchored ? "Offset X (pt)" : "X (pt)", value: positionBinding(horizontal: true), format: .number.precision(.fractionLength(0...2)))
                    TextField(selected.verticalAlignment == nil && selectedIsTextAnchored ? "Offset Y (pt)" : "Y (pt)", value: positionBinding(horizontal: false), format: .number.precision(.fractionLength(0...2)))
                }
                Picker("Horizontal position", selection: alignmentChoiceBinding(horizontal: true)) {
                    Text("Offset").tag("offset")
                    Text("Page left").tag("page:left")
                    Text("Page center").tag("page:center")
                    Text("Page right").tag("page:right")
                    Text("Margin left").tag("margins:left")
                    Text("Margin center").tag("margins:center")
                    Text("Margin right").tag("margins:right")
                }
                .accessibilityIdentifier("floatingImageHorizontalAlignment")
                Picker("Vertical position", selection: alignmentChoiceBinding(horizontal: false)) {
                    Text("Offset").tag("offset")
                    Text("Page top").tag("page:top")
                    Text("Page center").tag("page:center")
                    Text("Page bottom").tag("page:bottom")
                    Text("Margin top").tag("margins:top")
                    Text("Margin center").tag("margins:center")
                    Text("Margin bottom").tag("margins:bottom")
                }
                .accessibilityIdentifier("floatingImageVerticalAlignment")
                if selectedIsTextAnchored {
                    Text("Anchor target: \(selected.anchor.rawValue.capitalized) · character \(selected.anchorLocation)")
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("floatingImageAnchorTarget")
                    if let resolved = resolvedSelected {
                        Text("Physical page \(resolved.pageIndex + 1)")
                            .font(.caption).accessibilityIdentifier("floatingImageResolvedPage")
                    } else {
                        Text("Physical page unavailable")
                            .font(.caption).foregroundStyle(.secondary)
                            .help(canvas?.lastLayoutError ?? "The text anchor has no resolved page geometry yet.")
                            .accessibilityIdentifier("floatingImageResolvedPageUnavailable")
                    }
                    if let absolute = resolvedSelected.flatMap({ canvas?.resolvedPageOrigin(for: $0) }) {
                        Text(String(format: "Page position: X %.2f pt · Y %.2f pt", absolute.x, absolute.y))
                            .font(.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier("floatingImageResolvedPosition")
                    }
                } else {
                    Stepper("Page \(selected.pageIndex + 1)", value: Binding(get: { selected.pageIndex + 1 }, set: { value in update { $0.pageIndex = max(0, value - 1) } }), in: 1...9999)
                }
                HStack {
                    TextField("Width (pt)", value: sizeBinding(\.width), format: .number.precision(.fractionLength(0...2)))
                    TextField("Height (pt)", value: sizeBinding(\.height), format: .number.precision(.fractionLength(0...2)))
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Source crop (%)").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Reset Crop") { update({ $0.sourceCrop = nil }, action: "Reset Floating Image Crop") }
                            .disabled(selected.sourceCrop == nil)
                    }
                    HStack {
                        TextField("Left", value: cropPercentBinding(\.left), format: .number.precision(.fractionLength(0...2)))
                            .accessibilityLabel("Floating image left crop percent")
                        TextField("Top", value: cropPercentBinding(\.top), format: .number.precision(.fractionLength(0...2)))
                            .accessibilityLabel("Floating image top crop percent")
                    }
                    HStack {
                        TextField("Right", value: cropPercentBinding(\.right), format: .number.precision(.fractionLength(0...2)))
                            .accessibilityLabel("Floating image right crop percent")
                        TextField("Bottom", value: cropPercentBinding(\.bottom), format: .number.precision(.fractionLength(0...2)))
                            .accessibilityLabel("Floating image bottom crop percent")
                    }
                }
                Toggle("Maintain aspect ratio", isOn: valueBinding(\.preservesAspectRatio))
                TextField("Rotation (degrees)", value: valueBinding(\.rotationDegrees), format: .number.precision(.fractionLength(0...1)))
                Picker("Anchor", selection: Binding(get: { selected.anchor }, set: setAnchor)) {
                    ForEach(FloatingImage.Anchor.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                Picker("Wrap", selection: valueBinding(\.wrapping)) {
                    Text("No Wrap").tag(FloatingImage.Wrapping.none)
                    Text("Square").tag(FloatingImage.Wrapping.square)
                    Text("Tight").tag(FloatingImage.Wrapping.tight)
                    Text("Through (Word)").tag(FloatingImage.Wrapping.through)
                    Text("Top and Bottom").tag(FloatingImage.Wrapping.topAndBottom)
                }
                if selected.wrapping == .through {
                    Text("Through Wrap is retained for Word export. The native page keeps text out of openings inside the outline.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let contour = selected.wrapPolygon {
                    HStack {
                        Text("Word contour · \(contour.points.count) points")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Use Image Outline") {
                            update({ $0.wrapPolygon = nil }, action: "Replace Word Wrap Contour")
                        }
                        .help("Replace the imported Word wrap contour with one derived from the visible image. Undo restores the original contour.")
                    }
                    .accessibilityIdentifier("floatingImageWordWrapContour")
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Text distance (pt)").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        TextField("Top", value: wrapDistanceBinding(\.top), format: .number.precision(.fractionLength(0...1)))
                            .accessibilityLabel("Top text distance in points")
                        TextField("Right", value: wrapDistanceBinding(\.right), format: .number.precision(.fractionLength(0...1)))
                            .accessibilityLabel("Right text distance in points")
                    }
                    HStack {
                        TextField("Bottom", value: wrapDistanceBinding(\.bottom), format: .number.precision(.fractionLength(0...1)))
                            .accessibilityLabel("Bottom text distance in points")
                        TextField("Left", value: wrapDistanceBinding(\.left), format: .number.precision(.fractionLength(0...1)))
                            .accessibilityLabel("Left text distance in points")
                    }
                }
                Picker("Wrap side", selection: Binding(get: { selected.effectiveWrapSide }, set: { side in update { $0.wrapSide = side } })) {
                    Text("Both sides").tag(FloatingImage.WrapSide.both)
                    Text("Left only").tag(FloatingImage.WrapSide.leftOnly)
                    Text("Right only").tag(FloatingImage.WrapSide.rightOnly)
                    Text("Largest usable side").tag(FloatingImage.WrapSide.largestSide)
                    Text("Automatic").tag(FloatingImage.WrapSide.automatic)
                }
                .help("Automatic keeps both text lanes when readable, uses the only readable lane when necessary, and moves text below when neither lane is wide enough.")
                Picker("Layer", selection: valueBinding(\.layer)) {
                    Text("In Front of Text").tag(FloatingImage.Layer.inFrontOfText)
                    Text("Behind Text").tag(FloatingImage.Layer.behindText)
                }
                Toggle("Lock Position", isOn: valueBinding(\.positionLocked))
                HStack {
                    Button("Send to Back") { reorder(false) }
                    Button("Send Backward") { stepZOrder(false) }
                    Button("Bring Forward") { stepZOrder(true) }
                    Button("Bring to Front") { reorder(true) }
                }
                Button("Duplicate Image", systemImage: "plus.square.on.square", action: duplicateSelected)
                Button("Convert to Inline") { _ = editor.convertFloatingImageToInline(selected.id) }
                Button("Delete Image", role: .destructive) {
                    _ = editor.setFloatingImages(images.filter { $0.id != selected.id }, in: document, actionName: "Delete Image")
                    editor.selectedFloatingImageID = nil
                }
                HStack {
                    Button("Undo Image Change") { editor.textView?.undoManager?.undo() }
                    Button("Redo Image Change") { editor.textView?.undoManager?.redo() }
                }
            } else {
                Text("Select an image on the page to edit its layout.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct RevisionHistoryView: View {
    @ObservedObject var document: BOLDWriterDocument
    @ObservedObject var editor: EditorController
    @State private var error: String?

    private var reviewItems:
        [TrackChanges.ReviewItem] {
        TrackChanges.reviewItems(
            in:
                document.text
        )
    }

    private var trackedChangeCount:
        Int {
        reviewItems.count
    }

    private func isSelected(
        _ item:
            TrackChanges.ReviewItem
    ) -> Bool {
        if let selectedID =
            editor.selectedReviewChangeID {
            return
                selectedID
                == item.id
        }

        let selection =
            editor.selection

        if selection.length > 0 {
            return
                NSIntersectionRange(
                    selection,
                    item.range
                )
                .length > 0
        }

        return
            selection.location
                >= item.range.location
            && selection.location
                <= NSMaxRange(
                    item.range
                )
    }

    private func reviewIcon(
        _ item:
            TrackChanges.ReviewItem
    ) -> String {
        switch item.kind {
        case .insertion:
            return "plus.circle"

        case .deletion:
            return "minus.circle"

        case .formatting:
            return "textformat"

        case .footnoteBodyEdit,
             .endnoteBodyEdit:
            return "note.text"
        }
    }

    private func reviewItemRow(
        _ item:
            TrackChanges.ReviewItem
    ) -> some View {
        Button {
            editor.selectTrackedChange(
                item
            )
        } label: {
            HStack(
                alignment: .top,
                spacing: 8
            ) {
                Image(
                    systemName:
                        reviewIcon(
                            item
                        )
                )
                .frame(width: 18)

                VStack(
                    alignment: .leading,
                    spacing: 4
                ) {
                    Text(
                        item.title
                    )
                    .font(
                        .caption
                            .weight(
                                .semibold
                            )
                    )

                    Text(
                        item.preview
                    )
                    .font(.caption)
                    .lineLimit(3)
                    .foregroundStyle(
                        .primary
                    )

                    HStack(
                        spacing: 4
                    ) {
                        Text(
                            item.author
                                .isEmpty
                            ? "Unknown"
                            : item.author
                        )

                        Text("•")

                        Text(
                            item.date
                                .formatted(
                                    date:
                                        .abbreviated,
                                    time:
                                        .shortened
                                )
                        )
                    }
                    .font(.caption2)
                    .foregroundStyle(
                        .secondary
                    )
                }

                Spacer(
                    minLength: 0
                )
            }
            .padding(8)
            .frame(
                maxWidth:
                    .infinity,
                alignment:
                    .leading
            )
            .background(
                isSelected(item)
                    ? Color.accentColor
                        .opacity(
                            0.10
                        )
                    : Color.clear,
                in:
                    RoundedRectangle(
                        cornerRadius: 7
                    )
            )
            .contentShape(
                Rectangle()
            )
        }
        .buttonStyle(.plain)
        .help(
            "Go to "
            + item.title
        )
    }

    private var trackingBinding: Binding<Bool> {
        Binding(
            get: {
                document.metadata.trackChangesEnabled ?? false
            },
            set: {
                document.metadata.trackChangesEnabled = $0
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(
                        "Track Changes",
                        systemImage: "pencil.and.outline"
                    )
                    .font(.headline)

                    Spacer()

                    Toggle(
                        "",
                        isOn: trackingBinding
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                }

                if trackedChangeCount == 0 {
                    Text("No tracked changes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(
                        String(
                            trackedChangeCount
                        )
                        + " tracked change"
                        + (
                            trackedChangeCount
                                == 1
                                ? ""
                                : "s"
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    HStack {
                        Button(
                            "Previous"
                        ) {
                            editor
                                .previousTrackedChange()
                        }

                        Button(
                            "Next"
                        ) {
                            editor
                                .nextTrackedChange()
                        }
                    }
                    .controlSize(.small)

                    HStack {
                        Button("Accept") {
                            editor.acceptTrackedChangeAtSelection()
                        }

                        Button("Reject") {
                            editor.rejectTrackedChangeAtSelection()
                        }
                    }
                    .controlSize(.small)

                    ScrollView {
                        LazyVStack(
                            spacing: 5
                        ) {
                            ForEach(
                                reviewItems
                            ) {
                                item in

                                reviewItemRow(
                                    item
                                )
                            }
                        }
                    }
                    .frame(
                        minHeight: 80,
                        maxHeight: 260
                    )
                    .background(
                        Color(
                            nsColor:
                                .controlBackgroundColor
                        )
                        .opacity(0.55),
                        in:
                            RoundedRectangle(
                                cornerRadius: 8
                            )
                    )

                    HStack {
                        Button("Accept All") {
                            editor.acceptAllTrackedChanges()
                        }

                        Button("Reject All") {
                            editor.rejectAllTrackedChanges()
                        }
                    }
                    .controlSize(.small)
                }
            }
            .padding(10)

            Divider()

            HStack {
                Text("Recovery Points")
                    .font(.headline)

                Spacer()

                Button("Save Version") {
                    document.createRevision(
                        named: "Manual Save Point"
                    )
                }
            }
            .padding(10)

            List(document.metadata.revisions) { revision in
                VStack(
                    alignment: .leading,
                    spacing: 5
                ) {
                    Text(revision.name)
                        .font(.headline)

                    Text(revision.date.formatted())
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("Restore") {
                        do {
                            try document.restore(revision)
                        } catch {
                            self.error =
                                error.localizedDescription
                        }
                    }
                    .controlSize(.small)
                }
            }

            if let error {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding()
            }
        }
    }
}
