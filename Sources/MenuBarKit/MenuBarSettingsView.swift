import AppKit
import GarakutaCore
import SwiftUI

/// Settings UI for the menu bar module. Edits `MenuBarModule.settings` directly and saves on every change.
public struct MenuBarSettingsView: View {
    private let module: MenuBarModule

    @State private var settings: MenuBarSettings
    @State private var discovered: [(item: MenuBarItem, section: MenuBarSection)] = []
    @State private var accessibilityGranted = Permission.accessibility.isGranted
    @State private var screenRecordingGranted = Permission.screenRecording.isGranted
    @State private var newGroupName = ""
    @State private var statusMessage = ""

    public init(module: MenuBarModule) {
        self.module = module
        _settings = State(initialValue: module.settings)
    }

    public var body: some View {
        Form {
            permissionsSection
            revealSection
            barSection
            arrangeSection
            itemsSection
            spacersSection
            groupsSection
        }
        .formStyle(.grouped)
        .onChange(of: settings) { _, new in module.settings = new }
        .onAppear { refresh() }
    }

    // MARK: Sections

    private var permissionsSection: some View {
        Section("Permissions") {
            HStack {
                Label("Accessibility", systemImage: accessibilityGranted ? "checkmark.circle.fill" : "xmark.circle")
                Spacer()
                if !accessibilityGranted {
                    Button("Request…") { Permission.accessibility.request(); refresh() }
                }
            }
            HStack {
                Label("Screen Recording (captured icons only)", systemImage: screenRecordingGranted ? "checkmark.circle.fill" : "xmark.circle")
                Spacer()
                if !screenRecordingGranted {
                    Button("Request…") { Permission.screenRecording.request(); refresh() }
                }
            }
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
            Toggle("Clicking the Garakuta icon opens the bar instead of expanding the menu bar", isOn: $settings.secondaryBarEnabled)
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

    private var arrangeSection: some View {
        Section("Automatic arrangement") {
            Toggle("Hide the lowest-priority items when the menu bar runs out of room", isOn: $settings.autoArrangeByWidth)
            LabeledContent("Temporary show duration") {
                Slider(value: $settings.temporarySwapDuration, in: 3...30, step: 1) { Text("") }
                Text("\(Int(settings.temporarySwapDuration)) s").monospacedDigit().frame(width: 52)
            }
            Text("Priority follows the order of the item list below; drag to reorder. Items not in the list are hidden first.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var itemsSection: some View {
        Section {
            if !accessibilityGranted {
                Text("Grant Accessibility to list other apps' menu bar items.").foregroundStyle(.secondary)
            } else if discovered.isEmpty {
                Text("No items found.").foregroundStyle(.secondary)
            } else {
                List {
                    ForEach(orderedDiscovered, id: \.item.id) { entry in
                        HStack {
                            if let icon = NSRunningApplication(processIdentifier: entry.item.ownerPID)?.icon {
                                Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                            }
                            Text(entry.item.displayName).lineLimit(1)
                            Spacer()
                            Picker("", selection: Binding(
                                get: { entry.section },
                                set: { newSection in moveItem(entry.item, to: newSection) }
                            )) {
                                ForEach(MenuBarSection.allCases, id: \.self) { Text($0.displayName).tag($0) }
                            }
                            .labelsHidden()
                            .frame(width: 140)
                            Menu {
                                ForEach(settings.groups) { group in
                                    Button(group.memberKeys.contains(entry.item.stableKey) ? "Remove from \(group.name)" : "Add to \(group.name)") {
                                        toggleMembership(of: entry.item, in: group.id)
                                    }
                                }
                                if settings.groups.isEmpty { Text("No groups yet") }
                            } label: {
                                Image(systemName: "square.grid.2x2")
                            }
                            .menuStyle(.borderlessButton)
                            .frame(width: 28)
                        }
                    }
                    .onMove { from, to in reorderPriority(from: from, to: to) }
                }
                .frame(minHeight: 160)
            }
            if !statusMessage.isEmpty {
                Text(statusMessage).font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            HStack {
                Text("Menu bar items")
                Spacer()
                Button("Refresh") { refresh() }
            }
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
            Text("Position spacers by ⌘-dragging them in the menu bar.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var groupsSection: some View {
        Section("Groups") {
            ForEach($settings.groups) { $group in
                HStack {
                    Image(systemName: "square.grid.2x2")
                    TextField("Name", text: $group.name)
                    Text("\(group.memberKeys.count) items").foregroundStyle(.secondary)
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
            Text("A group shows as one icon in the menu bar; clicking it lists its members. Assign members with the grid button in the item list.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Helpers

    private var orderedDiscovered: [(item: MenuBarItem, section: MenuBarSection)] {
        let order = settings.priorityOrder
        return discovered.sorted { a, b in
            let ra = order.firstIndex(of: a.item.stableKey) ?? Int.max
            let rb = order.firstIndex(of: b.item.stableKey) ?? Int.max
            if ra != rb { return ra < rb }
            return a.item.frame.minX > b.item.frame.minX
        }
    }

    private func refresh() {
        accessibilityGranted = Permission.accessibility.isGranted
        screenRecordingGranted = Permission.screenRecording.isGranted
        discovered = module.items()
    }

    private func moveItem(_ item: MenuBarItem, to section: MenuBarSection) {
        statusMessage = "Moving \(item.displayName)…"
        Task { @MainActor in
            do {
                try await module.moveWithRetry(item, to: section)
                statusMessage = ""
            } catch {
                statusMessage = "Could not move \(item.displayName): \(error)"
            }
            settings = module.settings
            refresh()
        }
    }

    private func reorderPriority(from: IndexSet, to: Int) {
        var keys = orderedDiscovered.map(\.item.stableKey)
        keys.move(fromOffsets: from, toOffset: to)
        settings.priorityOrder = keys
    }

    private func toggleMembership(of item: MenuBarItem, in groupID: UUID) {
        guard let index = settings.groups.firstIndex(where: { $0.id == groupID }) else { return }
        if let at = settings.groups[index].memberKeys.firstIndex(of: item.stableKey) {
            settings.groups[index].memberKeys.remove(at: at)
        } else {
            settings.groups[index].memberKeys.append(item.stableKey)
        }
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
