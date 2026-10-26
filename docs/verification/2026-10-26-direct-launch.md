# T-Cube 0.9.0 — thin edges and optional face expansion

## Behavior

- The connected rounded bevel radius is reduced from 0.07 to 0.028, narrowing the geometric edge width by 60% while retaining smooth joins, 32 angular subdivisions and soft optical profiles. The transparent face sheen is resized to fit the larger opening. Cube/window scale and icon placement are unchanged.
- Appearance settings include “打开方式 → 点击面展开放大”. It defaults to enabled for both new and legacy configurations. Disabling it and choosing “应用设置” enables direct icon clicks.
- Direct mode intersects the nearest cube face with the actual icon plane, transforms into that face's local coordinates and tests the icon's painted rectangle. Rendering and hit mapping share the same rectangle definition. Blank margins, gaps and empty slots do nothing; clicks do not pass through to faces behind the cube.
- Native mouse-up launches the selected slot through the existing AppModel launch service. Existing primary drag and Control move-only gestures do not launch an icon. Right-click settings and face expansion mode are retained.
- The configuration flag is persisted atomically with other settings. Tooltip and accessibility guidance track the active mode.

## Verification

`env TCUBE_RENDER_PREVIEWS=1 swift test --scratch-path .build/tests` passed on 2026-10-26 at 15:22 local time: **90 tests, no failures** (4 native event-queue XCTest cases, 35 native/runtime/render cases, 51 core cases).

New tests cover configuration migration and persistence, all four front icon coordinates, all six face orientations, blank/margin rejection, and native projected clicks across all 24 face slots. Native checks also cover empty slots, immediately changing the mode, and no launch during drag or Control move-only gestures. Launch callbacks capture commands at the existing OS launch boundary, so tests do not open external apps.

Production-view render artifacts at `.build/glass-previews/thin-prism-dark.png`, `thin-prism-light.png`, `thin-glass-idle.png` and `thin-glass-motion.gif` were generated; dark/light snapshots were visually inspected. Fixtures use temporary configuration files. `git diff --check` passed.

Focused read-only review found no blocking issues in picking, launch wiring, gestures, settings or migration. Desktop automation is still unavailable due to the separately investigated local connection handshake failure; no physical input smoke check or actual desktop app launch is claimed.

## Package

`bash scripts/build-dmg.sh` successfully built **0.9.0 / build 17** at `build/T-Cube-0.9.0.dmg`. `bash scripts/verify-dmg.sh` passed image checksum, read-only mounting, executable/plist comparison, signature, Applications link and installation-note checks. The verification mount was ejected successfully.
