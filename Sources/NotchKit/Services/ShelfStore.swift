import Foundation

/// Files dropped onto the notch. Kept in memory only; the paths are what matter for drag-out.
@MainActor
@Observable
public final class ShelfStore {
    public private(set) var items: [URL] = []

    public init() {}

    public func add(_ urls: [URL]) {
        for url in urls where !items.contains(url) {
            items.append(url)
        }
    }

    public func remove(_ url: URL) {
        items.removeAll { $0 == url }
    }

    public func clear() {
        items.removeAll()
    }
}
