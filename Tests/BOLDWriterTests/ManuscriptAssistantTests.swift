import AppKit
import XCTest
@testable import BOLDWriter

@MainActor
final class ManuscriptAssistantTests: XCTestCase {
    func testLiveManuscriptRetrievalFindsSeparateChaptersAndOpensVerifiedRevision() throws {
        let document = BOLDWriterDocument()
        let text = """
        Covenant and promise
        The New Covenant gives the people a new heart and promises forgiveness.

        Comparison
        The New Covenant is described as continuity with the earlier promise, while the people remain responsible for faithful practice.
        """
        document.replaceText(with: NSAttributedString(string: text))
        let editor = EditorController()
        editor.selection = NSRange(location: 0, length: 0)
        let retrieval = ManuscriptRetrievalCoordinator(library: KnowledgeLibraryStore(libraryURL: temporaryDirectory()))
        let passages = try retrieval.retrieve(question: "Compare the New Covenant promises and responsibilities", scope: .currentManuscript,
            document: document, editor: editor)
        XCTAssertGreaterThanOrEqual(passages.count, 2)
        XCTAssertTrue(passages.allSatisfy { $0.verification == "current revision" })
        XCTAssertTrue(passages.contains { $0.excerpt.contains("new heart") })
        let validated = try retrieval.validate(passages[0], document: document)
        XCTAssertEqual(validated.verification, "current revision")
    }

    func testLibraryScopeUsesCanonicalSearchAndRestrictsSelectedDocument() throws {
        let root = temporaryDirectory()
        let store = KnowledgeLibraryStore(libraryURL: root.appendingPathComponent("index"))
        let first = root.appendingPathComponent("Chapter 2 Notes.txt")
        let second = root.appendingPathComponent("Research Note.txt")
        try "The New Covenant promises forgiveness and a renewed heart.".write(to: first, atomically: true, encoding: .utf8)
        try "A challenge: covenant responsibility remains part of the argument.".write(to: second, atomically: true, encoding: .utf8)
        let firstID = try store.add(url: first)
        _ = try store.add(url: second)
        let doc = BOLDWriterDocument()
        doc.replaceText(with: NSAttributedString(string: "A local manuscript."))
        let retrieval = ManuscriptRetrievalCoordinator(library: store)
        let all = try retrieval.retrieve(question: "New Covenant promise responsibility", scope: .wholeLibrary, document: doc, editor: EditorController())
        XCTAssertGreaterThanOrEqual(Set(all.map(\.title)).count, 2)
        let onlyFirst = try retrieval.retrieve(question: "New Covenant promise responsibility", scope: .selectedLibraryDocument,
            document: doc, editor: EditorController(), selectedDocumentID: firstID)
        XCTAssertFalse(onlyFirst.isEmpty)
        XCTAssertTrue(onlyFirst.allSatisfy { $0.title == "Chapter 2 Notes" })
        XCTAssertTrue(onlyFirst.allSatisfy { if case .knowledgeLibrary = $0.origin { return true }; return false })

        let chapterDoc = root.appendingPathComponent("Chapter Book.md")
        try "# Chapter 6\nEarlier covenant wording.\n# Chapter 7\nThe New Covenant promises forgiveness.\n# Chapter 8\nLater discussion.".write(to: chapterDoc, atomically: true, encoding: .utf8)
        let chapterID = try store.add(url: chapterDoc)
        let comparisonDocument = BOLDWriterDocument()
        comparisonDocument.replaceText(with: NSAttributedString(string: "The selected paragraph argues for continuity and responsibility."))
        let comparisonEditor = EditorController(); comparisonEditor.selection = NSRange(location: 0, length: comparisonDocument.text.length)
        let comparison = try retrieval.retrieve(question: "Does this agree with chapter 7 New Covenant?", scope: .selectionAndLibrary,
            document: comparisonDocument, editor: comparisonEditor)
        XCTAssertTrue(comparison.contains { $0.title == "Current Manuscript (selected)" })
        XCTAssertTrue(comparison.contains { $0.title == "Chapter Book" && $0.location.contains("Chapter 7") })
        XCTAssertTrue(comparison.filter { $0.title == "Chapter Book" }.allSatisfy { if case .knowledgeLibrary(let ref) = $0.origin { return ref.documentID == chapterID }; return false })
    }

