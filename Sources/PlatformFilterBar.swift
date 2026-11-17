import SwiftUI

/// The clickable discipline chips under the header. A chip is a filter, not a
/// label: clicking it narrows the list to that group, clicking it again clears
/// the filter, and several chips can be on at once (the groups are ORed).
///
/// Counts come from the already-scanned rows (`model.tagStats`, one O(n) pass
/// over a few dozen items), so a click is instant and never touches the disk.
/// The row is a wrapping layout: "All" plus eight groups does not fit on one
/// line at the 940 pt minimum window width, and clipping a chip would hide a
/// filter the user cannot then clear.
struct PlatformFilterBar: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let stats = model.tagStats
        let totalBytes = stats.values.reduce(Int64(0)) { $0 + $1.bytes }
        ChipFlowLayout(spacing: 7, rowSpacing: 7) {
            ChipButton(
                title: L("Все", "All"),
                symbol: "square.grid.2x2",
                count: model.items.count,
                active: model.selectedTags.isEmpty,
                dimmed: false,
                help: L("Показать все \(model.items.count) кэшей · \(humanBytes(totalBytes)) — сбросить фильтр по группам",
                        "Show all \(model.items.count) caches · \(humanBytes(totalBytes)) — clear the group filter"),
                action: { model.clearTagFilter() }
            )
            ForEach(PlatformTag.allCases) { tag in
                let chipStats = stats[tag] ?? PlatformFilter.Stats()
                ChipButton(
                    title: tag.chipTitle,
                    symbol: tag.systemImage,
                    count: chipStats.count,
                    active: model.selectedTags.contains(tag),
                    dimmed: chipStats.count == 0,
                    help: helpText(for: tag, stats: chipStats,
                                   active: model.selectedTags.contains(tag)),
                    action: { model.toggleTag(tag) }
                )
            }
        }
    }

    private func helpText(for tag: PlatformTag,
                          stats: PlatformFilter.Stats,
                          active: Bool) -> String {
        let found = L("\(stats.count) кэшей · \(humanBytes(stats.bytes)) найдено здесь",
                      "\(stats.count) caches · \(humanBytes(stats.bytes)) found here")
        let hint = active
            ? L("нажмите, чтобы снять фильтр", "click to clear the filter")
            : L("нажмите, чтобы отфильтровать", "click to filter")
        let empty = stats.count == 0
            ? L(" (сейчас в группе пусто)", " (nothing in this group right now)")
            : ""
        return "\(tag.title): \(found)\(empty) — \(hint)"
    }
}

/// One capsule chip. Active = accent fill and bold text; zero-row groups stay
/// visible (dimmed) and remain clickable, because "nothing here" is information
/// and the empty-result state explains it.
private struct ChipButton: View {
    let title: String
    let symbol: String
    let count: Int
    let active: Bool
    let dimmed: Bool
    let help: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 12.5, weight: active ? .bold : .medium))
                    .lineLimit(1)
                    .fixedSize()
                Text("\(count)")
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    // Without fixedSize the badge text is the first thing the
                    // label compresses, and a chip showed "…" instead of "37".
                    .fixedSize()
                    .padding(.horizontal, 5)
                    .padding(.vertical, 0.5)
                    .background(Capsule().fill(badgeFill))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(foreground)
            .background(Capsule().fill(background))
            .overlay(Capsule().stroke(border, lineWidth: 1))
            .contentShape(Capsule())
            .shadow(color: .black.opacity(active ? 0.16 : 0), radius: 3, y: 1)
            .opacity(dimmed && !active ? 0.5 : 1)
            .animation(.easeOut(duration: 0.12), value: active)
            .animation(.easeOut(duration: 0.12), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(title)
        .accessibilityValue(L("\(count) кэшей", "\(count) caches"))
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }

    private var foreground: Color {
        active ? .white : (hovering ? .accentColor : .primary)
    }

    private var background: Color {
        if active { return .accentColor }
        if hovering { return Color.accentColor.opacity(0.14) }
        return Color(nsColor: .controlBackgroundColor)
    }

    private var border: Color {
        if active { return .accentColor }
        if hovering { return Color.accentColor.opacity(0.5) }
        return Color.primary.opacity(0.10)
    }

    private var badgeFill: Color {
        // On an active chip the badge sits on the accent fill: a white overlay
        // there made the white count nearly invisible, so the pill darkens the
        // accent instead.
        active ? Color.black.opacity(0.18) : Color.secondary.opacity(0.13)
    }
}

