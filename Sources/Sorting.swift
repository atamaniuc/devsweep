import Foundation

/// How the main list and the dry-run sheet order their rows. Sorting is a pure
/// function of the scan result, so the UI re-sorts on every click without
/// touching the disk: a few dozen rows cost microseconds, and the sheet sorts
/// only the rows it is about to draw.
enum SortKey: String, CaseIterable, Identifiable, Codable, Sendable {
    case size
    case name

    var id: String { rawValue }

    var title: String {
        switch self {
        case .size: return L("Размер", "Size")
        case .name: return L("Название", "Name")
        }
    }

    var symbol: String {
        switch self {
        case .size: return "internaldrive"
        case .name: return "textformat.abc"
        }
    }
}

enum SortDirection: String, CaseIterable, Codable, Sendable {
    case ascending
    case descending

    var title: String {
        switch self {
        case .ascending: return L("по возрастанию", "ascending")
        case .descending: return L("по убыванию", "descending")
        }
    }

    var symbol: String {
        switch self {
        case .ascending: return "arrow.up"
        case .descending: return "arrow.down"
        }
    }

    var flipped: SortDirection { self == .ascending ? .descending : .ascending }
}

/// One immutable sort choice. `key` decides the primary comparison, `direction`
/// its order; name and input position break ties, so the order is total and
/// stable and a re-sort never shuffles equal-sized rows between frames.
struct SortState: Equatable, Sendable {
    var key: SortKey
    var direction: SortDirection

    init(key: SortKey = .size, direction: SortDirection = .descending) {
        self.key = key
        self.direction = direction
    }

    /// Clicking the active key flips the direction; picking another key applies
    /// that key's natural direction (biggest first for size, A→Z for name).
    mutating func select(_ newKey: SortKey) {
        if key == newKey {
            direction = direction.flipped
        } else {
            key = newKey
            direction = newKey == .size ? .descending : .ascending
        }
    }

    mutating func flip() { direction = direction.flipped }

    var summary: String { "\(key.title) \(direction.symbol)" }

    // MARK: - Comparison helpers

    private func sizeOrder(_ a: Int64, _ b: Int64) -> Bool {
        a == b ? false : (direction == .descending ? a > b : a < b)
    }

    /// Finder-style name ordering: case- and diacritic-insensitive with numeric
    /// runs compared by value ("v10" before "v11", "Ruby 3.3" after "Ruby 3.2").
    private func nameOrder(_ a: String, _ b: String) -> Bool {
        let result = a.localizedStandardCompare(b)
        if result == .orderedSame {
            // Fall back to a byte comparison so equal names still have a stable
            // total order instead of inheriting Swift's unstable sort.
            return a < b
        }
        return direction == .ascending ? result == .orderedAscending : result == .orderedDescending
    }

    // MARK: - Applying the order

    /// Sorts the index array and materialises the rows once. `enumerated()
    /// .sorted` copies every row on every comparison, and a CleanupItem carries
    /// a URL, strings and an array, so the ARC traffic dominated the sort:
    /// 20,000 rows took ~505 ms. Indices are distinct, which makes the input
    /// position tiebreak (`lhs < rhs`) implicit and keeps the same total order.
    private func order<T>(_ values: [T], by isOrderedBefore: (Int, Int) -> Bool) -> [T] {
        values.indices.sorted(by: isOrderedBefore).map { values[$0] }
    }

    func items(_ items: [CleanupItem]) -> [CleanupItem] {
        order(items) { lhs, rhs in
            switch key {
            case .size:
                let aSize = items[lhs].sizeBytes
                let bSize = items[rhs].sizeBytes
                if aSize != bSize { return sizeOrder(aSize, bSize) }
                let aTitle = items[lhs].title
                let bTitle = items[rhs].title
                return nameOrder(aTitle, bTitle) || (aTitle == bTitle && lhs < rhs)
            case .name:
                let aTitle = items[lhs].title
                let bTitle = items[rhs].title
                if aTitle != bTitle { return nameOrder(aTitle, bTitle) }
                let aSize = items[lhs].sizeBytes
                let bSize = items[rhs].sizeBytes
                return sizeOrder(aSize, bSize) || (aSize == bSize && lhs < rhs)
            }
        }
    }

    func targets(_ targets: [PreviewTarget]) -> [PreviewTarget] {
        order(targets) { lhs, rhs in
            switch key {
            case .size:
                let aSize = targets[lhs].sizeBytes
                let bSize = targets[rhs].sizeBytes
                if aSize != bSize { return sizeOrder(aSize, bSize) }
                let aTitle = targets[lhs].title
                let bTitle = targets[rhs].title
                return nameOrder(aTitle, bTitle) || (aTitle == bTitle && lhs < rhs)
            case .name:
                let aTitle = targets[lhs].title
                let bTitle = targets[rhs].title
                if aTitle != bTitle { return nameOrder(aTitle, bTitle) }
                let aSize = targets[lhs].sizeBytes
                let bSize = targets[rhs].sizeBytes
                return sizeOrder(aSize, bSize) || (aSize == bSize && lhs < rhs)
            }
        }
    }

    /// File rows in the dry-run sheet: by name the path is the name.
    func files(_ files: [PreviewFile]) -> [PreviewFile] {
        // Sizes arrive in walk order; callers cache the result instead of
        // sorting inside a body, and the index sort keeps a 200k-file re-sort
        // cheap instead of copying every path on every comparison.
        order(files) { lhs, rhs in
            switch key {
            case .size:
                let aSize = files[lhs].sizeBytes
                let bSize = files[rhs].sizeBytes
                if aSize != bSize { return sizeOrder(aSize, bSize) }
                let aPath = files[lhs].path
                let bPath = files[rhs].path
                return nameOrder(aPath, bPath) || (aPath == bPath && lhs < rhs)
            case .name:
                let aPath = files[lhs].path
                let bPath = files[rhs].path
                if aPath != bPath { return nameOrder(aPath, bPath) }
                let aSize = files[lhs].sizeBytes
                let bSize = files[rhs].sizeBytes
                return sizeOrder(aSize, bSize) || (aSize == bSize && lhs < rhs)
            }
        }
    }
}
