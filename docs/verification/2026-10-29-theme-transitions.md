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
- Node22 Windows tests: 143 passed, one non-Windows skip. Typecheck/build/whitespace checks passed. Native WebGL smoke is enabled in both Windows workflows, including interpolation, RGB/alpha bounds, geometry/pose stability, map reuse, interruption and stopping idle timers.

## Published verification

- [v0.16.1](https://github.com/gd0306/t-cube/releases/tag/v0.16.1), source/tag `fa5a63be5028f7082fbcb8ef12a1a757e73d03ce`, merged and pushed to master.
- [Branch Windows 2022/2025 checks](https://github.com/gd0306/t-cube/actions/runs/40810890328): both passed, including strict native WebGL brightness/alpha, map reuse, geometry, interruptions and idle cadence.
- [Master checks](https://github.com/gd0306/t-cube/actions/runs/40811327273): both passed on rerun. First 2025 attempt missed the final native hover; identical source had passed both branch environments and installed-NSIS validation.
- [Actual NSIS install verification](https://github.com/gd0306/t-cube/actions/runs/40811030650): passed. Artifact `12870621308` records the same source SHA.
- A synthetic pre-frame draw initially measured alpha -173/328223 because a replaced optical map briefly had UV offset zero. The retarget helper now inherits the complete prior UV transform; no pixel bounds were loosened.
- macOS full tests passed (181 total), release DMG mounted/signature/files/install link verified; release 0.16.1 (29) installed and launched on this device with original configuration retained.
- The downloaded artifact ZIP matched GitHub's `f10d8fcbc1b8415e2ae146b359f0f3b7d617eb6f489aa76811a61baf6b8e22b6` archive digest. Both installers and SHA256SUMS.txt matched GitHub server digests and byte sizes before and after publication.

| Asset | Bytes | SHA-256 |
| --- | ---: | --- |
| T-Cube-0.16.1-macos-arm64.dmg | 2014688 | `4623ef08571d92179a56669f34c5db2e7ad0b1be45bbd0c51ab7b9cd8616b7f8` |
| T-Cube-0.16.1-windows-x64-setup.exe | 125217169 | `5fa58feaa27ac2c394160ba68dcd35aa6b4e03b9fdb3a1dbb1c4c2327d01bb93` |

Signing/update activation remains as in 0.16.0: local/ad-hoc macOS signing, unsigned Windows installer, authenticated automatic replacement disabled without publisher credentials.
