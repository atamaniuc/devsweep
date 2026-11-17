import Foundation

/// Search across everything the app knows: the found rows, the catalog entries
/// that are supported but absent, the scanner-managed caches, and the scan
/// notes ("Telegram is running — quit it to clean"), so a search for a tool the
/// app knows never dead-ends in "nothing matches".
///
/// Two passes, in this order:
/// 1. the exact 1.5.1 behaviour — folded substring, every word must match;
/// 2. only when the exact pass returns nothing — a bounded fuzzy pass over
///    title words (edit distance 1, or 2 for long words, or a shared 4-letter
///    prefix) so a typo such as "whatsup" still finds WhatsApp.
///
/// The fuzzy pass never loosens a query that already matched, and tokens
/// shorter than four characters are exact-only, so "pip" cannot start matching
/// unrelated rows.
enum SearchIndex {
    // MARK: - Found rows

    static func filter(_ items: [CleanupItem], query: String) -> [CleanupItem] {
        let tokens = SearchQuery.tokens(query)
        guard !tokens.isEmpty else { return items }

        // Exact pass. Fast path for plain ASCII text: one byte buffer per row,
        // lowercased while it is built, so no String and no second
        // normalization pass are allocated. Non-ASCII rows (Cyrillic, accents,
        // full-width) and any byte-path miss take the authoritative
        // `SearchQuery.fold` path, which is what the shipped app used for
        // everything — the matched set is therefore identical, only the work is
        // smaller (20k rows in ~40 ms instead of ~150 ms).
        let asciiTokens: [[UInt8]]? = tokens.allSatisfy({ token in
            token.utf8.allSatisfy { $0 < 0x80 }
        }) ? tokens.map { Array($0.utf8) } : nil

        var exact: [CleanupItem] = []
        exact.reserveCapacity(min(items.count, 64))
        for item in items {
            if let asciiTokens, let bytes = asciiHaystack(for: item),
               matchesAll(asciiTokens, bytes) {
                exact.append(item)
                continue
            }
            if matchesAll(tokens, SearchQuery.fold(haystack(for: item))) {
                exact.append(item)
            }
        }
        if !exact.isEmpty { return exact }

        // Zero exact rows: the query is probably a near miss. A token that does
        // not occur in the haystack may still match one of the title words with
        // a small edit distance or a shared prefix.
        guard tokens.contains(where: { $0.count >= 4 }) else { return [] }
        var fuzzy: [CleanupItem] = []
        for item in items {
            let haystack = SearchQuery.fold(haystack(for: item))
            let words = foldedWords(item.title)
            if tokens.allSatisfy({ haystack.contains($0) || fuzzyMatch(token: $0, words: words) }) {
                fuzzy.append(item)
            }
        }
        return fuzzy
    }

    /// Catalog entries named by the search, whether or not their cache exists on
    /// this machine. Same rules as the shipped 1.5.1 behaviour: both
    /// localizations, the relative path and the discipline.
    static func matchingSpecs(_ query: String) -> [ToolCacheSpec] {
        SearchQuery.matchingSpecs(query)
    }

    // MARK: - Dedicated scanners

    /// Scanner-managed caches (npm, pnpm, uv, Docker, Homebrew, Telegram,
    /// WhatsApp…) a search names. Their rows exist only when the cache exists on
    /// this Mac, so this list is what keeps "telegram" from finding nothing
    /// while the scanner has no row to show.
    static func scannerMatches(_ query: String) -> [ScannerCaches.Entry] {
        let tokens = SearchQuery.tokens(query)
        guard !tokens.isEmpty else { return [] }

        let haystacks = ScannerCaches.entries.map { entry in
            let synonyms = scannerSynonyms[entry.titleEn] ?? []
            return SearchQuery.fold(([entry.titleEn, entry.pathsEn, entry.howEn] + synonyms)
                .joined(separator: " "))
        }

        var exact: [ScannerCaches.Entry] = []
        for (index, entry) in ScannerCaches.entries.enumerated() where matchesAll(tokens, haystacks[index]) {
            exact.append(entry)
        }
        if !exact.isEmpty { return exact }

        guard tokens.contains(where: { $0.count >= 4 }) else { return [] }
        var fuzzy: [ScannerCaches.Entry] = []
        for (index, entry) in ScannerCaches.entries.enumerated() {
            let words = foldedWords(entry.titleEn + " " + entry.pathsEn)
            if tokens.allSatisfy({ haystacks[index].contains($0) || fuzzyMatch(token: $0, words: words) }) {
                fuzzy.append(entry)
            }
        }
        return fuzzy
    }

