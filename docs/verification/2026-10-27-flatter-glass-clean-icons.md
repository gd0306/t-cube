# Flatter glass and clean icon edges — 0.12.2 (build 22)

## Appearance

The user selected a soft box with shallower faces rather than a more spherical body. The shared projection now uses a quartic superellipsoid, with analytical cubic-gradient normals. The decal's center-to-corner depth range falls from roughly 0.115 to 0.080 units; rounded corners and continuous normals remain. Specular and clearcoat highlights are softer. Body, decals and picking still share the same geometry definitions.

## Black-fringe investigation

A controlled native render disabled all glass layers and displayed a synthetic white icon on white. The original premultiplied, 64-bit CGImage texture path produced 284 pixels below 0.95 brightness, with a minimum near 0.905. This reproduced a sampling fringe independently of glass reflections or an application's baked artwork.

`IconTexture` converts to RGBA8 sRGB, unpremultiplies covered RGB and extends boundary colors into 16 pixels of zero-alpha padding. Alpha coverage and opaque dark details are unchanged. Empty groups skip this work; padding propagation starts only at foreground boundaries. Preparation runs during texture refresh, not animation.

The repaired control produced zero dark-fringe pixels (minimum near 0.997 before the geometry change, approximately 1.0 in the final run). A second black-background capture verifies that the icon still renders, preventing an invisible icon from passing the white-background check. Pixel tests cover coverage, opaque black detail and both image axes.

## Verification

- The new shallower-face test failed on the previous geometry and passed on the quartic geometry.
- `env TCUBE_RENDER_PREVIEWS=1 swift test --scratch-path .build/tests` passed: 4 XCTest cases, 44 native Swift Testing cases and 66 core cases. Full output is in `.build/verification/flatter-glass-tests.log`.
- The 48 native oblique edge-click cases retain the same slots and viewing angles. Their fixture now projects barycentric points on the rendered triangles, rather than ideal continuous points just above the mesh, which can miss at grazing angles. No production picking change was needed.
- Native dark/light gallery captures were inspected and README assets refreshed. The controlled edge captures are `.build/glass-previews/icon-edge-{white,dark}-fixed.png`; the original white baseline is retained separately.
- Release app build, DMG build, `bash scripts/verify-dmg.sh`, README links, gallery dimensions and `git diff --check` passed.
- Independent read-only review found no concrete correctness issue in geometry, texture preparation or the fixture correction.

No configuration schema changes were required. Tests use temporary stores; native renderer captures are not desktop automation results. Packaging remains ad-hoc signed.
