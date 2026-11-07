import AppKit
import Darwin
import SwiftUI

@main
struct BOLDWriterApp: App {
    init() {
#if !APP_STORE
        if let marker = CommandLine.arguments.firstIndex(of: "--acceptance-studio") {
            do {
                guard CommandLine.arguments.indices.contains(marker + 1) else {
                    throw BOLDCommandError.missingArgument("Studio acceptance request path")
                }
                try BookStudioAcceptance.run(requestURL: URL(fileURLWithPath: CommandLine.arguments[marker + 1]))
                Darwin.exit(0)
            } catch {
                fputs("BOLD_STUDIO_ACCEPTANCE_ERROR: \(error.localizedDescription)\n", stderr)
                Darwin.exit(2)
            }
        }
        if let marker = CommandLine.arguments.firstIndex(of: "--automation") {
            do {
                guard CommandLine.arguments.indices.contains(marker + 1) else {
                    throw BOLDCommandError.missingArgument("automation request JSON path")
                }
                try BookAutomationSession.run(requestURL: URL(fileURLWithPath: CommandLine.arguments[marker + 1]))
                Darwin.exit(0)
            } catch {
                fputs("BOLD_AUTOMATION_ERROR: \(error.localizedDescription)\n", stderr)
                Darwin.exit(2)
            }
        }
#endif
        UserDefaults.standard.register(defaults: [
            "defaultFont": "Helvetica",
            "defaultFontSize": 15.0,
            "openAIModel": "gpt-5.6",
            "writingPreferences": "Preserve my voice and intended meaning. Use clear, direct prose.",
            "speechRate": 0.48,
            "appearance": "System"
        ])
#if !APP_STORE
        if let marker = CommandLine.arguments.firstIndex(of: "--verify-release"), CommandLine.arguments.indices.contains(marker + 1) {
            do {
                try ReleaseDiagnostics.run(in: URL(fileURLWithPath: CommandLine.arguments[marker + 1], isDirectory: true))
                Darwin.exit(0)
            } catch {
                fputs("Release diagnostics failed: \(error.localizedDescription)\n", stderr)
                Darwin.exit(2)
            }
        }
        if let marker = CommandLine.arguments.firstIndex(of: "--generate-sample"), CommandLine.arguments.indices.contains(marker + 1) {
            let (text, metadata) = SampleDocumentFactory.make()
            let url = URL(fileURLWithPath: CommandLine.arguments[marker + 1])
            do {
                let wrapper = try BOLDWriterDocument.packageWrapper(text: text, metadata: metadata)
                try wrapper.write(to: url, options: .atomic, originalContentsURL: nil)
                print("Created sample at \(url.path)")
                Darwin.exit(0)
            } catch {
                fputs("Could not create sample: \(error.localizedDescription)\n", stderr)
                Darwin.exit(2)
            }
        }
#endif
    }

    var body: some Scene {
        DocumentGroup(newDocument: { BOLDWriterDocument() }) { configuration in
            DocumentView(document: configuration.document, sourceURL: configuration.fileURL)
        }
        .commands { BOLDWriterCommands(); KnowledgeLibraryCommands() }

        Window("Knowledge Library", id: "knowledge-library") {
            KnowledgeLibraryView()
        }
        .defaultSize(width: 1050, height: 700)

        Settings { SettingsView() }
    }
}

private struct KnowledgeLibraryCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Knowledge Library") { openWindow(id: "knowledge-library") }
                .keyboardShortcut("k", modifiers: [.command, .shift])
        }
    }
}


private struct BOLDReviewAndInsertCommands: Commands {
    @FocusedValue(\.documentActions) private var actions

