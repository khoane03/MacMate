import SwiftUI

struct ShortcutsTabView: View {
    let selectedTab: MainTab
    let snapManager: WindowSnapManager
    let windowManager: WindowManager
    let clipboardManager: ClipboardManager

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 14) {
                AccessibilityBanner()

                switch selectedTab {
                case .window:
                    WindowSwitchCard(manager: windowManager)
                    WindowSnapCard(manager: snapManager)
                case .clipboard:
                    ClipboardSettingsCard(manager: clipboardManager)
                case .mouse:
                    ScrollSettingsCard()
                    MouseChordCard()
                }

                // Global Restore Defaults Card
                RestoreDefaultsFooter()
            }
            .padding(14)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Accessibility Banner

private struct AccessibilityBanner: View {
    @ObservedObject private var keyInterceptor = KeyInterceptor.shared

    var body: some View {
        if !keyInterceptor.hasAccessibility {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 18))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cần cấp quyền Trợ năng")
                        .font(.system(size: 12.5, weight: .semibold))
                    Text("Bật MacMate trong Cài đặt hệ thống để dùng phím tắt và điều khiển cửa sổ.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Mở cài đặt quyền") { keyInterceptor.requestAccessibility() }
                        .font(.system(size: 11, weight: .semibold))
                        .buttonStyle(.link)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .macMateCard(padding: 12, tint: .orange)
        }
    }
}

// MARK: - Restore Defaults Footer

private struct RestoreDefaultsFooter: View {
    private let shortcuts = ShortcutManager.shared

