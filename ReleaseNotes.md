# BOLD Writer 1.0.0 source preview — no binary release yet

The version in the app identifies the current engineering build. It is not a
claim that BOLD Writer is ready for a general macOS release.

This public source snapshot includes a native Swift editor, DOCX import/export,
page layout and PDF publishing paths, editable cover projects, and a physical
3D book view. These areas have focused automated coverage, but important
end-to-end acceptance remains incomplete.

## Verified evidence at the public snapshot

- The macOS Release build and the focused GitHub Actions checks passed on the
  published source branches at the November 2026 checkpoint.
- An isolated QA app built from public source revision `a7a9380` recorded
  partial interactive acceptance: manuscript edit/Undo/Redo/save and
  same-process reopen; Book Audit print-proof navigation; a 3D book with actual
  synthetic manuscript text and opaque illustration; page navigation, orbit,
  and hardcover/paperback controls.
- Genuine disposable-app screenshots were captured; their public documentation
  update is still under review in pull request #20.

## Still required before a downloadable release

- Fresh-process document reopen, representative illustrated DOCX round trip,
  independent PDF export/reopen, editable cover save/reopen, and longer-book 3D
  memory and visual acceptance.
- Review and satisfy binary redistribution requirements for statically linked
  LAME, including user modification and relinking rights.
- Verify packaging on another supported Mac. Developer ID signing and Apple
  notarization have not been completed.

Do not use the public source preview as the sole copy of an irreplaceable
manuscript. Keep original Word documents and independently inspect exports.
See Docs/OpenSourceStatus.md for feature-level limitations and
Docs/BinaryReleaseGate.md for distribution prerequisites.
