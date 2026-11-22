import SwiftUI
import ImageCore

struct ImageResizeOptionsView: View {
    @Bindable var model: AppModel
    var body: some View {
        Section(L("Розмір у пікселях")) {
            HStack {
                Text(L("Масштаб"))
                Spacer(minLength: 8)
                Picker(L("Масштаб"), selection: $model.imageResizePreset) {
                    Text(L("1× · без змін")).tag(100)
                    Text("0.75× · 75%").tag(75)
                    Text("0.5× · 50%").tag(50)
                    Text("0.25× · 25%").tag(25)
                    Text(L("Власне зменшення…")).tag(0)
                }.labelsHidden().pickerStyle(.menu).controlSize(.regular)
            }
            if model.imageResizePreset == 0 {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent(L("Зменшити на"), value: "\(Int(model.imageSizeReduction))%")
                    Slider(value: $model.imageSizeReduction, in: 0...90, step: 1)
                        .accessibilityLabel(L("Зменшення ширини й висоти"))
                }
            }
            if let example = model.resizeExample {
                Text(L("Перше обране: \(example)")).monospacedDigit().font(.callout).foregroundStyle(.secondary)
            }
            DisclosureGroup(L("Як змінюються розміри")) {
                Text(L("50% масштабу — удвічі менша ширина й висота: 6000 × 2000 → 3000 × 1000. Пропорції зберігаємо, розміри округлюємо до цілих пікселів. Збільшення немає."))
                Text(L("0.75× залишає 75% ширини й висоти — тобто зменшує їх на 25%."))
                Text(L("Це розміри зображення, а не вага файла. Для зміни лише розмірів обери «Поточний формат» вище. Якщо його запис не підтримується в Chonko, покажемо пояснення й залишимо оригінал."))
            }
        }
    }
}
