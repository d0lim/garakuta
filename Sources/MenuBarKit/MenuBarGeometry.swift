import AppKit

/// Coordinate helpers. CoreGraphics space has its origin at the top-left of the main display; AppKit's is at the
/// bottom-left. Both share the x axis.
@MainActor
enum MenuBarGeometry {
    static var mainScreen: NSScreen? { NSScreen.screens.first }

    static func toAppKit(_ cg: CGRect) -> CGRect {
        guard let main = mainScreen else { return cg }
        return CGRect(x: cg.minX, y: main.frame.maxY - cg.maxY, width: cg.width, height: cg.height)
    }

    static func toCG(_ appKit: CGRect) -> CGRect {
        guard let main = mainScreen else { return appKit }
        return CGRect(x: appKit.minX, y: main.frame.maxY - appKit.maxY, width: appKit.width, height: appKit.height)
    }

    static func toCG(_ point: CGPoint) -> CGPoint {
        guard let main = mainScreen else { return point }
        return CGPoint(x: point.x, y: main.frame.maxY - point.y)
    }

    /// Menu bar height for a screen, falling back to the main screen's when the secondary reports zero.
    static func menuBarHeight(of screen: NSScreen) -> CGFloat {
        let h = screen.frame.maxY - screen.visibleFrame.maxY
        if h > 0 { return h }
        if let main = mainScreen, main != screen {
            let mh = main.frame.maxY - main.visibleFrame.maxY
            if mh > 0 { return mh }
        }
        return 24
    }

    /// Menu bar strip of a screen in AppKit coordinates.
    static func menuBarStrip(of screen: NSScreen) -> CGRect {
        let h = menuBarHeight(of: screen)
        return CGRect(x: screen.frame.minX, y: screen.frame.maxY - h, width: screen.frame.width, height: h)
    }

    /// The screen whose frame contains an AppKit point.
    static func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }

    static func screen(withDisplayID id: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { displayID(of: $0) == id }
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
    }

    /// Notch span in x (shared by CG and AppKit), or nil when the screen has none.
    static func notchSpan(of screen: NSScreen) -> ClosedRange<CGFloat>? {
        guard let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { return nil }
        return left.maxX...right.minX
    }

    static func isPointerInMenuBar(_ location: CGPoint = NSEvent.mouseLocation) -> NSScreen? {
        guard let screen = screen(containing: location) else { return nil }
        return menuBarStrip(of: screen).contains(location) ? screen : nil
    }
}
