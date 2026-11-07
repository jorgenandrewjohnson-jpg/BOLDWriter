# Structured footnotes

Use **Insert > Footnote** (Option-Command-F) at the cursor. Enter the note and
choose Save. Double-click a reference, or place the cursor on it and choose
**Insert > Edit Selected Footnote**, to edit or delete the note. The command
palette also offers Insert Footnote and Edit Footnote. Cancelling the editor
leaves a newly inserted empty note; Undo removes the insertion.

References have stable UUIDs and immutable text payloads within attributed text.
The editor's existing undo snapshots therefore include note content. Native
`.boldwriter` packages persist the reference locations, IDs, and note text in
`metadata.json`, restoring them onto the RTFD body when reopened. Recovery points
also preserve notes. Older packages without footnote metadata remain readable.
Numbers derive from document order, and deleting a reference deletes its note.

Print Layout and PDF place notes in a reserved area at the bottom of the physical
page containing each reference. `PageFootnotes.swift` derives a separator, measured
note fragments, and carry-over text from the document's plain-text note bodies.
`PaginatedEditor` and `PDFExporter` both shrink their TextKit body containers and
repeat layout (at most 32 passes) until the reservation covers the references
remaining on that page. The reservation only grows during one page's convergence;
this avoids an end-of-page reference oscillating between pages. A moved reference
can consequently leave extra white space on the preceding page, but its note is
drawn only on its final owning page. Notes longer than the available footnote
region continue on subsequent physical pages with a continued label. The minimum
body region is preserved, and the footnote region ends above the footer margin.
The layout plan is derived and is not persisted in `.boldwriter` files.

DOCX exports contain real `w:footnoteReference` elements, a related footnotes
part, content-type declaration, and separator notes. Imports resolve the actual
footnotes relationship and map Word IDs to new internal UUIDs in reference order.
The existing body text and image import path remains in use. Missing references,
duplicate IDs, external footnote parts, and unsupported note structures stop
import with an error, leaving the source unchanged.

## Current limitations

- Footnote content is editable plain text, including paragraphs, tabs, and line
  breaks. Formatting and hyperlink targets within imported notes are flattened.
  Notes containing images, tables, fields, nested references, or custom reference
  marks are rejected rather than silently dropping their content.
- Numbering is continuous Arabic numbering; Word section-based restart rules
  and custom numbering formats are not retained.
- Very dense pages with more new footnote references than can each receive one
  note line report a layout error instead of hiding or overlapping notes.
- RTF, plain-text, HTML, EPUB, and external clipboard interchange have no
  structured-footnote preservation guarantee. Use native files or DOCX.
- Existing manually typed superscript characters remain ordinary text; they
  cannot be reliably associated with note content automatically.
