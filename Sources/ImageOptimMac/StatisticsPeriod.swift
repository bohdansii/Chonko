import Foundation
import ImageCore

enum StatisticsPeriod: String, CaseIterable, Identifiable {
    case day = "День", week = "Тиждень", month = "Місяць", year = "Рік"
    var id: Self { self }
    var title: String {
        switch self { case .day: L("День"); case .week: L("Тиждень"); case .month: L("Місяць"); case .year: L("Рік") }
    }
    var component: Calendar.Component { self == .day ? .hour : self == .year ? .month : .day }
    func buckets(in data: OptimizationStatistics, now: Date, calendar: Calendar = .current) -> [StatisticsBucket] {
        let today = calendar.startOfDay(for: now)
        let start: Date
        let count: Int
        switch self {
        case .day: start = today; count = Int(calendar.dateInterval(of: .day, for: today)!.duration / 3600)
        case .week: start = calendar.date(byAdding: .day, value: -6, to: today)!; count = 7
        case .month: start = calendar.date(byAdding: .day, value: -29, to: today)!; count = 30
        case .year:
            let currentMonth = calendar.dateInterval(of: .month, for: now)!.start
            start = calendar.date(byAdding: .month, value: -11, to: currentMonth)!; count = 12
        }
        return (0..<count).map { index in
            let date = calendar.date(byAdding: component, value: index, to: start)!
            let end = calendar.date(byAdding: component, value: 1, to: date)!
            return StatisticsBucket(date: date, totals: data.totals(in: DateInterval(start: date, end: end)))
        }
    }
}
