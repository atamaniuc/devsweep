import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension BrandColor {
    var color: Color {
        switch self {
        case .blue: return .blue
        case .purple: return .purple
        case .orange: return .orange
        case .red: return .red
        case .green: return .green
        case .teal: return .teal
        case .indigo: return .indigo
        case .pink: return .pink
        case .yellow: return .yellow
        case .gray: return .secondary
        case .cyan: return .cyan
        case .brown: return .brown
        }
    }
}

struct ContentView: View {
    @StateObject private var model = AppModel()
    @State private var showConfirm = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            actionBar
            Divider()
            searchBar
            Divider()
            content
            Divider()
            logPanel
            footer
        }
        .frame(minWidth: 940, minHeight: 720)
        .background(
            LinearGradient(colors: [Color(nsColor: .windowBackgroundColor),
                                    Color.accentColor.opacity(0.05)],
                           startPoint: .top, endPoint: .bottom)
        )
        .task { await model.scanIfNeeded() }
        .sheet(isPresented: $showConfirm) { confirmation }
        .sheet(item: $model.preview) { report in
            PreviewSheet(report: report) { model.preview = nil }
        }
        .alert(item: $model.lastReport) { report in
            Alert(
                title: Text(report.failed == 0 ? L("Готово", "Done") : L("Готово с ошибками", "Done with errors")),
                message: Text(L("Освобождено \(humanBytes(report.freedBytes)).\nУдалено объектов: \(report.removed), пропущено: \(report.skipped), ошибок: \(report.failed).", "Freed \(humanBytes(report.freedBytes)).\nRemoved: \(report.removed), skipped: \(report.skipped), errors: \(report.failed).")),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(AppVersion.name)
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                        Text("v\(AppVersion.current)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                    }
                    Text(L(AppVersion.taglineRu, AppVersion.taglineEn))
                        .font(.system(size: 16.5, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.82))
                    Text(L("кэш-клинер для разработчиков и инженеров",
                           "the cache cleaner for developers and engineers"))
                        .font(.system(size: 13.5))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 16)
                VStack(alignment: .trailing, spacing: 9) {
                    // Two numbers side by side: how much is free right now, and
                    // how much the current selection would free. The second one is
                    // read from the O(1) selection ledger, so it follows the
                    // checkboxes without re-scanning or re-summing the list.
                    HStack(alignment: .top, spacing: 30) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(L("свободно на диске", "free on disk"))
                                .font(.system(size: 13.5, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text(humanBytes(model.freeBytes))
                                .font(.system(size: 37, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                        }
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(L("можно освободить", "can be freed"))
                                .font(.system(size: 13.5, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text(humanBytes(model.selectedBytes))
                                .font(.system(size: 37, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(model.selectedBytes > 0 ? Color.accentColor : Color.secondary)
                                .animation(.easeOut(duration: 0.12), value: model.selectedBytes)
                        }
                    }
                    .help(L("Сумма отмеченных галочками объектов; обновляется сразу при переключении",
                            "The total of the checked rows; updates immediately as you toggle them"))

                    ProgressView(value: min(max(model.usedFraction, 0), 1))
                        .progressViewStyle(.linear)
                        .frame(width: 290)
                        .tint(model.usedFraction > 0.9 ? .red : .accentColor)
                    HStack(spacing: 6) {
                        Text(L("занято \(humanPercent(model.usedFraction))", "used \(humanPercent(model.usedFraction))"))
                        Text("·")
                        Text(L("выбрано \(model.selectedCount) из \(model.items.count)",
                               "\(model.selectedCount) of \(model.items.count) selected"))
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize()
                }
            }

            // The catalog is broader than what this Mac actually has; say both
            // numbers so a missing tool reads as "nothing to clean here", not
            // as an app that forgot about it.
            HStack(spacing: 6) {
                Text(L("каталог \(ToolCaches.count) кэшей", "catalog of \(ToolCaches.count) caches"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(L("· найдено \(model.items.count) здесь", "· \(model.items.count) found here"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(model.items.isEmpty ? Color.secondary : Color.accentColor)
                Text("·")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                ForEach(ToolPlatform.allCases) { platform in
                    Text("\(platform.chipTitle) \(ToolCaches.specs(for: platform).count)")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.secondary.opacity(0.13)))
                        .fixedSize()
                        .lineLimit(1)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    // MARK: - Action bar

    private var actionBar: some View {
        HStack(spacing: 14) {
            Button {
                Task { await model.scan() }
            } label: {
                Label(L("Сканировать", "Scan"), systemImage: "arrow.clockwise")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.bordered)
            .disabled(model.phase != .idle)

            if model.hasAdvancedItems {
                Toggle(L("Расширенные категории", "Advanced categories"), isOn: $model.showAdvanced)
                    .toggleStyle(.switch)
                    .font(.system(size: 13, weight: .medium))
                    .help(L("Telegram, WhatsApp, временные файлы и симуляторы: проверяйте пути перед удалением", "Telegram, WhatsApp, temporary files and simulators: check the paths before deleting"))
            }

            Toggle("Dry run", isOn: $model.dryRun)
                .toggleStyle(.switch)
                .font(.system(size: 13, weight: .medium))
                .help(L("По умолчанию только план: точный список файлов, ничего не удаляется", "Plan only by default: the exact file list, nothing is deleted"))

            if model.isPreviewing {
                ProgressView().controlSize(.small)
            }

            Spacer()

            Text(L("выбрано \(model.selectedCount) · \(humanBytes(model.selectedBytes))", "selected \(model.selectedCount) · \(humanBytes(model.selectedBytes))"))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            Button(L("Выбрать все", "Check all")) { model.selectAllVisible() }
                .buttonStyle(.link)
                .font(.system(size: 13, weight: .medium))
                .disabled(model.phase != .idle || model.visibleItems.isEmpty || model.allVisibleSelected)
                .help(L("Отметить все видимые сейчас строки (с учётом поиска)", "Check every row visible now (after the search filter)"))

            Button(L("Снять все", "Uncheck all")) { model.clearAllVisible() }
                .buttonStyle(.link)
                .font(.system(size: 13, weight: .medium))
                .disabled(model.phase != .idle || model.selectedCount == 0)
                .help(L("Снять отметки со всех видимых сейчас строк", "Uncheck every row visible now"))

            if model.dryRun {
                Button {
                    Task { await model.buildPreview() }
                } label: {
                    Label(L("Показать план", "Show plan"), systemImage: "eye")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!model.canClean || model.isPreviewing)
            } else {
                Button {
                    showConfirm = true
                } label: {
                    Label(L("Очистить", "Clean"), systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.red)
                .disabled(!model.canClean)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 11)
    }

    // MARK: - Search

    /// Instant filter over the scan result: names, paths, warnings and the
    /// discipline group (so "web3", "cloud" or "gradle" narrow the list).
    private var searchBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField(L("Поиск: группа или название — web3, gradle, pip…",
                            "Search a group or tool — web3, gradle, pip…"),
                          text: $model.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14.5))
                    .focused($searchFocused)
                if model.isFiltering {
                    Button {
                        model.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(L("Очистить поиск", "Clear the search"))
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.1)))
            .frame(maxWidth: 500)

            Text(model.isFiltering
                 ? L("найдено \(model.visibleItems.count) из \(model.items.count)",
                     "\(model.visibleItems.count) of \(model.items.count) shown")
                 : L("\(model.items.count) объектов", "\(model.items.count) items"))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize()

            Spacer()

            Button(L("Поиск", "Search")) { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .onExitCommand { model.searchQuery = "" }
    }

    // MARK: - Item list

    private var content: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    Color.clear.frame(height: 0).id(Self.listTopID)
                    if model.phase != .idle {
                        statusBanner
                    }
                    if !model.notes.isEmpty {
                        notesView
                    }
                    if !model.visibleSafeItems.isEmpty {
                        sectionHeader(L("Безопасно удалить", "Safe to delete"), L("это кэши: приложение или пакетный менеджер восстановит их сам", "these are caches: the app or package manager recreates them"))
                        groupedRows(model.visibleSafeItems)
                    }
                    if model.showAdvanced && !model.visibleAdvancedItems.isEmpty {
                        sectionHeader(L("Расширенные", "Advanced"), L("прочитайте предупреждения: это данные, которые восстанавливаются не всегда", "read the warnings: this data is not always recreated"))
                        groupedRows(model.visibleAdvancedItems)
                    }
                    if model.isFiltering && model.visibleItems.isEmpty && !model.items.isEmpty {
                        noMatchState
                    }
                    if model.phase == .idle && model.items.isEmpty {
                        emptyState
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
            }
            // Rows arrive asynchronously after the scan. An NSScrollView whose
            // content grows from empty keeps the old "bottom" anchor, which
            // makes a fresh result open somewhere in the middle: scroll back to
            // the top once the new rows are laid out.
            .onChange(of: model.phase) { phase in
                guard phase == .idle else { return }
                for delay in [0.2, 0.7] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        proxy.scrollTo(Self.listTopID, anchor: .top)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private static let listTopID = "list-top"

    private func itemRows(_ items: [CleanupItem]) -> some View {
        ForEach(items) { item in
            ItemRow(item: item, selected: model.binding(for: item.id))
        }
    }

    /// Toolchain rows are grouped by discipline (web, mobile, desktop,
    /// embedded, data/ML/cloud): that grouping is the product difference from
    /// a generic "empty the Trash" cleaner.
    @ViewBuilder
    private func groupedRows(_ items: [CleanupItem]) -> some View {
        ForEach(ToolPlatform.allCases) { platform in
            let group = items.filter { $0.platform == platform }
            if !group.isEmpty {
                platformHeader(platform, group)
                itemRows(group)
            }
        }
        let rest = items.filter { $0.platform == nil }
        if !rest.isEmpty {
            if items.contains(where: { $0.platform != nil }) {
                sectionHeader(L("Система и приложения", "System and apps"),
                              L("менеджеры пакетов, IDE, Docker, временные файлы",
                                "package managers, IDEs, Docker, temporary files"))
            }
            itemRows(rest)
        }
    }

    private func platformHeader(_ platform: ToolPlatform, _ items: [CleanupItem]) -> some View {
        let size = items.reduce(Int64(0)) { $0 + $1.sizeBytes }
        return HStack(spacing: 9) {
            Image(systemName: platform.systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 18)
            Text(platform.title)
                .font(.system(size: 14.5, weight: .semibold))
            Text("\(items.count) · \(humanBytes(size))")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.secondary.opacity(0.1)))
            Spacer()
        }
        .padding(.top, 8)
    }

    private var phaseLabel: String {
        switch model.phase {
        case .scanning: return L("Сканирую кэши…", "Scanning caches…")
        case .cleaning: return L("Удаляю выбранное…", "Deleting selection…")
        case .rescanning: return L("Обновляю список…", "Refreshing the list…")
        case .idle: return ""
        }
    }

    private var statusBanner: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(phaseLabel)
                .font(.system(size: 14.5, weight: .medium))
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.accentColor.opacity(0.12)))
    }

    private var notesView: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(model.notes) { note in
                Label("\(note.category.title): \(note.text)", systemImage: "info.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.08)))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(.green)
            Text(L("Нечего чистить", "Nothing to clean"))
                .font(.system(size: 16, weight: .semibold))
            Text(L("Все известные кэши уже пусты, а данные не трогаются.", "Every known cache is already empty, and no user data is touched."))
                .font(.system(size: 13.5))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var noMatchState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text(L("Ничего не найдено", "Nothing matches"))
                .font(.system(size: 16, weight: .semibold))
            Text(L("По запросу «\(model.trimmedQuery)» строк нет. Попробуйте название инструмента (gradle, pip, foundry) или группу (web3, mobile).",
                   "No rows match “\(model.trimmedQuery)”. Try a tool name (gradle, pip, foundry) or a group (web3, mobile)."))
                .font(.system(size: 13.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if !model.catalogMatches.isEmpty {
                VStack(spacing: 3) {
                    Text(L("Поддерживается, но кэша на этом Mac нет:",
                           "Supported, but there is no cache on this Mac:"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(model.catalogMatches.prefix(8).map { L($0.titleRu, $0.titleEn) }.joined(separator: " · "))
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 6)
                .padding(.horizontal, 24)
            }
            Button(L("Очистить поиск", "Clear the search")) {
                model.searchQuery = ""
            }
            .font(.system(size: 13.5))
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private func sectionHeader(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 16.5, weight: .semibold))
            Text(subtitle).font(.system(size: 13.5)).foregroundStyle(.secondary)
        }
        .padding(.top, 6)
    }

    // MARK: - Log

    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Label(L("Журнал", "Log"), systemImage: "text.alignleft")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(model.logFileURL.path)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button(model.logExpanded ? L("Свернуть", "Collapse") : L("Развернуть", "Expand")) {
                    withAnimation(.easeInOut(duration: 0.15)) { model.logExpanded.toggle() }
                }
                .buttonStyle(.link)
                .font(.system(size: 13))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 7)

            if model.logExpanded {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(model.log.suffix(300)) { entry in
                            Text(entry.text)
                                .font(.system(size: 12.5, design: .monospaced))
                                .foregroundStyle(color(for: entry.level))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(10)
                }
                .frame(height: 128)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.6))
            }
        }
    }

    private func color(for level: LogLevel) -> Color {
        switch level {
        case .info: return .secondary
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.shield")
            Text(L("Удаляются только кэши из белого списка. Репозитории, контейнеры, образы, тома, настройки и личные файлы не трогаются.",
                   "Only allowlisted caches are deleted. Repositories, containers, images, volumes, settings and personal files are never touched."))
                .lineLimit(2)
            Spacer(minLength: 12)
            Button {
                NSWorkspace.shared.open(AppVersion.releasesURL)
            } label: {
                Text("v\(AppVersion.current) · GitHub")
                    .font(.system(size: 10, design: .monospaced))
                    .fixedSize()
            }
            .buttonStyle(.link)
        }
        .font(.system(size: 12.5))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 24)
        .padding(.vertical, 9)
    }

    // MARK: - Confirmation

    private var confirmation: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "trash.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.red)
                Text(L("Удалить \(model.selectedItems.count) объектов?", "Delete \(model.selectedItems.count) items?"))
                    .font(.title3.bold())
            }
            Text(L("Будет освобождено около \(humanBytes(model.selectedBytes)).", "About \(humanBytes(model.selectedBytes)) will be freed."))
                .foregroundStyle(.secondary)

            if model.selectedItems.contains(where: { $0.category.isAdvanced }) {
                Label(L("Среди выбранного есть расширенные категории — проверьте пути и предупреждения.", "Advanced categories are selected — check the paths and warnings."),
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.selectedItems.prefix(30)) { item in
                        HStack(spacing: 8) {
                            Text("\(item.category.title) · \(item.title)")
                                .font(.system(size: 12))
                                .lineLimit(1)
                            Spacer()
                            Text(item.sizeBytes > 0 ? humanBytes(item.sizeBytes) : "—")
                                .font(.system(size: 12, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(2)
            }
            .frame(maxHeight: 200)

            HStack {
                Spacer()
                Button(L("Отмена", "Cancel")) { showConfirm = false }
                    .keyboardShortcut(.cancelAction)
                Button(L("Удалить", "Delete")) {
                    showConfirm = false
                    Task { await model.cleanSelected() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560)
    }
}

private struct ItemRow: View {
    let item: CleanupItem
    @Binding var selected: Bool
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Toggle("", isOn: $selected)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .controlSize(.regular)
                .scaleEffect(1.12)
                .padding(.top, 9)

            glyph
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 15, weight: .semibold))
                Text(item.detail)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                if let warning = item.warning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.orange)
                }
            }

            Spacer(minLength: 10)

            Text(item.sizeBytes > 0 ? humanBytes(item.sizeBytes) : "—")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(selected ? Color.primary : Color.secondary)
                .padding(.top, 1)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(hovering ? Color.accentColor.opacity(0.07) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(hovering ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.07),
                        lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(hovering ? 0.07 : 0.03),
                radius: hovering ? 7 : 2, y: 1)
        .opacity(selected ? 1 : 0.8)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    /// The real macOS app icon when the tool ships one, otherwise its brand
    /// SF Symbol in the brand colour, so a Rust row looks like Rust and a
    /// Docker row shows the Docker icon.
    @ViewBuilder
    private var glyph: some View {
        if let bundleID = item.glyph.appBundleIdentifier,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 34, height: 34)
                .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
        } else {
            let tint = item.glyph.tint.color
            Image(systemName: item.glyph.systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(selected ? Color.white : tint)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(selected ? tint : tint.opacity(0.14))
                )
        }
    }
}


