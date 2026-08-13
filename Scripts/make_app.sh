#!/bin/bash
# Assembles build/AvilaVoice.app from the SwiftPM release build — no Xcode required.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/AvilaVoice.app"
BIN="$ROOT/.build/release/AvilaVoice"

[ -f "$BIN" ] || { echo "error: run 'make build' first ($BIN missing)"; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$BIN" "$APP/Contents/MacOS/AvilaVoice"
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/"
fi
# SwiftPM resource bundle (menu bar icon, Localizable.strings)
BUNDLE="$ROOT/.build/release/AvilaVoice_AvilaVoice.bundle"
if [ -d "$BUNDLE" ]; then
    cp -R "$BUNDLE" "$APP/Contents/Resources/"
fi

# Localized permission dialogs (InfoPlist.strings)
for lproj in "$ROOT"/Resources/*.lproj; do
    if [ -d "$lproj" ]; then
        cp -R "$lproj" "$APP/Contents/Resources/"
    fi
done

# Ad-hoc signature with a STABLE designated requirement (identifier only, no cdhash):
# macOS TCC validates apps against this requirement, so Accessibility/Input-Monitoring
# grants survive rebuilds even without a paid certificate.
codesign --force --sign - \
    --identifier com.onuryavuz.avila-voice \
    --requirements '=designated => identifier "com.onuryavuz.avila-voice"' \
    "$APP"

echo "built: $APP"
