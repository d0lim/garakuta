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

/// Everything a scan needs from the main actor, captured before it starts.
struct ScanInput: Sendable {
    var apps: [AppSnapshot]
    var settings: SwitcherSettings
    /// Screen the switcher will appear on (CG coordinates), for the current-screen filter.
    var screenFrame: CGRect?
    var trusted: Bool
    /// Focus order stamps: higher is more recent, 0 unknown.
    var focusStamps: [CGWindowID: UInt64]
    var dockPID: pid_t?
    /// Pid of the frontmost app, for the app-windows-only session.
    var frontmostPID: pid_t?
}

/// Result of one scan. AX elements are CF objects without Sendable annotations; they are only ever read from the
/// main actor after the result is published there.
final class ScanResult: @unchecked Sendable {
    let windows: [SwitcherWindow]
    let elements: [CGWindowID: AXUIElement]
    /// Front-to-back stacking order of every window the window server listed, for seeding the focus history.
    let stackingOrder: [CGWindowID]
    let scannedAt: Date

    init(windows: [SwitcherWindow], elements: [CGWindowID: AXUIElement], stackingOrder: [CGWindowID]) {
        self.windows = windows
        self.elements = elements
        self.stackingOrder = stackingOrder
        self.scannedAt = Date()
    }
}

private struct CGInfo {
    var pid: pid_t
    var bounds: CGRect
    var onScreen: Bool
    var title: String?
}

/// One app's share of a scan, produced in parallel with the others.
private final class AppScan: @unchecked Sendable {
    var windows: [CGWindowID: SwitcherWindow] = [:]
    var elements: [CGWindowID: AXUIElement] = [:]
    var hasWindows = false
}

/// Builds the switcher's window list from three sources:
/// 1. the window server (CGWindowList for the current Space, SkyLight for every Space when available),
/// 2. each app's Accessibility windows (titles, minimized state, the element to raise), read in parallel so one
///    unresponsive app delays only itself,
/// 3. SkyLight (which Space a window is on, and which Spaces are current).
/// Accessibility is required for titles and minimized windows; without it the list is window-server only.
/// `scan` may run on a background task; it must not touch AppKit objects.
enum WindowEnumerator {
    private static let axTimeout: Float = 0.1
    private static let spaces = SpaceInfo()

