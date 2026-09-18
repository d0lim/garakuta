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
        case `default`, groupAsOne, exclude, includeEvenWithoutWindows, passShortcutThrough

        public var displayName: String {
            switch self {
            case .default: "Default"
            case .groupAsOne: "Group windows as one"
            case .exclude: "Exclude"
            case .includeEvenWithoutWindows: "Show even without windows"
            case .passShortcutThrough: "Let the app have the shortcut"
            }
        }
    }

    /// What a tile shows.
    public enum Style: String, Codable, CaseIterable, Sendable {
        /// A live thumbnail with the title underneath. Needs Screen Recording; falls back to app icons without it.
        case thumbnails
        /// One large app icon per tile in a single row, like the system's app switcher.
        case appIcons
        /// A single column of titles with a small icon.
        case titles

        public var displayName: String {
            switch self {
            case .thumbnails: "Thumbnails"
            case .appIcons: "App icons"
            case .titles: "Titles"
            }
        }
    }

    /// How tall the grid may grow, expressed as the number of tile rows the screen height is divided into.
    public enum SizePreset: String, Codable, CaseIterable, Sendable {
        case auto, small, medium, large

        public var displayName: String {
            switch self {
            case .auto: "Automatic"
            case .small: "Small"
            case .medium: "Medium"
            case .large: "Large"
            }
        }

        /// Rows the grid is sized for on a landscape screen; portrait screens get three more.
        var rows: Int {
            switch self {
            case .small: 5
            case .medium: 4
            case .large, .auto: 3
            }
        }
    }

    public enum WindowOrder: String, Codable, CaseIterable, Sendable {
        case recentlyFocused, stackingOrder, alphabetical

        public var displayName: String {
            switch self {
            case .recentlyFocused: "Most recently used first"
            case .stackingOrder: "Front to back"
            case .alphabetical: "Alphabetical"
            }
        }
    }

    public enum TitleTruncation: String, Codable, CaseIterable, Sendable {
        case end, middle, start

        public var displayName: String {
            switch self {
            case .end: "At the end"
            case .middle: "In the middle"
            case .start: "At the start"
            }
        }
    }

    public enum PointerFollow: String, Codable, CaseIterable, Sendable {
        case never, otherDisplay, always

        public var displayName: String {
            switch self {
            case .never: "Never"
            case .otherDisplay: "When the window is on another display"
            case .always: "Always"
            }
        }
    }

    public static let defaultTrigger = KeyCombo(keyCode: UInt32(kVK_Tab), modifiers: UInt32(optionKey))

    public var trigger: KeyCombo = SwitcherSettings.defaultTrigger
    /// Optional second shortcut that lists only the windows of the active app.
    public var appWindowsTrigger: KeyCombo?
    public var style: Style = .thumbnails
    public var sizePreset: SizePreset = .auto
    public var windowOrder: WindowOrder = .recentlyFocused
    public var showMinimized = true
    public var showHiddenApps = true
    public var showOtherSpaces = true
    /// Merge the tabs of a tabbed window (Finder, Terminal, Safari…) into the one tile of the visible tab.
    public var groupTabs = true
    /// Only list windows that sit on the screen the switcher is shown on.
    public var currentScreenOnly = false
    public var targetScreen: TargetScreen = .pointer
    public var appRules: [String: AppRule] = [:]
    /// Seconds to wait before the panel appears; releasing the modifier before that switches to the next window.
    public var holdToShowDelay: Double = 0.15
    public var minimalDecorations = false
    public var closeOnMiddleClick = true
    /// Selecting by releasing the trigger's modifier keys.
    public var activateOnModifierRelease = true
    /// Moving the pointer over a tile selects it (once the pointer has actually moved since the panel appeared).
    public var hoverSelects = true
    /// Show the selected window at full size behind the panel.
    public var previewSelectedWindow = false
    public var pointerFollow: PointerFollow = .never
    public var showSpaceNumbers = false
    public var showDockBadges = true
    public var titleTruncation: TitleTruncation = .end
    /// Keep thumbnails fresh while the switcher is closed, so it opens with pictures rather than icons.
    public var refreshThumbnailsInBackground = true

    public init() {}

    /// Legacy name for the titles style, kept for the setup assistant.
    public var simpleMode: Bool {
        get { style == .titles }
        set { style = newValue ? .titles : .thumbnails }
    }

    private enum CodingKeys: String, CodingKey {
        case trigger, appWindowsTrigger, style, sizePreset, windowOrder, simpleMode, showMinimized, showHiddenApps,
             showOtherSpaces, groupTabs, currentScreenOnly, targetScreen, appRules, holdToShowDelay, minimalDecorations,
             closeOnMiddleClick, activateOnModifierRelease, hoverSelects, previewSelectedWindow, pointerFollow,
             showSpaceNumbers, showDockBadges, titleTruncation, refreshThumbnailsInBackground
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SwitcherSettings()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        func raw<T: RawRepresentable>(_ key: CodingKeys, _ fallback: T) -> T where T.RawValue == String {
            guard let s = try? c.decodeIfPresent(String.self, forKey: key), let v = T(rawValue: s) else { return fallback }
            return v
        }
        trigger = value(.trigger, d.trigger)
        appWindowsTrigger = try? c.decodeIfPresent(KeyCombo.self, forKey: .appWindowsTrigger)
        if let styleRaw = try? c.decodeIfPresent(String.self, forKey: .style), let s = Style(rawValue: styleRaw) {
            style = s
        } else {
            style = value(.simpleMode, false) ? .titles : d.style
        }
        sizePreset = raw(.sizePreset, d.sizePreset)
        windowOrder = raw(.windowOrder, d.windowOrder)
        showMinimized = value(.showMinimized, d.showMinimized)
        showHiddenApps = value(.showHiddenApps, d.showHiddenApps)
        showOtherSpaces = value(.showOtherSpaces, d.showOtherSpaces)
        groupTabs = value(.groupTabs, d.groupTabs)
        currentScreenOnly = value(.currentScreenOnly, d.currentScreenOnly)
        targetScreen = raw(.targetScreen, d.targetScreen)
        // Unknown rule names are dropped rather than failing the whole decode.
        if let rules = try? c.decodeIfPresent([String: String].self, forKey: .appRules) {
            appRules = rules.reduce(into: [:]) { acc, pair in
                if let rule = AppRule(rawValue: pair.value) { acc[pair.key] = rule }
            }
        }
        holdToShowDelay = value(.holdToShowDelay, d.holdToShowDelay)
        minimalDecorations = value(.minimalDecorations, d.minimalDecorations)
        closeOnMiddleClick = value(.closeOnMiddleClick, d.closeOnMiddleClick)
        activateOnModifierRelease = value(.activateOnModifierRelease, d.activateOnModifierRelease)
        hoverSelects = value(.hoverSelects, d.hoverSelects)
        previewSelectedWindow = value(.previewSelectedWindow, d.previewSelectedWindow)
        pointerFollow = raw(.pointerFollow, d.pointerFollow)
        showSpaceNumbers = value(.showSpaceNumbers, d.showSpaceNumbers)
        showDockBadges = value(.showDockBadges, d.showDockBadges)
        titleTruncation = raw(.titleTruncation, d.titleTruncation)
        refreshThumbnailsInBackground = value(.refreshThumbnailsInBackground, d.refreshThumbnailsInBackground)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(trigger, forKey: .trigger)
        try c.encodeIfPresent(appWindowsTrigger, forKey: .appWindowsTrigger)
        try c.encode(style, forKey: .style)
        try c.encode(sizePreset, forKey: .sizePreset)
        try c.encode(windowOrder, forKey: .windowOrder)
        try c.encode(showMinimized, forKey: .showMinimized)
        try c.encode(showHiddenApps, forKey: .showHiddenApps)
        try c.encode(showOtherSpaces, forKey: .showOtherSpaces)
        try c.encode(groupTabs, forKey: .groupTabs)
        try c.encode(currentScreenOnly, forKey: .currentScreenOnly)
        try c.encode(targetScreen, forKey: .targetScreen)
        try c.encode(appRules, forKey: .appRules)
        try c.encode(holdToShowDelay, forKey: .holdToShowDelay)
        try c.encode(minimalDecorations, forKey: .minimalDecorations)
        try c.encode(closeOnMiddleClick, forKey: .closeOnMiddleClick)
        try c.encode(activateOnModifierRelease, forKey: .activateOnModifierRelease)
        try c.encode(hoverSelects, forKey: .hoverSelects)
        try c.encode(previewSelectedWindow, forKey: .previewSelectedWindow)
        try c.encode(pointerFollow, forKey: .pointerFollow)
        try c.encode(showSpaceNumbers, forKey: .showSpaceNumbers)
        try c.encode(showDockBadges, forKey: .showDockBadges)
        try c.encode(titleTruncation, forKey: .titleTruncation)
        try c.encode(refreshThumbnailsInBackground, forKey: .refreshThumbnailsInBackground)
    }

    public func rule(for bundleID: String?) -> AppRule {
        guard let bundleID else { return .default }
        return appRules[bundleID] ?? .default
    }

    /// Same key with ⇧ added, used to cycle backwards.
    public var reverseTrigger: KeyCombo { Self.reverse(of: trigger) }

    static func reverse(of combo: KeyCombo) -> KeyCombo {
        KeyCombo(keyCode: combo.keyCode, modifiers: combo.modifiers | UInt32(shiftKey))
    }
}
