import Foundation
import ImageIO

public struct ScanSummary: Sendable {
    public var inaccessible = 0
    public var cloudOnly = 0
}

public enum ImageScanner {
    @concurrent public static func scan(roots: [URL], policy: ScanPolicy, tools: MediaTools? = nil, control: ScanControl = ScanControl(), onProgress: @Sendable (Int) async -> Void = { _ in }, onBatch: @Sendable ([ImageRecord]) async -> Void) async throws -> ScanSummary {
        let fm = FileManager.default
        var seen = Set<String>()
        var batch: [ImageRecord] = []
        var summary = ScanSummary()
        var visited = 0
        var lastProgress = ContinuousClock().now
        defer { control.finish() }
        let clock = ContinuousClock()
        var lastDelivery = clock.now
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .isPackageKey, .fileSizeKey, .contentModificationDateKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
        for root in roots {
            try Task.checkCancellation()
            if policy.excludes(root) || root.resolvingSymlinksInPath() != root.standardizedFileURL { continue }
            // Enumerator errors are counted instead of presenting a false claim of a complete scan.
            let errorCount = ScanErrorCount()
            guard let iterator = fm.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in errorCount.increment(); return true }) else {
                summary.inaccessible += 1; continue
            }
            while let url = nextURL(iterator) {
                try Task.checkCancellation()
                visited += 1
                if lastProgress.duration(to: clock.now) >= .milliseconds(300) {
                    await onProgress(visited)
                    lastProgress = clock.now
                }
                if policy.excludes(url) { iterator.skipDescendants(); continue }
                guard let values = try? url.resourceValues(forKeys: keys) else { summary.inaccessible += 1; continue }
                if values.isSymbolicLink == true || values.isPackage == true { iterator.skipDescendants(); continue }
                guard values.isRegularFile == true, FileKind.detect(url) != nil, policy.includedExtensions.contains(url.pathExtension.lowercased()), seen.insert(url.path).inserted else { continue }
                if values.isUbiquitousItem == true, values.ubiquitousItemDownloadingStatus != .current && values.ubiquitousItemDownloadingStatus != .downloaded { summary.cloudOnly += 1; continue }
                guard let size = values.fileSize, let modified = values.contentModificationDate else { summary.inaccessible += 1; continue }
                control.begin(url)
                let record: ImageRecord
                if FileKind.detect(url) != .images, let tools {
                    record = await MediaInspector.inspect(url: url, root: root, bytes: Int64(size), modified: modified, tools: tools)
                } else { record = autoreleasepool { inspect(url: url, root: root, bytes: Int64(size), modified: modified) } }
                control.finish()
                try Task.checkCancellation()
                if control.shouldSkip(url) { continue }
                batch.append(record)
                // Limit SwiftUI table snapshots during fast scans; still deliver slow scans promptly.
                if batch.count >= 200 || lastDelivery.duration(to: clock.now) >= .milliseconds(150) {
                    try Task.checkCancellation()
                    await onBatch(batch); batch.removeAll(keepingCapacity: true); lastDelivery = clock.now
                }
            }
            summary.inaccessible += errorCount.value
        }
        try Task.checkCancellation()
        if !batch.isEmpty { await onBatch(batch) }
        await onProgress(visited)
        return summary
    }

    private static func nextURL(_ iterator: FileManager.DirectoryEnumerator) -> URL? { iterator.nextObject() as? URL }

    public static func inspect(url: URL, root: URL, bytes: Int64, modified: Date) -> ImageRecord {
        let supported: Set<String> = ["jpg", "jpeg", "png", "webp", "tif", "tiff", "avif", "heic", "heif", "bmp", "gif", "jp2", "j2k", "jpf", "tga", "ico"]
        var reason: String?
        var width = 0, height = 0, depth = 8
        var alpha = false
        if !supported.contains(url.pathExtension.lowercased()) {
            switch url.pathExtension.lowercased() {
            case "svg": reason = L("SVG — вектор. Для перетворення потрібен вибір розміру; оригінал залишаємо.")
            case "psd", "psb": reason = L("PSD може містити шари. Щоб їх не втратити, оптимізацію пропущено.")
            default: reason = L("Цей формат потребує окремої обробки; оригінал залишаємо.")
            }
        } else if let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary), let info = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            width = info[kCGImagePropertyPixelWidth] as? Int ?? 0
            height = info[kCGImagePropertyPixelHeight] as? Int ?? 0
            depth = info[kCGImagePropertyDepth] as? Int ?? 8
            alpha = info[kCGImagePropertyHasAlpha] as? Bool ?? false
            let color = info[kCGImagePropertyColorModel] as? String
            if CGImageSourceGetCount(source) != 1 { reason = L("Анімації та багатосторінкові файли пропускаються.") }
            else if CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeHDRGainMap) != nil || CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeISOGainMap) != nil {
                reason = L("HDR-карта яскравості: пропущено для збереження HDR-даних.")
            }
            else if depth > 8 { reason = L("Понад 8 біт на канал: пропущено для захисту кольорів / HDR.") }
            else if hasAdditionalImageData(source) { reason = L("Є додаткові карти глибини або маски: пропущено, щоб їх не втратити.") }
            else if color != "RGB" && color != "Gray" { reason = L("Колірна модель \(color ?? L("невідома")) потребує окремої обробки.") }
            else if width <= 0 || height <= 0 || Int64(width) * Int64(height) > 100_000_000 { reason = L("Невідомі розміри або понад 100 Мп: пропущено для захисту пам’яті.") }
        } else { reason = L("Не вдалося прочитати зображення.") }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path), (attrs[.referenceCount] as? Int ?? 1) > 1 {
            reason = L("Файл має жорсткі посилання: пропущено для безпечної заміни.")
        }
        return ImageRecord(url: url, root: root, bytes: bytes, modified: modified, width: width, height: height, depth: depth, hasAlpha: alpha, restriction: reason)
    }

    private static func hasAdditionalImageData(_ source: CGImageSource) -> Bool {
        let protected: [CFString] = [kCGImageAuxiliaryDataTypeDepth, kCGImageAuxiliaryDataTypeDisparity,
            kCGImageAuxiliaryDataTypePortraitEffectsMatte, kCGImageAuxiliaryDataTypeSemanticSegmentationHairMatte,
            kCGImageAuxiliaryDataTypeSemanticSegmentationSkinMatte, kCGImageAuxiliaryDataTypeSemanticSegmentationTeethMatte,
            kCGImageAuxiliaryDataTypeSemanticSegmentationGlassesMatte, kCGImageAuxiliaryDataTypeSemanticSegmentationSkyMatte]
        return protected.contains { CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, $0) != nil }
    }
}

// Foundation's synchronous enumeration callback may run outside actor isolation.
private final class ScanErrorCount: Sendable {
    private let count = Synchronization.Mutex(0)
    func increment() { count.withLock { $0 += 1 } }
    var value: Int { count.withLock { $0 } }
}

import Synchronization
