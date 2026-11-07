# Audiobook Production API (M2)

This additive backend contract is owned by the Audio Production worktree. It has no SwiftUI presentation dependencies. Concrete declarations live in `Sources/BOLDWriter/AudioProduction/` and are internal to the application module so E2's UI can call them without introducing a second renderer.

## Constructing a project service

Create one `AudiobookProductionService` per persisted audiobook project:

```swift
let service = try AudiobookProductionService(
    projectID: projectID,
    projectDirectory: projectDirectory,
    providers: [AppleSystemNarrationProvider(), ElevenLabsNarrationProvider(apiKey: keyFromKeychain)]
)
```

The service stores only provider/voice/model/settings identifiers and media checkpoints in `production-manifest.json`. The caller must resolve ElevenLabs credentials from Keychain and inject them for the lifetime of the provider; neither the provider nor the manifest persists the key.

## Render flow

1. Build `AudiobookSourceItem` entries in narration order. Each entry has a stable segment ID, chapter ID/title, source fingerprint, and the prepared narration text. This is a production payload; it never mutates the manuscript.
2. Create `AudiobookNarratorProfile` values and an `AudiobookNarratorAssignmentPlan`. Resolution precedence is explicit segment assignment, chapter assignment, then default narrator.
3. Create an explicit `AudiobookRenderScope` (`.selectedChapters` with IDs or `.wholeBook`).
4. Call `billablePreflight(for:)` before display/confirmation. It returns one `AudiobookBillablePreflight` per account voice/model with the exact UTF-16 character count, exact-text fingerprint, selected chapters, largest chunk, and persisted attempted usage. Show the scope, intended voice/model, text leaving the Mac, and budget to the author. Then include a matching `AudiobookBillableApproval` with that exact count/fingerprint, provider, voice, model, and budget. The service checks both the text and prior attempted characters from the persisted manifest before any provider validation or synthesis request. It reserves each attempted request before sending it, so retries cannot exceed the approved character budget. If content changes after approval, the approval is rejected. No approval means no billable provider call.
5. Call `render(_:)` to start or `resume(_:)` to recheck and continue. Both return a job UUID. Set `forceRegenerationIDs` to the explicit segment IDs the author wants regenerated even when their fingerprints still match. `snapshot(for:)` provides the latest status; `updates(for:)` provides an `AsyncStream<AudiobookJobSnapshot>`. `cancel(_:)` stops at a chunk boundary and preserves completed output.

`AudiobookProductionService` uses the provider's verified request limit (clamped to the current M1 chunker boundary), fingerprints text and all narrator settings, checks checksums and decodability, and streams bounded segments. An atomically renamed response can be recovered if interruption occurred before its manifest update. Missing/corrupt chunks are queued again; verified unchanged chunks remain reusable. Apple synthesis uses the exact installed voice ID. ElevenLabs checks the authenticated account's model and voice catalog and omits speed settings because the current M1 request contract does not support one.

## Inspect and export

- `AudiobookProductionService.supportedExportFormats` lists `.mp3`, `.wav`, and `.m4a` in this build (bundled LAME MP3, PCM WAV, and Apple AAC/M4A).
- `verifiedAudio(chapterIDs:)` returns verified chunks sorted by saved chapter and segment order. Passing chapter IDs exports those selected chapters; `nil` selects the whole current book output.
- `inspect(chapterIDs:)` returns quality measurements over verified chapter sources without creating an export.
- `export(_:)` accepts `.mp3`, `.wav`, or `.m4a`, destination, title/author/album, MP3 quality settings, and mastering settings. It returns `AudiobookVerifiedExport`, which includes the installed file URL, actual bytes/duration/sample format, codec bitrate when measurable, metadata, measured quality, and mastering plan.
- MP3 and M4A Unicode title/author metadata are decoded and checked. WAV has no embedded title/author metadata in this implementation; these values remain in the export result/production project.
- All three exporters stage into a sibling temporary file, decode/inspect it, then atomically replace the selected destination. A failed export does not remove a previous successful destination.
- `AudiobookAudioQualityAnalyzer.inspect(sources:sourceIDs:)` streams measurements without assembling the book in memory. It reports integrated K-weighted loudness, sample peak, clipping, long quiet runs, source formats, missing/duplicate paths, and segment join jumps. It reports that true peak was not measured. It does not certify ACX/Audible or another platform.

## Persisted manifest and failure semantics

`production-manifest.json` is versioned independently from the M1 manifest and is atomically written. Every expected chunk is checkpointed before rendering and stores source/text/settings fingerprints, narrator identifiers, stable ID, path, checksum, decoded duration/bytes, successful/attempted billable character counts, status, and recoverable error. Successful chunks are retained when a later request fails or is cancelled. Export requires every selected expected chunk to be complete and verified. On relaunch, reconstruct the service with the same project ID and directory, then call `resume(request)` with the current request payload. Orphaned `.partial.` files under the project's chunk directory are removed during recovery.

The service rejects provider request-limit errors, missing narrator assignments, missing provider implementations, insufficient preflight disk space, mismatched billable approval, exhausted character budget, unreadable manifests, and missing/corrupt media. Retryable provider failures use a maximum of three bounded retries with exponential delay. Authentication and other permanent provider failures are reported without retry. Price and quota estimates are deliberately not invented: the app should display exact text/character count and account-selected voice/model before explicit approval.

## Integration constraints

- Do not pass the entire book in a single provider call. Segment payloads at paragraph-aware boundaries upstream; the service enforces a maximum request length for additional provider safety.
- Store API keys only in Keychain or an existing secure credential manager. Never put credentials in `AudiobookRenderRequest`, `AudiobookNarratorProfile`, manuscript metadata, or this manifest.
- Export the exact user's selected voice. The service never substitutes another voice.
- No live paid ElevenLabs generation is part of the deterministic tests. A user-facing call requires a valid Keychain key and an explicit matching approval.
- This interface is additive to M1. The existing Read Aloud reader and M1 playback/export flow remain available.
