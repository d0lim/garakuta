import AppKit
import GarakutaCore
import SwiftUI

/// N01–N08. One panel per display, shared services, settings persisted under "notch".
@MainActor
@Observable
public final class NotchModule: FeatureModule {
    public static let id = "notch"
    public private(set) var isRunning = false

    /// Current settings. Assigning applies them to every panel; call `saveSettings()` to persist.
    public var settings: NotchSettings {
        didSet { applySettings() }
    }

    public let activities = LiveActivityCenter()
    public let widgets: WidgetRegistry
    public var services: NotchServices { NotchServices.shared }

    private var controllers: [CGDirectDisplayID: NotchPanelController] = [:]
    private var mouseMonitors: [Any] = []
    private var screenObserver: NSObjectProtocol?
    private var busToken: UUID?
    private var spaceToken: UUID?

    public init() {
        settings = SettingsStore.shared.load("notch", default: NotchSettings())
        widgets = WidgetRegistry(services: NotchServices.shared)
        let services = NotchServices.shared
        activities.register(TimerActivity(service: services.timer))
        activities.register(NowPlayingActivity(service: services.nowPlaying))
        activities.register(BatteryActivity(service: services.battery))
        activities.settings = settings.liveActivities
        services.nowPlaying.onChange = { [weak self] in
            self?.activities.bump()
            self?.applyAudioLevelState()
        }
        services.timer.onChange = { [weak self] in self?.activities.bump() }
        services.battery.onChange = { [weak self] in self?.activities.bump() }
        activities.onChange = { [weak self] in
            self?.controllers.values.forEach { $0.restingStateChanged() }
        }
    }

    // MARK: FeatureModule

