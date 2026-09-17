import Foundation
import GarakutaCore

/// Persisted configuration for the menu bar module (SettingsStore key "menubar").
public struct MenuBarSettings: Codable, Equatable, Sendable {
    public static let storeKey = "menubar"

    public enum BarPlacement: String, Codable, CaseIterable, Sendable {
        case belowNotch
        case nearPointer
        case belowIcon

        public var displayName: String {
            switch self {
            case .belowNotch: "Below the notch"
            case .nearPointer: "Near the pointer"
            case .belowIcon: "Below the Garakuta icon"
            }
        }
    }

    public enum ImageMode: String, Codable, CaseIterable, Sendable {
        case appIcon
        case captured

        public var displayName: String {
            switch self {
            case .appIcon: "App icons"
            case .captured: "Captured menu bar images"
            }
        }
    }

    public struct Spacer: Codable, Equatable, Sendable, Identifiable {
        public var id: UUID
        public var length: Double

        public init(id: UUID = UUID(), length: Double = 16) {
            self.id = id
            self.length = length
        }
    }

    public struct Group: Codable, Equatable, Sendable, Identifiable {
        public var id: UUID
        public var name: String
        /// `MenuBarItem.stableKey` values.
        public var memberKeys: [String]

        public init(id: UUID = UUID(), name: String, memberKeys: [String] = []) {
            self.id = id
            self.name = name
            self.memberKeys = memberKeys
        }
    }

    // M02
    public var revealOnHover = false
    public var hoverDelay: Double = 0.25
    public var revealOnClickEmptyArea = true
    public var revealOnScroll = false
    public var revealHotKey: KeyCombo?
    public var autoRehide = true
    public var autoRehideDelay: Double = 3

    // M03
    public var secondaryBarEnabled = false
    public var barPlacement: BarPlacement = .belowNotch
    public var imageMode: ImageMode = .appIcon

    // M04
    public var autoArrangeByWidth = false
    public var temporarySwapDuration: Double = 8
    /// Stable keys in priority order; earlier entries stay visible longest. Unknown items have the lowest priority.
    public var priorityOrder: [String] = []

    // M05
    public var spacers: [Spacer] = []
    public var groups: [Group] = []

    // M01 persistence of the user's intent, re-applied when apps relaunch.
    public var sectionAssignments: [String: MenuBarSection] = [:]

    public init() {}

    // Decode leniently so new fields can be added without invalidating stored files.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = MenuBarSettings()
        revealOnHover = try c.decodeIfPresent(Bool.self, forKey: .revealOnHover) ?? d.revealOnHover
        hoverDelay = try c.decodeIfPresent(Double.self, forKey: .hoverDelay) ?? d.hoverDelay
        revealOnClickEmptyArea = try c.decodeIfPresent(Bool.self, forKey: .revealOnClickEmptyArea) ?? d.revealOnClickEmptyArea
        revealOnScroll = try c.decodeIfPresent(Bool.self, forKey: .revealOnScroll) ?? d.revealOnScroll
        revealHotKey = try c.decodeIfPresent(KeyCombo.self, forKey: .revealHotKey)
        autoRehide = try c.decodeIfPresent(Bool.self, forKey: .autoRehide) ?? d.autoRehide
        autoRehideDelay = try c.decodeIfPresent(Double.self, forKey: .autoRehideDelay) ?? d.autoRehideDelay
        secondaryBarEnabled = try c.decodeIfPresent(Bool.self, forKey: .secondaryBarEnabled) ?? d.secondaryBarEnabled
        barPlacement = try c.decodeIfPresent(BarPlacement.self, forKey: .barPlacement) ?? d.barPlacement
        imageMode = try c.decodeIfPresent(ImageMode.self, forKey: .imageMode) ?? d.imageMode
        autoArrangeByWidth = try c.decodeIfPresent(Bool.self, forKey: .autoArrangeByWidth) ?? d.autoArrangeByWidth
        temporarySwapDuration = try c.decodeIfPresent(Double.self, forKey: .temporarySwapDuration) ?? d.temporarySwapDuration
        priorityOrder = try c.decodeIfPresent([String].self, forKey: .priorityOrder) ?? d.priorityOrder
        spacers = try c.decodeIfPresent([Spacer].self, forKey: .spacers) ?? d.spacers
        groups = try c.decodeIfPresent([Group].self, forKey: .groups) ?? d.groups
        sectionAssignments = try c.decodeIfPresent([String: MenuBarSection].self, forKey: .sectionAssignments) ?? d.sectionAssignments
    }
}
