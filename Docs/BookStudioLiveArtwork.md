# Live artwork in 3D Book Studio

In 3D Book Studio, drag to orbit and scroll to zoom. Select a layer in **Live
cover artwork** to change its position, size, rotation, text, image fit, crop,
flips or opacity while viewing the book. Position and size use inches measured
from the full wrap's top-left corner, including bleed. Rotation uses degrees.
Layer locks are respected. Use **Continue in Cover Creator** for the full cover
editor, imports, layer creation, masks, linked layers and advanced typography.

Both workspaces use the same `CoverProject` and layer IDs in document metadata.
There is no export/import step, flattened replacement image, or separate 3D
artwork copy. Changes support document undo/redo and persist with the document.
Camera/model presentation transforms do not alter print artwork. Manuscript
content remains editable through **Edit Manuscript** and is rendered from its
pagination pipeline.

## Physical rendering corrections

- Decorative leaves use the manuscript surface's gutter orientation and profile,
  offset underneath it. Previously they crossed the print and hid text strips.
- Open camera presets use the same curved paper assembly instead of switching
  between incompatible rigid and curved geometry.
- Both halves share the opening angle. The front board's center is derived from
  its actual hinge rotation; each cover contacts its own stack's underside.
  Center gaps must differ when the turned and remaining stacks have different
  thicknesses. Mirroring the gaps moved the cover into the manuscript.
- Closed camera framing targets the book center instead of its spine.

## Reference evidence and limits

The supplied Pacdora audits demonstrate artwork placement, surface selection,
orbit/camera controls and a shared design/preview workflow. The mapping capture
contains identity UV-transform observations but no captured UV buffers, texture
uploads, or physical book equations. The Vectary audit covers public feature
pages rather than an exercised editor. These inform interaction design; they
cannot establish exact printer construction math.

This remains a geometric print preview, not a paper mechanics simulation or a
printer-certified production proof. Trim, caliper, page count and binding must
match the intended production specification. The open spine is still simplified;
this change does not claim physically simulated case binding or paper flex.
Direct dragging of individual artwork on the mesh is not provided: use the live
artwork inspector or the shared Cover Creator canvas.

## Reproducible verification

`./Scripts/bold test BookStudioArtworkEditingTests` checks shared project identity,
save/reload, undo/redo isolation, invalid edits and underlying leaf geometry.
To produce synthetic visual proofs and a disposable native document:

```sh
BOLD_STUDIO_PROOF_DIR=/tmp/bold-studio-proof ./Scripts/bold test BookStudioArtworkEditingTests
```

Inspect `closed.png`, `partial.png`, `reading.png` and `flat.png`. The fixture uses
synthetic cover artwork and manuscript textures, not a private user manuscript.
Physical support/contact and common-gutter regression suites additionally cover
different bindings and unequal page stacks.