    var body: some Commands {
        CommandMenu("Review") {
            Button("New Comment") { actions?.newComment() }
                .keyboardShortcut("m", modifiers: [.command, .option])
            Button("Edit Comment") { actions?.editComment() }
            Button("Delete Comment") { actions?.deleteComment() }
            Button("Previous Comment") { actions?.previousComment() }
            Button("Next Comment") { actions?.nextComment() }
            Button("Show Comments") { actions?.showComments() }

            Divider()

            Button(
                "Previous Change"
            ) {
                actions?.previousChange()
            }
            .keyboardShortcut(
                "[",
                modifiers: [
                    .command,
                    .option
                ]
            )

            Button(
                "Next Change"
            ) {
                actions?.nextChange()
            }
            .keyboardShortcut(
                "]",
                modifiers: [
                    .command,
                    .option
                ]
            )

            Divider()

            Button(
                "Accept Change"
            ) {
                actions?.acceptChange()
            }

            Button(
                "Reject Change"
            ) {
                actions?.rejectChange()
            }

            Divider()

            Button(
                "Accept All Changes"
            ) {
                actions?.acceptAllChanges()
            }

            Button(
                "Reject All Changes"
            ) {
                actions?.rejectAllChanges()
            }
        }

        CommandMenu("Insert") {
            Button("Page Break") { actions?.insertPageBreak() }.keyboardShortcut(.return, modifiers: [.command])
                .disabled(actions?.canEdit != true)
            Button("Footnote") { actions?.insertFootnote() }.keyboardShortcut("f", modifiers: [.command, .option])
                .disabled(actions?.canEdit != true)
            Button("Edit Selected Footnote…") { actions?.editFootnote() }
            Button("Endnote") { actions?.insertEndnote() }.keyboardShortcut("d", modifiers: [.command, .option])
                .disabled(actions?.canEdit != true)
            Button("Edit Selected Endnote…") { actions?.editEndnote() }
            Divider()
            Button("Equation") { actions?.showEquationToolbar() }.disabled(actions?.canEdit != true)
            Button("Table") { actions?.insertTable() }.disabled(actions?.canEdit != true)
            Button("Image…") { actions?.insertImage() }.disabled(actions?.canEdit != true)
            Button("Link…") { actions?.insertLink() }.keyboardShortcut("k", modifiers: [.command])
                .disabled(actions?.canEdit != true)
            Button("Horizontal Rule") { actions?.insertRule() }.disabled(actions?.canEdit != true)
            Button("Table of Contents") { actions?.insertTOC() }.disabled(actions?.canEdit != true)
            Button("Bookmark") { actions?.addBookmark() }.disabled(actions?.canEdit != true)
        }
    }
}

