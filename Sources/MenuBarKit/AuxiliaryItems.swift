import AppKit

/// M05: user-added spacers and group icons. Both are ordinary status items the user positions with ⌘-drag;
/// macOS persists their positions by autosave name.
@MainActor
final class SpacerItem {
    let id: UUID
    let statusItem: NSStatusItem

    static func autosaveName(_ id: UUID) -> String { "com.d0lim.garakuta.spacer.\(id.uuidString)" }

    init(spacer: MenuBarSettings.Spacer) {
        id = spacer.id
        statusItem = NSStatusBar.system.statusItem(withLength: CGFloat(spacer.length))
        statusItem.autosaveName = Self.autosaveName(spacer.id)
        statusItem.isVisible = true
        statusItem.button?.toolTip = "Garakuta spacer"
    }

    func setLength(_ length: Double) {
        statusItem.length = CGFloat(length)
    }

    func remove() {
        NSStatusBar.system.removeStatusItem(statusItem)
        Self.forgetDefaults(id)
    }

    static func forgetDefaults(_ id: UUID) {
        let name = autosaveName(id)
        UserDefaults.standard.removeObject(forKey: "NSStatusItem Preferred Position \(name)")
        UserDefaults.standard.removeObject(forKey: "NSStatusItem Visible \(name)")
    }
}

@MainActor
final class GroupItem {
    let id: UUID
    let statusItem: NSStatusItem
    var onClick: ((UUID) -> Void)?

    static func autosaveName(_ id: UUID) -> String { "com.d0lim.garakuta.group.\(id.uuidString)" }

    init(group: MenuBarSettings.Group) {
        id = group.id
        statusItem = NSStatusBar.system.statusItem(withLength: 24)
        statusItem.autosaveName = Self.autosaveName(group.id)
        statusItem.isVisible = true
        statusItem.button?.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: group.name)
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = group.name
        statusItem.button?.target = self
        statusItem.button?.action = #selector(clicked)
    }

    func update(name: String) {
        statusItem.button?.toolTip = name
    }

    @objc private func clicked() {
        onClick?(id)
    }

    func remove() {
        NSStatusBar.system.removeStatusItem(statusItem)
        let name = Self.autosaveName(id)
        UserDefaults.standard.removeObject(forKey: "NSStatusItem Preferred Position \(name)")
        UserDefaults.standard.removeObject(forKey: "NSStatusItem Visible \(name)")
    }
}
