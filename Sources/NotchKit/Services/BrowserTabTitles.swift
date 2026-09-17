import Foundation

/// Browsers publish playback state to the system but the service never hands out their metadata, so the title of
/// the tab that is playing stands in. Needs Automation permission for the browser on first use.
enum BrowserTabTitles {
    private static let chromeFamily: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary", "com.microsoft.edgemac",
        "com.brave.Browser", "com.vivaldi.Vivaldi", "company.thebrowser.Browser", "com.operasoftware.Opera",
    ]
    private static let safariFamily: Set<String> = ["com.apple.Safari", "com.apple.SafariTechnologyPreview"]

    static func isBrowser(_ bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return chromeFamily.contains(bundleIdentifier) || safariFamily.contains(bundleIdentifier)
    }

    /// AppleScript listing every tab as "URL<tab>title", one per line.
    static func script(for bundleIdentifier: String) -> String? {
        let titleProperty: String
        if chromeFamily.contains(bundleIdentifier) { titleProperty = "title" }
        else if safariFamily.contains(bundleIdentifier) { titleProperty = "name" }
        else { return nil }
        return """
        tell application id "\(bundleIdentifier)"
            set out to ""
            repeat with w in windows
                repeat with t in tabs of w
                    set out to out & (URL of t) & tab & (\(titleProperty) of t) & linefeed
                end repeat
            end repeat
            return out
        end tell
        """
    }

    /// Sites whose tabs are likely to be the one playing, most specific first.
    private static let mediaSites: [(host: String, path: String?)] = [
        ("music.youtube.com", nil), ("youtube.com", "/watch"), ("open.spotify.com", nil), ("music.apple.com", nil),
        ("soundcloud.com", nil), ("tidal.com", nil), ("deezer.com", nil), ("bandcamp.com", nil), ("mixcloud.com", nil),
        ("twitch.tv", nil), ("netflix.com", nil), ("vimeo.com", nil), ("podcasts.apple.com", nil),
    ]

    struct Pick: Equatable {
        var title: String
        var artist: String
    }

    /// Chooses the most likely media tab from the script output and turns its title into song and artist.
    static func pick(from output: String) -> Pick? {
        let tabs: [(url: URL, title: String)] = output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, let url = URL(string: String(parts[0])) else { return nil }
            return (url, String(parts[1]).trimmingCharacters(in: .whitespaces))
        }
        for site in mediaSites {
            for tab in tabs {
                guard let host = tab.url.host?.lowercased(), host == site.host || host.hasSuffix("." + site.host) else { continue }
                if let path = site.path, !tab.url.path.hasPrefix(path) { continue }
                if let pick = parse(title: tab.title, host: host) { return pick }
            }
        }
        return nil
    }

    /// Strips the site's suffix and splits "song • artist" style titles.
    static func parse(title raw: String, host: String) -> Pick? {
        var title = raw
        // Unread badges such as "(3) " that some sites prepend.
        if let match = title.range(of: #"^\(\d+\)\s+"#, options: .regularExpression) { title.removeSubrange(match) }
        for suffix in [" - YouTube Music", " - YouTube", " | Spotify", " - Spotify", " | Listen online for free on SoundCloud",
                       " on Apple Music", " - Apple Music", " | TIDAL", " - Twitch", " - Netflix", " on Vimeo", " | Deezer"] {
            if title.hasSuffix(suffix) { title.removeLast(suffix.count); break }
        }
        title = title.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, !["YouTube Music", "YouTube", "Spotify", "Netflix", "Twitch"].contains(title) else { return nil }
        for separator in [" • ", " · "] {
            if let range = title.range(of: separator) {
                return Pick(title: String(title[..<range.lowerBound]), artist: String(title[range.upperBound...]))
            }
        }
        if host.hasSuffix("soundcloud.com"), let range = title.range(of: " by ", options: .backwards) {
            return Pick(title: String(title[..<range.lowerBound]), artist: String(title[range.upperBound...]))
        }
        return Pick(title: title, artist: "")
    }
}
