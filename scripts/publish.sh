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
    brew trust $OWNER/mindspace 2>/dev/null || true
    brew install --cask $OWNER/mindspace/mindspace

Homebrew 6 will not load a cask from a personal tap until it is trusted — that
is the middle line, asked once per tap. Older Homebrew has no \`trust\` command
and does not need one, so the line is written to be a no-op there rather than
an error that stops the install.

The cask is named in full because \`brew install --cask mindspace\` fails with
"Cask 'mindspace' is unavailable" whenever the tap has not resolved — which
reads as though the app is missing rather than the tap.

The app is signed with a Developer ID and notarized, so macOS opens it without
complaint.

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