struct PreviewSheet: View {
    let report: PreviewReport
    let onClose: () -> Void

    @State private var savedPath: String?
    @State private var saving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "eye.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Что будет удалено", "What will be deleted"))
                        .font(.system(size: 20, weight: .bold))
                    Text(L("Dry run: ничего не удалено. Ниже — точный список файлов и команд.", "Dry run: nothing was deleted. Below is the exact list of files and commands."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(humanBytes(report.totalBytes))
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }

            HStack(spacing: 18) {
                Label(L("\(report.targetCount) items", "\(report.targetCount) items") + "", systemImage: "square.stack.3d.up")
                if report.fileCount > 0 {
                    Label(L("\(report.fileCount) файлов", "\(report.fileCount) files"), systemImage: "doc.on.doc")
                } else {
                    Label(L("файлы считаются при раскрытии строки",
                            "file lists are counted when a row is expanded"),
                          systemImage: "clock.arrow.circlepath")
                }
                Spacer()
            }
            .font(.system(size: 12.5))
            .foregroundStyle(.secondary)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(report.targets) { target in
                        PreviewTargetRow(target: target)
                    }
                }
                .padding(2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 10) {
                if let savedPath {
                    Text(L("Сохранено: \(savedPath)", "Saved: \(savedPath)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                if saving {
                    ProgressView().controlSize(.small)
                    Text(L("считаю полный список…", "counting every file…"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Button(L("Сохранить отчёт…", "Save report…")) { saveReport() }
                    .disabled(saving)
                Button(L("Закрыть", "Close")) { onClose() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 780, height: 580)
    }

    /// The saved report needs the full file lists, so the walk happens here,
    /// after the user explicitly asked for the file. The sheet stays usable and
    /// shows a spinner meanwhile.
    private func saveReport() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "devsweep-dry-run.txt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let items = report.targets.compactMap(\.item)
        saving = true
        savedPath = nil
        Task { @MainActor in
            let full = await Task.detached(priority: .userInitiated) {
                PreviewBuilder.build(items: items)
            }.value
            do {
                try full.textReport.write(to: url, atomically: true, encoding: .utf8)
                savedPath = url.path
            } catch {
                savedPath = L("ошибка записи: \(error.localizedDescription)", "write error: \(error.localizedDescription)")
            }
            saving = false
        }
    }
}

/// One target in the dry-run report. The plan arrives with sizes only; the
/// file list is walked the first time the row is opened, in pages. That keeps
/// "Show plan" instant even when the selection holds hundreds of thousands of
/// files, instead of freezing while every list is built up front.
private struct PreviewTargetRow: View {
    let target: PreviewTarget

    @State private var expanded = false
    @State private var scanning = false
    @State private var scannedFiles: [PreviewFile] = []
    @State private var scannedCount = 0
    @State private var scannedSize: Int64 = 0
    @State private var visibleLimit = 100

    private let pageSize = 200

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                toggle()
            } label: {
                header
            }
            .buttonStyle(.plain)

            if expanded {
                content
            }
        }
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.07)))
    }

    private var effectiveCount: Int {
        scannedCount > 0 ? scannedCount : target.fileCount
    }

    private var effectiveSize: Int64 {
        scannedSize > 0 ? scannedSize : target.sizeBytes
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: expanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 12)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(target.category) · \(target.title)")
                    .font(.system(size: 13, weight: .semibold))
                Text(target.path ?? (target.command ?? ""))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(humanBytes(effectiveSize))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                if scanning {
                    Text(L("считаю файлы…", "counting files…"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else if effectiveCount > 0 {
                    Text(L("\(effectiveCount) файлов", "\(effectiveCount) files"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 96, alignment: .trailing)
        }
        .contentShape(Rectangle())
    }

    private func toggle() {
        expanded.toggle()
        guard expanded, !scanning, scannedCount == 0, scannedFiles.isEmpty,
              target.command == nil else { return }
        scanning = true
        let snapshot = target
        Task { @MainActor in
            let result = await Task.detached(priority: .userInitiated) {
                PreviewBuilder.scanFiles(for: snapshot)
            }.value
            scannedFiles = result.files
            scannedCount = result.count
            scannedSize = result.size
            scanning = false
        }
    }

    @ViewBuilder
    private var content: some View {
        if let command = target.command {
            Text(L("Команда: \(command)", "Command: \(command)"))
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
            Text(L("Точный список определяет сам инструмент; для него dry-run недоступен.", "The tool itself decides the exact list; no dry run is available for it."))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        } else if scanning {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(L("Считаю файлы в этом кэше…", "Counting the files in this cache…"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } else if scannedFiles.isEmpty {
            Text(L("Пустой каталог: удалять нечего", "Empty directory: nothing to delete"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        } else {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(scannedFiles.prefix(visibleLimit)) { file in
                    HStack(spacing: 8) {
                        Text(file.path)
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        Spacer()
                        Text(humanBytes(file.sizeBytes))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if visibleLimit < scannedFiles.count {
                HStack(spacing: 12) {
                    Button(L("Показать ещё \(min(pageSize, scannedFiles.count - visibleLimit))",
                             "Show \(min(pageSize, scannedFiles.count - visibleLimit)) more")) {
                        visibleLimit = min(scannedFiles.count, visibleLimit + pageSize)
                    }
                    .font(.system(size: 12))
                    Button(L("Показать первые \(min(2000, scannedFiles.count))",
                             "Show the first \(min(2000, scannedFiles.count))")) {
                        visibleLimit = min(2000, scannedFiles.count)
                    }
                    .font(.system(size: 12))
                    .disabled(visibleLimit >= min(2000, scannedFiles.count))
                    Text(L("… и ещё \(scannedFiles.count - visibleLimit) файлов — полный список сохраняется в отчёт",
                           "… and \(scannedFiles.count - visibleLimit) more files — the full list goes into the saved report"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
        }
    }
}
