import SwiftUI
import ImageCore

struct ConversionWarningView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    private var isPDF: Bool { model.fileKind == .pdf }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(isPDF ? L("У PDF є спеціальні елементи") : L("Перетворити HDR на SDR?"), systemImage: "exclamationmark.triangle")
                .font(.title2.bold())
            Text(L("Файлів, яких це стосується: \(model.conversionWarningCount)."))
            Text(isPDF
                 ? L("Посилання, кнопки, закладки, вкладення, шари, профілі друку або теги доступності можуть змінитися чи стати недоступними. Текст і сторінки перевіримо. Можна продовжити з обраним стисненням або одразу стиснути в режимі «Зберегти якість».")
                 : L("Копія стане звичайним 8-бітним SDR-зображенням. HDR-яскравість, карта HDR та частина відтінків не збережуться. Навіть режим «Без втрат» стосуватиметься лише SDR-копії, а не HDR-оригіналу."))
            Text(L("Якщо продовжити з можливою втратою даних, збережемо копії поруч. Оригінали залишаться."))
                .foregroundStyle(.secondary)
            HStack {
                Button(L("Скасувати")) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if isPDF {
                    Button(L("Зберегти елементи й стиснути")) { model.confirmConversion(preservePDF: true) }
                }
                Button(isPDF ? L("Усе одно стиснути копію") : L("Перетворити на SDR і стиснути")) { model.confirmConversion(preservePDF: false) }
            }
        }
        .padding(24).frame(width: 660)
    }
}
