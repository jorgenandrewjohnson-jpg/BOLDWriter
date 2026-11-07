# Contributing to BOLD Writer

Thank you for helping authors make better books. BOLD Writer is a native macOS project; small, well-tested changes are easier to review and maintain than broad rewrites.

## First steps

1. Read [README.md](README.md), [current status](Docs/OpenSourceStatus.md), and [architecture](Docs/ArchitectureCurrent.md).
2. Search existing issues before opening a new one. For a proposed large change, describe the user workflow and data model first.
3. Use a branch from the current integration head. Keep commits focused and preserve unrelated changes.
4. Run the relevant tests and a Release build. Include exact test counts and any skipped GUI verification in your pull request.

The first clone should use `https://github.com/jorgenandrewjohnson-jpg/BOLDWriter.git`. Open `BOLDWriter.xcodeproj` in full Xcode for the native app, or use the commands below from the repository root. The public project website is [here](https://jorgenandrewjohnson-jpg.github.io/BOLDWriter/).

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export TMPDIR=/tmp
swift test -j 1 --filter DOCXImageTests
swift build -c release -j 1
Scripts/bold xcode-build
```

The full test suite has previously used excessive memory in one process. Start with focused suites and describe any resource interruption accurately. GUI work should be exercised in a disposable document; unit tests are not a substitute for interactive acceptance.

## Source and document safety

- Use synthetic or redistribution-cleared fixtures. Never commit a private manuscript, unpublished illustration, credential, personal information, or local QA output.
- Preserve original DOCX bytes. Test imports and exports on copies, including native save, close, reopen, and structural checks where relevant.
- Keep the manuscript model authoritative. Cover and 3D work should consume the real project data rather than introduce a second document state.
- Review dependencies and licenses before adding source. Record the upstream commit, file paths, license, adaptation, and attribution. Do not copy GPL/AGPL code into the MIT application without a deliberate, reviewed licensing decision.
- Do not run setup scripts or package hooks from the nine research repositories. The preserved research ZIP archives are not development workspaces.

## Pull requests

Explain the problem, the actual behavior changed, source provenance, tests run, GUI acceptance, and remaining limitations. Link to an issue when one exists. Do not include secrets or private manuscript screenshots. Maintainers review and merge changes; a passing CI job alone does not establish publishing fidelity.

Good first contributions include improving accessibility labels, creating synthetic DOCX fixtures, tightening error messages, and adding bounded tests for existing PDF or cover behavior. See [Roadmap.md](Docs/Roadmap.md) for larger work.

## Coding and review expectations

- Follow the existing Swift/AppKit/SwiftUI style near the changed code. Keep document state in the canonical model; avoid a second importer, renderer, or cover model for one feature.
- Prefer focused tests with synthetic, redistribution-cleared fixtures. Cover save/reopen and DOCX changes should prove persistence; visual or interactive changes also need a manual GUI check and a description of what was actually exercised.
- Keep UI work accessible through labels, keyboard focus, and readable contrast. Explain any deliberate behavior change in the pull request.
- Run `git diff --check`, the relevant focused tests, and a Release build before requesting review. Report exact executed tests and skips. Do not call a zero-execution runner a pass.
- Maintainers review changes on pull requests. Resolve review comments, keep the branch current, and avoid force-pushing shared branches. The default branch requires a pull request and resolved conversations; automated checks do not replace review of document fidelity or license obligations.

Please open a [question or idea discussion](https://github.com/jorgenandrewjohnson-jpg/BOLDWriter/discussions) for broad design proposals. Use [Issues](https://github.com/jorgenandrewjohnson-jpg/BOLDWriter/issues) for a reproducible defect or scoped task. Do not post a private manuscript as an example.

Please follow the [Code of Conduct](CODE_OF_CONDUCT.md). Report suspected vulnerabilities using [SECURITY.md](SECURITY.md), not a public bug report with exploit details.
