import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AutomationStudioView: View {
    @ObservedObject var document: BOLDWriterDocument
    @ObservedObject var editor: EditorController
    let onSelectWorkspace: (BookWorkspace) -> Void

    @State private var source = Self.defaultScript
    @State private var parsed: BOLDScript?
    @State private var plan: BOLDScriptPlan?
    @State private var previewRevision: UUID?
    @State private var diagnostics = "Paste or open a BOLD Script v1 file, then validate it."
    @State private var output = ""
    @State private var history: [String] = []
    @State private var fileError: String?
    @State private var automationUndoActionName: String?
    @State private var hasImageRecoveryCheckpoint = false

    var body: some View {
        VStack(spacing: 0) {
            BookWorkspaceSwitcher(current: .automationStudio, onSelect: onSelectWorkspace)
            HStack(spacing: 12) {
                Image(systemName: "curlybraces")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Automation Studio").font(.system(size: 20, weight: .semibold))
                    Text("BOLD Script v1 · Target: this open document")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Label("No script runs until you approve Apply Changes", systemImage: "checkmark.shield")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18).padding(.vertical, 13)
            Divider()

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Script editor").font(.headline)
                    HStack(spacing: 8) {
                        Button("Paste From Clipboard", systemImage: "doc.on.clipboard", action: paste)
                        Button("Open Script…", systemImage: "folder", action: openScript)
                        Button("Save Script…", systemImage: "square.and.arrow.down", action: saveScript)
                    }
                    .buttonStyle(.bordered)

                    BOLDScriptTextEditor(text: $source)
                        .frame(minWidth: 450, minHeight: 300)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))

                    HStack {
                        Button("Validate Script", systemImage: "checkmark.seal", action: validate)
                        Button("Preview Changes", systemImage: "list.bullet.rectangle", action: preview)
                            .buttonStyle(.borderedProminent)
                        Spacer()
                        Button("Cancel Operation", systemImage: "xmark.circle", action: cancel)
                            .disabled(plan == nil && parsed == nil)
                    }
                    Text(diagnostics)
                        .font(.system(.callout, design: .rounded))
                        .foregroundStyle(diagnostics.hasPrefix("Error") ? .red : .secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                }
                .padding(16)
                .frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                Divider()
                VStack(alignment: .leading, spacing: 13) {
                    HStack {
                        Text("Change preview").font(.headline)
                        Spacer()
                        Button("Apply Changes", systemImage: "play.fill", action: apply)
                            .buttonStyle(.borderedProminent)
                            .disabled(plan == nil || plan?.totalChanges == 0 || previewRevision != document.revisionID)
                    }
                    if let plan {
                        Label("\(plan.totalChanges) planned edits", systemImage: "doc.badge.gearshape")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Target: this open document. The complete proposed document was validated before approval.")
                            .font(.caption).foregroundStyle(.secondary)
                        List(Array(plan.changes.enumerated()), id: \.offset) { entry in
                            let item = entry.element
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.operation).font(.callout.weight(.medium))
                                Text("\(item.affectedMatches) match(es) · \(item.affectedParagraphs) paragraph(s)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 3)
                        }
                        .listStyle(.inset)
                        if !plan.imageInspection.isEmpty {
                            GroupBox("Floating image properties") {
                                ForEach(plan.imageInspection) { image in
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(image.assetName).font(.headline)
                                        Text("ID \(image.id.uuidString) · page \(image.pageIndex + 1) · \(image.width, specifier: "%.1f") × \(image.height, specifier: "%.1f") pt")
                                        Text("\(image.anchor.rawValue) · \(image.wrapping.rawValue) · \(image.layer.rawValue) · \(image.rotationDegrees, specifier: "%.1f")° · z \(image.zOrder) · \(image.positionLocked ? "locked" : "unlocked")")
                                    }
                                    .font(.caption)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 3)
                                }
                            }
                        }
                    } else {
                        ContentUnavailableView("No preview yet", systemImage: "doc.text.magnifyingglass", description: Text("Validate the script, then inspect the complete change list."))
                    }
                    GroupBox("Script output and diagnostics") {
                        ScrollView { Text(output.isEmpty ? "Ready." : output).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
                            .frame(minHeight: 50, maxHeight: 110)
                            .font(.system(.caption, design: .monospaced))
                    }
                    GroupBox("Execution history") {
                        ScrollView { VStack(alignment: .leading, spacing: 5) {
                            if history.isEmpty { Text("No automation has run in this window.").foregroundStyle(.secondary) }
                            ForEach(Array(history.enumerated()), id: \.offset) { _, entry in Text(entry).frame(maxWidth: .infinity, alignment: .leading) }
                        }.font(.caption).frame(maxWidth: .infinity, alignment: .leading) }
                            .frame(minHeight: 38, maxHeight: 90)
                    }
                    HStack {
                        Button("Undo Automation", systemImage: "arrow.uturn.backward", action: undoAutomation)
                            .disabled(!canUndoAutomation)
                        Spacer()
                        Text("One approved run is grouped as one Undo action.").font(.caption2).foregroundStyle(.secondary)
                    }
                    if hasImageRecoveryCheckpoint {
                        Button("Restore Image Recovery Checkpoint", systemImage: "clock.arrow.circlepath",
                               action: restoreImageCheckpoint)
                            .buttonStyle(.bordered)
                        Text("A durable native-package checkpoint matches this saved manuscript state.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                .frame(width: 390)
                .frame(maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .alert("BOLD Script", isPresented: Binding(get: { fileError != nil }, set: { if !$0 { fileError = nil } })) {
            Button("OK") { fileError = nil }
        } message: { Text(fileError ?? "") }
        .task { hasImageRecoveryCheckpoint = document.hasFloatingImageRecoveryCheckpoint }
    }

    private func paste() {
        guard let value = NSPasteboard.general.string(forType: .string), !value.isEmpty else {
            diagnostics = "Error: Clipboard does not contain text."
            return
        }
        source = value
        resetPreview("Clipboard text loaded. Validate the script before previewing.")
    }

    private func openScript() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json, .plainText, UTType(filenameExtension: "boldscript") ?? .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { source = try String(contentsOf: url, encoding: .utf8); resetPreview("Loaded \(url.lastPathComponent). Validate before previewing.") }
        catch { fileError = "Could not read the script: \(error.localizedDescription)" }
    }

    private func saveScript() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "boldscript") ?? .json]
        panel.nameFieldStringValue = "Automation.boldscript"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try source.write(to: url, atomically: true, encoding: .utf8); output = "Saved \(url.lastPathComponent)." }
        catch { fileError = "Could not save the script: \(error.localizedDescription)" }
    }

    private func validate() {
        do {
            parsed = try BOLDScript.parse(source)
            plan = nil
            diagnostics = "Valid BOLD Script v1 · \(parsed!.operations.count) supported operation(s) · target is this document."
            output = "Validation passed. No document changes have been made."
        } catch {
            parsed = nil; plan = nil
            diagnostics = "Error: \(error.localizedDescription)"
            output = "Validation failed. No document changes were made."
        }
    }

    private func preview() {
        if parsed == nil { validate() }
        guard let script = parsed else { return }
        if let required = script.documentRevision, required != document.revisionID {
            plan = nil
            diagnostics = "Error: Document revision precondition failed. Recheck the target document and create a new preview."
            output = "Precondition failed. No document changes were made."
            return
        }
        do {
            let current = editor.textView?.attributedString() ?? document.text
            let result = try BOLDScriptEngine.plan(script, on: current, floatingImages: document.metadata.floatingImages ?? [])
            plan = result
            previewRevision = document.revisionID
            diagnostics = result.totalChanges == 0
                ? (result.imageInspection.isEmpty ? "Valid script; no matching content or formatting changes were found." : "Read-only image inspection ready · review properties in the preview. No document changes are proposed.")
                : "Preview ready · \(result.totalChanges) proposed edits · review the list, then approve Apply Changes."
            output = "Preview created from document revision \(document.revisionID.uuidString). The manuscript is unchanged."
        } catch {
            plan = nil; diagnostics = "Error: \(error.localizedDescription)"; output = "Preview rejected. The manuscript is unchanged."
        }
    }

    private func apply() {
        guard let script = parsed, let plan, previewRevision == document.revisionID else {
            diagnostics = "Error: The document changed after preview. Create a fresh preview before applying."
            return
        }
        let imagesChanged = document.metadata.floatingImages != (plan.floatingImages.isEmpty ? nil : plan.floatingImages)
        if imagesChanged {
            do { try document.createFloatingImageRecoveryCheckpoint() }
            catch {
                diagnostics = "Error: The image recovery checkpoint could not be saved. No changes were applied."
                output = error.localizedDescription
                return
            }
        }
        guard editor.applyBOLDScriptPlan(plan, title: script.title) else {
            diagnostics = "Error: The approved plan could not be committed. No partial script changes were applied."
            return
        }
        automationUndoActionName = "BOLD Script: \(script.title)"
        let summary = "\(Date.now.formatted(date: .omitted, time: .standard)) · \(script.title) · \(plan.totalChanges) changes"
        history.insert(summary, at: 0)
        history = Array(history.prefix(20))
        output = "Applied \(plan.totalChanges) change(s) as one Undo action. Save the document to persist the result."
        diagnostics = "Automation completed. Review the manuscript, then save or use Undo Automation."
        self.plan = nil
        parsed = nil
    }

    private func restoreImageCheckpoint() {
        do {
            guard try document.restoreFloatingImageRecoveryCheckpoint() else {
                diagnostics = "No matching image recovery checkpoint was found."
                return
            }
            plan = nil
            parsed = nil
            hasImageRecoveryCheckpoint = false
            output = "The saved native-package checkpoint was restored. Review the manuscript and save it as a new recovery copy."
            diagnostics = "Crash-recovery checkpoint restored."
        } catch {
            diagnostics = "Error: Could not restore the image recovery checkpoint: \(error.localizedDescription)"
        }
    }

    private func undoAutomation() {
        guard canUndoAutomation else { return }
        editor.textView?.undoManager?.undo()
        automationUndoActionName = nil
        output = "Undo applied. Review the restored manuscript and save if appropriate."
        diagnostics = "Automation was undone through the document's native Undo manager."
    }

    private func cancel() {
        plan = nil; parsed = nil
        diagnostics = "Operation cancelled. No changes were applied."
        output = diagnostics
    }

    private func resetPreview(_ message: String) { parsed = nil; plan = nil; diagnostics = message; output = "" }

    private var canUndoAutomation: Bool {
        guard let name = automationUndoActionName,
              let manager = editor.textView?.undoManager else { return false }
        return manager.canUndo && manager.undoActionName == name
    }

    private static let defaultScript = """
    {
      "format": "bold-script",
      "version": 1,
      "title": "Normalize chapter headings",
      "target": { "scope": "document" },
      "operations": [
        {
          "type": "normalizeHeadings",
          "rules": [
            { "paragraphPrefix": "Chapter ", "style": "Heading 1" }
          ]
        }
      ]
    }
    """
}

