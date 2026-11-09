import SwiftUI
import Charts
import ImageCore

struct StatisticsView: View {
    let store: StatisticsStore
    var canReset = true
    @State private var confirmReset = false
    @State private var period: StatisticsPeriod = .week
    @State private var showFiles = false
    @State private var selectedDate: Date?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let buckets = period.buckets(in: store.data, now: timeline.date)
            let total = store.data.totals
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack {
                        Text(L("Статистика")).font(.largeTitle.bold())
                        Spacer()
                        Button(L("Скинути статистику"), systemImage: "arrow.counterclockwise", role: .destructive) {
                            confirmReset = true
                        }
                        .buttonStyle(.glass).buttonBorderShape(.capsule)
                        .disabled(!canReset || (total.files == 0 && store.persistenceError == nil))
                    }
                    if let error = store.persistenceError {
                        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                            .textSelection(.enabled)
                    }
                    if total.files == 0 {
                        ContentUnavailableView {
                            Label(L("Кожен менший файл має значення"), systemImage: "chart.bar.xaxis")
                        } description: {
                            Text(L("Збережи перше оптимізоване зображення — тут з’являться його результат та історія. Статистика залишиться після перезапуску."))
                        }.frame(minHeight: 360)
                    } else {
                        history(buckets: buckets)
                        Divider()
                        lifetime(total)
                        Divider()
                        formats
                    }
                    DisclosureGroup(L("Як рахуємо статистику")) {
                        Text(L("Враховуємо лише успішно збережені результати, зокрема більші файли, які ти вирішив залишити. Відкинуті результати, помилки та переміщення файлів не додаються. Різниця ваги = сума ваги оригіналів мінус сума ваги результатів; загальний відсоток рахуємо від сумарної ваги оригіналів. Це не оцінка якості й не лічильник вільного місця: оригінали поруч або в Кошику продовжують займати диск. Повторна обробка рахується як нове збереження. Історія починається з цієї версії; назви, шляхи й самі зображення в ній не зберігаємо."))
                            .font(.callout).foregroundStyle(.secondary).padding(.top, 8)
                    }
                    Text(L("Локально на цьому Mac · від \(formatDate(store.data.startedAt))"))
                        .font(.callout).foregroundStyle(.secondary)
                }
                .padding(32).frame(maxWidth: 1050, alignment: .leading).frame(maxWidth: .infinity)
            }
        }
        .confirmationDialog(L("Скинути всю статистику?"), isPresented: $confirmReset, titleVisibility: .visible) {
            Button(L("Скинути статистику"), role: .destructive) {
                guard canReset else { return }
                store.reset()
                selectedDate = nil
            }
        } message: {
            Text(L("Історію оптимізацій і загальні лічильники буде очищено. Файли залишаться на місці. Цю дію неможливо скасувати."))
        }
    }

    private func history(buckets: [StatisticsBucket]) -> some View {
        let total = buckets.reduce(into: StatisticsTotals()) { $0.merge($1.totals) }
        let selected = selectedDate.flatMap { date in
            buckets.last { $0.date <= date }
        }
        let displayed = selected?.totals ?? total
        return VStack(alignment: .leading, spacing: 18) {
            HStack {
                Picker(L("Період"), selection: $period) {
                    ForEach(StatisticsPeriod.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 400)
                    .onChange(of: period) { selectedDate = nil }
                Spacer()
                Picker(L("Показник"), selection: $showFiles) {
                    Text(L("Вага")).tag(false)
                    Text(L("Файли")).tag(true)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 170)
                Menu(L("Деталі")) {
                    Button(L("Увесь період")) { selectedDate = nil }
                    ForEach(buckets) { bucket in
                        Button(formatDate(bucket.date, includeTime: period == .day)) { selectedDate = bucket.date }
                    }
                }.help(L("Обрати часовий інтервал графіка з клавіатури"))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(showFiles ? L("Збережено зображень") : displayed.savedBytes < 0 ? L("Результати важчі на") : L("Копії легші на"))
                    .foregroundStyle(.secondary)
                Text(showFiles ? displayed.files.formatted() : bytes(abs(displayed.savedBytes)))
                    .font(.largeTitle.bold()).monospacedDigit().foregroundStyle(Color.accentColor)
                Text(selected.map { formatDate($0.date, includeTime: period == .day) }
                     ?? "\(formatDate(buckets.first!.date)) – \(formatDate(Date.now))")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Chart(buckets) { bucket in
                BarMark(x: .value(L("Дата"), bucket.date, unit: period.component),
                        y: .value(showFiles ? L("Зображення") : L("Різниця ваги"), showFiles ? Double(bucket.totals.files) : Double(bucket.totals.savedBytes)))
                    .foregroundStyle(Color.accentColor.gradient).cornerRadius(3)
                    .accessibilityLabel(formatDate(bucket.date, includeTime: period == .day))
                    .accessibilityValue(showFiles ? L("Зображень: \(bucket.totals.files)") : "\(bucket.totals.savedBytes < 0 ? L("Важчі на") : L("Легші на")) \(bytes(abs(bucket.totals.savedBytes)))")
                if let selected, selected.id == bucket.id {
                    RuleMark(x: .value(L("Обрана дата"), bucket.date, unit: period.component))
                        .foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                }
            }
            .chartXSelection(value: $selectedDate)
            .chartGesture { proxy in
                SpatialTapGesture().onEnded { event in proxy.selectXValue(at: event.location.x) }
            }
            .chartYAxis {
                if showFiles {
                    AxisMarks(position: .trailing, values: .stride(by: Double(max(1, Int(ceil(Double(buckets.map { $0.totals.files }.max() ?? 0) / 4)))))) {
                        AxisGridLine().foregroundStyle(.quaternary)
                        AxisValueLabel()
                    }
                } else {
                AxisMarks(position: .trailing) { value in
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(showFiles ? number.formatted(.number.precision(.fractionLength(0))) : "\(number < 0 ? "−" : "")\(bytes(Int64(abs(number))))")
                        }
                    }
                }
                }
            }
            .chartPlotStyle { plot in
                plot.background {
                    if !reduceTransparency {
                        RadialGradient(colors: [Color.accentColor.opacity(0.14), .clear], center: .center, startRadius: 0, endRadius: 400)
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
            }
            .frame(height: 280)
            Text(total.files == 0 ? L("За цей період збережених результатів ще немає.") : L("Обери стовпчик, щоб побачити результат за цей час."))
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private func lifetime(_ total: StatisticsTotals) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L("За весь час")).font(.title2.bold())
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 40) { lifetimeMetrics(total) }
                VStack(alignment: .leading, spacing: 20) { lifetimeMetrics(total) }
            }
            LabeledContent(L("Вага оригіналів"), value: bytes(total.originalBytes))
            LabeledContent(L("Вага збережених результатів"), value: bytes(total.resultBytes))
        }
    }
    @ViewBuilder private func lifetimeMetrics(_ total: StatisticsTotals) -> some View {
        metric(total.savedBytes < 0 ? L("Важчі на") : L("Легші на"), value: bytes(abs(total.savedBytes)))
        metric(L("Збережено файлів"), value: total.files.formatted())
        metric(L("Стали меншими"), value: total.smallerFiles.formatted())
        metric(L("Зміна ваги"), value: total.reduction.map { "\(abs($0).formatted(.number.precision(.fractionLength(1)).locale(ImageLocalization.locale)))% \($0 < 0 ? L("більше") : L("менше"))" } ?? "—")
    }
    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.callout).foregroundStyle(.secondary)
            Text(value).font(.title2.bold()).monospacedDigit()
        }.fixedSize(horizontal: true, vertical: false)
    }
    private var formats: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L("Формати результатів")).font(.title2.bold())
            ForEach(store.data.formats.keys.sorted(), id: \.self) { format in
                if let value = store.data.formats[format] {
                    HStack {
                        Text(OutputFormat(rawValue: format)?.title ?? format).font(.headline).frame(width: 110, alignment: .leading)
                        Text(L("Файлів: \(value.files.formatted())")).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(value.savedBytes < 0 ? "+" : "−")\(bytes(abs(value.savedBytes)))").monospacedDigit()
                    }.accessibilityElement(children: .combine)
                }
            }
        }
    }
    private func bytes(_ value: Int64) -> String { formatBytes(value) }
}
