import Foundation

/// A feature area (menu bar, notch, window switcher) that can be turned on and off independently.
@MainActor
public protocol FeatureModule: AnyObject {
    static var id: String { get }
    var isRunning: Bool { get }
    func start() throws
    func stop()
}
