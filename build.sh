#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="${SSH_SWITCH_APP_PATH:-$HOME/Applications/SSH Switch.app}"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/app.py" "$APP/Contents/Resources/app.py"
cp "$ROOT/askpass.sh" "$APP/Contents/Resources/askpass.sh"
cp "$ROOT/MenuBarIcon.svg" "$APP/Contents/Resources/MenuBarIcon.svg"
cp "$ROOT/locales.json" "$APP/Contents/Resources/locales.json"
clang -fobjc-arc -framework Cocoa -mmacosx-version-min=13.0 "$ROOT/MenuApp.m" -o "$APP/Contents/MacOS/SSH-Switch"
chmod 755 "$APP/Contents/MacOS/SSH-Switch"
chmod 700 "$APP/Contents/Resources/askpass.sh"
chmod 600 "$APP/Contents/Resources/app.py"
codesign --force --deep --sign - "$APP"
echo "Built: $APP"
