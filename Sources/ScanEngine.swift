import Foundation

struct ShellResult: Sendable {
    let status: Int32
    let stdout: String
    let stderr: String

    var output: String {
        let trimmedOut = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedErr = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedOut.isEmpty { return trimmedErr }
        if trimmedErr.isEmpty { return trimmedOut }
        return trimmedOut + "\n" + trimmedErr
    }
}

enum Shell {
    /// Runs a fixed command through the user's login shell so that PATH entries
    /// from .zprofile/.zshrc (fnm, /usr/local/bin, ~/.local/bin) are visible to
    /// a GUI app, which otherwise only sees /usr/bin:/bin:/usr/sbin:/sbin.
    static func login(_ command: String) -> ShellResult {
        run("/bin/zsh", ["-lc", command])
    }

    static func run(_ executable: String, _ arguments: [String]) -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            return ShellResult(status: -1, stdout: "", stderr: error.localizedDescription)
        }
        process.waitUntilExit()
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        return ShellResult(status: process.terminationStatus,
                           stdout: String(data: outData, encoding: .utf8) ?? "",
                           stderr: String(data: errData, encoding: .utf8) ?? "")
    }
}

enum Disk {
    static func volumeStats() -> (free: Int64, total: Int64) {
        let manager = FileManager.default
        let path = manager.fileExists(atPath: "/System/Volumes/Data") ? "/System/Volumes/Data" : "/"
        guard let attributes = try? manager.attributesOfFileSystem(forPath: path),
              let free = attributes[.systemFreeSize] as? NSNumber,
              let total = attributes[.systemSize] as? NSNumber else {
            return (0, 0)
        }
        return (free.int64Value, total.int64Value)
    }

    static func directorySize(_ url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey,
                                      .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: url,
                                                              includingPropertiesForKeys: keys,
                                                              options: [],
                                                              errorHandler: nil) else {
            return 0
        }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isSymbolicLink == true { continue }
            guard values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }

    static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// Fast size of a directory tree (du -sk); the Swift enumerator is kept in
    /// PreviewBuilder where the file list itself is needed.
    static func sizeOnDisk(_ url: URL) -> Int64 {
        let result = Shell.run("/usr/bin/du", ["-sk", url.path])
        guard result.status == 0 else { return 0 }
        let first = result.stdout.split(separator: "\t").first
            ?? result.stdout.split(separator: " ").first
            ?? ""
        let kib = Int64(first.trimmingCharacters(in: .whitespaces)) ?? 0
        return kib * 1024
    }
}

enum SizeParser {
    /// Parses Docker's "8.06GB (40%)" style strings into bytes.
    static func dockerSize(_ raw: String) -> Int64 {
        let token = raw.split(separator: " ").first.map(String.init) ?? raw
        let upper = token.uppercased()
        let suffixes: [(String, Double)] = [("GB", 1_000_000_000), ("MB", 1_000_000),
                                            ("KB", 1_000), ("B", 1)]
        for (suffix, multiplier) in suffixes where upper.hasSuffix(suffix) {
            let numberPart = String(upper.dropLast(suffix.count))
            if let value = Double(numberPart) {
                return Int64(value * multiplier)
            }
        }
        return 0
    }
}

enum ScanEngine {
    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    static func commandExists(_ name: String) -> Bool {
        Shell.login("command -v \(name)").status == 0
    }

    static func processRunning(_ pattern: String) -> Bool {
        Shell.run("/usr/bin/pgrep", ["-f", pattern]).status == 0
    }

    static func run() -> ScanResult {
        let scanners: [() -> ([CleanupItem], [ScanNote])] = [
            scanJetBrains, scanNpm, scanPnpm, scanBun, scanDocker,
            scanBrew, scanMacports, scanCaches, scanTelegram, scanWhatsapp,
            scanTmp, scanSimulators,
        ]

        // The scans are independent (separate du/shell calls), so run them in
        // parallel: sequential scanning took ~18 s, the wall clock here is the
        // slowest single scanner.
        let lock = NSLock()
        var items: [CleanupItem] = []
        var notes: [ScanNote] = []
        let group = DispatchGroup()
        for scanner in scanners {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                let (newItems, newNotes) = scanner()
                lock.lock()
                items.append(contentsOf: newItems)
                notes.append(contentsOf: newNotes)
                lock.unlock()
                group.leave()
            }
        }
        group.wait()

