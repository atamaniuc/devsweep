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
    case devtools
    case devtoolsAdvanced
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
        case .devtools: return L("Кэши инструментов", "Toolchain caches")
        case .devtoolsAdvanced: return L("Кэши инструментов (расширенные)", "Toolchain caches (advanced)")
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
        case .devtools: return L("cargo, ccache, pip, composer, yarn, pub, SPM, VS Code…", "cargo, ccache, pip, composer, yarn, pub, SPM, VS Code…")
        case .devtoolsAdvanced: return L("go modcache, gradle, maven, conda, playwright, DerivedData…", "go modcache, gradle, maven, conda, playwright, DerivedData…")
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
        case .devtools: return "hammer"
        case .devtoolsAdvanced: return "hammer.fill"
        case .telegram: return "paperplane"
        case .whatsapp: return "message"
        case .tmp: return "clock.arrow.circlepath"
        case .simulators: return "iphone"
        }
    }

    /// Advanced categories stay hidden until the user turns them on explicitly.
    var isAdvanced: Bool {
        switch self {
        case .devtoolsAdvanced: return true
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
    let skipped: Int
    let failed: Int
}

struct ToolCacheSpec: Sendable {
    let relativePath: String
    let titleRu: String
    let titleEn: String
    let advanced: Bool
    let commandID: String?
    let warningRu: String?
    let warningEn: String?
}

/// Package-manager / toolchain caches. Every path is regenerable: the tool
/// downloads or rebuilds it again.
enum ToolCaches {
    static let specs: [ToolCacheSpec] = [
        .init(relativePath: ".cargo/registry/cache", titleRu: "Rust: кэш crates", titleEn: "Rust: crates cache",
              advanced: false, commandID: nil, warningRu: nil, warningEn: nil),
        .init(relativePath: ".cargo/registry/src", titleRu: "Rust: распакованные исходники", titleEn: "Rust: extracted crate sources",
              advanced: false, commandID: nil, warningRu: nil, warningEn: nil),
        .init(relativePath: ".cargo/git", titleRu: "Rust: git-зависимости", titleEn: "Rust: git dependencies",
              advanced: true, commandID: nil,
              warningRu: "Git-зависимости склонируются заново", warningEn: "Git dependencies will be re-cloned"),
        .init(relativePath: ".cache/ccache", titleRu: "C/C++: ccache", titleEn: "C/C++: ccache",
              advanced: false, commandID: nil, warningRu: nil, warningEn: nil),
        .init(relativePath: ".cache/clangd/index", titleRu: "C/C++: индексы clangd", titleEn: "C/C++: clangd indexes",
              advanced: false, commandID: nil, warningRu: nil, warningEn: nil),
        .init(relativePath: "Library/Caches/go-build", titleRu: "Go: build cache", titleEn: "Go: build cache",
              advanced: false, commandID: "go-clean-cache", warningRu: nil, warningEn: nil),
        .init(relativePath: "go/pkg/mod", titleRu: "Go: кэш модулей", titleEn: "Go: module cache",
              advanced: true, commandID: "go-clean-modcache",
              warningRu: "Все зависимости перекачаются при следующей сборке",
              warningEn: "All dependencies will be re-downloaded on the next build"),
        .init(relativePath: ".gradle/caches", titleRu: "Gradle: кэш зависимостей", titleEn: "Gradle: dependency caches",
              advanced: true, commandID: nil,
              warningRu: "Следующая сборка будет дольше", warningEn: "The next build will be slower"),
        .init(relativePath: ".m2/repository", titleRu: "Maven: локальный репозиторий", titleEn: "Maven: local repository",
              advanced: true, commandID: nil,
              warningRu: "Артефакты скачаются заново", warningEn: "Artifacts will be re-downloaded"),
        .init(relativePath: ".ivy2/cache", titleRu: "Scala/Java: ivy cache", titleEn: "Scala/Java: ivy cache",
              advanced: false, commandID: nil, warningRu: nil, warningEn: nil),
        .init(relativePath: "Library/Caches/pip", titleRu: "Python: pip cache", titleEn: "Python: pip cache",
              advanced: false, commandID: nil, warningRu: nil, warningEn: nil),
        .init(relativePath: "Library/Caches/pypoetry", titleRu: "Python: Poetry cache", titleEn: "Python: Poetry cache",
              advanced: false, commandID: nil, warningRu: nil, warningEn: nil),
        .init(relativePath: ".cache/pre-commit", titleRu: "Python: окружения pre-commit", titleEn: "Python: pre-commit environments",
              advanced: false, commandID: nil, warningRu: nil, warningEn: nil),
        .init(relativePath: "Library/Caches/composer", titleRu: "PHP: Composer cache", titleEn: "PHP: Composer cache",
              advanced: false, commandID: nil, warningRu: nil, warningEn: nil),
        .init(relativePath: "Library/Caches/Yarn", titleRu: "Node: Yarn cache", titleEn: "Node: Yarn cache",
              advanced: false, commandID: nil, warningRu: nil, warningEn: nil),
        .init(relativePath: "Library/Caches/deno", titleRu: "Deno cache", titleEn: "Deno cache",
              advanced: false, commandID: nil, warningRu: nil, warningEn: nil),
        .init(relativePath: ".pub-cache", titleRu: "Dart/Flutter: pub cache", titleEn: "Dart/Flutter: pub cache",
              advanced: false, commandID: nil, warningRu: nil, warningEn: nil),
        .init(relativePath: "Library/Caches/org.swift.swiftpm", titleRu: "Swift: SPM cache", titleEn: "Swift: SPM cache",
              advanced: false, commandID: nil, warningRu: nil, warningEn: nil),
        .init(relativePath: ".android/cache", titleRu: "Android: SDK cache", titleEn: "Android: SDK cache",
              advanced: false, commandID: nil, warningRu: nil, warningEn: nil),
        .init(relativePath: "Library/Caches/ms-playwright", titleRu: "Playwright: браузеры", titleEn: "Playwright: browsers",
              advanced: true, commandID: nil,
              warningRu: "Браузеры скачаются заново", warningEn: "Browsers will be re-downloaded"),
        .init(relativePath: "Library/Developer/Xcode/DerivedData", titleRu: "Xcode: DerivedData", titleEn: "Xcode: DerivedData",
              advanced: true, commandID: nil,
              warningRu: "Xcode пересоберёт проект", warningEn: "Xcode will rebuild the project"),
        .init(relativePath: ".local/share/NuGet", titleRu: "NuGet: кэш пакетов", titleEn: "NuGet: package cache",
              advanced: true, commandID: nil, warningRu: nil, warningEn: nil),
        .init(relativePath: "Library/Caches/NuGet", titleRu: "NuGet: HTTP cache", titleEn: "NuGet: HTTP cache",
              advanced: true, commandID: nil, warningRu: nil, warningEn: nil),
        .init(relativePath: ".cache/huggingface", titleRu: "Hugging Face: модели", titleEn: "Hugging Face: models",
              advanced: true, commandID: nil,
              warningRu: "Модели скачаются заново", warningEn: "Models will be re-downloaded"),
        .init(relativePath: ".ollama/models", titleRu: "Ollama: модели", titleEn: "Ollama: models",
              advanced: true, commandID: nil,
              warningRu: "Модели скачаются заново", warningEn: "Models will be re-downloaded"),
        .init(relativePath: ".konan", titleRu: "Kotlin/Native cache", titleEn: "Kotlin/Native cache",
              advanced: true, commandID: nil, warningRu: nil, warningEn: nil),
        .init(relativePath: "Library/Caches/Coursier/v1", titleRu: "JVM: Coursier cache", titleEn: "JVM: Coursier cache",
              advanced: false, commandID: nil, warningRu: nil, warningEn: nil),
        .init(relativePath: ".sbt/boot", titleRu: "Scala: sbt boot", titleEn: "Scala: sbt boot",
              advanced: false, commandID: nil, warningRu: nil, warningEn: nil),
        .init(relativePath: ".gradle/wrapper/dists", titleRu: "Gradle: wrapper distributions", titleEn: "Gradle: wrapper distributions",
              advanced: false, commandID: nil, warningRu: nil, warningEn: nil),
        .init(relativePath: "Library/Application Support/Code/Cache", titleRu: "VS Code: cache", titleEn: "VS Code: cache",
              advanced: false, commandID: nil, warningRu: nil, warningEn: nil),
        .init(relativePath: "Library/Application Support/Code/CachedData", titleRu: "VS Code: cached data", titleEn: "VS Code: cached data",
              advanced: false, commandID: nil, warningRu: nil, warningEn: nil),
        .init(relativePath: "Library/Application Support/Cursor/Cache", titleRu: "Cursor: cache", titleEn: "Cursor: cache",
              advanced: false, commandID: nil, warningRu: nil, warningEn: nil),
        .init(relativePath: "Library/Application Support/Cursor/CachedData", titleRu: "Cursor: cached data", titleEn: "Cursor: cached data",
              advanced: false, commandID: nil, warningRu: nil, warningEn: nil),
        .init(relativePath: "Library/Caches/helm/repository", titleRu: "Helm: кэш чартов", titleEn: "Helm: chart cache",
              advanced: false, commandID: nil, warningRu: nil, warningEn: nil),
        .init(relativePath: ".kube/cache", titleRu: "kubectl: кэш discovery", titleEn: "kubectl: discovery cache",
              advanced: false, commandID: nil, warningRu: nil, warningEn: nil),
        .init(relativePath: ".cache/zig", titleRu: "Zig: cache", titleEn: "Zig: cache",
              advanced: false, commandID: nil, warningRu: nil, warningEn: nil),
        .init(relativePath: ".terraform.d/plugin-cache", titleRu: "Terraform: plugin cache", titleEn: "Terraform: plugin cache",
              advanced: false, commandID: nil, warningRu: nil, warningEn: nil),
        .init(relativePath: "miniconda3/pkgs", titleRu: "Conda: пакеты (miniconda3)", titleEn: "Conda: packages (miniconda3)",
              advanced: true, commandID: nil,
              warningRu: "Пакеты скачаются заново", warningEn: "Packages will be re-downloaded"),
        .init(relativePath: "anaconda3/pkgs", titleRu: "Conda: пакеты (anaconda3)", titleEn: "Conda: packages (anaconda3)",
              advanced: true, commandID: nil,
              warningRu: "Пакеты скачаются заново", warningEn: "Packages will be re-downloaded"),
        .init(relativePath: "miniforge3/pkgs", titleRu: "Conda: пакеты (miniforge3)", titleEn: "Conda: packages (miniforge3)",
              advanced: true, commandID: nil,
              warningRu: "Пакеты скачаются заново", warningEn: "Packages will be re-downloaded"),
        .init(relativePath: "opt/miniconda3/pkgs", titleRu: "Conda: пакеты (/opt/miniconda3)", titleEn: "Conda: packages (/opt/miniconda3)",
              advanced: true, commandID: nil,
              warningRu: "Пакеты скачаются заново", warningEn: "Packages will be re-downloaded"),
        .init(relativePath: "opt/anaconda3/pkgs", titleRu: "Conda: пакеты (/opt/anaconda3)", titleEn: "Conda: packages (/opt/anaconda3)",
              advanced: true, commandID: nil,
              warningRu: "Пакеты скачаются заново", warningEn: "Packages will be re-downloaded"),
        .init(relativePath: "Library/Developer/Xcode/iOS DeviceSupport", titleRu: "Xcode: iOS DeviceSupport", titleEn: "Xcode: iOS DeviceSupport",
              advanced: true, commandID: nil,
              warningRu: "Файлы пересоздадутся при подключении устройства",
              warningEn: "Files are recreated when a device is connected"),
        .init(relativePath: "Library/Android/sdk/system-images", titleRu: "Android: system images", titleEn: "Android: system images",
              advanced: true, commandID: nil,
              warningRu: "Образы скачаются заново", warningEn: "Images will be re-downloaded"),
        .init(relativePath: ".cache/torch", titleRu: "PyTorch: кэш моделей", titleEn: "PyTorch: model cache",
              advanced: true, commandID: nil,
              warningRu: "Веса скачаются заново", warningEn: "Weights will be re-downloaded"),
        .init(relativePath: ".lmstudio/models", titleRu: "LM Studio: модели", titleEn: "LM Studio: models",
              advanced: true, commandID: nil,
              warningRu: "Модели скачаются заново", warningEn: "Models will be re-downloaded"),
    ]
}

enum AppVersion {
    static var current: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }
    static let releasesURL = URL(string: "https://github.com/atamaniuc/clean-disk-app/releases/latest")!
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
    String(format: "%.0f%%", fraction * 100)
}
