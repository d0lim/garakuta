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
