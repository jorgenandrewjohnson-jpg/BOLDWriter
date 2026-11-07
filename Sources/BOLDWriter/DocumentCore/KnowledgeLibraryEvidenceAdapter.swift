import AppKit
import CryptoKit
import Foundation

struct EvidenceLibraryPassageOption: Identifiable, Equatable {
    let reference: KnowledgePassageReference
    let excerpt: String
    var id: UUID { reference.passageID }
}

enum KnowledgeLibraryEvidenceError: LocalizedError {
    case missingLocalSource
    case sourceUnavailable
    case sourceNotIndexed
    case externalReferenceOnly
    case noExactPassage
    case invalidReference
    case changedBeforeNavigation

    var errorDescription: String? {
        switch self {
        case .missingLocalSource: "Choose a local source file before adding it to the Knowledge Library."
        case .sourceUnavailable: "The source file is unavailable or cannot be read."
        case .sourceNotIndexed: "This source is not in the Knowledge Library yet. Add it from Evidence first."
        case .externalReferenceOnly: "This library item has no local searchable source. Its quotation cannot be verified here."
        case .noExactPassage: "No exact quotation was found in a current passage for this source."
        case .invalidReference: "The saved Knowledge Library passage reference is invalid."
        case .changedBeforeNavigation: "The source changed and the saved passage no longer resolves. Review the source and link a passage again."
        }
    }
}

/// Bridges evidence records to the canonical Knowledge Library identities.
/// It never owns a second index and only indexes files after an explicit author action.
@MainActor final class KnowledgeLibraryEvidenceAdapter: EvidenceLibraryReferenceResolving {
    private let store: KnowledgeLibraryStore

    init(store: KnowledgeLibraryStore? = nil) { self.store = store ?? .shared }

