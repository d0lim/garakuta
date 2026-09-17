import ApplicationServices
import CoreGraphics
import Foundation
@preconcurrency import ScreenCaptureKit

/// TCC permissions the selected features depend on. Requested only when a feature that needs them is enabled.
public enum Permission: String, CaseIterable, Sendable {
    case accessibility
    case screenRecording

    public var isGranted: Bool {
        switch self {
        case .accessibility: AXIsProcessTrusted()
        case .screenRecording: CGPreflightScreenCaptureAccess() || Self.screenRecordingProbeSucceeded
        }
    }

    /// The preflight check does not notice a Screen Recording grant made while the app is running; asking the
    /// capture framework for its window list does. Remembered once it succeeds.
    nonisolated(unsafe) private static var screenRecordingProbeSucceeded = false
    nonisolated(unsafe) private static var screenRecordingProbeInFlight = false

    /// Asks the capture framework whether it will serve us. Cheap enough to call from a settings poll; it does
    /// nothing while a previous probe is still running or once the permission is known to be granted.
    public static func probeScreenRecording() async -> Bool {
        if CGPreflightScreenCaptureAccess() || screenRecordingProbeSucceeded { return true }
        guard !screenRecordingProbeInFlight else { return false }
        screenRecordingProbeInFlight = true
        defer { screenRecordingProbeInFlight = false }
        let granted = (try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)) != nil
        if granted { screenRecordingProbeSucceeded = true }
        return granted
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
