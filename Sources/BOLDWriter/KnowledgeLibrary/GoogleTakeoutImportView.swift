import SwiftUI
import UniformTypeIdentifiers

struct GoogleTakeoutImportView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: GoogleTakeoutImportModel
    @ObservedObject private var library: KnowledgeLibraryStore
    @State private var chooseArchives = false
    @State private var chooseFolder = false

    init(library: KnowledgeLibraryStore, collectionID: KnowledgeCollectionID? = nil) {
        _library = ObservedObject(wrappedValue: library)
        _model = StateObject(wrappedValue: GoogleTakeoutImportModel(library: library, collectionID: collectionID))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if model.isScanning {
                ProgressView("Inspecting selected Takeout sources…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let preview = model.preview {
                controls(preview)
                selectionSummary(preview)
                selectionOptions
                documentList(preview)
                if !preview.issues.isEmpty { issues(preview.issues) }
                if !model.failures.isEmpty { failures }
                if model.isImporting { importProgress }
                Spacer(minLength: 0)
                footer
            } else {
                emptyState
            }
        }
        .padding(22)
        .frame(minWidth: 900, minHeight: 690)
        .fileImporter(isPresented: $chooseArchives, allowedContentTypes: [.zip], allowsMultipleSelection: true) { result in
            do {
                let picked = try result.get().map(TakeoutSource.archive)
                model.scan(model.sources + picked)
            } catch { model.showError(error.localizedDescription) }
        }
        .fileImporter(isPresented: $chooseFolder, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            do {
                let picked = try result.get().map(TakeoutSource.folder)
                model.scan(model.sources + picked)
            } catch { model.showError(error.localizedDescription) }
        }
        .alert("Google Takeout Import", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.clearError() } })) {
            Button("OK") { model.clearError() }
        } message: { Text(model.errorMessage ?? "Unknown import error") }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Import from Google Takeout").font(.title2.bold())
                Text("Choose ZIP parts or an extracted Drive folder. Everything is inspected and indexed on this Mac.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 18) {
            ContentUnavailableView("Select a Takeout export", systemImage: "archivebox", description: Text("Choose one or more numbered ZIP parts, or select an already extracted Drive folder. Photos, videos, and unsupported files are listed but never imported."))
            HStack {
                Button { chooseArchives = true } label: { Label("Choose ZIP Archives", systemImage: "doc.zipper") }.buttonStyle(.borderedProminent)
                Button { chooseFolder = true } label: { Label("Choose Extracted Folder", systemImage: "folder") }.buttonStyle(.bordered)
            }
            Spacer()
        }
    }

    private func controls(_ preview: TakeoutPreview) -> some View {
        HStack(spacing: 12) {
            Picker("Import into", selection: $model.collectionID) {
                ForEach(library.collections) { collection in
                    Text("\(collection.name) (\(collection.documentCount))").tag(collection.id)
                }
            }.frame(maxWidth: 260).disabled(model.isImporting)
            Button { chooseArchives = true } label: { Label("Add ZIP Parts", systemImage: "plus") }.disabled(model.isImporting)
            Button { chooseFolder = true } label: { Label("Add Extracted Folder", systemImage: "folder.badge.plus") }.disabled(model.isImporting)
            Text("\(preview.archiveCount) ZIP archive(s) · \(preview.folderCount) extracted folder(s)")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Clear Sources") { model.scan([]) }.disabled(model.isImporting)
        }
    }

    private func selectionSummary(_ preview: TakeoutPreview) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 5) {
                GridRow {
                    metric("Supported documents", "\(preview.supportedDocuments) found · \(model.selectedDocuments.count) selected")
                    metric("Photos and videos", "\(preview.skippedMedia) skipped")
                    metric("Other / metadata", "\(preview.entries.filter { $0.kind == .unsupported || $0.kind == .metadata }.count) skipped")
                }
                GridRow {
                    metric("Source archives", ByteCountFormatter.string(fromByteCount: Int64(clamping: preview.sourceBytes), countStyle: .file))
                    metric("Additional source copies", ByteCountFormatter.string(fromByteCount: Int64(clamping: preview.additionalSourceBytes), countStyle: .file))
                    metric("Estimated index growth", "~\(ByteCountFormatter.string(fromByteCount: Int64(clamping: preview.estimatedIndexBytes), countStyle: .file))")
                }
            }
            Text("Estimated additional local storage: \(ByteCountFormatter.string(fromByteCount: Int64(clamping: model.estimatedAdditionalBytes), countStyle: .file)) · Available: \(ByteCountFormatter.string(fromByteCount: Int64(clamping: model.availableBytes), countStyle: .file)). ZIP documents receive durable local copies; extracted folders are indexed in place to save space. The index estimate is approximate. Original archives remain untouched.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.subheadline.weight(.medium)) }
    }

    private var selectionOptions: some View {
        HStack(alignment: .top, spacing: 22) {
            DisclosureGroup("Choose document types") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.formats) { group in
                        Toggle(".\(group.format)  ·  \(group.selected)/\(group.total)", isOn: Binding(get: { group.selected > 0 }, set: { model.setFormat(group.format.lowercased(), selected: $0) }))
                    }
                    Label("Photos and videos remain excluded", systemImage: "checkmark.shield").font(.caption).foregroundStyle(.secondary)
                }.padding(.top, 6)
            }
            DisclosureGroup("Choose folders") {
                ScrollView { VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.folders) { group in
                        Toggle("\(group.label)  ·  \(group.selected)/\(group.total)", isOn: Binding(get: { group.selected > 0 }, set: { model.setFolder(group.key, selected: $0) }))
                    }
                }.frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 145).padding(.top, 6)
            }
        }
        .font(.subheadline)
    }

    private func documentList(_ preview: TakeoutPreview) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Preview").font(.headline)
                Text("\(preview.selectedDocuments.count) selected").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Select Supported") { for entry in preview.entries where entry.kind == .document { model.setSelected(entry.id, true) } }.disabled(model.isImporting)
                Button("Select None") { for entry in preview.entries where entry.kind == .document { model.setSelected(entry.id, false) } }.disabled(model.isImporting)
            }
            List {
                ForEach(preview.entries) { entry in
                    HStack(spacing: 10) {
                        if entry.kind == .document {
                            Toggle(isOn: Binding(get: { entry.selected }, set: { model.setSelected(entry.id, $0) })) { EmptyView() }.labelsHidden().disabled(model.isImporting)
                        } else {
                            Image(systemName: entry.kind == .unsafe ? "exclamationmark.triangle.fill" : entry.kind == .photo || entry.kind == .video ? "photo" : "doc")
                                .foregroundStyle(entry.kind == .unsafe ? .orange : .secondary).frame(width: 18)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.relativePath).lineLimit(1).help(entry.relativePath)
                            HStack(spacing: 8) {
                                Text(entry.source.url.lastPathComponent).lineLimit(1)
                                Text(entry.kind.label)
                                if let title = entry.metadata?.title { Text("· \(title)").lineLimit(1) }
                            }.font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let status = model.resultByEntry[entry.id] { Text(status).font(.caption).foregroundStyle(status == "Failed" ? .red : .secondary) }
                        Text(ByteCountFormatter.string(fromByteCount: Int64(clamping: entry.uncompressedBytes), countStyle: .file)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }.padding(.vertical, 2)
                }
            }.listStyle(.inset).frame(minHeight: 210)
        }
    }

    private func issues(_ issues: [TakeoutIssue]) -> some View {
        DisclosureGroup("Scan findings (\(issues.count))") {
            List(issues) { issue in
                VStack(alignment: .leading, spacing: 2) {
                    Text(issue.message).font(.callout)
                    Text([issue.source, issue.path].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 2)
            }.frame(maxHeight: 100)
        }.foregroundStyle(.secondary)
    }

    private var failures: some View {
        DisclosureGroup("Import failures (\(model.failures.count))") {
            ScrollView { VStack(alignment: .leading, spacing: 4) { ForEach(Array(model.failures.enumerated()), id: \.offset) { _, value in Text(value).font(.caption).textSelection(.enabled) } }.frame(maxWidth: .infinity, alignment: .leading) }
                .frame(maxHeight: 105)
        }.foregroundStyle(.red)
    }

    private var importProgress: some View {
        VStack(alignment: .leading, spacing: 5) {
            ProgressView(value: model.progress)
            HStack {
                Text("\(model.completedCount) of \(model.selectedDocuments.count) · \(model.importedCount) imported · \(model.duplicateCount) duplicates · \(model.unchangedCount) unchanged")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let current = model.currentItem { Text(current).font(.caption).lineLimit(1) }
                Button("Cancel Safely") { model.cancelImport() }
            }
        }
    }

    private var footer: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                if model.isImporting { Text("Import in progress. Completed documents are indexed and searchable immediately.").font(.caption).foregroundStyle(.secondary) }
                else if !model.failures.isEmpty { Text("Retrying is safe: completed items are fingerprinted and skipped. Failed items can be retried by scanning the same source again.").font(.caption).foregroundStyle(.secondary) }
                else { Text("No passwords or Google credentials are requested. Imported sources stay on this Mac.").font(.caption).foregroundStyle(.secondary) }
                if !model.hasEnoughSpace && !model.selectedDocuments.isEmpty {
                    Text("Not enough free space for the selected ZIP source copies and estimated index. Reduce the selection or free storage first.").font(.caption).foregroundStyle(.red)
                }
            }
            Spacer()
            if model.isImporting {
                EmptyView()
            } else {
                Button(model.failures.isEmpty ? "Import Selected Documents" : "Resume / Retry Import") { model.startImport() }
                    .buttonStyle(.borderedProminent).disabled(model.selectedDocuments.isEmpty || !model.hasEnoughSpace)
            }
        }
    }
}
