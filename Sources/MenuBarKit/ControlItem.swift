import AppKit

/// One of our own status items. The app icon is a normal item; the two separators switch between a short
/// visible length and a very long one that pushes everything to their left off screen.
@MainActor
final class ControlItem {
    enum Kind: String {
        case appIcon
        case hiddenSeparator
        case alwaysHiddenSeparator

        var autosaveName: String { "com.d0lim.garakuta.\(rawValue)" }

        /// "NSStatusItem Preferred Position" is the distance from the right edge of the status area.
        /// Fixing these before the items exist makes macOS lay them out as icon | hidden | always-hidden.
        var defaultPreferredPosition: CGFloat {
            switch self {
            case .appIcon: 0
            case .hiddenSeparator: 1
            case .alwaysHiddenSeparator: 2
            }
        }
    }

    static let expandedLength: CGFloat = 20
    static let collapsedLength: CGFloat = 10_000

    let kind: Kind
    let statusItem: NSStatusItem

    /// Frame in CoreGraphics coordinates. On macOS 26 the status item window is a proxy whose frame AppKit keeps in
    /// sync with the Control Center-hosted item, so it is still usable for layout even though it has no CGWindowID.
    var frame: CGRect? {
        guard let window = statusItem.button?.window, let main = NSScreen.screens.first else { return nil }
        let f = window.frame
        return CGRect(x: f.minX, y: main.frame.maxY - f.maxY, width: f.width, height: f.height)
    }

    /// True when the separator is stretched and the section to its left is pushed off screen.
    private(set) var isCollapsed = false

    init(kind: Kind) {
        self.kind = kind
        Self.seedDefaultsIfNeeded(for: kind)
        statusItem = NSStatusBar.system.statusItem(withLength: Self.expandedLength)
        statusItem.autosaveName = kind.autosaveName
        statusItem.isVisible = true
        statusItem.button?.imagePosition = .imageOnly
    }

    func setCollapsed(_ collapsed: Bool) {
        isCollapsed = collapsed
        statusItem.length = collapsed ? Self.collapsedLength : Self.expandedLength
        // With a 10k-point item the centered image would be far off screen anyway; drop it so the visible
        // tail of the item reads as empty menu bar.
        statusItem.button?.image = collapsed ? nil : separatorImage
    }

    var separatorImage: NSImage? {
        switch kind {
        case .appIcon: AppGlyph.image(accessibilityDescription: "Garakuta")
        case .hiddenSeparator: NSImage(systemSymbolName: "chevron.compact.left", accessibilityDescription: "Hidden items")
        case .alwaysHiddenSeparator: NSImage(systemSymbolName: "chevron.left.2", accessibilityDescription: "Always hidden items")
        }
    }

    func remove() {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private static func seedDefaultsIfNeeded(for kind: Kind) {
        let defaults = UserDefaults.standard
        let positionKey = "NSStatusItem Preferred Position \(kind.autosaveName)"
        if defaults.object(forKey: positionKey) == nil {
            defaults.set(kind.defaultPreferredPosition, forKey: positionKey)
        }
        let visibleKey = "NSStatusItem Visible \(kind.autosaveName)"
        if defaults.object(forKey: visibleKey) == nil {
            defaults.set(true, forKey: visibleKey)
        }
    }
}
