import Foundation

public struct VideoPreview: Identifiable, Sendable {
    public let directory: URL
    public let file: URL
    public let original: URL
    public let start: Double
    public let duration: Double
    public let bitratePercent: Double
    public let similarity: Double?
    public var id: String { file.path }
    public func discard() { try? FileManager.default.removeItem(at: directory) }
}

public enum VideoPreviewService {
    @concurrent public static func create(_ source: ImageRecord, settings: VideoSettings, automatic: Bool, tools: MediaTools, progress: @escaping @Sendable (Double?) async -> Void) async throws -> VideoPreview {
        guard source.isEligible, let info = source.media, source.kind == .video, info.duration > 0 else { throw ImageFailure.message(L("Обери підтримуване відео.")) }
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent("Chonko-preview-" + UUID().uuidString)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        var keep = false
        defer { if !keep { try? fm.removeItem(at: directory) } }
        let input = directory.appendingPathComponent("input").appendingPathExtension(source.url.pathExtension)
        try fm.copyItem(at: source.url, to: input)
        let digest = try ImageEncoder.sha256(input)
        guard try ImageEncoder.sha256(source.url) == digest else { throw ImageFailure.message(L("Файл змінюється іншою програмою. Спробуй пізніше.")) }
        let length = min(automatic ? 3.0 : 10.0, info.duration)
        let offsets = automatic ? [0.1, 0.8, 0.45].map { max(0, min(info.duration - length, info.duration * $0)) } : [max(0, (info.duration - length) / 2)]
        let targets = automatic ? Array(Set([settings.bitratePercent, min(95, settings.bitratePercent + 20), min(95, settings.bitratePercent + 40)])).sorted() : [settings.bitratePercent]
        var bestFile: URL?, bestStart = 0.0, bestSimilarity: Double?, bestPercent = settings.bitratePercent
        var trial = 0
        for target in targets {
            var candidateSettings = settings; candidateSettings.bitratePercent = target
            var scores: [Double] = []
            for offset in offsets {
                try Task.checkCancellation()
                let output = directory.appendingPathComponent("trial-\(trial).mp4")
                trial += 1
                let number = trial, total = targets.count * offsets.count
                try await MediaEncoder.encodeVideo(input, output: output, source: source, settings: candidateSettings, tools: tools, range: offset..<(offset + length)) { fraction in
                    await progress((Double(number - 1) + (fraction ?? 0)) / Double(total))
                }
                let score = try await similarity(original: input, result: output, source: source, start: offset, seconds: length, tools: tools)
                scores.append(score)
                bestFile = output; bestStart = offset
            }
            bestSimilarity = scores.min(); bestPercent = target
            // SSIM is only a technical hint; the user still sees and approves a preview.
            if !automatic || (bestSimilarity ?? 0) >= 0.985 { break }
        }
        guard let bestFile, try ImageEncoder.sha256(source.url) == digest else { throw ImageFailure.message(L("Оригінал змінився під час перевірки. Результат відкинуто.")) }
        try fm.removeItem(at: input)
        for url in try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where url.standardizedFileURL.path != bestFile.standardizedFileURL.path { try? fm.removeItem(at: url) }
        keep = true
        await progress(1)
        return VideoPreview(directory: directory, file: bestFile, original: source.url, start: bestStart, duration: length, bitratePercent: bestPercent, similarity: bestSimilarity)
    }

    private static func similarity(original: URL, result: URL, source: ImageRecord, start: Double, seconds: Double, tools: MediaTools) async throws -> Double {
        // Match displayed dimensions before comparing; the preview may have been downscaled.
        let info = try await MediaInspector.inspectVideo(url: result, root: result.deletingLastPathComponent(), bytes: Int64(try result.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0), modified: .now, tools: tools)
        let filter = "[0:v]setpts=PTS-STARTPTS,scale=\(info.width):\(info.height),format=yuv420p[ref];[1:v]setpts=PTS-STARTPTS,format=yuv420p[dist];[ref][dist]ssim[score]"
        let data = try await ExternalProcess.run(tools.tool("ffmpeg"), ["-hide_banner", "-v", "info", "-nostdin", "-ss", String(start), "-i", original.path, "-i", result.path, "-filter_complex", filter, "-map", "[score]", "-an", "-t", String(seconds), "-f", "null", "-"], timeout: .seconds(300))
        let log = String(decoding: data, as: UTF8.self)
        guard let range = log.range(of: "All:", options: .backwards),
              let score = Double(log[range.upperBound...].prefix(while: { $0.isNumber || $0 == "." })), score.isFinite else {
            throw ImageFailure.message(L("Не вдалося оцінити тестовий фрагмент."))
        }
        return score
    }
}
