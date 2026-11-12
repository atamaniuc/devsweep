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
- Headless modes: `--scan`, `--preview <file>`, `--tools`, `--tools-md`,
  `--bench-delete`.
- Release: bump `CFBundleShortVersionString`/`CFBundleVersion` in `Info.plist`,
  add a `## <version>` section to `CHANGELOG.md`, commit, push, then push tag
  `v<version>`. `.github/workflows/release.yml` builds, tests, zips
  `DevSweep-<version>.zip` and creates/updates the GitHub release; it fails when
  the version has no changelog section.

## Rules that bite

- **The catalog is the product.** A new cache is one `make(...)` entry in
  `ToolCaches.specs` (`Sources/Models.swift`); it automatically drives scanning,
  the allowlist, the preview and the UI. Never hand-edit the README table:
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
- **Screenshots: window-only.** Capture the app window by CGWindowID
  (`screencapture -x -l <id>`), never a full-screen capture — the background can
  contain private windows. Verify the image before committing it to `docs/`.
- UI strings are localized through `L(ru, en)`; the UI follows the system
  language. Repository artifacts (README, CHANGELOG, docs) are English.
