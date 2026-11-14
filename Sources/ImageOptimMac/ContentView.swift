import SwiftUI
import ImageCore

struct ContentView: View {
    @Bindable var model: AppModel
    @State private var comparison: ImageRowModel?
    @Environment(\.openWindow) private var openWindow
    @State private var showInputFormats = false
    @State private var receivingDrop = false
    var body: some View {
        VStack(spacing: 0) {
            workspaceControls
            Group {
                if model.showStatistics {
                    StatisticsView(store: model.statistics, canReset: !model.busy)
                } else {
                VStack(spacing: 0) {
                selectionBar
                Divider()
                if model.rows.isEmpty {
                    ContentUnavailableView {
                        Label(model.scanning ? L("Шукаємо файли") : L("Файли для оптимізації"), systemImage: "photo.on.rectangle")
                    } description: {
                        Text(model.scanning ? L("Список з’являтиметься поступово.") : L("Додай папки або проскануй свої файли. Обробка почнеться лише після твого натискання."))
                    } actions: {
                        if model.scanning { ProgressView() }
                        else {
                            Button(model.fileKind == .images ? L("Обрати зображення…") : L("Обрати файли…"), action: model.chooseImages)
                            Button(L("Обрати папку…"), action: model.chooseSearchFolder)
                            Text(L("Або перетягни файли сюди")).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if model.visibleRows.isEmpty {
                    ContentUnavailableView.search
                } else { imageTable }
                Divider()
                HStack {
                    if model.busy { ProgressView().controlSize(.small) }
                    Text(model.status).font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(model.savedBytes >= 0 ? L("Копії легші на") : L("Копії важчі на")): \(formatBytes(abs(model.savedBytes)))")
                        .monospacedDigit()
                        .help(L("Різниця ваги оригіналів і результатів. Копії поруч і файли в Кошику продовжують займати місце."))
                }
                .padding()
            }
                }
            }
            .navigationTitle(model.showStatistics ? L("Статистика") : model.fileKind.title)
            .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.94),
                    in: .rect(cornerRadius: 24))
        .clipShape(.rect(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24).strokeBorder(.separator.opacity(0.4))
                .allowsHitTesting(false)
        }
        .padding(8)
        }
        .frame(minWidth: 580, minHeight: 620)
        .contentShape(.rect)
        .dropDestination(for: URL.self, isEnabled: !model.busy) { urls, _ in
            receivingDrop = false
            model.importFiles(urls)
        }
        .onDropSessionUpdated { session in
            switch session.phase {
            case .entering, .active: receivingDrop = !model.busy
            default: receivingDrop = false
            }
        }
        .overlay {
            if receivingDrop {
                RoundedRectangle(cornerRadius: 24)
                    .fill(.regularMaterial)
                    .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(.tint, style: StrokeStyle(lineWidth: 3, dash: [10, 6])) }
                    .overlay {
                        VStack(spacing: 12) {
                            Image(systemName: "photo.badge.plus").font(.system(size: 44))
                            Text(L("Відпусти, щоб додати файли")).font(.title2.bold())
                            Text(L("Оптимізацію запустиш після вибору параметрів.")).foregroundStyle(.secondary)
                        }.padding(24)
                    }
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: model.busy) { _, busy in if busy { receivingDrop = false } }
        .containerBackground(.clear, for: .window)
        .onAppear { model.revealMainWindow = { openWindow(id: "main") } }
        .alert(L("Не вдалося виконати дію"), isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button(L("Гаразд")) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .confirmationDialog(L("Замінити оригінали?"), isPresented: $model.showReplaceConfirmation, titleVisibility: .visible) {
            Button(L("Оптимізувати й перемістити оригінали в Кошик"), role: .destructive, action: model.optimize)
        } message: {
            Text(L("Спочатку перевіримо нові файли. Оригінали перемістяться в Кошик лише після успішного збереження. Зміна розширення або назви може порушити посилання в інших програмах. Якщо результат не менший, запитаємо окремо."))
        }
        .confirmationDialog(L("Відкинути тимчасові результати?"), isPresented: $model.showRescanConfirmation, titleVisibility: .visible) {
            Button(L("Відкинути й сканувати"), role: .destructive, action: model.confirmRescan)
        } message: { Text(L("Результати, що очікують рішення, буде відкинуто. Оригінали залишаться.")) }
        .sheet(isPresented: $model.showConversionWarning) { ConversionWarningView(model: model) }
        .sheet(item: $model.videoPreview) { preview in VideoPreviewView(preview: preview) }
        .sheet(isPresented: $model.showDiagnostics) { DiagnosticsView(center: model.diagnostics) }
        .onChange(of: model.statistics.persistenceError) { _, error in
            if error != nil { model.diagnostics.record("statistics", "Statistics persistence failed") }
        }
        .sheet(isPresented: $model.showIgnoredFiles) { IgnoredFilesView(model: model) }
        .sheet(item: $comparison) { row in
            if row.record.kind == .images { ComparisonView(row: row) }
            else { MediaComparisonView(row: row) }
        }
        .sheet(isPresented: $model.showOnboarding) { FolderPermissionsView(model: model).interactiveDismissDisabled() }
        .confirmationDialog(L("Перемістити \(model.selectedFileCount) файлів у Кошик?"), isPresented: $model.showTrashConfirmation, titleVisibility: .visible) {
            Button(L("Перемістити в Кошик"), role: .destructive, action: model.trashSelectedFiles)
        } message: {
            Text(L("Буде переміщено вибрані оригінали, зокрема формати, які не підтримують оптимізацію. Відновити їх можна у Finder через Кошик."))
        }
    }

    private var workspaceControls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button(L("Папки"), systemImage: "sidebar.left") { model.showSourcesPanel.toggle() }
                    .labelStyle(.iconOnly)
                    .buttonBorderShape(.circle)
                Picker(L("Розділ"), selection: $model.showStatistics) {
                    Text(model.fileKind.title).tag(false)
                    Text(L("Статистика")).tag(true)
                }.pickerStyle(.segmented).labelsHidden()
                    .fixedSize(horizontal: true, vertical: false)
                    .clipShape(.capsule)
                Spacer(minLength: 0)
                if model.busy {
                    Button(model.isStopping ? L("Зупиняємо…") : L("Зупинити"), systemImage: "stop.circle", action: model.stop)
                        .disabled(model.isStopping)
                } else if !model.showStatistics {
                    Button(L("Оптимізувати (\(model.readyCount))"),
                           systemImage: "arrow.down.right.and.arrow.up.left", action: model.requestOptimization)
                        .buttonStyle(.glassProminent).disabled(model.readyCount == 0)
                }
                Button(L("Доступ до папок"), systemImage: "lock.open") { model.showOnboarding = true }
                    .labelStyle(.iconOnly)
                    .buttonBorderShape(.circle)
                    .help(L("Доступ до папок"))
                    .disabled(model.busy)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .frame(minHeight: model.busy ? 64 : 46)
            .overlay(alignment: .center) {
                VStack(spacing: 0) {
                    WorkingMascot(activity: model.scanning ? .searching : model.busy ? .optimizing : .idle)
                    if model.busy {
                        Text(model.scanning ? L("Шукаю…") : L("Працюю…"))
                            .font(.caption).foregroundStyle(.secondary).fixedSize()
                    }
                }
                .allowsHitTesting(false)
            }
            if let slow = model.slowScanFile {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Довго читаємо файл: \(slow.file.lastPathComponent)")).font(.callout.bold()).lineLimit(2)
                    Text(L("Це може бути великий файл, повільний диск або проблема читання. Можна пропустити файл чи зупинити пошук."))
                        .font(.caption).foregroundStyle(.secondary)
                    Button(L("Пропустити файл"), systemImage: "forward.end", action: model.skipSlowScanFile)
                }
                .padding(12).background(.orange.opacity(0.1), in: .rect(cornerRadius: 12))
            }
            if !model.showStatistics {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(L("Назва або шлях"), text: $model.search)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .glassEffect(.regular, in: .capsule)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, model.showSourcesPanel ? 24 : 56)
        .padding(.bottom, 12)
    }

