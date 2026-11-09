import Foundation
import CoreGraphics
import CoreText
import PDFKit
import Testing
@testable import ImageCore

@MainActor struct MediaTests {
    private var tools: MediaTools {
        MediaTools(directory: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/Codecs"))
    }

    @Test func pdfProfilesRetainTextAndPagesAndSaveAsPDF() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("document.pdf")
        try makePDF(input)
        let attributes = try input.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let source = try MediaInspector.inspectPDF(url: input, root: root, bytes: Int64(attributes.fileSize!), modified: attributes.contentModificationDate!)
        #expect(source.kind == .pdf && source.media?.pages == 1 && source.isEligible)
        for profile in PDFProfile.allCases {
            let result = try await MediaEncoder.encode(source, pdfProfile: profile, video: VideoSettings(), tools: tools) { _ in }
            defer { result.discard() }
            #expect(result.file.pathExtension == "pdf" && result.bytes > 0)
            let document = try #require(PDFDocument(url: result.file))
            #expect(document.pageCount == 1)
            #expect(document.string?.contains("Chonko PDF test") == true)
            if profile == .smaller { #expect(result.bytes < source.bytes) }
            let saved = try await CandidateStore.save(result, mode: .alongside, folder: nil, policy: ScanPolicy(), allowLarger: true)
            #expect(saved.url.pathExtension == "pdf")
            #expect(FileManager.default.fileExists(atPath: input.path))
        }
    }

    @Test func videoBitrateReductionPreservesDurationFramesAndAudio() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("clip.mp4")
        _ = try await ExternalProcess.run(tools.tool("ffmpeg"), ["-v", "error", "-nostdin", "-y", "-f", "lavfi", "-i", "testsrc2=size=640x360:rate=24", "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000", "-t", "4", "-c:v", "h264_videotoolbox", "-b:v", "6000000", "-c:a", "aac", "-b:a", "128k", "-pix_fmt", "yuv420p", input.path])
        let values = try input.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let source = try await MediaInspector.inspectVideo(url: input, root: root, bytes: Int64(values.fileSize!), modified: values.contentModificationDate!, tools: tools)
        #expect(source.isEligible && source.media?.audioStreams == 1)
        for mode in VideoEncodingMode.allCases {
            var settings = VideoSettings(); settings.mode = mode; settings.bitratePercent = 20
            let stages = MediaTestStages()
            let result = try await MediaEncoder.encode(source, pdfProfile: .preserve, video: settings, tools: tools, progress: { _ in }) { await stages.append($0) }
            let updates = await stages.values
            #expect(updates.contains { $0.stage.contains("Перевірка") && $0.fraction >= 0.9 })
            #expect(updates.contains { $0.fraction > 0 && $0.fraction <= 0.9 })
            #expect(!updates.contains { $0.stage.contains("із 2") })
            defer { result.discard() }
            let record = try await MediaInspector.inspectVideo(url: result.file, root: root, bytes: result.bytes, modified: .now, tools: tools)
            #expect(record.width == source.width && record.height == source.height)
            #expect(abs((record.media?.duration ?? 0) - (source.media?.duration ?? 0)) < 0.25)
            #expect(record.media?.audioStreams == 1)
            #expect(result.bytes < source.bytes)
            #expect((record.media?.bitrate ?? .max) < (source.media?.bitrate ?? 0))
            print("VIDEO_RESULT \(mode.rawValue): \(source.bytes) -> \(result.bytes) bytes")
            #expect(FileManager.default.fileExists(atPath: input.path))
        }
        var previewSettings = VideoSettings(); previewSettings.bitratePercent = 30
        for automatic in [false, true] {
            let preview = try await VideoPreviewService.create(source, settings: previewSettings, automatic: automatic, tools: tools) { _ in }
            defer { preview.discard() }
            #expect(preview.similarity != nil && preview.duration <= 10)
            #expect(FileManager.default.fileExists(atPath: preview.file.path))
            let previewInfo = try await MediaInspector.inspectVideo(url: preview.file, root: preview.directory, bytes: 0, modified: .now, tools: tools)
            #expect(previewInfo.media?.duration ?? 0 > 0)
            #expect(preview.bitratePercent >= previewSettings.bitratePercent)
            #expect(FileManager.default.fileExists(atPath: input.path))
        }
    }

    @Test func processCancellationAndTimeoutDoNotHang() async throws {
        let running = Task { try await ExternalProcess.run(URL(fileURLWithPath: "/bin/sleep"), ["30"]) }
        try await Task.sleep(for: .milliseconds(40))
        running.cancel()
        do { _ = try await running.value; Issue.record("Cancellation was ignored") }
        catch is CancellationError {} catch { Issue.record("Unexpected cancellation error: \(error)") }
        do {
            _ = try await ExternalProcess.run(URL(fileURLWithPath: "/bin/sleep"), ["30"], timeout: .milliseconds(50))
            Issue.record("Timeout was ignored")
        } catch { #expect(error.localizedDescription.contains("очікування")) }
    }

    @Test func targetBitrateAndMediaStatisticsAreIndependentOfImageFormats() {
        var settings = VideoSettings(); settings.bitratePercent = 25
        #expect(settings.targetBitrate(source: 8_000_000) == 2_000_000)
        var history = OptimizationStatistics()
        history.record(original: 1000, result: 300, formatName: "PDF")
        history.record(original: 2000, result: 500, formatName: "HEVC / H.265")
        #expect(history.totals.files == 2 && history.totals.savedBytes == 2200)
        #expect(history.formats["PDF"]?.files == 1)
    }

    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Chonko-media-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makePDF(_ url: URL) throws {
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let consumer = try #require(CGDataConsumer(url: url as CFURL))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        let text = NSAttributedString(string: "Chonko PDF test", attributes: [NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 18, nil)])
        context.textPosition = CGPoint(x: 50, y: 740)
        CTLineDraw(CTLineCreateWithAttributedString(text), context)
        let size = 1200
        var seed: UInt64 = 123
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            seed = seed &* 6364136223846793005 &+ 1
            pixels[offset] = UInt8(truncatingIfNeeded: seed >> 32)
            pixels[offset + 1] = UInt8(truncatingIfNeeded: seed >> 40)
            pixels[offset + 2] = UInt8(truncatingIfNeeded: seed >> 48)
            pixels[offset + 3] = 255
        }
        let data = Data(pixels)
        let provider = try #require(CGDataProvider(data: data as CFData))
        let image = try #require(CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        context.draw(image, in: CGRect(x: 50, y: 160, width: 500, height: 500))
        context.endPDFPage(); context.closePDF()
    }
}

private actor MediaTestStages {
    var values: [MediaProgress] = []
    func append(_ value: MediaProgress) { values.append(value) }
}
