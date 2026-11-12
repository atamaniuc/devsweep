# Changelog

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
