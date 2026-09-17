import Foundation

/// Cross-module events. Kits never import each other; they talk through this bus (see N08 in the plan).
public enum AppEvent: Sendable {
    case notchPanelExpanded(displayID: UInt32)
    case notchPanelCollapsed(displayID: UInt32)
    case hiddenItemsBarOpened(displayID: UInt32)
    case hiddenItemsBarClosed(displayID: UInt32)
    case screenParametersChanged
}

@MainActor
public final class EventBus {
    public static let shared = EventBus()
    private var subscribers: [UUID: (AppEvent) -> Void] = [:]

    public init() {}

    @discardableResult
    public func subscribe(_ handler: @escaping (AppEvent) -> Void) -> UUID {
        let id = UUID()
        subscribers[id] = handler
        return id
    }

    public func unsubscribe(_ id: UUID) {
        subscribers[id] = nil
    }

    public func publish(_ event: AppEvent) {
        for handler in subscribers.values { handler(event) }
    }
}
