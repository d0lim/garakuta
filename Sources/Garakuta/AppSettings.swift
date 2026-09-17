import Foundation
import GarakutaCore

/// App-level settings: which modules are enabled (O01-style per-feature on/off).
struct AppSettings: Codable {
    var menuBarEnabled = true
    var notchEnabled = true
    var switcherEnabled = true
    var onboardingCompleted = false

    static let key = "app"

    init() {}

    /// Lenient decoding so adding a field later never wipes stored settings.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        menuBarEnabled = try c.decodeIfPresent(Bool.self, forKey: .menuBarEnabled) ?? true
        notchEnabled = try c.decodeIfPresent(Bool.self, forKey: .notchEnabled) ?? true
        switcherEnabled = try c.decodeIfPresent(Bool.self, forKey: .switcherEnabled) ?? true
        onboardingCompleted = try c.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? false
    }

    @MainActor static func load() -> AppSettings { SettingsStore.shared.load(key, default: AppSettings()) }
    @MainActor func save() { SettingsStore.shared.save(self, for: Self.key) }
}
