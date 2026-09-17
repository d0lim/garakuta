import AppKit
import ApplicationServices
import CoreGraphics

/// Enumerates other apps' status items by walking `AXExtrasMenuBar` on running apps that can own one.
/// Requires Accessibility. Results are cached briefly; callers that just moved something call `invalidate()`.
@MainActor
final class MenuBarItemScanner {
    /// kCGStatusWindowLevel: the layer every status item window lives on.
    private static let statusLayer = 25
    private static let axTimeout: Float = 0.25
    private static let cacheLifetime: TimeInterval = 1.0

    /// System processes whose items must never be listed or moved.
    static let excludedBundleIdentifiers: Set<String> = [
        "com.apple.controlcenter",
        "com.apple.systemuiserver",
        "com.apple.Spotlight",
        "com.apple.Siri",
    ]

    private var elements: [String: AXUIElement] = [:]
    private var cached: [MenuBarItem] = []
    private var cachedAt: Date = .distantPast

    func element(for item: MenuBarItem) -> AXUIElement? { elements[item.id] }

    /// Activates the item as a click would (opens its menu / runs its action). False when the element is gone.
    func press(_ item: MenuBarItem) -> Bool {
        guard let element = elements[item.id] else { return false }
        return AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    func invalidate() {
        cachedAt = .distantPast
    }

    static func isSystemItem(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return excludedBundleIdentifiers.contains(bundleIdentifier)
    }

    func scan() -> [MenuBarItem] {
        guard AXIsProcessTrusted() else { return [] }
        if Date().timeIntervalSince(cachedAt) < Self.cacheLifetime { return cached }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownBundle = Bundle.main.bundleIdentifier
        let statusWindows = statusWindowFrames()
        var found: [MenuBarItem] = []
        var newElements: [String: AXUIElement] = [:]

        for app in NSWorkspace.shared.runningApplications {
            guard app.processIdentifier != ownPID, !app.isTerminated, app.activationPolicy != .prohibited else { continue }
            if let bundle = app.bundleIdentifier, bundle == ownBundle || Self.excludedBundleIdentifiers.contains(bundle) { continue }
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(axApp, Self.axTimeout)
            guard let extras = AXHelpers.copyElement(axApp, "AXExtrasMenuBar"),
                  let children = AXHelpers.copyElements(extras, kAXChildrenAttribute), !children.isEmpty
            else { continue }
            for (index, child) in children.enumerated() {
                guard let position = AXHelpers.copyPoint(child, kAXPositionAttribute),
                      let size = AXHelpers.copySize(child, kAXSizeAttribute)
                else { continue }
                let frame = CGRect(origin: position, size: size)
                let title: String? = AXHelpers.copyAttribute(child, kAXTitleAttribute)
                let description: String? = AXHelpers.copyAttribute(child, kAXDescriptionAttribute)
                let item = MenuBarItem(
                    ownerPID: app.processIdentifier,
                    ownerName: app.localizedName ?? app.bundleIdentifier ?? "PID \(app.processIdentifier)",
                    bundleIdentifier: app.bundleIdentifier,
                    index: index,
                    title: title?.isEmpty == false ? title : description,
                    frame: frame,
                    windowID: statusWindows.first { Self.matches($0.frame, frame) }?.id
                )
                found.append(item)
                newElements[item.id] = child
            }
        }
        elements = newElements
        cached = found.sorted { $0.frame.minX < $1.frame.minX }
        cachedAt = Date()
        return cached
    }

    // MARK: Window correlation

    private struct StatusWindow { let id: CGWindowID; let frame: CGRect }

    private func statusWindowFrames() -> [StatusWindow] {
        guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == Self.statusLayer,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict)
            else { return nil }
            return StatusWindow(id: id, frame: bounds)
        }
    }

    /// AX frames exclude the padding the window adds around the button, so match loosely on centre and row.
    private static func matches(_ window: CGRect, _ ax: CGRect) -> Bool {
        abs(window.midX - ax.midX) <= 4 && abs(window.midY - ax.midY) <= 4 && window.width >= ax.width - 2
    }
}
