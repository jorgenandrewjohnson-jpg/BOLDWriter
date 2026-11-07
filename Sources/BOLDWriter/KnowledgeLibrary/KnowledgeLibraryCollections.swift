import Foundation

struct KnowledgeCollectionID: Codable, Hashable, Identifiable, Sendable {
    let rawValue: UUID
    var id: UUID { rawValue }
    init(_ value: UUID = UUID()) { rawValue = value }
}

struct KnowledgeCollection: Identifiable, Codable, Hashable, Sendable {
    let id: KnowledgeCollectionID
    var name: String
    let createdAt: Date
    var documentCount: Int
}

struct KnowledgeImportSession: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let sourceLabel: String
    let startedAt: Date
    let completedAt: Date?
    let imported: Int
    let duplicates: Int
    let unchanged: Int
    let failures: Int
    let cancelled: Bool
    let summary: [String]
}
