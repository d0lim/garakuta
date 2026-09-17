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
@MainActor
public final class HotKeyCenter {
    public static let shared = HotKeyCenter()

    private struct Registration {
        let ref: EventHotKeyRef
        let handler: () -> Void
    }

    private var registrations: [UInt32: Registration] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?

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

    /// Returns a token to unregister with, or nil if the system refused (usually a conflict).
    @discardableResult
    public func register(_ combo: KeyCombo, handler: @escaping () -> Void) -> UInt32? {
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x474B5254), id: id)  // 'GKRT'
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return nil }
        registrations[id] = Registration(ref: ref, handler: handler)
        return id
    }

    public func unregister(_ token: UInt32) {
        guard let reg = registrations.removeValue(forKey: token) else { return }
        UnregisterEventHotKey(reg.ref)
    }

    private func fire(_ id: UInt32) {
        registrations[id]?.handler()
    }
}
