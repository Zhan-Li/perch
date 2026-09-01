# Changelog

Each release's section here becomes the body of its GitHub release, so keep
entries written for someone deciding whether to update — what changed for them,
not which files moved.

## 1.2.1

- Fixed the icon strip silently going missing. After Perch had been running a
  while, dragging a window would show nothing at all, and only relaunching
  brought the icons back. Everything except the drawing was still working — the
  drag was detected, the zones were hit tested, and dropping a window still
  snapped it — which is why it looked like the app had died rather than that it
  had simply stopped painting.

  The overlay marked itself as needing redisplay and then ordered its window
  in, leaving the drawing to the next turn of the run loop. AppKit does not
  redraw a window that is not yet in the visible occlusion state, and a panel
  that has just been ordered back in is not marked visible until the window
  server says so — so the redraw request fell into that gap and was dropped.
  Ordering the panel out can also discard its backing store, so what came back
  was an empty, fully transparent window. The overlay now draws synchronously
  the moment it is shown, and again whenever the hovered icon changes.

## 1.2.0

- The icon strip is now slightly translucent, so the windows you are arranging
  stay visible underneath it. Adjustable in **Edit Layouts…**.

## 1.1.2

- Removed the padding inside each layout icon, so the preview fills the tile.

## 1.1.1

- The split in each layout icon now runs edge to edge instead of floating
  inside the tile's padding.

## 1.1.0

- Layout icons can be made much larger. The old ceiling was low enough to make
  the icons awkward targets to hit mid-drag.
- Gave the app icon some depth.

## 1.0.4

- Perch now requires Accessibility access, not merely a working event tap,
  before reporting itself as ready. A mouse-only, listen-only event tap starts
  even with no permission at all, so the menu could claim everything was fine
  while every window operation silently failed.

## 1.0.3

- The permission state is logged at launch, so a broken install can be
  diagnosed without attaching a debugger.

## 1.0.2

- Accessibility access is detected by trying to use it rather than by asking,
  which is the only answer that reflects reality.
- Added `tools/install-latest.sh`, which does the whole ad-hoc update dance:
  download, replace, strip the quarantine flag, clear stale permission
  entries, relaunch.

## 1.0.1

- Added a generated app icon.
- Documented the two-copies TCC trap in `docs/DEVELOPING.md`.

## 1.0.0

- Initial release. Drag a window, drop it on an icon, and it snaps to that
  layout. Layouts are editable, and the icon strip follows the drag across
  displays.
