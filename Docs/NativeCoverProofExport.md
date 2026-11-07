# BOLD Writer — Physical Cover Guide in Cover Creator

The Cover Creator export dialog now offers **Create Physical Wrap Guide PDF…** for full-wrap print covers.

It opens a native sheet where the user supplies the actual interior page count, trim dimensions, paper sheet caliper, bleed, safe inset, and optional printer-specific spine allowance.

A live text readout shows the computed flat width, height, and spine thickness.

The save action uses a native macOS Save panel and the same `BOLDPrintCoverProofPDF` and `BOLDPrintCoverGeometry` engines already verified by regression and PDFKit tests.

The exporter refuses to replace an existing destination.

The sheet provides an error message if input validation or file export fails.

## Important

The generated PDF contains vector guidelines but does not include the user's current cover artwork.

It is a guide-only proof, not finished printer artwork.

The user must supply the actual printer specifications and final interior page count.

## Tests

`PrintCoverProofInputsTests` covers valid, missing, non-finite, odd-page, trim, bleed, safe inset, and paper allowance inputs.

This is the initial native Cover Creator integration. Real graphical interaction still requires acceptance testing in the installed application.
