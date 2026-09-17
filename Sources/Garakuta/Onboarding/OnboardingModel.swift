import AppKit
import Combine
import GarakutaCore
import MenuBarKit
import NotchKit
import ServiceManagement
import SwiftUI
import WindowSwitcherKit

/// State for the setup assistant. Everything the steps show is polled live so the user sees permission grants,
/// quit conflicting apps, and their own notch / switcher interactions reflected immediately.
@MainActor
final class OnboardingModel: ObservableObject {
    enum Step: Int, CaseIterable, Identifiable {
        case welcome, conflicts, accessibility, screenRecording, menuBarTour, notchTour, switcherTour, finish
        var id: Int { rawValue }

        var title: String {
            switch self {
            case .welcome: "Welcome"
            case .conflicts: "Other utilities"
            case .accessibility: "Accessibility"
            case .screenRecording: "Screen capture"
            case .menuBarTour: "Menu bar"
            case .notchTour: "Notch"
            case .switcherTour: "Switcher"
            case .finish: "Done"
            }
        }

        var systemImage: String {
            switch self {
            case .welcome: "sparkles"
            case .conflicts: "exclamationmark.triangle"
            case .accessibility: "hand.raised"
            case .screenRecording: "rectangle.dashed.badge.record"
            case .menuBarTour: "menubar.rectangle"
            case .notchTour: "rectangle.topthird.inset.filled"
            case .switcherTour: "rectangle.on.rectangle"
            case .finish: "checkmark.seal"
            }
        }
    }

    enum Bundle: String, CaseIterable, Identifiable {
        case everything, menuBar, windows, notch
        var id: String { rawValue }
        var title: String {
            switch self {
            case .everything: "Everything"
            case .menuBar: "Menu bar only"
            case .windows: "Window management"
            case .notch: "Notch only"
            }
        }
        var detail: String {
            switch self {
            case .everything: "Menu bar cleanup, notch panel and the window switcher."
            case .menuBar: "Hide and reveal menu bar icons. Nothing else."
            case .windows: "Option-Tab switcher plus the menu bar cleanup."
            case .notch: "Island-style panel around the notch with music, timer and shelf."
            }
        }
    }

    /// Another app that manages the menu bar, detected by behaviour (a status item wider than the screen).
    struct ConflictingApp: Identifiable {
        let id: pid_t
        let name: String
        let app: NSRunningApplication
    }

    let appModel: AppModel
    var onFinish: (() -> Void)?

    @Published var step: Step = .welcome
    @Published var bundle: Bundle = .everything

    // Live state
    @Published var conflicts: [ConflictingApp] = []
    /// The switcher shortcut is owned by another app (registration failed).
    @Published var shortcutTaken = false
    @Published var accessibilityGranted = false
    @Published var screenRecordingGranted = false
    @Published var hiddenSectionCollapsed = true
    @Published var itemCounts: [MenuBarSection: Int] = [:]
    @Published var notchExpandedSomewhere = false
    @Published var notchTried = false
    @Published var switcherVisible = false
    @Published var switcherTried = false
    @Published var launchAtLogin = false
    @Published var launchAtLoginError: String?

    private var ticker: AnyCancellable?

