# T-Cube 0.5.0 interaction verification

Verified on 2026-10-25. Bundle version 6, macOS 15+, Apple Silicon local development build.

## Root cause of the reported movement failure

The user confirmed using a trackpad press-and-drag or primary mouse button drag. Version 0.4.1 intentionally ignored movement in `mouseDragged` for the primary button; its regression test explicitly expected the panel to remain stationary. Previous right-button tests did not cover the user's operation.

Reproduced primary dragging without movement in the actual 0.4.1 application. Replaced the old test with the requested movement contract, observed failure (actual origin 100,175 versus expected 140,200), then implemented primary drag movement and saved position on release. Right-button movement remains supported.

## Current behavior

- Primary mouse button, trackpad press-and-drag, right-button drag, and Control + primary drag can move the floating panel. A drag does not rotate the cube or open an entry.
- Scrolling updates rotation directly and remains at that orientation without automatic alignment.
- Single-click selects the full visible face, including transparent areas and its rim. An analytic cube ray intersection avoids dependence on tiny textured icon hit regions or collider readiness.
- A native animated popover expands the selected face into a larger four-entry panel. Selecting an occupied entry opens its application/folder and closes the panel. Selecting an empty entry opens settings for that face.
- Single-click expansion waits for the system double-click interval. A second click cancels expansion and opens settings.
- The persistent settings footer contains an Exit T-Cube button, outside both settings tabs.

## Automated verification

`swift test --scratch-path .build/tests` completed successfully at 20:25:53: **41 tests, zero failures** (1 XCTest native right-event-queue test, 10 native/appearance Swift Testing tests, 30 core tests).

Coverage added/updated for primary movement and persistence, click-to-expand, double-click cancellation, all six face surfaces including clear rims, oblique nearest-face selection, and invalid/missing ray hits. Existing no-snap, hover, right-button movement/click, configuration preservation, and appearance tests remain passing.

Read-only independent code review found no important issues in these interaction changes. `git diff --check` passed.

## Actual desktop verification

- Reproduced the old primary drag failure before changing its behavior.
- Dragged the updated live floating window repeatedly with the primary mouse button through the desktop tool. One check moved persisted coordinates from 723,345.5 to 783,315.
- Repeated movement in the final 0.5.0 application: persisted position changed from 663.52734375,388 to 713,362.5 after an approximately 50-point horizontal / 25-point vertical drag. No settings window or entry opened during drag.
- Single-clicked the cube and observed an expanded Common face containing Notion and three empty entries in the native accessibility tree.
- Selected the Notion button in the final expanded Common face; the popover closed and no error dialog appeared. Notion was already running during this check.
- Opened another visible face (Folders), selected its empty entry, and observed Settings select the Top/Folders group.
- Double-clicked the cube and observed Settings open directly without a face launcher.
- Visually inspected the settings page: the Exit T-Cube button is visible in the lower-right footer.
- Clicked that Exit button, then checked the process list before re-querying the desktop app: **no TCube process remained**. Re-launched the final app afterward for use. (The desktop tool's later app observations may re-launch an exited app.)

Hardware right-button dragging is still covered by internal native event tracking tests rather than a physical right-button drag through the desktop tool; the reported primary dragging operation was tested in the live app.

## Installer

`bash scripts/build-dmg.sh` successfully generated `build/T-Cube-0.5.0.dmg`.

`bash scripts/verify-dmg.sh` passed: valid image checksum, read-only mount, matching app executable and metadata, valid local signature, correct Applications symlink and installation note; image detached successfully afterward.

The package uses an ad-hoc local signature and has not been notarized by Apple.
