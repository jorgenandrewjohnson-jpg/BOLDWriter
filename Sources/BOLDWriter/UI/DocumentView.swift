import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct DocumentView: View {
    @ObservedObject var document: BOLDWriterDocument
    private let sourceURL: URL?
    @StateObject private var editor = EditorController()
    @StateObject private var ai = AIManager()
    @StateObject private var manuscriptAI = ManuscriptAssistantModel()
    @StateObject private var reader = ReadAloudManager()
    @State private var manuscriptImportID: UUID?
    @State private var importingManuscriptName = ""
    @State private var outline: [OutlineItem] = []
    @State private var statistics = DocumentStatistics()
    @State private var showLeftSidebar: Bool
    @State private var leftSidebarTab: LeftSidebarTab = .outline
    @State private var searchFocusRequest = UUID()
    @State private var showRightSidebar = false
    @State private var rightSidebarTab: RightSidebarTab = .assistant
    @State private var printLayout: Bool
    @State private var editingMode: DocumentEditingMode
    @State private var showNonPrintingCharacters = false
    @State private var showLineNumbers = false
    @State private var showParagraphFormatting = false
    @State private var focusMode = false
    @State private var showExport = false
    @State private var showKindle = false
    @State private var showPalette = false
    @State private var showHelp = false
    @State private var showPublishingTOC = false
    @State private var showBookHealthCheck = false
    @State private var showBookAudit = false
    @State private var bookHealthReport: BookHealthReport?
    @State private var isRunningBookHealthCheck = false
    @State private var bookWorkspace: BookWorkspaceNavigation
    @State private var productionRenderedPageCount: Int? = nil
    @State private var showTranslateDocument = false
    @State private var showVoiceTyping = false
    @State private var showCitations = false
    @State private var showEvidence = false
    @State private var showEvidenceReview = false
    @State private var evidenceSelection = NSRange(location: 0, length: 0)
    @State private var showWordCount = false
    @State private var voiceTypingRange = NSRange(location: 0, length: 0)
    @State private var voiceTypingAttributes: [NSAttributedString.Key: Any] = [:]
    @State private var voiceTypingSourceText = ""
    @State private var showEquationToolbar = false
    @AppStorage("showEditorRuler") private var showEditorRuler = true
    @State private var publishingTOCMode: PublishingTOCMode = .printBook
    @AppStorage("didShowWelcome") private var didShowWelcome = false
    @AppStorage("appearance") private var appearance = "System"
    @AppStorage("speechRate") private var speechRate = 0.48
    @AppStorage("speechVoice") private var speechVoice = ""

    init(
        document: BOLDWriterDocument,
        sourceURL: URL? = nil
    ) {
        self.document =
            document
        self.sourceURL = sourceURL
        _bookWorkspace = State(initialValue: BookWorkspaceNavigation(document: document))

        let textLength =
            document.text.length

        _showLeftSidebar =
            State(
                initialValue:
                    LargeDocumentPolicy
                        .initialNavigationVisible(
                            textLength:
                                textLength
                        )
            )

        _printLayout =
            State(
                initialValue:
                    LargeDocumentPolicy
                        .initialPrintLayout(
                            textLength:
                                textLength
                        )
            )

        _editingMode =
            State(
                initialValue:
                    (
                        document.metadata
                            .trackChangesEnabled
                        ?? false
                    )
                        ? .suggesting
                        : .editing
            )

    }

    // BOLD_LIGHT_WORKSPACE_V14
    var body: some View {
        boldLightDocumentWorkspaceBody
            .preferredColorScheme(.light)
    }

    @ViewBuilder
    private var boldLightDocumentWorkspaceBody: some View {
        VStack(spacing: 0) {
        WordTitleBar(document: document)
        if manuscriptImportID != nil {
            HStack {
                ProgressView().controlSize(.small)
                Text("Importing \(importingManuscriptName)…")
                Spacer()
                Button("Cancel") { manuscriptImportID = nil }
            }.padding(8)
        }

        BookWorkspaceSwitcher(current: bookWorkspace.active, onSelect: selectWorkspace)
        DocumentFeatureToolbar(
            actions: DocumentFeatureActions(
                evidenceReview: { showEvidenceReview = true },
                evidence: {
                    evidenceSelection = editor.selection
                    showEvidence = true
                },
                readAloud: { reader.readSelection(in: editor) },
                audiobookStudio: openAudiobookStudio
            ),
            onReadSelection: { reader.readSelection(in: editor) },
            onReadParagraph: { reader.readParagraph(in: editor) },
            onReadSection: { reader.readSection(in: editor) },
            onReadFromCursor: { reader.readFromCursor(in: editor) },
            onReadDocument: { reader.readDocument(in: editor) }
        )

        WordRibbon(
            editor: editor,
            showLeftSidebar: $showLeftSidebar,
            showRightSidebar: $showRightSidebar,
            printLayout: $printLayout,
            editingMode: editingMode,
            onSetEditingMode: setEditingMode,
            showNonPrintingCharacters: showNonPrintingCharacters,
            onToggleNonPrintingCharacters: {
                showNonPrintingCharacters.toggle()
            },
            showLineNumbers: showLineNumbers,
            onToggleLineNumbers: {
                showLineNumbers.toggle()
            },
            onExport: {
                showExport = true
            },
            onInsertTOC:
                { publishingTOCMode = .printBook; showPublishingTOC = true },
            onInsertTOCMode: { mode in publishingTOCMode=mode; showPublishingTOC=true },
            onBookCoverCreator: { selectWorkspace(.coverCreator) },
            onBookHealthCheck: { showBookAudit = true },
            onPhysicalBookPreview: { selectWorkspace(.bookStudio3D) },
            onShowEquationToolbar: {
                showEquationToolbar = true
            },
            onInsertFootnote: {
                editor.insertFootnote(
                    trackChanges:
                        document.metadata
                            .trackChangesEnabled
                        ?? false
                )
            },
            onEditFootnote: {
                editor.editSelectedFootnote()
            },
            onInsertEndnote: {
                editor.insertEndnote(
                    trackChanges:
                        document.metadata
                            .trackChangesEnabled
                        ?? false
                )
            },
            onEditEndnote: {
                editor.editSelectedEndnote()
            },
            onShowCitations: {
                showCitations = true
            },
            onInsertBibliography: insertBibliography,
            onNewComment: addComment,
            onEditComment: editSelectedComment,
            onDeleteComment: deleteSelectedComment,
            onPreviousComment: { editor.navigateComment(previous: true, in: document) },
            onNextComment: { editor.navigateComment(previous: false, in: document) },
            onShowComments: toggleComments,
            onCheckSpelling: checkSpelling,
            onShowSpellingPanel: showSpellingAndGrammar,
            onLink: applyLink,
            onBookmark: addBookmark,
            onCrossReference: insertCrossReference,
            onUpdateFields: { _ = editor.updateAllFields(in: document) },
            onInsertCaption: insertCaption
        ).disabled(!editingMode.isEditable)

        if showEquationToolbar {
            WordEquationToolbar(
                editor: editor,
                onClose: {
                    showEquationToolbar = false
                }
            )
        }

        HStack(spacing: 0) {
                    LeftSidebarView(
                        document: document,
                        editor: editor,
                        outline: outline,
                        tab: $leftSidebarTab,
                        searchFocusRequest: searchFocusRequest
                    )
                        .frame(width: showLeftSidebar && !focusMode ? 240 : 0)
                        .clipped()
                        .accessibilityHidden(!showLeftSidebar || focusMode)
                        .allowsHitTesting(showLeftSidebar && !focusMode)
                        .disabled(!showLeftSidebar || focusMode)
                    if showLeftSidebar && !focusMode { Divider() }
                    ZStack(alignment: .bottom) {
                        editorCanvas
                        if reader.isSpeaking || reader.isPaused { playbackBar }
                    }
                    .frame(minWidth: 0, maxWidth: .infinity)
                    if showRightSidebar && !focusMode { Divider() }
                    RightSidebarView(document: document, editor: editor, ai: ai, manuscriptAI: manuscriptAI, statistics: statistics, tab: $rightSidebarTab)
                        .frame(width: showRightSidebar && !focusMode ? 300 : 0)
                        .clipped()
                        .accessibilityHidden(!showRightSidebar || focusMode)
                        .allowsHitTesting(showRightSidebar && !focusMode)
                        .disabled(!showRightSidebar || focusMode)
                }

        WordStatusBar(
            showLeftSidebar: $showLeftSidebar,
            printLayout: $printLayout,
            statistics: statistics,
            onShowWordCount: {
                showWordCount = true
            },
            zoom: Binding(
                get: {
                    editor.zoom
                },
                set: {
                    editor.zoom = $0
                }
            )
        )
    }
        .allowsHitTesting(bookWorkspace.active == .manuscript)
        .accessibilityHidden(bookWorkspace.active != .manuscript)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(appearance == "Dark" ? .dark : appearance == "Light" ? .light : nil)
        .focusedSceneValue(\.documentActions, actions)
        .overlay { workspaceOverlay }
        .safeAreaInset(
            edge:
                .bottom,
            spacing:
                0
        ) {
            BookProductionStatusStrip(
                snapshot:
                    productionStatusSnapshot,
                workspace:
                    bookWorkspace.active,
                onIssue:
                    routeProductionStatusIssue
            )
        }
        .sheet(item: $editor.editingFootnote) { note in FootnoteEditorView(
                note: note,
                editor: editor,
                trackChangesEnabled:
                    document.metadata
                        .trackChangesEnabled
                        ?? false
            ) }
        .sheet(item: $editor.editingEndnote) { note in EndnoteEditorView(
                note: note,
                editor: editor,
                trackChangesEnabled:
                    document.metadata
                        .trackChangesEnabled
                        ?? false
            ) }
        .sheet(isPresented: $showExport) { ExportView(document: document) }
        .sheet(isPresented: $showKindle) { ExportView(document: document, kindleMode: true) }
        .sheet(isPresented: $showTranslateDocument) {
            if #available(macOS 15.0, *) {
                TranslateDocumentView(
                    source:
                        document.text
                ) {
                    replacement,
                    languageName in

                    applyTranslation(
                        replacement,
                        languageName:
                            languageName
                    )
                }
            } else {
                TranslateDocumentUnavailableView()
            }
        }
        .sheet(isPresented: $showVoiceTyping) {
            VoiceTypingView {
                transcript in

                insertVoiceTypingTranscript(
                    transcript
                )
            }
        }
        .sheet(isPresented: $showCitations) {
            CitationManagerView(
                sources:
                    document.metadata
                        .citationSources
                        ?? [],
                style:
                    document.metadata
                        .citationStyle
                        ?? .apa,
                referencedSourceIDs: Set((document.metadata.claimEvidence ?? []).map(\.sourceID)).union(
                    DocumentCitations.citedSourceResolution(
                        in: document.text.string,
                        sources: document.metadata.citationSources ?? [],
                        style: document.metadata.citationStyle ?? .apa
                    ).citedSourceIDs
                ),
                onMergeSources: { keepID, removeID, draftSources in
                    guard document.createRevision(named: "Before Evidence Source Merge") else { return nil }
                    guard saveCitationLibrary(
                        sources: draftSources,
                        style: document.metadata.citationStyle ?? .apa
                    ) else { return nil }
                    do {
                        let merged = try DocumentEvidence.mergeSourceRecords(
                            keeping: keepID,
                            removing: removeID,
                            sources: document.metadata.citationSources ?? draftSources,
                            evidence: document.metadata.claimEvidence ?? []
                        )
                        document.metadata.citationSources = merged.sources
                        document.metadata.claimEvidence = merged.evidence
                        return merged.sources
                    } catch {
                        document.lastErrorMessage = error.localizedDescription
                        return nil
                    }
                },
                onSave: {
                    sources,
                    style in

                    saveCitationLibrary(
                        sources:
                            sources,
                        style:
                            style
                    )
                },
                onInsertCitation: {
                    source,
                    style,
                    sources in

                    saveCitationLibrary(
                        sources:
                            sources,
                        style:
                            style
                    )

                    insertCitation(
                        source,
                        style:
                            style
                    )
                },
                onInsertBibliography: {
                    sources,
                    style in

                    saveCitationLibrary(
                        sources:
                            sources,
                        style:
                            style
                    )

                    insertBibliography(
                        sources:
                            sources,
                        style:
                            style
                    )
                }
            )
        }
        .sheet(isPresented: $showEvidence) {
            EvidenceManagerView(
                manuscript: document.text.string,
                selection: evidenceSelection,
                sources: document.metadata.citationSources ?? [],
                evidence: document.metadata.claimEvidence ?? [],
                citationStyle: document.metadata.citationStyle ?? .apa,
                onSave: { sources, records in
                    document.metadata.citationSources = DocumentCitations.normalized(sources)
                    document.metadata.claimEvidence = records
                },
                onInsertCitation: { source in
                    insertCitationAfterEvidenceClaim(
                        source,
                        style: document.metadata.citationStyle ?? .apa,
                        selection: evidenceSelection
                    )
                }
            )
        }
        .sheet(isPresented: $showEvidenceReview) {
            EvidenceReviewView(
                manuscript: document.text.string,
                sources: document.metadata.citationSources ?? [],
                evidence: document.metadata.claimEvidence ?? [],
                style: document.metadata.citationStyle ?? .apa,
                outline: outline.isEmpty ? DocumentAnalysis.outline(for: document.text) : outline,
                onNavigateToClaim: { range in
                    guard let textView = editor.textView,
                          range.location >= 0,
                          range.length >= 0,
                          NSMaxRange(range) <= (textView.string as NSString).length else { return }
                    textView.window?.makeFirstResponder(textView)
                    textView.setSelectedRange(range)
                    textView.scrollRangeToVisible(range)
                },
                onAttachEvidence: { range in
                    showEvidenceReview = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        evidenceSelection = range
                        if let textView = editor.textView {
                            textView.window?.makeFirstResponder(textView)
                            textView.setSelectedRange(range)
                            textView.scrollRangeToVisible(range)
                        }
                        showEvidence = true
                    }
                },
                onUpdateCitations: { range in
                    updateCitationDisplays(within: range)
                }
            )
        }
        .sheet(isPresented: $showPalette) { CommandPaletteView(actions: actions) }
        .sheet(isPresented: $showWordCount) {
            WordCountView(
                statistics: statistics
            )
        }
        .sheet(isPresented: $showHelp) { HelpView() }
        .sheet(isPresented:$showPublishingTOC) {
            PublishingTOCCreatorView(mode:publishingTOCMode,onInsert:{settings in
                editor.insertTableOfContents(levels:settings.maximumHeadingLevel,mode:settings.mode,title:settings.title,showTitle:settings.showTitle,leader:settings.leader,customSettings:settings)
            },onUpdate:{settings in editor.updateSelectedTableOfContents(settings:settings,in:document)})
        }
        .sheet(isPresented: $showBookHealthCheck) {
            if let bookHealthReport {
                BookHealthCheckView(report: bookHealthReport) {
                    showBookHealthCheck = false
                    selectWorkspace(.coverCreator)
                }
            } else if isRunningBookHealthCheck {
                ProgressView("Checking production pagination and print covers…")
                    .padding(32)
                    .frame(minWidth: 420, minHeight: 180)
                    .accessibilityLabel("Checking My Book")
            }
        }
        .sheet(isPresented: $showBookAudit) {
            BookAuditView(document: document, editor: editor, onPrintReadinessCheck: {
                showBookAudit = false
                runBookHealthCheck()
            })
        }
        .sheet(isPresented: Binding(get: { !didShowWelcome }, set: { if !$0 { didShowWelcome = true } })) {
            WelcomeView(showHelp: $showHelp).interactiveDismissDisabled()
        }
        .task(id: document.revisionID) {
            let openingTextLength =
                document.text.length

            if LargeDocumentPolicy
                .isLarge(
                    textLength:
                        openingTextLength
                ),
               printLayout {
                printLayout =
                    false
            }

            do {
                try await Task.sleep(
                    for:
                        .milliseconds(
                            300
                        )
                )
            } catch {
                return
            }

            let revision =
                document.revisionID

            let textLength =
                document.text.length

            let shouldBuildOutline =
                LargeDocumentPolicy
                    .shouldBuildOutlineAutomatically(
                        textLength:
                            textLength,
                        navigationVisible:
                            showLeftSidebar
                    )

            let headings =
                shouldBuildOutline
                    ? DocumentAnalysis
                        .outline(
                            for:
                                document.text
                        )
                    : []

            let string =
                document.text.string

            let measured =
                await Task.detached(
                    priority:
                        .utility
                ) {
                    DocumentAnalysis
                        .statistics(
                            for:
                                string,
                            headingCount:
                                headings.count
                        )
                }
                .value

            guard
                !Task.isCancelled,
                document.revisionID
                    == revision
            else {
                return
            }

            outline =
                headings

            statistics =
                measured
        }
        .task(id: showLeftSidebar) {
            guard
                showLeftSidebar,
                LargeDocumentPolicy
                    .isLarge(
                        textLength:
                            document.text.length
                    ),
                outline.isEmpty
            else {
                return
            }

            do {
                try await Task.sleep(
                    for:
                        .milliseconds(
                            150
                        )
                )
            } catch {
                return
            }

            let revision =
                document.revisionID

            let headings =
                DocumentAnalysis
                    .outline(
                        for:
                            document.text
                    )

            guard
                !Task.isCancelled,
                document.revisionID
                    == revision,
                showLeftSidebar
            else {
                return
            }

            outline =
                headings
        }
        .onAppear {
            reader.rate = speechRate
            reader.selectedVoiceIdentifier = speechVoice
            editor.document = document
            editor.namedStyleDefinitions = NamedStyles.mergedWithBuiltIns(document.metadata.namedStyles ?? [])
        }
        .onReceive(NotificationCenter.default.publisher(for: .knowledgeLibraryNavigate)) { notification in
            guard let info = notification.userInfo,
                  let documentIDString = info["documentID"] as? String,
                  let documentUUID = UUID(uuidString: documentIDString),
                  let location = info["location"] as? Int,
                  let length = info["length"] as? Int,
                  let fingerprint = info["fingerprint"] as? String,
                  let source = info["source"] as? String,
                  let sourceURL,
                  sourceURL.standardizedFileURL.path == URL(string: source)?.standardizedFileURL.path,
                  (try? KnowledgeLibraryStore.shared.sourceMatches(documentID: KnowledgeDocumentID(documentUUID), fingerprint: fingerprint)) == true else { return }
            let range = NSRange(location: location, length: length)
            guard range.location >= 0, range.length >= 0, NSMaxRange(range) <= document.text.length else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                guard let textView = editor.textView, NSMaxRange(range) <= (textView.textStorage?.length ?? 0) else { return }
                textView.setSelectedRange(range)
                textView.scrollRangeToVisible(range)
                textView.window?.makeFirstResponder(textView)
            }
        }
        .onChange(of: speechRate) { _, value in reader.rate = value }
        .onChange(of: speechVoice) { _, value in reader.selectedVoiceIdentifier = value }
        .onDisappear { reader.stop() }
        .onChange(of: document.revisionID) { _, _ in
            productionRenderedPageCount =
                nil
        }
        .alert("BOLD Writer", isPresented: Binding(get: { document.lastErrorMessage != nil }, set: { if !$0 { document.lastErrorMessage = nil } })) {
            Button("OK") { document.lastErrorMessage = nil }
        } message: { Text(document.lastErrorMessage ?? "") }
        .onExitCommand { if focusMode { focusMode = false } }
        .frame(minWidth: 850, minHeight: 680)

        .onDrop(
            of:
                [
                    UTType.fileURL
                ],
            isTargeted:
                nil
        ) {
            providers in

            handleDroppedFiles(
                providers
            )
        }
}

    private var productionStatusPageSettings:
        [PageSettings]
    {
        var result =
            [
                document.metadata.page
            ]

        result.append(
            contentsOf:
                (
                    document.metadata.sections
                    ?? []
                )
                .map {
                    $0.page
                }
        )

        return result
    }

    private var productionStatusSnapshot:
        BookProductionStatusSnapshot
    {
        BookProductionStatusSnapshot
            .make(
                projects:
                    document.metadata
                        .coverProjects
                    ?? [],
                activeProjectID:
                    document.metadata
                        .activeCoverProjectID,
                renderedPageCount:
                    productionRenderedPageCount,
                manuscriptPageSettings:
                    productionStatusPageSettings
            )
    }

    private var activePrintCoverForStatus:
        CoverProject?
    {
        BookProductionStatusSnapshot
            .activePrintProject(
                projects:
                    document.metadata
                        .coverProjects
                    ?? [],
                activeProjectID:
                    document.metadata
                        .activeCoverProjectID
            )
    }

    private func routeProductionStatusIssue(
        _ issue:
            BookProductionReadinessIssue
    ) {
        switch issue {
        case .ready:
            return

        case .needsManuscriptPagination,
             .trimMismatch,
             .pageCountMismatch:
            selectWorkspace(
                .manuscript
            )

        case .spineMismatch:
            if let project =
                activePrintCoverForStatus
            {
                bookWorkspace
                    .requestCoverEdit(
                        projectID:
                            project.id,
                        panel:
                            .spine
                    )
            }

            selectWorkspace(
                .coverCreator
            )

        case .productionProfileMismatch,
             .manualCustom:
            if let project =
                activePrintCoverForStatus
            {
                bookWorkspace
                    .requestCoverEdit(
                        projectID:
                            project.id,
                        panel:
                            nil
                    )
            }

            selectWorkspace(
                .coverCreator
            )

        case .missingPrintCover:
            selectWorkspace(
                .coverCreator
            )
        }
    }

    private var workspaceOverlay: some View {
        GeometryReader { geometry in
            ZStack {
                if bookWorkspace.hasVisitedCover {
                    BookCoverCreatorView(
                        projects: bookWorkspace.document.metadata.coverProjects ?? [],
                        activeProjectID: bookWorkspace.document.metadata.activeCoverProjectID,
                        isActive: bookWorkspace.active == .coverCreator,
                        focusPanel: bookWorkspace.coverFocusPanel,
                        focusRequestID: bookWorkspace.coverFocusRequestID,
                        onSave: { projects, activeID in
                            bookWorkspace.saveCoverProjects(projects, activeID: activeID)
                        },
                        productionPreflight: { project in
                            var pageSettings: [PageSettings] = []
                            let bytes = try PDFExporter.data(
                                from: bookWorkspace.document.text,
                                settings: bookWorkspace.document.metadata.page,
                                sections: bookWorkspace.document.metadata.sections,
                                pageLayoutSink: { pageSettings = $0 },
                                floatingImages: bookWorkspace.document.metadata.floatingImages ?? []
                            )
                            guard let pdf = PDFDocument(data: bytes), pdf.pageCount > 0 else {
                                throw WriterError.message("Manuscript pagination produced no export-ready pages.")
                            }
                            return PhysicalBookDiagnostics.publishingPreflight(
                                project: project,
                                manuscriptPageCount: pdf.pageCount,
                                pageSettings: pageSettings
                            )
                        },
                        convertPaperback: { source, paper in
                            var pageSettings: [PageSettings] = []
                            let bytes = try PDFExporter.data(
                                from: bookWorkspace.document.text,
                                settings: bookWorkspace.document.metadata.page,
                                sections: bookWorkspace.document.metadata.sections,
                                pageLayoutSink: { pageSettings = $0 },
                                floatingImages: bookWorkspace.document.metadata.floatingImages ?? []
                            )
                            guard let pdf = PDFDocument(data: bytes), pdf.pageCount > 0,
                                  let first = pageSettings.first else {
                                throw WriterError.message("Manuscript pagination produced no export-ready pages.")
                            }
                            let width = Double(first.pageSize.width / 72)
                            let height = Double(first.pageSize.height / 72)
                            guard pageSettings.allSatisfy({
                                abs(Double($0.pageSize.width / 72) - width) <= 0.01
                                    && abs(Double($0.pageSize.height / 72) - height) <= 0.01
                            }) else {
                                throw WriterError.message("Manuscript pages use mixed trim sizes. Resolve pagination before generating a print wrap.")
                            }
                            guard let converted = PhysicalBookGeometry.adaptingArtworkToKDPPaperback(
                                source,
                                pageCount: pdf.pageCount,
                                trimWidth: width,
                                trimHeight: height,
                                paperStock: paper
                            ) else {
                                throw WriterError.message("Could not convert this artwork to the selected KDP paperback profile.")
                            }
                            return converted
                        },
                        convertHardcover: { source, paper in
                            var pageSettings: [PageSettings] = []
                            let bytes = try PDFExporter.data(
                                from: bookWorkspace.document.text,
                                settings: bookWorkspace.document.metadata.page,
                                sections: bookWorkspace.document.metadata.sections,
                                pageLayoutSink: { pageSettings = $0 },
                                floatingImages: bookWorkspace.document.metadata.floatingImages ?? []
                            )
                            guard let pdf = PDFDocument(data: bytes), pdf.pageCount > 0,
                                  let first = pageSettings.first else {
                                throw WriterError.message("Manuscript pagination produced no export-ready pages.")
                            }
                            let layout = PhysicalBookGeometry.kdpMeasured391HardcoverLayout
                            guard pdf.pageCount == layout.pageCount else {
                                throw WriterError.message("KDP hardcover measurements are verified for 391 pages. This manuscript currently paginates to \(pdf.pageCount); use the KDP calculator for its exact page count before generating hardcover geometry.")
                            }
                            let width = Double(first.pageSize.width / 72)
                            let height = Double(first.pageSize.height / 72)
                            guard abs(width - layout.trimWidth) <= 0.01,
                                  abs(height - layout.trimHeight) <= 0.01,
                                  pageSettings.allSatisfy({ abs(Double($0.pageSize.width / 72) - width) <= 0.01 && abs(Double($0.pageSize.height / 72) - height) <= 0.01 }),
                                  PhysicalBookDiagnostics.kdpInteriorMarginIssues(pageSettings: pageSettings, pageCount: pdf.pageCount).isEmpty else {
                                throw WriterError.message("Resolve the manuscript trim, pagination, and KDP margin errors before creating a hardcover wrap.")
                            }
                            guard let converted = PhysicalBookGeometry.adaptingArtworkToKDPHardcover(
                                source, pageCount: pdf.pageCount, trimWidth: width,
                                trimHeight: height, paperStock: paper,
                                measuredLayout: layout
                            ) else {
                                throw WriterError.message("Could not adapt this artwork to the measured KDP hardcover profile.")
                            }
                            return converted
                        },
                        onApplyProductionTemplate: { template in
                            bookWorkspace.applyProductionTemplateToManuscript(
                                template
                            )
                        },
                        onOpenManuscript: { selectWorkspace(.manuscript) },
                        onOpenBookStudio: { selectWorkspace(.bookStudio3D) },
                        onOpenBookStudioPanel: { panel in
                            bookWorkspace.requestStudioFocus(
                                panel:
                                    panel
                            )
                        }
                    )
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .background(Color(red: 37/255, green: 37/255, blue: 37/255))
                    .opacity(bookWorkspace.active == .coverCreator ? 1 : 0)
                    .allowsHitTesting(bookWorkspace.active == .coverCreator)
                    .disabled(bookWorkspace.active != .coverCreator)
                    .accessibilityHidden(bookWorkspace.active != .coverCreator)
                }

                if bookWorkspace.hasVisitedStudio {
                    PhysicalBookPreview(
                        document: bookWorkspace.document,
                        isActive: bookWorkspace.active == .bookStudio3D,

                        requestedFocusComponent:

                            bookWorkspace.studioFocusComponent,

                        focusRequestID:

                            bookWorkspace.studioFocusRequestID,
                                                onRenderedPageCountChange: { count in
                            productionRenderedPageCount = count
                        },
onEditCover: { id, panel in
                            bookWorkspace.requestCoverEdit(
                                projectID:
                                    id,
                                panel:
                                    panel
                            )

                            selectWorkspace(
                                .coverCreator
                            )
                        },
                        onEditManuscript: { pageNumber, range in
                            bookWorkspace.requestManuscriptEdit(
                                pageNumber:
                                    pageNumber,
                                range:
                                    range
                            )

                            openRequestedManuscriptPage()
                        },
                        onOpenAutomationStudio: { selectWorkspace(.automationStudio) }
                    )
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .opacity(bookWorkspace.active == .bookStudio3D ? 1 : 0)
                    .allowsHitTesting(bookWorkspace.active == .bookStudio3D)
                    .disabled(bookWorkspace.active != .bookStudio3D)
                    .accessibilityHidden(bookWorkspace.active != .bookStudio3D)
                }

                if bookWorkspace.hasVisitedAutomation {
                    AutomationStudioView(
                        document: document,
                        editor: editor,
                        onSelectWorkspace: selectWorkspace
                    )
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .opacity(bookWorkspace.active == .automationStudio ? 1 : 0)
                    .allowsHitTesting(bookWorkspace.active == .automationStudio)
                    .disabled(bookWorkspace.active != .automationStudio)
                    .accessibilityHidden(bookWorkspace.active != .automationStudio)
                }
            }
        }
    }

    private func openRequestedManuscriptPage() {
        selectWorkspace(
            .manuscript
        )

        let pageNumber =
            bookWorkspace.manuscriptPageRequest
            ?? 1

        let range =
            bookWorkspace.manuscriptRangeRequest

        DispatchQueue.main.async {
            guard
                bookWorkspace.active
                    == .manuscript,
                let textView =
                    editor.textView
            else {
                return
            }

            textView.window?
                .makeFirstResponder(
                    textView
                )

            if let scroll =
                textView.enclosingScrollView,
               let canvas =
                scroll.documentView
                    as? PaginatedEditor
            {
                canvas.revealPhysicalPage(
                    pageNumber,
                    selection:
                        range
                )

                return
            }

            if let range {
                let documentLength =
                    textView.string
                        .utf16
                        .count

                let location =
                    min(
                        max(
                            0,
                            range.location
                        ),
                        documentLength
                    )

                let available =
                    max(
                        0,
                        documentLength
                        - location
                    )

                let length =
                    min(
                        max(
                            0,
                            range.length
                        ),
                        available
                    )

                let safeRange =
                    NSRange(
                        location:
                            location,
                        length:
                            length
                    )

                textView.setSelectedRange(
                    safeRange
                )

                textView.scrollRangeToVisible(
                    safeRange
                )
            }
        }
    }

    private func selectWorkspace(_ destination: BookWorkspace) {
        guard bookWorkspace.active != destination else { return }
        if destination != .manuscript {
            editor.textView?.window?.makeFirstResponder(nil)
        }
        bookWorkspace.open(destination)
        if destination == .bookStudio3D, let window = editor.textView?.window,
           !window.styleMask.contains(.fullScreen) {
            let size = window.contentRect(forFrameRect: window.frame).size
            if size.width < 1210 || size.height < 740 {
                window.setContentSize(NSSize(width: max(1210, size.width), height: max(740, size.height)))
            }
        }
        if destination == .manuscript {
            DispatchQueue.main.async {
                guard bookWorkspace.active == .manuscript,
                      let textView = editor.textView else { return }
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    private var editorCanvas: some View {
        VStack(spacing: 0) {
            ZStack {
                Color(nsColor: printLayout ? .underPageBackgroundColor : .textBackgroundColor)
                RichTextEditor(document: document, controller: editor, printLayout: printLayout, editingEnabled: editingMode.isEditable, showNonPrintingCharacters: showNonPrintingCharacters, showLineNumbers: showLineNumbers, showRuler: showEditorRuler, onContextLink: applyLink, onContextComment: addComment, onContextSuggest: { setEditingMode(.suggesting) }, onContextSpelling: showSpellingAndGrammar, onImportManuscript: importManuscript, onPaginationFailure: { message in
                    printLayout = false
                    document.lastErrorMessage = message
                })
                    .frame(minWidth: 0, maxWidth: .infinity)

            }
            Divider()
            HStack(spacing: 8) {
                Button {
                    showLeftSidebar = focusMode || !showLeftSidebar
                    focusMode = false
                } label: { Image(systemName: "sidebar.left") }
                .help(showLeftSidebar && !focusMode ? "Hide Navigation" : "Show Navigation")
                .accessibilityLabel("Toggle Navigation sidebar")
                Text("\(statistics.words.formatted()) words").lineLimit(1)

                Text(
                    editingMode.rawValue
                )
                .lineLimit(1)

                Spacer()
                Picker("View", selection: $printLayout) {
                    Label("Continuous", systemImage: "text.alignleft").tag(false)
                    Label("Print Layout", systemImage: "doc").tag(true)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 190)
                Slider(value: $editor.zoom, in: 0.5...2.0, step: 0.05).frame(width: 80).accessibilityLabel("Zoom")
                Text("\(Int(editor.zoom * 100))%").monospacedDigit().frame(width: 42)
                Button {
                    showRightSidebar = focusMode || !showRightSidebar
                    focusMode = false
                } label: { Image(systemName: "sidebar.right") }
                .help(showRightSidebar && !focusMode ? "Hide Inspector" : "Show Inspector")
                .accessibilityLabel("Toggle AI, Inspector, and History sidebar")
            }.buttonStyle(.borderless).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12).frame(height: 30)
        }
    }

    private var playbackBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { playbackTransport; playbackSettings }
            VStack(spacing: 8) { playbackTransport; playbackSettings }
        }
        .buttonStyle(.borderless).padding(.horizontal, 18).padding(.vertical, 10)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 22))
        .shadow(radius: 8).padding(.horizontal, 12).padding(.bottom, 42)
    }

    private var playbackTransport: some View {
        HStack(spacing: 14) {
            Button { reader.moveSentence(direction: -1, editor: editor) } label: { Image(systemName: "backward.end.fill") }.help("Previous sentence")
            Button { reader.pauseOrResume() } label: { Image(systemName: reader.isPaused ? "play.fill" : "pause.fill") }
            Button { reader.stop() } label: { Image(systemName: "stop.fill") }
            Button { reader.moveSentence(direction: 1, editor: editor) } label: { Image(systemName: "forward.end.fill") }.help("Next sentence")
            Menu("Passage") {
                Button("Previous Paragraph") { reader.moveParagraph(direction: -1, editor: editor) }
                Button("Next Paragraph") { reader.moveParagraph(direction: 1, editor: editor) }
            }
            Text(reader.activeLabel).font(.caption).frame(minWidth: 90)
        }
    }

    private var playbackSettings: some View {
        HStack(spacing: 14) {
            Slider(value: $reader.rate, in: 0.1...0.65).frame(width: 100).accessibilityLabel("Speaking speed")
            Image(systemName: "speaker.wave.2").accessibilityHidden(true)
            Slider(value: $reader.volume, in: 0...1).frame(width: 70).accessibilityLabel("Volume for next playback")
        }
    }

    @ToolbarContentBuilder private var writerToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            if !focusMode {
                Button { showLeftSidebar.toggle() } label: { Label("Navigation", systemImage: "sidebar.left") }
                Button { showRightSidebar.toggle() } label: { Label("Inspector", systemImage: "sidebar.right") }
            }
        }
        ToolbarItemGroup(placement: .principal) {
            Menu {
                Section("Document") {
                    Button("Normal") {
                        editor.applyStyle(.normal)
                    }

                    Button("Title") {
                        editor.applyStyle(.title)
                    }

                    Button("Subtitle") {
                        editor.applyStyle(.subtitle)
                    }
                }

                Section("Headings") {
                    Button("Heading 1") {
                        editor.applyStyle(.heading1)
                    }

                    Button("Heading 2") {
                        editor.applyStyle(.heading2)
                    }

                    Button("Heading 3") {
                        editor.applyStyle(.heading3)
                    }

                    Button("Heading 4") {
                        editor.applyStyle(.heading4)
                    }
                    Button("Heading 5") { editor.applyStyle(.heading5) }
                    Button("Heading 6") { editor.applyStyle(.heading6) }
                }

                Section("Other Styles") {
                    Button("Normal") { editor.applyStyle(.normal) }
                    Button("No Spacing") { editor.applyStyle(.noSpacing) }
                    Button("Title") { editor.applyStyle(.title) }
                    Button("Subtitle") { editor.applyStyle(.subtitle) }
                    Button("Intense Quote") { editor.applyStyle(.intenseQuote) }
                }

                Section("Quotes & Supporting Text") {
                    Button("Quote") {
                        editor.applyStyle(.quote)
                    }

                    Button("Block Quote") {
                        editor.applyStyle(.blockQuote)
                    }

                    Button("Caption") {
                        editor.applyStyle(.caption)
                    }
                }
            } label: {
                Label(
                    editor.selectedNamedStyleName,
                    systemImage: "textformat"
                )
            }
            .frame(width: 125)
            .help("Paragraph style")

            Picker(
                "Font",
                selection: Binding(
                    get: { editor.fontFamily },
                    set: { editor.setFontFamily($0) }
                )
            ) {
                ForEach(NSFontManager.shared.availableFontFamilies, id: \.self) { family in
                    Text(family).tag(family)
                }
            }
            .frame(width: 145)
            .help("Font family")

            TextField("Size", value: $editor.fontSize, format: .number)
                .frame(width: 42)
                .onSubmit {
                    editor.setFontSize(editor.fontSize)
                }
                .help("Font size")

            Button {
                editor.toggleTrait(.boldFontMask)
            } label: {
                Image(systemName: "bold")
            }
            .help("Bold")

            Button {
                editor.toggleTrait(.italicFontMask)
            } label: {
                Image(systemName: "italic")
            }
            .help("Italic")

            Button {
                editor.toggleUnderline()
            } label: {
                Image(systemName: "underline")
            }
            .help("Underline")

            Button {
                editor.toggleStrikethrough()
            } label: {
                Image(systemName: "strikethrough")
            }
            .help("Strikethrough")

            Button {
                setEditingMode(
                    (document.metadata.trackChangesEnabled ?? false)
                        ? .editing
                        : .suggesting
                )
            } label: {
                Image(
                    systemName:
                        (document.metadata.trackChangesEnabled ?? false)
                            ? "pencil.and.outline"
                            : "pencil"
                )
            }
            .help(
                (document.metadata.trackChangesEnabled ?? false)
                    ? "Track Changes is on"
                    : "Turn on Track Changes"
            )

            ColorPicker(
                "Text Color",
                selection: Binding(
                    get: { Color(nsColor: editor.textColor) },
                    set: { editor.setTextColor(NSColor($0)) }
                )
            )
            .labelsHidden()
            .frame(width: 28)
            .help("Text color")

            Menu {
                Button("Highlight Yellow") {
                    editor.setHighlight(.systemYellow.withAlphaComponent(0.45))
                }

                Button("Remove Highlight") {
                    editor.setHighlight(.clear)
                }
            } label: {
                Image(systemName: "highlighter")
            }
            .help("Highlight")

            Button {
                editor.toggleBulletList()
            } label: {
                Image(systemName: "list.bullet")
            }
            .help("Bulleted list")

            Button {
                editor.toggleNumberedList()
            } label: {
                Image(systemName: "list.number")
            }
            .help("Numbered list")

            Menu {
                Button("Left") {
                    editor.setAlignment(.left)
                }

                Button("Center") {
                    editor.setAlignment(.center)
                }

                Button("Right") {
                    editor.setAlignment(.right)
                }

                Button("Justified") {
                    editor.setAlignment(.justified)
                }
            } label: {
                Image(systemName: "text.alignleft")
            }
            .help("Paragraph alignment")

            Button {
                editor.decreaseIndent()
            } label: {
                Image(systemName: "decrease.indent")
            }
            .help("Decrease indent")

            Button {
                editor.increaseIndent()
            } label: {
                Image(systemName: "increase.indent")
            }
            .help("Increase indent")

            Button {
                showParagraphFormatting.toggle()
            } label: {
                Image(systemName: "paragraph")
            }
            .help("Paragraph formatting")
            .popover(
                isPresented: $showParagraphFormatting,
                arrowEdge: .bottom
            ) {
                ParagraphFormattingPopover(editor: editor)
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Button("Read Selection") { reader.readSelection(in: editor) }
                Button("Read Current Paragraph") { reader.readParagraph(in: editor) }
                Button("Read Current Section") { reader.readSection(in: editor) }
                Button("Read From Cursor") { reader.readFromCursor(in: editor) }
                Button("Read Entire Document") { reader.readDocument(in: editor) }
                Divider()
                Button("Open Audiobook Studio…") { openAudiobookStudio() }
            } label: { Label("Read Aloud", systemImage: "speaker.wave.2") }
            Button { showRightSidebar = true } label: { Label("AI", systemImage: "sparkles") }
            Button { showExport = true } label: { Label("Export", systemImage: "square.and.arrow.up") }
        }
    }

    private func setEditingMode(
        _ mode: DocumentEditingMode
    ) {
        editingMode =
            mode

        switch mode {
        case .editing:
            document.metadata
                .trackChangesEnabled =
                false

        case .suggesting:
            document.metadata
                .trackChangesEnabled =
                true

        case .viewing:
            break
        }
    }

    private func openAudiobookStudio() {
        AudiobookStudioWindowController.show(
            document: document,
            editor: editor,
            reader: reader,
            sourceURL: sourceURL
        )
    }

    private func presentManuscriptImport() {
        let panel = NSOpenPanel()
        panel.title = "Import Manuscript into This Project"
        panel.allowedContentTypes = [.docx]
        panel.message = "Replace this project's manuscript and keep its cover and 3D setup. You can undo the import."
        panel.begin { response in
            if response == .OK, let url = panel.url { importManuscript(url) }
        }
    }

    private func importManuscript(_ url: URL) {
        guard manuscriptImportID == nil else { return }
        let token = UUID(), revision = document.revisionID
        manuscriptImportID = token
        importingManuscriptName = url.lastPathComponent
        Task {
            do {
                let imported = try await Task.detached(priority: .userInitiated) {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    let loaded = try BOLDWriterDocument(fileWrapper: FileWrapper(url: url), contentType: .docx)
                    return ImportedManuscriptTransfer(snapshot: WriterDocumentSnapshot(text: loaded.text, metadata: loaded.metadata))
                }.value
                guard manuscriptImportID == token else { return }
                manuscriptImportID = nil
                guard document.revisionID == revision else {
                    document.lastErrorMessage = "The manuscript changed while importing. Import again when you are ready to replace it."
                    return
                }
                document.importManuscript(imported.snapshot, undoManager: editor.textView?.undoManager)
            } catch {
                guard manuscriptImportID == token else { return }
                manuscriptImportID = nil
                document.lastErrorMessage = error.localizedDescription
            }
        }
    }

    private var actions: DocumentActions {
        DocumentActions(
            canEdit: editingMode.isEditable,
            importManuscript: presentManuscriptImport,
            undo: {
                editor.textView?
                    .undoManager?
                    .undo()
            },
            redo: {
                editor.textView?
                    .undoManager?
                    .redo()
            },
            toggleLeft: { showLeftSidebar.toggle() },
            showFindReplace: {
                leftSidebarTab = .search
                showLeftSidebar = true
                focusMode = false
                searchFocusRequest = UUID()
            },
            toggleRight: { showRightSidebar.toggle() },
            toggleFocus: { focusMode.toggle() },
            toggleFullScreen: toggleFullScreen,
            togglePrintLayout: { printLayout.toggle() },
            setEditingMode: setEditingMode,
            toggleNonPrintingCharacters: {
                showNonPrintingCharacters.toggle()
            },
            toggleLineNumbers: {
                showLineNumbers.toggle()
            },
            toggleRuler: { showEditorRuler.toggle() },
            compareDocuments: compareDocuments,
            translateDocument: {
                showTranslateDocument = true
            },
            lookUpDictionary: {
                if !editor.lookUpInDictionary() {
                    document.lastErrorMessage =
                        "Select a word, or place the insertion point inside a word, before using Dictionary."
                }
            },
            voiceTyping: beginVoiceTyping,
            checkSpelling: checkSpelling,
            showSpellingAndGrammar: showSpellingAndGrammar,
            toggleContinuousSpelling: toggleContinuousSpelling,
            toggleGrammarChecking: toggleGrammarChecking,
            showCitations: {
                showCitations = true
            },
            insertBibliography: insertBibliography,
            showExport: { showExport = true },
            showKindle: { showKindle = true },
            showPhysicalBookPreview: { selectWorkspace(.bookStudio3D) },
            showEquationToolbar: {
                showEquationToolbar = true
            },
            showPalette: { showPalette = true },
            showWordCount: {
                showWordCount = true
            },
            showHelp: { showHelp = true },
            saveVersion: { document.createRevision(named: "Manual Save Point") },
            insertPageBreak: { editor.insertPageBreak() },
            insertTable: { editor.showInsertTable() },
            insertImage: chooseImage,
            insertLink: applyLink,
            toggleBold: { if editingMode.isEditable { editor.toggleTrait(.boldFontMask) } },
            toggleItalic: { if editingMode.isEditable { editor.toggleTrait(.italicFontMask) } },
            toggleUnderline: { if editingMode.isEditable { editor.toggleUnderline() } },
            toggleBulletedList: { if editingMode.isEditable { editor.toggleBulletList() } },
            toggleNumberedList: { if editingMode.isEditable { editor.toggleNumberedList() } },
            toggleChecklist: { if editingMode.isEditable { editor.toggleChecklist() } },
            toggleChecklistItem: { if editingMode.isEditable { editor.toggleChecklistItem() } },
            increaseIndent: { if editingMode.isEditable { editor.increaseIndent() } },
            decreaseIndent: { if editingMode.isEditable { editor.decreaseIndent() } },
            clearFormatting: { if editingMode.isEditable { editor.clearDirectFormatting() } },
            setTextDirection: { direction in if editingMode.isEditable { editor.setTextDirection(direction) } },
            applyParagraphStyle: { style in if editingMode.isEditable { editor.applyStyle(style) } },
            insertRule: { editor.insertHorizontalRule() },
            insertTOC: insertTableOfContents,
            insertFootnote: {
                editor.insertFootnote(
                    trackChanges:
                        document.metadata
                            .trackChangesEnabled
                            ?? false
                )
            },
            editFootnote: { editor.editSelectedFootnote() },
            insertEndnote: {
                editor.insertEndnote(
                    trackChanges:
                        document.metadata
                            .trackChangesEnabled
                            ?? false
                )
            },
            editEndnote: { editor.editSelectedEndnote() },
            addBookmark: { document.metadata.bookmarks.append(DocumentBookmark(name: "Bookmark \(document.metadata.bookmarks.count + 1)", location: editor.selection.location)) },
            readFromCursor: { reader.readFromCursor(in: editor) },
            stopReading: { reader.stop() },
            printDocument: printDocument,
            previousChange: {
                editor.previousTrackedChange()
            },
            nextChange: {
                editor.nextTrackedChange()
            },
            acceptChange: {
                editor.acceptTrackedChangeAtSelection()
            },
            rejectChange: {
                editor.rejectTrackedChangeAtSelection()
            },
            acceptAllChanges: {
                editor.acceptAllTrackedChanges()
            },
            rejectAllChanges: {
                editor.rejectAllTrackedChanges()
            },
            newComment: addComment,
            editComment: editSelectedComment,
            deleteComment: deleteSelectedComment,
            previousComment: { editor.navigateComment(previous: true, in: document) },
            nextComment: { editor.navigateComment(previous: false, in: document) },
            showComments: toggleComments,
            tableAction: { editor.tableCommand($0) }
        )
    }

    private func toggleFullScreen() {
        guard
            let window =
                editor.textView?.window
                ?? NSApp.keyWindow
        else {
            document.lastErrorMessage =
                "The document window is not ready."
            return
        }

        window.toggleFullScreen(
            nil
        )
    }

    private func performNativeTextCommand(
        _ selector: Selector
    ) {
        guard
            let textView =
                editor.textView
        else {
            document.lastErrorMessage =
                "The document editor is not ready."
            return
        }

        textView.window?
            .makeFirstResponder(
                textView
            )

        if !NSApp.sendAction(
            selector,
            to:
                textView,
            from:
                nil
        ) {
            document.lastErrorMessage =
                "The requested spelling or grammar command is unavailable."
        }
    }

    private func checkSpelling() {
        performNativeTextCommand(
            #selector(
                NSTextView.checkSpelling(_:)
            )
        )
    }

    private func showSpellingAndGrammar() {
        performNativeTextCommand(
            #selector(
                NSTextView.showGuessPanel(_:)
            )
        )
    }

    private func toggleContinuousSpelling() {
        performNativeTextCommand(
            #selector(
                NSTextView.toggleContinuousSpellChecking(_:)
            )
        )
    }

    private func toggleGrammarChecking() {
        performNativeTextCommand(
            #selector(
                NSTextView.toggleGrammarChecking(_:)
            )
        )
    }

    @discardableResult
    private func saveCitationLibrary(
        sources: [CitationSource],
        style: CitationStyle
    ) -> Bool {
        do {
            var normalized =
                DocumentCitations.normalized(
                    sources
                )

            let previousByID = Dictionary(
                (document.metadata.citationSources ?? []).map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            let previousStyle = document.metadata.citationStyle ?? style
            for index in normalized.indices {
                guard let previous = previousByID[normalized[index].id] else { continue }
                var history = normalized[index].citationDisplayHistory ?? previous.citationDisplayHistory ?? [:]
                let priorDisplayed = CitationFormatter.citation(for: previous, style: previousStyle)
                let newlyDisplayed = CitationFormatter.citation(for: normalized[index], style: style)
                if priorDisplayed != newlyDisplayed, !priorDisplayed.isEmpty { history[style] = priorDisplayed }
                for citationStyle in CitationStyle.allCases {
                    let oldDisplay = CitationFormatter.citation(for: previous, style: citationStyle)
                    let newDisplay = CitationFormatter.citation(for: normalized[index], style: citationStyle)
                    if oldDisplay != newDisplay, !oldDisplay.isEmpty { history[citationStyle] = oldDisplay }
                }
                normalized[index].citationDisplayHistory = history.isEmpty ? nil : history
            }

            let linkedSourceIDs = Set(
                (document.metadata.claimEvidence ?? []).map(\.sourceID)
            )
            let citedSourceIDs = DocumentCitations.citedSourceResolution(
                in: document.text.string,
                sources: document.metadata.citationSources ?? [],
                style: document.metadata.citationStyle ?? style
            ).citedSourceIDs
            let remainingSourceIDs = Set(normalized.map(\.id))
            guard linkedSourceIDs.union(citedSourceIDs).isSubset(of: remainingSourceIDs) else {
                throw WriterError.message(
                    "Remove this source's evidence associations and in-text citations before deleting its citation source."
                )
            }

            try DocumentCitations.validate(
                normalized
            )

            document.metadata.citationSources =
                normalized

            document.metadata.citationStyle =
                style
            return true
        } catch {
            document.lastErrorMessage =
                error.localizedDescription
            return false
        }
    }

    private func insertCitation(
        _ source: CitationSource,
        style: CitationStyle
    ) {
        guard editingMode != .viewing else {
            document.lastErrorMessage =
                "Citations cannot be inserted while the document is in Viewing mode."
            return
        }

        guard let textView = editor.textView else {
            document.lastErrorMessage =
                "The document editor is not ready."
            return
        }

        let selectedRange = textView.selectedRange()
        guard let range = CitationFormatter.insertionRangeAfterSelection(
            in: textView.string,
            selection: selectedRange
        ) else {
            document.lastErrorMessage = "The selected manuscript location is no longer available."
            return
        }

        let insertion =
            CitationFormatter.contextualInlineInsertion(
                source:
                    source,
                style:
                    style,
                documentText:
                    textView.string,
                range:
                    range
            )

        let replacement =
            NSAttributedString(
                string:
                    insertion,
                attributes:
                    textView.typingAttributes
            )

        editor.replace(
            range:
                range,
            with:
                replacement,
            actionName:
                "Insert Citation",
            trackChanges:
                document.metadata
                    .trackChangesEnabled
                    ?? false
        )

        document.replaceEditedText(
            with:
                textView.attributedString()
        )
        if selectedRange.location <= (textView.string as NSString).length {
            textView.setSelectedRange(selectedRange)
        }
    }

    private func insertCitationAfterEvidenceClaim(
        _ source: CitationSource,
        style: CitationStyle,
        selection: NSRange
    ) {
        guard editingMode != .viewing else {
            document.lastErrorMessage =
                "Citations cannot be inserted while the document is in Viewing mode."
            return
        }

        guard let textView = editor.textView else {
            document.lastErrorMessage =
                "The document editor is not ready."
            return
        }

        guard let insertionPoint = CitationFormatter.insertionRangeAfterSelection(
            in: textView.string,
            selection: selection
        ) else {
            document.lastErrorMessage =
                "The selected claim is no longer available. Reselect it before inserting a citation."
            return
        }

        let insertion = CitationFormatter.contextualInlineInsertion(
            source: source,
            style: style,
            documentText: textView.string,
            range: insertionPoint
        )
        let replacement = NSAttributedString(
            string: insertion,
            attributes: textView.typingAttributes
        )

        editor.replace(
            range: insertionPoint,
            with: replacement,
            actionName: "Insert Citation",
            trackChanges: document.metadata.trackChangesEnabled ?? false
        )
        document.replaceEditedText(with: textView.attributedString())
        textView.setSelectedRange(selection)
    }

    private func insertBibliography() {
        let sources =
            document.metadata
                .citationSources
                ?? []

        guard !sources.isEmpty else {
            showCitations = true
            return
        }

        insertBibliography(
            sources:
                sources,
            style:
                document.metadata
                    .citationStyle
                    ?? .apa
        )
    }

    private func insertBibliography(
        sources: [CitationSource],
        style: CitationStyle
    ) {
        guard editingMode != .viewing else {
            document.lastErrorMessage =
                "A bibliography cannot be inserted while the document is in Viewing mode."
            return
        }

        guard let textView = editor.textView else {
            document.lastErrorMessage =
                "The document editor is not ready."
            return
        }

        let normalized = DocumentCitations.normalized(sources)

        let citationResolution = DocumentCitations.citedSourceResolution(
            in: textView.string,
            sources: normalized,
            style: style
        )
        let citedSources = normalized.filter { citationResolution.citedSourceIDs.contains($0.id) }

        guard !citedSources.isEmpty else {
            document.lastErrorMessage = citationResolution.ambiguousDisplays.isEmpty
                ? "No unambiguous in-text citations were found for these sources. The bibliography was not inserted."
                : "Some in-text citation displays match multiple source records. Resolve the ambiguous sources before inserting a bibliography."
            return
        }

        guard !normalized.isEmpty else {
            document.lastErrorMessage =
                "Add at least one citation source before inserting a bibliography."
            return
        }

        do {
            try DocumentCitations.validate(
                normalized
            )
        } catch {
            document.lastErrorMessage =
                error.localizedDescription
            return
        }

        let selectedRange = textView.selectedRange()
        guard let range = CitationFormatter.insertionRangeAfterSelection(
            in: textView.string,
            selection: selectedRange
        ) else {
            document.lastErrorMessage = "The selected manuscript location is no longer available."
            return
        }

        let bibliography =
            CitationFormatter.bibliography(
                sources:
                    citedSources,
                style:
                    style
            )

        let insertion =
            CitationFormatter.contextualBlockInsertion(
                bibliography,
                documentText:
                    textView.string,
                range:
                    range
            )

        let replacement =
            NSAttributedString(
                string:
                    insertion,
                attributes:
                    textView.typingAttributes
            )

        editor.replace(
            range:
                range,
            with:
                replacement,
            actionName:
                "Insert Bibliography",
            trackChanges:
                document.metadata
                    .trackChangesEnabled
                    ?? false
        )

        document.replaceEditedText(
            with:
                textView.attributedString()
        )
        if selectedRange.location <= (textView.string as NSString).length {
            textView.setSelectedRange(selectedRange)
        }
    }

    private func updateCitationDisplays(within range: NSRange) -> Int {
        guard editingMode.isEditable, let textView = editor.textView else {
            document.lastErrorMessage = "Citation text cannot be updated while the document is in Viewing mode."
            return 0
        }
        let sources = document.metadata.citationSources ?? []
        let style = document.metadata.citationStyle ?? .apa
        let replacements = DocumentCitations.outdatedCitationReplacements(
            in: textView.string,
            sources: sources,
            style: style,
            within: range
        )
        guard !replacements.isEmpty else { return 0 }
        let selection = textView.selectedRange()
        let selectionDelta = replacements.reduce(0) { total, item in
            NSMaxRange(item.range) <= selection.location
                ? total + (item.replacement as NSString).length - item.range.length
                : total
        }
        textView.undoManager?.beginUndoGrouping()
        for item in replacements {
            let attrs: [NSAttributedString.Key: Any] = item.range.location < (textView.textStorage?.length ?? 0)
                ? (textView.textStorage?.attributes(at: item.range.location, effectiveRange: nil) ?? textView.typingAttributes)
                : textView.typingAttributes
            editor.replace(
                range: item.range,
                with: NSAttributedString(string: item.replacement, attributes: attrs),
                actionName: "Update Citation Display",
                trackChanges: document.metadata.trackChangesEnabled ?? false
            )
        }
        textView.undoManager?.endUndoGrouping()
        document.replaceEditedText(with: textView.attributedString())
        let adjusted = NSRange(location: max(0, selection.location + selectionDelta), length: selection.length)
        if adjusted.location <= (textView.string as NSString).length,
           adjusted.length <= (textView.string as NSString).length - adjusted.location { textView.setSelectedRange(adjusted) }
        return replacements.count
    }

    private func beginVoiceTyping() {
        guard
            editingMode != .viewing
        else {
            document.lastErrorMessage =
                "Voice Typing is unavailable while the document is in Viewing mode."
            return
        }

        guard
            let view =
                editor.textView
        else {
            document.lastErrorMessage =
                "The document editor is not ready."
            return
        }

        voiceTypingRange =
            view.selectedRange()

        voiceTypingAttributes =
            view.typingAttributes

        voiceTypingSourceText =
            view.string

        showVoiceTyping =
            true
    }

    private func insertVoiceTypingTranscript(
        _ transcript: String
    ) {
        guard
            let view =
                editor.textView
        else {
            document.lastErrorMessage =
                "The document editor is not ready."
            return
        }

        guard
            view.string == voiceTypingSourceText
        else {
            document.lastErrorMessage =
                "The document changed while Voice Typing was open, so the transcript was not inserted."
            return
        }

        let length =
            view.attributedString()
                .length

        guard
            voiceTypingRange.location != NSNotFound,
            voiceTypingRange.location <= length,
            voiceTypingRange.length <= length - voiceTypingRange.location
        else {
            document.lastErrorMessage =
                "The original Voice Typing insertion point is no longer valid."
            return
        }

        let replacement =
            VoiceTypingText.attributedReplacement(
                transcript:
                    transcript,
                documentText:
                    view.string,
                replacementRange:
                    voiceTypingRange,
                typingAttributes:
                    voiceTypingAttributes
            )

        guard replacement.length > 0 else {
            return
        }

        editor.replace(
            range:
                voiceTypingRange,
            with:
                replacement,
            actionName:
                "Voice Typing",
            trackChanges:
                document.metadata
                    .trackChangesEnabled
                    ?? false
        )

        document.replaceEditedText(
            with:
                view.attributedString()
        )

        editor.navigate(
            to:
                NSRange(
                    location:
                        voiceTypingRange.location
                        + replacement.length,
                    length:
                        0
                )
        )
    }

    private func applyTranslation(
        _ replacement: NSAttributedString,
        languageName: String
    ) {
        guard
            let view =
                editor.textView
        else {
            document.lastErrorMessage =
                "The document editor is not ready."

            return
        }

        guard
            document.createRevision(
                named:
                    "Before Translation to \(languageName)"
            )
        else {
            document.lastErrorMessage =
                "The safety recovery point could not be created, so the translation was not applied."

            return
        }

        editor.replace(
            range:
                NSRange(
                    location:
                        0,
                    length:
                        view.attributedString()
                            .length
                ),
            with:
                replacement,
            actionName:
                "Translate Document",
            trackChanges:
                document.metadata
                    .trackChangesEnabled
                    ?? false
        )

        document.replaceEditedText(
            with:
                view.attributedString()
        )
    }

    private func handleDroppedFiles(
        _ providers: [NSItemProvider]
    ) -> Bool {
        LocalFileDrop.load(providers) { results in
            var failures: [String] = []
            for result in results {
                switch result {
                case .success(let url): openDroppedFile(url)
                case .failure(let error): failures.append(error.localizedDescription)
                }
            }
            if !failures.isEmpty {
                document.lastErrorMessage = "Could not load dropped files:\n" + failures.joined(separator: "\n")
            }
        }
    }

    private func openDroppedFile(
        _ url: URL
    ) {
        let contentType =
            BOLDWriterDocument
            .inferredContentType(
                for:
                    url
            )

        guard
            BOLDWriterDocument
            .supportsOpening(
                contentType
            )
        else {
            let alert =
                NSAlert()

            alert.alertStyle =
                .warning

            alert.messageText =
                "BOLD Writer cannot open this file type yet."

            alert.informativeText =
                url.lastPathComponent

            alert.addButton(
                withTitle:
                    "OK"
            )

            alert.runModal()

            return
        }

        let configuration =
            NSWorkspace
            .OpenConfiguration()

        configuration.activates =
            true

        NSWorkspace.shared.open(
            [
                url
            ],
            withApplicationAt:
                Bundle.main
                .bundleURL,
            configuration:
                configuration
        ) {
            _,
            error in

            guard
                let error
            else {
                return
            }

            DispatchQueue.main.async {
                let alert =
                    NSAlert()

                alert.alertStyle =
                    .warning

                alert.messageText =
                    "BOLD Writer could not open the dropped file."

                alert.informativeText =
                    error.localizedDescription

                alert.addButton(
                    withTitle:
                        "OK"
                )

                alert.runModal()
            }
        }
    }

    private func chooseImage() {
        guard editingMode.isEditable else { return }
        let panel = NSOpenPanel()
        panel.title = "Insert Image"
        panel.prompt = "Insert"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let page = document.metadata.page
            let bodyWidth = page.pageSize.width - page.leftMargin - page.rightMargin
            try editor.insertImage(data: data, name: url.lastPathComponent, maximumWidth: bodyWidth)
        } catch {
            document.lastErrorMessage = error.localizedDescription
        }
    }

    private func compareDocuments() {
        let panel =
            NSOpenPanel()

        panel.title =
            "Compare Documents"

        panel.message =
            "Choose the revised document to compare with the document currently open."

        panel.prompt =
            "Compare"

        panel.canChooseFiles =
            true

        panel.canChooseDirectories =
            false

        panel.allowsMultipleSelection =
            false

        panel.treatsFilePackagesAsDirectories =
            false

        panel.allowedContentTypes =
            BOLDWriterDocument
                .readableContentTypes
                .filter {
                    !$0.conforms(
                        to:
                            .pdf
                    )
                }

        guard
            panel.runModal()
                == .OK,
            let url =
                panel.url
        else {
            return
        }

        do {
            let wrapper =
                try FileWrapper(
                    url:
                        url
                )

            let resourceType =
                try? url.resourceValues(
                    forKeys:
                        [
                            .contentTypeKey
                        ]
                )
                .contentType

            let contentType =
                resourceType
                ?? UTType(
                    filenameExtension:
                        url.pathExtension
                )
                ?? (
                    wrapper.isDirectory
                        ? .boldWriterDocument
                        : .plainText
                )

            guard
                !contentType.conforms(
                    to:
                        .pdf
                )
            else {
                throw WriterError.message(
                    "Compare Documents does not compare PDF files. Choose an editable document."
                )
            }

            let comparison =
                try BOLDWriterDocument(
                    fileWrapper:
                        wrapper,
                    contentType:
                        contentType
                )

            let author =
                url.deletingPathExtension()
                    .lastPathComponent

            let changeCount =
                try editor.compareDocument(
                    with:
                        comparison.text,
                    in:
                        document,
                    author:
                        author.isEmpty
                            ? "Document Comparison"
                            : author
                )

            guard
                changeCount > 0
            else {
                document.lastErrorMessage =
                    "No text differences were found."

                return
            }

            document.metadata
                .trackChangesEnabled =
                true

            editingMode =
                .suggesting
        } catch {
            document.lastErrorMessage =
                "Could not compare documents: \(error.localizedDescription)"
        }
    }

    private func toggleComments() {
        if showLeftSidebar && leftSidebarTab == .comments {
            showLeftSidebar = false
        } else {
            leftSidebarTab = .comments
            showLeftSidebar = true
        }
    }

    private var selectedComment: DocumentComment? {
        if let id = editor.selectedCommentID,
           let comment = document.metadata.comments.first(where: { $0.id == id }) { return comment }
        return document.metadata.comments.first {
            let range = NSRange(location: $0.location, length: $0.length)
            return editor.selection.length > 0
                ? NSIntersectionRange(range, editor.selection).length > 0
                : editor.selection.location >= range.location && editor.selection.location <= NSMaxRange(range)
        }
    }

    private func addComment() {
        guard let text = CommentPrompt.show(title: "New Comment", confirmTitle: "Add Comment") else { return }
        do { _ = try editor.addComment(text: text, to: document) }
        catch { document.lastErrorMessage = error.localizedDescription }
    }

    private func applyLink() {
        guard let destination = CommentPrompt.show(title: "Link", initialText: "https://", confirmTitle: "Apply Link") else { return }
        do { try editor.applyHyperlink(destination, in: document) }
        catch { document.lastErrorMessage = error.localizedDescription }
    }

    private func addBookmark() {
        let suggested = "Bookmark\(document.metadata.bookmarks.count + 1)"
        guard let name = CommentPrompt.show(title: "Add Bookmark", initialText: suggested, confirmTitle: "Add") else { return }
        do { _ = try editor.addBookmark(name: name, to: document) }
        catch { document.lastErrorMessage = error.localizedDescription }
    }

    private func insertCrossReference() {
        _ = editor.ensureHeadingBookmarks(in: document)
        guard !document.metadata.bookmarks.isEmpty else {
            document.lastErrorMessage = "Add a bookmark before inserting a cross-reference."
            return
        }
        let names = document.metadata.bookmarks.map { bookmark in
            if bookmark.name.hasPrefix("BOLDCap_") { return "\(bookmark.name) (caption @ \(bookmark.location))" }
            if bookmark.name.hasPrefix("BOLDH_") { return "\(bookmark.name) (heading @ \(bookmark.location))" }
            return bookmark.name
        }.joined(separator: ", ")
        guard let name = CommentPrompt.show(title: "Cross-reference", initialText: names, confirmTitle: "Insert") else { return }
        let targetName = name.split(separator: " ").first.map(String.init) ?? name
        guard let bookmark = document.metadata.bookmarks.first(where: { $0.name.caseInsensitiveCompare(targetName) == .orderedSame }) else {
            document.lastErrorMessage = "Enter one of these bookmark names: \(names)"
            return
        }
        let kind = CommentPrompt.show(title: "Reference Form", initialText: "text", confirmTitle: "Insert")?.lowercased()
        editor.insertCrossReference(to: bookmark, pageNumber: kind == "page")
    }

    private func insertCaption() {
        guard let label = CommentPrompt.show(title: "Caption Label", initialText: "Figure", confirmTitle: "Next") else { return }
        guard let title = CommentPrompt.show(title: "Caption Text", initialText: "", confirmTitle: "Insert Caption") else { return }
        do { try editor.insertCaption(label: label, title: title) }
        catch { document.lastErrorMessage = error.localizedDescription }
    }

    private func editSelectedComment() {
        guard let comment = selectedComment else { return }
        if let text = CommentPrompt.show(title: "Edit Comment", initialText: comment.text, confirmTitle: "Save") {
            do { try editor.editComment(id: comment.id, text: text, in: document) }
            catch { document.lastErrorMessage = error.localizedDescription }
        }
    }

    private func deleteSelectedComment() {
        guard let comment = selectedComment else { return }
        editor.deleteComment(id: comment.id, in: document)
    }

    private func insertTableOfContents() { publishingTOCMode = .printBook; showPublishingTOC = true }

    private func runBookHealthCheck() {
        guard !isRunningBookHealthCheck else { return }
        let text = document.text.copy() as! NSAttributedString
        let page = document.metadata.page
        let sections = document.metadata.sections ?? []
        let floatingImages = document.metadata.floatingImages ?? []
        let projects = document.metadata.coverProjects ?? []
        let bookmarks = document.metadata.bookmarks
        let tocSettings = document.metadata.publishingTOCs ?? []
        bookHealthReport = nil
        isRunningBookHealthCheck = true
        showBookHealthCheck = true
        DispatchQueue.global(qos: .userInitiated).async {
            let report: BookHealthReport
            do {
                let production = try BookHealthReport.productionPDF(
                    from: text,
                    settings: page,
                    sections: sections,
                    floatingImages: floatingImages
                )
                report = BookHealthReport.evaluate(
                    pdfData: production.data,
                    pageSettings: production.pageSettings,
                    coverProjects: projects,
                    documentText: text,
                    pageRanges: production.pageRanges,
                    bookmarks: bookmarks,
                    tocSettings: tocSettings
                )
            } catch {
                report = BookHealthReport.exportFailure(error.localizedDescription)
            }
            DispatchQueue.main.async {
                bookHealthReport = report
                isRunningBookHealthCheck = false
            }
        }
    }

    private func printDocument() {
        do {
            _ = editor.updateAllFields(in:document)
            let data =
                try PDFExporter.data(
                    from:
                        document.text,
                    settings:
                        document.metadata.page,
                    sections:
                        document.metadata.sections,
                    floatingImages:
                        document.metadata.floatingImages ?? []
                )
            guard let pdf = PDFDocument(data: data) else { throw CocoaError(.fileReadCorruptFile) }
            let info = NSPrintInfo(dictionary: [:])
            info.paperSize = document.metadata.page.pageSize
            pdf.printOperation(for: info, scalingMode: .pageScaleDownToFit, autoRotate: true)?.run()
        } catch { document.lastErrorMessage = "Could not print: \(error.localizedDescription)" }
    }
}

