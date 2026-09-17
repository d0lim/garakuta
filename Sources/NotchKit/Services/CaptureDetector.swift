import AppKit

/// Best-effort detection of an active screen recording or share (N07 auto-hide).
///
/// macOS offers no public "someone is capturing the screen" signal. Without Screen Recording permission we
/// cannot read other windows' titles either, so this only checks for well-known capture processes. The reliable
/// half of N07 is `NSWindow.sharingType = .none`, which excludes the panel from captures regardless.
@MainActor
final class CaptureDetector {
    private static let captureBundleIDs: Set<String> = [
        "com.apple.screencaptureui",          // built-in screenshot / recording toolbar
        "com.obsproject.obs-studio",
        "com.loom.desktop",
        "com.techsmith.snagit",
    ]

    private(set) var isCapturing = false
    var onChange: ((Bool) -> Void)?
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in NotchServices.shared.capture.refresh() }
        }
        refresh()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func refresh() {
        let running = NSWorkspace.shared.runningApplications.contains {
            guard let id = $0.bundleIdentifier else { return false }
            return Self.captureBundleIDs.contains(id)
        }
        if running != isCapturing {
            isCapturing = running
            onChange?(running)
        }
    }
}