    public func start() throws {
        guard !isRunning else { return }
        isRunning = true
        NotchServices.shared.start()
        NotchServices.shared.nowPlaying.isEnabled = settings.liveActivities.enabledProviders.contains("nowPlaying")
        applyAudioLevelState()
        rebuildControllers()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.rebuildControllers() }
        }

        // Hover tracking: global for pointer outside our windows, local for pointer over them.
        mouseMonitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { _ in
            let location = NSEvent.mouseLocation
            Task { @MainActor in NotchModuleRegistry.current?.pointerMoved(to: location) }
        } as Any)
        mouseMonitors.append(NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { event in
            let location = NSEvent.mouseLocation
            Task { @MainActor in NotchModuleRegistry.current?.pointerMoved(to: location) }
            return event
        } as Any)
        mouseMonitors.append(NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            let dx = event.scrollingDeltaX, dy = event.scrollingDeltaY, phase = event.phase
            let location = NSEvent.mouseLocation
            Task { @MainActor in NotchModuleRegistry.current?.scrolled(dx: dx, dy: dy, phase: phase, at: location) }
            return event
        } as Any)
        mouseMonitors.append(NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { event in
            let dx = event.scrollingDeltaX, dy = event.scrollingDeltaY, phase = event.phase
            let location = NSEvent.mouseLocation
            Task { @MainActor in NotchModuleRegistry.current?.scrolled(dx: dx, dy: dy, phase: phase, at: location) }
        } as Any)
        NotchModuleRegistry.current = self

        // N06: full-screen / Mission Control rules.
        spaceToken = SpaceStateObserver.shared.subscribe { [weak self] state in
            self?.spaceStateChanged(state)
        }
        spaceStateChanged(SpaceStateObserver.shared.state)

        NotchServices.shared.capture.onChange = { [weak self] capturing in
            self?.controllers.values.forEach { $0.captureStateChanged(capturing) }
        }

        // N08: yield to the menu bar's secondary bar.
        busToken = EventBus.shared.subscribe { [weak self] event in
            switch event {
            case .hiddenItemsBarOpened(let id): self?.controllers[id]?.setSuspended(true)
            case .hiddenItemsBarClosed(let id): self?.controllers[id]?.setSuspended(false)
            default: break
            }
        }
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        controllers.values.forEach { $0.close() }
        controllers.removeAll()
        mouseMonitors.forEach { NSEvent.removeMonitor($0) }
        mouseMonitors.removeAll()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        if let busToken { EventBus.shared.unsubscribe(busToken) }
        busToken = nil
        if let spaceToken { SpaceStateObserver.shared.unsubscribe(spaceToken) }
        spaceToken = nil
        NotchServices.shared.capture.onChange = nil
        NotchServices.shared.timer.reset()
        NotchServices.shared.stop()
        if NotchModuleRegistry.current === self { NotchModuleRegistry.current = nil }
    }

    // MARK: Public controls

    public func saveSettings() {
        SettingsStore.shared.save(settings, for: "notch")
    }

    public func expand(displayID: CGDirectDisplayID) { controllers[displayID]?.expand() }
    public func collapse(displayID: CGDirectDisplayID) { controllers[displayID]?.collapse() }

    /// Toggles the panel on the given display, or on the display under the pointer when nil.
    public func toggle(displayID: CGDirectDisplayID? = nil) {
        let target = displayID ?? displayUnderPointer()
        guard let target, let controller = controllers[target] else { return }
        controller.toggle()
    }

    /// Current on-screen frame of the panel (AppKit coordinates), or nil when hidden.
    public func panelFrame(displayID: CGDirectDisplayID) -> CGRect? {
        controllers[displayID]?.panelFrame
    }

    public var panelStates: [CGDirectDisplayID: NotchPanelState] {
        controllers.mapValues { $0.model.state }
    }

    public var settingsView: AnyView { AnyView(NotchSettingsView(module: self)) }

    // MARK: Internals

    private func rebuildControllers() {
        let geometries = DisplayGeometry.all()
        let ids = Set(geometries.map(\.displayID))
        for (id, controller) in controllers where !ids.contains(id) {
            controller.close()
            controllers[id] = nil
        }
        for geometry in geometries {
            if let existing = controllers[geometry.displayID] {
                existing.apply(settings: settings, geometry: geometry)
            } else {
                let controller = NotchPanelController(geometry: geometry, settings: settings, activities: activities, widgets: widgets)
                controllers[geometry.displayID] = controller
                controller.show()
            }
        }
        spaceStateChanged(SpaceStateObserver.shared.state)
    }

    /// The tap on system audio exists only while it is wanted and there is something to show: the setting on,
    /// the module running, and an item actually playing.
    private func applyAudioLevelState() {
        let services = NotchServices.shared
        services.audioLevels.isEnabled = isRunning && settings.audioReactiveBars
            && settings.liveActivities.enabledProviders.contains("nowPlaying")
            && services.nowPlaying.track?.isPlaying == true
    }

    private func applySettings() {
        activities.settings = settings.liveActivities
        NotchServices.shared.nowPlaying.isEnabled = isRunning && settings.liveActivities.enabledProviders.contains("nowPlaying")
        applyAudioLevelState()
        let geometries = Dictionary(uniqueKeysWithValues: DisplayGeometry.all().map { ($0.displayID, $0) })
        for (id, controller) in controllers {
            if let geometry = geometries[id] { controller.apply(settings: settings, geometry: geometry) }
        }
    }

    private func spaceStateChanged(_ state: SpaceStateObserver.State) {
        for (id, controller) in controllers {
            controller.spaceStateChanged(fullScreen: state.fullScreenDisplays.contains(id), missionControl: state.missionControlActive)
        }
    }

    fileprivate func pointerMoved(to location: CGPoint) {
        controllers.values.forEach { $0.mouseMoved(to: location) }
    }

    fileprivate func scrolled(dx: CGFloat, dy: CGFloat, phase: NSEvent.Phase, at location: CGPoint) {
        controllers.values.forEach { $0.scroll(deltaX: dx, deltaY: dy, phase: phase, location: location) }
    }

    private func displayUnderPointer() -> CGDirectDisplayID? {
        let location = NSEvent.mouseLocation
        return DisplayGeometry.all().first { $0.frame.contains(location) }?.displayID ?? controllers.keys.first
    }
}

/// Lets the @Sendable event-monitor closures reach the module without capturing it.
@MainActor
enum NotchModuleRegistry {
    static weak var current: NotchModule?
}
