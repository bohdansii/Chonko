import ImageCore
import SwiftUI

struct AppSettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section(L("Мова")) {
                Picker(L("Мова застосунку"), selection: $model.language) {
                    Text("Українська").tag("uk")
                    Text("English").tag("en")
                }
                .disabled(model.busy || model.pendingCount > 0)
            }
            Section("Finder") {
                Button(L("Додати швидку дію…"), systemImage: "wand.and.stars", action: model.installFinderAction)
                    .disabled(model.busy)
                Text(L("Відкриє системне встановлення дії «Optimize in Chonko» для меню Finder. Обрані файли відкриватимуться тут для перевірки перед оптимізацією."))
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(8)
        .frame(width: 500, height: 300)
    }
}
