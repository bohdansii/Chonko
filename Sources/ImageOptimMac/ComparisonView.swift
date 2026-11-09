import ImageCore
import SwiftUI

struct ComparisonView: View {
    let row: ImageRowModel
    @Environment(\.dismiss) private var dismiss
    @State private var original: NSImage?
    @State private var result: NSImage?
    var body: some View {
        VStack {
            Text(row.record.url.lastPathComponent).font(.headline)
            HStack {
                preview(L("Оригінал"), image: original, bytes: row.record.bytes)
                Divider()
                preview(L("Результат"), image: result, bytes: row.outputBytes ?? 0)
            }
            Text(L("Попередній перегляд зменшений до 1600 пікселів; він не замінює перевірку зображення у повному розмірі."))
                .font(.callout).foregroundStyle(.secondary)
            Button(L("Закрити"), action: { dismiss() }).keyboardShortcut(.cancelAction)
        }
        .padding().frame(width: 900, height: 610)
        .task {
            async let before = ThumbnailLoader.load(row.originalLocation, pixels: 1600)
            async let after = loadResult()
            original = await before.flatMap(NSImage.init(data:))
            result = await after.flatMap(NSImage.init(data:))
        }
    }
    private func loadResult() async -> Data? {
        guard let url = row.candidate?.file ?? row.outputURL else { return nil }
        return await ThumbnailLoader.load(url, pixels: 1600)
    }
    private func preview(_ title: String, image: NSImage?, bytes: Int64) -> some View {
        VStack {
            Text(title).font(.headline)
            Text(formatBytes(bytes)).monospacedDigit()
            if let image { Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity) }
            else { ContentUnavailableView(L("Перегляд недоступний"), systemImage: "photo") }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