    /// Extra names a scanner entry answers to. The catalog has keywords for its
    /// rows; these entries do not, so the synonyms live next to the search code
    /// instead of being duplicated in `Models.swift`.
    private static let scannerSynonyms: [String: [String]] = [
        "npm": ["npm cache", "npm cacache", "node", "nodejs"],
        "pnpm": ["pnpm store", "pnpm store prune", "node"],
        "bun": ["bun cache", "bun pm cache", "node"],
        "uv": ["uv cache", "uv cache clean", "python", "pip"],
        "Docker": ["docker build cache", "docker builder prune", "docker images",
                   "dangling images", "container"],
        "Homebrew": ["brew", "brew cleanup", "brew cache"],
        "MacPorts": ["port", "port clean", "distfiles"],
        "IntelliJ IDEA": ["intellij", "jetbrains", "idea"],
        "nvim / jdtls": ["nvim", "neovim", "jdtls", "java"],
        "Telegram": ["telegram desktop", "telegram mac", "media cache", "медиа",
                     "telegram cache"],
        "WhatsApp": ["whatsapp web", "whatsapp desktop", "media cache", "whatsapp cache"],
        "iOS simulators": ["simulators", "xcrun simctl", "xcode", "ios"],
        "/private/tmp": ["tmp", "temporary files", "scratch"],
    ]

    // MARK: - Scan notes

    /// Notes that explain a search. An empty query returns the notes unchanged:
    /// the UI decides when a search is active, and "all notes" is the safe
    /// contract for the unfiltered case.
    static func matchingNotes(_ notes: [ScanNote], query: String) -> [ScanNote] {
        let tokens = SearchQuery.tokens(query)
        guard !tokens.isEmpty else { return notes }

        var exact: [ScanNote] = []
        for note in notes where matchesAll(tokens, SearchQuery.fold(noteHaystack(note))) {
            exact.append(note)
        }
        if !exact.isEmpty { return exact }

        guard tokens.contains(where: { $0.count >= 4 }) else { return [] }
        return notes.filter { note in
            let text = noteHaystack(note)
            let haystack = SearchQuery.fold(text)
            let words = foldedWords(text)
            return tokens.allSatisfy { haystack.contains($0) || fuzzyMatch(token: $0, words: words) }
        }
    }

    /// Single-note predicate: does this note answer the query? An empty query
    /// matches every note (matchingNotes' contract), and a token can match the
    /// note text, its category title, or a near-miss spelling of either.
    static func noteMatches(_ note: ScanNote, _ query: String) -> Bool {
        let tokens = SearchQuery.tokens(query)
        guard !tokens.isEmpty else { return true }
        let text = noteHaystack(note)
        let haystack = SearchQuery.fold(text)
        let words = foldedWords(text)
        return tokens.allSatisfy { haystack.contains($0) || fuzzyMatch(token: $0, words: words) }
    }

    private static func noteHaystack(_ note: ScanNote) -> String {
        "\(note.category.title) \(note.category.rawValue) \(note.text)"
    }

    // MARK: - Matching primitives

    /// Same list of fields as `haystack(for:)`, emitted straight into a
    /// lowercased byte buffer. Returns nil as soon as a non-ASCII byte appears:
    /// those rows need the full case/diacritic/width fold.
    private static func asciiHaystack(for item: CleanupItem) -> [UInt8]? {
        var out = [UInt8]()
        out.reserveCapacity(192)

        func append(_ text: String) -> Bool {
            for byte in text.utf8 {
                guard byte < 0x80 else { return false }
                out.append(byte >= 0x41 && byte <= 0x5A ? byte &+ 0x20 : byte)
            }
            out.append(0x20)
            return true
        }

        guard append(item.title),
              append(item.detail),
              append(item.category.title),
              append(item.category.rawValue) else { return nil }
        if let platform = item.platform {
            guard append(platform.title),
                  append(platform.englishTitle),
                  append(platform.chipTitle),
                  append(platform.rawValue) else { return nil }
        }
        if let warning = item.warning, !append(warning) { return nil }
        guard append(item.platformTag.chipTitle),
              append(item.platformTag.title) else { return nil }
        for keyword in item.keywords {
            if !append(keyword) { return nil }
        }
        return out
    }

