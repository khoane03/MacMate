import Foundation
import Combine

@MainActor
final class CleanerManager: ObservableObject {
    enum Phase {
        case idle, scanning, analyzing, ready, cleaning, finished
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var items: [CleanerItem] = []
    @Published private(set) var selectedIDs: Set<String> = []
    @Published private(set) var inaccessiblePaths = 0
    @Published private(set) var trashAccessDenied = false
    @Published private(set) var message: String?
    @Published private(set) var freedBytes: Int64 = 0
    @Published private(set) var previewItems: [CleanerItem] = []
    @Published var showingPreview = false

    var isBusy: Bool { phase == .scanning || phase == .analyzing || phase == .cleaning }
    var availableBytes: Int64 { items.filter(\.canDelete).reduce(0) { $0 + $1.bytes } }
    var selectedBytes: Int64 { items.filter { selectedIDs.contains($0.id) }.reduce(0) { $0 + $1.bytes } }
    var hasSelectedItems: Bool { items.contains { selectedIDs.contains($0.id) && $0.canDelete } }

    func scan() {
        guard !isBusy else { return }
        phase = .scanning
        message = nil
        showingPreview = false
        Task {
            let result = await Task.detached(priority: .utility) { CleanerScanner().scan() }.value
            phase = .analyzing
            // Keep all UI state changes on the main actor.
            items = result.items.sorted { $0.bytes > $1.bytes }
            inaccessiblePaths = result.inaccessiblePaths
            trashAccessDenied = result.trashAccessDenied
            selectedIDs = Set(items.filter { $0.safety == .safe && $0.bytes > 0 }.map(\.id))
            phase = .ready
        }
    }

    func toggle(_ item: CleanerItem) {
        guard item.canDelete && !isBusy else { return }
        if selectedIDs.contains(item.id) { selectedIDs.remove(item.id) }
        else { selectedIDs.insert(item.id) }
    }

    func preparePreview(trashOnly: Bool = false) {
        guard !isBusy else { return }
        let candidates = items.filter { item in
            item.canDelete && (item.bytes > 0 || item.category == .trash) &&
                (trashOnly ? item.category == .trash : selectedIDs.contains(item.id))
        }
        guard !candidates.isEmpty else { return }
        phase = .analyzing
        Task {
            let checked = await Task.detached(priority: .utility) { CleanerScanner().dryRun(candidates) }.value
            previewItems = checked
            phase = .ready
            showingPreview = !checked.isEmpty
            if checked.count != candidates.count { message = "Một số đường dẫn đã thay đổi và được loại khỏi danh sách." }
        }
    }

    func cleanConfirmed() {
        guard !isBusy, showingPreview, !previewItems.isEmpty else { return }
        let candidates = previewItems
        showingPreview = false
        phase = .cleaning
        Task {
            // Validate once more immediately before deletion.
            let outcome = await Task.detached(priority: .utility) {
                let scanner = CleanerScanner()
                return scanner.delete(scanner.dryRun(candidates))
            }.value
            freedBytes = outcome.bytes
            message = outcome.failures == 0 ? nil : "Không thể dọn \(outcome.failures) mục. Hãy kiểm tra quyền truy cập."
            phase = .finished
            // Refresh measured space after the operation, preserving its result message.
            let result = await Task.detached(priority: .utility) { CleanerScanner().scan() }.value
            items = result.items.sorted { $0.bytes > $1.bytes }
            inaccessiblePaths = result.inaccessiblePaths
            trashAccessDenied = result.trashAccessDenied
            selectedIDs = []
        }
    }
}
