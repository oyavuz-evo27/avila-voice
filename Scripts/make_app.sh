#!/bin/bash
# Assembles build/AvilaVoice.app from the SwiftPM release build — no Xcode required.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/AvilaVoice.app"
BIN="$ROOT/.build/release/AvilaVoice"

# Guard: a single stray quote in a .strings file silently kills ALL localization
# (bit us on 21.08. — the app fell back to raw keys). Lint every table up front.
for STRINGS in "$ROOT"/Sources/*/Resources/*.lproj/*.strings; do
  plutil -lint "$STRINGS" >/dev/null || { echo "✗ kaputte Strings-Datei: $STRINGS"; exit 1; }
done

[ -f "$BIN" ] || { echo "error: run 'make build' first ($BIN missing)"; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$BIN" "$APP/Contents/MacOS/AvilaVoice"
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/"
fi
# SwiftPM resource bundles (own: menu bar icon, Localizable.strings; dependencies:
# FluidAudio's Hub/Crypto bundles for the Parakeet model download)
for BUNDLE in "$ROOT"/.build/release/*.bundle; do
    if [ -d "$BUNDLE" ]; then
        cp -R "$BUNDLE" "$APP/Contents/Resources/"
    fi
done

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
