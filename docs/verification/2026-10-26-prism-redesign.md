# T-Cube 0.7.0 — transparent prism redesign

## Research and visual direction

Reviewed primary design references:

- [Apple — Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/): rounded floating forms, separation defined by light, motion and appearance designed together.
- [Spline — Glass Layer](https://docs.spline.design/materials-shading/shading-and-reflection/glass-layer): glass combines transparency, reflection and optical thickness, with material layering for richer results.
- [Miras Zhanatov — 3D Cube animation](https://dribbble.com/shots/23620747-3D-Cube-animation): inspected the published prism rendering for rounded edge continuity and concentrated chromatic highlights.

The desktop launcher uses an open transparent prism with concentrated light, rather than adopting the reference's solid colored body. The old rendering's uniform gray bevel looked like plastic, and its shallow viewing angle made the front dominate. The replacement uses a stronger three-face presentation and restrained layered edge illumination. Six face interiors remain clear at rest; each hovered face retains exactly four native app icons, with no labels or additional controls.

## Implementation

- `CrystalAppearance.swift`: one cached rounded bevel mesh, thin pearl highlights, low-opacity contrast and flowing selected-theme color. A faint diagonal face sheen appears only while hovering. Textures are generated on palette changes, never per frame; neutral resources are cached. Glass light is simulated; real desktop content behind the window is not refracted.
- `PrismMotion.swift`: elapsed-time 18-second light cycle and 160 ms hover response, bounded resume delta, ignored invalid deltas, and frozen flow under macOS Reduce Motion. Near-zero hover sheen settles fully to zero and disables its planes.
- `CubeView.swift`: weak scene subscription, at most 30 updates/second, skips hidden windows. Only texture offsets and layer opacity change; the user's chosen pose, window geometry, native input and saved configuration are untouched by animation.
- `Rotation.swift`: new default display angle yaw -0.66, pitch 0.52. The six-face upright test uses independently calculated normal/up vectors for this intentional display-angle change.

Existing theme cycling, hover scale, Control + primary drag, immediate face expansion, four-icon face artwork, native settings and quit behavior remain in place.

## Verification artifacts

The opt-in native renderer exports `.build/glass-previews/prism-dark.png`, `prism-warm.png`, `prism-light.png`, `prism-idle.png` and `prism-motion.gif`. These are snapshots of the production RealityKit view, using an isolated temporary configuration with system app icons. No user configuration is modified. The GIF is a short recorded segment of the running light animation, including a hover transition.

Checks include visible idle edges without icons, actual scene-clock texture movement, unchanged cube orientation during light animation, hover response, Reduce Motion, invalid/resumed frame times and all previous native input/persistence cases.

Final `env TCUBE_RENDER_PREVIEWS=1 swift test --scratch-path .build/tests` passed on 2026-10-26 at 10:44 local time: **78 tests, zero failures** (4 native event-queue XCTest cases, 31 native/runtime/render cases, 43 core cases). Final dark/light renders and recorded first/last motion frames were visually inspected. `git diff --check` passed.

`bash scripts/build-dmg.sh` built **0.7.0 / build 15** at `build/T-Cube-0.7.0.dmg`. `bash scripts/verify-dmg.sh` passed image checksum, read-only mounting, bundle plist/executable comparison, signature, Applications symlink and installation-note checks, then ejected the verification mount successfully.

Focused read-only review found no blocking issues. Its settled-sheen suggestion was applied. An additional occlusion-state guard was tried but stopped scene-clock updates in native snapshot fixtures, whose visible nonactivating panels do not reliably report unoccluded state. The implementation retains the verified visibility guard and RealityKit's scene scheduling. Live external desktop automation remains unavailable from the earlier `Sky Computer Use native pipe startup failed`; no physical mouse check or running-app replacement is claimed.
