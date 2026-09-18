import AppKit
import CoreGraphics
import PrivateAPIs

/// Thin Swift wrapper over the private SkyLight calls. Every method returns a neutral value when the symbols
/// failed to load, so callers fall back to "current Space only" behaviour. Stateless; safe to call off the main thread
/// once `isAvailable` has been evaluated (it triggers the one-time dlsym load).
struct SpaceInfo: Sendable {
    static let isAvailable: Bool = GKPrivateAPIsLoad()

    private var cid: CGSConnectionID { GKMainConnectionID() }

    private func spaceID(from dict: [String: Any]) -> UInt64? {
        if let n = dict["id64"] as? NSNumber { return n.uint64Value }
        if let n = dict["ManagedSpaceID"] as? NSNumber { return n.uint64Value }
        return nil
    }

    private func managedDisplays() -> [[String: Any]] {
        guard Self.isAvailable, let displays = GKCopyManagedDisplaySpaces(cid)?.takeRetainedValue() as? [[String: Any]] else {
            return []
        }
        return displays
    }

    /// 1-based position of every user Space on its display, in the order the system lists them.
    func spaceNumbers() -> [UInt64: Int] {
        var result: [UInt64: Int] = [:]
        for display in managedDisplays() {
            var number = 0
            for space in display["Spaces"] as? [[String: Any]] ?? [] {
                guard let id = spaceID(from: space) else { continue }
                let type = (space["type"] as? NSNumber)?.intValue ?? GKSpaceTypeUser
                guard type == GKSpaceTypeUser else { continue }
                number += 1
                result[id] = number
            }
        }
        return result
    }

    /// Space ids currently shown, one per display.
    func currentSpaceIDs() -> Set<UInt64> {
        var result: Set<UInt64> = []
        for display in managedDisplays() {
            if let current = display["Current Space"] as? [String: Any], let id = spaceID(from: current) {
                result.insert(id)
            }
        }
        if result.isEmpty, Self.isAvailable {
            let active = GKGetActiveSpace(cid)
            if active != 0 { result.insert(active) }
        }
        return result
    }

    /// Every Space on every display (user and full-screen Spaces).
    func allSpaceIDs() -> [UInt64] {
        var result: [UInt64] = []
        for display in managedDisplays() {
            for space in display["Spaces"] as? [[String: Any]] ?? [] {
                if let id = spaceID(from: space) { result.append(id) }
            }
        }
        return result
    }

    /// Spaces a window belongs to. Empty when unknown (or the window is on every Space).
    func spaces(of windowID: CGWindowID) -> [UInt64] {
        guard Self.isAvailable else { return [] }
        let ids = [NSNumber(value: windowID)] as CFArray
        guard let spaces = GKCopySpacesForWindows(cid, Int32(GKSpaceMaskAll), ids)?.takeRetainedValue() as? [NSNumber] else {
            return []
        }
        return spaces.map { $0.uint64Value }
    }

    func isFullScreenSpace(_ spaceID: UInt64) -> Bool {
        Self.isAvailable && GKSpaceGetType(cid, spaceID) == Int32(GKSpaceTypeFullscreen)
    }

    /// Window ids on the given spaces, including invisible (minimized / other Space) ones.
    func windowIDs(inSpaces spaces: [UInt64]) -> [CGWindowID] {
        guard Self.isAvailable, !spaces.isEmpty else { return [] }
        var setTags: UInt64 = 0
        var clearTags: UInt64 = 0
        let array = spaces.map { NSNumber(value: $0) } as CFArray
        guard let ids = GKCopyWindowsWithOptionsAndTags(cid, 0, array, 0x7, &setTags, &clearTags)?.takeRetainedValue() as? [NSNumber] else {
            return []
        }
        return ids.map { $0.uint32Value }
    }

    func bounds(of windowID: CGWindowID) -> CGRect? {
        guard Self.isAvailable else { return nil }
        var rect = CGRect.zero
        return GKGetWindowBounds(cid, windowID, &rect) == .success ? rect : nil
    }

    func level(of windowID: CGWindowID) -> CGWindowLevel? {
        guard Self.isAvailable else { return nil }
        var level: CGWindowLevel = 0
        return GKGetWindowLevel(cid, windowID, &level) == .success ? level : nil
    }

    /// Owning process of a window, via its window server connection.
    func ownerPID(of windowID: CGWindowID) -> pid_t? {
        guard Self.isAvailable else { return nil }
        var owner: CGSConnectionID = 0
        guard GKGetWindowOwner(cid, windowID, &owner) == .success else { return nil }
        var psn = ProcessSerialNumber()
        guard GKGetConnectionPSN(owner, &psn) == .success else { return nil }
        var pid: pid_t = 0
        return GKPIDForProcessSerialNumber(&psn, &pid) && pid > 0 ? pid : nil
    }

    /// Focuses one window of a process without raising its other windows (the publicly documented two-step focus sequence).
    func bringToFront(pid: pid_t, windowID: CGWindowID) -> Bool {
        guard Self.isAvailable else { return false }
        var psn = ProcessSerialNumber()
        guard GKProcessSerialNumberForPID(pid, &psn) else { return false }
        let status = GKSetFrontProcessWithOptions(&psn, windowID, 0x200)
        GKMakeKeyWindow(&psn, windowID)
        return status == .success
    }

    func windowID(of element: AXUIElement) -> CGWindowID? {
        guard Self.isAvailable else { return nil }
        var id: CGWindowID = 0
        return GKAXUIElementGetWindow(element, &id) && id != 0 ? id : nil
    }
}
