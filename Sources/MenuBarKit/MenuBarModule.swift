import AppKit
import GarakutaCore
import SwiftUI

/// M01–M05: hidden / always-hidden sections, reveal triggers and auto-rehide, the hidden items bar,
/// width-based auto-arrangement, spacers and groups.
@MainActor
public final class MenuBarModule: NSObject, FeatureModule {
    public static let id = "menubar"
    public private(set) var isRunning = false

    public enum MoveFailure: Error, CustomStringConvertible {
        case itemNotFound
        case landedIn(MenuBarSection)

        public var description: String {
            switch self {
            case .itemNotFound: "The item disappeared before it could be moved."
            case .landedIn(let section): "The item ended up in the \(section.displayName) section instead."
            }
        }
    }

    // MARK: State

    public var settings: MenuBarSettings {
        didSet {
            guard settings != oldValue else { return }
            SettingsStore.shared.save(settings, for: MenuBarSettings.storeKey)
            applySettings(previous: oldValue)
        }
    }

    private var appIcon: ControlItem?
    private var hiddenSeparator: ControlItem?
    private var alwaysHiddenSeparator: ControlItem?
    private var spacerItems: [UUID: SpacerItem] = [:]
    private var groupItems: [UUID: GroupItem] = [:]

    private let scanner = MenuBarItemScanner()
    private let mover = MenuBarItemMover()
    private var reveal: RevealController?
    private let bar = HiddenItemsBar()
    private var arranger: AutoArranger?

    private var busSubscription: UUID?
    private var observers: [NSObjectProtocol] = []
    private var arrangeTimer: Timer?
    private var moveInProgress = false
    private var enforceTask: Task<Void, Never>?
    private var pressRestoreTask: Task<Void, Never>?
    private var pressRestoreMonitor: Any?

    /// Whether the hidden section is currently pushed off screen.
    public private(set) var isHiddenSectionCollapsed = true
    /// Whether the always-hidden section is currently pushed off screen.
    public private(set) var isAlwaysHiddenSectionCollapsed = true

    public var onQuitRequested: (() -> Void)?
    /// Invoked from the context menu. Defaults to opening the SwiftUI Settings scene.
    public var onOpenSettingsRequested: (() -> Void)?

    public override init() {
        settings = SettingsStore.shared.load(MenuBarSettings.storeKey, default: MenuBarSettings())
        super.init()
    }

    // MARK: FeatureModule

