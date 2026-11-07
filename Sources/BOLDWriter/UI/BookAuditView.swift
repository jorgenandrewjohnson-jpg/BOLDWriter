import AppKit
import SwiftUI

struct BookAuditView: View {
    private static let scanQueue = DispatchQueue(label: "com.boldwriter.manuscript-audit", qos: .userInitiated)
    @ObservedObject var document: BOLDWriterDocument
    @StateObject private var knowledgeLibrary = KnowledgeLibraryStore.shared
    let editor: EditorController
    let onPrintReadinessCheck: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @State private var findings: [BOLDConsistencyFinding] = []
    @State private var crossDocumentFindings: [BOLDCrossDocumentFinding] = []
    @State private var crossAuditResult: BOLDCrossDocumentAuditResult?
    @State private var auditScope: BOLDAuditScope = .currentDocument
    @State private var selectedLibraryDocumentIDs: Set<UUID> = []
    @State private var crossNavigationError: String?
    @State private var selectedCategory = "All categories"
    @State private var isScanning = false
    @State private var scanGeneration = UUID()
    @State private var activeCancellation: BOLDAuditCancellationToken?
    @State private var overview = BOLDAuditOverview(words: 0, sectionCount: 0, shortestSectionWords: 0, longestSectionWords: 0)
    @State private var locationIndex = BOLDAuditLocationIndex("")
    @State private var scanDuration: TimeInterval?
    @State private var sortOrder = "Priority"
    @State private var showIgnored = false
    @State private var pendingCorrection: BOLDConsistencyFinding?
    @State private var rerunAfterCorrectionRevision = false
    @State private var ruleKind: BOLDConsistencyRuleKind = .preferredTerm
    @State private var matchText = ""
    @State private var replacement = ""
    @State private var explanation = ""
    @State private var caseSensitive = false
    @State private var wholeWord = true
    @State private var ruleScope: BOLDConsistencyRuleScope = .entireManuscript

    private var manuscript: String { editor.textView?.string ?? document.text.string }
    private var rules: [BOLDConsistencyRule] { document.metadata.manuscriptConsistencyRules ?? [] }
    private var ignoredIDs: Set<String> { Set(document.metadata.ignoredManuscriptFindings ?? []) }
    private var visibleFindings: [BOLDConsistencyFinding] {
        let filtered = findings.filter { finding in
            let argumentCategory = auditScope != .argumentReview || [
                BOLDConsistencyCategory.repeatedArguments, .duplicateParagraphs, .sectionLengthBalance, .argumentStructure
            ].contains(finding.category)
            return argumentCategory && !ignoredIDs.contains(finding.id)
                && (selectedCategory == "All categories" || categoryTitle(finding.category) == selectedCategory)
        }
        return filtered.sorted {
            let leftLocation = ($0.secondRange ?? $0.firstRange).location
            let rightLocation = ($1.secondRange ?? $1.firstRange).location
            if sortOrder == "Location" { return leftLocation < rightLocation }
            if $0.auditConfidence.sortOrder != $1.auditConfidence.sortOrder {
                return $0.auditConfidence.sortOrder < $1.auditConfidence.sortOrder
            }
            return leftLocation < rightLocation
        }
    }
    private var ignoredFindings: [BOLDConsistencyFinding] { findings.filter { ignoredIDs.contains($0.id) } }
    private var visibleCrossDocumentFindings: [BOLDCrossDocumentFinding] {
        let filtered = crossDocumentFindings.filter { !ignoredIDs.contains($0.id) &&
            (selectedCategory == "All categories" || $0.category.rawValue == selectedCategory) }
        return filtered.sorted { left, right in
            if sortOrder == "Location" {
                let leftKey = "\(left.primaryTitle)\u{1f}\(left.primary?.reference.utf16Range.location ?? Int.max)"
                let rightKey = "\(right.primaryTitle)\u{1f}\(right.primary?.reference.utf16Range.location ?? Int.max)"
                return leftKey.localizedStandardCompare(rightKey) == .orderedAscending
            }
            if left.confidence != right.confidence {
                return crossConfidenceOrder(left.confidence) < crossConfidenceOrder(right.confidence)
            }
            return left.primaryTitle.localizedCaseInsensitiveCompare(right.primaryTitle) == .orderedAscending
        }
    }
    private var ignoredCrossDocumentFindings: [BOLDCrossDocumentFinding] { crossDocumentFindings.filter { ignoredIDs.contains($0.id) } }
    private var activeFindingCount: Int { auditScope == .selectedLibrary ? visibleCrossDocumentFindings.count : visibleFindings.count }
    private var activeCategoryNames: [String] {
        auditScope == .selectedLibrary ? Array(Set(crossDocumentFindings.map { $0.category.rawValue })).sorted() : categoryNames
    }
    private var rulesPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if auditScope == .selectedLibrary { librarySelectionControls }
                Text("Project Rules").font(.headline)
                Toggle("Live checks after edits", isOn: Binding(
                    get: { document.metadata.manuscriptLiveAuditEnabled ?? false },
                    set: { document.metadata.manuscriptLiveAuditEnabled = $0; if $0 { runAudit() } }
                ))
                .help("Live checks wait briefly after an edit and discard results from older revisions.")

