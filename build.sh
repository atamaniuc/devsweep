#!/bin/bash
# Builds build/DevSweep.app as a UNIVERSAL (arm64 + x86_64) bundle from
# Sources/*.swift with the Command Line Tools toolchain (no Xcode project),
# ad-hoc signs it and prints the path.
#
# ARCHS="$(uname -m)" ./build.sh   builds just the host slice (fast iteration).
set -euo pipefail
cd "$(dirname "$0")"

APP="build/DevSweep.app"
read -r -a ARCHES <<< "${ARCHS:-arm64 x86_64}"

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/slices

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

SLICES=()
for ARCH in "${ARCHES[@]}"; do
  TARGET="${ARCH}-apple-macos13.0"
  echo "compiling $ARCH ($TARGET)"
  clang -O2 -target "$TARGET" -c Sources/fastwalk.c -o "build/slices/fastwalk-$ARCH.o"
  swiftc -O -swift-version 5 -target "$TARGET" \
    -import-objc-header Sources/Bridging.h \
    Sources/*.swift "build/slices/fastwalk-$ARCH.o" \
    -o "build/slices/DevSweep-$ARCH"
  SLICES+=("build/slices/DevSweep-$ARCH")
done

if [[ ${#SLICES[@]} -eq 1 ]]; then
  cp "${SLICES[0]}" "$APP/Contents/MacOS/DevSweep"
else
  lipo -create "${SLICES[@]}" -output "$APP/Contents/MacOS/DevSweep"
fi

cp Info.plist "$APP/Contents/Info.plist"
codesign --force --deep --sign - --timestamp=none "$APP" >/dev/null

# A release zip must run on both Intel and Apple silicon: fail loudly instead
# of shipping a single-architecture bundle.
BUILT_ARCHS=$(lipo -archs "$APP/Contents/MacOS/DevSweep")
echo "architectures: $BUILT_ARCHS"
for ARCH in "${ARCHES[@]}"; do
  if ! grep -qw "$ARCH" <<< "$BUILT_ARCHS"; then
    echo "error: built binary is missing the $ARCH slice ($BUILT_ARCHS)" >&2
    exit 1
  fi
done

echo "built $(pwd)/$APP"
