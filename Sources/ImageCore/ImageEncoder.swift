import Foundation
import ImageIO
import CryptoKit

public enum ImageEncoder {
    @concurrent public static func encode(_ source: ImageRecord, settings: EncodeSettings, codecURL: URL, progress: @Sendable (Double?) async -> Void) async throws -> EncodedCandidate {
        try Task.checkCancellation()
        guard source.isEligible else { throw ImageFailure.message(source.restriction ?? L("Файл не підтримується.")) }
        guard settings.format.isAvailable else { throw ImageFailure.message(L("Системний кодек \(settings.format.title) недоступний у цій macOS. Обери інший формат.")) }
        if settings.format == .webp && (source.width > 16383 || source.height > 16383) { throw ImageFailure.message(L("WebP підтримує максимум 16 383 × 16 383 пікселі.")) }
        if settings.format == .jpeg && source.hasAlpha { throw ImageFailure.message(L("JPEG не підтримує прозорість. Обери WebP або PNG.")) }
        if settings.lossless && !settings.format.supportsLossless { throw ImageFailure.message(L("Для \(settings.format.title) у цьому застосунку немає режиму без втрат. Обери PNG, TIFF або WebP.")) }
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent("ImageOptim-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        var keep = false
        defer { if !keep { try? fm.removeItem(at: directory) } }
        let input = directory.appendingPathComponent("input." + source.url.pathExtension)
        let output = directory.appendingPathComponent("result." + settings.format.fileExtension)
        let values = try fm.attributesOfItem(atPath: source.url.path)
        guard values[.type] as? FileAttributeType == .typeRegular, (values[.size] as? NSNumber)?.int64Value == source.bytes, values[.modificationDate] as? Date == source.modified else {
            throw ImageFailure.message(L("Оригінал змінився після сканування. Проскануй папку повторно."))
        }
        try fm.copyItem(at: source.url, to: input)
        let digest = try sha256(input)
        guard try sha256(source.url) == digest else { throw ImageFailure.message(L("Файл змінюється іншою програмою. Спробуй пізніше.")) }
        let snapshot = ImageScanner.inspect(url: input, root: directory, bytes: source.bytes, modified: source.modified)
        guard snapshot.isEligible else { throw ImageFailure.message(snapshot.restriction ?? L("Зображення більше не підтримується.")) }
        if settings.format == .jpeg && snapshot.hasAlpha { throw ImageFailure.message(L("JPEG не підтримує прозорість. Обери WebP або PNG.")) }
        await progress(nil)
        if settings.format == .webp {
            guard fm.isExecutableFile(atPath: codecURL.path) else { throw ImageFailure.message(L("Не знайдено вбудований кодек cwebp.")) }
            let directlySupported: Set<String> = ["jpg", "jpeg", "png", "webp", "tif", "tiff"]
            let inputSource = CGImageSourceCreateWithURL(input as CFURL, nil)
            let properties = inputSource.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }
            let orientation = properties?[kCGImagePropertyOrientation] as? Int ?? 1
            let retainOrientationOnly = !settings.preserveMetadata && orientation != 1
            var webpInput = input
            if !directlySupported.contains(source.url.pathExtension.lowercased()) || retainOrientationOnly {
                webpInput = directory.appendingPathComponent("decoded-input.png")
                try nativeEncode(input: input, output: webpInput, settings: EncodeSettings(format: .png, preserveMetadata: settings.preserveMetadata))
                try Task.checkCancellation()
            }
            try await runWebP(input: webpInput, output: output, settings: settings, retainOrientationOnly: retainOrientationOnly, codecURL: codecURL, progress: progress)
            if webpInput != input { try fm.removeItem(at: webpInput) }
        } else {
            try nativeEncode(input: input, output: output, settings: settings)
        }
        try Task.checkCancellation()
        // Force a full decode before any source can be moved to Trash.
        guard let decodedSource = CGImageSourceCreateWithURL(output as CFURL, nil), CGImageSourceGetCount(decodedSource) == 1,
              let image = CGImageSourceCreateImageAtIndex(decodedSource, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary), image.width == source.width, image.height == source.height else {
            throw ImageFailure.message(L("Результат не пройшов перевірку читання та розмірів. Оригінал збережено."))
        }
        let bytes = Int64(try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        guard bytes > 0 else { throw ImageFailure.message(L("Кодек створив порожній файл.")) }
        try fm.removeItem(at: input)
        keep = true
        await progress(1)
        return EncodedCandidate(source: source, directory: directory, file: output, bytes: bytes, sourceDigest: digest, settings: settings)
    }

    private static func runWebP(input: URL, output: URL, settings: EncodeSettings, retainOrientationOnly: Bool, codecURL: URL, progress: @Sendable (Double?) async -> Void) async throws {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = codecURL
        var arguments = settings.webpArguments
        // The private PNG contains only orientation metadata when metadata removal is requested.
        if retainOrientationOnly, let index = arguments.firstIndex(of: "-metadata") { arguments[index + 1] = "icc,exif" }
        process.arguments = arguments + [input.path, "-o", output.path]
        process.standardError = pipe
        process.standardOutput = FileHandle.nullDevice
        let (exits, exitContinuation) = AsyncStream<Int32>.makeStream(bufferingPolicy: .bufferingNewest(1))
        process.terminationHandler = { child in
            exitContinuation.yield(child.terminationStatus)
            exitContinuation.finish()
        }
        defer { exitContinuation.finish() }
        try Task.checkCancellation()
        try process.run()
        try? pipe.fileHandleForWriting.close()
        // Install termination handling before launch so a fast encoder cannot race completion.
        try await withTaskCancellationHandler {
            var tail = "", previous = -1
            let expression = try NSRegularExpression(pattern: "(\\d{1,3})%")
            while true {
                let data = pipe.fileHandleForReading.availableData
                if data.isEmpty { break }
                tail += String(decoding: data, as: UTF8.self)
                let matches = expression.matches(in: tail, range: NSRange(tail.startIndex..., in: tail))
                if let match = matches.last, let range = Range(match.range(at: 1), in: tail), let value = Int(tail[range]), value != previous {
                    previous = value
                    await progress(Double(value) / 100)
                }
                if tail.count > 5000 { tail = String(tail.suffix(2500)) }
                if Task.isCancelled && process.isRunning { process.terminate() }
            }
            var exitStatus: Int32?
            for await status in exits { exitStatus = status; break }
            try Task.checkCancellation()
            guard exitStatus == 0 else { throw ImageFailure.message("WebP: " + String(tail.suffix(600))) }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }

    private static func nativeEncode(input: URL, output: URL, settings: EncodeSettings) throws {
        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw ImageFailure.message(L("Не вдалося відкрити зображення.")) }
        guard let uti = settings.format.imageIOType else { throw ImageFailure.message(L("Цей формат потребує окремого кодека.")) }
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, uti as CFString, 1, nil) else { throw ImageFailure.message(L("Не вдалося створити результат.")) }
        var properties: [CFString: Any] = [:]
        if settings.preserveMetadata { properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:] }
        else if let original = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any], let orientation = original[kCGImagePropertyOrientation] { properties[kCGImagePropertyOrientation] = orientation }
        if !settings.format.alwaysLossless {
            properties[kCGImageDestinationLossyCompressionQuality] = settings.lossless ? 1.0 : Double(settings.quality) / 100
        }
        if settings.format == .tiff {
            var tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
            tiff[kCGImagePropertyTIFFCompression] = 5 // LZW, lossless.
            properties[kCGImagePropertyTIFFDictionary] = tiff
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ImageFailure.message(L("Не вдалося записати \(settings.format.title). Кодек може не підтримувати це зображення; також перевір вільне місце. Оригінал збережено.")) }
    }

    public static func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
