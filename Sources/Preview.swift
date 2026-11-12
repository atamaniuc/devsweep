import Foundation

struct PreviewFile: Identifiable, Sendable {
    let id: UUID
    let path: String
    let sizeBytes: Int64
}

struct PreviewTarget: Identifiable, Sendable {
    let id: UUID
    let title: String
    let category: String
    let path: String?
    let command: String?
    let sizeBytes: Int64
    let fileCount: Int
    let files: [PreviewFile]
    let truncated: Bool
    /// The scan result behind this row, so the sheet can list files on demand
    /// instead of walking every selected cache before the sheet even opens.
    let item: CleanupItem?
}

/// Result of a dry run: the exact files and commands a real run would touch.
struct PreviewReport: Identifiable {
    let id = UUID()
    let targets: [PreviewTarget]
    let totalBytes: Int64
    let createdAt: Date

    var targetCount: Int { targets.count }
    var fileCount: Int { targets.reduce(0) { $0 + $1.fileCount } }

    var textReport: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var lines: [String] = []
        lines.append(L("\(AppVersion.name) \(AppVersion.current) — dry run: что будет удалено",
                       "\(AppVersion.name) \(AppVersion.current) — dry run: what will be deleted"))
        lines.append(L("Дата: \(formatter.string(from: createdAt))", "Date: \(formatter.string(from: createdAt))"))
        lines.append(L("Ничего не удалено: это только план.", "Nothing was deleted: this is a plan only."))
        lines.append(L("Объектов: \(targetCount), файлов: \(fileCount), размер: \(humanBytes(totalBytes))", "Items: \(targetCount), files: \(fileCount), size: \(humanBytes(totalBytes))"))
        lines.append("")

