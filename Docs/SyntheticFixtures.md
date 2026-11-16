# Synthetic fixture guide

Fixtures let a contributor reproduce a document defect without a private manuscript. [CONTRIBUTING.md](../CONTRIBUTING.md) requires synthetic or redistribution-cleared fixtures; this guide is the one place that explains how to choose a fixture, create one, inspect it for private data, record where it came from, and keep originals untouched.

Existing fixtures live in [`Audit/QA/fixtures/`](../Audit/QA/fixtures) and are described by [`manifest.json`](../Audit/QA/fixtures/manifest.json). [`Scripts/qa/generate-fixtures.py`](../Scripts/qa/generate-fixtures.py) regenerates them deterministically, and [`Scripts/qa/verify-fixtures.py`](../Scripts/qa/verify-fixtures.py) checks the recorded SHA-256 values and import markers:

```sh
python3 Scripts/qa/verify-fixtures.py
```

## 1. Choose an existing fixture first

| Fixture | What it covers |
| --- | --- |
| `synthetic-0001` to `synthetic-1000-page-import.rtf` | Rich-text import at 1, 10, 50, 100, 391, 500 and 1000 nominal pages, with Unicode text, bold/italic/underline runs, bullet notes, explicit page breaks and section breaks |
| `independent-floating-drawingml.docx` | A floating `wp:anchor` picture with `wp:wrapSquare`, one PNG, two text runs, no document properties and no external relationships |

Start from the smallest fixture that reproduces the defect and extend the test around it. [`IndependentDOCXFixtureAcceptanceTests.swift`](../Tests/BOLDWriterTests/IndependentDOCXFixtureAcceptanceTests.swift) is the model: it takes the fixture path from `BOLD_QA_DOCX_FIXTURE`, writes evidence to `BOLD_QA_DOCX_REPORT`, and asserts package contents before and after import. Add a second fixture only when the existing one cannot express the defect, and say in the pull request why it cannot.

Page counts in the RTF fixtures are nominal: they come from explicit page breaks, so rendered pagination must still be measured independently.

## 2. Create a new fixture

Extend `Scripts/qa/generate-fixtures.py` instead of hand-editing bytes. The generator writes original synthetic prose, builds the placeholder PNG with `synthetic_png()`, and pins every ZIP entry to `date_time=(2020, 1, 1, 0, 0, 0)`, so the same input always produces the same SHA-256.

1. Add or extend a builder (`write_docx` for DOCX; the RTF builders for page-import fixtures).
2. Use text you wrote for the fixture. Never paste manuscript prose, a published excerpt, a real cover, or a screenshot from someone's book.
3. Generate images with `synthetic_png()`. A photographed asset can carry EXIF, GPS and author tags that no DOCX check will show.
4. Register the fixture in `Audit/QA/fixtures/manifest.json`: `id`, `path`, `fixtureSHA256`, image hash or `attributes`, and `notes` describing what it proves.
5. Regenerate, then confirm `python3 Scripts/qa/verify-fixtures.py` prints `PASS` for every fixture.

For a native `.boldwriter` fixture, build the package from a synthetic manuscript through `BOLDWriterDocument.packageWrapper` in a focused test, or save a disposable document you created for the test. Never save a fixture from a document that was open for real work: `metadata.json` persists `notes`, comment authors and citation records with the values that were live in that session.

For a PDF fixture, export a synthetic manuscript (or use `Scripts/qa/render-pdf-pages.swift`) and then run the PDF checks in section 3. Do not commit a print proof of a real interior.

## 3. Inspect the fixture for private data

Run the block below from the repository root. It targets the checked-in example fixture, and `F` is the only line to change. Empty output under a heading means that check found nothing; record the empty result, not a guess.

```sh
F=Audit/QA/fixtures/independent-floating-drawingml.docx

printf '%s\n' '== package parts =='
unzip -Z1 "$F"

printf '%s\n' '== embedded text =='
for part in $(unzip -Z1 "$F" | grep -E '^word/(document|header[0-9]*|footer[0-9]*|comments|footnotes|endnotes)\.xml$'); do
    printf '%s\n' "--- $part"
    unzip -p "$F" "$part" | grep -o '<w:t[^>]*>[^<]*' | sed 's/<w:t[^>]*>//'
done
unzip -p "$F" word/comments.xml 2>/dev/null | grep -o 'w:\(author\|initials\)="[^"]*"' | sort -u

printf '%s\n' '== media hashes =='
for part in $(unzip -Z1 "$F" | grep -E '^word/media/'); do
    printf '%s  ' "$part"
    unzip -p "$F" "$part" | shasum -a 256 | cut -d' ' -f1
done

printf '%s\n' '== document properties =='
unzip -p "$F" docProps/core.xml docProps/app.xml docProps/custom.xml 2>/dev/null |
    tr '<' '\n' |
    grep -E '^(dc:creator|cp:lastModifiedBy|dc:title|dc:subject|dc:description|cp:keywords|dcterms:created|dcterms:modified|Company|Manager|Template)[ >]' ||
    printf '%s\n' '(no document properties)'

printf '%s\n' '== external relationships =='
for part in $(unzip -Z1 "$F" | grep -E '(^|/)_rels/[^/]*\.rels$'); do
    unzip -p "$F" "$part" | tr '<' '\n' | grep 'TargetMode="External"' | sed "s|^|$part: |"
done
```

