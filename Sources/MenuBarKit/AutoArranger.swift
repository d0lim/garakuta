import AppKit
import GarakutaCore

/// M04: keeps visible items from running behind the notch (or off the left edge) by demoting the lowest-priority
/// ones to the hidden section, and restores them when space returns. Also offers temporary swaps.
@MainActor
final class AutoArranger {
    /// Items the arranger demoted itself; candidates for restoration. Stable keys, most recently demoted last.
    private(set) var autoHiddenKeys: [String] = []
    private var isRunningPass = false
    private var swapTask: Task<Void, Never>?

    private static let margin: CGFloat = 12
    private static let maxMovesPerPass = 3

    private weak var module: MenuBarModule?

    init(module: MenuBarModule) {
        self.module = module
    }

    func stop() {
        swapTask?.cancel()
        swapTask = nil
    }

    /// Left boundary (CG x) that visible items must stay to the right of on the main display.
    func leftBoundary() -> CGFloat? {
        guard let screen = MenuBarGeometry.mainScreen else { return nil }
        if let notch = MenuBarGeometry.notchSpan(of: screen) {
            return notch.upperBound + Self.margin
        }
        // No notch: stay clear of the frontmost app's menu titles.
        if let maxX = frontmostAppMenuMaxX() { return maxX + Self.margin }
        return screen.frame.minX + 300
    }

    func runPass() async {
        guard let module, module.isRunning, !isRunningPass, Permission.accessibility.isGranted else { return }
        isRunningPass = true
        defer { isRunningPass = false }
        guard let boundary = leftBoundary() else { return }
        var moves = 0
        var snapshot = module.items()

        // Demote while the leftmost visible item crosses the boundary.
        while moves < Self.maxMovesPerPass {
            let visible = snapshot.filter { $0.section == .visible }.map(\.item)
            guard let leftmost = visible.min(by: { $0.frame.minX < $1.frame.minX }), leftmost.frame.minX < boundary else { break }
            guard let victim = lowestPriority(among: visible) else { break }
            guard module.isRunning else { return }
            do {
                try await module.moveWithRetry(victim, to: .hidden, recordAssignment: false)
                autoHiddenKeys.append(victim.stableKey)
            } catch {
                NSLog("auto-arrange demote failed: %@", String(describing: error))
                break
            }
            moves += 1
            snapshot = module.items()
        }

        // Restore when there is comfortably room for the most recently demoted item.
        while moves < Self.maxMovesPerPass, let key = autoHiddenKeys.last {
            let visible = snapshot.filter { $0.section == .visible }.map(\.item)
            guard let candidate = snapshot.first(where: { $0.item.stableKey == key })?.item else {
                autoHiddenKeys.removeLast()
                continue
            }
            let leftmostX = visible.map(\.frame.minX).min() ?? (MenuBarGeometry.mainScreen?.frame.maxX ?? 0)
            guard leftmostX - boundary > candidate.frame.width + Self.margin * 2 else { break }
            guard module.isRunning else { return }
            do {
                try await module.moveWithRetry(candidate, to: .visible, recordAssignment: false)
                autoHiddenKeys.removeLast()
            } catch {
                break
            }
            moves += 1
            snapshot = module.items()
        }
    }

    /// Brings a hidden item into the visible section for a while, swapping out the lowest-priority visible item
    /// when the bar is full, then puts both back.
    func swapTemporarily(_ item: MenuBarItem, for duration: Double) {
        swapTask?.cancel()
        swapTask = Task { @MainActor [weak self] in
            guard let self, let module = self.module, module.isRunning else { return }
            let snapshot = module.items()
            guard let boundary = self.leftBoundary() else { return }
            let visible = snapshot.filter { $0.section == .visible }.map(\.item)
            let leftmostX = visible.map(\.frame.minX).min() ?? boundary + 1000
            var swappedOut: MenuBarItem?
            if leftmostX - boundary < item.frame.width + Self.margin * 2, let victim = self.lowestPriority(among: visible) {
                swappedOut = victim
                try? await module.moveWithRetry(victim, to: .hidden, recordAssignment: false)
            }
            try? await module.moveWithRetry(item, to: .visible, recordAssignment: false)
            try? await Task.sleep(for: .seconds(duration))
            // The module may have stopped or been released while we slept.
            guard !Task.isCancelled, let module = self.module, module.isRunning else { return }
            try? await module.moveWithRetry(item, to: .hidden, recordAssignment: false)
            if let swappedOut {
                try? await module.moveWithRetry(swappedOut, to: .visible, recordAssignment: false)
            }
        }
    }

    // MARK: Helpers

    /// Lowest-priority candidate for demotion. Items the user explicitly pinned to Visible and system items are
    /// never candidates, so auto-arrange cannot fight enforceAssignments.
    private func lowestPriority(among items: [MenuBarItem]) -> MenuBarItem? {
        guard let module else { return nil }
        let order = module.settings.priorityOrder
        let assignments = module.settings.sectionAssignments
        let candidates = items.filter { item in
            assignments[item.stableKey] != .visible && !MenuBarItemScanner.isSystemItem(bundleIdentifier: item.bundleIdentifier)
        }
        func rank(_ item: MenuBarItem) -> Int { order.firstIndex(of: item.stableKey) ?? Int.max }
        // Highest rank value = lowest priority; among ties prefer the leftmost (closest to overflow).
        return candidates.max { a, b in
            let ra = rank(a), rb = rank(b)
            if ra != rb { return ra < rb }
            return a.frame.minX > b.frame.minX
        }
    }

    private func frontmostAppMenuMaxX() -> CGFloat? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 0.25)
        guard let menuBar = AXHelpers.copyElement(axApp, kAXMenuBarAttribute),
              let children = AXHelpers.copyElements(menuBar, kAXChildrenAttribute), let last = children.last,
              let point = AXHelpers.copyPoint(last, kAXPositionAttribute),
              let size = AXHelpers.copySize(last, kAXSizeAttribute) else { return nil }
        return point.x + size.width
    }
}