private struct ParagraphFormattingPopover: View {
    @ObservedObject var editor: EditorController

    private var firstLineBinding: Binding<Double> {
        Binding(
            get: { editor.firstLineIndentInches },
            set: { editor.setFirstLineIndentInches($0) }
        )
    }

    private var hangingBinding: Binding<Double> {
        Binding(
            get: { editor.hangingIndentInches },
            set: { editor.setHangingIndentInches($0) }
        )
    }

    private var beforeBinding: Binding<Double> {
        Binding(
            get: { editor.paragraphSpacingBefore },
            set: { editor.setParagraphSpacingBefore($0) }
        )
    }

    private var afterBinding: Binding<Double> {
        Binding(
            get: { editor.paragraphSpacingAfter },
            set: { editor.setParagraphSpacing(CGFloat($0)) }
        )
    }

    private var exactBinding: Binding<Double> {
        Binding(
            get: {
                editor.exactLineSpacing > 0
                    ? editor.exactLineSpacing
                    : 12
            },
            set: {
                editor.setExactLineSpacing($0)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Paragraph")
                .font(.headline)

            GroupBox("Indentation") {
                VStack(spacing: 10) {
                    valueRow(
                        "First line",
                        value: firstLineBinding,
                        range: 0...3,
                        step: 0.125,
                        suffix: "in"
                    )

                    valueRow(
                        "Hanging",
                        value: hangingBinding,
                        range: 0...3,
                        step: 0.125,
                        suffix: "in"
                    )

                    HStack {
                        Spacer()

                        Button("Clear Special Indent") {
                            editor.clearSpecialIndent()
                        }
                    }
                }
                .padding(6)
            }

            GroupBox("Spacing") {
                VStack(spacing: 10) {
                    valueRow(
                        "Before",
                        value: beforeBinding,
                        range: 0...144,
                        step: 1,
                        suffix: "pt"
                    )

                    valueRow(
                        "After",
                        value: afterBinding,
                        range: 0...144,
                        step: 1,
                        suffix: "pt"
                    )
                }
                .padding(6)
            }

            GroupBox("Line Spacing") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Button("1.0") {
                            editor.setLineHeightMultiple(1.0)
                        }

                        Button("1.15") {
                            editor.setLineHeightMultiple(1.15)
                        }

                        Button("1.5") {
                            editor.setLineHeightMultiple(1.5)
                        }

                        Button("2.0") {
                            editor.setLineHeightMultiple(2.0)
                        }
                    }

                    valueRow(
                        "Exact",
                        value: exactBinding,
                        range: 6...144,
                        step: 1,
                        suffix: "pt"
                    )

                    if editor.exactLineSpacing > 0 {
                        Text(
                            "Exact "
                            + editor.exactLineSpacing.formatted(
                                .number.precision(.fractionLength(1))
                            )
                            + " pt is active."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } else {
                        Text(
                            "Multiple spacing "
                            + editor.lineHeightMultiple.formatted(
                                .number.precision(.fractionLength(2))
                            )
                            + "× is active."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(6)
            }
        }
        .padding(16)
        .frame(width: 330)
    }

    @ViewBuilder
    private func valueRow(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        suffix: String
    ) -> some View {
        HStack {
            Text(title)
                .frame(width: 70, alignment: .leading)

            Spacer()

            TextField(
                title,
                value: value,
                format: .number.precision(.fractionLength(3))
            )
            .labelsHidden()
            .multilineTextAlignment(.trailing)
            .frame(width: 62)

            Text(suffix)
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .leading)

            Stepper(
                "",
                value: value,
                in: range,
                step: step
            )
            .labelsHidden()
        }
    }
}

struct DocumentActions {
    var canEdit: Bool = true
    var importManuscript: () -> Void = {}
    var undo: () -> Void
    var redo: () -> Void
    var toggleLeft: () -> Void
    var showFindReplace: () -> Void
    var toggleRight: () -> Void
    var toggleFocus: () -> Void
    var toggleFullScreen: () -> Void = {}
    var togglePrintLayout: () -> Void
    var setEditingMode: (DocumentEditingMode) -> Void = { _ in }
    var toggleNonPrintingCharacters: () -> Void = {}
    var toggleLineNumbers: () -> Void = {}
    var toggleRuler: () -> Void = {}
    var compareDocuments: () -> Void = {}
    var translateDocument: () -> Void = {}
    var lookUpDictionary: () -> Void = {}
    var voiceTyping: () -> Void = {}
    var checkSpelling: () -> Void = {}
    var showSpellingAndGrammar: () -> Void = {}
    var toggleContinuousSpelling: () -> Void = {}
    var toggleGrammarChecking: () -> Void = {}
    var showCitations: () -> Void = {}
    var insertBibliography: () -> Void = {}
    var showExport: () -> Void
    var showKindle: () -> Void
    var showPhysicalBookPreview: () -> Void = {}
    var showEquationToolbar: () -> Void = {}
    var showPalette: () -> Void
    var showWordCount: () -> Void = {}
    var showHelp: () -> Void
    var saveVersion: () -> Void
    var insertPageBreak: () -> Void
    var insertTable: () -> Void
    var insertImage: () -> Void = {}
    var insertLink: () -> Void = {}
    var toggleBold: () -> Void = {}
    var toggleItalic: () -> Void = {}
    var toggleUnderline: () -> Void = {}
    var toggleBulletedList: () -> Void = {}
    var toggleNumberedList: () -> Void = {}
    var toggleChecklist: () -> Void = {}
    var toggleChecklistItem: () -> Void = {}
    var increaseIndent: () -> Void = {}
    var decreaseIndent: () -> Void = {}
    var clearFormatting: () -> Void = {}
    var setTextDirection: (NSWritingDirection) -> Void = { _ in }
    var applyParagraphStyle: (WriterStyle) -> Void = { _ in }
    var insertRule: () -> Void
    var insertTOC: () -> Void
    var insertFootnote: () -> Void
    var editFootnote: () -> Void
    var insertEndnote: () -> Void
    var editEndnote: () -> Void
    var addBookmark: () -> Void
    var readFromCursor: () -> Void
    var stopReading: () -> Void
    var printDocument: () -> Void
    var previousChange: () -> Void
    var nextChange: () -> Void
    var acceptChange: () -> Void
    var rejectChange: () -> Void
    var acceptAllChanges: () -> Void
    var rejectAllChanges: () -> Void
    var newComment: () -> Void
    var editComment: () -> Void
    var deleteComment: () -> Void
    var previousComment: () -> Void
    var nextComment: () -> Void
    var showComments: () -> Void = {}
    var tableAction: (String) -> Void = { _ in }
}

private struct DocumentActionsKey: FocusedValueKey { typealias Value = DocumentActions }
extension FocusedValues {
    var documentActions: DocumentActions? {
        get { self[DocumentActionsKey.self] }
        set { self[DocumentActionsKey.self] = newValue }
    }
}

struct CommandPaletteView: View {
    var actions: DocumentActions
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    private let commands = [
        "Previous Change",
        "Next Change",
        "New Comment",
        "Edit Comment",
        "Delete Comment",
        "Previous Comment",
        "Next Comment",
        "Show Comments",
        "Accept Change",
        "Reject Change",
        "Accept All Changes",
        "Reject All Changes",
        "Export PDF",
        "Prepare for Kindle",
        "Insert Page Break",
        "Insert Table",
        "Insert Table of Contents",
        "Insert Footnote",
        "Edit Footnote",
        "Insert Endnote",
        "Edit Endnote",
        "Add Bookmark",
        "Print Layout",
        "Focus Mode",
        "Full Screen",
        "Show Equation Toolbar",
        "Show Non-Printing Characters",
        "Line Numbers",
        "Compare Documents",
        "Translate Document",
        "Dictionary",
        "Voice Typing",
        "Check Spelling",
        "Spelling & Grammar",
        "Toggle Continuous Spell Checking",
        "Toggle Grammar Checking",
        "Citations",
        "Insert Bibliography",
        "Read Aloud",
        "Word Count",
        "Save Version",
        "Help"
    ]
    var body: some View {
        VStack(spacing: 0) {
            TextField("Type a command…", text: $query).textFieldStyle(.plain).font(.title2).padding(16)
            Divider()
            List(commands.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }, id: \.self) { command in
                Button(command) { run(command); dismiss() }.buttonStyle(.plain).padding(.vertical, 5)
            }
        }.frame(width: 500, height: 420)
    }
    private func run(_ command: String) {
        switch command {
        case "Previous Change":
            actions.previousChange()
        case "Next Change":
            actions.nextChange()
        case "New Comment": actions.newComment()
        case "Edit Comment": actions.editComment()
        case "Delete Comment": actions.deleteComment()
        case "Previous Comment": actions.previousComment()
        case "Next Comment": actions.nextComment()
        case "Show Comments": actions.showComments()
        case "Accept Change":
            actions.acceptChange()
        case "Reject Change":
            actions.rejectChange()
        case "Accept All Changes":
            actions.acceptAllChanges()
        case "Reject All Changes":
            actions.rejectAllChanges()
        case "Export PDF": actions.showExport()
        case "Prepare for Kindle": actions.showKindle()
        case "Insert Page Break": actions.insertPageBreak()
        case "Insert Table": actions.insertTable()
        case "Insert Table of Contents": actions.insertTOC()
        case "Insert Footnote": actions.insertFootnote()
        case "Edit Footnote": actions.editFootnote()
        case "Insert Endnote": actions.insertEndnote()
        case "Edit Endnote": actions.editEndnote()
        case "Add Bookmark": actions.addBookmark()
        case "Print Layout": actions.togglePrintLayout()
        case "Focus Mode": actions.toggleFocus()
        case "Full Screen": actions.toggleFullScreen()
        case "Show Equation Toolbar":
            actions.showEquationToolbar()
        case "Show Non-Printing Characters":
            actions.toggleNonPrintingCharacters()
        case "Line Numbers":
            actions.toggleLineNumbers()
        case "Compare Documents":
            actions.compareDocuments()
        case "Translate Document":
            actions.translateDocument()
        case "Dictionary":
            actions.lookUpDictionary()
        case "Voice Typing":
            actions.voiceTyping()
        case "Check Spelling":
            actions.checkSpelling()
        case "Spelling & Grammar":
            actions.showSpellingAndGrammar()
        case "Toggle Continuous Spell Checking":
            actions.toggleContinuousSpelling()
        case "Toggle Grammar Checking":
            actions.toggleGrammarChecking()
        case "Citations":
            actions.showCitations()
        case "Insert Bibliography":
            actions.insertBibliography()
        case "Read Aloud": actions.readFromCursor()
        case "Word Count": actions.showWordCount()
        case "Save Version": actions.saveVersion()
        case "Help": actions.showHelp()
        default: break
        }
    }
}

