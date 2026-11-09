import ImageCore
import AppKit

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    private var incomingFiles: [URL] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = self
        if let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") as? String,
           let url = Bundle.main.resourceURL?.appendingPathComponent(name),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model?.revealMainWindow?()
        sender.activate()
        return true
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        if let model { model.revealMainWindow?(); model.importFiles(urls) }
        else { incomingFiles.append(contentsOf: urls) }
        application.activate()
    }
    func receivePendingFiles() {
        guard !incomingFiles.isEmpty, let model else { return }
        let urls = incomingFiles; incomingFiles.removeAll(); model.importFiles(urls)
    }
    @objc func optimizeImages(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { error.pointee = L("Обери файли зображень у Finder.") as NSString; return }
        self.application(NSApp, open: urls)
    }
    private var terminationTask: Task<Void, Never>?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if let model, model.busy || model.pendingCount > 0 {
            let alert = NSAlert()
            alert.messageText = L("Завершити роботу?")
            alert.informativeText = L("Обробка зупиниться. Тимчасові результати, які очікують твого рішення, буде відкинуто. Уже збережені файли залишаться.")
            alert.addButton(withTitle: L("Залишитися"))
            alert.addButton(withTitle: L("Завершити"))
            if alert.runModal() != .alertSecondButtonReturn { return .terminateCancel }
        }
        if let model {
            if model.busy { model.stop() }
            // Finish an in-flight save/move before the process can exit and interrupt a copy.
            terminationTask = Task {
                await model.operation?.value
                model.cleanup()
                await model.statistics.flush()
                model.diagnostics.record("lifecycle", "Application exited normally")
                model.diagnostics.stopMonitoring()
                await model.diagnostics.flush()
                sender.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        }
        model?.cleanup()
        return .terminateNow
    }
}
