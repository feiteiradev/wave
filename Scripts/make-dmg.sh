#!/bin/bash
# Builds Wave.app, then wraps it in a drag-to-Applications disk image.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/Wave.app"
DMG="$ROOT/build/Wave.dmg"

"$ROOT/Scripts/make-app.sh"

VERSION=$(defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString)

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "==> Creating $DMG"
rm -f "$DMG"
hdiutil create -volname "Wave $VERSION" -srcfolder "$STAGE" \
  -ov -format UDZO "$DMG" >/dev/null

echo "==> Built $DMG"