private struct WordCountView: View {
    let statistics: DocumentStatistics

    @Environment(\.dismiss)
    private var dismiss

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 16
        ) {
            Text("Word Count")
                .font(.title2.bold())

            Grid(
                alignment: .leading,
                horizontalSpacing: 28,
                verticalSpacing: 10
            ) {
                GridRow {
                    Text("Words")
                    Text(
                        statistics.words.formatted()
                    )
                    .monospacedDigit()
                }

                GridRow {
                    Text("Characters")
                    Text(
                        statistics.characters.formatted()
                    )
                    .monospacedDigit()
                }

                GridRow {
                    Text("Characters excluding spaces")
                    Text(
                        statistics.charactersWithoutSpaces.formatted()
                    )
                    .monospacedDigit()
                }

                GridRow {
                    Text("Paragraphs")
                    Text(
                        statistics.paragraphs.formatted()
                    )
                    .monospacedDigit()
                }

                GridRow {
                    Text("Estimated reading time")
                    Text(
                        "\(statistics.estimatedMinutes) min"
                    )
                    .monospacedDigit()
                }

                GridRow {
                    Text("Headings")
                    Text(
                        statistics.headings.formatted()
                    )
                    .monospacedDigit()
                }
            }

            Divider()

            HStack {
                Spacer()

                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}

private struct FootnoteEditorView: View {
    let note: Footnote
    @ObservedObject var editor: EditorController
    let trackChangesEnabled: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Footnote").font(.headline)
            TextEditor(text: $draft).frame(minHeight: 160).border(Color.secondary.opacity(0.3))
                .accessibilityLabel("Footnote text")
            HStack {
                Button(
                    "Delete Footnote",
                    role: .destructive
                ) {
                    editor.deleteFootnote(
                        id: note.id,
                        trackChanges:
                            trackChangesEnabled
                    )
                    dismiss()
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    editor.updateFootnote(
                        id: note.id,
                        text: draft,
                        trackChanges:
                            trackChangesEnabled
                    )
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(width: 480).onAppear { draft = note.text }
    }
}

private struct EndnoteEditorView: View {
    let note: Endnote
    @ObservedObject var editor: EditorController
    let trackChangesEnabled: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Endnote").font(.headline)
            TextEditor(text: $draft).frame(minHeight: 160).border(Color.secondary.opacity(0.3))
                .accessibilityLabel("Endnote text")
            HStack {
                Button(
                    "Delete Endnote",
                    role: .destructive
                ) {
                    editor.deleteEndnote(
                        id: note.id,
                        trackChanges:
                            trackChangesEnabled
                    )
                    dismiss()
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    editor.updateEndnote(
                        id: note.id,
                        text: draft,
                        trackChanges:
                            trackChangesEnabled
                    )
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(width: 480).onAppear { draft = note.text }
    }
}

/// An immutable import result transferred after all decoding has finished.
private struct ImportedManuscriptTransfer: @unchecked Sendable {
    let snapshot: WriterDocumentSnapshot
}
