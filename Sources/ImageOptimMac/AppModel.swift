import AppKit
import Observation
import ImageCore
import Synchronization
import UniformTypeIdentifiers

@MainActor @Observable final class AppModel {
    let diagnostics: DiagnosticCenter
    var showDiagnostics = false
    private(set) var slowScanFile: ScanControl.Snapshot?
    @ObservationIgnored private var scanControl = ScanControl()
    @ObservationIgnored private var scanToken = UUID()
    @ObservationIgnored private var scanMonitor: Task<Void, Never>?
    @ObservationIgnored private var encodingTasks: [String: Task<EncodedCandidate, Error>] = [:]
    var fileKind: FileKind = .images
    var pdfProfile: PDFProfile = .preserve
    var videoSettings = VideoSettings()
    var videoPreview: VideoPreview?
    var mediaTools: MediaTools { MediaTools(directory: codecURL.deletingLastPathComponent()) }
    var roots: [URL] = []
    var rows: [ImageRowModel] = []
    var format: OutputFormat = .webp
    var lossless = false
    var quality = 75.0
    var preserveMetadata = true
    var performanceMode: PerformanceMode = .automatic {
        didSet { defaults.set(performanceMode.rawValue, forKey: "performanceMode") }
    }
    private(set) var activeEncodingCount = 0
    private(set) var peakEncodingCount = 0
    var saveMode: SaveMode = .replace
    var outputFolder: URL?
    var search = "" { didSet { scheduleFilter() } }
    var onlySelected = false { didSet { refreshVisibleRows() } }
    var scanning = false
    var optimizing = false
    var isStopping = false
    var managingFiles = false
    var status = L("Додай папку або обери «Мої файли», щоб розпочати.")
    var errorMessage: String?
    var showReplaceConfirmation = false
    var showRescanConfirmation = false
    var showTrashConfirmation = false
    var selectedRoot: String? { didSet { refreshVisibleRows() } }
    private(set) var ignoredPaths: Set<String> = []
    var ignoredFiles: [String] { ignoredPaths.sorted { $0.localizedStandardCompare($1) == .orderedAscending } }
    var showIgnoredFiles = false
    var showSourcesPanel = true
    var showOnboarding = false
    private(set) var suggestedFolders: [FolderAccess] = []
    var readyCount = 0
    var selectedFileCount = 0
    var savedBytes: Int64 = 0
    var showStatistics = false
    private(set) var inputFormats = InputFormat.defaults
    let statistics: StatisticsStore
    var language: String {
        didSet {
            defaults.set(language, forKey: "language")
            ImageLocalization.configure(language: language, resourceURL: Bundle.main.resourceURL)
            for row in rows { row.phase = ImageLocalization.relocalize(row.phase) }
            for folder in suggestedFolders { folder.status = ImageLocalization.relocalize(folder.status) }
            status = L("Обери, де шукати")
        }
    }
    private(set) var visibleRows: [ImageRowModel] = []
    private var pendingIDs = Set<String>()
    @ObservationIgnored private(set) var operation: Task<Void, Never>?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var generatedPaths = Set<String>()
    @ObservationIgnored private var filterTask: Task<Void, Never>?
    @ObservationIgnored private var accessTasks: [Task<Void, Never>] = []
    @ObservationIgnored private var folderBookmarks: [String: Data] = [:]
    @ObservationIgnored private var scopedURLs: [URL] = []
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let codecOverride: URL?
    @ObservationIgnored private var requestedRoots: [URL]?
    @ObservationIgnored private var changingSelectionBatch = false
    @ObservationIgnored var revealMainWindow: (() -> Void)?

