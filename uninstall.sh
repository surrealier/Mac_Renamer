#!/usr/bin/env bash
# Mac_Renamer uninstaller
#
#   curl -fsSL https://raw.githubusercontent.com/surrealier/Mac_Renamer/main/uninstall.sh | bash
#   (or run ./uninstall.sh from a clone)
#
# Quits the app, removes its login item, settings and Finder permission, then (after asking)
# deletes Mac_Renamer.app.
set -uo pipefail

BUNDLE_ID="com.surrealier.macrenamer"

echo
echo "  ============================================"
echo "    Mac_Renamer  -  uninstaller"
echo "  ============================================"
echo

app=""
for candidate in "/Applications/Mac_Renamer.app" "$HOME/Applications/Mac_Renamer.app"; do
  if [[ -d "$candidate" ]]; then app="$candidate"; break; fi
done

# 1) stop the running app
if pgrep -xq Mac_Renamer; then
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
  sleep 1
  pkill -x Mac_Renamer 2>/dev/null || true
  echo "  [x] Stopped Mac_Renamer"
else
  echo "  [-] Mac_Renamer was not running"
fi

# 2) login item + saved settings
if [[ -n "$app" ]]; then
  "$app/Contents/MacOS/Mac_Renamer" --uninstall >/dev/null 2>&1 && echo "  [x] Removed the login item"
fi
if defaults read "$BUNDLE_ID" >/dev/null 2>&1; then
  defaults delete "$BUNDLE_ID" >/dev/null 2>&1
  echo "  [x] Removed saved settings"
else
  echo "  [-] No saved settings found"
fi

# 3) the "control Finder" permission
tccutil reset AppleEvents "$BUNDLE_ID" >/dev/null 2>&1 && echo "  [x] Reset the Finder permission"

# 4) the app itself
if [[ -z "$app" ]]; then
  echo "  [-] Mac_Renamer.app not found in /Applications or ~/Applications"
  echo
  echo "  Done."
  exit 0
fi

answer="y"
if [[ -r /dev/tty ]]; then
  printf "  Also delete %s? [Y/n] " "$app"
  read -r answer < /dev/tty || answer="y"
fi
case "${answer:-y}" in
  [nN]*)
    echo
    echo "  Kept $app. Drag it to the Trash whenever you like."
    ;;
  *)
    rm -rf "$app" && echo "  [x] Deleted $app"
    echo
    echo "  Fully uninstalled."
    ;;
esac
echo
