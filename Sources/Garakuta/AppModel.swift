import AppKit
import Combine
import GarakutaCore
import MenuBarKit
import NotchKit
import SwiftUI
import WindowSwitcherKit

/// Owns the three feature modules and app-level settings.
@MainActor
final class AppModel: ObservableObject {
    @Published var settings = AppSettings.load()
    @Published var grantedPermissions: Set<Permission> = []

    let menuBar = MenuBarModule()
    let notch = NotchModule()
    let switcher = WindowSwitcherModule()

    /// Permission state has no notification; poll while a settings view is visible.
    let permissionTicker = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    init() {
        refreshPermissions()
        menuBar.onOpenSettingsRequested = { [weak self] in self?.openSettings() }
    }

    func refreshPermissions() {
        let granted = Set(Permission.allCases.filter(\.isGranted))
        if granted != grantedPermissions {
            grantedPermissions = granted
            switcher.permissionsMayHaveChanged()
        }
        if !granted.contains(.screenRecording) {
            Task { @MainActor [weak self] in
                if await Permission.probeScreenRecording() { self?.refreshPermissions() }
            }
        }
    }

    func applyModuleStates() {
        apply(menuBar, enabled: settings.menuBarEnabled)
        apply(notch, enabled: settings.notchEnabled)
        apply(switcher, enabled: settings.switcherEnabled)
    }

    private func apply(_ module: any FeatureModule, enabled: Bool) {
        if enabled, !module.isRunning {
            do { try module.start() } catch {
                NSLog("%@ failed to start: %@", type(of: module).id, String(describing: error))
            }
        } else if !enabled, module.isRunning {
            module.stop()
        }
    }

    private let settingsWindow = SettingsWindowController()
    private let onboardingWindow = OnboardingWindowController()

    func openSettings() {
        settingsWindow.show(model: self)
    }

    func openOnboarding() {
        onboardingWindow.show(appModel: self)
    }

    /// First launch, or forced with GARAKUTA_FORCE_ONBOARDING=1.
    var shouldShowOnboarding: Bool {
        !settings.onboardingCompleted || ProcessInfo.processInfo.environment["GARAKUTA_FORCE_ONBOARDING"] == "1"
    }
}
