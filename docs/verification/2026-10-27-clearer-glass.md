# Clearer glass — 0.12.3 (build 23)

## Change

The optical root now has 0.25 opacity, fading the glass shell, reflection, theme color and inner light together. Launcher decals are siblings of that root and retain their own full opacity. The shallower shape, curved hit areas, rotation, placement and stored configuration are unchanged.

Both READMEs describe the lighter appearance and latest interactions. Their matched native gallery is refreshed, and the GIF now demonstrates idle rotation, hover pause and resumption. Installation commands and short agent prompts continue to use `master`.

## Verification

- The native background-response requirement was strengthened from 0.45 to 0.70. The previous renderer failed at approximately 0.565; the final full run passed at approximately 0.724. This measures rendered backdrop response, not a claimed physical transmittance percentage.
- `env TCUBE_RENDER_PREVIEWS=1 swift test --scratch-path .build/tests` passed: 4 XCTest cases, 44 native Swift Testing cases and 66 core cases. The white-icon control still reported zero dark-fringe pixels. Full output is in `.build/verification/clear-glass-tests.log`.
- Native hover and idle captures were inspected. All four README assets are 1120×840 with a matching graphite background. The movement GIF comes from the real running scene, with pose checks during hover pause.
- Both README link sets, version references and master installation commands were verified.
- `bash scripts/build-app.sh`, `bash scripts/build-dmg.sh --skip-build`, `bash scripts/verify-dmg.sh` and `git diff --check` passed. The installer app, executable, signature and installation links were verified.
- Read-only review confirmed that root opacity persists through material updates and does not affect icon decals or interaction geometry.

The release also includes the earlier reviewed idle rotation, quick placement, soft shell, curved icons and texture-edge fixes that were developed after the last master update. Native captures use temporary stores and are distinct from desktop automation. No user configuration migration is required.
