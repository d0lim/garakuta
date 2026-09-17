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
                        Text(track.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        Text(track.artist).font(.system(size: 12)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                        ProgressView(value: track.duration > 0 ? min(track.position / track.duration, 1) : 0)
                            .tint(.white)
                        HStack(spacing: 18) {
                            Button { service.previous() } label: { Image(systemName: "backward.fill") }
                            Button { service.playPause() } label: {
                                Image(systemName: track.isPlaying ? "pause.fill" : "play.fill").font(.title3)
                            }
                            Button { service.next() } label: { Image(systemName: "forward.fill") }
                            Spacer()
                            Text(track.player.rawValue).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
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

    var body: some View {
        WidgetCard(title: "Timer", systemImage: "timer") {
            VStack(spacing: 8) {
                if service.isActive {
                    Text(service.remainingText)
                        .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(service.phase == .finished ? .orange : .white)
                    HStack(spacing: 12) {
                        if service.phase == .running {
                            Button("Pause") { service.pause() }
                        } else if service.phase == .paused {
                            Button("Resume") { service.start() }
                        }
                        Button("Reset") { service.reset() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Text("\(Int(minutes)) min")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Slider(value: $minutes, in: 1...120, step: 1)
                    Button("Start") { service.start(minutes * 60) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
        }
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
        WidgetCard(title: "Shelf", systemImage: "tray.full") {
            if store.items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "arrow.down.doc").font(.title2)
                    Text("Drop files on the notch").font(.system(size: 12))
                }
                .foregroundStyle(.white.opacity(0.6))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(store.items, id: \.self) { url in
                            VStack(spacing: 4) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                    .resizable().frame(width: 40, height: 40)
                                Text(url.lastPathComponent)
                                    .font(.system(size: 10)).lineLimit(1).frame(width: 64)
                            }
                            .foregroundStyle(.white)
                            .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
                            .contextMenu {
                                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                                Button("Remove") { store.remove(url) }
                            }
                        }
                        Button { store.clear() } label: { Image(systemName: "xmark.circle") }
                            .buttonStyle(.plain).foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
        }
    }
}
