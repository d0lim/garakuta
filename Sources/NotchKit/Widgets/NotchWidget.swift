import SwiftUI

/// A tile that can be placed on the expanded panel (N02).
@MainActor
public protocol NotchWidget: AnyObject {
    var id: String { get }
    var title: String { get }
    var systemImage: String { get }
    /// Minimum size the tile needs; wide tiles get a page to themselves.
    var minSize: CGSize { get }
    func makeView() -> AnyView
}

@MainActor
public final class WidgetRegistry {
    public private(set) var widgets: [String: NotchWidget] = [:]

    init(services: NotchServices) {
        register(NowPlayingWidget(service: services.nowPlaying))
        register(ShelfWidget(store: services.shelf))
        register(TimerWidget(service: services.timer))
        register(ClockWidget())
        register(BatteryWidget(service: services.battery))
    }

    public func register(_ widget: NotchWidget) {
        widgets[widget.id] = widget
    }

    public var all: [NotchWidget] { widgets.values.sorted { $0.title < $1.title } }

    /// Widgets in layout order, skipping disabled or unknown ids.
    func ordered(by layout: [NotchSettings.WidgetLayoutEntry]) -> [NotchWidget] {
        layout.filter(\.enabled).compactMap { widgets[$0.id] }
    }

    /// Packs widgets into pages: a widget wider than half the page width takes a whole page, others pair up.
    func pages(for layout: [NotchSettings.WidgetLayoutEntry], pageWidth: CGFloat) -> [[NotchWidget]] {
        var pages: [[NotchWidget]] = []
        var current: [NotchWidget] = []
        for widget in ordered(by: layout) {
            if widget.minSize.width > pageWidth / 2 - 12 {
                if !current.isEmpty { pages.append(current); current = [] }
                pages.append([widget])
            } else {
                current.append(widget)
                if current.count == 2 { pages.append(current); current = [] }
            }
        }
        if !current.isEmpty { pages.append(current) }
        return pages
    }

    /// Index of the widget page that contains `widgetID`, or nil when it is disabled.
    func pageIndex(of widgetID: String, layout: [NotchSettings.WidgetLayoutEntry], pageWidth: CGFloat) -> Int? {
        pages(for: layout, pageWidth: pageWidth).firstIndex { $0.contains { $0.id == widgetID } }
    }
}

// MARK: - Built-in widgets

@MainActor final class NowPlayingWidget: NotchWidget {
    let id = "nowPlaying", title = "Now Playing", systemImage = "music.note"
    let minSize = CGSize(width: 380, height: 120)
    private let service: NowPlayingService
    init(service: NowPlayingService) { self.service = service }
    func makeView() -> AnyView { AnyView(NowPlayingWidgetView(service: service)) }
}

@MainActor final class ShelfWidget: NotchWidget {
    let id = "shelf", title = "Shelf", systemImage = "tray.full"
    let minSize = CGSize(width: 380, height: 120)
    private let store: ShelfStore
    init(store: ShelfStore) { self.store = store }
    func makeView() -> AnyView { AnyView(ShelfWidgetView(store: store)) }
}

@MainActor final class TimerWidget: NotchWidget {
    let id = "timer", title = "Timer", systemImage = "timer"
    let minSize = CGSize(width: 200, height: 120)
    private let service: TimerService
    init(service: TimerService) { self.service = service }
    func makeView() -> AnyView { AnyView(TimerWidgetView(service: service)) }
}

@MainActor final class ClockWidget: NotchWidget {
    let id = "clock", title = "Clock", systemImage = "clock"
    let minSize = CGSize(width: 200, height: 120)
    func makeView() -> AnyView { AnyView(ClockWidgetView()) }
}

@MainActor final class BatteryWidget: NotchWidget {
    let id = "battery", title = "Battery", systemImage = "battery.100percent"
    let minSize = CGSize(width: 200, height: 120)
    private let service: BatteryService
    init(service: BatteryService) { self.service = service }
    func makeView() -> AnyView { AnyView(BatteryWidgetView(service: service)) }
}
