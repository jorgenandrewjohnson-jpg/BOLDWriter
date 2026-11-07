# Knowledge Library API (Milestones 1–3)

This document is the cross-feature contract for the local BOLD Writer knowledge
library. The API is implemented in `Sources/BOLDWriter/KnowledgeLibrary/` and is
available to the Evidence Manager without a network service or AI provider.

## Identity and references

`KnowledgeDocumentID` is a stable UUID assigned when a source is first added. It
is independent of the filename and source path, so duplicate filenames remain
distinct. `KnowledgePassageReference` combines that ID with a passage UUID, the
original source URI, a source fingerprint, a UTF-16 range when the indexed revision still matches, an
excerpt signature, and heading/paragraph context. Collection changes preserve
passage UUIDs. Takeout re-imports retain UUIDs for unchanged passages in the
same document; ordinary re-indexing creates fresh UUIDs. Links and backlinks
are safely revalidated against document identity and excerpt signature. UTF-16 offsets are valid only
for the fingerprinted revision. Consumers must call `resolve(_:)`; a changed
source is re-indexed and a passage is reported as revalidated, stale, or
unresolved. A reference must never be applied blindly to a different revision.

The source URL is stored as a security-scoped bookmark where supported and as a
display URI for diagnostics. Library records retain provenance (native BOLD
Writer, Markdown, plain text, DOCX import, PDF text extraction, or reference),
file identity, modification date, byte count, and content fingerprint. The
source remains read-only to the indexer.

## Service surface

`KnowledgeLibraryStore` owns a library package in Application Support. Its
public operations are `add(url:)`, `add(folderURL:)` for a folder explicitly
chosen by the user, `addReference(title:uri:notes:)`,
`remove(documentID:)`, `refresh(documentID:)`, `rebuildIndex()`, `search(_:)`,
`related(to:excluding:)`, `createLink(from:to:description:)`, `backlinks(to:)`,
`requestNavigation(to:quotation:)`, `consumeNavigationRequest()`, and
`resolve(_:)`. Collection APIs are `createCollection(name:)`,
`renameCollection(_:to:)`, `deleteCollection(_:)`,
`move(documentID:to:sourceFolder:)`,
`addToCollection(documentID:collectionID:sourceFolder:)`,
`remove(documentID:from:)`, and `documents(in:)`. Search accepts optional
`collectionID`; leaving it nil searches the full library. Collection membership
changes preserve document and passage IDs, source files, and links. The store
retains and displays original source-folder paths across all-collection views. Search
supports all documents, one book/document, one
chapter/heading, keyword terms, and exact phrases. `KnowledgeSearchResult`
returns identity, a verified passage reference, rank, and excerpt. SQLite FTS
is an implementation detail; this API is the stable contract.

## Source and freshness states

`KnowledgeSourceStatus` is one of `available`, `changed`, `unavailable`, or
`referenceOnly`. `KnowledgeReferenceStatus` is one of `current`, `revalidated`,
`stale`, or `unresolved`. A missing or unreadable source never yields a current
location. Fingerprint changes invalidate stored offsets until text extraction
and signature-based resolution succeed. PDF page numbers are returned only
when the extractor can verify the containing page; otherwise section and
paragraph context are used.

## Evidence Manager integration

Evidence records may store `KnowledgePassageReference` values and use the store
to resolve them at display time. The Evidence Manager owns evidence claims,
citations, and their editorial workflow; the library owns source identity,
search, passage locations, manual cross-document links, and backlinks. A search
match is discovery only and does not assert that two passages establish the
same fact. Evidence code must not write to indexed source files or duplicate
the library's document identity and passage-resolution rules.

## Persistence and privacy

The app-managed library package contains a SQLite database and bookmarks under
`~/Library/Application Support/BOLDWriter/KnowledgeLibraries/`. The database is
reconstructible from explicitly selected sources and is not embedded in source
documents. No manuscript text leaves the device. A project may be rebuilt or
removed without changing original files.

