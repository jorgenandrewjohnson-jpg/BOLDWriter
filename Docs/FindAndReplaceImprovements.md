# Find and Replace improvements — 2026-10-08

Starting HEAD: `e1a6390edbc483e2dcdb09924894015dc7687166`.

## Behavior

- Search compiles the same query rules for navigation and replacement. Case,
  literal and regex searches share UTF-16 ranges with the native editor.
- The sidebar caches its result list until the query, options, tab or document
  revision changes. Enumeration stops after 1,001 matches; the list displays
  the first 1,000 and explicitly identifies truncation. Next/Previous and
  Replace All still operate across the entire manuscript.
- Command-F and Find and Replace both open the same Search sidebar and focus
  the query field. Repeating the command refocuses the existing field. This
  replaces the native find-panel action that did not appear in Print Layout.
- Malformed regex queries display their error and disable replacements.
  Regex replacements support Foundation replacement templates (`$0`, `$1`,
  `$2`, etc.). Literal replacements preserve dollar signs and backslashes.
- Single and bulk search replacements inherit each match's font, paragraph
  style, color and named style. Attachment and note-reference attributes are
  removed from inserted ordinary text.
- Replace advances to the next match beyond inserted text. Replace All remains
  one undoable command, including with Track Changes enabled.
- Read-only editor views reject ordinary and tracked search replacements at
  the controller boundary; replacement controls are also disabled.
- Batch note protection reads footnotes/endnotes once and uses binary search
  to expand partial numbered-reference edits. Conflicting expanded edits,
  malformed note metadata, invalid/overlapping ranges and damaged table
  boundaries are rejected before mutation. Moved zero-width insertions are
  sorted in original document coordinates before application.
- Search snippets preserve composed characters at their boundaries. Whole-word
  literal queries support punctuation at their ends and Unicode letters,
  numbers and combining marks.
- Section selection in front matter ends at the first heading rather than
  including the entire manuscript. Child sections remain inside their parent.

## Verification

Focused command:
`./Scripts/bold test 'SearchNavigationTests|EditorRegressionTests|TrackChangesTests|FootnoteTests|EndnoteEditingTests|TableTests|DocumentAnalysisTests'`

189 tests passed, zero failures. New regressions cover regex capture templates,
UTF-16 offsets, Unicode boundaries/snippets, malformed expressions, empty and
negative display limits, zero-width matches, navigation beyond 1,000 results,
formatting, read-only safety, bulk/tracked undo, note-reference expansion and
front-matter sections. A 5,000-match replacement plus full attributed undo
passed in 0.017 seconds in the focused run; this is one synthetic fixture,
not a general performance guarantee.

Initial validation: `./Scripts/bold verify` ran 1,603 tests, nine opt-in skips,
zero failures (48.424 seconds). SwiftPM Release and native universal Release
passed. Installed diagnostics reopened native/DOCX samples, generated seven
export formats and checked four synthetic manuscript sizes up to 250,000 words.
GUI checks observed invalid-regex feedback, actual capture replacement of a
24-point bold heading and Undo restoration. The GUI pass also found the
Command-F native-panel issue; final validation follows the routing repair.
Logs live under `/tmp/bold-improvements-*`; generated diagnostics and GUI test
files are excluded from Git. The existing untracked audit folder is preserved.

## Limits

A displayed list is capped at 1,000 rows; navigation and replacement are not.
Regex evaluation uses Foundation synchronously and has no execution timeout.
Track Changes uses the existing per-match revision engine and grouped undo;
large tracked batches still have its existing snapshot costs. No live AI
provider connection or private manuscript acceptance is required or claimed.

## Final verification

- Final focused checks: 54 passed, zero failures, including native table
  save/reopen and atomic rejection of cross-cell replacement batches.
- Complete suite after the initial keyboard-focus race repair: 1,605 tests,
  nine opt-in skips, zero failures, 47.035 seconds.
- SwiftPM Release passed (77.16 seconds); native universal Release BUILD
  SUCCEEDED. Complete validation log: `/tmp/bold-improvements-verify-complete.log`.
- Final recoverable install and strict signature/UUID/Desktop symlink checks
  passed: `/tmp/bold-improvements-install-complete.log` and
  `/tmp/bold-improvements-signature-complete.log`.
- Original pre-task app remains at
  `/Applications/BOLD Writer Recoveries/BOLD Writer 20261008-144608-31599.app`.
  Intermediate app recoveries are also retained by the install script.
- Final installed executable diagnostics passed:
  `/tmp/bold-improvements-diagnostics-complete.log`; artifacts under
  `/tmp/boldwriter-improvements-complete-diagnostics-20261008/`. Native and DOCX
  samples reopened; PDF/RTF/HTML/Markdown/text/EPUB exports were generated;
  four synthetic manuscripts up to 250,000 words reopened and laid out a page.
- Final desktop observations: the first Command-F focuses Find; pasting `harbor`
  updates the query and returns four matches while preserving the title and
  manuscript. Next selects `Harbor`; repeated Command-F focuses the existing
  query; pasting `lantern` updates it and returns two matches. The final Search
  panel's screenshot was visually inspected. No private manuscript was edited.
- Installed UUIDs: x86_64 `25044F05-F414-3D57-97A4-61594E7925D2`,
  arm64 `9B5F62AD-8DF6-3C2C-A0AF-1339CDDC4D9B`.
- A final UI pass intentionally corrected a first-opening focus race: the
  focus task now waits for the new sidebar to mount and cancels when removed.
  Earlier GUI checks also observed actual regex replacement and Undo, rather
  than treating the unit tests as installed interactive acceptance.
- Final commit: see `git log -1 --oneline`; this note is part of that commit.

Production files: `App/BOLDWriterApp.swift`, `DocumentCore/Endnotes.swift`,
`Editor/EditorController.swift`, `Search/DocumentAnalysis.swift`,
`UI/DocumentView.swift`, `UI/SidebarViews.swift` (under `Sources/BOLDWriter/`).
Tests: `DocumentAnalysisTests.swift`, `EditorRegressionTests.swift`,
`SearchNavigationTests.swift` (under `Tests/BOLDWriterTests/`).
