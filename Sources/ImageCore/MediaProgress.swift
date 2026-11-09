import Foundation

public struct MediaProgress: Sendable {
    public let stage: String
    public let fraction: Double
    public let remainingSeconds: Double?
}

/// FFmpeg's progress stream is keyed data; publish each complete progress block in order.
actor VideoProgressReporter {
    private let stage: String
    private let duration: Double
    private let initial: Double
    private let weight: Double
    private let remainingPasses: Double
    private let progress: @Sendable (Double?) async -> Void
    private let update: @Sendable (MediaProgress) async -> Void
    private var values: [String: String] = [:]
    init(stage: String, duration: Double, initial: Double, weight: Double, remainingPasses: Double = 0,
         progress: @escaping @Sendable (Double?) async -> Void, update: @escaping @Sendable (MediaProgress) async -> Void) {
        self.stage = stage; self.duration = duration; self.initial = initial; self.weight = weight
        self.remainingPasses = remainingPasses; self.progress = progress; self.update = update
    }
    func receive(_ line: String) async {
        let pair = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        guard pair.count == 2 else { return }
        values[String(pair[0])] = String(pair[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard pair[0] == "progress" else { return }
        let time = max(0, Double(values["out_time_us"] ?? "") ?? 0) / 1_000_000
        let fraction = initial + min(1, time / max(duration, 0.001)) * weight
        let speed = Double((values["speed"] ?? "").replacingOccurrences(of: "x", with: "")) ?? 0
        let remaining = speed > 0 && time > 0 ? (max(0, duration - time) + duration * remainingPasses) / speed : nil
        await progress(fraction)
        await update(MediaProgress(stage: stage, fraction: fraction, remainingSeconds: remaining))
    }
}
