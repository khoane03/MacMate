import SwiftUI

public enum MainTab: String, CaseIterable, Identifiable {
    case window = "Cửa sổ"
    case clipboard = "Clipboard"
    case mouse = "Chuột"

    public var id: String { rawValue }

    public var title: String { rawValue }

    public var icon: String {
        switch self {
        case .window: return "macwindow.on.rectangle"
        case .clipboard: return "doc.on.clipboard.fill"
        case .mouse: return "computermouse.fill"
        }
    }
}

public struct MainView: View {
    private let snapManager = WindowSnapManager.shared
    private let windowManager = WindowManager.shared
    private let clipboardManager = ClipboardManager.shared

    @State private var selectedTab: MainTab = .window

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // App Header
            MacMateHeader()

            // Segmented Navigation Tabs
            tabBar
                .padding(.horizontal, 14)
                .padding(.bottom, 8)

            Divider().opacity(0.15)

            // Content Area by Tab
            ShortcutsTabView(
                selectedTab: selectedTab,
                snapManager: snapManager,
                windowManager: windowManager,
                clipboardManager: clipboardManager
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 390, height: 570)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(MainTab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 11, weight: selectedTab == tab ? .semibold : .regular))
                        Text(tab.title)
                            .font(.system(size: 11.5, weight: selectedTab == tab ? .bold : .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(selectedTab == tab ? Color(nsColor: .controlBackgroundColor) : Color.clear)
                    )
                    .foregroundStyle(selectedTab == tab ? Color.accentColor : Color.secondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(selectedTab == tab ? Color.primary.opacity(0.08) : Color.clear, lineWidth: 1)
                    )
                    .shadow(color: selectedTab == tab ? Color.black.opacity(0.04) : Color.clear, radius: 2, y: 1)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }
}
