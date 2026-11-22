# Changelog

## 1.2.0 — 2026-11-22

- Resize selected images with 1×, 0.75×, 0.5× and 0.25× presets, or a custom 0–90% reduction of width and height.
- Keep aspect ratio with whole-pixel rounding; never upscale.
- Choose Original Format to resize JPEG, PNG, WebP, HEIC/HEIF, TIFF, JPEG 2000 and AVIF without changing image formats where encoding is available.
- Show a live dimensions example and each result’s pixel dimensions.
- Preserve orientation, transparency and supported metadata, and validate the requested output dimensions before saving.
- Retain HDR conversion warnings and existing file protection, original-change checks and Trash replacement.

## 1.1.1 — 2026-11-14

- Default all three media modes to verified replacement, moving originals to Trash only after a successful save.
- Keep explicit conversion warnings and original retention for HDR→SDR and approved PDF feature loss.
- Includes the PDF repair and confirmed-conversion changes described below.

## 1.1.0 — 2026-11-14

Internal build; these fixes are included in the public 1.1.1 release.

- Accept qpdf's warning-only exit status during structural repair, then strictly check and validate the repaired result.
- Offer interactive/tagged PDFs a choice between Preserve Quality or explicitly confirmed lossy compression of a copy.
- Allow HDR/high-bit-depth photos to become 8-bit SDR copies after a clear warning; retain originals even if Replace was selected.
- Show repair/conversion notices per file and record confirmations/validation in local diagnostics.

## 1.0.0 — 2026-11-09

First public release of Chonko for Apple Silicon Macs running macOS 26 or later.

- Local image, PDF and video optimization; Ukrainian and English interface.
- File/folder selection, drag and drop, search filters and persistent ignored files.
- Image quality controls, format guidance and lossless options where supported.
- Three PDF profiles with document validation.
- Fast Apple hardware video encoding and single-pass Thorough HEVC encoding.
- Light, Balanced and Strong video compression, preview clips and SSIM-assisted suggestions.
- Per-file progress, approximate remaining time, Stop and Skip controls.
- Save alongside, save to a folder or verified replacement with originals moved to Trash.
- Persistent statistics and local exportable diagnostics.
- Native macOS controls, glass panels and animated mascot.

Earlier 0.x builds were private development versions.
