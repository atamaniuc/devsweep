import Foundation
import Combine
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    /// One model per app: the main window and the Settings window must edit the
    /// same filters and presets, otherwise "save the current view" is a lie.
    static let shared = AppModel()

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
    /// Asc/desc by size or name; applies to the list and (its own instance) to
    /// the dry-run sheet. Sorting is pure and in-memory.
    @Published var sort = SortState()
    /// Clickable discipline chips. Empty means "all tags".
    @Published var selectedTags: Set<PlatformTag> = []

    let settings = SettingsStore.shared

    let logFileURL: URL

    init() {
        let stats = Disk.volumeStats()
        freeBytes = stats.free
        totalBytes = stats.total
        let logsDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs")
        try? FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        logFileURL = logsDirectory.appendingPathComponent("\(AppVersion.name).log")
        applyStartupPreset()
    }

    /// The default preset is the view the app starts in: tags, filters, sort and
    /// search are restored before the first scan, so the first paint is already
    /// filtered instead of flashing the full list.
    private func applyStartupPreset() {
        guard let preset = settings.startupPreset() else { return }
        applyPreset(preset)
    }

    func applyPreset(_ preset: SettingsPreset) {
        selectedTags = Set(preset.tags.compactMap(PlatformTag.init(rawValue:)))
        showAdvanced = preset.showAdvanced
        dryRun = preset.dryRun
        searchQuery = preset.searchQuery
        sort = SortState(key: SortKey(rawValue: preset.sortKey) ?? .size,
                         direction: SortDirection(rawValue: preset.sortDirection) ?? .descending)
    }

    /// The current view as a saveable preset — what "Save as preset" in Settings
    /// captures: chips, advanced/dry-run switches, sort and search.
    func currentPreset(named name: String) -> SettingsPreset {
        SettingsPreset(name: name,
                       tags: selectedTags.map(\.rawValue).sorted(),
                       showAdvanced: showAdvanced,
                       dryRun: dryRun,
                       sortKey: sort.key.rawValue,
                       sortDirection: sort.direction.rawValue,
                       searchQuery: searchQuery)
    }

    var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(totalBytes - freeBytes) / Double(totalBytes)
    }

    // MARK: - Visible list (search + tags + advanced switch + sort)

    var trimmedQuery: String { searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isFiltering: Bool { !SearchQuery.tokens(searchQuery).isEmpty }
    var hasActiveFilters: Bool { isFiltering || !selectedTags.isEmpty }

    /// Rows that pass the search box, the chip filter and the advanced-category
    /// switch, in the selected order. Pure in-memory work on the scan result:
    /// switching a chip or a sort key never touches the disk.
    var visibleItems: [CleanupItem] {
        let searched = SearchIndex.filter(items, query: searchQuery)
        let tagged = PlatformFilter.apply(searched, tags: selectedTags)
        let advanced = CleanupFilters.visible(tagged, query: "", showAdvanced: showAdvanced)
        return sort.items(advanced)
    }

    var visibleSafeItems: [CleanupItem] { CleanupFilters.safe(visibleItems) }
    var visibleAdvancedItems: [CleanupItem] { CleanupFilters.advanced(visibleItems) }

    var hasAdvancedItems: Bool { items.contains { $0.category.isAdvanced } }

    /// Rows bucketed by chip, in the order their first sorted row appears: with
    /// "size desc" the biggest group leads, with "name asc" the alphabetically
    /// first group does. Rows are already sorted, so this is one linear pass.
    struct ItemGroup: Identifiable {
        let tag: PlatformTag
        let items: [CleanupItem]
        var id: String { tag.rawValue }
        var bytes: Int64 { items.reduce(Int64(0)) { $0 + $1.sizeBytes } }
    }

    func groups(for rows: [CleanupItem]) -> [ItemGroup] {
        var order: [PlatformTag] = []
        var buckets: [PlatformTag: [CleanupItem]] = [:]
        for row in rows {
            let tag = row.platformTag
            if buckets[tag] == nil { order.append(tag) }
            buckets[tag, default: []].append(row)
        }
        return order.map { ItemGroup(tag: $0, items: buckets[$0] ?? []) }
    }

    /// "found here" numbers for the chips: rows and bytes per discipline.
    var tagStats: [PlatformTag: PlatformFilter.Stats] { PlatformFilter.stats(items) }

    func toggleTag(_ tag: PlatformTag) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
    }

    func clearTagFilter() { selectedTags.removeAll() }

    /// Notes stay visible while the list is unfiltered; a search narrows them to
    /// the note that explains why a matching cache produced no row ("Telegram is
    /// running"), which is exactly the answer the user was looking for.
    var visibleNotes: [ScanNote] {
        isFiltering ? SearchIndex.matchingNotes(notes, query: searchQuery) : notes
    }

    var matchingNotes: [ScanNote] { SearchIndex.matchingNotes(notes, query: trimmedQuery) }

    /// Catalog entries named by the current search that have no cache on this
    /// machine: explains "Terraform is supported, nothing to clean here".
    var catalogMatches: [ToolCacheSpec] {
        SearchIndex.matchingSpecs(trimmedQuery)
    }

    /// Scanner-managed caches named by the search (Telegram, WhatsApp, npm, uv,
    /// Docker…): they are supported, they just never had a catalog row of their
    /// own, which is why searching for them used to find nothing.
    var scannerMatches: [ScannerCaches.Entry] {
        SearchIndex.scannerMatches(trimmedQuery)
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