## Bulk Takeout imports (Milestone 2)

`GoogleTakeoutScanner.scan(_:)` previews user-selected ZIP archives and
extracted folders. Numbered multipart Takeout ZIP files are selected together
as independent archive parts. The scanner rejects absolute/traversal paths,
symbolic links, duplicate entry names, encryption, malformed ZIP records,
oversized entries and excessive compression. It supports stored/deflated ZIP
and ZIP64 central directories and uses the platform `unzip` reader only for a
validated single member; it never asks an archive tool to extract untrusted
paths. Expansion is streamed in 1 MiB buffers, CRC and uncompressed length are
checked, one item is capped at 512 MiB, aggregate supported input at 20 GiB,
and a ZIP archive itself is never modified. Photos, videos, metadata sidecars,
and unsupported formats are previewed but not indexed by default.

`GoogleTakeoutImportModel` applies the preview selection to the existing
`KnowledgeLibraryStore`. ZIP document members receive durable, versioned local
copies below the existing library support directory before indexing. Files in
an explicitly selected extracted folder are indexed in place, with security
scoped access and source bookmarks, to avoid another full copy. Both paths use
the same document and passage IDs, SQLite database, FTS table, navigation and
backlink APIs as Milestone 1; they do not create a second search index.

The `takeout_imports` table records source identity, Google file ID and URL
when available, original relative path and filename, export format, source
SHA-256, metadata sidecar fields and import timestamp. Google IDs are used only
when present in the selected export metadata. Otherwise the importer uses an
explicitly labeled local source-path identity; it does not invent a Drive ID.
Content SHA-256 deduplicates against other library documents. Reopening the
same source re-hashes the content, skips unchanged records, and maps duplicate
content to the existing document ID. Partial work is safe to retry: committed
records are skipped, an already indexed staged copy is deduplicated, and a
cancelled in-progress ZIP member is removed before the next retry.
If the app exits while writing a member, UUID-named staging directories older
than 24 hours are removed when the library next opens; durable imported sources
and user-selected original files are not part of that cleanup.

For each supported document, the document row, passages, FTS rows and Takeout
provenance row are committed in one SQLite transaction. A parser failure removes
the newly staged copy and writes no document or provenance record. If a source
changes while it is being read, the expected fingerprint check rejects that
attempt. DOCX footnote bodies are searchable as separate passages whose source
location is the verified in-text footnote marker; opening the result selects the
marker and does not claim a page location for the note body.

An import record is exposed as `KnowledgeTakeoutImportRecord`. Removing its
document from the library cascades the provenance row but never deletes source
files or imported local copies. Source hierarchy is kept in `relativePath` and
inside ZIP-copy paths. Local copy storage and estimated FTS growth are separate
preview figures; extracted-folder files are not counted as additional copies.

## Collections and import history (Milestone 3)

`knowledge_collections` and `knowledge_collection_documents` are additive
tables inside the existing library database. Opening an M1/M2 database creates
a `My Library` collection and assigns its existing documents once. Imported
Drive folder paths are stored per membership. Moving or removing membership
never deletes source files or indexed documents; whole-library removal remains
a separate operation. Evidence references continue using the same canonical
document and passage IDs.

Takeout runs are summarized in `takeout_import_sessions` with imported,
duplicate, unchanged, failed, cancelled and finding summaries. The UI keeps the
latest 100 sessions. The current preview remains the place for the complete
scan listing; unsupported file types and malformed-file errors are saved in
the session summary.

## Future direct Drive connector boundary

`GoogleDriveConnector` is the provider interface for selected-folder child
listing, incremental change pages and writing an exported item to a local
destination. The Milestone 2 protocol has no concrete OAuth, token, or network
implementation. The available build has no configured OAuth client or Google
account authorization. See the milestone report for the official Drive API
assessment and the future system-browser OAuth/Keychain approval requirements.
