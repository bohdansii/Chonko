import SwiftUI
import ImageCore
import UniformTypeIdentifiers

struct DiagnosticsView: View {
    let center: DiagnosticCenter
    @Environment(\.dismiss) private var dismiss
    @State private var confirmClear = false
    @State private var errorMessage: String?
    @State private var exporting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("Діагностика")).font(.title2.bold())
            Text(L("Останні 200 технічних подій зберігаються на цьому Mac. Звіт не містить назв або шляхів зображень і нікуди не надсилається автоматично."))
                .foregroundStyle(.secondary)
            if center.writeFailed {
                Label(L("Не вдалося зберегти журнал на диск."), systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            List(center.events.reversed()) { event in
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.date.formatted(date: .abbreviated, time: .standard)).font(.caption).foregroundStyle(.secondary)
                    Text(event.operation + " · " + event.message).textSelection(.enabled)
                    if let details = event.details { Text(details).font(.caption.monospaced()).textSelection(.enabled) }
                    if let domain = event.domain, let code = event.code {
                        Text(domain + " · " + String(code)).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
            }
            .overlay {
                if center.events.isEmpty { ContentUnavailableView(L("Подій ще немає"), systemImage: "checkmark.circle") }
            }
            HStack {
                Button(L("Експортувати звіт…"), systemImage: "square.and.arrow.up") { Task { await export() } }
                    .disabled(exporting)
                Button(L("Оновити")) { Task { await center.reload() } }
                Button(L("Очистити журнал"), role: .destructive) { confirmClear = true }
                Spacer()
                Button(L("Готово")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 780, height: 580)
        .task { await center.reload() }
        .confirmationDialog(L("Очистити журнал?"), isPresented: $confirmClear, titleVisibility: .visible) {
            Button(L("Очистити журнал"), role: .destructive, action: center.clear)
        }
        .alert(L("Не вдалося експортувати звіт"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button(L("Гаразд")) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func export() async {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Chonko-Diagnostics.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        exporting = true
        defer { exporting = false }
        do { try await center.exportData().write(to: url, options: .atomic) }
        catch { errorMessage = error.localizedDescription }
    }
}
