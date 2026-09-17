import AppKit
import Carbon.HIToolbox
import GarakutaCore
import SwiftUI

/// Drives one switcher session: builds the list, shows the panel on the right screen, handles keys, refreshes
/// thumbnails, and activates the chosen window.
@MainActor
final class SwitcherController {
    let state = SwitcherState()
    private let activator = WindowActivator()
    /// Last completed scan. Shown immediately on trigger while a fresh scan runs in the background.
    private var lastScan: ScanResult?
    private var scanGeneration = 0
    /// Window the user (or the initial "next window" rule) has selected, tracked across list refreshes.
    private var selectedWindowID: CGWindowID?
    private var initialOffset = 1
    private var panel: SwitcherPanel?
    private var hosting: NSHostingView<SwitcherView>?
    private var thumbnailTimer: Timer?
    private var showTimer: Timer?
    private var globalFlagsMonitor: Any?
    private var globalClickMonitor: Any?
    private var pendingTriggerFlags: NSEvent.ModifierFlags = []
    private var pendingScreen: NSScreen?
    private var captureInFlight: Set<CGWindowID> = []
    /// Windows whose last capture came back empty (typically on another Space); retried only occasionally.
    private var captureFailedAt: [CGWindowID: Date] = [:]
    private var thumbnailCapturedAt: [CGWindowID: Date] = [:]
    private static let maxCapturesInFlight = 8
    private static let failedCaptureRetry: TimeInterval = 3

    var isOpen: Bool { state.isVisible || showTimer != nil }

    // MARK: Session

