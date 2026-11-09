import ImageCore
import SwiftUI

struct SourcesSidebarView: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("Папки")).font(.title2.bold()).padding(20)
            Picker(L("Тип файлів"), selection: Binding(get: { model.fileKind }, set: model.changeKind)) {
                Text(L("Фото")).tag(FileKind.images)
                Text("PDF").tag(FileKind.pdf)
                Text(L("Відео")).tag(FileKind.video)
            }
            .pickerStyle(.segmented).labelsHidden().padding(.horizontal, 20).padding(.bottom, 12)
            .disabled(model.busy || model.pendingCount > 0)
            List(selection: $model.selectedRoot) {
                Section(L("Почати пошук")) {
                    Button(L("Сканувати весь Mac"), systemImage: "desktopcomputer", action: model.scanComputer)
                    Button(model.fileKind == .images ? L("Обрати зображення…") : L("Обрати файли…"), systemImage: "doc.badge.plus", action: model.chooseImages)
                    Button(L("Обрати папку…"), systemImage: "folder", action: model.chooseSearchFolder)
                    Button(L("Додати папки…"), systemImage: "folder.badge.plus", action: model.addFolders)
                }.disabled(model.busy)
                Section(L("Поточні джерела")) {
                    Button(L("Сканувати знову"), systemImage: "arrow.clockwise", action: model.requestScan)
                        .disabled(model.busy || model.roots.isEmpty)
                        .help(L("Повторити пошук у поточних папках"))
                    if model.roots.isEmpty { Text(L("Обери, де шукати")).foregroundStyle(.secondary) }
                    ForEach(model.roots, id: \.path) { root in
                        Label(root.path == "/" ? L("Весь Mac") : root.lastPathComponent, systemImage: root.path == "/" ? "desktopcomputer" : "folder")
                            .tag(root.path).help(root.path)
                            .contextMenu {
                                Button(L("Прибрати зі списку"), systemImage: "minus.circle") { model.removeRoot(root) }.disabled(model.busy)
                            }
                    }
                    if model.roots.count > 1 {
                        Button(L("Результати з усіх папок")) { model.selectedRoot = nil }
                    }
                }
            }.listStyle(.sidebar).buttonStyle(.plain).scrollContentBackground(.hidden)
            Button {
                model.showIgnoredFiles = true
            } label: {
                Label(L("Виключення (\(model.ignoredPaths.count))"), systemImage: "eye.slash")
            }
            .buttonStyle(.glass).padding(.horizontal, 20).padding(.top, 12)
            Button(L("Діагностика…"), systemImage: "stethoscope") { model.showDiagnostics = true }
                .buttonStyle(.glass).padding(.horizontal, 20).padding(.top, 8)
            Text(L("«Весь Mac» шукає доступні особисті зображення, зокрема на підключених дисках. Системні ресурси й бібліотеки пропускаються. macOS може попросити доступ до папок."))
                .font(.callout).foregroundStyle(.secondary).padding(20)
        }
        .frame(minWidth: 240, idealWidth: 260, maxWidth: .infinity, minHeight: 480, maxHeight: .infinity)
        .padding(.top, 56)
        .modifier(WorkspaceGlass()).padding(8)
        .containerBackground(.clear, for: .window)
    }
}
