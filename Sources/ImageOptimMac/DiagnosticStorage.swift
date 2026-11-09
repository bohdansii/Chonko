import Foundation

actor DiagnosticStorage {
    private var events: [DiagnosticEvent]
    private let fileURL: URL?
    private(set) var writeFailed = false

    init(fileURL: URL?) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([DiagnosticEvent].self, from: data) {
            events = Array(saved.suffix(200))
        } else { events = [] }
    }

    func snapshot() -> [DiagnosticEvent] { events }

    func append(_ event: DiagnosticEvent) {
        events.append(event)
        events = Array(events.suffix(200))
        persist()
    }

    func clear() {
        events.removeAll()
        persist()
    }

    private func persist() {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(events).write(to: fileURL, options: .atomic)
            writeFailed = false
        } catch { writeFailed = true }
    }
}
