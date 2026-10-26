# T-Cube 0.6.2 — rounded glass edges

## Problem and change

The marked vertex spikes came from six independent square perimeter rings. Their outer extents reached 0.528 while their face planes were at 0.5005, so neighboring face rings extended beyond and intersected at cube vertices.

Replaced those rings with one welded rounded-box bevel surface: twelve quarter-cylinder edge strips joined tangentially to eight spherical corner octants. The six flat face interiors remain open. Surface normals are analytic and smooth, with outward triangle winding; shared tangent vertices are welded. The base mesh stays inside ±0.5 on every axis.

The renderer uses a 0.045 corner radius and 16 arc subdivisions. The neutral glass material uses low roughness, clearcoat highlights and opacity 0.09. A second continuous surface, offset by only 0.0015, adds a low-opacity theme gradient that fades at face tangents. Both meshes are cached and reused when rotating or cycling themes.

This is a custom RealityKit transparent 3D glass treatment. It does not sample or refract the macOS desktop through the 3D renderer. The separate AppKit expanded launcher continues to use native Liquid Glass.

Material API reference: [Apple PhysicallyBasedMaterial documentation](https://developer.apple.com/documentation/RealityKit/PhysicallyBasedMaterial).

## Automated verification

The new geometry suite verifies bounds, absent face caps, unit normals, nondegenerate outward triangles, one connected manifold with exactly six boundary loops, curved normals at all eight corners, continuous UV coordinates and a hand-calculated custom-radius sample. The empty implementation was observed failing before implementation; all five geometry tests passed afterward.

Final command on 2026-10-26 at **09:23:54**:

```bash
env TCUBE_RENDER_PREVIEWS=1 swift test --scratch-path .build/tests
```

Result: **67 tests passed, zero failures** (1 XCTest native event queue + 26 native/runtime/render tests + 40 core tests). The existing drag, hover, appearance persistence and immediate-launch regressions remain passing. A focused geometry/material review and scoped final refinement review found no blocking issues. `git diff --check` passed.

## Render QA and limits

The desktop automation connection repeatedly returned `Sky Computer Use native pipe startup failed`, including after reset and a later retry. No real desktop screenshot or successful automatic launch is claimed for this version.

Instead, an opt-in native test renders the production CubeView scene through `ARView.snapshot` using isolated temporary configuration. It exports three 880 × 880 previews at different rotations and on dark/light backgrounds. The previews were inspected: the former crossing spikes are absent, corners are continuous, and the revised frame is thinner and more transparent than the first material pass.

Preview files are under `.build/glass-previews/`:

- `rounded-front.png`
- `rounded-tilted.png`
- `rounded-light.png`

These previews intentionally use folder icons and fixed backgrounds, not the user's launch configuration or desktop. The temporary configuration is removed after rendering; no existing app entries, theme cycle or hover preferences are changed by this QA harness.

## Installer

The final `bash scripts/build-dmg.sh` succeeded for version **0.6.2/build 13**, creating `build/T-Cube-0.6.2.dmg`. The subsequent `bash scripts/verify-dmg.sh` passed image checksum, read-only mount, binary and Info.plist comparison, local signature, Applications link and installation-note checks. The image was detached successfully.

This is an Apple Silicon, locally ad-hoc signed development package without Apple notarization. No remote push was requested or performed for these changes.
