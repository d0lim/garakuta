import AppKit
import CoreGraphics

/// One window as shown in the switcher. Frames are CoreGraphics coordinates (top-left origin).
public struct SwitcherWindow: Identifiable, Hashable, Sendable {
    public let windowID: CGWindowID
    public let pid: pid_t
    public let appName: String
    public let bundleIdentifier: String?
    public var title: String
    public var frame: CGRect
    public var isMinimized: Bool
    public var isFullScreen: Bool
    public var isAppHidden: Bool
    public var isOnCurrentSpace: Bool
    public var spaceIDs: [UInt64]
    /// 1-based position of the window's Space on its display, when known.
    public var spaceNumber: Int?
    /// The owning app's Dock badge (unread count and the like), when it has one.
    public var dockBadge: String?
    /// A background tab of a tabbed window: same app, same frame as a visible window, on no Space of its own.
    public var isTab = false
    /// True for the stand-in tile of an app that has no windows (rule includeEvenWithoutWindows) or a grouped app.
    public var isAppPlaceholder: Bool

    public var id: CGWindowID { windowID }

    public var displayTitle: String { title.isEmpty ? appName : title }

    /// Width over height of the window itself; a sensible default when the size is unknown.
    public var aspectRatio: CGFloat {
        guard frame.width > 0, frame.height > 0 else { return 1.5 }
        return frame.width / frame.height
    }
}
