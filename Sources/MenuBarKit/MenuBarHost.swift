import Foundation

/// What the menu bar underneath us can do. Two generations matter:
///
/// - Through macOS 26 every status item is its own window and a very long item pushes its neighbours off screen.
///   That is how the hidden sections collapse, so reveal triggers, the auto-arranger and section assignments
///   all build on it.
/// - From macOS 27 the whole menu bar is one window and the system tucks icons that do not fit next to the notch
///   behind its own overflow button. An item cannot push anything off screen any more, and which icons overflow
///   is decided by width and ⌘-drag order alone. Everything that depended on collapsing is switched off there;
///   spacers, groups, the arrange guide and the item menu keep working.
public enum MenuBarHost {
    /// True when the system provides its own overflow handling and our sections cannot collapse.
    /// `GARAKUTA_ASSUME_SYSTEM_OVERFLOW=1` rehearses that mode on an older system.
    public static let systemManagesOverflow: Bool = {
        if ProcessInfo.processInfo.environment["GARAKUTA_ASSUME_SYSTEM_OVERFLOW"] == "1" { return true }
        return ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
    }()

    /// True when our own status items can collapse the sections to their left.
    public static var sectionsCanCollapse: Bool { !systemManagesOverflow }
}
