# T-Cube 0.6.3 — Control + primary drag

## Behavior

- Holding Control over the cube temporarily restores its resting size. The pointer retains its relative position in the small cube, including when starting near an enlarged corner.
- Control + primary-button drag moves the small cube and saves its actual resting position. Releasing Control during the gesture does not resize until primary-button release.
- Releasing Control outside a drag resumes normal hover enlargement. Modifier-only changes do not save a temporary position.
- Control-click does not open settings or a face. Existing primary drag, secondary drag, secondary click and face click remain available.
- Local modifier events provide immediate updates. A 30 Hz modifier-state timer runs only while hovering or interacting, including the native tracking loop, so an inactive floating panel can respond without a global keyboard monitor.

## Validation

`env TCUBE_RENDER_PREVIEWS=1 swift test --scratch-path .build/tests` completed successfully on 2026-10-26 at 10:00:52 (local time): **75 tests**, no failures (4 XCTest native event-queue tests, 31 app/runtime/render tests, 40 core tests).

New coverage checks stationary native modifier events, pointer anchoring, repeated Control transitions without position drift or saves, entering with Control already held, committing while Control remains held, and releasing Control mid-drag. Native event-queue tests exercise the real overlay receiver and nested AppKit tracking loop, including shrink-on-mouse-down and disk persistence. Control-click was first observed failing against the former secondary-click routing and now passes.

Synthetic drag/up events are created after shrinking in the event-tracking run loop: AppKit encodes their Y coordinates against the window height at construction. Fixtures use isolated temporary configuration stores, not the user's configuration.

Focused read-only review found no blocking issues. `git diff --check` passed.

## Desktop limitation

The desktop tool still reports `Sky Computer Use native pipe startup failed`, so physical Control transitions while another application is active have not been exercised in a live desktop session. Native modifier delivery and drag event handling are verified within the app test process. The running desktop app has not been replaced or restarted by this task.

## Package

Version **0.6.3 / build 14**. `bash scripts/build-dmg.sh` completed successfully and generated `build/T-Cube-0.6.3.dmg`. `bash scripts/verify-dmg.sh` then passed image checksum, read-only mount, bundled executable and Info.plist comparison, signature, Applications link and installation-note checks. The verification mount was ejected successfully.
