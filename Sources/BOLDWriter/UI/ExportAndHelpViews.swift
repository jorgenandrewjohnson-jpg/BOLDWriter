import AppKit
import SwiftUI

struct ExportView: View {
    @ObservedObject var document: BOLDWriterDocument
    @Environment(\.dismiss) private var dismiss
    @State private var format: ExportFormat = .pdf
    @State private var message: String?
    var kindleMode = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(kindleMode ? "Prepare for Kindle" : "Export Document").font(.title2.bold())
            Text(kindleMode ? "BOLD Writer prepares a standards-based file you can share, email, reveal in Finder, or upload using Amazon's public Send to Kindle page." : "Exports are written atomically so a failed export cannot overwrite the only good copy.")
                .foregroundStyle(.secondary)
            Picker("Format", selection: $format) {
                ForEach(kindleMode ? [ExportFormat.epub, .docx, .pdf] : ExportFormat.allCases) { Text($0.rawValue).tag($0) }
            }
            if format == .docx {
                Text("DOCX preserves editable text, named paragraph styles, structured tables, inline images, real footnotes and endnotes, and native Word comments, bookmarks, and hyperlinks. Footnote text uses plain formatting. Global page setup and default headers/footers round-trip; advanced multi-section layout may still vary.").font(.caption).foregroundStyle(.secondary)
            }
            if format == .pdf {
                Text("Footnotes and endnotes are collected in numbered sections at the end of the document.").font(.caption).foregroundStyle(.secondary)
            }
            if format == .epub {
                Text("This format preserves common text formatting. Footnotes and endnotes are exported as linked EPUB note sections. Images, comments, and advanced layout are not included. Keep your native manuscript and inspect the exported file.").font(.caption).foregroundStyle(.secondary)
            }
            if let message { Text(message).foregroundStyle(message.hasPrefix("Exported") ? .green : .red) }
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                if kindleMode {
                    Button("Open Send to Kindle") {
                        NSWorkspace.shared.open(URL(string: "https://www.amazon.com/sendtokindle")!)
                    }
                }
                Button(kindleMode ? "Prepare File…" : "Export…") { export() }.buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(width: 520)
    }

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(document.metadata.title.isEmpty ? "Untitled" : document.metadata.title).\(format.extensionName)"
        panel.allowedContentTypes = [
            format.contentType
        ]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let exportedURL =
                try ExportService.write(
                    format,
                    document: document,
                    to: url
                )
            message = "Exported to \(exportedURL.path)"
            NSWorkspace.shared.activateFileViewerSelecting([exportedURL])
        } catch {
            message = "Export failed: \(error.localizedDescription)"
        }
    }
}

struct WelcomeView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var showHelp: Bool
    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "text.book.closed.fill").font(.system(size: 58)).foregroundStyle(.white).padding(22)
                .background(RoundedRectangle(cornerRadius: 24).fill(LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)))
            Text("Welcome to BOLD Writer").font(.largeTitle.bold())
            Text("A focused home for books, papers, and long manuscripts.").font(.title3).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("Create New Document") { dismiss() }.buttonStyle(.borderedProminent)
                Button("Open Document") { dismiss(); NSDocumentController.shared.openDocument(nil) }
                Button("Open Word Document") { dismiss(); NSDocumentController.shared.openDocument(nil) }
                Button("Learn BOLD Writer") { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showHelp = true } }
            }
            HStack(spacing: 24) {
                Label("AI Assistant — optional", systemImage: "sparkles")
                Label("Read Aloud — included", systemImage: "speaker.wave.2")
            }.foregroundStyle(.secondary)
        }.padding(36).frame(minWidth: 720, minHeight: 420)
    }
}

struct HelpView: View {
    private let topics: [(String, String)] = [
        ("Getting Started", "Create a document and begin typing. Save in the native .boldwriter package format to preserve BOLD Writer metadata and recovery points."),
        ("Writing", "Use Continuous mode for flow or Print Layout to work with margins and page dimensions. Native undo, spell checking, grammar checking, dictation, and text services remain available."),
        ("Formatting", "Select text and use the toolbar for emphasis, type size, alignment, color, highlighting, and named paragraph styles."),
        ("Opening Word Documents", "Open common DOCX content directly. Advanced Word-only layout, macros, tracked changes, and complex floating objects may not import perfectly."),
        ("Exporting", "Export PDF, DOCX, RTF, HTML, Markdown, text, or EPUB. Exports never replace your native manuscript unless you explicitly choose the same destination."),
        ("Read Aloud", "Choose selection, paragraph, cursor, or full document. Playback uses installed macOS voices and does not require an account."),
        ("AI Assistant", "AI is optional. Choose a scope, enter an instruction, review the removed and added text, then Apply or Reject."),
        ("Undoing AI Changes", "Every applied AI edit uses the native undo manager and first creates a recovery point in History."),
        ("Sending to Kindle", "Prepare an EPUB, DOCX, or PDF, then use Share or Amazon's public Send to Kindle page. BOLD Writer does not use private Amazon APIs."),
        ("Keyboard Shortcuts", "⌘S Save · ⌘Z Undo · ⇧⌘Z Redo · ⇧⌘V Paste Without Formatting · ⌘F Find · ⇧⌘P Command Palette · ⌥⌘R Read From Cursor"),
        ("Backing Up Documents", "Keep your .boldwriter file in a backed-up folder and create named recovery points before structural edits."),
        ("Privacy", "Local editing and native Read Aloud stay on your Mac. Text is sent to OpenAI only when you deliberately request an AI action, and only for the displayed scope.")
    ]
    var body: some View {
        NavigationSplitView {
            List(topics, id: \.0) { topic in NavigationLink(topic.0, value: topic.0) }
                .navigationDestination(for: String.self) { name in
                    if let topic = topics.first(where: { $0.0 == name }) {
                        VStack(alignment: .leading, spacing: 12) { Text(topic.0).font(.title.bold()); Text(topic.1).font(.body) }.padding(28)
                    }
                }
        } detail: {
            ContentUnavailableView("BOLD Writer Help", systemImage: "questionmark.circle", description: Text("Choose a topic."))
        }.frame(minWidth: 700, minHeight: 500)
    }
}
