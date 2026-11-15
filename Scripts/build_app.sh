#!/bin/zsh
# Builds Bema.app into ./build and, with --install, copies it to ~/Applications
# and registers it with Finder (Open With and the Services / Quick Actions menu).
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Bema"

APP="$ROOT/build/Bema.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Bema"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
[[ -f "$ROOT/Resources/AppIcon.icns" ]] && cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/"

# Sign with a stable identity when one is available, so macOS remembers the Automation and
# Accessibility permissions across rebuilds. Override with SIGN_IDENTITY=...; falls back to ad-hoc.
IDENTITY="${SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  IDS="$(security find-identity -p codesigning -v 2>/dev/null)"
  IDENTITY="$(echo "$IDS" | grep -m1 'Developer ID Application' | awk '{print $2}')"
  [[ -z "$IDENTITY" ]] && IDENTITY="$(echo "$IDS" | grep -m1 'Apple Development' | awk '{print $2}')"
  [[ -z "$IDENTITY" ]] && IDENTITY="-"
fi
codesign --force --sign "$IDENTITY" "$APP"
echo "Signed with: $IDENTITY"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  DEST="$HOME/Applications/Bema.app"
  mkdir -p "$HOME/Applications"
  pkill -x Bema 2>/dev/null || true
  rm -rf "$DEST"
  cp -R "$APP" "$DEST"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST"
  /System/Library/CoreServices/pbs -update 2>/dev/null || true
  echo "Installed $DEST"
fi
