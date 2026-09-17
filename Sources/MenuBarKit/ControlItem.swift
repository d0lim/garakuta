import AppKit

/// One of our own status items. The chevron is the button that shows or tucks away the hidden section; the two
/// boundaries switch between a short length and a very long one that pushes everything to their left off screen.
/// The hidden boundary sits right next to the chevron, as narrow as possible and drawing nothing, so the chevron
/// reads as the boundary.
/// (Drawing the chevron at the tail of the long item itself does not work: the menu bar host renders only the
/// centred image of an item, and an image as wide as the item is not rendered at all.)
@MainActor
final class ControlItem {
    enum Kind: String {
        case chevron
        case hiddenSeparator
        case alwaysHiddenSeparator

        /// Autosave names carry the positions users have given the items; the chevron keeps the name of the app
        /// item it replaced so those positions survive.
        var autosaveName: String { "com.d0lim.garakuta.\(self == .chevron ? "appIcon" : rawValue)" }

        /// "NSStatusItem Preferred Position" is the distance from the right edge of the status area.
        /// Fixing these before the items exist makes macOS lay them out as chevron | hidden | always-hidden.
        var defaultPreferredPosition: CGFloat {
            switch self {
            case .chevron: 0
            case .hiddenSeparator: 1
            case .alwaysHiddenSeparator: 2
            }
        }

        var expandedLength: CGFloat {
            switch self {
            case .chevron: 22
            // As narrow as the bar allows: the boundary must stay in the bar (an item that is hidden and shown
            // again loses its place among the others), but it should not read as a gap beside the chevron.
            case .hiddenSeparator: 1
            case .alwaysHiddenSeparator: 18
            }
        }
    }

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
        statusItem = NSStatusBar.system.statusItem(withLength: kind.expandedLength)
        statusItem.autosaveName = kind.autosaveName
        statusItem.isVisible = true
        statusItem.button?.imagePosition = .imageOnly
    }

    func setCollapsed(_ collapsed: Bool) {
        isCollapsed = collapsed
        statusItem.length = collapsed ? Self.collapsedLength : kind.expandedLength
        // With a 10k-point item the centred image would be far off screen anyway; drop it so the visible tail of
        // the item reads as empty menu bar.
        statusItem.button?.image = collapsed || kind != .alwaysHiddenSeparator ? nil
            : Self.dividerImage(bars: 2, accessibilityDescription: "Always hidden items start here")
    }

    /// The chevron points at the hidden items while they are tucked away and flips once they are shown.
    func setChevron(pointingLeft: Bool) {
        let name = pointingLeft ? "chevron.left" : "chevron.right"
        let description = pointingLeft ? "Show hidden menu bar items" : "Hide menu bar items"
        statusItem.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: description)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .bold))
    }

    func remove() {
        NSStatusBar.system.removeStatusItem(statusItem)
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

    private static func seedDefaultsIfNeeded(for kind: Kind) {
        let defaults = UserDefaults.standard
        let positionKey = "NSStatusItem Preferred Position \(kind.autosaveName)"
        if defaults.object(forKey: positionKey) == nil {
            var position = kind.defaultPreferredPosition
            // A chevron placed for the first time goes right next to an existing hidden boundary.
            if kind == .chevron, let boundary = defaults.object(forKey: "NSStatusItem Preferred Position \(Kind.hiddenSeparator.autosaveName)") as? Double {
                position = CGFloat(boundary) - 1
            }
            defaults.set(position, forKey: positionKey)
        }
        let visibleKey = "NSStatusItem Visible \(kind.autosaveName)"
        if defaults.object(forKey: visibleKey) == nil {
            defaults.set(true, forKey: visibleKey)
        }
    }
}