        let order = Dictionary(uniqueKeysWithValues: CleanupCategory.allCases.enumerated().map { ($1.rawValue, $0) })
        items.sort { lhs, rhs in
            let left = order[lhs.category.rawValue] ?? 0
            let right = order[rhs.category.rawValue] ?? 0
            if left != right { return left < right }
            return lhs.title < rhs.title
        }
        notes.sort { lhs, rhs in
            let left = order[lhs.category.rawValue] ?? 0
            let right = order[rhs.category.rawValue] ?? 0
            if left != right { return left < right }
            return lhs.text < rhs.text
        }

        let stats = Disk.volumeStats()
        return ScanResult(items: items, notes: notes,
                          freeBytes: stats.free, totalBytes: stats.total)
    }

    // MARK: - JetBrains

    static func installedIntelliJVersions() -> [String] {
        var versions: [String] = []
        let folders = ["/Applications", home.appendingPathComponent("Applications").path]
        for folder in folders {
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: folder) else { continue }
            for name in entries where name.hasPrefix("IntelliJ IDEA") && name.hasSuffix(".app") {
                let path = folder + "/" + name
                if let bundle = Bundle(path: path),
                   let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String {
                    versions.append(version)
                }
            }
        }
        return versions
    }

    static func isIntelliJRunning() -> Bool {
        Shell.run("/usr/bin/pgrep", ["-f", "IntelliJ IDEA.app"]).status == 0
    }

    static func scanJetBrains() -> ([CleanupItem], [ScanNote]) {
        let cacheRoot = home.appendingPathComponent("Library/Caches/JetBrains")
        guard Disk.exists(cacheRoot) else { return ([], []) }

        if isIntelliJRunning() {
            return ([], [ScanNote(category: .jetbrains,
                                  text: L("IntelliJ IDEA запущена — кэш не трогаю", "IntelliJ IDEA is running — leaving the cache alone"))])
        }

        let entries = (try? FileManager.default.contentsOfDirectory(at: cacheRoot,
                                                                   includingPropertiesForKeys: nil)) ?? []
        let caches = entries.filter { $0.lastPathComponent.hasPrefix("IntelliJIdea") }
        guard !caches.isEmpty else { return ([], []) }

        func version(of url: URL) -> String {
            String(url.lastPathComponent.dropFirst("IntelliJIdea".count))
        }

        let installed = installedIntelliJVersions()
        var candidates: [URL] = []
        var notes: [ScanNote] = []

        if installed.isEmpty {
            let newest = caches.map(version).max(by: versionLess) ?? ""
            candidates = caches.filter { version(of: $0) != newest }
        } else {
            candidates = caches.filter { !installed.contains(version(of: $0)) }
            notes.append(ScanNote(category: .jetbrains,
                                  text: L("Установлена версия \(installed.joined(separator: ", ")) — её кэш остаётся", "Installed version: \(installed.joined(separator: ", ")) — its cache stays")))
        }

        let items = candidates.map { url -> CleanupItem in
            let ver = version(of: url)
            return CleanupItem(category: .jetbrains,
                               title: L("Кэш IntelliJ IDEA \(ver)", "IntelliJ IDEA \(ver) cache"),
                               detail: L("версия \(ver) не установлена • \(url.path)", "version \(ver) is not installed • \(url.path)"),
                               sizeBytes: Disk.sizeOnDisk(url),
                               action: .remove(url))
        }
        return (items, notes)
    }

    static func versionLess(_ lhs: String, _ rhs: String) -> Bool {
        let left = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let right = rhs.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(left.count, right.count)
        for index in 0..<count {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a < b }
        }
        return lhs < rhs
    }

    // MARK: - npm

    static func scanNpm() -> ([CleanupItem], [ScanNote]) {
        let cache = home.appendingPathComponent(".npm/_cacache")
        guard Disk.exists(cache) else { return ([], []) }
        let item = CleanupItem(category: .npm,
                               title: L("Кэш npm (_cacache)", "npm cache (_cacache)"),
                               detail: cache.path,
                               sizeBytes: Disk.sizeOnDisk(cache),
                               action: .command("npm-cache-clean"),
                               previewPath: cache)
        return ([item], [])
    }

    static func scanPnpm() -> ([CleanupItem], [ScanNote]) {
        guard commandExists("pnpm") else {
            return ([], [ScanNote(category: .pnpm, text: L("pnpm не установлен", "pnpm is not installed"))])
        }
        // `pnpm store path` depends on which pnpm binary the PATH resolves to
        // and can name a version that no longer exists (v10 vs v11), so fall
        // back to the store directories that are actually on disk.
        var candidates: [URL] = []
        let result = Shell.login("pnpm store path")
        let storePath = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.status == 0, !storePath.isEmpty {
            candidates.append(URL(fileURLWithPath: storePath))
        }
        let manager = FileManager.default
        for root in [home.appendingPathComponent("Library/pnpm/store"),
                     home.appendingPathComponent(".local/share/pnpm/store")] {
            if let versions = try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
                candidates.append(contentsOf: versions.sorted { versionLess($0.lastPathComponent, $1.lastPathComponent) })
            }
        }
        guard let store = candidates.first(where: { Disk.exists($0) }) else {
            return ([], [ScanNote(category: .pnpm, text: L("store не найден на диске", "store not found on disk"))])
        }
        let item = CleanupItem(category: .pnpm,
                               title: L("pnpm store без ссылок", "pnpm store without references"),
                               detail: "pnpm store prune • \(store.path)",
                               sizeBytes: Disk.sizeOnDisk(store),
                               action: .command("pnpm-store-prune"),
                               previewPath: store)
        return ([item], [])
    }

    static func scanBun() -> ([CleanupItem], [ScanNote]) {
        let cache = home.appendingPathComponent(".bun/install/cache")
        guard Disk.exists(cache) else {
            return ([], [ScanNote(category: .bun, text: L("кэш bun не найден", "bun cache not found"))])
        }
        let size = Disk.sizeOnDisk(cache)
        let hasBun = commandExists("bun")
        let action: CleanupAction = hasBun ? .command("bun-cache-clean") : .remove(cache)
        let detail = hasBun ? "bun pm cache rm • \(cache.path)" : cache.path
        let item = CleanupItem(category: .bun,
                               title: L("Кэш пакетов bun", "bun package cache"),
                               detail: detail,
                               sizeBytes: size,
                               action: action,
                               previewPath: cache)
        return ([item], [])
    }

    // MARK: - Docker

    static func scanDocker() -> ([CleanupItem], [ScanNote]) {
        let info = Shell.login("docker info --format '{{.ServerVersion}}'")
        guard info.status == 0 else {
            return ([], [ScanNote(category: .docker,
                                  text: L("Docker Desktop не запущен — Docker-очистка пропущена", "Docker Desktop is not running — Docker cleanup skipped"))])
        }

        var builderBytes: Int64 = 0
        var builderText = ""
        let df = Shell.login("docker system df --format '{{.Type}}|{{.Size}}|{{.Reclaimable}}'")
        if df.status == 0 {
            for line in df.stdout.split(separator: "\n") {
                let parts = line.split(separator: "|").map(String.init)
                guard parts.count == 3, parts[0] == "Build Cache" else { continue }
                builderText = parts[2]
                builderBytes = SizeParser.dockerSize(parts[2])
            }
        }

        let builder = CleanupItem(category: .docker,
                                  title: L("Build cache старше 24 часов", "Build cache older than 24 hours"),
                                  detail: "docker builder prune --filter until=24h"
                                          + (builderText.isEmpty ? "" : L(" • можно освободить \(builderText)", " • reclaimable: \(builderText)")),
                                  sizeBytes: builderBytes,
                                  action: .command("docker-builder-prune"))

        let dangling = CleanupItem(category: .docker,
                                   title: L("Dangling-образы без тегов", "Dangling untagged images"),
                                   detail: L("docker image prune -f (без -a, без томов и контейнеров)", "docker image prune -f (no -a, no volumes, no containers)"),
                                   sizeBytes: 0,
                                   action: .command("docker-image-prune"),
                                   warning: L("Образы, используемые контейнерами, не удаляются", "Images used by containers are never deleted"))

        var notes: [ScanNote] = []
        notes.append(ScanNote(category: .docker,
                              text: L("Docker не удаляет build cache сразу на диске Mac: место вернётся, когда Docker сожмёт образ", "Docker does not shrink its image file immediately: the space returns when Docker compacts it")))
        return ([builder, dangling], notes)
    }

    // MARK: - Homebrew / MacPorts

    static func scanBrew() -> ([CleanupItem], [ScanNote]) {
        guard commandExists("brew") else {
            return ([], [ScanNote(category: .brew,
                                  text: L("Homebrew не установлен (на этой машине MacPorts)", "Homebrew is not installed (this machine uses MacPorts)"))])
        }
        let cacheResult = Shell.login("brew --cache")
        let cachePath = cacheResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        var size: Int64 = 0
        if !cachePath.isEmpty, Disk.exists(URL(fileURLWithPath: cachePath)) {
            size = Disk.sizeOnDisk(URL(fileURLWithPath: cachePath))
        }
        let item = CleanupItem(category: .brew,
                               title: L("Старые версии и кэш Homebrew", "Old Homebrew versions and download cache"),
                               detail: "brew cleanup -s --prune=all"
                                       + (cachePath.isEmpty ? "" : " • \(cachePath)"),
                               sizeBytes: size,
                               action: .command("brew-cleanup"),
                               previewPath: cachePath.isEmpty ? nil : URL(fileURLWithPath: cachePath))
        return ([item], [])
    }

    static func scanMacports() -> ([CleanupItem], [ScanNote]) {
        guard commandExists("port") else {
            return ([], [ScanNote(category: .macports, text: L("MacPorts не установлен", "MacPorts is not installed"))])
        }
        let build = URL(fileURLWithPath: "/opt/local/var/macports/build")
        let distfiles = URL(fileURLWithPath: "/opt/local/var/macports/distfiles")
        var size: Int64 = 0
        if Disk.exists(build) { size += Disk.sizeOnDisk(build) }
        if Disk.exists(distfiles) { size += Disk.sizeOnDisk(distfiles) }
        let item = CleanupItem(category: .macports,
                               title: L("Build-каталоги и distfiles MacPorts", "MacPorts build directories and distfiles"),
                               detail: "port -q clean --all installed • /opt/local/var/macports",
                               sizeBytes: size,
                               action: .command("macports-clean"),
                               warning: L("Запустится с правами администратора: macOS спросит пароль", "Runs with administrator rights: macOS will ask for the password"),
                               previewPath: build)
        return ([item], [])
    }

    // MARK: - ~/.cache

    static func scanCaches() -> ([CleanupItem], [ScanNote]) {
        var items: [CleanupItem] = []
        let simple: [(String, String)] = [
            (".cache/puppeteer", L("Браузеры Puppeteer (Chrome, headless-shell)", "Puppeteer browsers (Chrome, headless-shell)")),
            (".cache/nvim/jdtls", L("Индексы Java-языкового сервера jdtls", "Java language server (jdtls) indexes")),
            (".cache/selenium", L("Драйверы Selenium", "Selenium drivers")),
        ]
        for (relative, title) in simple {
            let url = home.appendingPathComponent(relative)
            guard Disk.exists(url) else { continue }
            items.append(CleanupItem(category: .caches,
                                     title: title,
                                     detail: url.path,
                                     sizeBytes: Disk.sizeOnDisk(url),
                                     action: .remove(url)))
        }

        let uvCache = home.appendingPathComponent(".cache/uv")
        if Disk.exists(uvCache) {
            let hasUV = Shell.login("command -v uv").status == 0
            items.append(CleanupItem(category: .caches,
                                     title: L("Кэш uv", "uv cache"),
                                     detail: hasUV ? "uv cache clean" : uvCache.path,
                                     sizeBytes: Disk.sizeOnDisk(uvCache),
                                     action: hasUV ? .command("uv-cache-clean") : .remove(uvCache),
                                     previewPath: uvCache))
        }
        return (items, [])
    }

    // MARK: - Telegram / WhatsApp

    static func telegramPaths() -> [URL] {
        var paths: [URL] = [
            home.appendingPathComponent("Library/Caches/ru.keepcoder.Telegram"),
            home.appendingPathComponent("Library/Containers/ru.keepcoder.Telegram.TelegramShare/Data/Library/Caches"),
        ]
        let manager = FileManager.default
        let stable = Cleaner.telegramStable
        if let accounts = try? manager.contentsOfDirectory(at: stable, includingPropertiesForKeys: nil) {
            for account in accounts where account.lastPathComponent.hasPrefix("account-") {
                paths.append(account.appendingPathComponent("postbox/media"))
            }
            paths.append(stable.appendingPathComponent("accounts-metadata/media"))
        }
        return paths
    }

    static func scanTelegram() -> ([CleanupItem], [ScanNote]) {
        let existing = telegramPaths().filter { Disk.exists($0) }
        guard !existing.isEmpty else {
            return ([], [ScanNote(category: .telegram,
                                  text: L("Telegram не найден или кэш пуст", "Telegram not found or its cache is empty"))])
        }
        if processRunning("Telegram.app") {
            return ([], [ScanNote(category: .telegram,
                                  text: L("Telegram запущена — закройте её, чтобы очистить медиа-кэш", "Telegram is running — quit it to clean the media cache"))])
        }
        var items: [CleanupItem] = []
        for url in existing {
            let size = Disk.sizeOnDisk(url)
            guard size > 0 else { continue }
            items.append(CleanupItem(category: .telegram,
                                     title: L("Медиа-кэш Telegram", "Telegram media cache"),
                                     detail: url.path,
                                     sizeBytes: size,
                                     action: .remove(url),
                                     warning: L("Медиа перекачается при открытии чатов; переписка остаётся", "Media re-downloads when you open chats; messages stay")))
        }
        return (items, [])
    }

    static func scanWhatsapp() -> ([CleanupItem], [ScanNote]) {
        let caches = [
            home.appendingPathComponent("Library/Containers/net.whatsapp.WhatsApp/Data/Library/Caches"),
            home.appendingPathComponent("Library/Caches/net.whatsapp.WhatsApp"),
        ].filter { Disk.exists($0) }

        guard !caches.isEmpty else {
            return ([], [ScanNote(category: .whatsapp,
                                  text: L("WhatsApp не найден или кэш пуст", "WhatsApp not found or its cache is empty"))])
        }
        if processRunning("WhatsApp.app") {
            return ([], [ScanNote(category: .whatsapp,
                                  text: L("WhatsApp запущен — закройте его, чтобы очистить кэш", "WhatsApp is running — quit it to clean the cache"))])
        }
        var items: [CleanupItem] = []
        for url in caches {
            let size = Disk.sizeOnDisk(url)
            guard size > 0 else { continue }
            items.append(CleanupItem(category: .whatsapp,
                                     title: L("Кэш WhatsApp", "WhatsApp cache"),
                                     detail: url.path,
                                     sizeBytes: size,
                                     action: .remove(url),
                                     warning: L("MediaCache перекачается из чатов; сообщения не удаляются", "MediaCache re-downloads from chats; messages are not deleted")))
        }
        return (items, [])
    }

    // MARK: - /private/tmp

    static func scanTmp() -> ([CleanupItem], [ScanNote]) {
        let root = URL(fileURLWithPath: "/private/tmp")
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey]
        ) else { return ([], []) }

        let cutoff = Date().addingTimeInterval(-14 * 24 * 60 * 60)
        let uid = Int(getuid())
        var items: [CleanupItem] = []

        for url in entries {
            let name = url.lastPathComponent
            let knownPrefix = name.hasPrefix("claude-") || name.hasPrefix("dsh-") || name.hasPrefix("tmp")
            guard knownPrefix else { continue }
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { continue }
            let owner = (attributes[.ownerAccountID] as? NSNumber)?.intValue
            guard owner == uid,
                  let modified = attributes[.modificationDate] as? Date,
                  modified < cutoff else { continue }
            items.append(CleanupItem(category: .tmp,
                                     title: L("Временный каталог \(name)", "Temporary directory \(name)"),
                                     detail: L("\(url.path) • изменён \(Self.dateFormatter.string(from: modified))", "\(url.path) • modified \(Self.dateFormatter.string(from: modified))"),
                                     sizeBytes: Disk.sizeOnDisk(url),
                                     action: .remove(url),
                                     warning: L("Проверьте, что этот каталог не нужен запущенному процессу", "Make sure no running process needs this directory")))
        }
        return (items, [])
    }

    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy"
        formatter.locale = Locale(identifier: Localization.isRussian ? "ru_RU" : "en_US")
        return formatter
    }()

    // MARK: - Simulators

    static func scanSimulators() -> ([CleanupItem], [ScanNote]) {
        let developer = Shell.run("/usr/bin/xcode-select", ["-p"])
        let path = developer.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard developer.status == 0, path.contains("Xcode.app") else {
            return ([], [ScanNote(category: .simulators,
                                  text: L("Полный Xcode не установлен (xcode-select: \(path.isEmpty ? "нет" : path)) — симуляторы пропущены", "Full Xcode is not installed (xcode-select: \(path.isEmpty ? "none" : path)) — simulators skipped"))])
        }
        let list = Shell.run("/usr/bin/xcrun", ["simctl", "list", "devices"])
        guard list.status == 0 else {
            return ([], [ScanNote(category: .simulators,
                                  text: L("xcrun simctl не отвечает — симуляторы пропущены", "xcrun simctl is not responding — simulators skipped"))])
        }
        let item = CleanupItem(category: .simulators,
                               title: L("Недоступные симуляторы", "Unavailable simulators"),
                               detail: "xcrun simctl delete unavailable",
                               sizeBytes: 0,
                               action: .command("simctl-delete-unavailable"))
        return ([item], [])
    }
}
