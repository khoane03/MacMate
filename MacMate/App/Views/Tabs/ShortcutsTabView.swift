import SwiftUI

// MARK: - TAB 2: Features & Controls View

struct ShortcutsTabView: View {
    @ObservedObject var snapManager: WindowSnapManager
    @ObservedObject var windowManager: WindowManager
    @ObservedObject var clipboardManager: ClipboardManager
    @ObservedObject var keyInterceptor: KeyInterceptor = KeyInterceptor.shared
    @ObservedObject private var shortcutManager = ShortcutManager.shared
    @ObservedObject private var smoothScrollManager = SmoothScrollManager.shared

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 12) {
                // Accessibility Alert if not granted
                if !keyInterceptor.hasAccessibility {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                            .font(.system(size: 14))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Cần cấp quyền Trợ năng (Accessibility)")
                                .font(.system(size: 11, weight: .bold))
                            Text("Bật MacMate trong Cài đặt hệ thống để phím tắt hoạt động.")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button("Cấp quyền") {
                            keyInterceptor.requestAccessibility()
                        }
                        .font(.system(size: 9, weight: .semibold))
                        .controlSize(.mini)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.yellow.opacity(0.12)))
                }

                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tùy chỉnh từng tính năng")
                            .font(.system(size: 10, weight: .bold))
                        Text("Phím tắt được đặt ngay trong từng mục.")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Button("Đặt mặc định tất cả") {
                        shortcutManager.restoreDefaults()
                    }
                    .font(.system(size: 8, weight: .semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help("Khôi phục tổ hợp phím mặc định cho tất cả tính năng")
                }
                .macMateCard(padding: 10)

                // AltTab Card
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "macwindow.on.rectangle")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.accentColor)

                        VStack(alignment: .leading, spacing: 1) {
                            Text("Chuyển đổi cửa sổ")
                                .font(.system(size: 11.5, weight: .bold))
                            Text("Thay thế AltTab với live preview độc lập & chuẩn MRU")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Toggle("", isOn: Binding<Bool>(
                            get: { windowManager.isAltTabEnabled },
                            set: { windowManager.isAltTabEnabled = $0 }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                    }

                    shortcutBindingRow(.altTabNext)
                    shortcutBindingRow(.altTabPrevious)
                    if windowManager.isAltTabEnabled {
                        HStack(spacing: 6) {
                            shortcutPill(key: "W", desc: "Đóng cửa sổ")
                            shortcutPill(key: "Q", desc: "Thoát App")
                        }

                        if !windowManager.hasScreenRecording {
                            HStack(spacing: 6) {
                                Image(systemName: "camera.viewfinder")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.cyan)
                                Text("Cần quyền Ghi màn hình để hiện ảnh chụp cửa sổ thực tế.")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Cấp quyền") {
                                    windowManager.requestScreenRecordingPermission()
                                }
                                .font(.system(size: 8, weight: .semibold))
                                .controlSize(.mini)
                            }
                            .padding(5)
                            .background(RoundedRectangle(cornerRadius: 5).fill(Color.cyan.opacity(0.08)))
                        }
                    }
                }
                .macMateCard(padding: 12)

                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 8) {
                        Image(systemName: "cursorarrow.click.2")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Bấm đồng thời Chuột Trái + Phải mở Mission Control")
                                .font(.system(size: 10, weight: .semibold))
                            Text("Có thể bật/tắt Mouse Chord bằng phím tắt bên dưới.")
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $shortcutManager.isMouseChordEnabled)
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .labelsHidden()
                    }
                    shortcutBindingRow(.toggleMouseChord)
                }
                .macMateCard(padding: 12)

                // Window Snapping (Rectangle) Card
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "rectangle.split.2x1")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.accentColor)

                        VStack(alignment: .leading, spacing: 1) {
                            Text("Chia cửa sổ & Đa màn hình")
                                .font(.system(size: 11.5, weight: .bold))
                            Text("Bố trí cửa sổ nhanh với độ trễ 0ms")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Toggle("", isOn: Binding<Bool>(
                            get: { snapManager.isSnapEnabled },
                            set: { snapManager.isSnapEnabled = $0 }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                    }

                    VStack(spacing: 4) {
                        shortcutBindingRow(.snapLeft)
                        shortcutBindingRow(.snapRight)
                        shortcutBindingRow(.snapMaximize)
                        shortcutBindingRow(.snapCenter)
                        shortcutBindingRow(.moveNextDisplay)
                        shortcutBindingRow(.movePreviousDisplay)
                    }
                }
                .macMateCard(padding: 12)

                // Clipboard Manager (Maccy Replacement) Card
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.on.clipboard.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.accentColor)

                        VStack(alignment: .leading, spacing: 1) {
                            Text("Quản lý Clipboard")
                                .font(.system(size: 11.5, weight: .bold))
                            Text("Lịch sử sao chép thông minh, tìm kiếm & dán tức thì")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Toggle("", isOn: Binding<Bool>(
                            get: { clipboardManager.isMonitoringEnabled },
                            set: { clipboardManager.isMonitoringEnabled = $0 }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                    }

                    if clipboardManager.isMonitoringEnabled {
                        // Shortcuts & Quick Actions
                        HStack(spacing: 6) {
                            shortcutPill(key: "1..9", desc: "Dán tức thì")
                            shortcutPill(key: "⌥P", desc: "Ghim")
                            shortcutPill(key: "⌥⌫", desc: "Xóa")
                        }
                        // Storage limit + automatic cleanup options
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 4) {
                                Text("Giới hạn:")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)

                                ForEach([50, 100, 200, 500], id: \.self) { count in
                                    optionChip("\(count)", selected: clipboardManager.maxItemsCount == count) {
                                        clipboardManager.maxItemsCount = count
                                    }
                                }
                                optionChip("∞", selected: clipboardManager.hasUnlimitedHistory) {
                                    clipboardManager.maxItemsCount = 0
                                }

                                Spacer()

                                Text("\(clipboardManager.items.count) mục lưu")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)
                            }

                            HStack(spacing: 4) {
                                Text("Tự động xoá:")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)

                                ForEach([0, 7, 30, 90], id: \.self) { days in
                                    optionChip(days == 0 ? "Không" : "\(days) ngày",
                                               selected: clipboardManager.autoCleanupDays == days) {
                                        clipboardManager.autoCleanupDays = days
                                    }
                                }

                                Spacer()

                                Button {
                                    clipboardManager.cleanupNow()
                                } label: {
                                    Text("Dọn ngay")
                                        .font(.system(size: 8, weight: .bold))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(Color.orange.opacity(0.14)))
                                        .foregroundStyle(Color.orange)
                                }
                                .buttonStyle(.plain)
                                .help("Xoá mục chưa ghim cũ hơn \(clipboardManager.autoCleanupDays > 0 ? "\(clipboardManager.autoCleanupDays) ngày" : "30 ngày")")

                                Button {
                                    clipboardManager.requestClearAllUnpinned()
                                } label: {
                                    Text(clipboardManager.pendingClearAllConfirm ? "Chắc chắn?" : "Xoá tất cả")
                                        .font(.system(size: 8, weight: .bold))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(Color.red.opacity(clipboardManager.pendingClearAllConfirm ? 0.22 : 0.10)))
                                        .foregroundStyle(Color.red)
                                }
                                .buttonStyle(.plain)
                                .help("Xoá mọi mục chưa ghim (bấm 2 lần để xác nhận)")
                            }

                            if let message = clipboardManager.cleanupMessage {
                                Text(message)
                                    .font(.system(size: 7.8, weight: .medium))
                                    .foregroundStyle(Color.orange.opacity(0.95))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .transition(.opacity)
                            }

                            if clipboardManager.hasUnlimitedHistory {
                                Text(clipboardManager.autoCleanupDays == 0
                                     ? "Không giới hạn số mục: nên bật tự động xoá để tránh phình bộ nhớ."
                                     : "Không giới hạn số mục • tự động xoá sau \(clipboardManager.autoCleanupDays) ngày.")
                                    .font(.system(size: 7.5))
                                    .foregroundStyle(Color.orange.opacity(0.9))
                            }
                        }

                        // Ignore passwords toggle
                        HStack(spacing: 6) {
                            Image(systemName: "lock.shield")
                                .font(.system(size: 8.5))
                                .foregroundStyle(.green)
                            Text("Tự động bỏ qua mật khẩu (1Password, Bitwarden, Keychain)")
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Toggle("", isOn: Binding<Bool>(
                                get: { clipboardManager.ignoreConcealedTypes },
                                set: { clipboardManager.ignoreConcealedTypes = $0 }
                            ))
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .labelsHidden()
                        }

                        // Open HUD Button
                        Button {
                            clipboardManager.toggleHUD()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "macwindow")
                                    .font(.system(size: 8.5))
                                Text("Mở bảng Clipboard HUD")
                                    .font(.system(size: 8.5, weight: .semibold))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity)
                            .background(Color.accentColor.opacity(0.12))
                            .foregroundStyle(Color.accentColor)
                            .cornerRadius(5)
                        }
                        .buttonStyle(.plain)
                    }
                    shortcutBindingRow(.clipboardHUD)
                }
                .macMateCard(padding: 12)

                // Smooth scrolling for discrete external mouse wheels
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "computermouse.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.accentColor)

                        VStack(alignment: .leading, spacing: 1) {
                            Text("Cuộn mượt cho chuột ngoài")
                                .font(.system(size: 11.5, weight: .bold))
                            Text("Easing & quán tính kiểu Mos • không ảnh hưởng trackpad")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Toggle("", isOn: Binding(
                            get: { smoothScrollManager.isEnabled },
                            set: { smoothScrollManager.setEnabled($0) }
                        ))
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .labelsHidden()
                    }

                    HStack(spacing: 6) {
                        Text("Đảo chiều cuộn chuột ngoài • không ảnh hưởng trackpad/Magic Mouse")
                            .font(.system(size: 8.5, weight: .medium))
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { smoothScrollManager.isReverseScrollingEnabled },
                            set: { smoothScrollManager.setReverseScrollingEnabled($0) }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                    }

                    if smoothScrollManager.isEnabled {
                        HStack(spacing: 8) {
                            Text("Tốc độ")
                                .font(.system(size: 8.5, weight: .medium))
                                .frame(width: 48, alignment: .leading)
                            Slider(value: Binding(
                                get: { smoothScrollManager.speed },
                                set: { smoothScrollManager.setSpeed($0) }
                            ), in: 0.5...3.0, step: 0.1)
                                .controlSize(.mini)
                            Text(String(format: "%.1fx", smoothScrollManager.speed))
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .frame(width: 32, alignment: .trailing)
                        }

                        HStack(spacing: 8) {
                            Text("Độ mượt")
                                .font(.system(size: 8.5, weight: .medium))
                                .frame(width: 48, alignment: .leading)
                            Slider(value: Binding(
                                get: { smoothScrollManager.smoothness },
                                set: { smoothScrollManager.setSmoothness($0) }
                            ), in: 0...1, step: 0.05)
                                .controlSize(.mini)
                            Text("\(Int(smoothScrollManager.smoothness * 100))%")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .frame(width: 32, alignment: .trailing)
                        }

                        HStack(spacing: 5) {
                            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                                .font(.system(size: 8))
                                .foregroundStyle(.green)
                            Text("Hỗ trợ cuộn dọc, cuộn ngang và Shift + wheel")
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .macMateCard(padding: 12)

            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func optionChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 8.5, weight: selected ? .bold : .medium))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(selected ? Color.accentColor : Color.primary.opacity(0.06)))
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private func shortcutPill(key: String, desc: String) -> some View {
        HStack(spacing: 3) {
            Text(key)
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.08)))
            Text(desc)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }

    private func shortcutBindingRow(_ action: ShortcutAction) -> some View {
        let binding = shortcutManager.binding(for: action)
        return HStack(spacing: 6) {
            Toggle("", isOn: Binding(
                get: { shortcutManager.binding(for: action).isEnabled },
                set: { enabled in
                    var updated = shortcutManager.binding(for: action)
                    updated.isEnabled = enabled
                    _ = shortcutManager.setBinding(updated, for: action)
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()

            Text(action.title)
                .font(.system(size: 8.5, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            KeyRecorderView(binding: binding) { recorded in
                shortcutManager.setBinding(recorded, for: action)
            }
            .disabled(!binding.isEnabled)
        }
    }
}
