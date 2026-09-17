import AppKit
import GarakutaCore
import SwiftUI

/// Owns the NSPanel for one display: geometry, state transitions, hover / swipe / drop gestures, rules.
@MainActor
final class NotchPanelController {
    let displayID: CGDirectDisplayID
    let model: NotchPanelModel
    private let activities: LiveActivityCenter
    private let widgets: WidgetRegistry
    private var panel: NSPanel!
    private var dropView: DropCatchingView!

    private var openTask: Task<Void, Never>?
    private var closeTask: Task<Void, Never>?
    private var shrinkTask: Task<Void, Never>?
    private var swipeAccumulator: CGFloat = 0
    /// One page turn (or open/close) per swipe: set once a gesture has acted, cleared when the fingers lift.
    private var swipeConsumed = false
    /// Which live activity headed the pager at the last change, to keep the visible widget page stable (see restingStateChanged).
    private var lastPrimaryActivityID: String?
    private var hiddenByRules = false
    private var isFullScreen = false
    private var isMissionControl = false
    private var isCapturing = false

    var onStateChange: ((NotchPanelState) -> Void)?

    init(geometry: DisplayGeometry, settings: NotchSettings, activities: LiveActivityCenter, widgets: WidgetRegistry) {
        displayID = geometry.displayID
        self.activities = activities
        self.widgets = widgets
        let layout = NotchLayout(geometry: geometry, appearance: settings.appearance(forDisplay: geometry.displayID))
        model = NotchPanelModel(displayID: geometry.displayID, layout: layout, settings: settings)
        model.onTap = { [weak self] in self?.toggle() }
        makePanel(widgets: widgets)
        apply(settings: settings, geometry: geometry)
        restingStateChanged()
    }

