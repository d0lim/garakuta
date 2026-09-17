import AppKit

/// Per-display geometry needed by M04 (auto-hide by available width) and N01 (notch vs. floating island).
public struct DisplayGeometry: Sendable, Equatable {
    public let displayID: CGDirectDisplayID
    public let frame: CGRect
    public let menuBarHeight: CGFloat
    /// Width of the hardware notch, or nil when the display has none.
    public let notchWidth: CGFloat?

    public var hasNotch: Bool { notchWidth != nil }

    @MainActor
    public init?(screen: NSScreen) {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        displayID = CGDirectDisplayID(number.uint32Value)
        frame = screen.frame
        menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            notchWidth = right.minX - left.maxX
        } else {
            notchWidth = nil
        }
    }

    @MainActor
    public static func all() -> [DisplayGeometry] {
        NSScreen.screens.compactMap(DisplayGeometry.init(screen:))
    }
}
