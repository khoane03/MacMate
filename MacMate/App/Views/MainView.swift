import SwiftUI

public struct MainView: View {
    private let snapManager = WindowSnapManager.shared
    private let windowManager = WindowManager.shared
    private let clipboardManager = ClipboardManager.shared

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            MacMateHeader()
            Divider().padding(.horizontal, 14)

            ShortcutsTabView(
                snapManager: snapManager,
                windowManager: windowManager,
                clipboardManager: clipboardManager
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 380, height: 570)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
