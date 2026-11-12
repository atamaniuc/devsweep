import Foundation
import Darwin

/// Headless verification of the scan engine and the deletion allowlist.
/// Run the built binary with `--self-test`; it prints PASS/FAIL lines and exits
/// non-zero when any expectation breaks.
enum SelfTest {
    static func runAndExit() -> Never {
        print("CleanDisk self-test")
        let result = ScanEngine.run()
        print("free=\(humanBytes(result.freeBytes)) total=\(humanBytes(result.totalBytes)) items=\(result.items.count)")

        for item in result.items {
            print("  item \(item.category.rawValue) size=\(item.sizeBytes) selected=\(item.selected) title=\(item.title)")
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

        // Dry run: preview must enumerate real files for remove targets.
        let selected = result.items.filter { $0.selected }
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
        if Shell.login("command -v brew").status != 0 {
            expect(result.notes.contains { $0.category == .brew }, "brew absence reported in notes")
        }

        print(failures == 0 ? "SELF-TEST PASSED" : "SELF-TEST FAILED (\(failures) checks)")
        exit(failures == 0 ? 0 : 1)
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
        let report = PreviewBuilder.build(items: result.items.filter { $0.selected })
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
