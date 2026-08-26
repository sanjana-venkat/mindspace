#!/bin/bash
# Builds Noted.app: compiles the notefy-app executable and assembles
# it into a proper macOS app bundle (Info.plist, icon, ad-hoc signature).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CONFIG="${1:-debug}"
if [ "$CONFIG" = "release" ]; then
    swift build -c release --product notefy-app
    BIN_DIR=".build/release"
else
    swift build --product notefy-app
    BIN_DIR=".build/debug"
fi

APP_BUNDLE="$ROOT_DIR/Noted.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources/Fonts"

cp "$BIN_DIR/notefy-app" "$APP_BUNDLE/Contents/MacOS/notefy-app"
cp "$ROOT_DIR/AppResources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$ROOT_DIR/AppResources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
cp "$ROOT_DIR/AppResources/NotedLogo.png" "$APP_BUNDLE/Contents/Resources/NotedLogo.png"
cp "$ROOT_DIR"/AppResources/Fonts/*.ttf "$APP_BUNDLE/Contents/Resources/Fonts/"
if [ -d "$BIN_DIR/Notefy_NotefyApp.bundle" ]; then
    cp -R "$BIN_DIR/Notefy_NotefyApp.bundle" "$APP_BUNDLE/Contents/Resources/"
fi

# Give ad-hoc development builds a stable designated requirement. Without it,
# macOS keys TCC permissions to each build's changing cdhash and treats every
# rebuild as a new app.
codesign --force --deep --sign - \
    --requirements '=designated => identifier "com.notefy.app"' \
    "$APP_BUNDLE"

echo "Built $APP_BUNDLE"
