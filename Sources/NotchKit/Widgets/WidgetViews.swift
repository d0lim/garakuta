import SwiftUI
import UniformTypeIdentifiers

struct WidgetCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(12)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct NowPlayingWidgetView: View {
    let service: NowPlayingService

    var body: some View {
        WidgetCard(title: "Now Playing", systemImage: "music.note") {
            if let track = service.track {
                HStack(spacing: 14) {
                    Group {
                        if let art = service.artwork {
                            Image(nsImage: art).resizable().scaledToFill()
                        } else {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.1))
                                Image(systemName: "music.note").font(.title2).foregroundStyle(.white.opacity(0.7))
                            }
                        }
                    }
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.displayTitle).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        Text(track.artist.isEmpty ? track.album : track.artist).font(.system(size: 12)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                        // Position is extrapolated between reports, so redraw once a second while playing.
                        // Sources without a known duration (browsers, live streams) get no bar.
                        if track.duration > 0 {
                            TimelineView(.periodic(from: .now, by: track.isPlaying ? 1 : 3600)) { _ in
                                ProgressView(value: min(track.position / track.duration, 1)).tint(.white)
                            }
                        } else {
                            Spacer().frame(height: 6)
                        }
                        HStack(spacing: 18) {
                            Button { service.previous() } label: { Image(systemName: "backward.fill") }
                            Button { service.playPause() } label: {
                                Image(systemName: track.isPlaying ? "pause.fill" : "play.fill").font(.title3)
                            }
                            Button { service.next() } label: { Image(systemName: "forward.fill") }
                            Spacer()
                            Text(track.sourceName).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .foregroundStyle(.white)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "music.note.list").font(.title2)
                    Text(service.isEnabled ? "Nothing playing" : "Now Playing is off in settings")
                        .font(.system(size: 12))
                }
                .foregroundStyle(.white.opacity(0.6))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct TimerWidgetView: View {
    let service: TimerService
    @State private var minutes: Double = 25
    private static let presets: [Double] = [5, 15, 25, 45]

    var body: some View {
        WidgetCard(title: "Timer", systemImage: "timer") {
            if service.isActive {
                running
            } else {
                idle
            }
        }
    }

    /// Duration picker in three rows that fit a half-width card: presets, minute adjustment, start.
    private var idle: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(Self.presets, id: \.self) { preset in
                    Button("\(Int(preset))") { minutes = preset }
                        .buttonStyle(NotchPillButtonStyle(prominent: minutes == preset))
                }
            }
            HStack(spacing: 10) {
                Button { minutes = max(1, minutes - 1) } label: { Image(systemName: "minus") }
                    .buttonStyle(NotchPillButtonStyle(prominent: false))
                Text(Self.format(minutes * 60))
                    .font(.system(size: 24, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                Button { minutes = min(180, minutes + 1) } label: { Image(systemName: "plus") }
                    .buttonStyle(NotchPillButtonStyle(prominent: false))
            }
            Button { service.start(minutes * 60) } label: { Label("Start", systemImage: "play.fill").frame(maxWidth: .infinity) }
                .buttonStyle(NotchPillButtonStyle(prominent: true))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Countdown with a progress bar and transport controls; turns orange when time is up.
    private var running: some View {
        let finished = service.phase == .finished
        return VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(service.remainingText)
                    .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(finished ? .orange : .white)
                Spacer()
                Text(finished ? "Time's up" : (service.phase == .paused ? "Paused" : "of \(Self.format(service.duration))"))
                    .font(.system(size: 11))
                    .foregroundStyle(finished ? .orange : .white.opacity(0.6))
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.15))
                    Capsule().fill(finished ? Color.orange : .white)
                        .frame(width: geometry.size.width * progress)
                }
            }
            .frame(height: 4)
            .animation(.linear(duration: 0.5), value: progress)
            HStack(spacing: 8) {
                if service.phase == .running {
                    Button { service.pause() } label: { Label("Pause", systemImage: "pause.fill") }
                        .buttonStyle(NotchPillButtonStyle(prominent: true))
                } else if service.phase == .paused {
                    Button { service.start() } label: { Label("Resume", systemImage: "play.fill") }
                        .buttonStyle(NotchPillButtonStyle(prominent: true))
                }
                Button { service.reset() } label: { Label(finished ? "Dismiss" : "Reset", systemImage: "arrow.counterclockwise") }
                    .buttonStyle(NotchPillButtonStyle(prominent: finished))
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var progress: CGFloat {
        guard service.duration > 0 else { return 0 }
        return CGFloat(min(max(1 - service.remaining / service.duration, 0), 1))
    }

    private static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}

