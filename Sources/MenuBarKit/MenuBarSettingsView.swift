import AppKit
import GarakutaCore
import SwiftUI

/// Settings UI for the menu bar module. Edits `MenuBarModule.settings` directly and saves on every change.
/// Arranging icons is taught, not configured: the one gesture that works everywhere is ⌘-drag in the menu bar itself.
public struct MenuBarSettingsView: View {
    private let module: MenuBarModule

    @State private var settings: MenuBarSettings
    @State private var discovered: [MenuBarItem] = []
    @State private var accessibilityGranted = Permission.accessibility.isGranted
    @State private var screenRecordingGranted = Permission.screenRecording.isGranted
    @State private var newGroupName = ""

    public init(module: MenuBarModule) {
        self.module = module
        _settings = State(initialValue: module.settings)
    }

    public var body: some View {
        Form {
            arrangeSection
            revealSection
            barSection
            autoArrangeSection
            spacersSection
            groupsSection
            permissionsSection
        }
        .formStyle(.grouped)
        .onChange(of: settings) { _, new in module.settings = new }
        .onAppear { refresh() }
    }

    // MARK: Sections

    private var arrangeSection: some View {
        Section {
            ArrangeGuideView()
                .padding(.vertical, 6)
            VStack(alignment: .leading, spacing: 6) {
                step(1, "Hold ⌘ and drag any icon in the menu bar.")
                step(2, "Drop it left of the single divider to hide it, or left of the double divider to always hide it.")
                step(3, "Click ‹ to show the hidden icons again, or use one of the reveal options below.")
            }
            HStack {
                Button(module.isAlwaysHiddenSectionCollapsed ? "Show all sections while I arrange" : "Tuck the sections away") {
                    module.setAlwaysHiddenSectionCollapsed(!module.isAlwaysHiddenSectionCollapsed)
                }
                Text("Both dividers stay visible while the pointer is in the menu bar.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("Arrange the menu bar")
        } footer: {
            Text("Positions are remembered by macOS, so nothing needs to be saved here. Icons of apps that reset their position on launch are put back where you left them.")
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number)")
                .font(.caption.bold())
                .frame(width: 18, height: 18)
                .background(Color.accentColor.opacity(0.2), in: Circle())
            Text(text)
        }
    }

    private var revealSection: some View {
        Section("Show hidden items") {
            Toggle("When hovering over the menu bar", isOn: $settings.revealOnHover)
            if settings.revealOnHover {
                LabeledContent("Hover delay") {
                    Slider(value: $settings.hoverDelay, in: 0...1.5, step: 0.05) { Text("") }
                    Text("\(settings.hoverDelay, specifier: "%.2f") s").monospacedDigit().frame(width: 52)
                }
            }
            Toggle("When clicking an empty area of the menu bar", isOn: $settings.revealOnClickEmptyArea)
            Toggle("When scrolling or swiping in the menu bar", isOn: $settings.revealOnScroll)
            LabeledContent("Keyboard shortcut") {
                HotKeyRecorder(combo: $settings.revealHotKey)
            }
            Toggle("Hide again automatically", isOn: $settings.autoRehide)
            if settings.autoRehide {
                LabeledContent("After") {
                    Slider(value: $settings.autoRehideDelay, in: 0.5...15, step: 0.5) { Text("") }
                    Text("\(settings.autoRehideDelay, specifier: "%.1f") s").monospacedDigit().frame(width: 52)
                }
            }
        }
    }

    private var barSection: some View {
        Section("Hidden items bar") {
            Toggle("Clicking ‹ opens the bar instead of expanding the menu bar", isOn: $settings.secondaryBarEnabled)
            Picker("Position", selection: $settings.barPlacement) {
                ForEach(MenuBarSettings.BarPlacement.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Picker("Icons", selection: $settings.imageMode) {
                ForEach(MenuBarSettings.ImageMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            if settings.imageMode == .captured, !screenRecordingGranted {
                Text("Captured images need Screen Recording; app icons are shown until it is granted.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button("Open the bar now") { module.openHiddenItemsBar() }
        }
    }

    private var autoArrangeSection: some View {
        Section("When the menu bar runs out of room") {
            Toggle("Hide the leftmost icons automatically", isOn: $settings.autoArrangeByWidth)
            LabeledContent("Temporary show duration") {
                Slider(value: $settings.temporarySwapDuration, in: 3...30, step: 1) { Text("") }
                Text("\(Int(settings.temporarySwapDuration)) s").monospacedDigit().frame(width: 52)
            }
            Text("Icons nearest the notch (or the app menus) go first and come back when there is room again. Keep the ones you care about on the right.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var spacersSection: some View {
        Section("Spacers") {
            ForEach($settings.spacers) { $spacer in
                HStack {
                    Text("Spacer")
                    Slider(value: $spacer.length, in: 4...120, step: 2) { Text("") }
                    Text("\(Int(spacer.length)) pt").monospacedDigit().frame(width: 52)
                    Button(role: .destructive) { settings.spacers.removeAll { $0.id == spacer.id } } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                }
            }
            Button("Add spacer") { settings.spacers.append(.init()) }
            Text("A spacer is an empty icon. ⌘-drag it wherever you want a gap.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var groupsSection: some View {
        Section {
            ForEach($settings.groups) { $group in
                HStack {
                    Image(systemName: "square.grid.2x2")
                    TextField("Name", text: $group.name)
                    membersMenu(for: $group)
                    Button(role: .destructive) { settings.groups.removeAll { $0.id == group.id } } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                }
            }
            HStack {
                TextField("New group name", text: $newGroupName)
                Button("Add group") {
                    let name = newGroupName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    settings.groups.append(.init(name: name))
                    newGroupName = ""
                }
            }
        } header: {
            Text("Groups")
        } footer: {
            Text("A group is one icon in the menu bar; clicking it lists its members. Pick the members here, then hide the originals with ⌘-drag.")
        }
    }

    @ViewBuilder
    private func membersMenu(for group: Binding<MenuBarSettings.Group>) -> some View {
        if accessibilityGranted {
            Menu {
                if discovered.isEmpty {
                    Text("No icons found")
                } else {
                    ForEach(discovered, id: \.id) { item in
                        Toggle(item.displayName, isOn: Binding(
                            get: { group.wrappedValue.memberKeys.contains(item.stableKey) },
                            set: { on in
                                if on { group.wrappedValue.memberKeys.append(item.stableKey) }
                                else { group.wrappedValue.memberKeys.removeAll { $0 == item.stableKey } }
                            }
                        ))
                    }
                }
                Divider()
                Button("Refresh list") { refresh() }
            } label: {
                Text("\(group.wrappedValue.memberKeys.count) members")
            }
            .fixedSize()
        } else {
            Text("Grant Accessibility to pick members").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var permissionsSection: some View {
        Section {
            HStack {
                Label("Accessibility", systemImage: accessibilityGranted ? "checkmark.circle.fill" : "xmark.circle")
                Spacer()
                if !accessibilityGranted {
                    Button("Request…") { Permission.accessibility.request(); refresh() }
                }
            }
            HStack {
                Label("Screen Recording", systemImage: screenRecordingGranted ? "checkmark.circle.fill" : "xmark.circle")
                Spacer()
                if !screenRecordingGranted {
                    Button("Request…") { Permission.screenRecording.request(); refresh() }
                }
            }
        } header: {
            Text("Permissions")
        } footer: {
            Text("⌘-drag needs no permission. Accessibility lets the hidden items bar and groups list icons by name and click them; Screen Recording adds captured icon images.")
        }
    }

    // MARK: Helpers

    private func refresh() {
        accessibilityGranted = Permission.accessibility.isGranted
        screenRecordingGranted = Permission.screenRecording.isGranted
        discovered = module.items().map(\.item).sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
}

/// Click, then press a key combination. Backspace clears.
struct HotKeyRecorder: View {
    @Binding var combo: KeyCombo?
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Button(recording ? "Press keys…" : (combo?.displayString ?? "None")) {
                if recording { stop() } else { start() }
            }
            .frame(minWidth: 110)
            if combo != nil, !recording {
                Button { combo = nil } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.borderless)
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = UInt32(event.keyCode)
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            MainActor.assumeIsolated {
                if keyCode == 51 || keyCode == 117 {  // delete / forward delete clears
                    combo = nil
                } else if keyCode == 53 {  // escape cancels
                } else {
                    combo = KeyCombo(keyCode: keyCode, nsModifiers: flags)
                }
                stop()
            }
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