    @discardableResult
    func addOrFindSelectedSource(_ source: CitationSource) throws -> KnowledgeDocumentRecord {
        if let url = EvidenceVerification.resolvedLocalURL(for: source) {
            guard url.path.rangeOfCharacter(from: .controlCharacters) == nil,
                  FileManager.default.fileExists(atPath: url.path) else { throw KnowledgeLibraryEvidenceError.sourceUnavailable }
            if let record = store.documents.first(where: { Self.sameLocalSource($0.sourceURI, url: url) }) {
                if !record.isReference, record.status != .available { try store.refresh(documentID: record.id) }
                return try document(record.id)
            }
            let id = try store.add(url: url)
            return try document(id)
        }

        guard !source.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw KnowledgeLibraryEvidenceError.missingLocalSource
        }
        guard let match = store.documents.first(where: { Self.sameURI($0.sourceURI, source.url) }) else {
            throw KnowledgeLibraryEvidenceError.sourceNotIndexed
        }
        return match
    }

    func exactPassages(for source: CitationSource, quotation: String) throws -> [EvidenceLibraryPassageOption] {
        let quote = Self.normalized(quotation)
        guard !quote.isEmpty else { throw KnowledgeLibraryEvidenceError.noExactPassage }
        let record = try addOrFindSelectedSource(source)
        guard !record.isReference else { throw KnowledgeLibraryEvidenceError.externalReferenceOnly }
        try store.refresh(documentID: record.id) // force a content fingerprint check before trusting offsets
        let current = try document(record.id)
        guard current.status == .available, let url = try store.sourceURL(for: record.id) else {
            throw KnowledgeLibraryEvidenceError.sourceUnavailable
        }
        let text = try Self.loadText(at: url)
        let query = "\"\(quotation.replacingOccurrences(of: "\"", with: "\"\""))\""
        let results = try store.search(query, documentID: record.id, limit: 1000)
        return results.compactMap { result in
            guard result.reference.fingerprint == current.fingerprint,
                  Self.contains(quote, in: Self.substring(text, range: result.reference.utf16Range)),
                  Self.signatureMatches(result.reference, in: text) else { return nil }
            return EvidenceLibraryPassageOption(reference: result.reference, excerpt: result.excerpt)
        }
    }

    func serializedReference(for option: EvidenceLibraryPassageOption) throws -> Data {
        try JSONEncoder().encode(option.reference)
    }

    func resolve(_ serializedReference: Data, exactQuotation: String, revalidateDisk: Bool = false) -> EvidenceLibraryReferenceResolution {
        guard let reference = try? JSONDecoder().decode(KnowledgePassageReference.self, from: serializedReference) else {
            return EvidenceLibraryReferenceResolution(status: .unresolved, verifiedLocation: nil)
        }
        do {
            guard let record = store.documents.first(where: { $0.id == reference.documentID }), !record.isReference else {
                return EvidenceLibraryReferenceResolution(status: .unresolved, verifiedLocation: nil)
            }
            if revalidateDisk { try store.refresh(documentID: reference.documentID) }
            let (status, range) = try store.resolve(reference)
            guard status == .current || status == .revalidated, let range,
                  let url = try store.sourceURL(for: reference.documentID),
                  let text = try? Self.loadText(at: url),
                  let freshRecord = store.documents.first(where: { $0.id == reference.documentID }),
                  let digest = try? Self.fileSHA256(url), digest == freshRecord.fingerprint else {
                return EvidenceLibraryReferenceResolution(status: Self.evidenceStatus(status), verifiedLocation: nil)
            }
            guard let current = try currentResult(for: reference, quotation: exactQuotation, range: range, text: text, documentFingerprint: freshRecord.fingerprint) else {
                return EvidenceLibraryReferenceResolution(status: .stale, verifiedLocation: nil)
            }
            return EvidenceLibraryReferenceResolution(
                status: Self.evidenceStatus(status),
                verifiedLocation: "\(current.reference.context) · UTF-16 location \(range.location)"
            )
        } catch {
            return EvidenceLibraryReferenceResolution(status: .unresolved, verifiedLocation: nil)
        }
    }

    func openPassage(_ serializedReference: Data, exactQuotation: String, onError: @escaping (String) -> Void) -> EvidenceLibraryReferenceResolution {
        guard let reference = try? JSONDecoder().decode(KnowledgePassageReference.self, from: serializedReference) else {
            return EvidenceLibraryReferenceResolution(status: .unresolved, verifiedLocation: nil)
        }
        do {
            guard let originalRecord = store.documents.first(where: { $0.id == reference.documentID }), !originalRecord.isReference else {
                return EvidenceLibraryReferenceResolution(status: .unresolved, verifiedLocation: nil)
            }
            try store.refresh(documentID: reference.documentID)
            let (status, range) = try store.resolve(reference)
            guard (status == .current || status == .revalidated), let range,
                  let currentRecord = store.documents.first(where: { $0.id == reference.documentID }),
                  let url = try store.sourceURL(for: reference.documentID),
                  let text = try? Self.loadText(at: url),
                  try Self.fileSHA256(url) == currentRecord.fingerprint else {
                return EvidenceLibraryReferenceResolution(status: Self.evidenceStatus(status), verifiedLocation: nil)
            }
            guard let current = try currentResult(for: reference, quotation: exactQuotation, range: range, text: text, documentFingerprint: currentRecord.fingerprint) else {
                return EvidenceLibraryReferenceResolution(status: .stale, verifiedLocation: nil)
            }
            let scoped = url.startAccessingSecurityScopedResource()
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                if let error { onError(error.localizedDescription); return }
                NotificationCenter.default.post(name: .knowledgeLibraryNavigate, object: nil, userInfo: [
                    "location": current.reference.utf16Range.location,
                    "length": current.reference.utf16Range.length,
                    "fingerprint": current.reference.fingerprint,
                    "source": current.document.sourceURI
                ])
            }
            return EvidenceLibraryReferenceResolution(status: Self.evidenceStatus(status), verifiedLocation: "\(current.reference.context) · UTF-16 location \(range.location)")
        } catch {
            onError(error.localizedDescription)
            return EvidenceLibraryReferenceResolution(status: .unresolved, verifiedLocation: nil)
        }
    }

    // Compatibility implementation for the narrow pre-library contract.
    func passageReference(for source: CitationSource, exactQuotation: String) -> EvidenceLibraryPassageLink? {
        guard let option = (try? exactPassages(for: source, quotation: exactQuotation))?.first,
              let bytes = try? serializedReference(for: option) else { return nil }
        return EvidenceLibraryPassageLink(documentReference: option.reference.documentID.rawValue.uuidString, passageReference: bytes)
    }

    func resolve(_ serializedReference: Data) -> EvidenceLibraryReferenceResolution {
        guard let reference = try? JSONDecoder().decode(KnowledgePassageReference.self, from: serializedReference) else {
            return EvidenceLibraryReferenceResolution(status: .unresolved, verifiedLocation: nil)
        }
        do {
            let (status, range) = try store.resolve(reference)
            return EvidenceLibraryReferenceResolution(status: Self.evidenceStatus(status), verifiedLocation: range.map { "\(reference.context) · UTF-16 location \($0.location)" })
        } catch {
            return EvidenceLibraryReferenceResolution(status: .unresolved, verifiedLocation: nil)
        }
    }

    private func document(_ id: KnowledgeDocumentID) throws -> KnowledgeDocumentRecord {
        guard let value = store.documents.first(where: { $0.id == id }) else { throw KnowledgeLibraryEvidenceError.sourceUnavailable }
        return value
    }

    private func currentResult(for original: KnowledgePassageReference, quotation: String, range: NSRange, text: String, documentFingerprint: String) throws -> KnowledgeSearchResult? {
        let query = "\"\(quotation.replacingOccurrences(of: "\"", with: "\"\""))\""
        let matches = try store.search(query, documentID: original.documentID, limit: 1000).filter {
            $0.reference.fingerprint == documentFingerprint &&
            $0.reference.excerptSignature == original.excerptSignature &&
            Self.contains(Self.normalized(quotation), in: Self.substring(text, range: $0.reference.utf16Range)) &&
            Self.signatureMatches($0.reference, in: text)
        }
        if let exactLocation = matches.first(where: { $0.reference.utf16Range == range }) { return exactLocation }
        if matches.count == 1 { return matches[0] }
        let contextual = matches.filter { $0.reference.context == original.context }
        return contextual.count == 1 ? contextual[0] : nil
    }

    private static func sameLocalSource(_ uri: String, url: URL) -> Bool {
        guard let candidate = URL(string: uri), candidate.isFileURL else { return false }
        return candidate.standardizedFileURL.path == url.standardizedFileURL.path
    }

    private static func sameURI(_ first: String, _ second: String) -> Bool {
        guard let a = URL(string: first), let b = URL(string: second) else { return first == second }
        return a.standardizedFileURL.absoluteString == b.standardizedFileURL.absoluteString
    }

    private static func loadText(at url: URL) throws -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard FileManager.default.fileExists(atPath: url.path) else { throw KnowledgeLibraryEvidenceError.sourceUnavailable }
        return try BOLDWriterDocument(fileWrapper: FileWrapper(url: url), contentType: BOLDWriterDocument.inferredContentType(for: url)).text.string
    }

    private static func substring(_ text: String, range: NSRange) -> String {
        let value = text as NSString
        guard range.location >= 0, range.length >= 0, NSMaxRange(range) <= value.length else { return "" }
        return value.substring(with: range)
    }

    private static func signatureMatches(_ reference: KnowledgePassageReference, in text: String) -> Bool {
        let body = substring(text, range: reference.utf16Range).trimmingCharacters(in: .whitespacesAndNewlines)
        return sha(Data(body.utf8)) == reference.excerptSignature
    }

    private static func contains(_ quote: String, in passage: String) -> Bool {
        let needle = normalized(quote), haystack = normalized(passage)
        return !needle.isEmpty && haystack.range(of: needle) != nil
    }

    private static func normalized(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func fileSHA256(_ url: URL) throws -> String { sha(try Data(contentsOf: url, options: [.mappedIfSafe])) }
    private static func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    private static func evidenceStatus(_ status: KnowledgeReferenceStatus) -> EvidenceLibraryReferenceStatus {
        switch status {
        case .current: .current
        case .revalidated: .revalidated
        case .stale: .stale
        case .unresolved: .unresolved
        }
    }
}
