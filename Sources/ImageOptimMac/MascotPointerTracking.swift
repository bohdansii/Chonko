import AppKit
import SwiftUI

/// Receives this window's mouse moves even over AppKit-backed lists and controls.
struct MascotPointerTracking: NSViewRepresentable {
    let pointer: MascotPointer
    let enabled: Bool

    func makeNSView(context: Context) -> TrackingView { TrackingView(pointer: pointer) }
    func updateNSView(_ view: TrackingView, context: Context) {
        view.enabled = enabled
        if !enabled { pointer.location = nil }
    }
    static func dismantleNSView(_ view: TrackingView, coordinator: ()) { view.detach() }

    final class TrackingView: NSView {
        let pointer: MascotPointer
        var enabled = true
        private var monitor: Any?
        private weak var trackedWindow: NSWindow?
        private var previouslyAcceptedMoves = false
        private var area: NSTrackingArea?
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        init(pointer: MascotPointer) { self.pointer = pointer; super.init(frame: .zero) }
        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            detach()
            guard let window else { return }
            trackedWindow = window
            previouslyAcceptedMoves = window.acceptsMouseMovedEvents
            window.acceptsMouseMovedEvents = true
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
                MainActor.assumeIsolated {
                    self?.receive(event)
                }
                return event
            }
        }

        override func updateTrackingAreas() {
            if let area { removeTrackingArea(area) }
            let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
            addTrackingArea(area); self.area = area
            super.updateTrackingAreas()
        }
        override func mouseEntered(with event: NSEvent) { receive(event) }
        override func mouseExited(with event: NSEvent) { pointer.location = nil }

        private func receive(_ event: NSEvent) {
            guard enabled, NSApp.isActive, event.window === window else { pointer.location = nil; return }
            let point = convert(event.locationInWindow, from: nil)
            pointer.location = bounds.contains(point) ? point : nil
        }
        func detach() {
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            trackedWindow?.acceptsMouseMovedEvents = previouslyAcceptedMoves
            trackedWindow = nil
            pointer.location = nil
        }
    }
}
