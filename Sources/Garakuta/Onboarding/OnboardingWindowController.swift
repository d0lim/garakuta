import AppKit
import SwiftUI

/// Hosts the setup assistant. Shown on first launch and on demand from Settings.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var model: OnboardingModel?

    var isShowing: Bool { window?.isVisible ?? false }

    func show(appModel: AppModel) {
        if window == nil {
            let model = OnboardingModel(appModel: appModel)
            model.onFinish = { [weak self] in self?.close() }
            let hosting = NSHostingController(rootView: OnboardingView(model: model))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Set up Garakuta"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
            self.model = model
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        model = nil
        DispatchQueue.main.async {
            if NSApp.windows.filter({ $0.isVisible && $0.styleMask.contains(.titled) }).isEmpty {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}
