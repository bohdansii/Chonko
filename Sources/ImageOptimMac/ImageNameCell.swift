import SwiftUI
import ImageCore

struct ImageNameCell: View {
    @Bindable var row: ImageRowModel
    let busy: Bool
    @State private var thumbnail: NSImage?
    @State private var showDetails = false
    var body: some View {
        HStack {
            Toggle(L("Обрати \(row.record.url.lastPathComponent)"), isOn: $row.selected)
                .labelsHidden().toggleStyle(.checkbox)
                .disabled(busy || row.trashedOriginalURL != nil || row.candidate != nil)
            Group {
                if let thumbnail { Image(nsImage: thumbnail).resizable().scaledToFit() }
                else { Image(systemName: row.record.kind == .pdf ? "doc.richtext" : row.record.kind == .video ? "film" : "photo").foregroundStyle(.secondary) }
            }
            .frame(width: 52, height: 52)
            .accessibilityHidden(true)
            VStack(alignment: .leading) {
                Text(row.record.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                Text(row.record.kind == .pdf ? L("Сторінок: \(row.record.media?.pages ?? 0) · PDF") : "\(row.record.width) × \(row.record.height) · \(row.record.url.pathExtension.uppercased())")
                    .font(.callout).foregroundStyle(.secondary)
                if let media = row.record.media, row.record.kind == .video {
                    Text("\(media.duration.formatted(.number.precision(.fractionLength(1)))) s · \(media.frameRate.formatted(.number.precision(.fractionLength(2)))) fps · \((Double(media.bitrate) / 1_000_000).formatted(.number.precision(.fractionLength(2)))) Mbps")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Button(L("Інформація про файл"), systemImage: "info.circle") { showDetails = true }
                .labelStyle(.iconOnly).buttonStyle(.borderless)
                .help(L("Повний шлях та інформація про файл"))
                .popover(isPresented: $showDetails) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(row.record.url.lastPathComponent).font(.headline)
                        Text(L("Повний шлях")).font(.subheadline).foregroundStyle(.secondary)
                        Text(row.originalLocation.path).textSelection(.enabled)
                        LabeledContent(L("Змінено"), value: formatDate(row.record.modified, includeTime: true))
                        HStack {
                            Button(L("Скопіювати шлях")) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(row.originalLocation.path, forType: .string) }
                            Button(L("Показати у Finder")) { NSWorkspace.shared.activateFileViewerSelecting([row.originalLocation]) }
                        }
                    }.padding(20).frame(width: 400)
                }
            Button(L("Показати в папці"), systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([row.originalLocation]) }
                .labelStyle(.iconOnly).buttonStyle(.borderless)
                .help(row.trashedOriginalURL == nil ? L("Показати оригінал у Finder") : L("Показати оригінал у Кошику"))
                .accessibilityLabel(L("Показати \(row.record.url.lastPathComponent) у папці"))
        }
        .frame(minHeight: 76)
        .accessibilityElement(children: .contain)
        .help(row.record.url.path)
        .contextMenu {
            Button(L("Інформація про файл"), systemImage: "info.circle") { showDetails = true }
            Button(L("Показати оригінал у Finder")) { NSWorkspace.shared.activateFileViewerSelecting([row.originalLocation]) }
            Button(L("Копіювати шлях")) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(row.record.url.path, forType: .string) }
        }
        .task(id: row.id) {
            // Skip formats that would need an unbounded full-image decode for a tiny thumbnail.
            if row.record.width > 0, let data = await ThumbnailLoader.load(row.record.url), !Task.isCancelled { thumbnail = NSImage(data: data) }
        }
    }
}
