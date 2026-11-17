import SwiftUI

struct PreviewSheet: View {
    let report: PreviewReport
    let onClose: () -> Void

    @State private var savedPath: String?
    @State private var saving = false

    private static let planTopID = "plan-top"
    /// The sheet has its own sort choice, independent of the main window: the
    /// dry-run plan is a report, and re-ordering it must not re-order the list
    /// behind the sheet. Defaults to size descending, like the app.
    @State private var sort = SortState()

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
                // One compact control next to the total: the summary line below
                // stays about counts and sizes.
                SortPicker(sort: $sort)
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

            // The rows appear after the sheet animates in; an NSScrollView whose
            // LazyVStack grows then keeps the bottom anchor, which opens the plan
            // at its smallest rows. Scroll to the first row once the layout lands
            // (the same fix as the main list).
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        Color.clear.frame(height: 0).id(Self.planTopID)
                        ForEach(sort.targets(report.targets)) { target in
                            PreviewTargetRow(target: target, sort: $sort)
                        }
                    }
                    .padding(2)
                }
                .onAppear {
                    for delay in [0.05, 0.3] {
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            proxy.scrollTo(Self.planTopID, anchor: .top)
                        }
                    }
                }
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
    @Binding var sort: SortState

    @State private var expanded = false
    @State private var scanning = false
    /// Raw walk order. The sorted copy below is what the rows render, so a
    /// 200,000-file target is sorted once (when the walk finishes or the sort
    /// changes) instead of inside the SwiftUI body on every frame.
    @State private var scannedFiles: [PreviewFile] = []
    @State private var sortedFiles: [PreviewFile] = []
    @State private var resorting = false
    /// Bumped on every re-sort so a slow background sort cannot overwrite the
    /// result of a newer one when the user flips the sort twice quickly.
    @State private var sortGeneration = 0
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
        // Re-sort the cached rows when the user changes the sort, never during
        // the walk and never per drawn page.
        .onChange(of: sort) { newSort in
            resort(using: newSort)
        }
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

    /// The cached rows are sorted by name with `localizedStandardCompare`
    /// (Finder order), which costs ~42 ms for 5,000 paths but ~3 s for 200,000:
    /// small lists are sorted inline, big ones off the main thread so the sheet
    /// stays responsive while the order is rebuilt.
    private static let inlineSortLimit = 5_000

    private func resort(using state: SortState) {
        sortGeneration += 1
        let generation = sortGeneration
        let files = scannedFiles
        guard !files.isEmpty else {
            sortedFiles = []
            resorting = false
            return
        }
        guard files.count > Self.inlineSortLimit else {
            sortedFiles = state.files(files)
            resorting = false
            return
        }
        resorting = true
        Task { @MainActor in
            let sorted = await Task.detached(priority: .userInitiated) {
                state.files(files)
            }.value
            guard generation == sortGeneration else { return }
            sortedFiles = sorted
            resorting = false
        }
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
            // Read the binding, not a captured copy: the user may have changed
            // the sort while the row was counting files.
            resort(using: sort)
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
            if resorting {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(L("сортирую \(scannedFiles.count) файлов…", "sorting \(scannedFiles.count) files…"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(sortedFiles.prefix(visibleLimit)) { file in
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

            if visibleLimit < sortedFiles.count {
                HStack(spacing: 12) {
                    Button(L("Показать ещё \(min(pageSize, sortedFiles.count - visibleLimit))",
                             "Show \(min(pageSize, sortedFiles.count - visibleLimit)) more")) {
                        visibleLimit = min(sortedFiles.count, visibleLimit + pageSize)
                    }
                    .font(.system(size: 12))
                    Button(L("Показать первые \(min(2000, sortedFiles.count))",
                             "Show the first \(min(2000, sortedFiles.count))")) {
                        visibleLimit = min(2000, sortedFiles.count)
                    }
                    .font(.system(size: 12))
                    .disabled(visibleLimit >= min(2000, sortedFiles.count))
                    Text(L("… и ещё \(sortedFiles.count - visibleLimit) файлов — полный список сохраняется в отчёт",
                           "… and \(sortedFiles.count - visibleLimit) more files — the full list goes into the saved report"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
        }
    }
}
