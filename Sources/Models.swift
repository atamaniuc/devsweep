import Foundation

/// One group of things the app knows how to clean.
enum CleanupCategory: String, CaseIterable, Identifiable, Sendable {
    case jetbrains
    case npm
    case pnpm
    case bun
    case docker
    case brew
    case macports
    case caches
    case telegram
    case whatsapp
    case tmp
    case simulators

    var id: String { rawValue }

    var title: String {
        switch self {
        case .jetbrains: return "IntelliJ IDEA"
        case .npm: return "npm"
        case .pnpm: return "pnpm"
        case .bun: return "bun"
        case .docker: return "Docker"
        case .brew: return "Homebrew"
        case .macports: return "MacPorts"
        case .caches: return L("Кэши ~/.cache", "~/.cache caches")
        case .telegram: return "Telegram"
        case .whatsapp: return "WhatsApp"
        case .tmp: return L("Временные файлы", "Temporary files")
        case .simulators: return L("Симуляторы iOS", "iOS simulators")
        }
    }

    var subtitle: String {
        switch self {
        case .jetbrains: return L("кэши версий IDE, которые не установлены", "caches of IDE versions that are not installed")
        case .npm: return L("скачанные пакеты, перекачиваются при установке", "downloaded packages, re-downloaded on install")
        case .pnpm: return L("пакеты в store без ссылок из проектов", "store packages no longer referenced by projects")
        case .bun: return L("кэш пакетов ~/.bun/install/cache", "package cache in ~/.bun/install/cache")
        case .docker: return L("build cache старше 24 ч и образы без тегов", "build cache older than 24 h and untagged images")
        case .brew: return L("старые версии и кэш загрузок", "old versions and download cache")
        case .macports: return L("build-каталоги и distfiles (нужен пароль администратора)", "build directories and distfiles (administrator password required)")
        case .caches: return L("puppeteer, nvim/jdtls, selenium, uv", "puppeteer, nvim/jdtls, selenium, uv")
        case .telegram: return L("медиа-кэш клиента, сообщения остаются", "client media cache, messages stay")
        case .whatsapp: return L("MediaCache и сетевой кэш", "MediaCache and network cache")
        case .tmp: return L("scratch старше 14 дней в /private/tmp", "scratch older than 14 days in /private/tmp")
        case .simulators: return L("симуляторы, которых нет в Xcode", "simulators missing from Xcode")
        }
    }

    var systemImage: String {
        switch self {
        case .jetbrains: return "chevron.left.forwardslash.chevron.right"
        case .npm: return "shippingbox"
        case .pnpm: return "shippingbox.circle"
        case .bun: return "leaf"
        case .docker: return "shippingbox.fill"
        case .brew: return "mug"
        case .macports: return "wrench.and.screwdriver"
        case .caches: return "internaldrive"
        case .telegram: return "paperplane"
        case .whatsapp: return "message"
        case .tmp: return "clock.arrow.circlepath"
        case .simulators: return "iphone"
        }
    }

    /// Advanced categories stay hidden until the user turns them on explicitly.
    var isAdvanced: Bool {
        switch self {
        case .telegram, .whatsapp, .tmp, .simulators: return true
        default: return false
        }
    }
}

enum CleanupAction: Sendable {
    case remove(URL)
    case command(String)

    var commandID: String? {
        if case let .command(id) = self { return id }
        return nil
    }
}

struct CleanupItem: Identifiable, Sendable {
    let id: UUID
    let category: CleanupCategory
    let title: String
    let detail: String
    let sizeBytes: Int64
    let action: CleanupAction
    let warning: String?
    let previewPath: URL?
    var selected: Bool

    init(category: CleanupCategory,
         title: String,
         detail: String,
         sizeBytes: Int64,
         action: CleanupAction,
         warning: String? = nil,
         previewPath: URL? = nil,
         selected: Bool = true) {
        self.id = UUID()
        self.category = category
        self.title = title
        self.detail = detail
        self.sizeBytes = sizeBytes
        self.action = action
        self.warning = warning
        self.previewPath = previewPath
        self.selected = selected
    }
}

struct ScanNote: Identifiable, Sendable {
    let id: UUID
    let category: CleanupCategory
    let text: String

    init(category: CleanupCategory, text: String) {
        self.id = UUID()
        self.category = category
        self.text = text
    }
}

struct ScanResult: Sendable {
    let items: [CleanupItem]
    let notes: [ScanNote]
    let freeBytes: Int64
    let totalBytes: Int64
}

struct CleanReport: Identifiable {
    let id = UUID()
    let freedBytes: Int64
    let removed: Int
    let failed: Int
}

// Helpers shared by the UI and the log.

func humanBytes(_ bytes: Int64) -> String {
    let value = Double(bytes)
    if bytes >= 1_073_741_824 {
        return String(format: "%.1f " + L("ГиБ", "GiB"), value / 1_073_741_824)
    }
    if bytes >= 1_048_576 {
        return String(format: "%.0f " + L("МиБ", "MiB"), value / 1_048_576)
    }
    if bytes >= 1024 {
        return String(format: "%.0f " + L("КиБ", "KiB"), value / 1024)
    }
    return "\(bytes) " + L("Б", "B")
}

func humanPercent(_ fraction: Double) -> String {
    String(format: "%.0f%%", fraction)
}
