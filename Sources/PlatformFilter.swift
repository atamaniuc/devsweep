import Foundation

/// Filtering behind the clickable discipline chips. Pure and allocation-light:
/// it runs on every click over the scan result (a few dozen rows), so picking a
/// chip is instant and never touches the disk.
enum PlatformFilter {
    struct Stats: Equatable, Sendable {
        var count: Int = 0
        var bytes: Int64 = 0
    }

    /// An empty tag set means "all rows"; otherwise a row must carry one of the
    /// selected tags. Tags combine with AND against the search box, not with
    /// each other: selecting Web and Cloud shows both groups.
    static func apply(_ items: [CleanupItem], tags: Set<PlatformTag>) -> [CleanupItem] {
        guard !tags.isEmpty else { return items }
        return items.filter { tags.contains($0.platformTag) }
    }

    /// Per-chip "found here" numbers: rows and bytes. One pass, used by the
    /// header so a chip can say "Web 8 · 3.1 GB".
    static func stats(_ items: [CleanupItem]) -> [PlatformTag: Stats] {
        var result: [PlatformTag: Stats] = [:]
        result.reserveCapacity(PlatformTag.allCases.count)
        for item in items {
            var stats = result[item.platformTag] ?? Stats()
            stats.count += 1
            stats.bytes += item.sizeBytes
            result[item.platformTag] = stats
        }
        return result
    }
}
