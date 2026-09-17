import AppKit
import GarakutaCore
import QuickLookThumbnailing

/// Files dropped onto the notch. The list survives relaunches (paths under Application Support); files that have
/// disappeared in the meantime are dropped when the list is loaded.
@MainActor
@Observable
public final class ShelfStore {
    private static let storeKey = "shelf"

    public private(set) var items: [URL] = []
    /// Quick Look previews by file, filled in lazily by `thumbnail(for:)`.
    private(set) var thumbnails: [URL: NSImage] = [:]
    private var thumbnailRequests: Set<URL> = []

    public init() {
        let paths = SettingsStore.shared.load(Self.storeKey, default: [String]())
        items = paths.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    public func add(_ urls: [URL]) {
        for url in urls where !items.contains(url) {
            items.append(url)
        }
        persist()
    }

    public func remove(_ url: URL) {
        items.removeAll { $0 == url }
        thumbnails[url] = nil
        persist()
    }

    public func clear() {
        items.removeAll()
        thumbnails.removeAll()
        persist()
    }

    private func persist() {
        SettingsStore.shared.save(items.map(\.path), for: Self.storeKey)
    }

    // MARK: Previews

    /// The file's Quick Look preview once it has been generated, the Finder icon until then.
    func thumbnail(for url: URL) -> NSImage {
        if let cached = thumbnails[url] { return cached }
        requestThumbnail(for: url)
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private func requestThumbnail(for url: URL) {
        guard !thumbnailRequests.contains(url) else { return }
        thumbnailRequests.insert(url)
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 96, height: 96), scale: 2, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            let image = representation.map { NSImage(cgImage: $0.cgImage, size: CGSize(width: 48, height: 48)) }
            Task { @MainActor [weak self] in
                guard let self else { return }
                thumbnailRequests.remove(url)
                if let image, items.contains(url) { thumbnails[url] = image }
            }
        }
    }

    // MARK: Actions

    public func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    public func reveal(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    public func copyPaths(_ urls: [URL]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
    }

    /// Zips the files into an archive next to the first one and puts the archive on the shelf.
    public func compress(_ urls: [URL]) {
        guard let first = urls.first else { return }
        let folder = first.deletingLastPathComponent()
        let baseName = urls.count == 1 ? first.deletingPathExtension().lastPathComponent : "Archive"
        var destination = folder.appendingPathComponent("\(baseName).zip")
        var counter = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = folder.appendingPathComponent("\(baseName) \(counter).zip")
            counter += 1
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent"] + urls.map(\.path) + [destination.path]
        process.standardOutput = nil
        process.standardError = nil
        let archivePath = destination.path
        process.terminationHandler = { process in
            guard process.terminationStatus == 0 else { return }
            Task { @MainActor [weak self] in self?.add([URL(fileURLWithPath: archivePath)]) }
        }
        try? process.run()
    }
}