/// Capsule button legible on the panel's dark background; the system styles draw dark text there.
struct NotchPillButtonStyle: ButtonStyle {
    var prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(prominent ? .black : .white)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(prominent ? Color.white : Color.white.opacity(0.14), in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}

struct ClockWidgetView: View {
    var body: some View {
        WidgetCard(title: "Clock", systemImage: "clock") {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 2) {
                    Text(context.date, format: .dateTime.hour().minute().second())
                        .font(.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit())
                    Text(context.date, format: .dateTime.weekday(.wide).month().day())
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct BatteryWidgetView: View {
    let service: BatteryService

    var body: some View {
        WidgetCard(title: "Battery", systemImage: "battery.100percent") {
            if let s = service.status {
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: s.onACPower ? "bolt.fill" : "battery.75percent")
                            .foregroundStyle(s.onACPower ? .green : .white)
                        Text("\(s.percent)%")
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                    }
                    Text(s.isCharging ? "Charging" : (s.onACPower ? "On power adapter" : "On battery"))
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("No battery").foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct ShelfWidgetView: View {
    let store: ShelfStore

    var body: some View {
        WidgetCard(title: store.items.isEmpty ? "Shelf" : "Shelf · \(store.items.count)", systemImage: "tray.full") {
            if store.items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "arrow.down.doc").font(.title2)
                    Text("Drop files on the notch to keep them here").font(.system(size: 12))
                    Text("They stay until you remove them, even across relaunches.").font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                }
                .foregroundStyle(.white.opacity(0.6))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 8) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(store.items, id: \.self) { url in
                                shelfItem(url)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    Divider().overlay(.white.opacity(0.2)).frame(height: 56)
                    shelfActions
                }
            }
        }
    }

    private func shelfItem(_ url: URL) -> some View {
        VStack(spacing: 4) {
            Image(nsImage: store.thumbnail(for: url))
                .resizable().aspectRatio(contentMode: .fit)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(url.lastPathComponent)
                .font(.system(size: 10)).lineLimit(1).truncationMode(.middle).frame(width: 68)
        }
        .foregroundStyle(.white)
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .onTapGesture(count: 2) { store.open(url) }
        .contextMenu {
            Button("Open") { store.open(url) }
            Button("Reveal in Finder") { store.reveal([url]) }
            ShareLink(item: url) { Text("Share…") }
            Divider()
            Button("Compress") { store.compress([url]) }
            Button("Copy") { store.copyPaths([url]) }
            Divider()
            Button("Remove from Shelf") { store.remove(url) }
        }
        .help(url.path)
    }

    /// Whole-shelf actions: drag everything out at once, share, compress, clear.
    private var shelfActions: some View {
        VStack(alignment: .leading, spacing: 4) {
            MultiFileDragView(urls: store.items) {
                Label("Drag all", systemImage: "square.stack.3d.up")
            }
            ShareLink(items: store.items) { Label("Share…", systemImage: "square.and.arrow.up") }
            Menu {
                Button("Reveal in Finder") { store.reveal(store.items) }
                Button("Compress into one archive") { store.compress(store.items) }
                Button("Copy") { store.copyPaths(store.items) }
                Divider()
                Button("Clear Shelf") { store.clear() }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .font(.system(size: 11))
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.85))
        .frame(width: 96, alignment: .leading)
    }
}

/// A label that starts a drag of several files at once. SwiftUI's `onDrag` hands over a single item, so the
/// drag session is started from AppKit.
struct MultiFileDragView<Label: View>: NSViewRepresentable {
    let urls: [URL]
    @ViewBuilder let label: Label

    func makeNSView(context: Context) -> DragSourceView {
        let view = DragSourceView()
        view.hosting = NSHostingView(rootView: label)
        view.hosting?.translatesAutoresizingMaskIntoConstraints = false
        if let hosting = view.hosting {
            view.addSubview(hosting)
            NSLayoutConstraint.activate([
                hosting.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                hosting.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                hosting.topAnchor.constraint(equalTo: view.topAnchor),
                hosting.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
        }
        view.urls = urls
        return view
    }

    func updateNSView(_ nsView: DragSourceView, context: Context) {
        nsView.urls = urls
        nsView.hosting?.rootView = label
    }

    final class DragSourceView: NSView, NSDraggingSource {
        var urls: [URL] = []
        var hosting: NSHostingView<Label>?
        private var mouseDownAt: CGPoint?

        override var intrinsicContentSize: NSSize { hosting?.intrinsicContentSize ?? super.intrinsicContentSize }

        override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(point) ? self : nil }

        override func mouseDown(with event: NSEvent) { mouseDownAt = event.locationInWindow }

        override func mouseDragged(with event: NSEvent) {
            guard let start = mouseDownAt, hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) > 4, !urls.isEmpty else { return }
            mouseDownAt = nil
            let items = urls.enumerated().map { index, url -> NSDraggingItem in
                let item = NSDraggingItem(pasteboardWriter: url as NSURL)
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                let origin = convert(event.locationInWindow, from: nil)
                // Fan the icons out a little so the stack reads as several files.
                item.setDraggingFrame(NSRect(x: origin.x - 24 + CGFloat(index) * 6, y: origin.y - 24 - CGFloat(index) * 6, width: 48, height: 48), contents: icon)
                return item
            }
            beginDraggingSession(with: items, event: event, source: self)
        }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            [.copy, .generic]
        }
    }
}
