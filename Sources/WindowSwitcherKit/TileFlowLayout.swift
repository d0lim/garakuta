import AppKit
import SwiftUI

/// Tiles of one height and their own widths laid out left to right, wrapping when the next one would cross the
/// width limit. Rows are centred. The arithmetic is separate from the SwiftUI layout so the panel can be sized, and
/// the automatic size preset chosen, before anything is rendered.
enum TileFlow {
    struct Placement: Equatable {
        var origins: [CGPoint]
        var rows: [[Int]]
        var size: CGSize
    }

    static func place(widths: [CGFloat], rowHeight: CGFloat, maxWidth: CGFloat, spacing: CGFloat) -> Placement {
        var rows: [[Int]] = [[]]
        var rowWidths: [CGFloat] = [0]
        for (index, width) in widths.enumerated() {
            let current = rowWidths[rowWidths.count - 1]
            let projected = current == 0 ? width : current + spacing + width
            if projected > maxWidth, !rows[rows.count - 1].isEmpty {
                rows.append([index])
                rowWidths.append(width)
            } else {
                rows[rows.count - 1].append(index)
                rowWidths[rowWidths.count - 1] = projected
            }
        }
        let gridWidth = rowWidths.max() ?? 0
        var origins = [CGPoint](repeating: .zero, count: widths.count)
        var y: CGFloat = 0
        for (rowIndex, row) in rows.enumerated() {
            var x = ((gridWidth - rowWidths[rowIndex]) / 2).rounded()
            for index in row {
                origins[index] = CGPoint(x: x, y: y)
                x += widths[index] + spacing
            }
            y += rowHeight + spacing
        }
        let height = rows.first?.isEmpty == true ? 0 : y - spacing
        return Placement(origins: origins, rows: rows, size: CGSize(width: gridWidth, height: max(0, height)))
    }
}

/// SwiftUI `Layout` over `TileFlow`. Every subview reports its own width; the height is fixed.
struct TileFlowLayout: Layout {
    var rowHeight: CGFloat
    var maxWidth: CGFloat
    var spacing: CGFloat

    private func widths(_ subviews: Subviews) -> [CGFloat] {
        subviews.map { $0.sizeThatFits(.unspecified).width }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        TileFlow.place(widths: widths(subviews), rowHeight: rowHeight, maxWidth: maxWidth, spacing: spacing).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let w = widths(subviews)
        let placement = TileFlow.place(widths: w, rowHeight: rowHeight, maxWidth: maxWidth, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            let origin = placement.origins[index]
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), anchor: .topLeading,
                          proposal: ProposedViewSize(width: w[index], height: rowHeight))
        }
    }
}

/// Everything the view needs to draw tiles for one screen, one style and one size: decided once per session so
/// the panel does not resize under the pointer.
struct SwitcherMetrics: Equatable {
    var style: SwitcherSettings.Style
    var preset: SwitcherSettings.SizePreset
    /// Height of a whole tile, thumbnail and title included.
    var tileHeight: CGFloat
    /// Height of the thumbnail area inside a tile (thumbnails style only).
    var thumbnailHeight: CGFloat
    var minTileWidth: CGFloat
    var maxTileWidth: CGFloat
    /// Widest the grid may grow before wrapping.
    var maxGridWidth: CGFloat
    /// Tallest the grid may grow before it scrolls.
    var maxGridHeight: CGFloat
    var iconSize: CGFloat
    var fontSize: CGFloat
    var spacing: CGFloat = 10
    var tilePadding: CGFloat = 8

    static let titleRowHeight: CGFloat = 20
    static let subtitleRowHeight: CGFloat = 14

    /// Width of the tile for a window, from its aspect ratio.
    func tileWidth(for window: SwitcherWindow) -> CGFloat {
        switch style {
        case .thumbnails:
            let content = window.isAppPlaceholder ? thumbnailHeight : thumbnailHeight * window.aspectRatio
            return (min(max(content + tilePadding * 2, minTileWidth), maxTileWidth)).rounded()
        case .appIcons:
            return minTileWidth
        case .titles:
            return maxTileWidth
        }
    }

    /// The most comfortable panel width for a screen: about 60 cm of a physical display, never less than 45% or
    /// more than 90% of it. A wide monitor is usually sat close to, so the panel should not span all of it.
    static func comfortableFraction(physicalWidthMM: CGFloat?) -> CGFloat {
        guard let physicalWidthMM, physicalWidthMM > 0 else { return 0.9 }
        return min(0.9, max(0.45, 600 / physicalWidthMM))
    }

