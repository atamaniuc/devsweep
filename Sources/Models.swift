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
    case cloud
    case web3
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .web: return L("Web и backend", "Web & backend")
        case .mobile: return L("Мобильная разработка", "Mobile")
        case .desktop: return L("Desktop и нативные языки", "Desktop & native")
        case .embedded: return L("Embedded", "Embedded")
        case .cloud: return L("Облако и инфраструктура", "Cloud & infrastructure")
        case .web3: return L("Web3 и блокчейн", "Web3 & blockchain")
        case .other: return L("Данные и ML", "Data & ML")
        }
    }

    var systemImage: String {
        switch self {
        case .web: return "globe"
        case .mobile: return "iphone"
        case .desktop: return "desktopcomputer"
        case .embedded: return "cpu"
        case .cloud: return "cloud"
        case .web3: return "bitcoinsign.circle"
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
        case .cloud: return "Cloud & infrastructure"
        case .web3: return "Web3 & blockchain"
        case .other: return "Data & ML"
        }
    }

    /// Short label for the discipline chips in the header.
    var chipTitle: String {
        switch self {
        case .web: return L("Web", "Web")
        case .mobile: return L("Mobile", "Mobile")
        case .desktop: return L("Desktop", "Desktop")
        case .embedded: return L("Embedded", "Embedded")
        case .cloud: return L("Cloud", "Cloud")
        case .web3: return "Web3"
        case .other: return L("Данные", "Data/ML")
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

/// Brand tint for the row glyph. Kept as a plain enum so Models.swift stays
/// UI-framework free and `--self-test` can check every glyph.
enum BrandColor: String, Sendable, CaseIterable {
    case blue, purple, orange, red, green, teal, indigo, pink, yellow, gray, cyan, brown
}

/// Icon identity of a row: an SF Symbol drawn in the tool's own brand colour,
/// plus, when the tool ships a GUI app, the bundle id whose real macOS icon is
/// used instead (Docker, VS Code, Xcode, Unity, Telegram...). That is how a
/// developer finds a tool in the list: by its logo, not by a generic box.
struct ToolGlyph: Sendable, Equatable {
    let systemImage: String
    let tint: BrandColor
    /// Bundle id of the GUI app whose icon identifies this tool, if any.
    let appBundleIdentifier: String?

    init(_ systemImage: String, _ tint: BrandColor, app: String? = nil) {
        self.systemImage = systemImage
        self.tint = tint
        self.appBundleIdentifier = app
    }
}

/// Per-tool brand glyphs for the catalog (99 specs) and for the fixed
/// categories. Rules are matched against the catalog path, longest/most
/// specific first: when a new spec is added without a rule, `--self-test` fails
/// instead of shipping a generic box.
enum ToolBrand {
    static func look(for spec: ToolCacheSpec) -> ToolGlyph? {
        let path = spec.relativePath.lowercased()
        for rule in rules where rule.match.contains(where: { path.contains($0) }) {
            return ToolGlyph(rule.icon, rule.tint, app: rule.app)
        }
        return nil
    }

    /// Legit fallback only for hand-written scanner rows and for a catalog
    /// entry whose platform has no more specific look.
    static func generic(for platform: ToolPlatform) -> ToolGlyph {
        switch platform {
        case .web: return ToolGlyph("globe", .blue)
        case .mobile: return ToolGlyph("iphone", .green)
        case .desktop: return ToolGlyph("desktopcomputer", .indigo)
        case .embedded: return ToolGlyph("cpu", .teal)
        case .cloud: return ToolGlyph("cloud.fill", .blue)
        case .web3: return ToolGlyph("bitcoinsign.circle", .purple)
        case .other: return ToolGlyph("brain.head.profile", .gray)
        }
    }

    static func forCategory(_ category: CleanupCategory) -> ToolGlyph {
        switch category {
        case .jetbrains:
            return ToolGlyph("chevron.left.forwardslash.chevron.right", .purple,
                             app: "com.jetbrains.intellij")
        case .npm: return ToolGlyph("shippingbox.fill", .red)
        case .pnpm: return ToolGlyph("shippingbox.circle.fill", .orange)
        case .bun: return ToolGlyph("leaf.fill", .pink)
        case .docker: return ToolGlyph("shippingbox.fill", .blue, app: "com.docker.docker")
        case .brew: return ToolGlyph("mug.fill", .orange)
        case .macports: return ToolGlyph("wrench.and.screwdriver.fill", .orange)
        case .caches: return ToolGlyph("internaldrive.fill", .blue)
        case .devtools: return ToolGlyph("hammer.fill", .blue)
        case .devtoolsAdvanced: return ToolGlyph("hammer.fill", .orange)
        case .telegram: return ToolGlyph("paperplane.fill", .blue, app: "ru.keepcoder.Telegram")
        case .whatsapp: return ToolGlyph("message.fill", .green, app: "net.whatsapp.WhatsApp")
        case .tmp: return ToolGlyph("clock.arrow.circlepath", .gray)
        case .simulators: return ToolGlyph("iphone", .blue, app: "com.apple.dt.Xcode")
        }
    }

    /// Ordered: the first rule whose one of the fragments occurs in the path
    /// wins. Specific fragments (e.g. "library/caches/nuget") come before the
    /// generic ones ("nuget").
    private struct Rule {
        let match: [String]
        let icon: String
        let tint: BrandColor
        let app: String?

        init(_ match: [String], _ icon: String, _ tint: BrandColor, app: String? = nil) {
            self.match = match
            self.icon = icon
            self.tint = tint
            self.app = app
        }
    }

    private static let rules: [Rule] = [
        // Web & backend
        Rule(["yarn/berry"], "circle.hexagongrid.fill", .blue),
        Rule(["library/caches/yarn"], "circle.hexagongrid.fill", .blue),
        Rule([".npm/_npx"], "shippingbox.fill", .red),
        Rule(["node-gyp"], "shippingbox", .green),
        Rule(["firebase"], "flame.fill", .orange),
        Rule(["library/caches/deno"], "shippingbox", .gray),
        Rule([".cache/deno"], "shippingbox", .gray),
        Rule([".cache/yarn"], "circle.hexagongrid.fill", .blue),
        Rule(["library/caches/typescript"], "chevron.left.forwardslash.chevron.right", .blue),
        Rule([".cache/parcel"], "shippingbox.fill", .orange),
        Rule(["library/caches/cypress"], "checkmark.seal.fill", .green),
        Rule(["library/caches/bun"], "hare.fill", .pink),
        Rule([".cache/prisma"], "triangle.fill", .indigo),
        Rule(["puppeteer"], "pawprint.fill", .green),
        Rule(["selenium"], "globe", .green),
        Rule(["ms-playwright"], "play.rectangle.fill", .green),
        Rule(["composer"], "square.stack.3d.up.fill", .brown),
        Rule([".bundle/cache"], "diamond.fill", .red),
        Rule([".gem/ruby"], "diamond.fill", .red),
        Rule([".gem/specs"], "diamond", .red),
        Rule([".rvm/archives"], "diamond", .red),
        Rule([".hex/packages"], "hexagon.fill", .purple),
        Rule(["rebar3"], "gearshape.fill", .red),

        // Mobile
        Rule([".gradle/wrapper"], "square.stack.3d.up.fill", .green),
        Rule([".gradle/caches"], "hammer.fill", .green),
        Rule(["androidstudio"], "hammer.fill", .green, app: "com.google.android.studio"),
        Rule(["system-images"], "iphone", .green),
        Rule([".android/cache"], "smartphone", .green),
        Rule(["cocoapods/repos"], "square.stack.3d.up.fill", .red),
        Rule(["cocoapods"], "shippingbox.fill", .red),
        Rule([".pub-cache"], "shippingbox.fill", .blue),
        Rule(["library/caches/fastlane"], "paperplane.fill", .green),
        Rule([".konan"], "k.circle.fill", .purple),
        Rule(["deriveddata"], "hammer.fill", .blue, app: "com.apple.dt.Xcode"),
        Rule(["devicesupport"], "iphone", .blue, app: "com.apple.dt.Xcode"),
        Rule(["xcode/userdata/previews"], "rectangle.on.rectangle", .blue, app: "com.apple.dt.Xcode"),
        Rule(["coresimulator"], "iphone", .blue, app: "com.apple.dt.Xcode"),
        Rule(["caches/com.apple.dt.xcode"], "hammer.fill", .blue, app: "com.apple.dt.Xcode"),

        // Desktop & native
        Rule([".cargo/registry/index"], "list.bullet.rectangle", .orange),
        Rule([".cargo/registry/src"], "gearshape.2", .orange),
        Rule([".cargo/registry/cache"], "gearshape.2.fill", .orange),
        Rule([".cargo/git"], "arrow.triangle.branch", .orange),
        Rule(["cache/ccache"], "chevron.left.forwardslash.chevron.right", .blue),
        Rule(["clangd"], "chevron.left.forwardslash.chevron.right", .purple),
        Rule(["bazelisk"], "square.stack.3d.up", .green),
        Rule(["cache/bazel"], "square.stack.3d.up.fill", .green),
        Rule([".conan2"], "shippingbox.fill", .blue),
        Rule(["vcpkg"], "shippingbox", .blue),
        Rule(["library/caches/go-build"], "g.circle.fill", .cyan),
        Rule(["go/pkg/mod"], "g.circle.fill", .cyan),
        Rule(["org.swift.swiftpm"], "swift", .orange),
        Rule([".nuget/packages"], "shippingbox.fill", .purple),
        Rule(["library/caches/nuget"], "shippingbox", .purple),
        Rule([".local/share/nuget"], "shippingbox", .purple),
        Rule(["electron-builder"], "atom", .indigo),
        Rule(["library/caches/electron"], "atom", .blue),
        Rule(["library/unity"], "cube.fill", .gray),
        Rule(["godot/export_templates"], "gamecontroller.fill", .blue),
        Rule(["unrealengine"], "cube.transparent", .gray),
        Rule(["cache/zig"], "bolt.fill", .yellow),
        Rule([".cache/sccache"], "bolt.fill", .orange),
        Rule([".rustup/downloads"], "arrow.down.circle.fill", .orange),
        Rule([".rustup/tmp"], "gearshape.2", .orange),
        Rule([".cache/vscode-ripgrep"], "chevron.left.forwardslash.chevron.right", .blue,
             app: "com.microsoft.VSCode"),
        Rule([".cache/github-copilot"], "sparkles", .teal),
        Rule(["windsurf"], "chevron.left.forwardslash.chevron.right", .teal),
        Rule(["antigravity"], "chevron.left.forwardslash.chevron.right", .purple),
        Rule(["caches/zed"], "z.square.fill", .gray),
        Rule(["code - insiders"], "chevron.left.forwardslash.chevron.right", .teal,
             app: "com.microsoft.VSCodeInsiders"),
        Rule(["support/code"], "chevron.left.forwardslash.chevron.right", .blue,
             app: "com.microsoft.VSCode"),
        Rule(["cursor"], "cursorarrow.rays", .gray, app: "com.todesktop.230313mzl4w4u92"),

        // Embedded
        Rule([".platformio/packages"], "cpu.fill", .orange),
        Rule([".platformio"], "cpu", .orange),
        Rule([".espressif/dist"], "cpu.fill", .red),
        Rule([".espressif"], "cpu", .red),
        Rule(["arduino15/packages"], "cpu.fill", .teal),
        Rule(["arduino15"], "cpu", .teal),
        Rule(["cache/arduino"], "cpu", .teal),
        Rule(["cache/tinygo"], "cpu", .cyan),

        // Data & ML
        Rule(["caches/pip"], "shippingbox.fill", .blue),
        Rule(["pypoetry"], "text.book.closed.fill", .blue),
        Rule(["pre-commit"], "checkmark.shield.fill", .green),
        Rule(["miniconda3"], "leaf.fill", .green),
        Rule(["anaconda3"], "leaf.fill", .green),
        Rule(["miniforge3"], "leaf.fill", .green),
        Rule(["huggingface"], "face.smiling.fill", .yellow),
        Rule([".ollama"], "brain.head.profile", .gray),
        Rule(["lmstudio"], "brain", .purple),
        Rule(["cache/torch"], "flame.fill", .orange),
        Rule(["cache/whisper"], "waveform", .gray),
        Rule(["coursier"], "cup.and.saucer.fill", .orange),
        Rule([".sbt"], "cup.and.saucer.fill", .red),
        Rule([".gradle/daemon"], "hammer.fill", .green),
        Rule(["ivy2"], "cup.and.saucer.fill", .orange),
        Rule([".m2/repository"], "shippingbox.fill", .red),
        Rule(["cache/nix"], "snowflake", .blue),
        Rule(["cache/jax"], "function", .green),
        Rule([".keras"], "brain.head.profile", .red),
        Rule([".nv/computecache"], "cpu.fill", .green),
        Rule([".triton/cache"], "bolt.horizontal.fill", .green),
        Rule(["cache/jupyter"], "book.closed.fill", .orange),
        Rule([".julia/compiled"], "function", .purple),
        Rule([".julia/packages"], "shippingbox.fill", .purple),
        Rule([".oh-my-zsh/cache"], "terminal.fill", .gray),
        Rule([".cache/pkg"], "shippingbox", .gray),

        // Cloud & infrastructure
        Rule([".aws/sso"], "key.fill", .orange),
        Rule([".aws/cli"], "cloud.fill", .orange),
        Rule(["gcloud"], "cloud.fill", .blue),
        Rule(["azure"], "cloud.fill", .blue),
        Rule([".pulumi/plugins"], "cloud.fill", .purple),
        Rule([".pulumi/logs"], "cloud", .purple),
        Rule([".supabase/bin"], "bolt.fill", .green),
        Rule([".supabase/artifacts"], "bolt.fill", .green),
        Rule([".supabase"], "bolt", .green),
        Rule(["wrangler"], "cloud.fill", .orange),
        Rule([".terraform.d/checkpoint"], "arrow.triangle.2.circlepath", .purple),
        Rule(["plugin-cache"], "square.stack.3d.up.fill", .purple),
        Rule([".cache/gh"], "terminal.fill", .gray),
        Rule(["helm/repository"], "helm", .blue),
        Rule([".kube/http-cache"], "square.grid.3x3.fill", .blue),
        Rule([".kube/cache"], "square.grid.3x3.fill", .blue),
        Rule([".minikube/cache"], "shippingbox.fill", .blue),
        Rule([".ansible/tmp"], "wrench.and.screwdriver", .red),
        Rule([".vagrant.d/boxes"], "shippingbox", .indigo),

        // Web3 & blockchain
        Rule([".foundry"], "hammer.fill", .gray),
        Rule([".svm"], "curlybraces", .purple),
        Rule(["cache/solana"], "waveform.path", .purple),
        Rule([".avm"], "sailboat.fill", .blue),
        Rule([".solc-select"], "curlybraces", .purple),
        Rule([".solcx"], "curlybraces", .purple),
        Rule(["hardhat"], "hammer.fill", .yellow),
    ]
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
    /// Extra names the row answers to when searching: the untranslated tool
    /// name and its catalog path, so "foundry" finds the row on a Russian UI.
    let keywords: [String]
    /// The tool's brand icon (or its real app icon) so rows are recognisable
    /// by logo instead of a generic box.
    let glyph: ToolGlyph

    init(category: CleanupCategory,
         title: String,
         detail: String,
         sizeBytes: Int64,
         action: CleanupAction,
         warning: String? = nil,
         previewPath: URL? = nil,
         platform: ToolPlatform? = nil,
         keywords: [String] = [],
         glyph: ToolGlyph? = nil) {
        self.id = UUID()
        self.category = category
        self.title = title
        self.detail = detail
        self.sizeBytes = sizeBytes
        self.action = action
        self.warning = warning
        self.previewPath = previewPath
        self.platform = platform
        self.keywords = keywords
        self.glyph = glyph ?? ToolBrand.forCategory(category)
    }
}

/// Defaults of the two switches in the action bar. Advanced categories are
/// *shown* out of the box; being visible is not the same as being selected.
enum UIDefaults {
    static let showAdvanced = true
    static let dryRun = true
    /// Advanced rows are never preselected: what is not selected cannot be
    /// deleted by an accidental "clean", and the warning stays opt-in.
    static let preselectAdvanced = false
}

/// Selection bookkeeping, deliberately outside SwiftUI so `--self-test` can
/// drive it. Sizes are indexed by id, so flipping one checkbox is O(1) and the
/// "can be freed" number never walks the list: a scan with a hundred rows and
/// a user who clicks every checkbox must not lag.
struct SelectionLedger: Sendable {
    private(set) var ids: Set<UUID> = []
    private(set) var bytes: Int64 = 0
    private var sizes: [UUID: Int64] = [:]

    var count: Int { ids.count }
    var isEmpty: Bool { ids.isEmpty }

    /// Rebuilds the ledger for a fresh scan and applies the default selection:
    /// every safe item is checked, advanced items are not.
    mutating func load(_ items: [CleanupItem], preselectAdvanced: Bool = UIDefaults.preselectAdvanced) {
        sizes.removeAll(keepingCapacity: true)
        ids.removeAll(keepingCapacity: true)
        bytes = 0
        for item in items {
            sizes[item.id] = item.sizeBytes
            if preselectAdvanced || !item.category.isAdvanced {
                ids.insert(item.id)
                bytes += item.sizeBytes
            }
        }
    }

    /// Returns true when the state actually changed, so callers can skip
    /// publishing a no-op update.
    @discardableResult
    mutating func set(_ id: UUID, selected: Bool) -> Bool {
        if selected {
            guard !ids.contains(id) else { return false }
            ids.insert(id)
            bytes += sizes[id] ?? 0
            return true
        }
        guard ids.remove(id) != nil else { return false }
        bytes -= sizes[id] ?? 0
        return true
    }

    mutating func setAll(_ items: [CleanupItem], selected: Bool) {
        for item in items {
            if selected {
                sizes[item.id] = item.sizeBytes
            }
            _ = set(item.id, selected: selected)
        }
    }

    func isSelected(_ id: UUID) -> Bool { ids.contains(id) }

    func selectedItems(in items: [CleanupItem]) -> [CleanupItem] {
        items.filter { ids.contains($0.id) }
    }
}

/// Search over names, paths, warnings and discipline groups. Folding is case-
/// and diacritic-insensitive; multiple words are ANDed, so "web solana" narrows
/// the list instead of widening it.
enum SearchQuery {
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                     locale: .current)
    }

    static func tokens(_ rawQuery: String) -> [String] {
        fold(rawQuery).split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    static func matches(_ item: CleanupItem, _ rawQuery: String) -> Bool {
        let tokens = tokens(rawQuery)
        guard !tokens.isEmpty else { return true }
        let haystack = fold(item.searchHaystack)
        return tokens.allSatisfy { haystack.contains($0) }
    }
}

extension CleanupItem {
    /// Everything a row can be found by: the visible title, the path/command,
    /// the warning, the discipline group in both languages, plus the catalog
    /// keywords passed at scan time.
    var searchHaystack: String {
        var parts: [String] = [title, detail, category.title, category.rawValue]
        if let platform {
            parts.append(platform.title)
            parts.append(platform.englishTitle)
            parts.append(platform.chipTitle)
            parts.append(platform.rawValue)
        }
        if let warning {
            parts.append(warning)
        }
        parts.append(contentsOf: keywords)
        return parts.joined(separator: " ")
    }
}

extension SearchQuery {
    /// Catalog entries a search term names, whether or not their cache exists
    /// on this machine. The empty state uses it to answer "Terraform is
    /// supported, but there is no cache here" instead of a bare "nothing
    /// matches", which made the catalog look smaller than it is.
    static func matchingSpecs(_ rawQuery: String) -> [ToolCacheSpec] {
        let tokens = tokens(rawQuery)
        guard !tokens.isEmpty else { return [] }
        return ToolCaches.specs.filter { spec in
            let haystack = fold([spec.titleRu, spec.titleEn, spec.relativePath,
                                 spec.platform.title, spec.platform.englishTitle,
                                 spec.platform.rawValue].joined(separator: " "))
            return tokens.allSatisfy { haystack.contains($0) }
        }
    }
}

/// Every tool the app knows how to detect is either in the generated catalog or
/// has a dedicated scanner. `--self-test` fails when a CLI installed on this
/// machine is in neither list: that is how a missing Terraform/Prisma entry is
/// caught instead of being discovered by a user.
enum ToolCoverage {
    enum Coverage: Sendable {
        /// At least one catalog spec path must contain one of these fragments.
        case catalog([String])
        /// Handled by a dedicated scanner in ScanEngine (commands, Docker, ...).
        case scanner(String)
    }

    struct Tool: Sendable {
        let cli: String
        let coverage: Coverage
    }

    static let tools: [Tool] = [
        Tool(cli: "npm", coverage: .catalog([".npm/"])),
        Tool(cli: "yarn", coverage: .catalog(["caches/yarn", "yarn/berry"])),
        Tool(cli: "pnpm", coverage: .scanner("pnpm store prune")),
        Tool(cli: "bun", coverage: .catalog(["caches/bun"])),
        Tool(cli: "deno", coverage: .catalog(["caches/deno"])),
        Tool(cli: "cargo", coverage: .catalog([".cargo/"])),
        Tool(cli: "rustc", coverage: .catalog([".cargo/"])),
        Tool(cli: "go", coverage: .catalog(["go/pkg/mod"])),
        Tool(cli: "swift", coverage: .catalog(["swift.swiftpm", "deriveddata"])),
        Tool(cli: "xcodebuild", coverage: .catalog(["deriveddata", "devicesupport"])),
        Tool(cli: "pod", coverage: .catalog(["cocoapods"])),
        Tool(cli: "composer", coverage: .catalog(["composer"])),
        Tool(cli: "bundle", coverage: .catalog([".bundle/cache"])),
        Tool(cli: "port", coverage: .scanner("port -q clean --all installed")),
        Tool(cli: "brew", coverage: .scanner("brew cleanup -s")),
        Tool(cli: "java", coverage: .catalog([".m2/", "coursier", "ivy2"])),
        Tool(cli: "mvn", coverage: .catalog([".m2/"])),
        Tool(cli: "python3", coverage: .catalog(["caches/pip"])),
        Tool(cli: "pip3", coverage: .catalog(["caches/pip"])),
        Tool(cli: "poetry", coverage: .catalog(["pypoetry"])),
        Tool(cli: "uv", coverage: .scanner("uv cache clean")),
        Tool(cli: "docker", coverage: .scanner("docker builder prune")),
        Tool(cli: "aws", coverage: .catalog([".aws/"])),
        Tool(cli: "gcloud", coverage: .catalog(["gcloud"])),
        Tool(cli: "az", coverage: .catalog(["azure"])),
        Tool(cli: "pulumi", coverage: .catalog([".pulumi/"])),
        Tool(cli: "terraform", coverage: .catalog([".terraform.d/"])),
        Tool(cli: "tofu", coverage: .catalog([".terraform.d/"])),
        Tool(cli: "helm", coverage: .catalog(["helm/repository"])),
        Tool(cli: "kubectl", coverage: .catalog([".kube/"])),
        Tool(cli: "supabase", coverage: .catalog([".supabase/"])),
        Tool(cli: "wrangler", coverage: .catalog(["wrangler"])),
        Tool(cli: "forge", coverage: .catalog([".foundry"])),
        Tool(cli: "solana", coverage: .catalog(["solana"])),
        Tool(cli: "anchor", coverage: .catalog([".avm"])),
        Tool(cli: "gradle", coverage: .catalog([".gradle/"])),
        Tool(cli: "flutter", coverage: .catalog([".pub-cache"])),
        Tool(cli: "dart", coverage: .catalog([".pub-cache"])),
        Tool(cli: "gh", coverage: .catalog([".cache/gh"])),
        Tool(cli: "nix", coverage: .catalog(["cache/nix"])),
        Tool(cli: "bazel", coverage: .catalog(["bazel"])),
        Tool(cli: "bazelisk", coverage: .catalog(["bazelisk"])),
        Tool(cli: "conan", coverage: .catalog(["conan2"])),
        Tool(cli: "vcpkg", coverage: .catalog(["vcpkg"])),
        Tool(cli: "dotnet", coverage: .catalog(["nuget"])),
        Tool(cli: "zig", coverage: .catalog(["cache/zig"])),
        Tool(cli: "platformio", coverage: .catalog(["platformio"])),
        Tool(cli: "pio", coverage: .catalog(["platformio"])),
        Tool(cli: "idf.py", coverage: .catalog(["espressif"])),
        Tool(cli: "arduino-cli", coverage: .catalog(["arduino"])),
        Tool(cli: "tinygo", coverage: .catalog(["tinygo"])),
        Tool(cli: "mix", coverage: .catalog([".hex/", "rebar3"])),
        Tool(cli: "rebar3", coverage: .catalog(["rebar3"])),
        Tool(cli: "sbt", coverage: .catalog([".sbt/"])),
        Tool(cli: "scala", coverage: .catalog(["coursier", ".sbt/", "ivy2"])),
        Tool(cli: "ollama", coverage: .catalog([".ollama/"])),
        Tool(cli: "lms", coverage: .catalog(["lmstudio"])),
    ]

    /// Empty when every installed CLI maps to a catalog entry or a dedicated
    /// scanner. The message names the CLI and the accepted path fragments.
    static func coverageIssues(installed: (String) -> Bool) -> [String] {
        let paths = ToolCaches.specs.map { $0.relativePath.lowercased() }
        var issues: [String] = []
        for tool in tools where installed(tool.cli) {
            guard case let .catalog(fragments) = tool.coverage else { continue }
            let covered = fragments.contains { fragment in
                paths.contains { $0.contains(fragment) }
            }
            if !covered {
                issues.append("\(tool.cli): no catalog entry matching \(fragments)")
            }
        }
        return issues
    }
}

/// The list the window shows: search first, then the advanced-category switch.
/// Kept as plain functions so the headless self-test checks exactly the rows the
/// UI renders.
enum CleanupFilters {
    static func matching(_ items: [CleanupItem], query: String) -> [CleanupItem] {
        guard !SearchQuery.tokens(query).isEmpty else { return items }
        return items.filter { SearchQuery.matches($0, query) }
    }

    static func visible(_ items: [CleanupItem], query: String, showAdvanced: Bool) -> [CleanupItem] {
        let matched = matching(items, query: query)
        return showAdvanced ? matched : matched.filter { !$0.category.isAdvanced }
    }

    static func safe(_ items: [CleanupItem]) -> [CleanupItem] {
        items.filter { !$0.category.isAdvanced }
    }

    static func advanced(_ items: [CleanupItem]) -> [CleanupItem] {
        items.filter { $0.category.isAdvanced }
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

    /// Brand glyph from the catalog rules, platform generic as a last resort.
    var glyph: ToolGlyph {
        ToolBrand.look(for: self) ?? ToolBrand.generic(for: platform)
    }

    /// A path with `*` in it, e.g. `~/.gem/ruby/*/cache`.
    var isPattern: Bool { relativePath.contains("*") }

    /// The deepest directory before the first wildcard component: the base the
    /// allowlist may safely open up, and the starting point of the expansion.
    var patternBaseURL: URL {
        let components = relativePath.split(separator: "/").map(String.init)
        let index = components.firstIndex { $0.contains("*") } ?? components.count
        let base = components.prefix(index).joined(separator: "/")
        if relativePath.hasPrefix("/") {
            return URL(fileURLWithPath: "/" + base)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(base)
    }

    /// Concrete paths for this spec on disk. Non-pattern specs return their
    /// single URL whether or not it exists; callers still check existence.
    func matchingURLs() -> [URL] {
        guard isPattern else { return [url] }
        let components = relativePath.split(separator: "/").map(String.init)
        let firstPattern = components.firstIndex { $0.contains("*") } ?? components.count
        var candidates = [patternBaseURL]
        for component in components[firstPattern...] {
            var next: [URL] = []
            for base in candidates {
                if component.contains("*") {
                    let entries = (try? FileManager.default.contentsOfDirectory(
                        at: base, includingPropertiesForKeys: nil)) ?? []
                    for entry in entries where Glob.matches(component, entry.lastPathComponent) {
                        next.append(entry)
                    }
                } else {
                    let candidate = base.appendingPathComponent(component)
                    if FileManager.default.fileExists(atPath: candidate.path) {
                        next.append(candidate)
                    }
                }
            }
            candidates = next
        }
        return candidates
    }
}

/// Minimal glob support for catalog paths: only `*` inside a path component,
/// used where a cache lives under a versioned directory
/// (`~/.gem/ruby/*/cache`). Kept here so scanning, the allowlist and `--self-test`
/// all agree on what a pattern matches.
enum Glob {
    static func matches(_ pattern: String, _ name: String) -> Bool {
        let parts = pattern.split(separator: "*", omittingEmptySubsequences: false).map(String.init)
        if parts.count == 1 { return pattern == name }
        var rest = Substring(name)
        if let first = parts.first, !first.isEmpty {
            guard rest.hasPrefix(first) else { return false }
            rest = rest.dropFirst(first.count)
        }
        for part in parts.dropFirst().dropLast() where !part.isEmpty {
            guard let range = rest.range(of: part) else { return false }
            rest = rest[range.upperBound...]
        }
        if let last = parts.last, !last.isEmpty {
            guard rest.hasSuffix(last), rest.count >= last.count else { return false }
        }
        return true
    }
}

/// Caches the app cleans through a dedicated scanner (a command, multi-path
/// logic, or a runtime check) rather than a catalog spec. They are part of the
/// supported surface, so the README documents them next to the catalog: "uv" or
/// "npm" missing from the generated table used to look like missing support.
enum ScannerCaches {
    struct Entry: Sendable {
        let titleEn: String
        let pathsEn: String
        let howEn: String
    }

    static let entries: [Entry] = [
        Entry(titleEn: "npm", pathsEn: "~/.npm/_cacache",
              howEn: "npm cache clean --force"),
        Entry(titleEn: "pnpm", pathsEn: "~/Library/pnpm/store/v*, ~/.local/share/pnpm/store/v*",
              howEn: "pnpm store prune + removal of stale store versions"),
        Entry(titleEn: "bun", pathsEn: "~/.bun/install/cache",
              howEn: "bun pm cache rm"),
        Entry(titleEn: "uv", pathsEn: "~/.cache/uv",
              howEn: "uv cache clean --force"),
        Entry(titleEn: "Docker", pathsEn: "build cache, dangling images",
              howEn: "docker builder prune --filter until=24h; docker image prune -f"),
        Entry(titleEn: "Homebrew", pathsEn: "~/Library/Caches/Homebrew",
              howEn: "brew cleanup -s --prune=all"),
        Entry(titleEn: "MacPorts", pathsEn: "/opt/local/var/macports/build, distfiles",
              howEn: "port -q clean --all installed (asks for the admin password)"),
        Entry(titleEn: "IntelliJ IDEA", pathsEn: "~/Library/Caches/JetBrains/IntelliJIdea*",
              howEn: "removes caches of versions that are not installed"),
        Entry(titleEn: "nvim / jdtls", pathsEn: "~/.cache/nvim/jdtls",
              howEn: "remove"),
        Entry(titleEn: "Telegram", pathsEn: "per-account media cache",
              howEn: "remove; messages stay"),
        Entry(titleEn: "WhatsApp", pathsEn: "MediaCache and network cache",
              howEn: "remove; messages stay"),
        Entry(titleEn: "iOS simulators", pathsEn: "simulators missing from Xcode",
              howEn: "xcrun simctl delete unavailable"),
        Entry(titleEn: "/private/tmp", pathsEn: "scratch older than 14 days",
              howEn: "remove"),
    ]
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
        make(".cache/node-gyp", "Node: заголовки node-gyp (Linux-путь)", "Node: node-gyp headers (Linux path)", .web),
        make("Library/Caches/node-gyp", "Node: заголовки node-gyp", "Node: node-gyp headers", .web),
        make("Library/Caches/bun", "bun: кэш компиляции", "bun: compile cache", .web),
        make(".cache/prisma", "Prisma: движки и кэш", "Prisma: engines and cache", .web),
        make(".cache/firebase", "Firebase CLI: кэш", "Firebase CLI: cache", .web),
        make("Library/Caches/deno", "Deno: кэш модулей", "Deno: module cache", .web),
        make("Library/Caches/typescript", "TypeScript: кэш сервера", "TypeScript: server cache", .web),
        make("Library/Caches/Cypress", "Cypress: бинарники и кэш", "Cypress: binaries and cache", .web),
        make(".cache/puppeteer", "Puppeteer: браузеры", "Puppeteer: browsers", .web),
        make(".cache/selenium", "Selenium: драйверы и браузеры", "Selenium: drivers and browsers", .web),
        make("Library/Caches/ms-playwright", "Playwright: браузеры", "Playwright: browsers", .web,
             advanced: true, warning: ("Браузеры скачаются заново", "Browsers will be re-downloaded")),
        make("Library/Caches/composer", "PHP: Composer cache", "PHP: Composer cache", .web),
        make(".bundle/cache", "Ruby: Bundler cache", "Ruby: Bundler cache", .web),
        make(".gem/ruby/*/cache", "Ruby: кэш скачанных gem'ов", "Ruby: downloaded gem cache", .web),
        make(".gem/specs", "Ruby: кэш метаданных gem'ов", "Ruby: gem metadata cache", .web),
        make(".rvm/archives", "Ruby: RVM архивы", "Ruby: RVM archives", .web,
             advanced: true, warning: ("Архивы скачаются заново", "Archives will be re-downloaded")),
        make(".hex/packages", "Elixir: Hex packages", "Elixir: Hex packages", .web),
        make(".cache/rebar3", "Erlang: rebar3 cache", "Erlang: rebar3 cache", .web),

        // MARK: Mobile

        make(".gradle/caches", "Gradle: кэш зависимостей", "Gradle: dependency caches", .mobile,
             advanced: true, warning: ("Следующая сборка будет дольше", "The next build will be slower")),
        make(".gradle/wrapper/dists", "Gradle: wrapper distributions", "Gradle: wrapper distributions", .mobile),
        make(".android/cache", "Android: SDK cache", "Android: SDK cache", .mobile),
        make("Library/Caches/Google/AndroidStudio*", "Android Studio: кэши IDE", "Android Studio: IDE caches", .mobile),
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
        make("Library/Caches/com.apple.dt.Xcode", "Xcode: кэши IDE", "Xcode: IDE caches", .mobile,
             advanced: true, warning: ("Xcode пересоздаст кэши", "Xcode recreates the caches")),

        // MARK: Desktop & native languages

        make(".cargo/registry/index", "Rust: индекс реестра", "Rust: registry index", .desktop),
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
        make("Library/Application Support/Godot/export_templates", "Godot: шаблоны экспорта", "Godot: export templates", .desktop,
             advanced: true, warning: ("Шаблоны скачаются заново", "Templates will be re-downloaded")),
        make("Library/Application Support/Epic/UnrealEngine/Common/DerivedDataCache",
             "Unreal Engine: DerivedDataCache", "Unreal Engine: DerivedDataCache", .desktop,
             advanced: true, warning: ("Шейдеры пересоберутся при следующем запуске", "Shaders are rebuilt on the next launch")),
        make(".cache/zig", "Zig: cache", "Zig: cache", .desktop),
        make(".cache/sccache", "Rust: sccache", "Rust: sccache", .desktop),
        make(".rustup/downloads", "Rust: скачанные тулчейны", "Rust: downloaded toolchains", .desktop),
        make(".rustup/tmp", "Rust: временные файлы rustup", "Rust: rustup temp files", .desktop),
        make(".cache/vscode-ripgrep", "VS Code: кэш ripgrep", "VS Code: ripgrep cache", .desktop),
        make(".cache/github-copilot", "GitHub Copilot: кэш", "GitHub Copilot: cache", .desktop),
        make("Library/Application Support/Code/Cache", "VS Code: cache", "VS Code: cache", .desktop),
        make("Library/Application Support/Code/CachedData", "VS Code: cached data", "VS Code: cached data", .desktop),
        make("Library/Application Support/Code/GPUCache", "VS Code: GPU cache", "VS Code: GPU cache", .desktop),
        make("Library/Application Support/Code/CachedExtensionVSIXs", "VS Code: кэш VSIX расширений", "VS Code: cached extension VSIX", .desktop),
        make("Library/Application Support/Code - Insiders/Cache", "VS Code Insiders: cache", "VS Code Insiders: cache", .desktop),
        make("Library/Application Support/Cursor/Cache", "Cursor: cache", "Cursor: cache", .desktop),
        make("Library/Application Support/Cursor/CachedData", "Cursor: cached data", "Cursor: cached data", .desktop),
        make("Library/Application Support/Cursor/GPUCache", "Cursor: GPU cache", "Cursor: GPU cache", .desktop),
        make("Library/Application Support/Windsurf/Cache", "Windsurf: cache", "Windsurf: cache", .desktop),
        make("Library/Application Support/Windsurf/CachedData", "Windsurf: cached data", "Windsurf: cached data", .desktop),
        make("Library/Application Support/Antigravity/Cache", "Antigravity: cache", "Antigravity: cache", .desktop),
        make("Library/Application Support/Antigravity/CachedData", "Antigravity: cached data", "Antigravity: cached data", .desktop),
        make("Library/Caches/Zed", "Zed: кэш редактора", "Zed: editor cache", .desktop),

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
        make(".cache/jax", "JAX: кэш компиляции", "JAX: compilation cache", .other),
        make(".keras", "Keras: скачанные модели", "Keras: downloaded models", .other,
             advanced: true, warning: ("Модели скачаются заново", "Models will be re-downloaded")),
        make(".nv/ComputeCache", "CUDA: кэш компиляции", "CUDA: compute cache", .other),
        make(".triton/cache", "Triton: кэш ядер", "Triton: kernel cache", .other),
        make(".cache/jupyter", "Jupyter: кэш", "Jupyter: cache", .other),
        make(".cache/huggingface/datasets", "Hugging Face: датасеты", "Hugging Face: datasets", .other,
             advanced: true, warning: ("Датасеты скачаются заново", "Datasets will be re-downloaded")),
        make(".cache/huggingface", "Hugging Face: модели", "Hugging Face: models", .other,
             advanced: true, warning: ("Модели скачаются заново", "Models will be re-downloaded")),
        make(".ollama/models", "Ollama: модели", "Ollama: models", .other,
             advanced: true, warning: ("Модели скачаются заново", "Models will be re-downloaded")),
        make(".lmstudio/models", "LM Studio: модели", "LM Studio: models", .other,
             advanced: true, warning: ("Модели скачаются заново", "Models will be re-downloaded")),
        make(".cache/torch", "PyTorch: кэш моделей", "PyTorch: model cache", .other,
             advanced: true, warning: ("Веса скачаются заново", "Weights will be re-downloaded")),
        make(".julia/compiled", "Julia: скомпилированный код", "Julia: compiled code", .other),
        make(".julia/packages", "Julia: пакеты", "Julia: packages", .other,
             advanced: true, warning: ("Пакеты скачаются заново", "Packages will be re-downloaded")),
        make(".oh-my-zsh/cache", "Oh My Zsh: кэш плагинов", "Oh My Zsh: plugin cache", .other),
        make(".cache/whisper", "Whisper: модели", "Whisper: models", .other,
             advanced: true, warning: ("Модели скачаются заново", "Models will be re-downloaded")),
        make("Library/Caches/Coursier/v1", "JVM: Coursier cache", "JVM: Coursier cache", .other),
        make(".sbt/boot", "JVM: sbt boot (Spark, Scala)", "JVM: sbt boot (Spark, Scala)", .other),
        make(".sbt/launchers", "JVM: sbt launchers", "JVM: sbt launchers", .other,
             advanced: true, warning: ("Лаунчеры скачаются заново", "Launchers will be re-downloaded")),
        make(".gradle/daemon", "Gradle: логи и состояние демона", "Gradle: daemon logs and state", .other),
        make(".ivy2/cache", "JVM: Ivy cache (sbt, Spark)", "JVM: Ivy cache (sbt, Spark)", .other),
        make(".m2/repository", "JVM: Maven local repo (Java, Spark)", "JVM: Maven local repo (Java, Spark)", .other,
             advanced: true, warning: ("Артефакты скачаются заново", "Artifacts will be re-downloaded")),
        make(".cache/nix", "Nix: кэш", "Nix: cache", .other),
        make(".ivy2/jars", "Scala/Java: ivy jars", "Scala/Java: ivy jars", .other,
             advanced: true, warning: ("Артефакты скачаются заново", "Artifacts will be re-downloaded")),
        make(".cache/pkg", "pkg: кэш бинарников", "pkg: binary cache", .other),

        // MARK: Cloud & infrastructure

        make(".aws/cli/cache", "AWS CLI: кэш учётных данных", "AWS CLI: credential cache", .cloud),
        make(".aws/sso/cache", "AWS CLI: кэш SSO-токенов", "AWS CLI: SSO token cache", .cloud,
             advanced: true, warning: ("Потребуется `aws sso login` заново", "`aws sso login` is required again")),
        make(".config/gcloud/logs", "GCP: логи gcloud", "GCP: gcloud logs", .cloud),
        make(".azure/logs", "Azure CLI: логи", "Azure CLI: logs", .cloud),
        make(".pulumi/plugins", "Pulumi: плагины провайдеров", "Pulumi: provider plugins", .cloud,
             advanced: true, warning: ("Плагины скачаются при следующем `pulumi up`", "Plugins download on the next `pulumi up`")),
        make(".pulumi/logs", "Pulumi: логи", "Pulumi: logs", .cloud),
        make(".supabase/artifacts", "Supabase: скачанные артефакты", "Supabase: downloaded artifacts", .cloud),
        make(".supabase/bin", "Supabase: скачанные бинарники", "Supabase: downloaded binaries", .cloud,
             advanced: true, warning: ("Бинарники скачаются при следующем `supabase start`", "Binaries download on the next `supabase start`")),
        make(".supabase/traces", "Supabase: трейсы CLI", "Supabase: CLI traces", .cloud),
        make(".wrangler/cache", "Cloudflare Wrangler: кэш", "Cloudflare Wrangler: cache", .cloud),
        make(".terraform.d/plugin-cache", "Terraform: plugin cache", "Terraform: plugin cache", .cloud),
        make(".terraform.d/checkpoint_cache", "Terraform: кэш проверки обновлений", "Terraform: update-check cache", .cloud),
        make(".cache/gh", "GitHub CLI: кэш", "GitHub CLI: cache", .cloud),
        make("Library/Caches/helm/repository", "Helm: кэш чартов", "Helm: chart cache", .cloud),
        make(".kube/cache", "kubectl: кэш discovery", "kubectl: discovery cache", .cloud),
        make(".kube/http-cache", "kubectl: HTTP-кэш", "kubectl: HTTP cache", .cloud),
        make(".minikube/cache", "minikube: скачанные образы и бинарники", "minikube: cached images and binaries", .cloud),
        make(".ansible/tmp", "Ansible: временные файлы", "Ansible: temp files", .cloud),
        make(".vagrant.d/boxes", "Vagrant: скачанные boxes", "Vagrant: downloaded boxes", .cloud,
             advanced: true, warning: ("Boxes скачаются заново (`vagrant box add`)", "Boxes are re-downloaded (`vagrant box add`)")),

        // MARK: Web3 & blockchain

        make(".foundry/cache", "Foundry: кэш forge", "Foundry: forge cache", .web3),
        make(".svm", "Solidity: версии solc (svm)", "Solidity: solc versions (svm)", .web3,
             advanced: true, warning: ("solc скачается при следующей сборке", "solc downloads on the next build")),
        make(".cache/solana", "Solana: кэш сборки", "Solana: build cache", .web3),
        make(".avm", "Anchor: версии AVM", "Anchor: AVM versions", .web3,
             advanced: true, warning: ("Anchor переустановит тулчейн при следующей сборке", "Anchor reinstalls the toolchain on the next build")),
        make(".solc-select", "solc-select: версии компилятора", "solc-select: compiler versions", .web3,
             advanced: true, warning: ("Компиляторы скачаются заново", "Compilers will be re-downloaded")),
        make(".solcx", "py-solc-x: версии компилятора", "py-solc-x: compiler versions", .web3,
             advanced: true, warning: ("Компиляторы скачаются заново", "Compilers will be re-downloaded")),
        make("Library/Caches/hardhat-nodejs", "Hardhat: кэш компиляторов", "Hardhat: compilers cache", .web3),
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
//
// Disk sizes use decimal units (GB/MB/KB), the way Finder, `du -h` and the
// drive vendors report them: 1 GB = 1_000_000_000 bytes. Internally every size
// stays in bytes (du -sk output is converted once), so only the presentation
// changes.
func humanBytes(_ bytes: Int64) -> String {
    let value = Double(bytes)
    if bytes >= 1_000_000_000 {
        return String(format: "%.1f %@", value / 1_000_000_000, L("ГБ", "GB"))
    }
    if bytes >= 1_000_000 {
        return String(format: "%.0f %@", value / 1_000_000, L("МБ", "MB"))
    }
    if bytes >= 1_000 {
        return String(format: "%.0f %@", value / 1_000, L("КБ", "KB"))
    }
    return "\(bytes) " + L("Б", "B")
}

func humanPercent(_ fraction: Double) -> String {
    String(format: "%.0f%%", fraction * 100)
}
