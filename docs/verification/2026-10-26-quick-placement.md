# Quick placement — 0.11.0 (build 19)

## Behavior

- The menu bar's 快捷位置 submenu and Appearance's 快捷位置 buttons offer top left, top right, bottom left, bottom right and center. Both invoke the same app action.
- Placement uses the screen nearest the cube's resting center and its visible frame, excluding the menu bar and Dock. Corners have a 24-point margin, reduced when space is limited.
- Requests use the resting cube size, clear temporary Control geometry and save the resting origin immediately. Later hover exit does not restore an old location or save an enlarged frame.
- The app closes an expanded face and shows a hidden cube before placing it. Active drags reject placement requests. No new configuration fields are required.

## Checks

- `swift test --scratch-path .build/tests --filter QuickPlacement` passed all six new cases. They cover hand-calculated coordinates, negative and detached display coordinates, small/oversized screens, real NSMenu actions with disk persistence, hover/Control geometry, and drag rejection.
- `swift test --scratch-path .build/tests` passed the full suite; optional native image export remained disabled. Existing drag, direct launch, idle rotation, themes and placement checks passed.
- `bash scripts/build-app.sh`, `bash scripts/build-dmg.sh --skip-build`, `bash scripts/verify-dmg.sh` and `git diff --check` passed. README links were verified.
- Read-only code review found no critical or important issues. AppDelegate's hidden-window reveal wiring was reviewed but not exercised through desktop automation.

## Native test environment

An initial negative-screen runtime fixture described a display at y=0 with height 1080, while the real attached display starts at y=-102. NSWindow constrained its requested upper position, confirmed by `constrainFrameRect`. The native fixture now uses a smaller 800-point extent; core geometry tests retain arbitrary screen coordinates. No application behavior was changed to bypass AppKit constraints.

Tests use temporary configuration stores. No manual multi-monitor clicking session or desktop automation result is claimed.
