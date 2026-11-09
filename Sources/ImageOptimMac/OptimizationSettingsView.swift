import SwiftUI
import ImageCore

struct OptimizationSettingsView: View {
    @Bindable var model: AppModel
    var body: some View {
        Form {
            if model.fileKind == .images {
            Section(L("Формат")) {
                Picker(L("Зберегти як"), selection: $model.format) {
                    ForEach(OutputFormat.allCases) { format in
                        Text(format.title + (format.isAvailable ? "" : L(" · недоступний"))).tag(format).disabled(!format.isAvailable)
                    }
                }
                .onChange(of: model.format) {
                    model.applyFormatDefaults()
                }
                Text(model.format.shortDescription).font(.callout).foregroundStyle(.secondary)
                DisclosureGroup(L("Про \(model.format.title)")) {
                    Text(model.format.explanation).foregroundStyle(.secondary)
                    Link(L("Офіційна документація"), destination: model.format.documentation)
                }
            }
            Section(L("Якість")) {
                if model.format.canChooseLossless {
                    Toggle(L("Без втрати якості"), isOn: $model.lossless)
                        .help(L("Зберігає пікселі зображення. Уже втрачені деталі не відновлюються; файл може збільшитися."))
                }
                if model.lossless {
                    Text(L("Якість зображення збережеться. Файл може стати більшим — тоді запитаємо, чи залишати його."))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledContent(L("Якість зображення"), value: "\(Int(model.quality)) / \(model.format.qualityMaximum)")
                        Slider(value: $model.quality, in: 1...Double(model.format.qualityMaximum), step: 1) { Text(L("Якість зображення \(model.format.title)")) }
                            .labelsHidden().accessibilityValue(L("\(Int(model.quality)), діапазон від 1 до \(model.format.qualityMaximum)"))
                    }
                    DisclosureGroup(L("Докладніше про якість")) {
                        HStack { Text(L("Менший файл")); Spacer(); Text(L("Більше деталей")) }.font(.callout).foregroundStyle(.secondary)
                        Text(L("Менше число — менший файл. Більше число — більше деталей.")).font(.callout).foregroundStyle(.secondary)
                        Button(L("Почати з \(model.format.suggestedQuality)")) { model.quality = Double(model.format.suggestedQuality) }
                        Text(L("Якщо результат виглядає гірше — збільш число й спробуй знову.")).font(.callout).foregroundStyle(.secondary)
                        Text(model.format.qualityExplanation)
                        Text(L("Це не відсоток зменшення файла. Однакове число в різних форматах може дати різний результат."))
                        Link(L("Офіційна довідка"), destination: model.format.qualityDocumentation)
                    }
                }
            }
            } else if model.fileKind == .pdf {
                PDFOptionsView(model: model)
            } else {
                VideoOptionsView(model: model)
            }
            Section(L("Збереження")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Розташування")).font(.callout).foregroundStyle(.secondary)
                    Menu {
                        Picker(L("Розташування"), selection: $model.saveMode) {
                            ForEach(SaveMode.allCases) { mode in Text(mode.title).tag(mode) }
                        }.pickerStyle(.inline)
                    } label: {
                        Text(model.saveMode.title)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.bordered)
                    .menuIndicator(.visible)
                    .accessibilityLabel(L("Розташування"))
                    .accessibilityValue(model.saveMode.title)
                }
                if model.saveMode == .folder {
                    Button(L("Обрати папку…"), action: model.chooseOutputFolder)
                    Text(model.outputFolder?.path ?? L("Папку не обрано")).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                }
                DisclosureGroup(L("Про збереження файлів")) {
                    if model.saveMode == .folder {
                        Text(L("Збережемо структуру підпапок. Однакові назви отримають суфікси."))
                    }
                    if model.saveMode == .replace {
                        Text(L("Оригінали — у Кошик"))
                        Text(L("Зміна розширення може порушити посилання. Існуючі файли ніколи не перезаписуються; конфлікти назв отримують суфікси."))
                    }
                    Text(L("Якщо результат не менший, оригінал залишається. Біля файла обери «Зберегти» або «Відкинути»."))
                }
                .foregroundStyle(.secondary)
            }
            DisclosureGroup(L("Захист оригіналів")) {
                Text(L("Системні ресурси, поточні шпалери, бібліотеки «Фото», пакети застосунків, символічні посилання та приховані папки виключені."))
                Text(L("Анімації, RAW, HDR, понад 8 біт на канал і непідтримувані формати показуються як пропущені."))
                Text(L("Метадані зберігаються за можливості кодека, зокрема геолокація. Розміри зображень не змінюємо."))
            }.foregroundStyle(.secondary)
            DisclosureGroup(L("Що означають відсотки")) {
                Text(L("«На 75% менше» означає: файл 4 МБ став 1 МБ. Залишилося 25% початкової ваги. Це не вимір якості зображення."))
                Text(L("Формула: (було − стало) ÷ було × 100. Якщо 1 МБ став 1,2 МБ, результат на 20% більший; оригінал залишиться до твого рішення."))
                Text(L("Прогрес 50% означає перебіг кодування, а не зменшення файла на 50%. WebP повідомляє фактичний прогрес. Системні кодеки інших форматів показують індикатор без відсотка; кінцева вага з’явиться після завершення."))
                Text(L("Навіть якщо копія менша, оригінал поруч або в Кошику продовжує займати місце. Різниця ваги копій не дорівнює автоматично звільненому місцю на диску."))
            }
            Section(L("Швидкість")) {
                Picker(L("Режим"), selection: $model.performanceMode) {
                    ForEach(PerformanceMode.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).labelsHidden()
                if model.fileKind == .video {
                    Text(L("Відео обробляємо по одному, щоб залишалося достатньо пам’яті та застосунок реагував на зупинку."))
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                Text(model.performanceMode == .automatic ? L("До 2 файлів одночасно. Менше навантаження на Mac.") : L("До 4 файлів одночасно. Більше навантаження й витрата батареї; якість не змінюється."))
                    .font(.callout).foregroundStyle(.secondary)
                }
            }

        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .controlSize(.large)
        .disabled(model.busy)
    }
}
