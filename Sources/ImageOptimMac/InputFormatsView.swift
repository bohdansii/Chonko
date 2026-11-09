import SwiftUI
import ImageCore

struct InputFormatsView: View {
    let model: AppModel
    @State private var formats: Set<InputFormat>
    @Environment(\.dismiss) private var dismiss
    init(model: AppModel) {
        self.model = model
        _formats = State(initialValue: model.inputFormats)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("Формати пошуку")).font(.headline)
            Text(L("Обери типи оригіналів. WebP та AVIF типово приховані; увімкни їх, якщо хочеш конвертувати в інший формат."))
                .font(.callout).foregroundStyle(.secondary)
            ForEach(InputFormat.allCases) { format in
                Toggle(format.title, isOn: Binding(get: { formats.contains(format) }, set: { included in
                    if included { formats.insert(format) } else { formats.remove(format) }
                })).toggleStyle(.checkbox)
            }
            HStack {
                Button(L("Усі")) { formats = Set(InputFormat.allCases) }
                Button(L("Типові")) { formats = InputFormat.defaults }
                Spacer()
                Button(L("Застосувати")) { model.setInputFormats(formats); dismiss() }.keyboardShortcut(.defaultAction)
            }
            Text(L("Застосування повторить пошук у поточних папках. Створені цим застосунком результати виключені з повторного сканування; їх можна відкрити окремо через Finder."))
                .font(.caption).foregroundStyle(.secondary)
        }.padding(20).frame(width: 340)
    }
}
