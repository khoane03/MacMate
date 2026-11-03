import SwiftUI

struct CleanerTabView: View {
    @StateObject private var manager = CleanerManager()
    @StateObject private var uninstallManager = AppUninstallManager()
    @State private var expandedCategory: CleanerCategory?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 8) {
                summaryCard

                ForEach(CleanerCategory.allCases) { category in
                    categoryCard(category)
                }

                appUninstallCard

                if let message = manager.message {
                    Text(message)
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if manager.trashAccessDenied {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("MacMate chưa được phép đọc Thùng rác.")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Bật Truy cập toàn bộ ổ đĩa cho MacMate trong Cài đặt hệ thống, mở lại ứng dụng rồi bấm Quét.")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Button("Mở cài đặt quyền truy cập") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .font(.system(size: 9, weight: .semibold))
                        .controlSize(.mini)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .macMateCard(padding: 10, tint: .orange)
                }

                if manager.inaccessiblePaths > (manager.trashAccessDenied ? 1 : 0) {
                    Text("Một số vị trí không thể đọc; dung lượng hiển thị có thể chưa đầy đủ.")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack {
                    Button("Quét") { manager.scan() }
                        .disabled(manager.isBusy)
                    Spacer()
                    Button("Dọn dẹp") { manager.preparePreview() }
                        .disabled(manager.isBusy || !manager.hasSelectedItems)
                        .buttonStyle(.borderedProminent)
                }
                .font(.system(size: 10, weight: .semibold))
                .controlSize(.small)
                .padding(.top, 2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .onAppear {
            if manager.phase == .idle { manager.scan() }
            if uninstallManager.applications.isEmpty { uninstallManager.scan() }
        }
        .sheet(isPresented: $manager.showingPreview) {
            previewSheet
        }
        .sheet(isPresented: $uninstallManager.showingConfirmation) {
            uninstallConfirmationSheet
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.accentColor)
                Text("Thống kê dung lượng")
                    .font(.system(size: 11, weight: .bold))
                Spacer()
                if manager.isBusy { ProgressView().controlSize(.mini) }
            }
            Text("Có thể giải phóng \(size(manager.availableBytes))")
                .font(.system(size: 18, weight: .bold, design: .rounded))
            Text(statusText)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            if manager.phase == .finished {
                Text("Đã giải phóng \(size(manager.freedBytes))")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.green)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .macMateCard(padding: 11)
    }

    private func categoryCard(_ category: CleanerCategory) -> some View {
        let categoryItems = manager.items.filter { $0.category == category }
        let bytes = categoryItems.reduce(Int64(0)) { $0 + $1.bytes }
        let selectable = categoryItems.filter { $0.canDelete && ($0.bytes > 0 || $0.category == .trash) }
        let selectedCount = selectable.filter { manager.selectedIDs.contains($0.id) }.count
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: category.icon)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text(category.title)
                        .font(.system(size: 10.5, weight: .bold))
                    Text("\(size(bytes)) · \(category == .trash && manager.trashAccessDenied ? "Cần quyền truy cập" : (categoryItems.isEmpty ? "Không có dữ liệu" : "\(categoryItems.count) mục"))")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !selectable.isEmpty {
                    Toggle(category.title, isOn: Binding(
                        get: { selectedCount == selectable.count },
                        set: { enabled in
                            for item in selectable where manager.selectedIDs.contains(item.id) != enabled {
                                manager.toggle(item)
                            }
                        }
                    ))
                    .labelsHidden()
                    .controlSize(.mini)
                    .disabled(manager.isBusy)
                }
            }
            HStack(spacing: 8) {
                Text(category == .trash && manager.trashAccessDenied ? "Không thể đọc Thùng rác" : categoryStatus(categoryItems))
                    .font(.system(size: 8.5))
                    .foregroundStyle(.secondary)
                Spacer()
                if category == .trash && !categoryItems.isEmpty {
                    Button("Dọn thùng rác") { manager.preparePreview(trashOnly: true) }
                        .disabled(manager.isBusy)
                }
                Button(expandedCategory == category ? "Thu gọn" : "Xem chi tiết") {
                    expandedCategory = expandedCategory == category ? nil : category
                }
                .disabled(categoryItems.isEmpty)
            }
            .font(.system(size: 9, weight: .medium))
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)

            if expandedCategory == category {
                Divider()
                if category == .agent {
                    ForEach(["Cache", "Context", "History", "Session cũ", "Dữ liệu tạm"], id: \.self) { kind in
                        HStack {
                            Text(kind)
                            Spacer()
                            Text(size(categoryItems.filter { $0.kind == kind }.reduce(Int64(0)) { $0 + $1.bytes }))
                        }
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    }
                    Divider()
                }
                if category == .trash {
                    Text("\(categoryItems.reduce(0) { $0 + $1.fileCount }) tệp trong thùng rác")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                ForEach(categoryItems) { item in
                    itemRow(item)
                }
            }
        }
        .macMateCard(padding: 10)
    }

    private func itemRow(_ item: CleanerItem) -> some View {
        HStack(spacing: 6) {
            if item.canDelete {
                Toggle(item.name, isOn: Binding(
                    get: { manager.selectedIDs.contains(item.id) },
                    set: { _ in manager.toggle(item) }
                ))
                .labelsHidden()
                .controlSize(.mini)
                .disabled(manager.isBusy || (item.bytes == 0 && item.category != .trash))
            } else {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(width: 13)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
                Text("\(item.kind) · \(item.safety.title) · \(item.fileCount) tệp")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Text(size(item.bytes))
                .font(.system(size: 9, weight: .semibold, design: .rounded))
        }
        .help(item.url.path)
    }

    private var appUninstallCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "app.badge")
                    .foregroundStyle(Color.accentColor)
                Text("Gỡ ứng dụng và dữ liệu")
                    .font(.system(size: 10.5, weight: .bold))
                Spacer()
                if uninstallManager.isBusy { ProgressView().controlSize(.mini) }
            }
            Text("Chọn ứng dụng để xem dữ liệu liên quan. Các mục sẽ được chuyển vào Thùng rác.")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)

            Menu(uninstallManager.selectedApplication?.name ?? "Chọn ứng dụng") {
                ForEach(uninstallManager.applications) { application in
                    Button(application.name) { uninstallManager.select(application) }
                }
            }
            .controlSize(.small)
            .disabled(uninstallManager.isBusy || uninstallManager.applications.isEmpty)

            if let application = uninstallManager.selectedApplication {
                Text("Mã ứng dụng: \(application.bundleID)")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                ForEach(uninstallManager.parts) { part in
                    HStack(spacing: 6) {
                        if part.isApplication {
                            Image(systemName: "app.fill")
                                .frame(width: 13)
                        } else {
                            Toggle(part.name, isOn: Binding(
                                get: { uninstallManager.selectedPaths.contains(part.id) },
                                set: { _ in uninstallManager.toggle(part) }
                            ))
                            .labelsHidden()
                            .controlSize(.mini)
                            .disabled(uninstallManager.isBusy)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(part.name)
                                .font(.system(size: 9, weight: .medium))
                            Text(part.url.path)
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Text(size(part.bytes))
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .help(part.url.path)
                    if part.requiresReview {
                        Text("Cần xem lại: đường dẫn này chỉ trùng tên ứng dụng.")
                            .font(.system(size: 8))
                            .foregroundStyle(.orange)
                    }
                }
                Button("Xem trước và gỡ cài đặt") { uninstallManager.confirm() }
                    .disabled(uninstallManager.isBusy || uninstallManager.parts.isEmpty)
                    .controlSize(.small)
            }

            if let message = uninstallManager.message {
                Text(message)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .macMateCard(padding: 10)
    }

    private var uninstallConfirmationSheet: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Xác nhận gỡ cài đặt")
                .font(.system(size: 13, weight: .bold))
            Text("Ứng dụng và dữ liệu đã chọn sẽ được chuyển vào Thùng rác. Dữ liệu AI Agent được bảo vệ, tài khoản trực tuyến, Chuỗi khoá và thư mục dùng chung không nằm trong danh sách này.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(uninstallManager.parts.filter { uninstallManager.selectedPaths.contains($0.id) }) { part in
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(part.name) · \(size(part.bytes))")
                                .font(.system(size: 9, weight: .semibold))
                            Text(part.url.path)
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .frame(maxHeight: 210)
            HStack {
                Button("Huỷ") { uninstallManager.showingConfirmation = false }
                Spacer()
                Button("Chuyển vào Thùng rác") {
                    uninstallManager.uninstall { manager.scan() }
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.small)
        }
        .padding(16)
        .frame(width: 360)
    }

    private var previewSheet: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Xem trước khi dọn dẹp")
                .font(.system(size: 13, weight: .bold))
            Text("Sẽ xoá \(manager.previewItems.count) mục, khoảng \(size(manager.previewItems.reduce(Int64(0)) { $0 + $1.bytes })). Hành động này không thể hoàn tác.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(manager.previewItems) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(item.name).fontWeight(.semibold)
                                Spacer()
                                Text(size(item.bytes))
                            }
                            Text("\(item.safety.title) · \(item.url.path)")
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        .font(.system(size: 9))
                    }
                }
            }
            .frame(maxHeight: 230)
            HStack {
                Button("Huỷ") { manager.showingPreview = false }
                Spacer()
                Button("Xác nhận dọn dẹp") { manager.cleanConfirmed() }
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.small)
        }
        .padding(16)
        .frame(width: 360)
    }

    private var statusText: String {
        switch manager.phase {
        case .idle: return "Sẵn sàng quét"
        case .scanning: return "Đang quét..."
        case .analyzing: return "Đang phân tích..."
        case .ready: return manager.items.isEmpty ? "Không có dữ liệu cần dọn" : "Đã quét xong"
        case .cleaning: return "Đang dọn dẹp..."
        case .finished: return "Đã dọn dẹp thành công"
        }
    }

    private func categoryStatus(_ items: [CleanerItem]) -> String {
        if items.isEmpty { return "Không có dữ liệu" }
        if items.contains(where: { $0.safety == .review }) { return "Nên xem lại" }
        if items.allSatisfy({ $0.safety == .protected }) { return "Được bảo vệ" }
        return "An toàn để dọn"
    }

    private func size(_ bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var index = 0
        while value >= 1024 && index < units.count - 1 {
            value /= 1024
            index += 1
        }
        return String(format: index == 0 ? "%.0f %@" : "%.1f %@", locale: Locale(identifier: "vi_VN"), value, units[index])
    }
}
