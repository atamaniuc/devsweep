import Foundation
import AppKit
import Darwin

/// Pure decision logic for the low-disk alert, deliberately outside the timer
/// and the UI so `--self-test` can prove every branch without a disk or a
/// window. Hysteresis: once an alert has fired it stays silent until free space
/// rises above the threshold plus a 10% band, otherwise a machine that sits
/// just under the threshold would pop an alert on every check tick.
enum DiskAlertRules {
    /// Free space must climb this far above the threshold before the alert is
    /// allowed to fire again.
    static let rearmFactor: Double = 1.1

    static func rearmBytes(thresholdBytes: Int64) -> Int64 {
        Int64(Double(max(thresholdBytes, 0)) * rearmFactor)
    }

    /// True when the alert should fire on this check.
    static func decide(freeBytes: Int64,
                       thresholdBytes: Int64,
                       wasAlerted: Bool,
                       alertsEnabled: Bool) -> Bool {
        guard alertsEnabled, thresholdBytes > 0 else { return false }
        guard !wasAlerted else { return false }
        return freeBytes < thresholdBytes
    }

    /// True once free space has risen above `threshold * 1.1`, clearing the
    /// hysteresis latch so the next low tick can alert again.
    static func shouldRearm(freeBytes: Int64, thresholdBytes: Int64) -> Bool {
        guard thresholdBytes > 0 else { return true }
        return freeBytes >= rearmBytes(thresholdBytes: thresholdBytes)
    }
}

/// Persisted hysteresis latch shared by the in-app monitor and the headless
/// `--disk-check` mode, so the launch agent and the open window do not double
/// alert for the same low-space episode.
enum DiskAlertState {
    static let key = "DevSweep.alerts.wasAlerted"
    /// The time of the last alert, used by the UI to explain itself.
    static let lastAlertKey = "DevSweep.alerts.lastAlertAt"

    static func wasAlerted(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key)
    }

    static func save(_ value: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: key)
    }

    static func recordAlert(in defaults: UserDefaults = .standard) {
        defaults.set(Date().timeIntervalSince1970, forKey: lastAlertKey)
    }
}

enum LaunchAgentStatus: Equatable {
    case notInstalled
    case installed
    case failed(String)

    var isInstalled: Bool { self == .installed }

    var hasFailed: Bool {
        if case .failed = self { return true }
        return false
    }

    var summary: String {
        switch self {
        case .notInstalled:
            return L("не установлен", "not installed")
        case .installed:
            return L("установлен и загружен", "installed and loaded")
        case .failed(let reason):
            return L("ошибка: \(reason)", "failed: \(reason)")
        }
    }
}

/// The background check agent: a per-user LaunchAgent that runs the app with
/// `--disk-check` every N minutes. Installed only when the user flips the
/// toggle — never from `--self-test`, never on launch.
enum LaunchAgent {
    static let label = "com.atamaniuc.devsweep.alert"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static func executableURL() -> URL? {
        Bundle.main.executableURL ?? CommandLine.arguments.first.map { URL(fileURLWithPath: $0) }
    }

    /// On-disk status. Reading it never installs anything.
    static func status() -> LaunchAgentStatus {
        FileManager.default.fileExists(atPath: plistURL.path) ? .installed : .notInstalled
    }

    /// The exact property list the agent would install. Kept pure so the
    /// self-test can validate the real bytes without touching
    /// `~/Library/LaunchAgents`.
    static func plistObject(intervalMinutes: Int, executablePath: String) -> [String: Any] {
        [
            "Label": label,
            "ProgramArguments": [executablePath, "--disk-check"],
            "StartInterval": max(intervalMinutes, 1) * 60,
            "RunAtLoad": false,
            "ProcessType": "Background",
            "LowPriorityIO": true,
        ]
    }

