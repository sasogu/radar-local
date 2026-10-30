#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

INKSCAPE="${INKSCAPE:-inkscape}"
MAGICK="${MAGICK:-magick}"
if ! command -v "$MAGICK" >/dev/null 2>&1; then
  MAGICK=convert
fi
MASTER="${TMPDIR:-/tmp}/radar-local-icon-1024.png"

"$INKSCAPE" assets/icon/icon.svg --export-type=png --export-filename="$MASTER" --export-width=1024 --export-height=1024 >/dev/null
"$MAGICK" "$MASTER" -alpha off assets/icon/icon-1024.png

for spec in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  density="${spec%%:*}"
  size="${spec##*:}"
  "$MAGICK" assets/icon/icon-1024.png -resize "${size}x${size}" -alpha off \
    "android/app/src/main/res/mipmap-${density}/ic_launcher.png"
done

for spec in mdpi:108 hdpi:162 xhdpi:216 xxhdpi:324 xxxhdpi:432; do
  density="${spec%%:*}"
  size="${spec##*:}"
  "$INKSCAPE" assets/icon/icon-foreground.svg --export-type=png \
    --export-filename="android/app/src/main/res/mipmap-${density}/ic_launcher_foreground.png" \
    --export-width="$size" --export-height="$size" >/dev/null
done

IOS="ios/Runner/Assets.xcassets/AppIcon.appiconset"
for spec in \
  "Icon-App-20x20@1x.png:20" "Icon-App-20x20@2x.png:40" "Icon-App-20x20@3x.png:60" \
  "Icon-App-29x29@1x.png:29" "Icon-App-29x29@2x.png:58" "Icon-App-29x29@3x.png:87" \
  "Icon-App-40x40@1x.png:40" "Icon-App-40x40@2x.png:80" "Icon-App-40x40@3x.png:120" \
  "Icon-App-60x60@2x.png:120" "Icon-App-60x60@3x.png:180" \
  "Icon-App-76x76@1x.png:76" "Icon-App-76x76@2x.png:152" \
  "Icon-App-83.5x83.5@2x.png:167" "Icon-App-1024x1024@1x.png:1024"; do
  file="${spec%%:*}"
  size="${spec##*:}"
  "$MAGICK" assets/icon/icon-1024.png -resize "${size}x${size}" -alpha off "$IOS/$file"
done

echo "Generated Android and iOS icons"
