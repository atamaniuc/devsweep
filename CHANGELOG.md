# Changelog

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