    /// Called on every trigger press. Opens (after the hold delay) or cycles when already open.
    func trigger(reverse: Bool) {
        if isOpen {
            state.moveSelection(by: reverse ? -1 : 1)
            selectedWindowID = state.selected?.windowID
            return
        }
        let settings = state.settings
        let screen = targetScreen(settings)
        // Show the cached list right away; the fresh scan replaces it when it lands.
        state.windows = lastScan?.windows ?? []
        state.query = ""
        initialOffset = reverse ? -1 : 1
        state.selectedIndex = state.windows.count > 1 ? (reverse ? state.windows.count - 1 : 1) : 0
        selectedWindowID = state.selected?.windowID
        pendingTriggerFlags = settings.trigger.nsModifiers.subtracting(.shift)
        refreshWindows(settings: settings, screenFrame: cgFrame(of: screen))

        let canTrackRelease = settings.activateOnModifierRelease && !pendingTriggerFlags.isEmpty
        if canTrackRelease {
            installGlobalMonitors()
        }
        let delay = (canTrackRelease && Permission.accessibility.isGranted) ? settings.holdToShowDelay : 0
        if delay > 0 {
            pendingScreen = screen
            showTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let screen = self.pendingScreen else { return }
                    self.presentPanel(on: screen)
                }
            }
        } else {
            presentPanel(on: screen)
        }
    }

    func hide() {
        showTimer?.invalidate(); showTimer = nil
        thumbnailTimer?.invalidate(); thumbnailTimer = nil
        removeGlobalMonitors()
        state.isVisible = false
        panel?.orderOut(nil)
        state.thumbnails.removeAll()
        captureInFlight.removeAll()
        captureFailedAt.removeAll()
        thumbnailCapturedAt.removeAll()
    }

    func activateSelection() {
        let selected = state.selected
        hide()
        guard let selected else { return }
        activator.activate(selected, element: lastScan?.elements[selected.windowID])
    }

    /// Runs the enumeration off the main actor and publishes the result if this session is still open.
    /// Also used at start-up to warm the cache so the first hotkey press has something to show.
    func refreshWindows(settings: SwitcherSettings? = nil, screenFrame: CGRect? = nil) {
        let settings = settings ?? state.settings
        let apps = AppSnapshot.current(excluding: ProcessInfo.processInfo.processIdentifier)
        let trusted = AXIsProcessTrusted()
        scanGeneration += 1
        let generation = scanGeneration
        let wasOpen = isOpen
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = WindowEnumerator.scan(apps: apps, settings: settings, screenFrame: screenFrame, trusted: trusted)
            await MainActor.run { [weak self] in
                guard let self, generation == self.scanGeneration else { return }
                self.lastScan = result
                if wasOpen && self.isOpen { self.publish(result) }
            }
        }
    }

    private func publish(_ result: ScanResult) {
        state.windows = result.windows
        let list = state.filtered
        if let id = selectedWindowID, let index = list.firstIndex(where: { $0.windowID == id }) {
            state.selectedIndex = index
        } else if list.count > 1 {
            state.selectedIndex = initialOffset > 0 ? 1 : list.count - 1
        } else {
            state.selectedIndex = 0
        }
        selectedWindowID = state.selected?.windowID
        state.thumbnails = state.thumbnails.filter { key, _ in result.windows.contains { $0.windowID == key } }
        relayout()
    }

    // MARK: Panel

    private func presentPanel(on screen: NSScreen) {
        showTimer?.invalidate(); showTimer = nil
        let panel = self.panel ?? makePanel()
        self.panel = panel
        // Decided before the first layout so the tile width does not change once the panel is on screen.
        state.thumbnailsEnabled = Permission.screenRecording.isGranted && !state.settings.simpleMode
        if state.thumbnailsEnabled { startThumbnailRefresh() }
        layout(panel, on: screen)
        state.isVisible = true
        panel.makeKeyAndOrderFront(nil)
    }

    private func makePanel() -> SwitcherPanel {
        let panel = SwitcherPanel()
        let view = SwitcherView(state: state,
                                onActivate: { [weak self] w in self?.state.select(id: w.windowID); self?.activateSelection() },
                                onHover: { [weak self] w in self?.state.select(id: w.windowID); self?.selectedWindowID = w.windowID })
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = [.intrinsicContentSize]
        panel.contentView = hosting
        self.hosting = hosting
        panel.onKeyDown = { [weak self] event in self?.handleKey(event) ?? false }
        panel.onFlagsChanged = { [weak self] event in self?.handleFlags(event.modifierFlags) }
        panel.onMiddleClick = { [weak self] in
            guard let self, self.state.settings.closeOnMiddleClick else { return }
            self.closeSelected()
        }
        return panel
    }

    private func layout(_ panel: SwitcherPanel, on screen: NSScreen) {
        state.maxGridWidth = screen.visibleFrame.width * 0.8
        hosting?.layoutSubtreeIfNeeded()
        var size = hosting?.fittingSize ?? CGSize(width: 400, height: 200)
        size.width = min(max(size.width, 240), screen.visibleFrame.width - 40)
        size.height = min(max(size.height, 80), screen.visibleFrame.height - 40)
        let origin = CGPoint(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.midY - size.height / 2)
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
    }

    private func targetScreen(_ settings: SwitcherSettings) -> NSScreen {
        switch settings.targetScreen {
        case .pointer:
            let p = NSEvent.mouseLocation
            return NSScreen.screens.first { $0.frame.contains(p) } ?? NSScreen.main ?? NSScreen.screens[0]
        case .menuBar:
            return NSScreen.screens[0]
        case .activeWindow:
            if let app = NSWorkspace.shared.frontmostApplication {
                let ax = AXUIElementCreateApplication(app.processIdentifier)
                AXUIElementSetMessagingTimeout(ax, 0.25)
                if let focused: AXUIElement = AX.attribute(ax, kAXFocusedWindowAttribute),
                   let p = AX.point(focused, kAXPositionAttribute), let main = NSScreen.screens.first {
                    let appKitPoint = CGPoint(x: p.x, y: main.frame.maxY - p.y - 1)
                    if let s = NSScreen.screens.first(where: { $0.frame.contains(appKitPoint) }) { return s }
                }
            }
            return NSScreen.main ?? NSScreen.screens[0]
        }
    }

    private func cgFrame(of screen: NSScreen) -> CGRect? {
        guard let main = NSScreen.screens.first else { return nil }
        let f = screen.frame
        return CGRect(x: f.minX, y: main.frame.maxY - f.maxY, width: f.width, height: f.height)
    }

    // MARK: Input

    /// Returns true when the event was consumed.
    private func handleKey(_ event: NSEvent) -> Bool {
        switch Int(event.keyCode) {
        case kVK_Escape:
            hide(); return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            activateSelection(); return true
        case kVK_Tab:
            state.moveSelection(by: event.modifierFlags.contains(.shift) ? -1 : 1)
            selectedWindowID = state.selected?.windowID
            return true
        case kVK_RightArrow, kVK_DownArrow:
            state.moveSelection(by: 1); selectedWindowID = state.selected?.windowID; return true
        case kVK_LeftArrow, kVK_UpArrow:
            state.moveSelection(by: -1); selectedWindowID = state.selected?.windowID; return true
        case kVK_Delete:
            if !state.query.isEmpty { state.query.removeLast(); state.selectedIndex = 0; selectedWindowID = state.selected?.windowID }
            return true
        case kVK_ANSI_W where event.modifierFlags.contains(.command):
            closeSelected(); return true
        default:
            break
        }
        if let chars = event.charactersIgnoringModifiers, !chars.isEmpty,
           chars.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
           !event.modifierFlags.contains(.command), !event.modifierFlags.contains(.control) {
            state.query += chars
            state.selectedIndex = 0
            selectedWindowID = state.selected?.windowID
            relayout()
            return true
        }
        return false
    }

    private func handleFlags(_ flags: NSEvent.ModifierFlags) {
        guard state.settings.activateOnModifierRelease, !pendingTriggerFlags.isEmpty else { return }
        let relevant = flags.intersection([.command, .option, .control, .shift, .function])
        if relevant.intersection(pendingTriggerFlags).isEmpty {
            if isOpen { activateSelection() }
        }
    }

    private func closeSelected() {
        guard let selected = state.selected else { return }
        if activator.close(selected, element: lastScan?.elements[selected.windowID]) {
            state.windows.removeAll { $0.windowID == selected.windowID }
            state.thumbnails[selected.windowID] = nil
            if state.selectedIndex >= state.filtered.count { state.selectedIndex = max(0, state.filtered.count - 1) }
            relayout()
        }
    }

    private func relayout() {
        guard let panel, state.isVisible, let screen = panel.screen ?? NSScreen.main else { return }
        layout(panel, on: screen)
    }

    private func installGlobalMonitors() {
        removeGlobalMonitors()
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let flags = event.modifierFlags
            Task { @MainActor in self?.handleFlags(flags) }
        }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
    }

    private func removeGlobalMonitors() {
        if let m = globalFlagsMonitor { NSEvent.removeMonitor(m) }
        if let m = globalClickMonitor { NSEvent.removeMonitor(m) }
        globalFlagsMonitor = nil
        globalClickMonitor = nil
    }

    // MARK: Thumbnails

    private func startThumbnailRefresh() {
        thumbnailTimer?.invalidate()
        refreshThumbnails()
        thumbnailTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshThumbnails() }
        }
    }

    /// Captures a bounded number of windows at a time, in list order, so the tiles the user sees first fill first.
    /// Windows that came back empty (on another Space, for instance) keep their icon and are retried slowly.
    private func refreshThumbnails() {
        guard state.isVisible, state.thumbnailsEnabled else { return }
        let maxWidth = CGFloat(state.settings.thumbnailWidth) * 2
        let now = Date()
        // Tiles without a thumbnail yet come first, then the stalest ones, so a long list fills in evenly instead
        // of the top rows hogging every refresh.
        // Windows on another Space cannot be captured (the framework hands back a blank frame); their tile keeps the icon.
        let candidates = state.filtered.prefix(40)
            .filter { !$0.isAppPlaceholder && ($0.isOnCurrentSpace || $0.isMinimized) && !captureInFlight.contains($0.windowID) }
            .sorted { (thumbnailCapturedAt[$0.windowID] ?? .distantPast) < (thumbnailCapturedAt[$1.windowID] ?? .distantPast) }
        for window in candidates {
            guard captureInFlight.count < Self.maxCapturesInFlight else { break }
            let id = window.windowID
            if let failed = captureFailedAt[id], now.timeIntervalSince(failed) < Self.failedCaptureRetry { continue }
            captureInFlight.insert(id)
            Task { [weak self] in
                let image = await WindowCapture.shared.image(ofWindow: id, maxWidth: maxWidth)
                await MainActor.run {
                    guard let self else { return }
                    self.captureInFlight.remove(id)
                    if let image {
                        self.captureFailedAt[id] = nil
                        self.thumbnailCapturedAt[id] = Date()
                        if self.state.isVisible { self.state.thumbnails[id] = image }
                    } else {
                        self.captureFailedAt[id] = Date()
                    }
                }
            }
        }
    }
}
