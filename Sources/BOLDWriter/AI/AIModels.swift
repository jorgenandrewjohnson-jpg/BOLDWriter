import Foundation

enum AIContextScope: String, CaseIterable, Identifiable {
    case selection = "Selection"
    case paragraph = "Paragraph"
    case section = "Section"
    case document = "Entire Document"
    var id: String { rawValue }
}

enum AIEditOperation: String, Codable {
    case replaceSelection
    case replaceParagraph
    case replaceSection
    case insertAtCursor
}

struct AIEditProposal: Identifiable, Equatable {
    var id = UUID()
    var operation: AIEditOperation
    var range: NSRange
    var originalText: String
    var replacementText: String
    var summary: String
    var documentRevisionID: UUID
}

struct AIContext {
    var scope: AIContextScope
    var range: NSRange
    var text: String
    var outline: [String]
    var instructions: String
    var documentRevisionID: UUID
}

protocol AIProvider {
    func propose(command: String, context: AIContext) async throws -> (operation: AIEditOperation, replacement: String, summary: String)
    func testConnection() async throws
}

enum AIProviderError: LocalizedError {
    case notConfigured
    case invalidResponse
    case service(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "No AI service is configured. Add your OpenAI API key in Settings > AI."
        case .invalidResponse: "The AI service returned a response BOLD Writer could not safely interpret. No document changes were made."
        case .service(let message): message
        }
    }
}
