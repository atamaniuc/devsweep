import Foundation
import AppKit

/// Self-test checks for the clickable discipline chips: the tag model, the pure
/// filter the buttons call, and the speed of both over a full-size scan result.
/// The SwiftUI row itself is verified through the build and the window; this file
/// covers exactly the logic behind it, so `--self-test` fails if a chip stops
/// matching the catalog or starts costing time.
enum FilterChecks {
    static func all() -> [(String, Bool)] {
        var checks: [(String, Bool)] = []
        func check(_ label: String, _ ok: Bool) { checks.append((label, ok)) }

        // MARK: - The eight chips

        let expectedOrder: [PlatformTag] = [.web, .mobile, .desktop, .embedded,
                                            .cloud, .web3, .dataML, .other]
        check("chip row has eight tags in catalog order",
              PlatformTag.allCases == expectedOrder)
        check("every chip has a non-empty title, short label and SF Symbol",
              PlatformTag.allCases.allSatisfy {
                  !$0.chipTitle.isEmpty && !$0.title.isEmpty && !$0.systemImage.isEmpty
              })
        check("the eight chip labels are unique",
              Set(PlatformTag.allCases.map(\.chipTitle)).count == PlatformTag.allCases.count)
        check("every chip SF Symbol exists on this macOS",
              PlatformTag.allCases.allSatisfy {
                  NSImage(systemSymbolName: $0.systemImage, accessibilityDescription: nil) != nil
              })
        check("chip titles follow the catalog platform titles",
              PlatformTag.allCases.allSatisfy { tag in
                  guard let platform = tag.toolPlatform else {
                      return tag.title == L("Другое (система и приложения)",
                                            "Other (system and apps)")
                  }
                  return tag.title == platform.title && tag.chipTitle == platform.chipTitle
              })

        // MARK: - Other is the catch-all, Data/ML is a discipline

        check("rows without a platform fall into the Other chip",
              PlatformTag.tag(for: nil) == .other)
        check("catalog Data/ML (ToolPlatform.other) maps to Data/ML, not Other",
              PlatformTag.tag(for: .other) == .dataML)
        check("each catalog platform maps to its own chip",
              Set(ToolPlatform.allCases.map { PlatformTag.tag(for: $0) }).count
                  == ToolPlatform.allCases.count)

        func probe(_ platform: ToolPlatform?, _ size: Int64) -> CleanupItem {
            CleanupItem(category: platform == nil ? .telegram : .devtools,
                        title: "probe \(platform?.rawValue ?? "scanner")",
                        detail: "/private/tmp/probe",
                        sizeBytes: size,
                        action: .remove(URL(fileURLWithPath: "/private/tmp/probe")),
                        platform: platform)
        }

        let web = probe(.web, 1_000)
        let mobile = probe(.mobile, 2_000)
        let desktop = probe(.desktop, 3_000)
        let embedded = probe(.embedded, 4_000)
        let cloud = probe(.cloud, 5_000)
        let web3 = probe(.web3, 6_000)
        let dataML = probe(.other, 7_000)
        let scanner = probe(nil, 8_000)
        let items = [web, mobile, desktop, embedded, cloud, web3, dataML, scanner]

        check("scanner rows (platform == nil) land in Other",
              scanner.platform == nil && scanner.platformTag == .other)
        check("Data/ML rows are not merged into Other", dataML.platformTag == .dataML)
        check("Other and Data/ML read differently in the UI",
              PlatformTag.other.chipTitle != PlatformTag.dataML.chipTitle
                  && PlatformTag.other.title != PlatformTag.dataML.title)

        // MARK: - Partition: every found row belongs to exactly one chip

        let stats = PlatformFilter.stats(items)
        check("every found row belongs to exactly one chip",
              stats.values.reduce(0) { $0 + $1.count } == items.count)
        check("each chip counts its own rows",
              PlatformTag.allCases.allSatisfy { stats[$0]?.count == 1 })
        check("each chip sums the bytes of its own rows",
              stats[.web]?.bytes == 1_000 && stats[.mobile]?.bytes == 2_000
                  && stats[.desktop]?.bytes == 3_000 && stats[.embedded]?.bytes == 4_000
                  && stats[.cloud]?.bytes == 5_000 && stats[.web3]?.bytes == 6_000
                  && stats[.dataML]?.bytes == 7_000 && stats[.other]?.bytes == 8_000)
        check("a group with no rows has no stats entry",
              PlatformFilter.stats([web])[.cloud] == nil
                  && PlatformFilter.stats([web])[.other] == nil)
        check("an empty scan result has empty stats",
              PlatformFilter.stats([]).isEmpty)

        // MARK: - Filter semantics

        check("no selected chip keeps every row",
              PlatformFilter.apply(items, tags: []).map(\.id) == items.map(\.id))
        check("one chip keeps only its own group",
              PlatformFilter.apply(items, tags: [.web]).map(\.id) == [web.id])
        check("two chips are ORed into a union",
              Set(PlatformFilter.apply(items, tags: [.cloud, .other]).map(\.id))
                  == Set([cloud.id, scanner.id]))
        check("Other catches scanner rows and nothing else",
              PlatformFilter.apply(items, tags: [.other]).map(\.id) == [scanner.id])
        check("Data/ML is not part of the Other filter",
              !PlatformFilter.apply(items, tags: [.other]).contains { $0.id == dataML.id })
        check("all eight chips together keep every row",
              PlatformFilter.apply(items, tags: Set(PlatformTag.allCases)).count == items.count)
        check("filtering an empty list is empty",
              PlatformFilter.apply([], tags: [.web]).isEmpty
                  && PlatformFilter.apply([], tags: []).isEmpty)

        // MARK: - Speed: the row is rebuilt on every body pass, so it must stay
        // far below a frame even on a scan result much larger than this Mac's.

        var perfItems: [CleanupItem] = []
        perfItems.reserveCapacity(20_000)
        let platforms = ToolPlatform.allCases
        for index in 0..<20_000 {
            perfItems.append(probe(platforms[index % platforms.count], Int64(index)))
        }
        let expectedUnion = perfItems.reduce(0) { partial, item in
            let tag = item.platformTag
            return partial + ((tag == .web || tag == .cloud) ? 1 : 0)
        }

        let statsStart = Date()
        var statsCount = 0
        for _ in 0..<3 { statsCount = PlatformFilter.stats(perfItems).values.reduce(0) { $0 + $1.count } }
        let statsMillis = Date().timeIntervalSince(statsStart) * 1000 / 3

        let applyStart = Date()
        var applied = 0
        for _ in 0..<3 { applied = PlatformFilter.apply(perfItems, tags: [.web, .cloud]).count }
        let applyMillis = Date().timeIntervalSince(applyStart) * 1000 / 3

        print(String(format: "chip filter: stats %.2f ms, apply %.2f ms for 20,000 rows",
                     statsMillis, applyMillis))
        check("chip stats stay instant on 20,000 rows (< 100 ms)", statsMillis < 100)
        check("chip filtering stays instant on 20,000 rows (< 100 ms)", applyMillis < 100)
        check("20,000-row stats cover every row", statsCount == 20_000)
        check("20,000-row filter keeps the union of two chips", applied == expectedUnion)

        return checks
    }
}
