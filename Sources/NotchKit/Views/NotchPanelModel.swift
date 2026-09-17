import AppKit
import GarakutaCore
import SwiftUI

/// Observable state for one display's panel, read by the SwiftUI content.
@MainActor
@Observable
final class NotchPanelModel {
    let displayID: CGDirectDisplayID
    var layout: NotchLayout
    var settings: NotchSettings
    var state: NotchPanelState = .collapsed
    var page = 0
    var isHovering = false
    var isDragTarget = false
    /// True while the menu bar module's secondary bar is open on this display (N08).
    var suspended = false
    /// Set by N06 rules: expansion is not allowed (compact-only full-screen rule).
    var expansionBlocked = false

    var onTap: (() -> Void)?

    /// Width of each side area in the compact state, following the widest content the activity draws (see
    /// `NotchContentView.compactRow`). Changing it resizes the window through `onCompactSideChange`.
    private(set) var compactSide: CGFloat = NotchLayout.minimumCompactSide
    private var compactContentWidths: [Bool: CGFloat] = [:]
    var onCompactSideChange: (() -> Void)?

    /// Called by the compact row with the measured width of one side (leading or trailing).
    func reportCompactContent(width: CGFloat, leading: Bool) {
        compactContentWidths[leading] = width
        let side = NotchLayout.compactSide(forContentWidth: compactContentWidths.values.max() ?? 0)
        guard abs(side - compactSide) > 0.5 else { return }
        compactSide = side
        onCompactSideChange?()
    }

    init(displayID: CGDirectDisplayID, layout: NotchLayout, settings: NotchSettings) {
        self.displayID = displayID
        self.layout = layout
        self.settings = settings
    }

    var appearance: NotchSettings.Appearance { layout.appearance }

    var spring: Animation {
        let speed = max(0.25, appearance.animationSpeed)
        return .spring(response: 0.38 / speed, dampingFraction: 0.82)
    }
}