    var body: some View {
        HStack {
            Spacer()
            Button {
                shortcuts.restoreDefaults()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 10))
                    Text("Khôi phục phím tắt mặc định")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Khôi phục tất cả phím tắt mặc định của MacMate")
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Window Switcher Settings Card

private struct WindowSwitchCard: View {
    @ObservedObject var manager: WindowManager

    var body: some View {
        SettingsCard(
            title: "Chuyển cửa sổ (Alt+Tab)",
            subtitle: "Xem trước và chuyển nhanh giữa các cửa sổ",
            icon: "macwindow.on.rectangle",
            tint: .blue
        ) {
            Toggle("Bật chuyển cửa sổ", isOn: $manager.isAltTabEnabled)
        } content: {
            ShortcutBindingRow(action: .altTabNext)
            ShortcutBindingRow(action: .altTabPrevious)

            if manager.isAltTabEnabled {
                HStack(spacing: 12) {
                    ShortcutHint(key: "W", label: "Đóng cửa sổ")
                    ShortcutHint(key: "Q", label: "Thoát ứng dụng")
                }
                .padding(.vertical, 3)

                if !manager.hasScreenRecording {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "camera.viewfinder")
                            .foregroundStyle(.cyan)
                            .font(.system(size: 14))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Cần quyền Ghi màn hình")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Cấp quyền để MacMate hiển thị hình ảnh thu nhỏ thực tế của các cửa sổ.")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                            Button("Cấp quyền ghi màn hình") {
                                manager.requestScreenRecordingPermission()
                            }
                            .font(.system(size: 10.5, weight: .semibold))
                            .buttonStyle(.link)
                        }
                    }
                    .padding(10)
                    .background(Color.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }
}

// MARK: - Window Snap Settings Card

private struct WindowSnapCard: View {
    @ObservedObject var manager: WindowSnapManager

    var body: some View {
        SettingsCard(
            title: "Sắp xếp cửa sổ",
            subtitle: "Chia màn hình và chuyển giữa các màn hình",
            icon: "rectangle.split.2x1",
            tint: .indigo
        ) {
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

// MARK: - Clipboard Settings Card

private struct ClipboardSettingsCard: View {
    @ObservedObject var manager: ClipboardManager

    var body: some View {
        SettingsCard(
            title: "Lịch sử Clipboard",
            subtitle: "Tự động ghi nhớ, tìm kiếm và dán lại nội dung",
            icon: "doc.on.clipboard.fill",
            tint: .orange
        ) {
            Toggle("Bật theo dõi Clipboard", isOn: $manager.isMonitoringEnabled)
        } content: {
            ShortcutBindingRow(action: .clipboardHUD)

            if manager.isMonitoringEnabled {
                HStack(spacing: 10) {
                    ShortcutHint(key: "1–9", label: "Dán nhanh")
                    ShortcutHint(key: "⌥P", label: "Ghim")
                    ShortcutHint(key: "⌥⌫", label: "Xóa")
                }
                .padding(.vertical, 3)

                Divider().opacity(0.15)

                // History Limit Chips
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Giới hạn lưu trữ")
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                        Text("\(manager.items.count) mục hiện tại")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 6) {
                        ForEach([50, 100, 200, 500], id: \.self) { count in
                            SettingsChip(title: "\(count)", selected: manager.maxItemsCount == count) {
                                manager.maxItemsCount = count
                            }
                        }
                        SettingsChip(title: "Không giới hạn", selected: manager.hasUnlimitedHistory) {
                            manager.maxItemsCount = 0
                        }
                    }
                }

                // Auto Cleanup Chips
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tự động dọn dẹp sau")
                        .font(.system(size: 11, weight: .medium))
                    HStack(spacing: 6) {
                        ForEach([0, 7, 30, 90], id: \.self) { days in
                            SettingsChip(title: days == 0 ? "Không xóa" : "\(days) ngày", selected: manager.autoCleanupDays == days) {
                                manager.autoCleanupDays = days
                            }
                        }
                    }
                }

                Toggle("Bỏ qua mật khẩu từ ứng dụng bảo mật (1Password, Keychain…)", isOn: $manager.ignoreConcealedTypes)
                    .font(.system(size: 11))
                    .toggleStyle(.checkbox)

                Divider().opacity(0.15)

                // Actions: Open HUD & Cleanup
                HStack(spacing: 8) {
                    Button {
                        manager.toggleHUD()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "macwindow")
                            Text("Mở bảng Clipboard")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)

                    Spacer(minLength: 0)

                    Button("Dọn mục cũ") { manager.cleanupNow() }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .help("Xóa các mục chưa ghim cũ hơn thời gian quy định")

                    Button(manager.pendingClearAllConfirm ? "Xác nhận xóa" : "Xóa hết") {
                        manager.requestClearAllUnpinned()
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.red)
                    .controlSize(.regular)
                    .help("Bấm hai lần để xóa sạch toàn bộ mục chưa ghim")
                }
                .font(.system(size: 11, weight: .medium))

                if let message = manager.cleanupMessage {
                    Text(message)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - Mouse & Scroll Settings Cards

private struct MouseChordCard: View {
    @ObservedObject private var shortcuts = ShortcutManager.shared

    var body: some View {
        SettingsCard(
            title: "Cử chỉ chuột (Mission Control)",
            subtitle: "Bấm đồng thời cả chuột trái và chuột phải",
            icon: "cursorarrow.click.2",
            tint: .purple
        ) {
            Toggle("Bật tổ hợp chuột", isOn: $shortcuts.isMouseChordEnabled)
        } content: {
            EmptyView()
        }
    }
}

private struct ScrollSettingsCard: View {
    @ObservedObject private var manager = SmoothScrollManager.shared

    var body: some View {
        SettingsCard(
            title: "Cuộn chuột ngoài mượt mà",
            subtitle: "Khắc phục hiện tượng giật khi dùng chuột rời trên macOS",
            icon: "computermouse.fill",
            tint: .green
        ) {
            Toggle("Bật cuộn mượt", isOn: Binding(
                get: { manager.isEnabled }, set: { manager.setEnabled($0) }
            ))
        } content: {
            Toggle("Đảo chiều cuộn chuột ngoài (tự nhiên)", isOn: Binding(
                get: { manager.isReverseScrollingEnabled },
                set: { manager.setReverseScrollingEnabled($0) }
            ))
            .font(.system(size: 11.5))
            .toggleStyle(.checkbox)

            if manager.isEnabled {
                Divider().opacity(0.15)

                ScrollSlider(
                    title: "Tốc độ cuộn",
                    value: Binding(
                        get: { manager.speed }, set: { manager.setSpeed($0) }
                    ),
                    range: 0.5...3,
                    step: 0.1,
                    display: String(format: "%.1fx", manager.speed)
                )

                ScrollSlider(
                    title: "Độ mượt mà",
                    value: Binding(
                        get: { manager.smoothness }, set: { manager.setSmoothness($0) }
                    ),
                    range: 0...1,
                    step: 0.05,
                    display: "\(Int(manager.smoothness * 100))%"
                )

                Text("Hỗ trợ bánh xe cuộn dọc, ngang và giữ Shift để cuộn ngang.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Reusable Settings Card Container

private struct SettingsCard<Control: View, Content: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    @ViewBuilder let control: Control
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            control
                .font(.system(size: 11.5, weight: .medium))
                .toggleStyle(.switch)
                .controlSize(.small)

            if Content.self != EmptyView.self {
                Divider().opacity(0.15)
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .macMateCard(padding: 14)
    }
}

// MARK: - Shortcut Binding Row Component

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
            .font(.system(size: 11.5))
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

// MARK: - Settings Chip Component

private struct SettingsChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10.5, weight: selected ? .bold : .medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 4.5)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(
                    Capsule().fill(selected ? Color.accentColor : Color.primary.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shortcut Hint Component

private struct ShortcutHint: View {
    let key: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                )
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Scroll Slider Component

private struct ScrollSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let display: String

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 80, alignment: .leading)
            Slider(value: $value, in: range, step: step)
                .controlSize(.small)
            Text(display)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .frame(width: 44, alignment: .trailing)
        }
    }
}
