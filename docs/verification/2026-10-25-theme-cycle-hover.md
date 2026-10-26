# T-Cube 0.6.0 verification

Version 0.6.0/build 11, verified 2026-10-25. Development branch: `feat/theme-cycle-hover`, based on the previously pushed 0.5.4 commit `1539938`.

## Delivered behavior

- Six color presets: Aurora, Ocean, Sunset, Starfield, Blossom, Forest. Appearance settings support selecting multiple presets in order and cycling every 10 or 20 seconds.
- The active cycling theme is transient and updates only the aura; a tick does not save JSON, rebuild icon textures, or resize the panel. Stopping rotation restores saved manual colors. Glow intensity remains user-configured.
- Pointer entry enlarges the cube without clicking; pointer exit restores its resting size. Latest user steering sets the default multiplier to **2.0**, doubling width and height. The multiplier remains configurable from 1.1 to 2.0.
- Resting geometry is separate from hover presentation. Repeated hovering near a screen edge does not change saved position. Gestures freeze geometry until release; dragging an enlarged cube saves its corresponding resting position.
- Existing icon-only faces, transparent Liquid Glass launcher, immediate primary click, wheel pose preservation, right/primary dragging, status menu and settings Exit button remain.
- Old configurations keep apps, folders, manual colors, resting scale and position. Missing new preferences default to rotation disabled and hover enabled at 2×.

## Automated checks

Final `swift test --scratch-path .build/tests` passed at **21:41:59**, with **61 tests and zero failures**: 1 XCTest native right-event-queue test, 25 native/runtime/appearance tests, 35 core tests.

New coverage includes configuration migration/round-trip and invalid preferences, preset order/wrap, timer state and cancellation, preservation of glow, no disk writes or full-change callbacks on ticks, no timer reset on unrelated edits, model release while its timer sleeps, native pointer-enter/exit without mouse buttons, 2× default enlargement, repeated screen-edge entry/exit, gesture freeze, enlarged-drag normalization, and primary drag through the actual input receiver.

Focused core and hover reviews and a complete integration review found no important correctness issues. A scoped follow-up review approved event-coordinate forwarding and the updated 2× default. `git diff --check` passed.

## Actual release application

- Launched `build/T-Cube.app` through the desktop tool. Idle window capture was approximately **214 × 214 pixels**.
- Moved the tool's input into the cube with a scroll event, without clicking. The window capture became approximately **428 × 428 pixels** with visible face icons, confirming 2× enlargement in the running app. A pure hardware-hover action is not exposed by the desktop tool; the no-button native entry/exit test covers that event path directly.
- Opened Appearance and inspected the six preset controls, multi-selection checkboxes, 10/20-second interval picker, automatic enlargement toggle and **2.0×** multiplier.
- Enabled rotation with the default selected Aurora/Ocean/Sunset themes and 10-second setting. The live “当前主题” value advanced automatically while settings were left open, with no manual theme action.
- Changed the interval to 20 seconds, applied it, and confirmed `intervalSeconds: 20` in the saved configuration. Changing the cycle settings restarted from Aurora as intended.
- Restored rotation to disabled with the default 10-second selection. The user's manual Aurora colors, glow intensity 1, and resting scale 0.65 remained. Hover remained enabled at 2×. Existing launcher entries were not edited during QA.
- Closed Settings; the cube capture returned to approximately **214 × 214 pixels** after leaving its region.

The desktop captures are isolated window images; transparent pixels do not include the desktop backdrop.

## Installer

`bash scripts/build-dmg.sh` generated `build/T-Cube-0.6.0.dmg`. The final `bash scripts/verify-dmg.sh` verified its checksum, mounted it read-only, compared binary and bundle metadata, checked the local signature, Applications link and installation note, then detached it successfully.

The package is Apple Silicon, locally ad-hoc signed, without Apple notarization. No remote push was made for this development request.

## 0.6.1: double the previous hover effect

Latest request: make the already-enlarged cube twice as large again. Updated default and maximum hover multiplier from 2.0 to **4.0** (both width and height relative to the resting cube). Updated validation, UI slider, error text, defaults and README. Existing saved multipliers remain readable.

Updated the native no-button pointer test to expect a 100 × 100 resting panel to become 400 × 400 and then restore. The updated default/round-trip tests and native geometry test failed against 0.6.0, then passed after the change. Full suite passed at **22:15:52** on 2026-10-25: **61 tests, zero failures**.

Launched 0.6.1 and set the current user's saved multiplier to 4.0 through Appearance, then applied it. Saved configuration was checked. The user's current enabled six-theme cycle and resting scale were preserved. The isolated live cube capture measured approximately **214 × 214 pixels** while idle and **854 × 854 pixels** enlarged, approximately twice the preceding 428 × 428 hover capture.

Generated `build/T-Cube-0.6.1.dmg`; final image checksum, mounted binary/metadata, local signature, Applications symlink and installation note all verified, and the image detached successfully. `git diff --check` passed.
