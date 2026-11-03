import Foundation

enum CleanerCategory: String, CaseIterable, Identifiable, Sendable {
    case system, developer, agent, trash

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "Rác hệ thống"
        case .developer: return "Dữ liệu lập trình"
        case .agent: return "Dữ liệu AI Agent"
        case .trash: return "Thùng rác"
        }
    }
    var icon: String {
        switch self {
        case .system: return "internaldrive"
        case .developer: return "hammer"
        case .agent: return "sparkles.rectangle.stack"
        case .trash: return "trash"
        }
    }
}

enum CleanerSafety: Sendable {
    case safe, review, protected

    var title: String {
        switch self {
        case .safe: return "An toàn để dọn"
        case .review: return "Nên xem lại"
        case .protected: return "Được bảo vệ"
        }
    }
}

struct CleanerItem: Identifiable, Sendable {
    let id: String
    let category: CleanerCategory
    let name: String
    let kind: String
    let url: URL
    let bytes: Int64
    let fileCount: Int
    let safety: CleanerSafety
    let isTrashChild: Bool

    var canDelete: Bool { safety != .protected }
}

struct CleanerScanResult: Sendable {
    let items: [CleanerItem]
    let inaccessiblePaths: Int
    let trashAccessDenied: Bool
}

struct CleanerScanner: Sendable {
    private struct Target {
        let path: String
        let category: CleanerCategory
        let name: String
        let kind: String
        let safety: CleanerSafety
    }

