# BOLD Writer development roadmap

This is a guide for contributors, not a release promise. The [current status](OpenSourceStatus.md) records what is implemented and what still lacks end-to-end acceptance. A passing build is not a print-production certification.

## 1. Contributor onboarding and reproducible builds — in progress

- **Done:** public source snapshot, MIT license and third-party notices, focused macOS CI, contributor/security/community guides.
- **Next:** reproduce the build on more supported Macs, make test prerequisites discoverable, document common Xcode failures, and keep examples free of private content.

## 2. Writing and document-editing stability — in progress

- **Done:** native rich-text model, persistence, core editing commands, search, styles, and many focused tests.
- **Next:** full save/close/fresh-process-reopen acceptance; long-manuscript editing; clear recovery for invalid documents; keyboard and VoiceOver review.

## 3. DOCX compatibility and page layout — in progress

- **Done:** supported floating artwork crop, rotation, anchoring, and wrap polygon preservation through import/native save/export; synthetic tests for many structures.
- **Next:** independent illustrated DOCX round-trip corpus, unsupported DrawingML dependency cases, chapter-boundary pagination, widow/orphan and keep-with-next behavior, and editor/PDF page matching.

## 4. Book design and professional publishing — in progress

- **Done:** page geometry, facing-page options, PDF output, and Book Health checks for geometry, font embedding, and placed raster resolution.
- **Next:** printer-specific preflight, font and image proofing, accessible error explanations, table/footnote pagination, and verified print exports.

## 5. Cover design and physical 3D book — in progress

- **Done:** editable cover layers, masks, crops, alignment, grouping, and native 3D rendering of synthetic manuscript and cover data.
- **Next:** complete installed-GUI save/reopen/export acceptance, accurate cover proofing, smooth interaction, repeated-open memory measurement, and visual polish.

## 6. Testing, accessibility, and performance — in progress

- **Done:** focused CI and bounded performance/acceptance tests.
- **Next:** isolate the full-suite memory spike, make UI controls keyboard/VoiceOver accessible, strengthen corrupt-input tests, and automate safe synthetic end-to-end workflows.

## 7. First stable downloadable macOS release — planned

Requires all critical data-preservation and GUI gates, tested migration/recovery, a reviewed binary-distribution license plan for LGPL components, signing, notarization, and a clear support policy. There is no verified downloadable binary release yet.

## Long-term ambitions

Deeper Word compatibility, sophisticated typography, professional cover and 3D tooling, and optional private manuscript-aware assistance. These depend on the stability work above and should be proposed through an issue or discussion before large implementation efforts.

Choose an existing [issue](https://github.com/jorgenandrewjohnson-jpg/BOLDWriter/issues) or suggest a tightly scoped task. A helpful contribution has a reproducible fixture, a narrow code change, and honest test and GUI evidence.
