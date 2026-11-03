import Foundation
import AppKit
import Combine

struct UninstallApplication: Identifiable, Sendable {
    let name: String
    let bundleID: String
    let url: URL
    var id: String { url.path }
}

struct UninstallPart: Identifiable, Sendable {
    let url: URL
    let name: String
    let bytes: Int64
    let isApplication: Bool
    let requiresReview: Bool
    var id: String { url.path }
}

struct AppUninstallScanner: Sendable {
    private let home: URL
    private let applicationRoots: [URL]
    private let ownBundleID = "com.app.MacMate"

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
         applicationRoots: [URL]? = nil) {
        self.home = home.standardizedFileURL
        self.applicationRoots = (applicationRoots ?? [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")])
            .map(\.standardizedFileURL)
    }

    func applications() -> [UninstallApplication] {
        let fm = FileManager.default
        var result: [UninstallApplication] = []
        for root in applicationRoots {
            guard let entries = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey]) else { continue }
            for url in entries where url.pathExtension == "app" {
                guard !isSymbolicLink(url), let bundleID = bundleIdentifier(at: url),
                      validBundleID(bundleID), bundleID.lowercased() != ownBundleID.lowercased(),
                      !bundleID.lowercased().hasPrefix("com.apple.") else { continue }
                result.append(UninstallApplication(name: url.deletingPathExtension().lastPathComponent,
                                                   bundleID: bundleID, url: url.standardizedFileURL))
            }
        }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func preview(_ application: UninstallApplication) -> [UninstallPart] {
        guard validateApplication(application) else { return [] }
        var parts: [UninstallPart] = [UninstallPart(url: application.url, name: "Ứng dụng", bytes: measure(application.url), isApplication: true, requiresReview: false)]
        for (url, name, requiresReview) in dataLocations(for: application) {
            guard FileManager.default.fileExists(atPath: url.path), !isSymbolicLink(url),
                  isWithinHome(url) else { continue }
            parts.append(UninstallPart(url: url, name: name, bytes: measure(url), isApplication: false, requiresReview: requiresReview))
        }
        return parts
    }

    func dryRun(_ application: UninstallApplication, selectedPaths: Set<String>) -> [UninstallPart] {
        let current = preview(application)
        guard current.contains(where: { $0.isApplication && selectedPaths.contains($0.id) }) else { return [] }
        return current.filter { selectedPaths.contains($0.id) }
    }

    func moveToTrash(_ application: UninstallApplication, selectedPaths: Set<String>) -> (moved: Int, failures: Int) {
        let parts = dryRun(application, selectedPaths: selectedPaths)
        guard let appPart = parts.first(where: \.isApplication) else { return (0, selectedPaths.count) }
        let fm = FileManager.default
        do {
            try fm.trashItem(at: appPart.url, resultingItemURL: nil)
        } catch {
            return (0, parts.count)
        }
        var moved = 1
        var failures = max(0, selectedPaths.count - parts.count)
        for part in parts where !part.isApplication {
            // Revalidate each data path against this exact bundle ID immediately before moving it.
            guard dataLocations(for: application).contains(where: { $0.0 == part.url }),
                  isWithinHome(part.url), !isSymbolicLink(part.url) else {
                failures += 1; continue
            }
            do {
                try fm.trashItem(at: part.url, resultingItemURL: nil)
                moved += 1
            } catch {
                failures += 1
            }
        }
        return (moved, failures)
    }

    private func validateApplication(_ application: UninstallApplication) -> Bool {
        let url = application.url.standardizedFileURL
        guard !isSymbolicLink(url), url.pathExtension == "app",
              applicationRoots.contains(where: { url.deletingLastPathComponent() == $0 }),
              validBundleID(application.bundleID), application.bundleID.lowercased() != ownBundleID.lowercased(),
              !application.bundleID.lowercased().hasPrefix("com.apple.") else { return false }
        return bundleIdentifier(at: url) == application.bundleID
    }

    private func dataLocations(for application: UninstallApplication) -> [(URL, String, Bool)] {
        let bundleID = application.bundleID
        guard validBundleID(bundleID) else { return [] }
        let identity = (application.name + " " + bundleID).lowercased()
        if ["cursor", "claude", "codex", "visual studio code", "vscode", "continue", "aider",
            "chatgpt", "openai", "copilot", "windsurf", "antigravity"]
            .contains(where: identity.contains) {
            // Agent stores may contain credentials, sessions, and project context.
            return []
        }
        var paths: [(String, String, Bool)] = [
            ("Library/Application Support/\(bundleID)", "Dữ liệu hỗ trợ", false),
            ("Library/Containers/\(bundleID)", "Dữ liệu ứng dụng", false),
            ("Library/Caches/\(bundleID)", "Cache", false),
            ("Library/Caches/\(bundleID).ShipIt", "Cache cập nhật", false),
            ("Library/Preferences/\(bundleID).plist", "Tùy chọn", false),
            ("Library/Saved Application State/\(bundleID).savedState", "Trạng thái lưu", false),
            ("Library/HTTPStorages/\(bundleID)", "Dữ liệu mạng", false),
            ("Library/WebKit/\(bundleID)", "Dữ liệu trình duyệt", false),
            ("Library/Logs/\(bundleID)", "Nhật ký", false)
        ]
        // Product-name folders are ambiguous, so the user must opt in explicitly.
        if !application.name.isEmpty && application.name != "." && application.name != ".." {
            paths.append(("Library/Application Support/\(application.name)", "Dữ liệu theo tên ứng dụng", true))
        }
        return paths.map { (home.appendingPathComponent($0.0).standardizedFileURL, $0.1, $0.2) }
    }

    private func bundleIdentifier(at url: URL) -> String? {
        let infoURL = url.appendingPathComponent("Contents/Info.plist")
        guard !isSymbolicLink(infoURL),
              let data = try? Data(contentsOf: infoURL),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        return info["CFBundleIdentifier"] as? String
    }

    private func validBundleID(_ value: String) -> Bool {
        !value.isEmpty && !value.contains("..") &&
            value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }
    }

    private func isWithinHome(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(home.path + "/")
    }

    private func isSymbolicLink(_ url: URL) -> Bool {
        var current = url.standardizedFileURL
        let stops = Set(([home] + applicationRoots).map(\.path))
        while current.path != "/" {
            if (try? current.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true { return true }
            if stops.contains(current.path) { break }
            current.deleteLastPathComponent()
        }
        return false
    }

    private func measure(_ url: URL) -> Int64 {
        if let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), values.isRegularFile == true {
            return Int64(values.fileSize ?? 0)
        }
        var bytes: Int64 = 0
        if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]) {
            while let child = enumerator.nextObject() as? URL {
                guard let values = try? child.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]) else { continue }
                if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
                if values.isRegularFile == true { bytes += Int64(values.fileSize ?? 0) }
            }
        }
        return bytes
    }
}

