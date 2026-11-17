# Changelog

## 1.6.2 — 2026-11-17

WhatsApp (and Telegram) are now actually detected, including the media that
WhatsApp 26.x keeps outside the app container.

### Fixed

- **WhatsApp 26.x media was invisible.** The scanner looked at
  `~/Library/Containers/net.whatsapp.WhatsApp/Data/Library/Caches` (360 KB here)
  while downloaded chat media lives in the shared group container:
  `~/Library/Group Containers/group.net.whatsapp.WhatsApp.shared/Message/Media`
  (149 MB here). That path is now scanned as its own advanced row ("WhatsApp
  media: photos and videos") and is explicitly opened in the deletion
  allowlist — only `Message/Media`, never the container root that holds the
  message database.
- **"Not detected" while the app was running.** The messenger scanners used to
  return no rows at all when Telegram/WhatsApp were open; searching for them
  showed only a note and the app looked unsupported. Both now always return
  their rows, each carrying a "quit it before cleaning" warning plus the
  explanatory note. Verified with both apps running on this Mac:
  `whatsapp 149114880 WhatsApp media: photos and videos`,
  `whatsapp 368640 WhatsApp cache`, `telegram 4250955776 Telegram media cache`.

### Verification

- `--self-test`: 311 PASS, 0 FAIL. New checks: the media path is measured on
  this machine (149 MB), becomes a removable row, passes the allowlist, and the
  shared container root is refused; scan notes still match which app really runs.
- `--scan` prints the WhatsApp rows while WhatsApp is running.

## 1.6.1 — 2026-11-17

A search for a messenger must not claim the app is running when it is not.

### Fixed

- **"WhatsApp is running" while it was closed.** The scanner used `pgrep -f
  WhatsApp.app`, which also matched WhatsApp's background ServiceExtension
  (`/Applications/WhatsApp.app/Contents/PlugIns/ServiceExtension`): the cache
  was skipped and the note said the app was running even after the user quit
  it. The check now compares the exact process name (`pgrep -x WhatsApp`), so a
  closed app exposes its cache and only a really running app is skipped.
- **Empty caches say so.** When the Telegram/WhatsApp cache directory exists
  but is empty, the scan now emits a note ("WhatsApp cache is empty — nothing
  to clean") instead of silence, so searching for the tool explains the state
  instead of looking like missing support.
- **`whatsup` resolves to WhatsApp**: the fuzzy fallback matched the title
  ("WhatsApp cache") via the shared `what` prefix and the scanner list by
  synonym; self-test now pins both the typo lookup and the "closed app emits no
  running note" rule.

### Verification

- `--self-test`: 305 PASS, 0 FAIL (adds process/note consistency checks and a
  fuzzy "whatsup" lookup); `--scan` on this machine now prints
  `note whatsapp: WhatsApp cache is empty — nothing to clean` with WhatsApp
  closed, and `note telegram: Telegram is running — …` with Telegram open.

## 1.6.0 — 2026-11-17

The window becomes a real control panel: sort it, filter it with the discipline
tags, search everything the app knows, and configure low-disk alerts and presets
in a proper Settings window.

### Added — sorting

- **Asc/desc by size or name**, in the main window and in the dry-run sheet.
  Sorting ignores the discipline grouping: rows are one flat, globally sorted
  list (Safe and Advanced stay separate sections because the risk separation is
  not a category). One click on the arrow flips the direction.
- Sorting is a pure in-memory operation over the scan result. It was measured
  at 8.4 ms for 20,000 rows after switching the comparator to sort indices
  instead of copying whole `CleanupItem` values (~535 ms before); the dry-run
  sheet sorts its targets instantly and its file lists through a cached sort
  (off the main thread above 5,000 rows, so a 200k-file name sort cannot freeze
  the sheet).
- The plan opens at the top of the list again: a growing `LazyVStack` in the
  sheet kept the bottom anchor and opened "Show plan" at its smallest rows.

### Added — clickable discipline chips

- The header tags now count what was **found here** and are filters: Web,
  Mobile, Desktop, Embedded, Cloud, Web3, Data/ML and the new **Other**
  catch-all for rows without a discipline (npm, pnpm, bun, uv, Docker, brew,
  MacPorts, IntelliJ, Telegram, WhatsApp, temporary files). Chips are
  multi-select (union), "All" clears, zero-row chips stay visible and dimmed,
  counts are one O(n) pass and filtering never touches the disk. The row wraps
  to two balanced rows at the 940 pt minimum width.
- The search counter says "N of M shown" when a chip filter is active, not only
  when the search box is used.

### Added — search covers everything the app knows

- Dedicated-scanner rows carry keywords, so `uv`, `docker`, `brew`, `pnpm` and
  friends find them.
- `ScannerCaches` entries are searchable, and scan **notes** are too: searching
  `telegram` / `whatsapp` now answers with "Telegram is running — quit it to
  clean the media cache" instead of "nothing matches".
- A fuzzy fallback runs only when the exact pass finds nothing (edit distance
  for tokens of 5+ characters, a 4-character shared prefix otherwise), so
  `whatsup` finds WhatsApp; exact results never get looser. 20,000 rows filter
  in ~33 ms.

### Added — Settings (⌘,)

- **Low-disk alerts**: enable, threshold slider (1–100 GB), check interval
  (5/15/30/60 min), "open DevSweep when the alert fires", a real `NSAlert` with
  free space, threshold and what the current selection could free, and a
  Test alert button. Hysteresis re-arms only after free space rises 10% above
  the threshold, so the alert does not repeat every tick.
- **Background checks**: an optional launch agent
  (`~/Library/LaunchAgents/com.atamaniuc.devsweep.alert.plist`) runs the app
  with `--disk-check`; nothing is installed unless the user flips the toggle.
- **View presets**: save the current chips + search + advanced/dry-run switches
  + sort under a name, apply any preset, and pick the default that the app
  restores on launch.
- Settings persist immediately in `UserDefaults` and the alert monitor re-reads
  them every tick, so changes take effect without relaunching.

### Verification

- `--self-test`: **301 PASS, 0 FAIL** (was 153), including 33 sort checks,
  27 chip checks, 40 search checks and 47 settings checks; sort 20k in 8.4 ms,
  search 20k in ~33 ms, chip stats/apply 20k in ~7 ms.
- `--disk-check` prints the decision and exits 0 (`alerts=off decision=disabled`
  on a clean install).
- Universal release: `x86_64 arm64`, `--audit` exit 0, README tool table
  matches the compiled catalog.

## 1.5.1 — 2026-11-13

The catalog grows to **142 caches** and the docs stop hiding the ones a scanner
handles (that is why "uv" and "npm" looked missing).

### Added — broader, audit-driven coverage

- **142 toolchain caches** (was 108). New entries were chosen from what
  developers actually install and verified against the tools' own cache
  conventions: IDE/Electron caches (VS Code GPU + cached VSIX, Cursor GPU cache,
  Windsurf, Antigravity, Zed), Android Studio IDE caches (versioned pattern),
  Godot export templates, minikube cached images, kubectl HTTP cache, Ansible
  temp files, Vagrant boxes (advanced), sbt launchers, Gradle daemon state,
  Ruby gem cache (`~/.gem/ruby/*/cache`) and gem metadata, JAX, Keras, CUDA
  compute cache, Triton kernels, Jupyter and Hugging Face datasets.
- **Wildcard catalog paths** (`~/.gem/ruby/*/cache`): a versioned cache becomes
  one row per installed version, each named after its version and each passing
  the allowlist through the pattern's parent directory.
- **pnpm stale stores**: on this Mac `pnpm store path` is v10 (1.0 GB) while
  v11 (4.7 GB) is unreachable for the current pnpm. The scanner now reports the
  stale store versions as removable rows instead of silently ignoring 4.7 GB.
- **Scanner-managed caches are documented**: the generated README section now
  lists npm, pnpm, bun, uv, Docker, Homebrew, MacPorts, IntelliJ, nvim/jdtls,
  Telegram, WhatsApp, simulators and `/private/tmp` — all supported, none of
  them expressed as a path spec. `--self-test` fails if that section disappears.
- Removed three Linux-only paths (`.cache/deno`, `.cache/yarn`, `.cache/parcel`)
  that can never exist on macOS; catalog entries that can never match are noise,
  not coverage.

### Note — what is deliberately *not* cleaned

Project-local caches live inside your repositories and are never touched:
`.next/cache`, `.angular/cache`, `.turbo`, `node_modules/.cache` (Webpack, Nx,
Metro, Vite), `_build` (Mix), `target` (Rust/dbt), `var/cache` (Symfony),
`storage/framework` (Laravel), Godot's project cache. Cleaning those would mean
deleting build artifacts of a project the user may be mid-way through; the app
only removes user-level caches that the tool itself recreates.

## 1.5.0 — 2026-11-13

The window becomes a live control panel: what is free, what the checked rows
would free, what is actually on this Mac, and it opens instantly.

### Added — selection, plan and search

- **Two live numbers in the header**: `free on disk` and `can be freed`. The
  second one follows every checkbox click in O(1) (a selection ledger keeps the
  running total, so it never re-sums or re-scans the list; 20,000 toggles take
  ~3 ms in `--self-test`).
- **Check all / Uncheck all** replace the single "clear selection" link. Both act
  on the rows visible right now, so they respect the search filter.
- **Instant search** by tool, path, warning or discipline (`web3`, `cloud`,
  `gradle`, `pip`), with multi-word AND. `⌘F` focuses it, a miss shows the
  supported-but-absent tools instead of an empty list.
- **Advanced categories and dry run are on by default**; advanced rows are shown
  but *not* preselected, so an accidental "clean" cannot touch data whose
  warning the user has not read.

### Added — honest catalog coverage

- The header now says both numbers: **catalog of 108 caches** and **N found
  here**. A missing tool reads as "nothing to clean on this Mac", not as an app
  that forgot about it.
- Ten real gaps found by auditing this machine against the catalog are closed:
  macOS node-gyp headers (`~/Library/Caches/node-gyp`, 131 MB here), bun's
  compile cache, Prisma engines, VS Code ripgrep and GitHub Copilot caches,
  `.ivy2/jars`, pkg binaries, `gh` cache, and Terraform's update-check cache.
  Terraform itself is not installed here, but `~/.terraform.d` exists and is now
  detected.
- `--audit` prints the catalog against the disk (found/absent, sizes) and fails
  when an installed CLI has neither a catalog entry nor a dedicated scanner.
  `--self-test` runs the same coverage check, so the next missing tool fails the
  build instead of waiting for a user to notice.

### Changed — modern look, readable type

- Larger typography across the header, rows, section headers and log; secondary
  text (free-on-disk labels, counts, hints) is 13-13.5 pt instead of 11-12 pt.
- Rows are cards with a hover state, a 36 px brand glyph and the size in
  semibold rounded digits. Rows for tools with a GUI app (Docker, VS Code,
  Cursor, Xcode, Unity, Telegram, WhatsApp, IntelliJ) use the app's real macOS
  icon; the rest use a per-tool SF Symbol in the brand colour (Rust orange,
  npm red, Flutter blue, Supabase green...). `--self-test` refuses a catalog
  entry without a curated glyph or a glyph that is not a real SF Symbol here.
- **Decimal units**: GB/MB/KB everywhere (1 GB = 1,000,000,000 bytes), matching
  Finder and the drive vendors, instead of GiB/MiB.

### Fixed — "Show plan" no longer freezes

- The sheet used to walk every selected cache before it appeared (~16 s for
  286k files) and then build file rows for every target up front. Now the plan
  opens immediately from the sizes the scan already has; a row's file list is
  walked only when that row is expanded, shows a spinner while counting, and is
  rendered in pages of 100 (with "show 200 more" / "show the first 2,000").
  Saving the report still produces the complete list, with a progress indicator.
- Self-test: the plan is built in ~0.07 ms for 28 rows in `--self-test`.

## 1.4.0 — 2026-11-13

Two new disciplines, and the release pipeline now publishes itself.

### Added — Cloud & infrastructure and Web3 & blockchain groups

- The catalog grows to **99 toolchain caches** with two new groups in the UI and
  in the generated table:
  - **Cloud & infrastructure (13)**: AWS CLI credential and SSO token caches,
    gcloud logs, Azure CLI logs, Pulumi provider plugins and logs, Supabase
    downloaded artifacts/binaries/CLI traces, Cloudflare Wrangler cache,
    Terraform plugin cache, Helm chart cache, kubectl discovery cache.
  - **Web3 & blockchain (7)**: Foundry forge cache, Solana build cache,
    Hardhat compilers cache, and the solc toolchains svm, solc-select,
    py-solc-x plus Anchor's AVM versions (advanced: re-downloaded on the next
    build).
- Helm, kubectl and Terraform moved from "Data, ML & cloud" into the new Cloud
  group; "Data, ML & cloud" is now "Data & ML".
- Every new path was checked before shipping: the Supabase layout is taken from
  the CLI's own state-layout doc (`artifacts/`, `bin/`, `traces/` under
  `SUPABASE_HOME`), the Wrangler cache from `workers-sdk`'s config-cache
  implementation (`<config>/cache`), and the Hardhat cache from its
  `env-paths("hardhat")` call (`~/Library/Caches/hardhat-nodejs`).

