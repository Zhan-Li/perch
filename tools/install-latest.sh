#!/bin/bash
# Installs the latest published Perch release into /Applications.
#
#     curl -fsSL https://raw.githubusercontent.com/Zhan-Li/perch/main/tools/install-latest.sh | bash
#
# Download, replace, strip the download flag, clear stale permission entries,
# relaunch.
#
# This exists for one job: migrating off a release signed **ad-hoc** (1.2.1 and
# earlier). Those pinned the code hash, which changed on every build, so each
# release invalidated the previous release's Accessibility grant and left a dead
# entry behind — while System Settings still showed the toggle on, because that
# list is keyed by bundle path rather than by signature.
#
# Releases from 1.2.2 pin a stable certificate instead, so grants survive
# updates and a plain drag-the-DMG install is enough. This script still resets
# the grant on every run, which costs a re-tick you no longer need. Prefer it
# when coming from 1.2.1 or earlier; prefer the DMG for routine updates.
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

# Clear permission entries left behind by earlier builds. One line of output per
# entry cleared: more than one means ad-hoc releases had stacked up conflicting
# grants, which is the usual cause of "waiting for Accessibility access" when
# the toggle already looks enabled.
tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null || true

open "$APP"

cat <<'EOF'

Installed. One step left:

  System Settings ▸ Privacy & Security ▸ Accessibility ▸ enable Perch

Perch checks once a second, so it starts working the moment you tick it —
no restart needed.
EOF
