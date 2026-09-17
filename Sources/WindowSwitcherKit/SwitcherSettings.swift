import Carbon.HIToolbox
import Foundation
import GarakutaCore

/// W02: how the switcher is triggered, what it lists, and how it looks. Persisted via SettingsStore key "switcher".
/// Decoding is lenient: unknown or missing keys fall back to defaults so a new field never resets the user's settings.
public struct SwitcherSettings: Codable, Equatable, Sendable {
    public static let storeKey = "switcher"

    public enum TargetScreen: String, Codable, CaseIterable, Sendable {
        case pointer, menuBar, activeWindow

        public var displayName: String {
            switch self {
            case .pointer: "Screen with the pointer"
            case .menuBar: "Screen with the menu bar"
            case .activeWindow: "Screen with the active window"
            }
        }
    }

    public enum AppRule: String, Codable, CaseIterable, Sendable {
        case `default`, groupAsOne, exclude, includeEvenWithoutWindows

        public var displayName: String {
            switch self {
            case .default: "Default"
            case .groupAsOne: "Group windows as one"
            case .exclude: "Exclude"
            case .includeEvenWithoutWindows: "Show even without windows"
            }
        }
    }

    public static let defaultTrigger = KeyCombo(keyCode: UInt32(kVK_Tab), modifiers: UInt32(optionKey))

    public var trigger: KeyCombo = SwitcherSettings.defaultTrigger
    /// Thumbnails off: title + icon only. Also the automatic mode when Screen Recording is missing.
    public var simpleMode = false
    public var showMinimized = true
    public var showHiddenApps = true
    public var showOtherSpaces = true
    /// Only list windows that sit on the screen the switcher is shown on.
    public var currentScreenOnly = false
    public var targetScreen: TargetScreen = .pointer
    public var appRules: [String: AppRule] = [:]
    /// Width of a tile's thumbnail in points.
    public var thumbnailWidth: Double = 220
    /// Seconds to wait before the panel appears; releasing the modifier before that switches to the next window.
    public var holdToShowDelay: Double = 0.15
    public var minimalDecorations = false
    public var closeOnMiddleClick = true
    /// Selecting by releasing the trigger's modifier keys.
    public var activateOnModifierRelease = true

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case trigger, simpleMode, showMinimized, showHiddenApps, showOtherSpaces, currentScreenOnly, targetScreen,
             appRules, thumbnailWidth, holdToShowDelay, minimalDecorations, closeOnMiddleClick, activateOnModifierRelease
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SwitcherSettings()
        trigger = (try? c.decodeIfPresent(KeyCombo.self, forKey: .trigger)) ?? d.trigger
        simpleMode = (try? c.decodeIfPresent(Bool.self, forKey: .simpleMode)) ?? d.simpleMode
        showMinimized = (try? c.decodeIfPresent(Bool.self, forKey: .showMinimized)) ?? d.showMinimized
        showHiddenApps = (try? c.decodeIfPresent(Bool.self, forKey: .showHiddenApps)) ?? d.showHiddenApps
        showOtherSpaces = (try? c.decodeIfPresent(Bool.self, forKey: .showOtherSpaces)) ?? d.showOtherSpaces
        currentScreenOnly = (try? c.decodeIfPresent(Bool.self, forKey: .currentScreenOnly)) ?? d.currentScreenOnly
        if let raw = try? c.decodeIfPresent(String.self, forKey: .targetScreen), let value = TargetScreen(rawValue: raw) {
            targetScreen = value
        } else {
            targetScreen = d.targetScreen
        }
        // Unknown rule names are dropped rather than failing the whole decode.
        if let raw = try? c.decodeIfPresent([String: String].self, forKey: .appRules) {
            appRules = raw.reduce(into: [:]) { acc, pair in
                if let rule = AppRule(rawValue: pair.value) { acc[pair.key] = rule }
            }
        } else {
            appRules = d.appRules
        }
        thumbnailWidth = (try? c.decodeIfPresent(Double.self, forKey: .thumbnailWidth)) ?? d.thumbnailWidth
        holdToShowDelay = (try? c.decodeIfPresent(Double.self, forKey: .holdToShowDelay)) ?? d.holdToShowDelay
        minimalDecorations = (try? c.decodeIfPresent(Bool.self, forKey: .minimalDecorations)) ?? d.minimalDecorations
        closeOnMiddleClick = (try? c.decodeIfPresent(Bool.self, forKey: .closeOnMiddleClick)) ?? d.closeOnMiddleClick
        activateOnModifierRelease = (try? c.decodeIfPresent(Bool.self, forKey: .activateOnModifierRelease)) ?? d.activateOnModifierRelease
    }

    public func rule(for bundleID: String?) -> AppRule {
        guard let bundleID else { return .default }
        return appRules[bundleID] ?? .default
    }

    /// Same key with ⇧ added, used to cycle backwards.
    public var reverseTrigger: KeyCombo {
        KeyCombo(keyCode: trigger.keyCode, modifiers: trigger.modifiers | UInt32(shiftKey))
    }
}
