import AppKit
import CoreGraphics

/// Tracks whether each display is showing a full-screen app or Mission Control (N06). Heuristic, public-API only:
/// a full-screen app owns an on-screen layer-0 window whose bounds equal the display; Mission Control shows a
/// Dock-owned window covering the display on a layer other than the Dock's own.
@MainActor
public final class SpaceStateObserver {
    public struct State: Equatable, Sendable {
        public var fullScreenDisplays: Set<CGDirectDisplayID> = []
        public var missionControlActive = false
    }

    public static let shared = SpaceStateObserver()

    public private(set) var state = State()

    /// Single-handler convenience; prefer `subscribe` when more than one module listens.
    public var onChange: ((State) -> Void)? {
        didSet { updatePolling() }
    }

    private var subscribers: [UUID: (State) -> Void] = [:]
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?

    private init() {}

    /// Starts observing on the first subscriber and stops polling when the last one leaves.
    @discardableResult
    public func subscribe(_ handler: @escaping (State) -> Void) -> UUID {
        let id = UUID()
        subscribers[id] = handler
        updatePolling()
        return id
    }

    public func unsubscribe(_ id: UUID) {
        subscribers[id] = nil
        updatePolling()
    }

    private var hasListeners: Bool { onChange != nil || !subscribers.isEmpty }

    private func updatePolling() {
        if hasListeners, timer == nil {
            let center = NSWorkspace.shared.notificationCenter
            for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
                observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.refresh() }
                })
            }
            // Mission Control has no notification; poll cheaply while someone cares.
            timer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
            refresh()
        } else if !hasListeners, timer != nil {
            timer?.invalidate()
            timer = nil
            observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
            observers.removeAll()
        }
    }

    public func refresh() {
        let new = Self.compute()
        if new != state {
            state = new
            onChange?(new)
            for handler in subscribers.values { handler(new) }
        }
    }

    private static func compute() -> State {
        var result = State()
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return result
        }
        let displays = DisplayGeometry.all()
        // Convert each display frame to CG (top-left origin) coordinates.
        guard let main = NSScreen.screens.first else { return result }
        let cgFrames: [(CGDirectDisplayID, CGRect)] = displays.map { d in
            (d.displayID, CGRect(x: d.frame.minX, y: main.frame.maxY - d.frame.maxY, width: d.frame.width, height: d.frame.height))
        }
        for info in list {
            guard let layer = info[kCGWindowLayer as String] as? Int,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict) else { continue }
            let owner = info[kCGWindowOwnerName as String] as? String ?? ""
            for (id, frame) in cgFrames where abs(bounds.minX - frame.minX) < 1 && abs(bounds.minY - frame.minY) < 1
                && abs(bounds.width - frame.width) < 1 && abs(bounds.height - frame.height) < 1 {
                if layer == 0 && owner != "Dock" && owner != "Window Server" {
                    result.fullScreenDisplays.insert(id)
                } else if owner == "Dock" && layer != 20 {
                    result.missionControlActive = true
                }
            }
        }
        return result
    }
}
