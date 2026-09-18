import AppKit
import Carbon.HIToolbox
import GarakutaCore
import SwiftUI

/// Drives the switcher: keeps the window list warm from app events, shows the panel on the right screen, handles
/// keys, refreshes thumbnails, and activates the chosen window.
@MainActor
final class SwitcherController {
    let state = SwitcherState()
    private let focus = FocusHistory()
    private let thumbnails = ThumbnailStore()
    private let events = WindowEventObserver()
    private let activator = WindowActivator()
    private let preview = PreviewPanel()

    // MARK: Window list

    /// Last completed scan. Shown immediately on trigger; kept fresh by app events while closed.
    private var lastScan: ScanResult?
    private var scanGeneration = 0
    private var scanInFlight = false
    private var scanRequested = false
    private var refreshTimer: Timer?
    private var backgroundCaptureTimer: Timer?
    private var frontmostPID: pid_t? = NSWorkspace.shared.frontmostApplication?.processIdentifier
    private var seededFocus = false

    // MARK: Session

    /// Window the user has selected, followed by id across list refreshes.
    private var selectedWindowID: CGWindowID?
    /// True once the user moved the selection themselves; until then the selection is the default pick and keeps
    /// tracking the list as it settles.
    private var userPicked = false
    /// Windows present when the shortcut was pressed. A window that arrives later is drawn where the list puts
    /// it but the default pick steps over it: the user was not choosing among windows they could not see.
    private var summonIDs: Set<CGWindowID> = []
    private var initialReverse = false
    private var panel: SwitcherPanel?
    private var hosting: NSHostingView<SwitcherView>?
    private var sessionScreen: NSScreen?
    private var thumbnailTimer: Timer?
    private var showTimer: Timer?
    private var repeatTimer: Timer?
    private var lastTriggerAt = Date.distantPast
    private var previewTimer: Timer?
    private var globalFlagsMonitor: Any?
    private var globalClickMonitor: Any?
    private var pendingTriggerFlags: NSEvent.ModifierFlags = []
    private var pendingTrigger: KeyCombo?
    private var pendingScreen: NSScreen?
    /// Where the pointer was when the panel appeared; hovering selects only once it has moved from here.
    private var pointerAtShow: CGPoint?

    var isOpen: Bool { state.isVisible || showTimer != nil }

    var onOpenStateChanged: ((Bool) -> Void)?

    init() {
        thumbnails.onImage = { [weak self] id, image in
            guard let self else { return }
            self.state.thumbnails[id] = image
        }
    }

    // MARK: Lifecycle

    func start() {
        events.onStructureChanged = { [weak self] _ in self?.requestRefresh() }
        events.onFocus = { [weak self] pid, id in
            guard let self else { return }
            if let id { self.focus.touch(id) } else { self.requestRefresh() }
            if !self.isOpen { self.scheduleBackgroundCapture(id) }
        }
        events.onAppActivated = { [weak self] app in
            guard let self else { return }
            self.frontmostPID = app.processIdentifier
            self.requestRefresh()
        }
        events.start()
        refreshWindows()
    }

    func stop() {
        hide()
        events.stop()
        refreshTimer?.invalidate(); refreshTimer = nil
        backgroundCaptureTimer?.invalidate(); backgroundCaptureTimer = nil
    }

    /// Accessibility may be granted while running; observers for already-running apps are added then.
    func accessibilityMayHaveChanged() {
        events.attachMissing()
        requestRefresh()
    }

    // MARK: Trigger

