import SwiftUI

/// Looping illustration of the one gesture that arranges the menu bar: hold ⌘ and drag an icon across the chevron.
/// Shown in settings and the setup assistant instead of a per-item list, which turned out to be harder to grasp.
public struct ArrangeGuideView: View {
    /// Which menu bar the illustration shows.
    public enum Style: Sendable {
        /// Our chevron and double divider: hidden and always-hidden sections.
        case sections
        /// The system's own overflow button: icons on the left overflow first, ⌘-drag decides the order.
        case systemOverflow
    }

    private let style: Style

    public init(style: Style = .sections) {
        self.style = style
    }

    private static let period: TimeInterval = 4.2
    private static let barSize = CGSize(width: 420, height: 30)

    public var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.period) / Self.period
            scene(progress: t)
        }
        .frame(width: Self.barSize.width, height: 92)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(style == .sections
                            ? "Hold the command key and drag a menu bar icon to the left of the chevron to hide it."
                            : "Hold the command key and drag a menu bar icon to the left so it overflows first.")
    }

    // Timeline (fractions of one loop): pointer arrives, ⌘ appears, icon is dragged left across the divider,
    // pointer releases, the icon settles dimmed in the hidden section, then everything fades back.
    private func scene(progress t: Double) -> some View {
        let bar = Self.barSize
        let dividerX: CGFloat = 178          // the chevron: hidden ‹ visible
        let doubleDividerX: CGFloat = 70     // double divider: always hidden | hidden
        let startX: CGFloat = 250            // the dragged icon's home in the visible section
        let endX: CGFloat = 140              // where it lands, left of the divider
        let drag = smooth(clamp((t - 0.22) / 0.42))
        let iconX = startX + (endX - startX) * drag
        let commandVisible = t > 0.12 && t < 0.72
        let dragging = t > 0.18 && t < 0.68
        let settled = t > 0.66
        let fade = t > 0.9 ? 1 - (t - 0.9) / 0.1 : 1

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.08))
                .frame(width: bar.width, height: bar.height)

            // Section tints
            Rectangle().fill(Color.accentColor.opacity(0.10)).frame(width: dividerX - 14, height: bar.height)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 8))
            if style == .sections {
                Rectangle().fill(Color.accentColor.opacity(0.18)).frame(width: doubleDividerX - 14, height: bar.height)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 8))
                divider(bars: 2).position(x: doubleDividerX, y: bar.height / 2)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).position(x: dividerX, y: bar.height / 2)
            } else {
                Image(systemName: "chevron.right.2").font(.system(size: 12, weight: .bold)).position(x: dividerX, y: bar.height / 2)
            }

            // Idle icons
            glyph("wifi").position(x: 318, y: bar.height / 2)
            glyph("battery.100percent").position(x: 356, y: bar.height / 2)
            Text("9:41").font(.system(size: 11, weight: .medium)).monospacedDigit().position(x: 400, y: bar.height / 2)
            glyph("moon.zzz.fill").position(x: 110, y: bar.height / 2).opacity(0.45)
            glyph("bell.badge.fill").position(x: 40, y: bar.height / 2).opacity(0.3)

            // The dragged icon
            glyph("cloud.fill")
                .scaleEffect(dragging ? 1.15 : 1)
                .shadow(color: .black.opacity(dragging ? 0.25 : 0), radius: 3, y: 1)
                .opacity(settled ? 0.45 : 1)
                .position(x: iconX, y: bar.height / 2)

            // Pointer and ⌘ badge
            Image(systemName: "cursorarrow")
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .position(x: iconX + 7, y: bar.height / 2 + 9)
                .opacity(t < 0.9 ? 1 : 0)
            Text("⌘")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.secondary.opacity(0.4)))
                .position(x: iconX, y: bar.height + 26)
                .opacity(commandVisible ? 1 : 0)

            // Section labels
            if style == .sections {
                label("Always hidden", at: doubleDividerX / 2 - 7, width: doubleDividerX - 14)
                label("Hidden", at: (doubleDividerX + dividerX) / 2, width: dividerX - doubleDividerX - 14)
                label("Visible", at: (dividerX + bar.width) / 2, width: bar.width - dividerX - 14)
            } else {
                label("Overflows first", at: dividerX / 2 - 7, width: dividerX - 14)
                label("Stays visible", at: (dividerX + bar.width) / 2, width: bar.width - dividerX - 14)
            }
        }
        .opacity(fade)
        .animation(.easeInOut(duration: 0.25), value: dragging)
        .animation(.easeInOut(duration: 0.25), value: settled)
        .animation(.easeInOut(duration: 0.2), value: commandVisible)
    }

    private func glyph(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: 13, weight: .medium)).foregroundStyle(.primary)
    }

    private func divider(bars: Int) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<bars, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 1).fill(.primary.opacity(0.7)).frame(width: 2, height: 12)
            }
        }
    }

    private func label(_ text: String, at x: CGFloat, width: CGFloat) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(width: max(width, 40))
            .position(x: x, y: Self.barSize.height + 62)
    }

    private func clamp(_ x: Double) -> Double { min(1, max(0, x)) }

    /// Ease in-out.
    private func smooth(_ x: Double) -> CGFloat { CGFloat(x * x * (3 - 2 * x)) }
}
