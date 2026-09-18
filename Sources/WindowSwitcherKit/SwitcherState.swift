import AppKit
import CoreGraphics
import GarakutaCore
import Observation

/// Observable model behind the switcher panel: the window list, filter query, selection, and thumbnails.
@MainActor
@Observable
final class SwitcherState {
    var settings = SwitcherSettings()
    var windows: [SwitcherWindow] = [] { didSet { rebuildFiltered() } }
    var query = "" { didSet { rebuildFiltered() } }
    /// Session filter: only this app's windows (the app-windows shortcut).
    var frontmostOnly: pid_t? { didSet { rebuildFiltered() } }
    var selectedIndex = 0
    var thumbnails: [CGWindowID: CGImage] = [:]
    var thumbnailsEnabled = false
    var isVisible = false
    var metrics = SwitcherMetrics.make(style: .thumbnails, preset: .medium, screen: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                       physicalWidthMM: nil, showsSubtitle: true)
    /// Tile under a file drag, if any.
    var dropTarget: CGWindowID?

    /// Windows shown, in display order. Ranked by match quality while a query is typed.
    private(set) var filtered: [SwitcherWindow] = []
    /// Match details for highlighting, by window; only while a query is typed.
    private(set) var titleMatches: [CGWindowID: SearchMatch] = [:]
    private(set) var appMatches: [CGWindowID: SearchMatch] = [:]

    private func rebuildFiltered() {
        var list = windows
        if let pid = frontmostOnly { list = list.filter { $0.pid == pid } }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else {
            filtered = list
            titleMatches = [:]
            appMatches = [:]
            return
        }
        var scored: [(SwitcherWindow, Int)] = []
        var titles: [CGWindowID: SearchMatch] = [:]
        var apps: [CGWindowID: SearchMatch] = [:]
        for w in list {
            let title = w.isAppPlaceholder ? nil : SearchMatcher.match(query: q, in: w.title)
            let app = SearchMatcher.match(query: q, in: w.appName)
            // The app name gets a slight edge: "saf" should list Safari's windows before a file called "safety".
            let best = max(title?.score ?? 0, app.map { $0.score + $0.score / 50 } ?? 0)
            guard best > 0 else { continue }
            if let title { titles[w.windowID] = title }
            if let app { apps[w.windowID] = app }
            scored.append((w, best))
        }
        // Stable: equal scores keep the list order.
        filtered = scored.enumerated().sorted { a, b in
            a.element.1 != b.element.1 ? a.element.1 > b.element.1 : a.offset < b.offset
        }.map(\.element.0)
        titleMatches = titles
        appMatches = apps
    }

    var selected: SwitcherWindow? {
        let list = filtered
        guard !list.isEmpty else { return nil }
        return list[min(max(selectedIndex, 0), list.count - 1)]
    }

    func moveSelection(by delta: Int) {
        let count = filtered.count
        guard count > 0 else { selectedIndex = 0; return }
        selectedIndex = ((selectedIndex + delta) % count + count) % count
    }

    /// Moves the selection to the tile above or below in the flow layout, staying in the same column if possible.
    func moveSelection(rows delta: Int) {
        let list = filtered
        guard list.count > 1 else { return }
        let widths = list.map(metrics.tileWidth(for:))
        let placement = TileFlow.place(widths: widths, rowHeight: metrics.tileHeight, maxWidth: metrics.maxGridWidth, spacing: metrics.spacing)
        guard let rowIndex = placement.rows.firstIndex(where: { $0.contains(selectedIndex) }) else { return }
        let rowCount = placement.rows.count
        let targetRow = ((rowIndex + delta) % rowCount + rowCount) % rowCount
        let centerX = placement.origins[selectedIndex].x + widths[selectedIndex] / 2
        let candidates = placement.rows[targetRow]
        guard let nearest = candidates.min(by: {
            abs(placement.origins[$0].x + widths[$0] / 2 - centerX) < abs(placement.origins[$1].x + widths[$1] / 2 - centerX)
        }) else { return }
        selectedIndex = nearest
    }

    func select(id: CGWindowID) {
        if let i = filtered.firstIndex(where: { $0.windowID == id }) { selectedIndex = i }
    }

    func appIcon(for window: SwitcherWindow) -> NSImage? {
        NSRunningApplication(processIdentifier: window.pid)?.icon
    }
}
