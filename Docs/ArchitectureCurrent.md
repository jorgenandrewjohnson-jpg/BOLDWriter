# Current architecture

BOLD Writer is a native SwiftUI/AppKit macOS app. `BOLDWriterDocument` owns the canonical attributed manuscript and metadata in a `.boldwriter` package. The editor, pagination, PDF export, and 3D interior consume that manuscript state. `CoverProject` owns editable cover layers; cover export and 3D textures consume that project state.

```text
DOCX/other import → BOLDWriterDocument → PaginatedEditor / PDFExporter → PDF pages → 3D interior
                                      ↘ Book Health inspection
CoverProject layers → cover raster / print proof → 3D front, spine, and back textures
```

`DocumentCore` contains the native models, cover operations, page geometry, and preflight checks. `Editor` bridges AppKit text editing and paginated views. `ImportExport` reads and writes DOCX/OPC and publication formats. `UI` presents manuscript, cover, and book workspaces. `App` coordinates document lifecycle and bounded acceptance runners. Tests are in `Tests/BOLDWriterTests`.

DOCX import treats unknown structures carefully. Supported floating pictures have independent metadata and original image bytes; unsupported drawings may be held as opaque package parts. The importer must not quietly discard artwork. The exporter reconstructs supported structures and validates required package pieces. Native save uses `FileWrapper` rather than editing the source DOCX in place. Exact Word layout for every construct is not claimed.

The cover editor stores image bytes and non-destructive layer properties separately: placement, crop, mask, visibility, lock state, grouping, and transforms. Rendering to PDF or a 3D texture does not replace the editable cover project.

The 3D Studio uses a native scene and paginated PDF page textures. Interactive preview resolution is distinct from print output; texture resources are bounded and identical cover rasters are reused across scene poses. Render-runner evidence does not replace GUI acceptance.

SwiftPM and Xcode compile the same Swift sources. The `LAMEEncoder` C target contains vendored LAME 3.100 source under separate LGPL terms. Other native frameworks include PDFKit, Core Graphics, SceneKit, AppKit, and SwiftUI. There is no JavaScript or Rust runtime embedded for the nine source-harvest repositories. See [third-party attribution](ThirdPartyAttribution.md).

This document describes the current module boundaries. See [current development status](OpenSourceStatus.md) for acceptance limits.
