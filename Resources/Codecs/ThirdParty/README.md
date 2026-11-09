# Chonko media tools

Chonko invokes these executables as separate local processes:
- FFmpeg / ffprobe 9.0.2, GPL-enabled static build with x265 and Apple VideoToolbox.
- x265 4.1, GPLv2 or later; CMake policies CMP0025/CMP0054 changed to NEW for CMake 4 compatibility. Assembly disabled.
- Ghostscript 10.08.0, GNU AGPLv3; bundled URW fonts retain their upstream notices.
- qpdf 12.4.2, Apache-2.0, with static libjpeg-turbo 3.1.2 and native crypto.

Complete license texts accompany the binaries. Exact source URLs and SHA-256 hashes are in sources.json. Reproduction scripts are in the project's scripts directory. The matching codec source archive is delivered beside the installer in releases/Chonko-codec-sources-v1.0.0.zip; retain and distribute it with the corresponding binaries when sharing this build. Tools are built for ARM64 macOS 26.0 or later, without external runtime package managers.

Google libwebp 1.6.0 uses the pinned official ARM64 binaries; the exact distribution and matching upstream source archive accompany the release. See THIRD_PARTY_NOTICES.md at the repository root.
