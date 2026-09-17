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
            let triggerChanged = controller.state.settings.trigger != newValue.trigger
            controller.state.settings = newValue
            SettingsStore.shared.save(newValue, for: SwitcherSettings.storeKey)
            if isRunning && triggerChanged { registerHotKeys() }
        }
    }

    private let controller = SwitcherController()
    private var hotKeyTokens: [UInt32] = []

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
        controller.refreshWindows()  // warm the cache so the first press shows a list immediately
        isRunning = true
    }

    public func stop() {
        controller.hide()
        unregisterHotKeys()
        isRunning = false
    }

    /// Opens the switcher (or cycles when already open), as the hotkey does.
    public func show(reverse: Bool = false) {
        controller.trigger(reverse: reverse)
    }

    public func hide() {
        controller.hide()
    }

    public var isVisible: Bool { controller.isOpen }

    /// True when the system refused the trigger shortcut, which means another app registered the same hot key.
    /// Switchers that intercept keys with an event tap instead are not detected this way.
    public private(set) var hotKeyConflict = false

    public var settingsView: some View {
        SwitcherSettingsView(settings: settings) { [weak self] new in self?.settings = new }
    }

    private func registerHotKeys() {
        unregisterHotKeys()
        let settings = controller.state.settings
        if let t = HotKeyCenter.shared.register(settings.trigger, handler: { [weak self] in self?.controller.trigger(reverse: false) }) {
            hotKeyTokens.append(t)
            hotKeyConflict = false
        } else {
            hotKeyConflict = true
            NSLog("WindowSwitcher: could not register %@ (in use by another app?)", settings.trigger.displayString)
        }
        if let t = HotKeyCenter.shared.register(settings.reverseTrigger, handler: { [weak self] in self?.controller.trigger(reverse: true) }) {
            hotKeyTokens.append(t)
        }
    }

    private func unregisterHotKeys() {
        hotKeyTokens.forEach { HotKeyCenter.shared.unregister($0) }
        hotKeyTokens.removeAll()
    }
}
