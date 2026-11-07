# MP3 encoder dependency

The host's current Core Audio tool lists MPEG Layer III, but a real `afconvert` encode attempt failed with `ExtAudioFileSetProperty ('cfmt') failed ('fmt?')`. An `AVAudioConverter` from 44.1 kHz stereo PCM to `kAudioFormatMPEGLayer3` was also unavailable (`init(from:to:)` returned nil). A production app therefore cannot assume Apple's decoder-facing format identifier implies an installed encoder.

M2 vendors the LAME 3.100 C encoder source from the official SourceForge project archive. It compiles into the app from source for the active architecture; no prebuilt Homebrew/FFmpeg installation or runtime subprocess is needed. The SwiftPM C target and the synchronized Xcode source group use the same vendored source. The Swift layer calls a narrow C bridge and writes/reads bounded PCM buffers.

Provenance, SHA-256, upstream COPYING, and selected source files are recorded in `Sources/BOLDWriter/AudioProduction/LAME/`. The vendored source identifies itself as LGPL v2 or later. Before commercial distribution, legal review must confirm the exact LGPL relinking/source obligations for this application's distribution model and evaluate any applicable patent or codec distribution requirements. This engineering note is not legal advice. No unsupported platform acceptance is claimed.

Official references:

- [Apple Core Audio MPEG Layer III format identifier](https://developer.apple.com/documentation/coreaudiotypes/kaudioformatmpeglayer3)
- [Apple AVAudioConverter supported conversions and encoding](https://developer.apple.com/documentation/avfaudio/avaudioconverter)
- [LAME project](https://lame.sourceforge.io/)
- [LAME source downloads](https://lame.sourceforge.io/download.php)
