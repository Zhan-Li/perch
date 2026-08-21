#!/bin/bash
# Builds Perch.app. No Xcode required — Command Line Tools are enough.
set -euo pipefail

APP_NAME="Perch"
ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/build"
BUNDLE="$BUILD/$APP_NAME.app"

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$ROOT/Resources/Info.plist" "$BUNDLE/Contents/Info.plist"
printf 'APPL????' > "$BUNDLE/Contents/PkgInfo"

# Regenerate with tools/make-icon.sh if you change the artwork.
if [ -f "$ROOT/Resources/Perch.icns" ]; then
	cp "$ROOT/Resources/Perch.icns" "$BUNDLE/Contents/Resources/Perch.icns"
fi

# Universal binary. Set PERCH_ARCH=native for a fast single-slice dev build;
# release builds must ship both or Intel Macs cannot launch the app at all.
compile() {
	swiftc \
		-O \
		-target "$1"-apple-macos13.0 \
		-framework AppKit \
		-framework ApplicationServices \
		-framework ServiceManagement \
		"$ROOT"/Sources/*.swift \
		-o "$2"
}

if [ "${PERCH_ARCH:-universal}" = "native" ]; then
	compile "$(uname -m)" "$BUNDLE/Contents/MacOS/$APP_NAME"
else
	compile arm64 "$BUILD/$APP_NAME-arm64"
	compile x86_64 "$BUILD/$APP_NAME-x86_64"
	lipo -create "$BUILD/$APP_NAME-arm64" "$BUILD/$APP_NAME-x86_64" \
		-output "$BUNDLE/Contents/MacOS/$APP_NAME"
	rm -f "$BUILD/$APP_NAME-arm64" "$BUILD/$APP_NAME-x86_64"
fi

# Sign with a stable identity so the designated requirement pins the signing
# certificate rather than the code hash. An ad-hoc signature pins the cdhash,
# which changes on every build — macOS then revokes Accessibility access while
# System Settings still shows the toggle switched on, which looks like a bug in
# the app rather than a stale grant.
#
# Set PERCH_SIGN_IDENTITY to the Developer ID certificate before shipping.
IDENTITY="${PERCH_SIGN_IDENTITY:-Perch Development}"
if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
	codesign --force --sign "$IDENTITY" --timestamp=none "$BUNDLE"
else
	echo "warning: signing identity '$IDENTITY' not found; using ad-hoc." >&2
	echo "         Accessibility access will need re-granting after every build." >&2
	codesign --force --sign - --timestamp=none "$BUNDLE"
fi

echo "Built $BUNDLE"