    static func plistData(intervalMinutes: Int, executablePath: String) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: plistObject(intervalMinutes: intervalMinutes,
                                                                         executablePath: executablePath),
                                           format: .xml,
                                           options: 0)
    }

    /// Writes the plist and loads it into the user's `gui` domain. Returns the
    /// resulting status so the Settings window can show failures honestly.
    @discardableResult
    static func install(intervalMinutes: Int) -> LaunchAgentStatus {
        guard let executable = executableURL() else {
            return .failed(L("не найден путь к исполняемому файлу", "app executable path not found"))
        }
        do {
            let data = try plistData(intervalMinutes: intervalMinutes, executablePath: executable.path)
            try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: plistURL, options: .atomic)
        } catch {
            return .failed(error.localizedDescription)
        }
        load()
        return FileManager.default.fileExists(atPath: plistURL.path) ? .installed : .failed(L("plist не записан", "plist was not written"))
    }

    /// Stops the agent (if loaded) and removes its plist.
    @discardableResult
    static func uninstall() -> LaunchAgentStatus {
        bootout()
        try? FileManager.default.removeItem(at: plistURL)
        return status()
    }

    /// Re-installs with the current interval when the user changes it while
    /// background checks are on.
    @discardableResult
    static func refresh(intervalMinutes: Int) -> LaunchAgentStatus {
        guard status().isInstalled else { return .notInstalled }
        return install(intervalMinutes: intervalMinutes)
    }

    // MARK: - launchctl

    private static var domainTarget: String { "gui/\(getuid())" }

    private static func load() {
        // Drop a stale registration first so an interval change takes effect.
        _ = run(["bootout", domainTarget, plistURL.path])
        if run(["bootstrap", domainTarget, plistURL.path]) == 0 { return }
        // macOS 12 and older spell the same operation load/unload.
        _ = run(["load", "-w", plistURL.path])
    }

    private static func bootout() {
        if run(["bootout", domainTarget, plistURL.path]) == 0 { return }
        _ = run(["unload", "-w", plistURL.path])
    }

    @discardableResult
    private static func run(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return -1
        }
        process.waitUntilExit()
        return process.terminationStatus
    }
}

/// Watches free disk space while the app runs and raises the low-disk alert.
/// A repeating timer on the main run loop re-reads `SettingsStore.shared` each
/// tick, so changing the threshold or the interval in Settings applies without
/// a relaunch. The alert itself is a plain `NSAlert`: it activates the app and
/// is reliable in an ad-hoc signed build, unlike a notification permission
/// prompt.
enum DiskAlertMonitor {
    /// The timer wakes up often enough that waking at the configured interval
    /// is accurate to a few seconds; the store's interval still gates the work.
    private static let tickSeconds: TimeInterval = 15

    private static var timer: Timer?
    private static var lastCheck = Date.distantPast
    private static let isHeadlessSelfTest = CommandLine.arguments.contains("--self-test")

