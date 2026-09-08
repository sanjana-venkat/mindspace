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

: "${MINDSPACE_SIGN_IDENTITY:?Set MINDSPACE_SIGN_IDENTITY to your Developer ID Application certificate name}"
: "${MINDSPACE_NOTARY_PROFILE:?Set MINDSPACE_NOTARY_PROFILE to a notarytool keychain profile}"

echo "==> Pushing code to $REPO"
git remote get-url mindspace >/dev/null 2>&1 || git remote add mindspace "https://github.com/$REPO.git"
git push -u mindspace main

echo "==> Building, signing, notarizing, and publishing v$VERSION"
MINDSPACE_REPO="$REPO" ./scripts/release.sh "$VERSION"

echo "==> Updating the tap at $TAP_REPO"

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