    init(defaults: UserDefaults = .standard, codecURL: URL? = nil, statistics: StatisticsStore = StatisticsStore(), diagnostics: DiagnosticCenter = DiagnosticCenter()) {
        self.defaults = defaults; self.codecOverride = codecURL
        self.statistics = statistics
        self.diagnostics = diagnostics
        if statistics.persistenceError != nil { diagnostics.record("statistics", "History could not be loaded") }
        ignoredPaths = Set((defaults.stringArray(forKey: "ignoredPaths") ?? []).map {
            URL(fileURLWithPath: $0).standardizedFileURL.path
        })
        self.performanceMode = defaults.string(forKey: "performanceMode").flatMap(PerformanceMode.init(rawValue:)) ?? .automatic
        self.language = defaults.string(forKey: "language") ?? (Locale.preferredLanguages.first?.hasPrefix("uk") == true ? "uk" : "en")
        ImageLocalization.configure(language: language, resourceURL: Bundle.main.resourceURL)
        suggestedFolders = FolderAccess.suggested()
        status = L("Обери, де шукати")
        if let stored = defaults.stringArray(forKey: "inputFormats") { inputFormats = Set(stored.compactMap(InputFormat.init(rawValue:))) }
    }

    var busy: Bool { scanning || optimizing || managingFiles }
    var selectedFiles: [ImageRowModel] { rows.filter { $0.selected && $0.candidate == nil && $0.trashedOriginalURL == nil } }
    var pendingCount: Int { pendingIDs.count }
    var chosen: [ImageRowModel] { rows.filter { $0.selected && $0.record.isEligible && !$0.completed && $0.candidate == nil } }
    func applyFormatDefaults() {
        lossless = format.alwaysLossless
        quality = Double(format.suggestedQuality)
    }
    func refreshVisibleRows() {
        visibleRows = rows.filter { row in
            (!onlySelected || row.selected) && (search.isEmpty || row.record.url.path.localizedStandardContains(search))
            && (selectedRoot == nil || row.record.root.path == selectedRoot)
        }
    }
    private func scheduleFilter() {
        filterTask?.cancel()
        filterTask = Task {
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            refreshVisibleRows()
        }
    }
    var codecURL: URL { codecOverride ?? Bundle.main.resourceURL!.appendingPathComponent("Codecs/cwebp") }
    var policy: ScanPolicy {
        var excluded = filePolicy.excludedFiles
        excluded.formUnion(rows.compactMap { $0.outputURL?.path })
        excluded.formUnion(generatedPaths)
        excluded.formUnion(ignoredPaths)
        return ScanPolicy(excludedFiles: excluded, includedExtensions: fileKind == .images ? Set(inputFormats.flatMap(\.extensions)) : fileKind.extensions)
    }
    var filePolicy: ScanPolicy {
        ScanPolicy(excludedFiles: Set(NSScreen.screens.compactMap { NSWorkspace.shared.desktopImageURL(for: $0)?.standardizedFileURL.path }))
    }

    func setInputFormats(_ formats: Set<InputFormat>) {
        guard !busy, pendingCount == 0 else { return }
        inputFormats = formats
        defaults.set(formats.map(\.rawValue), forKey: "inputFormats")
        if !roots.isEmpty { scan() }
    }

    func changeKind(_ kind: FileKind) {
        guard !busy, pendingCount == 0, kind != fileKind else { return }
        rows.removeAll(); visibleRows.removeAll(); readyCount = 0; selectedFileCount = 0; savedBytes = 0
        selectedRoot = nil; search = ""; fileKind = kind
        saveMode = kind == .images ? .replace : .alongside
        status = L("Обери файли або папку для пошуку.")
    }

    func importFiles(_ urls: [URL]) {
        if busy {
            let previous = operation
            Task { await previous?.value; importFiles(urls) }
            return
        }
        let kinds = Set(urls.compactMap(FileKind.detect))
        guard kinds.count <= 1 else { errorMessage = L("Додавай окремо зображення, PDF або відео. Для кожного типу є свій режим."); return }
        if let kind = kinds.first, kind != fileKind {
            guard pendingCount == 0 else { errorMessage = L("Спочатку збережи або відкинь поточні результати."); return }
            changeKind(kind)
        }
        showStatistics = false; showOnboarding = false
        search = ""; onlySelected = false; selectedRoot = nil
        let files = urls.filter { $0.isFileURL }
        guard !files.isEmpty else { errorMessage = L("Обери локальні файли зображень."); return }
        files.forEach { rememberAccess($0) }
        let token = UUID(), control = ScanControl(), policy = filePolicy
        scanToken = token; scanControl = control
        scanning = true
        status = L("Додаємо зображення…")
        diagnostics.setStage("import")
        diagnostics.record("import", "Explicit file import started")
        monitorScan(token: token, control: control)
        operation = Task {
            let records = await FinderImageInput.inspect(files, policy: policy, tools: mediaTools, control: control)
            guard scanToken == token, !Task.isCancelled else { return }
            let existing = Set(rows.map(\.id))
            let added = records.filter { !existing.contains($0.id) && !ignoredPaths.contains($0.url.standardizedFileURL.path) }
            append(added)
            status = L("Додано: \(added.count). Уже в списку, виключено або не вдалося додати: \(urls.count - added.count).")
            diagnostics.record("import", "Explicit file import completed; added \(added.count)")
            scanning = false
            scanMonitor?.cancel(); slowScanFile = nil
            diagnostics.setStage("idle")
        }
    }