/// Left-aligned flow layout: chips fill a row until the next one would overflow,
/// then wrap. At the 940 pt minimum width nine chips need two rows, and a naive
/// wrap leaves the ninth alone on the second line, so when everything fits in
/// two rows the split is balanced instead (5 + 4). `Layout` exists on macOS 13,
/// the app's minimum.
private struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 7
    var rowSpacing: CGFloat = 7

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rowWidth(_ sizes: [CGSize], _ range: Range<Int>) -> CGFloat {
        guard !range.isEmpty else { return 0 }
        let content = range.reduce(CGFloat(0)) { $0 + sizes[$1].width }
        return content + spacing * CGFloat(range.count - 1)
    }

    /// Row for a contiguous index range; caller guarantees a non-empty range.
    private func makeRow(_ sizes: [CGSize], _ range: Range<Int>) -> Row {
        Row(indices: Array(range),
            width: rowWidth(sizes, range),
            height: range.map { sizes[$0].height }.max() ?? 0)
    }

    /// Greedy: fill a line until the next chip would overflow.
    private func greedyRows(_ sizes: [CGSize], maxWidth: CGFloat) -> [Row] {
        var result: [Row] = []
        var start = 0
        var width: CGFloat = 0
        for index in sizes.indices {
            let candidate = index == start ? sizes[index].width : width + spacing + sizes[index].width
            if index > start && candidate > maxWidth {
                result.append(makeRow(sizes, start..<index))
                start = index
                width = sizes[index].width
            } else {
                width = candidate
            }
        }
        if start < sizes.count { result.append(makeRow(sizes, start..<sizes.count)) }
        return result
    }

    private func rows(_ sizes: [CGSize], maxWidth: CGFloat) -> [Row] {
        let greedy = greedyRows(sizes, maxWidth: maxWidth)
        guard greedy.count > 1, sizes.count > 2 else { return greedy }

        // Two rows: pick the split whose wider row is the narrowest, so the chips
        // end up balanced instead of hanging one chip on its own line.
        var best: (split: Int, widest: CGFloat)?
        for split in 1..<sizes.count {
            let first = rowWidth(sizes, 0..<split)
            let second = rowWidth(sizes, split..<sizes.count)
            guard first <= maxWidth, second <= maxWidth else { continue }
            let widest = max(first, second)
            if best == nil || widest < best!.widest {
                best = (split, widest)
            }
        }
        guard let best else { return greedy }
        return [makeRow(sizes, 0..<best.split),
                makeRow(sizes, best.split..<sizes.count)]
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let proposed = proposal.width ?? 0
        guard proposed > 0, proposed.isFinite else {
            // Measurement pass without a real width: report the unwrapped row so
            // the parent never sees a pathological (one-chip-per-line) height.
            return CGSize(width: rowWidth(sizes, 0..<sizes.count),
                          height: sizes.map(\.height).max() ?? 0)
        }
        let rows = rows(sizes, maxWidth: proposed)
        let height = rows.reduce(0) { $0 + $1.height }
            + rowSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposed, height: height)
    }

    func placeSubviews(in bounds: CGRect,
                       proposal: ProposedViewSize,
                       subviews: Subviews,
                       cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let rows = rows(sizes, maxWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = sizes[index]
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                                      proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + rowSpacing
        }
    }
}
