import CoreGraphics
import PDFKit
import Foundation
import Testing
import ImageCore
@testable import ImageOptimMac

@MainActor struct MediaModelTests {
    @Test func pdfConsentCanSwitchProfileOrCompressCopy() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("Chonko-consent-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let input = root.appendingPathComponent("links.pdf")
        var box = CGRect(x: 0, y: 0, width: 100, height: 100)
        let consumer = try #require(CGDataConsumer(url: input as CFURL))
        let writer = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
        writer.beginPDFPage(nil); writer.endPDFPage(); writer.closePDF()
        let document = try #require(PDFDocument(url: input))
        let link = PDFAnnotation(bounds: CGRect(x: 5, y: 5, width: 30, height: 20), forType: .link, withProperties: nil)
        link.url = URL(string: "https://example.com")
        document.page(at: 0)?.addAnnotation(link); #expect(document.write(to: input))
        let attrs = try input.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let record = try MediaInspector.inspectPDF(url: input, root: root, bytes: Int64(attrs.fileSize!), modified: attrs.contentModificationDate!)
        for preserve in [true, false] {
            let suite = "Chonko-consent-" + UUID().uuidString
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let codec = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/Codecs/cwebp")
            let model = AppModel(defaults: defaults, codecURL: codec)
            let row = ImageRowModel(record)
            model.fileKind = .pdf; model.pdfProfile = .balanced; model.saveMode = .alongside
            model.rows = [row]; model.readyCount = 1
            model.requestOptimization()
            #expect(model.showConversionWarning && !model.optimizing && model.operation == nil)
            model.confirmConversion(preservePDF: preserve)
            await model.operation?.value
            #expect(model.pdfProfile == (preserve ? .preserve : .balanced))
            #expect(!model.showConversionWarning && !model.showReplaceConfirmation)
            #expect(row.outputBytes != nil)
            if !preserve { #expect(row.saveMode == .alongside) }
            #expect(fm.fileExists(atPath: input.path))
            model.cleanup()
        }
    }

    @Test func hdrSelectionRequiresWarningBeforeEncoding() throws {
        let suite = "Chonko-hdr-consent-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults)
        let record = ImageRecord(url: URL(fileURLWithPath: "/tmp/consent-hdr.jpg"), root: URL(fileURLWithPath: "/tmp"), bytes: 1, modified: .now, width: 64, height: 64, requiresSDRConversion: true)
        model.rows = [ImageRowModel(record)]
        model.requestOptimization()
        #expect(model.showConversionWarning && model.conversionWarningCount == 1)
        #expect(model.operation == nil && !model.optimizing && !model.showReplaceConfirmation)
        model.cleanup()
    }

    @Test func allMediaModesDefaultToVerifiedReplacement() throws {
        let suite = "Chonko-default-saving-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults)
        #expect(model.saveMode == .replace)
        for kind in [FileKind.pdf, .video, .images] {
            model.saveMode = .alongside
            model.changeKind(kind)
            #expect(model.saveMode == .replace)
        }
        model.cleanup()
    }

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
        #expect(model.saveMode == .replace)
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
        #expect(model.fileKind == .pdf && model.rows.count == 1 && model.saveMode == .replace)
        model.cleanup()
    }
}
