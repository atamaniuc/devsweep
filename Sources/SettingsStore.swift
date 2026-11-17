import Foundation
import SwiftUI
import AppKit

/// A named bundle of view preferences — the tags, filters and switches the app
/// starts with. Save the current view as a preset on the Settings tab and pick
/// one as the default; the next launch opens exactly that view.
struct SettingsPreset: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var tags: [String]
    var showAdvanced: Bool
    var dryRun: Bool
    var sortKey: String
    var sortDirection: String
    var searchQuery: String

    init(id: String = UUID().uuidString,
         name: String,
         tags: [String] = [],
         showAdvanced: Bool = true,
         dryRun: Bool = true,
         sortKey: String = SortKey.size.rawValue,
         sortDirection: String = SortDirection.descending.rawValue,
         searchQuery: String = "") {
        self.id = id
        self.name = name
        self.tags = tags
        self.showAdvanced = showAdvanced
        self.dryRun = dryRun
        self.sortKey = sortKey
        self.sortDirection = sortDirection
        self.searchQuery = searchQuery
    }
}

/// User preferences in `UserDefaults`: low-disk alerts and saved presets.
/// `@Published` properties write through on every change, so a toggle is
/// durable the moment it flips and nothing needs an explicit Save button.
///
/// Deliberately not `@MainActor`: `--self-test` constructs stores synchronously
/// from a non-isolated context against an isolated `UserDefaults` suite, and
/// this Swift 5 build has no strict-concurrency enforcement. All window access
/// still happens on the main thread.
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    /// Check intervals the UI offers, in minutes.
    static let intervalOptions = [5, 15, 30, 60]
    /// The alert threshold the user can pick: 1–100 GB.
    static let thresholdRange: ClosedRange<Double> = 1...100

    @Published var alertsEnabled: Bool { didSet { defaults.set(alertsEnabled, forKey: Keys.alertsEnabled) } }
    @Published var thresholdGB: Double {
        didSet {
            let clamped = min(max(thresholdGB, SettingsStore.thresholdRange.lowerBound),
                              SettingsStore.thresholdRange.upperBound)
            if clamped != thresholdGB {
                thresholdGB = clamped
                return
            }
            defaults.set(thresholdGB, forKey: Keys.thresholdGB)
        }
    }
    @Published var checkIntervalMinutes: Int { didSet { defaults.set(checkIntervalMinutes, forKey: Keys.checkInterval) } }
    @Published var openAppOnAlert: Bool { didSet { defaults.set(openAppOnAlert, forKey: Keys.openAppOnAlert) } }
    @Published var backgroundChecks: Bool { didSet { defaults.set(backgroundChecks, forKey: Keys.backgroundChecks) } }
    @Published var presets: [SettingsPreset] { didSet { persistPresets() } }
    @Published var defaultPresetID: String? { didSet { defaults.set(defaultPresetID, forKey: Keys.defaultPresetID) } }

    private let defaults: UserDefaults

    private enum Keys {
        static let alertsEnabled = "DevSweep.alerts.enabled"
        static let thresholdGB = "DevSweep.alerts.thresholdGB"
        static let checkInterval = "DevSweep.alerts.checkIntervalMinutes"
        static let openAppOnAlert = "DevSweep.alerts.openApp"
        static let backgroundChecks = "DevSweep.alerts.background"
        static let presets = "DevSweep.presets"
        static let defaultPresetID = "DevSweep.presets.default"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        alertsEnabled = defaults.object(forKey: Keys.alertsEnabled) as? Bool ?? false
        let storedThreshold = defaults.object(forKey: Keys.thresholdGB) as? Double ?? 10
        thresholdGB = min(max(storedThreshold, SettingsStore.thresholdRange.lowerBound),
                          SettingsStore.thresholdRange.upperBound)
        let interval = defaults.object(forKey: Keys.checkInterval) as? Int ?? 15
        checkIntervalMinutes = SettingsStore.intervalOptions.contains(interval) ? interval : 15
        openAppOnAlert = defaults.object(forKey: Keys.openAppOnAlert) as? Bool ?? true
        backgroundChecks = defaults.object(forKey: Keys.backgroundChecks) as? Bool ?? false
        defaultPresetID = defaults.string(forKey: Keys.defaultPresetID)
        if let data = defaults.data(forKey: Keys.presets),
           let decoded = try? JSONDecoder().decode([SettingsPreset].self, from: data) {
            presets = decoded
        } else {
            presets = []
        }
        // A default that points at a deleted preset would make "the app starts
        // in my default view" quietly false.
        if let id = defaultPresetID, !presets.contains(where: { $0.id == id }) {
            defaultPresetID = nil
        }
    }

    // MARK: - Alerts

    var thresholdBytes: Int64 { Int64(max(thresholdGB, 0.1) * 1_000_000_000) }

    // MARK: - Presets

    func startupPreset() -> SettingsPreset? {
        guard let id = defaultPresetID else { return nil }
        return presets.first { $0.id == id }
    }

    func preset(named name: String) -> SettingsPreset? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return presets.first { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
    }

    func upsertPreset(_ preset: SettingsPreset) {
        if let index = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[index] = preset
        } else {
            presets.append(preset)
        }
    }

    func deletePreset(id: String) {
        presets.removeAll { $0.id == id }
        if defaultPresetID == id { defaultPresetID = nil }
    }

    func setDefaultPreset(_ id: String?) {
        guard let id, presets.contains(where: { $0.id == id }) else {
            defaultPresetID = nil
            return
        }
        defaultPresetID = id
    }

    func isDefault(_ preset: SettingsPreset) -> Bool { defaultPresetID == preset.id }

    private func persistPresets() {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        defaults.set(data, forKey: Keys.presets)
    }
}

/// Opens the standard macOS Settings window (⌘,) without tying the window code
/// to macOS 14's `SettingsLink`.
///
/// The SwiftUI `Settings` scene is opened through the app menu's "Settings…"
/// item, whose action is SwiftUI's own menu callback. `NSApp.sendAction` with
/// `showSettingsWindow:` reports success on macOS 13 but does not create the
/// window, so the reliable route is the same one a user click takes: fire that
/// menu item. The selector calls are kept as fallbacks for older systems.
enum SettingsOpener {
    static func open() {
        NSApp.activate(ignoringOtherApps: true)
        if let (menu, index) = settingsMenuItemLocation() {
            menu.performActionForItem(at: index)
            return
        }
        if NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) { return }
        if NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil) { return }
    }

    /// First menu item whose title is the system's "Settings…"/"Preferences…".
    /// The title is matched in both languages because SwiftUI localizes that
    /// item itself, independently of this app's `L()` choice.
    private static func settingsMenuItemLocation() -> (NSMenu, Int)? {
        let titles = ["Settings…", "Settings...", "Настройки…", "Настройки...",
                      "Preferences…", "Preferences...", "Параметры…", "Параметры..."]
        func find(in menu: NSMenu?) -> (NSMenu, Int)? {
            guard let menu else { return nil }
            for (index, item) in menu.items.enumerated() {
                if titles.contains(item.title) { return (menu, index) }
                if let submenu = item.submenu, let hit = find(in: submenu) { return hit }
            }
            return nil
        }
        return find(in: NSApp.mainMenu)
    }
}
