import Foundation

public struct SaveResult: Sendable {
    public let url: URL
    public let trashedOriginal: URL?
    public let warning: String?
}

public enum CandidateStore {
    private static let coordinator = CandidateSaveCoordinator()
    public static func save(_ candidate: EncodedCandidate, mode: SaveMode, folder: URL?, policy: ScanPolicy, allowLarger: Bool = false) async throws -> SaveResult {
        try await coordinator.save(candidate, mode: mode, folder: folder, policy: policy, allowLarger: allowLarger)
    }

    public static func saveSynchronously(_ candidate: EncodedCandidate, mode: SaveMode, folder: URL?, policy: ScanPolicy, allowLarger: Bool = false) throws -> SaveResult {
        let fm = FileManager.default
        let source = candidate.source.url
        guard !candidate.isLarger || allowLarger else { throw ImageFailure.message(L("Результат не менший. Потрібне твоє рішення.")) }
        guard !policy.excludes(source), source.resolvingSymlinksInPath().path == source.standardizedFileURL.path else { throw ImageFailure.message(L("Захищений файл або символічне посилання. Збереження зупинено.")) }
        guard try ImageEncoder.sha256(source) == candidate.sourceDigest else { throw ImageFailure.message(L("Оригінал змінився під час обробки. Збереження зупинено.")) }
        let parent: URL
        if mode == .folder {
            guard let folder, !policy.excludes(folder), folder.resolvingSymlinksInPath().path == folder.standardizedFileURL.path else { throw ImageFailure.message(L("Обери доступну папку результатів поза системними каталогами.")) }
            // Preserve the relative hierarchy; root names and suffixes prevent collisions across roots.
            let rootPath = candidate.source.root.path
            let rootPrefix = rootPath == "/" ? "/" : rootPath + "/"
            guard source.path.hasPrefix(rootPrefix) else { throw ImageFailure.message(L("Файл поза обраною папкою сканування.")) }
            let relativeParent = String(source.deletingLastPathComponent().path.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let rootName = rootPath == "/" ? "Mac" : candidate.source.root.lastPathComponent
            parent = folder.appendingPathComponent(rootName, isDirectory: true).appendingPathComponent(relativeParent, isDirectory: true)
        } else { parent = source.deletingLastPathComponent() }
        guard !policy.excludes(parent), parent.resolvingSymlinksInPath().path == parent.standardizedFileURL.path else { throw ImageFailure.message(L("Папка результату захищена або містить символічне посилання.")) }
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let base = source.deletingPathExtension().lastPathComponent
        let ext = candidate.file.pathExtension
        var index = 0
        var destination: URL
        repeat {
            let suffix = index == 0 ? "" : "-optimized-\(index)"
            destination = parent.appendingPathComponent(base + suffix).appendingPathExtension(ext)
            index += 1
        } while fm.fileExists(atPath: destination.path)
        // copyItem refuses to overwrite if a file appears between the check and the copy.
        try fm.copyItem(at: candidate.file, to: destination)
        guard try ImageEncoder.sha256(destination) == ImageEncoder.sha256(candidate.file) else {
            try? fm.removeItem(at: destination)
            throw ImageFailure.message(L("Копія не пройшла перевірку. Оригінал збережено."))
        }
        var trashed: NSURL?
        if mode == .replace && !candidate.retainsOriginal {
            do {
                guard try ImageEncoder.sha256(source) == candidate.sourceDigest else { throw ImageFailure.message(L("Оригінал змінився перед заміною.")) }
                try fm.trashItem(at: source, resultingItemURL: &trashed)
            } catch {
                candidate.discard()
                return SaveResult(url: destination, trashedOriginal: nil, warning: L("Новий файл збережено, але оригінал залишено: ") + error.localizedDescription)
            }
        }
        candidate.discard()
        return SaveResult(url: destination, trashedOriginal: trashed as URL?, warning: nil)
    }
}

private actor CandidateSaveCoordinator {
    func save(_ candidate: EncodedCandidate, mode: SaveMode, folder: URL?, policy: ScanPolicy, allowLarger: Bool) throws -> SaveResult {
        try Task.checkCancellation()
        return try CandidateStore.saveSynchronously(candidate, mode: mode, folder: folder, policy: policy, allowLarger: allowLarger)
    }
}
