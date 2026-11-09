# Binary distribution gate

The source repository is public, but no downloadable BOLD Writer application
has passed the binary distribution gate. `Scripts/package-release.sh` refuses
to build a distribution package until the release owner explicitly confirms a
completed review with `BOLD_WRITER_BINARY_REVIEW_CONFIRMED=1`. Setting that flag
is a record of completed review, not a substitute for it.

## Unresolved LGPL requirement

The Xcode and SwiftPM builds compile vendored LAME 3.100 C source into the app.
The included `Sources/BOLDWriter/AudioProduction/LAME/COPYING` identifies the
GNU Library General Public License version 2, and `LICENSE.upstream` describes
LAME's LGPL conditions. The notices and corresponding source are retained in
the repository. The packager stages those notices in the app bundle.

For a statically linked executable, the GNU project's [LGPL FAQ](https://www.gnu.org/licenses/gpl-faq.html.en#LGPLStaticVsDynamic)
and [Library GPL v2 section 6](https://www.gnu.org/licenses/old-licenses/lgpl-2.0.html)
describe an obligation to let recipients modify the library and relink the
application. The current package script does **not** yet provide and verify a
complete relinkable distribution. A reviewer must choose and test a compliant
approach, including the required notices, corresponding LAME source, and
relinkable application materials or another permitted mechanism. This note
does not make a legal determination about the final package.

## Acceptance before the review flag is used

1. Document and test the LGPL distribution/relink procedure for the exact
   candidate build and verify the notices and source it carries.
2. Complete fresh-process native save/reopen, illustrated DOCX and PDF export,
   cover persistence, 3D interaction, and bounded long-book memory acceptance
   using disposable documents.
3. Confirm build provenance, app identity, package contents, integrity hashes,
   macOS compatibility, and actual signing/notarization state.
4. Review `INSTALL.txt` and `ReleaseNotes.md` against the candidate revision.

No Developer ID signing or Apple notarization has been established. An ad-hoc
signature is only a local integrity mechanism and must be described accurately
if a reviewed prerelease package is eventually distributed.
