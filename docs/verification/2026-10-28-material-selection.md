# Independent glass and slime materials

The macOS Appearance settings now have a separate **Material / 材质** selector with **Glass / 玻璃** and **Slime / 史莱姆**. Glass remains the default. The existing nine themes, custom colors, optical styles and automatic theme cycling are shared by both materials; Slime is not a theme preset or a cycling-list entry.

`CubeAppearance.material` persists the selection and defaults to glass when decoding existing configurations without that field. Theme presets preserve the selected material when displayed by the automatic cycle. Switching material preserves the active theme and saved colors. Only changing material resets the shell mesh and elastic state; changing theme while using slime leaves the deformation active.

Ordinary glass retains its original mesh, PBR settings, opacity and pearl highlights. Slime lazily creates the dynamic mesh. Stable launcher decals, ray picking, window movement, rotation and Reduce Motion behavior remain covered by the existing regressions.

## Automated verification

```sh
env TCUBE_RENDER_PREVIEWS=1 TCUBE_SLIME_PREVIEWS=1 swift test --scratch-path .build/tests
bash scripts/build-app.sh --debug
codesign --verify --deep --strict build/T-Cube.app
git diff --check
```

All passed: 4 synchronous XCTest cases, 48 native Swift Testing cases and 70 core Swift Testing cases, 122 total. Both opt-in visual exports were enabled. Logs are in `.build/slime-material-full-tests.log` and `.build/slime-material-build.log`.

Coverage includes old configuration decoding, every theme combined with both materials, persisted material selection, cycling without material changes, changing material without changing the active theme, glass remaining rigid across optical styles, slime motion/rebound, re-entry resetting the old deformation, native pointer input and transparent-window visibility. The original glass backdrop-response check remains above 0.70 (measured approximately 0.723).

Independent code review found no important issues.

## Local desktop verification

The local `build/T-Cube.app` was replaced and relaunched. In the actual settings window, Appearance shows an enabled Glass/Slime segmented selector while automatic theme cycling is enabled. Glass is selected; the theme grid contains the original nine presets and no Slime preset. The optical-style picker is labeled 光效样式. The settings footer reads 设置已保存, and Apply is disabled; no user settings were applied during this inspection.

Native PNG/GIF exports remain under `.build/slime-previews/` and `.build/glass-previews/`. The earlier [slime hover record](2026-10-27-slime-hover.md) describes the experimental prototype; this record describes the integrated material selection. Windows rendering is unchanged.
