import Foundation

public enum FinderImageInput {
    @concurrent public static func inspect(_ urls: [URL], policy: ScanPolicy = ScanPolicy(), tools: MediaTools? = nil, control: ScanControl = ScanControl()) async -> [ImageRecord] {
        var seen = Set<String>()
        defer { control.finish() }
        var records: [ImageRecord] = []
        for url in urls {
            guard !Task.isCancelled else { break }
            guard url.isFileURL, !policy.excludes(url),
                  FileKind.detect(url) != nil,
                  url.resolvingSymlinksInPath() == url.standardizedFileURL,
                  seen.insert(url.standardizedFileURL.path).inserted,
                  let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                  attrs[.type] as? FileAttributeType == .typeRegular,
                  let bytes = attrs[.size] as? NSNumber,
                  let date = attrs[.modificationDate] as? Date else { continue }
            control.begin(url)
            let record: ImageRecord
            if FileKind.detect(url) != .images, let tools {
                record = await MediaInspector.inspect(url: url, root: url.deletingLastPathComponent(), bytes: bytes.int64Value, modified: date, tools: tools)
            } else { record = autoreleasepool { ImageScanner.inspect(url: url, root: url.deletingLastPathComponent(), bytes: bytes.int64Value, modified: date) } }
            control.finish()
            if !Task.isCancelled && !control.shouldSkip(url) { records.append(record) }
        }
        return records
    }
}
