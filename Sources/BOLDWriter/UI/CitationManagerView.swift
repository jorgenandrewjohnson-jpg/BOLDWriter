import SwiftUI

struct CitationManagerView: View {
    let referencedSourceIDs: Set<UUID>
    let onMergeSources: (UUID, UUID, [CitationSource]) -> [CitationSource]?
    let onSave: ([CitationSource], CitationStyle) -> Void
    let onInsertCitation:
        (
            CitationSource,
            CitationStyle,
            [CitationSource]
        ) -> Void
    let onInsertBibliography:
        (
            [CitationSource],
            CitationStyle
        ) -> Void

    @Environment(\.dismiss)
    private var dismiss

    @State private var sources: [CitationSource]
    @State private var style: CitationStyle
    @State private var selectedID: UUID?
    @State private var searchText = ""
    @State private var mergeTargetID: UUID?
    @State private var mergeError: String?

    init(
        sources: [CitationSource],
        style: CitationStyle,
        referencedSourceIDs: Set<UUID> = [],
        onMergeSources: @escaping (UUID, UUID, [CitationSource]) -> [CitationSource]? = { _, _, _ in nil },
        onSave:
            @escaping (
                [CitationSource],
                CitationStyle
            ) -> Void,
        onInsertCitation:
            @escaping (
                CitationSource,
                CitationStyle,
                [CitationSource]
            ) -> Void,
        onInsertBibliography:
            @escaping (
                [CitationSource],
                CitationStyle
            ) -> Void
    ) {
        self.referencedSourceIDs = referencedSourceIDs
        self.onMergeSources = onMergeSources
        self.onSave = onSave
        self.onInsertCitation = onInsertCitation
        self.onInsertBibliography = onInsertBibliography

        _sources = State(initialValue: sources)
        _style = State(initialValue: style)
        _selectedID = State(initialValue: sources.first?.id)
    }

    private var selectedIndex: Int? {
        guard let selectedID else {
            return nil
        }

        return sources.firstIndex {
            $0.id == selectedID
        }
    }

    private var selectedSource: CitationSource? {
        guard
            let selectedIndex,
            sources.indices.contains(selectedIndex)
        else {
            return nil
        }

        return sources[selectedIndex]
    }

