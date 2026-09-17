import AppKit
import GarakutaCore

/// M02: reveals the hidden section on hover, scroll/swipe, or hotkey and re-hides it once the pointer has left the
/// menu bar for a while. Clicking the collapsed separator's empty tail is handled by the module's button action.
@MainActor
final class RevealController {
    var settings: MenuBarSettings { didSet { applySettings() } }

    /// Called to expand the hidden section (true) or collapse it (false).
    var setRevealed: ((Bool) -> Void)?
    var isRevealed: (() -> Bool)?
    /// Frames (AppKit) that count as "still using the menu bar" for auto-rehide, such as the hidden items bar.
    var extraKeepAliveFrames: (() -> [CGRect])?

    private var monitors: [Any] = []
    private var hoverTimer: Timer?
    private var rehideTimer: Timer?
    private var hotKeyToken: UInt32?
    private var pointerWasInMenuBar = false
    /// Set when the user clicks something in the menu bar while revealed; a menu is probably open, so rehide waits
    /// for the next click anywhere (which closes the menu).
    private var menuLikelyOpen = false
    private var lastScrollReveal = Date.distantPast

    init(settings: MenuBarSettings) {
        self.settings = settings
    }

    func start() {
        stop()
        let moved = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { event in
            let location = NSEvent.mouseLocation
            MainActor.assumeIsolated { RevealController.current?.pointerMoved(to: location) }
        }
        let clicked = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            let location = NSEvent.mouseLocation
            MainActor.assumeIsolated { RevealController.current?.pointerClicked(at: location) }
        }
        let scrolled = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { event in
            let dx = event.scrollingDeltaX
            let dy = event.scrollingDeltaY
            let location = NSEvent.mouseLocation
            MainActor.assumeIsolated { RevealController.current?.scrolled(dx: dx, dy: dy, at: location) }
        }
        monitors = [moved, clicked, scrolled].compactMap { $0 }
        RevealController.current = self
        applySettings()
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        hoverTimer?.invalidate()
        rehideTimer?.invalidate()
        if let hotKeyToken { HotKeyCenter.shared.unregister(hotKeyToken) }
        hotKeyToken = nil
        if RevealController.current === self { RevealController.current = nil }
    }

    /// Call after a programmatic reveal so auto-rehide is armed.
    func didReveal() {
        menuLikelyOpen = false
        scheduleRehideIfNeeded()
    }

    func cancelRehide() {
        rehideTimer?.invalidate()
        rehideTimer = nil
    }

    // MARK: Events

    private func pointerMoved(to location: CGPoint) {
        let inMenuBar = MenuBarGeometry.isPointerInMenuBar(location) != nil
        if inMenuBar != pointerWasInMenuBar {
            pointerWasInMenuBar = inMenuBar
            if inMenuBar {
                cancelRehide()
                if settings.revealOnHover, isRevealed?() == false {
                    hoverTimer?.invalidate()
                    hoverTimer = Timer.scheduledTimer(withTimeInterval: settings.hoverDelay, repeats: false) { _ in
                        Task { @MainActor in
                            guard let self = RevealController.current, MenuBarGeometry.isPointerInMenuBar() != nil else { return }
                            self.setRevealed?(true)
                            self.didReveal()
                        }
                    }
                }
            } else {
                hoverTimer?.invalidate()
                scheduleRehideIfNeeded()
            }
        } else if inMenuBar {
            cancelRehide()
        }
        if !inMenuBar, let frames = extraKeepAliveFrames?(), frames.contains(where: { $0.contains(location) }) {
            cancelRehide()
        }
    }

    private func pointerClicked(at location: CGPoint) {
        guard isRevealed?() == true else { return }
        if MenuBarGeometry.isPointerInMenuBar(location) != nil {
            // Probably opened a status item menu; hold off until the next click closes it.
            menuLikelyOpen = true
            cancelRehide()
        } else if menuLikelyOpen {
            menuLikelyOpen = false
            scheduleRehideIfNeeded()
        }
    }

    private func scrolled(dx: CGFloat, dy: CGFloat, at location: CGPoint) {
        guard settings.revealOnScroll, MenuBarGeometry.isPointerInMenuBar(location) != nil else { return }
        let threshold: CGFloat = 6
        let now = Date()
        guard now.timeIntervalSince(lastScrollReveal) > 0.4 else { return }
        if dy < -threshold || dx < -threshold {
            lastScrollReveal = now
            setRevealed?(true)
            didReveal()
        } else if dy > threshold || dx > threshold {
            lastScrollReveal = now
            setRevealed?(false)
        }
    }

    private func scheduleRehideIfNeeded() {
        guard settings.autoRehide, isRevealed?() == true, !menuLikelyOpen else { return }
        rehideTimer?.invalidate()
        rehideTimer = Timer.scheduledTimer(withTimeInterval: settings.autoRehideDelay, repeats: false) { _ in
            Task { @MainActor in
                guard let self = RevealController.current else { return }
                guard MenuBarGeometry.isPointerInMenuBar() == nil, !self.menuLikelyOpen else {
                    self.scheduleRehideIfNeeded()
                    return
                }
                if let frames = self.extraKeepAliveFrames?(), frames.contains(where: { $0.contains(NSEvent.mouseLocation) }) {
                    self.scheduleRehideIfNeeded()
                    return
                }
                self.setRevealed?(false)
            }
        }
    }

    private func applySettings() {
        if let hotKeyToken { HotKeyCenter.shared.unregister(hotKeyToken) }
        hotKeyToken = nil
        if let combo = settings.revealHotKey {
            hotKeyToken = HotKeyCenter.shared.register(combo) {
                guard let self = RevealController.current else { return }
                let revealed = self.isRevealed?() ?? false
                self.setRevealed?(!revealed)
                if !revealed { self.didReveal() }
            }
        }
    }

    /// Global monitor closures are not actor-isolated; they reach the controller through this main-actor slot.
    private static var current: RevealController?
}
