import Foundation

public struct StatisticsTotals: Codable, Sendable, Equatable {
    public var files: Int = 0
    public var smallerFiles: Int = 0
    public var originalBytes: Int64 = 0
    public var resultBytes: Int64 = 0
    public init(files: Int = 0, smallerFiles: Int = 0, originalBytes: Int64 = 0, resultBytes: Int64 = 0) {
        self.files = files; self.smallerFiles = smallerFiles
        self.originalBytes = originalBytes; self.resultBytes = resultBytes
    }
    public var savedBytes: Int64 { originalBytes - resultBytes }
    public var reduction: Double? { FileSizeChange(originalBytes: originalBytes, resultBytes: resultBytes).percentReduction }
    public mutating func merge(_ other: Self) {
        files += other.files; smallerFiles += other.smallerFiles
        originalBytes += other.originalBytes; resultBytes += other.resultBytes
    }
}
