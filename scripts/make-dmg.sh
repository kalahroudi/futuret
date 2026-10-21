#!/bin/bash
# Builds dist/FutureT-<version>.dmg with the app and an Applications shortcut.
# Usage: scripts/make-dmg.sh [version]     Set SIGN_IDENTITY to sign the app and the disk image.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-0.1.0}"
DMG="dist/FutureT-$VERSION.dmg"

scripts/bundle.sh "$VERSION"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "dist/FutureT.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -volname "FutureT" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

if [ "${SIGN_IDENTITY:--}" != "-" ]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
fi
hdiutil verify "$DMG" >/dev/null
echo "Built $DMG"
