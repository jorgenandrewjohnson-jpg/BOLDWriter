# Development roadmap

This is a prioritized work list, not a promise that any unfinished feature is ready for publication.

## Next acceptance work

1. Build the application locally, verify its source identity and signature, and complete installed-app GUI acceptance with disposable documents.
2. Exercise a disposable illustrated DOCX through import, editing, native save, fresh-process reopen, DOCX/PDF export, and structural artwork comparison.
3. Exercise cover layers and the physical 3D book interactively, including page turns, distant-page navigation, and repeated-open memory behavior.
4. Diagnose the full-suite memory spike in bounded test groups before making a complete-suite pass a release gate.

## Publishing quality

- Improve unsupported Word DrawingML and exact text-wrapping fidelity without losing source artwork.
- Strengthen pagination at chapter and section boundaries, image anchoring, tables, footnotes, and typography.
- Complete cover production export and printer-specific preflight for trim, bleed, color, fonts, and effective image resolution.
- Improve accessibility, error recovery, and realistic 3D book behavior with actual manuscript and cover data.

## Contributor-sized opportunities

- Add small synthetic DOCX fixtures with independent structural assertions.
- Improve accessibility labels and keyboard navigation in the cover and book workspaces.
- Add precise, actionable error text for unsupported imports and print checks.
- Reduce stale historical documentation and add source-provenance notes to adapted code.

Each item should finish with focused tests, a Release build, and GUI acceptance where the feature is interactive. Protect authors' original files throughout.
