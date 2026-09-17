import AppKit
import GarakutaCore
import MenuBarKit
import NotchKit
import SwiftUI
import WindowSwitcherKit

@main
struct GarakutaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // The menu bar icon is an NSStatusItem owned by MenuBarModule so its position can be pinned next to
        // the section separators. This scene hosts the settings window only.
        Settings {
            SettingsRootView(model: delegate.model)
        }
    }
}

struct SettingsRootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        TabView {
            GeneralSettingsView(model: model)
                .tabItem { Label("General", systemImage: "gearshape") }
            ModuleSettingsTabs(model: model)
        }
        .frame(minWidth: 620, minHeight: 480)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private let debugSignals = DebugSignals()

    func applicationDidFinishLaunching(_ notification: Notification) {
        debugSignals.install(model: model)
        NSApp.setActivationPolicy(.accessory)
        for permission in Permission.allCases {
            NSLog("permission %@: %@", permission.rawValue, permission.isGranted ? "granted" : "missing")
        }
        model.applyModuleStates()
        if model.shouldShowOnboarding {
            model.openOnboarding()
        }
    }

    /// Return to accessory mode when the settings window closes so no Dock icon lingers.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model.openSettings()
        return true
    }
}
