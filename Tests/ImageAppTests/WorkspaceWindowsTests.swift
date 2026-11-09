import AppKit
import Testing
@testable import ImageOptimMac

@MainActor struct WorkspaceWindowsTests {
    @Test func entireWorkspaceFitsLaptopScreen() {
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 850)
        let requested = NSRect(x: 500, y: -20, width: 1200, height: 1000)
        let fitted = WorkspaceWindows.fittedFrame(requested, in: screen, left: 272, right: 332)
        #expect(fitted.minX - 272 >= screen.minX)
        #expect(fitted.maxX + 332 <= screen.maxX)
        #expect(fitted.minY >= screen.minY && fitted.maxY <= screen.maxY)
    }


    @Test func sharedWindowHasNoIndependentPanelShadows() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let workspace = WorkspaceWindows()
        workspace.register(window, role: .main)
        #expect(window.childWindows?.isEmpty ?? true)
        #expect(!window.hasShadow)
        #expect(!window.isOpaque)
        #expect(window.backgroundColor == .clear)
    }
}
