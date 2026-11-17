import SwiftUI
import AppKit

/// The Settings window (⌘,): low-disk alerts and saved view presets.
///
/// Both tabs write straight into `SettingsStore`, so there is no Save button:
/// the monitor re-reads the store on every tick and `AppModel` applies a preset
/// the moment it is picked. Everything here is in-memory and instant.
struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var model: AppModel

    private enum Tab: String {
        case alerts
        case presets
    }

    @State private var tab: Tab = .alerts
    @State private var freeBytes: Int64 = 0
    @State private var totalBytes: Int64 = 0
    @State private var agentStatus: LaunchAgentStatus = LaunchAgent.status()
    @State private var newPresetName = ""
    @State private var savedPresetName: String?

    /// The free-space readout is a cheap `attributesOfFileSystem` call; a slow
    /// poll keeps it honest while the window is open without touching the disk
    /// in the background.
    private let volumeTimer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $tab) {
                alertsTab
                    .tag(Tab.alerts)
                    .tabItem {
                        Label(L("Алерты", "Alerts"), systemImage: "externaldrive.badge.exclamationmark")
                    }
                presetsTab
                    .tag(Tab.presets)
                    .tabItem {
                        Label(L("Пресеты", "Presets"), systemImage: "slider.horizontal.3")
                    }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)

            Divider()
            footer
        }
        // Minimum sizes instead of a fixed frame: macOS restores the Settings
        // window's last frame from defaults, and an old/small restored size must
        // not clip the tabs. The content also stays comfortable when the user
        // resizes the window.
        .frame(minWidth: 620, idealWidth: 660, minHeight: 540, idealHeight: 620)
        .onAppear {
            refreshVolume()
            agentStatus = LaunchAgent.status()
        }
        .onReceive(volumeTimer) { _ in refreshVolume() }
        .onChange(of: settings.alertsEnabled) { enabled in
            guard enabled else { return }
            // Turning the alert on should evaluate right away instead of
            // waiting a whole interval to find an already-low disk.
            Task { @MainActor in DiskAlertMonitor.tick(force: true) }
        }
        .onChange(of: settings.checkIntervalMinutes) { _ in
            guard settings.backgroundChecks else { return }
            agentStatus = LaunchAgent.refresh(intervalMinutes: settings.checkIntervalMinutes)
        }
    }

    // MARK: - Alerts tab

    private var alertsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader(L("Оповещения о месте на диске", "Low-disk alerts"),
                              caption: L("Когда свободного места становится меньше порога, поверх всех окон появляется алерт с предложением открыть DevSweep.",
                                         "When free space drops below the threshold, an alert appears above every window and offers to open DevSweep."))

                card {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: alertsBinding) {
                            Text(L("Оповещать, когда мало места на диске", "Alert when free space is low"))
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .toggleStyle(.switch)

                        if settings.alertsEnabled {
                            Divider()

                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 12) {
                                    Text(L("Порог", "Threshold"))
                                        .font(.system(size: 13, weight: .medium))
                                        .frame(width: 90, alignment: .leading)
                                    Slider(value: $settings.thresholdGB,
                                           in: SettingsStore.thresholdRange,
                                           step: 1)
                                        .accessibilityLabel(L("Порог свободного места в гигабайтах",
                                                              "Free-space threshold in gigabytes"))
                                    Text("\(Int(settings.thresholdGB.rounded())) \(L("ГБ", "GB"))")
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .monospacedDigit()
                                        .frame(width: 66, alignment: .trailing)
                                }

                                HStack(spacing: 12) {
                                    Text(L("Сейчас", "Free now"))
                                        .font(.system(size: 13, weight: .medium))
                                        .frame(width: 90, alignment: .leading)
                                    Label("\(humanBytes(freeBytes)) " + L("свободно из \(humanBytes(totalBytes))",
                                                                          "free of \(humanBytes(totalBytes))"),
                                          systemImage: "internaldrive")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }

                                HStack(spacing: 12) {
                                    Text(L("Проверять", "Check every"))
                                        .font(.system(size: 13, weight: .medium))
                                        .frame(width: 90, alignment: .leading)
                                    Picker("", selection: $settings.checkIntervalMinutes) {
                                        ForEach(SettingsStore.intervalOptions, id: \.self) { minutes in
                                            Text(L("\(minutes) мин", "\(minutes) min")).tag(minutes)
                                        }
                                    }
                                    .labelsHidden()
                                    .pickerStyle(.menu)
                                    .frame(width: 120)
                                    Spacer()
                                }
                            }
                        }
                    }
                }

                card {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: $settings.openAppOnAlert) {
                            Text(L("Открывать DevSweep при срабатывании", "Open DevSweep when the alert fires"))
                                .font(.system(size: 14, weight: .medium))
                        }
                        .toggleStyle(.switch)

                        Divider()

                        Toggle(isOn: backgroundBinding) {
                            Text(L("Проверять в фоне (агент автозапуска)", "Check in background (launch agent)"))
                                .font(.system(size: 14, weight: .medium))
                        }
                        .toggleStyle(.switch)

                        Text(L("Устанавливает ~/Library/LaunchAgents/\(LaunchAgent.label).plist: он запускает DevSweep с флагом --disk-check каждые \(settings.checkIntervalMinutes) мин. Агент только проверяет место и открывает приложение — ничего не удаляется и не сканируется.",
                               "Installs ~/Library/LaunchAgents/\(LaunchAgent.label).plist: it runs DevSweep with --disk-check every \(settings.checkIntervalMinutes) min. The agent only checks free space and opens the app — it deletes and scans nothing."))
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 7) {
                            Circle()
                                .fill(agentStatus.isInstalled ? Color.green : (agentStatus.hasFailed ? Color.red : Color.secondary.opacity(0.5)))
                                .frame(width: 7, height: 7)
                            Text(L("Агент: \(agentStatus.summary)", "Launch agent: \(agentStatus.summary)"))
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(agentStatus.hasFailed ? Color.red : Color.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }

                card {
                    HStack(alignment: .center, spacing: 14) {
                        Button(L("Проверить алерт", "Test alert")) {
                            DiskAlertMonitor.testAlert()
                            refreshVolume()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        Text(L("Показывает настоящий алерт прямо сейчас: так выглядит срабатывание при низком месте.",
                               "Shows the real alert right now, exactly as it appears when space runs low."))
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(18)
        }
    }

    // MARK: - Presets tab

    private var presetsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader(L("Пресеты представления", "View presets"),
                              caption: L("Пресет — это чипы дисциплин, поиск, переключатели «расширенные» и «dry run», а также сортировка. Пресет по умолчанию применяется при следующем запуске.",
                                         "A preset bundles the discipline chips, the search, the advanced/dry-run switches and the sort. The default preset is restored on the next launch."))

                card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L("Сохранить текущий вид", "Save the current view"))
                            .font(.system(size: 14, weight: .semibold))

                        HStack(spacing: 10) {
                            TextField(L("Название пресета", "Preset name"), text: $newPresetName)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 13))
                                .frame(width: 230)
                                .onSubmit { saveCurrentView() }
                            Button(L("Сохранить пресет", "Save current view as preset")) {
                                saveCurrentView()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(trimmedPresetName.isEmpty)
                            Spacer(minLength: 0)
                        }

                        Text(L("Сохраняется именно то, что сейчас в главном окне: чипы + поиск + переключатели + сортировка.",
                               "What is saved is exactly the current main window: chips + search + switches + sort."))
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)

                        if let savedPresetName {
                            Label(L("Сохранено: \(savedPresetName)", "Saved: \(savedPresetName)"),
                                  systemImage: "checkmark.circle.fill")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(.green)
                        }
                    }
                }

                if settings.presets.isEmpty {
                    emptyPresetsState
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(L("Сохранённые пресеты", "Saved presets"))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text("\(settings.presets.count)")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.secondary.opacity(0.12)))
                            Spacer()
                        }
                        ForEach(settings.presets) { preset in
                            presetRow(preset)
                        }
                    }
                }
            }
            .padding(18)
        }
    }

    private var emptyPresetsState: some View {
        VStack(spacing: 8) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text(L("Пока нет пресетов", "No presets yet"))
                .font(.system(size: 15, weight: .semibold))
            Text(L("Настройте чипы и поиск в главном окне, вернитесь сюда и сохраните вид под именем.",
                   "Set the chips and search in the main window, come back here and save the view under a name."))
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.06)))
    }

    private func presetRow(_ preset: SettingsPreset) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    if settings.isDefault(preset) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.yellow)
                    }
                    Text(preset.name)
                        .font(.system(size: 14.5, weight: .semibold))
                }
                if !preset.tags.isEmpty {
                    HStack(spacing: 5) {
                        ForEach(preset.tags.compactMap(PlatformTag.init(rawValue:)), id: \.self) { tag in
                            Text(tag.chipTitle)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                        }
                    }
                }
                Text(summary(for: preset))
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                Button {
                    settings.setDefaultPreset(settings.isDefault(preset) ? nil : preset.id)
                } label: {
                    Image(systemName: settings.isDefault(preset) ? "star.fill" : "star")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(settings.isDefault(preset) ? Color.yellow : Color.secondary)
                }
                .buttonStyle(.borderless)
                .help(L("Сделать пресетом по умолчанию (применяется при запуске)",
                        "Make this the default preset (applied on launch)"))

                Button(L("Применить", "Apply")) {
                    model.applyPreset(preset)
                    savedPresetName = nil
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    settings.deletePreset(id: preset.id)
                    if savedPresetName == preset.name { savedPresetName = nil }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .help(L("Удалить пресет", "Delete preset"))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(settings.isDefault(preset) ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(settings.isDefault(preset) ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.08),
                        lineWidth: 1)
        )
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Text(AppVersion.name)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
            Text("v\(AppVersion.current)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
            Divider().frame(height: 11)
            Text(L("Настройки сохраняются сразу; ничего не удаляется без вашего действия.",
                   "Settings save instantly; nothing is deleted without your action."))
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button("GitHub") {
                NSWorkspace.shared.open(AppVersion.releasesURL)
            }
            .buttonStyle(.link)
            .font(.system(size: 11, design: .monospaced))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
    }

    // MARK: - Bindings

    /// Turning the master switch on evaluates once immediately; the monitor
    /// itself keeps running for the whole session.
    private var alertsBinding: Binding<Bool> {
        Binding(
            get: { settings.alertsEnabled },
            set: { settings.alertsEnabled = $0 }
        )
    }

    /// Installing or removing the launch agent is the only side effect of a
    /// toggle, and it happens exactly when the user flips this switch.
    private var backgroundBinding: Binding<Bool> {
        Binding(
            get: { settings.backgroundChecks },
            set: { enabled in
                settings.backgroundChecks = enabled
                agentStatus = enabled
                    ? LaunchAgent.install(intervalMinutes: settings.checkIntervalMinutes)
                    : LaunchAgent.uninstall()
            }
        )
    }

    // MARK: - Helpers

    private func refreshVolume() {
        let stats = Disk.volumeStats()
        freeBytes = stats.free
        totalBytes = stats.total
    }

    private var trimmedPresetName: String {
        newPresetName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func saveCurrentView() {
        let name = trimmedPresetName
        guard !name.isEmpty else { return }
        var preset = model.currentPreset(named: name)
        // Saving under an existing name updates that preset instead of silently
        // creating a duplicate the user cannot tell apart.
        if let existing = settings.preset(named: name) {
            preset.id = existing.id
        }
        settings.upsertPreset(preset)
        newPresetName = ""
        savedPresetName = name
    }

    private func summary(for preset: SettingsPreset) -> String {
        var parts: [String] = []
        parts.append(preset.showAdvanced ? L("расширенные", "advanced") : L("без расширенных", "no advanced"))
        parts.append(preset.dryRun ? "dry run" : L("реальная очистка", "real clean"))
        let key = SortKey(rawValue: preset.sortKey)?.title ?? preset.sortKey
        let direction = SortDirection(rawValue: preset.sortDirection) == .ascending ? "↑" : "↓"
        parts.append("\(key) \(direction)")
        if !preset.searchQuery.isEmpty {
            parts.append(L("поиск: \(preset.searchQuery)", "search: \(preset.searchQuery)"))
        }
        return parts.joined(separator: " · ")
    }

    private func sectionHeader(_ title: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 19, weight: .bold, design: .rounded))
            Text(caption)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}
