import AppKit
import Foundation

enum ManuscriptSearchScope: String, CaseIterable, Identifiable {
    case currentManuscript = "Current Manuscript"
    case currentChapter = "Current Chapter"
    case selectionAndLibrary = "Selected Paragraph + Library"
    case wholeLibrary = "Knowledge Library"
    case selectedLibraryDocument = "Selected Library Document"
    var id: String { rawValue }
}

struct ManuscriptEvidence: Identifiable, Equatable {
    enum Origin: Equatable {
        case liveManuscript(documentRevisionID: UUID, range: NSRange)
        case knowledgeLibrary(KnowledgePassageReference)
    }
    let id: String
    let title: String
    let location: String
    let excerpt: String
    let origin: Origin
    var verification: String
    var rank: Double
}

struct ManuscriptAnswer: Equatable {
    struct Claim: Equatable, Identifiable {
        let text: String
        let sourceIDs: [String]
        var id: String { text }
    }
    let claims: [Claim]
    let uncertainClaims: [String]
    var text: String { claims.map(\.text).joined(separator: "\n\n") }
    var sourceIDs: [String] { Array(Set(claims.flatMap(\.sourceIDs))).sorted() }
}

protocol ManuscriptAnswerProvider {
    var displayName: String { get }
    var isLocal: Bool { get }
    func answer(question: String, evidence: [ManuscriptEvidence]) async throws -> ManuscriptAnswer
}

enum ManuscriptAssistantError: LocalizedError {
    case emptyQuestion
    case noEvidence
    case providerUnavailable
    case staleSource(String)
    case missingSource(String)
    case invalidAnswer

    var errorDescription: String? {
        switch self {
        case .emptyQuestion: "Enter a question first."
        case .noEvidence: "No relevant passages were found in the selected scope. Try different wording or broaden the scope."
        case .providerUnavailable: "OpenAI is not configured. Add a key in Settings > AI."
        case .staleSource(let title): "The source ‘\(title)’ changed while the answer was being prepared. Search again to refresh its passages."
        case .missingSource(let title): "The source ‘\(title)’ is missing or cannot be read. Its passage was excluded."
        case .invalidAnswer: "The AI response did not match the retrieved source list. No citation was accepted."
        }
    }
}

@MainActor
final class ManuscriptRetrievalCoordinator {
    private let library: KnowledgeLibraryStore
    private let passageLimit: Int
    private let characterBudget: Int

    init(library: KnowledgeLibraryStore? = nil, passageLimit: Int = 12, characterBudget: Int = 18_000) {
        self.library = library ?? KnowledgeLibraryStore.shared
        self.passageLimit = max(1, passageLimit)
        self.characterBudget = max(1_000, characterBudget)
    }

    func retrieve(question: String, scope: ManuscriptSearchScope, document: BOLDWriterDocument,
                  editor: EditorController, selectedDocumentID: KnowledgeDocumentID? = nil) throws -> [ManuscriptEvidence] {
        let cleanQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuestion.isEmpty else { throw ManuscriptAssistantError.emptyQuestion }
        var candidates: [ManuscriptEvidence] = []
        if scope == .currentManuscript || scope == .currentChapter || scope == .selectionAndLibrary {
            candidates += livePassages(question: cleanQuestion, document: document, editor: editor,
                chapterOnly: scope == .currentChapter, includeSelection: scope == .selectionAndLibrary)
        }
        if scope == .wholeLibrary || scope == .selectedLibraryDocument || scope == .selectionAndLibrary {
            let id = scope == .selectedLibraryDocument ? selectedDocumentID : nil
            guard scope != .selectedLibraryDocument || id != nil else { return candidates }
            candidates += try libraryPassages(question: cleanQuestion, documentID: id)
        }
        // Comparison questions need distinct passages, including counterpoints. Multiple
        // query variants prevent an AND-only FTS query from hiding the other side.
        var seen = Set<String>()
        let ordered = candidates.sorted { $0.rank < $1.rank }.filter { seen.insert($0.id).inserted }
        var bounded: [ManuscriptEvidence] = []
        var used = 0
        for item in ordered {
            guard bounded.count < passageLimit else { break }
            let remaining = characterBudget - used
            guard remaining > 120 else { break }
            let excerpt = String(item.excerpt.prefix(remaining))
            bounded.append(ManuscriptEvidence(id: item.id, title: item.title, location: item.location,
                excerpt: excerpt, origin: item.origin, verification: item.verification, rank: item.rank))
            used += excerpt.count
        }
        return bounded
    }