    private var visibleSources: [CitationSource] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sources }
        return sources.filter { "\($0.author) \($0.title) \($0.publisher) \($0.containerTitle) \($0.year) \($0.url)".localizedCaseInsensitiveContains(query) }
    }

    private var compatibleMergeTargets: [CitationSource] {
        guard let selectedSource else { return [] }
        return sources.filter { $0.id != selectedSource.id && DocumentEvidence.canSafelyMerge(selectedSource, $0) }
    }

    private var canInsertCitation: Bool {
        guard let source = selectedSource else {
            return false
        }

        return !source.title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    private var canInsertBibliography: Bool {
        sources.contains {
            !$0.title
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Citations").font(.title2.bold())
                    Text("Basic in-app APA, MLA, and Chicago text formatting; verify guide-specific rules before publication.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Spacer()

                Picker(
                    "Style",
                    selection: $style
                ) {
                    ForEach(CitationStyle.allCases) {
                        citationStyle in

                        Text(citationStyle.rawValue)
                            .tag(citationStyle)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 150)
            }
            .padding(16)

            Divider()

            HStack(spacing: 0) {
                VStack(spacing: 8) {
                    HStack {
                        Text("Sources")
                            .font(.headline)

                        Spacer()

                        Button {
                            addSource()
                        } label: {
                            Image(systemName: "plus")
                        }
                        .help("Add source")

                        Button {
                            deleteSelectedSource()
                        } label: {
                            Image(systemName: "minus")
                        }
                        .disabled(selectedIndex == nil || selectedSource.map { referencedSourceIDs.contains($0.id) } == true)
                        .help("Delete selected source")
                    }
                    .padding(
                        [.top, .horizontal],
                        12
                    )

                    TextField("Search existing sources", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal, 12)

                    List {
                        ForEach(visibleSources) {
                            source in

                            Button {
                                selectedID = source.id
                            } label: {
                                VStack(
                                    alignment: .leading,
                                    spacing: 3
                                ) {
                                    Text(
                                        source.title.isEmpty
                                            ? "Untitled Source"
                                            : source.title
                                    )
                                    .lineLimit(1)

                                    Text(
                                        source.author.isEmpty
                                            ? source.type.rawValue
                                            : source.author
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                }
                                .frame(
                                    maxWidth: .infinity,
                                    alignment: .leading
                                )
                                .padding(5)
                                .background(
                                    selectedID == source.id
                                        ? Color.accentColor.opacity(0.16)
                                        : Color.clear
                                )
                                .clipShape(
                                    RoundedRectangle(
                                        cornerRadius: 5
                                    )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listStyle(.inset)
                }
                .frame(width: 230)

                Divider()

                VStack(spacing: 6) {
                    if !compatibleMergeTargets.isEmpty {
                        HStack {
                            Picker("Merge matching source", selection: $mergeTargetID) {
                                Text("Choose compatible record").tag(UUID?.none)
                                ForEach(compatibleMergeTargets) { source in
                                    Text(source.title.isEmpty ? "Untitled source" : source.title).tag(UUID?.some(source.id))
                                }
                            }
                            Button("Merge Into Selected") { mergeSelectedDuplicate() }.disabled(mergeTargetID == nil)
                        }.padding(.horizontal, 12).padding(.top, 8)
                        Text("Only records for the same local file or canonical URL with identical citation displays can merge. Evidence links are reassigned; original source files remain untouched.")
                            .font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 12)
                    }
                    sourceEditor
                    if let mergeError { Text(mergeError).font(.caption).foregroundStyle(.orange).padding(.horizontal, 12) }
                }
                    .frame(
                        minWidth: 440,
                        maxWidth: .infinity
                    )
            }
            .frame(minHeight: 410)

            Divider()

            HStack {
                Button("Done") {
                    save()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Insert Bibliography") {
                    let safe = validSources()

                    onSave(
                        safe,
                        style
                    )

                    onInsertBibliography(
                        safe,
                        style
                    )

                    dismiss()
                }
                .disabled(!canInsertBibliography)

                Button("Insert Citation") {
                    guard
                        let source = selectedSource
                    else {
                        return
                    }

                    let safe = validSources()

                    guard
                        let stored = safe.first(
                            where: {
                                $0.id == source.id
                            }
                        )
                    else {
                        return
                    }

                    onSave(
                        safe,
                        style
                    )

                    onInsertCitation(
                        stored,
                        style,
                        safe
                    )

                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canInsertCitation)
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 820, height: 600)
    }

    @ViewBuilder
    private var sourceEditor: some View {
        if selectedIndex != nil {
            Form {
                Picker(
                    "Source Type",
                    selection: sourceTypeBinding
                ) {
                    ForEach(CitationSourceType.allCases) {
                        type in

                        Text(type.rawValue)
                            .tag(type)
                    }
                }

                TextField(
                    "Author",
                    text: textBinding(\.author)
                )

                TextField(
                    "Title",
                    text: textBinding(\.title)
                )

                TextField(
                    "Year",
                    text: textBinding(\.year)
                )

                TextField(
                    "Publisher",
                    text: textBinding(\.publisher)
                )

                TextField(
                    "Journal / Website",
                    text: textBinding(\.containerTitle)
                )

                TextField(
                    "URL",
                    text: textBinding(\.url)
                )

                TextField("Publication date", text: optionalTextBinding(\.publicationDate))
                TextField("Source page or section", text: optionalTextBinding(\.sourceLocation))
                TextField("Research notes", text: optionalTextBinding(\.researchNotes), axis: .vertical)

                let hints = DocumentCitations.metadataHints(for: selectedSource ?? CitationSource())
                if !hints.isEmpty {
                    Section("Metadata review") {
                        ForEach(hints, id: \.self) { hint in Label(hint, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary) }
                        Text("These are completeness hints, not style-compliance findings. Check the applicable guide before publication.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .padding(8)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "books.vertical")
                    .font(.system(size: 30))
                    .foregroundStyle(.secondary)

                Text("No Source Selected")
                    .font(.headline)

                Text(
                    "Add a source to begin building citations."
                )
                .foregroundStyle(.secondary)
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity
            )
        }
    }

    private var sourceTypeBinding:
        Binding<CitationSourceType>
    {
        Binding(
            get: {
                guard
                    let selectedIndex,
                    sources.indices.contains(selectedIndex)
                else {
                    return .book
                }

                return sources[selectedIndex].type
            },
            set: {
                newValue in

                guard
                    let selectedIndex,
                    sources.indices.contains(selectedIndex)
                else {
                    return
                }

                sources[selectedIndex].type = newValue
            }
        )
    }

    private func textBinding(
        _ keyPath:
            WritableKeyPath<CitationSource, String>
    ) -> Binding<String> {
        Binding(
            get: {
                guard
                    let selectedIndex,
                    sources.indices.contains(selectedIndex)
                else {
                    return ""
                }

                return sources[selectedIndex][keyPath: keyPath]
            },
            set: {
                newValue in

                guard
                    let selectedIndex,
                    sources.indices.contains(selectedIndex)
                else {
                    return
                }

                sources[selectedIndex][keyPath: keyPath] = newValue
            }
        )
    }

    private func optionalTextBinding(_ keyPath: WritableKeyPath<CitationSource, String?>) -> Binding<String> {
        Binding(
            get: {
                guard let selectedIndex, sources.indices.contains(selectedIndex) else { return "" }
                return sources[selectedIndex][keyPath: keyPath] ?? ""
            },
            set: { newValue in
                guard let selectedIndex, sources.indices.contains(selectedIndex) else { return }
                sources[selectedIndex][keyPath: keyPath] = newValue.isEmpty ? nil : newValue
            }
        )
    }

    private func addSource() {
        let source = CitationSource(
            title: "Untitled Source"
        )

        sources.append(source)
        selectedID = source.id
    }

    private func deleteSelectedSource() {
        guard let selectedIndex else {
            return
        }

        sources.remove(at: selectedIndex)

        if sources.indices.contains(selectedIndex) {
            selectedID = sources[selectedIndex].id
        } else {
            selectedID = sources.last?.id
        }
    }

    private func mergeSelectedDuplicate() {
        guard let keepID = selectedID, let removeID = mergeTargetID else { return }
        guard let updated = onMergeSources(keepID, removeID, validSources()) else {
            mergeError = "The records could not be merged. Their evidence and source records were left unchanged."
            return
        }
        sources = updated
        selectedID = keepID
        mergeTargetID = nil
        mergeError = "Merged source records. Existing evidence now points to the retained source; the local source file was not changed."
    }

    private func validSources() -> [CitationSource] {
        DocumentCitations
            .normalized(sources)
            .filter {
                !$0.title.isEmpty
            }
    }

    private func save() {
        onSave(
            validSources(),
            style
        )
    }
}