    func testContextBudgetBoundsRetrievedPassages() throws {
        let root = temporaryDirectory()
        let file = root.appendingPathComponent("Long Notes.txt")
        try String(repeating: "Covenant argument supports the conclusion. ", count: 500).write(to: file, atomically: true, encoding: .utf8)
        let store = KnowledgeLibraryStore(libraryURL: root.appendingPathComponent("index"))
        _ = try store.add(url: file)
        let doc = BOLDWriterDocument(); doc.replaceText(with: NSAttributedString(string: ""))
        let result = try ManuscriptRetrievalCoordinator(library: store, passageLimit: 50, characterBudget: 1_200)
            .retrieve(question: "covenant argument conclusion", scope: .wholeLibrary, document: doc, editor: EditorController())
        XCTAssertLessThanOrEqual(result.reduce(0) { $0 + $1.excerpt.count }, 1_200)
    }

    func testSyntheticTwentyNoteLibraryAndLongManuscriptProvideBroadCoverage() throws {
        let root = temporaryDirectory()
        let library = KnowledgeLibraryStore(libraryURL: root.appendingPathComponent("index"))
        let manuscript = root.appendingPathComponent("Long Manuscript.md")
        var chapters: [String] = []
        for chapter in 1...12 {
            chapters.append("## Chapter \(chapter)\nThe New Covenant \(chapter.isMultiple(of: 2) ? "promises forgiveness and a renewed heart" : "includes responsibility and faithful practice"). Discussion of the argument continues with naïve authoring and 日本語 Unicode.\n")
        }
        try chapters.joined(separator: "\n").write(to: manuscript, atomically: true, encoding: .utf8)
        _ = try library.add(url: manuscript)
        var mutableDocuments: [URL] = []
        for index in 1...20 {
            let url = root.appendingPathComponent("Research-\(index).md")
            let position = index.isMultiple(of: 2) ? "supports" : "challenges"
            try "# Research Note \(index)\nThis source \(position) the New Covenant argument with \(index.isMultiple(of: 2) ? "forgiveness evidence" : "responsibility evidence"). The New Covenant remains the repeated term.\nCafé, naïve, ἐν ἀρχῇ, and 日本語.".write(to: url, atomically: true, encoding: .utf8)
            _ = try library.add(url: url)
            mutableDocuments.append(url)
        }
        XCTAssertEqual(library.documents.count, 21)
        let comparison = try library.search("responsibility")
        XCTAssertGreaterThanOrEqual(comparison.count, 10)
        let earlier = try XCTUnwrap(library.search("forgiveness", documentID: library.documents.first(where: { $0.title == "Research-2" })?.id).first?.reference)
        let chapterHits = try library.search("New Covenant", documentID: library.documents.first(where: { $0.title == "Long Manuscript" })?.id)
        XCTAssertGreaterThanOrEqual(chapterHits.count, 12)
        try "# Research Note 2\nUpdated text about unrelated materials.".write(to: mutableDocuments[1], atomically: true, encoding: .utf8)
        let noteID = try XCTUnwrap(library.documents.first(where: { $0.title == "Research-2" })?.id)
        try library.refresh(documentID: noteID)
        XCTAssertEqual(try library.resolve(earlier).0, .stale)
    }

    func testAssistantRequiresExplicitApprovalAndRejectsManufacturedSourceIDs() async throws {
        let root = temporaryDirectory()
        let file = root.appendingPathComponent("Research.txt")
        try "New Covenant promises a renewed heart and forgiveness.".write(to: file, atomically: true, encoding: .utf8)
        let store = KnowledgeLibraryStore(libraryURL: root.appendingPathComponent("index"))
        _ = try store.add(url: file)
        let model = ManuscriptAssistantModel(retrieval: ManuscriptRetrievalCoordinator(library: store))
        model.scope = .wholeLibrary
        model.question = "What does the New Covenant promise?"
        let doc = BOLDWriterDocument(); doc.replaceText(with: NSAttributedString(string: "Current manuscript"))
        model.search(document: doc, editor: EditorController())
        for _ in 0..<20 where model.isSearching { await Task.yield() }
        XCTAssertFalse(model.evidence.isEmpty)
        XCTAssertNil(model.answer)
        XCTAssertFalse(model.pendingApproval)
        let provider = FixedAnswerProvider(sourceIDs: ["invented-source"])
        model.prepareRemoteSend(document: doc)
        XCTAssertTrue(model.pendingApproval)
        model.sendApproved(document: doc, provider: provider)
        for _ in 0..<20 where model.isSending { await Task.yield() }
        XCTAssertNil(model.answer)
        XCTAssertEqual(model.errorMessage, ManuscriptAssistantError.invalidAnswer.localizedDescription)
    }