The four checks answer the four questions a reviewer will ask:

- **Embedded text.** Every `w:t` run in the main document, headers, footers, comments, footnotes and endnotes must be fixture prose you wrote. Comment `w:author` and `w:initials` are names, not prose, and they travel with the file.
- **Media.** Every part under `word/media/` must be generated or licence-cleared artwork. Record each hash; the manifest's `imageSHA256` is what the acceptance test compares against, so a changed image is a changed fixture.
- **Metadata.** `docProps/core.xml` carries `dc:creator`, `cp:lastModifiedBy`, `dc:title`, `dc:subject` and `cp:keywords`; `docProps/app.xml` carries `Company`, `Manager` and `Template`. All of them must be synthetic or absent. A missing `docProps` part is the cleanest result and is what the checked-in DOCX fixture does.
- **External relationships.** Any `Relationship` with `TargetMode="External"` in a `_rels/*.rels` part is a URL or path stored in the file. A fixture must not point at an intranet host, a shared drive, a cloud document, a tracking URL, or a local home directory.

### Native `.boldwriter` packages

A native package is a directory: `content.rtfd/TXT.rtf` holds the text and `metadata.json` holds everything else.

```sh
P=/path/to/fixture.boldwriter
find "$P" -type f | sort
/usr/bin/textutil -convert txt -stdout "$P/content.rtfd"
python3 -m json.tool "$P/metadata.json" | grep -E '"(notes|author|url|localFilePath|quotation|sourceLocation|authorNote|title)"'
find "$P" -type f -print0 | xargs -0 shasum -a 256
```

Every value those keys return must be fixture material. `DocumentComment.author` defaults to `NSFullUserName()`, so a comment added in a real session records the author's macOS account name; `CitationSource.localFilePath` and `CitationSource.fileBookmark` can record an absolute path and a bookmark into a private file. Set synthetic values explicitly rather than relying on defaults.

### PDF

```sh
F=/path/to/fixture.pdf
strings "$F" | grep -E '/(Author|Creator|Producer|Title|Subject) ' | sort -u
strings "$F" | grep -o 'URI *([^)]*)' | sort -u
```

The first line must show only synthetic titles and authors, and the second must be empty or list only URLs you intend to publish.

## 4. Record source and license

The manifest entry is the record. It states the fixture's path, its SHA-256, what it contains and what it proves, and `generator` names the script that produced it. A fixture produced by `Scripts/qa/generate-fixtures.py` is original work covered by the project's MIT licence; write that in the `notes` field.

If a fixture is adapted from third-party material, also:

- add a row to [the third-party inventory](ThirdPartyAttribution.md) with the upstream project, pinned revision, licence and the files used;
- keep the upstream licence text next to the adapted asset;
- confirm the licence permits redistribution inside an MIT-licensed application before you commit the bytes.

If you cannot state where a fixture came from and under which licence, do not commit it.

## 5. Keep originals untouched

- Work on a copy. Record the source hash before you start (`shasum -a 256 "$F"`) and again after the import, and expect the same value; every BOLD Writer import and export path must leave the source bytes alone.
- Never open an author's document in the app to obtain a fixture, and never attach one to an issue or discussion.
- The acceptance test refuses to overwrite evidence: it fails when `BOLD_QA_DOCX_REPORT` already exists, so each run writes to a new path.
- Local QA output is not a fixture. Keep it outside the repository; `Scripts/qa/run-qa.sh` writes its output to a separate run directory.

## 6. Recorded result on the example fixture

Following section 3 on `Audit/QA/fixtures/independent-floating-drawingml.docx` at source commit `a7a9380`, with the block run from the repository root:

```text
== package parts ==
[Content_Types].xml
_rels/.rels
word/_rels/document.xml.rels
word/document.xml
word/media/floating.png
== embedded text ==
--- word/document.xml
Before anchor
After anchor
== media hashes ==
word/media/floating.png  0ced92978c3552c182a5a01ad01717bcc93cf1669be2c215b4f2012475b71783
== document properties ==
(no document properties)
== external relationships ==
```

The result matches `manifest.json`: one PNG whose hash equals `imageSHA256`, the two paragraph texts the acceptance test asserts, no document properties, no external relationship, and five package parts. `python3 Scripts/qa/verify-fixtures.py` reports `PASS independent-floating-drawingml` for the same file, and `IndependentDOCXFixtureAcceptanceTests` is the test that consumes it.

## 7. Reviewer checklist

- The manifest entry exists and its SHA-256 matches the committed file.
- Every text run, comment author, media part and property in section 3 is synthetic or licence-cleared.
- No `TargetMode="External"` relationship and no `localFilePath` in a native package.
- The generator produces the fixture deterministically; `verify-fixtures.py` passes.
- Source and licence are recorded, with a [third-party inventory](ThirdPartyAttribution.md) row when the material came from somewhere else.
- The pull request names the fixture path and hash, and states which checks produced no output.
