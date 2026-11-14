<p align="center"><img src="design/Chonko-02-logo.svg" alt="Chonko" width="360"></p>

# Chonko

**Smaller files. More room. All on your Mac.**

Chonko is a native macOS app for local image, PDF and video compression, with English and Ukrainian interfaces.

[Download 1.1.1](https://github.com/bohdansii/Chonko/releases/tag/v1.1.1) · [Українською](README.uk.md) · [Report an issue](https://github.com/bohdansii/Chonko/issues)

## Install

Requires an **Apple Silicon Mac (M1 or later) running macOS 26+**. Intel Macs are not supported by this release.

1. Download `Chonko-v1.1.1.dmg` from [Releases](https://github.com/bohdansii/Chonko/releases/latest).
2. Open it and drag **Chonko.app** to **Applications**.
3. Launch it from Applications. Quit the previous version before updating.

This personal build is ad-hoc signed and **not notarized by Apple**. macOS may block a downloaded copy. If you trust this release, attempt to open it, then use **System Settings → Privacy & Security → Open Anyway**. Do not disable Gatekeeper globally. See [Apple's instructions](https://support.apple.com/102445). Installer checksums are in `SHA256SUMS.txt`.

No paid Apple Developer membership, Homebrew, terminal or account is required to use the app. Encoders are bundled.

## Features

- Images: WebP, JPEG, PNG, HEIC, TIFF, JPEG 2000 and AVIF when the system encoder is available; quality controls and supported lossless modes.
- PDF: Preserve Quality, Balanced and Smaller File profiles, with page/text validation.
- Video: supported MP4/MOV/M4V input to MP4, HEVC/H.264, compression presets and optional resolution limits.
- Individual files, folders, drag and drop, search filters, persistent ignored files and Reveal in Finder.
- Per-file progress, approximate video ETA, Stop and Skip controls.
- Save alongside, save to a chosen folder, or verified replacement with originals moved to Trash.
- Before/after comparison, persistent statistics and local diagnostic report export.
- Native macOS controls, glass panels and an animated mascot.

## First steps

Select **Images / PDF / Video**, choose files or a folder, review selection and output settings, then press **Optimize**. Processing never starts automatically on launch.

For video, start with **Fast → HEVC → Balanced**. Fast uses Apple's hardware encoder; Thorough uses single-pass software HEVC and takes longer. Preview Clip encodes a short excerpt. Suggest Compression compares samples at several bitrates; it does not optimize the entire file.

Light / Balanced / Strong retain **70% / 50% / 30% of the source video bitrate**. These are data targets, not quality percentages or guaranteed whole-file sizes. Audio contributes to the final size. Images, PDF and video default to verified replacement, with confirmation and originals moved to Trash after successful saving. Confirmed HDR→SDR and lossy PDF feature conversion save copies and retain originals.

## Safety and limits

System resources, application packages, Photos libraries, hidden folders, symbolic links and hard-linked files are skipped. Entire Mac searches accessible personal files of the selected type, respecting macOS permissions. Cloud-only files are not downloaded automatically.

Existing files are never overwritten. Originals changed during processing are not replaced. A result that is not smaller needs a manual Save or Discard decision. Copies and originals in Trash still occupy disk space; byte savings do not automatically equal reclaimed storage.

RAW and animated images are skipped. HDR/high-bit-depth photos can be converted to 8-bit SDR copies after a warning; HDR brightness is lost and originals are retained. Video supports one progressive 8-bit SDR track with compatible audio; HDR, Dolby Vision, subtitles and complex track layouts are not supported yet. Encrypted PDFs, forms and signatures are skipped; interactive or tagged PDFs offer Preserve Quality or confirmed lossy compression of a copy. Recoverable qpdf warnings no longer block structural repair; outputs still require validation. OCR and AV1 video encoding are not included. Mixed media types use separate batches.

Changing formats changes file extensions and may break references in other apps. Check copies of important files first. Lossy compression cannot guarantee visually identical results.

## Privacy and support

Processing stays **on your Mac**. Files are not uploaded, and diagnostic reports are never sent automatically.

Use **Diagnostics… → Export Report…**, then attach the JSON to an issue. After a crash, reopen Chonko before exporting. Reports include app/system details, job stages, redacted codec errors and up to 200 technical events; original filenames and paths are excluded. Check screenshots for private content before posting them publicly.

## Build

Swift 6, SwiftUI, AppKit, Swift Charts, ImageIO, PDFKit and AVKit; macOS 26+ target. Use compatible Xcode / Command Line Tools with Swift 6.2+ and a macOS 26+ SDK.

```sh
git clone https://github.com/bohdansii/Chonko.git
cd Chonko
swift test --disable-sandbox
bash build-app.sh
```

ARM64 tools are included in `Resources/Codecs`. To rebuild media tools and fetch the pinned official Google WebP package, run `python3 scripts/build-media-tools.py` (network required). The build script produces a DMG and ZIP in `releases/`, signing outside cloud-managed directories. It does not notarize the app.

## Rights and third-party software

© 2026 Bohdan ([@bohdansii](https://github.com/bohdansii)). The original Chonko source and branding are publicly visible **without an open-source license**. See [LICENSE](LICENSE).

Independent third-party components retain their own licenses and rights. Notices and corresponding codec sources accompany releases; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
