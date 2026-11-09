import Foundation

/// Hourly aggregates contain no image names, paths or content.
public struct OptimizationStatistics: Codable, Sendable, Equatable {
    public var version = 1
    public var startedAt: Date
    public private(set) var hours: [StatisticsBucket] = []
    public private(set) var formats: [String: StatisticsTotals] = [:]
    public init(startedAt: Date = .now) { self.startedAt = startedAt }
    public var totals: StatisticsTotals {
        hours.reduce(into: StatisticsTotals()) { $0.merge($1.totals) }
    }
    public mutating func record(original: Int64, result: Int64, format: OutputFormat, at date: Date = .now, calendar: Calendar = .current) {
        record(original: original, result: result, formatName: format.rawValue, at: date, calendar: calendar)
    }
    public mutating func record(original: Int64, result: Int64, formatName: String, at date: Date = .now, calendar: Calendar = .current) {
        guard original > 0, result > 0 else { return }
        let hour = calendar.dateInterval(of: .hour, for: date)!.start
        let value = StatisticsTotals(files: 1, smallerFiles: result < original ? 1 : 0, originalBytes: original, resultBytes: result)
        if let index = hours.lastIndex(where: { $0.date == hour }) { hours[index].totals.merge(value) }
        else { hours.append(StatisticsBucket(date: hour, totals: value)) }
        formats[formatName, default: StatisticsTotals()].merge(value)
    }
    public func totals(in interval: DateInterval) -> StatisticsTotals {
        hours.lazy.filter { $0.date >= interval.start && $0.date < interval.end }
            .reduce(into: StatisticsTotals()) { $0.merge($1.totals) }
    }
}
