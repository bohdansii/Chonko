import Foundation
import Observation
import Synchronization

@MainActor @Observable final class DiagnosticCenter {
    static let shared = DiagnosticCenter(fileURL: URL.applicationSupportDirectory.appending(path: "Chonko/Diagnostics/events.json"))
    private(set) var events: [DiagnosticEvent] = []
    private(set) var writeFailed = false
    @ObservationIgnored private let storage: DiagnosticStorage
    @ObservationIgnored private var queue: Task<Void, Never>?
    @ObservationIgnored private var pulseTask: Task<Void, Never>?
    @ObservationIgnored private var watchdog: Task<Void, Never>?
    @ObservationIgnored private let heartbeat = DiagnosticsHeartbeat()
    let sessionID = UUID().uuidString
    private let sessionStarted = Date()

    init(fileURL: URL? = nil) { storage = DiagnosticStorage(fileURL: fileURL) }

    /// Messages are fixed technical descriptions. Error userInfo and file paths are never recorded.
    func record(_ operation: String, _ message: String, error: Error? = nil) {
        let event = DiagnosticEvent(operation: operation, message: message, error: error)
        let previous = queue
        queue = Task {
            await previous?.value
            await storage.append(event)
            await reload()
        }
    }

    func reload() async {
        events = await storage.snapshot()
        writeFailed = await storage.writeFailed
    }

    func clear() {
        let previous = queue
        queue = Task {
            await previous?.value
            await storage.clear()
            await reload()
        }
    }

    func flush() async { await queue?.value }

    func setStage(_ stage: String) { heartbeat.state.withLock { $0.stage = stage } }

    func startMonitoring() {
        guard pulseTask == nil else { return }
        let heartbeat = heartbeat, storage = storage
        pulseTask = Task {
            while !Task.isCancelled {
                heartbeat.state.withLock { $0.time = ProcessInfo.processInfo.systemUptime }
                do { try await Task.sleep(for: .seconds(1)) } catch { break }
            }
        }
        watchdog = Task.detached(priority: .utility) {
            var reported = false
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(2)) } catch { break }
                let state = heartbeat.state.withLock { $0 }
                let delay = ProcessInfo.processInfo.systemUptime - state.time
                if delay >= 5 && !reported {
                    await storage.append(DiagnosticEvent(operation: state.stage, message: "Main thread unresponsive for at least 5 seconds"))
                    reported = true
                } else if delay < 3 { reported = false }
            }
        }
        let previous = queue
        queue = Task {
            await previous?.value
            let saved = await storage.snapshot()
            if let last = saved.last(where: { $0.operation == "lifecycle" }), last.message.hasPrefix("Application started") {
                await storage.append(DiagnosticEvent(operation: "lifecycle", message: "Previous session ended without a normal exit; possible force quit or crash"))
            }
            await storage.append(DiagnosticEvent(operation: "lifecycle", message: "Application started; session \(sessionID)"))
            await reload()
        }
    }

    func stopMonitoring() {
        pulseTask?.cancel()
        watchdog?.cancel()
        pulseTask = nil
        watchdog = nil
    }

    func exportData() async throws -> Data {
        await flush()
        let report = Report(appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development",
                            macOS: ProcessInfo.processInfo.operatingSystemVersionString,
                            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "development",
                            sessionID: sessionID, exportedAt: .now, sessionStarted: sessionStarted,
                            uptimeSeconds: ProcessInfo.processInfo.systemUptime,
                            processors: ProcessInfo.processInfo.activeProcessorCount,
                            memoryBytes: ProcessInfo.processInfo.physicalMemory,
                            currentStage: heartbeat.state.withLock { $0.stage },
                            writeFailed: await storage.writeFailed,
                            latestCrash: Self.latestCrashSummary(),
                            events: await storage.snapshot())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(report)
    }

    // Export only the system crash's reason and top symbols, never the raw report or paths.
    private static func latestCrashSummary() -> String? {
        let folder = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/DiagnosticReports")
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil),
              let file = files.filter({ $0.lastPathComponent.hasPrefix("ImageOptimMac-") && $0.pathExtension == "ips" }).sorted(by: { $0.lastPathComponent > $1.lastPathComponent }).first,
              let data = try? Data(contentsOf: file), data.count < 10_000_000,
              let text = String(data: data, encoding: .utf8), let newline = text.firstIndex(of: "\n"),
              let headerData = text[..<newline].data(using: .utf8),
              let header = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any],
              header["bundleID"] as? String == Bundle.main.bundleIdentifier,
              let body = text[text.index(after: newline)...].data(using: .utf8),
              let report = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
        let exception = report["exception"] as? [String: Any] ?? [:]
        let termination = report["termination"] as? [String: Any] ?? [:]
        let type = exception["type"] as? String ?? "unknown"
        let signal = exception["signal"] as? String ?? "unknown"
        let reason = termination["indicator"] as? String ?? "unknown"
        return "\(file.lastPathComponent); \(type); \(signal); \(reason)"
    }

    private struct Report: Encodable {
        let appVersion: String
        let macOS: String
        let build: String
        let sessionID: String
        let exportedAt: Date
        let sessionStarted: Date
        let uptimeSeconds: Double
        let processors: Int
        let memoryBytes: UInt64
        let currentStage: String
        let writeFailed: Bool
        let latestCrash: String?
        let events: [DiagnosticEvent]
    }
}

private final class DiagnosticsHeartbeat: Sendable {
    let state = Mutex((time: ProcessInfo.processInfo.systemUptime, stage: "idle"))
}