    private func makePanel(widgets: WidgetRegistry) {
        let frame = model.layout.frame(for: .collapsed)
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Not isFloatingPanel: setting it forces NSFloatingWindowLevel (3), which sits below the menu bar and makes
        // AppKit constrain the frame under it. The explicit level above keeps the panel over the notch.
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovableByWindowBackground = false
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false

        let hosting = NSHostingView(rootView: NotchContentView(model: model, activities: activities, widgets: widgets))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        // The window frame is driven by the state machine, never by SwiftUI's ideal size.
        hosting.sizingOptions = []
        let drop = DropCatchingView(frame: frame)
        drop.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: drop.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: drop.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: drop.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: drop.bottomAnchor),
        ])
        drop.onDragEntered = { [weak self] in
            guard let self, model.settings.dragToOpenEnabled else { return false }
            model.isDragTarget = true
            expand(source: .drag)
            return true
        }
        drop.onDragExited = { [weak self] in self?.model.isDragTarget = false }
        drop.onDrop = { [weak self] urls in
            guard let self else { return }
            model.isDragTarget = false
            NotchServices.shared.shelf.add(urls)
            showShelfPage()
        }
        panel.contentView = drop
        self.panel = panel
        dropView = drop
    }

    // MARK: Settings / geometry

    func apply(settings: NotchSettings, geometry: DisplayGeometry) {
        model.settings = settings
        model.layout = NotchLayout(geometry: geometry, appearance: settings.appearance(forDisplay: displayID))
        panel.sharingType = settings.hideFromCapture ? .none : .readOnly
        activities.settings = settings.liveActivities
        // Keep the window sized for the current state.
        panel.setFrame(model.layout.frame(for: model.state), display: true)
        updateVisibility()
    }

    var panelFrame: CGRect? { panel.isVisible ? panel.frame : nil }

    // MARK: State machine

    enum Source { case hover, click, drag, programmatic }

    private var restingState: NotchPanelState {
        activities.primary != nil ? .compact : .collapsed
    }

    func restingStateChanged() {
        let primaryID = activities.primary?.id
        defer { lastPrimaryActivityID = primaryID }
        guard model.state != .expanded else {
            // The activity page is inserted before (or removed from before) the widget pages. Shift the index so
            // whatever the user is looking at, such as the timer they just started, stays on screen.
            if lastPrimaryActivityID == nil, primaryID != nil {
                model.page += 1
            } else if lastPrimaryActivityID != nil, primaryID == nil {
                model.page = max(0, model.page - 1)
            }
            return
        }
        transition(to: restingState)
    }

    func expand(source: Source = .programmatic) {
        guard !model.suspended, !model.expansionBlocked, !hiddenByRules else { return }
        if model.settings.modifierOnlyShow && source == .hover && !NSEvent.modifierFlags.contains(.option) { return }
        closeTask?.cancel()
        transition(to: .expanded)
    }

    func collapse() {
        openTask?.cancel()
        transition(to: restingState)
    }

    func toggle() {
        model.state == .expanded ? collapse() : expand(source: .click)
    }

    private func transition(to new: NotchPanelState) {
        guard new != model.state else { return }
        let old = model.state
        let target = model.layout.frame(for: new)
        shrinkTask?.cancel()
        let growing = target.width * target.height >= panel.frame.width * panel.frame.height
        if growing {
            panel.setFrame(target, display: false)
            model.state = new
        } else {
            model.state = new
            let duration = 0.4 / max(0.25, model.appearance.animationSpeed)
            shrinkTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(duration))
                guard let self, !Task.isCancelled, model.state == new else { return }
                panel.setFrame(target, display: true)
            }
        }
        if new == .expanded { model.page = 0 }
        if old == .expanded { EventBus.shared.publish(.notchPanelCollapsed(displayID: displayID)) }
        if new == .expanded { EventBus.shared.publish(.notchPanelExpanded(displayID: displayID)) }
        onStateChange?(new)
    }

    /// Number of pages the expanded pager currently shows (activity page + widget pages, at least one).
    private var pageCount: Int {
        let widgetPages = widgets.pages(for: model.settings.widgetLayout, pageWidth: model.layout.widgetPageWidth).count
        return max(1, widgetPages + (activities.primary != nil ? 1 : 0))
    }

    private func setPage(_ index: Int) {
        model.page = max(0, min(index, pageCount - 1))
    }

    private func showShelfPage() {
        guard let widgetPage = widgets.pageIndex(of: "shelf", layout: model.settings.widgetLayout, pageWidth: model.layout.widgetPageWidth) else { return }
        setPage(widgetPage + (activities.primary != nil ? 1 : 0))
    }

    // MARK: Hover

    /// Called by the module's shared mouse monitor with the pointer location in screen coordinates.
    func mouseMoved(to location: CGPoint) {
        guard panel.isVisible, !model.suspended else { return }
        let rect = model.layout.hoverRect(for: model.state, padding: model.settings.hoverPadding)
        let inside = rect.contains(location)
        if inside != model.isHovering {
            model.isHovering = inside
            if inside {
                closeTask?.cancel()
                guard model.state != .expanded else { return }
                openTask?.cancel()
                openTask = Task { @MainActor [weak self] in
                    guard let self else { return }
                    try? await Task.sleep(for: .seconds(model.settings.hoverOpenDelay))
                    guard !Task.isCancelled, model.isHovering else { return }
                    expand(source: .hover)
                }
            } else {
                openTask?.cancel()
                guard model.state == .expanded else { return }
                closeTask = Task { @MainActor [weak self] in
                    guard let self else { return }
                    try? await Task.sleep(for: .seconds(model.settings.hoverCloseDelay))
                    guard !Task.isCancelled, !model.isHovering, !model.isDragTarget else { return }
                    collapse()
                }
            }
        }
    }

    /// Two-finger swipes: horizontal pages while expanded, vertical opens/closes (N04).
    func scroll(deltaX: CGFloat, deltaY: CGFloat, phase: NSEvent.Phase, location: CGPoint) {
        guard model.settings.swipeNavigationEnabled, panel.frame.insetBy(dx: -model.settings.hoverPadding, dy: -model.settings.hoverPadding).contains(location) else { return }
        if phase == .began {
            swipeAccumulator = 0
            swipeConsumed = false
        }
        if phase == .changed, !swipeConsumed {
            if model.state == .expanded {
                swipeAccumulator += deltaX
                if abs(swipeAccumulator) > 40 {
                    setPage(model.page + (swipeAccumulator > 0 ? -1 : 1))
                    swipeConsumed = true
                } else if deltaY < -12 {
                    collapse()
                    swipeConsumed = true
                }
            } else if deltaY > 12 {
                expand(source: .click)
                swipeConsumed = true
            }
        }
        if phase == .ended || phase == .cancelled {
            swipeAccumulator = 0
            swipeConsumed = false
        }
    }

    // MARK: Rules (N06 / N07 / N08)

    func spaceStateChanged(fullScreen: Bool, missionControl: Bool) {
        isFullScreen = fullScreen
        isMissionControl = missionControl
        updateVisibility()
    }

    func captureStateChanged(_ capturing: Bool) {
        isCapturing = capturing
        updateVisibility()
    }

    func setSuspended(_ suspended: Bool) {
        model.suspended = suspended
        if suspended && model.state == .expanded { collapse() }
    }

    private func updateVisibility() {
        let s = model.settings
        var hide = !s.isEnabled(onDisplay: displayID)
        if isFullScreen && s.fullScreenRule == .hide { hide = true }
        if isMissionControl && s.missionControlRule == .hide { hide = true }
        if isCapturing && s.autoHideWhileCapturing { hide = true }
        model.expansionBlocked = isFullScreen && s.fullScreenRule == .compactOnly
        if model.expansionBlocked && model.state == .expanded { collapse() }
        hiddenByRules = hide
        if hide {
            if model.state == .expanded { collapse() }
            panel.orderOut(nil)
        } else if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    func show() {
        updateVisibility()
    }

    func close() {
        openTask?.cancel()
        closeTask?.cancel()
        shrinkTask?.cancel()
        panel.orderOut(nil)
        panel.close()
    }
}

/// Container that accepts file drops on behalf of the SwiftUI content (N04 drag-to-open, shelf).
final class DropCatchingView: NSView {
    var onDragEntered: (() -> Bool)?
    var onDragExited: (() -> Void)?
    var onDrop: (([URL]) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        onDragEntered?() == true ? .copy : []
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        onDragExited?()
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        onDrop?(urls)
        return !urls.isEmpty
    }
}
