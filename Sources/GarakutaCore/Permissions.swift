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

    /// Forgets the system's record of this app for the permission so it can be granted afresh.
    ///
    /// The system ties a grant to the code signature it saw when the app first asked. A copy of the app signed
    /// differently (another build, another install) then shows as switched on in System Settings while the
    /// check still fails. Resetting removes the stale record; the next request registers the running copy.
    @discardableResult
    public func reset() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let service = switch self {
        case .accessibility: "Accessibility"
        case .screenRecording: "ScreenCapture"
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", service, bundleID]
        process.standardOutput = nil
        process.standardError = nil
        do {
            try process.run()
        } catch {
            return false
        }
        process.waitUntilExit()
        return process.terminationStatus == 0
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
