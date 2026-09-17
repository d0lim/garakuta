import GarakutaCore
import SwiftUI

/// Edits every NotchSettings field. Changes apply live and persist when the view disappears or on Save.
public struct NotchSettingsView: View {
    @Bindable var module: NotchModule
    @State private var selectedDisplay: CGDirectDisplayID?

    public init(module: NotchModule) {
        self.module = module
    }

    public var body: some View {
        Form {
            generalSection
            appearanceSection(title: "Appearance", appearance: $module.settings.appearance)
            rulesSection
            widgetsSection
            activitiesSection
            displaysSection
            HStack {
                Spacer()
                Button("Save") { module.saveSettings() }.keyboardShortcut("s")
            }
        }
        .formStyle(.grouped)
        .onDisappear { module.saveSettings() }
    }

    private var generalSection: some View {
        Section("General") {
            Toggle("Enable notch panel", isOn: $module.settings.enabled)
            LabeledSlider(title: "Hover open delay", value: $module.settings.hoverOpenDelay, range: 0...1.5, unit: "s")
            LabeledSlider(title: "Hover close delay", value: $module.settings.hoverCloseDelay, range: 0...2, unit: "s")
            LabeledSlider(title: "Hover area padding", value: $module.settings.hoverPadding, range: 0...40, unit: "pt")
            Toggle("Open only while holding ⌥", isOn: $module.settings.modifierOnlyShow)
            Toggle("Two-finger swipe to switch pages", isOn: $module.settings.swipeNavigationEnabled)
            Toggle("Open when dragging files onto the notch", isOn: $module.settings.dragToOpenEnabled)
        }
    }

    private func appearanceSection(title: String, appearance: Binding<NotchSettings.Appearance>) -> some View {
        Section(title) {
            Picker("Size", selection: presetBinding(appearance)) {
                Text("Compact").tag(0)
                Text("Wide").tag(1)
                Text("Custom").tag(2)
            }
            if case .custom(let w, let h) = appearance.wrappedValue.sizePreset {
                LabeledSlider(title: "Width", value: Binding(
                    get: { w }, set: { appearance.wrappedValue.sizePreset = .custom(width: $0, height: h) }
                ), range: 240...1000, unit: "pt")
                LabeledSlider(title: "Height", value: Binding(
                    get: { h }, set: { appearance.wrappedValue.sizePreset = .custom(width: w, height: $0) }
                ), range: 80...500, unit: "pt")
            }
            LabeledSlider(title: "Corner radius", value: appearance.cornerRadius, range: 0...40, unit: "pt")
            ColorPicker("Background", selection: Binding(
                get: { appearance.wrappedValue.background.color },
                set: { appearance.wrappedValue.background = NotchSettings.RGBA($0) }
            ), supportsOpacity: true)
            LabeledSlider(title: "Animation speed", value: appearance.animationSpeed, range: 0.5...2.5, unit: "×")
            LabeledSlider(title: "Horizontal offset", value: appearance.xOffset, range: -300...300, unit: "pt")
            Picker("Island on displays without a notch", selection: appearance.islandPlacement) {
                Text("Inside the menu bar").tag(NotchSettings.IslandPlacement.menuBar)
                Text("Below the menu bar").tag(NotchSettings.IslandPlacement.belowMenuBar)
            }
            if appearance.wrappedValue.islandPlacement == .belowMenuBar {
                LabeledSlider(title: "Vertical offset", value: appearance.yOffset, range: 0...60, unit: "pt")
            }
            LabeledSlider(title: "Island width", value: appearance.pillWidth, range: 80...400, unit: "pt")
            LabeledSlider(title: "Island height", value: appearance.pillHeight, range: 16...48, unit: "pt")
        }
    }

    private func presetBinding(_ appearance: Binding<NotchSettings.Appearance>) -> Binding<Int> {
        Binding(
            get: {
                switch appearance.wrappedValue.sizePreset {
                case .compact: 0
                case .wide: 1
                case .custom: 2
                }
            },
            set: { index in
                switch index {
                case 0: appearance.wrappedValue.sizePreset = .compact
                case 1: appearance.wrappedValue.sizePreset = .wide
                default:
                    let s = appearance.wrappedValue.sizePreset.expandedSize
                    appearance.wrappedValue.sizePreset = .custom(width: s.width, height: s.height)
                }
            }
        )
    }

