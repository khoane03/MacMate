import SwiftUI

struct ShortcutsTabView: View {
    let snapManager: WindowSnapManager
    let windowManager: WindowManager
    let clipboardManager: ClipboardManager

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 12) {
                AccessibilityBanner()
                ShortcutsIntroCard()
                WindowSwitchCard(manager: windowManager)
                WindowSnapCard(manager: snapManager)
                ClipboardSettingsCard(manager: clipboardManager)
                MouseChordCard()
                ScrollSettingsCard()
            }
            .padding(14)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct AccessibilityBanner: View {
    @ObservedObject private var keyInterceptor = KeyInterceptor.shared

    var body: some View {
        if !keyInterceptor.hasAccessibility {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 16))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cần cấp quyền Trợ năng")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Bật MacMate trong Cài đặt hệ thống để dùng phím tắt và điều khiển cửa sổ.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Mở cài đặt quyền") { keyInterceptor.requestAccessibility() }
                        .font(.system(size: 10, weight: .semibold))
                        .buttonStyle(.link)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .macMateCard(padding: 12, tint: .orange)
        }
    }
}

private struct ShortcutsIntroCard: View {
    private let shortcuts = ShortcutManager.shared

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Tùy chỉnh MacMate")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text("Bật tính năng và gán phím tắt ngay bên dưới.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("Khôi phục") { shortcuts.restoreDefaults() }
                .font(.system(size: 10, weight: .medium))
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Khôi phục tất cả phím tắt mặc định")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .macMateCard(padding: 14, tint: .accentColor)
    }
}

private struct WindowSwitchCard: View {
    @ObservedObject var manager: WindowManager

