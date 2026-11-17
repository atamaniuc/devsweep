import Foundation

/// Self-test coverage for the asc/desc feature: pure SortState logic, the row
/// orders the main window and the dry-run sheet draw, and the cost of sorting a
/// large synthetic scan result. The gate in SelfTest.swift loops `all()` and
/// prints one PASS/FAIL line per check.
enum SortChecks {
    static func all() -> [(String, Bool)] {
        var checks: [(String, Bool)] = []

        func item(_ title: String, _ size: Int64) -> CleanupItem {
            CleanupItem(category: .devtools, title: title, detail: "",
                        sizeBytes: size,
                        action: .remove(URL(fileURLWithPath: "/private/tmp/sort-check")))
        }

        func titles(_ state: SortState, _ items: [CleanupItem]) -> [String] {
            state.items(items).map(\.title)
        }

        // MARK: - Main list: size asc/desc

        let sizes = [item("small", 10), item("big", 900), item("medium", 100)]
        checks.append(("sort size desc puts the biggest row first",
                       titles(SortState(key: .size, direction: .descending), sizes)
                       == ["big", "medium", "small"]))
        checks.append(("sort size asc puts the smallest row first",
                       titles(SortState(key: .size, direction: .ascending), sizes)
                       == ["small", "medium", "big"]))

        // MARK: - Main list: name asc/desc, case-mixed, numeric runs

        let names = [item("beta", 1), item("Alpha", 2), item("gamma", 3)]
        checks.append(("sort name asc is case-insensitive Finder order",
                       titles(SortState(key: .name, direction: .ascending), names)
                       == ["Alpha", "beta", "gamma"]))
        checks.append(("sort name desc reverses the A→Z order",
                       titles(SortState(key: .name, direction: .descending), names)
                       == ["gamma", "beta", "Alpha"]))

        let versions = [item("v11", 1), item("v9", 2), item("v10", 3)]
        checks.append(("sort name asc compares numeric runs by value (v9 < v10 < v11)",
                       titles(SortState(key: .name, direction: .ascending), versions)
                       == ["v9", "v10", "v11"]))
        checks.append(("sort name desc keeps numeric order (v11 > v10 > v9)",
                       titles(SortState(key: .name, direction: .descending), versions)
                       == ["v11", "v10", "v9"]))

        // MARK: - Ties: equal sizes and equal names stay deterministic

        let equalSizes = [item("zeta", 50), item("Alpha", 50), item("beta", 50)]
        checks.append(("equal sizes are ordered by name, same direction as the size key (asc)",
                       titles(SortState(key: .size, direction: .ascending), equalSizes)
                       == ["Alpha", "beta", "zeta"]))
        checks.append(("equal sizes are ordered by name, same direction as the size key (desc)",
                       titles(SortState(key: .size, direction: .descending), equalSizes)
                       == ["zeta", "beta", "Alpha"]))

        let equalNames = [item("same", 10), item("same", 30), item("same", 20)]
        checks.append(("equal names fall back to size (name asc)",
                       SortState(key: .name, direction: .ascending).items(equalNames).map(\.sizeBytes)
                       == [10, 20, 30]))
        checks.append(("equal names fall back to size (name desc)",
                       SortState(key: .name, direction: .descending).items(equalNames).map(\.sizeBytes)
                       == [30, 20, 10]))

        // Identical rows must not shuffle: the input position is the last
        // tiebreak, in both directions, so a re-sort is a no-op on screen.
        let twins = [item("same", 5), item("same", 5), item("same", 5)]
        checks.append(("equal names and equal sizes keep the input order (asc)",
                       SortState(key: .name, direction: .ascending).items(twins).map(\.id)
                       == twins.map(\.id)))
        checks.append(("equal names and equal sizes keep the input order (desc)",
                       SortState(key: .name, direction: .descending).items(twins).map(\.id)
                       == twins.map(\.id)))

        // MARK: - Total and stable order

        let mixed = [item("cache-b", 30), item("cache-a", 30), item("Cache-A", 30),
                     item("cache-10", 10), item("cache-9", 10), item("cache", 20)]
        let sizeDesc = SortState(key: .size, direction: .descending)
        let first = sizeDesc.items(mixed).map(\.id)
        let second = sizeDesc.items(mixed).map(\.id)
        let third = sizeDesc.items(mixed).map(\.id)
        checks.append(("re-sorting the same input yields the identical order",
                       first == second && second == third))
        checks.append(("sort order is total: every row appears exactly once",
                       Set(first).count == mixed.count && first.count == mixed.count))
        let nameDesc = SortState(key: .name, direction: .descending)
        checks.append(("re-sorting by name is stable too",
                       nameDesc.items(mixed).map(\.id) == nameDesc.items(mixed).map(\.id)))
        checks.append(("name sort is case-insensitive but keeps both spellings",
                       Set(nameDesc.items(mixed).map(\.title)).count == mixed.count))

        // MARK: - SortState.select / flip / summary

        var state = SortState(key: .size, direction: .descending)
        state.select(.size)
        checks.append(("selecting the active key flips the direction",
                       state == SortState(key: .size, direction: .ascending)))
        state.select(.name)
        checks.append(("selecting a new key takes its natural direction (name → A→Z)",
                       state == SortState(key: .name, direction: .ascending)))
        state.select(.size)
        checks.append(("back to size takes size's natural direction (biggest first)",
                       state == SortState(key: .size, direction: .descending)))
        state.flip()
        checks.append(("flip() inverts the direction", state.direction == .ascending))
        state.flip()
        checks.append(("flip() twice restores the direction", state.direction == .descending))
        let summary = SortState(key: .name, direction: .ascending).summary
        checks.append(("summary names the key and the direction arrow",
                       summary == "\(SortKey.name.title) \(SortDirection.ascending.symbol)"))

        // MARK: - Dry-run sheet: target rows

        func target(_ title: String, _ size: Int64) -> PreviewTarget {
            PreviewTarget(id: UUID(), title: title, category: "devtools", path: nil,
                          command: nil, sizeBytes: size, fileCount: 0, files: [],
                          truncated: false, item: nil)
        }

        let targets = [target("medium cache", 100), target("Big cache", 900),
                       target("small cache", 10)]
        checks.append(("sheet targets sort by size desc",
                       SortState(key: .size, direction: .descending).targets(targets).map(\.title)
                       == ["Big cache", "medium cache", "small cache"]))
        checks.append(("sheet targets sort by size asc",
                       SortState(key: .size, direction: .ascending).targets(targets).map(\.title)
                       == ["small cache", "medium cache", "Big cache"]))
        checks.append(("sheet targets sort by name asc",
                       SortState(key: .name, direction: .ascending).targets(targets).map(\.title)
                       == ["Big cache", "medium cache", "small cache"]))
        checks.append(("sheet targets sort by name desc",
                       SortState(key: .name, direction: .descending).targets(targets).map(\.title)
                       == ["small cache", "medium cache", "Big cache"]))

        // MARK: - Dry-run sheet: file rows

        func file(_ path: String, _ size: Int64) -> PreviewFile {
            PreviewFile(id: UUID(), path: path, sizeBytes: size)
        }

        let files = [file("/c/a.bin", 5), file("/c/deep/z.bin", 500), file("/c/b.bin", 5),
                     file("/c/deep/v10.bin", 50), file("/c/deep/v9.bin", 50)]
        checks.append(("sheet files sort by size desc",
                       SortState(key: .size, direction: .descending).files(files).map(\.path)
                       == ["/c/deep/z.bin", "/c/deep/v10.bin", "/c/deep/v9.bin",
                           "/c/b.bin", "/c/a.bin"]))
        checks.append(("sheet files sort by name asc",
                       SortState(key: .name, direction: .ascending).files(files).map(\.path)
                       == ["/c/a.bin", "/c/b.bin", "/c/deep/v9.bin", "/c/deep/v10.bin",
                           "/c/deep/z.bin"]))
        checks.append(("sheet files sort by name desc",
                       SortState(key: .name, direction: .descending).files(files).map(\.path)
                       == ["/c/deep/z.bin", "/c/deep/v10.bin", "/c/deep/v9.bin",
                           "/c/b.bin", "/c/a.bin"]))
        // The sheet caches one sorted array and pages slice it: sorting the same
        // walk twice must produce the same list, not shuffle equal rows.
        let fileSort = SortState(key: .size, direction: .descending)
        checks.append(("sheet file sort is repeatable (cached array is stable)",
                       fileSort.files(files).map(\.id) == fileSort.files(files).map(\.id)))
        let duplicateFiles = [file("/c/x", 5), file("/c/x", 5)]
        checks.append(("identical file rows keep walk order (index tiebreak)",
                       fileSort.files(duplicateFiles).map(\.id) == duplicateFiles.map(\.id)))

        // MARK: - Performance

        // A 20,000-row scan is what the main list re-sorts on every click; it
        // must not turn an instant toggle into a visible stall.
        var large: [CleanupItem] = []
        large.reserveCapacity(20_000)
        for index in 0..<20_000 {
            let size = Int64((index * 7919) % 100_000)
            large.append(item("cache-\(index)", size))
        }
        let perfSort = SortState(key: .size, direction: .descending)
        let started = Date()
        let sorted = perfSort.items(large)
        let millis = Date().timeIntervalSince(started) * 1000
        print(String(format: "sort: 20,000 items in %.2f ms", millis))
        checks.append(("sorting 20,000 rows stays under 250 ms", millis < 250))
        checks.append(("sorting 20,000 rows keeps every row",
                       sorted.count == large.count &&
                       sorted.first?.sizeBytes == large.map(\.sizeBytes).max()))

        return checks
    }
}
