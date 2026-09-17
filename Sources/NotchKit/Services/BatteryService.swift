import Foundation
import IOKit.ps

/// Reads battery state through IOKit power sources. Surfaces as a live activity for a few seconds whenever
/// the charging state changes.
@MainActor
@Observable
public final class BatteryService {
    public struct Status: Equatable, Sendable {
        public var percent: Int
        public var isCharging: Bool
        public var onACPower: Bool
    }

    public private(set) var status: Status?
    /// True for a few seconds after a charging-state change.
    public private(set) var isHighlighted = false
    var onChange: (() -> Void)?

    private var timer: Timer?
    private var highlightTask: Task<Void, Never>?

    public init() {}

    func start() {
        guard timer == nil else { return }
        refresh(initial: true)
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            Task { @MainActor in NotchServices.shared.battery.refresh(initial: false) }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func refresh(initial: Bool) {
        let new = Self.read()
        guard new != status else { return }
        let chargingChanged = new?.onACPower != status?.onACPower || new?.isCharging != status?.isCharging
        status = new
        if chargingChanged && !initial {
            isHighlighted = true
            highlightTask?.cancel()
            highlightTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                self?.isHighlighted = false
                self?.onChange?()
            }
        }
        onChange?()
    }

    private static func read() -> Status? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                  let capacity = desc[kIOPSCurrentCapacityKey] as? Int else { continue }
            let charging = desc[kIOPSIsChargingKey] as? Bool ?? false
            let state = desc[kIOPSPowerSourceStateKey] as? String
            return Status(percent: capacity, isCharging: charging, onACPower: state == kIOPSACPowerValue)
        }
        return nil
    }
}