### Added — releases happen on push

- `.github/workflows/release.yml` now runs on `macos-latest` (the `macos-13`,
  `macos-14` and `macos-15` labels are refused for this repository with
  "configuration ... is not supported"). Pushing a `v*` tag builds, self-tests,
  zips and publishes the release; re-runs update it in place.
- Verified end to end with 1.3.0: the artifact published by the workflow is a
  universal `x86_64 arm64` bundle (checked with `lipo` after downloading the
  release asset).
- `build.sh` fails when either slice is missing, so a tag can never publish a
  single-architecture bundle.

## 1.3.0 — 2026-11-13

DevSweep: real product identity and a catalog broad enough to deserve the
"for developers and engineers" claim.

### Added — the catalog is the product

- **82 toolchain caches**, up from 45, each tagged with a discipline:
  **web & backend** (14), **mobile** (13), **desktop & native** (25),
  **embedded** (9), **data, ML & cloud** (21).
- New coverage includes Yarn Berry, npm npx cache, node-gyp headers, Firebase
  CLI, Cypress, Deno, PHP/Ruby/Elixir/Erlang caches, Bazel and
  Bazelisk, Conan 2, vcpkg, .NET global packages, Electron and electron-builder,
  Unity, Unreal Engine DerivedDataCache, VS Code Insiders, PlatformIO,
  ESP-IDF (dist/tools/python env), Arduino staging/cores/arduino-cli, TinyGo,
  CocoaPods spec repos, fastlane, Xcode Previews, CoreSimulator caches, Whisper,
  and the Nix cache.
