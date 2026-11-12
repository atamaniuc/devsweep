import Foundation

enum LogLevel: Sendable {
    case info
    case success
    case warning
    case error
}

struct CleanupLogEntry: Identifiable, Sendable {
    let id: UUID
    let text: String
    let level: LogLevel

    init(_ text: String, level: LogLevel = .info) {
        self.id = UUID()
        self.text = text
        self.level = level
    }
}

enum Cleaner {
    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    /// Telegram keeps its media cache per account inside this group container.
    static var telegramStable: URL {
        home.appendingPathComponent("Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram/stable")
    }

    static func allowedBases() -> [URL] {
        var bases: [URL] = [
            home.appendingPathComponent("Library/Caches/JetBrains"),
            home.appendingPathComponent(".npm/_cacache"),
            home.appendingPathComponent(".cache/puppeteer"),
            home.appendingPathComponent(".cache/nvim/jdtls"),
            home.appendingPathComponent(".cache/selenium"),
            home.appendingPathComponent(".cache/uv"),
            home.appendingPathComponent(".bun/install/cache"),
            home.appendingPathComponent("Library/Caches/Homebrew"),
            home.appendingPathComponent("Library/Caches/ru.keepcoder.Telegram"),
            home.appendingPathComponent("Library/Containers/ru.keepcoder.Telegram.TelegramShare/Data/Library/Caches"),
            home.appendingPathComponent("Library/Containers/net.whatsapp.WhatsApp/Data/Library/Caches"),
        ]

        let manager = FileManager.default
        if let accounts = try? manager.contentsOfDirectory(at: telegramStable, includingPropertiesForKeys: nil) {
            for account in accounts where account.lastPathComponent.hasPrefix("account-") {
                bases.append(account.appendingPathComponent("postbox/media"))
            }
            bases.append(telegramStable.appendingPathComponent("accounts-metadata/media"))
        }
        return bases
    }

