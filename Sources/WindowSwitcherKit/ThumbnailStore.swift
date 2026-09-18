import AppKit
import CoreGraphics
import GarakutaCore
import PrivateAPIs

/// Window pictures for the tiles. Kept between sessions so the switcher opens with pictures rather than icons,
/// bounded in count and size. Two sources: ScreenCaptureKit for windows on the current Space, and the window
/// server's own capture for minimized windows and windows on other Spaces, which ScreenCaptureKit hands back blank.
@MainActor
final class ThumbnailStore {
    /// Delivered on the main actor whenever a picture arrives.
    var onImage: ((CGWindowID, CGImage) -> Void)?

    private(set) var images: [CGWindowID: CGImage] = [:]
    private var capturedAt: [CGWindowID: Date] = [:]
    /// Windows whose last capture came back empty; retried only occasionally.
    private var failedAt: [CGWindowID: Date] = [:]
    private var inFlight: Set<CGWindowID> = []

    private static let maxInFlight = 8
    private static let maxImages = 80
    private static let failedRetry: TimeInterval = 3

    static var windowServerCaptureAvailable: Bool { GKHWCaptureAvailable() }

    func image(for id: CGWindowID) -> CGImage? { images[id] }
    func age(of id: CGWindowID) -> TimeInterval { capturedAt[id].map { Date().timeIntervalSince($0) } ?? .infinity }
    func isCapturing(_ id: CGWindowID) -> Bool { inFlight.contains(id) }
    var inFlightCount: Int { inFlight.count }
    var hasCapacity: Bool { inFlight.count < Self.maxInFlight }

    /// Whether a capture is worth requesting now: not already running, and not one that just failed.
    func shouldCapture(_ id: CGWindowID, now: Date = Date()) -> Bool {
        if inFlight.contains(id) { return false }
        if let failed = failedAt[id], now.timeIntervalSince(failed) < Self.failedRetry { return false }
        return true
    }

    /// Captures one window scaled to `maxWidth` device pixels. Silent when a capture is already running.
    func capture(_ window: SwitcherWindow, maxWidth: CGFloat) {
        let id = window.windowID
        guard shouldCapture(id), !window.isAppPlaceholder else { return }
        inFlight.insert(id)
        let preferWindowServer = !window.isOnCurrentSpace || window.isMinimized
        Task { [weak self] in
            let image = await Self.captureImage(id: id, maxWidth: maxWidth, preferWindowServer: preferWindowServer)
            await MainActor.run {
                guard let self else { return }
                self.inFlight.remove(id)
                if let image {
                    self.failedAt[id] = nil
                    self.capturedAt[id] = Date()
                    self.images[id] = image
                    self.onImage?(id, image)
                } else {
                    self.failedAt[id] = Date()
                }
            }
        }
    }

    /// Drops pictures of windows that are gone, oldest first when over the limit.
    func prune(keeping ids: Set<CGWindowID>) {
        for id in images.keys where !ids.contains(id) {
            images[id] = nil
            capturedAt[id] = nil
            failedAt[id] = nil
        }
        if images.count > Self.maxImages {
            let victims = capturedAt.sorted { $0.value < $1.value }.prefix(images.count - Self.maxImages).map(\.key)
            for id in victims { images[id] = nil; capturedAt[id] = nil }
        }
    }

    func removeAll() {
        images.removeAll()
        capturedAt.removeAll()
        failedAt.removeAll()
    }

    // MARK: Capture

    /// A window's picture from whichever source can see it, scaled down to `maxWidth` pixels.
    nonisolated static func captureImage(id: CGWindowID, maxWidth: CGFloat, preferWindowServer: Bool) async -> CGImage? {
        if preferWindowServer {
            if let image = await windowServerCapture(id: id, maxWidth: maxWidth) { return image }
            return await WindowCapture.shared.image(ofWindow: id, maxWidth: maxWidth)
        }
        if let image = await WindowCapture.shared.image(ofWindow: id, maxWidth: maxWidth) { return image }
        return await windowServerCapture(id: id, maxWidth: maxWidth)
    }

    /// Full-size picture for the preview: the backing-store resolution, no downscaling.
    nonisolated static func captureFullSize(id: CGWindowID, onCurrentSpace: Bool) async -> CGImage? {
        if onCurrentSpace, let image = await WindowCapture.shared.image(ofWindow: id, maxWidth: nil) { return image }
        return await windowServerCapture(id: id, maxWidth: nil)
    }

    private nonisolated static func windowServerCapture(id: CGWindowID, maxWidth: CGFloat?) async -> CGImage? {
        guard GKHWCaptureAvailable(), CGPreflightScreenCaptureAccess() else { return nil }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let cid = GKMainConnectionID()
                guard let raw = GKHWCaptureWindow(cid, id, maxWidth == nil) else {
                    continuation.resume(returning: nil)
                    return
                }
                let image = maxWidth.map { downscale(raw, maxWidth: $0) } ?? raw
                continuation.resume(returning: WindowCapture.isFlat(image) ? nil : image)
            }
        }
    }

    nonisolated static func downscale(_ image: CGImage, maxWidth: CGFloat) -> CGImage {
        guard CGFloat(image.width) > maxWidth, image.width > 0 else { return image }
        let scale = maxWidth / CGFloat(image.width)
        let width = Int(maxWidth), height = max(1, Int(CGFloat(image.height) * scale))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }
}
