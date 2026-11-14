import Foundation
import PDFKit
import CoreGraphics

public enum MediaEncoder {
    @concurrent public static func encode(_ source: ImageRecord, pdfProfile: PDFProfile, video: VideoSettings, tools: MediaTools, allowPDFLoss: Bool = false, progress: @escaping @Sendable (Double?) async -> Void, update: @escaping @Sendable (MediaProgress) async -> Void = { _ in }) async throws -> EncodedCandidate {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent("Chonko-media-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        var keep = false
        defer { if !keep { try? fm.removeItem(at: directory) } }
        try Task.checkCancellation()
        let attrs = try source.url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard attrs.isRegularFile == true, attrs.isSymbolicLink != true, Int64(attrs.fileSize ?? -1) == source.bytes,
              attrs.contentModificationDate == source.modified else { throw ImageFailure.message(L("Оригінал змінився після сканування. Додай файл повторно.")) }
        guard (try fm.attributesOfItem(atPath: source.url.path)[.referenceCount] as? Int ?? 1) <= 1 else { throw ImageFailure.message(L("Файл має жорсткі посилання: пропущено для безпечної заміни.")) }
        let input = directory.appendingPathComponent("input").appendingPathExtension(source.url.pathExtension)
        try fm.copyItem(at: source.url, to: input)
        let digest = try ImageEncoder.sha256(input)
        guard try ImageEncoder.sha256(source.url) == digest else { throw ImageFailure.message(L("Файл змінюється іншою програмою. Спробуй пізніше.")) }
        let snapshot = await MediaInspector.inspect(url: input, root: directory, bytes: source.bytes, modified: source.modified, tools: tools)
        guard snapshot.isEligible else { throw ImageFailure.message(snapshot.restriction ?? L("Файл більше не підтримується.")) }
        let output = directory.appendingPathComponent(source.kind == .pdf ? "result.pdf" : "result.mp4")
        await progress(nil)
        var notices: [String] = []
        if source.kind == .pdf {
            notices = try await encodePDF(input, output: output, source: snapshot, profile: pdfProfile, allowFeatureLoss: allowPDFLoss, tools: tools, progress: progress)
        } else {
            try await encodeVideo(input, output: output, source: snapshot, settings: video, tools: tools, progress: progress, update: update)
        }
        try Task.checkCancellation()
        let bytes = Int64(try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        guard bytes > 0 else { throw ImageFailure.message(L("Інструмент створив порожній файл.")) }
        try fm.removeItem(at: input)
        keep = true
        await progress(1)
        return EncodedCandidate(source: source, directory: directory, file: output, bytes: bytes, sourceDigest: digest, settings: EncodeSettings(), mediaFormat: source.kind == .pdf ? "PDF" : video.codec.title, notices: notices, retainsOriginal: source.kind == .pdf && allowPDFLoss && pdfProfile != .preserve && snapshot.media?.hasProtectedFeatures == true)
    }

    private static func encodePDF(_ input: URL, output: URL, source: ImageRecord, profile: PDFProfile, allowFeatureLoss: Bool, tools: MediaTools, progress: @escaping @Sendable (Double?) async -> Void) async throws -> [String] {
        var notices: [String] = []
        if profile == .preserve {
            let report = try await ExternalProcess.run(tools.tool("qpdf"), ["--object-streams=generate", "--compress-streams=y", "--recompress-flate", "--compression-level=9", input.path, output.path], successfulExitCodes: [0, 3])
            if String(decoding: report, as: UTF8.self).contains("WARNING:") {
                notices.append(L("Структуру PDF відновлено; результат пройшов перевірку."))
            }
        } else {
            guard source.media?.hasProtectedFeatures != true || allowFeatureLoss else {
                throw ImageFailure.message(L("PDF має інтерактивні елементи, вкладення або теги доступності. Обери «Зберегти якість»."))
            }
            let args = ["-dSAFER", "-dBATCH", "-dNOPAUSE", "-sDEVICE=pdfwrite", "-dCompatibilityLevel=1.7", "-dAutoRotatePages=/None", "-dPreserveAnnots=true", "-dDetectDuplicateImages=true", "-dDownsampleColorImages=true", "-dColorImageDownsampleType=/Bicubic", "-dColorImageResolution=\(profile.dpi)", "-dAutoFilterColorImages=false", "-dColorImageFilter=/DCTEncode", "-dDownsampleGrayImages=true", "-dGrayImageResolution=\(profile.dpi)", "-dDownsampleMonoImages=true", "-dMonoImageResolution=300", "-dAutoFilterGrayImages=false", "-dGrayImageFilter=/DCTEncode", "-dPassThroughJPEGImages=false", "-sOutputFile=\(output.path)", "-c", "<< /ColorImageDict << /QFactor \(profile.jpegQFactor) /Blend 1 /ColorTransform 1 >> /GrayImageDict << /QFactor \(profile.jpegQFactor) /Blend 1 >> >> setdistillerparams", "-f", input.path]
            let pages = max(1, source.media?.pages ?? 1)
            _ = try await ExternalProcess.run(tools.tool("gs"), args) { line in
                if line.hasPrefix("Page "), let page = Int(line.dropFirst(5).trimmingCharacters(in: .whitespaces)) {
                    await progress(min(0.9, Double(page) / Double(pages) * 0.9))
                }
            }
        }
        _ = try await ExternalProcess.run(tools.tool("qpdf"), ["--check", output.path], timeout: .seconds(60))
        try validatePDF(input: input, output: output, allowFeatureLoss: allowFeatureLoss && profile != .preserve)
        if allowFeatureLoss && profile != .preserve && source.media?.hasProtectedFeatures == true {
            notices.append(L("Спеціальні елементи PDF могли змінитися; оригінал збережено."))
        }
        return notices
    }

    private static func validatePDF(input: URL, output: URL, allowFeatureLoss: Bool) throws {
        guard let before = PDFDocument(url: input), let after = PDFDocument(url: output), before.pageCount == after.pageCount, !after.isEncrypted else {
            throw ImageFailure.message(L("PDF не пройшов перевірку сторінок. Оригінал збережено."))
        }
        for index in 0..<before.pageCount {
            try Task.checkCancellation()
            guard let a = before.page(at: index), let b = after.page(at: index) else { throw ImageFailure.message(L("Не вдалося перевірити сторінку PDF.")) }
            let ar = a.bounds(for: .mediaBox), br = b.bounds(for: .mediaBox)
            let normalize: (String?) -> String = { ($0 ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            guard abs(ar.width - br.width) < 1, abs(ar.height - br.height) < 1, a.rotation == b.rotation,
                  normalize(a.string) == normalize(b.string), (allowFeatureLoss || (a.annotations.count == b.annotations.count && zip(a.annotations, b.annotations).allSatisfy { $0.url == $1.url && $0.action?.type == $1.action?.type })) else {
                throw ImageFailure.message(L("Змінилися текст, розміри або примітки PDF. Оригінал збережено."))
            }
            // Render every page to exercise the result rather than trusting only its header.
            let image = b.thumbnail(of: CGSize(width: 256, height: 256), for: .mediaBox)
            guard image.size.width > 0 else { throw ImageFailure.message(L("Сторінка PDF не відкривається.")) }
        }
    }

    static func encodeVideo(_ input: URL, output: URL, source: ImageRecord, settings: VideoSettings, tools: MediaTools, range: Range<Double>? = nil, progress: @escaping @Sendable (Double?) async -> Void, update: @escaping @Sendable (MediaProgress) async -> Void = { _ in }) async throws {
        guard let info = source.media else { throw ImageFailure.message(L("Немає даних відео.")) }
        let duration = range.map { $0.upperBound - $0.lowerBound } ?? info.duration
        let bitrate = settings.targetBitrate(source: info.bitrate)
        let encoder = settings.mode == .compact && settings.codec == .hevc ? "libx265" : settings.codec == .hevc ? "hevc_videotoolbox" : "h264_videotoolbox"
        var base = ["-hide_banner", "-v", "error", "-nostdin", "-y"]
        if let range { base += ["-ss", String(range.lowerBound)] }
        base += ["-i", input.path]
        if range != nil { base += ["-t", String(duration)] }
        base += ["-map", "0:v:0", "-map", "0:a?", "-map_metadata", "0", "-c:v", encoder, "-b:v", String(bitrate), "-pix_fmt", "yuv420p", "-fps_mode", "passthrough", "-metadata:s:v:0", "rotate=0", "-c:a", "copy"]
        if settings.maximumHeight > 0 && source.height > settings.maximumHeight {
            base += ["-vf", "scale=-2:\(settings.maximumHeight)"]
        }
        if encoder == "libx265" { base += ["-preset", "medium", "-x265-params", "pools=4:frame-threads=2:log-level=error"] }
        else { base += ["-allow_sw", "0", "-maxrate", String(bitrate * 12 / 10), "-bufsize", String(bitrate * 2)] }
        if settings.codec == .hevc { base += ["-tag:v", "hvc1"] }
        base += ["-movflags", "+faststart", "-progress", "pipe:1", "-stats_period", "0.5", output.path]
        let initial = 0.0
        let stage = L("Стиснення відео")
        let reporter = VideoProgressReporter(stage: stage, duration: duration, initial: initial, weight: 0.9 - initial, progress: progress, update: update)
        await update(MediaProgress(stage: stage, fraction: initial, remainingSeconds: nil))
        _ = try await ExternalProcess.run(tools.tool("ffmpeg"), base, timeout: .seconds(max(1800, duration * 30))) { await reporter.receive($0) }
        await progress(0.9)
        await update(MediaProgress(stage: L("Перевірка результату"), fraction: 0.9, remainingSeconds: nil))
        let bytes = Int64(try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        let result = try await MediaInspector.inspectVideo(url: output, root: output.deletingLastPathComponent(), bytes: bytes, modified: .now, tools: tools)
        let resizing = settings.maximumHeight > 0 && source.height > settings.maximumHeight
        let expectedHeight = resizing ? settings.maximumHeight : source.height
        let expectedWidth = resizing ? Int((Double(source.width) * Double(expectedHeight) / Double(source.height) / 2).rounded()) * 2 : source.width
        guard let after = result.media, abs(after.duration - duration) <= max(0.25, 2 / max(info.frameRate, 1)),
              after.audioStreams == info.audioStreams,
              abs(after.frameRate - info.frameRate) < 0.1,
              result.width == expectedWidth && result.height == expectedHeight else {
            throw ImageFailure.message(L("Відео не пройшло перевірку тривалості, розмірів або доріжок. Оригінал збережено."))
        }
        let validation = VideoProgressReporter(stage: L("Перевірка результату"), duration: duration, initial: 0.9, weight: 0.09, progress: progress, update: update)
        _ = try await ExternalProcess.run(tools.tool("ffmpeg"), ["-v", "error", "-nostdin", "-xerror", "-i", output.path, "-map", "0:v:0", "-map", "0:a?", "-progress", "pipe:1", "-stats_period", "0.5", "-f", "null", "-"], timeout: .seconds(max(300, duration * 3))) { await validation.receive($0) }
    }
}
