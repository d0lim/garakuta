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
    /// True for the stand-in tile of an app that has no windows (rule includeEvenWithoutWindows) or a grouped app.
    public var isAppPlaceholder: Bool

    public var id: CGWindowID { windowID }

    public var displayTitle: String { title.isEmpty ? appName : title }
}
