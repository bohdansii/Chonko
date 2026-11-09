import Foundation

public enum PerformanceMode: String, CaseIterable, Identifiable, Sendable {
    case automatic, fast
    public var id: Self { self }
    public var title: String { self == .automatic ? L("Автоматично") : L("Швидко") }
    public var workerLimit: Int {
        let info = ProcessInfo.processInfo
        if info.thermalState == .serious || info.thermalState == .critical { return 1 }
        if self == .automatic && info.isLowPowerModeEnabled { return 1 }
        return min(self == .fast ? 4 : 2, max(1, info.activeProcessorCount / 2))
    }
    public var pixelBudget: Int64 {
        // Budget approximately 32 bytes per pixel for concurrent decode/encode working sets.
        min(self == .fast ? 96_000_000 : 48_000_000, Int64(ProcessInfo.processInfo.physicalMemory / 32))
    }
}
