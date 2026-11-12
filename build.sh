#!/bin/bash
# Builds build/CleanDisk.app from Sources/*.swift with the Command Line Tools
# toolchain (no Xcode project needed), ad-hoc signs it and prints the path.
set -euo pipefail
cd "$(dirname "$0")"

ARCH=$(uname -m)
TARGET="${ARCH}-apple-macos13.0"
APP="build/CleanDisk.app"

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Icon is nice to have: a failure here must not break the build.
if [[ -f Tools/make-icon.swift ]]; then
  if swiftc -O -o build/make-icon Tools/make-icon.swift >/dev/null 2>&1 \
     && ./build/make-icon build/AppIcon.iconset >/dev/null 2>&1 \
     && iconutil -c icns -o "$APP/Contents/Resources/AppIcon.icns" build/AppIcon.iconset >/dev/null 2>&1; then
    echo "icon: built"
  else
    echo "icon: skipped (iconset failed)"
    rm -f "$APP/Contents/Resources/AppIcon.icns"
  fi
fi

echo "compiling for $TARGET"
clang -O2 -target "$TARGET" -c Sources/fastwalk.c -o build/fastwalk.o
swiftc -O -swift-version 5 -target "$TARGET" \
  -import-objc-header Sources/Bridging.h \
  Sources/*.swift build/fastwalk.o \
  -o "$APP/Contents/MacOS/CleanDisk"

cp Info.plist "$APP/Contents/Info.plist"
codesign --force --deep --sign - --timestamp=none "$APP" >/dev/null

echo "built $(pwd)/$APP"