- The UI groups toolchain rows by discipline with per-group count and size.

### Added — docs cannot drift from code

- `--tools` and `--tools-md` print the catalog (plain text / markdown).
- `scripts/update-readme-tools.sh` regenerates the README table from the binary.
- `--self-test` now compares the README table with the compiled catalog, checks
  that every declared cache passes the deletion allowlist, that no cache path is
  inside `node_modules`/`.git`, that paths are unique, and that every discipline
  keeps at least five caches.

### Added — release engineering

- `build.sh` now produces a **universal binary (arm64 + x86_64)**, verifies with
  `lipo` that both slices are present and fails otherwise; `ARCHS=$(uname -m)`
  builds just the host slice for fast iteration.
- `.github/workflows/release.yml`: pushing a `v*` tag builds the universal app
  on GitHub Actions, runs `--self-test`, zips `DevSweep-<version>.zip`, and
  creates or updates the release with notes extracted from this file (the run
  fails if the version has no notes).
- `LICENSE` (MIT), repository `AGENTS.md`, and README rewritten around the new
  positioning, including a generated per-discipline table.

### Changed

- The product is now **DevSweep** (bundle `com.atamaniuc.devsweep`, binary
  `DevSweep`, log `~/Library/Logs/DevSweep.log`, repository `atamaniuc/devsweep`).
  Headline: *"Reclaim the gigabytes your toolchain quietly hoards."*
