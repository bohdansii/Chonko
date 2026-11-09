import Foundation

public struct StatisticsBucket: Codable, Sendable, Identifiable, Equatable {
    public var date: Date
    public var totals: StatisticsTotals
    public var id: Date { date }
    public init(date: Date, totals: StatisticsTotals) { self.date = date; self.totals = totals }
}
