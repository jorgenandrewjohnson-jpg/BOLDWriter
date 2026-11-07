# Third-party source and attribution

BOLD Writer's top-level source is MIT licensed. This inventory does not replace component license texts or a distribution review.

| Component | Use in BOLD Writer | License and notice |
| --- | --- | --- |
| WordCraft (`storytold/wordcraft`, pinned `8c57b0775ce70736047db6d291ae77c53b27da7c`) | Native Swift adaptations of DOCX picture crop and wrap-polygon representation, import/export, and text exclusion. | MIT OR Apache-2.0 upstream; MIT option recorded in [`WordCraft-LICENSE-MIT.txt`](ThirdParty/WordCraft-LICENSE-MIT.txt). Source comments and the engineering registry name the original files. |
| Fabric.js (`fabricjs/fabric.js`, pinned `5157cd00903e75da3240eb3c952adc4c71ba8ab2`) | Native rotated-corner geometry used for cover snapping, alignment, and transform bounds. | MIT; [`FabricJS-LICENSE.txt`](ThirdParty/FabricJS-LICENSE.txt). |
| LAME 3.100 | Vendored C source for MP3 encoding. | LGPL v2 or later materials, [`COPYING`](../Sources/BOLDWriter/AudioProduction/LAME/COPYING), [`LICENSE.upstream`](../Sources/BOLDWriter/AudioProduction/LAME/LICENSE.upstream), and [`PROVENANCE.md`](../Sources/BOLDWriter/AudioProduction/LAME/PROVENANCE.md). Binary distribution needs a separate relinking/source-obligation review. |

Scribus, Vivliostyle, Tiptap, PDF.js, Three.js, PhotoCraft, and ArtCraft were studied for relevant engineering. Their source is not automatically included or relicensed by this inventory. The source comments and retained notices distinguish actual adaptations from architectural references. No GPL/AGPL source was copied into the MIT app merely because a public repository exposed it.

Contributors must review file-level notices, transitive dependencies, and asset rights before adding new third-party code or media. Keep the source archives in the separate research workspace untouched; they are not release artifacts.
