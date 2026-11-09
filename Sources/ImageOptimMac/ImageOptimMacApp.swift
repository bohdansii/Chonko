import ImageCore
import SwiftUI

@main struct ImageOptimMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel(statistics: StatisticsStore(fileURL: StatisticsStore.defaultURL), diagnostics: .shared)
    @State private var workspace = WorkspaceWindows()
    @State private var mascotPointer = MascotPointer()
    var body: some Scene {
        Window("Chonko", id: "main") {
            HStack(spacing: 12) {
                if model.showSourcesPanel {
                    SourcesSidebarView(model: model).frame(width: 260)
                        .modifier(WorkspacePanelSurface())
                }
                ContentView(model: model)
                    .modifier(WorkspacePanelSurface())
                Group {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(L("Оптимізація")).font(.title2.bold()).padding(20)
                        OptimizationSettingsView(model: model)
                    }
                    .padding(.top, 24)
                    .modifier(WorkspaceGlass()).padding(8).frame(width: 320)
                    .modifier(WorkspacePanelSurface())
                }
            }
            .overlay(alignment: .topLeading) {
                WorkspaceWindowControls()
                    .frame(width: 72, height: 16)
                    .padding(.leading, 24).padding(.top, 28)
            }
            .coordinateSpace(name: "mascotWorkspace")
            .background(MascotPointerTracking(pointer: mascotPointer, enabled: !model.busy))
            .onChange(of: workspace.appearsActive) { _, active in
                if !active { mascotPointer.location = nil }
            }
            .onChange(of: model.busy) { _, busy in
                if busy { mascotPointer.location = nil }
            }
            .environment(\.mascotPointer, mascotPointer)
            .ignoresSafeArea(.container, edges: .top)
                .environment(\.appearsActive, workspace.appearsActive)
                .environment(\.controlActiveState, workspace.appearsActive ? .key : .inactive)
                .background(WorkspaceWindowAttachment(workspace: workspace, role: .main))
                .id(model.language)
                .environment(\.locale, Locale(identifier: model.language))
                .onAppear { delegate.model = model; model.start(); model.diagnostics.startMonitoring(); delegate.receivePendingFiles() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1360, height: 760)
        .defaultWindowPlacement { _, context in
            let rect = context.defaultDisplay.visibleRect
            return WindowPlacement(x: rect.minX + 12, y: rect.minY + 28, width: min(1500, rect.width - 24), height: min(820, rect.height - 56))
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button(L("Діагностика…"), systemImage: "stethoscope") { model.showDiagnostics = true }
            }
            CommandGroup(after: .newItem) {
                Button(model.fileKind == .images ? L("Обрати зображення…") : L("Обрати файли…"), systemImage: "photo.badge.plus", action: model.chooseImages)
                    .keyboardShortcut("i").disabled(model.busy)
                Button(L("Обрати папку для пошуку…"), systemImage: "folder") { model.chooseSearchFolder() }
                    .keyboardShortcut("o").disabled(model.busy)
                Button(L("Додати ще папки…"), systemImage: "folder.badge.plus") { model.addFolders() }
                    .keyboardShortcut("o", modifiers: [.command, .shift]).disabled(model.busy)
                Button(L("Сканувати знову"), systemImage: "arrow.clockwise") { model.requestScan() }
                    .keyboardShortcut("r").disabled(model.busy || model.roots.isEmpty)
            }
            CommandGroup(replacing: .help) {
                Link(L("Документація WebP"), destination: URL(string: "https://developers.google.com/speed/webp/docs/cwebp")!)
                Link(L("Про AVIF"), destination: URL(string: "https://aomedia.org/specifications/avif/")!)
            }
        }
        Settings {
            AppSettingsView(model: model)
                .id(model.language)
                .environment(\.locale, Locale(identifier: model.language))
        }

    }
}
