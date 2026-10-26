# Idle rotation — 0.10.0 (build 18)

## Behavior

- Idle cubes rotate slowly around smoothly changing, independently seeded directions. Angular velocity blends to a new target every 5–9 active seconds, without snapping to canonical faces.
- Pointer entry immediately freezes the current orientation. Manual scrolling remains available while hovered; pointer exit resumes from that orientation.
- Both drag trackers, disabled rotation, hidden windows and Reduce Motion pause the motion. Paused time is discarded; long frame deltas are capped to avoid catch-up jumps.
- Appearance → 动态旋转 → 空闲时自动旋转 defaults to enabled and saves through Apply settings. Older configurations decode with rotation enabled while preserving existing data.
- Rendering reuses the existing scene subscription, throttled to at most 30 updates per second, and performs no configuration writes. File drops resolve the current scene orientation.

## Verification

- Before implementation, `swift test --scratch-path .build/tests --filter IdleRotation` failed on missing idle scene movement and missing persisted settings.
- Final `env TCUBE_RENDER_PREVIEWS=1 swift test --scratch-path .build/tests` passed: 4 XCTest cases, 37 native Swift Testing cases (including visual export), and 56 core cases.
- Core tests cover slow bounded motion, varying axes, smooth direction transitions, normalized quaternions, pause/resume continuity and invalid/long frame deltas.
- Native tests exercise the real scene subscription and input overlay, manual rotation while hovered, primary/secondary drag pauses, settings, hidden windows and Reduce Motion. The live-scene test accounts for the desktop's accessibility preference.
- `bash scripts/build-app.sh`, `bash scripts/build-dmg.sh --skip-build`, `bash scripts/verify-dmg.sh`, and `git diff --check` passed. The DMG's app, executable, signature, Applications link and installation note were verified.
- Read-only code review found no product correctness issues. Its test portability observation concerning Reduce Motion was addressed before the final run.

## Visual evidence and scope

The opt-in exporter writes `.build/glass-previews/idle-rotation-hover.gif`: idle rotation, a hovered interval with a fixed pose, then resumed rotation. Frames 11, 23 and 35 are also exported as PNGs; idle frames were inspected for composition. README material comparisons deliberately disable automatic rotation to retain matching views.

These are native scene captures with an isolated temporary configuration, not desktop automation. The tests verify scene motion and native input delivery; no claim is made about a fresh manual trackpad session. Local packages remain ad-hoc signed.
