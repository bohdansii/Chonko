import Foundation

public struct FileSizeChange: Sendable, Equatable {
    public let originalBytes: Int64
    public let resultBytes: Int64
    public init(originalBytes: Int64, resultBytes: Int64) {
        self.originalBytes = originalBytes; self.resultBytes = resultBytes
    }
    public var percentReduction: Double? {
        guard originalBytes > 0, resultBytes >= 0 else { return nil }
        return (Double(originalBytes) - Double(resultBytes)) / Double(originalBytes) * 100
    }
    public var summary: String {
        guard let percent = percentReduction else { return L("Немає порівняння") }
        if percent == 0 { return L("Вага та сама") }
        let style = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(1)).locale(ImageLocalization.locale)
        let amount = abs(percent) < 0.1 ? "<\(0.1.formatted(style))" : abs(percent).formatted(style)
        return percent > 0 ? L("На \(amount)% менше") : L("На \(amount)% більше")
    }
    public var explanation: String {
        let before = formatBytes(originalBytes)
        let after = formatBytes(resultBytes)
        return L("\(before) → \(after). \(summary). Формула економії: (було − стало) ÷ було × 100. Це зміна кількості байтів, а не вимір якості зображення.")
    }
}
