# Clean Disk

![Clean Disk window](docs/screenshot.png)

A small macOS desktop app (SwiftUI) that frees disk space by deleting only
regenerable caches. **Dry run is the default**: it lists the exact files and
commands before anything is deleted.

## What it cleans

Safe by default: IntelliJ IDEA caches of IDE versions that are not installed,
npm, pnpm store, bun, uv, Puppeteer, Selenium, nvim/jdtls, Docker build cache
older than 24 h plus dangling images, Homebrew, MacPorts build dirs
(administrator prompt), Telegram media cache, WhatsApp caches, `/private/tmp`
scratch, unavailable Xcode simulators.

The UI follows the system language (English or Russian).

## Safety model

- Every deletion goes through a hard allowlist: absolute path, no `..`, no
  symlinks, no `node_modules`/`.git`, only known cache directories plus
  `/private/tmp` scratch entries.
- Repositories, containers, images, volumes, settings and personal files are
  never touched.
- An app's cache is skipped while that app is running (IntelliJ, Telegram,
  WhatsApp).
- Commands are a fixed whitelist; Docker is only `builder prune --filter
  until=24h` and dangling `image prune -f` (never `-a`, never volumes).
- Nothing is deleted without your click: dry run lists files, then a separate
  confirmation is required with dry run off.

## Build and run

Needs macOS 13+ and the Command Line Tools (Swift toolchain); there is no Xcode
project.

```bash
./build.sh
open build/CleanDisk.app
```

The bundle is ad-hoc signed and lives in `build/CleanDisk.app`.

## Tests and headless modes

```bash
# allowlist, detection, delete path, preview checks (exit code checked)
./build/CleanDisk.app/Contents/MacOS/CleanDisk --self-test

# scan only: timing and detected items
./build/CleanDisk.app/Contents/MacOS/CleanDisk --scan

# full dry-run report (the same list the preview sheet shows)
./build/CleanDisk.app/Contents/MacOS/CleanDisk --preview /tmp/cleandisk-plan.txt
```

`--self-test` runs no destructive action against real caches; its delete check
uses a scratch directory under `/private/tmp`.

## Performance

Scanning runs every category in parallel; cache sizes come from `du`. The
dry-run file list uses a small C walker (`Sources/fastwalk.c`) because Swift's
`FileManager` enumeration was the bottleneck:

| step | before | after |
| --- | --- | --- |
| scan (12 categories) | 18.3 s | 5.2 s |
| scan + dry-run over ~375k files | 41 s | 16.6 s |

Logs go to `~/Library/Logs/CleanDisk.log`.