@MainActor
final class AppUninstallManager: ObservableObject {
    @Published private(set) var applications: [UninstallApplication] = []
    @Published private(set) var selectedApplication: UninstallApplication?
    @Published private(set) var parts: [UninstallPart] = []
    @Published private(set) var selectedPaths: Set<String> = []
    @Published private(set) var isBusy = false
    @Published var showingConfirmation = false
    @Published private(set) var message: String?

    func scan() {
        guard !isBusy else { return }
        isBusy = true
        Task {
            applications = await Task.detached(priority: .utility) { AppUninstallScanner().applications() }.value
            isBusy = false
        }
    }

    func select(_ application: UninstallApplication) {
        guard !isBusy else { return }
        isBusy = true
        message = nil
        Task {
            let found = await Task.detached(priority: .utility) { AppUninstallScanner().preview(application) }.value
            selectedApplication = application
            parts = found
            selectedPaths = Set(found.filter { !$0.requiresReview }.map(\.id))
            isBusy = false
        }
    }

    func toggle(_ part: UninstallPart) {
        guard !part.isApplication && !isBusy else { return }
        if selectedPaths.contains(part.id) { selectedPaths.remove(part.id) }
        else { selectedPaths.insert(part.id) }
    }

    func confirm() {
        guard let application = selectedApplication, !isBusy,
              !NSRunningApplication.runningApplications(withBundleIdentifier: application.bundleID).contains(where: { !$0.isTerminated }) else {
            message = "Hãy thoát ứng dụng trước khi gỡ cài đặt."
            return
        }
        showingConfirmation = true
    }

    func uninstall(onComplete: @escaping @MainActor () -> Void) {
        guard let application = selectedApplication, showingConfirmation, !isBusy else { return }
        if NSRunningApplication.runningApplications(withBundleIdentifier: application.bundleID).contains(where: { !$0.isTerminated }) {
            showingConfirmation = false
            message = "Ứng dụng đang chạy. Hãy thoát ứng dụng trước khi gỡ cài đặt."
            return
        }
        showingConfirmation = false
        isBusy = true
        let selected = selectedPaths
        Task {
            let result = await Task.detached(priority: .utility) {
                AppUninstallScanner().moveToTrash(application, selectedPaths: selected)
            }.value
            message = result.moved == 0
                ? "Không thể chuyển ứng dụng vào Thùng rác. Hãy kiểm tra quyền truy cập."
                : (result.failures == 0
                    ? "Đã chuyển ứng dụng và dữ liệu đã chọn vào Thùng rác."
                    : "Đã gỡ ứng dụng, nhưng \(result.failures) mục dữ liệu chưa được chuyển.")
            selectedApplication = nil
            parts = []
            selectedPaths = []
            isBusy = false
            scan()
            onComplete()
        }
    }
}
