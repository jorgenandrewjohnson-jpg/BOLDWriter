# BOLD Writer

**Be Bold. Write Freely. Publish Beautifully.**

BOLD Writer began with a simple idea: authors should be able to create beautiful, professional books without expensive software, complicated publishing tools, or restrictive platforms. It is now a free, open-source macOS project that programmers, designers, students, and authors can build together.

The vision is one welcoming studio for manuscript writing and editing, typography, page layout, illustration, cover design, 3D book previews, and print publishing. Every author deserves tools to bring a story to life. **Let's be BOLD together.**

BOLD Writer is still a work in progress. It combines a native manuscript editor, page layout, cover design, PDF production checks, and an interactive 3D book preview. A successful build does not mean every imported Word document or print job is production ready.

## What works today

- Native rich-text editing, styles, search, outline navigation, comments, bookmarks, undo/redo, and `.boldwriter` document packages.
- DOCX import and export for many text, style, table, section, image, and drawing structures. Supported floating pictures retain crop, rotation, anchoring, wrap distances, wrap sides, and edited Tight/Through wrap polygons through native save and DOCX export. Some Word structures remain unsupported and may be preserved opaquely or rejected with an error.
- Paginated manuscript preview and PDF export from the same manuscript data, with page settings, facing-page options, floating images, running content, and Book Health checks for PDF geometry, fonts, and placed raster resolution.
- An editable cover project with text and image layers, masks, crops, transforms, groups, alignment, guides, print-wrap geometry, and export. The 3D preview uses manuscript pages and cover artwork from the project.
- Read Aloud, audiobook production, and optional AI features. Ordinary writing, saving, and export require no AI account. Remote AI use is optional and should be reviewed before sending manuscript text.

The [current status and limits](Docs/OpenSourceStatus.md) distinguish implemented code, automated tests, installed-app acceptance, and unfinished work. Keep original DOCX files and independent backups until your specific book has passed a complete round trip and print proof.

## Build and test

Requirements: macOS 14 or later and a full Xcode installation. The current engineering build uses Xcode 26.6. SwiftPM and the Xcode project share application sources. SwiftPM includes the vendored LAME C target; it does not download package dependencies.

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export TMPDIR=/tmp
swift test -j 1
swift build -c release -j 1
Scripts/bold xcode-build
```

The native app is built at `DerivedDataRelease/Build/Products/Release/BOLD Writer.app`. `Scripts/bold` also provides focused tests, source identity checks, installation, and installed-app verification. Inspect a running app for unsaved work and close it normally before local installation. `Scripts/bold install` backs up the previous bundle; `Scripts/bold verify-install` checks the installed source revision and signature. An ad-hoc signature is **not** Apple Developer ID signing or notarization.

Use [OpenSourceStatus.md](Docs/OpenSourceStatus.md) and fresh test output for current claims. The complete test suite has previously exceeded practical memory limits in one process; use focused suites while diagnosing that resource issue.

## Project structure

| Location | Purpose |
| --- | --- |
| `Sources/BOLDWriter/DocumentCore` | Native document model, layout data, cover model, PDF preflight |
| `Sources/BOLDWriter/Editor` | AppKit rich-text editing and paginated canvas |
| `Sources/BOLDWriter/ImportExport` | DOCX, PDF, EPUB, and other import/export paths |
| `Sources/BOLDWriter/UI` | SwiftUI workspaces and inspectors, including Cover Creator and 3D Studio |
| `Sources/BOLDWriter/App` | App lifecycle, automation, and acceptance runners |
| `Sources/BOLDWriter/AudioProduction/LAME` | Vendored LGPL MP3 encoder source and notices |
| `Tests/BOLDWriterTests` | Unit and integration tests |

See [current architecture](Docs/ArchitectureCurrent.md), [contributing guide](CONTRIBUTING.md), and [roadmap](Docs/Roadmap.md).

## Privacy and source custody

Native documents belong to the author. Do not attach a private manuscript, unpublished cover, API key, or personal data to a public issue or pull request. Reproduce defects with synthetic or permission-cleared fixtures. The original nine source-research ZIP archives are not part of the app source tree and are not build inputs.

## License and third-party code

BOLD Writer's own code is offered under the repository's [MIT license](LICENSE). Some included components have separate licenses, notably the vendored LAME 3.100 source under LGPL terms. The [third-party inventory](Docs/ThirdPartyAttribution.md) identifies source origins, notices, and distribution considerations. The MIT license does not replace those component licenses. Contributors should preserve copyright and license notices when adapting code.

The project is not yet a notarized general-release binary, and professional print output must be checked against the intended printer's specifications. Contributions that improve fidelity, reliability, accessibility, and reproducible acceptance are welcome.
