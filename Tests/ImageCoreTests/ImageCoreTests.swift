import Foundation
import ImageIO
import Testing
@testable import ImageCore

struct ImageCoreTests {
    let fm = FileManager.default
    var codec: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/Codecs/cwebp") }

    @Test func systemResourcesAreProtected() {
        let policy = ScanPolicy(excludedFiles: ["/Users/test/Pictures/current.jpg"])
        for path in ["/System/Library/a.png", "/Library/Desktop Pictures/a.jpg", "/Applications/Test.app/a.png", "/Users/test/Library/a.png", "/Users/test/Pictures/Main.photoslibrary/a.jpg", "/Users/test/Pictures/current.jpg"] {
            #expect(policy.excludes(URL(fileURLWithPath: path)))
        }
        #expect(!policy.excludes(URL(fileURLWithPath: "/Users/test/Pictures/holiday.jpg")))
        let temporary = fm.temporaryDirectory.appendingPathComponent("saved-result.webp")
        #expect(ScanPolicy(excludedFiles: [temporary.path]).excludes(temporary))
    }

    @Test func qualityIsNotLossless() {
        let lossy = EncodeSettings(quality: 100)
        #expect(!lossy.webpArguments.contains("-lossless"))
        let lossless = EncodeSettings(lossless: true)
        #expect(lossless.webpArguments.contains("-lossless"))
        #expect(lossless.webpArguments.contains("-exact"))
        #expect(EncodeSettings(quality: 0).quality == 1)
        #expect(EncodeSettings(quality: 200).quality == 100)
    }

