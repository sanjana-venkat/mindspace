#!/bin/bash
# Builds Mindspace.app: compiles the notefy-app executable and assembles
# it into a proper macOS app bundle. Development builds are ad-hoc signed;
# releases can pass MINDSPACE_SIGN_IDENTITY for Developer ID signing.
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

APP_BUNDLE="$ROOT_DIR/Mindspace.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources/Fonts"

cp "$BIN_DIR/notefy-app" "$APP_BUNDLE/Contents/MacOS/notefy-app"
cp "$ROOT_DIR/AppResources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
if [ -n "${MINDSPACE_VERSION:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $MINDSPACE_VERSION" "$APP_BUNDLE/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $MINDSPACE_VERSION" "$APP_BUNDLE/Contents/Info.plist"
fi
cp "$ROOT_DIR/AppResources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
cp "$ROOT_DIR/AppResources/NotedLogo.png" "$APP_BUNDLE/Contents/Resources/NotedLogo.png"
cp "$ROOT_DIR"/AppResources/Fonts/*.ttf "$APP_BUNDLE/Contents/Resources/Fonts/"
cp "$ROOT_DIR"/AppResources/Fonts/*.otf "$APP_BUNDLE/Contents/Resources/Fonts/" 2>/dev/null || true
if [ -d "$BIN_DIR/Notefy_NotefyApp.bundle" ]; then
    cp -R "$BIN_DIR/Notefy_NotefyApp.bundle" "$APP_BUNDLE/Contents/Resources/"
fi

if [ -n "${MINDSPACE_SIGN_IDENTITY:-}" ]; then
    codesign --force --deep --options runtime --timestamp \
        --entitlements "$ROOT_DIR/AppResources/Mindspace.entitlements" \
        --sign "$MINDSPACE_SIGN_IDENTITY" "$APP_BUNDLE"
else
    # A stable designated requirement keeps TCC permissions across local builds.
    codesign --force --deep --sign - \
        --requirements '=designated => identifier "com.notefy.app"' \
        --entitlements "$ROOT_DIR/AppResources/Mindspace.entitlements" \
        "$APP_BUNDLE"
fi

codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

echo "Built $APP_BUNDLE"