    private var selectionBar: some View {
        VStack(spacing: 10) {
            HStack {
                if model.fileKind == .images {
                Button(L("Формати пошуку"), systemImage: "line.3.horizontal.decrease") { showInputFormats = true }
                    .disabled(model.pendingCount > 0)
                    .popover(isPresented: $showInputFormats) { InputFormatsView(model: model) }
                }
                Spacer(minLength: 8)
                Button(L("Обрати всі видимі")) { model.selectVisible(true) }
                Button(L("Зняти вибір")) { model.selectVisible(false) }
            }
            HStack {
                Menu {
                    Button(L("Ігнорувати вибрані"), systemImage: "eye.slash", action: model.ignoreSelectedFiles)
                    Divider()
                    Button(L("Перемістити в папку…"), systemImage: "folder", action: model.moveSelectedFiles)
                    Button(L("Перемістити в Кошик…"), systemImage: "trash", role: .destructive) { model.showTrashConfirmation = true }
                } label: { Label(L("Дії (\(model.selectedFileCount))"), systemImage: "ellipsis.circle") }
                    .disabled(model.selectedFileCount == 0 || model.pendingCount > 0)
                    .fixedSize()
                Spacer()
                Toggle(L("Лише вибрані"), isOn: $model.onlySelected).toggleStyle(.checkbox)
            }
        }
        .buttonStyle(.glass).buttonBorderShape(.capsule).controlSize(.large)
        .disabled(model.busy)
        .padding(16)
    }

