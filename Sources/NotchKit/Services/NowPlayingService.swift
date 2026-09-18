import AppKit
import Foundation

/// What the system says is playing, from any app that publishes to the system's now-playing service: Music,
/// Spotify, browsers, podcast and video players alike.
///
/// The service refuses calls from processes Apple has not signed, so the app does not talk to it directly. A small
/// helper library (Sources/NowPlayingBridge) is loaded into the system perl interpreter, which the service does
/// answer, and streams changes back over a pipe. When the helper cannot run, the older Apple Events polling of
/// Music and Spotify takes over; it needs Automation permission on first use.
@MainActor
@Observable
public final class NowPlayingService {
    public struct Track: Equatable, Sendable {
        /// Name of the app playing, for display.
        public var sourceName: String
        public var bundleIdentifier: String?
        public var isPlaying: Bool
        public var title: String
        public var artist: String
        public var album: String
        public var duration: TimeInterval
        /// Progress as the source last reported it, at `reportedAt`, advancing at `playbackRate`.
        public var reportedElapsed: TimeInterval
        public var reportedAt: Date
        public var playbackRate: Double
        /// Changes whenever the artwork does; the image itself lives in `NowPlayingService.artwork`.
        var artworkKey: String?

        /// Current playback position, extrapolated from the last report while playing.
        public var position: TimeInterval {
            let elapsed = isPlaying ? reportedElapsed + Date().timeIntervalSince(reportedAt) * playbackRate : reportedElapsed
            return duration > 0 ? min(max(elapsed, 0), duration) : max(elapsed, 0)
        }

        public var displayTitle: String { title.isEmpty ? sourceName : title }
    }

    public private(set) var track: Track?
    public private(set) var artwork: NSImage?
    public var isEnabled = false { didSet { isEnabled ? start() : stop() } }
    var onChange: (() -> Void)?

    /// How long a paused item keeps its live activity before it is considered finished with.
    static let pausedActivityLifetime: TimeInterval = 5 * 60
    private var pausedAt: Date?
    private var pauseExpiry: Task<Void, Never>?

    private let bridge = NowPlayingBridgeClient()
    private var usingBridge = false

    // Browser tab titles, standing in for metadata the service withholds for browsers.
    private var browserPick: BrowserTabTitles.Pick?
    private var browserTitleTimer: Timer?
    private var browserTitleInFlight = false
    private var lastBridgeRecord: NowPlayingBridgeClient.Record?

    // Apple Events fallback
    private var pollTimer: Timer?
    private var pollInFlight = false
    private var artworkTask: Task<Void, Never>?
    /// Item whose artwork the helper's artwork mode was last asked for; asked once per item.
    private var artworkFetchKey: String?
    private var lastArtworkURL: URL?
    private let executor = AppleScriptExecutor()

    public init() {
        bridge.onRecord = { [weak self] record in self?.apply(record) }
        bridge.onStop = { [weak self] in
            // The helper died and is not coming back: fall back to polling so music still shows up.
            guard let self, isEnabled, usingBridge else { return }
            usingBridge = false
            startPolling()
        }
    }

    /// True when a live activity should be shown: playing, or paused only recently.
    public var isActive: Bool {
        guard let track else { return false }
        if track.isPlaying { return true }
        guard let pausedAt else { return true }
        return Date().timeIntervalSince(pausedAt) < Self.pausedActivityLifetime
    }

    private func start() {
        if bridge.isAvailable, bridge.start() {
            usingBridge = true
        } else {
            usingBridge = false
            startPolling()
        }
    }

    private func stop() {
        bridge.stop()
        usingBridge = false
        stopPolling()
        stopBrowserTitles()
        publish(nil)
    }

    // MARK: Controls

    public func playPause() { command(.togglePlayPause, script: "playpause") }
    public func next() { command(.nextTrack, script: "next track") }
    public func previous() { command(.previousTrack, script: "previous track") }