private struct BOLDScriptTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        let view = NSTextView()
        view.delegate = context.coordinator
        view.isRichText = false
        view.allowsUndo = true
        view.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        view.textContainerInset = NSSize(width: 12, height: 12)
        view.string = text
        view.backgroundColor = NSColor.textBackgroundColor
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        scroll.documentView = view
        context.coordinator.highlight(view)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView, view.string != text else { return }
        let selected = view.selectedRange()
        view.string = text
        view.setSelectedRange(NSRange(location: min(selected.location, (text as NSString).length), length: 0))
        context.coordinator.highlight(view)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        init(text: Binding<String>) { _text = text }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            text = view.string
            highlight(view)
        }
        func highlight(_ view: NSTextView) {
            guard let storage = view.textStorage else { return }
            let full = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: full)
            let patterns: [(String, NSColor)] = [
                (#""(?:\\.|[^"\\])*"(?=\s*:)"#, .systemPurple),
                (#""(?:\\.|[^"\\])*"(?!\s*:)"#, .systemRed),
                (#"\b(?:true|false|null)\b"#, .systemBlue),
                (#"\b\d+\b"#, .systemOrange)
            ]
            for (pattern, color) in patterns {
                guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
                for match in expression.matches(in: view.string, range: full) { storage.addAttribute(.foregroundColor, value: color, range: match.range) }
            }
            storage.endEditing()
        }
    }
}
