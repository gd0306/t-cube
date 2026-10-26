# Curved icons — 0.12.1 (build 21)

## Change

Icon textures now drape over subdivided curved patches instead of floating flat planes. Glass and decals share the cubic surface projection; a 0.0015-unit normal offset prevents surface interference. One cached GPU mesh is reused across the six group orientations. Empty pixels stay transparent and no face outline is introduced.

Direct clicks intersect the same cached triangles and interpolate their texture UVs, then use the existing icon rectangles. Only the nearest front-facing patch receives a click, including when its slot is empty. Face expansion intersects the glass body's mesh, so transparent space beyond its rounded corners no longer opens a group. Drag, Ctrl move-only and hover behavior remain unchanged.

## Verification

- Before implementation, an oblique ray targeting the curved right edge of slot 0 returned no icon. The regression now passes.
- New core cases cover shell conformity across the entire patch, hand-calculated surface points, outward triangles, upright UVs, six groups, all four slots, margins and three viewing directions.
- Native input tests open all 24 configured slots and additionally exercise 48 icon outer-edge clicks across six groups at two oblique display angles. Launch callbacks capture results without opening external apps.
- `env TCUBE_RENDER_PREVIEWS=1 swift test --scratch-path .build/tests` passed: 4 XCTest, 41 native Swift Testing and 65 core cases. The native exporter also verified backdrop transparency and idle rotation/hover pause.
- Dark and light production-renderer captures were inspected for floating icon edges, orientation and readability. README PNGs/GIF were refreshed; local links and 1120×840 gallery dimensions were verified.
- `bash scripts/build-app.sh`, `bash scripts/build-dmg.sh --skip-build`, `bash scripts/verify-dmg.sh` and `git diff --check` passed. The installer, executable, signature and installation links were verified. Independent read-only review found no concrete correctness or click regression.

## Scope

No configuration schema change is required. Surface geometry is generated once; triangle picking runs only on clicks. Native captures use isolated temporary configuration stores and system sample icons. They do not represent manual desktop automation or a fresh physical trackpad session.
