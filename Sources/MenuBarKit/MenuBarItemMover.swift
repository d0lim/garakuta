import AppKit
import CoreGraphics

/// Moves another app's status item by replaying a ⌘-drag. Requires Accessibility (CGEventPost).
/// The cursor is warped back to where it started once the drag finishes.
@MainActor
struct MenuBarItemMover {
    enum MoveError: Error, CustomStringConvertible {
        case accessibilityDenied
        case eventCreationFailed

        var description: String {
            switch self {
            case .accessibilityDenied: "Accessibility permission is required to rearrange menu bar items."
            case .eventCreationFailed: "Could not create mouse events."
            }
        }
    }

    func drag(from start: CGPoint, to end: CGPoint) async throws {
        guard AXIsProcessTrusted() else { throw MoveError.accessibilityDenied }
        let source = CGEventSource(stateID: .hidSystemState)
        let originalCursor = CGEvent(source: nil)?.location ?? start

        func post(_ type: CGEventType, at point: CGPoint) throws {
            guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else {
                throw MoveError.eventCreationFailed
            }
            event.flags = .maskCommand
            event.post(tap: .cghidEventTap)
        }

        try post(.leftMouseDown, at: start)
        try await Task.sleep(for: .milliseconds(60))
        let steps = 8
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let point = CGPoint(x: start.x + (end.x - start.x) * t, y: start.y)
            try post(.leftMouseDragged, at: point)
            try await Task.sleep(for: .milliseconds(25))
        }
        try post(.leftMouseUp, at: end)
        try await Task.sleep(for: .milliseconds(80))
        CGWarpMouseCursorPosition(originalCursor)
    }
}
