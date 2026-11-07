# Current development status

This is a capability and acceptance record, not a release-readiness claim. The public source snapshot is based on local development commit `e43e631` (2026-11-07). Its original local history and machine-specific QA evidence were intentionally kept outside this public repository.

| Area | Implemented and tested | Still open |
| --- | --- | --- |
| DOCX | Supported floating image crops, anchors, rotations, wrap distances, edited Tight/Through polygons, native persistence, and DOCX reimport have focused tests. Unsupported DrawingML package parts have bounded opaque preservation. | Full illustrated-manuscript fidelity, every Word drawing type, exact Through Wrap text flow, and installed-GUI round trips are unverified. |
| Editor and pagination | Canonical manuscript data drives editor layout and PDF output; focused geometry and page-layout tests pass. | Long real manuscripts, chapter-boundary pagination, and full typography need broader installed-GUI acceptance. |
| Cover Creator | Editable layers, masks, crops, groups, alignment, replacement, and print-wrap data are implemented. Rotated selection bounds are included in transform handles. | A complete installed-GUI cover design/save/reopen/high-resolution export pass is not complete. |
| 3D Book Studio | Native render runners show real manuscript text and illustration and navigate a synthetic 229-page book under a bounded memory run. | Interactive GUI orbit, zoom, page turns, and repeated-open memory behavior remain unverified after the computer-control connection failed. |
| PDF and Book Health | Production PDF output and checks for page geometry, font embedding, and placed raster resolution have focused tests. | Printer-specific preflight, broad PDF inspection, and print-ready certification require more work. |
| AI and audiobook | Optional AI and local audio workflows exist; LAME MP3 source is vendored. | Live-provider behavior, full manuscript-aware AI acceptance, and binary-distribution license review remain open. |

The integrated source passes focused DOCX image (27), floating-image layout (39), and cover multi-layer (5), linking (23), and transform-lock (8) tests. The authoritative native Xcode Release build and the SwiftPM Release build passed at `9c5aba1`; an earlier SwiftPM attempt was interrupted because source changed during compilation and is not counted as a product failure. The complete monolithic test suite was not rerun because an earlier run reached excessive memory use. These figures are not a complete application test count.

The installed app was last independently verified at `e93e626`; newer source was not installed because the running app's unsaved state could not be inspected after GUI control failed. Do not call the newer source installed or GUI accepted until installation and interactive checks are repeated.

Private author manuscripts and original illustrated DOCX files are not included in this public source snapshot. The project remains under active development; run end-to-end acceptance on disposable copies before relying on it for publication.
