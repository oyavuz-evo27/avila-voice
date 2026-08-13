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
[ -f "$ROOT/Resources/AppIcon.icns" ] && cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/"

# Ad-hoc signature: required so macOS TCC (mic/accessibility) remembers permissions.
codesign --force --sign - "$APP"

echo "built: $APP"