struct BOLDWriterCommands: Commands {
    @FocusedValue(\.documentActions) private var actions
    @FocusedValue(\.coverWorkspaceMenus) private var cover
    @FocusedValue(\.studioUndoActions) private var studioUndo
    var body: some Commands {
        CommandGroup(after: .saveItem) {
            Button("Import Manuscript into This Project…") { actions?.importManuscript() }
                .disabled(actions?.canEdit != true)
            Divider()
            Button("Save Version") { actions?.saveVersion() }.keyboardShortcut("s", modifiers: [.command, .option])
            Divider()
            Button("Export…") { actions?.showExport() }.keyboardShortcut("e", modifiers: [.command, .shift])
            Button("Prepare for Kindle…") { actions?.showKindle() }
            Button("Print…") { actions?.printDocument() }.keyboardShortcut("p")
        }
        CommandGroup(
            replacing:
                .undoRedo
        ) {
            Button(
                "Undo"
            ) {
                if let studioUndo { studioUndo.undo() }
                else if let cover { cover.undo() }
                else {
                    // Let AppKit route the command to the active responder. In
                    // a paginated manuscript each page view shares the same
                    // session manager, but EditorController.textView may still
                    // point at the page that was active before a reflow. Using
                    // the responder chain also preserves native undo behavior
                    // for focused inspector fields and Automation Studio.
                    let focusedManager = NSApp.keyWindow?.firstResponder?.undoManager
                    if let focusedManager, focusedManager.canUndo { focusedManager.undo() }
                    else { actions?.undo() }
                }
            }
            .keyboardShortcut(
                "z",
                modifiers: [
                    .command
                ]
            )

            Button(
                "Redo"
            ) {
                if let studioUndo { studioUndo.redo() }
                else if let cover { cover.redo() }
                else {
                    let focusedManager = NSApp.keyWindow?.firstResponder?.undoManager
                    if let focusedManager, focusedManager.canRedo { focusedManager.redo() }
                    else { actions?.redo() }
                }
            }
            .keyboardShortcut(
                "z",
                modifiers: [
                    .command,
                    .shift
                ]
            )

            Divider()

            Button(
                "Paste Without Formatting"
            ) {
                NSApp.sendAction(
                    #selector(
                        WritingTextView
                            .pasteWithoutFormatting(_:)
                    ),
                    to:
                        nil,
                    from:
                        nil
                )
            }
            .keyboardShortcut(
                "v",
                modifiers: [
                    .command,
                    .shift
                ]
            )

            Divider()

            Button("Find…") {
                actions?.showFindReplace()
            }
            .keyboardShortcut(
                "f",
                modifiers: [
                    .command
                ]
            )

            Button(
                "Find and Replace…"
            ) {
                actions?.showFindReplace()
            }
            .keyboardShortcut(
                "h",
                modifiers: [
                    .command,
                    .option
                ]
            )

            Divider()

            Button(
                "Command Palette…"
            ) {
                actions?
                    .showPalette()
            }
            .keyboardShortcut(
                "p",
                modifiers: [
                    .command,
                    .shift
                ]
            )
        }
        CommandGroup(after: .sidebar) {
            Button("Full Screen") {
                actions?.toggleFullScreen()
            }
            .keyboardShortcut(
                "f",
                modifiers: [
                    .command,
                    .control
                ]
            )

            Divider()

            Button("Toggle Navigation Sidebar") { actions?.toggleLeft() }.keyboardShortcut("1", modifiers: [.command, .control])
            Button("Toggle Inspector") { actions?.toggleRight() }.keyboardShortcut("2", modifiers: [.command, .control])
            Button("Print Layout / Continuous") { actions?.togglePrintLayout() }.keyboardShortcut("l", modifiers: [.command, .option])

            Menu("Mode") {
                Button("Editing") {
                    actions?.setEditingMode(.editing)
                }

                Button("Suggesting") {
                    actions?.setEditingMode(.suggesting)
                }

                Button("Viewing") {
                    actions?.setEditingMode(.viewing)
                }
            }

            Button("Show Equation Toolbar") { actions?.showEquationToolbar() }
            Button("Show Non-Printing Characters") { actions?.toggleNonPrintingCharacters() }
                .keyboardShortcut("8", modifiers: [.command])
            Button("Focus Mode") { actions?.toggleFocus() }.keyboardShortcut("f", modifiers: [.command, .shift])
            Divider()
            Button("3D Book Preview") { actions?.showPhysicalBookPreview() }
                .keyboardShortcut("3", modifiers: [.command, .option, .shift])
        }
        BOLDCombinedWorkspaceCommands()
        CommandMenu("Table") {
            Button("Insert Table…") { actions?.insertTable() }
            Divider()
            Button("Add Row Below") { actions?.tableAction("addRow") }
            Button("Delete Row") { actions?.tableAction("deleteRow") }
            Button("Add Column After") { actions?.tableAction("addColumn") }
            Button("Delete Column") { actions?.tableAction("deleteColumn") }
            Divider()
            Button("Toggle First Row as Header") { actions?.tableAction("header") }
            Button("Widen Column") { actions?.tableAction("wider") }
            Button("Narrow Column") { actions?.tableAction("narrower") }
            Divider()
            Button("Delete Table") { actions?.tableAction("deleteTable") }
        }
        CommandMenu("Format") {
            Button("Bold") { actions?.toggleBold() }.keyboardShortcut("b", modifiers: [.command])
                .disabled(actions?.canEdit != true)
            Button("Italic") { actions?.toggleItalic() }.keyboardShortcut("i", modifiers: [.command])
                .disabled(actions?.canEdit != true)
            Button("Underline") { actions?.toggleUnderline() }.keyboardShortcut("u", modifiers: [.command])
                .disabled(actions?.canEdit != true)
            Divider()
            Menu("Paragraph Style") {
                Button("Normal Text") { actions?.applyParagraphStyle(.normal) }.keyboardShortcut("0", modifiers: [.command, .option])
                Button("Title") { actions?.applyParagraphStyle(.title) }
                Button("Subtitle") { actions?.applyParagraphStyle(.subtitle) }
                Divider()
                Button("Heading 1") { actions?.applyParagraphStyle(.heading1) }.keyboardShortcut("1", modifiers: [.command, .option])
                Button("Heading 2") { actions?.applyParagraphStyle(.heading2) }.keyboardShortcut("2", modifiers: [.command, .option])
                Button("Heading 3") { actions?.applyParagraphStyle(.heading3) }.keyboardShortcut("3", modifiers: [.command, .option])
                Button("Heading 4") { actions?.applyParagraphStyle(.heading4) }.keyboardShortcut("4", modifiers: [.command, .option])
                Button("Heading 5") { actions?.applyParagraphStyle(.heading5) }.keyboardShortcut("5", modifiers: [.command, .option])
                Button("Heading 6") { actions?.applyParagraphStyle(.heading6) }.keyboardShortcut("6", modifiers: [.command, .option])
            }
            .disabled(actions?.canEdit != true)
            Button("Bulleted List") { actions?.toggleBulletedList() }.keyboardShortcut("8", modifiers: [.command, .shift])
                .disabled(actions?.canEdit != true)
            Button("Numbered List") { actions?.toggleNumberedList() }.keyboardShortcut("7", modifiers: [.command, .shift])
                .disabled(actions?.canEdit != true)
            Button("Checklist") { actions?.toggleChecklist() }
                .disabled(actions?.canEdit != true)
            Button("Toggle Checklist Item") { actions?.toggleChecklistItem() }
                .disabled(actions?.canEdit != true)
            Button("Increase Indent") { actions?.increaseIndent() }.keyboardShortcut("]", modifiers: [.command])
                .disabled(actions?.canEdit != true)
            Button("Decrease Indent") { actions?.decreaseIndent() }.keyboardShortcut("[", modifiers: [.command])
                .disabled(actions?.canEdit != true)
            Button("Clear Formatting") { actions?.clearFormatting() }.keyboardShortcut("\\", modifiers: [.command])
                .disabled(actions?.canEdit != true)
            Menu("Text Direction") {
                Button("Left to Right") { actions?.setTextDirection(.leftToRight) }
                Button("Right to Left") { actions?.setTextDirection(.rightToLeft) }
            }
            .disabled(actions?.canEdit != true)
            Divider()
            Button("Show Fonts") { NSApp.sendAction(#selector(NSFontManager.orderFrontFontPanel(_:)), to: nil, from: nil) }.keyboardShortcut("t", modifiers: [.command])
            Button("Show Colors") { NSColorPanel.shared.orderFront(nil) }.keyboardShortcut("c", modifiers: [.command, .shift])
            Button("Show Ruler") { actions?.toggleRuler() }
        }
        CommandMenu("Layout") {
            Button("Toggle Print Layout") { actions?.togglePrintLayout() }
            Button("Insert Page Break") { actions?.insertPageBreak() }
        }
        CommandMenu("Tools") {
            Menu("Spelling and Grammar") {
                Button("Check Spelling") {
                    actions?.checkSpelling()
                }

                Button("Show Spelling and Grammar") {
                    actions?.showSpellingAndGrammar()
                }

                Divider()

                Button("Toggle Continuous Spell Checking") {
                    actions?.toggleContinuousSpelling()
                }

                Button("Toggle Grammar Checking") {
                    actions?.toggleGrammarChecking()
                }
            }

            Divider()

            Button("Line Numbers") { actions?.toggleLineNumbers() }
            Button("Compare Documents…") { actions?.compareDocuments() }
            Button("Translate Document…") { actions?.translateDocument() }
            Button("Dictionary") { actions?.lookUpDictionary() }
            Button("Voice Typing…") { actions?.voiceTyping() }
            Button("Citations…") { actions?.showCitations() }

            Button("Word Count…") {
                actions?.showWordCount()
            }
            .keyboardShortcut(
                "c",
                modifiers: [
                    .command,
                    .shift
                ]
            )

            Divider()
            Button("Read From Cursor") { actions?.readFromCursor() }.keyboardShortcut("r", modifiers: [.command, .option])
            Button("Stop Reading") { actions?.stopReading() }
            Button("Command Palette…") { actions?.showPalette() }
        }
        CommandMenu("AI") {
            Button("Show AI Assistant") { actions?.toggleRight() }.keyboardShortcut("a", modifiers: [.command, .shift])
            SettingsLink { Text("AI Settings…") }
        }
        CommandGroup(replacing: .help) {
            Button("BOLD Writer Help") { actions?.showHelp() }.keyboardShortcut("?", modifiers: [.command])
        }
    }
}

private struct BOLDCombinedWorkspaceCommands: Commands {
    var body: some Commands {
        BOLDReviewAndInsertCommands()
        CoverWorkspaceCommands()
    }
}
