import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Borderless non-activating panel that receives key events (so typing filters and modifier release works)
/// without stealing activation from the frontmost app.
@MainActor
final class SwitcherPanel: NSPanel {
    var onKeyDown: ((NSEvent) -> Bool)?
    var onFlagsChanged: ((NSEvent) -> Void)?
    var onMiddleClick: (() -> Void)?

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

    override func flagsChanged(with event: NSEvent) {
        onFlagsChanged?(event)
        super.flagsChanged(with: event)
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