    func chooseImages() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = fileKind.extensions.sorted().compactMap { UTType(filenameExtension: $0) }
        panel.prompt = L("Додати")
        panel.message = L("Обери один або кілька файлів. Папки сканувати не будемо.")
        guard panel.runModal() == .OK else { return }
        importFiles(panel.urls)
    }

    func start() {
        guard !started else { return }
        started = true
        let arguments = ProcessInfo.processInfo.arguments
        if let root = ProcessInfo.processInfo.environment["IMAGEOPTIM_QA_ROOT"] {
            if let kind = ProcessInfo.processInfo.environment["IMAGEOPTIM_QA_KIND"].flatMap(FileKind.init(rawValue:)) { fileKind = kind; saveMode = .alongside }
            roots = [URL(fileURLWithPath: root, isDirectory: true)]
            scan(); return
        }
        if let index = arguments.firstIndex(of: "--scan-folder"), arguments.count > index + 1 {
            roots = [URL(fileURLWithPath: arguments[index + 1], isDirectory: true)]
            scan(); return
        }
        generatedPaths = Set(defaults.stringArray(forKey: "generatedPaths") ?? [])
        folderBookmarks = defaults.dictionary(forKey: "folderBookmarks") as? [String: Data] ?? [:]
        roots = (defaults.stringArray(forKey: "scanRoots") ?? []).map { path in
            if let data = folderBookmarks[path] {
                var stale = false
                if let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale) {
                    if url.startAccessingSecurityScopedResource() { scopedURLs.append(url) }
                    if stale { folderBookmarks[url.path] = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) }
                    return url
                }
            }
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        if !defaults.bool(forKey: "onboardingComplete") { showOnboarding = true }
    }

    func persist() {
        guard !ProcessInfo.processInfo.arguments.contains("--scan-folder"), ProcessInfo.processInfo.environment["IMAGEOPTIM_QA_ROOT"] == nil else { return }
        defaults.set(roots.map(\.path), forKey: "scanRoots")
        defaults.set(Array(generatedPaths), forKey: "generatedPaths")
        defaults.set(folderBookmarks, forKey: "folderBookmarks")
    }

    func requestAccess(to suggestion: FolderAccess?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.allowsMultipleSelection = suggestion == nil
        panel.directoryURL = suggestion?.url
        panel.message = L("Обери папку для пошуку й збереження оптимізованих зображень.")
        panel.prompt = L("Надати доступ")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            let canonical = url.resolvingSymlinksInPath().standardizedFileURL
            guard !policy.excludes(canonical) else { errorMessage = L("Системні каталоги та бібліотеки виключено. Обери папку зі своїми зображеннями."); continue }
            rememberAccess(url)
            if !roots.contains(canonical) { roots.append(canonical) }
            if let suggestion {
                suggestion.url = canonical; suggestion.checking = true
                suggestion.status = L("Перевіряємо читання…")
                accessTasks.append(Task {
                    let accessible = await Self.probeFolder(canonical)
                    guard !Task.isCancelled else { return }
                    suggestion.checking = false
                    suggestion.status = accessible ? L("Читання доступне · \(canonical.lastPathComponent)") : L("Додано · macOS обмежує читання")
                })
            }
        }
        persist()
    }

    private func rememberAccess(_ url: URL) {
        if url.startAccessingSecurityScopedResource() { scopedURLs.append(url) }
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        folderBookmarks[path] = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    @concurrent private static func probeFolder(_ url: URL) async -> Bool {
        guard !Task.isCancelled else { return false }
        // Read one enumeration result instead of loading every filename in a large directory.
        return probeFolderSynchronously(url)
    }

    nonisolated private static func probeFolderSynchronously(_ url: URL) -> Bool {
        let failed = Mutex(false)
        guard let iterator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants], errorHandler: { _, _ in failed.withLock { $0 = true }; return false }) else { return false }
        _ = iterator.nextObject()
        return !failed.withLock { $0 }
    }

    func finishOnboarding(scan shouldScan: Bool) {
        showOnboarding = false
        defaults.set(true, forKey: "onboardingComplete")
        persist()
        if shouldScan { requestScan() }
    }

    func removeRootWithoutScanning(_ root: URL) {
        roots.removeAll { $0 == root }; folderBookmarks[root.path] = nil
        if selectedRoot == root.path { selectedRoot = nil }
        persist()
    }

    func removeRoot(_ root: URL) {
        guard !busy else { return }
        requestScan(in: roots.filter { $0 != root })
    }

    func chooseSearchFolder() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.message = L("Шукати зображення лише в цій папці та її підпапках. Попередні джерела буде замінено.")
        panel.prompt = L("Шукати тут")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let canonical = url.resolvingSymlinksInPath().standardizedFileURL
        guard !policy.excludes(canonical) else { errorMessage = L("Обери папку зі своїми зображеннями поза системними каталогами."); return }
        rememberAccess(url)
        requestScan(in: [canonical])
    }

    func addFolders() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true
        panel.prompt = L("Додати")
        guard panel.runModal() == .OK else { return }
        var newRoots = roots
        for url in panel.urls {
            let canonical = url.resolvingSymlinksInPath().standardizedFileURL
            if policy.excludes(canonical) { errorMessage = L("Системні папки, бібліотеки та пакети застосунків виключені з обробки."); continue }
            if !newRoots.contains(canonical) { newRoots.append(canonical) }
            rememberAccess(url)
        }
        requestScan(in: newRoots)
    }

    func scanHome() {
        guard !busy else { return }
        requestScan(in: [FileManager.default.homeDirectoryForCurrentUser])
    }
    func scanComputer() {
        guard !busy else { return }
        requestScan(in: [URL(fileURLWithPath: "/", isDirectory: true)])
    }
    func installFinderAction() {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("Optimize in Chonko.workflow"), FileManager.default.fileExists(atPath: url.path), NSWorkspace.shared.open(url) else {
            errorMessage = L("Не вдалося відкрити інсталятор дії Finder.")
            return
        }
    }

    func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.prompt = L("Зберігати тут")
        if panel.runModal() == .OK, let url = panel.url {
            let canonical = url.resolvingSymlinksInPath().standardizedFileURL
            guard !policy.excludes(canonical) else { errorMessage = L("Обери папку поза системними каталогами."); return }
            outputFolder = canonical
        }
    }

    func requestScan() {
        requestedRoots = nil
        if pendingCount > 0 { showRescanConfirmation = true }
        else { scan() }
    }

    func requestScan(in newRoots: [URL]) {
        guard !busy else { return }
        requestedRoots = newRoots
        if pendingCount > 0 { showRescanConfirmation = true }
        else { confirmRescan() }
    }

    func confirmRescan() {
        if let requestedRoots { roots = requestedRoots; selectedRoot = nil; persist() }
        requestedRoots = nil
        scan()
    }

    func scan() {
        guard !busy else { return }
        rows.forEach { $0.candidate?.discard() }
        rows.removeAll()
        visibleRows.removeAll(); readyCount = 0; selectedFileCount = 0; savedBytes = 0; pendingIDs.removeAll()
        scanning = true; status = L("Шукаємо зображення… Системні каталоги виключено.")
        let roots = roots, policy = policy
        let token = UUID()
        scanToken = token
        let control = ScanControl()
        scanControl = control
        slowScanFile = nil
        diagnostics.setStage("scan")
        diagnostics.record("scan", "Scan started")
        monitorScan(token: token, control: control)
        operation = Task {
            do {
                let report = try await ImageScanner.scan(roots: roots, policy: policy, tools: mediaTools, control: control, onProgress: { [weak self] visited in
                    await self?.scanProgress(visited, token: token)
                }) { [weak self] batch in
                    await self?.acceptScanBatch(batch, token: token)
                }
                guard scanToken == token else { return }
                status = L("Знайдено: \(rows.count). Недоступних шляхів: \(report.inaccessible). Лише в iCloud: \(report.cloudOnly).")
                diagnostics.record("scan", "Scan completed; found \(rows.count), inaccessible \(report.inaccessible), cloud-only \(report.cloudOnly)")
            } catch is CancellationError {
                guard scanToken == token else { return }
                status = L("Пошук зупинено. Знайдено: \(rows.count).")
            } catch {
                guard scanToken == token else { return }
                errorMessage = error.localizedDescription
                diagnostics.record("scan", "Scan failed", error: error)
            }
            guard scanToken == token else { return }
            scanning = false
            scanMonitor?.cancel()
            slowScanFile = nil
            diagnostics.setStage("idle")
        }
    }

    private func monitorScan(token: UUID, control: ScanControl) {
        scanMonitor?.cancel()
        scanMonitor = Task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard self.scanToken == token, self.scanning else { return }
                if let current = control.current, Date.now.timeIntervalSince(current.startedAt) >= 10 {
                    if slowScanFile?.file != current.file {
                        diagnostics.record("scan", "Image inspection taking longer than 10 seconds")
                    }
                    slowScanFile = current
                } else { slowScanFile = nil }
            }
        }
    }

    private func acceptScanBatch(_ batch: [ImageRecord], token: UUID) {
        guard scanning, token == scanToken, !Task.isCancelled else { return }
        append(batch)
    }

    private func scanProgress(_ visited: Int, token: UUID) {
        guard scanning, token == scanToken else { return }
        status = L("Переглянуто шляхів: \(visited). Знайдено: \(rows.count).")
    }

    func skipSlowScanFile() {
        guard scanning, let slowScanFile else { return }
        guard scanControl.skipCurrent(expected: slowScanFile.file) else {
            self.slowScanFile = nil
            return
        }
        diagnostics.record("scan", "Skip current inspection requested")
        status = L("Пропуск запитано. Очікуємо завершення поточного читання.")
        self.slowScanFile = nil
    }

    func append(_ records: [ImageRecord]) {
        let added = records.filter { !ignoredPaths.contains($0.url.standardizedFileURL.path) }.map(ImageRowModel.init)
        for row in added {
            if row.selected { readyCount += 1 }
            if row.selected { selectedFileCount += 1 }
            row.selectionChanged = { [weak self, weak row] selected in
                guard let self, let row else { return }
                self.selectedFileCount += selected ? 1 : -1
                if row.record.isEligible && !row.completed && row.candidate == nil { self.readyCount += selected ? 1 : -1 }
                if self.onlySelected && !self.changingSelectionBatch { self.scheduleFilter() }
            }
        }
        rows.append(contentsOf: added)
        refreshVisibleRows()
    }

    func ignoreSelectedFiles() {
        guard !busy, pendingCount == 0 else { return }
        let paths = Set(selectedFiles.map { $0.record.url.standardizedFileURL.path })
        guard !paths.isEmpty else { return }
        ignoredPaths.formUnion(paths)
        defaults.set(Array(ignoredPaths).sorted(), forKey: "ignoredPaths")
        rows.removeAll { paths.contains($0.record.url.standardizedFileURL.path) }
        readyCount = chosen.count
        selectedFileCount = selectedFiles.count
        refreshVisibleRows()
    }

    func restoreIgnoredFiles(_ paths: Set<String>) {
        guard !busy else { return }
        ignoredPaths.subtract(paths)
        defaults.set(Array(ignoredPaths).sorted(), forKey: "ignoredPaths")
    }

    func selectVisible(_ selected: Bool) {
        changingSelectionBatch = true
        for row in visibleRows where row.trashedOriginalURL == nil && row.candidate == nil { row.selected = selected }
        changingSelectionBatch = false
        if onlySelected { refreshVisibleRows() }
    }

    func previewVideo(automatic: Bool) {
        guard !busy, let row = chosen.first(where: { $0.record.kind == .video }) else { return }
        diagnostics.setStage("videoPreview")
        diagnostics.record("videoPreview", "Preview started; automatic \(automatic)")
        videoPreview?.discard(); videoPreview = nil
        optimizing = true
        status = automatic ? L("Підбираємо бітрейт на трьох фрагментах…") : L("Створюємо тестовий фрагмент…")
        let settings = videoSettings, tools = mediaTools
        operation = Task {
            do {
                let preview = try await VideoPreviewService.create(row.record, settings: settings, automatic: automatic, tools: tools) { fraction in
                    await MainActor.run { row.progress = fraction }
                }
                if Task.isCancelled { preview.discard(); throw CancellationError() }
                videoSettings.bitratePercent = preview.bitratePercent
                videoPreview = preview
                status = L("Фрагмент готовий. Перевір вигляд перед обробкою всього відео.")
            } catch is CancellationError { status = L("Перевірку зупинено. Оригінал збережено.") }
            catch { errorMessage = error.localizedDescription; diagnostics.record("videoPreview", "Video preview failed", error: error) }
            row.progress = nil; optimizing = false; isStopping = false
            diagnostics.setStage("idle")
            diagnostics.record("videoPreview", "Preview completed or cancelled")
        }
    }

    func requestOptimization() {
        guard !busy, !chosen.isEmpty else { return }
        if saveMode == .folder && outputFolder == nil { chooseOutputFolder(); if outputFolder == nil { return } }
        if saveMode == .replace { showReplaceConfirmation = true }
        else { optimize() }
    }

    func optimize() {
        guard !busy else { return }
        let queue = chosen
        let settings = EncodeSettings(format: format, lossless: lossless, quality: Int(quality), preserveMetadata: preserveMetadata)
        let mode = saveMode, folder = outputFolder, policy = filePolicy, codecURL = codecURL
        optimizing = true
        isStopping = false
        diagnostics.setStage("optimize")
        diagnostics.record("optimize", "Batch started; kind \(fileKind.rawValue), files \(queue.count), format \(fileKind == .images ? settings.format.rawValue : fileKind == .pdf ? "pdf" : videoSettings.codec.rawValue), mode \(mode.rawValue)")
        status = L("Оптимізація файлів…")
        queue.forEach { $0.phase = L("У черзі"); $0.progress = nil }
        let workerLimit = fileKind == .video ? 1 : performanceMode.workerLimit
        operation = Task {
            var processed = 0
            var next = 0
            var active = 0
            var pixelsInFlight: Int64 = 0
            peakEncodingCount = 0
            await withTaskGroup(of: Int64.self) { group in
                while next < queue.count || active > 0 {
                    while next < queue.count && active < workerLimit && !Task.isCancelled {
                        let row = queue[next]
                        let pixels = Int64(row.record.width) * Int64(row.record.height)
                        if active > 0 && pixelsInFlight + pixels > performanceMode.pixelBudget { break }
                        next += 1; active += 1; pixelsInFlight += pixels
                        group.addTask { [self] in
                            await process(row, settings: settings, mode: mode, folder: folder, policy: policy, codecURL: codecURL)
                            return pixels
                        }
                    }
                    if active == 0 { break }
                    if let pixels = await group.next() {
                        active -= 1; pixelsInFlight -= pixels; processed += 1
                        status = L("Оброблено \(processed) із \(queue.count). Рішень очікують: \(pendingCount).")
                    }
                    if Task.isCancelled { group.cancelAll() }
                }
            }
            for row in queue where row.phase == L("У черзі") { row.phase = L("Зупинено · оригінал збережено") }
            optimizing = false
            isStopping = false
            diagnostics.record("optimize", "Batch finished or cancelled; processed \(processed), pending \(pendingCount)")
            diagnostics.setStage("idle")
            readyCount = chosen.count
            selectedFileCount = selectedFiles.count
            persist()
            refreshVisibleRows()
        }
    }

    private func process(_ row: ImageRowModel, settings: EncodeSettings, mode: SaveMode, folder: URL?, policy: ScanPolicy, codecURL: URL) async {
                activeEncodingCount += 1
                peakEncodingCount = max(peakEncodingCount, activeEncodingCount)
                defer { activeEncodingCount -= 1; row.running = false; encodingTasks[row.id] = nil }
                row.startedAt = .now
                row.lastDiagnosticStage = ""; row.lastDiagnosticFraction = -1; row.remainingSeconds = nil
                diagnostics.record("file", "Job \(row.diagnosticID); kind \(row.record.kind.rawValue); bytes \(row.record.bytes); dimensions \(row.record.width)x\(row.record.height); video mode \(videoSettings.mode.rawValue), codec \(videoSettings.codec.rawValue), bitrate \(videoSettings.bitratePercent)%")
                row.skipRequested = false
                row.running = true; row.phase = L("Кодування…")
                row.saveMode = mode; row.outputFolder = folder
                do {
                    let encoding = Task {
                        let progress: @Sendable (Double?) async -> Void = { [row] fraction in
                            await MainActor.run { row.progress = fraction }
                        }
                        if row.record.kind == .images {
                            return try await ImageEncoder.encode(row.record, settings: settings, codecURL: codecURL, progress: progress)
                        }
                        return try await MediaEncoder.encode(row.record, pdfProfile: pdfProfile, video: videoSettings, tools: mediaTools, progress: progress) { [self, row] update in
                            await MainActor.run {
                                row.phase = update.stage; row.remainingSeconds = update.remainingSeconds
                                status = update.stage + " · \(Int(update.fraction * 100))%"
                                if row.lastDiagnosticStage != update.stage || update.fraction - row.lastDiagnosticFraction >= 0.1 {
                                    row.lastDiagnosticStage = update.stage; row.lastDiagnosticFraction = update.fraction
                                    diagnostics.setStage(update.stage)
                                    diagnostics.record("videoProgress", "Job \(row.diagnosticID); \(update.stage); \(Int(update.fraction * 100))%; elapsed \(Int(Date.now.timeIntervalSince(row.startedAt ?? .now)))s")
                                }
                            }
                        }
                    }
                    encodingTasks[row.id] = encoding
                    let candidate = try await withTaskCancellationHandler {
                        try await encoding.value
                    } onCancel: { encoding.cancel() }
                    if Task.isCancelled || row.skipRequested { candidate.discard(); throw CancellationError() }
                    row.outputBytes = candidate.bytes
                    if row.selected { readyCount -= 1 }
                    row.candidate = candidate
                    pendingIDs.insert(row.id)
                    if candidate.isLarger {
                        row.phase = L("Результат не менший. Обери дію.")
                    } else {
                        row.phase = L("Перевірка та збереження…")
                        let result = try await CandidateStore.save(candidate, mode: mode, folder: folder, policy: policy)
                        finish(row, result: result)
                    }
                } catch is CancellationError {
                    row.candidate?.discard(); row.candidate = nil
                    pendingIDs.remove(row.id)
                    diagnostics.record("file", "Job \(row.diagnosticID); cancelled or skipped; progress \(Int((row.progress ?? 0) * 100))%")
                    row.phase = row.skipRequested ? L("Пропущено · оригінал збережено") : L("Зупинено · оригінал збережено")
                } catch {
                    diagnostics.record("file", "Job \(row.diagnosticID); stage \(row.lastDiagnosticStage)")
                    row.phase = error.localizedDescription
                    diagnostics.record("optimize", "Job \(row.diagnosticID); encoding or save failed; kind \(row.record.kind.rawValue)", error: error)
                }
    }

    private func finish(_ row: ImageRowModel, result: SaveResult) {
        if let candidate = row.candidate {
            if let mediaFormat = candidate.mediaFormat { statistics.record(original: row.record.bytes, result: candidate.bytes, formatName: mediaFormat) }
            else { statistics.record(original: row.record.bytes, result: candidate.bytes, format: candidate.settings.format) }
        }
        row.trashedOriginalURL = result.trashedOriginal
        row.outputURL = result.url; row.completed = true; row.selected = false; row.candidate = nil
        if result.warning != nil { diagnostics.record("save", "Output saved; original retained after replacement warning") }
        row.phase = result.warning ?? (result.trashedOriginal == nil ? L("Збережено") : L("Збережено · оригінал у Кошику"))
        generatedPaths.insert(result.url.path)
        pendingIDs.remove(row.id)
        savedBytes += row.record.bytes - (row.outputBytes ?? row.record.bytes)
    }

    func keepLarger(_ row: ImageRowModel) {
        guard !busy, let candidate = row.candidate else { return }
        let mode = row.saveMode, folder = row.outputFolder, policy = filePolicy
        optimizing = true; row.running = true
        operation = Task {
            do {
                let result = try await CandidateStore.save(candidate, mode: mode, folder: folder, policy: policy, allowLarger: true)
                finish(row, result: result)
            } catch {
                row.phase = error.localizedDescription
                diagnostics.record("save", "Saving retained result failed", error: error)
            }
            row.running = false; optimizing = false
            persist(); refreshVisibleRows()
        }
    }

    func discard(_ row: ImageRowModel) {
        row.candidate?.discard(); row.candidate = nil; row.completed = true; row.selected = false
        row.phase = L("Пропущено · оригінал збережено")
        pendingIDs.remove(row.id)
        refreshVisibleRows()
    }

    func stop() {
        operation?.cancel()
        if scanning {
            scanToken = UUID()
            scanning = false
            scanMonitor?.cancel()
            slowScanFile = nil
            status = L("Пошук зупинено. Знайдено: \(rows.count).")
            diagnostics.record("scan", "Scan cancellation requested")
            diagnostics.setStage("idle")
        } else if optimizing {
            isStopping = true
            status = L("Зупиняємо обробку. Уже розпочате збереження має завершитися.")
            diagnostics.setStage("cancelling")
            diagnostics.record("optimize", "Batch cancellation requested")
            for task in encodingTasks.values { task.cancel() }
        }
    }

    func skipEncoding(_ row: ImageRowModel) {
        guard row.running, row.candidate == nil, !row.skipRequested else { return }
        row.skipRequested = true
        row.selected = false
        row.completed = true
        row.phase = L("Пропуск запитано. Очікуємо завершення поточного читання.")
        encodingTasks[row.id]?.cancel()
        diagnostics.record("optimize", "Current file skip requested")
    }

    func moveSelectedFiles() {
        guard !busy, pendingCount == 0, selectedFileCount > 0 else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.prompt = L("Перемістити сюди")
        panel.message = L("Перемістити обрані оригінали. Існуючі файли в папці не перезаписуватимуться.")
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let canonical = folder.resolvingSymlinksInPath().standardizedFileURL
        guard !policy.excludes(canonical) else { errorMessage = L("Системна папка не може бути місцем призначення."); return }
        rememberAccess(folder)
        manageSelectedFiles(.move(canonical))
    }

    func trashSelectedFiles() { manageSelectedFiles(.trash) }

    func manageSelectedFiles(_ action: FileAction) {
        guard !busy, pendingCount == 0 else { return }
        let records = selectedFiles.map(\.record), policy = policy
        guard !records.isEmpty else { return }
        managingFiles = true
        operation = Task {
            let report = await ImageFileManager.perform(action, on: records, policy: policy) { [weak self] done, count in
                await self?.updateFileActionProgress(done: done, count: count)
            }
            for row in rows {
                if let failure = report.failures[row.id] {
                    row.phase = failure
                    diagnostics.record("fileAction", "File move or Trash action failed")
                }
            }
            rows.removeAll { report.succeeded.contains($0.id) }
            readyCount = rows.filter { $0.selected && $0.record.isEligible && !$0.completed && $0.candidate == nil }.count
            selectedFileCount = selectedFiles.count
            refreshVisibleRows()
            let verb: String
            switch action { case .trash: verb = L("Переміщено в Кошик"); case .move: verb = L("Переміщено в папку") }
            status = L("\(verb): \(report.succeeded.count). Не вдалося: \(report.failures.count).") + (report.cancelled ? L(" Дію зупинено.") : "")
            managingFiles = false
        }
    }

    private func updateFileActionProgress(done: Int, count: Int) { status = L("Переміщуємо файли: \(done) із \(count)…") }
    func cleanup() {
        stop(); filterTask?.cancel(); accessTasks.forEach { $0.cancel() }; persist()
        rows.forEach { $0.candidate?.discard() }
        videoPreview?.discard()
        scopedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
    }
}
