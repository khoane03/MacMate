import SwiftUI
import AppKit

// MARK: - App Icon Cache for Fast & Smooth Rendering

private enum AppIconCache {
    private static var cache: [String: NSImage] = [:]

    static func icon(for bundleID: String?, appName: String?) -> NSImage? {
        let key = bundleID ?? appName ?? ""
        guard !key.isEmpty else { return nil }
        if let cached = cache[key] { return cached }

        if let bundleID = bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let img = NSWorkspace.shared.icon(forFile: url.path)
            cache[key] = img
            return img
        }
        if let appName = appName,
           let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == appName }),
           let icon = app.icon {
            cache[key] = icon
            return icon
        }
        return nil
    }
}

// MARK: - Clipboard HUD Overlay View

public struct ClipboardOverlayView: View {
    @ObservedObject var manager: ClipboardManager

    public init(manager: ClipboardManager) {
        self.manager = manager
    }

    public var body: some View {
        ZStack {
            // Modern Frosted Glass Background
            VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
                .overlay(Color(nsColor: .windowBackgroundColor).opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.24),
                                    Color.white.opacity(0.10),
                                    Color.primary.opacity(0.06)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )

            VStack(spacing: 0) {
                // Top Search & Filter Header
                topSearchBar

                // Filter Category Bar
                categoryBar

                Divider().opacity(0.15)

                // List of Clips or Empty State
                if manager.filteredItems.isEmpty {
                    emptyStateView
                } else {
                    clipsListView
                }

                Divider().opacity(0.15)

                // Bottom Footer & Hotkey Hints
                footerBar
            }
        }
        .frame(width: 440, height: 540)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.25), radius: 24, x: 0, y: 12)
        .background(Color.clear)
    }

    // MARK: - Top Search Bar

    private var topSearchBar: some View {
        VStack(spacing: 10) {
            // Header Bar
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.on.clipboard.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.accentColor)

                    Text("Clipboard")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("\(manager.filteredItems.count)")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }

                Spacer()

                Button {
                    manager.hideHUD()
                } label: {
                    HStack(spacing: 3) {
                        Text("⎋")
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        Text("Đóng")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.primary.opacity(0.07)))
                }
                .buttonStyle(.plain)
                .help("Đóng (Esc)")
            }

            // Spotlight-style Search Input
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(manager.searchText.isEmpty ? Color.secondary : Color.accentColor)

                TextField("Tìm văn bản, liên kết, ảnh… (1–9 dán nhanh)", text: $manager.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5, weight: .medium))
                    .onSubmit {
                        manager.pasteSelectedItem()
                    }

                if !manager.searchText.isEmpty {
                    Button {
                        manager.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Xóa tìm kiếm")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8.5)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.65))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Color.primary.opacity(manager.searchText.isEmpty ? 0.08 : 0.18), lineWidth: 1)
            )
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    // MARK: - Category Filter Bar

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach([ClipType.all, .text, .image, .url, .file, .color], id: \.self) { type in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            manager.selectedFilter = type
                        }
                    } label: {
                        HStack(spacing: 4.5) {
                            Image(systemName: type.icon)
                                .font(.system(size: 9.5))
                            Text(type.title)
                                .font(.system(size: 10.5, weight: manager.selectedFilter == type ? .bold : .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(
                                manager.selectedFilter == type
                                    ? Color.accentColor
                                    : Color.primary.opacity(0.06)
                            )
                        )
                        .foregroundStyle(manager.selectedFilter == type ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Clips List View

    private var clipsListView: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 6) {
                    ForEach(Array(manager.filteredItems.enumerated()), id: \.element.id) { index, item in
                        clipRow(index: index, item: item)
                            .id(item.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Single Clip Row

    private func clipRow(index: Int, item: ClipItem) -> some View {
        let isSelected = manager.selectedIndex == index
        let isHovered = manager.hoveredItemID == item.id
        let shortcutDigit = index < 9 ? "\(index + 1)" : nil
        let appIconImage = AppIconCache.icon(for: item.sourceBundleID, appName: item.sourceAppName)

        return Button {
            manager.pasteItem(item)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                // Keycap Badge (1..9) or Pin Indicator
                ZStack {
                    if item.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                    } else if let digit = shortcutDigit {
                        Text(digit)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(isSelected ? Color.white : .primary.opacity(0.85))
                    } else {
                        Image(systemName: item.type.icon)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                        .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                        .stroke(isSelected ? Color.clear : Color.primary.opacity(0.1), lineWidth: 0.5)
                )
                .padding(.top, 2)

                // Main Content Column
                VStack(alignment: .leading, spacing: 4) {
                    // Header Row: App Icon + App Name + Timestamp + Action Buttons
                    HStack(spacing: 5) {
                        if let img = appIconImage {
                            Image(nsImage: img)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 12, height: 12)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }

                        if let appName = item.sourceAppName, !appName.isEmpty {
                            Text(appName)
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(Color.accentColor)
                            Text("•")
                                .font(.system(size: 8.5))
                                .foregroundStyle(.secondary.opacity(0.6))
                        }

                        Text(item.relativeTimeText)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)

                        Spacer()

                        // Action Buttons: Pin / Delete (Smooth hover display)
                        HStack(spacing: 6) {
                            Button {
                                manager.togglePin(item)
                            } label: {
                                Image(systemName: item.isPinned ? "pin.slash.fill" : "pin.fill")
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(item.isPinned ? .orange : .secondary)
                                    .frame(width: 20, height: 20)
                                    .background(Circle().fill(Color.primary.opacity(0.06)))
                            }
                            .buttonStyle(.plain)
                            .help(item.isPinned ? "Bỏ ghim (⌥P)" : "Ghim lên đầu (⌥P)")

                            Button {
                                manager.deleteItem(item)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(.red.opacity(0.85))
                                    .frame(width: 20, height: 20)
                                    .background(Circle().fill(Color.red.opacity(0.08)))
                            }
                            .buttonStyle(.plain)
                            .help("Xóa mục này (⌥⌫)")
                        }
                        .opacity(isHovered || isSelected ? 1 : 0)
                        .allowsHitTesting(isHovered || isSelected)
                    }

                    // Content View by Type
                    switch item.type {
                    case .image:
                        if let imgData = manager.thumbnailData(for: item), let nsImg = NSImage(data: imgData) {
                            HStack(spacing: 10) {
                                Image(nsImage: nsImg)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxWidth: 160, maxHeight: 75)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                                    )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.primary)
                                    Text(item.detail)
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                    case .color:
                        HStack(spacing: 10) {
                            if let hex = item.colorHex {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color(hex: hex))
                                    .frame(width: 26, height: 26)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .stroke(Color.primary.opacity(0.2), lineWidth: 0.5)
                                    )
                                    .shadow(color: Color.black.opacity(0.1), radius: 2, y: 1)
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title)
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.primary)
                                Text(item.detail)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                        }

                    case .file:
                        HStack(spacing: 8) {
                            Image(systemName: "doc.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title)
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(item.detail)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                    case .url:
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 5) {
                                Image(systemName: "link")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.blue)
                                Text(item.title)
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(Color.blue)
                                    .lineLimit(1)
                            }
                            Text(item.detail)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }

                    case .text, .rtf, .all:
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)

                            if let text = item.plainText, text != item.title {
                                Text(text.replacingOccurrences(of: "\n", with: " "))
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(
                        isSelected
                            ? Color.accentColor.opacity(0.16)
                            : (isHovered ? Color.primary.opacity(0.045) : Color.clear)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.45) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            manager.hoveredItemID = hovering ? item.id : nil
            if hovering {
                manager.selectedIndex = index
            }
        }
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: 10) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 64, height: 64)
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Color.accentColor)
            }

            Text("Lịch sử Clipboard trống")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text("Hãy sao chép (⌘C) văn bản, hình ảnh hoặc tệp tin để MacMate tự động lưu lại tại đây.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 44)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Bottom Footer Bar

    private var footerBar: some View {
        HStack {
            // Key hints
            HStack(spacing: 8) {
                legendItem(key: "↵", label: "Dán")
                legendItem(key: "1–9", label: "Nhanh")
                legendItem(key: "⌥P", label: "Ghim")
                legendItem(key: "⌥⌫", label: "Xóa")
                legendItem(key: "⎋", label: "Đóng")
            }

            Spacer()

            // Count & Clear button
            HStack(spacing: 7) {
                Text("\(manager.filteredItems.count) mục")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.secondary)

                Button {
                    manager.clearAllHistory()
                } label: {
                    Text("Xóa hết")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.red.opacity(0.85))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(Capsule().fill(Color.red.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .help("Xóa toàn bộ mục chưa ghim")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.primary.opacity(0.025))
    }

    private func legendItem(key: String, label: String) -> some View {
        HStack(spacing: 3) {
            Text(key)
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .padding(.horizontal, 4.5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(0.09))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                )
            Text(label)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Color Hex Initializer

private extension Color {
    init(hex: String) {
        let cleanHex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleanHex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch cleanHex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
