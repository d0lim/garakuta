import SwiftUI

/// Something worth showing in the compact notch while it is happening (N03).
@MainActor
public protocol LiveActivityProvider: AnyObject {
    var id: String { get }
    var title: String { get }
    var isActive: Bool { get }
    /// Small view shown left of the notch.
    func compactLeading() -> AnyView
    /// Small view shown right of the notch.
    func compactTrailing() -> AnyView
    /// Full page shown first when the panel is expanded.
    func expandedView() -> AnyView
}

/// Resolves which providers are active, ordered by the user's priority list.
@MainActor
@Observable
public final class LiveActivityCenter {
    public private(set) var providers: [LiveActivityProvider] = []
    private(set) var version = 0
    var onChange: (() -> Void)?
    var settings = NotchSettings.LiveActivitySettings() { didSet { bump() } }

    init() {}

    func register(_ provider: LiveActivityProvider) {
        providers.append(provider)
    }

    /// Called by providers whenever their state changes.
    func bump() {
        version += 1
        onChange?()
    }

    public var activeProviders: [LiveActivityProvider] {
        _ = version
        let enabled = providers.filter { settings.enabledProviders.contains($0.id) && $0.isActive }
        return enabled.sorted { a, b in
            let ia = settings.priorityOrder.firstIndex(of: a.id) ?? Int.max
            let ib = settings.priorityOrder.firstIndex(of: b.id) ?? Int.max
            return ia < ib
        }
    }

    public var primary: LiveActivityProvider? { activeProviders.first }
    public var secondary: LiveActivityProvider? { activeProviders.dropFirst().first }
}

// MARK: - Built-in providers

@MainActor
final class NowPlayingActivity: LiveActivityProvider {
    let id = "nowPlaying"
    let title = "Now Playing"
    private let service: NowPlayingService

    init(service: NowPlayingService) { self.service = service }

    var isActive: Bool { service.isActive }

    func compactLeading() -> AnyView { AnyView(NowPlayingCompactArtwork(service: service)) }
    func compactTrailing() -> AnyView { AnyView(NowPlayingCompactBars(service: service)) }
    func expandedView() -> AnyView { AnyView(NowPlayingWidgetView(service: service)) }
}

@MainActor
final class TimerActivity: LiveActivityProvider {
    let id = "timer"
    let title = "Timer"
    private let service: TimerService

    init(service: TimerService) { self.service = service }

    var isActive: Bool { service.isActive }

    func compactLeading() -> AnyView {
        AnyView(Image(systemName: service.phase == .finished ? "bell.fill" : "timer")
            .foregroundStyle(service.phase == .finished ? .orange : .white)
            .font(.system(size: 13, weight: .semibold)))
    }

    func compactTrailing() -> AnyView {
        AnyView(TimerCompactLabel(service: service))
    }

    func expandedView() -> AnyView { AnyView(TimerWidgetView(service: service)) }
}

@MainActor
final class BatteryActivity: LiveActivityProvider {
    let id = "battery"
    let title = "Battery"
    private let service: BatteryService

    init(service: BatteryService) { self.service = service }

    var isActive: Bool { service.isHighlighted && service.status != nil }

    func compactLeading() -> AnyView {
        AnyView(Image(systemName: service.status?.onACPower == true ? "bolt.fill" : "battery.100percent")
            .foregroundStyle(service.status?.onACPower == true ? .green : .white)
            .font(.system(size: 13, weight: .semibold)))
    }

    func compactTrailing() -> AnyView {
        AnyView(Text("\(service.status?.percent ?? 0)%")
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.white))
    }

    func expandedView() -> AnyView { AnyView(BatteryWidgetView(service: service)) }
}

private struct TimerCompactLabel: View {
    let service: TimerService
    var body: some View {
        Text(service.remainingText)
            .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(.white)
    }
}

private struct NowPlayingCompactArtwork: View {
    let service: NowPlayingService
    var body: some View {
        Group {
            if let art = service.artwork {
                Image(nsImage: art).resizable().scaledToFill()
            } else {
                Image(systemName: "music.note").foregroundStyle(.white).font(.system(size: 12, weight: .bold))
            }
        }
        .frame(width: 18, height: 18)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

private struct NowPlayingCompactBars: View {
    let service: NowPlayingService

    /// Driven by the clock rather than by a repeating animation: the bars settle the moment playback pauses and
    /// pick up again on resume. A `repeatForever` animation is installed once, and a pause in between leaves it
    /// with nothing to restart.
    var body: some View {
        let playing = service.track?.isPlaying == true
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !playing)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0..<4, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(.white)
                        .frame(width: 3, height: playing ? Self.height(bar: index, at: time) : 4)
                }
            }
            .frame(width: 18, height: 18)
            .animation(.easeOut(duration: 0.2), value: playing)
        }
    }

    /// Each bar rides its own offset cycle so they do not rise and fall as one block.
    private static func height(bar index: Int, at time: TimeInterval) -> CGFloat {
        let wave = sin(time * 2.4 + Double(index) * 1.3)
        return 6 + CGFloat((wave + 1) / 2) * 10
    }
}
