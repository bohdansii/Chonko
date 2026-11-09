import Foundation
import ImageIO
import Testing
import ImageCore
@testable import ImageOptimMac

@MainActor struct AppFeaturesTests {
    @Test func launchDoesNotScanAndFiltersAllowExplicitWebP() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "Peelbit-features-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set([root.path], forKey: "scanRoots")
        defaults.set(true, forKey: "onboardingComplete")
        defaults.set(true, forKey: "scanAtLaunch") // Even an old preference must not trigger a scan.
        let model = AppModel(defaults: defaults, codecURL: codec)
        model.start()
        #expect(!model.scanning && model.operation == nil && model.rows.isEmpty)
        let source = try png(root.appendingPathComponent("original.png"))
        let candidate = try await ImageEncoder.encode(source, settings: EncodeSettings(lossless: true), codecURL: codec) { _ in }
        defer { candidate.discard() }
        let webp = root.appendingPathComponent("existing.webp")
        try FileManager.default.copyItem(at: candidate.file, to: webp)
        model.scan(); await model.operation?.value
        #expect(model.rows.count == 1)
        model.setInputFormats([.webp]); await model.operation?.value
        #expect(model.rows.map { $0.record.url.pathExtension } == ["webp"])
        model.setInputFormats([.png]); await model.operation?.value
        model.importFiles([webp, webp]); await model.operation?.value
        #expect(model.rows.count == 2)
        #expect(model.inputFormats == [.png])
        let reloaded = AppModel(defaults: defaults)
        #expect(reloaded.inputFormats == [.png])
        model.cleanup()
    }

    @Test func explicitFilesDoNotScanSiblingsAndCancelledImportCannotAppend() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try png(root.appendingPathComponent("chosen.png"))
        let second = try png(root.appendingPathComponent("sibling.png"))
        let suite = "Chonko-explicit-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults, codecURL: codec)
        model.setInputFormats([])
        model.importFiles([first.url, first.url, root, URL(string: "https://example.com/image.png")!])
        await model.operation?.value
        #expect(model.rows.map(\.id) == [first.id])
        #expect(model.roots.isEmpty && model.readyCount == 1)
        model.importFiles([second.url])
        let cancelled = model.operation
        model.stop()
        await cancelled?.value
        #expect(model.rows.map(\.id) == [first.id])
        #expect(!model.busy)
        model.importFiles([second.url]); await model.operation?.value
        #expect(model.rows.count == 2 && model.readyCount == 2)
        #expect(FileManager.default.fileExists(atPath: first.url.path))
        model.cleanup()
    }

    @Test func boundedParallelEncodingKeepsCountersAndCancellationConsistent() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "Peelbit-parallel-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let records = try (0..<8).map { try png(root.appendingPathComponent("image-\($0).png")) }
        let model = AppModel(defaults: defaults, codecURL: codec)
        model.saveMode = .alongside
        model.append(records); model.performanceMode = .fast
        model.optimize(); await model.operation?.value
        #expect(model.peakEncodingCount >= min(2, PerformanceMode.fast.workerLimit))
        #expect(model.peakEncodingCount <= 4)
        #expect(model.activeEncodingCount == 0 && !model.optimizing)
        #expect(model.readyCount == 0)
        #expect(model.statistics.data.totals.files + model.pendingCount == 8)
        for record in records { #expect(FileManager.default.fileExists(atPath: record.url.path)) }
        model.cleanup()
        let cancelled = AppModel(defaults: defaults, codecURL: codec)
        cancelled.append(records); cancelled.performanceMode = .fast
        cancelled.optimize(); cancelled.stop(); await cancelled.operation?.value
        #expect(cancelled.activeEncodingCount == 0 && !cancelled.optimizing)
        #expect(cancelled.readyCount == cancelled.chosen.count)
        #expect(cancelled.selectedFileCount == cancelled.selectedFiles.count)
        #expect(cancelled.statistics.data.totals.files == 0)
        cancelled.cleanup()
    }

    @Test func ignoredFilesPersistAcrossSearchesAndCanBeRestored() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "Chonko-ignored-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set([root.path], forKey: "scanRoots")
        defaults.set(true, forKey: "onboardingComplete")
        let record = try png(root.appendingPathComponent("ignore-me.png"))
        let model = AppModel(defaults: defaults)
        model.append([record])
        model.ignoreSelectedFiles()
        #expect(model.rows.isEmpty && model.visibleRows.isEmpty)
        #expect(model.readyCount == 0 && model.selectedFileCount == 0)
        #expect(FileManager.default.fileExists(atPath: record.url.path))
        model.append([record])
        #expect(model.rows.isEmpty)
        let reloaded = AppModel(defaults: defaults)
        reloaded.start()
        #expect(reloaded.ignoredFiles == [record.url.standardizedFileURL.path])
        reloaded.scan()
        await reloaded.operation?.value
        #expect(reloaded.rows.isEmpty)
        reloaded.restoreIgnoredFiles(reloaded.ignoredPaths)
        reloaded.scan()
        await reloaded.operation?.value
        #expect(reloaded.rows.count == 1)
        #expect(AppModel(defaults: defaults).ignoredPaths.isEmpty)
        model.cleanup()
        reloaded.cleanup()
    }

    @Test func stoppedScanCannotAppendResultsOrClobberNextScan() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try png(root.appendingPathComponent("sample.png"))
        let suite = "Chonko-cancel-scan-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set([root.path], forKey: "scanRoots")
        defaults.set(true, forKey: "onboardingComplete")
        let model = AppModel(defaults: defaults)
        model.start()
        model.scan()
        let cancelled = model.operation
        model.stop()
        #expect(!model.scanning)
        model.scan()
        await cancelled?.value
        await model.operation?.value
        #expect(!model.scanning && model.rows.count == 1)
        model.cleanup()
    }

    @Test func skipRequestCanOnlyTargetTheDisplayedScanFile() {
        let control = ScanControl()
        let old = URL(fileURLWithPath: "/old.png")
        let current = URL(fileURLWithPath: "/current.png")
        control.begin(old)
        control.begin(current)
        #expect(!control.skipCurrent(expected: old))
        #expect(!control.shouldSkip(current))
        #expect(control.skipCurrent(expected: current))
        #expect(control.shouldSkip(current))
    }

    @Test(.timeLimit(.minutes(1))) func skippingRunningEncodingKeepsSourceAndDoesNotSave() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try png(root.appendingPathComponent("skip.png"))
        let slowCodec = root.appendingPathComponent("slow-codec")
        try Data("#!/bin/sh\nexec /bin/sleep 5\n".utf8).write(to: slowCodec)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: slowCodec.path)
        let suite = "Chonko-skip-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults, codecURL: slowCodec)
        model.append([source])
        let row = try #require(model.rows.first)
        model.optimize()
        while !row.running && model.optimizing { await Task.yield() }
        model.skipEncoding(row)
        await model.operation?.value
        #expect(!model.optimizing && row.skipRequested)
        #expect(model.statistics.data.totals.files == 0)
        #expect(model.pendingCount == 0)
        #expect(FileManager.default.fileExists(atPath: source.url.path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("skip.webp").path))
        model.cleanup()
    }

    private var codec: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/Codecs/cwebp") }
    private func makeDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "Peelbit-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    private func png(_ url: URL) throws -> ImageRecord {
        let context = try #require(CGContext(data: nil, width: 512, height: 512, bitsPerComponent: 8, bytesPerRow: 2048, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(red: 0.2, green: 0.6, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 512, height: 512))
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        try #require(CGImageDestinationFinalize(destination))
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return ImageScanner.inspect(url: url, root: url.deletingLastPathComponent(), bytes: (attrs[.size] as! NSNumber).int64Value, modified: attrs[.modificationDate] as! Date)
    }
}