    /// Called on every trigger press. Opens (after the hold delay) or cycles when already open.
    func trigger(_ combo: KeyCombo, reverse: Bool, appWindowsOnly: Bool) {
        lastTriggerAt = Date()
        if isOpen {
            state.moveSelection(by: reverse ? -1 : 1)
            userPicked = true
            didChangeSelection()
            return
        }
        let settings = state.settings
        let screen = targetScreen(settings)
        sessionScreen = screen
        state.query = ""
        state.frontmostOnly = appWindowsOnly ? frontmostPID : nil
        // Show the warm list right away; a fresh scan replaces it when it lands.
        state.windows = lastScan?.windows ?? []
        summonIDs = Set(state.windows.map(\.windowID))
        userPicked = false
        initialReverse = reverse
        applyDefaultSelection()
        pendingTrigger = combo
        pendingTriggerFlags = combo.nsModifiers.subtracting(.shift)
        refreshWindows(screenFrame: cgFrame(of: screen))

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
        startKeyRepeat(combo)
    }

    /// The default pick: the second window when the first is the one the user is on, otherwise the first; from
    /// the end when cycling backwards. Windows that were not there at the press do not count.
    private func applyDefaultSelection() {
        let list = state.filtered
        guard !list.isEmpty else { state.selectedIndex = 0; selectedWindowID = nil; return }
        var present = list.indices.filter { summonIDs.contains(list[$0].windowID) }
        if present.isEmpty { present = Array(list.indices) }
        let firstIsCurrent: Bool = {
            let first = list[present[0]]
            return first.pid == frontmostPID && first.isOnCurrentSpace && !first.isMinimized && !first.isAppHidden
        }()
        let index: Int
        if initialReverse {
            index = present.count > 1 ? present[present.count - 1] : present[0]
        } else if firstIsCurrent, present.count > 1 {
            index = present[1]
        } else {
            index = present[0]
        }
        state.selectedIndex = index
        selectedWindowID = state.selected?.windowID
    }

    func hide() {
        beginHide()
        endHide()
    }

    /// The visible part of dismissing: the panel goes, the monitors stop. Cheap, so the window the user picked
    /// can be asked to come forward right after.
    private func beginHide() {
        showTimer?.invalidate(); showTimer = nil
        thumbnailTimer?.invalidate(); thumbnailTimer = nil
        repeatTimer?.invalidate(); repeatTimer = nil
        previewTimer?.invalidate(); previewTimer = nil
        removeGlobalMonitors()
        let wasVisible = state.isVisible
        state.isVisible = false
        panel?.orderOut(nil)
        preview.reset()
        if wasVisible { onOpenStateChanged?(false) }
    }

