#!/bin/bash
# Cuts a Mindspace release: builds the app, wraps it in a DMG, publishes the
# GitHub release, and updates the Homebrew cask's version and checksum.
#
#   ./scripts/release.sh 0.1.0
set -euo pipefail

VERSION="${1:?usage: ./scripts/release.sh <version>}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

REPO="${MINDSPACE_REPO:-sanjana-venkat/mindspace}"
TAP="${MINDSPACE_TAP:-sanjana-venkat/homebrew-mindspace}"
DMG="Mindspace-$VERSION.dmg"

SIGNED_RELEASE=false
if [ -n "${MINDSPACE_SIGN_IDENTITY:-}" ] && [ -n "${MINDSPACE_NOTARY_PROFILE:-}" ]; then
    SIGNED_RELEASE=true
elif [ -n "${MINDSPACE_SIGN_IDENTITY:-}" ] || [ -n "${MINDSPACE_NOTARY_PROFILE:-}" ]; then
    echo "Set both MINDSPACE_SIGN_IDENTITY and MINDSPACE_NOTARY_PROFILE, or neither for an ad-hoc alpha." >&2
    exit 1
fi

MINDSPACE_VERSION="$VERSION" ./scripts/build_app.sh release

STAGING="$(mktemp -d)"
cp -R Mindspace.app "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "Mindspace" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"

if [ "$SIGNED_RELEASE" = true ]; then
    codesign --force --timestamp --sign "$MINDSPACE_SIGN_IDENTITY" "$DMG"
    xcrun notarytool submit "$DMG" --keychain-profile "$MINDSPACE_NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
    RELEASE_NOTES="Download the notarized DMG, open it, and drag Mindspace to Applications."
else
    RELEASE_NOTES="Download the DMG and drag Mindspace to Applications. This alpha is ad-hoc signed: on first launch, try opening it once, then use System Settings → Privacy & Security → Open Anyway."
    echo "WARNING: creating an ad-hoc alpha; users must approve it in Privacy & Security." >&2
fi

SHA="$(shasum -a 256 "$DMG" | awk '{print $1}')"
echo "sha256 $SHA"

gh release create "v$VERSION" "$DMG" \
    --repo "$REPO" \
    --title "Mindspace $VERSION" \
    --notes "$RELEASE_NOTES"

# Point the cask at the new build.
sed -i '' "s/version \".*\"/version \"$VERSION\"/" Casks/mindspace.rb
sed -i '' "s/sha256 \".*\"/sha256 \"$SHA\"/" Casks/mindspace.rb
echo "Updated Casks/mindspace.rb — commit it here and copy it into $TAP"
