#!/bin/bash
# Regenerates Resources/Perch.icns from tools/make-icon.swift.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

swift "$ROOT/tools/make-icon.swift" "$WORK/icon-1024.png"

ICONSET="$WORK/Perch.iconset"
mkdir -p "$ICONSET"

# name:pixel-size pairs required by iconutil
for entry in \
	16x16:16 16x16@2x:32 \
	32x32:32 32x32@2x:64 \
	128x128:128 128x128@2x:256 \
	256x256:256 256x256@2x:512 \
	512x512:512 512x512@2x:1024
do
	name="${entry%%:*}"
	px="${entry##*:}"
	sips -z "$px" "$px" "$WORK/icon-1024.png" --out "$ICONSET/icon_$name.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o "$ROOT/Resources/Perch.icns"
echo "wrote $ROOT/Resources/Perch.icns"
