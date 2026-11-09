import Foundation
import Testing
@testable import ImageCore

struct StatisticsTests {
    @Test func savedBytesUseWeightedTotalsAndIncludeAcceptedLargerFiles() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        var data = OptimizationStatistics(startedAt: date)
        data.record(original: 100, result: 50, format: .webp, at: date, calendar: calendar)
        data.record(original: 900, result: 900, format: .png, at: date, calendar: calendar)
        #expect(data.hours.count == 1)
        #expect(data.totals.files == 2)
        #expect(data.totals.smallerFiles == 1)
        #expect(data.totals.reduction == 5)
        data.record(original: 200, result: 300, format: .png, at: date.addingTimeInterval(3600), calendar: calendar)
        #expect(data.totals.savedBytes == -50)
        #expect(data.formats["png"]?.files == 2)
        let hour = try #require(calendar.dateInterval(of: .hour, for: date))
        #expect(data.totals(in: hour).files == 2)
        #expect(data.totals(in: DateInterval(start: hour.end, duration: 3600)).files == 1)
        let roundTrip = try JSONDecoder().decode(OptimizationStatistics.self, from: JSONEncoder().encode(data))
        #expect(roundTrip == data)
        data.record(original: 0, result: 2, format: .webp)
        #expect(data.totals.files == 3)
    }
}