    func validate(_ evidence: ManuscriptEvidence, document: BOLDWriterDocument) throws -> ManuscriptEvidence {
        switch evidence.origin {
        case .liveManuscript(let revision, let range):
            guard revision == document.revisionID else { throw ManuscriptAssistantError.staleSource(evidence.title) }
            let ns = document.text.string as NSString
            guard range.location >= 0, range.length >= 0, range.location <= ns.length, range.length <= ns.length - range.location else {
                throw ManuscriptAssistantError.staleSource(evidence.title)
            }
            return evidence
        case .knowledgeLibrary(let reference):
            let status = try library.resolve(reference).0
            guard status == .current || status == .revalidated else {
                throw status == .unresolved ? ManuscriptAssistantError.missingSource(evidence.title) : ManuscriptAssistantError.staleSource(evidence.title)
            }
            return ManuscriptEvidence(id: evidence.id, title: evidence.title, location: evidence.location,
                excerpt: evidence.excerpt, origin: evidence.origin, verification: status.rawValue, rank: evidence.rank)
        }
    }

    private func libraryPassages(question: String, documentID: KnowledgeDocumentID?) throws -> [ManuscriptEvidence] {
        var results: [KnowledgeSearchResult] = []
        let chapter = chapterContext(from: question)
        let searchQuestion = question.replacingOccurrences(of: #"(?i)\bchapter\s+\d+\b"#, with: "", options: .regularExpression)
        for query in queryVariants(searchQuestion) {
            results += try library.search(query, documentID: documentID, context: chapter, limit: 30)
        }
        var seen = Set<UUID>()
        return results.filter { seen.insert($0.reference.passageID).inserted }.map { result in
            ManuscriptEvidence(id: "lib-\(result.reference.passageID.uuidString)", title: result.document.title,
                location: result.reference.context, excerpt: result.excerpt, origin: .knowledgeLibrary(result.reference),
                verification: "pending verification", rank: result.rank)
        }
    }

    private func livePassages(question: String, document: BOLDWriterDocument, editor: EditorController, chapterOnly: Bool, includeSelection: Bool = false) -> [ManuscriptEvidence] {
        let attributed = document.text
        let string = attributed.string
        let ns = string as NSString
        guard ns.length > 0 else { return [] }
        let outline = DocumentAnalysis.outline(for: attributed)
        let selection = editor.selection
        let chapterRange = DocumentAnalysis.sectionRange(at: min(selection.location, ns.length), in: attributed)
        let queryTokens = tokens(question)
        guard !queryTokens.isEmpty else { return [] }
        var heading = "Opening"
        var paragraphs: [(NSRange, String)] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byParagraphs, .substringNotRequired]) { _, range, _, _ in
            if let item = outline.last(where: { $0.range.location <= range.location }) { heading = item.title }
            guard range.length > 0, (!chapterOnly || NSLocationInRange(range.location, chapterRange) || chapterRange.location == range.location) else { return }
            let text = ns.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { paragraphs.append((range, text)) }
        }
        var found = paragraphs.compactMap { range, text -> ManuscriptEvidence? in
            let bodyTokens = tokens(text)
            let hits = queryTokens.reduce(0) { $0 + (bodyTokens.contains($1) ? 1 : 0) }
            guard hits > 0 else { return nil }
            let title = "Current Manuscript"
            let context = heading
            return ManuscriptEvidence(id: "live-\(document.revisionID.uuidString)-\(range.location)", title: title,
                location: context, excerpt: text, origin: .liveManuscript(documentRevisionID: document.revisionID, range: range),
                verification: "current revision", rank: -Double(hits) - Double(text.count) / 100_000)
        }
        if includeSelection {
            let selectedRange = selection.length > 0 ? selection : DocumentAnalysis.paragraphRange(at: selection.location, in: string)
            if selectedRange.location >= 0, selectedRange.length > 0, selectedRange.location <= ns.length, selectedRange.length <= ns.length - selectedRange.location {
                let selectedText = ns.substring(with: selectedRange).trimmingCharacters(in: .whitespacesAndNewlines)
                if !selectedText.isEmpty {
                    let heading = outline.last(where: { $0.range.location <= selectedRange.location })?.title ?? "Selected paragraph"
                    let selected = ManuscriptEvidence(id: "selection-\(document.revisionID.uuidString)-\(selectedRange.location)", title: "Current Manuscript (selected)",
                        location: heading, excerpt: selectedText, origin: .liveManuscript(documentRevisionID: document.revisionID, range: selectedRange),
                        verification: "current revision", rank: -100)
                    found.insert(selected, at: 0)
                }
            }
        }
        return found
    }

    private func queryVariants(_ question: String) -> [String] {
        let terms = tokens(question).filter { $0.count > 2 }.sorted()
        var values = [question]
        if terms.count > 3 { values.append(terms.prefix(6).joined(separator: " ")) }
        if terms.count > 5 { values.append(terms.suffix(5).joined(separator: " ")) }
        // The canonical FTS API intentionally ANDs unquoted terms. Search each
        // meaningful term as a separate query so comparison questions can retrieve
        // distinct arguments that use different vocabulary.
        values += terms.prefix(8).map { $0 }
        return Array(NSOrderedSet(array: values)) as? [String] ?? values
    }
    private func chapterContext(from question: String) -> String? {
        guard let range = question.range(of: #"(?i)\bchapter\s+\d+\b"#, options: .regularExpression) else { return nil }
        return String(question[range]).capitalized
    }
    private func tokens(_ value: String) -> Set<String> {
        Set(value.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 1 })
    }
}