    init(appModel: AppModel) {
        self.appModel = appModel
        bundle = Self.bundle(for: appModel.settings)
        refresh()
        ticker = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            self?.refresh()
        }
    }

    // MARK: Steps

    var visibleSteps: [Step] {
        Step.allCases.filter { step in
            switch step {
            case .conflicts: appModel.settings.menuBarEnabled || appModel.settings.switcherEnabled
            case .menuBarTour: appModel.settings.menuBarEnabled
            case .notchTour: appModel.settings.notchEnabled
            case .switcherTour: appModel.settings.switcherEnabled
            default: true
            }
        }
    }

    var isFirst: Bool { visibleSteps.first == step }
    var isLast: Bool { visibleSteps.last == step }

    func next() {
        guard let index = visibleSteps.firstIndex(of: step), index + 1 < visibleSteps.count else { return }
        step = visibleSteps[index + 1]
    }

    func back() {
        guard let index = visibleSteps.firstIndex(of: step), index > 0 else { return }
        step = visibleSteps[index - 1]
    }

    // MARK: Bundle

    func apply(bundle: Bundle) {
        self.bundle = bundle
        var s = appModel.settings
        switch bundle {
        case .everything: (s.menuBarEnabled, s.notchEnabled, s.switcherEnabled) = (true, true, true)
        case .menuBar: (s.menuBarEnabled, s.notchEnabled, s.switcherEnabled) = (true, false, false)
        case .windows: (s.menuBarEnabled, s.notchEnabled, s.switcherEnabled) = (true, false, true)
        case .notch: (s.menuBarEnabled, s.notchEnabled, s.switcherEnabled) = (false, true, false)
        }
        appModel.settings = s
        s.save()
        appModel.applyModuleStates()
    }

    private static func bundle(for s: AppSettings) -> Bundle {
        switch (s.menuBarEnabled, s.notchEnabled, s.switcherEnabled) {
        case (true, false, false): .menuBar
        case (true, false, true): .windows
        case (false, true, false): .notch
        default: .everything
        }
    }

    // MARK: Live refresh

    func refresh() {
        conflicts = appModel.menuBar.isRunning
            ? appModel.menuBar.otherMenuBarManagers().compactMap { pid, name in
                NSRunningApplication(processIdentifier: pid).map { ConflictingApp(id: pid, name: name, app: $0) }
            }
            : []
        shortcutTaken = appModel.switcher.isRunning && appModel.switcher.hotKeyConflict
        accessibilityGranted = Permission.accessibility.isGranted
        screenRecordingGranted = Permission.screenRecording.isGranted
        appModel.refreshPermissions()

        if appModel.menuBar.isRunning {
            hiddenSectionCollapsed = appModel.menuBar.isHiddenSectionCollapsed
            if accessibilityGranted, step == .menuBarTour {
                var counts: [MenuBarSection: Int] = [:]
                for (_, section) in appModel.menuBar.items() { counts[section, default: 0] += 1 }
                itemCounts = counts
            }
        }
        if appModel.notch.isRunning {
            notchExpandedSomewhere = appModel.notch.panelStates.values.contains(.expanded)
            if notchExpandedSomewhere, step == .notchTour { notchTried = true }
        }
        if appModel.switcher.isRunning {
            switcherVisible = appModel.switcher.isVisible
            if switcherVisible, step == .switcherTour { switcherTried = true }
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: Actions

    func quit(_ conflict: ConflictingApp) {
        conflict.app.terminate()
    }

    func requestAccessibility() { Permission.accessibility.request() }
    func resetAccessibility() {
        Permission.accessibility.reset()
        Permission.accessibility.request()
    }
    func requestScreenRecording() { Permission.screenRecording.request() }

    func openPrivacyPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    func toggleHiddenSection() { appModel.menuBar.toggleHiddenSection() }

    var revealOnHover: Bool {
        get { appModel.menuBar.settings.revealOnHover }
        set { appModel.menuBar.settings.revealOnHover = newValue; objectWillChange.send() }
    }

    var notchPreset: NotchSettings.SizePreset {
        get { appModel.notch.settings.appearance.sizePreset }
        set {
            appModel.notch.settings.appearance.sizePreset = newValue
            appModel.notch.saveSettings()
            objectWillChange.send()
        }
    }

    func demoNotch() { appModel.notch.toggle(displayID: nil) }

    var switcherHotKey: String { appModel.switcher.settings.trigger.displayString }

    var switcherSimpleMode: Bool {
        get { appModel.switcher.settings.simpleMode }
        set { appModel.switcher.settings.simpleMode = newValue; objectWillChange.send() }
    }

    func demoSwitcher() { appModel.switcher.show() }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func finish() {
        ticker?.cancel()
        var s = appModel.settings
        s.onboardingCompleted = true
        appModel.settings = s
        s.save()
        onFinish?()
    }
}