- Puppeteer and Selenium moved from the generic `~/.cache` category into the web
  toolchain group (same paths, same safety, better grouping).

## 1.2.0 — 2026-11-13

Built for developers: the app now understands the caches that IDEs, package
managers and model tools leave behind.

### Added — developer toolchain caches

- **Rust**: cargo registry cache, extracted crate sources, git dependencies.
- **C/C++**: ccache, clangd indexes.
- **Go**: build cache, module cache.
- **JVM**: Gradle caches and wrapper distributions, Maven local repository,
  Ivy cache, Coursier cache, sbt boot, Kotlin/Native.
- **Python**: pip, Poetry, pre-commit environments, Conda package caches
  (miniconda/anaconda/miniforge).
- **PHP**: Composer cache. **Node**: Yarn cache. **Deno**. **Dart/Flutter**:
  pub cache. **Swift**: SPM cache. **Android**: SDK cache, system images.
- **Editors**: VS Code and Cursor caches.
- **Infra**: Helm chart cache, kubectl discovery cache, Terraform plugin cache,
  Zig cache.
- **ML**: Playwright browsers, Xcode DerivedData and iOS DeviceSupport, NuGet
  caches, PyTorch model cache, Hugging Face, Ollama and LM Studio models.

Safe toolchain caches stay in "Toolchain caches"; dependency/model caches that
rebuild or re-download slowly go to "Toolchain caches (advanced)" with explicit
warnings.

