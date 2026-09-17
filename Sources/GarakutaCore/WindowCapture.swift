import CoreGraphics
// SCShareableContent is only marked Sendable in the macOS 26 SDK; older SDKs need the preconcurrency import.
@preconcurrency import ScreenCaptureKit

/// Captures a single window as an image via ScreenCaptureKit (CGWindowListCreateImage is gone in macOS 15).
/// Shareable content is cached briefly because fetching it costs tens of milliseconds.
public actor WindowCapture {
    public static let shared = WindowCapture()

    private var content: SCShareableContent?
    private var contentFetchedAt: Date = .distantPast
    private let contentTTL: TimeInterval = 2

    public var isAvailable: Bool { CGPreflightScreenCaptureAccess() }

    public func window(id: CGWindowID) async -> SCWindow? {
        guard CGPreflightScreenCaptureAccess() else { return nil }
        if content == nil || Date().timeIntervalSince(contentFetchedAt) > contentTTL {
            content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            contentFetchedAt = Date()
        }
        return content?.windows.first { $0.windowID == id }
    }

    public func image(ofWindow id: CGWindowID, maxWidth: CGFloat? = nil, scale: CGFloat = 2) async -> CGImage? {
        guard let window = await window(id: id), window.frame.width > 0, window.frame.height > 0 else { return nil }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        var width = window.frame.width * scale
        var height = window.frame.height * scale
        if let maxWidth, width > maxWidth {
            height *= maxWidth / width
            width = maxWidth
        }
        config.width = Int(width)
        config.height = Int(height)
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        return try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    public func invalidate() {
        content = nil
    }
}
