import AppKit
import ImageCore
import SwiftUI

struct IgnoredFilesView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var selection: Set<String> = []

    private var paths: [String] {
        model.ignoredFiles.filter { search.isEmpty || $0.localizedStandardContains(search) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("Виключення")).font(.title2.bold())
            Text(L("Ці файли приховані під час пошуку. Виключення зберігаються за повним шляхом. Після повернення файл з’явиться під час наступного пошуку."))
                .foregroundStyle(.secondary)
            TextField(L("Назва або шлях"), text: $search).textFieldStyle(.roundedBorder)
            List(paths, id: \.self, selection: $selection) { path in
                VStack(alignment: .leading, spacing: 4) {
                    Text(URL(fileURLWithPath: path).lastPathComponent)
                    Text(path).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(2).help(path)
                }
                .tag(path)
                .contextMenu {
                    Button(L("Показати у Finder"), systemImage: "folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                    }
                    Button(L("Повернути в пошук"), systemImage: "eye") {
                        model.restoreIgnoredFiles([path])
                        selection.remove(path)
                    }.disabled(model.busy)
                }
            }
            .overlay {
                if model.ignoredPaths.isEmpty {
                    ContentUnavailableView(L("Виключень немає"), systemImage: "eye")
                } else if paths.isEmpty {
                    ContentUnavailableView.search
                }
            }
            HStack {
                Button(L("Повернути вибрані в пошук")) {
                    model.restoreIgnoredFiles(selection)
                    selection.removeAll()
                }.disabled(selection.isEmpty || model.busy)
                Button(L("Повернути всі")) {
                    model.restoreIgnoredFiles(model.ignoredPaths)
                    selection.removeAll()
                }.disabled(model.ignoredPaths.isEmpty || model.busy)
                Spacer()
                Button(L("Готово")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 740, height: 560)
    }
}
