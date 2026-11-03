# Full-length edge reflection / 0.20.2 (37)

The user found that the 0.20.1 collapsed handle looked bright only in its middle with black ends. The macOS reflection was only 20 points tall over a 52-point capsule, with near-black tint and transparent gradient ends. The original native dark preview center-column samples were RGB (19,22,28) near the top, (106,113,123) in the middle and (15,16,21) near the bottom. The Windows renderer also faded the reflection completely out during parts of the cycle.

## Fix and scope

Only the collapsed handle rendering changes. A broad reflective gradient spans three capsule heights and moves gently back and forth while remaining over both ends throughout its cycle. Dark tint is softened to blue black, and the highlight shoulders retain color rather than becoming transparent inside the capsule. Static accessibility/low-power styles retain a full-length reflection. Forced colors still use system colors on Windows. The 10×56 hit geometry, 8×52 visible body, right-window shape alignment, system appearance following, cube, input and data behavior are unchanged.

macOS still uses one cached gradient and one Core Animation translation, with an eight-second cycle and preferred 24 FPS (12–30 range). The raster is 16×312 RGBA pixels at 2× scale (about 20 KiB before platform overhead), not a large image or full-screen effect. Windows still uses a single CSS transform animation and local packaged assets. No frame/timer callbacks, windows, dependencies or 3D rendering are added. Existing hidden/occluded/static-mode animation gates remain intact; visibility checks still fail closed.

## Verification

- Red/green: the real native dark-end pixel regression failed at both ends on 0.20.1 and passed on the fix. Restoring the old production animation also failed the new native extrema pixel regression; restoring the fix passed. Native tests freeze actual production keyframe offsets and inspect both ends, rather than deriving expected coverage from the implementation.
- Red/green: actual Chrome phase-zero coverage/opacity failed on the old renderer. The fixed renderer passes five phases in both appearances, including real screenshot pixel brightness at both ends. Temporarily removing the reflection background still failed the dark screenshot assertion despite full layer geometry/opacity, proving it checks visible output.
- `swift test --no-parallel --scratch-path .build/tests`: 6 XCTest + 148 native + 126 core registered; 271 executed/passed, nine opt-in cases skipped. Enabled edge preview/focused verification separately passed all six edge-view cases.
- Node 22 `npm run typecheck`, `npm test`, `npm run build`: typecheck/build passed; 226 tests passed and one Win32-only test skipped on macOS. Updated actual Chrome screenshot checks and actual Electron lifecycle/media/CSP/right-offset/stale-DOM visibility fixtures passed.
- Existing 40-cycle animation count checks still retain exactly one animation while visible and zero while hidden/occluded/static. No lifecycle code was changed.
- Independent read-only review found no blocking functional, resource or accessibility issues. The optional concern about Windows geometry-only checks was addressed with both-appearance screenshot pixel checks and the missing-reflection mutation above.
- Release app build and mounted DMG checksum, signature, executable, Applications-link and install-note checks passed. `git diff --check` passed.

## Native previews

| macOS light | macOS dark | Windows light | Windows dark |
| --- | --- | --- | --- |
| <img src="../images/full-edge-mac-light.png" width="40" alt="Full-length native light reflection"> | <img src="../images/full-edge-mac-dark.png" width="40" alt="Full-length native dark reflection"> | <img src="../images/full-edge-windows-light.png" width="40" alt="Full-length Windows light reflection"> | <img src="../images/full-edge-windows-dark.png" width="40" alt="Full-length Windows dark reflection"> |

The native cache exports show actual material/tint/reflection layers; they do not screen-capture WindowServer desktop backdrop blur. Windows previews and sampled pixels come from the actual local renderer.

## Acceptance

The existing 0.20.1 app and four recursive user JSON files were backed up under ignored `build/install-backups/0.20.2/20261103-194721/`. Local installation requires normal exit of the running app. Installation, remote native CI and public artifact verification are pending and will be recorded after execution. The previously unavailable computer-use service means manual desktop checks must be distinguished from automated native fixture checks.
