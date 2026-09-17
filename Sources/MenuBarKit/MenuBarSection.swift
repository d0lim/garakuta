import Foundation

/// The three regions of the status item area, from right to left: visible, hidden, always hidden.
public enum MenuBarSection: String, CaseIterable, Sendable, Codable {
    case visible
    case hidden
    case alwaysHidden

    public var displayName: String {
        switch self {
        case .visible: "Visible"
        case .hidden: "Hidden"
        case .alwaysHidden: "Always Hidden"
        }
    }
}
