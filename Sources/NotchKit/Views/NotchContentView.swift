import SwiftUI

/// Root SwiftUI view inside the panel window. Draws the shape for the current state and its contents.
struct NotchContentView: View {
    let model: NotchPanelModel
    let activities: LiveActivityCenter
    let widgets: WidgetRegistry

    var body: some View {
        let size = model.layout.size(for: model.state, compactSide: model.compactSide)
        ZStack(alignment: .top) {
            background
                .frame(width: size.width, height: size.height)
                .overlay(alignment: .top) { content.frame(width: size.width, height: size.height) }
                .clipShape(shape)
                .overlay {
                    if model.isDragTarget {
                        shape.strokeBorder(.white.opacity(0.7), lineWidth: 2)
                            .frame(width: size.width, height: size.height)
                            .overlay(alignment: .bottom) {
                                if model.state == .expanded {
                                    Label("Drop to keep on the Shelf", systemImage: "tray.and.arrow.down.fill")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 12).padding(.vertical, 6)
                                        .background(.white.opacity(0.18), in: Capsule())
                                        .padding(.bottom, 26)
                                        .allowsHitTesting(false)
                                }
                            }
                    }
                }
                .contentShape(shape)
                .onTapGesture { model.onTap?() }
                .padding(.top, model.layout.topInset(for: model.state))
                .animation(model.spring, value: model.state)
                .animation(model.spring, value: model.layout)
                .animation(model.spring, value: model.compactSide)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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

    /// The activity's two small views, each measured so the side areas are exactly as wide as they need to be.
    private var compactRow: some View {
        let notchWidth = model.layout.collapsedSize.width
        let side = model.compactSide
        let primary = activities.primary
        let secondary = activities.secondary
        return HStack(spacing: 0) {
            HStack { Spacer(minLength: 0); primary?.compactLeading().fixedSize().measuringCompactContent(model: model, leading: true) }
                .frame(width: side - 4)
            Spacer().frame(width: notchWidth + 8)
            HStack { (secondary ?? primary)?.compactTrailing().fixedSize().measuringCompactContent(model: model, leading: false); Spacer(minLength: 0) }
                .frame(width: side - 4)
        }
        .frame(height: model.layout.compactSize(side: side).height)
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

private extension View {
    /// Reports this view's width to the model as the content of one compact side.
    func measuringCompactContent(model: NotchPanelModel, leading: Bool) -> some View {
        onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            model.reportCompactContent(width: width, leading: leading)
        }
    }
}
