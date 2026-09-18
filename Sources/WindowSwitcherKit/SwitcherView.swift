import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The tiles inside the switcher panel: a wrapping grid of thumbnails, a row of app icons, or a column of titles.
struct SwitcherView: View {
    @Bindable var state: SwitcherState
    var onActivate: (SwitcherWindow) -> Void
    var onHover: (SwitcherWindow) -> Void
    var onDrop: (SwitcherWindow, [URL]) -> Void

    private var m: SwitcherMetrics { state.metrics }
    private var minimal: Bool { state.settings.minimalDecorations }

    var body: some View {
        VStack(spacing: 10) {
            if !state.query.isEmpty {
                HStack {
                    Image(systemName: "magnifyingglass")
                    Text(state.query)
                    Spacer()
                }
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
            }
            if state.filtered.isEmpty {
                Text(state.windows.isEmpty ? (state.query.isEmpty ? "Loading windows…" : "No windows") : "No matches")
                    .foregroundStyle(.secondary)
                    .frame(width: 320, height: 120)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        TileFlowLayout(rowHeight: m.tileHeight, maxWidth: m.maxGridWidth, spacing: m.spacing) {
                            ForEach(Array(state.filtered.enumerated()), id: \.element.windowID) { index, window in
                                tile(window, selected: index == state.selectedIndex)
                                    .id(window.windowID)
                                    .onHover { inside in if inside { onHover(window) } }
                                    .onTapGesture { onActivate(window) }
                                    .onDrop(of: [.fileURL], isTargeted: Binding(
                                        get: { state.dropTarget == window.windowID },
                                        set: { state.dropTarget = $0 ? window.windowID : nil }
                                    )) { providers in
                                        Self.loadURLs(providers) { urls in onDrop(window, urls) }
                                        return true
                                    }
                            }
                        }
                        .padding(4)
                    }
                    .frame(maxHeight: m.maxGridHeight + 8)
                    .onChange(of: state.selectedIndex) { _, _ in
                        if let sel = state.selected { withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(sel.windowID) } }
                    }
                }
            }
        }
        .padding(12)
        .frame(minWidth: 240)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.12)))
        )
    }

    // MARK: Tiles

    @ViewBuilder
    private func tile(_ window: SwitcherWindow, selected: Bool) -> some View {
        let width = m.tileWidth(for: window)
        let dropping = state.dropTarget == window.windowID
        Group {
            switch m.style {
            case .thumbnails: thumbnailTile(window, width: width)
            case .appIcons: appIconTile(window, width: width)
            case .titles: titleTile(window, width: width)
            }
        }
        .padding(m.tilePadding)
        .frame(width: width, height: m.tileHeight)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.35) : Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(dropping ? Color.green : (selected ? Color.accentColor : .clear), lineWidth: 2)
        )
        .contentShape(Rectangle())
    }

    private func thumbnailTile(_ window: SwitcherWindow, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.15))
                if state.thumbnailsEnabled, !window.isAppPlaceholder, let cg = state.thumbnails[window.windowID] {
                    Image(decorative: cg, scale: 2)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else if let icon = state.appIcon(for: window) {
                    let side = min(64, m.thumbnailHeight * 0.55)
                    Image(nsImage: icon).resizable().frame(width: side, height: side)
                }
            }
            .frame(width: width - m.tilePadding * 2, height: m.thumbnailHeight)
            HStack(spacing: 6) {
                if let icon = state.appIcon(for: window) {
                    Image(nsImage: icon).resizable().frame(width: m.iconSize, height: m.iconSize)
                }
                VStack(alignment: .leading, spacing: 1) {
                    titleText(window)
                    if !minimal && !window.isAppPlaceholder && window.title != window.appName && !window.title.isEmpty {
                        Text(highlighted(window.appName, state.appMatches[window.windowID]))
                            .font(.system(size: max(9, m.fontSize - 2))).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                badges(window)
            }
        }
    }

    private func appIconTile(_ window: SwitcherWindow, width: CGFloat) -> some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                if let icon = state.appIcon(for: window) {
                    Image(nsImage: icon).resizable().frame(width: m.iconSize, height: m.iconSize)
                }
                if !minimal, let badge = window.dockBadge, state.settings.showDockBadges {
                    dockBadge(badge).offset(x: 6, y: -4)
                }
            }
            Text(highlighted(window.displayTitle, state.titleMatches[window.windowID] ?? state.appMatches[window.windowID]))
                .font(.system(size: m.fontSize, weight: .medium))
                .lineLimit(1)
                .truncationMode(truncation)
                .frame(width: width - m.tilePadding * 2)
            if !minimal { badges(window, dock: false).frame(height: 12) }
        }
    }

    private func titleTile(_ window: SwitcherWindow, width: CGFloat) -> some View {
        HStack(spacing: 8) {
            if let icon = state.appIcon(for: window) {
                Image(nsImage: icon).resizable().frame(width: m.iconSize, height: m.iconSize)
            }
            titleText(window)
            Spacer(minLength: 8)
            if !minimal && !window.isAppPlaceholder && window.title != window.appName && !window.title.isEmpty {
                Text(highlighted(window.appName, state.appMatches[window.windowID]))
                    .font(.system(size: max(9, m.fontSize - 2))).foregroundStyle(.secondary).lineLimit(1)
            }
            badges(window)
        }
    }

    private func titleText(_ window: SwitcherWindow) -> some View {
        Text(highlighted(window.displayTitle, window.isAppPlaceholder ? state.appMatches[window.windowID] : state.titleMatches[window.windowID]))
            .font(.system(size: m.fontSize, weight: .medium))
            .lineLimit(1)
            .truncationMode(truncation)
    }

    private var truncation: Text.TruncationMode {
        switch state.settings.titleTruncation {
        case .end: .tail
        case .middle: .middle
        case .start: .head
        }
    }

    /// Small status glyphs: minimized, full screen, other Space (with its number when asked), hidden app, Dock badge.
    @ViewBuilder
    private func badges(_ window: SwitcherWindow, dock: Bool = true) -> some View {
        if !minimal {
            HStack(spacing: 4) {
                if window.isMinimized { badge("arrow.down.right.and.arrow.up.left") }
                if window.isFullScreen { badge("arrow.up.left.and.arrow.down.right") }
                if !window.isOnCurrentSpace && !window.isMinimized {
                    if state.settings.showSpaceNumbers, let n = window.spaceNumber {
                        Text("\(n)")
                            .font(.system(size: 9, weight: .semibold)).monospacedDigit()
                            .frame(minWidth: 14, minHeight: 14)
                            .background(Color.secondary.opacity(0.25), in: Circle())
                    } else {
                        badge("rectangle.on.rectangle")
                    }
                }
                if window.isAppHidden { badge("eye.slash") }
                if dock, state.settings.showDockBadges, let text = window.dockBadge { dockBadge(text) }
            }
        }
    }

    private func badge(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 9)).foregroundStyle(.secondary)
    }

    private func dockBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold)).monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Color.red, in: Capsule())
            .lineLimit(1)
    }

    /// The text with the matched characters marked, or plain when nothing matched.
    private func highlighted(_ text: String, _ match: SearchMatch?) -> AttributedString {
        var result = AttributedString(text)
        guard let match else { return result }
        let chars = Array(text)
        for range in match.ranges where range.upperBound <= chars.count {
            let lower = String(chars[0..<range.lowerBound]).utf16.count
            let length = String(chars[range]).utf16.count
            guard let start = result.characters.index(result.startIndex, offsetBy: lower, limitedBy: result.endIndex),
                  let end = result.characters.index(start, offsetBy: length, limitedBy: result.endIndex) else { continue }
            result[start..<end].backgroundColor = Color.yellow.opacity(0.45)
            result[start..<end].foregroundColor = .primary
        }
        return result
    }

    // MARK: Drops

    private static func loadURLs(_ providers: [NSItemProvider], completion: @escaping @MainActor ([URL]) -> Void) {
        let group = DispatchGroup()
        let lock = NSLock()
        nonisolated(unsafe) var urls: [URL] = []
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url {
                    lock.lock(); urls.append(url); lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            let collected = urls
            Task { @MainActor in completion(collected) }
        }
    }
}
