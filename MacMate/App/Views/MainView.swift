import SwiftUI

public struct MainView: View {
    @State private var selectedTab: Int
    @ObservedObject private var batteryManager = BatteryManager.shared
    @ObservedObject private var snapManager = WindowSnapManager.shared
    @ObservedObject private var windowManager = WindowManager.shared
    @ObservedObject private var clipboardManager = ClipboardManager.shared
    @ObservedObject private var updateManager = UpdateManager.shared
    @ObservedObject private var thermalManager = ThermalManager.shared

    public init(initialTab: Int = 0) {
        _selectedTab = State(initialValue: min(max(initialTab, 0), 2))
    }

    public var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ModernHeaderBar(
                    batteryManager: batteryManager,
                    updateManager: updateManager,
                    thermalManager: thermalManager,
                    onSelectThermal: {
                        selectedTab = 0
                        thermalManager.selectedSection = 1
                    }
                )

                TopTabBar(selectedTab: $selectedTab)
                Divider().padding(.horizontal, 14)

                Group {
                    if selectedTab == 0 {
                        HardwareCareTabView(
                            batteryManager: batteryManager,
                            thermalManager: thermalManager
                        )
                    } else if selectedTab == 1 {
                        ShortcutsTabView(
                            snapManager: snapManager,
                            windowManager: windowManager,
                            clipboardManager: clipboardManager
                        )
                    } else {
                        CleanerTabView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider().padding(.horizontal, 14)
                FooterView(updateManager: updateManager)
            }

            if updateManager.showUpdateModal {
                UpdateModalView(updateManager: updateManager)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: updateManager.showUpdateModal)
        .frame(width: 380, height: 570)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
