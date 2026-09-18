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
    private let levels = NotchServices.shared.audioLevels

    var body: some View {
        // Only the two states SwiftUI needs to know about; the levels themselves reach the bars directly.
        NowPlayingBars(playing: service.track?.isPlaying == true, reactive: levels.isRunning)
            .frame(width: 20, height: 18)
    }
}

/// Five bars drawn with Core Animation layers, which interpolate the heights themselves.
///
/// Every SwiftUI version of this was expensive in the same way: the bars sit in the compact row, the row measures
/// itself so the panel can size to its content, and so each new height re-ran a layout pass. A canvas skipped the
/// layout but still had to be redrawn on every frame. Handing the heights to the layers costs a property set a
/// dozen times a second, and nothing at all while the idle wave is running.
private struct NowPlayingBars: NSViewRepresentable {
    let playing: Bool
    /// True while levels are being measured; the bars then follow them instead of the idle wave.
    let reactive: Bool

    func makeNSView(context: Context) -> BarsView {
        let view = BarsView()
        view.playing = playing
        view.reactive = reactive
        context.coordinator.token = NotchServices.shared.audioLevels.subscribe { [weak view] levels in
            view?.apply(levels: levels)
        }
        return view
    }

    func updateNSView(_ view: BarsView, context: Context) {
        view.playing = playing
        view.reactive = reactive
        view.apply(levels: NotchServices.shared.audioLevels.levels)
    }

    static func dismantleNSView(_ view: BarsView, coordinator: Coordinator) {
        if let token = coordinator.token { NotchServices.shared.audioLevels.unsubscribe(token) }
        coordinator.token = nil
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var token: UUID?
    }

    final class BarsView: NSView {
        private static let count = AudioLevelService.bandCount
        private static let barWidth: CGFloat = 2.5
        private static let spacing: CGFloat = 2
        private static let height: CGFloat = 16
        /// The shortest a bar gets, as a fraction of its full height: a flat row of dots rather than nothing.
        private static let floorScale: CGFloat = 0.25
        private static let idleKey = "idle"

        private var bars: [CALayer] = []
        private var idleRunning = false
        var playing = false
        var reactive = false

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            let total = CGFloat(Self.count) * Self.barWidth + CGFloat(Self.count - 1) * Self.spacing
            for index in 0..<Self.count {
                let bar = CALayer()
                bar.backgroundColor = NSColor.white.cgColor
                bar.cornerRadius = 1
                bar.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                bar.bounds = CGRect(x: 0, y: 0, width: Self.barWidth, height: Self.height)
                bar.position = CGPoint(x: (frameRect.width - total) / 2 + CGFloat(index) * (Self.barWidth + Self.spacing) + Self.barWidth / 2,
                                       y: frameRect.height / 2)
                bar.transform = CATransform3DMakeScale(1, Self.floorScale, 1)
                layer?.addSublayer(bar)
                bars.append(bar)
            }
        }

        required init?(coder: NSCoder) { nil }

        /// The bars keep their own size whatever the row around them does, so a new height never moves anything else.
        override var intrinsicContentSize: NSSize { NSSize(width: 20, height: 18) }

        override func layout() {
            super.layout()
            let total = CGFloat(Self.count) * Self.barWidth + CGFloat(Self.count - 1) * Self.spacing
            for (index, bar) in bars.enumerated() {
                bar.position = CGPoint(x: (bounds.width - total) / 2 + CGFloat(index) * (Self.barWidth + Self.spacing) + Self.barWidth / 2,
                                       y: bounds.height / 2)
            }
        }

        func apply(levels: [Float]) {
            guard playing else {
                stopIdle()
                setScales(Array(repeating: Self.floorScale, count: Self.count), duration: 0.2)
                return
            }
            guard reactive, levels.count == Self.count else {
                startIdle()
                return
            }
            stopIdle()
            setScales(levels.map { Self.floorScale + CGFloat($0) * (1 - Self.floorScale) }, duration: 1.0 / 12)
        }

        private func setScales(_ scales: [CGFloat], duration: CFTimeInterval) {
            CATransaction.begin()
            CATransaction.setAnimationDuration(duration)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .linear))
            for (bar, scale) in zip(bars, scales) {
                bar.transform = CATransform3DMakeScale(1, scale, 1)
            }
            CATransaction.commit()
        }

        /// A repeating animation per bar, offset so they do not rise and fall as one block. Once installed it runs
        /// without waking the app at all.
        private func startIdle() {
            guard !idleRunning else { return }
            idleRunning = true
            for (index, bar) in bars.enumerated() {
                let animation = CABasicAnimation(keyPath: "transform.scale.y")
                animation.fromValue = 0.4
                animation.toValue = 1.0
                animation.duration = 0.45
                animation.autoreverses = true
                animation.repeatCount = .infinity
                animation.timeOffset = Double(index) * 0.17
                animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                bar.add(animation, forKey: Self.idleKey)
            }
        }

        private func stopIdle() {
            guard idleRunning else { return }
            idleRunning = false
            for bar in bars { bar.removeAnimation(forKey: Self.idleKey) }
        }
    }
}




