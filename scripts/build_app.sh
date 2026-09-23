#!/bin/bash
# Builds Mindspace.app: compiles the notefy-app executable and assembles
# it into a proper macOS app bundle. Development builds are ad-hoc signed;
# releases can pass MINDSPACE_SIGN_IDENTITY for Developer ID signing.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CONFIG="${1:-debug}"
if [ "$CONFIG" = "release" ]; then
    # Both architectures: the app is handed to people whose Macs we do not
    # know, and an arm64-only build installs cleanly on an Intel Mac and then
    # refuses to open. SwiftPM puts a multi-arch build somewhere else than a
    # native one, hence the second path.
    swift build -c release --arch arm64 --arch x86_64 --product notefy-app
    if [ -d ".build/apple/Products/Release" ]; then
        BIN_DIR=".build/apple/Products/Release"
    else
        BIN_DIR=".build/release"
    fi
else
    swift build --product notefy-app
    BIN_DIR=".build/debug"
fi

APP_BUNDLE="$ROOT_DIR/Mindspace.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources/Fonts"

cp "$BIN_DIR/notefy-app" "$APP_BUNDLE/Contents/MacOS/notefy-app"
# A release binary still carries its debug symbols — around 10MB of them —
# and nothing ships that reads them. Stripping happens before signing, or the
# signature is invalidated.
if [ "$CONFIG" = "release" ]; then
    strip -x "$APP_BUNDLE/Contents/MacOS/notefy-app"
fi
cp "$ROOT_DIR/AppResources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
if [ -n "${MINDSPACE_VERSION:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $MINDSPACE_VERSION" "$APP_BUNDLE/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $MINDSPACE_VERSION" "$APP_BUNDLE/Contents/Info.plist"
fi
cp "$ROOT_DIR/AppResources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
cp "$ROOT_DIR/AppResources/NotedLogo.png" "$APP_BUNDLE/Contents/Resources/NotedLogo.png"
cp "$ROOT_DIR"/AppResources/Fonts/*.ttf "$APP_BUNDLE/Contents/Resources/Fonts/"
cp "$ROOT_DIR"/AppResources/Fonts/*.otf "$APP_BUNDLE/Contents/Resources/Fonts/" 2>/dev/null || true
RESOURCE_BUNDLE="$APP_BUNDLE/Contents/Resources/Notefy_NotefyApp.bundle"
if [ -d "$BIN_DIR/Notefy_NotefyApp.bundle" ]; then
    cp -R "$BIN_DIR/Notefy_NotefyApp.bundle" "$APP_BUNDLE/Contents/Resources/"
else
    echo "error: SwiftPM produced no resource bundle — the app would ship without its artwork." >&2
    exit 1
fi

# SwiftPM emits a flat directory here with no Info.plist. macOS 26 will open
# that as a bundle; macOS 15 refuses it, `Bundle(url:)` returns nil, and the
# app used to die on launch there — every release up to 0.1.5 did. Giving it a
# real Info.plist makes it a bundle everywhere.
if [ ! -f "$RESOURCE_BUNDLE/Info.plist" ]; then
    cat > "$RESOURCE_BUNDLE/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleIdentifier</key>
    <string>com.notefy.app.resources</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Notefy_NotefyApp</string>
    <key>CFBundlePackageType</key>
    <string>BNDL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
</dict>
</plist>
PLIST
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

if [ "$CONFIG" = "release" ]; then
    ARCHS="$(lipo -archs "$APP_BUNDLE/Contents/MacOS/notefy-app")"
    case "$ARCHS" in
        *arm64*x86_64*|*x86_64*arm64*) ;;
        *)
            echo "error: release binary is $ARCHS — an Intel Mac could not run it." >&2
            exit 1
            ;;
    esac
fi

# The bundle has to be openable as a bundle, not merely present. This is the
# check that would have caught the 0.1.5 launch crash before it shipped.
if ! /usr/bin/plutil -lint "$RESOURCE_BUNDLE/Info.plist" >/dev/null; then
    echo "error: the resource bundle has no usable Info.plist — it will not load on macOS 15." >&2
    exit 1
fi

# And the app has to actually start. A packaging fault that traps in a
# `dispatch_once` shows up here in two seconds and nowhere else until a tester
# reports a crash log.
"$APP_BUNDLE/Contents/MacOS/notefy-app" &
LAUNCH_PID=$!
sleep 4
if kill -0 "$LAUNCH_PID" 2>/dev/null; then
    kill "$LAUNCH_PID" 2>/dev/null || true
    wait "$LAUNCH_PID" 2>/dev/null || true
else
    echo "error: the app exited within four seconds of launching — it is crashing on start." >&2
    exit 1
fi

echo "Built $APP_BUNDLE"
