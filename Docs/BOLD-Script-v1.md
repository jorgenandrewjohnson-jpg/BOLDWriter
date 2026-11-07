# BOLD Script v1

BOLD Script v1 is a JSON document-operation format. It is data, not Swift,
JavaScript, shell, or another executable language. Pasting a script never runs
it. Automation Studio validates it, builds a preview against the currently
open document, and waits for the author to choose **Apply Changes**.

## Manifest

```json
{
  "format": "bold-script",
  "version": 1,
  "title": "Normalize chapter headings",
  "target": { "scope": "document" },
  "operations": [
    {
      "type": "normalizeHeadings",
      "rules": [
        { "paragraphPrefix": "Chapter ", "style": "Heading 1" }
      ]
    }
  ]
}
```

Unknown keys, operations, targets, styles, malformed values, and stale revision
preconditions are rejected before mutation. Version 1 targets the open document
only. Selected ranges, batch files, regular expressions, and general-purpose
code are not supported by this initial runtime.

An optional `preconditions` object may contain `documentRevision` with the UUID
shown in the preview diagnostics. If the document changes before approval, the
script is rejected and must be previewed again.

## Supported operations

* `replaceText`: exact, case-sensitive literal replacement throughout the
  document. Note references are protected and conflicting table structure is
  rejected.
* `formatText`: exact literal match with any of `fontFamily`, `fontSize`,
  `bold`, and `italic`.
* `setParagraphStyle`: apply a built-in paragraph style to paragraphs beginning
  with `paragraphPrefix`.
* `normalizeHeadings`: apply one or more prefix-to-Heading-1-through-6 rules.
* `insertFloatingImage`: insert an image from an absolute local path on a
  1-based page using point-based geometry, optional rotation, wrap mode, layer,
  and position lock. The path is read when Automation Studio creates the
  preview; applying the plan stores the image bytes in the document model.
* `updateFloatingImage`: update an existing image by its stable `imageID` with
  position, size, rotation, wrapping, layer, or lock values.

Floating-image records are persisted in native `metadata.json` and included in
the script Undo group. PDF pagination uses TextKit exclusion paths for square,
alpha-contour tight, and top/bottom wrapping; no-wrap leaves the text layout
unmodified. PDF drawing respects page/margin geometry, rotation, z-order, and
front/behind text layering. Tight contours are sampled from source alpha at up
to 512 by 512 cells. Paragraph and character targets rebase with simple text
edits and fall back to their saved page position if their target is deleted.
Before an approved script changes floating images, the application atomically
writes the complete prior native package to a bounded Application Support
recovery folder. On reopening the unchanged manuscript, Automation Studio offers
to restore the matching package. This is separate from the normal Undo action.

The live manuscript canvas does not yet draw or hit-test these floating objects,
so the GUI currently exposes no drag handles or image inspector. The shared
model and PDF pipeline are in place, but full GUI editing and matching onscreen
exclusion geometry remain incomplete.

DOCX export is explicitly refused when floating objects are present because
the current DOCX writer cannot represent their anchored positions faithfully.

The machine-readable schema is [`../Schemas/BOLD-Script-v1.schema.json`](../Schemas/BOLD-Script-v1.schema.json).

Formatting parameters and style names are checked before planning. An
operation with no matches is reported as zero changes; it is never guessed at.
The whole candidate is checked for table integrity before it can be approved.
An approved run is committed in one native Undo action.

See [`../Examples/AutomationScripts/normalize-chapter-headings.boldscript`](../Examples/AutomationScripts/normalize-chapter-headings.boldscript)
and [`../Examples/AutomationScripts/standardize-manuscript-format.boldscript`](../Examples/AutomationScripts/standardize-manuscript-format.boldscript).
