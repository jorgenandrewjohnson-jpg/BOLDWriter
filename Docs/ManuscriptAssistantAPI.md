# Manuscript Assistant API (M1)

The Manuscript Assistant is implemented in `Sources/BOLDWriter/ManuscriptAI/`.
It uses the existing `KnowledgeLibraryStore` API and does not add a second index
or change the Knowledge Library schema.

## Retrieval and source records

`ManuscriptRetrievalCoordinator` accepts an explicit `ManuscriptSearchScope`.
For the open manuscript it searches the current in-memory text, so unsaved edits
are included without writing them to a source file or indexing database. These
passages carry the document revision UUID and UTF-16 range and are rejected if
the revision changes. For library scope it calls `KnowledgeLibraryStore.search`
for the selected canonical document or the complete library, including multiple
single-term refinements for comparison questions. Chapter references in a query
are passed to the library context filter. Search candidates are ranked, deduped,
and capped at 12 passages / 18,000 excerpt characters by default.

`ManuscriptEvidence` explicitly records either a live-manuscript revision/range
or a canonical `KnowledgePassageReference`. The assistant validates every
selected reference through `KnowledgeLibraryStore.resolve(_:)` before remote
submission and again before opening a source. Only `current` and `revalidated`
library references are eligible. The model receives app-issued evidence IDs;
the response parser rejects IDs that were not in the request's evidence list.
The UI displays source title, heading/paragraph context, excerpt, verification
state, canonical reference, and an Open Source action.

## Provider boundary and privacy

`ManuscriptAnswerProvider` is a dependency-injected boundary. The existing
`OpenAIProvider` implements it alongside the precision-editing `AIProvider`, so
both features use the same Keychain credential, configured OpenAI model, and
injectable URL session. A deterministic mock implements the answer protocol in
tests. No local model is claimed or assumed.

Retrieval is local. The author must select **Review excerpts and ask OpenAI**,
inspect the question and exact selected passages, and then select **Send to
OpenAI**. The existing precision-editing UI has the same two-step disclosure
and shows the exact text, command, writing preferences, and outline sent.
Remote requests include only the question and bounded excerpts; they do not
upload the library or perform background indexing/synchronization.

## Editing and other feature APIs

Precision editing reuses the existing `AIManager`, revision recovery point,
stale-range validation, attributed editor replacement, and Undo/Redo path.
Accept/reject remains author controlled. Existing behavior rejects a proposal
when the document revision or original range changed.

The Evidence Manager and Manuscript Quality branches do not expose additional
integrated read APIs in the primary baseline. M1 therefore consumes canonical
Knowledge Library references directly and does not duplicate evidence records
or consistency findings. An adapter can be added when those stable public
interfaces are promoted to primary.
