# Third-party components

Chonko uses Apple's system frameworks and invokes independent bundled tools as separate local executables, exchanging ordinary files and command-line arguments. The original Chonko source is not under an open-source license; that notice does not restrict any rights provided by these components' licenses.

| Component | Version | License / location |
|---|---|---|
| Google libwebp / cwebp / dwebp | 1.6.0 | BSD-style; `Resources/Codecs/COPYING`, `AUTHORS`, `PATENTS` |
| libpng / zlib / libjpeg-turbo (official WebP distribution) | 1.6.47 / 1.3.1 / 3.1.0 | Upstream notices in `Resources/Codecs/ThirdParty/` |
| FFmpeg / ffprobe | 9.0.2 | GPL-enabled build; `Resources/Codecs/ThirdParty/FFmpeg-*` |
| x265 | 4.1 | GPLv2 or later; `Resources/Codecs/ThirdParty/x265-COPYING.txt` |
| Ghostscript and bundled URW fonts | 10.08.0 | AGPLv3 and upstream notices; `Resources/Codecs/ThirdParty/Ghostscript-*` |
| qpdf | 12.4.2 | Apache-2.0; `Resources/Codecs/ThirdParty/qpdf-LICENSE.txt` |
| libjpeg-turbo | 3.1.2 (qpdf build) | Upstream BSD/IJG/zlib terms; `Resources/Codecs/ThirdParty/libjpeg-turbo-LICENSE.md` |

The release asset **Chonko-codec-sources-v1.1.1.zip** contains source archives, a pinned official Google WebP ARM64 distribution, hashes and reproduction scripts. Keep it with the corresponding binaries when redistributing third-party components. Exact upstream URLs and SHA-256 checksums are in `scripts/media-sources.json` and `Resources/Codecs/ThirdParty/sources.json`.

FFmpeg is statically built with x265. x265 CMake policies CMP0025/CMP0054 are changed from OLD to NEW for CMake 4 compatibility, and assembly is disabled; the build script contains the exact changes. Ghostscript, qpdf and FFmpeg build settings are recorded in `scripts/`. WebP executables are the pinned, unmodified official Google distribution; the matching libwebp source is included separately.

Apple frameworks are provided by macOS and are not redistributed here. No permission concerning Apple's names or trademarks is granted by this repository.
