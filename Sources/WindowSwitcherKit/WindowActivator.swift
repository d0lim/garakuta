import AppKit
import ApplicationServices

/// Brings a chosen window to the front, un-minimizing it and switching Space when needed.
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
}
