import AppKit
import GarakutaCore
import SwiftUI

/// Permissions, module switches, and a warning when another menu bar manager is running.
struct GeneralSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("Modules") {
                Toggle("Menu bar management", isOn: binding(\.menuBarEnabled))
                Toggle("Notch panel", isOn: binding(\.notchEnabled))
                Toggle("Window switcher", isOn: binding(\.switcherEnabled))
            }
            Section("Permissions") {
                permissionRow("Accessibility", .accessibility,
                              detail: "Needed to read and rearrange other apps' menu bar items and to list windows.")
                permissionRow("Screen Recording", .screenRecording,
                              detail: "Optional. Enables real icon images in the hidden items bar and window thumbnails.")
            }
            if !conflicts.isEmpty || model.switcher.hotKeyConflict {
                Section("Conflicts") {
                    if !conflicts.isEmpty {
                        Label("\(conflicts.joined(separator: ", ")) also manages the menu bar. Two managers fight over icon positions; quit it before using menu bar management.",
                              systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    if model.switcher.hotKeyConflict {
                        Label("Another app already owns the switcher shortcut \(model.switcher.settings.trigger.displayString). Quit it or pick a different shortcut in the Switcher tab.",
                              systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
            }
            Section("Setup") {
                LabeledContent("Setup assistant") {
                    Button("Run again…") { model.openOnboarding() }
                }
            }
            Section("Storage") {
                LabeledContent("Settings folder") {
                    Button(SettingsStore.shared.directory.path) {
                        NSWorkspace.shared.open(SettingsStore.shared.directory)
                    }
                    .buttonStyle(.link)
                }
            }
        }
        .formStyle(.grouped)
        .onReceive(model.permissionTicker) { _ in model.refreshPermissions() }
    }

    private var conflicts: [String] {
        guard model.menuBar.isRunning else { return [] }
        return model.menuBar.otherMenuBarManagers().map(\.name).sorted()
    }

    private func binding(_ keyPath: WritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { newValue in
                model.settings[keyPath: keyPath] = newValue
                model.settings.save()
                model.applyModuleStates()
            }
        )
    }

    @ViewBuilder
    private func permissionRow(_ title: String, _ permission: Permission, detail: String) -> some View {
        let granted = model.grantedPermissions.contains(permission)
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button("Request…") {
                    permission.request()
                    model.refreshPermissions()
                }
            }
        }
    }
}
