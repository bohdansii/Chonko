import Foundation
import ImageCore

actor StatisticsWriter {
    private var savedRevision = 0
    func write(_ data: OptimizationStatistics, to url: URL, revision: Int) throws {
        guard revision > savedRevision else { return }
        let encoded = try JSONEncoder().encode(data)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoded.write(to: url, options: .atomic)
        savedRevision = revision
    }
}
