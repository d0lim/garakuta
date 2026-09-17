import SwiftUI

/// Root SwiftUI view inside the panel window. Draws the shape for the current state and its contents.
struct NotchContentView: View {
    let model: NotchPanelModel
    let activities: LiveActivityCenter
    let widgets: WidgetRegistry

    var body: some View {
        let size = model.layout.size(for: model.state)
        ZStack(alignment: .top) {
            background
                .frame(width: size.width, height: size.height)
                .overlay(alignment: .top) { content.frame(width: size.width, height: size.height) }
                .clipShape(shape)
                .shadow(color: .black.opacity(shadowOpacity), radius: 10, y: 4)
                .overlay {
                    if model.isDragTarget {
                        shape.strokeBorder(.white.opacity(0.7), lineWidth: 2)
                            .frame(width: size.width, height: size.height)
                    }
                }
                .contentShape(shape)
                .onTapGesture { model.onTap?() }
                .padding(.top, model.layout.topInset(for: model.state))
                .animation(model.spring, value: model.state)
                .animation(model.spring, value: model.layout)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var shadowOpacity: Double {
        if model.state == .collapsed && model.layout.hasNotch { return 0 }
        // A pill resting in the menu bar wants a lighter shadow than a floating card.
        if model.state != .expanded && model.layout.islandInMenuBar { return 0.2 }
        return 0.35
    }

    private var shape: some InsettableShape {
        if model.layout.hasNotch {
            return AnyInsettableShape(NotchShape(topRadius: NotchLayout.topEarRadius, bottomRadius: model.state == .collapsed ? 10 : model.appearance.cornerRadius))
        }
        return AnyInsettableShape(RoundedRectangle(cornerRadius: model.state == .collapsed ? model.appearance.pillHeight / 2 : model.appearance.cornerRadius, style: .continuous))
    }

    private var background: some View {
        model.appearance.background.color
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .collapsed:
            Color.clear
        case .compact:
            compactRow
        case .expanded:
            expandedPager
        }
    }

    private var compactRow: some View {
        let notchWidth = model.layout.collapsedSize.width
        let side = model.appearance.sizePreset.compactSideWidth
        let primary = activities.primary
        let secondary = activities.secondary
        return HStack(spacing: 0) {
            HStack { Spacer(minLength: 0); primary?.compactLeading() }
                .frame(width: side - 6)
            Spacer().frame(width: notchWidth + 12)
            HStack { (secondary ?? primary)?.compactTrailing(); Spacer(minLength: 0) }
                .frame(width: side - 6)
        }
        .frame(height: model.layout.compactSize.height)
        .transition(.opacity)
    }

    private var pages: [AnyView] {
        var result: [AnyView] = []
        if let primary = activities.primary {
            result.append(primary.expandedView())
        }
        for group in widgets.pages(for: model.settings.widgetLayout, pageWidth: model.layout.widgetPageWidth) {
            result.append(AnyView(
                HStack(spacing: 10) {
                    ForEach(Array(group.enumerated()), id: \.offset) { _, widget in
                        widget.makeView()
                    }
                }
            ))
        }
        if result.isEmpty {
            result.append(AnyView(Text("Enable widgets in settings").foregroundStyle(.white.opacity(0.6))))
        }
        return result
    }

    private var expandedPager: some View {
        let pages = self.pages
        let index = max(0, min(model.page, pages.count - 1))
        let topInset = model.layout.coversMenuBar ? model.layout.menuBarHeight : 8
        return VStack(spacing: 6) {
            ZStack {
                ForEach(Array(pages.enumerated()), id: \.offset) { i, page in
                    page
                        .padding(.horizontal, 12)
                        .opacity(i == index ? 1 : 0)
                        .offset(x: CGFloat(i - index) * model.layout.expandedSize.width)
                }
            }
            .frame(maxHeight: .infinity)
            .animation(model.spring, value: index)
            if pages.count > 1 {
                HStack(spacing: 5) {
                    ForEach(0..<pages.count, id: \.self) { i in
                        Circle().fill(.white.opacity(i == index ? 0.9 : 0.3)).frame(width: 5, height: 5)
                            .onTapGesture { model.page = i }
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .padding(.top, topInset)
        .transition(.opacity)
    }
}

/// Type-erased insettable shape so the notch and pill can share one code path.
struct AnyInsettableShape: InsettableShape {
    private let pathBuilder: @Sendable (CGRect, CGFloat) -> Path

    init<S: InsettableShape>(_ shape: S) {
        pathBuilder = { rect, inset in shape.inset(by: inset).path(in: rect) }
    }

    private init(builder: @escaping @Sendable (CGRect, CGFloat) -> Path) { pathBuilder = builder }

    func path(in rect: CGRect) -> Path { pathBuilder(rect, 0) }

    func inset(by amount: CGFloat) -> AnyInsettableShape {
        let builder = pathBuilder
        return AnyInsettableShape(builder: { rect, inset in builder(rect, inset + amount) })
    }
}
