import AppKit
import ApplicationServices
import CoreGraphics
import GarakutaCore

/// Main-thread snapshot of a running app, so the scan can run off the main actor.
struct AppSnapshot: Sendable {
    let pid: pid_t
    let name: String
    let bundleIdentifier: String?
    let isHidden: Bool

    @MainActor
    static func current(excluding ownPID: pid_t) -> [AppSnapshot] {
        NSWorkspace.shared.runningApplications
            .filter { $0.processIdentifier != ownPID && $0.activationPolicy == .regular && !$0.isTerminated }
            .map { AppSnapshot(pid: $0.processIdentifier, name: $0.localizedName ?? $0.bundleIdentifier ?? "PID \($0.processIdentifier)",
                               bundleIdentifier: $0.bundleIdentifier, isHidden: $0.isHidden) }
    }
}

/// Result of one scan. AX elements are CF objects without Sendable annotations; they are only ever read from the
/// main actor after the result is published there.
final class ScanResult: @unchecked Sendable {
    let windows: [SwitcherWindow]
    let elements: [CGWindowID: AXUIElement]
    let scannedAt: Date

    init(windows: [SwitcherWindow], elements: [CGWindowID: AXUIElement]) {
        self.windows = windows
        self.elements = elements
        self.scannedAt = Date()
    }
}

private struct CGInfo {
    var pid: pid_t
    var bounds: CGRect
    var onScreen: Bool
    var title: String?
}

/// Builds the switcher's window list from three sources:
/// 1. the window server (CGWindowList for the current Space, SkyLight for every Space when available),
/// 2. each app's Accessibility windows (titles, minimized state, the element to raise),
/// 3. SkyLight (which Space a window is on, and which Spaces are current).
/// Accessibility is required for titles and minimized windows; without it the list is window-server only.
/// `scan` is pure and may run on a background task; it must not touch AppKit objects.
enum WindowEnumerator {
    private static let axTimeout: Float = 0.1
    private static let spaces = SpaceInfo()

    nonisolated static func scan(apps: [AppSnapshot], settings: SwitcherSettings, screenFrame: CGRect?, trusted: Bool) -> ScanResult {
        let appsByPID = Dictionary(uniqueKeysWithValues: apps.map { ($0.pid, $0) })
        let currentSpaces = spaces.currentSpaceIDs()

        // 1a. Window server, current Space: bounds, on-screen flag, z-order.
        var cgInfo: [CGWindowID: CGInfo] = [:]
        var cgOrder: [CGWindowID] = []  // front to back
        if let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] {
            for info in list {
                guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                      let id = info[kCGWindowNumber as String] as? CGWindowID,
                      let pid = info[kCGWindowOwnerPID as String] as? pid_t, appsByPID[pid] != nil,
                      let dict = info[kCGWindowBounds as String] as? NSDictionary,
                      let bounds = CGRect(dictionaryRepresentation: dict),
                      bounds.width >= 50, bounds.height >= 50,
                      (info[kCGWindowAlpha as String] as? Double ?? 1) > 0
                else { continue }
                cgInfo[id] = CGInfo(pid: pid, bounds: bounds, onScreen: info[kCGWindowIsOnscreen as String] as? Bool ?? false,
                                    title: info[kCGWindowName as String] as? String)
                cgOrder.append(id)
            }
        }

        // 1b. Window server, every Space (SkyLight). CGWindowList omits windows on other Spaces.
        if settings.showOtherSpaces, SpaceInfo.isAvailable {
            for id in spaces.windowIDs(inSpaces: spaces.allSpaceIDs()) where cgInfo[id] == nil {
                guard spaces.level(of: id) == 0,
                      let bounds = spaces.bounds(of: id), bounds.width >= 50, bounds.height >= 50,
                      let pid = spaces.ownerPID(of: id), appsByPID[pid] != nil
                else { continue }
                cgInfo[id] = CGInfo(pid: pid, bounds: bounds, onScreen: false, title: nil)
                cgOrder.append(id)
            }
        }

        var results: [CGWindowID: SwitcherWindow] = [:]
        var newElements: [CGWindowID: AXUIElement] = [:]
        var appsWithWindows: Set<pid_t> = []

        func spaceState(_ id: CGWindowID, onScreenFallback: Bool) -> (ids: [UInt64], current: Bool) {
            let ids = spaces.spaces(of: id)
            if ids.isEmpty { return (ids, onScreenFallback) }
            return (ids, !Set(ids).isDisjoint(with: currentSpaces))
        }

        func addWindowServerOnly(_ app: AppSnapshot) {
            for id in cgOrder {
                guard let info = cgInfo[id], info.pid == app.pid, results[id] == nil else { continue }
                let (ids, onCurrent) = spaceState(id, onScreenFallback: info.onScreen)
                if !onCurrent && !settings.showOtherSpaces { continue }
                results[id] = SwitcherWindow(windowID: id, pid: app.pid, appName: app.name, bundleIdentifier: app.bundleIdentifier,
                                             title: info.title ?? "", frame: info.bounds, isMinimized: false,
                                             isFullScreen: ids.contains { spaces.isFullScreenSpace($0) },
                                             isAppHidden: app.isHidden, isOnCurrentSpace: onCurrent, spaceIDs: ids,
                                             isAppPlaceholder: false)
                appsWithWindows.insert(app.pid)
            }
        }