    static func start() {
        guard !isHeadlessSelfTest else { return }
        guard timer == nil else { return }
        let timer = Timer(timeInterval: tickSeconds, repeats: true) { _ in
            Task { @MainActor in tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        // First check shortly after launch: an already-low disk should alert
        // without waiting a whole interval.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            Task { @MainActor in tick(force: true) }
        }
    }

    static func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// One check. Re-reads the store, applies hysteresis and raises the alert.
    @MainActor
    static func tick(force: Bool = false) {
        let settings = SettingsStore.shared
        guard settings.alertsEnabled else { return }
        let now = Date()
        let interval = TimeInterval(max(settings.checkIntervalMinutes, 1) * 60)
        guard force || now.timeIntervalSince(lastCheck) >= interval else { return }
        lastCheck = now
        assess()
    }

    /// The decision itself, separated from the timer: the UI can force a check
    /// and `--self-test` never calls it.
    @MainActor
    static func assess() {
        let settings = SettingsStore.shared
        let stats = Disk.volumeStats()
        var wasAlerted = DiskAlertState.wasAlerted()
        if wasAlerted && DiskAlertRules.shouldRearm(freeBytes: stats.free, thresholdBytes: settings.thresholdBytes) {
            DiskAlertState.save(false)
            wasAlerted = false
        }
        let fire = DiskAlertRules.decide(freeBytes: stats.free,
                                         thresholdBytes: settings.thresholdBytes,
                                         wasAlerted: wasAlerted,
                                         alertsEnabled: settings.alertsEnabled)
        guard fire else { return }
        DiskAlertState.save(true)
        DiskAlertState.recordAlert()
        presentAlert(freeBytes: stats.free, totalBytes: stats.total, thresholdBytes: settings.thresholdBytes)
    }

    /// "Test alert" in Settings: the real alert dialog, right now, without
    /// touching the hysteresis latch (a test is not a disk-low episode).
    @MainActor
    static func testAlert() {
        let stats = Disk.volumeStats()
        presentAlert(freeBytes: stats.free,
                     totalBytes: stats.total,
                     thresholdBytes: SettingsStore.shared.thresholdBytes)
    }

    @MainActor
    private static func presentAlert(freeBytes: Int64, totalBytes: Int64, thresholdBytes: Int64) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("Мало места на диске", "Low disk space")

        var lines = [L("Свободно \(humanBytes(freeBytes)) из \(humanBytes(totalBytes)).",
                       "\(humanBytes(freeBytes)) free of \(humanBytes(totalBytes)).")]
        lines.append(L("Порог оповещения: \(humanBytes(thresholdBytes)).",
                       "Alert threshold: \(humanBytes(thresholdBytes))."))
        let canFree = AppModel.shared.hasScanned ? AppModel.shared.selectedBytes : 0
        if canFree > 0 {
            lines.append(L("DevSweep уже нашёл кэшей на \(humanBytes(canFree)) — их можно удалить.",
                           "DevSweep already found \(humanBytes(canFree)) of caches it can remove."))
        } else {
            lines.append(L("Откройте DevSweep, чтобы посмотреть, что можно освободить.",
                           "Open DevSweep to see what can be freed."))
        }
        alert.informativeText = lines.joined(separator: "\n")
        alert.addButton(withTitle: L("Открыть DevSweep", "Open DevSweep"))
        alert.addButton(withTitle: L("Позже", "Later"))

        NSApp.activate(ignoringOtherApps: true)
        bringMainWindowFront()
        NSSound(named: "Basso")?.play()

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            bringMainWindowFront()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @MainActor
    private static func bringMainWindowFront() {
        let windows = NSApp.windows
        let main = windows.first { $0.title == AppVersion.name && $0.isVisible }
            ?? windows.first { $0.title == AppVersion.name }
            ?? windows.first
        main?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Headless mode (run by the launch agent)

    /// `--disk-check`: one decision, one line of output, exit 0. When the
    /// criterion holds it opens the app itself (the launch agent cannot show a
    /// window); with `openAppOnAlert` off it only prints the decision.
    static func runHeadlessCheckAndExit() -> Never {
        let settings = SettingsStore.shared
        let stats = Disk.volumeStats()
        let thresholdBytes = settings.thresholdBytes
        var parts = [
            "disk-check free=\(humanBytes(stats.free))",
            "total=\(humanBytes(stats.total))",
            "threshold=\(humanBytes(thresholdBytes))",
            "interval=\(settings.checkIntervalMinutes)m",
            "alerts=\(settings.alertsEnabled ? "on" : "off")",
        ]
        guard settings.alertsEnabled else {
            parts.append("decision=disabled")
            print(parts.joined(separator: " "))
            exit(0)
        }

        var wasAlerted = DiskAlertState.wasAlerted()
        if wasAlerted && DiskAlertRules.shouldRearm(freeBytes: stats.free, thresholdBytes: thresholdBytes) {
            DiskAlertState.save(false)
            wasAlerted = false
        }
        let fire = DiskAlertRules.decide(freeBytes: stats.free,
                                         thresholdBytes: thresholdBytes,
                                         wasAlerted: wasAlerted,
                                         alertsEnabled: true)
        if fire {
            DiskAlertState.save(true)
            DiskAlertState.recordAlert()
            parts.append("decision=ALERT")
            if settings.openAppOnAlert {
                parts.append("app=\(openAppBundle() ? "opened" : "open-failed")")
            } else {
                parts.append("app=skipped")
            }
        } else {
            parts.append(wasAlerted ? "decision=OK(hysteresis)" : "decision=OK")
        }
        print(parts.joined(separator: " "))
        exit(0)
    }

    private static func openAppBundle() -> Bool {
        let bundle = Bundle.main.bundleURL
        guard bundle.pathExtension == "app" else { return false }
        // `open(_:)` returns synchronously; a short run-loop spin lets
        // LaunchServices finish handing the request over before we exit.
        let opened = NSWorkspace.shared.open(bundle)
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        return opened
    }
}
