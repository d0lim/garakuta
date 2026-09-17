import AppKit
import SwiftUI

/// Grid of window tiles shown inside the switcher panel.
struct SwitcherView: View {
    @Bindable var state: SwitcherState
    var onActivate: (SwitcherWindow) -> Void
    var onHover: (SwitcherWindow) -> Void

    private var tileWidth: CGFloat { state.settings.simpleMode || !state.thumbnailsEnabled ? 200 : CGFloat(state.settings.thumbnailWidth) }
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
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: tileWidth, maximum: tileWidth), spacing: 10)], spacing: 10) {
                            ForEach(Array(state.filtered.enumerated()), id: \.element.windowID) { index, window in
                                tile(window, selected: index == state.selectedIndex)
                                    .id(window.windowID)
                                    .onHover { inside in if inside { onHover(window) } }
                                    .onTapGesture { onActivate(window) }
                            }
                        }
                        .padding(4)
                    }
                    .frame(maxHeight: 560)
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

    @ViewBuilder
    private func tile(_ window: SwitcherWindow, selected: Bool) -> some View {
        let showThumb = state.thumbnailsEnabled && !state.settings.simpleMode && !window.isAppPlaceholder
        VStack(alignment: .leading, spacing: 6) {
            if showThumb {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.15))
                    if let cg = state.thumbnails[window.windowID] {
                        Image(decorative: cg, scale: 2)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else if let icon = state.appIcon(for: window) {
                        Image(nsImage: icon).resizable().frame(width: 48, height: 48)
                    }
                }
                .frame(width: tileWidth - 16, height: (tileWidth - 16) * 0.62)
            }
            HStack(spacing: 6) {
                if let icon = state.appIcon(for: window) {
                    Image(nsImage: icon).resizable().frame(width: showThumb ? 18 : 32, height: showThumb ? 18 : 32)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(window.displayTitle).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    if !minimal && !window.isAppPlaceholder && window.title != window.appName && !window.title.isEmpty {
                        Text(window.appName).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if !minimal {
                    if window.isMinimized { badge("arrow.down.right.and.arrow.up.left") }
                    if window.isFullScreen { badge("arrow.up.left.and.arrow.down.right") }
                    if !window.isOnCurrentSpace && !window.isMinimized { badge("rectangle.on.rectangle") }
                    if window.isAppHidden { badge("eye.slash") }
                }
            }
        }
        .padding(8)
        .frame(width: tileWidth)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.35) : Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
        )
    }

    private func badge(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 9)).foregroundStyle(.secondary)
    }
}
