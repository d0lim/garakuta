import AppKit
import ApplicationServices
import GarakutaCore

/// Which windows the user has been in, most recent last. The order the switcher lists windows in when it follows
/// use rather than stacking. Stamps come from focus events; windows never seen focused keep their stacking order.
@MainActor
final class FocusHistory {
    private(set) var stamps: [CGWindowID: UInt64] = [:]
    private var counter: UInt64 = 0
    var onChange: ((CGWindowID) -> Void)?

    func stamp(of id: CGWindowID) -> UInt64 { stamps[id] ?? 0 }

    /// Records that `id` was just focused.
    func touch(_ id: CGWindowID) {
        counter += 1
        stamps[id] = counter
        onChange?(id)
    }

    /// Gives unknown windows their stacking order as a starting point (front first), without touching known ones.
    func seed(frontToBack ids: [CGWindowID]) {
        for id in ids.reversed() where stamps[id] == nil {
            counter += 1
            stamps[id] = counter
        }
    }

    func forget(_ ids: Set<CGWindowID>) {
        for id in ids { stamps[id] = nil }
    }
}

/// Listens to every regular app for the events that change the window list or the focus order, through one
/// Accessibility observer per process, and to the workspace for apps coming and going. A wedged app costs only
/// its own observer; the run loop source is the main one, so callbacks arrive on the main actor.
@MainActor
final class WindowEventObserver {
    /// A window gained focus (its id when the Accessibility bridge could name it).
    var onFocus: ((pid_t, CGWindowID?) -> Void)?
    /// Windows were created, destroyed, renamed, minimized or restored; the list wants a refresh.
    var onStructureChanged: ((pid_t) -> Void)?
    /// An app was activated; the frontmost app changed.
    var onAppActivated: ((NSRunningApplication) -> Void)?

    private var observers: [pid_t: AXObserver] = [:]
    private var workspaceObservers: [NSObjectProtocol] = []
    private let spaces = SpaceInfo()

    private static let notifications: [String] = [
        kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification, kAXWindowCreatedNotification,
        kAXUIElementDestroyedNotification, kAXTitleChangedNotification, kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification, kAXApplicationActivatedNotification,
    ]

    func start() {
        stop()
        WindowEventObserver.current = self
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated {
                WindowEventObserver.current?.attach(app)
                WindowEventObserver.current?.onStructureChanged?(app.processIdentifier)
            }
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated {
                WindowEventObserver.current?.detach(app.processIdentifier)
                WindowEventObserver.current?.onStructureChanged?(app.processIdentifier)
            }
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { WindowEventObserver.current?.appActivated(app) }
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { WindowEventObserver.current?.onStructureChanged?(0) }
        })
        if AXIsProcessTrusted() {
            for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
                attach(app)
            }
        }
    }

    func stop() {
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()
        for pid in Array(observers.keys) { detach(pid) }
        if WindowEventObserver.current === self { WindowEventObserver.current = nil }
    }

    /// Attaches observers to apps launched before Accessibility was granted.
    func attachMissing() {
        guard AXIsProcessTrusted() else { return }
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && observers[app.processIdentifier] == nil {
            attach(app)
        }
    }

    private func attach(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard pid != ProcessInfo.processInfo.processIdentifier, observers[pid] == nil, AXIsProcessTrusted() else { return }
        var observer: AXObserver?
        guard AXObserverCreate(pid, WindowEventObserver.callback, &observer) == .success, let observer else { return }
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, 0.25)
        let refcon = UnsafeMutableRawPointer(bitPattern: Int(pid))
        var added = 0
        for name in Self.notifications where AXObserverAddNotification(observer, element, name as CFString, refcon) == .success {
            added += 1
        }
        guard added > 0 else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
    }

    private func detach(_ pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    private func appActivated(_ app: NSRunningApplication) {
        onAppActivated?(app)
        // The app's own focus notification usually follows; when it does not (the app answers no AX), the
        // activation still names its focused window after one bounded read.
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.2)
        if let focused: AXUIElement = AX.attribute(element, kAXFocusedWindowAttribute) {
            onFocus?(app.processIdentifier, spaces.windowID(of: focused))
        } else {
            onFocus?(app.processIdentifier, nil)
        }
    }

    private func handle(pid: pid_t, windowID: CGWindowID?, notification: String) {
        switch notification {
        case kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification:
            onFocus?(pid, windowID)
        case kAXApplicationActivatedNotification:
            break  // the workspace notification carries this
        default:
            onStructureChanged?(pid)
        }
    }

    private static var current: WindowEventObserver?

    /// Arrives on the main thread (the observer's run loop source is the main one). The element is resolved to a
    /// window id here, before crossing into the actor, because it is a CF object without a Sendable annotation.
    private static let callback: AXObserverCallback = { _, element, notification, refcon in
        let pid = pid_t(Int(bitPattern: refcon))
        let name = notification as String
        let windowID = name == kAXFocusedWindowChangedNotification || name == kAXMainWindowChangedNotification
            ? SpaceInfo().windowID(of: element) : nil
        MainActor.assumeIsolated {
            WindowEventObserver.current?.handle(pid: pid, windowID: windowID, notification: name)
        }
    }
}
