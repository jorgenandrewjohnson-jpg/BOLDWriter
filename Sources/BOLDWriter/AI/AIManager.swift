import AppKit
import Foundation
import SwiftUI

@MainActor
final class AIManager: ObservableObject {
    @Published var command = ""
    @Published var scope: AIContextScope = .selection
    @Published var proposal: AIEditProposal?
    @Published var status = "AI editing is optional. BOLD Writer works without it."
    @Published var isWorking = false
    @Published var errorMessage: String?

    func makeContext(document: BOLDWriterDocument, editor: EditorController) -> AIContext {
        let string = document.text.string
        let ns = string as NSString
        let selection = validated(editor.selection, length: ns.length)
        let range: NSRange
        switch scope {
        case .selection:
            range = selection.length > 0 ? selection : DocumentAnalysis.paragraphRange(at: selection.location, in: string)
        case .paragraph:
            range = DocumentAnalysis.paragraphRange(at: selection.location, in: string)
        case .section:
            range = DocumentAnalysis.sectionRange(at: selection.location, in: document.text)
        case .document:
            range = NSRange(location: 0, length: ns.length)
        }
        let maximum = scope == .document ? 120_000 : 60_000
        let bounded = NSRange(location: range.location, length: min(range.length, maximum))
        let contextText = ns.substring(with: bounded)
        let preferences = UserDefaults.standard.string(forKey: "writingPreferences") ?? ""
        let terminologyRules = (document.metadata.manuscriptConsistencyRules ?? []).filter(\.enabled).map { rule in
            switch rule.kind {
            case .preferredTerm:
                return "Prefer ‘\(rule.replacement ?? rule.matchText)’ over ‘\(rule.matchText)’ when editing original prose. \(rule.explanation)"
            case .disallowedTerm:
                return "Avoid adding ‘\(rule.matchText)’ in original prose. \(rule.explanation)"
            case .capitalization:
                return "Preserve the author's capitalization rule for ‘\(rule.matchText)’ (preferred form: \(rule.replacement ?? "not specified")). \(rule.explanation)"
            }
        }
        var instructions = preferences
        if !terminologyRules.isEmpty {
            instructions += (instructions.isEmpty ? "" : "\n") + "Explicit manuscript rules: " + terminologyRules.joined(separator: "; ")
        }
        instructions += "\nDo not alter quotations, citations, or evidence references. Preserve the stated conclusion unless the author explicitly requests a change."
        return AIContext(
            scope: scope,
            range: bounded,
            text: contextText,
            outline: DocumentAnalysis.outline(for: document.text).map(\.title),
            instructions: instructions,
            documentRevisionID: document.revisionID
        )
    }

    func requestProposal(document: BOLDWriterDocument, editor: EditorController, provider injectedProvider: AIProvider? = nil) async {
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isWorking = true
        errorMessage = nil
        proposal = nil
        defer { isWorking = false }
        do {
            let context = makeContext(document: document, editor: editor)
            let requestedCaret = validated(editor.selection, length: document.text.length).location
            let requestedCommand = command
            let model = UserDefaults.standard.string(forKey: "openAIModel") ?? "gpt-5.6"
            let provider: AIProvider
            if let injectedProvider { provider = injectedProvider }
            else {
                guard let key = try KeychainService.shared.loadAPIKey(), !key.isEmpty else { throw AIProviderError.notConfigured }
                provider = OpenAIProvider(apiKey: key, model: model)
            }
            let response = try await provider.propose(command: requestedCommand, context: context)
            guard document.revisionID == context.documentRevisionID else {
                throw AIProviderError.service("The document changed while the AI was working. No proposal was applied; request a fresh preview to protect your newer writing.")
            }
            let targetRange = response.operation == .insertAtCursor ? NSRange(location: requestedCaret, length: 0) : context.range
            let original = response.operation == .insertAtCursor ? "" : context.text
            proposal = AIEditProposal(
                operation: response.operation,
                range: targetRange,
                originalText: original,
                replacementText: response.replacement,
                summary: response.summary,
                documentRevisionID: context.documentRevisionID
            )
            status = "Review the proposed change before applying it."
        } catch {
            errorMessage = error.localizedDescription
            status = "No changes were made."
        }
    }

    func applyProposal(document: BOLDWriterDocument, editor: EditorController) throws {
        guard let proposal else { return }
        guard proposal.documentRevisionID == document.revisionID else {
            throw AIProviderError.service("The document changed after this proposal was created. Request a fresh proposal so newer writing is not overwritten.")
        }
        let ns = document.text.string as NSString
        guard proposal.range.location >= 0, proposal.range.location <= ns.length,
              proposal.range.length >= 0, proposal.range.length <= ns.length - proposal.range.location,
              ns.substring(with: proposal.range) == proposal.originalText else {
            throw AIProviderError.service("The proposed range is stale. No change was applied.")
        }
        guard editor.textView != nil else { throw AIProviderError.service("The document editor is not ready. No changes were made.") }
        guard document.createRevision(named: "Before AI: \(proposal.summary)", kind: .aiSafety) else {
            throw AIProviderError.service("The safety recovery point could not be created, so the AI edit was cancelled.")
        }
        let baseAttributes: [NSAttributedString.Key: Any]
        if document.text.length > 0 {
            let at = min(proposal.range.location, document.text.length - 1)
            baseAttributes = document.text.attributes(at: at, effectiveRange: nil)
        } else {
            baseAttributes = [.font: NSFont.systemFont(ofSize: 15)]
        }
        editor.replace(
            range: proposal.range,
            with: NSAttributedString(
                string: proposal.replacementText,
                attributes: baseAttributes
            ),
            actionName: "AI Edit",
            trackChanges:
                document.metadata
                    .trackChangesEnabled
                    ?? false
        )
        self.proposal = nil
        status = "AI edit applied. Use Undo or restore the safety snapshot at any time."
    }

    func rejectProposal() {
        proposal = nil
        status = "Proposal rejected. The document was not changed."
    }

    private func validated(_ range: NSRange, length: Int) -> NSRange {
        let location = min(max(0, range.location), length)
        return NSRange(location: location, length: min(max(0, range.length), length - location))
    }
}