    private var imageTable: some View {
        Table(model.visibleRows) {
            TableColumn(L("Файли")) { row in
                ImageNameCell(row: row, busy: model.busy)
            }.width(min: 200, ideal: 240, max: 280)
            TableColumn(L("Було")) { row in
                Text(formatBytes(row.record.bytes)).monospacedDigit()
            }.width(70)
            TableColumn(L("Стало")) { row in
                VStack(alignment: .leading) {
                    if let bytes = row.outputBytes {
                        Text(formatBytes(bytes)).monospacedDigit()
                        let change = FileSizeChange(originalBytes: row.record.bytes, resultBytes: bytes)
                        Text(change.summary)
                            .foregroundStyle(bytes >= row.record.bytes ? .orange : .green)
                            .font(.callout).monospacedDigit()
                            .help(change.explanation)
                            .accessibilityLabel(change.explanation)
                    } else { Text("—").foregroundStyle(.secondary) }
                }
            }.width(110)
            TableColumn(L("Стан і дії")) { row in
                VStack(alignment: .leading, spacing: 6) {
                    Text(row.phase).font(.callout).lineLimit(3).help(row.phase)
                    if let notice = row.conversionNotice { Text(notice).font(.caption).foregroundStyle(.secondary) }
                    if row.running {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            if let started = row.startedAt, context.date.timeIntervalSince(started) >= 10, row.candidate == nil {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(row.record.kind == .video ? L("Минуло \(Int(context.date.timeIntervalSince(started))) с. Час залежить від довжини відео й режиму стиснення.") : (row.skipRequested ? L("Пропуск запитано. Очікуємо завершення поточного читання.") : L("Обробка триває довше звичайного. Великий файл або повільний кодек.")))
                                        .font(.caption).foregroundStyle(.secondary)
                                    Button(L("Пропустити файл"), systemImage: "forward.end") { model.skipEncoding(row) }
                                        .disabled(row.skipRequested)
                                }
                            }
                        }
                        if let progress = row.progress {
                            ProgressView(value: progress) {
                                Text(row.record.kind == .video ? "\(Int(progress * 100))%" : L("\(Int(progress * 100))% · кінцева вага після кодування")).font(.caption)
                            }
                        } else { ProgressView(L("Читання / кодування…")).controlSize(.small) }
                        if let seconds = row.remainingSeconds {
                            Text(L("Орієнтовно ще \(max(1, Int(ceil(seconds / 60)))) хв · перевірка може тривати довше")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if row.candidate != nil && !row.running {
                        HStack {
                            Button(L("Зберегти")) { model.keepLarger(row) }
                                .help(row.saveMode == .replace ? L("Зберегти більший результат; оригінал перемістити в Кошик") : L("Зберегти результат, хоча він не менший"))
                            Button(L("Відкинути")) { model.discard(row) }
                            Button(L("Порівняти")) { comparison = row }
                        }.disabled(model.busy)
                    } else if let output = row.outputURL {
                        HStack {
                            Button(L("Показати у Finder")) { NSWorkspace.shared.activateFileViewerSelecting([output]) }
                            Button(L("Порівняти")) { comparison = row }
                        }
                    }
                }.padding(.vertical, 6).accessibilityElement(children: .contain)
            }.width(min: 210, ideal: 290)
        }
    }
}
