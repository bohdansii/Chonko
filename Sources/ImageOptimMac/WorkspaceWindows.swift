import AppKit
import SwiftUI
import Observation

/// All three visual panels belong to one native window and share its focus.
@MainActor @Observable final class WorkspaceWindows {
    enum Role { case main }
    private(set) var appearsActive = NSApp?.isActive ?? false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init() {
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.appearsActive = NSApp.isActive }
            })
        }
    }

    func register(_ window: NSWindow, role: Role) {
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        window.hasShadow = false
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(type)?.isHidden = true
        }
        guard let screen = window.screen ?? NSScreen.main else { return }
        let bounds = screen.visibleFrame.insetBy(dx: 12, dy: 12)
        window.maxSize = bounds.size
        window.setFrame(Self.fittedFrame(window.frame, in: bounds, left: 0, right: 0), display: true)
    }

    static func fittedFrame(_ requested: NSRect, in bounds: NSRect, left: CGFloat, right: CGFloat) -> NSRect {
        let width = min(requested.width, bounds.width - left - right)
        let height = min(requested.height, bounds.height)
        let x = min(max(requested.minX, bounds.minX + left), bounds.maxX - right - width)
        let y = min(max(requested.minY, bounds.minY), bounds.maxY - height)
        return NSRect(x: x, y: y, width: width, height: height)
    }
}

struct WorkspacePanelBackdrop: NSViewRepresentable {
    @Environment(\.appearsActive) private var appearsActive
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.alphaValue = 1
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.state = appearsActive ? .active : .inactive
    }
}

struct WorkspaceWindowAttachment: NSViewRepresentable {
    let workspace: WorkspaceWindows
    let role: WorkspaceWindows.Role
    func makeNSView(context: Context) -> WindowProbe {
        let view = WindowProbe()
        view.attach = { workspace.register($0, role: role) }
        return view
    }
    func updateNSView(_ nsView: WindowProbe, context: Context) {}
}

final class WindowProbe: NSView {
    var attach: ((NSWindow) -> Void)?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        Task { @MainActor [weak self, weak window] in
            if let window { self?.attach?(window) }
        }
    }
}
