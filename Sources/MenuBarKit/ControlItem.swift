import AppKit

/// One of our own status items. The main item is a chevron that reveals or hides the sections; the two separators
/// switch between a short visible length and a very long one that pushes everything to their left off screen.
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

    /// The main item points at the hidden items while they are tucked away and flips once they are shown.
    func setChevron(pointingLeft: Bool) {
        let name = pointingLeft ? "chevron.left" : "chevron.right"
        let description = pointingLeft ? "Show hidden menu bar items" : "Hide menu bar items"
        statusItem.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: description)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .bold))
    }

    var separatorImage: NSImage? {
        switch kind {
        case .appIcon: nil
        case .hiddenSeparator: Self.dividerImage(bars: 1, accessibilityDescription: "Hidden items start here")
        case .alwaysHiddenSeparator: Self.dividerImage(bars: 2, accessibilityDescription: "Always hidden items start here")
        }
    }

    /// Thin vertical bars marking where a section starts, drawn as a template so they follow the menu bar tint.
    private static func dividerImage(bars: Int, accessibilityDescription: String) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            let barWidth: CGFloat = 2, gap: CGFloat = 3, height: CGFloat = 12
            let total = CGFloat(bars) * barWidth + CGFloat(bars - 1) * gap
            var x = (size.width - total) / 2
            NSColor.black.setFill()
            for _ in 0..<bars {
                NSBezierPath(roundedRect: NSRect(x: x, y: (size.height - height) / 2, width: barWidth, height: height), xRadius: 1, yRadius: 1).fill()
                x += barWidth + gap
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = accessibilityDescription
        return image
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
