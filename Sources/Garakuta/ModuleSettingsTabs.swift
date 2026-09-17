import SwiftUI

/// The pages of the settings window.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general, menuBar, notch, switcher

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .menuBar: "Menu Bar"
        case .notch: "Notch"
        case .switcher: "Switcher"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .menuBar: "menubar.rectangle"
        case .notch: "rectangle.topthird.inset.filled"
        case .switcher: "rectangle.on.rectangle"
        }
    }

    /// First page shown. `GARAKUTA_DEBUG_SETTINGS_TAB` picks another one for layout snapshots.
    static var initial: SettingsTab {
        ProcessInfo.processInfo.environment["GARAKUTA_DEBUG_SETTINGS_TAB"].flatMap(SettingsTab.init(rawValue:)) ?? .general
    }
}

/// Icon-and-label page switcher along the top of the settings window, in the style of a preferences toolbar.
struct SettingsTabStrip: View {
    @Binding var selection: SettingsTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(SettingsTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 20, weight: .regular))
                            .frame(height: 24)
                        Text(tab.title).font(.caption)
                    }
                    .frame(width: 84)
                    .padding(.vertical, 6)
                    .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .background(selection == tab ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(selection == tab ? Color.accentColor : Color.secondary)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
