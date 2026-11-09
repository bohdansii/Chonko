import Foundation
import Testing
import ImageCore
@testable import ImageOptimMac

@MainActor struct StatisticsStoreTests {
    @Test func historySurvivesRestartAndLatestSnapshotWins() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "Statistics.json")
        let store = StatisticsStore(fileURL: url)
        for _ in 0..<100 { store.record(original: 100, result: 25, format: .webp) }
        await store.flush()
        #expect(store.persistenceError == nil)
        let reloaded = StatisticsStore(fileURL: url)
        #expect(reloaded.data == store.data)
        #expect(reloaded.data.totals.files == 100)
        #expect(reloaded.data.totals.savedBytes == 7500)
        let json = try String(contentsOf: url, encoding: .utf8)
        #expect(!json.contains("/Users/"))
    }
    @Test func damagedHistoryIsPreserved() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let original = Data("damaged history".utf8)
        try original.write(to: url)
        let store = StatisticsStore(fileURL: url)
        #expect(store.persistenceError != nil)
        store.record(original: 100, result: 20, format: .webp)
        await store.flush()
        #expect(try Data(contentsOf: url) == original)
        #expect(store.data.totals.savedBytes == 80)
    }
    @Test func resetPersistsAndQueuedWritesCannotRestoreOldHistory() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "Statistics.json")
        let store = StatisticsStore(fileURL: url)
        for _ in 0..<50 { store.record(original: 100, result: 20, format: .webp) }
        store.reset()
        await store.flush()
        #expect(StatisticsStore(fileURL: url).data.totals.files == 0)
        #expect(store.data.hours.isEmpty && store.data.formats.isEmpty)
        store.record(original: 200, result: 50, format: .png)
        await store.flush()
        #expect(StatisticsStore(fileURL: url).data.totals.files == 1)
        #expect(StatisticsStore(fileURL: url).data.totals.savedBytes == 150)
    }

    @Test func explicitResetRecoversFromDamagedHistory() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("bad history".utf8).write(to: url)
        let store = StatisticsStore(fileURL: url)
        store.reset()
        await store.flush()
        let reloaded = StatisticsStore(fileURL: url)
        #expect(reloaded.persistenceError == nil)
        #expect(reloaded.data.totals.files == 0)
    }

    @Test func periodsIncludeZerosAndDaylightSavingHours() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12)))
        var data = OptimizationStatistics(startedAt: date)
        data.record(original: 100, result: 20, format: .avif, at: date, calendar: calendar)
        let day = StatisticsPeriod.day.buckets(in: data, now: date, calendar: calendar)
        #expect(day.count == 25)
        #expect(day.reduce(0) { $0 + $1.totals.files } == 1)
        #expect(StatisticsPeriod.week.buckets(in: data, now: date, calendar: calendar).count == 7)
        #expect(StatisticsPeriod.month.buckets(in: data, now: date, calendar: calendar).count == 30)
        #expect(StatisticsPeriod.year.buckets(in: data, now: date, calendar: calendar).count == 12)
    }
}
