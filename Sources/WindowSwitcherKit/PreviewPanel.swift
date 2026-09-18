import AppKit
import CoreGraphics

/// Shows the selected window at its real place and size behind the switcher, so the pick can be checked without
/// leaving the panel. Full-size pictures are fetched per window and kept for the session, a few at a time.
@MainActor
final class PreviewPanel {
    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private var panel: Panel?
    private let imageView = NSImageView()
    private var shownID: CGWindowID?
    private var frames: [CGWindowID: CGImage] = [:]
    private var order: [CGWindowID] = []
    private var fetching: Set<CGWindowID> = []
    private var generation = 0
    private static let maxFrames = 10

    /// Level right under the switcher panel so the picture never covers a tile, not even for a frame.
    private func makePanel(below level: NSWindow.Level) -> Panel {
        let panel = Panel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = NSWindow.Level(rawValue: level.rawValue - 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.animationBehavior = .none
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 10
        imageView.layer?.masksToBounds = true
        panel.contentView = imageView
        return panel
    }

    /// Shows `window` when a picture is available, fetching one otherwise. Windows on other Spaces and minimized
    /// windows have no place on screen, so nothing is shown for them.
    func show(_ window: SwitcherWindow, below level: NSWindow.Level) {
        guard window.isOnCurrentSpace, !window.isMinimized, !window.isAppPlaceholder, window.frame.width > 0 else {
            hide()
            return
        }
        let id = window.windowID
        if let image = frames[id] {
            present(image, at: window.frame, id: id, below: level)
            return
        }
        // Keep whatever is showing until the new picture lands; a blank panel would flash.
        guard !fetching.contains(id) else { return }
        fetching.insert(id)
        generation += 1
        let gen = generation
        Task { [weak self] in
            let image = await ThumbnailStore.captureFullSize(id: id, onCurrentSpace: true)
            await MainActor.run {
                guard let self else { return }
                self.fetching.remove(id)
                guard let image else { return }
                self.store(id, image)
                if gen == self.generation { self.present(image, at: window.frame, id: id, below: level) }
            }
        }
    }

    func hide() {
        panel?.orderOut(nil)
        shownID = nil
    }

    /// Ends the session: the pictures go with it.
    func reset() {
        hide()
        frames.removeAll()
        order.removeAll()
        generation += 1
    }

    private func store(_ id: CGWindowID, _ image: CGImage) {
        frames[id] = image
        order.removeAll { $0 == id }
        order.append(id)
        if order.count > Self.maxFrames { frames[order.removeFirst()] = nil }
    }

    private func present(_ image: CGImage, at cgFrame: CGRect, id: CGWindowID, below level: NSWindow.Level) {
        let panel = self.panel ?? makePanel(below: level)
        self.panel = panel
        guard let main = NSScreen.screens.first else { return }
        let frame = CGRect(x: cgFrame.minX, y: main.frame.maxY - cgFrame.maxY, width: cgFrame.width, height: cgFrame.height)
        if id != shownID {
            imageView.image = NSImage(cgImage: image, size: frame.size)
            shownID = id
        }
        panel.setFrame(frame, display: true)
        panel.orderFront(nil)
    }
}
