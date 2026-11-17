import Foundation
import SwiftUI

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
/// Stub: the settings work stream replaces the storage with the full model
/// (alert hysteresis, background checks, preset editing) and builds the
/// Settings window; these names and the persistence contract are kept.
@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var alertsEnabled: Bool { didSet { defaults.set(alertsEnabled, forKey: Keys.alertsEnabled) } }
    @Published var thresholdGB: Double { didSet { defaults.set(thresholdGB, forKey: Keys.thresholdGB) } }
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
        thresholdGB = defaults.object(forKey: Keys.thresholdGB) as? Double ?? 10
        checkIntervalMinutes = defaults.object(forKey: Keys.checkInterval) as? Int ?? 15
        openAppOnAlert = defaults.object(forKey: Keys.openAppOnAlert) as? Bool ?? true
        backgroundChecks = defaults.object(forKey: Keys.backgroundChecks) as? Bool ?? false
        defaultPresetID = defaults.string(forKey: Keys.defaultPresetID)
        if let data = defaults.data(forKey: Keys.presets),
           let decoded = try? JSONDecoder().decode([SettingsPreset].self, from: data) {
            presets = decoded
        } else {
            presets = []
        }
    }

    var thresholdBytes: Int64 { Int64(max(thresholdGB, 0.1) * 1_000_000_000) }

    func startupPreset() -> SettingsPreset? {
        guard let id = defaultPresetID else { return nil }
        return presets.first { $0.id == id }
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

    private func persistPresets() {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        defaults.set(data, forKey: Keys.presets)
    }
}

/// Opens the standard macOS Settings window (⌘,) without tying the window code
/// to macOS 14's `SettingsLink`.
enum SettingsOpener {
    static func open() {}
}

/// Watches free disk space while the app runs and raises the low-disk alert.
/// Stub: the settings work stream starts the timer and shows the alert.
enum DiskAlertMonitor {
    static func start() {}
}

enum SettingsChecks {
    static func all() -> [(String, Bool)] { [] }
}
