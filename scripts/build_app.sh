#!/usr/bin/env bash
# Builds dist/Mac_Renamer.app and dist/Mac_Renamer.zip.
#
#   ./scripts/build_app.sh              # version from the latest git tag
#   VERSION=1.2.0 ./scripts/build_app.sh
#
# With full Xcode installed the binary is universal (Apple Silicon + Intel); with only the
# Command Line Tools it is built for this Mac's architecture.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)}"
VERSION="${VERSION:-0.0.0}"
BUILD="${BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
APP="dist/Mac_Renamer.app"

rm -rf dist
mkdir -p dist

if xcodebuild -version >/dev/null 2>&1; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
else
  echo "note: full Xcode not found — building for $(uname -m) only"
  ARCH_FLAGS=()
fi

# (the ${a[@]+…} form keeps an empty array safe under `set -u` in macOS's bash 3.2)
swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --product MacRenamerApp
BIN_DIR="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --product MacRenamerApp --show-bin-path)"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/MacRenamerApp" "$APP/Contents/MacOS/Mac_Renamer"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# App icon: Resources/AppIcon.png (1024×1024) → AppIcon.icns
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$(dirname "$ICONSET")"

# Ad-hoc signature (no Apple Developer ID): seals Info.plist + binary so Gatekeeper sees a
# consistent bundle and Apple Silicon will run it.
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --strict --verbose=2 "$APP"

ditto -c -k --sequesterRsrc --keepParent "$APP" dist/Mac_Renamer.zip
(cd dist && shasum -a 256 Mac_Renamer.zip > Mac_Renamer.zip.sha256)

echo
echo "Built Mac_Renamer $VERSION ($BUILD)"
lipo -info "$APP/Contents/MacOS/Mac_Renamer"
ls -lh dist/Mac_Renamer.zip
