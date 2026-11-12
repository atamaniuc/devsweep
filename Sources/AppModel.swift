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
    @Published var showAdvanced = false
    @Published var logExpanded = true
    @Published var lastReport: CleanReport?
    @Published var hasScanned = false
    @Published var dryRun = true
    @Published var preview: PreviewReport?
    @Published var isPreviewing = false

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

    var visibleItems: [CleanupItem] {
        showAdvanced ? items : items.filter { !$0.category.isAdvanced }
    }

    var safeItems: [CleanupItem] { items.filter { !$0.category.isAdvanced } }
    var advancedItems: [CleanupItem] { items.filter { $0.category.isAdvanced } }
    var hasAdvancedItems: Bool { !advancedItems.isEmpty }
    var selectedItems: [CleanupItem] { items.filter { $0.selected } }
    var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.sizeBytes } }
    var canClean: Bool { phase == .idle && !selectedItems.isEmpty }

    func binding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { self.items.first(where: { $0.id == id })?.selected ?? false },
            set: { newValue in
                if let index = self.items.firstIndex(where: { $0.id == id }) {
                    self.items[index].selected = newValue
                }
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
        appendLog(L("Очистка: \(chosen.count) объектов, \(humanBytes(selectedSize))", "Cleaning: \(chosen.count) items, \(humanBytes(selectedSize))"), level: .info)

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
        phase = .idle

        let freed = max(0, freeBytes - freeBefore)
        let removed = entries.filter { if case .success = $0.level { return true } else { return false } }.count
        let skipped = entries.filter { if case .warning = $0.level { return true } else { return false } }.count
        let failed = entries.filter { if case .error = $0.level { return true } else { return false } }.count
        lastReport = CleanReport(freedBytes: freed, removed: removed, skipped: skipped, failed: failed)
        appendLog(L("Освобождено \(humanBytes(freed)), ошибок: \(failed)", "Freed \(humanBytes(freed)), errors: \(failed)"), level: failed == 0 ? .success : .error)
        writeLogFile()
    }

    func selectAll() {
        for index in items.indices where !items[index].category.isAdvanced {
            items[index].selected = true
        }
    }

    func clearSelection() {
        for index in items.indices {
            items[index].selected = false
        }
    }

    private func appendLive(_ entry: CleanupLogEntry) {
        log.append(entry)
    }

    // MARK: - Dry run

    func buildPreview() async {
        let chosen = selectedItems
        guard !chosen.isEmpty, phase == .idle else { return }
        isPreviewing = true
        appendLog(L("Dry run: собираю список файлов…", "Dry run: collecting the file list…"), level: .info)
        let report = await Task.detached(priority: .userInitiated) {
            PreviewBuilder.build(items: chosen)
        }.value
        preview = report
        isPreviewing = false
        appendLog(L("Dry run: \(report.targetCount) объектов, \(report.fileCount) файлов, \(humanBytes(report.totalBytes)); ничего не удалено", "Dry run: \(report.targetCount) items, \(report.fileCount) files, \(humanBytes(report.totalBytes)); nothing was deleted"),
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
        for item in items {
            lines.append("item=\(item.category.rawValue) selected=\(item.selected) size=\(item.sizeBytes) title=\(item.title)")
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
