#!/bin/bash
# Renders the app icon set from Scripts/icon/icon.svg. The checked-in icon is a PLACEHOLDER (a plug on a
# cord), not a final brand; replace the SVG and run this again.
# The rounded square sits on the macOS icon grid: 824 of 1024 pixels, with a soft shadow.
#
#   Scripts/render-app-icon.sh
#
# Needs: brew install librsvg imagemagick
set -euo pipefail

cd "$(dirname "$0")/.."
SOURCE=Scripts/icon/icon.svg
OUT=KillCord/Assets.xcassets/AppIcon.appiconset
WORK=$(mktemp -d)
trap 'rm -r "$WORK"' EXIT

rsvg-convert -w 824 -h 824 "$SOURCE" -o "$WORK/plate.png"
magick -size 1024x1024 xc:none \
  \( "$WORK/plate.png" -background none -gravity center -extent 1024x1024 \
     -channel A -evaluate multiply 0.35 +channel -blur 0x14 -geometry +0+12 \) -composite \
  \( "$WORK/plate.png" -background none -gravity center -extent 1024x1024 \) -composite \
  "$WORK/icon.png"

for size in 16 32 128 256 512; do
  magick "$WORK/icon.png" -resize "${size}x${size}" "$OUT/icon_${size}x${size}@1x.png"
  magick "$WORK/icon.png" -resize "$((size * 2))x$((size * 2))" "$OUT/icon_${size}x${size}@2x.png"
done
echo "Rendered $OUT from $SOURCE"
