import AppKit
import GarakutaCore

/// Panel state machine states.
public enum NotchPanelState: Sendable, Equatable {
    case collapsed
    case compact
    case expanded
}

/// Sizes and positions for one display, derived from its geometry and the resolved appearance.
struct NotchLayout: Equatable {
    static let topEarRadius: CGFloat = 6

    let geometry: DisplayGeometry
    let appearance: NotchSettings.Appearance
    let menuBarHeight: CGFloat

    init(geometry: DisplayGeometry, appearance: NotchSettings.Appearance) {
        self.geometry = geometry
        self.appearance = appearance
        // Secondary displays report a zero-height menu bar through visibleFrame; fall back to the status bar.
        menuBarHeight = geometry.menuBarHeight > 1 ? geometry.menuBarHeight : max(NSStatusBar.system.thickness, 24)
    }

    var hasNotch: Bool { geometry.hasNotch }

    /// The island sits inside the menu bar of a display without a notch.
    var islandInMenuBar: Bool { !hasNotch && appearance.islandPlacement == .menuBar }

    /// The panel hangs from the top edge of the screen and covers the menu bar while expanded.
    var coversMenuBar: Bool { hasNotch || islandInMenuBar }

    var collapsedSize: CGSize {
        if let notch = geometry.notchWidth {
            return CGSize(width: notch + Self.topEarRadius * 2, height: menuBarHeight)
        }
        // Inside the menu bar the pill keeps a small margin above and below.
        let height = islandInMenuBar ? min(appearance.pillHeight, menuBarHeight - 4) : appearance.pillHeight
        return CGSize(width: appearance.pillWidth, height: height)
    }

    var compactSize: CGSize {
        let base = collapsedSize
        let side = appearance.sizePreset.compactSideWidth
        return CGSize(width: base.width + side * 2, height: coversMenuBar ? base.height : base.height + 8)
    }

    var expandedSize: CGSize {
        let s = appearance.sizePreset.expandedSize
        return CGSize(width: max(s.width, compactSize.width), height: s.height + (coversMenuBar ? menuBarHeight : 0))
    }

    /// Width available to widget pages inside the expanded panel.
    var widgetPageWidth: CGFloat { expandedSize.width - 24 }

    func size(for state: NotchPanelState) -> CGSize {
        switch state {
        case .collapsed: collapsedSize
        case .compact: compactSize
        case .expanded: expandedSize
        }
    }

    /// Top edge of the panel in AppKit screen coordinates.
    func topY(for state: NotchPanelState) -> CGFloat {
        if hasNotch { return geometry.frame.maxY }
        if islandInMenuBar {
            // Collapsed and compact pills are centred in the menu bar; the expanded panel grows from the top edge.
            return state == .expanded ? geometry.frame.maxY : geometry.frame.maxY - (menuBarHeight - collapsedSize.height) / 2
        }
        return geometry.frame.maxY - menuBarHeight - appearance.yOffset
    }

    var centerX: CGFloat { geometry.frame.midX + appearance.xOffset }

    /// Window frame (AppKit coordinates) for a state, anchored top-centre.
    func frame(for state: NotchPanelState) -> CGRect {
        let size = size(for: state)
        return CGRect(x: centerX - size.width / 2, y: topY(for: state) - size.height, width: size.width, height: size.height)
    }

    /// Area that counts as "hovering the notch" while collapsed/compact.
    func hoverRect(for state: NotchPanelState, padding: CGFloat) -> CGRect {
        frame(for: state == .expanded ? .expanded : (state == .compact ? .compact : .collapsed)).insetBy(dx: -padding, dy: -padding)
    }
}