@MainActor
final class ManuscriptAssistantModel: ObservableObject {
    @Published var question = ""
    @Published var scope: ManuscriptSearchScope = .currentManuscript
    @Published var selectedDocumentID: KnowledgeDocumentID?
    @Published private(set) var evidence: [ManuscriptEvidence] = []
    @Published private(set) var answer: ManuscriptAnswer?
    @Published private(set) var isSearching = false
    @Published private(set) var isSending = false
    @Published var errorMessage: String?
    @Published private(set) var pendingApproval = false
    @Published private(set) var scopeSummary = ""
    private let retrieval: ManuscriptRetrievalCoordinator
    private var requestID = UUID()
    private var requestTask: Task<Void, Never>?

    init(retrieval: ManuscriptRetrievalCoordinator? = nil) { self.retrieval = retrieval ?? ManuscriptRetrievalCoordinator() }

    func search(document: BOLDWriterDocument, editor: EditorController) {
        cancel()
        requestID = UUID()
        let id = requestID
        isSearching = true; answer = nil; errorMessage = nil; pendingApproval = false
        requestTask = Task { [weak self] in
            guard let self else { return }
            do {
                await Task.yield()
                try Task.checkCancellation()
                let found = try self.retrieval.retrieve(question: self.question, scope: self.scope, document: document,
                    editor: editor, selectedDocumentID: self.selectedDocumentID)
                guard id == self.requestID, !Task.isCancelled else { return }
                self.evidence = found
                self.scopeSummary = "\(self.scope.rawValue) · \(found.count) passages · \(found.reduce(0) { $0 + $1.excerpt.count }) characters"
                if found.isEmpty { self.errorMessage = ManuscriptAssistantError.noEvidence.localizedDescription }
            } catch { if id == self.requestID { self.errorMessage = error.localizedDescription } }
            if id == self.requestID { self.isSearching = false }
        }
    }

    func prepareRemoteSend(document: BOLDWriterDocument) {
        do {
            guard !evidence.isEmpty else { throw ManuscriptAssistantError.noEvidence }
            evidence = try evidence.map { try retrieval.validate($0, document: document) }
            pendingApproval = true
            scopeSummary = "OpenAI (remote) · \(evidence.count) verified passages · \(evidence.reduce(0) { $0 + $1.excerpt.count }) characters. Only the question and passages shown below will leave this Mac."
        } catch { errorMessage = error.localizedDescription }
    }

    func sendApproved(document: BOLDWriterDocument, provider injected: ManuscriptAnswerProvider? = nil) {
        guard pendingApproval else { return }
        requestTask?.cancel()
        requestID = UUID()
        let id = requestID
        let questionCopy = question
        let evidenceCopy = evidence
        let provider: ManuscriptAnswerProvider
        if let injected { provider = injected }
        else if let key = try? KeychainService.shared.loadAPIKey(), !key.isEmpty {
            let model = UserDefaults.standard.string(forKey: "openAIModel") ?? "gpt-5.6"
            provider = OpenAIProvider(apiKey: key, model: model)
        } else { errorMessage = ManuscriptAssistantError.providerUnavailable.localizedDescription; return }
        pendingApproval = false; isSending = true; errorMessage = nil
        requestTask = Task { [weak self] in
            guard let self else { return }
            defer { if id == self.requestID { self.isSending = false } }
            do {
                let response = try await provider.answer(question: questionCopy, evidence: evidenceCopy)
                try Task.checkCancellation()
                guard id == self.requestID else { return }
                let allowed = Set(evidenceCopy.map(\.id))
                guard !response.claims.isEmpty,
                      response.claims.allSatisfy({ !$0.sourceIDs.isEmpty && $0.sourceIDs.allSatisfy(allowed.contains) }) else {
                    throw ManuscriptAssistantError.invalidAnswer
                }
                self.answer = response
            } catch { if id == self.requestID, !Task.isCancelled { self.errorMessage = error.localizedDescription } }
        }
    }

    func cancel() { requestTask?.cancel(); requestTask = nil; requestID = UUID(); isSearching = false; isSending = false; pendingApproval = false }
    func dismissApproval() { pendingApproval = false }
}
