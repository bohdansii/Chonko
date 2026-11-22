import Foundation
import CoreGraphics
import ImageIO
import Testing
@testable import ImageCore

struct ImageResizeTests {
    private var codec: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/Codecs/cwebp")
    }

    @Test(arguments: OutputFormat.allCases.filter(\.isAvailable))
    func resizingRetainsActualInputFormat(format: OutputFormat) async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let base = try fixture(root.appendingPathComponent("base.png"), width: 201, height: 99)
        let converted = try await ImageEncoder.encode(base, settings: EncodeSettings(format: format), codecURL: codec) { _ in }
        defer { converted.discard() }
        let input = root.appendingPathComponent("input." + format.fileExtension)
        try FileManager.default.copyItem(at: converted.file, to: input)
        let source = try record(input)
        let hash = try ImageEncoder.sha256(input)
        var settings = EncodeSettings(); settings.preserveInputFormat = true; settings.scalePercent = 50
        let result = try await ImageEncoder.encode(source, settings: settings, codecURL: codec) { _ in }
        defer { result.discard() }
        let before = try #require(CGImageSourceCreateWithURL(input as CFURL, nil))
        let after = try #require(CGImageSourceCreateWithURL(result.file as CFURL, nil))
        #expect(CGImageSourceGetType(before) == CGImageSourceGetType(after))
        let image = try #require(CGImageSourceCreateImageAtIndex(after, 0, nil))
        #expect(image.width == 101 && image.height == 50)
        #expect(result.settings.format == format)
        #expect(try ImageEncoder.sha256(input) == hash)
        #expect(try FileManager.default.contentsOfDirectory(at: result.directory, includingPropertiesForKeys: nil).count == 1)
    }

    @Test(arguments: [true, false])
    func resizeKeepsTransparencyAndOrientation(preserveMetadata: Bool) async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try fixture(root.appendingPathComponent("rotated.png"), width: 200, height: 100, alpha: true, orientation: 6)
        var settings = EncodeSettings(lossless: true, preserveMetadata: preserveMetadata); settings.scalePercent = 50
        let result = try await ImageEncoder.encode(source, settings: settings, codecURL: codec) { _ in }
        defer { result.discard() }
        let output = try #require(CGImageSourceCreateWithURL(result.file as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(output, 0, nil) as? [CFString: Any])
        let image = try #require(CGImageSourceCreateImageAtIndex(output, 0, nil))
        #expect(image.width == 100 && image.height == 50)
        #expect(properties[kCGImagePropertyOrientation] as? Int == 6)
        #expect(properties[kCGImagePropertyHasAlpha] as? Bool == true)
        if preserveMetadata, let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            #expect(exif[kCGImagePropertyExifPixelXDimension] as? Int == 100)
            #expect(exif[kCGImagePropertyExifPixelYDimension] as? Int == 50)
        }
        let context = try #require(CGContext(data: nil, width: 100, height: 50, bitsPerComponent: 8, bytesPerRow: 400, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: 100, height: 50))
        let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        #expect(pixels[3] < 255 && pixels[3] > 0)
    }

    @Test func hdrResizeKeepsOriginalAndProducesSDR() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try #require(Bundle.module.url(forResource: "hdr-gainmap", withExtension: "jpg", subdirectory: "Fixtures"))
        let input = root.appendingPathComponent("hdr.jpg")
        try FileManager.default.copyItem(at: fixture, to: input)
        var settings = EncodeSettings(); settings.preserveInputFormat = true; settings.scalePercent = 25; settings.allowHDRToSDR = true
        let result = try await ImageEncoder.encode(record(input), settings: settings, codecURL: codec) { _ in }
        defer { result.discard() }
        let output = try #require(CGImageSourceCreateWithURL(result.file as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(output, 0, nil))
        #expect(image.width == 16 && image.height == 16 && result.retainsOriginal)
        #expect(CGImageSourceCopyAuxiliaryDataInfoAtIndex(output, 0, kCGImageAuxiliaryDataTypeISOGainMap) == nil)
    }

    @Test func resizeAllowsWebPWhenOriginalExceedsWebPLimit() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try fixture(root.appendingPathComponent("wide.png"), width: 18000, height: 20)
        var settings = EncodeSettings(); settings.scalePercent = 50
        let result = try await ImageEncoder.encode(source, settings: settings, codecURL: codec) { _ in }
        defer { result.discard() }
        let output = try #require(CGImageSourceCreateWithURL(result.file as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(output, 0, nil))
        #expect(image.width == 9000 && image.height == 10)
    }

    @Test func unsupportedOriginalAndInvalidScaleKeepSource() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try fixture(root.appendingPathComponent("still.gif"), width: 30, height: 20, type: "com.compuserve.gif")
        let hash = try ImageEncoder.sha256(source.url)
        var settings = EncodeSettings(); settings.preserveInputFormat = true; settings.scalePercent = 50
        do {
            _ = try await ImageEncoder.encode(source, settings: settings, codecURL: codec) { _ in }
            Issue.record("An unsupported original format was silently converted")
        } catch { #expect(error.localizedDescription.contains("поточний формат")) }
        settings.preserveInputFormat = false
        for scale in [0, 101] {
            settings.scalePercent = scale
            do {
                _ = try await ImageEncoder.encode(source, settings: settings, codecURL: codec) { _ in }
                Issue.record("Invalid scale was accepted")
            } catch { #expect(error.localizedDescription.contains("10%")) }
        }
        #expect(try ImageEncoder.sha256(source.url) == hash)
    }

    @Test func resizedJPEGCanReplaceUsingTrashWithoutChangingExtension() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try fixture(root.appendingPathComponent("photo.jpeg"), width: 600, height: 200, type: "public.jpeg")
        var settings = EncodeSettings(); settings.preserveInputFormat = true; settings.scalePercent = 50
        let candidate = try await ImageEncoder.encode(source, settings: settings, codecURL: codec) { _ in }
        #expect(candidate.file.pathExtension == "jpeg")
        let saved = try await CandidateStore.save(candidate, mode: .replace, folder: nil, policy: ScanPolicy(), allowLarger: true)
        let trashed = try #require(saved.trashedOriginal)
        defer { try? FileManager.default.removeItem(at: trashed) }
        #expect(!FileManager.default.fileExists(atPath: source.url.path))
        #expect(saved.url.pathExtension == "jpeg")
        let output = try #require(CGImageSourceCreateWithURL(saved.url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(output, 0, nil))
        #expect(image.width == 300 && image.height == 100)
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Chonko-resize-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func record(_ url: URL) throws -> ImageRecord {
        let info = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return ImageScanner.inspect(url: url, root: url.deletingLastPathComponent(), bytes: Int64(info.fileSize!), modified: info.contentModificationDate!)
    }
    private func fixture(_ url: URL, width: Int, height: Int, alpha: Bool = false, orientation: Int = 1, type: String = "public.png") throws -> ImageRecord {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: (alpha ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast).rawValue))
        context.setFillColor(CGColor(red: 0.3, green: 0.5, blue: 0.8, alpha: alpha ? 0.5 : 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation, kCGImagePropertyExifDictionary: [kCGImagePropertyExifPixelXDimension: width, kCGImagePropertyExifPixelYDimension: height]] as CFDictionary)
        try #require(CGImageDestinationFinalize(destination))
        return try record(url)
    }
}
