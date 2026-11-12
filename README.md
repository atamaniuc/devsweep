# Clean Disk 1.2.0

![Clean Disk window](docs/screenshot.png)

A small macOS desktop app (SwiftUI) that frees disk space by deleting only
regenerable caches. **Dry run is the default**: it lists the exact files and
commands before anything is deleted.

## Download

Grab `CleanDisk-1.2.0.zip` from the [latest release](https://github.com/atamaniuc/clean-disk-app/releases/latest),
unzip it and open `CleanDisk.app`. The bundle is ad-hoc signed, so on first
launch macOS may ask to confirm with right-click → Open. Release notes live in
[CHANGELOG.md](CHANGELOG.md).

## What it cleans

Built for developers: it knows the caches left by package managers, IDEs and
model tooling.

- **Rust**: cargo registry cache, crate sources, git dependencies.
- **Go**: build cache, module cache.
- **JVM**: Gradle caches + wrapper dists, Maven, Ivy, Coursier, sbt, Kotlin/Native.
- **Python**: pip, Poetry, pre-commit, Conda package caches, uv.
- **Node**: npm, pnpm store, bun, Yarn, Playwright browsers.
- **Other**: C/C++ ccache and clangd, PHP Composer, Deno, Dart/Flutter pub,
  Swift SPM, Android SDK caches, Helm, kubectl, Terraform, Zig, NuGet.
- **Editors**: JetBrains caches of non-installed IDE versions, VS Code and
  Cursor caches.
- **ML**: PyTorch, Hugging Face, Ollama, LM Studio models; Xcode DerivedData.
- **System**: Docker build cache + dangling images, Homebrew, MacPorts,
  `/private/tmp` scratch, Telegram/WhatsApp caches, unavailable simulators.

Dependency and model caches that rebuild or re-download slowly are grouped under
"Toolchain caches (advanced)" with explicit warnings.

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
