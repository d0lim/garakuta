import CoreGraphics
import Foundation

/// A status item belonging to another app.
///
/// On macOS 26 the window server hosts every status item inside Control Center, so window ownership no longer
/// identifies the app. Items are discovered through each app's Accessibility tree (`AXExtrasMenuBar`) instead;
/// `windowID` is the Control Center window whose frame matches, when one is found, and is only needed for capture.
/// Frames use CoreGraphics coordinates (origin at the top-left of the main display), the same space CGEvent uses.
public struct MenuBarItem: Identifiable, Hashable, Sendable {
    public let ownerPID: pid_t
    public let ownerName: String
    public let bundleIdentifier: String?
    /// Index within the owning app's extras menu bar. Stable while the app keeps the same set of items.
    public let index: Int
    public let title: String?
    public let frame: CGRect
    public let windowID: CGWindowID?

    /// Identity for this launch of the owning app (used for the AX element cache).
    public var id: String { "\(ownerPID):\(index)" }

    /// Identity that survives relaunches of the owning app: bundle identifier plus index.
    public var stableKey: String { "\((bundleIdentifier ?? "pid-\(ownerPID)")):\(index)" }

    public var displayName: String {
        if let title, !title.isEmpty, title != ownerName {
            return "\(ownerName) — \(title)"
        }
        return ownerName
    }
}
