#!/bin/bash
# One-shot publish for Mindspace: pushes the code, cuts the GitHub release with
# the DMG, and creates/updates the Homebrew tap so `brew install --cask
# mindspace` works.
#
#   ./scripts/publish.sh 0.1.0
set -euo pipefail

VERSION="${1:-0.1.0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

OWNER="${MINDSPACE_OWNER:-sanjana-venkat}"
REPO="$OWNER/mindspace"
TAP_REPO="$OWNER/homebrew-mindspace"
DMG="Mindspace-$VERSION.dmg"

echo "==> Pushing code to $REPO"
git remote get-url mindspace >/dev/null 2>&1 || git remote add mindspace "https://github.com/$REPO.git"
git push -u mindspace main

if [ ! -f "$DMG" ]; then
    echo "==> Building $DMG"
    ./scripts/build_app.sh release
    STAGING="$(mktemp -d)"
    cp -R Mindspace.app "$STAGING/"
    ln -s /Applications "$STAGING/Applications"
    hdiutil create -volname "Mindspace" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
    rm -rf "$STAGING"
fi

SHA="$(shasum -a 256 "$DMG" | awk '{print $1}')"
echo "==> $DMG  sha256 $SHA"

echo "==> Publishing release v$VERSION"
gh release create "v$VERSION" "$DMG" --repo "$REPO" \
    --title "Mindspace $VERSION" \
    --notes "Open the DMG and drag Mindspace to Applications.

This build is ad-hoc signed rather than notarized, so the first launch needs a
right-click → **Open** (or System Settings → Privacy & Security → *Open Anyway*).
Homebrew handles that for you.

    brew tap $OWNER/mindspace
    brew install --cask mindspace"

echo "==> Updating the tap at $TAP_REPO"
sed -i '' "s/version \".*\"/version \"$VERSION\"/" Casks/mindspace.rb
sed -i '' "s/sha256 \".*\"/sha256 \"$SHA\"/" Casks/mindspace.rb

TAP_DIR="$(mktemp -d)/homebrew-mindspace"
if gh repo view "$TAP_REPO" >/dev/null 2>&1; then
    git clone "https://github.com/$TAP_REPO.git" "$TAP_DIR"
else
    gh repo create "$TAP_REPO" --public --description "Homebrew tap for Mindspace"
    git clone "https://github.com/$TAP_REPO.git" "$TAP_DIR"
fi

mkdir -p "$TAP_DIR/Casks"
cp Casks/mindspace.rb "$TAP_DIR/Casks/mindspace.rb"
cat > "$TAP_DIR/README.md" <<TAPREADME
# Homebrew tap for Mindspace

    brew tap $OWNER/mindspace
    brew install --cask mindspace

Source: https://github.com/$REPO
TAPREADME

cd "$TAP_DIR"
git add -A
git commit -m "mindspace $VERSION" >/dev/null
git push
cd "$ROOT_DIR"

echo
echo "Done."
echo "  Release:  https://github.com/$REPO/releases/tag/v$VERSION"
echo "  Install:  brew tap $OWNER/mindspace && brew install --cask mindspace"
