#!/usr/bin/env bash
# Mac_Renamer installer
#
#   curl -fsSL https://raw.githubusercontent.com/surrealier/Mac_Renamer/main/install.sh | bash
#
# Downloads the latest release, puts Mac_Renamer.app in /Applications (or ~/Applications if
# /Applications isn't writable) and starts it. Files fetched with curl aren't quarantined, so
# Gatekeeper's "unidentified developer" prompt doesn't appear.
set -euo pipefail

REPO="surrealier/Mac_Renamer"
URL="https://github.com/$REPO/releases/latest/download/Mac_Renamer.zip"
APP_NAME="Mac_Renamer.app"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Mac_Renamer is for macOS. (On Windows, see github.com/surrealier/Windows_Renamer.)" >&2
  exit 1
fi

major="$(sw_vers -productVersion | cut -d. -f1)"
if (( major < 13 )); then
  echo "Mac_Renamer needs macOS 13 Ventura or later (this Mac has $(sw_vers -productVersion))." >&2
  exit 1
fi

DEST="/Applications"
if [[ ! -w "$DEST" ]]; then
  DEST="$HOME/Applications"
  mkdir -p "$DEST"
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "==> Downloading Mac_Renamer…"
curl -fL --progress-bar "$URL" -o "$tmp/Mac_Renamer.zip"
ditto -x -k "$tmp/Mac_Renamer.zip" "$tmp"

if pgrep -xq Mac_Renamer; then
  echo "==> Quitting the running copy…"
  osascript -e 'tell application id "com.surrealier.macrenamer" to quit' >/dev/null 2>&1 || pkill -x Mac_Renamer || true
  sleep 1
fi

echo "==> Installing to $DEST/$APP_NAME"
rm -rf "${DEST:?}/$APP_NAME"
ditto "$tmp/$APP_NAME" "$DEST/$APP_NAME"
xattr -dr com.apple.quarantine "$DEST/$APP_NAME" 2>/dev/null || true

open "$DEST/$APP_NAME"
echo
echo "✅ Mac_Renamer is running in your menu bar."
echo "   Select files in Finder and press ⌥F2 (Fn+⌥+F2 on a MacBook keyboard)."
echo "   The first time, click OK when macOS asks to let Mac_Renamer control Finder."
