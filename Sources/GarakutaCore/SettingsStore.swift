import Foundation

/// JSON-per-key settings under ~/Library/Application Support/Garakuta. Each module owns one Codable settings
/// type and reads/writes it through this store so export/import (O05) can later dump the whole directory.
@MainActor
public final class SettingsStore {
    public static let shared = SettingsStore()

    public let directory: URL
    private var cache: [String: Any] = [:]

    public init(directory: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.directory = directory ?? base.appendingPathComponent("Garakuta", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    public func load<T: Codable>(_ key: String, default defaultValue: @autoclosure () -> T) -> T {
        if let cached = cache[key] as? T { return cached }
        let url = directory.appendingPathComponent("\(key).json")
        if let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(T.self, from: data) {
            cache[key] = value
            return value
        }
        let value = defaultValue()
        cache[key] = value
        return value
    }

    public func save<T: Codable>(_ value: T, for key: String) {
        cache[key] = value
        let url = directory.appendingPathComponent("\(key).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(value) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