        for (index, target) in targets.enumerated() {
            lines.append("\(index + 1). [\(target.category)] \(target.title)")
            if let path = target.path { lines.append(L("   путь: \(path)", "   path: \(path)")) }
            if let command = target.command {
                lines.append(L("   команда: \(command)", "   command: \(command)"))
                lines.append(L("   примечание: точный список определяет сам инструмент; dry-run для него недоступен", "   note: the tool itself decides the exact list; no dry run is available for it"))
            }
            lines.append(L("   размер: \(humanBytes(target.sizeBytes)), файлов: \(target.fileCount)", "   size: \(humanBytes(target.sizeBytes)), files: \(target.fileCount)"))
            if target.truncated {
                lines.append(L("   показаны первые \(target.files.count) файлов, полный список обрезан", "   first \(target.files.count) files shown, the full list is truncated"))
            }
            for file in target.files {
                lines.append("   \(humanBytes(file.sizeBytes))\t\(file.path)")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}

enum PreviewBuilder {
    /// The plan the sheet shows immediately: sizes and paths already known from
    /// the scan, no tree walk at all. File lists are produced per target when a
    /// row is expanded (`scanFiles(for:)`), so "Show plan" is instant even for a
    /// 300k-file selection.
    static func plan(items: [CleanupItem]) -> PreviewReport {
        let targets = items.map { item -> PreviewTarget in
            let command = item.action.commandID.map { Cleaner.commandLine($0) ?? $0 }
            let path = item.previewPath?.path
            return PreviewTarget(id: UUID(),
                                 title: item.title,
                                 category: item.category.title,
                                 path: path ?? (command == nil ? item.detail : nil),
                                 command: command,
                                 sizeBytes: item.sizeBytes,
                                 fileCount: 0,
                                 files: [],
                                 truncated: false,
                                 item: item)
        }
        return PreviewReport(targets: targets,
                             totalBytes: targets.reduce(Int64(0)) { $0 + $1.sizeBytes },
                             createdAt: Date())
    }

    /// Walk one target on demand (called when the user expands its row).
    /// Runs the same C walker as the full report, so the counts match.
    static func scanFiles(for target: PreviewTarget) -> (files: [PreviewFile], count: Int, size: Int64) {
        guard target.command == nil else { return ([], 0, 0) }
        guard let path = target.path else { return ([], 0, 0) }
        return scanDirectory(URL(fileURLWithPath: path))
    }

    /// Caps memory for enormous caches; the text report says when a list is cut.
    static let maxFilesPerTarget = 200_000

    static func build(items: [CleanupItem]) -> PreviewReport {
        // Each target is an independent tree walk; walking them in parallel
        // keeps the dry-run sheet responsive for ~400k files.
        var results = [PreviewTarget?](repeating: nil, count: items.count)
        let lock = NSLock()
        let group = DispatchGroup()

        for (index, item) in items.enumerated() {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                let target = buildTarget(item)
                lock.lock()
                results[index] = target
                lock.unlock()
                group.leave()
            }
        }
        group.wait()

        let targets = results.compactMap { $0 }
        let total = targets.reduce(Int64(0)) { $0 + $1.sizeBytes }
        return PreviewReport(targets: targets, totalBytes: total, createdAt: Date())
    }

    private static func buildTarget(_ item: CleanupItem) -> PreviewTarget {
        switch item.action {
        case .remove(let url):
            let scan = scanDirectory(url)
            return PreviewTarget(
                id: UUID(),
                title: item.title,
                category: item.category.title,
                path: url.path,
                command: nil,
                sizeBytes: scan.size,
                fileCount: scan.count,
                files: scan.files,
                truncated: scan.count > scan.files.count,
                item: item
            )
        case .command(let id):
            let command = Cleaner.commandLine(id) ?? id
            var files: [PreviewFile] = []
            var count = 0
            var size: Int64 = 0
            if let path = item.previewPath, Disk.exists(path) {
                let scan = scanDirectory(path)
                files = scan.files
                count = scan.count
                size = scan.size
            }
            if size == 0 { size = item.sizeBytes }
            return PreviewTarget(
                id: UUID(),
                title: item.title,
                category: item.category.title,
                path: item.previewPath?.path,
                command: command,
                sizeBytes: size,
                fileCount: count,
                files: files,
                truncated: count > files.count,
                item: item
            )
        }
    }

    private static func scanDirectory(_ url: URL) -> (files: [PreviewFile], count: Int, size: Int64) {
        // Fast path: the C walker (Sources/fastwalk.c).
        let tempPath = NSTemporaryDirectory() + "cleandisk-walk-\(UUID().uuidString).txt"
        var total: Int64 = 0
        let found = cd_scan(url.path, tempPath, &total, maxFilesPerTarget)
        if found >= 0 {
            let content = (try? String(contentsOfFile: tempPath, encoding: .utf8)) ?? ""
            try? FileManager.default.removeItem(atPath: tempPath)
            var files: [PreviewFile] = []
            files.reserveCapacity(min(Int(found), maxFilesPerTarget))
            content.enumerateLines { line, _ in
                guard let tab = line.firstIndex(of: "\t") else { return }
                let size = Int64(line[line.startIndex..<tab]) ?? 0
                let path = String(line[line.index(after: tab)...])
                files.append(PreviewFile(id: UUID(), path: path, sizeBytes: size))
            }
            return (files, Int(found), total)
        }
        try? FileManager.default.removeItem(atPath: tempPath)
        return scanDirectorySwift(url)
    }

    private static func scanDirectorySwift(_ url: URL) -> (files: [PreviewFile], count: Int, size: Int64) {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey,
                                      .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: url,
                                                              includingPropertiesForKeys: keys,
                                                              options: [],
                                                              errorHandler: nil) else {
            return ([], 0, 0)
        }
        var files: [PreviewFile] = []
        var count = 0
        var size: Int64 = 0
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isSymbolicLink == true { continue }
            guard values.isRegularFile == true else { continue }
            let bytes = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            count += 1
            size += bytes
            if files.count < maxFilesPerTarget {
                files.append(PreviewFile(id: UUID(), path: file.path, sizeBytes: bytes))
            }
        }
        return (files, count, size)
    }
}