    var body: some View {
        SettingsCard(title: "Chuyển cửa sổ", subtitle: "Chuyển nhanh giữa các cửa sổ đang mở", icon: "macwindow.on.rectangle", tint: .blue) {
            Toggle("Bật chuyển cửa sổ", isOn: $manager.isAltTabEnabled)
        } content: {
            ShortcutBindingRow(action: .altTabNext)
            ShortcutBindingRow(action: .altTabPrevious)
            if manager.isAltTabEnabled {
                HStack(spacing: 10) {
                    ShortcutHint(key: "W", label: "Đóng cửa sổ")
                    ShortcutHint(key: "Q", label: "Thoát ứng dụng")
                }
                .padding(.top, 2)
                if !manager.hasScreenRecording {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "camera.viewfinder")
                            .foregroundStyle(.cyan)
                        Text("Cấp quyền Ghi màn hình để xem trước cửa sổ.")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Cấp quyền") { manager.requestScreenRecordingPermission() }
                            .buttonStyle(.link)
                    }
                    .font(.system(size: 10))
                    .padding(9)
                    .background(Color.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
}

private struct WindowSnapCard: View {
    @ObservedObject var manager: WindowSnapManager

    var body: some View {
        SettingsCard(title: "Sắp xếp cửa sổ", subtitle: "Chia màn hình và chuyển giữa các màn hình", icon: "rectangle.split.2x1", tint: .indigo) {
            Toggle("Bật sắp xếp cửa sổ", isOn: $manager.isSnapEnabled)
        } content: {
            ShortcutBindingRow(action: .snapLeft)
            ShortcutBindingRow(action: .snapRight)
            ShortcutBindingRow(action: .snapMaximize)
            ShortcutBindingRow(action: .snapCenter)
            ShortcutBindingRow(action: .moveNextDisplay)
            ShortcutBindingRow(action: .movePreviousDisplay)
        }
    }
}

private struct ClipboardSettingsCard: View {
    @ObservedObject var manager: ClipboardManager

    var body: some View {
        SettingsCard(title: "Clipboard", subtitle: "Lưu, tìm và dán lại nội dung đã sao chép", icon: "doc.on.clipboard.fill", tint: .orange) {
            Toggle("Bật lịch sử Clipboard", isOn: $manager.isMonitoringEnabled)
        } content: {
            ShortcutBindingRow(action: .clipboardHUD)

            if manager.isMonitoringEnabled {
                HStack(spacing: 8) {
                    ShortcutHint(key: "1–9", label: "Dán nhanh")
                    ShortcutHint(key: "⌥P", label: "Ghim")
                    ShortcutHint(key: "⌥⌫", label: "Xóa")
                }
                .padding(.vertical, 3)

                Divider()
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("Giới hạn lịch sử")
                            .font(.system(size: 10, weight: .medium))
                        Spacer()
                        Text("\(manager.items.count) mục")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 5) {
                        ForEach([50, 100, 200, 500], id: \.self) { count in
                            SettingsChip(title: "\(count)", selected: manager.maxItemsCount == count) {
                                manager.maxItemsCount = count
                            }
                        }
                        SettingsChip(title: "∞", selected: manager.hasUnlimitedHistory) {
                            manager.maxItemsCount = 0
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text("Tự động xóa sau")
                        .font(.system(size: 10, weight: .medium))
                    HStack(spacing: 5) {
                        ForEach([0, 7, 30, 90], id: \.self) { days in
                            SettingsChip(title: days == 0 ? "Không" : "\(days) ngày", selected: manager.autoCleanupDays == days) {
                                manager.autoCleanupDays = days
                            }
                        }
                    }
                }

                if manager.hasUnlimitedHistory {
                    Text(manager.autoCleanupDays == 0
                         ? "Nên bật tự động xóa để giới hạn dung lượng lưu trữ."
                         : "Các mục cũ sẽ tự xóa sau \(manager.autoCleanupDays) ngày.")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Toggle("Bỏ qua mật khẩu từ ứng dụng bảo mật", isOn: $manager.ignoreConcealedTypes)
                    .font(.system(size: 10))

                HStack(spacing: 8) {
                    Button("Mở bảng Clipboard") { manager.toggleHUD() }
                        .buttonStyle(.borderedProminent)
                    Spacer(minLength: 0)
                    Button("Dọn ngay") { manager.cleanupNow() }
                        .help("Xóa mục chưa ghim cũ hơn \(manager.autoCleanupDays > 0 ? "\(manager.autoCleanupDays) ngày" : "30 ngày")")
                    Button(manager.pendingClearAllConfirm ? "Xác nhận xóa" : "Xóa tất cả") {
                        manager.requestClearAllUnpinned()
                    }
                    .foregroundStyle(.red)
                    .help("Xóa mọi mục chưa ghim; bấm hai lần để xác nhận")
                }
                .font(.system(size: 10, weight: .medium))
                .controlSize(.small)

                if let message = manager.cleanupMessage {
                    Text(message)
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct MouseChordCard: View {
    @ObservedObject private var shortcuts = ShortcutManager.shared

    var body: some View {
        SettingsCard(title: "Mission Control", subtitle: "Bấm đồng thời chuột trái và phải", icon: "cursorarrow.click.2", tint: .purple) {
            Toggle("Bật tổ hợp chuột", isOn: $shortcuts.isMouseChordEnabled)
        } content: {
            ShortcutBindingRow(action: .toggleMouseChord)
        }
    }
}

private struct ScrollSettingsCard: View {
    @ObservedObject private var manager = SmoothScrollManager.shared

    var body: some View {
        SettingsCard(title: "Cuộn chuột", subtitle: "Cuộn mượt cho chuột ngoài", icon: "computermouse.fill", tint: .green) {
            Toggle("Bật cuộn mượt", isOn: Binding(
                get: { manager.isEnabled }, set: { manager.setEnabled($0) }
            ))
        } content: {
            Toggle("Đảo chiều cuộn chuột ngoài", isOn: Binding(
                get: { manager.isReverseScrollingEnabled },
                set: { manager.setReverseScrollingEnabled($0) }
            ))
            .font(.system(size: 10))

            if manager.isEnabled {
                ScrollSlider(title: "Tốc độ", value: Binding(
                    get: { manager.speed }, set: { manager.setSpeed($0) }
                ), range: 0.5...3, step: 0.1, display: String(format: "%.1fx", manager.speed))
                ScrollSlider(title: "Độ mượt", value: Binding(
                    get: { manager.smoothness }, set: { manager.setSmoothness($0) }
                ), range: 0...1, step: 0.05, display: "\(Int(manager.smoothness * 100))%")
                Text("Hỗ trợ cuộn dọc, cuộn ngang và Shift + bánh xe")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SettingsCard<Control: View, Content: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    @ViewBuilder let control: Control
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            control
                .font(.system(size: 10, weight: .medium))
                .toggleStyle(.switch)
                .controlSize(.small)
            Divider()
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .macMateCard(padding: 13)
    }
}

private struct ShortcutBindingRow: View {
    let action: ShortcutAction
    @ObservedObject private var shortcuts = ShortcutManager.shared

    var body: some View {
        let binding = shortcuts.binding(for: action)
        return HStack(spacing: 8) {
            Toggle(action.title, isOn: Binding(
                get: { shortcuts.binding(for: action).isEnabled },
                set: { enabled in
                    var updated = shortcuts.binding(for: action)
                    updated.isEnabled = enabled
                    _ = shortcuts.setBinding(updated, for: action)
                }
            ))
            .font(.system(size: 10))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            KeyRecorderView(binding: binding) { shortcuts.setBinding($0, for: action) }
                .disabled(!binding.isEnabled)
        }
        .frame(minHeight: 28)
    }
}

private struct SettingsChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: selected ? .semibold : .regular))
                .frame(minWidth: 36)
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(selected ? Color.accentColor : Color.primary.opacity(0.07), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct ShortcutHint: View {
    let key: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 5))
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}

private struct ScrollSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let display: String

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .frame(width: 54, alignment: .leading)
            Slider(value: $value, in: range, step: step)
                .controlSize(.small)
            Text(display)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .frame(width: 38, alignment: .trailing)
        }
    }
}
