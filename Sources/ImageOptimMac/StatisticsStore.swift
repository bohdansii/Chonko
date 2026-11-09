import Foundation
import Observation
import ImageCore

@MainActor @Observable final class StatisticsStore {
    private(set) var data = OptimizationStatistics()
    private(set) var persistenceError: String?
    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private let writer = StatisticsWriter()
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var writeTask: Task<Void, Never>?
    @ObservationIgnored private var canWrite = true

    static var defaultURL: URL {
        URL.applicationSupportDirectory.appending(path: "Peelbit/\(Bundle.main.bundleIdentifier ?? "local.bohdan.ImageOptimMac")/Statistics.json")
    }
    init(fileURL: URL? = nil) {
        self.fileURL = fileURL
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let loaded = try JSONDecoder().decode(OptimizationStatistics.self, from: Data(contentsOf: fileURL))
            guard loaded.version == 1,
                  loaded.hours.allSatisfy({ $0.totals.files >= 0 && $0.totals.originalBytes >= 0 && $0.totals.resultBytes >= 0 }) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            data = loaded
        } catch {
            canWrite = false
            persistenceError = L("Не вдалося прочитати історію. Її файл залишено без змін. Нові результати видно лише до закриття програми. \(error.localizedDescription)")
        }
    }
    func record(original: Int64, result: Int64, format: OutputFormat, at date: Date = .now) {
        data.record(original: original, result: result, format: format, at: date)
        persist()
    }

    func record(original: Int64, result: Int64, formatName: String) {
        data.record(original: original, result: result, formatName: formatName)
        persist()
    }

    func reset() {
        data = OptimizationStatistics()
        canWrite = true
        persistenceError = nil
        persist()
    }

    private func persist() {
        guard let fileURL, canWrite else { return }
        revision += 1
        let snapshot = data, revision = revision, writer = writer
        writeTask = Task {
            do {
                try await writer.write(snapshot, to: fileURL, revision: revision)
                if self.revision == revision { persistenceError = nil }
            } catch {
                if self.revision == revision { persistenceError = L("Не вдалося зберегти статистику. \(error.localizedDescription)") }
            }
        }
    }
    func flush() async { await writeTask?.value }
}
