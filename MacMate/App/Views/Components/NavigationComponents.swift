import SwiftUI

// MARK: - Modern Compact Header Bar

struct ModernHeaderBar: View {
    @ObservedObject var batteryManager: BatteryManager
    @ObservedObject var updateManager: UpdateManager
    @ObservedObject var thermalManager: ThermalManager = ThermalManager.shared
    var onSelectThermal: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image("MenuBarIcon")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 1) {
                    Text("MacMate")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("Tiện ích cho máy Mac")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    updateManager.checkForUpdates(silent: false)
                } label: {
                    HStack(spacing: 4) {
                        Text("v\(UpdateManager.currentVersion)")
                        if updateManager.hasNewUpdate {
                            Circle().fill(Color.green).frame(width: 6, height: 6)
                        }
                    }
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(updateManager.hasNewUpdate ? Color.green.opacity(0.14) : Color.primary.opacity(0.06)))
                    .foregroundStyle(updateManager.hasNewUpdate ? Color.green : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(updateManager.hasNewUpdate ? "Đã có bản mới! Bấm để cập nhật" : "Kiểm tra bản cập nhật mới")

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .help("Thoát MacMate")
            }

            HStack(spacing: 6) {
                statusPill(icon: batteryStatusIcon, title: statusText, color: statusColor)

                if thermalManager.cpuAvgTemp > 0 {
                    Button {
                        onSelectThermal?()
                    } label: {
                        statusPill(
                            icon: "thermometer.medium",
                            title: String(format: "%.0f°C", thermalManager.cpuPeakTemp > 0 ? thermalManager.cpuPeakTemp : thermalManager.cpuAvgTemp),
                            color: headerTempColor
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Bấm để xem nhiệt độ và cảm biến")
                }

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private func statusPill(icon: String, title: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(color.opacity(0.12)))
        .foregroundStyle(color)
    }

    private var headerTempColor: Color {
        let temp = thermalManager.cpuPeakTemp > 0 ? thermalManager.cpuPeakTemp : thermalManager.cpuAvgTemp
        if temp < 60.0 {
            return .green
        } else if temp < 80.0 {
            return .orange
        } else {
            return .red
        }
    }

    private var statusColor: Color {
        if batteryManager.isBypassActive {
            return .cyan
        } else if batteryManager.isCharging {
            return .green
        } else if batteryManager.isPluggedIn {
            return .orange
        } else {
            return .secondary
        }
    }

    private var statusText: String {
        if batteryManager.isBypassActive {
            return "\(batteryManager.chargeLimit)% · Bypass"
        } else if batteryManager.isCharging {
            return "Đang sạc"
        } else if batteryManager.isPluggedIn {
            return "Đã kết nối nguồn"
        } else {
            return "Pin \(batteryManager.currentLevel)%"
        }
    }

    private var batteryStatusIcon: String {
        if batteryManager.isBypassActive { return "shield.lefthalf.filled" }
        if batteryManager.isCharging { return "battery.100percent.bolt" }
        if batteryManager.isPluggedIn { return "powerplug" }
        return "battery.100percent"
    }
}

// MARK: - Top Tab Navigation Bar

struct TopTabBar: View {
    @Binding var selectedTab: Int

    var body: some View {
        HStack(spacing: 4) {
            tabButton(index: 0, title: "Pin & Phần cứng", icon: "shield.checkered")
            tabButton(index: 1, title: "Tính năng", icon: "square.grid.2x2")
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.primary.opacity(0.055)))
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    private func tabButton(index: Int, title: String, icon: String) -> some View {
        Button {
            selectedTab = index
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: selectedTab == index ? .bold : .medium))
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selectedTab == index ? Color.accentColor : Color.clear)
            )
            .foregroundStyle(selectedTab == index ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

struct MacMateCardStyle: ViewModifier {
    var padding: CGFloat = 12
    var tint: Color? = nil

    func body(content: Content) -> some View {
        let strokeColor = tint.map { $0.opacity(0.3) } ?? Color.primary.opacity(0.08)
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(strokeColor, lineWidth: 1)
            )
    }
}

extension View {
    func macMateCard(padding: CGFloat = 12, tint: Color? = nil) -> some View {
        modifier(MacMateCardStyle(padding: padding, tint: tint))
    }
}
