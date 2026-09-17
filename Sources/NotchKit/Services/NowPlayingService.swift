import AppKit
import Foundation

/// Polls Music and Spotify through AppleScript while enabled. MediaRemote is not used because macOS 15.4+
/// requires an entitlement for it. Scripts are only compiled for players that are currently running, which
/// avoids the "Where is Spotify?" dialog on Macs without that app. Needs Automation permission on first use.
@MainActor
@Observable
public final class NowPlayingService {
    public enum Player: String, Sendable, CaseIterable {
        case music = "Music"
        case spotify = "Spotify"

        var bundleIdentifier: String {
            switch self {
            case .music: "com.apple.Music"
            case .spotify: "com.spotify.client"
            }
        }
    }

    public struct Track: Equatable, Sendable {
        public var player: Player
        public var isPlaying: Bool
        public var title: String
        public var artist: String
        public var album: String
        public var position: TimeInterval
        public var duration: TimeInterval
        public var artworkURL: URL?
    }

    public private(set) var track: Track?
    public private(set) var artwork: NSImage?
    public var isEnabled = false { didSet { isEnabled ? startPolling() : stopPolling() } }
    var onChange: (() -> Void)?

    private var timer: Timer?
    private var artworkTask: Task<Void, Never>?
    private var lastArtworkURL: URL?
    /// One poll at a time; a hung player or the first Automation consent dialog must not stack requests.
    private var pollInFlight = false
    private let executor = AppleScriptExecutor()

    public init() {}

    private func startPolling() {
        guard timer == nil else { return }
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in NotchServices.shared.nowPlaying.poll() }
        }
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    private func isRunning(_ player: Player) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleIdentifier).isEmpty
    }

    func poll() {
        guard !pollInFlight else { return }
        let running = Player.allCases.filter { isRunning($0) }
        guard !running.isEmpty else {
            if track != nil { publish(nil) }
            return
        }
        pollInFlight = true
        let executor = self.executor
        Task { @MainActor [weak self] in
            var found: Track?
            for player in running {
                let output = await executor.run(Self.source(for: player), cacheKey: player.rawValue)
                if let output, let t = Self.parse(output, player: player) {
                    // Prefer whichever is actually playing.
                    if found == nil || (t.isPlaying && found?.isPlaying == false) { found = t }
                }
            }
            guard let self else { return }
            pollInFlight = false
            if found != track { publish(found) }
        }
    }

    private func publish(_ new: Track?) {
        track = new
        updateArtwork()
        onChange?()
    }

    private static func parse(_ result: String, player: Player) -> Track? {
        guard result != "stopped" else { return nil }
        let parts = result.components(separatedBy: "|")
        guard parts.count >= 6 else { return nil }
        func number(_ s: String) -> TimeInterval { TimeInterval(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }
        let artwork = parts.count > 6 ? URL(string: parts[6...].joined(separator: "|")) : nil
        return Track(player: player, isPlaying: parts[0] == "playing", title: parts[1], artist: parts[2], album: parts[3],
                     position: number(parts[4]), duration: number(parts[5]), artworkURL: artwork)
    }

    private static func source(for player: Player) -> String {
        switch player {
        case .music:
            return """
            tell application "Music"
                set st to (player state as string)
                if st is "playing" or st is "paused" then
                    set t to current track
                    return st & "|" & (name of t) & "|" & (artist of t) & "|" & (album of t) & "|" & (player position as string) & "|" & (duration of t as string)
                end if
                return "stopped"
            end tell
            """
        case .spotify:
            return """
            tell application "Spotify"
                set st to (player state as string)
                if st is "playing" or st is "paused" then
                    set t to current track
                    return st & "|" & (name of t) & "|" & (artist of t) & "|" & (album of t) & "|" & (player position as string) & "|" & (((duration of t) / 1000) as string) & "|" & (artwork url of t)
                end if
                return "stopped"
            end tell
            """
        }
    }

    private func updateArtwork() {
        guard let url = track?.artworkURL else {
            artwork = nil
            lastArtworkURL = nil
            return
        }
        guard url != lastArtworkURL else { return }
        lastArtworkURL = url
        artworkTask?.cancel()
        artworkTask = Task { @MainActor [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url), !Task.isCancelled else { return }
            self?.artwork = NSImage(data: data)
        }
    }

    // MARK: Controls

    public func playPause() { control("playpause") }
    public func next() { control("next track") }
    public func previous() { control("previous track") }

    private func control(_ command: String) {
        guard let player = track?.player, isRunning(player) else { return }
        let executor = self.executor
        Task { @MainActor [weak self] in
            _ = await executor.run("tell application \"\(player.rawValue)\" to \(command)", cacheKey: nil)
            try? await Task.sleep(for: .milliseconds(300))
            self?.poll()
        }
    }
}

/// Runs AppleScript on a dedicated serial queue so a slow or consent-blocked player never stalls the UI.
/// NSAppleScript objects are created and used only on that queue.
final class AppleScriptExecutor: Sendable {
    private let queue = DispatchQueue(label: "com.d0lim.garakuta.applescript", qos: .utility)
    private nonisolated(unsafe) var cache: [String: NSAppleScript] = [:]

    func run(_ source: String, cacheKey: String?) async -> String? {
        await withCheckedContinuation { continuation in
            queue.async {
                let script: NSAppleScript
                if let cacheKey, let cached = self.cache[cacheKey] {
                    script = cached
                } else {
                    guard let fresh = NSAppleScript(source: source) else {
                        continuation.resume(returning: nil)
                        return
                    }
                    if let cacheKey { self.cache[cacheKey] = fresh }
                    script = fresh
                }
                var error: NSDictionary?
                let result = script.executeAndReturnError(&error).stringValue
                continuation.resume(returning: error == nil ? result : nil)
            }
        }
    }
}
