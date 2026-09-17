import AppKit
import GarakutaCore

/// M03: a floating strip below the menu bar showing hidden items as clickable buttons.
@MainActor
final class HiddenItemsBar {
    struct Entry {
        let item: MenuBarItem
        let image: NSImage?
    }

    private final class Panel: NSPanel {
        var onEscape: (() -> Void)?
        override var canBecomeKey: Bool { true }
        override func cancelOperation(_ sender: Any?) { onEscape?() }
    }

    private static let buttonSize: CGFloat = 26
    private static let spacing: CGFloat = 4
    private static let padding: CGFloat = 6

    var onPress: ((MenuBarItem) -> Void)?
    var onClose: (() -> Void)?

    private(set) var isOpen = false
    private(set) var displayID: CGDirectDisplayID?

    private var panel: Panel?
    private var outsideClickMonitors: [Any] = []
    private var buttons: [NSButton] = []
    private var entries: [Entry] = []

    var frame: CGRect? { panel?.frame }

    func open(entries: [Entry], on screen: NSScreen, placement: MenuBarSettings.BarPlacement, anchor: CGRect?) {
        close(notify: false)
        self.entries = entries
        let panel = makePanel()
        self.panel = panel
        displayID = MenuBarGeometry.displayID(of: screen)

        let count = max(entries.count, 1)
        let width = CGFloat(count) * Self.buttonSize + CGFloat(count - 1) * Self.spacing + Self.padding * 2
        let height = Self.buttonSize + Self.padding * 2
        let menuBarHeight = MenuBarGeometry.menuBarHeight(of: screen)
        let top = screen.frame.maxY - menuBarHeight - 6

        var centerX: CGFloat
        switch placement {
        case .belowNotch:
            centerX = MenuBarGeometry.notchSpan(of: screen).map { ($0.lowerBound + $0.upperBound) / 2 } ?? screen.frame.midX
        case .nearPointer:
            centerX = NSEvent.mouseLocation.x
        case .belowIcon:
            centerX = anchor?.midX ?? screen.frame.maxX - 100
        }
        centerX = min(max(centerX, screen.frame.minX + width / 2 + 8), screen.frame.maxX - width / 2 - 8)
        panel.setFrame(CGRect(x: centerX - width / 2, y: top - height, width: width, height: height), display: false)

        populate(panel: panel, entries: entries)
        panel.makeKeyAndOrderFront(nil)
        isOpen = true
        installOutsideClickMonitor()
    }

    func close(notify: Bool = true) {
        outsideClickMonitors.forEach { NSEvent.removeMonitor($0) }
        outsideClickMonitors.removeAll()
        if HiddenItemsBar.current === self { HiddenItemsBar.current = nil }
        panel?.orderOut(nil)
        panel = nil
        buttons.removeAll()
        let wasOpen = isOpen
        isOpen = false
        if wasOpen, notify { onClose?() }
    }

    /// Replaces a button image once an async capture arrives.
    func updateImage(_ image: NSImage, for item: MenuBarItem) {
        guard let index = entries.firstIndex(where: { $0.item.id == item.id }), index < buttons.count else { return }
        buttons[index].image = image
    }

    // MARK: Building

    private func makePanel() -> Panel {
        let panel = Panel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.onEscape = { [weak self] in self?.close() }
        return panel
    }

    private func populate(panel: Panel, entries: [Entry]) {
        let effect = NSVisualEffectView(frame: panel.contentLayoutRect)
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 10
        effect.layer?.masksToBounds = true
        effect.autoresizingMask = [.width, .height]
        panel.contentView = effect

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = Self.spacing
        stack.edgeInsets = NSEdgeInsets(top: Self.padding, left: Self.padding, bottom: Self.padding, right: Self.padding)
        stack.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            stack.topAnchor.constraint(equalTo: effect.topAnchor),
            stack.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])

        buttons.removeAll()
        if entries.isEmpty {
            let label = NSTextField(labelWithString: "No hidden items")
            label.font = .systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
            stack.addArrangedSubview(label)
            return
        }
        for (index, entry) in entries.enumerated() {
            let button = NSButton(image: entry.image ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)!,
                                  target: self, action: #selector(buttonPressed(_:)))
            button.isBordered = false
            button.imageScaling = .scaleProportionallyDown
            button.toolTip = entry.item.displayName
            button.tag = index
            button.setButtonType(.momentaryChange)
            button.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: Self.buttonSize),
                button.heightAnchor.constraint(equalToConstant: Self.buttonSize),
            ])
            stack.addArrangedSubview(button)
            buttons.append(button)
        }
    }

    @objc private func buttonPressed(_ sender: NSButton) {
        guard sender.tag < entries.count else { return }
        let item = entries[sender.tag].item
        onPress?(item)
    }

    /// Clicks in other apps arrive through the global monitor; clicks in our own windows (for example the notch
    /// panel) only reach a local monitor, so both are installed.
    private func installOutsideClickMonitor() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        let global = NSEvent.addGlobalMonitorForEvents(matching: mask) { _ in
            let location = NSEvent.mouseLocation
            MainActor.assumeIsolated { HiddenItemsBar.closeIfOutside(location) }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: mask) { event in
            let location = NSEvent.mouseLocation
            MainActor.assumeIsolated { HiddenItemsBar.closeIfOutside(location) }
            return event
        }
        outsideClickMonitors = [global, local].compactMap { $0 }
        HiddenItemsBar.current = self
    }

    private static func closeIfOutside(_ location: CGPoint) {
        guard let bar = current, let frame = bar.frame else { return }
        if !frame.contains(location) { bar.close() }
    }

    private static var current: HiddenItemsBar?
}
