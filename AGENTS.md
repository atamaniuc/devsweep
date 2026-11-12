# AGENTS.md — DevSweep

macOS SwiftUI app that frees disk space by deleting only regenerable **developer
toolchain caches**. SwiftUI + a small C walker, no Xcode project, no third-party
dependencies.

## Build, test, release

```bash
./build.sh                          # universal arm64 + x86_64 (fails if a slice is missing)
ARCHS="$(uname -m)" ./build.sh      # host slice only, for quick iteration
./build/DevSweep.app/Contents/MacOS/DevSweep --self-test   # the release gate
```

- `--self-test` is the only gate that counts: allowlist, catalog breadth,
  README/catalog sync, delete path in `/private/tmp`, preview enumeration.
- Headless modes: `--scan`, `--audit`, `--preview <file>`, `--tools`,
  `--tools-md`, `--bench-delete`. `--audit` prints the catalog against the disk
  and exits 1 when an installed CLI has neither a catalog entry nor a scanner.
- Release: bump `CFBundleShortVersionString`/`CFBundleVersion` in `Info.plist`,
  add a `## <version>` section to `CHANGELOG.md`, commit, push, then push tag
  `v<version>`. `.github/workflows/release.yml` builds, tests, zips
  `DevSweep-<version>.zip` and creates/updates the GitHub release; it fails when
  the version has no changelog section.
- CI runs on `macos-latest` on purpose: `macos-13`, `macos-14` and `macos-15`
  are refused for this repository ("configuration ... is not supported") while
  `macos-latest` schedules fine (Apple silicon, cross-builds the Intel slice).

## Rules that bite

- **The catalog is the product** (142 caches in 7 disciplines as of 1.5.1: web,
  mobile, desktop, embedded, cloud, Web3, data/ML). A new cache is one
  `make(...)` entry in `ToolCaches.specs` (`Sources/Models.swift`); it
  automatically drives scanning, the allowlist, the preview, the UI grouping and
  the generated README table. Never hand-edit the README table:
  `./scripts/update-readme-tools.sh` regenerates it from the binary and
  `--self-test` fails when they differ.
- **Every toolchain path must be regenerable.** If deleting it makes the user
  re-download or rebuild something slow, it belongs in `advanced: true` with a
  `warning`. Never add a directory that can contain user work.
- **The allowlist is the only thing between a checkbox and user data**
  (`Cleaner.isAllowed`): absolute paths, no `..`, no symlinks, never
  `node_modules`/`.git`, fixed command whitelist with hard timeouts.
- **Deletion is syscall-bound.** Do not "optimise" it by rewriting the walker in
  another language; `--bench-delete` shows FileManager, `/bin/rm -rf` and the C
  walker within noise.
- **Release artifacts must be universal** (Intel + Apple silicon); `build.sh`
  already enforces both slices.
- **Selection is a ledger, not `items.filter`** (`SelectionLedger`): the
  header's "can be freed" number reads a running `bytes`/`count` so a checkbox
  click is O(1). Advanced rows are shown but *not* preselected — visible is not
  the same as selected, and an unread warning must never be one click from
  deletion.
- **`Show plan` must not walk before it shows anything.** `PreviewBuilder.plan`
  builds the sheet from sizes the scan already has; `PreviewBuilder.scanFiles`
  walks one target only when its row is expanded, and the row renders pages of
  100. Saving the report walks everything, with a spinner — that is the only
  place a full walk is justified.
- **Every row owns a brand glyph.** `ToolBrand.rules` maps catalog paths to an
  SF Symbol + tint; when the tool ships a GUI app the real macOS icon is used
  via its bundle id. `--self-test` fails on an uncurated spec or a missing SF
  Symbol on the running macOS (e.g. `hardhat.fill` does not exist on macOS 13).
- **Scanner-managed caches are documented too.** `ScannerCaches.entries` (npm,
  pnpm, bun, uv, Docker, Homebrew, MacPorts, IntelliJ, nvim/jdtls, Telegram,
  WhatsApp, simulators, /private/tmp) is rendered into the README's "Also cleaned
  by dedicated scanners" section; a path spec would be wrong for them (commands,
  runtime checks, versioned stores). Omitting them made users read the catalog as
  the whole story and report "uv missing".
- **Wildcards are supported but narrow**: `~/.gem/ruby/*/cache` expands to one
  row per installed version; the allowlist opens the pattern's parent, the row's
  concrete path is what gets deleted, and the row title carries the version.
- **A catalog entry that can never exist on macOS is noise.** Three Linux-only
  paths (`.cache/deno`, `.cache/yarn`, `.cache/parcel`) were removed after the
  audit; do not add XDG paths to a macOS app unless the tool really uses them
  here (`.rustup`, `.gem`, `.julia`, `.sccache` are cross-platform, `.cache/uv`
  is scanner-managed because the path exists on macOS too).
- **Project-local caches are never cleaned**: `.next/cache`, `.angular/cache`,
  `.turbo`, `node_modules/.cache/*`, `_build`, `target`, `var/cache`,
  `storage/framework`, Godot's `.godot` live inside repositories. Cleaning them
  would delete a build state the user may be mid-way through; keep them out of
  the catalog and say so in the README.
- **pnpm stores are versioned**: `pnpm store path` names the current store; other
  version dirs under `~/Library/pnpm/store` are unreachable and can be removed
  (4.7 GB of v11 next to a 1.0 GB v10 on this Mac). They are separate rows with
  an `advanced`-style warning, not part of `pnpm store prune`.
- **Installed-but-unsupported is a bug, not a surprise.** `ToolCoverage` lists
  every CLI known to be worth detecting; `--self-test` fails when one installed
  here maps to neither the catalog nor a dedicated scanner. When a user says
  "Terraform is missing", run `--audit` first: the entry may be absent from the
  catalog, or simply absent from the disk (the header now shows both numbers).
- **Sizes are decimal**: `humanBytes` prints GB/MB/KB (1 GB = 1e9 B) to match
  Finder, though every size stays in bytes internally (`du -sk` × 1024).
- **UI verification is possible without a build-time harness**: grant
  Accessibility to the shell, then drive the running app with System Events —
  `AXPress` on `AXLink`/`AXCheckBox`/`AXButton` elements and read `value of
  every static text` to assert that e.g. unchecking a row changes "can be
  freed" 25.6 GB → 25.5 GB. Window positions move between calls, so re-read
  `position of window 1` before using `click at`.
- **A scan must reset the list to the top.** An `NSScrollView` whose content
  grows from empty keeps the old bottom anchor, so a fresh result used to open
  mid-list; `ContentView` scrolls to `listTopID` after the phase returns to
  `.idle` (deferred, the rows are not laid out yet in the same runloop turn).
- **Screenshots: window-only.** Capture the app window by CGWindowID
  (`screencapture -x -l <id>`), never a full-screen capture — the background can
  contain private windows. Verify the image before committing it to `docs/`.
- UI strings are localized through `L(ru, en)`; the UI follows the system
  language. Repository artifacts (README, CHANGELOG, docs) are English.
