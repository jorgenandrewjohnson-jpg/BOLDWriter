# Evidence Review read-only summary API

Codex C's future manuscript audit can consume this evidence-specific interface without duplicating source verification or claim analysis:

```swift
@MainActor
EvidenceAuditSummaryProvider.summary(
    manuscript: String,
    evidence: [ClaimEvidence],
    sources: [CitationSource]
) -> EvidenceAuditSummary
```

The returned summary contains passage count, passages with no BOLD Writer evidence association, passages with only user-entered/unverified evidence, challenging evidence count, unresolved anchors, missing source records/files, stale canonical passage references, and bibliography metadata hints. It is read-only. It does not judge claim truth, evidence support, prose quality, or consistency. Sentence segmentation is a mechanical coverage inventory for Evidence Review, not a replacement for the Book Audit scanner.

Canonical passage links remain opaque persisted `KnowledgePassageReference` data in evidence records and are resolved by `KnowledgeLibraryEvidenceAdapter`; this API does not create a second library or index.
