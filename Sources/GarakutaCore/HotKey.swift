import AppKit
import Carbon.HIToolbox

/// A global keyboard shortcut. Backed by Carbon's RegisterEventHotKey, which works without Accessibility and
/// swallows the key event so the frontmost app never sees it.
public struct KeyCombo: Codable, Hashable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32  // Carbon modifier mask: cmdKey, optionKey, controlKey, shiftKey

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public init(keyCode: UInt32, nsModifiers: NSEvent.ModifierFlags) {
        var mask: UInt32 = 0
        if nsModifiers.contains(.command) { mask |= UInt32(cmdKey) }
        if nsModifiers.contains(.option) { mask |= UInt32(optionKey) }
        if nsModifiers.contains(.control) { mask |= UInt32(controlKey) }
        if nsModifiers.contains(.shift) { mask |= UInt32(shiftKey) }
        self.init(keyCode: keyCode, modifiers: mask)
    }

    public var nsModifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        return flags
    }

    public var displayString: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + KeyCombo.keyName(keyCode)
    }

    static func keyName(_ code: UInt32) -> String {
        switch Int(code) {
        case kVK_Tab: return "⇥"
        case kVK_Space: return "Space"
        case kVK_Escape: return "⎋"
        case kVK_Return: return "↩"
        case kVK_ANSI_Grave: return "`"
        default: break
        }
        let source = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        guard let layoutPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return "#\(code)" }
        let data = unsafeBitCast(layoutPtr, to: CFData.self) as Data
        var deadKeys: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = data.withUnsafeBytes { raw -> OSStatus in
            let layout = raw.baseAddress!.assumingMemoryBound(to: UCKeyboardLayout.self)
            return UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  UInt32(kUCKeyTranslateNoDeadKeysBit), &deadKeys, 4, &length, &chars)
        }
        guard status == noErr, length > 0 else { return "#\(code)" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}

/// Registers global hot keys and dispatches presses on the main actor.
///
/// Two backends. Carbon's RegisterEventHotKey works without any permission and swallows the key for the frontmost
/// app, but the system's own shortcuts (⌘⇥ and friends) reach the Dock before it. Those are taken with an event
/// tap inserted at the head of the session, which needs Accessibility; the tap returns nothing for a matching
/// press so the system switcher never sees it.
@MainActor
public final class HotKeyCenter {
    public static let shared = HotKeyCenter()

    private enum Backend {
        case carbon(EventHotKeyRef)
        case tap
    }

    private struct Registration {
        let combo: KeyCombo
        var backend: Backend?
        let handler: () -> Void
    }

    private var registrations: [UInt32: Registration] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?
    private var tap: KeyEventTap?
    private var suspended = false
    private var recording: KeyRecording?

    private init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let id = hotKeyID.id
            Task { @MainActor in HotKeyCenter.shared.fire(id) }
            return noErr
        }, 1, &spec, nil, &eventHandler)
    }

    /// True for combinations the system claims for itself, which only the event tap can take.
    public static func needsEventTap(_ combo: KeyCombo) -> Bool {
        combo.modifiers & UInt32(cmdKey) != 0 && (Int(combo.keyCode) == kVK_Tab || Int(combo.keyCode) == kVK_ANSI_Grave)
    }

    /// Whether `combo` can be registered right now: system-owned combinations need Accessibility.
    public static func canRegister(_ combo: KeyCombo) -> Bool {
        !needsEventTap(combo) || AXIsProcessTrusted()
    }

    /// Returns a token to unregister with, or nil if the system refused (usually a conflict) or the combination
    /// needs Accessibility that has not been granted.
    @discardableResult
    public func register(_ combo: KeyCombo, handler: @escaping () -> Void) -> UInt32? {
        let id = nextID
        nextID += 1
        var registration = Registration(combo: combo, backend: nil, handler: handler)
        if !suspended {
            guard let backend = activate(combo, id: id) else { return nil }
            registration.backend = backend
        } else if !Self.canRegister(combo) {
            return nil
        }
        registrations[id] = registration
        return id
    }

    public func unregister(_ token: UInt32) {
        guard let reg = registrations.removeValue(forKey: token) else { return }
        deactivate(reg, id: token)
    }

    /// Takes every registered key back from the system, for as long as it takes to record a new one.
    public func suspend() {
        guard !suspended else { return }
        suspended = true
        for (id, reg) in registrations {
            deactivate(reg, id: id)
            registrations[id]?.backend = nil
        }
    }

    public func resume() {
        guard suspended else { return }
        suspended = false
        for (id, reg) in registrations where reg.backend == nil {
            registrations[id]?.backend = activate(reg.combo, id: id)
        }
    }

    private func activate(_ combo: KeyCombo, id: UInt32) -> Backend? {
        if Self.needsEventTap(combo) {
            guard AXIsProcessTrusted() else { return nil }
            let tap = self.tap ?? KeyEventTap()
            self.tap = tap
            guard tap.add(combo, id: id, owner: self) else { return nil }
            return .tap
        }
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x474B5254), id: id)  // 'GKRT'
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return nil }
        return .carbon(ref)
    }

    private func deactivate(_ reg: Registration, id: UInt32) {
        switch reg.backend {
        case .carbon(let ref): UnregisterEventHotKey(ref)
        case .tap: tap?.remove(id: id)
        case nil: break
        }
    }

    fileprivate func fire(_ id: UInt32) {
        registrations[id]?.handler()
    }

    // MARK: Recording

    /// Waits for the next key press with at least one modifier and hands it over; nil when Esc cancelled.
    /// Every registered key is suspended meanwhile so pressing the current shortcut records rather than fires,
    /// and with Accessibility the press is taken with a tap so even ⌘⇥ can be recorded.
    public func recordNextKey(_ completion: @escaping @MainActor (KeyCombo?) -> Void) {
        cancelRecording()
        suspend()
        recording = KeyRecording(owner: self) { [weak self] combo in
            guard let self else { return }
            self.recording = nil
            self.resume()
            completion(combo)
        }
    }

    public var isRecording: Bool { recording != nil }

    public func cancelRecording() {
        guard let recording else { return }
        self.recording = nil
        recording.stop()
        resume()
    }
}

