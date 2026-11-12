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
        case .caches: return L("uv, nvim/jdtls и другие кэши ~/.cache", "uv, nvim/jdtls and other ~/.cache entries")
        case .devtools: return L("пакетные менеджеры и тулчейны языков", "package managers and language toolchains")
        case .devtoolsAdvanced: return L("зависимости и модели: восстановятся, но медленно", "dependencies and models: they come back, but slowly")
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

/// The discipline a toolchain cache belongs to. The README table and the app
/// list are generated from the same specs, so documentation cannot drift from
/// what the app actually cleans.
enum ToolPlatform: String, CaseIterable, Identifiable, Sendable {
    case web
    case mobile
    case desktop
    case embedded
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .web: return L("Web и backend", "Web & backend")
        case .mobile: return L("Мобильная разработка", "Mobile")
        case .desktop: return L("Desktop и нативные языки", "Desktop & native")
        case .embedded: return L("Embedded", "Embedded")
        case .other: return L("Данные, ML и облако", "Data, ML & cloud")
        }
    }

    var systemImage: String {
        switch self {
        case .web: return "globe"
        case .mobile: return "iphone"
        case .desktop: return "desktopcomputer"
        case .embedded: return "cpu"
        case .other: return "brain.head.profile"
        }
    }

    /// Stable English heading for the generated README section: the docs are
    /// English whatever the system language is.
    var englishTitle: String {
        switch self {
        case .web: return "Web & backend"
        case .mobile: return "Mobile"
        case .desktop: return "Desktop & native"
        case .embedded: return "Embedded"
        case .other: return "Data, ML & cloud"
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
    /// Set for toolchain caches: lets the UI group them by discipline.
    let platform: ToolPlatform?
    var selected: Bool

    init(category: CleanupCategory,
         title: String,
         detail: String,
         sizeBytes: Int64,
         action: CleanupAction,
         warning: String? = nil,
         previewPath: URL? = nil,
         platform: ToolPlatform? = nil,
         selected: Bool = true) {
        self.id = UUID()
        self.category = category
        self.title = title
        self.detail = detail
        self.sizeBytes = sizeBytes
        self.action = action
        self.warning = warning
        self.previewPath = previewPath
        self.platform = platform
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
    /// Path relative to the home directory, or an absolute path when it starts
    /// with "/" (e.g. /opt/miniconda3/pkgs).
    let relativePath: String
    let titleRu: String
    let titleEn: String
    let platform: ToolPlatform
    let advanced: Bool
    let commandID: String?
    let warningRu: String?
    let warningEn: String?

    var url: URL {
        if relativePath.hasPrefix("/") { return URL(fileURLWithPath: relativePath) }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(relativePath)
    }

    /// How the path is shown in the UI and the README.
    var displayPath: String {
        relativePath.hasPrefix("/") ? relativePath : "~/" + relativePath
    }
}

/// Package-manager / toolchain caches. Every path is regenerable: the tool
/// downloads or rebuilds it again. The list is deliberately broad because this
/// is the product: a generic cleaner knows Downloads and Trash, DevSweep knows
/// what a Rust, Flutter, Unreal or PlatformIO developer leaves behind.
enum ToolCaches {
    private static func make(_ relativePath: String,
                             _ titleRu: String,
                             _ titleEn: String,
                             _ platform: ToolPlatform,
                             advanced: Bool = false,
                             commandID: String? = nil,
                             warning: (ru: String, en: String)? = nil) -> ToolCacheSpec {
        ToolCacheSpec(relativePath: relativePath,
                      titleRu: titleRu,
                      titleEn: titleEn,
                      platform: platform,
                      advanced: advanced,
                      commandID: commandID,
                      warningRu: warning?.ru,
                      warningEn: warning?.en)
    }

    static let specs: [ToolCacheSpec] = [
        // MARK: Web & backend

        make("Library/Caches/Yarn", "Yarn: кэш пакетов", "Yarn: package cache", .web),
        make(".yarn/berry/cache", "Yarn Berry: global cache", "Yarn Berry: global cache", .web,
             advanced: true, warning: ("Пакеты скачаются заново", "Packages will be re-downloaded")),
        make(".npm/_npx", "npm: кэш npx", "npm: npx cache", .web),
        make(".cache/node-gyp", "Node: заголовки node-gyp", "Node: node-gyp headers", .web),
        make(".cache/firebase", "Firebase CLI: кэш", "Firebase CLI: cache", .web),
        make("Library/Caches/deno", "Deno: кэш модулей", "Deno: module cache", .web),
        make("Library/Caches/Cypress", "Cypress: бинарники и кэш", "Cypress: binaries and cache", .web),
        make(".cache/puppeteer", "Puppeteer: браузеры", "Puppeteer: browsers", .web),
        make(".cache/selenium", "Selenium: драйверы и браузеры", "Selenium: drivers and browsers", .web),
        make("Library/Caches/ms-playwright", "Playwright: браузеры", "Playwright: browsers", .web,
             advanced: true, warning: ("Браузеры скачаются заново", "Browsers will be re-downloaded")),
        make("Library/Caches/composer", "PHP: Composer cache", "PHP: Composer cache", .web),
        make(".bundle/cache", "Ruby: Bundler cache", "Ruby: Bundler cache", .web),
        make(".hex/packages", "Elixir: Hex packages", "Elixir: Hex packages", .web),
        make(".cache/rebar3", "Erlang: rebar3 cache", "Erlang: rebar3 cache", .web),

        // MARK: Mobile

        make(".gradle/caches", "Gradle: кэш зависимостей", "Gradle: dependency caches", .mobile,
             advanced: true, warning: ("Следующая сборка будет дольше", "The next build will be slower")),
        make(".gradle/wrapper/dists", "Gradle: wrapper distributions", "Gradle: wrapper distributions", .mobile),
        make(".android/cache", "Android: SDK cache", "Android: SDK cache", .mobile),
        make("Library/Android/sdk/system-images", "Android: system images", "Android: system images", .mobile,
             advanced: true, warning: ("Образы скачаются заново", "Images will be re-downloaded")),
        make("Library/Caches/CocoaPods", "CocoaPods: кэш pod'ов", "CocoaPods: pod cache", .mobile),
        make(".cocoapods/repos", "CocoaPods: spec-репозитории", "CocoaPods: spec repositories", .mobile,
             advanced: true, warning: ("`pod repo update` склонирует их заново", "`pod repo update` clones them again")),
        make(".pub-cache", "Dart/Flutter: pub cache", "Dart/Flutter: pub cache", .mobile),
        make("Library/Caches/fastlane", "fastlane: кэш", "fastlane: cache", .mobile),
        make(".konan", "Kotlin/Native cache", "Kotlin/Native cache", .mobile,
             advanced: true, warning: ("Зависимости скачаются при следующей сборке", "Dependencies download on the next build")),
        make("Library/Developer/Xcode/DerivedData", "Xcode: DerivedData", "Xcode: DerivedData", .mobile,
             advanced: true, warning: ("Xcode пересоберёт проект", "Xcode will rebuild the project")),
        make("Library/Developer/Xcode/iOS DeviceSupport", "Xcode: iOS DeviceSupport", "Xcode: iOS DeviceSupport", .mobile,
             advanced: true, warning: ("Файлы пересоздадутся при подключении устройства", "Files are recreated when a device is connected")),
        make("Library/Developer/Xcode/UserData/Previews", "Xcode: Previews", "Xcode: Previews", .mobile,
             advanced: true, warning: ("SwiftUI-превью пересоздадутся", "SwiftUI previews are recreated")),
        make("Library/Developer/CoreSimulator/Caches", "CoreSimulator: кэш", "CoreSimulator: caches", .mobile),

        // MARK: Desktop & native languages

        make(".cargo/registry/cache", "Rust: кэш crates", "Rust: crates cache", .desktop),
        make(".cargo/registry/src", "Rust: распакованные исходники", "Rust: extracted crate sources", .desktop),
        make(".cargo/git", "Rust: git-зависимости", "Rust: git dependencies", .desktop,
             advanced: true, warning: ("Git-зависимости склонируются заново", "Git dependencies will be re-cloned")),
        make(".cache/ccache", "C/C++: ccache", "C/C++: ccache", .desktop),
        make(".cache/clangd/index", "C/C++: индексы clangd", "C/C++: clangd indexes", .desktop),
        make(".cache/bazel", "Bazel: output base", "Bazel: output base", .desktop),
        make("Library/Caches/bazelisk", "Bazelisk: скачанные bazel", "Bazelisk: downloaded bazel", .desktop),
        make(".conan2/p", "C/C++: Conan 2 packages", "C/C++: Conan 2 packages", .desktop,
             advanced: true, warning: ("Пакеты скачаются заново", "Packages will be re-downloaded")),
        make(".cache/vcpkg", "C/C++: vcpkg archives", "C/C++: vcpkg archives", .desktop),
        make("Library/Caches/go-build", "Go: build cache", "Go: build cache", .desktop,
             commandID: "go-clean-cache"),
        make("go/pkg/mod", "Go: кэш модулей", "Go: module cache", .desktop,
             advanced: true, commandID: "go-clean-modcache",
             warning: ("Все зависимости перекачаются при следующей сборке", "All dependencies will be re-downloaded on the next build")),
        make("Library/Caches/org.swift.swiftpm", "Swift: SPM cache", "Swift: SPM cache", .desktop),
        make(".nuget/packages", ".NET: NuGet global packages", ".NET: NuGet global packages", .desktop,
             advanced: true, warning: ("`dotnet restore` скачает пакеты заново", "`dotnet restore` downloads the packages again")),
        make(".local/share/NuGet", ".NET: NuGet кэш пакетов", ".NET: NuGet package cache", .desktop,
             advanced: true),
        make("Library/Caches/NuGet", ".NET: NuGet HTTP cache", ".NET: NuGet HTTP cache", .desktop,
             advanced: true),
        make("Library/Caches/electron", "Electron: скачанные версии", "Electron: downloaded versions", .desktop),
        make("Library/Caches/electron-builder", "electron-builder: кэш", "electron-builder: cache", .desktop),
        make("Library/Unity/cache", "Unity: кэш пакетов", "Unity: package cache", .desktop),
        make("Library/Application Support/Epic/UnrealEngine/Common/DerivedDataCache",
             "Unreal Engine: DerivedDataCache", "Unreal Engine: DerivedDataCache", .desktop,
             advanced: true, warning: ("Шейдеры пересоберутся при следующем запуске", "Shaders are rebuilt on the next launch")),
        make(".cache/zig", "Zig: cache", "Zig: cache", .desktop),
        make("Library/Application Support/Code/Cache", "VS Code: cache", "VS Code: cache", .desktop),
        make("Library/Application Support/Code/CachedData", "VS Code: cached data", "VS Code: cached data", .desktop),
        make("Library/Application Support/Code - Insiders/Cache", "VS Code Insiders: cache", "VS Code Insiders: cache", .desktop),
        make("Library/Application Support/Cursor/Cache", "Cursor: cache", "Cursor: cache", .desktop),
        make("Library/Application Support/Cursor/CachedData", "Cursor: cached data", "Cursor: cached data", .desktop),

        // MARK: Embedded

        make(".platformio/packages", "PlatformIO: платформы и тулчейны", "PlatformIO: platforms and toolchains", .embedded,
             advanced: true, warning: ("PlatformIO скачает платформы заново", "PlatformIO re-downloads the platforms")),
        make(".platformio/.cache", "PlatformIO: кэш сборки", "PlatformIO: build cache", .embedded),
        make(".espressif/dist", "ESP-IDF: дистрибутивы", "ESP-IDF: distributions", .embedded),
        make(".espressif/tools", "ESP-IDF: тулчейны", "ESP-IDF: toolchains", .embedded,
             advanced: true, warning: ("`install.sh` переустановит тулчейны", "`install.sh` reinstalls the toolchains")),
        make(".espressif/python_env", "ESP-IDF: python env", "ESP-IDF: python env", .embedded,
             advanced: true, warning: ("`install.sh` пересоздаст окружение", "`install.sh` recreates the environment")),
        make("Library/Arduino15/staging", "Arduino: staging", "Arduino: staging", .embedded),
        make("Library/Arduino15/packages", "Arduino: скачанные ядра", "Arduino: downloaded cores", .embedded,
             advanced: true, warning: ("Ядра скачаются через Boards Manager", "Cores re-download through Boards Manager")),
        make(".cache/arduino", "arduino-cli: кэш", "arduino-cli: cache", .embedded),
        make(".cache/tinygo", "TinyGo: кэш сборки", "TinyGo: build cache", .embedded),

        // MARK: Data, ML & cloud

        make("Library/Caches/pip", "Python: pip cache", "Python: pip cache", .other),
        make("Library/Caches/pypoetry", "Python: Poetry cache", "Python: Poetry cache", .other),
        make(".cache/pre-commit", "Python: окружения pre-commit", "Python: pre-commit environments", .other),
        make("miniconda3/pkgs", "Conda: пакеты (miniconda3)", "Conda: packages (miniconda3)", .other,
             advanced: true, warning: ("Пакеты скачаются заново", "Packages will be re-downloaded")),
        make("anaconda3/pkgs", "Conda: пакеты (anaconda3)", "Conda: packages (anaconda3)", .other,
             advanced: true, warning: ("Пакеты скачаются заново", "Packages will be re-downloaded")),
        make("miniforge3/pkgs", "Conda: пакеты (miniforge3)", "Conda: packages (miniforge3)", .other,
             advanced: true, warning: ("Пакеты скачаются заново", "Packages will be re-downloaded")),
        make("/opt/miniconda3/pkgs", "Conda: пакеты (/opt/miniconda3)", "Conda: packages (/opt/miniconda3)", .other,
             advanced: true, warning: ("Пакеты скачаются заново", "Packages will be re-downloaded")),
        make("/opt/anaconda3/pkgs", "Conda: пакеты (/opt/anaconda3)", "Conda: packages (/opt/anaconda3)", .other,
             advanced: true, warning: ("Пакеты скачаются заново", "Packages will be re-downloaded")),
        make(".cache/huggingface", "Hugging Face: модели", "Hugging Face: models", .other,
             advanced: true, warning: ("Модели скачаются заново", "Models will be re-downloaded")),
        make(".ollama/models", "Ollama: модели", "Ollama: models", .other,
             advanced: true, warning: ("Модели скачаются заново", "Models will be re-downloaded")),
        make(".lmstudio/models", "LM Studio: модели", "LM Studio: models", .other,
             advanced: true, warning: ("Модели скачаются заново", "Models will be re-downloaded")),
        make(".cache/torch", "PyTorch: кэш моделей", "PyTorch: model cache", .other,
             advanced: true, warning: ("Веса скачаются заново", "Weights will be re-downloaded")),
        make(".cache/whisper", "Whisper: модели", "Whisper: models", .other,
             advanced: true, warning: ("Модели скачаются заново", "Models will be re-downloaded")),
        make("Library/Caches/Coursier/v1", "JVM: Coursier cache", "JVM: Coursier cache", .other),
        make(".sbt/boot", "Scala: sbt boot", "Scala: sbt boot", .other),
        make(".ivy2/cache", "Scala/Java: ivy cache", "Scala/Java: ivy cache", .other),
        make(".m2/repository", "Maven: локальный репозиторий", "Maven: local repository", .other,
             advanced: true, warning: ("Артефакты скачаются заново", "Artifacts will be re-downloaded")),
        make("Library/Caches/helm/repository", "Helm: кэш чартов", "Helm: chart cache", .other),
        make(".kube/cache", "kubectl: кэш discovery", "kubectl: discovery cache", .other),
        make(".terraform.d/plugin-cache", "Terraform: plugin cache", "Terraform: plugin cache", .other),
        make(".cache/nix", "Nix: кэш", "Nix: cache", .other),
    ]

    /// How many distinct toolchain caches the app knows about (shown in the UI
    /// and in the README headline).
    static var count: Int { specs.count }

    static func specs(for platform: ToolPlatform) -> [ToolCacheSpec] {
        specs.filter { $0.platform == platform }
    }
}

enum AppVersion {
    static let name = "DevSweep"
    static let taglineEn = "Reclaim the gigabytes your toolchain quietly hoards."
    static let taglineRu = "Верните гигабайты, которые ваш тулчейн тихо копит."

    static var current: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }
    static let releasesURL = URL(string: "https://github.com/atamaniuc/devsweep/releases/latest")!
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
