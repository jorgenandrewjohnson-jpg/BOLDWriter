import AppKit
import AVFoundation
import Security
import SwiftUI
import UniformTypeIdentifiers

struct AudiobookStudioView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var document: BOLDWriterDocument
    @ObservedObject var editor: EditorController
    @ObservedObject var reader: ReadAloudManager
    var sourceURL: URL?
    var onClose: (() -> Void)? = nil

    @AppStorage("speechVoice") private var savedVoice = ""
    @AppStorage("speechRate") private var savedRate = 0.48
    @AppStorage("audiobook.favoriteVoices") private var favoriteIDs: String = ""
    @AppStorage("audiobook.elevenlabsCharactersUsed") private var usedCharacters = 0
    @AppStorage("audiobook.globalPronunciations") private var globalPronunciationJSON = "[]"
    @State private var query = ""
    @State private var localeFilter = "All languages"
    @State private var previewText = "This is a short sample of your selected narration voice."
    @State private var rules: [PronunciationRule] = []
    @State private var ruleTerm = ""
    @State private var ruleSpoken = ""
    @State private var ruleLocale = ""
    @State private var ruleMatching = PronunciationRule.Matching.wholeWord
    @State private var ruleScope = PronunciationRule.Scope.project
    @State private var ruleCaseSensitive = false
    @State private var globalRules: [PronunciationRule] = []
    @State private var project: AudiobookProjectManifest?
    @State private var chapters: [AudiobookChapter] = []
    @State private var selectedChapterID: String?
    @State private var projectURL: URL?
    @State private var outputURL: URL?
    @State private var productionService: AudiobookProductionService?
    @State private var productionJobID: UUID?
    @State private var jobSnapshot: AudiobookJobSnapshot?
    @State private var jobStartedAt: Date?
    @State private var lastProductionChapterIDs: [String]?
    @State private var pendingProductionRequest: AudiobookRenderRequest?
    @State private var pendingBillableApprovals: [AudiobookBillablePreflight] = []
    @State private var qualityReport: AudiobookAudioQualityReport?
    @State private var showQualityReport = false
    @State private var showLargeShareWarning = false
    @State private var largeShareURL: URL?
    @State private var useBalancedMastering = false
    @State private var mp3Quality = AudiobookMP3Settings.Quality.balanced
    @State private var providerKey = ""
    @State private var hasProviderKey = false
    @State private var providerStatus = ""
    @State private var models: [ElevenLabsModel] = []
    @State private var voices: [ElevenLabsVoice] = []
    @State private var premiumVoiceID = ""
    @State private var modelID = ""
    @AppStorage("audiobook.elevenlabsUsageBudget") private var usageBudget = 100_000
    @State private var pendingGenerationText = ""
    @State private var pendingChapterID: String?
    @State private var showGenerationConfirmation = false
    @State private var showCancelProductionConfirmation = false
    @State private var isLoadingProvider = false
    @State private var isRendering = false
    @State private var activeTask: Task<Void, Never>?
    @State private var status = "Set up a narration project or preview a voice."
    @State private var player: AVAudioPlayer?
    @State private var queuePlayer: AVQueuePlayer?
    @State private var showAddRule = false
    @State private var showVideoExportOptions = false
    @State private var showExportWorkflow = false
    @State private var exportFormatCode = "m4a"
    @State private var exportScopeCode = "book"
    @State private var pendingChapterVoiceID = ""
    @State private var pendingPreviewVoiceID = ""
    @State private var pendingPreviewModelID = ""
    @State private var pendingPreviewAssignmentKey: String?
    @State private var previewedVoiceAssignmentKey: String?
    @State private var videoPortrait = false
    @State private var videoBackground = Color.black
    @State private var exportChapterOnly = false

    private var nativeVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter { voice in
            (query.isEmpty || voice.name.localizedCaseInsensitiveContains(query) || voice.language.localizedCaseInsensitiveContains(query)) &&
            (localeFilter == "All languages" || voice.language.localizedCaseInsensitiveContains(localeFilter))
        }.sorted { lhs, rhs in
            if isFavorite(lhs.identifier) != isFavorite(rhs.identifier) { return isFavorite(lhs.identifier) }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
    private var locales: [String] { Array(Set(AVSpeechSynthesisVoice.speechVoices().map(\.language))).sorted() }
    private var manuscript: String { editor.textView?.string ?? document.text.string }
    private var wordCount: Int { manuscript.split(whereSeparator: \.isWhitespace).count }
    private var selectedChapter: AudiobookChapter? { chapters.first { $0.id == selectedChapterID } }
    private var generationCharacterCount: Int {
        pendingProductionRequest == nil
            ? pendingGenerationText.utf16.count
            : pendingBillableApprovals.reduce(0) { $0 + $1.exactCharacterCount }
    }
    private var productionBudgetExceeded: Bool {
        pendingBillableApprovals.contains { max(usedCharacters, $0.priorAttemptedCharacters) + $0.exactCharacterCount > usageBudget }
    }
    private var priorAttemptedCharacters: Int { max(usedCharacters, pendingBillableApprovals.map(\.priorAttemptedCharacters).max() ?? 0) }
    private var completeProjectAudioFiles: [URL]? {
        let included = chapters.filter { $0.included != false }
        guard !included.isEmpty,
              included.allSatisfy({ $0.state == .complete && ($0.audioFiles?.isEmpty == false) && ($0.audioFiles ?? []).allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) }) else { return nil }
        return included.flatMap { $0.audioFiles ?? [] }
    }
    private var selectedChapterAudioFiles: [URL]? {
        guard let chapter = selectedChapter, chapter.included != false, chapter.state == .complete,
              let files = chapter.audioFiles, !files.isEmpty,
              files.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else { return nil }
        return files
    }
    private var nativeRateMinimum: Double { max(Double(AVSpeechUtteranceMinimumSpeechRate), 0.24) }
    private var nativeRateMaximum: Double { max(nativeRateMinimum, min(Double(AVSpeechUtteranceMaximumSpeechRate), 0.60)) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                manuscriptPanel.frame(minWidth: 245, idealWidth: 280, maxWidth: 320)
                Divider()
                voicePanel.frame(minWidth: 350, maxWidth: .infinity)
                Divider()
                productionPanel.frame(minWidth: 280, idealWidth: 320, maxWidth: 360)
            }
            Divider()
            playbackBar
        }
        .frame(minWidth: 1000, minHeight: 680)
        .background(Color(nsColor: .windowBackgroundColor))
        .task { loadSavedProject(); refreshCredentialState() }
        .onChange(of: savedRate) { _, value in
            reader.rate = value; project?.speed = value
            markNarrationChaptersStale(ids: Set(chapters.filter { $0.voiceIdentifier == nil }.map(\.id)), reason: "Narration speed changed.")
        }
        .onChange(of: savedVoice) { _, _ in
            markNarrationChaptersStale(ids: Set(chapters.filter { $0.voiceIdentifier == nil }.map(\.id)), reason: "Book narrator changed.")
        }
        .onChange(of: document.revisionID) { _, _ in markChangedChaptersStale() }
        .onChange(of: selectedChapterID) { _, id in
            guard let chapter = chapters.first(where: { $0.id == id }), let voice = chapter.voiceIdentifier else {
                pendingChapterVoiceID = ""
                return
            }
            let provider = chapter.narratorProviderIdentifier ?? "apple.system"
            pendingChapterVoiceID = provider == "elevenlabs" ? "elevenlabs|\(voice)|\(chapter.narratorModelIdentifier ?? modelID)" : "apple.system|\(voice)"
        }
        .sheet(isPresented: $showGenerationConfirmation) { generationConfirmation }
        .sheet(isPresented: $showAddRule) { pronunciationEditor }
        .sheet(isPresented: $showVideoExportOptions) { videoExportOptions }
        .sheet(isPresented: $showExportWorkflow) { exportWorkflow }
        .sheet(isPresented: $showQualityReport) { qualityReportSheet }
        .alert("Cancel audiobook production?", isPresented: $showCancelProductionConfirmation) {
            Button("Keep Running", role: .cancel) { }
            Button("Cancel Job", role: .destructive) { cancelProduction() }
        } message: {
            Text("The current segment will finish safely. Verified audio is preserved and can be resumed later.")
        }
        .confirmationDialog("Large audiobook export", isPresented: $showLargeShareWarning, titleVisibility: .visible) {
            Button("Open macOS Share Picker") {
                if let largeShareURL { presentSharePicker(for: largeShareURL) }
            }
            Button("Cancel", role: .cancel) { largeShareURL = nil }
        } message: {
            Text("\(largeShareURL.map(fileSize) ?? "This file") may exceed some email or message attachment limits. Consider exporting MP3 or sharing one chapter at a time. No file is sent until you choose a service in the macOS picker.")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.and.mic").font(.title2).foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Audiobook Studio").font(.title3.weight(.semibold))
                Text(document.metadata.title.isEmpty ? "Untitled manuscript" : document.metadata.title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Button("Save Project") { saveProject() }.disabled(project == nil)
            Button("Done") { if let onClose { onClose() } else { dismiss() } }
                .keyboardShortcut(.cancelAction)
        }.padding(.horizontal, 18).padding(.vertical, 12)
    }

    private var manuscriptPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MANUSCRIPT").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            Label(document.metadata.title, systemImage: "book.closed").font(.headline).lineLimit(2)
            HStack {
                Label("\(wordCount.formatted()) words", systemImage: "text.alignleft")
                Spacer(minLength: 4)
                Text("~\(max(1, wordCount / 150)) min").foregroundStyle(.secondary)
            }.font(.caption)
            HStack {
                Button("Read Selection") { reader.readSelection(in: editor) }
                Button("Read Cursor") { reader.readFromCursor(in: editor) }
            }.buttonStyle(.bordered).controlSize(.small)
            Divider()
            HStack {
                Text("Chapters").font(.headline)
                Spacer()
                Button("Prepare") { prepareProject() }.help("Create chapter-aware narration sections from manuscript headings")
            }
            if chapters.isEmpty {
                ContentUnavailableView("Prepare a project", systemImage: "text.book.closed", description: Text("Uses manuscript headings as chapters and keeps the source text unchanged."))
            } else {
                List(selection: $selectedChapterID) {
                    ForEach(chapters) { chapter in
                        HStack(spacing: 8) {
                            Image(systemName: chapter.state == .complete ? "checkmark.circle.fill" : chapter.state == .stale ? "arrow.triangle.2.circlepath" : "circle").foregroundStyle(chapter.state == .complete ? .green : .secondary)
                            Toggle("", isOn: chapterIncludedBinding(chapter)).labelsHidden().help("Include this chapter in production and complete-book exports")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(chapter.title).lineLimit(1)
                                Text("\(chapter.text.split(whereSeparator: \.isWhitespace).count) words").font(.caption2).foregroundStyle(.secondary)
                            }
                        }.tag(chapter.id)
                    }
                }.listStyle(.sidebar)
            }
            Spacer(minLength: 0)
            Text("Narration rules affect prepared speech only. Your manuscript stays unchanged.").font(.caption2).foregroundStyle(.secondary)
        }.padding(14)
    }

    private var voicePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("VOICE").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                Spacer()
                Picker("Provider", selection: Binding(get: { project?.provider ?? "Apple" }, set: { value in
                    ensureProject(); project?.provider = value
                    markNarrationChaptersStale(ids: Set(chapters.map(\.id)), reason: "Narration provider changed.")
                    if value == "ElevenLabs" { loadProviderCatalog() }
                })) {
                    Text("Mac voices").tag("Apple")
                    Text("ElevenLabs").tag("ElevenLabs")
                }.pickerStyle(.segmented).frame(width: 220)
            }
            if (project?.provider ?? "Apple") == "Apple" { nativeVoiceChooser }
            else { premiumVoiceChooser }
            Divider()
            HStack {
                Text("Pronunciation preferences").font(.headline)
                Spacer()
                Button { showAddRule = true } label: { Label("Add Rule", systemImage: "plus") }
            }
            if rules.isEmpty {
                Text("Add a written term and the spoken form you prefer. These rules are stored with this audiobook project.").font(.caption).foregroundStyle(.secondary)
            } else {
                List {
                    ForEach(rules + globalRules) { rule in
                        HStack {
                            VStack(alignment: .leading) { Text(rule.writtenTerm).fontWeight(.medium); Text("spoken as \(rule.spokenForm) · \(rule.scope.rawValue)").font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            Button(role: .destructive) { removeRule(rule) } label: { Image(systemName: "trash") }.buttonStyle(.plain)
                        }
                    }
                }.frame(minHeight: 90, maxHeight: 150)
            }
            Spacer(minLength: 0)
            Text("Mac voice quality shown below comes from macOS. Voice availability depends on voices installed in System Settings.").font(.caption2).foregroundStyle(.secondary)
        }.padding(14)
    }

    private var nativeVoiceChooser: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Search installed voices", text: $query).textFieldStyle(.roundedBorder)
                Picker("Language", selection: $localeFilter) {
                    Text("All languages").tag("All languages")
                    ForEach(locales, id: \.self) { Text($0).tag($0) }
                }.frame(width: 155)
            }
            List(selection: Binding(get: { savedVoice.isEmpty ? nil : savedVoice }, set: { newValue in
                savedVoice = newValue ?? ""; reader.selectedVoiceIdentifier = savedVoice; ensureProject(); project?.voiceIdentifier = savedVoice
            })) {
                ForEach(nativeVoices, id: \.identifier) { voice in
                    HStack(spacing: 9) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(voice.name).fontWeight(.medium)
                            Text("\(voice.language) · \(qualityName(voice.quality)) · \(genderName(voice.gender))").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { toggleFavorite(voice.identifier) } label: { Image(systemName: isFavorite(voice.identifier) ? "star.fill" : "star").foregroundStyle(isFavorite(voice.identifier) ? .yellow : .secondary) }.buttonStyle(.plain)
                        Button { playPreview(voice: voice.identifier) } label: { Image(systemName: "play.circle.fill").font(.title3) }.buttonStyle(.plain).help("Preview \(voice.name)")
                    }.tag(voice.identifier)
                }
            }.listStyle(.inset)
            if !savedVoice.isEmpty && !AVSpeechSynthesisVoice.speechVoices().contains(where: { $0.identifier == savedVoice }) {
                Label("Saved voice is not installed. Choose another voice in the list, or open System Settings → Accessibility → Spoken Content → System Voice.", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
            TextField("Short preview passage", text: $previewText).textFieldStyle(.roundedBorder)
            HStack {
            Text("Speaking speed").font(.subheadline)
                Slider(value: $savedRate, in: nativeRateMinimum...nativeRateMaximum)
                Text("\(speedLabel(savedRate))").monospacedDigit().frame(width: 40)
            }
            Text("Available range for this live system speech engine: \(speedLabel(nativeRateMinimum)) to \(speedLabel(nativeRateMaximum)).").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var premiumVoiceChooser: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SecureField("ElevenLabs API key", text: $providerKey)
                Button("Save Key") { saveProviderKey() }.disabled(providerKey.isEmpty)
                Button("Load Voices") { loadProviderCatalog() }.disabled(!hasProviderKey || isLoadingProvider)
            }
            if !hasProviderKey { Text("Key is stored in macOS Keychain. Account voice names and IDs are fetched from ElevenLabs when requested.").font(.caption).foregroundStyle(.secondary) }
            if hasProviderKey { Button("Remove ElevenLabs Key", role: .destructive) { removeProviderKey() }.font(.caption) }
            if isLoadingProvider { ProgressView("Connecting to ElevenLabs…") }
            if !voices.isEmpty {
                Picker("Voice", selection: $premiumVoiceID) {
                    ForEach(voices) { voice in Text(voice.name + (voice.language.isEmpty ? "" : " · \(voice.language)")).tag(voice.voice_id) }
                }.onChange(of: premiumVoiceID) { _, value in
                    project?.voiceIdentifier = value
                    markNarrationChaptersStale(ids: Set(chapters.map(\.id)), reason: "Book narrator changed.")
                }
                Picker("Text to speech model", selection: $modelID) {
                    ForEach(models) { Text($0.name ?? $0.model_id).tag($0.model_id) }
                }.onChange(of: modelID) { _, value in
                    project?.modelIdentifier = value
                    markNarrationChaptersStale(ids: Set(chapters.map(\.id)), reason: "Narration model changed.")
                }
                HStack {
                    Button("Preview Selected Voice") { preparePremiumGeneration(previewText) }
                    Text("Preview text is sent for billable generation.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if !providerStatus.isEmpty { Text(providerStatus).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            Spacer()
        }
    }

    private var productionPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PRODUCTION").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            Text(project == nil ? "Not prepared" : "\(chapters.count) chapters · project ready").font(.headline)
            if let chapter = selectedChapter {
                Text(chapter.title).font(.subheadline.weight(.medium)).lineLimit(2)
                Text("\(chapter.text.split(whereSeparator: \.isWhitespace).count) words · \(chapter.state.rawValue.capitalized)").font(.caption).foregroundStyle(.secondary)
                Picker("Narrator", selection: $pendingChapterVoiceID) {
                    Text("Use book narrator").tag("")
                    ForEach(AVSpeechSynthesisVoice.speechVoices().sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }, id: \.identifier) { voice in
                        Text("Mac · \(voice.name) · \(voice.language)").tag("apple.system|\(voice.identifier)")
                    }
                    ForEach(voices) { voice in
                        Text("ElevenLabs · \(voice.name)\(voice.language.isEmpty ? "" : " · \(voice.language)")").tag("elevenlabs|\(voice.voice_id)|\(modelID)")
                    }
                }
                .help("Choose a narrator to preview, then apply it to this chapter.")
                HStack {
                    Button("Preview Narrator") { previewChapterNarrator(chapter) }.disabled(pendingChapterVoiceID.isEmpty)
                    Button("Assign to Chapter") { assignChapterNarrator(chapter) }
                        .disabled(pendingChapterVoiceID == chapterNarratorSelection(chapter) || (!pendingChapterVoiceID.isEmpty && previewedVoiceAssignmentKey != voiceAssignmentKey(chapter, voice: pendingChapterVoiceID)))
                }.buttonStyle(.bordered).controlSize(.small)
                HStack {
                    Button(pendingChapterVoiceID.isEmpty ? "Use Chapter Voice for Passage" : "Assign Voice to Passage") {
                        assignNarratorToSelectedPassage(chapter)
                    }
                    .disabled(selectedPassageRange(in: chapter) == nil || (!pendingChapterVoiceID.isEmpty && previewedVoiceAssignmentKey != voiceAssignmentKey(chapter, voice: pendingChapterVoiceID)))
                    .help("Select a passage in the manuscript, then assign the chosen narrator explicitly to that passage.")
                    if !(chapter.passageNarratorAssignments ?? []).isEmpty {
                        Text("\((chapter.passageNarratorAssignments ?? []).count) passage override(s)").font(.caption).foregroundStyle(.secondary)
                    }
                }.buttonStyle(.bordered).controlSize(.small)
                if let narratorID = chapter.voiceIdentifier, AVSpeechSynthesisVoice(identifier: narratorID) == nil {
                    Label("This chapter’s saved narrator is unavailable. Select an installed narrator to continue.", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                }
                Button((project?.provider ?? "Apple") == "ElevenLabs" ? "Listen / Generate Chapter" : "Listen to Chapter") { listenToChapter(chapter) }.buttonStyle(.borderedProminent)
                if let files = chapter.audioFiles, files.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) {
                    Button("Play Rendered Audio") { playRendered(files) }
                    Button("Reveal Rendered Audio") { NSWorkspace.shared.activateFileViewerSelecting(files) }
                }
                Button("Render Chapter") { prepareProduction(chapterIDs: [chapter.id]) }.disabled(isRendering || chapter.text.isEmpty)
                Button("Generate Chapter") { prepareProduction(chapterIDs: [chapter.id]) }.disabled((project?.provider ?? "Apple") != "ElevenLabs" || isRendering)
            } else {
                Text("Choose a chapter to listen or generate a cloud narration.").font(.caption).foregroundStyle(.secondary)
            }
            if let jobSnapshot {
                ProgressView(value: jobSnapshot.progress)
                Text(productionProgressDescription(jobSnapshot)).font(.caption).foregroundStyle(.secondary)
                if jobSnapshot.state == .partial || jobSnapshot.state == .failed {
                    Label("Failed segments are recorded; verified work is preserved and resume will retry eligible segments.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
                if let error = jobSnapshot.lastError {
                    Text(error).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            if isRendering {
                HStack {
                    ProgressView(status)
                    Button("Pause") { pauseProduction() }.disabled(productionJobID == nil)
                    Button("Cancel Job", role: .destructive) { showCancelProductionConfirmation = true }.disabled(productionJobID == nil)
                }
            }
            else if jobSnapshot?.state == .cancelled || jobSnapshot?.state == .partial || jobSnapshot?.state == .failed {
                Button("Resume Production") { resumeProduction() }.disabled(isRendering)
            }
            Divider()
            Text("Cloud usage guard").font(.headline)
            Stepper("Budget: \(usageBudget.formatted()) characters", value: $usageBudget, in: 1000...2_000_000, step: 1000)
            Text("Used this installation: \(usedCharacters.formatted()) characters").font(.caption).foregroundStyle(.secondary)
            Text("ElevenLabs text leaves this Mac only after you review and confirm each billable request. Text length is shown before sending.").font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("Exports").font(.headline)
            Button("Save Project File…") { saveProjectAs() }.disabled(project == nil)
            Button((project?.provider ?? "Apple") == "ElevenLabs" ? "Start Included Book Production" : "Render All Included Chapters") { prepareProduction(chapterIDs: nil) }.disabled(chapters.isEmpty || isRendering)
            Button("Inspect Audio Quality…") { inspectAudioQuality() }.disabled(completeProjectAudioFiles == nil || isRendering)
            Button("Save Last Generated MP3…") { saveLastGeneratedAudio() }.disabled(outputURL?.pathExtension.lowercased() != "mp3")
            Button("Render Mac Voice Sample…") { prepareSampleExport() }
            Button("Export Audiobook…") { showExportWorkflow = true }.disabled(chapters.isEmpty || isRendering)
            Button("Export for YouTube…") { exportChapterOnly = false; showVideoExportOptions = true }.disabled(completeProjectAudioFiles == nil || isRendering)
            Button("Export Selected Chapter Video…") { exportChapterOnly = true; showVideoExportOptions = true }.disabled(selectedChapterAudioFiles == nil || isRendering)
            Button("Reveal Output Folder") { if let outputURL { NSWorkspace.shared.activateFileViewerSelecting([outputURL]) } }.disabled(outputURL == nil)
            Button("Share Last Export…") { shareLastExport() }.disabled(project?.lastExportURL == nil)
            if let last = project?.lastExportURL, FileManager.default.fileExists(atPath: last.path) {
                Text("\(last.lastPathComponent) · \(fileSize(last))").font(.caption).foregroundStyle(.secondary).lineLimit(1).textSelection(.enabled)
                HStack {
                    Button("Copy File") { copyExportFile(last) }
                    Button("Copy Path") { copyExportPath(last) }
                }.buttonStyle(.bordered).controlSize(.small)
            }
            Spacer()
        }.padding(14)
    }

    private var playbackBar: some View {
        HStack(spacing: 12) {
            Button { reader.moveParagraph(direction: -1, editor: editor) } label: { Image(systemName: "backward.end") }.help("Previous paragraph")
            Button { reader.pauseOrResume() } label: { Image(systemName: reader.isPaused ? "play.fill" : "pause.fill") }.disabled(!reader.isSpeaking).help("Pause or resume")
            Button { reader.stop() } label: { Image(systemName: "stop.fill") }.disabled(!reader.isSpeaking).help("Stop")
            Button { reader.moveParagraph(direction: 1, editor: editor) } label: { Image(systemName: "forward.end") }.help("Next paragraph")
            VStack(alignment: .leading, spacing: 3) {
                Text(reader.activeLabel).font(.subheadline.weight(.medium))
                Text(reader.isSpeaking ? (reader.isPaused ? "Paused" : "Speaking") : "Ready").font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Slider(value: $savedRate, in: nativeRateMinimum...nativeRateMaximum).frame(width: 170)
            Text("\(speedLabel(savedRate))").monospacedDigit().frame(width: 42)
        }.padding(.horizontal, 18).padding(.vertical, 12)
    }

    private var generationConfirmation: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(pendingProductionRequest == nil ? "Confirm ElevenLabs voice preview" : "Review audiobook generation").font(.title2.bold())
            if pendingProductionRequest == nil {
                Text("\(generationCharacterCount.formatted()) characters will be sent once to ElevenLabs for voice \(voices.first(where: { $0.voice_id == pendingPreviewVoiceID })?.name ?? "selected voice") using \(models.first(where: { $0.model_id == pendingPreviewModelID })?.name ?? pendingPreviewModelID). This is a short preview and does not change chapter assignments.")
            } else {
                Text("Review the exact narration scope and character counts before any text leaves this Mac.")
                ForEach(pendingBillableApprovals) { disclosure in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(voices.first(where: { $0.voice_id == disclosure.voiceIdentifier })?.name ?? disclosure.voiceIdentifier) · \(models.first(where: { $0.model_id == disclosure.modelIdentifier })?.name ?? disclosure.modelIdentifier)").font(.subheadline.weight(.medium))
                        Text("\(disclosure.exactCharacterCount.formatted()) characters across \(disclosure.selectedChapterIDs.count) chapter(s); prior attempted: \(disclosure.priorAttemptedCharacters.formatted())").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Text("This request may use paid account quota. Character use is shown below; dollar cost varies by account plan and is not estimated here. It cannot be undone after submission.").foregroundStyle(.secondary)
            if productionBudgetExceeded || generationCharacterCount > usageBudget { Label("Your configured character budget would be exceeded.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
            Text("Configured character budget: \(usageBudget.formatted()) · Remaining after prior attempts: \(max(0, usageBudget - priorAttemptedCharacters).formatted())").font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { showGenerationConfirmation = false; pendingProductionRequest = nil }.keyboardShortcut(.cancelAction)
                Button(pendingProductionRequest == nil ? "Send Preview" : "Approve and Start Production") {
                    showGenerationConfirmation = false
                    if pendingProductionRequest != nil { activeTask = Task { await approveAndStartProduction() } }
                    else { activeTask = Task { await generatePremium() } }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(productionBudgetExceeded || (pendingProductionRequest == nil && usedCharacters + generationCharacterCount > usageBudget))
            }
        }.padding(22).frame(width: 480)
    }

    private var videoExportOptions: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(exportChapterOnly ? "Export Chapter Video" : "Export Audiobook for YouTube").font(.title2.bold())
            Text("Creates a playable MP4 with H.264 video, AAC audio, book artwork, and embedded title metadata. Uploading to YouTube is not included.").font(.callout).foregroundStyle(.secondary)
            TextField("Author", text: Binding(get: { project?.author ?? "" }, set: { ensureProject(); project?.author = $0 }))
            Picker("Video layout", selection: $videoPortrait) {
                Text("16:9 Landscape").tag(false)
                Text("9:16 Vertical").tag(true)
            }.pickerStyle(.segmented)
            ColorPicker("Background", selection: $videoBackground, supportsOpacity: false)
            if let cover = document.metadata.coverProjects?.first(where: { $0.id == document.metadata.activeCoverProjectID }) ?? document.metadata.coverProjects?.first,
               let preview = try? CoverArtwork.render(cover, includeGuides: false, includeTemplate: false, scale: 0.25) {
                HStack {
                    Image(nsImage: preview).resizable().aspectRatio(contentMode: .fit).frame(width: 100, height: 72)
                    Text("Uses the active BOLD Writer cover artwork, fitted without cropping.").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Label("No cover is available. A title card will be generated.", systemImage: "rectangle.on.rectangle").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { showVideoExportOptions = false }
                Button("Choose Destination…") { showVideoExportOptions = false; exportVideo() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(exportChapterOnly ? selectedChapterAudioFiles == nil : completeProjectAudioFiles == nil)
            }
        }
        .padding(22)
        .frame(width: 500)
    }

    private var exportWorkflow: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Export Audiobook").font(.title2.bold())
            Text("The selected production audio is verified before the export replaces a destination file.").font(.callout).foregroundStyle(.secondary)
            Picker("Format", selection: $exportFormatCode) {
                Text("MP3").tag("mp3")
                Text("AAC M4A").tag("m4a")
                Text("WAV PCM").tag("wav")
            }.pickerStyle(.segmented)
            if exportFormatCode == "mp3" {
                Picker("MP3 quality", selection: $mp3Quality) {
                    ForEach(AudiobookMP3Settings.Quality.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
            } else {
                Text(exportFormatCode == "wav" ? "Linear PCM · 44.1 kHz · 16 bit · stereo" : "AAC audio in an M4A container · Apple system encoder")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Toggle("Apply balanced spoken-word mastering", isOn: $useBalancedMastering)
            Text(useBalancedMastering ? "The encoder applies measured constant gain within the sample-peak ceiling. True peak is not measured." : "Keep source gain unchanged; quality measurements are still included in the verification result.")
                .font(.caption).foregroundStyle(.secondary)
            Picker("Export scope", selection: $exportScopeCode) {
                Text("Complete book").tag("book")
                Text("Selected chapter").tag("chapter")
                Text("All included chapters as separate files").tag("separate")
            }
            TextField("Author", text: Binding(get: { project?.author ?? "" }, set: { ensureProject(); project?.author = $0 }))
            if isRendering { ProgressView(status).frame(maxWidth: .infinity, alignment: .leading) }
            HStack {
                Spacer()
                Button("Cancel") { showExportWorkflow = false }
                Button("Choose Destination…") { showExportWorkflow = false; runAudioExportWorkflow() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isSelectedExportScopeReady)
            }
        }
        .padding(22)
        .frame(width: 520)
    }

    private var isSelectedExportScopeReady: Bool {
        switch exportScopeCode {
        case "chapter": return selectedChapterAudioFiles != nil
        case "separate":
            let included = chapters.filter { $0.included != false }
            return !included.isEmpty && included.allSatisfy { $0.state == .complete && ($0.audioFiles?.isEmpty == false) && ($0.audioFiles ?? []).allSatisfy { FileManager.default.fileExists(atPath: $0.path) } }
        default: return completeProjectAudioFiles != nil
        }
    }

    private var pronunciationEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pronunciation Rule").font(.title2.bold())
            TextField("Written term", text: $ruleTerm)
            TextField("Speak as", text: $ruleSpoken)
            Picker("Matching", selection: $ruleMatching) { ForEach(PronunciationRule.Matching.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            Picker("Scope", selection: $ruleScope) { ForEach(PronunciationRule.Scope.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            Picker("Locale", selection: $ruleLocale) { Text("Any locale").tag(""); ForEach(locales, id: \.self) { Text($0).tag($0) } }
            Toggle("Case-sensitive", isOn: $ruleCaseSensitive)
            Text("The source manuscript is never modified. Apple speech uses a text replacement for supported terms; cloud requests use the same prepared narration text.").font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Cancel") { showAddRule = false }; Button("Add") {
                guard !ruleTerm.isEmpty, !ruleSpoken.isEmpty else { return }
                let rule = PronunciationRule(writtenTerm: ruleTerm, spokenForm: ruleSpoken, locale: ruleLocale, scope: ruleScope, matching: ruleMatching, caseSensitive: ruleCaseSensitive)
                if ruleScope == .global { globalRules.append(rule); saveGlobalRules() }
                else { rules.append(rule); project?.pronunciations = rules }
                ruleTerm = ""; ruleSpoken = ""; showAddRule = false
            }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 420)
    }

    private func qualityName(_ quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality { case .default: "Standard"; case .enhanced: "Enhanced"; case .premium: "Premium"; @unknown default: "System" }
    }
    private func genderName(_ gender: AVSpeechSynthesisVoiceGender) -> String {
        switch gender { case .male: "Male-sounding"; case .female: "Female-sounding"; case .unspecified: "Unspecified"; @unknown default: "Unspecified" }
    }
    private func speedLabel(_ rate: Double) -> String { "\(String(format: "%.1f", max(0.5, min(2.0, rate / 0.48))))×" }
    private func isFavorite(_ identifier: String) -> Bool { favoriteIDs.split(separator: ",").contains(Substring(identifier)) }
    private func toggleFavorite(_ identifier: String) {
        var values = Set(favoriteIDs.split(separator: ",").map(String.init))
        if values.contains(identifier) { values.remove(identifier) } else { values.insert(identifier) }
        favoriteIDs = values.sorted().joined(separator: ",")
    }
    private func playPreview(voice: String) {
        reader.selectedVoiceIdentifier = voice
        reader.rate = savedRate
        let locale = AVSpeechSynthesisVoice(identifier: voice)?.language
        let text = applyPronunciations(previewText, locale: locale)
        reader.read(text, range: NSRange(location: 0, length: (text as NSString).length), label: "Voice Preview", in: nil)
    }
    private func ensureProject() {
        guard project == nil else { return }
        project = makeManifest()
    }
    private func makeManifest() -> AudiobookProjectManifest {
        let chapters = makeChapters()
        return AudiobookProjectManifest(sourceURL: sourceURL, sourceFingerprint: AudiobookChapter.digest(manuscript), title: document.metadata.title, author: "", voiceIdentifier: savedVoice, speed: savedRate, pronunciations: rules, chapters: chapters)
    }
    private func makeChapters() -> [AudiobookChapter] {
        let text = manuscript
        let outline = DocumentAnalysis.outline(for: document.text)
        let nsText = text as NSString
        let headings: [(range: NSRange, title: String)]
        if outline.isEmpty {
            headings = ChapterHeadingParser.explicitHeadings(in: text).map { ($0.range, $0.title) }
        } else {
            headings = outline.map { ($0.range, $0.title) }
        }
        let valid = headings.sorted { $0.range.location < $1.range.location }.filter { $0.range.location >= 0 && $0.range.location < nsText.length }
        var result: [AudiobookChapter] = []
        if let first = valid.first {
            if first.range.location > 0 {
                let intro = nsText.substring(to: first.range.location).trimmingCharacters(in: .whitespacesAndNewlines)
                if !intro.isEmpty { result.append(AudiobookChapter(id: "front-matter", title: "Opening", text: intro)) }
            }
            for (index, item) in valid.enumerated() {
                let end = index + 1 < valid.count ? valid[index + 1].range.location : nsText.length
                guard end > item.range.location else { continue }
                let chapterText = nsText.substring(with: NSRange(location: item.range.location, length: end - item.range.location)).trimmingCharacters(in: .whitespacesAndNewlines)
                result.append(AudiobookChapter(id: "heading-\(item.range.location)", title: item.title, text: chapterText))
            }
        }
        if result.isEmpty { result = [AudiobookChapter(id: "whole-book", title: document.metadata.title, text: text)] }
        let activeProvider = project?.provider == "ElevenLabs" ? "elevenlabs" : "apple.system"
        let activeVoice = activeProvider == "elevenlabs" ? premiumVoiceID : savedVoice
        let activeModel = activeProvider == "elevenlabs" ? modelID : ""
        return result.map { chapter in
            var value = chapter
            let stored = project?.chapters.first(where: { $0.id == chapter.id })
            let sourceRange = (text as NSString).range(of: chapter.text)
            let headingLocation = chapter.id.hasPrefix("heading-") ? Int(chapter.id.dropFirst("heading-".count)) : nil
            value.sourceLocation = headingLocation ?? (sourceRange.location == NSNotFound ? nil : sourceRange.location)
            let assignedProvider = stored?.narratorProviderIdentifier ?? activeProvider
            let assignedModel = assignedProvider == "elevenlabs" ? (stored?.narratorModelIdentifier ?? activeModel) : ""
            let assignedVoice = stored?.voiceIdentifier ?? activeVoice
            let ruleFingerprint = (rules + globalRules).map { "\($0.locale)|\($0.writtenTerm)|\($0.spokenForm)|\($0.scope.rawValue)|\($0.matching.rawValue)|\($0.caseSensitive)" }.joined(separator: "|")
            let isBookNarrator = assignedProvider == activeProvider && assignedVoice == activeVoice && assignedModel == activeModel
            value.voiceIdentifier = isBookNarrator ? nil : assignedVoice
            value.narratorProviderIdentifier = isBookNarrator ? nil : assignedProvider
            value.narratorModelIdentifier = isBookNarrator ? nil : assignedModel
            value.passageNarratorAssignments = stored?.passageNarratorAssignments ?? []
            value.included = stored?.included ?? true
            value.fingerprint = AudiobookChapter.digest(chapter.text + "\nvoice:\(assignedVoice)\nrate:\(savedRate)\nprovider:\(assignedProvider)\nmodel:\(assignedModel)\nrules:\(ruleFingerprint)")
            if let old = stored, old.fingerprint == value.fingerprint,
               let files = old.audioFiles, files.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) {
                value.audioFiles = files; value.audioSegments = old.audioSegments; value.state = .complete
            } else if let old = stored, old.fingerprint == value.fingerprint {
                value.audioSegments = old.audioSegments
            } else if let old = stored, old.fingerprint != value.fingerprint {
                value.audioFiles = old.audioFiles; value.audioSegments = old.audioSegments; value.state = .stale
            }
            return value
        }
    }
    private func prepareProject() {
        chapters = makeChapters(); rules = project?.pronunciations ?? rules
        if project == nil { project = makeManifest() }
        project?.chapters = chapters; project?.sourceFingerprint = AudiobookChapter.digest(manuscript)
        project?.sourceURL = sourceURL
        project?.voiceIdentifier = (project?.provider == "ElevenLabs") ? premiumVoiceID : savedVoice
        project?.speed = savedRate; project?.modelIdentifier = modelID
        selectedChapterID = chapters.first?.id
        status = "Prepared \(chapters.count) chapter(s). Source remains unchanged."
    }
    private func chapterIncludedBinding(_ chapter: AudiobookChapter) -> Binding<Bool> {
        Binding(get: { chapterIncluded(chapter.id) }, set: { value in
            guard let index = chapters.firstIndex(where: { $0.id == chapter.id }) else { return }
            chapters[index].included = value
            project?.chapters = chapters
            saveProject()
        })
    }
    private func chapterIncluded(_ id: String) -> Bool {
        chapters.first(where: { $0.id == id })?.included != false
    }
    private func previewChapterNarrator(_ chapter: AudiobookChapter) {
        let selected = selectedPassageRange(in: chapter).map { (chapter.text as NSString).substring(with: $0) }
        let preview = String((selected ?? chapter.text).prefix(320))
        let parts = pendingChapterVoiceID.split(separator: "|", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else { status = "Choose an available narrator to preview."; return }
        if parts[0] == "apple.system" {
            guard let voice = AVSpeechSynthesisVoice(identifier: parts[1]) else { status = "That Mac narrator is unavailable."; return }
            reader.selectedVoiceIdentifier = voice.identifier
            reader.rate = savedRate
            let text = applyPronunciations(preview, locale: voice.language)
            reader.read(text, range: NSRange(location: 0, length: (text as NSString).length), label: "Preview · \(voice.name)", in: nil)
            previewedVoiceAssignmentKey = voiceAssignmentKey(chapter, voice: pendingChapterVoiceID)
            status = "Previewing \(voice.name). Assign it to the chapter when ready."
        } else if parts[0] == "elevenlabs", let voice = voices.first(where: { $0.voice_id == parts[1] }) {
            pendingPreviewVoiceID = voice.voice_id
            pendingPreviewModelID = parts.count > 2 ? parts[2] : modelID
            pendingPreviewAssignmentKey = voiceAssignmentKey(chapter, voice: pendingChapterVoiceID)
            pendingChapterID = nil
            pendingGenerationText = applyPronunciations(String(preview.prefix(320)), locale: voice.language)
            pendingProductionRequest = nil
            pendingBillableApprovals = []
            showGenerationConfirmation = true
            status = "Review the paid preview request before assigning this narrator."
        } else { status = "That account narrator is no longer available." }
    }
    private func assignChapterNarrator(_ chapter: AudiobookChapter) {
        guard let index = chapters.firstIndex(where: { $0.id == chapter.id }) else { return }
        if !pendingChapterVoiceID.isEmpty && previewedVoiceAssignmentKey != voiceAssignmentKey(chapter, voice: pendingChapterVoiceID) {
            status = "Preview this narrator for the chapter before assigning it."
            return
        }
        let parts = pendingChapterVoiceID.split(separator: "|", maxSplits: 2).map(String.init)
        if !pendingChapterVoiceID.isEmpty {
            guard parts.count >= 2 else { status = "Choose an available narrator."; return }
            if parts[0] == "apple.system" && AVSpeechSynthesisVoice(identifier: parts[1]) == nil {
                status = "The selected narrator is no longer installed. Choose an available voice."; return
            }
            if parts[0] == "elevenlabs" && !voices.contains(where: { $0.voice_id == parts[1] }) {
                status = "The selected account narrator is no longer available. Refresh the voice catalog."; return
            }
        }
        chapters[index].voiceIdentifier = parts.count > 1 ? parts[1] : nil
        chapters[index].narratorProviderIdentifier = parts.first == "apple.system" || parts.first == "elevenlabs" ? parts[0] : nil
        chapters[index].narratorModelIdentifier = parts.first == "elevenlabs" ? (parts.count > 2 ? parts[2] : modelID) : nil
        chapters[index].state = .stale
        project?.chapters = chapters
        saveProject()
        status = "Narrator assigned for \(chapter.title). Existing audio is marked outdated."
    }

    private func selectedPassageRange(in chapter: AudiobookChapter) -> NSRange? {
        let selection = editor.selection
        guard selection.length > 0, let chapterStart = chapter.sourceLocation,
              selection.location >= chapterStart else { return nil }
        let relative = NSRange(location: selection.location - chapterStart, length: selection.length)
        let chapterText = chapter.text as NSString
        guard relative.location >= 0, NSMaxRange(relative) <= chapterText.length,
              NSMaxRange(selection) <= (manuscript as NSString).length,
              chapterText.substring(with: relative) == (manuscript as NSString).substring(with: selection) else { return nil }
        return relative
    }

    private func voiceAssignmentKey(_ chapter: AudiobookChapter, voice: String) -> String {
        let range = selectedPassageRange(in: chapter)
        return "\(chapter.id)|\(voice)|\(range.map { "\($0.location):\($0.length)" } ?? "chapter")"
    }

    private func assignNarratorToSelectedPassage(_ chapter: AudiobookChapter) {
        guard let range = selectedPassageRange(in: chapter),
              let index = chapters.firstIndex(where: { $0.id == chapter.id }) else {
            status = "Select text inside this chapter in the manuscript before assigning a passage narrator."
            return
        }
        if !pendingChapterVoiceID.isEmpty && previewedVoiceAssignmentKey != voiceAssignmentKey(chapter, voice: pendingChapterVoiceID) {
            status = "Preview this narrator for the marked passage before assigning it."
            return
        }
        let source = chapter.text as NSString
        let passageText = source.substring(with: range)
        var assignments = (chapters[index].passageNarratorAssignments ?? []).filter { NSIntersectionRange($0.range, range).length == 0 }
        if !pendingChapterVoiceID.isEmpty {
            let parts = pendingChapterVoiceID.split(separator: "|", maxSplits: 2).map(String.init)
            guard parts.count >= 2 else { status = "Choose a narrator before assigning the selected passage."; return }
            if parts[0] == "apple.system" && AVSpeechSynthesisVoice(identifier: parts[1]) == nil {
                status = "The selected Mac narrator is no longer installed."; return
            }
            if parts[0] == "elevenlabs" && !voices.contains(where: { $0.voice_id == parts[1] }) {
                status = "The selected account narrator is no longer available."; return
            }
            assignments.append(AudiobookPassageNarratorAssignment(
                id: "passage-\(chapter.id)-\(range.location)-\(range.length)",
                location: range.location,
                length: range.length,
                textFingerprint: AudiobookChapter.digest(passageText),
                providerIdentifier: parts[0],
                voiceIdentifier: parts[1],
                modelIdentifier: parts.first == "elevenlabs" ? (parts.count > 2 ? parts[2] : modelID) : nil
            ))
        }
        chapters[index].passageNarratorAssignments = assignments.sorted { $0.location < $1.location }
        chapters[index].state = .stale
        project?.chapters = chapters
        saveProject()
        status = pendingChapterVoiceID.isEmpty
            ? "The selected passage now uses its chapter narrator; existing chapter audio is marked outdated."
            : "Narrator assigned to the marked passage in \(chapter.title); existing chapter audio is marked outdated."
    }
    private func chapterNarratorSelection(_ chapter: AudiobookChapter) -> String {
        guard let voice = chapter.voiceIdentifier else { return "" }
        let provider = chapter.narratorProviderIdentifier ?? "apple.system"
        return provider == "elevenlabs" ? "elevenlabs|\(voice)|\(chapter.narratorModelIdentifier ?? modelID)" : "apple.system|\(voice)"
    }
    private func markChangedChaptersStale() {
        guard project != nil, !chapters.isEmpty else { return }
        let current = makeChapters()
        let currentByID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0.fingerprint) })
        var didChange = false
        for index in chapters.indices where currentByID[chapters[index].id] != chapters[index].fingerprint {
            chapters[index].state = .stale; didChange = true
        }
        if didChange { project?.chapters = chapters; saveProject(); status = "Manuscript changed. Affected narration chapters are marked stale." }
    }
    private func markNarrationChaptersStale(ids: Set<String>, reason: String) {
        guard !ids.isEmpty else { return }
        var changed = false
        for index in chapters.indices where ids.contains(chapters[index].id) && chapters[index].state == .complete {
            chapters[index].state = .stale
            changed = true
        }
        guard changed else { return }
        project?.chapters = chapters
        saveProject()
        status = "\(reason) Affected chapter audio is marked outdated."
    }
    private func readChapter(_ chapter: AudiobookChapter) {
        let voiceID = chapter.voiceIdentifier ?? savedVoice
        guard let voice = AVSpeechSynthesisVoice(identifier: voiceID) else { status = "The selected chapter narrator is no longer installed. Choose an available narrator."; return }
        reader.selectedVoiceIdentifier = voice.identifier
        let text = applyPronunciations(chapter.text, locale: voice.language)
        reader.read(text, range: NSRange(location: 0, length: (text as NSString).length), label: chapter.title, in: nil)
    }
    private func listenToChapter(_ chapter: AudiobookChapter) {
        if let files = chapter.audioFiles, !files.isEmpty, files.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) { playRendered(files) }
        else if (project?.provider ?? "Apple") == "ElevenLabs" { prepareProduction(chapterIDs: [chapter.id]) }
        else { readChapter(chapter) }
    }
    private func applyPronunciations(_ text: String, locale: String? = nil) -> String {
        PronunciationProcessor.apply(text, rules: rules + globalRules, locale: locale)
    }
    private func refreshCredentialState() {
        hasProviderKey = ((try? ElevenLabsKeychain.load()) ?? nil) != nil
        globalRules = (try? JSONDecoder().decode([PronunciationRule].self, from: Data(globalPronunciationJSON.utf8))) ?? []
    }
    private func saveGlobalRules() {
        guard let data = try? JSONEncoder().encode(globalRules) else { return }
        globalPronunciationJSON = String(decoding: data, as: UTF8.self)
    }
    private func removeRule(_ rule: PronunciationRule) {
        if rule.scope == .global { globalRules.removeAll { $0.id == rule.id }; saveGlobalRules() }
        else { rules.removeAll { $0.id == rule.id }; project?.pronunciations = rules }
    }
    private func saveProviderKey() {
        do { try ElevenLabsKeychain.save(providerKey); providerKey = ""; hasProviderKey = true; productionService = nil; providerStatus = "API key saved in macOS Keychain." }
        catch { providerStatus = error.localizedDescription }
    }
    private func removeProviderKey() {
        do { try ElevenLabsKeychain.remove(); hasProviderKey = false; providerKey = ""; productionService = nil; providerStatus = "ElevenLabs API key removed from Keychain." }
        catch { providerStatus = error.localizedDescription }
    }
    private func loadProviderCatalog() {
        guard let key = try? ElevenLabsKeychain.load(), !key.isEmpty else { providerStatus = "Save a valid API key first."; return }
        isLoadingProvider = true
        Task {
            defer { isLoadingProvider = false }
            do {
                let api = ElevenLabsProvider(apiKey: key)
                async let fetchedVoices = api.voices()
                async let fetchedModels = api.models()
                voices = try await fetchedVoices; models = try await fetchedModels
                if premiumVoiceID.isEmpty { premiumVoiceID = voices.first?.voice_id ?? "" }
                if modelID.isEmpty { modelID = models.first?.model_id ?? "" }
                project?.provider = "ElevenLabs"; project?.modelIdentifier = modelID
                providerStatus = "Loaded \(voices.count) account voices and \(models.count) text to speech models."
            } catch { providerStatus = error.localizedDescription }
        }
    }
    private func preparePremiumGeneration(_ text: String) {
        guard !text.isEmpty else { providerStatus = "Enter preview text or select a chapter."; return }
        pendingPreviewVoiceID = premiumVoiceID
        pendingPreviewModelID = modelID
        pendingPreviewAssignmentKey = nil
        pendingChapterID = nil
        pendingGenerationText = applyPronunciations(text, locale: voices.first(where: { $0.voice_id == premiumVoiceID })?.language)
        pendingProductionRequest = nil
        pendingBillableApprovals = []
        showGenerationConfirmation = true
    }

    private func prepareProduction(chapterIDs: [String]?) {
        prepareProject()
        guard let request = makeProductionRequest(chapterIDs: chapterIDs) else {
            status = "Choose an installed narrator and at least one included chapter before production."
            return
        }
        if request.assignmentPlan.narrators.values.contains(where: { $0.providerID == "elevenlabs" }), !hasProviderKey {
            providerStatus = "Save an ElevenLabs API key in Keychain before starting paid generation."
            return
        }
        isRendering = true
        status = "Checking the selected chapter and narrator scope…"
        activeTask = Task {
            do {
                let service = try productionServiceForCurrentProject()
                productionService = service
                let disclosures = try await service.billablePreflight(for: request)
                pendingProductionRequest = request
                pendingBillableApprovals = disclosures
                if disclosures.isEmpty {
                    try await startProduction(request, service: service, resume: jobSnapshot?.state == .cancelled || jobSnapshot?.state == .partial || jobSnapshot?.state == .failed)
                } else {
                    pendingChapterID = nil
                    showGenerationConfirmation = true
                    status = "Review the exact text count and provider scope before sending."
                }
            } catch {
                status = "Production preflight failed: \(error.localizedDescription)"
                providerStatus = error.localizedDescription
            }
        }
    }

    private func makeProductionRequest(chapterIDs: [String]?) -> AudiobookRenderRequest? {
        ensureProject()
        guard let project else { return nil }
        let selected = chapters.filter { chapter in
            chapter.included != false && (chapterIDs == nil || chapterIDs!.contains(chapter.id))
        }
        guard !selected.isEmpty else { return nil }

        var narrators: [String: AudiobookNarratorProfile] = [:]
        var chapterNarrators: [String: String] = [:]
        var segmentNarrators: [String: String] = [:]
        var items: [AudiobookSourceItem] = []
        func narratorProfile(providerID: String, voiceID: String, modelIdentifier: String) -> String? {
            guard !voiceID.isEmpty, providerID != "elevenlabs" || !modelIdentifier.isEmpty else { return nil }
            let profileID = "\(providerID)|\(voiceID)|\(modelIdentifier)"
            let modelLimit = models.first(where: { $0.model_id == modelIdentifier })?.maximum_text_length_per_request ?? 3_500
            narrators[profileID] = AudiobookNarratorProfile(
                id: profileID,
                providerID: providerID,
                voiceIdentifier: voiceID,
                modelIdentifier: modelIdentifier,
                speed: providerID == "apple.system" ? savedRate : nil,
                pronunciationFingerprint: AudiobookChapter.digest((rules + globalRules).map { "\($0.locale)|\($0.writtenTerm)|\($0.spokenForm)|\($0.scope.rawValue)|\($0.matching.rawValue)|\($0.caseSensitive)" }.joined(separator: "|")),
                maximumRequestCharacters: providerID == "elevenlabs" ? min(3_500, modelLimit) : 3_500
            )
            return profileID
        }
        for chapter in selected {
            let providerID = chapter.narratorProviderIdentifier ?? ((project.provider == "ElevenLabs") ? "elevenlabs" : "apple.system")
            let voiceID = chapter.voiceIdentifier ?? ((providerID == "elevenlabs") ? premiumVoiceID : savedVoice)
            let modelIdentifier = providerID == "elevenlabs" ? (chapter.narratorModelIdentifier ?? modelID) : ""
            guard let defaultProfileID = narratorProfile(providerID: providerID, voiceID: voiceID, modelIdentifier: modelIdentifier) else { return nil }
            chapterNarrators[chapter.id] = defaultProfileID
            let source = chapter.text as NSString
            for segment in chapter.narrationRanges() {
                let segmentText = source.substring(with: segment.range)
                let itemID = "chapter-\(chapter.id)-range-\(segment.range.location)-\(segment.range.length)"
                let profileID: String
                if let assignment = segment.passageAssignment {
                    guard let assignedProfileID = narratorProfile(
                        providerID: assignment.providerIdentifier,
                        voiceID: assignment.voiceIdentifier,
                        modelIdentifier: assignment.modelIdentifier ?? ""
                    ) else { return nil }
                    profileID = assignedProfileID
                    segmentNarrators[itemID] = assignedProfileID
                } else { profileID = defaultProfileID }
                let language = narrators[profileID].flatMap { profile in
                    profile.providerID == "elevenlabs"
                        ? voices.first(where: { $0.voice_id == profile.voiceIdentifier })?.language
                        : AVSpeechSynthesisVoice(identifier: profile.voiceIdentifier)?.language
                }
                items.append(AudiobookSourceItem(
                    id: itemID,
                    chapterID: chapter.id,
                    chapterTitle: chapter.title,
                    sourceTextFingerprint: AudiobookChapter.digest("\(chapter.fingerprint)|\(segment.range.location)|\(segment.range.length)|\(segmentText)"),
                    narrationText: applyPronunciations(segmentText, locale: language)
                ))
            }
        }
        guard let defaultNarratorID = chapterNarrators[selected[0].id] else { return nil }
        let scope: AudiobookRenderScope = chapterIDs == nil
            ? AudiobookRenderScope(kind: .wholeBook)
            : AudiobookRenderScope(kind: .selectedChapters, selectedChapterIDs: selected.map(\.id))
        return AudiobookRenderRequest(
            projectID: project.projectID,
            sourceFingerprint: AudiobookChapter.digest(manuscript),
            scope: scope,
            items: items,
            assignmentPlan: AudiobookNarratorAssignmentPlan(
                defaultNarratorID: defaultNarratorID,
                chapterNarrators: chapterNarrators,
                segmentNarrators: segmentNarrators,
                narrators: narrators
            )
        )
    }

    private func productionServiceForCurrentProject() throws -> AudiobookProductionService {
        ensureProject()
        guard let project else { throw AudiobookProductionError.invalidManifest }
        if let productionService, productionService.projectID == project.projectID { return productionService }
        let directory = generatedDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var providers: [any AudiobookNarrationProvider] = [AppleSystemNarrationProvider()]
        if let key = try? ElevenLabsKeychain.load(), !key.isEmpty {
            providers.append(ElevenLabsNarrationProvider(apiKey: key))
        }
        return try AudiobookProductionService(projectID: project.projectID, projectDirectory: directory, providers: providers)
    }

    private func startProduction(_ request: AudiobookRenderRequest, service: AudiobookProductionService, resume: Bool) async throws {
        var approvedRequest = request
        approvedRequest.billableApprovals = pendingBillableApprovals.map { disclosure in
            AudiobookBillableApproval(
                providerID: disclosure.providerID,
                voiceIdentifier: disclosure.voiceIdentifier,
                modelIdentifier: disclosure.modelIdentifier,
                reviewedCharacterCount: disclosure.exactCharacterCount,
                reviewedTextFingerprint: disclosure.reviewedTextFingerprint,
                characterBudget: usageBudget,
                charactersAlreadyUsed: disclosure.priorAttemptedCharacters
            )
        }
        pendingProductionRequest = approvedRequest
        lastProductionChapterIDs = request.scope.kind == .wholeBook ? nil : request.scope.selectedChapterIDs
        jobStartedAt = Date()
        status = resume ? "Resuming production from verified chapter segments…" : "Starting audiobook production…"
        let jobID = try await (resume ? service.resume(approvedRequest) : service.render(approvedRequest))
        productionJobID = jobID
        jobSnapshot = await service.snapshot(for: jobID)
        let projectID = request.projectID
        let updates = await service.updates(for: projectID)
        activeTask = Task {
            for await snapshot in updates {
                guard !Task.isCancelled else { return }
                jobSnapshot = snapshot
                status = productionProgressDescription(snapshot)
                if snapshot.state == .complete {
                    syncCompletedProduction(chapterIDs: request.scope.kind == .wholeBook ? nil : request.scope.selectedChapterIDs, service: service)
                    isRendering = false
                    return
                }
                if snapshot.state == .cancelled || snapshot.state == .partial || snapshot.state == .failed {
                    isRendering = false
                    if let error = snapshot.lastError { status = "Production stopped: \(error)" }
                    return
                }
            }
        }
        isRendering = true
    }

    private func approveAndStartProduction() async {
        guard let request = pendingProductionRequest else { return }
        do {
            let service = try productionServiceForCurrentProject()
            productionService = service
            let latest = try await service.billablePreflight(for: request)
            guard latest == pendingBillableApprovals else {
                pendingBillableApprovals = latest
                pendingProductionRequest = request
                status = "Narration text or provider scope changed. Review the updated disclosure before approving."
                showGenerationConfirmation = true
                return
            }
            guard !productionBudgetExceeded else {
                status = "The configured character budget would be exceeded; no provider request was sent."
                return
            }
            isRendering = true
            try await startProduction(request, service: service, resume: jobSnapshot?.state == .cancelled || jobSnapshot?.state == .partial)
        } catch {
            isRendering = false
            status = "Production could not start: \(error.localizedDescription)"
            providerStatus = error.localizedDescription
        }
    }

    private func syncCompletedProduction(chapterIDs: [String]?, service: AudiobookProductionService) {
        Task {
            do {
                let records = try await service.verifiedAudio(chapterIDs: chapterIDs)
                for chapterID in Set(records.map(\.chapterID)) {
                    guard let index = chapters.firstIndex(where: { $0.id == chapterID }) else { continue }
                    let chapterRecords = records.filter { $0.chapterID == chapterID }
                    let urls = chapterRecords.map { service.projectDirectory.appendingPathComponent($0.relativePath) }
                    chapters[index].audioFiles = urls
                    chapters[index].state = .complete
                }
                project?.chapters = chapters
                outputURL = records.first.map { service.projectDirectory.appendingPathComponent($0.relativePath) }
                project?.lastExportURL = outputURL
                saveProject()
                status = "Production complete. \(records.count) verified audio segment(s) are ready."
            } catch { status = "Production finished, but audio verification failed: \(error.localizedDescription)" }
        }
    }

    private func pauseProduction() {
        guard let productionService, let productionJobID else { return }
        status = "Pausing after the current audio segment… Completed segments remain saved."
        Task { await productionService.cancel(productionJobID) }
    }

    private func cancelProduction() {
        guard let productionService, let productionJobID else { return }
        status = "Cancelling after the current audio segment… Verified audio is preserved."
        Task { await productionService.cancel(productionJobID) }
    }

    private func resumeProduction() {
        prepareProject()
        guard let request = makeProductionRequest(chapterIDs: lastProductionChapterIDs) else {
            status = "The current chapter text or narrator settings need review before resuming."
            return
        }
        isRendering = true
        activeTask = Task {
            defer { if jobSnapshot?.state != .rendering && jobSnapshot?.state != .queued { isRendering = false } }
            do {
                let service = try productionServiceForCurrentProject()
                productionService = service
                pendingBillableApprovals = try await service.billablePreflight(for: request)
                if !pendingBillableApprovals.isEmpty {
                    pendingProductionRequest = request
                    showGenerationConfirmation = true
                } else {
                    try await startProduction(request, service: service, resume: true)
                }
            } catch { status = "Resume failed: \(error.localizedDescription)" }
        }
    }

    private func productionProgressDescription(_ snapshot: AudiobookJobSnapshot) -> String {
        let current = snapshot.currentChapterID.flatMap { id in chapters.first(where: { $0.id == id })?.title } ?? snapshot.currentChapterID ?? "Queued"
        let elapsed = jobStartedAt.map { max(0, Date().timeIntervalSince($0)) } ?? 0
        let remaining = snapshot.progress > 0 ? elapsed * (1 - snapshot.progress) / snapshot.progress : nil
        let elapsedLabel = elapsed > 0 ? " · elapsed \(Int(elapsed / 60))m \(Int(elapsed) % 60)s" : ""
        let time = remaining.map { " · ~\(Int($0 / 60)) min remaining" } ?? ""
        return "\(current) · \(snapshot.completedChunks)/\(snapshot.totalChunks) segments · \(Int(snapshot.progress * 100))%\(elapsedLabel)\(time)"
    }

    private func inspectAudioQuality() {
        guard completeProjectAudioFiles != nil else { return }
        isRendering = true
        Task {
            defer { isRendering = false }
            do {
                let service = try productionServiceForCurrentProject()
                productionService = service
                qualityReport = try await service.inspect(chapterIDs: chapters.filter { $0.included != false }.map(\.id))
                showQualityReport = true
            } catch { status = "Audio quality inspection failed: \(error.localizedDescription)" }
        }
    }

    private var qualityReportSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Audio Quality Report").font(.title2.bold())
            if let report = qualityReport {
                LabeledContent("Duration", value: String(format: "%.1f min", report.totalDurationSeconds / 60))
                LabeledContent("Integrated loudness", value: report.integratedLoudnessLUFS.map { String(format: "%.1f LUFS", $0) } ?? "Not measurable")
                LabeledContent("Sample peak", value: String(format: "%.1f dBFS", report.samplePeakDBFS))
                LabeledContent("Clipped samples", value: report.clippedSampleCount.formatted())
                LabeledContent("Longest quiet run", value: String(format: "%.1f sec", report.longestQuietRunSeconds))
                LabeledContent("Source chapters", value: "\(report.chapterJoins.count + 1)")
                Text("True peak was not measured. This report does not certify a commercial distributor standard.").font(.caption).foregroundStyle(.secondary)
                if !report.warnings.isEmpty {
                    Divider()
                    ForEach(Array(report.warnings.enumerated()), id: \.offset) { _, warning in
                        Label(warning, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                    }
                }
            } else { Text("No report is available.") }
            HStack { Spacer(); Button("Done") { showQualityReport = false }.keyboardShortcut(.defaultAction) }
        }
        .padding(22)
        .frame(width: 500)
    }
    private func generatePremium() async {
        guard let key = try? ElevenLabsKeychain.load(), !key.isEmpty,
              let model = models.first(where: { $0.model_id == pendingPreviewModelID }),
              !pendingPreviewVoiceID.isEmpty else { providerStatus = "Choose an account voice and model."; return }
        guard usedCharacters + generationCharacterCount <= usageBudget else { providerStatus = "Project usage budget reached."; return }
        isRendering = true
        defer { isRendering = false }
        do {
            let requestLimit = model.maximum_text_length_per_request ?? 10_000
            guard !pendingGenerationText.isEmpty else { providerStatus = "There is no preview text to generate."; return }
            guard pendingGenerationText.utf16.count <= requestLimit else { providerStatus = "The selected model limit is shorter than this preview."; return }
            let directory = generatedDirectory()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let api = ElevenLabsProvider(apiKey: key)
            providerStatus = "Generating one short voice preview…"
            let data = try await api.synthesize(text: pendingGenerationText, voiceID: pendingPreviewVoiceID, modelID: pendingPreviewModelID, limit: requestLimit)
            let fingerprint = AudiobookChapter.digest(pendingGenerationText + "\nvoice:\(pendingPreviewVoiceID)\nmodel:\(pendingPreviewModelID)")
            let file = directory.appendingPathComponent("voice-preview-\(fingerprint.prefix(16))-\(UUID().uuidString).mp3")
            try data.write(to: file, options: .atomic)
            usedCharacters += generationCharacterCount
            outputURL = file
            player = try AVAudioPlayer(contentsOf: file); player?.prepareToPlay(); player?.play()
            if let pendingPreviewAssignmentKey { previewedVoiceAssignmentKey = pendingPreviewAssignmentKey }
            providerStatus = "Played a paid \(generationCharacterCount.formatted())-character preview. Chapter assignments were not changed."
        } catch {
            if let pendingChapterID, let index = chapters.firstIndex(where: { $0.id == pendingChapterID }) { chapters[index].state = .failed; project?.chapters = chapters; saveProject() }
            providerStatus = error.localizedDescription
        }
    }
    private func prepareSampleExport() {
        guard let voice = AVSpeechSynthesisVoice(identifier: savedVoice), !previewText.isEmpty else { status = "Choose a Mac voice and enter preview text."; return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "\(safeFilename(document.metadata.title))-voice-sample.caf"; panel.allowedContentTypes = [.init(filenameExtension: "caf") ?? .audio]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        status = "Rendering a local voice sample…"; isRendering = true
        Task {
            defer { isRendering = false }
            do {
                let files = try await LocalSpeechRenderer.render(applyPronunciations(previewText, locale: voice.language), voice: voice, rate: savedRate, directory: url.deletingLastPathComponent(), basename: url.deletingPathExtension().lastPathComponent)
                outputURL = files.first; status = "Local CAF audio saved: \(files.first?.lastPathComponent ?? "")"
            }
            catch { status = "Audio render failed: \(error.localizedDescription)" }
        }
    }
    private func generatedDirectory() -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("BOLDWriter/AudiobookProjects/GeneratedAudio/\(project?.projectID.uuidString ?? "unsaved")", isDirectory: true)
        return directory
    }
    private func playRendered(_ files: [URL]) {
        let items = files.map { AVPlayerItem(url: $0) }
        let queue = AVQueuePlayer(items: items); queuePlayer = queue; queue.play()
    }
    private func saveLastGeneratedAudio() {
        guard let outputURL else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "\(safeFilename(document.metadata.title))-narration.mp3"; panel.allowedContentTypes = [.mp3]
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            try FileManager.default.copyItem(at: outputURL, to: destination)
            project?.lastExportURL = destination; self.outputURL = destination; saveProject()
            status = "MP3 saved: \(destination.lastPathComponent)"
        } catch { status = "Could not save MP3: \(error.localizedDescription)" }
    }
    private func runAudioExportWorkflow() {
        guard let format = AudiobookExportRequest.Format(rawValue: exportFormatCode) else { status = "Choose a supported export format."; return }
        if exportScopeCode == "separate" {
            let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
            panel.prompt = "Export Chapters"
            guard panel.runModal() == .OK, let directory = panel.url else { return }
            exportSeparateChapters(format: format, directory: directory)
            return
        }
        let chapterIDs: [String]
        let title: String
        if exportScopeCode == "chapter" {
            guard let chapter = selectedChapter, selectedChapterAudioFiles != nil else { status = "Render the selected chapter before exporting."; return }
            chapterIDs = [chapter.id]; title = chapter.title
        } else {
            guard completeProjectAudioFiles != nil else { status = "Render all included chapters before exporting the complete book."; return }
            chapterIDs = chapters.filter { $0.included != false }.map(\.id); title = document.metadata.title
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(safeFilename(document.metadata.title))\(exportScopeCode == "chapter" ? "-\(safeFilename(title))" : "")-audiobook.\(format.rawValue)"
        panel.allowedContentTypes = [exportContentType(format)]
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        isRendering = true
        status = "Exporting \(title) as \(format.rawValue.uppercased())…"
        Task {
            defer { isRendering = false }
            do {
                let result = try await exportThroughProductionService(chapterIDs: chapterIDs, format: format, title: title, destination: destination)
                outputURL = destination
                project?.lastExportURL = destination
                saveProject()
                status = "Verified \(format.rawValue.uppercased()) · \(result.durationSeconds.formatted(.number.precision(.fractionLength(1)))) s · \(result.bytes.formatted(.byteCount(style: .file))) · \(destination.lastPathComponent)"
            } catch {
                status = "Audiobook export failed: \(error.localizedDescription)"
            }
        }
    }
    private func exportSeparateChapters(format: AudiobookExportRequest.Format, directory: URL) {
        let included = chapters.filter { $0.included != false }
        guard !included.isEmpty else { status = "No chapters are included in this audiobook."; return }
        isRendering = true
        Task {
            defer { isRendering = false }
            var completed = 0
            for chapter in included {
                guard chapter.state == .complete else {
                    status = "\(chapter.title) has no current rendered audio. No further chapter files were exported."; return
                }
                let destination = directory.appendingPathComponent("\(safeFilename(document.metadata.title))-\(safeFilename(chapter.title)).\(format.rawValue)")
                do {
                    let result = try await exportThroughProductionService(chapterIDs: [chapter.id], format: format, title: chapter.title, destination: destination)
                    completed += 1; outputURL = destination; project?.lastExportURL = destination; saveProject()
                    status = "Verified \(completed)/\(included.count) chapter exports · last \(result.bytes.formatted(.byteCount(style: .file))): \(destination.lastPathComponent)"
                } catch { status = "Stopped at \(chapter.title): \(error.localizedDescription)"; return }
            }
            status = "Verified \(completed) separate \(format.rawValue.uppercased()) chapter exports."
        }
    }
    private func exportThroughProductionService(chapterIDs: [String], format: AudiobookExportRequest.Format, title: String, destination: URL) async throws -> AudiobookVerifiedExport {
        let service = try productionServiceForCurrentProject()
        productionService = service
        let mastering: AudiobookMasteringSettings = useBalancedMastering ? .balancedSpokenWord : .original
        let request = AudiobookExportRequest(
            chapterIDs: chapterIDs,
            format: format,
            destination: destination,
            title: title,
            author: project?.author ?? "",
            album: document.metadata.title,
            mp3Settings: AudiobookMP3Settings(quality: mp3Quality),
            mastering: mastering
        )
        let result = try await service.export(request)
        qualityReport = result.quality
        return result
    }

    private func exportContentType(_ format: AudiobookExportRequest.Format) -> UTType {
        switch format {
        case .mp3: .mp3
        case .wav: .wav
        case .m4a: .mpeg4Audio
        }
    }
    private func exportVideo() {
        let chapterIDs: [String]
        let chapterTitle: String?
        if exportChapterOnly {
            guard let selectedChapter, selectedChapterAudioFiles != nil else { status = "Render the selected chapter before exporting its video."; return }
            chapterIDs = [selectedChapter.id]
            chapterTitle = selectedChapter.title
        } else {
            guard completeProjectAudioFiles != nil else { status = "Render all included chapters before exporting the complete video."; return }
            chapterIDs = chapters.filter { $0.included != false }.map(\.id)
            chapterTitle = nil
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        let title = safeFilename(document.metadata.title)
        panel.nameFieldStringValue = "\(title)\(chapterTitle.map { "-\(safeFilename($0))" } ?? "")-youtube.mp4"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        let artwork: NSImage? = document.metadata.coverProjects?
            .first(where: { $0.id == document.metadata.activeCoverProjectID })
            .flatMap { try? CoverArtwork.render($0, includeGuides: false, includeTemplate: false, scale: 0.25) }
            ?? document.metadata.coverProjects?.first.flatMap { try? CoverArtwork.render($0, includeGuides: false, includeTemplate: false, scale: 0.25) }
        let background = NSColor(videoBackground)
        let metadata = AudiobookVideoMetadata(title: document.metadata.title, author: project?.author ?? "", chapterTitle: chapterTitle, backgroundColor: background, portrait: videoPortrait, coverImage: artwork)
        isRendering = true
        status = "Creating YouTube MP4…"
        Task {
            defer { isRendering = false }
            let masteredAudio = destination.deletingLastPathComponent().appendingPathComponent(".boldwriter-video-audio-\(UUID().uuidString).m4a")
            defer { try? FileManager.default.removeItem(at: masteredAudio) }
            do {
                let audio = try await exportThroughProductionService(
                    chapterIDs: chapterIDs,
                    format: .m4a,
                    title: document.metadata.title,
                    destination: masteredAudio
                )
                try await Task.detached(priority: .userInitiated) {
                    try await AudiobookVideoExporter.export(sources: [audio.fileURL], metadata: metadata, to: destination)
                }.value
                outputURL = destination; project?.lastExportURL = destination; saveProject()
                status = "Verified H.264/AAC MP4 · \(fileSize(destination)) · mastered source · \(destination.lastPathComponent)"
            } catch { status = "Video export failed: \(error.localizedDescription)" }
        }
    }
    private func saveProject() {
        guard var project else { return }
        project.chapters = chapters; project.pronunciations = rules
        project.voiceIdentifier = project.provider == "ElevenLabs" ? premiumVoiceID : savedVoice
        project.modelIdentifier = modelID; project.speed = savedRate; project.updatedAt = Date()
        let destination = projectURL ?? defaultProjectURL()
        do { let data = try JSONEncoder.pretty.encode(project); try data.write(to: destination, options: .atomic); self.project = project; projectURL = destination; status = "Project saved locally." }
        catch { status = "Project save failed: \(error.localizedDescription)" }
    }
    private func saveProjectAs() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "\(safeFilename(document.metadata.title))-Audiobook.boldaudio"; panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url { projectURL = url; saveProject() }
    }
    private func loadSavedProject() {
        let url = defaultProjectURL()
        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        guard let saved = try? decoder.decode(AudiobookProjectManifest.self, from: data) else { return }
        project = saved; projectURL = url; chapters = saved.chapters; rules = saved.pronunciations
        if saved.provider == "ElevenLabs" { premiumVoiceID = saved.voiceIdentifier; modelID = saved.modelIdentifier }
        else { savedVoice = saved.voiceIdentifier }
        savedRate = saved.speed; selectedChapterID = chapters.first?.id
        if saved.provider == "ElevenLabs" { loadProviderCatalog() }
        if saved.sourceURL != sourceURL || saved.sourceFingerprint != AudiobookChapter.digest(manuscript) {
            status = "Source changed or moved. Review chapters and prepare updated narration before export."
            chapters = chapters.map { var value = $0; value.state = .stale; return value }
        } else { status = "Restored audiobook project." }
    }
    private func defaultProjectURL() -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("BOLDWriter/AudiobookProjects", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let key = AudiobookChapter.digest((sourceURL?.standardizedFileURL.path ?? document.metadata.title) + document.metadata.title)
        return directory.appendingPathComponent(key + ".json")
    }
    private func safeFilename(_ value: String) -> String { value.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-") }
    private func shareLastExport() {
        guard let path = project?.lastExportURL else { return }
        let bytes = (try? FileManager.default.attributesOfItem(atPath: path.path)[.size] as? NSNumber)?.int64Value ?? 0
        if AudiobookSharePolicy.shouldWarn(fileSizeBytes: bytes) {
            largeShareURL = path
            showLargeShareWarning = true
            return
        }
        presentSharePicker(for: path)
    }
    private func presentSharePicker(for path: URL) {
        guard FileManager.default.fileExists(atPath: path.path) else { status = "The selected export is no longer available."; return }
        let picker = NSSharingServicePicker(items: [path]); picker.show(relativeTo: .zero, of: NSApp.keyWindow?.contentView ?? NSView(), preferredEdge: .minY)
        largeShareURL = nil
    }
    private func copyExportFile(_ url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
        status = "File copied to the clipboard."
    }
    private func copyExportPath(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
        status = "File path copied to the clipboard."
    }
    private func fileSize(_ url: URL) -> String {
        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601; return encoder }
}

private enum ElevenLabsKeychain {
    static func save(_ value: String) throws { try write(value) }
    static func remove() throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.boldwriter.elevenlabs", kSecAttrAccount as String: "api-key"]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.unexpectedStatus(status) }
    }
    static func load() throws -> String? {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.boldwriter.elevenlabs", kSecAttrAccount as String: "api-key", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result); query.removeAll()
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError.unexpectedStatus(status) }
        return String(data: data, encoding: .utf8)
    }
    private static func write(_ value: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.boldwriter.elevenlabs", kSecAttrAccount as String: "api-key"]
        let attrs: [String: Any] = [kSecValueData as String: Data(value.utf8), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound { var add = query; attrs.forEach { add[$0.key] = $0.value }; let added = SecItemAdd(add as CFDictionary, nil); guard added == errSecSuccess else { throw KeychainError.unexpectedStatus(added) } }
        else if status != errSecSuccess { throw KeychainError.unexpectedStatus(status) }
    }
}

enum LocalSpeechRenderer {
    static func render(_ text: String, voice: AVSpeechSynthesisVoice, rate: Double, directory: URL, basename: String) async throws -> [URL] {
        let chunks = AudiobookProjectManifest.chunks(text)
        guard !chunks.isEmpty else { throw WriterError.message("There is no text to render.") }
        var output: [URL] = []
        for (index, chunk) in chunks.enumerated() {
            let chunkURL = directory.appendingPathComponent(String(format: "%@-%04d.caf", basename, index + 1))
            try await renderChunk(chunk, voice: voice, rate: rate, to: chunkURL)
            output.append(chunkURL)
        }
        return output
    }
    private static func renderChunk(_ text: String, voice: AVSpeechSynthesisVoice, rate: Double, to url: URL) async throws {
        let synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: text); utterance.voice = voice
        utterance.rate = Float(min(max(rate, Double(AVSpeechUtteranceMinimumSpeechRate)), Double(AVSpeechUtteranceMaximumSpeechRate)))
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let lock = NSLock(); var file: AVAudioFile?; var finished = false
            synthesizer.write(utterance) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                lock.lock(); defer { lock.unlock() }
                guard !finished else { return }
                do {
                    if pcm.frameLength == 0 { finished = true; continuation.resume(); return }
                    if file == nil { file = try AVAudioFile(forWriting: url, settings: pcm.format.settings) }
                    try file?.write(from: pcm)
                } catch { finished = true; continuation.resume(throwing: error) }
            }
        }
    }
}