    @Test func eightBitHDRGainMapJPEGIsProtected() throws {
        let url = try #require(Bundle.module.url(forResource: "hdr-gainmap", withExtension: "jpg", subdirectory: "Fixtures"))
        let image = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyDepth] as? Int == 8)
        #expect(CGImageSourceGetCount(image) == 1)
        #expect(CGImageSourceCopyAuxiliaryDataInfoAtIndex(image, 0, kCGImageAuxiliaryDataTypeISOGainMap) != nil)
        let attributes = try fm.attributesOfItem(atPath: url.path)
        let record = ImageScanner.inspect(url: url, root: url.deletingLastPathComponent(), bytes: (attributes[.size] as? NSNumber)!.int64Value, modified: attributes[.modificationDate] as! Date)
        #expect(record.isEligible)
        #expect(record.requiresSDRConversion)
    }

    @Test func hdrConversionRequiresConsentAndKeepsOriginal() async throws {
        let original = try #require(Bundle.module.url(forResource: "hdr-gainmap", withExtension: "jpg", subdirectory: "Fixtures"))
        let root = try directory()
        defer { try? fm.removeItem(at: root) }
        let input = root.appendingPathComponent("hdr.jpg")
        try fm.copyItem(at: original, to: input)
        let values = try input.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let record = ImageScanner.inspect(url: input, root: root, bytes: Int64(values.fileSize!), modified: values.contentModificationDate!)
        let hash = try ImageEncoder.sha256(input)
        var settings = EncodeSettings(format: .webp)
        do {
            _ = try await ImageEncoder.encode(record, settings: settings, codecURL: codec) { _ in }
            Issue.record("HDR converted without consent")
        } catch { #expect(error.localizedDescription.contains("підтвердження")) }
        settings.allowHDRToSDR = true
        for format in [OutputFormat.webp, .png, .jpeg] {
            settings.format = format
            let candidate = try await ImageEncoder.encode(record, settings: settings, codecURL: codec) { _ in }
            #expect(candidate.retainsOriginal)
            let decoded = try #require(CGImageSourceCreateWithURL(candidate.file as CFURL, nil))
            #expect(CGImageSourceCopyAuxiliaryDataInfoAtIndex(decoded, 0, kCGImageAuxiliaryDataTypeISOGainMap) == nil)
            let props = try #require(CGImageSourceCopyPropertiesAtIndex(decoded, 0, nil) as? [CFString: Any])
            #expect(props[kCGImagePropertyDepth] as? Int == 8)
            let saved = try await CandidateStore.save(candidate, mode: .replace, folder: nil, policy: ScanPolicy(), allowLarger: true)
            #expect(saved.trashedOriginal == nil)
            #expect(try ImageEncoder.sha256(input) == hash)
        }
    }

    @Test func scanSkipsPackagesAndSymlinksAndDeduplicates() async throws {
        let root = try directory()
        defer { try? fm.removeItem(at: root) }
        _ = try fixture(at: root.appendingPathComponent("normal.png"))
        let package = root.appendingPathComponent("Test.app", isDirectory: true)
        try fm.createDirectory(at: package, withIntermediateDirectories: true)
        _ = try fixture(at: package.appendingPathComponent("internal.png"))
        try fm.createSymbolicLink(at: root.appendingPathComponent("link.png"), withDestinationURL: root.appendingPathComponent("normal.png"))
        let collector = Collector()
        _ = try await ImageScanner.scan(roots: [root, root], policy: ScanPolicy()) { records in await collector.add(records) }
        let records = await collector.records
        #expect(records.count == 1)
        #expect(records.first?.isEligible == true)
    }

    @Test func webpLosslessRoundTripAndNoOverwrite() async throws {
        let root = try directory()
        defer { try? fm.removeItem(at: root) }
        let source = try fixture(at: root.appendingPathComponent("drawing.png"))
        let originalHash = try ImageEncoder.sha256(source.url)
        let candidate = try await ImageEncoder.encode(source, settings: EncodeSettings(lossless: true), codecURL: codec) { _ in }
        defer { candidate.discard() }
        #expect(try pixels(source.url) == pixels(candidate.file))
        let collision = root.appendingPathComponent("drawing.webp")
        try Data("existing file".utf8).write(to: collision)
        let result = try await CandidateStore.save(candidate, mode: .alongside, folder: nil, policy: ScanPolicy(), allowLarger: true)
        #expect(result.url.lastPathComponent == "drawing-optimized-1.webp")
        #expect(try String(contentsOf: collision, encoding: .utf8) == "existing file")
        #expect(try ImageEncoder.sha256(source.url) == originalHash)
    }

    @Test func largerResultsRequireDecision() async throws {
        let root = try directory()
        defer { try? fm.removeItem(at: root) }
        let source = try fixture(at: root.appendingPathComponent("photo.jpg"), jpeg: true)
        let candidate = try await ImageEncoder.encode(source, settings: EncodeSettings(lossless: true), codecURL: codec) { _ in }
        defer { candidate.discard() }
        #expect(candidate.isLarger)
        await #expect(throws: (any Error).self) {
            try await CandidateStore.save(candidate, mode: .replace, folder: nil, policy: ScanPolicy())
        }
        #expect(fm.fileExists(atPath: source.url.path))
        let result = try await CandidateStore.save(candidate, mode: .alongside, folder: nil, policy: ScanPolicy(), allowLarger: true)
        #expect(fm.fileExists(atPath: result.url.path))
        #expect(fm.fileExists(atPath: source.url.path))
    }

    @Test func changedOriginalIsNeverReplaced() async throws {
        let root = try directory()
        defer { try? fm.removeItem(at: root) }
        let source = try fixture(at: root.appendingPathComponent("drawing.png"))
        let candidate = try await ImageEncoder.encode(source, settings: EncodeSettings(), codecURL: codec) { _ in }
        defer { candidate.discard() }
        try Data("edited elsewhere".utf8).write(to: source.url)
        await #expect(throws: (any Error).self) {
            try await CandidateStore.save(candidate, mode: .replace, folder: nil, policy: ScanPolicy(), allowLarger: true)
        }
        #expect(try String(contentsOf: source.url, encoding: .utf8) == "edited elsewhere")
    }

    @Test(arguments: [OutputFormat.png, .jpeg, .avif, .heic, .tiff, .jpeg2000]) func nativeFormatsDecode(format: OutputFormat) async throws {
        let root = try directory()
        defer { try? fm.removeItem(at: root) }
        let source = try fixture(at: root.appendingPathComponent("drawing.png"))
        let candidate = try await ImageEncoder.encode(source, settings: EncodeSettings(format: format), codecURL: codec) { _ in }
        defer { candidate.discard() }
        #expect(candidate.bytes > 0)
        if format.alwaysLossless { #expect(try pixels(source.url) == pixels(candidate.file)) }
    }

    @Test(arguments: [OutputFormat.png, .tiff, .jpeg2000]) func nativeLosslessIsPixelExact(format: OutputFormat) async throws {
        let root = try directory()
        defer { try? fm.removeItem(at: root) }
        let source = try fixture(at: root.appendingPathComponent("original.png"))
        let candidate = try await ImageEncoder.encode(source, settings: EncodeSettings(format: format, lossless: true), codecURL: codec) { _ in }
        defer { candidate.discard() }
        #expect(try pixels(source.url) == pixels(candidate.file))
    }

    @Test(arguments: ["heic", "heif", "avif", "bmp", "gif", "jp2", "tga", "ico"]) func additionalInputsConvertToWebP(ext: String) async throws {
        let root = try directory()
        defer { try? fm.removeItem(at: root) }
        let base = try fixture(at: root.appendingPathComponent("base.png"))
        let sourceImage = try #require(CGImageSourceCreateWithURL(base.url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(sourceImage, 0, nil))
        let types = ["heic": "public.heic", "heif": "public.heic", "avif": "public.avif", "bmp": "com.microsoft.bmp", "gif": "com.compuserve.gif", "jp2": "public.jpeg-2000", "tga": "com.truevision.tga-image", "ico": "com.microsoft.ico"]
        let input = root.appendingPathComponent("input." + ext)
        let dest = try #require(CGImageDestinationCreateWithURL(input as CFURL, types[ext]! as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.6] as CFDictionary)
        try #require(CGImageDestinationFinalize(dest))
        let attrs = try fm.attributesOfItem(atPath: input.path)
        let record = ImageScanner.inspect(url: input, root: root, bytes: (attrs[.size] as! NSNumber).int64Value, modified: attrs[.modificationDate] as! Date)
        #expect(record.isEligible)
        let result = try await ImageEncoder.encode(record, settings: EncodeSettings(lossless: true), codecURL: codec) { _ in }
        defer { result.discard() }
        #expect(try pixels(input) == pixels(result.file))
    }

    @Test func formatQualityScalesAndSizePercentagesAreDistinct() {
        #expect(EncodeSettings(format: .avif, quality: 100).quality == 99)
        #expect(EncodeSettings(format: .jpeg2000, quality: 100).quality == 99)
        #expect(EncodeSettings(format: .heic, quality: 100).quality == 100)
        #expect(!OutputFormat.heic.supportsLossless)
        #expect(!OutputFormat.avif.supportsLossless)
        #expect(OutputFormat.tiff.alwaysLossless)
        #expect(FileSizeChange(originalBytes: 4_000_000, resultBytes: 1_000_000).percentReduction == 75)
        #expect(FileSizeChange(originalBytes: 100, resultBytes: 120).percentReduction == -20)
        #expect(FileSizeChange(originalBytes: 100, resultBytes: 100).summary == "Вага та сама")
        #expect(FileSizeChange(originalBytes: 0, resultBytes: 10).percentReduction == nil)
        #expect(FileSizeChange(originalBytes: 10_000, resultBytes: 9_999).summary.contains("<0,1"))
    }

    @Test(arguments: OutputFormat.allCases) func transparencyIsRetainedOrExplicitlyRejected(format: OutputFormat) async throws {
        let root = try directory()
        defer { try? fm.removeItem(at: root) }
        let image = try #require(CGContext(data: nil, width: 64, height: 32, bitsPerComponent: 8, bytesPerRow: 256, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        image.clear(CGRect(x: 0, y: 0, width: 64, height: 32))
        image.setFillColor(red: 1, green: 0, blue: 0, alpha: 0.5)
        image.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        let url = root.appendingPathComponent("alpha.png")
        let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(dest, try #require(image.makeImage()), nil)
        try #require(CGImageDestinationFinalize(dest))
        let attrs = try fm.attributesOfItem(atPath: url.path)
        let record = ImageScanner.inspect(url: url, root: root, bytes: (attrs[.size] as! NSNumber).int64Value, modified: attrs[.modificationDate] as! Date)
        if format == .jpeg {
            await #expect(throws: (any Error).self) { try await ImageEncoder.encode(record, settings: EncodeSettings(format: format), codecURL: codec) { _ in } }
        } else {
            let result = try await ImageEncoder.encode(record, settings: EncodeSettings(format: format), codecURL: codec) { _ in }
            defer { result.discard() }
            let output = try pixels(result.file)
            #expect(output.contains(0))
            let source = try #require(CGImageSourceCreateWithURL(result.file as CFURL, nil))
            let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            #expect([CGImageAlphaInfo.premultipliedLast, .premultipliedFirst, .last, .first].contains(decoded.alphaInfo))
        }
    }

    @Test(arguments: [true, false]) func orientationSurvivesWebPMetadataChoice(preserve: Bool) async throws {
        let root = try directory()
        defer { try? fm.removeItem(at: root) }
        let base = try fixture(at: root.appendingPathComponent("base.png"))
        let original = try #require(CGImageSourceCreateWithURL(base.url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(original, 0, nil))
        let url = root.appendingPathComponent("rotated.heic")
        let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.heic" as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, [kCGImagePropertyOrientation: 6, kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 50.0, kCGImagePropertyGPSLatitudeRef: "N", kCGImagePropertyGPSLongitude: 30.0, kCGImagePropertyGPSLongitudeRef: "E"]] as CFDictionary)
        try #require(CGImageDestinationFinalize(dest))
        let attrs = try fm.attributesOfItem(atPath: url.path)
        let record = ImageScanner.inspect(url: url, root: root, bytes: (attrs[.size] as! NSNumber).int64Value, modified: attrs[.modificationDate] as! Date)
        let result = try await ImageEncoder.encode(record, settings: EncodeSettings(lossless: true, preserveMetadata: preserve), codecURL: codec) { _ in }
        defer { result.discard() }
        func orientation(_ url: URL) throws -> Int {
            let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
            return (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])?[kCGImagePropertyOrientation] as? Int ?? 1
        }
        #expect(try orientation(url) == orientation(result.file))
        if !preserve {
            let source = try #require(CGImageSourceCreateWithURL(result.file as CFURL, nil))
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            #expect(properties?[kCGImagePropertyGPSDictionary] == nil)
        }
    }

    @Test func animatedGIFRemainsProtected() throws {
        let root = try directory()
        defer { try? fm.removeItem(at: root) }
        let base = try fixture(at: root.appendingPathComponent("base.png"))
        let source = try #require(CGImageSourceCreateWithURL(base.url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let url = root.appendingPathComponent("animation.gif")
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "com.compuserve.gif" as CFString, 2, nil))
        for _ in 0..<2 { CGImageDestinationAddImage(destination, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary) }
        try #require(CGImageDestinationFinalize(destination))
        let attrs = try fm.attributesOfItem(atPath: url.path)
        let record = ImageScanner.inspect(url: url, root: root, bytes: (attrs[.size] as! NSNumber).int64Value, modified: attrs[.modificationDate] as! Date)
        #expect(!record.isEligible)
        #expect(record.restriction?.contains("Анімації") == true)
    }

    @Test(.timeLimit(.minutes(1))) func rapidEncoderExitsDoNotBlockCompletion() async throws {
        let root = try directory()
        defer { try? fm.removeItem(at: root) }
        let source = try fixture(at: root.appendingPathComponent("fast-exit.png"))
        let codec = codec
        let completed = try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<4 {
                group.addTask {
                    for _ in 0..<8 {
                        let candidate = try await ImageEncoder.encode(source, settings: EncodeSettings(), codecURL: codec) { _ in }
                        candidate.discard()
                    }
                    return 8
                }
            }
            var count = 0
            for try await countInGroup in group { count += countInGroup }
            return count
        }
        #expect(completed == 32)
    }

    @Test func concurrentSavesResolveNameCollisions() async throws {
        let root = try directory()
        defer { try? fm.removeItem(at: root) }
        let png = try fixture(at: root.appendingPathComponent("same.png"))
        let jpeg = try fixture(at: root.appendingPathComponent("same.jpg"), jpeg: true)
        let a = try await ImageEncoder.encode(png, settings: EncodeSettings(), codecURL: codec) { _ in }
        let b = try await ImageEncoder.encode(jpeg, settings: EncodeSettings(), codecURL: codec) { _ in }
        defer { a.discard(); b.discard() }
        async let first = CandidateStore.save(a, mode: .alongside, folder: nil, policy: ScanPolicy(), allowLarger: true)
        async let second = CandidateStore.save(b, mode: .alongside, folder: nil, policy: ScanPolicy(), allowLarger: true)
        let results = try await [first, second]
        #expect(results[0].url != results[1].url)
        #expect(results.allSatisfy { fm.fileExists(atPath: $0.url.path) })
    }

    @Test func folderModePreservesHierarchy() async throws {
        let root = try directory(), output = try directory()
        defer { try? fm.removeItem(at: root); try? fm.removeItem(at: output) }
        let sub = root.appendingPathComponent("trip", isDirectory: true)
        try fm.createDirectory(at: sub, withIntermediateDirectories: true)
        let source = try fixture(at: sub.appendingPathComponent("drawing.png"), root: root)
        let candidate = try await ImageEncoder.encode(source, settings: EncodeSettings(), codecURL: codec) { _ in }
        defer { candidate.discard() }
        let result = try await CandidateStore.save(candidate, mode: .folder, folder: output, policy: ScanPolicy(), allowLarger: true)
        #expect(result.url.path == output.appendingPathComponent(root.lastPathComponent).appendingPathComponent("trip/drawing.webp").path)
        #expect(fm.fileExists(atPath: source.url.path))
    }

    @Test func folderSaveFromWholeMacRootPreservesPath() async throws {
        let root = try directory(), output = try directory()
        defer { try? fm.removeItem(at: root); try? fm.removeItem(at: output) }
        let source = try fixture(at: root.appendingPathComponent("whole-mac.png"), root: URL(fileURLWithPath: "/"))
        let candidate = try await ImageEncoder.encode(source, settings: EncodeSettings(), codecURL: codec) { _ in }
        defer { candidate.discard() }
        let result = try await CandidateStore.save(candidate, mode: .folder, folder: output, policy: ScanPolicy(), allowLarger: true)
        let relative = String(source.url.deletingPathExtension().path.dropFirst()) + ".webp"
        #expect(result.url.path == output.appendingPathComponent("Mac").appendingPathComponent(relative).path)
        #expect(fm.fileExists(atPath: source.url.path))
    }

    @Test func cancelledSaveLeavesOriginalAndCandidateUntouched() async throws {
        let root = try directory()
        defer { try? fm.removeItem(at: root) }
        let source = try fixture(at: root.appendingPathComponent("cancel-save.png"))
        let candidate = try await ImageEncoder.encode(source, settings: EncodeSettings(), codecURL: codec) { _ in }
        defer { candidate.discard() }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await CandidateStore.save(candidate, mode: .replace, folder: nil, policy: ScanPolicy(), allowLarger: true)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(fm.fileExists(atPath: source.url.path))
        #expect(fm.fileExists(atPath: candidate.file.path))
        #expect(!fm.fileExists(atPath: root.appendingPathComponent("cancel-save.webp").path))
    }

    @Test func cancellationDoesNotSaveOrDelete() async throws {
        let root = try directory()
        defer { try? fm.removeItem(at: root) }
        let source = try fixture(at: root.appendingPathComponent("drawing.png"))
        let codec = codec
        let task = Task {
            try Task.checkCancellation()
            return try await ImageEncoder.encode(source, settings: EncodeSettings(), codecURL: codec) { _ in }
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(fm.fileExists(atPath: source.url.path))
        #expect(!fm.fileExists(atPath: root.appendingPathComponent("drawing.webp").path))
    }

    @Test func replacementEitherTrashesOriginalOrReportsRetention() async throws {
        let root = try directory()
        defer { try? fm.removeItem(at: root) }
        let source = try fixture(at: root.appendingPathComponent("replace-fixture-" + UUID().uuidString + ".png"))
        let originalHash = try ImageEncoder.sha256(source.url)
        let candidate = try await ImageEncoder.encode(source, settings: EncodeSettings(), codecURL: codec) { _ in }
        defer { candidate.discard() }
        let result = try await CandidateStore.save(candidate, mode: .replace, folder: nil, policy: ScanPolicy(), allowLarger: true)
        #expect(fm.fileExists(atPath: result.url.path))
        if let trash = result.trashedOriginal {
            #expect(!fm.fileExists(atPath: source.url.path))
            #expect(try ImageEncoder.sha256(trash) == originalHash)
            // Restore only the disposable fixture created by this test, then remove with its test directory.
            try fm.moveItem(at: trash, to: source.url)
        } else {
            #expect(result.warning != nil)
            #expect(try ImageEncoder.sha256(source.url) == originalHash)
        }
    }

    @Test func movingUnsupportedImagesPreservesExistingFiles() async throws {
        let root = try directory(), destination = try directory()
        defer { try? fm.removeItem(at: root); try? fm.removeItem(at: destination) }
        let source = root.appendingPathComponent("vector.svg")
        try Data("<svg>original</svg>".utf8).write(to: source)
        let values = try source.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let record = ImageScanner.inspect(url: source, root: root, bytes: Int64(values.fileSize!), modified: values.contentModificationDate!)
        #expect(!record.isEligible)
        let collision = destination.appendingPathComponent("vector.svg")
        try Data("existing".utf8).write(to: collision)
        let report = await ImageFileManager.perform(.move(destination), on: [record], policy: ScanPolicy()) { _, _ in }
        #expect(report.succeeded == [record.id])
        #expect(!fm.fileExists(atPath: source.path))
        #expect(try String(contentsOf: collision, encoding: .utf8) == "existing")
        #expect(try String(contentsOf: destination.appendingPathComponent("vector-1.svg"), encoding: .utf8) == "<svg>original</svg>")
    }

    @Test func fileActionsRefuseChangedAndProtectedFiles() async throws {
        let root = try directory(), destination = try directory()
        defer { try? fm.removeItem(at: root); try? fm.removeItem(at: destination) }
        let record = try fixture(at: root.appendingPathComponent("protected.png"))
        let protected = await ImageFileManager.perform(.trash, on: [record], policy: ScanPolicy(excludedFiles: [record.id])) { _, _ in }
        #expect(protected.succeeded.isEmpty)
        #expect(fm.fileExists(atPath: record.url.path))
        try Data("changed".utf8).write(to: record.url)
        let changed = await ImageFileManager.perform(.move(destination), on: [record], policy: ScanPolicy()) { _, _ in }
        #expect(changed.succeeded.isEmpty)
        #expect(changed.failures.count == 1)
        #expect(try String(contentsOf: record.url, encoding: .utf8) == "changed")
    }

    private func directory() throws -> URL {
        let root = fm.temporaryDirectory.appendingPathComponent("ImageOptim-test-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func fixture(at url: URL, jpeg: Bool = false, root: URL? = nil) throws -> ImageRecord {
        let size = 256
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let i = (y * size + x) * 4
                bytes[i] = UInt8(x); bytes[i + 1] = UInt8(y); bytes[i + 2] = UInt8((x * 3 + y * 7) % 256); bytes[i + 3] = 255
            }
        }
        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
        let image = try #require(CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, (jpeg ? "public.jpeg" : "public.png") as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.3] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return ImageScanner.inspect(url: url, root: root ?? url.deletingLastPathComponent(), bytes: Int64(values.fileSize!), modified: values.contentModificationDate!)
    }

    private func pixels(_ url: URL) throws -> Data {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let context = try #require(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Data(bytes: try #require(context.data), count: image.width * image.height * 4)
    }
}

private actor Collector {
    var records: [ImageRecord] = []
    func add(_ batch: [ImageRecord]) { records.append(contentsOf: batch) }
}