                if rules.isEmpty {
                    Text("Create a local writing rule. Examples: prefer Yeshua over Yehoshua, or flag a prohibited phrase.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 7) {
                            ForEach(rules) { rule in ruleRow(rule) }
                        }
                    }.frame(maxHeight: 120)
                }
                Divider()
                Picker("Rule type", selection: $ruleKind) {
                    Text("Preferred terminology").tag(BOLDConsistencyRuleKind.preferredTerm)
                    Text("Disallowed term").tag(BOLDConsistencyRuleKind.disallowedTerm)
                    Text("Capitalization").tag(BOLDConsistencyRuleKind.capitalization)
                }
                TextField("Variant or phrase to flag", text: $matchText)
                if ruleKind != .disallowedTerm {
                    TextField(ruleKind == .preferredTerm ? "Preferred spelling (optional)" : "Correct capitalization", text: $replacement)
                }
                TextField("Explanation for the author (optional)", text: $explanation)
                Toggle("Match case exactly", isOn: $caseSensitive)
                Toggle("Match whole words", isOn: $wholeWord)
                Picker("Scope", selection: $ruleScope) {
                    Text("Entire manuscript").tag(BOLDConsistencyRuleScope.entireManuscript)
                    Text("Outside recognized quotations").tag(BOLDConsistencyRuleScope.outsideQuotationMarks)
                }
                Text("Quoted text is protected using quote style, block quote, and balanced nested punctuation cues. Incomplete quotation boundaries are shown for review.")
                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if auditScope == .selectedLibrary {
                    Text("Saved rules are applied read-only across the selected sources. Quotation metadata is not available in every imported excerpt, so cross-document matches never offer automatic replacement.")
                        .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text("Evidence Manager summary: pending committed read-only API integration.")
                        .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Button("Add Rule") { addRule() }.disabled(matchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Export Audit Report…", action: exportReport)
                    .disabled((auditScope == .selectedLibrary ? crossDocumentFindings.isEmpty : findings.isEmpty) || isScanning)
                Spacer(minLength: 0)
            }.frame(width: 280)
        }
        .frame(width: 280)
        .frame(maxHeight: .infinity)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Book Audit").font(.title2.weight(.semibold))
                    Text("Local review · findings never change manuscript text automatically")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if isScanning {
                    Button("Cancel") { cancelCurrentScan() }
                } else {
                    Button { runAudit() } label: { Label("Run Book Audit", systemImage: "arrow.clockwise") }
                }
                Button("Layout & Print Readiness", action: onPrintReadinessCheck)
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(2)

            HStack(spacing: 10) {
                Picker("Audit scope", selection: $auditScope) {
                    Text("Current Document").tag(BOLDAuditScope.currentDocument)
                    Text("Argument Review").tag(BOLDAuditScope.argumentReview)
                    Text("Selected Library").tag(BOLDAuditScope.selectedLibrary)
                }.frame(width: 220)
                metric("Words", value: "\(overview.words)")
                metric("Sections", value: "\(overview.sectionCount)")
                metric("Balance", value: sectionBalance)
                if auditScope == .selectedLibrary {
                    metric("Library", value: "\(selectedLibraryDocumentIDs.count) selected")
                }
                Spacer()
                Picker("Sort findings", selection: $sortOrder) {
                    Text("Priority").tag("Priority")
                    Text("Location").tag("Location")
                }.frame(width: 130)
                Picker("Filter findings", selection: $selectedCategory) {
                    Text("All categories").tag("All categories")
                    ForEach(activeCategoryNames, id: \.self) { Text($0).tag($0) }
                }.frame(width: 225)
            }
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(2)

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Findings").font(.headline)
                        Text("\(activeFindingCount)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Spacer()
                    }
                    if auditScope != .selectedLibrary && findings.isEmpty && !isScanning {
                        ContentUnavailableView("Run an audit", systemImage: "checklist", description: Text("Scan manuscript structure, links, headings, repetition, terminology, dates, names, and project rules."))
                    } else if auditScope != .selectedLibrary {
                        List(visibleFindings) { finding in
                            findingRow(finding)
                        }.listStyle(.inset)
                    } else if crossDocumentFindings.isEmpty && !isScanning {
                        ContentUnavailableView("Select Library sources", systemImage: "books.vertical", description: Text("Choose related manuscripts or research notes, then run a read-only cross-document audit."))
                    } else {
                        List(visibleCrossDocumentFindings) { finding in crossDocumentFindingRow(finding) }
                            .listStyle(.inset)
                    }
                    let ignoredCount = auditScope == .selectedLibrary ? ignoredCrossDocumentFindings.count : ignoredFindings.count
                    if ignoredCount > 0 {
                        Toggle("Show ignored issues (\(ignoredCount))", isOn: $showIgnored)
                            .font(.caption)
                        if showIgnored {
                            if auditScope != .selectedLibrary {
                                ForEach(ignoredFindings) { finding in ignoredFindingRow(categoryTitle(finding.category), excerpt(for: finding)) { unignore(finding) } }
                            } else {
                                ForEach(ignoredCrossDocumentFindings) { finding in ignoredFindingRow(finding.category.rawValue, finding.primaryExcerpt) { unignoreCrossFinding(finding) } }
                            }
                        }
                    }
                }.frame(minWidth: 430, maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                rulesPanel
            }
            .frame(minHeight: 390, maxHeight: .infinity)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    if auditScope != .selectedLibrary {
                        Text("Potential dates, names, and similar arguments are review suggestions, not established contradictions.")
                        Text("Up to 1,500 prioritized findings are shown. Citation targets lack structured source links; external link reachability is not checked. Page-layout heading warnings use Layout & Print Readiness.")
                    } else {
                        Text("Exact duplicates and literal rule matches are labeled separately from review suggestions. Date, name, and argument similarities are not factual contradictions.")
                        if let crossAuditResult {
                            Text("\(crossAuditResult.scannedDocumentCount) sources scanned · \(crossAuditResult.unavailableDocumentCount) unavailable · \(crossAuditResult.omittedPassageCount) passages omitted · \(crossAuditResult.staleResultCount) stale references rejected.")
                        }
                    }
                }
                Spacer()
                if let scanDuration { Text(String(format: "Last audit %.2f s", scanDuration)).monospacedDigit() }
            }
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(2)
        }
        .padding(18)
        .frame(minWidth: 980, minHeight: 800)
        .confirmationDialog("Apply this correction?", isPresented: Binding(
            get: { pendingCorrection != nil },
            set: { if !$0 { pendingCorrection = nil } }
        ), titleVisibility: .visible) {
            if let finding = pendingCorrection,
               let replacement = finding.suggestedReplacement {
                Button("Replace “\(finding.matchedText ?? "")” with “\(replacement)”") {
                    apply(finding)
                }
            }
            Button("Cancel", role: .cancel) { pendingCorrection = nil }
        } message: {
            Text(pendingCorrection?.isInsideQuotationText == true
                ? "This occurrence is inside recognized quotation marks. Verify the source text before accepting this one edit. It can be undone with the editor’s normal Undo command."
                : "This edits one exact occurrence and can be undone with the editor’s normal Undo command.")
        }
        .task(id: document.revisionID) {
            guard auditScope != .selectedLibrary else { return }
            guard document.metadata.manuscriptLiveAuditEnabled == true else { return }
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            runAudit()
        }
        .onChange(of: document.revisionID) { _, _ in
            let rerunAfterCorrection = rerunAfterCorrectionRevision
            rerunAfterCorrectionRevision = false
            cancelCurrentScan()
            findings = []
            scanDuration = nil
            if rerunAfterCorrection {
                DispatchQueue.main.async { runAudit() }
            }
        }
        .onAppear {
            selectedLibraryDocumentIDs = Set(document.metadata.manuscriptAuditLibraryDocumentIDs ?? [])
                .intersection(Set(knowledgeLibrary.documents.map { $0.id.rawValue }))
        }
        .onChange(of: selectedLibraryDocumentIDs) { _, ids in
            document.metadata.manuscriptAuditLibraryDocumentIDs = ids.sorted { $0.uuidString < $1.uuidString }
        }
        .onChange(of: auditScope) { _, _ in
            cancelCurrentScan()
            selectedCategory = "All categories"
            showIgnored = false
        }
        .alert("Source passage is no longer current", isPresented: Binding(
            get: { crossNavigationError != nil },
            set: { if !$0 { crossNavigationError = nil } }
        )) {
            Button("OK", role: .cancel) { crossNavigationError = nil }
        } message: {
            Text(crossNavigationError ?? "")
        }
    }

    private var categoryNames: [String] {
        Array(Set(findings.map { categoryTitle($0.category) })).sorted()
    }

    private var sectionBalance: String {
        guard overview.sectionCount > 1 else { return "1 section" }
        return "\(overview.shortestSectionWords)–\(overview.longestSectionWords) words"
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.headline.monospacedDigit())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.padding(.horizontal, 10).padding(.vertical, 6)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 7))
    }

    private func findingRow(_ finding: BOLDConsistencyFinding) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(categoryTitle(finding.category)).font(.subheadline.weight(.semibold))
                Spacer()
                Text(priorityTitle(finding)).font(.caption2.weight(.medium)).foregroundStyle(priorityColor(finding))
            }
            Text(location(for: finding)).font(.caption).foregroundStyle(.secondary)
            Text(excerpt(for: finding)).font(.callout).lineLimit(3).textSelection(.enabled)
            if finding.isInsideQuotationText {
                Label("Inside quotation marks — verify the source before editing", systemImage: "quote.bubble")
                    .font(.caption2).foregroundStyle(.orange)
            }
            Text(finding.explanation).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Go to text") { editor.navigate(to: targetRange(for: finding)) }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                if let suggestion = finding.suggestedReplacement, finding.matchedText != nil {
                    Button("Review replacement: \(suggestion)") { pendingCorrection = finding }
                        .controlSize(.small)
                }
                Spacer()
                Button("Ignore") { ignore(finding) }.controlSize(.small)
                if let id = finding.ruleID, let rule = rules.first(where: { $0.id == id }) {
                    Button("Disable rule") { setRule(rule, enabled: false) }.controlSize(.small)
                }
            }
            if finding.secondRange != nil {
                Text("Compared with: \(comparisonExcerpt(for: finding))")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
        }.padding(.vertical, 5)
    }

    private func ruleRow(_ rule: BOLDConsistencyRule) -> some View {
        HStack(alignment: .top) {
            Toggle("", isOn: Binding(
                get: { rule.enabled },
                set: { setRule(rule, enabled: $0) }
            )).labelsHidden().controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.matchText + (rule.replacement.map { " → \($0)" } ?? ""))
                    .font(.caption.weight(.medium)).lineLimit(2)
                Text(rule.explanation.isEmpty ? rule.kind.rawValue : rule.explanation)
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
            Button { removeRule(rule) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless).help("Delete this project rule")
        }
    }

    private var librarySelectionControls: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Library collection").font(.headline)
                Spacer()
                Button("Manage…") { openWindow(id: "knowledge-library") }
                    .buttonStyle(.link).controlSize(.small)
            }
            HStack {
                Text("Select up to 100 sources for this project audit.")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { selectedLibraryDocumentIDs = [] }
                    .buttonStyle(.link).controlSize(.small)
            }
            BOLDAuditLibrarySelectionList(documents: knowledgeLibrary.documents, selectedIDs: $selectedLibraryDocumentIDs)
                .frame(height: 120)
            if knowledgeLibrary.documents.isEmpty {
                Text("Add or select sources in the Knowledge Library to begin.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Divider()
        }
    }

    private func crossDocumentFindingRow(_ finding: BOLDCrossDocumentFinding) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(finding.category.rawValue).font(.subheadline.weight(.semibold))
                Spacer()
                Text(finding.confidence.rawValue.uppercased()).font(.caption2.weight(.medium))
                    .foregroundStyle(finding.confidence == .exactDuplicate || finding.confidence == .exactRuleViolation ? .orange : .secondary)
            }
            HStack(alignment: .top, spacing: 8) {
                passageCard(title: finding.primaryTitle, excerpt: finding.primaryExcerpt, result: finding.primary, query: finding.query)
                if let comparisonTitle = finding.comparisonTitle, let comparisonExcerpt = finding.comparisonExcerpt {
                    passageCard(title: comparisonTitle, excerpt: comparisonExcerpt, result: finding.comparison, query: finding.query)
                }
            }
            Text(finding.explanation).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if finding.isQuoted {
                Label("Quotation context detected; this cross-document result is informational only.", systemImage: "quote.bubble")
                    .font(.caption2).foregroundStyle(.orange)
            }
            HStack {
                if let primary = finding.primary {
                    Button("Open source passage") { openLibraryResult(primary, query: finding.query) }
                        .controlSize(.small)
                }
                if let comparison = finding.comparison {
                    Button("Open comparison") { openLibraryResult(comparison, query: finding.query) }
                        .controlSize(.small)
                }
                Spacer()
                Button("Ignore") { ignoreCrossFinding(finding) }.controlSize(.small)
            }
        }.padding(.vertical, 6)
    }

    private func passageCard(title: String, excerpt: String, result: KnowledgeSearchResult?, query: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption.weight(.semibold)).lineLimit(1)
            if let result {
                Text("\(result.reference.context) · UTF-16 offset \(result.reference.utf16Range.location)")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Text(excerpt).font(.caption2).lineLimit(5).textSelection(.enabled)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(7)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
    }

    private func ignoredFindingRow(_ category: String, _ excerpt: String, reenable: @escaping () -> Void) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(category).font(.caption.weight(.semibold))
                Text(excerpt).font(.caption2).lineLimit(2).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Re-enable", action: reenable).controlSize(.small)
        }.padding(.vertical, 2)
    }

    private func runAudit() {
        guard auditScope != .selectedLibrary else {
            runCrossDocumentAudit()
            return
        }
        activeCancellation?.cancel()
        let generation = UUID()
        scanGeneration = generation
        let cancellation = BOLDAuditCancellationToken()
        activeCancellation = cancellation
        isScanning = true
        let started = ProcessInfo.processInfo.systemUptime
        let revision = document.revisionID
        let storage = editor.textView?.textStorage ?? document.text
        let snapshot = BOLDBookAuditAnalyzer.snapshot(from: storage)
        let settings = BOLDAuditMetadataSnapshot(
            sections: document.metadata.sections ?? [],
            bookmarks: document.metadata.bookmarks,
            tableOfContents: document.metadata.publishingTOCs ?? [],
            footnotes: document.metadata.footnotes,
            rules: rules
        )
        Self.scanQueue.async {
            guard !cancellation.isCancelled,
                  let result = BOLDBookAuditAnalyzer.analyze(snapshot, metadata: settings, shouldCancel: { cancellation.isCancelled }) else { return }
            guard let metrics = BOLDBookAuditAnalyzer.overview(for: snapshot.text, shouldCancel: { cancellation.isCancelled }),
                  let index = BOLDAuditLocationIndex(snapshot.text, shouldCancel: { cancellation.isCancelled }) else { return }
            let duration = ProcessInfo.processInfo.systemUptime - started
            DispatchQueue.main.async {
                guard scanGeneration == generation,
                      document.revisionID == revision,
                      !cancellation.isCancelled else { return }
                findings = result
                overview = metrics
                locationIndex = index
                scanDuration = duration
                isScanning = false
                activeCancellation = nil
            }
        }
    }

    private func runCrossDocumentAudit() {
        activeCancellation?.cancel()
        let cancellation = BOLDAuditCancellationToken()
        activeCancellation = cancellation
        crossDocumentFindings = []
        crossAuditResult = nil
        guard !selectedLibraryDocumentIDs.isEmpty else {
            isScanning = false
            crossAuditResult = BOLDCrossDocumentAuditResult(findings: [], scannedDocumentCount: 0, unavailableDocumentCount: 0, omittedPassageCount: 0, staleResultCount: 0, elapsed: 0)
            return
        }
        isScanning = true
        let adapter = BOLDKnowledgeLibraryAuditAdapter(library: knowledgeLibrary) {
            openWindow(id: "knowledge-library")
        }
        let coordinator = BOLDCrossDocumentAuditCoordinator(library: adapter)
        let selectedIDs = selectedLibraryDocumentIDs
        let currentRules = rules
        Task { @MainActor in
            let result = await coordinator.run(selectedDocumentIDs: selectedIDs, rules: currentRules, cancellation: cancellation)
            guard activeCancellation === cancellation, !cancellation.isCancelled else { return }
            isScanning = false
            activeCancellation = nil
            guard let result else { return }
            crossAuditResult = result
            crossDocumentFindings = result.findings
            scanDuration = result.elapsed
        }
    }

    private func cancelCurrentScan() {
        scanGeneration = UUID()
        activeCancellation?.cancel()
        activeCancellation = nil
        isScanning = false
    }

    private func addRule() {
        let kind = ruleKind
        var current = rules
        current.append(BOLDConsistencyRule(
            kind: kind,
            matchText: matchText.trimmingCharacters(in: .whitespacesAndNewlines),
            replacement: replacement.isEmpty || kind == .disallowedTerm ? nil : replacement,
            explanation: explanation,
            caseSensitive: caseSensitive,
            wholeWord: wholeWord,
            scope: ruleScope
        ))
        document.metadata.manuscriptConsistencyRules = current
        matchText = ""; replacement = ""; explanation = ""
        runAudit()
    }

    private func setRule(_ rule: BOLDConsistencyRule, enabled: Bool) {
        var current = rules
        guard let index = current.firstIndex(where: { $0.id == rule.id }) else { return }
        current[index].enabled = enabled
        document.metadata.manuscriptConsistencyRules = current
        runAudit()
    }

    private func removeRule(_ rule: BOLDConsistencyRule) {
        document.metadata.manuscriptConsistencyRules = rules.filter { $0.id != rule.id }
        runAudit()
    }

    private func ignore(_ finding: BOLDConsistencyFinding) {
        var ignored = document.metadata.ignoredManuscriptFindings ?? []
        if !ignored.contains(finding.id) { ignored.append(finding.id) }
        document.metadata.ignoredManuscriptFindings = ignored
    }

    private func unignore(_ finding: BOLDConsistencyFinding) {
        document.metadata.ignoredManuscriptFindings = (document.metadata.ignoredManuscriptFindings ?? [])
            .filter { $0 != finding.id }
    }

    private func ignoreCrossFinding(_ finding: BOLDCrossDocumentFinding) {
        var ignored = document.metadata.ignoredManuscriptFindings ?? []
        if !ignored.contains(finding.id) { ignored.append(finding.id) }
        document.metadata.ignoredManuscriptFindings = ignored
    }

    private func unignoreCrossFinding(_ finding: BOLDCrossDocumentFinding) {
        document.metadata.ignoredManuscriptFindings = (document.metadata.ignoredManuscriptFindings ?? [])
            .filter { $0 != finding.id }
    }

    private func openLibraryResult(_ result: KnowledgeSearchResult, query: String) {
        let adapter = BOLDKnowledgeLibraryAuditAdapter(library: knowledgeLibrary) {
            openWindow(id: "knowledge-library")
        }
        if !adapter.open(result, query: query) {
            crossNavigationError = "The source changed or its canonical passage can no longer be resolved. Rerun the cross-document audit before navigating."
        }
    }

    private func exportReport() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "Book-Audit-Report.md"
        panel.title = "Export Book Audit Report"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let report: String
        if auditScope != .selectedLibrary {
            report = BOLDAuditReportExporter.markdown(
                title: document.metadata.title, text: manuscript,
                findings: findings.filter { !ignoredIDs.contains($0.id) }, ignoredCount: ignoredFindings.count
            )
        } else {
            report = BOLDCrossDocumentReportExporter.markdown(
                title: document.metadata.title,
                findings: crossDocumentFindings.filter { !ignoredIDs.contains($0.id) },
                scannedDocumentCount: crossAuditResult?.scannedDocumentCount ?? 0,
                omittedCount: crossAuditResult?.omittedPassageCount ?? 0,
                staleCount: crossAuditResult?.staleResultCount ?? 0
            )
        }
        do {
            try Data(report.utf8).write(to: url, options: .atomic)
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "The audit report could not be exported"
            alert.runModal()
        }
    }

    private func apply(_ finding: BOLDConsistencyFinding) {
        defer { pendingCorrection = nil }
        guard let replacement = finding.suggestedReplacement,
              let expected = finding.matchedText,
              finding.firstRange.location >= 0,
              NSMaxRange(finding.firstRange) <= (manuscript as NSString).length,
              (manuscript as NSString).substring(with: finding.firstRange) == expected else {
            runAudit(); return
        }
        editor.navigate(to: finding.firstRange)
        rerunAfterCorrectionRevision = true
        guard editor.applyManuscriptReplacement(replacement, in: finding.firstRange, expectedText: expected) else {
            rerunAfterCorrectionRevision = false
            return
        }
    }

    private func excerpt(for finding: BOLDConsistencyFinding) -> String {
        let ns = manuscript as NSString
        let range = targetRange(for: finding)
        guard range.location >= 0, NSMaxRange(range) <= ns.length else { return "Text changed; rerun the audit." }
        let start = max(0, range.location - 70)
        let end = min(ns.length, NSMaxRange(range) + 120)
        return ns.substring(with: NSRange(location: start, length: end - start))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func location(for finding: BOLDConsistencyFinding) -> String {
        locationIndex.describe(targetRange(for: finding).location)
    }

    private func comparisonExcerpt(for finding: BOLDConsistencyFinding) -> String {
        let range = finding.firstRange
        let ns = manuscript as NSString
        guard range.location >= 0, NSMaxRange(range) <= ns.length else { return "Text changed." }
        let start = max(0, range.location - 35)
        let end = min(ns.length, NSMaxRange(range) + 60)
        return ns.substring(with: NSRange(location: start, length: end - start))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func targetRange(for finding: BOLDConsistencyFinding) -> NSRange {
        finding.secondRange ?? finding.firstRange
    }

    private func categoryTitle(_ category: BOLDConsistencyCategory) -> String {
        switch category {
        case .conflictingDates: "Potential date conflict"
        case .nameVariants: "Potential name variant"
        case .terminology: "Terminology inconsistency"
        case .capitalization: "Capitalization inconsistency"
        case .duplicateParagraphs: "Repeated or similar passage"
        case .repeatedArguments: "Potentially similar argument"
        case .authorRuleViolation: "Author rule"
        case .uncertainQuotation: "Quotation context needs review"
        case .emptySection: "Empty section"
        case .headingHierarchy: "Heading hierarchy"
        case .brokenCrossReference: "Broken internal reference"
        case .unresolvedLink: "Unresolved document link"
        case .duplicateSectionBoundary: "Duplicate section boundary"
        case .unreferencedFootnote: "Unreferenced footnote"
        case .malformedTableOfContents: "Malformed table of contents"
        case .sectionLengthBalance: "Chapter length imbalance"
        case .argumentStructure: "Argument structure review"
        }
    }

    private func crossConfidenceOrder(_ confidence: BOLDCrossDocumentConfidence) -> Int {
        switch confidence {
        case .exactRuleViolation, .exactDuplicate: 0
        case .potentialInconsistency: 1
        case .unavailableSource: 2
        case .reviewSuggestion: 3
        }
    }

    private func priorityTitle(_ finding: BOLDConsistencyFinding) -> String {
        finding.auditConfidence.rawValue.uppercased()
    }

    private func priorityColor(_ finding: BOLDConsistencyFinding) -> Color {
        switch finding.auditConfidence {
        case .confirmedStructuralDefect: .red
        case .exactRuleViolation, .exactDuplicate: .orange
        case .potentialInconsistency: .yellow
        case .reviewSuggestion: .secondary
        }
    }
}

private struct BOLDAuditLibrarySelectionList: View {
    let documents: [KnowledgeDocumentRecord]
    @Binding var selectedIDs: Set<UUID>

    var body: some View {
        List(documents) { record in
            Button {
                if selectedIDs.contains(record.id.rawValue) {
                    selectedIDs.remove(record.id.rawValue)
                } else if selectedIDs.count < BOLDCrossDocumentSnapshotter.maximumDocuments {
                    selectedIDs.insert(record.id.rawValue)
                }
            } label: {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: selectedIDs.contains(record.id.rawValue) ? "checkmark.square.fill" : "square")
                        .foregroundStyle(selectedIDs.contains(record.id.rawValue) ? Color.accentColor : Color.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(record.title).lineLimit(1)
                        Text("\(record.provenance) · \(record.status.rawValue)")
                            .font(.caption2).foregroundStyle(record.status == .available ? Color.secondary : Color.orange)
                    }
                }.font(.caption).frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain)
        }.listStyle(.plain)
    }
}

final class BOLDAuditCancellationToken {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}
