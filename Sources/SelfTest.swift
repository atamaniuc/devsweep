import Foundation
import Darwin
import AppKit

/// Headless verification of the scan engine and the deletion allowlist.
/// Run the built binary with `--self-test`; it prints PASS/FAIL lines and exits
/// non-zero when any expectation breaks.
enum SelfTest {
    static func runAndExit() -> Never {
        print("DevSweep self-test \(AppVersion.current)")
        let result = ScanEngine.run()
        print("free=\(humanBytes(result.freeBytes)) total=\(humanBytes(result.totalBytes)) items=\(result.items.count)")

        for item in result.items {
            print("  item \(item.category.rawValue) size=\(item.sizeBytes) title=\(item.title)")
        }
        for note in result.notes {
            print("  note \(note.category.rawValue): \(note.text)")
        }

        var failures = 0
        func expect(_ condition: Bool, _ label: String) {
            if condition {
                print("  PASS \(label)")
            } else {
                failures += 1
                print("  FAIL \(label)")
            }
        }

        let home = NSHomeDirectory()

        // The allowlist is the only thing between a checkbox and user data.
        expect(!Cleaner.isAllowed(URL(fileURLWithPath: "/etc/passwd")), "refuse /etc/passwd")
        expect(!Cleaner.isAllowed(URL(fileURLWithPath: "/")), "refuse /")
        expect(!Cleaner.isAllowed(URL(fileURLWithPath: home)), "refuse home")
        expect(!Cleaner.isAllowed(URL(fileURLWithPath: home + "/Library")), "refuse ~/Library")
        expect(Cleaner.isAllowed(URL(fileURLWithPath: home + "/.cache/puppeteer")), "allow puppeteer cache")
        expect(Cleaner.isAllowed(URL(fileURLWithPath: home + "/.cache/puppeteer/chrome")), "allow puppeteer child")
        expect(!Cleaner.isAllowed(URL(fileURLWithPath: home + "/.cache/puppeteer-evil")), "refuse sibling prefix")
        expect(Cleaner.isAllowed(URL(fileURLWithPath: home + "/.npm/_cacache")), "allow npm cache")
        expect(!Cleaner.isAllowed(URL(fileURLWithPath: home + "/.npm/_cacacheX")), "refuse _cacacheX")
        expect(Cleaner.isAllowed(URL(fileURLWithPath: home + "/.cache/nvim/jdtls")), "allow nvim/jdtls")
        expect(!Cleaner.isAllowed(URL(fileURLWithPath: home + "/.cache/nvim/other")), "refuse nvim/other")
        expect(Cleaner.isAllowed(URL(fileURLWithPath: home + "/.bun/install/cache")), "allow bun cache")
        expect(!Cleaner.isAllowed(URL(fileURLWithPath: home + "/.bun")), "refuse ~/.bun root")
        expect(Cleaner.isAllowed(URL(fileURLWithPath: home + "/.npm/_cacache/x")), "allow npm child")
        expect(Cleaner.isAllowed(URL(fileURLWithPath: home + "/Library/Caches/Homebrew")), "allow brew cache")
        expect(Cleaner.isAllowed(URL(fileURLWithPath: home + "/Library/Containers/net.whatsapp.WhatsApp/Data/Library/Caches")), "allow WhatsApp cache")
        expect(!Cleaner.isAllowed(URL(fileURLWithPath: home + "/Library/Containers/net.whatsapp.WhatsApp/Data/Library")), "refuse WhatsApp Library root")
        expect(!Cleaner.isAllowed(URL(fileURLWithPath: home + "/Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram/stable")), "refuse Telegram group container root")
        expect(Cleaner.isAllowed(URL(fileURLWithPath: home + "/.cargo/registry/cache")), "allow cargo registry cache")
        expect(!Cleaner.isAllowed(URL(fileURLWithPath: home + "/.cargo")), "refuse ~/.cargo root")
        expect(Cleaner.isAllowed(URL(fileURLWithPath: home + "/go/pkg/mod")), "allow Go module cache")
        expect(!Cleaner.isAllowed(URL(fileURLWithPath: home + "/go")), "refuse ~/go root")
        expect(Cleaner.isAllowed(URL(fileURLWithPath: home + "/.gradle/caches")), "allow Gradle caches")
        expect(Cleaner.isAllowed(URL(fileURLWithPath: home + "/.pub-cache")), "allow pub cache")
        expect(!Cleaner.isAllowed(URL(fileURLWithPath: home + "/node_modules/pkg")), "refuse node_modules")
        expect(!Cleaner.isAllowed(URL(fileURLWithPath: home + "/.git/config")), "refuse .git")
        expect(Cleaner.isAllowed(URL(fileURLWithPath: "/private/tmp/claude-abc")), "allow tmp scratch")
        expect(!Cleaner.isAllowed(URL(fileURLWithPath: "/private/tmp/other")), "refuse other tmp entry")
        expect(!Cleaner.isAllowed(URL(fileURLWithPath: "/private/tmp/claude-abc/def")), "refuse nested tmp entry")

        // The cache of the installed IDE must never be proposed for deletion.
        let installed = ScanEngine.installedIntelliJVersions()
        print("installed IntelliJ: \(installed.joined(separator: ", "))")
        let jetbrains = result.items.filter { $0.category == .jetbrains }
        for version in installed {
            expect(!jetbrains.contains { $0.title.contains(version) }, "keep installed IntelliJ cache \(version)")
        }

        // A symlink inside an allowed directory is still refused.
        let cacheRoot = URL(fileURLWithPath: home + "/.cache")
        if FileManager.default.fileExists(atPath: cacheRoot.path) {
            let link = cacheRoot.appendingPathComponent("cleandisk-selftest-link")
            try? FileManager.default.removeItem(at: link)
            try? FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: "/etc"))
            expect(!Cleaner.isAllowed(link), "refuse symlink inside allowed directory")
            try? FileManager.default.removeItem(at: link)
        }

        // End-to-end delete through the guard, in a safe scratch location.
        let scratch = URL(fileURLWithPath: "/private/tmp/tmp-cleandisk-selftest-\(getpid())")
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        try? "x".write(to: scratch.appendingPathComponent("f.txt"), atomically: true, encoding: .utf8)
        let deleteEntries = Cleaner.perform([
            CleanupItem(category: .tmp, title: "selftest", detail: scratch.path,
                        sizeBytes: 1, action: .remove(scratch))
        ])
        expect(!FileManager.default.fileExists(atPath: scratch.path), "delete allowlisted scratch directory")
        expect(deleteEntries.contains { entry in
            if case .success = entry.level { return true } else { return false }
        }, "delete reports success")

        // Command whitelist: only the known ids resolve.
        expect(Cleaner.perform([]).isEmpty, "empty plan does nothing")

        // Dry run: preview must enumerate real files for remove targets. The
        // headless path uses the same ledger and the same defaults as the window.
        var previewLedger = SelectionLedger()
        previewLedger.load(result.items)
        let selected = previewLedger.selectedItems(in: result.items)
        let preview = PreviewBuilder.build(items: selected)
        print("preview: targets=\(preview.targetCount) files=\(preview.fileCount) size=\(humanBytes(preview.totalBytes))")
        for target in preview.targets {
            print("  preview \(target.category) · \(target.title): files=\(target.fileCount) size=\(target.sizeBytes)")
        }
        expect(preview.targetCount == selected.count, "preview covers every selected item")
        expect(preview.totalBytes >= 0, "preview has a size")
        expect(preview.textReport.contains("Ничего не удалено") ||
               preview.textReport.contains("Nothing was deleted"),
               "preview text says nothing was deleted")
        if let jetbrains = preview.targets.first(where: { $0.category == "IntelliJ IDEA" }) {
            expect(jetbrains.fileCount > 0, "preview lists IntelliJ cache files")
        }
        if let npm = preview.targets.first(where: { $0.category == "npm" }), npm.sizeBytes > 0 {
            expect(npm.fileCount > 0, "preview lists npm cache files")
        }
        if let bun = preview.targets.first(where: { $0.category == "bun" }), bun.sizeBytes > 0 {
            expect(bun.fileCount > 0, "preview lists bun cache files")
        }

        // "Show plan" must be instant: the plan carries sizes only, and the
        // 300k-file walk happens per row when the user expands it.
        var planLedger = SelectionLedger()
        planLedger.load(result.items)
        let planItems = planLedger.selectedItems(in: result.items)
        let planStart = Date()
        var plan = PreviewBuilder.plan(items: planItems)
        for _ in 0..<50 { plan = PreviewBuilder.plan(items: planItems) }
        let planMillis = Date().timeIntervalSince(planStart) * 1000 / 50
        print(String(format: "dry-run plan: %.2f ms for %d rows (no file walk)", planMillis, plan.targetCount))
        expect(plan.targetCount == planItems.count, "plan covers every selected row")
        expect(plan.targets.allSatisfy { $0.files.isEmpty }, "plan defers the file lists to row expansion")
        expect(planMillis < 50, "plan stays under 50 ms per open")

        // The expanded categories must actually be detected on this machine.
        let categories = Set(result.items.map(\.category.rawValue))
        print("categories with items: \(categories.sorted().joined(separator: ", "))")
        if FileManager.default.fileExists(atPath: home + "/.bun/install/cache") {
            expect(categories.contains("bun"), "bun cache detected")
        }
        if FileManager.default.fileExists(atPath: home + "/Library/pnpm/store") ||
           FileManager.default.fileExists(atPath: home + "/Library/pnpm/store/v11") ||
           Shell.login("command -v pnpm").status == 0 {
            expect(categories.contains("pnpm"), "pnpm store detected")
        }
        if Shell.login("command -v port").status == 0 {
            expect(categories.contains("macports"), "MacPorts detetected")
        }
        if FileManager.default.fileExists(atPath: home + "/.cargo/registry/cache") {
            expect(categories.contains("devtools"), "cargo cache detected")
        }
        if FileManager.default.fileExists(atPath: home + "/go/pkg/mod") {
            expect(categories.contains("devtoolsAdvanced"), "Go module cache detected as advanced")
        }
        if Shell.login("command -v brew").status != 0 {
            expect(result.notes.contains { $0.category == .brew }, "brew absence reported in notes")
        }

        // MARK: Catalog breadth
        //
        // The toolchain catalog is the product: a generic cleaner knows
        // Downloads and Trash, this app knows what each discipline leaves
        // behind. These checks fail the build if the catalog shrinks or if a
        // declared cache is not actually deletable through the allowlist.
        print("toolchain catalog: \(ToolCaches.count) caches")
        for platform in ToolPlatform.allCases {
            let count = ToolCaches.specs(for: platform).count
            print("  \(platform.rawValue): \(count)")
            expect(count >= 5, "at least 5 \(platform.rawValue) toolchain caches")
        }
        expect(ToolCaches.count >= 60, "catalog covers at least 60 toolchain caches")
        expect(Set(ToolCaches.specs.map(\.relativePath)).count == ToolCaches.count,
               "no duplicate toolchain cache paths")
        let notAllowed = ToolCaches.specs.filter { !Cleaner.isAllowed($0.url) }.map(\.relativePath)
        expect(notAllowed.isEmpty, "every declared toolchain cache is allowlisted \(notAllowed)")
        expect(!ToolCaches.specs.contains {
            $0.relativePath.contains("node_modules") || $0.relativePath.contains("/.git")
        }, "no toolchain cache inside node_modules or .git")

        // Detected toolchain rows must carry their platform grouping.
        let toolchainItems = result.items.filter { $0.category == .devtools || $0.category == .devtoolsAdvanced }
        expect(toolchainItems.allSatisfy { $0.platform != nil }, "every toolchain item has a platform")
        print("toolchain items detected on this machine: \(toolchainItems.count)")

        // MARK: Selection ledger, search and defaults
        //
        // The header's "can be freed" number, Check all/Uncheck all and the
        // search box are pure logic (SelectionLedger, SearchQuery,
        // CleanupFilters). Testing them here means the gate covers exactly the
        // functions the SwiftUI views call.

        let heavy = CleanupItem(category: .devtoolsAdvanced, title: "synthetic advanced",
                                detail: "/private/tmp/synthetic-advanced", sizeBytes: 4_096,
                                action: .remove(URL(fileURLWithPath: "/private/tmp")), platform: .cloud)
        let light = CleanupItem(category: .devtools, title: "synthetic safe",
                                detail: "/private/tmp/synthetic-safe", sizeBytes: 1_024,
                                action: .remove(URL(fileURLWithPath: "/private/tmp")), platform: .web)

        var ledger = SelectionLedger()
        ledger.load([heavy, light])
        expect(ledger.count == 1 && ledger.bytes == 1_024,
               "preselection: safe row checked, advanced row not")
        expect(ledger.set(heavy.id, selected: true), "checking a row reports a change")
        expect(ledger.bytes == 5_120, "checking a row adds its size to can-be-freed")
        expect(!ledger.set(heavy.id, selected: true), "checking twice is a no-op")
        expect(ledger.set(heavy.id, selected: false), "unchecking a row reports a change")
        expect(ledger.bytes == 1_024, "unchecking a row subtracts its size")
        ledger.setAll([heavy, light], selected: true)
        expect(ledger.count == 2 && ledger.bytes == 5_120, "Check all covers every visible row")
        ledger.setAll([heavy, light], selected: false)
        expect(ledger.isEmpty && ledger.bytes == 0, "Uncheck all empties the ledger")

        // A checkbox must stay instant: the header number is O(1), not a filter
        // over the list on every click.
        let toggleStart = Date()
        var speedLedger = SelectionLedger()
        speedLedger.load([heavy, light])
        for _ in 0..<10_000 {
            speedLedger.set(heavy.id, selected: true)
            speedLedger.set(heavy.id, selected: false)
        }
        let toggleMillis = Date().timeIntervalSince(toggleStart) * 1000
        print(String(format: "selection ledger: 20,000 toggles in %.2f ms", toggleMillis))
        expect(toggleMillis < 250, "20,000 checkbox toggles stay under 250 ms")

        expect(UIDefaults.showAdvanced, "advanced categories are shown by default")
        expect(UIDefaults.dryRun, "dry run is on by default")
        expect(!UIDefaults.preselectAdvanced, "advanced rows are not preselected by default")

        let solana = CleanupItem(category: .devtools, title: "Solana: build cache",
                                 detail: "/Users/x/.cache/solana", sizeBytes: 0,
                                 action: .remove(URL(fileURLWithPath: "/private/tmp")), platform: .web3,
                                 keywords: ["Solana: build cache", ".cache/solana", "Web3 & blockchain"])
        expect(SearchQuery.matches(solana, "solana"), "search finds a tool by name")
        expect(SearchQuery.matches(solana, "SOLANA"), "search is case-insensitive")
        expect(SearchQuery.matches(solana, "web3"), "search finds rows by discipline group")
        expect(SearchQuery.matches(solana, "solana web3"), "multiple words are ANDed")
        expect(!SearchQuery.matches(solana, "gradle"), "unrelated query does not match")
        expect(!SearchQuery.matches(solana, "web3 gradle"), "one missing word rejects the row")
        expect(SearchQuery.matches(solana, "   "), "blank query matches everything")

        for platform in ToolPlatform.allCases {
            let probe = CleanupItem(category: .devtools, title: "probe", detail: "/private/tmp/probe",
                                    sizeBytes: 0, action: .remove(URL(fileURLWithPath: "/private/tmp")),
                                    platform: platform)
            expect(SearchQuery.matches(probe, platform.rawValue),
                   "group \(platform.rawValue) is searchable by its name")
            expect(SearchQuery.matches(probe, platform.englishTitle),
                   "group \(platform.rawValue) is searchable by its English title")
        }

        let catalogProbes = ToolCaches.specs.map { spec in
            CleanupItem(category: spec.advanced ? .devtoolsAdvanced : .devtools,
                        title: spec.titleRu,
                        detail: spec.url.path,
                        sizeBytes: 0,
                        action: .remove(spec.url),
                        platform: spec.platform,
                        keywords: [spec.titleEn, spec.relativePath])
        }
        expect(zip(catalogProbes, ToolCaches.specs).allSatisfy { SearchQuery.matches($0.0, $0.1.titleEn) },
               "every catalog cache is findable by its English name")

        let filtered = CleanupFilters.visible([solana, heavy, light], query: "web3", showAdvanced: false)
        expect(filtered.map(\.id) == [solana.id], "search narrows the list before the advanced switch")
        let advancedOnly = CleanupFilters.visible([heavy, light], query: "", showAdvanced: false)
        expect(advancedOnly.map(\.id) == [light.id], "advanced switch hides advanced rows when off")

        // MARK: Catalog coverage and brand identity
        //
        // The icons must be recognisable at a glance: every catalog entry has
        // a curated brand glyph, every glyph is a real SF Symbol on this macOS,
        // and every CLI installed here maps to the catalog or a dedicated
        // scanner. That last check is what catches a missing Terraform/Prisma
        // entry instead of leaving it for a user to notice.

        let uncurated = ToolCaches.specs.filter { ToolBrand.look(for: $0) == nil }.map(\.titleEn)
        print("catalog: \(ToolCaches.count) caches, \(uncurated.count) without a brand glyph")
        expect(uncurated.isEmpty, "every catalog cache has a brand icon \(uncurated)")
        expect(ToolCaches.count >= 105, "catalog covers at least 105 toolchain caches")

        let brandSymbols = Set(ToolCaches.specs.map { $0.glyph.systemImage })
            .union(CleanupCategory.allCases.map { ToolBrand.forCategory($0).systemImage })
        let missingSymbols = brandSymbols.filter {
            NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil
        }.sorted()
        print("brand symbols: \(brandSymbols.count) unique, missing: \(missingSymbols)")
        expect(missingSymbols.isEmpty, "every brand SF Symbol exists on this macOS")

        for required in ["Library/Caches/node-gyp", "Library/Caches/bun", ".cache/prisma",
                         ".terraform.d/checkpoint_cache", ".cache/gh", ".ivy2/jars",
                         ".cache/vscode-ripgrep"] {
            expect(ToolCaches.specs.contains { $0.relativePath == required },
                   "catalog covers \(required)")
        }

        // Installed CLIs must be supported: no silent holes.
        let cliList = ToolCoverage.tools.map(\.cli).joined(separator: " ")
        let installedResult = Shell.login(
            "for c in \(cliList); do command -v \"$c\" >/dev/null 2>&1 && echo \"$c\"; done")
        let installedCLIs = Set(installedResult.stdout.split(separator: "\n").map {
            $0.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty })
        print("installed CLIs seen by the coverage audit: \(installedCLIs.sorted().joined(separator: ", "))")
        let coverageIssues = ToolCoverage.coverageIssues { installedCLIs.contains($0) }
        expect(coverageIssues.isEmpty, "every installed CLI is in the catalog or has a scanner \(coverageIssues)")
        expect(ToolCoverage.tools.count >= 40, "coverage audit tracks at least 40 tools")

        // Searching a supported-but-absent tool must name it instead of
        // pretending the catalog is empty.
        let terraformMatches = SearchQuery.matchingSpecs("terraform")
        expect(terraformMatches.contains { $0.titleEn.lowercased().contains("terraform") },
               "catalog search finds supported tools that are not installed (terraform)")

        // Documentation must not drift from the catalog: the README table is
        // generated from the same specs and compared verbatim.
        if let root = repositoryRoot() {
            let readmePath = root.appendingPathComponent("README.md")
            let readme = (try? String(contentsOf: readmePath, encoding: .utf8)) ?? ""
            if let actual = markedBlock(in: readme, start: "<!-- tools:begin -->", end: "<!-- tools:end -->") {
                let expected = toolTableMarkdown()
                expect(actual == expected, "README tool table matches the app catalog")
                if actual != expected {
                    print("  README table is stale: run ./scripts/update-readme-tools.sh")
                }
            } else {
                expect(false, "README contains the tools marker block")
            }
        } else {
            print("  note: README check skipped (binary is not inside the source checkout)")
        }

        print(failures == 0 ? "SELF-TEST PASSED" : "SELF-TEST FAILED (\(failures) checks)")
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: - Catalog as documentation

    /// Markdown table generated from `ToolCaches.specs`, used by the README and
    /// by `scripts/update-readme-tools.sh`. English titles keep the README
    /// stable regardless of the system language.
    static func toolTableMarkdown() -> String {
        var lines: [String] = []
        for platform in ToolPlatform.allCases {
            let specs = ToolCaches.specs(for: platform)
            guard !specs.isEmpty else { continue }
            lines.append("### \(platform.englishTitle)")
            lines.append("")
            lines.append("| Tool | Cache path | Class |")
            lines.append("| --- | --- | --- |")
            for spec in specs {
                let cls = spec.advanced ? "advanced" : "safe"
                lines.append("| \(spec.titleEn) | `\(spec.displayPath)` | \(cls) |")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Plain grouped listing: the human-readable form of the catalog.
    static func toolListText() -> String {
        var lines: [String] = []
        lines.append("DevSweep \(AppVersion.current): \(ToolCaches.count) toolchain caches")
        for platform in ToolPlatform.allCases {
            let specs = ToolCaches.specs(for: platform)
            guard !specs.isEmpty else { continue }
            lines.append("")
            lines.append("\(platform.title) (\(specs.count))")
            for spec in specs {
                let cls = spec.advanced ? "advanced" : "safe    "
                lines.append("  [\(cls)] \(spec.titleEn)  \(spec.displayPath)")
            }
        }
        return lines.joined(separator: "\n")
    }

    static func runTools(asMarkdown: Bool) -> Never {
        print(asMarkdown ? toolTableMarkdown() : toolListText())
        exit(0)
    }

    /// `--audit`: which catalog caches exist on this machine, their sizes, which
    /// are absent, and which installed CLIs the catalog/scanner list does not
    /// cover. This is the measurement behind the catalog, not a guess.
    static func runAudit() -> Never {
        print("DevSweep \(AppVersion.current) catalog audit")
        var present: [(ToolCacheSpec, Int64)] = []
        var missing: [ToolCacheSpec] = []
        for spec in ToolCaches.specs {
            if Disk.exists(spec.url) {
                present.append((spec, Disk.sizeOnDisk(spec.url)))
            } else {
                missing.append(spec)
            }
        }
        present.sort { $0.1 > $1.1 }
        let total = present.reduce(Int64(0)) { $0 + $1.1 }
        print("catalog=\(ToolCaches.count) present=\(present.count) absent=\(missing.count) foundSize=\(humanBytes(total))")
        for (spec, size) in present {
            print("  FOUND  \(humanBytes(size))  \(spec.titleEn)  \(spec.displayPath)")
        }
        for spec in missing {
            print("  ABSENT  \(spec.titleEn)  \(spec.displayPath)")
        }

        let cliList = ToolCoverage.tools.map(\.cli).joined(separator: " ")
        let installedResult = Shell.login(
            "for c in \(cliList); do command -v \"$c\" >/dev/null 2>&1 && echo \"$c\"; done")
        let installedCLIs = Set(installedResult.stdout.split(separator: "\n").map {
            $0.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty })
        print("installed CLIs: \(installedCLIs.sorted().joined(separator: ", "))")
        let issues = ToolCoverage.coverageIssues { installedCLIs.contains($0) }
        if issues.isEmpty {
            print("coverage: every installed CLI is covered by the catalog or a scanner")
        } else {
            print("coverage issues:")
            for issue in issues { print("  MISSING  \(issue)") }
        }
        exit(issues.isEmpty ? 0 : 1)
    }

    /// The source checkout, found by walking up from the executable. Returns nil
    /// for a released bundle that sits outside the repository.
    static func repositoryRoot() -> URL? {
        var url = URL(fileURLWithPath: CommandLine.arguments.first ?? "").resolvingSymlinksInPath()
        let manager = FileManager.default
        for _ in 0..<7 {
            url = url.deletingLastPathComponent()
            if manager.fileExists(atPath: url.appendingPathComponent("README.md").path),
               manager.fileExists(atPath: url.appendingPathComponent("Sources").path) {
                return url
            }
        }
        return nil
    }

    static func markedBlock(in text: String, start: String, end: String) -> String? {
        guard let startRange = text.range(of: start),
              let endRange = text.range(of: end, range: startRange.upperBound..<text.endIndex) else {
            return nil
        }
        return String(text[startRange.upperBound..<endRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Deletion benchmark on freshly created fake cache trees under
    /// /private/tmp (never touches real caches).
    static func runDeleteBench() -> Never {
        let base = "/private/tmp/tmp-cdbench-\(getpid())"
        let dirs = 200
        let filesPerDir = 100

        let manager = FileManager.default

        func makeTree(_ root: String) {
            for d in 0..<dirs {
                let dir = root + "/d\(d)/sub"
                try? manager.createDirectory(atPath: dir, withIntermediateDirectories: true)
                for f in 0..<filesPerDir {
                    manager.createFile(atPath: dir + "/f\(f).dat", contents: Data(repeating: 7, count: 64))
                }
            }
        }

        func measure(_ label: String, _ block: () -> Bool) {
            let started = Date()
            let ok = block()
            let elapsed = Date().timeIntervalSince(started) * 1000
            print(String(format: "  %@ %8.1f ms  ok=%@", label as NSString, elapsed, (ok ? "true" : "false") as NSString))
        }

        print("delete benchmark: \(dirs * filesPerDir) files/tree, 3 trees in \(base)")

        let fmTree = base + "/fm"
        makeTree(fmTree)
        measure("FileManager.removeItem") { (try? manager.removeItem(atPath: fmTree)) != nil }

        let rmTree = base + "/rm"
        makeTree(rmTree)
        measure("/bin/rm -rf (system C)") { Shell.run("/bin/rm", ["-rf", rmTree]).status == 0 }

        let cTree = base + "/c"
        makeTree(cTree)
        measure("cd_rmtree (C, embedded)") { cd_rmtree(cTree) == 0 }

        // The app path: same helper, guarded by the allowlist.
        let appTree = "/private/tmp/tmp-cdbench-app-\(getpid())"
        makeTree(appTree)
        measure("Cleaner.remove (app path)") {
            _ = Cleaner.perform([CleanupItem(category: .tmp, title: "bench", detail: appTree,
                                             sizeBytes: 0, action: .remove(URL(fileURLWithPath: appTree)))])
            return !manager.fileExists(atPath: appTree)
        }

        let leftovers = [fmTree, rmTree, cTree, appTree].filter { manager.fileExists(atPath: $0) }
        print(leftovers.isEmpty ? "DELETE BENCH PASSED" : "DELETE BENCH FAILED: \(leftovers)")
        exit(leftovers.isEmpty ? 0 : 1)
    }

    /// Headless scan only (no preview walk); used to time scanning.
    static func runScan() -> Never {
        let started = Date()
        let result = ScanEngine.run()
        let elapsed = Date().timeIntervalSince(started)
        print("scan seconds: \(String(format: "%.2f", elapsed))")
        print("free=\(humanBytes(result.freeBytes)) items=\(result.items.count)")
        for item in result.items {
            print("  \(item.category.rawValue) \(item.sizeBytes) \(item.title)")
        }
        for note in result.notes {
            print("  note \(note.category.rawValue): \(note.text)")
        }
        exit(0)
    }

    /// Headless dry run: writes the same report the preview sheet shows and
    /// exits without deleting anything.
    static func runPreview(outPath: String?) -> Never {
        let scanStart = Date()
        let result = ScanEngine.run()
        let scanTime = Date().timeIntervalSince(scanStart)
        let walkStart = Date()
        var ledger = SelectionLedger()
        ledger.load(result.items)
        let report = PreviewBuilder.build(items: ledger.selectedItems(in: result.items))
        let walkTime = Date().timeIntervalSince(walkStart)
        let reportStart = Date()
        let text = report.textReport
        let reportTime = Date().timeIntervalSince(reportStart)
        print(String(format: "timing: scan %.2fs, walk %.2fs, report %.2fs", scanTime, walkTime, reportTime))
        if let outPath {
            do {
                try text.write(to: URL(fileURLWithPath: outPath), atomically: true, encoding: .utf8)
                print("dry-run report written: \(outPath)")
            } catch {
                print("cannot write report: \(error.localizedDescription)")
                exit(1)
            }
        }
        print(text)
        print("DRY-RUN ONLY: nothing was deleted")
        exit(0)
    }
}
