import CoreGraphics
import Foundation

/// Everything the notch panel can be configured with. Persisted as JSON under the "notch" key.
public struct NotchSettings: Codable, Equatable, Sendable {
    public struct RGBA: Codable, Equatable, Sendable {
        public var red: Double
        public var green: Double
        public var blue: Double
        public var alpha: Double
        public init(red: Double, green: Double, blue: Double, alpha: Double) {
            self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
        }
        public static let black = RGBA(red: 0, green: 0, blue: 0, alpha: 1)
    }

    public enum SizePreset: Codable, Equatable, Sendable {
        case compact
        case wide
        case custom(width: Double, height: Double)

        /// Expanded panel size.
        var expandedSize: CGSize {
            switch self {
            case .compact: CGSize(width: 480, height: 180)
            case .wide: CGSize(width: 640, height: 230)
            case .custom(let w, let h): CGSize(width: max(240, w), height: max(80, h))
            }
        }

        /// Extra width added on each side of the notch in the compact state.
        var compactSideWidth: CGFloat {
            switch self {
            case .compact: 84
            case .wide: 112
            case .custom(let w, _): max(60, min(140, w / 5))
            }
        }
    }

    public struct Appearance: Codable, Equatable, Sendable {
        public var sizePreset: SizePreset = .compact
        public var cornerRadius: Double = 18
        public var background: RGBA = .black
        /// 1 = default speed; 2 = twice as fast.
        public var animationSpeed: Double = 1
        /// Horizontal nudge in points.
        public var xOffset: Double = 0
        /// Vertical nudge in points; only used when the island sits below the menu bar.
        public var yOffset: Double = 6
        /// Width of the floating island on displays without a hardware notch.
        public var pillWidth: Double = 160
        public var pillHeight: Double = 26
        /// Where the island goes on displays without a hardware notch.
        public var islandPlacement: IslandPlacement = .menuBar
        public init() {}

        private enum CodingKeys: String, CodingKey {
            case sizePreset, cornerRadius, background, animationSpeed, xOffset, yOffset, pillWidth, pillHeight, islandPlacement
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let d = Appearance()
            sizePreset = (try? c.decodeIfPresent(SizePreset.self, forKey: .sizePreset)) ?? d.sizePreset
            cornerRadius = try c.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? d.cornerRadius
            background = (try? c.decodeIfPresent(RGBA.self, forKey: .background)) ?? d.background
            animationSpeed = try c.decodeIfPresent(Double.self, forKey: .animationSpeed) ?? d.animationSpeed
            xOffset = try c.decodeIfPresent(Double.self, forKey: .xOffset) ?? d.xOffset
            yOffset = try c.decodeIfPresent(Double.self, forKey: .yOffset) ?? d.yOffset
            pillWidth = try c.decodeIfPresent(Double.self, forKey: .pillWidth) ?? d.pillWidth
            pillHeight = try c.decodeIfPresent(Double.self, forKey: .pillHeight) ?? d.pillHeight
            islandPlacement = (try? c.decodeIfPresent(IslandPlacement.self, forKey: .islandPlacement)) ?? d.islandPlacement
        }
    }

    /// Placement of the island on displays without a hardware notch.
    public enum IslandPlacement: String, Codable, CaseIterable, Sendable {
        /// A pill centred inside the menu bar, expanding downwards from the top edge of the screen.
        case menuBar
        /// A pill floating just below the menu bar.
        case belowMenuBar
    }

    public enum FullScreenRule: String, Codable, CaseIterable, Sendable {
        case hide, compactOnly, alwaysShow
        public var title: String {
            switch self {
            case .hide: "Hide"
            case .compactOnly: "Compact only"
            case .alwaysShow: "Always show"
            }
        }
    }

    public enum MissionControlRule: String, Codable, CaseIterable, Sendable {
        case hide, show
        public var title: String { self == .hide ? "Hide" : "Show" }
    }

