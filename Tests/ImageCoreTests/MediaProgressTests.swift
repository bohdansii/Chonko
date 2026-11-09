import Foundation
import Testing
@testable import ImageCore

private actor ProgressSamples {
    var values: [MediaProgress] = []
    func append(_ value: MediaProgress) { values.append(value) }
}

struct MediaProgressTests {
    @Test func progressIsParsedAtBlockBoundariesAndEstimatesRemainingTime() async {
        let samples = ProgressSamples()
        let reporter = VideoProgressReporter(stage: "pass1", duration: 100, initial: 0, weight: 0.4, remainingPasses: 1, progress: { _ in }, update: { await samples.append($0) })
        for line in ["out_time_us=25000000", "speed=0.5x", "progress=continue", "out_time_us=N/A", "speed=N/A", "progress=end"] { await reporter.receive(line) }
        let values = await samples.values
        #expect(values.count == 2)
        #expect(values[0].fraction == 0.1)
        #expect(values[0].remainingSeconds == 350)
        #expect(values[1].remainingSeconds == nil)
    }

    @Test func childOutputReachesCallbackBeforeChildExits() async throws {
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: marker) }
        // The child fails if its first line is buffered until process termination.
        _ = try await ExternalProcess.run(URL(fileURLWithPath: "/bin/sh"), ["-c", "printf 'ready\\n'; sleep 1; test -f \"$1\"", "test", marker.path]) { line in
            if line == "ready" { try? Data().write(to: marker) }
        }
        #expect(FileManager.default.fileExists(atPath: marker.path))
    }
}
