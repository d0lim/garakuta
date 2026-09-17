import AppKit
import CoreGraphics
import GarakutaCore
import Observation

/// Observable model behind the switcher panel: the window list, filter query, selection, and thumbnails.
@MainActor
@Observable
final class SwitcherState {
    var settings = SwitcherSettings()
    var windows: [SwitcherWindow] = []
    var query = ""
    var selectedIndex = 0
    var thumbnails: [CGWindowID: CGImage] = [:]
    var thumbnailsEnabled = false
    var isVisible = false

    var filtered: [SwitcherWindow] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return windows }
        return windows.filter { $0.title.lowercased().contains(q) || $0.appName.lowercased().contains(q) }
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

    func select(id: CGWindowID) {
        if let i = filtered.firstIndex(where: { $0.windowID == id }) { selectedIndex = i }
    }

    func appIcon(for window: SwitcherWindow) -> NSImage? {
        NSRunningApplication(processIdentifier: window.pid)?.icon
    }
}
