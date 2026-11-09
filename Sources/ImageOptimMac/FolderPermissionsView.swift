import ImageCore
import SwiftUI

struct FolderPermissionsView: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable().frame(width: 44, height: 44).accessibilityHidden(true)
                    Text(verbatim: "Chonko").font(.title2.weight(.semibold))
                }
                Text(L("Де шукати зображення?")).font(.largeTitle).bold()
                Text(L("Обери папки, до яких хочеш надати доступ. Усі зображення залишаються на твоєму Mac."))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(28)
            Form {
                Section(L("Рекомендовані папки · усі необов’язкові")) {
                    ForEach(model.suggestedFolders) { folder in
                        LabeledContent {
                            HStack {
                                if folder.checking { ProgressView().controlSize(.small) }
                                Button(L("Обрати й надати доступ…")) { model.requestAccess(to: folder) }
                                    .disabled(folder.checking)
                                    .accessibilityLabel(L("Надати доступ до папки «\(folder.title)»"))
                                    .accessibilityValue(folder.status)
                            }
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(folder.title)
                                    Text(folder.status).font(.callout).foregroundStyle(.secondary)
                                }
                            } icon: { Image(systemName: folder.icon) }
                        }
                        .padding(.vertical, 6)
                    }
                }
                Section {
                    Button(L("Додати іншу папку або диск…"), systemImage: "folder.badge.plus") { model.requestAccess(to: nil) }
                    if !model.roots.isEmpty {
                        ForEach(model.roots, id: \.path) { root in
                            LabeledContent {
                                Button(L("Прибрати"), systemImage: "minus.circle") { model.removeRootWithoutScanning(root) }
                                    .labelStyle(.iconOnly).help(L("Прибрати \(root.lastPathComponent) з пошуку"))
                            } label: { Text(root.path).font(.callout).textSelection(.enabled) }
                        }
                    }
                } header: { Text(L("Обрано для пошуку: \(model.roots.count)")) }
                Section {
                    Text(L("Підтверди потрібну папку в системному вікні. macOS може додатково запитати дозвіл. Позначка читання описує перевірку зараз і не гарантує доступу до всіх вкладених файлів."))
                    Text(L("Системні папки й бібліотеки «Фото» не потрібні. Повний доступ до диска не є обов’язковим для роботи з обраними папками."))
                    Button(L("Відкрити Системні параметри…")) {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
                    }
                    Text(L("Якщо доступ заблоковано: Приватність і безпека → Файли й папки. Захищені дозволи змінюються лише тобою в macOS."))
                }.foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .controlSize(.large)
            Divider()
            HStack {
                Button(L("Пізніше")) { model.finishOnboarding(scan: false) }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(L("Почати пошук"), systemImage: "magnifyingglass") { model.finishOnboarding(scan: true) }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.roots.isEmpty || model.suggestedFolders.contains(where: \.checking))
            }.padding(24)
        }
        .frame(width: 720, height: 760)
    }
}
