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

    func items(_ items: [CleanupItem]) -> [CleanupItem] {
        items.enumerated().sorted { lhs, rhs in
            switch key {
            case .size:
                if lhs.element.sizeBytes != rhs.element.sizeBytes {
                    return sizeOrder(lhs.element.sizeBytes, rhs.element.sizeBytes)
                }
                return nameOrder(lhs.element.title, rhs.element.title)
                    || (lhs.element.title == rhs.element.title && lhs.offset < rhs.offset)
            case .name:
                if lhs.element.title != rhs.element.title {
                    return nameOrder(lhs.element.title, rhs.element.title)
                }
                return sizeOrder(lhs.element.sizeBytes, rhs.element.sizeBytes)
                    || (lhs.element.sizeBytes == rhs.element.sizeBytes && lhs.offset < rhs.offset)
            }
        }.map(\.element)
    }

    func targets(_ targets: [PreviewTarget]) -> [PreviewTarget] {
        targets.enumerated().sorted { lhs, rhs in
            switch key {
            case .size:
                if lhs.element.sizeBytes != rhs.element.sizeBytes {
                    return sizeOrder(lhs.element.sizeBytes, rhs.element.sizeBytes)
                }
                return nameOrder(lhs.element.title, rhs.element.title)
                    || (lhs.element.title == rhs.element.title && lhs.offset < rhs.offset)
            case .name:
                if lhs.element.title != rhs.element.title {
                    return nameOrder(lhs.element.title, rhs.element.title)
                }
                return sizeOrder(lhs.element.sizeBytes, rhs.element.sizeBytes)
                    || (lhs.element.sizeBytes == rhs.element.sizeBytes && lhs.offset < rhs.offset)
            }
        }.map(\.element)
    }

    /// File rows in the dry-run sheet: by name the path is the name.
    func files(_ files: [PreviewFile]) -> [PreviewFile] {
        // Sizes arrive in walk order; sorting 200k rows takes ~40 ms, so callers
        // cache the result instead of sorting inside a body.
        files.enumerated().sorted { lhs, rhs in
            switch key {
            case .size:
                if lhs.element.sizeBytes != rhs.element.sizeBytes {
                    return sizeOrder(lhs.element.sizeBytes, rhs.element.sizeBytes)
                }
                return nameOrder(lhs.element.path, rhs.element.path)
                    || (lhs.element.path == rhs.element.path && lhs.offset < rhs.offset)
            case .name:
                if lhs.element.path != rhs.element.path {
                    return nameOrder(lhs.element.path, rhs.element.path)
                }
                return sizeOrder(lhs.element.sizeBytes, rhs.element.sizeBytes)
                    || (lhs.element.sizeBytes == rhs.element.sizeBytes && lhs.offset < rhs.offset)
            }
        }.map(\.element)
    }
}
