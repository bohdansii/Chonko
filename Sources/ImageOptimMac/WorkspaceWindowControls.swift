import AppKit
import SwiftUI

/// Uses native AppKit window buttons inside the panel's reserved header.
struct WorkspaceWindowControls: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 72, height: 16))
        let controls: [(NSWindow.ButtonType, Selector)] = [
            (.closeButton, #selector(NSWindow.performClose(_:))),
            (.miniaturizeButton, #selector(NSWindow.performMiniaturize(_:))),
            (.zoomButton, #selector(NSWindow.performZoom(_:)))
        ]
        for (index, control) in controls.enumerated() {
            guard let button = NSWindow.standardWindowButton(control.0, for: [.titled, .closable, .miniaturizable, .resizable]) else { continue }
            button.frame.origin = NSPoint(x: CGFloat(index) * 24, y: 1)
            button.action = control.1
            host.addSubview(button)
        }
        return host
    }

    func updateNSView(_ view: NSView, context: Context) {
        Task { @MainActor [weak view] in
            guard let view, let window = view.window else { return }
            for button in view.subviews.compactMap({ $0 as? NSButton }) {
                button.target = window
            }
        }
    }
}