/// One active tap over key presses at the session level. Presses matching a registered combination are swallowed
/// and reported; everything else passes through untouched.
@MainActor
final class KeyEventTap {
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var combos: [UInt32: KeyCombo] = [:]
    private weak var owner: HotKeyCenter?

    static var current: KeyEventTap?

    func add(_ combo: KeyCombo, id: UInt32, owner: HotKeyCenter) -> Bool {
        self.owner = owner
        if port == nil, !install() { return false }
        combos[id] = combo
        return true
    }

    func remove(id: UInt32) {
        combos[id] = nil
        if combos.isEmpty { uninstall() }
    }

    private func install() -> Bool {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: KeyEventTap.callback, userInfo: nil) else {
            return false
        }
        self.port = port
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        KeyEventTap.current = self
        return true
    }

    private func uninstall() {
        if let port { CGEvent.tapEnable(tap: port, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        port = nil
        source = nil
        if KeyEventTap.current === self { KeyEventTap.current = nil }
    }

    /// The id of the registration matching a press, if any.
    private func match(keyCode: UInt32, modifiers: UInt32) -> UInt32? {
        combos.first { $0.value.keyCode == keyCode && $0.value.modifiers == modifiers }?.key
    }

    static func carbonModifiers(_ flags: CGEventFlags) -> UInt32 {
        var mask: UInt32 = 0
        if flags.contains(.maskCommand) { mask |= UInt32(cmdKey) }
        if flags.contains(.maskAlternate) { mask |= UInt32(optionKey) }
        if flags.contains(.maskControl) { mask |= UInt32(controlKey) }
        if flags.contains(.maskShift) { mask |= UInt32(shiftKey) }
        return mask
    }

    private static let callback: CGEventTapCallBack = { _, type, event, _ in
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            MainActor.assumeIsolated {
                if let port = KeyEventTap.current?.port { CGEvent.tapEnable(tap: port, enable: true) }
            }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }
        let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
        let modifiers = carbonModifiers(event.flags)
        let swallowed: Bool = MainActor.assumeIsolated {
            guard let tap = KeyEventTap.current, let id = tap.match(keyCode: keyCode, modifiers: modifiers) else { return false }
            tap.owner?.fire(id)
            return true
        }
        return swallowed ? nil : Unmanaged.passUnretained(event)
    }
}

/// Captures one key press for a shortcut recorder: with Accessibility through a tap so the system's own shortcuts
/// can be recorded too, otherwise through a local monitor on our own windows.
@MainActor
final class KeyRecording {
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var monitor: Any?
    private let completion: @MainActor (KeyCombo?) -> Void
    private weak var owner: HotKeyCenter?

    static var current: KeyRecording?

    init(owner: HotKeyCenter, completion: @escaping @MainActor (KeyCombo?) -> Void) {
        self.owner = owner
        self.completion = completion
        KeyRecording.current = self
        if AXIsProcessTrusted(), installTap() { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = UInt32(event.keyCode)
            let modifiers = KeyCombo(keyCode: keyCode, nsModifiers: event.modifierFlags.intersection([.command, .option, .control, .shift])).modifiers
            MainActor.assumeIsolated { KeyRecording.current?.received(keyCode: keyCode, modifiers: modifiers) }
            return nil
        }
    }

    func stop() {
        if let port { CGEvent.tapEnable(tap: port, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let monitor { NSEvent.removeMonitor(monitor) }
        port = nil
        source = nil
        monitor = nil
        if KeyRecording.current === self { KeyRecording.current = nil }
    }

    private func installTap() -> Bool {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: KeyRecording.callback, userInfo: nil) else { return false }
        self.port = port
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }

    /// Esc cancels; a bare key without modifiers is refused so a shortcut always needs a modifier.
    private func received(keyCode: UInt32, modifiers: UInt32) {
        if Int(keyCode) == kVK_Escape {
            finish(nil)
        } else if modifiers != 0 {
            finish(KeyCombo(keyCode: keyCode, modifiers: modifiers))
        } else {
            NSSound.beep()
        }
    }

    private func finish(_ combo: KeyCombo?) {
        stop()
        completion(combo)
    }

    private static let callback: CGEventTapCallBack = { _, type, event, _ in
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }
        let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
        let modifiers = KeyEventTap.carbonModifiers(event.flags)
        MainActor.assumeIsolated { KeyRecording.current?.received(keyCode: keyCode, modifiers: modifiers) }
        return nil
    }
}
