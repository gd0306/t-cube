# Theme transitions and Windows defaults — 0.16.1

## Behavior

- Theme changes use a finite 400ms smooth transition. macOS retains the previous visible frame while preparing materials and a valid new snapshot, hides the warming ARView, then blends premultiplied pixels in a single image surface. Input interrupts immediately; continuous display resumes after preparation; idle saving detaches again.
- macOS snapshot failure keeps a usable live surface. Pending theme applications survive non-input cancellation, and stale callbacks cannot replace newer frames.
- Windows blends optical endpoint maps on the same geometry/UVs using premultiplied shader samples; endpoint glow/style opacity is folded into samples. Palette interpolation is linear RGB, textures are reused per animation frame, interrupted transitions flatten once and release superseded maps. Reduced Motion/material switches complete immediately.
- Windows idle saving defaults OFF; face expansion defaults ON. Explicit saved choices are retained. macOS idle-saving default is unchanged.
- Both platforms remove the cube's content-library overlay button. Menu-bar/tray, shortcut and explicit text-drop capture remain available.

## Local verification

- `swift test --scratch-path .build/tests --no-parallel`: 4 XCTest, 79 native Swift Testing, 98 core tests passed.
- A real ARView regression reproduced exposed preparation (`alphaValue == 1`), then passed with the previous frame retained and warming view hidden; final snapshots contain visible pixels and the renderer detaches again.
- Deterministic injected captures reproduced pending-theme cancellation and nil-snapshot bugs (7 issues); fixes pass, including stale completion rejection and visible failure fallback.
- Pixel tests cover transparent highlights on black/white backdrops, endpoint identity and transparent RGB leakage.
- Node22 Windows tests: 142 passed, one non-Windows skip. Typecheck/build/whitespace checks passed. Native WebGL smoke is enabled in both Windows workflows, including interpolation, RGB/alpha bounds, geometry/pose stability, map reuse, interruption and stopping idle timers.
