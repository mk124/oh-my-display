#!/bin/bash
# Packages the OhMyDisplay menu bar app into dist/OhMyDisplay.app with an ad-hoc signature.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product OhMyDisplay

app=dist/OhMyDisplay.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/OhMyDisplay "$app/Contents/MacOS/"
cp Packaging/Info.plist "$app/Contents/"
Packaging/make-icon.sh "$app/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$app"

echo "Packaged $app"