    /// Metrics for a style and a *concrete* preset (never `.auto`).
    static func make(style: SwitcherSettings.Style, preset: SwitcherSettings.SizePreset, screen: CGRect, physicalWidthMM: CGFloat?,
                     showsSubtitle: Bool) -> SwitcherMetrics {
        let landscape = screen.width >= screen.height
        let maxGridWidth = (screen.width * comfortableFraction(physicalWidthMM: physicalWidthMM) - 40).rounded()
        let maxGridHeight = (screen.height * 0.8 - 60).rounded()
        var m = SwitcherMetrics(style: style, preset: preset, tileHeight: 0, thumbnailHeight: 0, minTileWidth: 0, maxTileWidth: 0,
                                maxGridWidth: maxGridWidth, maxGridHeight: maxGridHeight, iconSize: 18, fontSize: 12)
        switch style {
        case .thumbnails:
            let rows = CGFloat(preset.rows + (landscape ? 0 : 3))
            let tileHeight = ((maxGridHeight - (rows - 1) * m.spacing) / rows).rounded(.down)
            let textRows = titleRowHeight + (showsSubtitle ? subtitleRowHeight : 0)
            m.tileHeight = tileHeight
            m.thumbnailHeight = tileHeight - textRows - m.tilePadding * 2 - 6
            // Narrow enough that a portrait window does not waste a whole slot, wide enough for a few words of title.
            let ratio = maxGridWidth / maxGridHeight
            let minFraction = landscape ? max(0.09, 0.7 / (ratio * rows)) : 1.3 / rows
            let maxFraction = landscape ? min(0.30, 1.5 / (ratio * rows)) : min(0.5, 2.1 / rows)
            m.minTileWidth = (maxGridWidth * minFraction).rounded()
            m.maxTileWidth = (maxGridWidth * maxFraction).rounded()
            switch preset {
            case .small: m.iconSize = 16; m.fontSize = 11
            case .medium: m.iconSize = 18; m.fontSize = 12
            case .large, .auto: m.iconSize = 20; m.fontSize = 13
            }
        case .appIcons:
            switch preset {
            case .small: m.iconSize = 64; m.fontSize = 11
            case .medium: m.iconSize = 88; m.fontSize = 12
            case .large, .auto: m.iconSize = 112; m.fontSize = 13
            }
            m.minTileWidth = (m.iconSize + 40).rounded()
            m.maxTileWidth = m.minTileWidth
            m.tileHeight = m.iconSize + titleRowHeight + m.tilePadding * 2 + 6
            m.thumbnailHeight = m.iconSize
        case .titles:
            switch preset {
            case .small: m.iconSize = 18; m.fontSize = 12; m.tileHeight = 30
            case .medium: m.iconSize = 22; m.fontSize = 13; m.tileHeight = 34
            case .large, .auto: m.iconSize = 26; m.fontSize = 14; m.tileHeight = 40
            }
            m.spacing = 4
            m.tilePadding = 6
            let width = min(max(screen.width * 0.42, 420), 900).rounded()
            m.minTileWidth = width
            m.maxTileWidth = width
            // One title per row: a list reads top to bottom.
            m.maxGridWidth = width
            m.thumbnailHeight = 0
        }
        return m
    }

    /// Resolves `.auto` to the largest preset whose grid fits in the height limit for these windows; the smallest
    /// preset when none does.
    static func resolve(style: SwitcherSettings.Style, preset: SwitcherSettings.SizePreset, screen: CGRect, physicalWidthMM: CGFloat?,
                        showsSubtitle: Bool, windows: [SwitcherWindow]) -> SwitcherMetrics {
        let candidates: [SwitcherSettings.SizePreset] = preset == .auto ? [.large, .medium, .small] : [preset]
        var chosen: SwitcherMetrics?
        for candidate in candidates {
            let m = make(style: style, preset: candidate, screen: screen, physicalWidthMM: physicalWidthMM, showsSubtitle: showsSubtitle)
            chosen = m
            let placement = TileFlow.place(widths: windows.map(m.tileWidth(for:)), rowHeight: m.tileHeight,
                                           maxWidth: m.maxGridWidth, spacing: m.spacing)
            if placement.size.height <= m.maxGridHeight { break }
        }
        return chosen ?? make(style: style, preset: .small, screen: screen, physicalWidthMM: physicalWidthMM, showsSubtitle: showsSubtitle)
    }
}