        for app in apps {
            let rule = settings.rule(for: app.bundleIdentifier)
            if rule == .exclude { continue }
            if app.isHidden && !settings.showHiddenApps { continue }

            guard trusted else {
                addWindowServerOnly(app)
                continue
            }

            // 2. Accessibility windows.
            let axApp = AXUIElementCreateApplication(app.pid)
            AXUIElementSetMessagingTimeout(axApp, axTimeout)
            let axWindows: [AXUIElement] = AX.attribute(axApp, kAXWindowsAttribute) ?? []
            for window in axWindows {
                let subrole: String? = AX.attribute(window, kAXSubroleAttribute)
                guard subrole == nil || subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole else { continue }
                guard let id = spaces.windowID(of: window) ?? matchByFrame(window, in: cgInfo) else { continue }
                let minimized = AX.bool(window, kAXMinimizedAttribute)
                if minimized && !settings.showMinimized { continue }
                let fullScreen = AX.bool(window, "AXFullScreen")
                let title: String = AX.attribute(window, kAXTitleAttribute) ?? cgInfo[id]?.title ?? ""
                let frame: CGRect
                if let p = AX.point(window, kAXPositionAttribute), let s = AX.size(window, kAXSizeAttribute) {
                    frame = CGRect(origin: p, size: s)
                } else {
                    frame = cgInfo[id]?.bounds ?? .zero
                }
                if !minimized, frame.width < 50 || frame.height < 50 { continue }
                let (ids, onCurrent) = spaceState(id, onScreenFallback: cgInfo[id]?.onScreen ?? true)
                if !onCurrent && !minimized && !settings.showOtherSpaces { continue }
                results[id] = SwitcherWindow(windowID: id, pid: app.pid, appName: app.name, bundleIdentifier: app.bundleIdentifier,
                                             title: title, frame: frame, isMinimized: minimized,
                                             isFullScreen: fullScreen || ids.contains { spaces.isFullScreenSpace($0) },
                                             isAppHidden: app.isHidden, isOnCurrentSpace: onCurrent, spaceIDs: ids,
                                             isAppPlaceholder: false)
                newElements[id] = window
                appsWithWindows.insert(app.pid)
            }
            // Apps that timed out or hide their AX tree still get their window-server windows (no titles).
            addWindowServerOnly(app)
        }

        // Screen filter (W02 current-screen-only) uses CG coordinates.
        if settings.currentScreenOnly, let screenFrame {
            results = results.filter { $0.value.isMinimized || $0.value.frame.intersects(screenFrame) }
        }

        // Order: window server z-order first (front to back), then anything else (minimized windows without CG entries).
        var ordered: [SwitcherWindow] = []
        var seen: Set<CGWindowID> = []
        for id in cgOrder {
            if let w = results[id] { ordered.append(w); seen.insert(id) }
        }
        for id in results.keys.sorted() where !seen.contains(id) {
            ordered.append(results[id]!)
        }
        // Keep z-order but push minimized windows after visible ones, like the Dock's switcher.
        ordered = ordered.filter { !$0.isMinimized } + ordered.filter { $0.isMinimized }

        // Rules: group as one, include even without windows.
        var finalList: [SwitcherWindow] = []
        var groupedApps: Set<pid_t> = []
        for w in ordered {
            if settings.rule(for: w.bundleIdentifier) == .groupAsOne {
                if groupedApps.contains(w.pid) { continue }
                groupedApps.insert(w.pid)
                var g = w
                g.isAppPlaceholder = true
                g.title = w.appName
                finalList.append(g)
            } else {
                finalList.append(w)
            }
        }
        for app in apps where settings.rule(for: app.bundleIdentifier) == .includeEvenWithoutWindows && !appsWithWindows.contains(app.pid) {
            // Synthetic id: tag with the top bit so it cannot clash with a real CGWindowID.
            let fakeID = CGWindowID(0x8000_0000) | CGWindowID(UInt32(truncatingIfNeeded: app.pid))
            finalList.append(SwitcherWindow(windowID: fakeID, pid: app.pid, appName: app.name, bundleIdentifier: app.bundleIdentifier,
                                            title: app.name, frame: .zero, isMinimized: false, isFullScreen: false,
                                            isAppHidden: app.isHidden, isOnCurrentSpace: true, spaceIDs: [], isAppPlaceholder: true))
        }

        return ScanResult(windows: finalList, elements: newElements)
    }

    /// Fallback correlation when _AXUIElementGetWindow is unavailable: same position and size as a window-server window.
    private static func matchByFrame(_ window: AXUIElement, in cg: [CGWindowID: CGInfo]) -> CGWindowID? {
        guard let p = AX.point(window, kAXPositionAttribute), let s = AX.size(window, kAXSizeAttribute) else { return nil }
        let frame = CGRect(origin: p, size: s)
        return cg.first { abs($0.value.bounds.minX - frame.minX) < 2 && abs($0.value.bounds.minY - frame.minY) < 2
            && abs($0.value.bounds.width - frame.width) < 2 && abs($0.value.bounds.height - frame.height) < 2 }?.key
    }
}
