import AppKit
import SwiftUI

struct KnowledgeLibraryView: View {
    @StateObject private var library = KnowledgeLibraryStore.shared
    @State private var query = ""
    @State private var results: [KnowledgeSearchResult] = []
    @State private var selectedID: UUID?
    @State private var scopeCollectionID: KnowledgeCollectionID?
    @State private var scopeDocumentID: KnowledgeDocumentID?
    @State private var referenceTitle = ""
    @State private var referenceURI = ""
    @State private var referenceNotes = ""
    @State private var showAddReference = false
    @State private var showTakeoutImport = false
    @State private var showCreateCollection = false
    @State private var showImportHistory = false
    @State private var newCollectionName = ""
    @State private var linkOrigin: KnowledgePassageReference?
    @State private var linkDescription = ""
    @State private var errorMessage: String?
    @State private var isAdding = false
    @State private var isAddingFolder = false
    private var selected: KnowledgeSearchResult? { results.first { $0.id == selectedID } }
    private var visibleDocuments: [KnowledgeDocumentRecord] {
        guard let scopeCollectionID else { return library.documents }
        return (try? library.documents(in: scopeCollectionID)) ?? []
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Picker("Collection", selection: $scopeCollectionID) {
                        Text("All Collections (\(library.documents.count))").tag(Optional<KnowledgeCollectionID>.none)
                        ForEach(library.collections) { collection in
                            Text("\(collection.name) (\(collection.documentCount))").tag(Optional(collection.id))
                        }
                    }.labelsHidden().frame(maxWidth: 300)
                    Button { showCreateCollection = true } label: { Label("New Collection", systemImage: "folder.badge.plus") }
                    Button { showImportHistory = true } label: { Label("Import History", systemImage: "clock.arrow.circlepath") }
                }.padding(.horizontal).padding(.top, 10)
                HStack {
                    TextField("Search this library", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { search() }
                    Button { search() } label: { Image(systemName: "magnifyingglass") }.help("Search")
                }.padding()
                if query.isEmpty && !visibleDocuments.isEmpty {
                    List {
                        if scopeDocumentID != nil { Button("Search All Documents") { scopeDocumentID = nil; scopeCollectionID = nil; search() } }
                        ForEach(visibleDocuments) { document in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(document.title).font(.headline)
                                HStack(spacing: 5) {
                                    Text("\(document.provenance) · \(statusLabel(document.status))").font(.caption).foregroundStyle(document.status == .available ? Color.secondary : Color.orange)
                                    if library.duplicateSourceCount(for: document.id) > 0 {
                                        Label("Duplicate source", systemImage: "doc.on.doc.fill").font(.caption).foregroundStyle(.orange)
                                    }
                                }
                                if let folders = try? library.sourceFolders(for: document.id), !folders.isEmpty {
                                    Text(folders.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Text(document.sourceURI).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }.padding(.vertical, 3)
                                .contextMenu {
                                    Button("Set Search Scope to This Document") { scopeDocumentID = document.id; search() }
                                    Menu("Move to Collection") {
                                        ForEach(library.collections.filter { $0.id != scopeCollectionID }) { collection in
                                            Button(collection.name) { do { try library.move(documentID: document.id, to: collection.id); search() } catch { errorMessage = error.localizedDescription } }
                                        }
                                    }
                                    if let collectionID = scopeCollectionID {
                                        Button("Remove from This Collection") { do { try library.remove(documentID: document.id, from: collectionID); search() } catch { errorMessage = error.localizedDescription } }
                                    } else {
                                        Button("Remove from Library") { do { try library.remove(documentID: document.id); search() } catch { errorMessage = error.localizedDescription } }
                                    }
                                }
                        }
                    }
                } else if results.isEmpty {
                    ContentUnavailableView(query.isEmpty ? "Search your library" : "No matches", systemImage: "text.book.closed", description: Text(query.isEmpty ? "Add documents, then search all indexed sources." : "Try other keywords or an exact phrase."))
                } else {
                    List(selection: $selectedID) {
                        ForEach(results) { result in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.document.title).font(.headline)
                                Text(result.reference.context).font(.caption).foregroundStyle(.secondary)
                                Text(result.excerpt).font(.callout).lineLimit(3)
                            }.padding(.vertical, 4).tag(result.id)
                                .contextMenu {
                                    Button("Open Passage") { open(result) }
                                    Button(linkOrigin == nil ? "Set as Link Origin" : "Link From Selected Passage") { makeLink(to: result) }
                                }
                        }
                    }
                }
            }
            .navigationTitle("Knowledge Library")
            .toolbar {
                ToolbarItemGroup {
                    Button { addFiles() } label: { Label("Add Documents", systemImage: "plus") }
                    Button { isAddingFolder = true } label: { Label("Add Folder", systemImage: "folder.badge.plus") }
                    Button { showTakeoutImport = true } label: { Label("Import from Google Takeout", systemImage: "archivebox") }
                    Button { showAddReference = true } label: { Label("Add Reference", systemImage: "link.badge.plus") }
                    Button { rebuild() } label: { Label("Rebuild Index", systemImage: "arrow.clockwise") }
                    Button { removeSelected() } label: { Label("Remove", systemImage: "minus") }.disabled(selected == nil)
                }
            }
        } detail: {
            if let selected {
                VStack(alignment: .leading, spacing: 14) {
                    Text(selected.document.title).font(.title2.bold())
                    Label(selected.reference.context, systemImage: "text.alignleft").foregroundStyle(.secondary)
                    Text(selected.excerpt).textSelection(.enabled).padding().frame(maxWidth: .infinity, alignment: .leading).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    Text(selected.document.sourceURI).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    Text("Source status: \(statusLabel(selected.document.status))").font(.caption).foregroundStyle(selected.document.status == .available ? Color.secondary : Color.orange)
                    if let folders = try? library.sourceFolders(for: selected.document.id), !folders.isEmpty {
                        Label("Original folder: \(folders.joined(separator: " · "))", systemImage: "folder").font(.caption).foregroundStyle(.secondary)
                    }
                    if library.duplicateSourceCount(for: selected.document.id) > 0 {
                        Label("Also imported from \(library.duplicateSourceCount(for: selected.document.id)) duplicate source item(s)", systemImage: "doc.on.doc.fill").font(.caption).foregroundStyle(.orange)
                    }
                    HStack {
                        Button("Open in BOLD Writer") { open(selected) }.buttonStyle(.borderedProminent)
                        Button("Find Related in All Documents") { scopeDocumentID = nil; search() }.disabled(query.isEmpty)
                        Button(linkOrigin == nil ? "Set as Link Origin" : "Link From Origin") { makeLink(to: selected) }
                        Button("View Backlinks") { showBacklinks() }
                    }
                    TextField("Optional link description", text: $linkDescription).textFieldStyle(.roundedBorder).frame(maxWidth: 420)
                    if linkOrigin != nil { Text("Link origin selected. Choose a different result as the destination.").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Text("A match helps you discover passages; it does not establish a factual relationship.").font(.caption).foregroundStyle(.secondary)
                }.padding(24)
            } else {
                ContentUnavailableView("Select a passage", systemImage: "arrow.left", description: Text("Search results include the source document and verified paragraph location."))
            }
        }
        .frame(minWidth: 850, minHeight: 540)
        .alert("Knowledge Library", isPresented: Binding(get: { errorMessage != nil || library.lastError != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? library.lastError ?? "Unknown error") }
        .fileImporter(isPresented: $isAdding, allowedContentTypes: [.item], allowsMultipleSelection: true) { outcome in
            do { for url in try outcome.get() { _ = try library.add(url: url, collectionID: scopeCollectionID) }; search() }
            catch { errorMessage = error.localizedDescription }
        }
        .fileImporter(isPresented: $isAddingFolder, allowedContentTypes: [.folder], allowsMultipleSelection: false) { outcome in
            do { for folder in try outcome.get() { _ = try library.add(folderURL: folder, collectionID: scopeCollectionID) }; search() }
            catch { errorMessage = error.localizedDescription }
        }
        .sheet(isPresented: $showAddReference) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Add External Reference").font(.title2.bold())
                TextField("Title", text: $referenceTitle)
                TextField("Source URL", text: $referenceURI)
                Text("Research notes (optional)").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $referenceNotes).frame(minHeight: 130).overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                HStack {
                    Button("Cancel") { showAddReference = false }
                    Spacer()
                    Button("Add to Library") {
                        do { _ = try library.addReference(title: referenceTitle.isEmpty ? referenceURI : referenceTitle, uri: referenceURI, notes: referenceNotes, collectionID: scopeCollectionID); referenceTitle = ""; referenceURI = ""; referenceNotes = ""; showAddReference = false; search() }
                        catch { errorMessage = error.localizedDescription }
                    }.disabled(referenceURI.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.padding(24).frame(width: 470, height: 340)
        }
        .sheet(isPresented: $showTakeoutImport) { GoogleTakeoutImportView(library: library, collectionID: scopeCollectionID) }
        .sheet(isPresented: $showCreateCollection) {
            VStack(alignment: .leading, spacing: 14) {
                Text("New Collection").font(.title2.bold())
                TextField("Collection name", text: $newCollectionName).textFieldStyle(.roundedBorder)
                HStack { Button("Cancel") { showCreateCollection = false }; Spacer(); Button("Create") {
                    do { scopeCollectionID = try library.createCollection(name: newCollectionName); newCollectionName = ""; showCreateCollection = false; scopeDocumentID = nil; search() }
                    catch { errorMessage = error.localizedDescription }
                }.buttonStyle(.borderedProminent).disabled(newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }.padding(24).frame(width: 400)
        }
        .sheet(isPresented: $showImportHistory) { KnowledgeImportHistoryView(library: library) }
        .onAppear { library.detectSourceChanges() }
        .onChange(of: query) { _, _ in search() }
        .onChange(of: scopeCollectionID) { _, _ in scopeDocumentID = nil; search() }
        .onReceive(library.$pendingNavigationRequest.compactMap { $0 }) { request in
            scopeCollectionID = nil
            scopeDocumentID = request.reference.documentID
            query = "\"\(request.quotation)\""
            search()
            selectedID = results.first(where: { $0.reference.passageID == request.reference.passageID })?.id ?? selectedID
            _ = library.consumeNavigationRequest()
        }
    }

    private func search() {
        do { results = try library.search(query, documentID: scopeDocumentID, collectionID: scopeCollectionID); if !results.contains(where: { $0.id == selectedID }) { selectedID = results.first?.id } }
        catch { errorMessage = error.localizedDescription }
    }
    private func addFiles() { isAdding = true }
    private func rebuild() { do { try library.rebuildIndex(); search() } catch { errorMessage = error.localizedDescription } }
    private func removeSelected() {
        guard let selected else { return }
        do {
            if let scopeCollectionID { try library.remove(documentID: selected.document.id, from: scopeCollectionID) }
            else { try library.remove(documentID: selected.document.id) }
            search()
        } catch { errorMessage = error.localizedDescription }
    }
    private func statusLabel(_ status: KnowledgeSourceStatus) -> String {
        switch status { case .available: "Indexed"; case .changed: "Changed"; case .unavailable: "Missing"; case .referenceOnly: "Reference" }
    }
    private func open(_ result: KnowledgeSearchResult) {
        guard let url = try? library.sourceURL(for: result.document.id), !result.document.isReference else { errorMessage = "This source is an external reference and has no local document to open."; return }
        let scoped = url.startAccessingSecurityScopedResource()
        guard (try? library.sourceMatches(documentID: result.document.id, fingerprint: result.reference.fingerprint)) == true else {
            if scoped { url.stopAccessingSecurityScopedResource() }
            do { try library.refresh(documentID: result.document.id); search(); errorMessage = "This source changed since it was indexed. Its old passage location was rejected; updated results are ready." }
            catch { errorMessage = error.localizedDescription }
            return
        }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if scoped { url.stopAccessingSecurityScopedResource() }
            if let error { errorMessage = error.localizedDescription; return }
            NotificationCenter.default.post(name: .knowledgeLibraryNavigate, object: nil, userInfo: ["documentID": result.document.id.rawValue.uuidString, "location": result.reference.utf16Range.location, "length": result.reference.utf16Range.length, "fingerprint": result.reference.fingerprint, "source": result.document.sourceURI])
        }
    }
    private func makeLink(to result: KnowledgeSearchResult) {
        guard let origin = linkOrigin else { linkOrigin = result.reference; return }
        guard origin.passageID != result.reference.passageID else { errorMessage = "Choose a different destination passage."; return }
        do { try library.createLink(from: origin, to: result.reference, description: linkDescription.isEmpty ? nil : linkDescription); linkOrigin = nil; linkDescription = "" }
        catch { errorMessage = error.localizedDescription }
    }
    private func showBacklinks() {
        guard let selected else { return }
        do { let links = try library.backlinks(to: selected.reference); let sources = links.compactMap { link in library.documents.first(where: { $0.id == link.origin.documentID })?.title }; errorMessage = links.isEmpty ? "No backlinks to this passage." : "Backlinks from: \(sources.joined(separator: ", "))" }
        catch { errorMessage = error.localizedDescription }
    }
}

extension Notification.Name { static let knowledgeLibraryNavigate = Notification.Name("BOLDWriter.KnowledgeLibrary.Navigate") }
