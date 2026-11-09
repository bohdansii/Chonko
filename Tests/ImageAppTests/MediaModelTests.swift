import CoreGraphics
import Foundation
import Testing
import ImageCore
@testable import ImageOptimMac

@MainActor struct MediaModelTests {
    @Test func modesScanTheirOwnExtensionsAndExplicitPDFSwitchesSafely() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("Chonko-mode-test-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let input = root.appendingPathComponent("document.pdf")
        var page = CGRect(x: 0, y: 0, width: 100, height: 100)
        let consumer = try #require(CGDataConsumer(url: input as CFURL))
        let pdf = try #require(CGContext(consumer: consumer, mediaBox: &page, nil))
        pdf.beginPDFPage(nil); pdf.endPDFPage(); pdf.closePDF()
        let suite = "Chonko-media-model-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults)
        model.roots = [root]
        model.scan(); await model.operation?.value
        #expect(model.rows.isEmpty)
        model.changeKind(.pdf)
        #expect(model.saveMode == .alongside)
        model.scan(); await model.operation?.value
        #expect(model.rows.count == 1 && model.readyCount == 1)
        #expect(model.rows.first?.record.media?.pages == 1)
        model.ignoreSelectedFiles()
        model.scan(); await model.operation?.value
        #expect(model.rows.isEmpty)
        model.restoreIgnoredFiles(model.ignoredPaths)
        model.changeKind(.images)
        #expect(model.saveMode == .replace)
        model.importFiles([input]); await model.operation?.value
        #expect(model.fileKind == .pdf && model.rows.count == 1 && model.saveMode == .alongside)
        model.cleanup()
    }
}
