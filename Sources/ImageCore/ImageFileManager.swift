import Foundation

public enum ImageFileManager {
    @concurrent public static func perform(_ action: FileAction, on records: [ImageRecord], policy: ScanPolicy, progress: @Sendable (Int, Int) async -> Void) async -> FileActionReport {
        var report = FileActionReport()
        for (index, record) in records.enumerated() {
            if Task.isCancelled { report.cancelled = true; break }
            do {
                try performOne(action, record: record, policy: policy)
                report.succeeded.insert(record.id)
            } catch { report.failures[record.id] = error.localizedDescription }
            await progress(index + 1, records.count)
        }
        return report
    }

    private static func performOne(_ action: FileAction, record: ImageRecord, policy: ScanPolicy) throws {
        let fm = FileManager.default, source = record.url
        guard !policy.excludes(source), source.resolvingSymlinksInPath().path == source.standardizedFileURL.path else {
            throw ImageFailure.message(L("Захищений шлях або символічне посилання. Файл залишено."))
        }
        // URL resource values can be cached from scanning; fresh attributes are essential before moving.
        let values = try fm.attributesOfItem(atPath: source.path)
        guard values[.type] as? FileAttributeType == .typeRegular, (values[.size] as? NSNumber)?.int64Value == record.bytes, values[.modificationDate] as? Date == record.modified else {
            throw ImageFailure.message(L("Файл змінився після сканування. Проскануй папку повторно."))
        }
        switch action {
        case .trash:
            try fm.trashItem(at: source, resultingItemURL: nil)
        case .move(let folder):
            guard !policy.excludes(folder), folder.resolvingSymlinksInPath().path == folder.standardizedFileURL.path else {
                throw ImageFailure.message(L("Обери папку поза системними каталогами й посиланнями."))
            }
            guard source.deletingLastPathComponent().path != folder.path else { throw ImageFailure.message(L("Файл уже в цій папці.")) }
            guard try folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw ImageFailure.message(L("Папка призначення недоступна.")) }
            var destination = folder.appendingPathComponent(source.lastPathComponent)
            let base = source.deletingPathExtension().lastPathComponent
            var index = 1
            while fm.fileExists(atPath: destination.path) {
                destination = folder.appendingPathComponent("\(base)-\(index)").appendingPathExtension(source.pathExtension)
                index += 1
            }
            // Foundation refuses existing destinations; a concurrent name collision leaves the source intact.
            try fm.moveItem(at: source, to: destination)
        }
    }
}
