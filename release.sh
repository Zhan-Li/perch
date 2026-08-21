#!/bin/bash
# Builds Perch.app and packages it as an installable .dmg in dist/.
#
#   ./release.sh          # version taken from Info.plist
#   ./release.sh 1.2.0    # explicit version, also written into the bundle
set -euo pipefail

APP_NAME="Perch"
ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/build"
DIST="$ROOT/dist"
BUNDLE="$BUILD/$APP_NAME.app"

VERSION="${1:-}"
if [ -n "$VERSION" ]; then
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$ROOT/Resources/Info.plist"
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$ROOT/Resources/Info.plist"
fi

"$ROOT/build.sh"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$BUNDLE/Contents/Info.plist")"
DMG="$DIST/$APP_NAME-$VERSION.dmg"

# Optional notarisation, skipped unless a Developer ID is configured. Without
# it the download still works, but users must right-click ▸ Open the first
# time, and macOS asks for Accessibility access again after every update.
if [ -n "${PERCH_NOTARY_PROFILE:-}" ]; then
	echo "Notarising with profile '$PERCH_NOTARY_PROFILE'…"
	xcrun notarytool submit "$BUNDLE" --keychain-profile "$PERCH_NOTARY_PROFILE" --wait
	xcrun stapler staple "$BUNDLE"
else
	echo "note: PERCH_NOTARY_PROFILE unset — shipping without notarisation." >&2
fi

# Staging folder with an /Applications symlink, so the DMG opens with the
# familiar drag-to-install layout.
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$BUNDLE" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

mkdir -p "$DIST"
rm -f "$DMG"
hdiutil create \
	-volname "$APP_NAME" \
	-srcfolder "$STAGING" \
	-ov -format UDZO \
	-quiet \
	"$DMG"

echo
echo "Built $DMG"
shasum -a 256 "$DMG"
