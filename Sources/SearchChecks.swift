import Foundation

/// Checks for the search stream: exact folded matching, the keyword/platform
/// surface, the zero-result fuzzy fallback, scanner and note lookup, and the
/// 20k-row performance budget. Pure in-memory probes only, plus a
/// machine-tolerant check against the notes this Mac's Telegram/WhatsApp
/// scanners return right now (skipped when there is no such note).
enum SearchChecks {
    static func all() -> [(String, Bool)] {
        var checks: [(String, Bool)] = []
        func expect(_ condition: Bool, _ label: String) { checks.append((label, condition)) }

        // MARK: Synthetic rows

        let telegram = makeItem(title: "Telegram media cache", category: .telegram)
        let whatsapp = makeItem(title: "WhatsApp cache", category: .whatsapp)
        let docker = makeItem(title: "Build cache older than 24 hours",
                              detail: "docker builder prune --filter until=24h",
                              keywords: ["docker", "build cache"], platform: .web)
        let solana = makeItem(title: "Solana toolchain cache", platform: .web3)
        let puppeteer = makeItem(title: "Puppeteer browsers", platform: .web)
        let accent = makeItem(title: "Résumé models", platform: .other)
        let uv = makeItem(title: "Кэш uv", detail: "~/.cache/uv",
                          keywords: ["uv cache", "python"], platform: .web)
        let noPlatform = makeItem(title: "npm cache (_cacache)", category: .npm)
        let rows = [telegram, whatsapp, docker, solana, puppeteer, accent, uv, noPlatform]

        // Exact matching: single word, folded case, detail/keywords, chip names.
        expect(SearchIndex.filter(rows, query: "telegram").map(\.id) == [telegram.id],
               "search: exact title word finds the row")
        expect(SearchIndex.filter(rows, query: "TELEGRAM").map(\.id) == [telegram.id],
               "search: case-insensitive folding")
        expect(SearchIndex.filter(rows, query: "resume").map(\.id) == [accent.id],
               "search: diacritic-insensitive folding")
        expect(SearchIndex.filter(rows, query: "python").map(\.id) == [uv.id],
               "search: catalog keywords are searchable")
        expect(SearchIndex.filter(rows, query: "web3").map(\.id) == [solana.id],
               "search: discipline platform word is searchable")
        // "other" finds the row through its chip title (row has no platform)
        // and also the Data/ML row through `ToolPlatform.other.rawValue`.
        let otherHits = SearchIndex.filter(rows, query: "other")
        expect(otherHits.contains { $0.id == noPlatform.id }
               && otherHits.contains { $0.id == accent.id },
               "search: chip name is searchable")
        expect(SearchIndex.filter(rows, query: "builder prune").map(\.id) == [docker.id],
               "search: multi-word AND over the detail")
        expect(SearchIndex.filter(rows, query: "telegram solana").isEmpty,
               "search: multi-word AND does not widen")
        expect(SearchIndex.filter(rows, query: "   ").count == rows.count,
               "search: empty query returns every row")

        // Fuzzy fallback: only when the exact pass found nothing.
        expect(SearchIndex.filter(rows, query: "whatsup").map(\.id) == [whatsapp.id],
               "search: typo 'whatsup' finds WhatsApp")
        expect(SearchIndex.filter(rows, query: "solona").map(\.id) == [solana.id],
               "search: one-edit typo 'solona' finds Solana")
        expect(SearchIndex.filter(rows, query: "whatsup cache").map(\.id) == [whatsapp.id],
               "search: fuzzy works per token with a multi-word query")
        expect(SearchIndex.filter(rows, query: "pip").isEmpty,
               "search: short token 'pip' is exact-only (no fuzzy false positives)")
        let nearMissRows = [makeItem(title: "Solana toolchain cache"),
                            makeItem(title: "Solona toolchain cache")]
        let exactOnly = SearchIndex.filter(nearMissRows, query: "solana")
        expect(exactOnly.count == 1 && exactOnly.first?.title == "Solana toolchain cache",
               "search: fuzzy never loosens a query that already matched exactly")
        let longWordRows = [makeItem(title: "Abcdefgh cache")]
        expect(SearchIndex.filter(longWordRows, query: "abXdefYh").count == 1,
               "search: two edits are allowed for 8+ character tokens")

        // SearchIndex.haystack(for:) duplicates the field list of the model's
        // `searchHaystack` for speed; a model change would otherwise silently
        // make some column unsearchable.
        let warningProbe = CleanupItem(category: .devtools, title: "Probe cache", detail: "",
                                       sizeBytes: 0,
                                       action: .remove(URL(fileURLWithPath: "/private/tmp/search-check")),
                                       warning: "needs admin password",
                                       platform: .cloud, keywords: ["kwprobe"])
        let haystackProbes = [docker, uv, accent, noPlatform, warningProbe]
        let haystackTokens = ["docker", "cache", "python", "resume", "web", "cloud",
                              "password", "kwprobe", "other"]
        var haystackAgrees = true
        for probe in haystackProbes {
            let fast = SearchIndex.haystack(for: probe).lowercased()
            let model = probe.searchHaystack.lowercased()
            for token in haystackTokens where fast.contains(token) != model.contains(token) {
                haystackAgrees = false
            }
        }
        expect(haystackAgrees, "search: fast haystack exposes the same fields as searchHaystack")

        // MARK: Catalog

        let terraform = SearchIndex.matchingSpecs("terraform")
        expect(terraform.contains { $0.titleEn == "Terraform: update-check cache" },
               "search: catalog specs match 'terraform'")
        expect(SearchIndex.matchingSpecs("Terraform").count == terraform.count,
               "search: catalog spec matching is case-insensitive")
        expect(SearchIndex.matchingSpecs("").isEmpty, "search: empty catalog query finds nothing")

        // MARK: Dedicated scanners

        expect(SearchIndex.scannerMatches("telegram").map(\.titleEn) == ["Telegram"],
               "search: scanner list names Telegram")
        expect(SearchIndex.scannerMatches("telegram desktop").map(\.titleEn) == ["Telegram"],
               "search: scanner synonym 'telegram desktop'")
        expect(SearchIndex.scannerMatches("whatsapp").map(\.titleEn) == ["WhatsApp"],
               "search: scanner list names WhatsApp")
        expect(SearchIndex.scannerMatches("whatsup").map(\.titleEn) == ["WhatsApp"],
               "search: typo 'whatsup' finds the WhatsApp scanner entry")
        expect(SearchIndex.scannerMatches("uv cache").map(\.titleEn) == ["uv"],
               "search: scanner synonym 'uv cache'")
        expect(SearchIndex.scannerMatches("docker build cache").map(\.titleEn) == ["Docker"],
               "search: scanner synonym 'docker build cache'")
        expect(SearchIndex.scannerMatches("pnpm store").map(\.titleEn) == ["pnpm"],
               "search: scanner synonym 'pnpm store'")
        expect(SearchIndex.scannerMatches("brew").map(\.titleEn) == ["Homebrew"],
               "search: scanner synonym 'brew'")
        expect(SearchIndex.scannerMatches("").isEmpty, "search: empty scanner query finds nothing")

        // MARK: Notes

        let telegramNote = ScanNote(category: .telegram,
                                    text: "Telegram запущена — закройте её, чтобы очистить медиа-кэш")
        let whatsappNote = ScanNote(category: .whatsapp,
                                    text: "WhatsApp запущен — закройте его, чтобы очистить кэш")
        let dockerNote = ScanNote(category: .docker,
                                  text: "Docker Desktop не запущен — Docker-очистка пропущена")
        let notes = [telegramNote, whatsappNote, dockerNote]

        expect(SearchIndex.matchingNotes(notes, query: "telegram").map(\.id) == [telegramNote.id],
               "search: 'telegram' finds the synthetic running-app note")
        expect(SearchIndex.matchingNotes(notes, query: "медиа").map(\.id) == [telegramNote.id],
               "search: note text is searchable (Russian word)")
        expect(SearchIndex.matchingNotes(notes, query: "docker").map(\.id) == [dockerNote.id],
               "search: note matches on its category title text")
        expect(SearchIndex.matchingNotes(notes, query: "whatsup").map(\.id) == [whatsappNote.id],
               "search: note lookup has the same typo tolerance")
        expect(SearchIndex.matchingNotes(notes, query: "kubernetes").isEmpty,
               "search: unrelated query finds no note")
        expect(SearchIndex.matchingNotes(notes, query: "").count == notes.count,
               "search: empty note query returns the notes unchanged")
        expect(SearchIndex.noteMatches(telegramNote, "telegram"),
               "search: single-note predicate matches its own text")
        expect(!SearchIndex.noteMatches(telegramNote, "kubernetes"),
               "search: single-note predicate rejects unrelated text")
        expect(SearchIndex.noteMatches(telegramNote, ""),
               "search: single-note predicate treats an empty query as match-all")

        // Machine-tolerant: if the real scanners produce a note on this Mac, the
        // matching query must find it. No note (cache found and app not running,
        // or nothing installed) means there is nothing to assert.
        let (_, telegramNotes) = ScanEngine.scanTelegram()
        if let note = telegramNotes.first {
            expect(SearchIndex.matchingNotes(telegramNotes, query: "telegram").contains { $0.id == note.id },
                   "search: this Mac's real Telegram note answers 'telegram'")
        }
        let (_, whatsappNotes) = ScanEngine.scanWhatsapp()
        if let note = whatsappNotes.first {
            expect(SearchIndex.matchingNotes(whatsappNotes, query: "whatsapp").contains { $0.id == note.id },
                   "search: this Mac's real WhatsApp note answers 'whatsapp'")
        }

        // MARK: Performance

        var stress: [CleanupItem] = []
        stress.reserveCapacity(20_000)
        for index in 0..<20_000 {
            stress.append(makeItem(title: "Synthetic cache \(index)",
                                   detail: "~/Library/Caches/synthetic/\(index)",
                                   keywords: ["synthetic", "cache"],
                                   platform: .web))
        }
        let start = DispatchTime.now()
        let hits = SearchIndex.filter(stress, query: "synthetic")
        let elapsedMS = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
        expect(hits.count == stress.count, "search: 20k-row exact query returns every row")
        expect(elapsedMS < 100, "search: 20k-row exact query stays under 100 ms")
        print(String(format: "  search: 20,000 rows, exact query %.1f ms", elapsedMS))

        return checks
    }

    private static func makeItem(title: String,
                                 detail: String = "",
                                 keywords: [String] = [],
                                 category: CleanupCategory = .devtools,
                                 platform: ToolPlatform? = nil) -> CleanupItem {
        CleanupItem(category: category,
                    title: title,
                    detail: detail,
                    sizeBytes: 1024,
                    action: .remove(URL(fileURLWithPath: "/private/tmp/search-check")),
                    platform: platform,
                    keywords: keywords)
    }
}
