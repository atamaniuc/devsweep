import Foundation

/// Self-test coverage for the Settings work stream: the store round-trip in an
/// isolated `UserDefaults` suite, preset bookkeeping, the pure low-disk alert
/// decision with its hysteresis, and the background agent's path. Nothing here
/// raises a real alert, installs a launch agent or writes the user's own
/// preferences — the whole store is exercised through a throwaway suite.
enum SettingsChecks {
    static func all() -> [(String, Bool)] {
        var checks: [(String, Bool)] = []
        func check(_ condition: Bool, _ label: String) {
            checks.append((label, condition))
        }

        // Snapshot before anything else: the last check proves this file never
        // touched the user's real preferences.
        let standardBefore = standardDevSweepValues()

        let suiteName = "devsweep.selftest.\(UUID().uuidString)"
        guard let suite = UserDefaults(suiteName: suiteName) else {
            return [("isolated UserDefaults suite can be created", false)]
        }
        defer { suite.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: suite)
        check(store.presets.isEmpty, "a fresh store has no presets")
        check(!store.alertsEnabled, "low-disk alerts start off")
        check(store.thresholdGB == 10, "threshold starts at 10 GB")
        check(store.thresholdBytes == 10_000_000_000, "thresholdBytes converts GB to bytes (10 GB)")
        check(store.startupPreset() == nil, "startupPreset is nil without a default")
        check(SettingsStore.intervalOptions == [5, 15, 30, 60], "check intervals are 5/15/30/60 minutes")

        // Alert settings and presets must come back from a freshly built store.
        store.alertsEnabled = true
        store.thresholdGB = 25
        store.checkIntervalMinutes = 30
        store.openAppOnAlert = false
        store.backgroundChecks = true
        let probe = SettingsPreset(name: "probe", tags: ["web", "cloud"],
                                   showAdvanced: false, dryRun: false,
                                   sortKey: "name", sortDirection: "ascending",
                                   searchQuery: "pip")
        store.upsertPreset(probe)
        store.setDefaultPreset(probe.id)
        check(store.thresholdBytes == 25_000_000_000, "thresholdBytes follows the chosen threshold")
        check(store.startupPreset() == probe, "startupPreset returns the selected preset")
        check(store.isDefault(probe), "the chosen preset is marked default")
        check(store.preset(named: "PROBE") == probe, "preset lookup by name is case-insensitive")
        suite.synchronize()

        let recreated = SettingsStore(defaults: UserDefaults(suiteName: suiteName) ?? suite)
        check(recreated.alertsEnabled, "alert master switch survives a store rebuild")
        check(recreated.thresholdGB == 25, "threshold survives a store rebuild")
        check(recreated.checkIntervalMinutes == 30, "check interval survives a store rebuild")
        check(!recreated.openAppOnAlert, "open-app switch survives a store rebuild")
        check(recreated.backgroundChecks, "background switch survives a store rebuild")
        check(recreated.presets == [probe], "saved presets survive a store rebuild")
        check(recreated.defaultPresetID == probe.id, "default preset id survives a store rebuild")
        check(recreated.startupPreset() == probe, "the default preset is the startup preset after a rebuild")
        check(UserDefaults(suiteName: suiteName)?.data(forKey: "DevSweep.presets") != nil,
              "presets are stored as JSON data in the suite")

        // Update-in-place, delete and default cleanup.
        var renamed = probe
        renamed.name = "probe 2"
        recreated.upsertPreset(renamed)
        check(recreated.presets.count == 1 && recreated.presets.first?.name == "probe 2",
              "upsert updates a preset in place")
        recreated.deletePreset(id: renamed.id)
        check(recreated.presets.isEmpty && recreated.defaultPresetID == nil,
              "deleting the default preset clears the default")
        check(recreated.startupPreset() == nil, "deleting the default preset leaves no startup preset")

        // The threshold the UI offers is 1–100 GB and cannot store a value
        // outside it, otherwise a stray drag could disable alerts forever.
        let clampStore = SettingsStore(defaults: suite)
        clampStore.thresholdGB = 0.2
        check(clampStore.thresholdGB == 1, "threshold clamps at 1 GB")
        clampStore.thresholdGB = 500
        check(clampStore.thresholdGB == 100, "threshold clamps at 100 GB")

        // Preset save/load speed: the list is re-encoded on every change, so a
        // laggy encoder would be felt while clicking.
        let timingStore = SettingsStore(defaults: suite)
        let singleStart = DispatchTime.now().uptimeNanoseconds
        timingStore.upsertPreset(SettingsPreset(name: "single"))
        let singleMilliseconds = Double(DispatchTime.now().uptimeNanoseconds - singleStart) / 1_000_000
        let saveStart = DispatchTime.now().uptimeNanoseconds
        for index in 0..<20 {
            timingStore.upsertPreset(SettingsPreset(name: "preset \(index)", tags: ["web"]))
        }
        let batchMilliseconds = Double(DispatchTime.now().uptimeNanoseconds - saveStart) / 1_000_000
        let loadStart = DispatchTime.now().uptimeNanoseconds
        if let data = UserDefaults(suiteName: suiteName)?.data(forKey: "DevSweep.presets") {
            _ = try? JSONDecoder().decode([SettingsPreset].self, from: data)
        }
        let loadMilliseconds = Double(DispatchTime.now().uptimeNanoseconds - loadStart) / 1_000_000
        print(String(format: "  presets: one save %.3f ms, 21 saves %.3f ms, load %.3f ms",
                     singleMilliseconds, batchMilliseconds, loadMilliseconds))
        check(singleMilliseconds < 5, "a single preset save stays fast")
        check(batchMilliseconds < 20, "saving 21 presets stays fast")
        check(loadMilliseconds < 20, "loading 21 presets stays fast")

        // Pure alert decisions: every branch of the hysteresis.
        let threshold = Int64(10_000_000_000) // 10 GB
        check(DiskAlertRules.decide(freeBytes: 5_000_000_000, thresholdBytes: threshold,
                                    wasAlerted: false, alertsEnabled: true),
              "alert fires below the threshold")
        check(!DiskAlertRules.decide(freeBytes: 20_000_000_000, thresholdBytes: threshold,
                                     wasAlerted: false, alertsEnabled: true),
              "alert stays quiet above the threshold")
        check(!DiskAlertRules.decide(freeBytes: 2_000_000_000, thresholdBytes: threshold,
                                     wasAlerted: false, alertsEnabled: false),
              "disabled alerts never fire")
        check(!DiskAlertRules.decide(freeBytes: 2_000_000_000, thresholdBytes: 0,
                                     wasAlerted: false, alertsEnabled: true),
              "a zero threshold never fires")
        check(!DiskAlertRules.decide(freeBytes: 9_000_000_000, thresholdBytes: threshold,
                                     wasAlerted: true, alertsEnabled: true),
              "hysteresis blocks a repeat while free space stays low")
        check(!DiskAlertRules.shouldRearm(freeBytes: 10_500_000_000, thresholdBytes: threshold),
              "hysteresis holds inside the 10% band")
        check(DiskAlertRules.shouldRearm(freeBytes: 11_100_000_000, thresholdBytes: threshold),
              "hysteresis re-arms above threshold * 1.1")
        check(DiskAlertRules.decide(freeBytes: 9_000_000_000, thresholdBytes: threshold,
                                    wasAlerted: false, alertsEnabled: true),
              "a re-armed alert fires on the next low tick")

        // Background agent: the plist generator is validated with the real
        // system parser in /tmp. Nothing is installed into
        // ~/Library/LaunchAgents and launchctl is never called.
        check(LaunchAgent.plistURL.path.hasSuffix("/Library/LaunchAgents/com.atamaniuc.devsweep.alert.plist"),
              "launch agent plist lives in ~/Library/LaunchAgents")
        let plistExisted = FileManager.default.fileExists(atPath: LaunchAgent.plistURL.path)
        let agentExecutable = "/Applications/DevSweep.app/Contents/MacOS/DevSweep"
        do {
            let data = try LaunchAgent.plistData(intervalMinutes: 15, executablePath: agentExecutable)
            check(!data.isEmpty, "launch agent plist data is generated")
            let object = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            check(object?["Label"] as? String == LaunchAgent.label, "launch agent plist has the label")
            check(object?["StartInterval"] as? Int == 900, "launch agent plist checks every 15 minutes")
            check(object?["RunAtLoad"] as? Bool == false, "launch agent does not run at load")
            let arguments = object?["ProgramArguments"] as? [String] ?? []
            check(arguments.count == 2 && arguments[0] == agentExecutable && arguments[1] == "--disk-check",
                  "launch agent plist runs the app with --disk-check")

            let tempURL = URL(fileURLWithPath: "/private/tmp/devsweep-selftest-agent-\(ProcessInfo.processInfo.processIdentifier).plist")
            try data.write(to: tempURL)
            let lint = plutilLint(tempURL)
            print("  launch agent plist: plutil -lint exit=\(lint.status) \(lint.output.trimmingCharacters(in: .whitespacesAndNewlines))")
            check(lint.status == 0 && lint.output.contains("OK"), "launch agent plist passes plutil -lint")
            try? FileManager.default.removeItem(at: tempURL)
            check(!FileManager.default.fileExists(atPath: tempURL.path), "temporary launch agent plist removed")
        } catch {
            check(false, "launch agent plist generation")
        }
        check(FileManager.default.fileExists(atPath: LaunchAgent.plistURL.path) == plistExisted,
              "self-test never writes ~/Library/LaunchAgents")
        check(LaunchAgent.status().isInstalled == plistExisted, "launch agent status reads the real path")
        check(!LaunchAgent.status().hasFailed, "launch agent status is a valid status")

        // The user's real preferences are untouched by the whole self-test.
        check(standardDevSweepValues().isEqual(standardBefore),
              "self-test does not write UserDefaults.standard")

        return checks
    }

    private static func standardDevSweepValues() -> NSDictionary {
        UserDefaults.standard.dictionaryRepresentation()
            .filter { $0.key.hasPrefix("DevSweep.") || $0.key.hasPrefix("NSWindow") }
            as NSDictionary
    }

    /// `plutil -lint` on a generated plist: the same validator that catches a
    /// malformed launch agent before `launchctl` sees it.
    private static func plutilLint(_ url: URL) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/plutil")
        process.arguments = ["-lint", url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (-1, "\(error)")
        }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