    nonisolated static func scan(_ input: ScanInput) async -> ScanResult {
        let settings = input.settings
        let appsByPID = Dictionary(uniqueKeysWithValues: input.apps.map { ($0.pid, $0) })
        let currentSpaces = spaces.currentSpaceIDs()
        let spaceNumbers = settings.showSpaceNumbers ? spaces.spaceNumbers() : [:]

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
        let frozenInfo = cgInfo
        let frozenOrder = cgOrder

        // 2. Per-app Accessibility, in parallel. Apps that timed out or hide their AX tree still get their
        //    window-server windows (no titles).
        let apps = input.apps.filter { app in
            let rule = settings.rule(for: app.bundleIdentifier)
            if rule == .exclude { return false }
            if app.isHidden && !settings.showHiddenApps { return false }
            if let front = input.frontmostPID, app.pid != front { return false }
            return true
        }
        var dockBadges: [String: String] = [:]
        var scans: [pid_t: AppScan] = [:]
        await withTaskGroup(of: (pid_t, AppScan?, [String: String]?).self) { group in
            for app in apps {
                group.addTask {
                    (app.pid, scanApp(app, settings: settings, cgInfo: frozenInfo, cgOrder: frozenOrder, currentSpaces: currentSpaces,
                                      spaceNumbers: spaceNumbers, trusted: input.trusted), nil)
                }
            }
            if settings.showDockBadges, input.trusted, let dockPID = input.dockPID {
                group.addTask { (dockPID, nil, readDockBadges(dockPID)) }
            }
            for await (pid, scan, badges) in group {
                if let scan { scans[pid] = scan }
                if let badges { dockBadges = badges }
            }
        }

        var results: [CGWindowID: SwitcherWindow] = [:]
        var elements: [CGWindowID: AXUIElement] = [:]
        var appsWithWindows: Set<pid_t> = []
        for (pid, scan) in scans {
            results.merge(scan.windows) { a, _ in a }
            elements.merge(scan.elements) { a, _ in a }
            if scan.hasWindows { appsWithWindows.insert(pid) }
        }

        // Tabs: a window of the same app with the same frame as a shown window, on no Space of its own, is a
        // background tab. It gets its own tile only when the user asked for tabs to be separate.
        let byPID = Dictionary(grouping: results.values, by: \.pid)
        for (_, windows) in byPID where windows.count > 1 {
            let anchors = windows.filter { !$0.spaceIDs.isEmpty || $0.isMinimized }
            for w in windows where w.spaceIDs.isEmpty && !w.isMinimized {
                let sibling = anchors.contains { a in
                    abs(a.frame.minX - w.frame.minX) < 3 && abs(a.frame.minY - w.frame.minY) < 3
                        && abs(a.frame.width - w.frame.width) < 3 && abs(a.frame.height - w.frame.height) < 3
                }
                if sibling {
                    results[w.windowID]?.isTab = true
                    if settings.groupTabs { results[w.windowID] = nil }
                }
            }
        }

        // A window on no Space at all that is not minimized has no place on screen: an app's hidden helper window
        // (many Electron apps keep one) or a tab already merged above. Only decided when Space membership is known.
        if SpaceInfo.isAvailable {
            results = results.filter { !$0.value.spaceIDs.isEmpty || $0.value.isMinimized || $0.value.isAppPlaceholder }
        }

        // Screen filter (W02 current-screen-only) uses CG coordinates.
        if settings.currentScreenOnly, let screenFrame = input.screenFrame {
            results = results.filter { $0.value.isMinimized || $0.value.frame.intersects(screenFrame) }
        }

        // Dock badges, per app name.
        if !dockBadges.isEmpty {
            for (id, w) in results {
                if let badge = dockBadges[w.appName] { results[id]?.dockBadge = badge }
            }
        }

        // Order: stacking order (front to back) is the base; the focus history overrides it when asked. Windows
        // never seen focused keep their stacking position behind every focused one.
        var ordered: [SwitcherWindow] = []
        var seen: Set<CGWindowID> = []
        for id in cgOrder {
            if let w = results[id] { ordered.append(w); seen.insert(id) }
        }
        for id in results.keys.sorted() where !seen.contains(id) {
            ordered.append(results[id]!)
        }
        switch settings.windowOrder {
        case .recentlyFocused:
            let position = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($1.windowID, $0) })
            ordered.sort { a, b in
                let sa = input.focusStamps[a.windowID] ?? 0, sb = input.focusStamps[b.windowID] ?? 0
                if sa != sb { return sa > sb }
                return position[a.windowID]! < position[b.windowID]!
            }
        case .alphabetical:
            ordered.sort { a, b in
                let byApp = a.appName.localizedCaseInsensitiveCompare(b.appName)
                if byApp != .orderedSame { return byApp == .orderedAscending }
                return a.displayTitle.localizedCaseInsensitiveCompare(b.displayTitle) == .orderedAscending
            }
        case .stackingOrder:
            break
        }
        // Minimized windows and windows of hidden apps go last, like the Dock's switcher.
        ordered = ordered.filter { !$0.isMinimized && !$0.isAppHidden } + ordered.filter { $0.isAppHidden && !$0.isMinimized }
            + ordered.filter { $0.isMinimized }

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
                                            isAppHidden: app.isHidden, isOnCurrentSpace: true, spaceIDs: [],
                                            dockBadge: dockBadges[app.name], isAppPlaceholder: true))
        }

        return ScanResult(windows: finalList, elements: elements, stackingOrder: cgOrder)
    }

    // MARK: One app

    private nonisolated static func scanApp(_ app: AppSnapshot, settings: SwitcherSettings, cgInfo: [CGWindowID: CGInfo], cgOrder: [CGWindowID],
                                            currentSpaces: Set<UInt64>, spaceNumbers: [UInt64: Int], trusted: Bool) -> AppScan {
        let scan = AppScan()

        func spaceState(_ id: CGWindowID, onScreenFallback: Bool) -> (ids: [UInt64], current: Bool) {
            let ids = spaces.spaces(of: id)
            if ids.isEmpty { return (ids, onScreenFallback) }
            return (ids, !Set(ids).isDisjoint(with: currentSpaces))
        }

        func number(for ids: [UInt64]) -> Int? {
            ids.compactMap { spaceNumbers[$0] }.first
        }

        func addWindowServerOnly() {
            for id in cgOrder {
                guard let info = cgInfo[id], info.pid == app.pid, scan.windows[id] == nil else { continue }
                let (ids, onCurrent) = spaceState(id, onScreenFallback: info.onScreen)
                if !onCurrent && !settings.showOtherSpaces { continue }
                scan.windows[id] = SwitcherWindow(windowID: id, pid: app.pid, appName: app.name, bundleIdentifier: app.bundleIdentifier,
                                                  title: info.title ?? "", frame: info.bounds, isMinimized: false,
                                                  isFullScreen: ids.contains { spaces.isFullScreenSpace($0) },
                                                  isAppHidden: app.isHidden, isOnCurrentSpace: onCurrent, spaceIDs: ids,
                                                  spaceNumber: number(for: ids), isAppPlaceholder: false)
                scan.hasWindows = true
            }
        }

        guard trusted else {
            addWindowServerOnly()
            return scan
        }

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
            scan.windows[id] = SwitcherWindow(windowID: id, pid: app.pid, appName: app.name, bundleIdentifier: app.bundleIdentifier,
                                              title: title, frame: frame, isMinimized: minimized,
                                              isFullScreen: fullScreen || ids.contains { spaces.isFullScreenSpace($0) },
                                              isAppHidden: app.isHidden, isOnCurrentSpace: onCurrent, spaceIDs: ids,
                                              spaceNumber: number(for: ids), isAppPlaceholder: false)
            scan.elements[id] = window
            scan.hasWindows = true
        }
        addWindowServerOnly()
        return scan
    }

    /// Fallback correlation when _AXUIElementGetWindow is unavailable: same position and size as a window-server window.
    private static func matchByFrame(_ window: AXUIElement, in cg: [CGWindowID: CGInfo]) -> CGWindowID? {
        guard let p = AX.point(window, kAXPositionAttribute), let s = AX.size(window, kAXSizeAttribute) else { return nil }
        let frame = CGRect(origin: p, size: s)
        return cg.first { abs($0.value.bounds.minX - frame.minX) < 2 && abs($0.value.bounds.minY - frame.minY) < 2
            && abs($0.value.bounds.width - frame.width) < 2 && abs($0.value.bounds.height - frame.height) < 2 }?.key
    }

    // MARK: Dock badges

    /// App name → badge text, read from the Dock's Accessibility list. Only apps with a badge appear.
    private nonisolated static func readDockBadges(_ dockPID: pid_t) -> [String: String] {
        let dock = AXUIElementCreateApplication(dockPID)
        AXUIElementSetMessagingTimeout(dock, axTimeout)
        guard let children: [AXUIElement] = AX.attribute(dock, kAXChildrenAttribute) else { return [:] }
        var result: [String: String] = [:]
        for list in children {
            let role: String? = AX.attribute(list, kAXRoleAttribute)
            guard role == kAXListRole, let items: [AXUIElement] = AX.attribute(list, kAXChildrenAttribute) else { continue }
            for item in items {
                guard let badge: String = AX.attribute(item, "AXStatusLabel"), !badge.isEmpty,
                      let title: String = AX.attribute(item, kAXTitleAttribute) else { continue }
                result[title] = badge
            }
        }
        return result
    }
}