    /// Equivalent of `CleanupItem.searchHaystack` built with one reserved
    /// string: the computed property allocates an array of 8–15 small strings
    /// per row, which costs more than the matching itself on a 20k-row list.
    /// `SearchChecks` asserts the two expose the same fields, so this fast path
    /// cannot silently drift from the model's definition.
    static func haystack(for item: CleanupItem) -> String {
        var out = ""
        out.reserveCapacity(192)
        out += item.title
        out += " "
        out += item.detail
        out += " "
        out += item.category.title
        out += " "
        out += item.category.rawValue
        if let platform = item.platform {
            out += " "
            out += platform.title
            out += " "
            out += platform.englishTitle
            out += " "
            out += platform.chipTitle
            out += " "
            out += platform.rawValue
        }
        if let warning = item.warning {
            out += " "
            out += warning
        }
        out += " "
        out += item.platformTag.chipTitle
        out += " "
        out += item.platformTag.title
        for keyword in item.keywords {
            out += " "
            out += keyword
        }
        return out
    }

    private static func matchesAll(_ tokens: [String], _ haystack: String) -> Bool {
        for token in tokens where !haystack.contains(token) { return false }
        return true
    }

    private static func matchesAll(_ tokens: [[UInt8]], _ haystack: [UInt8]) -> Bool {
        for token in tokens where !containsBytes(haystack, token) { return false }
        return true
    }

    /// Substring search over already-lowercased bytes: allocation-free and far
    /// cheaper than normalizing a Swift String for each of 20k rows.
    private static func containsBytes(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
        guard !needle.isEmpty else { return true }
        guard haystack.count >= needle.count else { return false }
        let lastStart = haystack.count - needle.count
        let first = needle[0]
        var start = 0
        while start <= lastStart {
            if haystack[start] == first {
                var offset = 1
                while offset < needle.count && haystack[start + offset] == needle[offset] {
                    offset += 1
                }
                if offset == needle.count { return true }
            }
            start += 1
        }
        return false
    }

    /// Folded words of a title/note: punctuation and the em dash are separators,
    /// so "WhatsApp media cache" yields ["whatsapp", "media", "cache"].
    private static func foldedWords(_ text: String) -> [String] {
        SearchQuery.fold(text)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }

    /// A token is "near" a word when they share the first four characters, or
    /// their edit distance is 1 (tokens of 5–7 characters) or 2 (8+).
    /// Tokens shorter than four characters never fuzzy-match: "pip" must not
    /// start pulling in unrelated rows.
    private static func fuzzyMatch(token: String, words: [String]) -> Bool {
        guard token.count >= 4 else { return false }
        let tokenChars = Array(token)
        let limit = token.count >= 8 ? 2 : 1
        for word in words {
            if sharesPrefix(token, word) { return true }
            guard token.count >= 5, abs(word.count - token.count) <= limit else { continue }
            if isNear(tokenChars, Array(word), maxDistance: limit) { return true }
        }
        return false
    }

    private static func sharesPrefix(_ lhs: String, _ rhs: String) -> Bool {
        lhs.count >= 4 && rhs.count >= 4 && lhs.prefix(4) == rhs.prefix(4)
    }

    /// Levenshtein distance with early exit: returns true as soon as the final
    /// distance is known to exceed `maxDistance`, so the common unrelated-word
    /// case costs one DP row, not a full matrix.
    private static func isNear(_ lhs: [Character], _ rhs: [Character], maxDistance: Int) -> Bool {
        guard !lhs.isEmpty, !rhs.isEmpty, abs(lhs.count - rhs.count) <= maxDistance else { return false }
        var previous = Array(0...rhs.count)
        var current = [Int](repeating: 0, count: rhs.count + 1)
        for row in 1...max(lhs.count, 1) {
            current[0] = row
            var rowMinimum = row
            for column in 1...max(rhs.count, 1) {
                let substitution = lhs[row - 1] == rhs[column - 1] ? 0 : 1
                current[column] = min(previous[column] + 1,
                                      current[column - 1] + 1,
                                      previous[column - 1] + substitution)
                rowMinimum = min(rowMinimum, current[column])
            }
            if rowMinimum > maxDistance { return false }
            swap(&previous, &current)
        }
        return previous[rhs.count] <= maxDistance
    }
}