### Fixed

- `uv cache clean` no longer stalls for up to 300 s (or gets skipped) when a
  long-running `uv run ...` process holds the cache lock. The app now runs
  `uv cache clean --force`: measured on an isolated cache with a held lock,
  plain clean was still waiting after 10 s, `--force` finished in **183 ms**
  and the lock-holding process kept running.

### UI

- Version is shown in the window (`v1.2.0`) and the footer links to the latest
  GitHub release.

## 1.1.0 — 2026-11-12

First public release.

### Added

- SwiftUI desktop app with **dry run as the default**: the exact file list with
  sizes and the commands that would run, plus "Save report…".
- Categories: IntelliJ IDEA caches of non-installed versions, npm, pnpm store,
  bun, uv, Puppeteer, Selenium, nvim/jdtls, Docker build cache older than 24 h
  plus dangling images, Homebrew, MacPorts (administrator prompt), Telegram
  media cache, WhatsApp caches, `/private/tmp` scratch, unavailable Xcode
  simulators.
- UI language follows the system preference (English or Russian).
- Headless modes: `--self-test`, `--scan`, `--preview <file>`,
  `--bench-delete`.
- Live progress in the log while deleting; removed / skipped / errors are
  counted separately.

### Safety

- Every deletion passes a hard allowlist: absolute paths only, no `..`, no
  symlinks, no `node_modules`/`.git`. Repositories, containers, images,
  volumes, settings and personal files are never touched.
- The cache of a running app is skipped (IntelliJ, Telegram, WhatsApp).
  Docker is limited to `builder prune --filter until=24h` and dangling
  `image prune -f` (never `-a`, never volumes).
- External commands are a fixed whitelist and have hard timeouts; `uv cache
  clean` used to block 300 s on a lock held by `uv run ...`, now it gives up in
  25 s and reports "skipped".

### Performance

- Scan: 18.3 s → 5.2 s (parallel scanners, `du` sizes).
- Dry run over ~375k files: 41 s → 14.2 s (parallel C walker).
- Deletion benchmark on a fake 20k-file cache: `FileManager` 2.52 s,
  `/bin/rm -rf` 2.66 s, embedded C `rmtree` 2.77 s — deletion is syscall-bound,
  so the fix was timeouts and progress, not a different language.