    private func command(_ command: NowPlayingBridgeClient.Command, script: String) {
        if usingBridge {
            bridge.send(command)
            return
        }
        guard let player = track.flatMap({ ScriptedPlayer(bundleIdentifier: $0.bundleIdentifier) }), player.isRunning else { return }
        let executor = self.executor
        Task { @MainActor [weak self] in
            _ = await executor.run("tell application \"\(player.rawValue)\" to \(script)", cacheKey: nil)
            try? await Task.sleep(for: .milliseconds(300))
            self?.poll()
        }
    }

    // MARK: Publishing

    private func publish(_ new: Track?) {
        let old = track
        track = new
        if let new, let old, new.isPlaying != old.isPlaying || new.title != old.title {
            pausedAt = new.isPlaying ? nil : Date()
        } else if let new, old == nil {
            pausedAt = new.isPlaying ? nil : Date()
        } else if new == nil {
            pausedAt = nil
        }
        schedulePauseExpiry()
        onChange?()
    }

    private func schedulePauseExpiry() {
        pauseExpiry?.cancel()
        guard pausedAt != nil else { return }
        pauseExpiry = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.pausedActivityLifetime + 1))
            guard !Task.isCancelled else { return }
            self?.onChange?()
        }
    }

    // MARK: Bridge records

    private func apply(_ record: NowPlayingBridgeClient.Record) {
        lastBridgeRecord = record
        let info = record.info
        guard !info.isEmpty || record.pid > 0 else {
            stopBrowserTitles()
            if track != nil { artwork = nil; publish(nil) }
            return
        }
        // The pid the service names may be a helper process (browsers); the bundle identifier finds the app then.
        let app = (record.pid > 0 ? NSRunningApplication(processIdentifier: pid_t(record.pid)) : nil)
            ?? record.bundle.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first }
        func string(_ key: String) -> String { info["kMRMediaRemoteNowPlayingInfo\(key)"] as? String ?? "" }
        func number(_ key: String) -> Double? { (info["kMRMediaRemoteNowPlayingInfo\(key)"] as? NSNumber)?.doubleValue }
        var title = string("Title")
        var artist = string("Artist")
        let browser = BrowserTabTitles.isBrowser(app?.bundleIdentifier ?? record.bundle)
        if browser, title.isEmpty {
            if let pick = browserPick {
                title = pick.title
                artist = pick.artist
            }
            startBrowserTitles(bundleIdentifier: app?.bundleIdentifier ?? "")
        } else {
            stopBrowserTitles()
        }
        // A source that has registered but has nothing loaded reports neither a title nor a duration. A browser
        // shows up as soon as it plays; its tab title follows a moment later.
        guard !title.isEmpty || (number("Duration") ?? 0) > 0 || (browser && record.playing) else {
            if track != nil { artwork = nil; publish(nil) }
            return
        }
        let rate = number("PlaybackRate") ?? (record.playing ? 1 : 0)
        // The item's live position is right the moment the playback state changes; the reported elapsed time and
        // its timestamp only catch up a beat later, and extrapolating from that pair in between rewinds the bar.
        var elapsed = record.position ?? number("ElapsedTime") ?? 0
        var elapsedAt = record.position != nil ? record.parsedAt : (info["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date ?? Date())
        // A position that agrees with where the bar already is keeps the existing anchor, so the steady stream of
        // position reports neither restarts the extrapolation nor counts as a change worth publishing.
        if let current = track, current.isPlaying == record.playing, current.title == title,
           abs(current.position - elapsed) < 2 {
            elapsed = current.reportedElapsed
            elapsedAt = current.reportedAt
        }
        let artworkData = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data
        let artworkKey = string("ArtworkIdentifier").nilIfEmpty ?? string("ContentItemIdentifier").nilIfEmpty
            ?? artworkData.map { "\($0.count)" }
        let new = Track(sourceName: app?.localizedName ?? "Now Playing", bundleIdentifier: app?.bundleIdentifier,
                        isPlaying: record.playing, title: title, artist: artist, album: string("Album"),
                        duration: number("Duration") ?? 0, reportedElapsed: elapsed, reportedAt: elapsedAt,
                        playbackRate: record.playing ? (rate > 0 ? rate : 1) : 0, artworkKey: artworkKey)
        if let artworkData, !artworkData.isEmpty, artworkKey != track?.artworkKey || artwork == nil {
            artwork = NSImage(data: artworkData)
        } else if artworkData == nil && artworkKey != track?.artworkKey {
            artwork = nil
        }
        if new != track { publish(new) }
        // The direct read carries no artwork bytes; a separate helper process asks the callback query once per
        // item. Browsers never answer it and the process simply times out.
        if artworkData == nil, let artworkKey, artworkKey != artworkFetchKey {
            artworkFetchKey = artworkKey
            bridge.fetchArtwork { [weak self] data, key in
                guard let self, let data, !data.isEmpty, key == nil || key == self.track?.artworkKey else { return }
                self.artwork = NSImage(data: data)
                self.onChange?()
            }
        }
    }

    // MARK: Browser tab titles

    private func startBrowserTitles(bundleIdentifier: String) {
        guard browserTitleTimer == nil else { return }
        refreshBrowserTitle(bundleIdentifier: bundleIdentifier)
        browserTitleTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in NotchServices.shared.nowPlaying.refreshBrowserTitle(bundleIdentifier: bundleIdentifier) }
        }
    }

    private func stopBrowserTitles() {
        browserTitleTimer?.invalidate()
        browserTitleTimer = nil
        browserPick = nil
    }

    private func refreshBrowserTitle(bundleIdentifier: String) {
        guard !browserTitleInFlight, let source = BrowserTabTitles.script(for: bundleIdentifier) else { return }
        browserTitleInFlight = true
        let executor = self.executor
        Task { @MainActor [weak self] in
            let output = await executor.run(source, cacheKey: "tabs:\(bundleIdentifier)")
            guard let self else { return }
            browserTitleInFlight = false
            if output == nil { NSLog("browser tab titles unavailable for %@ (Automation permission?)", bundleIdentifier) }
            let pick = output.flatMap { BrowserTabTitles.pick(from: $0) }
            guard pick != browserPick else { return }
            browserPick = pick
            if let record = lastBridgeRecord { apply(record) }
        }
    }

    // MARK: Apple Events fallback (Music and Spotify)

    enum ScriptedPlayer: String, CaseIterable {
        case music = "Music"
        case spotify = "Spotify"

        var bundleIdentifier: String {
            switch self {
            case .music: "com.apple.Music"
            case .spotify: "com.spotify.client"
            }
        }

        init?(bundleIdentifier: String?) {
            guard let match = Self.allCases.first(where: { $0.bundleIdentifier == bundleIdentifier }) else { return nil }
            self = match
        }

        @MainActor var isRunning: Bool {
            !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
        }
    }

    private func startPolling() {
        guard pollTimer == nil else { return }
        poll()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in NotchServices.shared.nowPlaying.poll() }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        artworkTask?.cancel()
        lastArtworkURL = nil
    }

    /// Scripts are only compiled for players that are running, which avoids "Where is Spotify?" dialogs on Macs
    /// without that app. One poll at a time: a hung player or the first consent dialog must not stack requests.
    func poll() {
        guard !usingBridge, !pollInFlight else { return }
        let running = ScriptedPlayer.allCases.filter { $0.isRunning }
        guard !running.isEmpty else {
            if track != nil { artwork = nil; publish(nil) }
            return
        }
        pollInFlight = true
        let executor = self.executor
        Task { @MainActor [weak self] in
            var found: (Track, URL?)?
            for player in running {
                let output = await executor.run(Self.source(for: player), cacheKey: player.rawValue)
                if let output, let parsed = Self.parse(output, player: player) {
                    if found == nil || (parsed.0.isPlaying && found?.0.isPlaying == false) { found = parsed }
                }
            }
            guard let self else { return }
            pollInFlight = false
            if let found {
                updateArtwork(from: found.1)
                if found.0 != track { publish(found.0) }
            } else if track != nil {
                updateArtwork(from: nil)
                publish(nil)
            }
        }
    }

    private static func parse(_ result: String, player: ScriptedPlayer) -> (Track, URL?)? {
        guard result != "stopped" else { return nil }
        let parts = result.components(separatedBy: "|")
        guard parts.count >= 6 else { return nil }
        func number(_ s: String) -> TimeInterval { TimeInterval(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }
        let artworkURL = parts.count > 6 ? URL(string: parts[6...].joined(separator: "|")) : nil
        let playing = parts[0] == "playing"
        let track = Track(sourceName: player.rawValue, bundleIdentifier: player.bundleIdentifier, isPlaying: playing,
                          title: parts[1], artist: parts[2], album: parts[3], duration: number(parts[5]),
                          reportedElapsed: number(parts[4]), reportedAt: Date(), playbackRate: playing ? 1 : 0,
                          artworkKey: artworkURL?.absoluteString)
        return (track, artworkURL)
    }

    private static func source(for player: ScriptedPlayer) -> String {
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

    private func updateArtwork(from url: URL?) {
        guard let url else {
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
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// Runs the now-playing helper (Resources/nowplaying.pl + libNowPlayingBridge.dylib) inside the system perl
/// interpreter and parses the records it streams. See Sources/NowPlayingBridge for the protocol.
final class NowPlayingBridgeClient: @unchecked Sendable {
    /// One helper record. `info` holds property-list values only (strings, numbers, dates, data), which are safe to
    /// hand across threads even though the type system cannot see that.
    struct Record: @unchecked Sendable {
        var info: [String: Any]
        var playing: Bool
        var pid: Int
        /// Bundle identifier of the playing app when the helper could name it (macOS 15.4 and later).
        var bundle: String?
        /// The item's own live position in seconds, when the helper could read it, and when it was parsed.
        /// Preferred over the elapsed-time-plus-timestamp pair, which lags a playback-state change by a moment.
        var position: TimeInterval?
        var parsedAt = Date()
    }

    enum Command: Int {
        case play = 0, pause = 1, togglePlayPause = 2, stop = 3, nextTrack = 4, previousTrack = 5
    }

    @MainActor var onRecord: ((Record) -> Void)?
    /// Called once the helper has failed repeatedly and restarts have been given up.
    @MainActor var onStop: (() -> Void)?

    nonisolated init() {}

    private static let interpreter = URL(fileURLWithPath: "/usr/bin/perl")
    private let script = Bundle.main.url(forResource: "nowplaying", withExtension: "pl")
    private let library = Bundle.main.privateFrameworksURL?.appendingPathComponent("libNowPlayingBridge.dylib")

    private let lock = NSLock()
    private var process: Process?
    private var buffer = Data()
    private var wanted = false
    private var failures = 0

    var isAvailable: Bool {
        guard let script, let library else { return false }
        let fm = FileManager.default
        return fm.isExecutableFile(atPath: Self.interpreter.path) && fm.fileExists(atPath: script.path) && fm.fileExists(atPath: library.path)
    }

    /// Starts streaming. Returns false when the helper could not be launched at all.
    @MainActor
    @discardableResult
    func start() -> Bool {
        lock.lock(); wanted = true; failures = 0; lock.unlock()
        return launch()
    }

    func stop() {
        lock.lock()
        wanted = false
        let running = process
        process = nil
        lock.unlock()
        running?.terminate()
    }

    private func launch() -> Bool {
        guard let script, let library else { return false }
        let process = Process()
        process.executableURL = Self.interpreter
        process.arguments = [script.path, library.path]
        var env = ProcessInfo.processInfo.environment
        env["GARAKUTA_NOW_PLAYING_MODE"] = "stream"
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.standardError
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            self?.consume(data)
        }
        process.terminationHandler = { [weak self] _ in
            pipe.fileHandleForReading.readabilityHandler = nil
            self?.processEnded()
        }
        do {
            try process.run()
        } catch {
            NSLog("now-playing helper failed to start: %@", String(describing: error))
            return false
        }
        lock.lock()
        self.process = process
        buffer.removeAll()
        lock.unlock()
        return true
    }

    private func processEnded() {
        lock.lock()
        process = nil
        let restart = wanted
        failures += 1
        let attempt = failures
        lock.unlock()
        guard restart else { return }
        // A helper that exits within seconds of starting is broken; stop retrying after a few attempts.
        guard attempt <= 5 else {
            NSLog("now-playing helper keeps exiting; giving up")
            Task { @MainActor in self.onStop?() }
            return
        }
        let delay = Double(attempt) * 2
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            lock.lock(); let stillWanted = wanted; lock.unlock()
            if stillWanted { _ = launch() }
        }
    }

    private func consume(_ data: Data) {
        lock.lock()
        buffer.append(data)
        var lines: [Data] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            lines.append(buffer.subdata(in: buffer.startIndex..<newline))
            buffer.removeSubrange(buffer.startIndex...newline)
        }
        if lines.count > 0 { failures = 0 }
        lock.unlock()
        for line in lines {
            guard let plist = Data(base64Encoded: line),
                  let object = try? PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any]
            else { continue }
            let record = Record(info: object["info"] as? [String: Any] ?? [:],
                                playing: (object["playing"] as? Bool) ?? false,
                                pid: (object["pid"] as? Int) ?? 0,
                                bundle: object["bundle"] as? String,
                                position: (object["position"] as? NSNumber)?.doubleValue)
            Task { @MainActor in self.onRecord?(record) }
        }
    }

    /// Fetches the current item's artwork through a short-lived helper process running the callback query, which
    /// only players outside browsers answer. Delivers the bytes and the item they belong to, or nil on a timeout.
    func fetchArtwork(_ completion: @escaping @MainActor (Data?, String?) -> Void) {
        guard let script, let library else { Task { @MainActor in completion(nil, nil) }; return }
        let process = Process()
        process.executableURL = Self.interpreter
        process.arguments = [script.path, library.path]
        var env = ProcessInfo.processInfo.environment
        env["GARAKUTA_NOW_PLAYING_MODE"] = "artwork"
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = nil
        process.terminationHandler = { _ in
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            var data: Data?
            var key: String?
            for line in output.split(separator: 0x0A) {
                guard let plist = Data(base64Encoded: Data(line)),
                      let object = try? PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any],
                      let info = object["info"] as? [String: Any] else { continue }
                data = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data
                key = (info["kMRMediaRemoteNowPlayingInfoArtworkIdentifier"] as? String)
                    ?? (info["kMRMediaRemoteNowPlayingInfoContentItemIdentifier"] as? String)
            }
            Task { @MainActor in completion(data, key) }
        }
        do { try process.run() } catch { Task { @MainActor in completion(nil, nil) } }
    }

    /// Sends a transport command through a short-lived helper process.
    func send(_ command: Command) {
        guard let script, let library else { return }
        let process = Process()
        process.executableURL = Self.interpreter
        process.arguments = [script.path, library.path]
        var env = ProcessInfo.processInfo.environment
        env["GARAKUTA_NOW_PLAYING_MODE"] = "command"
        env["GARAKUTA_NOW_PLAYING_COMMAND"] = String(command.rawValue)
        process.environment = env
        process.standardOutput = nil
        process.standardError = nil
        try? process.run()
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
