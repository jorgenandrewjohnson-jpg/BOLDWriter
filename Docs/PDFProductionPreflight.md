# PDF Interior Production Preflight

The native PDFKit-based CLI validates book-interior PDF production geometry before upload. It reads files without rewriting them.

Example commands:

    Scripts/bold pdf-preflight "Interior.pdf" --trim 6x9 --min-pages 2 --max-pages 1000 --require-even-pages
    Scripts/bold pdf-preflight "Bleed Interior.pdf" --trim 6x9 --bleed 0.125 --json

Flags: `--trim` sets target TrimBox dimensions in inches; `--bleed` requires minimum outward MediaBox clearance on all four sides relative to the TrimBox; `--min-pages` and `--max-pages` constrain page count; `--require-even-pages` requires even page count; `--json` returns structured results with schema version 2, page dimensions, issue codes and counts.

The command checks MediaBoxes, TrimBoxes, mixed page sizes, trim outside media, and per-edge bleed, and warns about rotated pages. It rejects malformed or unreadable PDFs. Missing TrimBoxes may default to MediaBoxes according to PDFKit.

Exit statuses: 0 valid, 2 invalid arguments or unreadable PDF, 3 production validation failures.

This does not validate every printer's specification, image DPI, embedded fonts, or graphical user interface behavior.

Disposable PDF fixture tests reside in `Scripts/tests/test-pdf-preflight.py`.
