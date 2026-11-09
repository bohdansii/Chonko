import Foundation
import Synchronization
import Darwin

/// Bounded output, asynchronous exit notification, cancellation and timeout for bundled tools.
public enum ExternalProcess {
    @concurrent public static func run(_ executable: URL, _ arguments: [String], timeout: Duration = .seconds(300), onLine: @escaping @Sendable (String) async -> Void = { _ in }) async throws -> Data {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw ImageFailure.message(L("Не знайдено вбудований інструмент: \(executable.lastPathComponent)"))
        }
        let process = Process(), pipe = Pipe()
        process.executableURL = executable; process.arguments = arguments
        if executable.lastPathComponent == "gs" {
            var environment = ProcessInfo.processInfo.environment
            environment["GS_OPTIONS"] = nil
            environment["GS_LIB"] = executable.deletingLastPathComponent().appendingPathComponent("Ghostscript/Resource/Font").path
            process.environment = environment
        }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe; process.standardError = pipe
        let (exits, continuation) = AsyncStream<Int32>.makeStream(bufferingPolicy: .bufferingNewest(1))
        process.terminationHandler = { child in continuation.yield(child.terminationStatus); continuation.finish() }
        let timedOut = Mutex(false)
        defer { continuation.finish(); try? pipe.fileHandleForReading.close(); try? pipe.fileHandleForWriting.close() }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try process.run()
            try pipe.fileHandleForWriting.close()
            if Task.isCancelled { stop(process) }
            let timer = Task.detached {
                do { try await Task.sleep(for: timeout) } catch { return }
                if process.isRunning { timedOut.withLock { $0 = true }; stop(process) }
            }
            defer { timer.cancel() }
            let reader = Task.detached { () throws -> Data in
                var output = Data(), pending = Data()
                while true {
                    let chunk = pipe.fileHandleForReading.availableData
                    if chunk.isEmpty { break }
                    output.append(chunk)
                    if output.count > 8 * 1024 * 1024 { output.removeFirst(output.count - 8 * 1024 * 1024) }
                    pending.append(chunk)
                    while let newline = pending.firstIndex(of: 10) {
                        await onLine(String(decoding: pending[..<newline], as: UTF8.self))
                        pending.removeSubrange(...newline)
                    }
                    if pending.count > 65536 { pending.removeAll(keepingCapacity: true) }
                }
                return output
            }
            var status: Int32 = -1
            for await value in exits { status = value; break }
            let output = try await reader.value
            try Task.checkCancellation()
            if timedOut.withLock({ $0 }) { throw MediaProcessFailure(tool: executable.lastPathComponent, status: nil, timedOut: true, output: "") }
            guard status == 0 else {
                let detail = String(decoding: output.suffix(1600), as: UTF8.self)
                throw MediaProcessFailure(tool: executable.lastPathComponent, status: status, timedOut: false, output: detail)
            }
            return output
        } onCancel: { stop(process) }
    }

    private static func stop(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        Task.detached {
            try? await Task.sleep(for: .seconds(2))
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }
}
