#!/bin/bash
# Generates the app icon as .icns from generate-icon.swift. Usage: make-icon.sh <output.icns>
set -euo pipefail
dir="$(dirname "$0")"

iconset=$(mktemp -d)/AppIcon.iconset
mkdir -p "$iconset"
master="$iconset/icon_512x512@2x.png"
swift "$dir/generate-icon.swift" "$master"

for size in 16 32 128 256 512; do
  sips -z $size $size "$master" --out "$iconset/icon_${size}x${size}.png" >/dev/null
done
for size in 16 32 128 256; do
  sips -z $((size * 2)) $((size * 2)) "$master" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$iconset" -o "$1"
echo "Generated $1"
