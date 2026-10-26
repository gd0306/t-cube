# T-Cube 0.8.0 — softer edges and glass themes

The user supplied a luminous glass-cube reference, then clarified that edge and corner detail is the priority. The implementation emphasizes a transparent shell, gentler highlights and rounded joins; interior effects remain restrained.

## Changes

- Production connected bevel radius increases from 0.038 to 0.07; angular subdivisions increase from 24 to 32. Highlight profiles soften across the bevel and leave the middle transparent. Existing continuous welded geometry supplies tangent joins between edges and spherical corner patches.
- Added three presets: 幻彩水晶 (`prism`, iridescent), 月光凝露 (`moonstone`), 极光流体 (`auroraFlow`). These carry a material style as well as colors and participate in existing 10/20-second cycling.
- Appearance settings expose a material picker, preserve the selected material while editing custom colors, and include material identity when matching a preset. Legacy configuration decodes a missing material as clear glass, without changing stored colors, entries, scale or position.
- New materials show faint procedural light threads inside the shell. Their strength falls by 86% on hover to protect icon legibility; classic clear material disables them. Inner light uses one small sphere with cached procedural texture, no collisions. Per-frame updates only shift UV coordinates and layer opacity; chosen cube pose and window geometry do not change. Existing Reduce Motion behavior freezes the flow.
- Existing four-icon artwork, immediate launcher, native settings, theme cycling and Control + primary small-size dragging are retained.

## Verification

`env TCUBE_RENDER_PREVIEWS=1 swift test --scratch-path .build/tests` passed on 2026-10-26 at 14:55 local time: **82 tests, no failures** (4 XCTest native event-queue cases, 32 app/runtime/render cases, 46 core cases).

New checks cover old appearance decoding, material save/load with new theme cycling, material retention with custom colors, and restoring the manual material when cycling is disabled. Existing native-render checks confirm visible idle edges, live flow movement and unchanged cube pose.

Native production-view previews were inspected on dark, warm and light backgrounds and at several angles. Generated artifacts include `.build/glass-previews/soft-prism-dark.png`, `soft-prism-light.png`, `soft-moonstone.png`, `soft-auroraFlow.png` and `soft-glass-motion.gif`. The first and last recorded frames confirm interior light recedes as app icons appear. Fixtures use temporary isolated configuration, never the user's configuration.

Focused read-only code review and inner-light follow-up found no blocking issues. `git diff --check` passed. Desktop automation remains unavailable from the separately diagnosed local handshake failure; no physical input smoke check or running-app replacement is claimed.

## Package

`bash scripts/build-dmg.sh` successfully built version **0.8.0 / build 16** at `build/T-Cube-0.8.0.dmg`. `bash scripts/verify-dmg.sh` passed checksum, read-only mount, bundle executable and plist comparison, signature, Applications link and installation-note checks. The verification image was ejected successfully.
