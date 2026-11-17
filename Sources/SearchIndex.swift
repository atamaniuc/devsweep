import Foundation

/// Search across everything the app knows: the found rows, the catalog entries
/// that are supported but absent, the scanner-managed caches, and the scan
/// notes ("Telegram is running — quit it to clean"), so a search for a tool the
/// app knows never dead-ends in "nothing matches".
///
/// Stub: the exact-substring behaviour that shipped in 1.5.1. The search work
/// stream replaces the bodies with catalogue/scanner/note matching and a fuzzy
/// fallback, keeping these signatures.
enum SearchIndex {
    static func filter(_ items: [CleanupItem], query: String) -> [CleanupItem] {
        CleanupFilters.matching(items, query: query)
    }

    static func matchingSpecs(_ query: String) -> [ToolCacheSpec] {
        SearchQuery.matchingSpecs(query)
    }

    static func scannerMatches(_ query: String) -> [ScannerCaches.Entry] {
        []
    }

    static func matchingNotes(_ notes: [ScanNote], query: String) -> [ScanNote] {
        []
    }

    static func noteMatches(_ note: ScanNote, _ query: String) -> Bool {
        false
    }
}

enum SearchChecks {
    static func all() -> [(String, Bool)] { [] }
}