    private let home: URL

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home.standardizedFileURL
    }

    // Only explicit user-local data locations may enter the scan. Never scan projects or credentials.
    private var targets: [Target] {
        [
            Target(path: "Library/Caches", category: .system, name: "Cache ứng dụng", kind: "Cache", safety: .protected),
            Target(path: "Library/Logs", category: .system, name: "File log cũ", kind: "Log", safety: .review),
            Target(path: "Library/Logs/DiagnosticReports", category: .system, name: "Báo cáo sự cố", kind: "Báo cáo sự cố", safety: .review),
            Target(path: "Library/Caches/com.apple.Safari", category: .system, name: "Cache trình duyệt", kind: "Cache", safety: .review),
            Target(path: "Library/Caches/TemporaryItems", category: .system, name: "File tạm", kind: "Dữ liệu tạm", safety: .protected),
            Target(path: "Library/Developer/Xcode/DerivedData", category: .developer, name: "Xcode DerivedData", kind: "Build cache", safety: .safe),
            Target(path: "Library/Developer/Xcode/Archives", category: .developer, name: "Xcode Archives", kind: "Bản lưu trữ", safety: .review),
            Target(path: "Library/Developer/Xcode/iOS DeviceSupport", category: .developer, name: "DeviceSupport", kind: "Dữ liệu thiết bị", safety: .review),
            Target(path: "Library/Caches/org.swift.swiftpm", category: .developer, name: "SwiftPM cache", kind: "Cache", safety: .safe),
            Target(path: "Library/Caches/Homebrew", category: .developer, name: "Homebrew cache", kind: "Cache", safety: .safe),
            Target(path: ".npm/_cacache", category: .developer, name: "npm cache", kind: "Cache", safety: .safe),
            Target(path: "Library/pnpm/store", category: .developer, name: "pnpm cache", kind: "Cache", safety: .review),
            Target(path: "Library/Caches/Yarn", category: .developer, name: "yarn cache", kind: "Cache", safety: .safe),
            Target(path: "Library/Caches/com.microsoft.VSCode", category: .developer, name: "VS Code build cache", kind: "Cache", safety: .review),
            Target(path: "Library/Caches/com.todesktop.230313mzl4w4u92", category: .agent, name: "Cursor", kind: "Cache", safety: .review),
            Target(path: ".cursor/cache", category: .agent, name: "Cursor", kind: "Cache", safety: .review),
            Target(path: ".cursor/projects", category: .agent, name: "Cursor", kind: "Context", safety: .protected),
            Target(path: ".cursor/chats", category: .agent, name: "Cursor", kind: "History", safety: .protected),
            Target(path: ".claude/projects", category: .agent, name: "Claude Code", kind: "Session cũ", safety: .protected),
            Target(path: ".claude/debug", category: .agent, name: "Claude Code", kind: "Dữ liệu tạm", safety: .review),
            Target(path: ".claude/cache", category: .agent, name: "Claude Code", kind: "Cache", safety: .review),
            Target(path: ".codex/sessions", category: .agent, name: "Codex", kind: "Session cũ", safety: .protected),
            Target(path: ".codex/log", category: .agent, name: "Codex", kind: "Log", safety: .review),
            Target(path: ".codex/tmp", category: .agent, name: "Codex", kind: "Dữ liệu tạm", safety: .review),
            Target(path: "Library/Application Support/Code/User/workspaceStorage", category: .agent, name: "VS Code Agent", kind: "Context", safety: .protected),
            Target(path: "Library/Application Support/Code/CachedData", category: .agent, name: "VS Code Agent", kind: "Cache", safety: .review),
            Target(path: "Library/Application Support/Code/logs", category: .agent, name: "VS Code Agent", kind: "Log", safety: .review),
            Target(path: ".continue/cache", category: .agent, name: "Agent khác", kind: "Cache", safety: .review),
            Target(path: ".continue/sessions", category: .agent, name: "Agent khác", kind: "Session cũ", safety: .protected),
            Target(path: ".aider.chat.history.md", category: .agent, name: "Agent khác", kind: "History", safety: .protected)
        ]
    }

    func scan() -> CleanerScanResult {
        var items: [CleanerItem] = []
        var inaccessible = 0
        var trashAccessDenied = false
        let fm = FileManager.default
        for target in targets {
            let url = home.appendingPathComponent(target.path).standardizedFileURL
            guard isWithinHome(url), fm.fileExists(atPath: url.path) else { continue }
            if target.path == "Library/Caches" || target.path == "Library/Logs" || target.path == "Library/Logs/DiagnosticReports" {
                guard let children = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
                    inaccessible += 1; continue
                }
                for child in children where !targets.contains(where: { $0.path == target.path + "/" + child.lastPathComponent }) {
                    if target.path.hasPrefix("Library/Logs") && !isOldLog(child) { continue }
                    if let item = makeItem(url: child, category: target.category, name: child.lastPathComponent, kind: target.kind, safety: target.safety, trash: false) {
                        items.append(item)
                    }
                }
            } else if let item = makeItem(url: url, category: target.category, name: target.name, kind: target.kind, safety: target.safety, trash: false) {
                items.append(item)
            }
        }
        let trash = home.appendingPathComponent(".Trash")
        if let children = try? fm.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil) {
            for child in children {
                if let item = makeItem(url: child, category: .trash, name: child.lastPathComponent, kind: "Tệp trong thùng rác", safety: .review, trash: true) {
                    items.append(item)
                }
            }
        } else if fm.fileExists(atPath: trash.path) {
            inaccessible += 1
            trashAccessDenied = true
        }
        return CleanerScanResult(items: items, inaccessiblePaths: inaccessible, trashAccessDenied: trashAccessDenied)
    }

    func dryRun(_ items: [CleanerItem]) -> [CleanerItem] {
        items.compactMap { item in
            guard validate(item), FileManager.default.fileExists(atPath: item.url.path) else { return nil }
            return makeItem(url: item.url, category: item.category, name: item.name,
                            kind: item.kind, safety: item.safety, trash: item.isTrashChild)
        }
    }

    func delete(_ items: [CleanerItem]) -> (bytes: Int64, failures: Int) {
        var freed: Int64 = 0
        var failures = 0
        for item in items {
            guard validate(item), FileManager.default.fileExists(atPath: item.url.path) else {
                failures += 1; continue
            }
            do {
                try FileManager.default.removeItem(at: item.url)
                freed += item.bytes
            } catch {
                failures += 1
            }
        }
        return (freed, failures)
    }

    private func makeItem(url: URL, category: CleanerCategory, name: String, kind: String, safety: CleanerSafety, trash: Bool) -> CleanerItem? {
        let path = url.standardizedFileURL
        guard isWithinHome(path), !isSymbolicLink(path) else { return nil }
        let (bytes, count) = measure(path)
        return CleanerItem(id: path.path, category: category, name: name, kind: kind, url: path, bytes: bytes, fileCount: count, safety: safety, isTrashChild: trash)
    }

    private func measure(_ url: URL) -> (Int64, Int) {
        let fm = FileManager.default
        if let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), values.isRegularFile == true {
            return (Int64(values.fileSize ?? 0), 1)
        }
        var total: Int64 = 0
        var count = 0
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]) else {
            return (0, 0)
        }
        while let child = enumerator.nextObject() as? URL {
            guard let values = try? child.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]) else { continue }
            if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            if values.isRegularFile == true {
                total += Int64(values.fileSize ?? 0)
                count += 1
            }
        }
        return (total, count)
    }

    private func isOldLog(_ url: URL) -> Bool {
        let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        guard let rootDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
              rootDate < cutoff else { return false }
        if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.contentModificationDateKey, .isSymbolicLinkKey]) {
            while let child = enumerator.nextObject() as? URL {
                guard let values = try? child.resourceValues(forKeys: [.contentModificationDateKey, .isSymbolicLinkKey]),
                      values.isSymbolicLink != true,
                      let date = values.contentModificationDate, date < cutoff else { return false }
            }
        }
        return true
    }

    private func validate(_ item: CleanerItem) -> Bool {
        guard item.canDelete, isWithinHome(item.url), !isSymbolicLink(item.url) else { return false }
        let path = item.url.standardizedFileURL.path
        let trash = home.appendingPathComponent(".Trash").path + "/"
        if item.isTrashChild { return item.category == .trash && path.hasPrefix(trash) && !path.dropFirst(trash.count).contains("/") }
        guard item.category != .trash else { return false }
        if item.category == .system {
            let logs = home.appendingPathComponent("Library/Logs").path + "/"
            let reports = home.appendingPathComponent("Library/Logs/DiagnosticReports").path + "/"
            return (path.hasPrefix(logs) && !path.dropFirst(logs.count).contains("/") && isOldLog(item.url)) ||
                (path.hasPrefix(reports) && !path.dropFirst(reports.count).contains("/") && isOldLog(item.url)) ||
                targets.contains {
                    $0.category == .system && $0.safety != .protected &&
                    $0.path != "Library/Logs" && $0.path != "Library/Logs/DiagnosticReports" &&
                    home.appendingPathComponent($0.path).path == path
                }
        }
        return targets.contains { $0.category == item.category && $0.safety != .protected && home.appendingPathComponent($0.path).path == path }
    }

    private func isWithinHome(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return path.hasPrefix(home.path + "/") && !path.split(separator: "/").contains("..")
    }

    private func isSymbolicLink(_ url: URL) -> Bool {
        var current = url.standardizedFileURL
        while current.path != home.path && current.path != "/" {
            if (try? current.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true { return true }
            current.deleteLastPathComponent()
        }
        return false
    }
}