    func testChangedLiveManuscriptReferenceCannotBeOpenedOrValidated() throws {
        let document = BOLDWriterDocument(); document.replaceText(with: NSAttributedString(string: "Covenant promise"))
        let retrieval = ManuscriptRetrievalCoordinator(library: KnowledgeLibraryStore(libraryURL: temporaryDirectory()))
        let evidence = try XCTUnwrap(retrieval.retrieve(question: "covenant promise", scope: .currentManuscript, document: document, editor: EditorController()).first)
        document.replaceText(with: NSAttributedString(string: "Revised, different text"))
        XCTAssertThrowsError(try retrieval.validate(evidence, document: document))
    }

    func testRejectingPrecisionEditLeavesManuscriptUnchanged() {
        let document = BOLDWriterDocument()
        document.replaceText(with: NSAttributedString(string: "Author's original conclusion."))
        let manager = AIManager()
        manager.proposal = AIEditProposal(operation: .replaceSelection, range: NSRange(location: 0, length: document.text.length),
            originalText: document.text.string, replacementText: "A changed conclusion.", summary: "Rewrite", documentRevisionID: document.revisionID)
        manager.rejectProposal()
        XCTAssertNil(manager.proposal)
        XCTAssertEqual(document.text.string, "Author's original conclusion.")
        XCTAssertTrue(document.metadata.revisions.isEmpty)
    }

    func testCanceledAnswerCannotOverwriteNewerSearchRequest() async throws {
        let root = temporaryDirectory()
        let file = root.appendingPathComponent("Two Arguments.txt")
        try "Forgiveness is promised to the people.\nResponsibility remains in the covenant argument.".write(to: file, atomically: true, encoding: .utf8)
        let store = KnowledgeLibraryStore(libraryURL: root.appendingPathComponent("index"))
        _ = try store.add(url: file)
        let document = BOLDWriterDocument(); document.replaceText(with: NSAttributedString(string: "The open manuscript."))
        let editor = EditorController()
        let model = ManuscriptAssistantModel(retrieval: ManuscriptRetrievalCoordinator(library: store))
        model.scope = .wholeLibrary
        model.question = "forgiveness"
        model.search(document: document, editor: editor)
        for _ in 0..<100 where model.isSearching { await Task.yield() }
        let firstSourceID = try XCTUnwrap(model.evidence.first?.id)
        model.prepareRemoteSend(document: document)
        let provider = SuspendedManuscriptProvider(sourceID: firstSourceID)
        model.sendApproved(document: document, provider: provider)
        await provider.waitUntilRequested()

        model.question = "responsibility"
        model.search(document: document, editor: editor)
        for _ in 0..<100 where model.isSearching { await Task.yield() }
        XCTAssertTrue(model.evidence.contains { $0.excerpt.localizedCaseInsensitiveContains("Responsibility") })
        await provider.resolve()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertNil(model.answer)
        XCTAssertTrue(model.evidence.contains { $0.excerpt.localizedCaseInsensitiveContains("Responsibility") })
    }

    private func temporaryDirectory() -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ManuscriptAssistant-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

private struct FixedAnswerProvider: ManuscriptAnswerProvider {
    let sourceIDs: [String]
    var displayName: String { "Deterministic mock" }
    var isLocal: Bool { true }
    func answer(question: String, evidence: [ManuscriptEvidence]) async throws -> ManuscriptAnswer {
        ManuscriptAnswer(claims: [ManuscriptAnswer.Claim(text: "Supported answer", sourceIDs: sourceIDs)], uncertainClaims: [])
    }
}

private actor SuspendedManuscriptProvider: ManuscriptAnswerProvider {
    nonisolated let displayName = "Suspended deterministic provider"
    nonisolated var isLocal: Bool { true }
    private let sourceID: String
    private var didReceiveRequest = false
    private var requestWaiter: CheckedContinuation<Void, Never>?
    private var resultContinuation: CheckedContinuation<ManuscriptAnswer, Never>?

    init(sourceID: String) { self.sourceID = sourceID }
    func answer(question: String, evidence: [ManuscriptEvidence]) async throws -> ManuscriptAnswer {
        didReceiveRequest = true
        requestWaiter?.resume()
        requestWaiter = nil
        return await withCheckedContinuation { resultContinuation = $0 }
    }
    func waitUntilRequested() async {
        if didReceiveRequest { return }
        await withCheckedContinuation { requestWaiter = $0 }
    }
    func resolve() {
        resultContinuation?.resume(returning: ManuscriptAnswer(
            claims: [.init(text: "An old answer", sourceIDs: [sourceID])], uncertainClaims: []))
        resultContinuation = nil
    }
}
