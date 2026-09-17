import GarakutaCore
import MenuBarKit
import NotchKit
import SwiftUI

struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                // No ScrollView: every step is designed to fit, and ImageRenderer (used for layout snapshots)
                // cannot draw scroll content.
                stepContent
                    .padding(28)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                Divider()
                footer
            }
        }
        .frame(width: 780, height: 560)
        .animation(.spring(duration: 0.35), value: model.step)
    }

    // MARK: Chrome

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Garakuta").font(.title2.bold()).padding(.top, 24).padding(.bottom, 12)
            ForEach(model.visibleSteps) { step in
                HStack(spacing: 10) {
                    Image(systemName: step.systemImage).frame(width: 18)
                    Text(step.title)
                    Spacer()
                    if stepIsDone(step) { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.green) }
                }
                .padding(.vertical, 6).padding(.horizontal, 10)
                .background(model.step == step ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(model.step == step ? .primary : .secondary)
                .contentShape(Rectangle())
                .onTapGesture { model.step = step }
            }
            Spacer()
        }
        .padding(16)
        .frame(width: 232)
        .background(.quaternary.opacity(0.4))
    }

    private var footer: some View {
        HStack {
            Button("Back") { model.back() }.disabled(model.isFirst)
            Spacer()
            if model.isLast {
                Button("Finish") { model.finish() }.keyboardShortcut(.defaultAction)
            } else {
                Button("Continue") { model.next() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
    }

    private func stepIsDone(_ step: OnboardingModel.Step) -> Bool {
        switch step {
        case .conflicts: model.conflicts.isEmpty && !model.shortcutTaken
        case .accessibility: model.accessibilityGranted
        case .screenRecording: model.screenRecordingGranted
        case .notchTour: model.notchTried
        case .switcherTour: model.switcherTried
        default: false
        }
    }

    // MARK: Steps

    @ViewBuilder
    private var stepContent: some View {
        switch model.step {
        case .welcome: welcome
        case .conflicts: conflicts
        case .accessibility: accessibility
        case .screenRecording: screenRecording
        case .menuBarTour: menuBarTour
        case .notchTour: notchTour
        case .switcherTour: switcherTour
        case .finish: finish
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
                header("Welcome to Garakuta", "A menu bar organizer, a notch panel and a window switcher. Pick what you want to start with; you can change it any time in Settings.")
            }
            VStack(spacing: 10) {
                ForEach(OnboardingModel.Bundle.allCases) { bundle in
                    Button { model.apply(bundle: bundle) } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: model.bundle == bundle ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(model.bundle == bundle ? Color.accentColor : .secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(bundle.title).font(.headline)
                                Text(bundle.detail).font(.callout).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .background(model.bundle == bundle ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04),
                                    in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("Modules start immediately as you pick, so the rest of this assistant is live.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var conflicts: some View {
        VStack(alignment: .leading, spacing: 18) {
            header("Other utilities", "Some apps do the same job as a Garakuta module. Running both at once leads to icons jumping around or a shortcut that only one of them receives.")
            if model.conflicts.isEmpty && !model.shortcutTaken {
                statusBanner(ok: true, model.accessibilityGranted
                             ? "No other menu bar manager detected, and the system accepted the switcher shortcut."
                             : "The system accepted the switcher shortcut. Detecting other menu bar managers needs Accessibility; if icons jump around after enabling Garakuta, quit the other manager.")
            } else {
                ForEach(model.conflicts) { conflict in
                    conflictRow("\(conflict.name) is running", "manages menu bar icons too; both would fight over positions") {
                        Button("Quit \(conflict.name)") { model.quit(conflict) }
                    }
                }
                if model.shortcutTaken {
                    conflictRow("Another app owns \(model.switcherHotKey)", "only one app can receive a shortcut; quit it or change the switcher shortcut in Settings") { EmptyView() }
                }
                Text("This list updates by itself once the other app has quit.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func conflictRow<Action: View>(_ title: String, _ detail: String, @ViewBuilder action: () -> Action) -> some View {
        HStack(alignment: .top) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            action()
        }
        .padding(12)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }

    private var accessibility: some View {
        VStack(alignment: .leading, spacing: 18) {
            header("Accessibility permission", "Optional, but it unlocks everything that reads or moves other apps' menu bar items and windows. macOS requires it for any app that does this.")
            statusBanner(ok: model.accessibilityGranted,
                         model.accessibilityGranted ? "Accessibility is granted." : "Not granted yet. Garakuta runs in a reduced mode.")
            HStack(alignment: .top, spacing: 16) {
                capabilityList("Works without it", ok: true, [
                    "Hide and reveal menu bar sections",
                    "Hover, click, scroll and hotkey reveal",
                    "You ⌘-drag icons between sections yourself",
                    "The whole notch panel",
                    "Switcher: list and focus windows (press ⌥⇥ again to cycle, Return to pick)",
                ])
                capabilityList("Needs it", ok: false, [
                    "Listing other apps' icons by name and section",
                    "Moving icons automatically (arrange by width, groups)",
                    "Clicking icons from the hidden items bar",
                    "Switcher: minimized windows and releasing ⌥ to select",
                ])
            }
            if !model.accessibilityGranted {
                HStack {
                    Button("Grant Accessibility…") { model.requestAccessibility() }.buttonStyle(.borderedProminent)
                    Button("Open System Settings") { model.openPrivacyPane("Privacy_Accessibility") }
                }
                Text("The checkmark appears within a second after you turn Garakuta on in System Settings.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Already switched on but still not detected? The grant belongs to an earlier copy of Garakuta. Reset it, then grant again.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("Reset…") { model.resetAccessibility() }.controlSize(.small)
                }
            }
        }
    }

    private var screenRecording: some View {
        VStack(alignment: .leading, spacing: 18) {
            header("Screen Recording permission", "Optional. Only used to draw real icon images in the hidden items bar and live thumbnails in the switcher. Without it you get app icons instead.")
            statusBanner(ok: model.screenRecordingGranted,
                         model.screenRecordingGranted ? "Screen Recording is granted." : "Not granted. Icons and titles are used instead of captures.")
            if !model.screenRecordingGranted {
                HStack {
                    Button("Grant Screen Recording…") { model.requestScreenRecording() }
                    Button("Open System Settings") { model.openPrivacyPane("Privacy_ScreenCapture") }
                }
            }
            Text("Captured images stay on this Mac and are never written to disk.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var menuBarTour: some View {
        VStack(alignment: .leading, spacing: 18) {
            header("Your menu bar, in three sections", "Garakuta adds a ‹ button and two dividers. Everything left of the single divider is hidden, everything left of the double divider is always hidden. Hold ⌘ and drag any icon across a divider to move it.")
            ArrangeGuideView()
            HStack(spacing: 12) {
                Button(model.hiddenSectionCollapsed ? "Show hidden items now" : "Hide them again") { model.toggleHiddenSection() }
                    .buttonStyle(.borderedProminent)
                Text(model.hiddenSectionCollapsed ? "Hidden section is collapsed." : "Hidden section is showing. Look at the menu bar.")
                    .foregroundStyle(.secondary)
            }
            Toggle("Also reveal when I hover the menu bar", isOn: Binding(get: { model.revealOnHover }, set: { model.revealOnHover = $0 }))
            if model.accessibilityGranted {
                HStack(spacing: 18) {
                    ForEach(MenuBarSection.allCases, id: \.self) { section in
                        Label("\(model.itemCounts[section] ?? 0) \(section.displayName.lowercased())", systemImage: "app.badge")
                    }
                }
                .font(.callout).foregroundStyle(.secondary)
                Text("Spacers, groups and the hidden items bar live in Settings › Menu Bar.").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Grant Accessibility so the hidden items bar and groups can list icons by name.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var notchTour: some View {
        VStack(alignment: .leading, spacing: 18) {
            header("The notch panel", "Move the pointer to the notch, click it, or drop a file on it. Displays without a notch get a floating pill under the menu bar.")
            statusBanner(ok: model.notchTried,
                         model.notchTried ? "You opened the panel. Nice." : (model.notchExpandedSomewhere ? "Panel is open." : "Try it now: hover or click the notch."))
            HStack {
                Button("Open it for me") { model.demoNotch() }
                Picker("Size", selection: Binding(get: { presetTag(model.notchPreset) }, set: { model.notchPreset = preset(for: $0) })) {
                    Text("Compact").tag("compact")
                    Text("Wide").tag("wide")
                }
                .pickerStyle(.segmented).frame(width: 200)
            }
            Text("Two-finger swipe left or right to page between widgets. Swipe down to close. Colors, offsets, full-screen rules and widgets are in Settings › Notch.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func presetTag(_ p: NotchSettings.SizePreset) -> String {
        if case .wide = p { return "wide" }
        return "compact"
    }

    private func preset(for tag: String) -> NotchSettings.SizePreset { tag == "wide" ? .wide : .compact }

    private var switcherTour: some View {
        VStack(alignment: .leading, spacing: 18) {
            header("Window switcher", "Hold \(model.switcherHotKey) to see every window, including minimized ones and windows on other Spaces. Type to filter.")
            statusBanner(ok: model.switcherTried,
                         model.switcherTried ? "You opened the switcher." : "Try it now: press \(model.switcherHotKey).")
            HStack {
                Button("Open it for me") { model.demoSwitcher() }
                Toggle("Simple mode (titles only, no thumbnails)", isOn: Binding(get: { model.switcherSimpleMode }, set: { model.switcherSimpleMode = $0 }))
            }
            if !model.accessibilityGranted {
                Text("Without Accessibility, releasing ⌥ cannot be detected: press \(model.switcherHotKey) again to cycle and Return to pick.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Change the shortcut, exclude apps or group an app into one tile in Settings › Switcher.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var finish: some View {
        VStack(alignment: .leading, spacing: 18) {
            header("You're set", "Garakuta lives in the menu bar. Right-click its icon for settings, or run this assistant again from Settings › General.")
            VStack(alignment: .leading, spacing: 8) {
                summaryRow("Menu bar", model.appModel.settings.menuBarEnabled)
                summaryRow("Notch panel", model.appModel.settings.notchEnabled)
                summaryRow("Window switcher", model.appModel.settings.switcherEnabled)
                summaryRow("Accessibility", model.accessibilityGranted)
                summaryRow("Screen Recording", model.screenRecordingGranted)
            }
            Toggle("Launch Garakuta at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
            if let error = model.launchAtLoginError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }

    // MARK: Pieces

    private func header(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.largeTitle.bold())
            Text(subtitle).font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func statusBanner(ok: Bool, _ text: String) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(ok ? .green : .secondary)
                .symbolEffect(.bounce, value: ok)
            Text(text)
            Spacer()
        }
        .padding(12)
        .background((ok ? Color.green : Color.secondary).opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }

    private func capabilityList(_ title: String, ok: Bool, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            ForEach(items, id: \.self) { item in
                Label(item, systemImage: ok ? "checkmark" : "lock")
                    .font(.callout)
                    .foregroundStyle(ok ? .primary : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }

    private func summaryRow(_ title: String, _ on: Bool) -> some View {
        HStack {
            Image(systemName: on ? "checkmark.circle.fill" : "minus.circle").foregroundStyle(on ? .green : .secondary)
            Text(title)
        }
    }
}