    /// Bookkeeping nobody is waiting for, one run loop turn later.
    private func endHide() {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isOpen else { return }
            self.state.frontmostOnly = nil
            self.state.query = ""
            self.state.dropTarget = nil
            self.thumbnails.prune(keeping: Set(self.lastScan?.windows.map(\.windowID) ?? []))
        }
    }

    func activateSelection() {
        let selected = state.selected
        let element = selected.flatMap { lastScan?.elements[$0.windowID] }
        beginHide()
        if let selected {
            activator.activate(selected, element: element)
            focus.touch(selected.windowID)
            followPointer(to: selected)
        }
        endHide()
    }

    private func followPointer(to window: SwitcherWindow) {
        switch state.settings.pointerFollow {
        case .never: return
        case .always: activator.movePointer(to: window)
        case .otherDisplay:
            guard let main = NSScreen.screens.first, let session = sessionScreen else { return }
            let center = CGPoint(x: window.frame.midX, y: main.frame.maxY - window.frame.midY)
            if !session.frame.contains(center) { activator.movePointer(to: window) }
        }
    }

    // MARK: Refresh

    /// Coalesces bursts of app events into one scan.
    func requestRefresh() {
        guard refreshTimer == nil else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.refreshTimer = nil
                self.refreshWindows()
            }
        }
    }

    /// Runs the enumeration off the main actor and publishes the result. Also used at start-up to warm the cache
    /// so the first hotkey press has something to show.
    func refreshWindows(screenFrame: CGRect? = nil) {
        if scanInFlight { scanRequested = true; return }
        scanInFlight = true
        let settings = state.settings
        let frame = screenFrame ?? sessionScreen.flatMap(cgFrame(of:))
        let input = ScanInput(
            apps: AppSnapshot.current(excluding: ProcessInfo.processInfo.processIdentifier),
            settings: settings,
            screenFrame: frame,
            trusted: AXIsProcessTrusted(),
            focusStamps: focus.stamps,
            dockPID: NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier,
            frontmostPID: isOpen ? state.frontmostOnly : nil
        )
        scanGeneration += 1
        let generation = scanGeneration
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = await WindowEnumerator.scan(input)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.scanInFlight = false
                guard generation == self.scanGeneration else { return }
                self.lastScan = result
                if !self.seededFocus {
                    self.seededFocus = true
                    self.focus.seed(frontToBack: result.stackingOrder)
                }
                if self.isOpen { self.publish(result) }
                if self.scanRequested {
                    self.scanRequested = false
                    self.requestRefresh()
                }
            }
        }
    }

    private func publish(_ result: ScanResult) {
        state.windows = result.windows
        let list = state.filtered
        if userPicked, let id = selectedWindowID, let index = list.firstIndex(where: { $0.windowID == id }) {
            state.selectedIndex = index
        } else if userPicked, !list.isEmpty {
            state.selectedIndex = min(state.selectedIndex, list.count - 1)
        } else {
            applyDefaultSelection()
        }
        selectedWindowID = state.selected?.windowID
        relayout()
        didChangeSelection()
    }

    // MARK: Panel

    private func presentPanel(on screen: NSScreen) {
        showTimer?.invalidate(); showTimer = nil
        let panel = self.panel ?? makePanel()
        self.panel = panel
        // Decided before the first layout so the tiles do not change size once the panel is on screen.
        state.thumbnailsEnabled = Permission.screenRecording.isGranted && state.settings.style == .thumbnails
        state.thumbnails = thumbnails.images
        state.metrics = metrics(for: screen)
        if state.thumbnailsEnabled { startThumbnailRefresh() }
        pointerAtShow = NSEvent.mouseLocation
        layout(panel, on: screen)
        state.isVisible = true
        panel.makeKeyAndOrderFront(nil)
        onOpenStateChanged?(true)
        didChangeSelection()
    }

    private func metrics(for screen: NSScreen) -> SwitcherMetrics {
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        let physical = displayID.map { CGDisplayScreenSize(CGDirectDisplayID($0)).width }
        return SwitcherMetrics.resolve(style: state.settings.style, preset: state.settings.sizePreset, screen: screen.visibleFrame,
                                       physicalWidthMM: physical.map { CGFloat($0) }, showsSubtitle: !state.settings.minimalDecorations,
                                       windows: state.filtered)
    }

    private func makePanel() -> SwitcherPanel {
        let panel = SwitcherPanel()
        let view = SwitcherView(
            state: state,
            onActivate: { [weak self] w in self?.state.select(id: w.windowID); self?.activateSelection() },
            onHover: { [weak self] w in self?.hovered(w) },
            onDrop: { [weak self] w, urls in self?.dropped(urls, on: w) }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = [.intrinsicContentSize]
        panel.contentView = hosting
        self.hosting = hosting
        panel.onKeyDown = { [weak self] event in self?.handleKey(event) ?? false }
        panel.onKeyUp = { [weak self] event in self?.handleKeyUp(event) }
        panel.onFlagsChanged = { [weak self] event in self?.handleFlags(event.modifierFlags) }
        panel.onMiddleClick = { [weak self] in
            guard let self, self.state.settings.closeOnMiddleClick else { return }
            self.closeSelected()
        }
        panel.onScroll = { [weak self] delta in
            guard let self, self.state.settings.style != .thumbnails || abs(delta) >= 1 else { return }
            self.state.moveSelection(by: delta > 0 ? 1 : -1)
            self.userPicked = true
            self.didChangeSelection()
        }
        return panel
    }

    private func layout(_ panel: SwitcherPanel, on screen: NSScreen) {
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

    private func relayout() {
        guard let panel, state.isVisible, let screen = sessionScreen ?? panel.screen ?? NSScreen.main else { return }
        layout(panel, on: screen)
    }

    // MARK: Selection

    private func didChangeSelection() {
        selectedWindowID = state.selected?.windowID
        updatePreview()
    }

    private func hovered(_ window: SwitcherWindow) {
        guard state.settings.hoverSelects, state.isVisible else { return }
        // A pointer that happens to rest over the grid when the panel appears must not steal the selection.
        if let start = pointerAtShow {
            let p = NSEvent.mouseLocation
            guard hypot(p.x - start.x, p.y - start.y) >= 8 else { return }
            pointerAtShow = nil
        }
        state.select(id: window.windowID)
        userPicked = true
        didChangeSelection()
    }

    private func dropped(_ urls: [URL], on window: SwitcherWindow) {
        guard !urls.isEmpty, let app = NSRunningApplication(processIdentifier: window.pid), let bundleURL = app.bundleURL else { return }
        beginHide()
        NSWorkspace.shared.open(urls, withApplicationAt: bundleURL, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
        endHide()
    }

    private func updatePreview() {
        previewTimer?.invalidate(); previewTimer = nil
        guard state.settings.previewSelectedWindow, state.isVisible, let panel else { preview.hide(); return }
        guard let selected = state.selected else { preview.hide(); return }
        previewTimer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.state.isVisible, self.state.selected?.windowID == selected.windowID else { return }
                self.preview.show(selected, below: panel.level)
            }
        }
    }

    // MARK: Input

    /// Returns true when the event was consumed.
    private func handleKey(_ event: NSEvent) -> Bool {
        let command = event.modifierFlags.contains(.command)
        switch Int(event.keyCode) {
        case kVK_Escape:
            hide(); return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            activateSelection(); return true
        case kVK_Tab:
            state.moveSelection(by: event.modifierFlags.contains(.shift) ? -1 : 1)
            userPicked = true; didChangeSelection()
            return true
        case kVK_RightArrow:
            state.moveSelection(by: 1); userPicked = true; didChangeSelection(); return true
        case kVK_LeftArrow:
            state.moveSelection(by: -1); userPicked = true; didChangeSelection(); return true
        case kVK_DownArrow:
            if state.settings.style == .titles { state.moveSelection(by: 1) } else { state.moveSelection(rows: 1) }
            userPicked = true; didChangeSelection(); return true
        case kVK_UpArrow:
            if state.settings.style == .titles { state.moveSelection(by: -1) } else { state.moveSelection(rows: -1) }
            userPicked = true; didChangeSelection(); return true
        case kVK_Delete:
            if !state.query.isEmpty { state.query.removeLast(); state.selectedIndex = 0; didChangeSelection(); relayout() }
            return true
        case kVK_ANSI_W where command:
            closeSelected(); return true
        case kVK_ANSI_M where command:
            actOnSelected { activator.toggleMinimized($0, element: $1) }; return true
        case kVK_ANSI_F where command:
            actOnSelected { activator.toggleFullScreen($0, element: $1) }; return true
        case kVK_ANSI_H where command:
            actOnSelected { window, _ in activator.toggleAppHidden(window) }; return true
        case kVK_ANSI_Q where command:
            actOnSelected { window, _ in activator.quitApp(window) }; return true
        default:
            break
        }
        if let chars = event.charactersIgnoringModifiers, !chars.isEmpty,
           chars.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
           !command, !event.modifierFlags.contains(.control) {
            state.query += chars
            state.selectedIndex = 0
            userPicked = true
            didChangeSelection()
            relayout()
            return true
        }
        return false
    }

    private func handleKeyUp(_ event: NSEvent) {
        if let pendingTrigger, UInt32(event.keyCode) == pendingTrigger.keyCode {
            repeatTimer?.invalidate(); repeatTimer = nil
        }
    }

    /// Acting on a tile is a commitment to that window: the selection follows it by id from here, even as the
    /// list reorders under the open switcher (minimizing or hiding moves it to the end).
    private func actOnSelected(_ action: (SwitcherWindow, AXUIElement?) -> Bool) {
        guard let selected = state.selected else { return }
        userPicked = true
        selectedWindowID = selected.windowID
        if !action(selected, lastScan?.elements[selected.windowID]) { NSSound.beep() }
        requestRefresh()
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
        userPicked = true
        if activator.close(selected, element: lastScan?.elements[selected.windowID]) {
            state.windows.removeAll { $0.windowID == selected.windowID }
            state.thumbnails[selected.windowID] = nil
            if state.selectedIndex >= state.filtered.count { state.selectedIndex = max(0, state.filtered.count - 1) }
            didChangeSelection()
            relayout()
            requestRefresh()
        }
    }

    // MARK: Key repeat

    /// Holding the trigger key cycles at the system's key repeat rate. The hotkey may or may not deliver repeats
    /// itself, so a tick is skipped when a press arrived within the last interval.
    private func startKeyRepeat(_ combo: KeyCombo) {
        repeatTimer?.invalidate()
        let delay = max(0.15, NSEvent.keyRepeatDelay)
        let interval = max(0.03, NSEvent.keyRepeatInterval)
        let keyCode = CGKeyCode(combo.keyCode)
        repeatTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isOpen else { return }
                self.repeatTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                    Task { @MainActor in self?.repeatTick(keyCode: keyCode, interval: interval) }
                }
            }
        }
    }

    private func repeatTick(keyCode: CGKeyCode, interval: TimeInterval) {
        guard isOpen, CGEventSource.keyState(.combinedSessionState, key: keyCode) else {
            repeatTimer?.invalidate(); repeatTimer = nil
            return
        }
        let flags = NSEvent.modifierFlags
        guard flags.isSuperset(of: pendingTriggerFlags) else { return }
        guard Date().timeIntervalSince(lastTriggerAt) > interval * 0.8 else { return }
        lastTriggerAt = Date()
        state.moveSelection(by: flags.contains(.shift) ? -1 : 1)
        userPicked = true
        didChangeSelection()
    }

    // MARK: Monitors

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

    /// Captures a bounded number of windows at a time. Tiles without a picture come first, then the stalest, so a
    /// long list fills in evenly instead of the top rows hogging every refresh.
    private func refreshThumbnails() {
        guard state.isVisible, state.thumbnailsEnabled else { return }
        let scale = sessionScreen?.backingScaleFactor ?? 2
        let candidates = state.filtered.prefix(60)
            .filter { !$0.isAppPlaceholder && thumbnails.shouldCapture($0.windowID) }
            .sorted { thumbnails.age(of: $0.windowID) > thumbnails.age(of: $1.windowID) }
        for window in candidates {
            guard thumbnails.hasCapacity else { break }
            // A picture is only worth refreshing when it is older than the refresh period.
            guard thumbnails.age(of: window.windowID) > 0.2 else { continue }
            thumbnails.capture(window, maxWidth: state.metrics.tileWidth(for: window) * scale)
        }
    }

    /// A window that just took focus gets a fresh picture a moment later, so the next summon shows it current.
    private func scheduleBackgroundCapture(_ id: CGWindowID?) {
        guard state.settings.refreshThumbnailsInBackground, state.settings.style == .thumbnails, Permission.screenRecording.isGranted,
              let id else { return }
        backgroundCaptureTimer?.invalidate()
        backgroundCaptureTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isOpen, let window = self.lastScan?.windows.first(where: { $0.windowID == id }) else { return }
                let scale = NSScreen.main?.backingScaleFactor ?? 2
                self.thumbnails.capture(window, maxWidth: self.state.metrics.tileWidth(for: window) * scale)
            }
        }
    }
}