    public func start() throws {
        guard !isRunning else { return }
        let alwaysHidden = ControlItem(kind: .alwaysHiddenSeparator)
        let hidden = ControlItem(kind: .hiddenSeparator)
        let icon = ControlItem(kind: .appIcon)
        alwaysHiddenSeparator = alwaysHidden
        hiddenSeparator = hidden
        appIcon = icon

        icon.statusItem.button?.image = icon.separatorImage
        icon.statusItem.button?.target = self
        icon.statusItem.button?.action = #selector(appIconClicked(_:))
        icon.statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        for separator in [hidden, alwaysHidden] {
            separator.statusItem.button?.target = self
            separator.statusItem.button?.action = #selector(separatorClicked(_:))
        }
        applyCollapseState()

        for spacer in settings.spacers { spacerItems[spacer.id] = SpacerItem(spacer: spacer) }
        for group in settings.groups { addGroupItem(group) }

        let reveal = RevealController(settings: settings)
        reveal.setRevealed = { [weak self] revealed in self?.setHiddenSectionCollapsed(!revealed) }
        reveal.isRevealed = { [weak self] in self?.isHiddenSectionCollapsed == false }
        reveal.extraKeepAliveFrames = { [weak self] in self?.bar.frame.map { [$0] } ?? [] }
        reveal.start()
        self.reveal = reveal

        bar.onPress = { [weak self] item in self?.barPressed(item) }
        bar.onClose = { [weak self] in
            guard let self else { return }
            EventBus.shared.publish(.hiddenItemsBarClosed(displayID: self.bar.displayID ?? 0))
        }

        arranger = AutoArranger(module: self)

        busSubscription = EventBus.shared.subscribe { [weak self] event in
            guard let self else { return }
            switch event {
            case .notchPanelExpanded: self.closeHiddenItemsBar()
            case .screenParametersChanged: self.scheduleArrangePass()
            default: break
            }
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { MenuBarModule.active?.scheduleArrangePass() }
        })
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { MenuBarModule.active?.scheduleEnforceAssignments(after: 2.5) }
        })
        MenuBarModule.active = self

        scheduleEnforceAssignments(after: 3)
        restartArrangeTimer()
        isRunning = true
    }

    public func stop() {
        // Mark stopped first so any in-flight async work (moves, enforcement, swaps) bails out at its next guard.
        isRunning = false
        enforceTask?.cancel()
        enforceTask = nil
        pressRestoreTask?.cancel()
        pressRestoreTask = nil
        if let pressRestoreMonitor { NSEvent.removeMonitor(pressRestoreMonitor) }
        pressRestoreMonitor = nil
        arranger?.stop()
        arranger = nil
        reveal?.stop()
        reveal = nil
        bar.close(notify: false)
        arrangeTimer?.invalidate()
        arrangeTimer = nil
        if let busSubscription { EventBus.shared.unsubscribe(busSubscription) }
        busSubscription = nil
        observers.forEach { NotificationCenter.default.removeObserver($0); NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        spacerItems.values.forEach { NSStatusBar.system.removeStatusItem($0.statusItem) }
        spacerItems.removeAll()
        groupItems.values.forEach { NSStatusBar.system.removeStatusItem($0.statusItem) }
        groupItems.removeAll()
        [appIcon, hiddenSeparator, alwaysHiddenSeparator].compactMap { $0 }.forEach { $0.remove() }
        appIcon = nil
        hiddenSeparator = nil
        alwaysHiddenSeparator = nil
        if MenuBarModule.active === self { MenuBarModule.active = nil }
    }

    private static var active: MenuBarModule?

    // MARK: Settings application

    private func applySettings(previous: MenuBarSettings) {
        reveal?.settings = settings
        guard isRunning else { return }

        // Spacers
        let wantedSpacers = Dictionary(uniqueKeysWithValues: settings.spacers.map { ($0.id, $0) })
        for (id, item) in spacerItems where wantedSpacers[id] == nil {
            item.remove()
            spacerItems[id] = nil
        }
        for spacer in settings.spacers {
            if let existing = spacerItems[spacer.id] {
                existing.setLength(spacer.length)
            } else {
                spacerItems[spacer.id] = SpacerItem(spacer: spacer)
            }
        }

        // Groups
        let wantedGroups = Dictionary(uniqueKeysWithValues: settings.groups.map { ($0.id, $0) })
        for (id, item) in groupItems where wantedGroups[id] == nil {
            item.remove()
            groupItems[id] = nil
        }
        for group in settings.groups {
            if let existing = groupItems[group.id] {
                existing.update(name: group.name)
            } else {
                addGroupItem(group)
            }
        }

        if settings.autoArrangeByWidth != previous.autoArrangeByWidth {
            restartArrangeTimer()
            if settings.autoArrangeByWidth { scheduleArrangePass() }
        }
    }

    private func addGroupItem(_ group: MenuBarSettings.Group) {
        let item = GroupItem(group: group)
        item.onClick = { [weak self] id in self?.openHiddenItemsBar(groupID: id) }
        groupItems[group.id] = item
    }

    // MARK: Section visibility

    public func setHiddenSectionCollapsed(_ collapsed: Bool) {
        isHiddenSectionCollapsed = collapsed
        if collapsed {
            isAlwaysHiddenSectionCollapsed = true
        }
        applyCollapseState()
        if !collapsed { reveal?.didReveal() } else { reveal?.cancelRehide() }
    }

    public func setAlwaysHiddenSectionCollapsed(_ collapsed: Bool) {
        isAlwaysHiddenSectionCollapsed = collapsed
        if !collapsed { isHiddenSectionCollapsed = false }
        applyCollapseState()
        if !collapsed { reveal?.didReveal() }
    }

    public func toggleHiddenSection() {
        setHiddenSectionCollapsed(!isHiddenSectionCollapsed)
    }

    /// M02: expand the hidden section (auto-rehide applies).
    public func revealHidden() { setHiddenSectionCollapsed(false) }

    /// Collapse both sections and close the hidden items bar.
    public func hideAll() {
        setHiddenSectionCollapsed(true)
        closeHiddenItemsBar()
    }

    private func applyCollapseState() {
        hiddenSeparator?.setCollapsed(isHiddenSectionCollapsed)
        alwaysHiddenSeparator?.setCollapsed(isAlwaysHiddenSectionCollapsed)
    }

    // MARK: Items

    /// Apps that appear to be running their own menu bar manager: any status item wider than a screen is a
    /// collapse spacer like ours. Empty without Accessibility.
    public func otherMenuBarManagers() -> [(pid: pid_t, name: String)] {
        var seen: Set<pid_t> = []
        return scanner.scan().compactMap { item in
            guard item.frame.width > 1000, !seen.contains(item.ownerPID) else { return nil }
            seen.insert(item.ownerPID)
            return (item.ownerPID, item.ownerName)
        }
    }

    /// Other apps' status items with the section each currently sits in. Empty without Accessibility.
    public func items() -> [(item: MenuBarItem, section: MenuBarSection)] {
        let all = scanner.scan()
        guard let hiddenFrame = hiddenSeparator?.frame, let alwaysHiddenFrame = alwaysHiddenSeparator?.frame else {
            return all.map { ($0, .visible) }
        }
        return all.map { ($0, classify($0, hiddenFrame: hiddenFrame, alwaysHiddenFrame: alwaysHiddenFrame)) }
    }

    /// Moves an item into a section, retrying up to three times, and records the user's intent so it can be
    /// re-applied when the owning app relaunches.
    public func moveWithRetry(_ item: MenuBarItem, to section: MenuBarSection, recordAssignment: Bool = true) async throws {
        var lastError: Error = MoveFailure.itemNotFound
        for attempt in 0..<3 {
            do {
                try await move(item, to: section)
                if recordAssignment { settings.sectionAssignments[item.stableKey] = section }
                return
            } catch {
                lastError = error
                try? await Task.sleep(for: .milliseconds(200 * (attempt + 1)))
            }
        }
        throw lastError
    }

    /// Moves an item into a section by ⌘-dragging it next to the matching separator, then verifies the result.
    /// Both sections are expanded during the move and the previous collapse state is restored afterwards.
    public func move(_ item: MenuBarItem, to section: MenuBarSection) async throws {
        guard isRunning else { throw MoveFailure.itemNotFound }
        while moveInProgress { try await Task.sleep(for: .milliseconds(100)) }
        guard isRunning else { throw MoveFailure.itemNotFound }
        moveInProgress = true
        let previousHidden = isHiddenSectionCollapsed
        let previousAlwaysHidden = isAlwaysHiddenSectionCollapsed
        isAlwaysHiddenSectionCollapsed = false
        isHiddenSectionCollapsed = false
        applyCollapseState()
        reveal?.cancelRehide()
        defer {
            isHiddenSectionCollapsed = previousHidden
            isAlwaysHiddenSectionCollapsed = previousAlwaysHidden
            applyCollapseState()
            moveInProgress = false
        }
        try await Task.sleep(for: .milliseconds(150))

        scanner.invalidate()
        var all = scanner.scan()
        guard let current = all.first(where: { $0.id == item.id }),
              let hiddenFrame = hiddenSeparator?.frame,
              let alwaysHiddenFrame = alwaysHiddenSeparator?.frame else {
            throw MoveFailure.itemNotFound
        }
        if MenuBarItemScanner.isSystemItem(bundleIdentifier: current.bundleIdentifier) { throw MoveFailure.itemNotFound }
        if classify(current, hiddenFrame: hiddenFrame, alwaysHiddenFrame: alwaysHiddenFrame) == section { return }

        let halfWidth = current.frame.width / 2
        let targetX: CGFloat
        switch section {
        case .visible: targetX = hiddenFrame.maxX + halfWidth + 2
        case .hidden: targetX = hiddenFrame.minX - halfWidth - 2
        case .alwaysHidden: targetX = alwaysHiddenFrame.minX - halfWidth - 2
        }
        let start = CGPoint(x: current.frame.midX, y: current.frame.midY)
        guard isRunning else { throw MoveFailure.itemNotFound }
        try await mover.drag(from: start, to: CGPoint(x: targetX, y: start.y))

        try await Task.sleep(for: .milliseconds(200))
        scanner.invalidate()
        all = scanner.scan()
        guard let moved = all.first(where: { $0.id == item.id }),
              let newHidden = hiddenSeparator?.frame,
              let newAlwaysHidden = alwaysHiddenSeparator?.frame else {
            throw MoveFailure.itemNotFound
        }
        let landed = classify(moved, hiddenFrame: newHidden, alwaysHiddenFrame: newAlwaysHidden)
        if landed != section { throw MoveFailure.landedIn(landed) }
    }

    private func classify(_ item: MenuBarItem, hiddenFrame: CGRect, alwaysHiddenFrame: CGRect) -> MenuBarSection {
        let x = item.frame.midX
        if x > hiddenFrame.minX { return .visible }
        if x > alwaysHiddenFrame.minX { return .hidden }
        return .alwaysHidden
    }

    /// Re-applies persisted section assignments for items that drifted (for example after their app relaunched).
    public func enforceAssignments(maxMoves: Int = 3) async {
        guard isRunning, Permission.accessibility.isGranted, !settings.sectionAssignments.isEmpty else { return }
        var moves = 0
        for (item, section) in items() where moves < maxMoves {
            guard isRunning else { return }
            guard let wanted = settings.sectionAssignments[item.stableKey], wanted != section else { continue }
            do {
                try await moveWithRetry(item, to: wanted, recordAssignment: false)
                moves += 1
            } catch {
                NSLog("enforce assignment %@ -> %@ failed: %@", item.displayName, wanted.rawValue, String(describing: error))
            }
        }
    }

    private func scheduleEnforceAssignments(after seconds: Double) {
        enforceTask?.cancel()
        enforceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, self.isRunning else { return }
            await self.enforceAssignments()
        }
    }

    /// Activates an item as a click would. Uses Accessibility first; falls back to revealing the item and posting
    /// a real click at its position.
    @discardableResult
    public func press(_ item: MenuBarItem) -> Bool {
        guard isRunning else { return false }
        if scanner.press(item) { return true }
        pressRestoreTask?.cancel()
        if let pressRestoreMonitor { NSEvent.removeMonitor(pressRestoreMonitor) }
        pressRestoreMonitor = nil
        let previousHidden = isHiddenSectionCollapsed
        let previousAlwaysHidden = isAlwaysHiddenSectionCollapsed
        pressRestoreTask = Task { @MainActor [weak self] in
            guard let self, self.isRunning else { return }
            self.isAlwaysHiddenSectionCollapsed = false
            self.isHiddenSectionCollapsed = false
            self.applyCollapseState()
            self.reveal?.cancelRehide()
            try? await Task.sleep(for: .milliseconds(150))
            self.scanner.invalidate()
            if !Task.isCancelled, self.isRunning, let current = self.scanner.scan().first(where: { $0.id == item.id }) {
                let point = CGPoint(x: current.frame.midX, y: current.frame.midY)
                let source = CGEventSource(stateID: .hidSystemState)
                if let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
                   let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) {
                    down.post(tap: .cghidEventTap)
                    try? await Task.sleep(for: .milliseconds(40))
                    up.post(tap: .cghidEventTap)
                }
            }
            // The click usually opened a menu, which would close if we collapsed now. Restore the previous
            // collapse state on the next click anywhere (the menu dismissing) or after a timeout.
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, self.isRunning else { return }
            await self.waitForClickOrTimeout(seconds: 15)
            guard !Task.isCancelled, self.isRunning else { return }
            self.isHiddenSectionCollapsed = previousHidden
            self.isAlwaysHiddenSectionCollapsed = previousAlwaysHidden
            self.applyCollapseState()
        }
        return false
    }

    private func waitForClickOrTimeout(seconds: Double) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let box = ContinuationBox(continuation)
            pressRestoreMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
                MainActor.assumeIsolated { MenuBarModule.active?.finishPressRestore(box) }
            }
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                self?.finishPressRestore(box)
            }
        }
    }

    private final class ContinuationBox {
        private var continuation: CheckedContinuation<Void, Never>?
        init(_ continuation: CheckedContinuation<Void, Never>) { self.continuation = continuation }
        func resume() {
            continuation?.resume()
            continuation = nil
        }
    }

    private func finishPressRestore(_ box: ContinuationBox) {
        if let pressRestoreMonitor { NSEvent.removeMonitor(pressRestoreMonitor) }
        pressRestoreMonitor = nil
        box.resume()
    }

    // MARK: Hidden items bar (M03)

    public var isHiddenItemsBarOpen: Bool { bar.isOpen }

    public func openHiddenItemsBar(displayID: CGDirectDisplayID? = nil) {
        let entries = items().filter { $0.section != .visible }.map(\.item)
        openBar(with: entries, displayID: displayID)
    }

    public func openHiddenItemsBar(groupID: UUID) {
        guard let group = settings.groups.first(where: { $0.id == groupID }) else { return }
        let keys = Set(group.memberKeys)
        let entries = items().map(\.item).filter { keys.contains($0.stableKey) }
        openBar(with: entries, displayID: nil)
    }

    public func closeHiddenItemsBar() {
        bar.close()
    }

    private func openBar(with entries: [MenuBarItem], displayID: CGDirectDisplayID?) {
        let screen = displayID.flatMap { MenuBarGeometry.screen(withDisplayID: $0) }
            ?? MenuBarGeometry.screen(containing: NSEvent.mouseLocation)
            ?? MenuBarGeometry.mainScreen
        guard let screen else { return }
        let anchor = appIcon?.frame.map { MenuBarGeometry.toAppKit($0) }
        let barEntries = entries.map { item in
            HiddenItemsBar.Entry(item: item, image: NSRunningApplication(processIdentifier: item.ownerPID)?.icon)
        }
        bar.open(entries: barEntries, on: screen, placement: settings.barPlacement, anchor: anchor)
        EventBus.shared.publish(.hiddenItemsBarOpened(displayID: MenuBarGeometry.displayID(of: screen) ?? 0))

        if settings.imageMode == .captured, Permission.screenRecording.isGranted {
            for item in entries {
                guard let windowID = item.windowID else { continue }
                Task { @MainActor [weak self] in
                    guard let cg = await WindowCapture.shared.image(ofWindow: windowID, maxWidth: 88) else { return }
                    let image = NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / 2, height: CGFloat(cg.height) / 2))
                    self?.bar.updateImage(image, for: item)
                }
            }
        }
    }

    private func barPressed(_ item: MenuBarItem) {
        bar.close()
        press(item)
    }

    // MARK: Auto-arrange (M04)

    private func restartArrangeTimer() {
        arrangeTimer?.invalidate()
        arrangeTimer = nil
        guard settings.autoArrangeByWidth else { return }
        arrangeTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { _ in
            MainActor.assumeIsolated { MenuBarModule.active?.scheduleArrangePass() }
        }
    }

    public func scheduleArrangePass() {
        guard settings.autoArrangeByWidth, let arranger else { return }
        Task { @MainActor in await arranger.runPass() }
    }

    /// M04: temporarily bring a hidden item into view, swapping a low-priority visible item out if needed.
    public func swapTemporarily(_ item: MenuBarItem) {
        arranger?.swapTemporarily(item, for: settings.temporarySwapDuration)
    }

    // MARK: Spacers and groups (M05)

    public func addSpacer(length: Double = 16) {
        settings.spacers.append(.init(length: length))
    }

    public func removeSpacer(id: UUID) {
        settings.spacers.removeAll { $0.id == id }
    }

    public func addGroup(named name: String) {
        settings.groups.append(.init(name: name))
    }

    public func removeGroup(id: UUID) {
        settings.groups.removeAll { $0.id == id }
    }

    // MARK: Settings UI

    public func settingsView() -> AnyView {
        AnyView(MenuBarSettingsView(module: self))
    }

    // MARK: Actions

    @objc private func appIconClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu(from: sender)
        } else if settings.secondaryBarEnabled {
            if bar.isOpen { closeHiddenItemsBar() } else { openHiddenItemsBar(displayID: sender.window?.screen.flatMap { MenuBarGeometry.displayID(of: $0) }) }
        } else {
            toggleHiddenSection()
        }
    }

    @objc private func separatorClicked(_ sender: NSStatusBarButton) {
        if sender === hiddenSeparator?.statusItem.button {
            if isHiddenSectionCollapsed, !settings.revealOnClickEmptyArea { return }
            toggleHiddenSection()
        } else {
            setAlwaysHiddenSectionCollapsed(!isAlwaysHiddenSectionCollapsed)
        }
    }

    private func showMenu(from button: NSStatusBarButton) {
        guard let statusItem = appIcon?.statusItem else { return }
        statusItem.menu = buildMenu()
        button.performClick(nil)
        statusItem.menu = nil
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let hiddenToggle = NSMenuItem(
            title: isHiddenSectionCollapsed ? "Show Hidden Items" : "Hide Hidden Items",
            action: #selector(menuToggleHidden), keyEquivalent: ""
        )
        hiddenToggle.target = self
        menu.addItem(hiddenToggle)

        let alwaysToggle = NSMenuItem(
            title: isAlwaysHiddenSectionCollapsed ? "Show Always-Hidden Items" : "Hide Always-Hidden Items",
            action: #selector(menuToggleAlwaysHidden), keyEquivalent: ""
        )
        alwaysToggle.target = self
        menu.addItem(alwaysToggle)

        let barItem = NSMenuItem(title: "Show Hidden Items Bar", action: #selector(menuOpenBar), keyEquivalent: "")
        barItem.target = self
        menu.addItem(barItem)

        menu.addItem(.separator())
        let itemsMenuItem = NSMenuItem(title: "Menu Bar Items", action: nil, keyEquivalent: "")
        itemsMenuItem.submenu = buildItemsSubmenu()
        menu.addItem(itemsMenuItem)

        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(menuOpenSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let quit = NSMenuItem(title: "Quit Garakuta", action: #selector(menuQuit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    private func buildItemsSubmenu() -> NSMenu {
        let submenu = NSMenu()
        if !Permission.accessibility.isGranted {
            let grant = NSMenuItem(title: "Grant Accessibility Access…", action: #selector(menuRequestAccessibility), keyEquivalent: "")
            grant.target = self
            submenu.addItem(grant)
            submenu.addItem(.separator())
        }
        let snapshot = items()
        for section in MenuBarSection.allCases {
            let header = NSMenuItem(title: section.displayName, action: nil, keyEquivalent: "")
            header.isEnabled = false
            submenu.addItem(header)
            let entries = snapshot.filter { $0.section == section }
            if entries.isEmpty {
                let empty = NSMenuItem(title: "   (none)", action: nil, keyEquivalent: "")
                empty.isEnabled = false
                submenu.addItem(empty)
            }
            for (item, _) in entries {
                let entry = NSMenuItem(title: "   \(item.displayName)", action: nil, keyEquivalent: "")
                entry.image = NSRunningApplication(processIdentifier: item.ownerPID)?.icon.map { icon in
                    let small = icon.copy() as! NSImage
                    small.size = NSSize(width: 16, height: 16)
                    return small
                }
                entry.submenu = buildMoveSubmenu(for: item, current: section)
                submenu.addItem(entry)
            }
            submenu.addItem(.separator())
        }
        return submenu
    }

    private func buildMoveSubmenu(for item: MenuBarItem, current: MenuBarSection) -> NSMenu {
        let menu = NSMenu()
        for target in MenuBarSection.allCases where target != current {
            let entry = NSMenuItem(title: "Move to \(target.displayName)", action: #selector(menuMoveItem(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = MoveRequest(item: item, section: target)
            menu.addItem(entry)
        }
        if current != .visible {
            menu.addItem(.separator())
            let swap = NSMenuItem(title: "Show Temporarily", action: #selector(menuSwapItem(_:)), keyEquivalent: "")
            swap.target = self
            swap.representedObject = MoveRequest(item: item, section: .visible)
            menu.addItem(swap)
        }
        let activate = NSMenuItem(title: "Activate", action: #selector(menuPressItem(_:)), keyEquivalent: "")
        activate.target = self
        activate.representedObject = MoveRequest(item: item, section: current)
        menu.addItem(activate)
        return menu
    }

    private final class MoveRequest: NSObject {
        let item: MenuBarItem
        let section: MenuBarSection
        init(item: MenuBarItem, section: MenuBarSection) {
            self.item = item
            self.section = section
        }
    }

    @objc private func menuToggleHidden() { toggleHiddenSection() }
    @objc private func menuToggleAlwaysHidden() { setAlwaysHiddenSectionCollapsed(!isAlwaysHiddenSectionCollapsed) }
    @objc private func menuOpenBar() { openHiddenItemsBar() }
    @objc private func menuRequestAccessibility() { Permission.accessibility.request() }
    @objc private func menuQuit() { onQuitRequested?() ?? NSApp.terminate(nil) }

    @objc private func menuOpenSettings() {
        if let onOpenSettingsRequested {
            onOpenSettingsRequested()
        } else {
            NSApp.activate()
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }

    @objc private func menuMoveItem(_ sender: NSMenuItem) {
        guard let request = sender.representedObject as? MoveRequest else { return }
        Task { @MainActor in
            do {
                try await moveWithRetry(request.item, to: request.section)
            } catch {
                NSLog("move %@ -> %@ failed: %@", request.item.displayName, request.section.rawValue, String(describing: error))
            }
        }
    }

    @objc private func menuSwapItem(_ sender: NSMenuItem) {
        guard let request = sender.representedObject as? MoveRequest else { return }
        swapTemporarily(request.item)
    }

    @objc private func menuPressItem(_ sender: NSMenuItem) {
        guard let request = sender.representedObject as? MoveRequest else { return }
        press(request.item)
    }
}
