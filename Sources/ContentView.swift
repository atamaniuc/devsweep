import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = AppModel()
    @State private var showConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            actionBar
            Divider()
            content
            Divider()
            logPanel
            footer
        }
        .frame(minWidth: 860, minHeight: 680)
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
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(AppVersion.name)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text(L(AppVersion.taglineRu, AppVersion.taglineEn))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.75))
                HStack(spacing: 8) {
                    Text(L("кэш-клинер для разработчиков и инженеров",
                           "the cache cleaner for developers and engineers"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(L("\(ToolCaches.count) кэшей тулчейнов · macOS 13+",
                           "\(ToolCaches.count) toolchain caches · macOS 13+"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.12)))
                    Text("v\(AppVersion.current)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.12)))
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(humanBytes(model.freeBytes))
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(L("свободно на диске", "free on disk"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressView(value: min(max(model.usedFraction, 0), 1))
                    .progressViewStyle(.linear)
                    .frame(width: 210)
                    .tint(model.usedFraction > 0.9 ? .red : .accentColor)
                Text(L("занято \(humanPercent(model.usedFraction))", "used \(humanPercent(model.usedFraction))"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        }
        .padding(20)
    }

    // MARK: - Action bar

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button {
                Task { await model.scan() }
            } label: {
                Label(L("Сканировать", "Scan"), systemImage: "arrow.clockwise")
            }
            .disabled(model.phase != .idle)

            if model.hasAdvancedItems {
                Toggle(L("Расширенные категории", "Advanced categories"), isOn: $model.showAdvanced)
                    .toggleStyle(.switch)
                    .font(.caption)
                    .help(L("Telegram, WhatsApp, временные файлы и симуляторы: проверяйте пути перед удалением", "Telegram, WhatsApp, temporary files and simulators: check the paths before deleting"))
            }

            Toggle("Dry run", isOn: $model.dryRun)
                .toggleStyle(.switch)
                .font(.caption)
                .help(L("По умолчанию только план: точный список файлов, ничего не удаляется", "Plan only by default: the exact file list, nothing is deleted"))

            if model.isPreviewing {
                ProgressView().controlSize(.small)
            }

            Spacer()

            Text(L("выбрано \(model.selectedItems.count) · \(humanBytes(model.selectedSize))", "selected \(model.selectedItems.count) · \(humanBytes(model.selectedSize))"))
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.secondary)

            Button(L("Снять всё", "Clear selection")) { model.clearSelection() }
                .buttonStyle(.link)
                .font(.caption)
                .disabled(model.phase != .idle)

            if model.dryRun {
                Button {
                    Task { await model.buildPreview() }
                } label: {
                    Label(L("Показать план", "Show plan"), systemImage: "eye")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canClean || model.isPreviewing)
            } else {
                Button {
                    showConfirm = true
                } label: {
                    Label(L("Очистить", "Clean"), systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(!model.canClean)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    // MARK: - Item list

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if model.phase != .idle {
                    statusBanner
                }
                if !model.notes.isEmpty {
                    notesView
                }
                if !model.safeItems.isEmpty {
                    sectionHeader(L("Безопасно удалить", "Safe to delete"), L("это кэши: приложение или пакетный менеджер восстановит их сам", "these are caches: the app or package manager recreates them"))
                    groupedRows(model.safeItems)
                }
                if model.showAdvanced && !model.advancedItems.isEmpty {
                    sectionHeader(L("Расширенные", "Advanced"), L("прочитайте предупреждения: это данные, которые восстанавливаются не всегда", "read the warnings: this data is not always recreated"))
                    groupedRows(model.advancedItems)
                }
                if model.phase == .idle && model.items.isEmpty {
                    emptyState
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

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
        return HStack(spacing: 8) {
            Image(systemName: platform.systemImage)
                .font(.system(size: 11))
                .foregroundStyle(Color.accentColor)
            Text(platform.title)
                .font(.system(size: 12, weight: .semibold))
            Text("\(items.count) · \(humanBytes(size))")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.top, 6)
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
                .font(.callout)
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.12)))
    }

    private var notesView: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(model.notes) { note in
                Label("\(note.category.title): \(note.text)", systemImage: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(.green)
            Text(L("Нечего чистить", "Nothing to clean"))
                .font(.headline)
            Text(L("Все известные кэши уже пусты, а данные не трогаются.", "Every known cache is already empty, and no user data is touched."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func sectionHeader(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    // MARK: - Log

    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Label(L("Журнал", "Log"), systemImage: "text.alignleft")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(model.logFileURL.path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button(model.logExpanded ? L("Свернуть", "Collapse") : L("Развернуть", "Expand")) {
                    withAnimation(.easeInOut(duration: 0.15)) { model.logExpanded.toggle() }
                }
                .buttonStyle(.link)
                .font(.caption)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)

            if model.logExpanded {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(model.log.suffix(300)) { entry in
                            Text(entry.text)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(color(for: entry.level))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(10)
                }
                .frame(height: 118)
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
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
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
            Text(L("Будет освобождено около \(humanBytes(model.selectedSize)).", "About \(humanBytes(model.selectedSize)) will be freed."))
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

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle("", isOn: $selected)
                .labelsHidden()
                .toggleStyle(.checkbox)

            Image(systemName: item.category.systemImage)
                .frame(width: 22)
                .foregroundStyle(selected ? Color.accentColor : Color.secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                Text(item.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                if let warning = item.warning {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
            }

            Spacer(minLength: 8)

            Text(item.sizeBytes > 0 ? humanBytes(item.sizeBytes) : "—")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.07)))
        .opacity(selected ? 1 : 0.72)
    }
}


struct PreviewSheet: View {
    let report: PreviewReport
    let onClose: () -> Void

    @State private var savedPath: String?

    private let visibleFilesPerTarget = 500

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "eye.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Что будет удалено", "What will be deleted"))
                        .font(.title3.bold())
                    Text(L("Dry run: ничего не удалено. Ниже — точный список файлов и команд.", "Dry run: nothing was deleted. Below is the exact list of files and commands."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(humanBytes(report.totalBytes))
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }

            HStack(spacing: 16) {
                Label(L("\(report.targetCount) items", "\(report.targetCount) items") + "", systemImage: "square.stack.3d.up")
                Label(L("\(report.fileCount) файлов", "\(report.fileCount) files"), systemImage: "doc.on.doc")
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(report.targets) { target in
                        targetRow(target)
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
                Button(L("Сохранить отчёт…", "Save report…")) { saveReport() }
                Button(L("Закрыть", "Close")) { onClose() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 780, height: 580)
    }

    private func targetRow(_ target: PreviewTarget) -> some View {
        DisclosureGroup {
            if let command = target.command {
                Text(L("Команда: \(command)", "Command: \(command)"))
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                Text(L("Точный список определяет сам инструмент; для него dry-run недоступен.", "The tool itself decides the exact list; no dry run is available for it."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else if target.files.isEmpty {
                Text(L("Пустой каталог: удалять нечего", "Empty directory: nothing to delete"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(target.files.prefix(visibleFilesPerTarget)) { file in
                    HStack(spacing: 8) {
                        Text(file.path)
                            .font(.system(size: 10, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        Spacer()
                        Text(humanBytes(file.sizeBytes))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                if target.fileCount > visibleFilesPerTarget {
                    Text(L("… и ещё \(target.fileCount - visibleFilesPerTarget) файлов — полный список сохраняется в отчёт", "… and \(target.fileCount - visibleFilesPerTarget) more files — the full list goes into the saved report"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(target.category) · \(target.title)")
                        .font(.system(size: 12, weight: .medium))
                    Text(target.path ?? (target.command ?? ""))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(humanBytes(target.sizeBytes))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    if target.fileCount > 0 {
                        Text(L("\(target.fileCount) файлов", "\(target.fileCount) files"))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
    }

    private func saveReport() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "cleandisk-dry-run.txt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try report.textReport.write(to: url, atomically: true, encoding: .utf8)
            savedPath = url.path
        } catch {
            savedPath = L("ошибка записи: \(error.localizedDescription)", "write error: \(error.localizedDescription)")
        }
    }
}
