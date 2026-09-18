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
///   SIGWINCH toggle the hidden menu bar section
///   SIGPROF  start or reset the notch timer
///   SIGVTALRM dump the Accessibility tree of Control Center's menu bar extras to the log (Now Playing probe)
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
        add(SIGWINCH) { model.menuBar.toggleHiddenSection() }
        add(SIGVTALRM) { Self.dumpControlCenterExtras() }
        add(SIGPROF) {
            let timer = model.notch.services.timer
            let seconds = Double(ProcessInfo.processInfo.environment["GARAKUTA_DEBUG_TIMER_SECONDS"] ?? "") ?? 25 * 60
            timer.isActive ? timer.reset() : timer.start(seconds)
        }
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

    /// Every attribute of every Control Center menu bar extra, three levels deep, so what the Now Playing item
    /// exposes without being opened can be read off the log.
    private static func dumpControlCenterExtras() {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").first else {
            NSLog("AX dump: Control Center not running"); return
        }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 0.5)
        var extrasRef: AnyObject?
        guard AXUIElementCopyAttributeValue(axApp, "AXExtrasMenuBar" as CFString, &extrasRef) == .success, let extras = extrasRef else {
            NSLog("AX dump: no extras menu bar (trusted=%d)", AXIsProcessTrusted() ? 1 : 0); return
        }
        // swiftlint:disable:next force_cast
        let bar = extras as! AXUIElement
        var childrenRef: AnyObject?
        guard AXUIElementCopyAttributeValue(bar, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { NSLog("AX dump: no children"); return }
        for child in children {
            var idRef: AnyObject?
            _ = AXUIElementCopyAttributeValue(child, kAXIdentifierAttribute as CFString, &idRef)
            guard (idRef as? String) == "com.apple.menuextra.now-playing" else { continue }
            NSLog("AX dump: --- now playing item ---")
            dump(child, depth: 0, maxDepth: 4)
            var actionsRef: CFArray?
            if AXUIElementCopyActionNames(child, &actionsRef) == .success { NSLog("AX dump: actions %@", (actionsRef as? [String] ?? []).joined(separator: ",")) }
            var paramRef: CFArray?
            if AXUIElementCopyParameterizedAttributeNames(child, &paramRef) == .success { NSLog("AX dump: parameterized %@", (paramRef as? [String] ?? []).joined(separator: ",")) }
        }
    }

    private static func dump(_ element: AXUIElement, depth: Int, maxDepth: Int) {
        var namesRef: CFArray?
        let names = AXUIElementCopyAttributeNames(element, &namesRef) == .success ? (namesRef as? [String] ?? []) : []
        var line = String(repeating: "  ", count: depth)
        for name in names where name != kAXChildrenAttribute && name != kAXParentAttribute && name != kAXTopLevelUIElementAttribute && name != kAXWindowAttribute && name != "AXPath" {
            var valueRef: AnyObject?
            guard AXUIElementCopyAttributeValue(element, name as CFString, &valueRef) == .success, let value = valueRef else { continue }
            let text: String
            if let s = value as? String { text = "\"\(s)\"" }
            else if let n = value as? NSNumber { text = n.stringValue }
            else if CFGetTypeID(value) == AXUIElementGetTypeID() { text = "<element>" }
            else if let array = value as? [AnyObject] { text = "[\(array.count)]" }
            else { text = String(describing: value).replacingOccurrences(of: "\n", with: " ").prefix(80).description }
            line += "\(name)=\(text) "
        }
        NSLog("AX dump: %@", line)
        guard depth < maxDepth else { return }
        var childrenRef: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success, let children = childrenRef as? [AXUIElement] {
            for child in children { dump(child, depth: depth + 1, maxDepth: maxDepth) }
        }
    }

    private func add(_ sig: Int32, _ action: @escaping @MainActor () -> Void) {
        signal(sig, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        source.setEventHandler { Task { @MainActor in action() } }
        source.resume()
        sources.append(source)
    }
}
