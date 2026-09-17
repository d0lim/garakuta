import AppKit
import Carbon.HIToolbox
import GarakutaCore
import SwiftUI

/// Settings pane for W01–W02. Edits a copy and calls `onChange` for every change so the module can persist it.
public struct SwitcherSettingsView: View {
    @State private var settings: SwitcherSettings
    @State private var newRuleBundleID = ""
    @State private var newRule: SwitcherSettings.AppRule = .groupAsOne
    private let onChange: (SwitcherSettings) -> Void

    public init(settings: SwitcherSettings, onChange: @escaping (SwitcherSettings) -> Void) {
        _settings = State(initialValue: settings)
        self.onChange = onChange
    }

    public var body: some View {
        Form {
            Section("Trigger") {
                HStack {
                    Text("Shortcut")
                    Spacer()
                    HotKeyRecorder(combo: $settings.trigger)
                        .frame(width: 140, height: 24)
                }
                Text("Add ⇧ to the shortcut to cycle backwards.").font(.caption).foregroundStyle(.secondary)
                Toggle("Select by releasing the modifier keys", isOn: $settings.activateOnModifierRelease)
                HStack {
                    Text("Show after holding for")
                    Slider(value: $settings.holdToShowDelay, in: 0...0.6, step: 0.05)
                    Text(String(format: "%.2f s", settings.holdToShowDelay)).monospacedDigit().frame(width: 52)
                }
            }
            Section("Windows") {
                Toggle("Show minimized windows", isOn: $settings.showMinimized)
                Toggle("Show windows of hidden apps", isOn: $settings.showHiddenApps)
                Toggle("Show windows from other Spaces", isOn: $settings.showOtherSpaces)
                    .disabled(!SpaceInfo.isAvailable)
                if !SpaceInfo.isAvailable {
                    Text("Other Spaces are unavailable: private window server symbols did not load.").font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Only windows on the switcher's screen", isOn: $settings.currentScreenOnly)
                Picker("Show the switcher on", selection: $settings.targetScreen) {
                    ForEach(SwitcherSettings.TargetScreen.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
            }
            Section("Appearance") {
                Toggle("Simple mode (titles and icons only, no thumbnails)", isOn: $settings.simpleMode)
                if !Permission.screenRecording.isGranted {
                    HStack {
                        Text("Thumbnails need Screen Recording permission.").font(.caption).foregroundStyle(.secondary)
                        Button("Request…") { Permission.screenRecording.request() }.controlSize(.small)
                    }
                }
                HStack {
                    Text("Thumbnail width")
                    Slider(value: $settings.thumbnailWidth, in: 140...360, step: 10)
                    Text("\(Int(settings.thumbnailWidth)) pt").monospacedDigit().frame(width: 56)
                }
                Toggle("Minimal decorations (hide app name and badges)", isOn: $settings.minimalDecorations)
                Toggle("Middle click closes the window", isOn: $settings.closeOnMiddleClick)
            }
            Section("Per-app rules") {
                if settings.appRules.isEmpty {
                    Text("No rules. Apps use the default behaviour.").foregroundStyle(.secondary)
                }
                ForEach(settings.appRules.keys.sorted(), id: \.self) { bundleID in
                    HStack {
                        appIcon(bundleID)
                        Text(appName(bundleID)).lineLimit(1)
                        Spacer()
                        Picker("", selection: Binding(
                            get: { settings.appRules[bundleID] ?? .default },
                            set: { settings.appRules[bundleID] = $0 }
                        )) {
                            ForEach(SwitcherSettings.AppRule.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 220)
                        Button(role: .destructive) { settings.appRules[bundleID] = nil } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                    }
                }
                HStack {
                    Picker("Add", selection: $newRuleBundleID) {
                        Text("Choose a running app…").tag("")
                        ForEach(runningApps(), id: \.bundleIdentifier) { app in
                            Text(app.localizedName ?? app.bundleIdentifier ?? "").tag(app.bundleIdentifier ?? "")
                        }
                    }
                    Picker("", selection: $newRule) {
                        ForEach(SwitcherSettings.AppRule.allCases.filter { $0 != .default }, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                    Button("Add") {
                        guard !newRuleBundleID.isEmpty else { return }
                        settings.appRules[newRuleBundleID] = newRule
                        newRuleBundleID = ""
                    }
                    .disabled(newRuleBundleID.isEmpty)
                }
            }
            if !Permission.accessibility.isGranted {
                Section {
                    HStack {
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                        Text("Accessibility permission is required to list minimized windows, read titles, and switch windows.")
                        Spacer()
                        Button("Grant…") { Permission.accessibility.request() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings) { _, new in onChange(new) }
    }

    private func runningApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && settings.appRules[$0.bundleIdentifier!] == nil }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func appName(_ bundleID: String) -> String {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first, let name = app.localizedName { return name }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path)
        }
        return bundleID
    }

    @ViewBuilder
    private func appIcon(_ bundleID: String) -> some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 18, height: 18)
        } else {
            Image(systemName: "app").frame(width: 18, height: 18)
        }
    }
}

/// Click, then press a key combination. Esc cancels.
struct HotKeyRecorder: NSViewRepresentable {
    @Binding var combo: KeyCombo

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.onRecord = { combo = $0 }
        view.combo = combo
        return view
    }

    func updateNSView(_ nsView: RecorderView, context: Context) {
        nsView.combo = combo
        nsView.needsDisplay = true
    }

    final class RecorderView: NSView {
        var combo = KeyCombo(keyCode: 0, modifiers: 0)
        var onRecord: ((KeyCombo) -> Void)?
        private var recording = false { didSet { needsDisplay = true } }

        override var acceptsFirstResponder: Bool { true }
        override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self); recording = true }
        override func resignFirstResponder() -> Bool { recording = false; return true }

        override func keyDown(with event: NSEvent) {
            guard recording else { super.keyDown(with: event); return }
            if Int(event.keyCode) == kVK_Escape { recording = false; return }
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !mods.isEmpty else { NSSound.beep(); return }
            let new = KeyCombo(keyCode: UInt32(event.keyCode), nsModifiers: mods)
            combo = new
            onRecord?(new)
            recording = false
            window?.makeFirstResponder(nil)
        }

        override func draw(_ dirtyRect: NSRect) {
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
            (recording ? NSColor.controlAccentColor.withAlphaComponent(0.15) : NSColor.controlBackgroundColor).setFill()
            path.fill()
            (recording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
            path.stroke()
            let text = recording ? "Press keys…" : combo.displayString
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor]
            let size = text.size(withAttributes: attrs)
            text.draw(at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attrs)
        }
    }
}