    public struct WidgetLayoutEntry: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var enabled: Bool
        public init(id: String, enabled: Bool) { self.id = id; self.enabled = enabled }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        }
    }

    public struct LiveActivitySettings: Codable, Equatable, Sendable {
        public var enabledProviders: Set<String> = ["nowPlaying", "timer", "battery"]
        public var priorityOrder: [String] = ["timer", "nowPlaying", "battery"]
        public init() {}

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let d = LiveActivitySettings()
            enabledProviders = try c.decodeIfPresent(Set<String>.self, forKey: .enabledProviders) ?? d.enabledProviders
            priorityOrder = try c.decodeIfPresent([String].self, forKey: .priorityOrder) ?? d.priorityOrder
        }
    }

    public struct DisplayOverride: Codable, Equatable, Sendable {
        public var enabled: Bool?
        public var appearance: Appearance?
        public init(enabled: Bool? = nil, appearance: Appearance? = nil) {
            self.enabled = enabled; self.appearance = appearance
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled)
            appearance = try? c.decodeIfPresent(Appearance.self, forKey: .appearance)
        }
    }

    public var enabled = true
    public var appearance = Appearance()
    public var hoverOpenDelay: Double = 0.15
    public var hoverCloseDelay: Double = 0.45
    public var hoverPadding: Double = 8
    public var swipeNavigationEnabled = true
    public var dragToOpenEnabled = true
    public var modifierOnlyShow = false
    public var fullScreenRule: FullScreenRule = .hide
    public var missionControlRule: MissionControlRule = .hide
    public var hideFromCapture = true
    public var autoHideWhileCapturing = false
    public var widgetLayout: [WidgetLayoutEntry] = [
        .init(id: "nowPlaying", enabled: true),
        .init(id: "shelf", enabled: true),
        .init(id: "timer", enabled: true),
        .init(id: "clock", enabled: true),
        .init(id: "battery", enabled: true),
    ]
    public var liveActivities = LiveActivitySettings()
    /// Keyed by the display ID rendered as a string.
    public var displayOverrides: [String: DisplayOverride] = [:]

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case enabled, appearance, hoverOpenDelay, hoverCloseDelay, hoverPadding, swipeNavigationEnabled, dragToOpenEnabled
        case modifierOnlyShow, fullScreenRule, missionControlRule, hideFromCapture, autoHideWhileCapturing
        case widgetLayout, liveActivities, displayOverrides
    }

    /// Lenient: every missing or malformed field falls back to its default so a settings file written by an
    /// older or newer build never resets the user's configuration wholesale.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = NotchSettings()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        appearance = (try? c.decodeIfPresent(Appearance.self, forKey: .appearance)) ?? d.appearance
        hoverOpenDelay = try c.decodeIfPresent(Double.self, forKey: .hoverOpenDelay) ?? d.hoverOpenDelay
        hoverCloseDelay = try c.decodeIfPresent(Double.self, forKey: .hoverCloseDelay) ?? d.hoverCloseDelay
        hoverPadding = try c.decodeIfPresent(Double.self, forKey: .hoverPadding) ?? d.hoverPadding
        swipeNavigationEnabled = try c.decodeIfPresent(Bool.self, forKey: .swipeNavigationEnabled) ?? d.swipeNavigationEnabled
        dragToOpenEnabled = try c.decodeIfPresent(Bool.self, forKey: .dragToOpenEnabled) ?? d.dragToOpenEnabled
        modifierOnlyShow = try c.decodeIfPresent(Bool.self, forKey: .modifierOnlyShow) ?? d.modifierOnlyShow
        fullScreenRule = (try? c.decodeIfPresent(FullScreenRule.self, forKey: .fullScreenRule)) ?? d.fullScreenRule
        missionControlRule = (try? c.decodeIfPresent(MissionControlRule.self, forKey: .missionControlRule)) ?? d.missionControlRule
        hideFromCapture = try c.decodeIfPresent(Bool.self, forKey: .hideFromCapture) ?? d.hideFromCapture
        autoHideWhileCapturing = try c.decodeIfPresent(Bool.self, forKey: .autoHideWhileCapturing) ?? d.autoHideWhileCapturing
        widgetLayout = (try? c.decodeIfPresent([WidgetLayoutEntry].self, forKey: .widgetLayout)) ?? d.widgetLayout
        liveActivities = (try? c.decodeIfPresent(LiveActivitySettings.self, forKey: .liveActivities)) ?? d.liveActivities
        displayOverrides = (try? c.decodeIfPresent([String: DisplayOverride].self, forKey: .displayOverrides)) ?? d.displayOverrides
    }

    public func isEnabled(onDisplay displayID: CGDirectDisplayID) -> Bool {
        displayOverrides[String(displayID)]?.enabled ?? enabled
    }

    public func appearance(forDisplay displayID: CGDirectDisplayID) -> Appearance {
        displayOverrides[String(displayID)]?.appearance ?? appearance
    }

    public var enabledWidgetIDs: [String] {
        widgetLayout.filter(\.enabled).map(\.id)
    }
}