    private var rulesSection: some View {
        Section("Rules") {
            Picker("In full-screen apps", selection: $module.settings.fullScreenRule) {
                ForEach(NotchSettings.FullScreenRule.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Picker("In Mission Control", selection: $module.settings.missionControlRule) {
                ForEach(NotchSettings.MissionControlRule.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Toggle("Hide from screen sharing and screenshots", isOn: $module.settings.hideFromCapture)
            Toggle("Hide while a recording app is running", isOn: $module.settings.autoHideWhileCapturing)
            Text("Detection covers the built-in screenshot toolbar, OBS, Loom and Snagit only. Hiding from capture works regardless.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var widgetsSection: some View {
        Section("Widgets") {
            List {
                ForEach($module.settings.widgetLayout) { $entry in
                    HStack {
                        Image(systemName: module.widgets.widgets[entry.id]?.systemImage ?? "questionmark")
                            .frame(width: 20)
                        Text(module.widgets.widgets[entry.id]?.title ?? entry.id)
                        Spacer()
                        Toggle("", isOn: $entry.enabled).labelsHidden()
                    }
                }
                .onMove { from, to in module.settings.widgetLayout.move(fromOffsets: from, toOffset: to) }
            }
            .frame(minHeight: 160)
            Text("Drag to reorder. Wide widgets get a page each; others share a page in pairs.")
                .font(.caption).foregroundStyle(.secondary)
            let missing = module.widgets.all.filter { w in !module.settings.widgetLayout.contains { $0.id == w.id } }
            if !missing.isEmpty {
                ForEach(missing, id: \.id) { widget in
                    Button("Add \(widget.title)") {
                        module.settings.widgetLayout.append(.init(id: widget.id, enabled: true))
                    }
                }
            }
        }
    }

    private var activitiesSection: some View {
        Section("Live Activities") {
            List {
                ForEach(module.settings.liveActivities.priorityOrder, id: \.self) { id in
                    HStack {
                        Text(module.activities.providers.first { $0.id == id }?.title ?? id)
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { module.settings.liveActivities.enabledProviders.contains(id) },
                            set: { on in
                                if on { module.settings.liveActivities.enabledProviders.insert(id) }
                                else { module.settings.liveActivities.enabledProviders.remove(id) }
                            }
                        )).labelsHidden()
                    }
                }
                .onMove { from, to in module.settings.liveActivities.priorityOrder.move(fromOffsets: from, toOffset: to) }
            }
            .frame(minHeight: 110)
            Text("Top of the list wins the primary slot. Now Playing follows whatever app the system reports as playing: music players, browsers, podcasts and video alike.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var displaysSection: some View {
        Section("Per-display overrides") {
            let displays = DisplayGeometry.all()
            Picker("Display", selection: $selectedDisplay) {
                Text("Choose…").tag(CGDirectDisplayID?.none)
                ForEach(displays, id: \.displayID) { d in
                    Text(displayName(d)).tag(CGDirectDisplayID?.some(d.displayID))
                }
            }
            if let id = selectedDisplay {
                let key = String(id)
                let override = module.settings.displayOverrides[key] ?? .init()
                Toggle("Override enabled state", isOn: Binding(
                    get: { override.enabled != nil },
                    set: { on in
                        var o = module.settings.displayOverrides[key] ?? .init()
                        o.enabled = on ? module.settings.enabled : nil
                        module.settings.displayOverrides[key] = o
                    }
                ))
                if let enabled = override.enabled {
                    Toggle("Enabled on this display", isOn: Binding(
                        get: { enabled },
                        set: { module.settings.displayOverrides[key]?.enabled = $0 }
                    ))
                }
                Toggle("Override appearance", isOn: Binding(
                    get: { override.appearance != nil },
                    set: { on in
                        var o = module.settings.displayOverrides[key] ?? .init()
                        o.appearance = on ? module.settings.appearance : nil
                        module.settings.displayOverrides[key] = o
                    }
                ))
                if override.appearance != nil {
                    appearanceSection(title: "Appearance for this display", appearance: Binding(
                        get: { module.settings.displayOverrides[key]?.appearance ?? module.settings.appearance },
                        set: { module.settings.displayOverrides[key]?.appearance = $0 }
                    ))
                }
            }
        }
    }

    private func displayName(_ d: DisplayGeometry) -> String {
        let name = NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == d.displayID }?.localizedName
        return "\(name ?? "Display \(d.displayID)")\(d.hasNotch ? " (notch)" : "")"
    }
}

private struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let unit: String

    var body: some View {
        HStack {
            Text(title)
            Slider(value: $value, in: range)
            Text(String(format: value < 10 ? "%.2f%@" : "%.0f%@", value, unit))
                .monospacedDigit()
                .frame(width: 64, alignment: .trailing)
                .foregroundStyle(.secondary)
        }
    }
}
