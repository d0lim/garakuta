import Foundation

/// Simple in-app countdown. Active as a live activity while running or briefly after finishing.
@MainActor
@Observable
public final class TimerService {
    public enum Phase: Sendable, Equatable { case idle, running, paused, finished }

    public private(set) var phase: Phase = .idle
    public private(set) var remaining: TimeInterval = 0
    public var duration: TimeInterval = 25 * 60
    var onChange: (() -> Void)?

    private var endDate: Date?
    private var tick: Timer?
    private var finishedResetTask: Task<Void, Never>?

    public init() {}

    public func start(_ seconds: TimeInterval? = nil) {
        if let seconds { duration = seconds }
        remaining = phase == .paused ? remaining : duration
        endDate = Date().addingTimeInterval(remaining)
        phase = .running
        tick?.invalidate()
        tick = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            Task { @MainActor in NotchServices.shared.timer.update() }
        }
        onChange?()
    }

    public func pause() {
        guard phase == .running else { return }
        update()
        phase = .paused
        tick?.invalidate()
        tick = nil
        onChange?()
    }

    public func reset() {
        tick?.invalidate()
        tick = nil
        finishedResetTask?.cancel()
        phase = .idle
        remaining = 0
        endDate = nil
        onChange?()
    }

    private func update() {
        guard phase == .running, let endDate else { return }
        remaining = max(0, endDate.timeIntervalSinceNow)
        if remaining == 0 {
            phase = .finished
            tick?.invalidate()
            tick = nil
            onChange?()
            finishedResetTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(6))
                guard !Task.isCancelled, self?.phase == .finished else { return }
                self?.reset()
            }
        }
    }

    public var isActive: Bool { phase == .running || phase == .paused || phase == .finished }

    public var remainingText: String {
        let total = Int(remaining.rounded(.up))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}
