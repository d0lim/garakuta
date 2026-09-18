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
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else { return nil }
        // Windows on another Space come back as a flat grey rectangle; callers would rather show an icon than that.
        return Self.isFlat(image) ? nil : image
    }

    /// True when the image is (nearly) a single colour, sampled on a coarse grid.
    public static func isFlat(_ image: CGImage) -> Bool {
        let side = 8
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let data = context.data else { return false }
        let pixels = data.bindMemory(to: UInt8.self, capacity: side * side * 4)
        var minimum = [UInt8](repeating: 255, count: 3), maximum = [UInt8](repeating: 0, count: 3)
        for i in 0..<(side * side) {
            for c in 0..<3 {
                let v = pixels[i * 4 + c]
                minimum[c] = min(minimum[c], v)
                maximum[c] = max(maximum[c], v)
            }
        }
        return (0..<3).allSatisfy { Int(maximum[$0]) - Int(minimum[$0]) < 16 }
    }

    public func invalidate() {
        content = nil
    }
}
