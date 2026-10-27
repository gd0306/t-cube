# macOS slime hover experiment

Historical prototype record. The integrated version exposes slime as an independent material, shared by all themes; see [material selection verification](2026-10-28-material-selection.md).

Branch: `experiment/slime-hover`, based on `450a54f` on `master`.

## Behavior

- A tinted, translucent gel shell replaces the thin glass appearance in this experimental macOS build.
- Moving the pointer across the body pulls a local patch outward. The contact trails quick pointer movement; releasing it produces a damped elastic rebound.
- Launcher decals keep their original geometry and picking, so icons remain sharp and stable.
- Pointer coordinates are captured in screen space after native hover handling. Ray picking is coalesced to the scene's 30 Hz animation cadence and refreshed after rotation or window-frame changes.
- Hover exit and window/rotation drags release the deformation. Reduce Motion removes it. The feature adds no persisted configuration fields.
- One `LowLevelMesh` streams positions and corrected normals to all shell layers; topology and texture buffers are retained.

## Automated verification

```sh
env TCUBE_RENDER_PREVIEWS=1 TCUBE_SLIME_PREVIEWS=1 swift test --scratch-path .build/tests
bash scripts/build-app.sh --debug
codesign --verify --deep --strict build/T-Cube.app
git diff --check
```

All passed: 4 synchronous XCTest cases, 46 native Swift Testing cases (including both enabled render previews), and 69 core Swift Testing cases, 119 total.

Focused regression cases were observed failing before the implementation/fix, then passing:

- Pointer motion must move shell vertices while leaving icon vertices, cube pose, window frame and saved configuration alone.
- A discrete scroll rotation under a stationary pointer must pull the newly visible patch instead of retaining the old local contact.
- Contact motion must lag, rebound through rest and settle; invalid time and Reduce Motion must not leave an animated deformation.
- A transparent-window snapshot must retain visible coverage. The initial material had only about 12% center alpha; the final material has about 23%. A white-background composite must retain visible tint.

The opaque-backdrop test now normalizes the center response by the actual sampled background difference. Its floor is 40% for the deliberately thicker gel, paired with the separate clear-window visibility check. The final normalized response was approximately 0.436.

Logs: `.build/slime-final-tests.log`, `.build/slime-app-build.log`. Native images and the pointer/rebound GIF are in `.build/slime-previews/`; regenerate them with the command above.

## Local installation and desktop observation

The previously running application was `build/T-Cube.app`; no copy was installed in `/Applications` or `~/Applications`. The experiment overwrote that local bundle, passed ad-hoc signature verification, and was launched from the same path using the existing user configuration. Test fixtures were stored in temporary directories, never in the user's configuration file.

Native clear-background snapshots and white composites show the gel shell. The desktop automation tool's JPEG capture shows launcher icons but largely omits the optical shell, unlike the native scene capture. The user directly inspected the running application and confirmed that both the gel shell and pointer deformation are visible ("都能看到"). Treat this as the desktop visual confirmation rather than the automation tool's JPEG capture.

This remains an experimental branch. Windows rendering is unchanged.
