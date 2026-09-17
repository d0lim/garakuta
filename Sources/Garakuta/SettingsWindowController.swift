import AppKit
import SwiftUI

/// Our own settings window. The SwiftUI `Settings` scene cannot be opened reliably from an accessory app
/// without a main menu, so the window is hosted directly.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show(model: AppModel) {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsRootView(model: model))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Garakuta Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 720, height: 540))
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Back to a menu-bar-only app once the last regular window is gone.
        DispatchQueue.main.async {
            if NSApp.windows.filter({ $0.isVisible && $0.styleMask.contains(.titled) }).isEmpty {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}