    /// The single gate every deletion passes through. Kept deliberately strict:
    /// one wrong path here would delete user data.
    static func isAllowed(_ url: URL) -> Bool {
        let raw = url.path
        guard raw.hasPrefix("/") else { return false }
        guard !raw.contains("/../"), !raw.hasSuffix("/.."), !raw.contains("/./") else { return false }

        let protected: Set<String> = ["/", "/private", "/private/tmp", "/tmp",
                                      home.path, home.appendingPathComponent("Library").path,
                                      home.appendingPathComponent("Library/Caches").path,
                                      home.appendingPathComponent(".cache").path]
        if protected.contains(raw) { return false }

        if raw.contains("/node_modules") || raw.contains("/.git/") || raw.hasSuffix("/.git") {
            return false
        }

        if let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]),
           values.isSymbolicLink == true {
            return false
        }

        // /private/tmp may standardize to /tmp, so match on the raw path.
        if raw.hasPrefix("/private/tmp/") {
            let rel = String(raw.dropFirst("/private/tmp/".count))
            if !rel.contains("/"), rel.hasPrefix("claude-") || rel.hasPrefix("dsh-") || rel.hasPrefix("tmp") {
                return true
            }
        }

        for base in allowedBases() {
            let basePath = base.path
            if raw == basePath || raw.hasPrefix(basePath + "/") {
                return true
            }
        }
        return false
    }

    static func perform(_ items: [CleanupItem], onEntry: ((CleanupLogEntry) -> Void)? = nil) -> [CleanupLogEntry] {
        var entries: [CleanupLogEntry] = []

        func emit(_ entry: CleanupLogEntry) {
            entries.append(entry)
            onEntry?(entry)
        }

        for item in items {
            switch item.action {
            case .remove(let url):
                emit(CleanupLogEntry(L("Удаляю: \(url.path) (\(humanBytes(item.sizeBytes)))",
                                       "Removing: \(url.path) (\(humanBytes(item.sizeBytes)))"),
                                     level: .info))
                for entry in remove(url) { emit(entry) }
            case .command(let id):
                let command = commandLine(id) ?? id
                emit(CleanupLogEntry(L("Выполняю: \(command)", "Running: \(command)"), level: .info))
                for entry in runCommand(id) { emit(entry) }
            }
        }
        return entries
    }

    static func remove(_ url: URL) -> [CleanupLogEntry] {
        guard isAllowed(url) else {
            return [CleanupLogEntry(L("ОТКАЗ: \(url.path) вне белого списка",
                                       "REFUSED: \(url.path) is outside the allowlist"), level: .error)]
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            return [CleanupLogEntry(L("Пропущено (уже нет): \(url.path)",
                                       "Skipped (already gone): \(url.path)"), level: .info)]
        }

        // The C walker is the fast path: FileManager.removeItem spends minutes
        // on a cache with hundreds of thousands of files.
        if cd_rmtree(url.path) == 0 {
            return [CleanupLogEntry(L("Удалено: \(url.path)", "Removed: \(url.path)"), level: .success)]
        }

        do {
            try FileManager.default.removeItem(at: url)
            return [CleanupLogEntry(L("Удалено: \(url.path)", "Removed: \(url.path)"), level: .success)]
        } catch {
            return [CleanupLogEntry(L("Не удалось удалить \(url.path): \(error.localizedDescription)",
                                       "Could not remove \(url.path): \(error.localizedDescription)"), level: .error)]
        }
    }

    /// Fixed command per id. Nothing else can be executed: previews and the
    /// cleaner share this table. Nothing else can be executed: previews and the
    /// cleaner share this table.
    static func commandLine(_ id: String) -> String? {
        switch id {
        case "npm-cache-clean": return "npm cache clean --force"
        case "pnpm-store-prune": return "pnpm store prune"
        case "bun-cache-clean": return "bun pm cache rm"
        case "uv-cache-clean": return "uv cache clean"
        case "brew-cleanup": return "brew cleanup -s --prune=all"
        case "macports-clean": return "port -q clean --all installed"
        case "docker-builder-prune": return "docker builder prune -f --filter until=24h"
        case "docker-image-prune": return "docker image prune -f"
        case "simctl-delete-unavailable": return "xcrun simctl delete unavailable"
        default: return nil
        }
    }

    static func needsAdministrator(_ id: String) -> Bool {
        id == "macports-clean"
    }

    /// Every command has a hard deadline: `uv cache clean` used to block for
    /// 300 s waiting on a lock held by `uv run ...`, which looked like a hang.
    static func timeout(for id: String) -> TimeInterval {
        switch id {
        case "uv-cache-clean": return 25
        case "pnpm-store-prune": return 120
        case "npm-cache-clean": return 180
        case "bun-cache-clean": return 240
        case "brew-cleanup": return 240
        case "docker-builder-prune": return 420
        case "docker-image-prune": return 120
        case "macports-clean": return 900
        case "simctl-delete-unavailable": return 180
        default: return 120
        }
    }

    private static func runCommand(_ id: String) -> [CleanupLogEntry] {
        guard let command = commandLine(id) else {
            return [CleanupLogEntry(L("Внутренняя ошибка: неизвестная команда \(id)",
                                       "Internal error: unknown command \(id)"), level: .error)]
        }

        var entries: [CleanupLogEntry] = []
        let limit = timeout(for: id)

        func execute(_ commandToRun: String) -> ShellResult {
            if needsAdministrator(id) {
                let script = "do shell script \"\(commandToRun)\" with administrator privileges"
                return Shell.run("/usr/bin/osascript", ["-e", script], timeout: limit)
            }
            return Shell.login(commandToRun, timeout: limit)
        }

        // uv takes its own cache lock; fail in 10 s instead of its default 300 s.
        let actual = id == "uv-cache-clean" ? "UV_LOCK_TIMEOUT=10 uv cache clean" : command
        var result = execute(actual)

        if result.status != 0, id == "pnpm-store-prune" {
            entries.append(CleanupLogEntry(L("pnpm store занят, повторяю через 2 с…",
                                             "pnpm store is busy, retrying in 2 s…"), level: .info))
            Thread.sleep(forTimeInterval: 2)
            result = execute(actual)
        }

        if result.status == 0 {
            for line in tailLines(result.output, count: 3) {
                entries.append(CleanupLogEntry("  \(line)", level: .info))
            }
            entries.append(CleanupLogEntry(L("Готово: \(command)", "Done: \(command)"), level: .success))
            return entries
        }

        if result.status == -2 {
            entries.append(CleanupLogEntry(L("Команда прервана по таймауту \(Int(limit)) с: \(command)",
                                             "Command stopped after \(Int(limit)) s timeout: \(command)"),
                                           level: .error))
        } else if id == "uv-cache-clean" && (result.output.lowercased().contains("lock") ||
                                             result.output.lowercased().contains("in-use")) {
            entries.append(CleanupLogEntry(L("uv-кэш занят другим uv-процессом (например `uv run ...`) — пропущено, повторите позже",
                                             "uv cache is locked by another uv process (e.g. `uv run ...`) — skipped, retry later"),
                                           level: .warning))
        } else {
            entries.append(CleanupLogEntry(L("Команда не выполнена (код \(result.status)): \(command)",
                                             "Command failed (code \(result.status)): \(command)"),
                                           level: .error))
            for line in tailLines(result.output, count: 3) {
                entries.append(CleanupLogEntry("  \(line)", level: .info))
            }
        }

        if id == "npm-cache-clean" {
            entries.append(contentsOf: remove(home.appendingPathComponent(".npm/_cacache")))
        }
        if id == "bun-cache-clean" {
            entries.append(contentsOf: remove(home.appendingPathComponent(".bun/install/cache")))
        }
        return entries
    }

    private static func tailLines(_ text: String, count: Int) -> [String] {
        let lines = text.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        return Array(lines.suffix(count))
    }
}
