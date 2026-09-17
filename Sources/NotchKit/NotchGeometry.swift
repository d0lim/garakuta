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

    var collapsedSize: CGSize {
        if let notch = geometry.notchWidth {
            return CGSize(width: notch + Self.topEarRadius * 2, height: menuBarHeight)
        }
        return CGSize(width: appearance.pillWidth, height: appearance.pillHeight)
    }

    var compactSize: CGSize {
        let base = collapsedSize
        let side = appearance.sizePreset.compactSideWidth
        return CGSize(width: base.width + side * 2, height: hasNotch ? base.height : base.height + 8)
    }

    var expandedSize: CGSize {
        let s = appearance.sizePreset.expandedSize
        return CGSize(width: max(s.width, compactSize.width), height: s.height + (hasNotch ? menuBarHeight : 0))
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
    var topY: CGFloat {
        hasNotch ? geometry.frame.maxY : geometry.frame.maxY - menuBarHeight - appearance.yOffset
    }

    var centerX: CGFloat { geometry.frame.midX + appearance.xOffset }

    /// Window frame (AppKit coordinates) for a state, anchored top-centre.
    func frame(for state: NotchPanelState) -> CGRect {
        let size = size(for: state)
        return CGRect(x: centerX - size.width / 2, y: topY - size.height, width: size.width, height: size.height)
    }

    /// Area that counts as "hovering the notch" while collapsed/compact.
    func hoverRect(for state: NotchPanelState, padding: CGFloat) -> CGRect {
        frame(for: state == .expanded ? .expanded : (state == .compact ? .compact : .collapsed)).insetBy(dx: -padding, dy: -padding)
    }
}
