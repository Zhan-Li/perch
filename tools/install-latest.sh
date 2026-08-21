#!/bin/bash
# Installs the latest published Perch release into /Applications.
#
#     curl -fsSL https://raw.githubusercontent.com/Zhan-Li/perch/main/tools/install-latest.sh | bash
#
# Perch is signed ad-hoc, so each release has a different code signature and
# macOS treats it as a different app — the previous Accessibility grant stops
# applying. This script does the whole dance: download, replace, strip the
# download flag, clear the stale permission entries, relaunch.
#
# You still have to tick the box in System Settings once per update. That is a
# limitation of shipping without a paid Apple Developer ID, not a bug.
set -euo pipefail

REPO="Zhan-Li/perch"
BUNDLE_ID="com.zhanli.perch"
APP="/Applications/Perch.app"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "Finding the latest release..."
URL="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
	| grep -o '"browser_download_url"[^,]*\.dmg"' \
	| head -1 | cut -d'"' -f4)"

if [ -z "$URL" ]; then
	echo "error: no .dmg asset found on the latest release." >&2
	exit 1
fi

echo "Downloading $(basename "$URL")..."
curl -fsSL -o "$WORK/Perch.dmg" "$URL"

echo "Quitting any running copy..."
osascript -e 'quit app "Perch"' 2>/dev/null || true
pkill -f "Perch.app/Contents/MacOS/Perch" 2>/dev/null || true
sleep 1

# Mount at a path we choose. Parsing `hdiutil attach` output is a trap: if a
# previous run left a volume behind, the image mounts as "/Volumes/Perch 3" and
# naive field-splitting yields "3".
MOUNT="$WORK/mnt"
mkdir -p "$MOUNT"
hdiutil attach "$WORK/Perch.dmg" -nobrowse -readonly -mountpoint "$MOUNT" -quiet
trap 'hdiutil detach "$MOUNT" -quiet 2>/dev/null || true; rm -rf "$WORK"' EXIT

if [ ! -d "$MOUNT/Perch.app" ]; then
	echo "error: the disk image does not contain Perch.app" >&2
	exit 1
fi

# Stage the new copy first and only then swap it in, so a failure part way
# through cannot leave the machine with no Perch installed at all.
echo "Installing to ${APP}..."
STAGED="$WORK/staged-Perch.app"
rm -rf "$STAGED"
cp -R "$MOUNT/Perch.app" "$STAGED"
hdiutil detach "$MOUNT" -quiet
rm -rf "$APP"
mv "$STAGED" "$APP"

# Downloaded apps carry a quarantine flag. Left in place, macOS may run the app
# from a read-only translocated path where the permission grant will not stick.
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

# Clear permission entries left behind by earlier builds. More than one line of
# output here means stale entries were conflicting, which is the usual cause of
# "waiting for Accessibility access" when the toggle already looks enabled.
tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null || true

open "$APP"

cat <<'EOF'

Installed. One step left:

  System Settings ▸ Privacy & Security ▸ Accessibility ▸ enable Perch

Perch checks once a second, so it starts working the moment you tick it —
no restart needed.
EOF
