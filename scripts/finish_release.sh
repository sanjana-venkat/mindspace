#!/bin/bash
# Everything after the app-specific password, in one run.
#
# You paste the password once, into notarytool's own hidden prompt — it never
# touches this script, your shell history, or the process list. Then it stores
# the profile, checks Apple actually accepts it, and publishes 0.1.8.
#
#   ./scripts/finish_release.sh
set -euo pipefail

VERSION="${1:-0.1.8}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "==> Storing the notarization profile"
echo "    Paste the app-specific password when asked. It will not be shown."
xcrun notarytool store-credentials "mindspace" \
    --apple-id sanjanavnkt20@gmail.com \
    --team-id 5GV64S6S7C

echo
echo "==> Checking Apple accepts it"
if ! xcrun notarytool history --keychain-profile "mindspace" >/dev/null 2>&1; then
    echo
    echo "Apple still refuses those credentials." >&2
    echo "Most likely: that was the Apple ID password rather than an" >&2
    echo "app-specific one, or App Store Connect has an agreement waiting" >&2
    echo "to be accepted. Nothing has been published." >&2
    exit 1
fi
echo "    Accepted."

echo
echo "==> Publishing $VERSION"
export MINDSPACE_SIGN_IDENTITY="Developer ID Application: Sanjana Venkat (5GV64S6S7C)"
export MINDSPACE_NOTARY_PROFILE="mindspace"
export MINDSPACE_RELEASE_NOTES="$(cat "$ROOT_DIR/docs/release-notes-$VERSION.md")"
./scripts/publish.sh "$VERSION"
