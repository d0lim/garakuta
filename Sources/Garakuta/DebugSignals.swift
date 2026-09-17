import AppKit
import Foundation
import SwiftUI

/// Test hooks, enabled only when GARAKUTA_DEBUG_SIGNALS=1: lets a script drive the app without synthetic input,
/// which macOS drops unless the sender has Accessibility.
///   SIGUSR1  toggle the notch panel on the main display
///   SIGUSR2  show the window switcher
///   SIGINFO  open the settings window (SIGINFO is ctrl-T from a terminal)
///   SIGURG   open the setup assistant
///   SIGALRM  render every onboarding step to PNG files in $GARAKUTA_SNAPSHOT_DIR (layout check without a screen)
@MainActor
final class DebugSignals {
    private var sources: [DispatchSourceSignal] = []

    func install(model: AppModel) {
        guard ProcessInfo.processInfo.environment["GARAKUTA_DEBUG_SIGNALS"] == "1" else { return }
        NSLog("debug signal hooks installed")
        add(SIGUSR1) { model.notch.toggle(displayID: nil) }
        add(SIGUSR2) { model.switcher.isVisible ? model.switcher.hide() : model.switcher.show() }
        add(SIGINFO) { model.openSettings() }
        add(SIGURG) { model.openOnboarding() }
        add(SIGALRM) { Self.snapshotOnboarding(model: model) }
    }

    /// Renders each step off-screen so layouts can be reviewed on a machine without Screen Recording access.
    private static func snapshotOnboarding(model: AppModel) {
        guard let dir = ProcessInfo.processInfo.environment["GARAKUTA_SNAPSHOT_DIR"] else { return }
        let onboarding = OnboardingModel(appModel: model)
        for step in OnboardingModel.Step.allCases {
            onboarding.step = step
            let renderer = ImageRenderer(content: OnboardingView(model: onboarding).frame(width: 780, height: 560))
            renderer.scale = 1
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { continue }
            let url = URL(fileURLWithPath: dir).appendingPathComponent("onboarding-\(step.rawValue)-\(step.title.lowercased().replacingOccurrences(of: " ", with: "-")).png")
            try? png.write(to: url)
        }
        NSLog("onboarding snapshots written to %@", dir)
    }

    private func add(_ sig: Int32, _ action: @escaping @MainActor () -> Void) {
        signal(sig, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        source.setEventHandler { Task { @MainActor in action() } }
        source.resume()
        sources.append(source)
    }
}
