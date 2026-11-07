# LAME vendoring record

- Upstream project: https://lame.sourceforge.io/
- Source release: LAME 3.100 (2017-10-13), official SourceForge source archive `lame-3.100.tar.gz`.
- Download URL: https://downloads.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz
- Archive SHA-256: `ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e`
- Encoder code is distributed under LGPL version 2 or (at your option) any later version; see `COPYING` and source notices. Frontend/decoder sources are not included. The build configuration disables the bundled MPGLIB decoder and command line frontend.
- This package compiles LAME's C encoder sources directly into the application. This avoids any runtime Homebrew/FFmpeg dependency and keeps app-sandbox execution out of the pipeline. It also means release distribution must satisfy applicable LGPL source and relinkability obligations. Legal review is required before commercial distribution; no patent or codec-distribution opinion is made here.

Build config was generated on macOS using upstream `./configure --disable-shared --enable-static --disable-frontend --disable-decoder`. The committed `config.h` is a fixed macOS portability config with no machine-specific assembly. See `Docs/AudiobookProductionAPI.md` and `Docs/AudiobookMP3Dependency.md`.
