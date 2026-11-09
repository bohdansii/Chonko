import Foundation
import ImageIO
import Testing
import ImageCore
@testable import ImageOptimMac

@MainActor struct AppModelTests {
    @Test func defaultReplacementRequiresConfirmationBeforeEncoding() {
        let model = AppModel()
        #expect(model.saveMode == .replace)
        let root = URL(fileURLWithPath: "/Users/test/Pictures")
        model.append([ImageRecord(url: root.appendingPathComponent("image.png"), root: root, bytes: 100, modified: Date(), width: 32, height: 32)])
        model.requestOptimization()
        #expect(model.showReplaceConfirmation)
        #expect(!model.optimizing && model.operation == nil)
    }

    @Test func selectionAndFiltersStayConsistent() {
        let model = AppModel()
        let root = URL(fileURLWithPath: "/Users/test/Pictures")
        let records = (0..<1000).map { i in
            ImageRecord(url: root.appendingPathComponent("image-\(i).png"), root: root, bytes: 100, modified: Date(), restriction: i == 0 ? "unsupported" : nil)
        }
        model.append(records)
        #expect(model.readyCount == 999)
        model.selectVisible(true)
        #expect(model.selectedFileCount == 1000)
        #expect(model.readyCount == 999)
        model.selectVisible(false)
        #expect(model.readyCount == 0)
        model.rows[1].selected = true
        #expect(model.readyCount == 1)
        model.search = "image-999.png"
        model.refreshVisibleRows()
        #expect(model.visibleRows.count == 1)
        model.selectVisible(true)
        #expect(model.readyCount == 2)
        #expect(model.selectedFileCount == 2)
        model.onlySelected = true
        #expect(model.visibleRows.count == 1)
        model.cleanup()
    }

    @Test func batchCountersAndLargerDecisionsStayConsistent() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ImageOptim-model-test-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "ImageOptim-test-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { try? fm.removeItem(at: root); defaults.removePersistentDomain(forName: suite) }
        let source = root.appendingPathComponent("photo.jpg")
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(data: nil, width: 256, height: 256, bitsPerComponent: 8, bytesPerRow: 1024, space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        for y in 0..<256 {
            context.setFillColor(red: CGFloat(y)/255, green: 0.4, blue: 0.7, alpha: 1)
            context.fill(CGRect(x: 0, y: y, width: 256, height: 1))
        }
        let image = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(source as CFURL, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.1] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        let codec = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/Codecs/cwebp")
        let model = AppModel(defaults: defaults, codecURL: codec)
        model.roots = [root]
        model.scan()
        await model.operation?.value
        #expect(model.readyCount == 1)
        model.saveMode = .alongside
        model.lossless = true
        model.format = .tiff
        model.optimize()
        await model.operation?.value
        #expect(model.readyCount == 0)
        #expect(model.statistics.data.totals.files == 0)
        #expect(model.pendingCount == 1)
        if model.pendingCount == 1 {
            model.discard(try #require(model.rows.first))
            #expect(model.pendingCount == 0)
            #expect(model.readyCount == 0)
        }
        #expect(model.statistics.data.totals.files == 0)
        model.scan()
        await model.operation?.value
        model.optimize()
        await model.operation?.value
        model.keepLarger(try #require(model.rows.first))
        await model.operation?.value
        #expect(model.statistics.data.totals.files == 1)
        #expect(model.statistics.data.totals.savedBytes < 0)
        #expect(fm.fileExists(atPath: source.path))
        model.cleanup()
    }

    @Test func largeListCounterBenchmark() {
        let model = AppModel()
        let root = URL(fileURLWithPath: "/Users/test/Pictures")
        model.append((0..<20_000).map { i in ImageRecord(url: root.appendingPathComponent("image-\(i).png"), root: root, bytes: 100, modified: Date()) })
        let clock = ContinuousClock()
        var total = 0
        let previous = clock.measure { for _ in 0..<200 { total += model.chosen.count } }
        let cached = clock.measure { for _ in 0..<200 { total += model.readyCount } }
        #expect(total == 8_000_000)
        print("COUNTER_BENCHMARK 200 reads × 20000 rows: traversal=\(previous), cached=\(cached)")
        // Avoid saving benchmark paths or affecting the user's app preferences.
    }

    @Test func folderOnlySearchAndMovingUnsupportedFiles() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ImageOptim-scope-test-" + UUID().uuidString)
        let chosen = root.appendingPathComponent("chosen"), destination = root.appendingPathComponent("destination")
        try fm.createDirectory(at: chosen, withIntermediateDirectories: true)
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("<svg/>".utf8).write(to: chosen.appendingPathComponent("chosen.svg"))
        try Data("<svg/>".utf8).write(to: root.appendingPathComponent("outside.svg"))
        let suite = "ImageOptim-test-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { try? fm.removeItem(at: root); defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults)
        model.setInputFormats([.other])
        model.roots = [root]
        model.requestScan(in: [chosen])
        await model.operation?.value
        #expect(model.roots == [chosen])
        #expect(model.rows.count == 1)
        #expect(model.rows.first?.record.url.lastPathComponent == "chosen.svg")
        #expect(model.readyCount == 0)
        model.selectVisible(true)
        #expect(model.selectedFileCount == 1)
        model.manageSelectedFiles(.move(destination))
        await model.operation?.value
        #expect(model.rows.isEmpty)
        #expect(model.selectedFileCount == 0)
        #expect(model.readyCount == 0)
        #expect(fm.fileExists(atPath: destination.appendingPathComponent("chosen.svg").path))
        #expect(fm.fileExists(atPath: root.appendingPathComponent("outside.svg").path))
        model.cleanup()
    }
}
