import SwiftUI

/// Per-module settings tabs. Filled in once each Kit exposes its settings view.
struct ModuleSettingsTabs: View {
    @ObservedObject var model: AppModel

    var body: some View {
        model.menuBar.settingsView().tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }
        model.notch.settingsView.tabItem { Label("Notch", systemImage: "rectangle.topthird.inset.filled") }
        model.switcher.settingsView.tabItem { Label("Switcher", systemImage: "rectangle.on.rectangle") }
    }
}
