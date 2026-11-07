# BOLD Writer — Read Actual Interior PDF in Cover Guide

Inside Cover Creator, open **Export Cover** and select
**Create Physical Wrap Guide PDF…**.

In the sheet, choose **Read Interior PDF…**.

BOLD Writer reads the selected PDF without writing to it,
checks every page for consistent trim dimensions, and fills
the page count and trim width and height automatically.

The user still supplies the printer's actual paper caliper,
bleed, spine allowance, and desired safe text inset.

Mixed trim sizes, unreadable or locked files, rotated
90/270-degree pages, and trim regions extending beyond
the media region are rejected before values are applied.

If validation fails, existing form values remain unchanged.

This feature does not merge, edit, export, or replace the
interior PDF. It does not infer printer-specific paper
caliper or binding allowances.

The Open panel and Save panel use native macOS interfaces.

Automated regression tests use disposable PDFs.
Real mouse and Finder interaction still requires an
authorized graphical user session.

## Raw PDF finishing-box validation

PDFKit can normalize malformed PDF finishing boxes. The inspector independently examines explicit raw /TrimBox coordinates using CoreGraphics before accepting an interior. A handcrafted PDF fixture verifies rejection of negative out-of-media coordinates.
