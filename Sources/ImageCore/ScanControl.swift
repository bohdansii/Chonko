import Foundation
import Synchronization

public final class ScanControl: Sendable {
    public struct Snapshot: Sendable {
        public let file: URL
        public let startedAt: Date
    }
    private struct State {
        var current: Snapshot?
        var skipped: Set<String> = []
    }
    private let state = Mutex(State())
    public init() {}
    public var current: Snapshot? { state.withLock { $0.current } }
    public func begin(_ url: URL) {
        state.withLock { $0.current = Snapshot(file: url, startedAt: .now) }
    }
    public func finish() { state.withLock { $0.current = nil } }
    @discardableResult public func skipCurrent(expected: URL? = nil) -> Bool {
        state.withLock {
            guard let file = $0.current?.file, expected == nil || expected == file else { return false }
            $0.skipped.insert(file.path)
            return true
        }
    }
    public func shouldSkip(_ url: URL) -> Bool { state.withLock { $0.skipped.contains(url.path) } }
}
