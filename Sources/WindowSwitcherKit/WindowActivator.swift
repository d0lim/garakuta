import AppKit
import ApplicationServices

/// Brings a chosen window to the front, un-minimizing it and switching Space when needed, and performs the other
/// window commands the switcher offers while open.
@MainActor
struct WindowActivator {
    // SpaceInfo is stateless; kept as a property for readability.
    private let spaces = SpaceInfo()

    func activate(_ window: SwitcherWindow, element: AXUIElement?) {
        guard let app = NSRunningApplication(processIdentifier: window.pid) else { return }
        if window.isAppPlaceholder && window.frame == .zero {
            app.unhide()
            app.activate()
            return
        }
        if window.isAppHidden { app.unhide() }
        if let element, window.isMinimized {
            AX.set(element, kAXMinimizedAttribute, false)
        }
        // Window-level focus first so the app's other windows stay where they are; the AX raise then makes sure
        // the window is key even when the private call is unavailable.
        let usedPrivate = spaces.bringToFront(pid: window.pid, windowID: window.windowID)
        if let element {
            AX.perform(element, kAXRaiseAction)
            AX.set(element, kAXMainAttribute, true)
            AX.set(element, kAXFocusedAttribute, true)
        }
        if !usedPrivate || element == nil {
            app.activate()
        }
    }

    /// Closes a window via its close button (middle click). Returns false if no button was found.
    func close(_ window: SwitcherWindow, element: AXUIElement?) -> Bool {
        guard let element else { return false }
        if let button: AXUIElement = AX.attribute(element, kAXCloseButtonAttribute) {
            return AX.perform(button, kAXPressAction)
        }
        return false
    }

    /// Minimizes the window, or restores it when it is minimized.
    @discardableResult
    func toggleMinimized(_ window: SwitcherWindow, element: AXUIElement?) -> Bool {
        guard let element, !window.isAppPlaceholder else { return false }
        if window.isFullScreen && !window.isMinimized {
            // Minimizing is ignored while full screen; leave full screen first and let the animation finish.
            AX.set(element, "AXFullScreen", false)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                AX.set(element, kAXMinimizedAttribute, true)
            }
            return true
        }
        return AX.set(element, kAXMinimizedAttribute, !window.isMinimized)
    }

    @discardableResult
    func toggleFullScreen(_ window: SwitcherWindow, element: AXUIElement?) -> Bool {
        guard let element, !window.isAppPlaceholder else { return false }
        return AX.set(element, "AXFullScreen", !window.isFullScreen)
    }

    /// Hides the app, or shows it again when it is hidden.
    @discardableResult
    func toggleAppHidden(_ window: SwitcherWindow) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: window.pid) else { return false }
        return app.isHidden ? app.unhide() : app.hide()
    }

    /// Asks the app to quit, as ⌘Q would.
    @discardableResult
    func quitApp(_ window: SwitcherWindow) -> Bool {
        NSRunningApplication(processIdentifier: window.pid)?.terminate() ?? false
    }

    /// Puts the pointer in the middle of the window (CG coordinates).
    func movePointer(to window: SwitcherWindow) {
        guard window.frame.width > 0, window.frame.height > 0 else { return }
        CGWarpMouseCursorPosition(CGPoint(x: window.frame.midX, y: window.frame.midY))
    }
}
