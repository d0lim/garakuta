import ApplicationServices
import CoreGraphics
import Foundation

/// TCC permissions the selected features depend on. Requested only when a feature that needs them is enabled.
public enum Permission: String, CaseIterable, Sendable {
    case accessibility
    case screenRecording

    public var isGranted: Bool {
        switch self {
        case .accessibility: AXIsProcessTrusted()
        case .screenRecording: CGPreflightScreenCaptureAccess()
        }
    }

    /// Opens the system prompt. Returns the state after the request; the user may still need to relaunch.
    @discardableResult
    public func request() -> Bool {
        switch self {
        case .accessibility:
            // Literal key: the kAXTrustedCheckOptionPrompt global is not concurrency-safe under Swift 6.
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        case .screenRecording:
            return CGRequestScreenCaptureAccess()
        }
    }
}
