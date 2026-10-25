# T-Cube 0.4.1 verification

Verified on 2026-10-24 on the development Mac. Bundle version 5, macOS 15+, Apple Silicon local build.

## Interaction changes

- Scroll updates the displayed quaternion directly. There is no delayed face alignment, snap task, or rotation animation after input stops. Trackpad momentum events are ignored.
- Right-button movement uses an explicit AppKit tracking loop from mouse-down through drag and release. It moves the panel using screen coordinates and saves the final position. Control + left drag follows the same path for trackpad use.
- The clear native input overlay remains eligible for window hit testing. Right-click opens settings on release, while a drag does not open settings.
- Both trackpad axes rotate the cube; the physical gesture direction is independent of the Natural Scroll preference.

## Automated verification

`swift test --scratch-path .build/tests` completed successfully at 13:20:19: 36 tests, zero failures (1 XCTest native event-queue test, 8 native/appearance Swift Testing tests, 27 core tests).

The event-queue test creates a visible panel and posts right-drag and right-up events into its own application queue. The production tracking loop consumes those events, moves the panel by 40 × 25 points and persists the new position. It does not synthesize input into another application. A separate regression test verifies the displayed scroll pose remains unchanged after 650 ms.

Other coverage includes input routing, right-click versus drag, hover visibility, clear face backgrounds, scroll direction and both axes, appearance persistence and migration, invalid configuration preservation, launch entries, and screen placement.

## Actual application checks

- Launched the release build `build/T-Cube.app` through the desktop tool.
- Right-clicked the cube and observed the settings window open successfully, then closed it and returned to the floating cube.
- Inspected the clear idle cube screenshot: only a very faint rim is visible, without app icons or a filled face interior.
- In the preceding 0.4 settings verification, switched to Ocean and applied it, then restored Aurora and applied it. The saved state was visible in the settings UI.

The desktop tool cannot perform a held right-button drag. Continuous physical mouse/trackpad dragging therefore still requires user confirmation; the native application event-queue test verifies the production drag path without claiming hardware validation.

## Installer

`bash scripts/build-dmg.sh` completed successfully and generated `build/T-Cube-0.4.1.dmg`.

`bash scripts/verify-dmg.sh` completed successfully: image checksum valid, read-only mount succeeded, app/executable/Info.plist matched the built application, application signature verified, Applications symlink targets `/Applications`, and the installation note matched. The image was detached successfully afterward.

This is a locally ad-hoc signed development build, without Apple notarization.
