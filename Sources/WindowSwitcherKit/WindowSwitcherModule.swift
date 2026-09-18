import AppKit
import GarakutaCore
import PrivateAPIs
import SwiftUI

/// W01–W02: app/window switcher with live thumbnails, search, minimized and other-Space windows, per-app rules.
/// Falls back to current-Space-only enumeration when SkyLight symbols are unavailable.
@MainActor
public final class WindowSwitcherModule: FeatureModule {
    public static let id = "switcher"
    public private(set) var isRunning = false

    /// True when the private SkyLight/HIServices symbols loaded, enabling other-Space windows and window-level focus.
    public private(set) var canEnumerateOtherSpaces = false
    /// Comma-separated names of private symbols that failed to resolve, empty when all loaded.
    public var missingPrivateSymbols: String { String(cString: GKPrivateAPIsMissingSymbols()) }

    public var settings: SwitcherSettings {
        get { controller.state.settings }
        set {
            let old = controller.state.settings
            controller.state.settings = newValue
            SettingsStore.shared.save(newValue, for: SwitcherSettings.storeKey)
            if isRunning, old.trigger != newValue.trigger || old.appWindowsTrigger != newValue.appWindowsTrigger || old.appRules != newValue.appRules {
                registerHotKeys()
            }
            if isRunning, old.windowOrder != newValue.windowOrder || old.groupTabs != newValue.groupTabs || old.showSpaceNumbers != newValue.showSpaceNumbers
                || old.showDockBadges != newValue.showDockBadges || old.appRules != newValue.appRules {
                controller.requestRefresh()
            }
        }
    }

    private let controller = SwitcherController()
    private var hotKeyTokens: [UInt32] = []
    private var activationObserver: NSObjectProtocol?
    /// True while the frontmost app has the "let the app have the shortcut" rule and our hot keys are unregistered.
    private var shortcutYielded = false

    public init() {
        controller.state.settings = SettingsStore.shared.load(SwitcherSettings.storeKey, default: SwitcherSettings())
    }

    public func start() throws {
        guard !isRunning else { return }
        canEnumerateOtherSpaces = GKPrivateAPIsLoad()
        if !canEnumerateOtherSpaces {
            NSLog("WindowSwitcher: private symbols missing (%@); other Spaces disabled", missingPrivateSymbols)
        }
        registerHotKeys()
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { note in
            let bundleID = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated { WindowSwitcherModule.active?.frontmostChanged(bundleID: bundleID) }
        }
        WindowSwitcherModule.active = self
        controller.start()  // warms the cache so the first press shows a list immediately
        isRunning = true
    }

    public func stop() {
        controller.stop()
        unregisterHotKeys()
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        activationObserver = nil
        if WindowSwitcherModule.active === self { WindowSwitcherModule.active = nil }
        isRunning = false
    }

    private static var active: WindowSwitcherModule?

    /// Opens the switcher (or cycles when already open), as the hotkey does.
    public func show(reverse: Bool = false) {
        controller.trigger(settings.trigger, reverse: reverse, appWindowsOnly: false)
    }

    /// Opens the switcher listing only the active app's windows.
    public func showAppWindows(reverse: Bool = false) {
        controller.trigger(settings.appWindowsTrigger ?? settings.trigger, reverse: reverse, appWindowsOnly: true)
    }

    public func hide() {
        controller.hide()
    }

    public var isVisible: Bool { controller.isOpen }

    /// Call when Accessibility may have been granted, so observers reach apps that were already running.
    public func permissionsMayHaveChanged() {
        guard isRunning else { return }
        controller.accessibilityMayHaveChanged()
    }

    /// True when the system refused the trigger shortcut, which means another app registered the same hot key.
    /// Switchers that intercept keys with an event tap instead are not detected this way.
    public private(set) var hotKeyConflict = false

    public var settingsView: some View {
        SwitcherSettingsView(settings: settings) { [weak self] new in self?.settings = new }
    }

    // MARK: Hot keys

    /// An app with the pass-through rule keeps the shortcut while it is frontmost (virtual machines and remote
    /// desktops want ⌥⇥ for the other system).
    private func frontmostChanged(bundleID: String?) {
        let yield = settings.rule(for: bundleID) == .passShortcutThrough
        guard yield != shortcutYielded else { return }
        shortcutYielded = yield
        if yield {
            unregisterHotKeys()
        } else {
            registerHotKeys()
        }
    }

    private func registerHotKeys() {
        unregisterHotKeys()
        if shortcutYielded { return }
        let settings = controller.state.settings
        let trigger = settings.trigger
        if let t = HotKeyCenter.shared.register(trigger, handler: { [weak self] in
            self?.controller.trigger(trigger, reverse: false, appWindowsOnly: false)
        }) {
            hotKeyTokens.append(t)
            hotKeyConflict = false
        } else {
            hotKeyConflict = true
            NSLog("WindowSwitcher: could not register %@ (in use by another app?)", trigger.displayString)
        }
        if let t = HotKeyCenter.shared.register(settings.reverseTrigger, handler: { [weak self] in
            self?.controller.trigger(trigger, reverse: true, appWindowsOnly: false)
        }) {
            hotKeyTokens.append(t)
        }
        if let appTrigger = settings.appWindowsTrigger {
            if let t = HotKeyCenter.shared.register(appTrigger, handler: { [weak self] in
                self?.controller.trigger(appTrigger, reverse: false, appWindowsOnly: true)
            }) {
                hotKeyTokens.append(t)
            }
            if let t = HotKeyCenter.shared.register(SwitcherSettings.reverse(of: appTrigger), handler: { [weak self] in
                self?.controller.trigger(appTrigger, reverse: true, appWindowsOnly: true)
            }) {
                hotKeyTokens.append(t)
            }
        }
    }

    private func unregisterHotKeys() {
        hotKeyTokens.forEach { HotKeyCenter.shared.unregister($0) }
        hotKeyTokens.removeAll()
    }
}
