import Foundation

/// Shared services used by widgets and live activities across all displays.
@MainActor
public final class NotchServices {
    public static let shared = NotchServices()

    public let nowPlaying = NowPlayingService()
    public let timer = TimerService()
    public let battery = BatteryService()
    public let shelf = ShelfStore()
    let capture = CaptureDetector()

    private init() {}

    func start() {
        battery.start()
        capture.start()
    }

    func stop() {
        nowPlaying.isEnabled = false
        battery.stop()
        capture.stop()
    }
}
