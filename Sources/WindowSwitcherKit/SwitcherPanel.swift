import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Borderless non-activating panel that receives key events (so typing filters and modifier release works)
/// without stealing activation from the frontmost app.
@MainActor
final class SwitcherPanel: NSPanel {
    var onKeyDown: ((NSEvent) -> Bool)?
    var onKeyUp: ((NSEvent) -> Void)?
    var onFlagsChanged: ((NSEvent) -> Void)?
    var onMiddleClick: (() -> Void)?
    /// Scroll wheel steps that reached the panel itself (outside the grid's own scrolling); positive is forward.
    var onScroll: ((CGFloat) -> Void)?
    private var scrollAccumulator: CGFloat = 0

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) != true { super.keyDown(with: event) }
    }

    override func keyUp(with event: NSEvent) {
        onKeyUp?(event)
        super.keyUp(with: event)
    }

    override func flagsChanged(with event: NSEvent) {
        onFlagsChanged?(event)
        super.flagsChanged(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        // Horizontal scrolling walks the selection; vertical scrolling is left to the grid.
        guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { super.scrollWheel(with: event); return }
        scrollAccumulator += event.scrollingDeltaX
        if abs(scrollAccumulator) >= 24 {
            onScroll?(scrollAccumulator < 0 ? 1 : -1)
            scrollAccumulator = 0
        }
    }

    override func otherMouseUp(with event: NSEvent) {
        if event.buttonNumber == 2 { onMiddleClick?() } else { super.otherMouseUp(with: event) }
    }

    override func cancelOperation(_ sender: Any?) {
        _ = onKeyDown?(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: windowNumber,
                                        context: nil, characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", isARepeat: false,
                                        keyCode: UInt16(kVK_Escape))!)
    }
}
