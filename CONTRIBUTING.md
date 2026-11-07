# Contributing to BOLD Writer

Thank you for helping authors make better books. BOLD Writer is a native macOS project; small, well-tested changes are easier to review and maintain than broad rewrites.

## First steps

1. Read [README.md](README.md), [current status](Docs/OpenSourceStatus.md), and [architecture](Docs/ArchitectureCurrent.md).
2. Search existing issues before opening a new one. For a proposed large change, describe the user workflow and data model first.
3. Use a branch from the current integration head. Keep commits focused and preserve unrelated changes.
4. Run the relevant tests and a Release build. Include exact test counts and any skipped GUI verification in your pull request.

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

Please follow the [Code of Conduct](CODE_OF_CONDUCT.md). Report suspected vulnerabilities using [SECURITY.md](SECURITY.md), not a public bug report with exploit details.
