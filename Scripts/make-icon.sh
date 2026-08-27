#!/bin/bash
# Turns Resources/AppIcon-source.png into Resources/Wave.icns.
#
# The generated source art is an opaque square: a purple squircle on white.
# macOS wants the opposite — a transparent canvas with the squircle inset to
# 824/1024 of it, which is the Big Sur icon grid. The flood fills knock out the
# white surround from the four corners; they cannot eat the white wave because
# it is not connected to the border.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/Resources/AppIcon-source.png"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

W=$(magick identify -format "%w" "$SRC")
E=$((W - 1))
magick "$SRC" -alpha set -fuzz 12% \
  -fill none -floodfill +0+0 white \
  -fill none -floodfill +${E}+0 white \
  -fill none -floodfill +0+${E} white \
  -fill none -floodfill +${E}+${E} white \
  -resize 824x824 -background none -gravity center -extent 1024x1024 \
  "$WORK/icon.png"

ICONSET="$WORK/Wave.iconset"
mkdir -p "$ICONSET"
for spec in "16:16x16" "32:16x16@2x" "32:32x32" "64:32x32@2x" \
            "128:128x128" "256:128x128@2x" "256:256x256" "512:256x256@2x" \
            "512:512x512" "1024:512x512@2x"; do
  magick "$WORK/icon.png" -resize "${spec%%:*}x${spec%%:*}" "$ICONSET/icon_${spec#*:}.png"
done

iconutil -c icns "$ICONSET" -o "$ROOT/Resources/Wave.icns"
echo "==> Wrote $ROOT/Resources/Wave.icns"
