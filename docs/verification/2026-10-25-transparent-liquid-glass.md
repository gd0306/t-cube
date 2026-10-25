# T-Cube 0.5.2 final refinement

This supersedes the expanded-panel presentation described for 0.5.0. User requested only four app icons, dismissal on any outside click, and transparent Liquid Glass.

## Final presentation

- 220 × 220 point borderless, non-opaque NSPanel with clear window background. No NSPopover shell, arrow, header, instruction, app-name text, configuration button, or close button.
- On macOS 26+, content is embedded directly in NSGlassEffectView with style `.clear`, no tint, and 24-point corners. On macOS 27 interactive glass feedback is enabled. Earlier supported macOS uses NSVisualEffectView behind the window as a compatibility fallback.
- Four fixed icon positions in a 2 × 2 arrangement, 64-point icons. Unconfigured positions remain blank and have no control.
- Clicking an icon closes the expansion and opens the configured target. Local outside mouse-down events close and are consumed, preventing an immediate second expansion. Mouse-down events in other applications close via a global mouse event monitor. Both monitors are removed on close. Esc also closes.
- Primary/trackpad dragging, right dragging, free scroll orientation, and the settings footer Exit button remain in place.

## Evidence

`swift test --scratch-path .build/tests` passed at 20:41:24 on 2026-10-25: **42 tests, zero failures** (1 XCTest + 11 native/appearance + 30 core).

The new expansion regression test exercises the production controller with actual windows: clicks belonging to the expansion preserve it, source-window clicks dismiss it, and the nil-window path used by the global monitor dismisses it. A focused independent review found no important issues with transparent compositing or event-monitor lifecycle.

Launched the final release app through the desktop tool. Single-clicked the cube and observed a separate T-Cube · 入口 window. Its accessibility tree contained only the grid and the configured Notion button; the other three positions were blank. Its window screenshot showed a thin rounded glass perimeter and the icon without the removed controls. The screenshot captures the isolated window and does not show the desktop backdrop behind its transparent pixels.

Clicked outside the expansion on its right side through the desktop tool and observed it disappear, returning to the T-Cube floating window. The existing live primary-drag and actual Exit-button checks are recorded in `2026-10-25-primary-drag-face-expansion.md`.

`bash scripts/build-dmg.sh` generated the final `build/T-Cube-0.5.2.dmg`. The subsequent `bash scripts/verify-dmg.sh` passed checksum, read-only mount, app binary/metadata comparison, local signature, Applications symlink, and installation-note checks; the image was detached. This is a local ad-hoc signed development package, not Apple-notarized.

## 0.5.3: icons only on all six cube faces

Removed group titles, entry-name captions, and empty-slot plus marks from the shared face texture renderer. Existing icon positions remain unchanged, and unconfigured slots are transparent.

Added rendering regressions: changing group/entry names must not change the face image, and an unconfigured face must contain no visible pixels. Both tests failed against the previous renderer, then passed after removing text and placeholder drawing. Updated the existing visible-content test to use a real configured folder icon.

`swift test --scratch-path .build/tests` passed at 20:52:09: **44 tests, zero failures** (1 XCTest + 13 native/appearance + 30 core). Release build and `scripts/verify-dmg.sh` passed for `build/T-Cube-0.5.3.dmg`; `git diff --check` passed.

Launched 0.5.3 through the desktop tool. Clicking the face still opened its icon-only transparent glass panel, and clicking outside closed it. The isolated cube screenshot did not expose hover content during this automation check, so it is not used as visual evidence for the face textures; the render regressions verify icon visibility and removal of captions/placeholder marks.

## 0.5.4: immediate click expansion

The reported latency was an explicit wait for `NSEvent.doubleClickInterval` before requesting expansion, followed by a 180 ms opacity/scale animation. Removed the task, double-click settings branch, and custom introduction animation. A completed primary click now selects the hit face and requests expansion synchronously from `mouseUp`. Settings remain accessible through right-click, the status menu, and Command-comma.

Updated two interaction regressions to assert expansion immediately when `mouseUp` returns, without sleeping or yielding. They failed against 0.5.3, then passed after removing the wait; repeated clicks also expand without opening settings. The 150 ms fixture wait happens before any input to let the camera initialize, and is not part of the expansion assertion.

`swift test --scratch-path .build/tests` passed at 20:56:41 with **44 tests, zero failures**. Release packaging succeeded for `build/T-Cube-0.5.4.dmg`. Launched that release and clicked a face through the desktop tool: the first state query after the click already showed T-Cube · 入口 and the Notion button, without the second observation required by previous versions. Clicking outside returned to the cube. No hardware latency in milliseconds is inferred from the automation call duration.

The final DMG checksum, mounted app binary/metadata, local signature, Applications symlink, and installation note were verified successfully and the image detached. `git diff --check` passed.
