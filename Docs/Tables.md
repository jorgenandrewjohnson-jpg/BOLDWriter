# Structured editable tables

Choose **Insert > Table** or **Table > Insert Table…**, then choose the row and
column counts. Tables are inserted at the cursor. The default is 3 × 3; supported
sizes are 1–100 rows, 1–20 columns, and no more than 1,000 cells.

Click a cell and type directly in the document. Return adds a paragraph within
the cell. Tab moves to the next cell; Shift-Tab moves back. Tab in the final cell
adds a row when the size limit permits it. Click the paragraph below a table to
continue writing body text.

The **Table** menu operates on the cell containing the cursor:

- Add/delete a row or column, or delete the whole table. Deleting the last row or
  column deletes the table.
- Toggle the first row as a shaded header.
- Widen/narrow the current column. These commands adjust relative widths;
  dragging column borders is not implemented.

Cell text supports the normal editor formatting commands, search, and text
copy/paste. Select a complete table to copy its structure within BOLD Writer;
pasted tables receive new IDs. Pasting into a cell inserts plain text, using the
current typing format. Partial cross-cell edits that would destroy cell
boundaries are rejected; use the row/column/table commands for structural edits.
All edits and structural commands participate in the existing undo system.

## Persistence and exchange

Stable table and cell UUIDs, row/column positions, header state, and relative
widths are persisted in native metadata. Attributed cell contents remain part of
the document text. Native TextKit table blocks provide onscreen layout, borders,
padding, and PDF/print rendering. Recovery history preserves tables too.

Ordinary rectangular DOCX tables import as editable structured tables. DOCX
export writes real `w:tbl`, `w:tr`, and `w:tc` elements with grid widths, borders,
cell padding, and first-row header information. Common cell text formatting,
inline images, and footnotes use the existing import/export paths. Legacy
tab-delimited documents retain the existing DOCX export behavior; existing tab
text is not automatically converted to structured tables in the editor.

## Limits

- Merged cells, nested tables, irregular grids, formulas, and advanced table
  styling are not supported. Unsupported or malformed DOCX tables stop import
  with an explanatory error; the source file remains unchanged.
- Word styling beyond common text formatting, basic widths, and header state is
  not retained. Custom row heights and exact Word pagination are not retained.
- PDF and print use the existing TextKit pagination. Ordinary multi-page tables
  flow across pages; headers are not repeated and row splitting is controlled by
  TextKit. An unlayable row/image reports an export error rather than discarding
  content. There is no new onscreen pagination system.
- Internal whole-table copy/paste preserves structure. Advanced clipboard
  interoperability with other applications is not guaranteed. EPUB/Kindle EPUB
  preserves readable cell text through the existing exporter, not table layout;
  use DOCX or PDF when table structure/layout matters.
