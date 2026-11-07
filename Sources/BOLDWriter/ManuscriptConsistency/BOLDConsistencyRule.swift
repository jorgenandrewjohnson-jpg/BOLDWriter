import Foundation

public enum BOLDConsistencyRuleKind: String, Codable, CaseIterable, Identifiable {
    case preferredTerm
    case disallowedTerm
    case capitalization

    public var id: String { rawValue }
}

public enum BOLDConsistencyRuleScope: String, Codable, CaseIterable, Identifiable {
    case entireManuscript
    case outsideQuotationMarks

    public var id: String { rawValue }
}

/// A local project rule. `matchText` is always treated as a literal string.
public struct BOLDConsistencyRule: Codable, Equatable, Identifiable {
    public var id: UUID
    public var kind: BOLDConsistencyRuleKind
    public var matchText: String
    public var replacement: String?
    public var explanation: String
    public var enabled: Bool
    public var caseSensitive: Bool
    public var wholeWord: Bool
    public var scope: BOLDConsistencyRuleScope

    public init(
        id: UUID = UUID(),
        kind: BOLDConsistencyRuleKind = .preferredTerm,
        matchText: String,
        replacement: String? = nil,
        explanation: String = "",
        enabled: Bool = true,
        caseSensitive: Bool = false,
        wholeWord: Bool = true,
        scope: BOLDConsistencyRuleScope = .entireManuscript
    ) {
        self.id = id
        self.kind = kind
        self.matchText = matchText
        self.replacement = replacement
        self.explanation = explanation
        self.enabled = enabled
        self.caseSensitive = caseSensitive
        self.wholeWord = wholeWord
        self.scope = scope
    }
}
