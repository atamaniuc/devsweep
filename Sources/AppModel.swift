import Foundation
import Combine
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case scanning
        case cleaning
        case rescanning
    }

    @Published var items: [CleanupItem] = []
    @Published var notes: [ScanNote] = []
    @Published var phase: Phase = .idle
    @Published var log: [CleanupLogEntry] = []
    @Published var freeBytes: Int64 = 0
    @Published var totalBytes: Int64 = 0
    @Published var showAdvanced = UIDefaults.showAdvanced
    @Published var logExpanded = true
    @Published var lastReport: CleanReport?
    @Published var hasScanned = false
    @Published var dryRun = UIDefaults.dryRun
    @Published var preview: PreviewReport?
    @Published var isPreviewing = false
    /// O(1) selection arithmetic: the header's "can be freed" number is read
    /// from here, never recomputed by filtering the list.
    @Published private(set) var selection = SelectionLedger()
    @Published var searchQuery = ""

    let logFileURL: URL

    init() {
        let stats = Disk.volumeStats()
        freeBytes = stats.free
        totalBytes = stats.total
        let logsDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs")
        try? FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        logFileURL = logsDirectory.appendingPathComponent("\(AppVersion.name).log")
    }

    var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(totalBytes - freeBytes) / Double(totalBytes)
    }

    // MARK: - Visible list (search + advanced switch)

    var trimmedQuery: String { searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isFiltering: Bool { !SearchQuery.tokens(searchQuery).isEmpty }

    /// Rows that pass the search box and the advanced-category switch.
    var visibleItems: [CleanupItem] {
        CleanupFilters.visible(items, query: searchQuery, showAdvanced: showAdvanced)
    }

    var visibleSafeItems: [CleanupItem] { CleanupFilters.safe(visibleItems) }
    var visibleAdvancedItems: [CleanupItem] { CleanupFilters.advanced(visibleItems) }

    var hasAdvancedItems: Bool { items.contains { $0.category.isAdvanced } }

    /// Catalog entries named by the current search that have no cache on this
    /// machine: explains "Terraform is supported, nothing to clean here".
    var catalogMatches: [ToolCacheSpec] {
        SearchQuery.matchingSpecs(trimmedQuery)
    }
    var selectedItems: [CleanupItem] { selection.selectedItems(in: items) }
    /// "Can be freed right now" — follows the checkboxes, O(1).
    var selectedBytes: Int64 { selection.bytes }
    var selectedCount: Int { selection.count }
    var canClean: Bool { phase == .idle && !selection.isEmpty }

    func binding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { self.selection.isSelected(id) },
            set: { newValue in
                _ = self.selection.set(id, selected: newValue)
            }
        )
    }

    func scanIfNeeded() async {
        guard !hasScanned else { return }
        await scan()
    }

    func scan() async {
        guard phase != .scanning else { return }
        phase = .scanning
        appendLog(L("Сканирую кэши…", "Scanning caches…"), level: .info)
        let result = await Task.detached(priority: .userInitiated) { ScanEngine.run() }.value
        items = result.items
        notes = result.notes
        freeBytes = result.freeBytes
        totalBytes = result.totalBytes
        selection.load(result.items)
        phase = .idle
        hasScanned = true
        let total = result.items.reduce(Int64(0)) { $0 + $1.sizeBytes }
        appendLog(L("Найдено \(result.items.count) объектов на \(humanBytes(total))", "Found \(result.items.count) items, \(humanBytes(total))"), level: .info)
        for note in result.notes {
            appendLog("\(note.category.title): \(note.text)", level: .info)
        }
        writeLogFile()
    }

    func cleanSelected() async {
        let chosen = selectedItems
        guard !chosen.isEmpty, phase == .idle else { return }
        phase = .cleaning
        let freeBefore = freeBytes
        let plannedBytes = selectedBytes
        appendLog(L("Очистка: \(chosen.count) объектов, \(humanBytes(plannedBytes))", "Cleaning: \(chosen.count) items, \(humanBytes(plannedBytes))"), level: .info)

        let entries = await Task.detached(priority: .userInitiated) { [weak self] in
            Cleaner.perform(chosen) { entry in
                Task { @MainActor [weak self] in
                    self?.appendLive(entry)
                }
            }
        }.value

        phase = .rescanning
        let result = await Task.detached(priority: .userInitiated) { ScanEngine.run() }.value
        items = result.items
        notes = result.notes
        freeBytes = result.freeBytes
        totalBytes = result.totalBytes
        selection.load(result.items)
        phase = .idle

        let freed = max(0, freeBytes - freeBefore)
        let removed = entries.filter { if case .success = $0.level { return true } else { return false } }.count
        let skipped = entries.filter { if case .warning = $0.level { return true } else { return false } }.count
        let failed = entries.filter { if case .error = $0.level { return true } else { return false } }.count
        lastReport = CleanReport(freedBytes: freed, removed: removed, skipped: skipped, failed: failed)
        appendLog(L("Освобождено \(humanBytes(freed)), ошибок: \(failed)", "Freed \(humanBytes(freed)), errors: \(failed)"), level: failed == 0 ? .success : .error)
        writeLogFile()
    }

    /// "Check all" / "Uncheck all" act on what the user can see right now
    /// (search hits, advanced rows visible), not on hidden rows.
    func selectAllVisible() {
        guard phase == .idle else { return }
        selection.setAll(visibleItems, selected: true)
    }

    func clearAllVisible() {
        guard phase == .idle else { return }
        selection.setAll(visibleItems, selected: false)
    }

    var allVisibleSelected: Bool {
        let visible = visibleItems
        return !visible.isEmpty && visible.allSatisfy { selection.isSelected($0.id) }
    }

    private func appendLive(_ entry: CleanupLogEntry) {
        log.append(entry)
    }

    // MARK: - Dry run

    /// Opens the dry-run sheet immediately with the sizes known from the scan;
    /// file lists are counted per target only when a row is expanded. Walking
    /// 300k files before showing anything made the button feel broken.
    func buildPreview() async {
        let chosen = selectedItems
        guard !chosen.isEmpty, phase == .idle else { return }
        let report = PreviewBuilder.plan(items: chosen)
        preview = report
        appendLog(L("Dry run: \(report.targetCount) объектов на \(humanBytes(report.totalBytes)); список файлов считается при раскрытии строки, ничего не удалено",
                    "Dry run: \(report.targetCount) items, \(humanBytes(report.totalBytes)); file lists are counted when a row is expanded, nothing was deleted"),
                  level: .info)
        writeLogFile()
    }

    // MARK: - Log

    private func appendLog(_ text: String, level: LogLevel) {
        log.append(CleanupLogEntry(text, level: level))
    }

    private func writeLogFile() {
        let formatter = ISO8601DateFormatter()
        var lines: [String] = []
        lines.append("=== \(AppVersion.name) \(AppVersion.current) \(formatter.string(from: Date())) ===")
        lines.append("free=\(humanBytes(freeBytes)) total=\(humanBytes(totalBytes))")
        lines.append("selected=\(selectedCount) can_free=\(humanBytes(selectedBytes)) search=\(searchQuery)")
        for item in items {
            lines.append("item=\(item.category.rawValue) selected=\(selection.isSelected(item.id)) size=\(item.sizeBytes) title=\(item.title)")
        }
        for note in notes {
            lines.append("note=\(note.category.rawValue) \(note.text)")
        }
        for entry in log {
            lines.append("log \(entry.text)")
        }
        let text = lines.joined(separator: "\n") + "\n\n"
        if let handle = try? FileHandle(forWritingTo: logFileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(text.utf8))
        } else {
            try? Data(text.utf8).write(to: logFileURL, options: .atomic)
        }
    }
}
