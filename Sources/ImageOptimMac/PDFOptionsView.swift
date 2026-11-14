import SwiftUI
import ImageCore

struct PDFOptionsView: View {
    @Bindable var model: AppModel
    var body: some View {
        Section("PDF") {
            Picker(L("Стиснення"), selection: $model.pdfProfile) {
                ForEach(PDFProfile.allCases) { Text($0.title).tag($0) }
            }
            Text(model.pdfProfile == .preserve
                 ? L("Оптимізує структуру PDF, не стискаючи зображення з втратами. Економія може бути невеликою.")
                 : L("Стискає зображення всередині PDF. Текст залишається текстом; вигляд фотографій і сканів може змінитися."))
                .font(.callout).foregroundStyle(.secondary)
            DisclosureGroup(L("Докладніше про PDF")) {
                if model.pdfProfile != .preserve {
                    Text(L("Зображення: до \(model.pdfProfile.dpi) dpi. Менша роздільність дає менші файли, але може погіршити дрібні деталі."))
                }
                Text(L("Захищені PDF, форми й цифрові підписи пропускаються. Для інтерактивних або тегованих PDF запропонуємо зберегти елементи або стиснути копію з попередженням."))
                Text(L("Перед збереженням перевіряємо сторінки, текст, розміри та можливість відкриття."))
            }
        }
    }
}
