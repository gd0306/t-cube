# System appearance edge glass / 0.20.1 (36)

The user approved changing only the collapsed edge handle: OS light appearance uses white frosted glass, dark appearance uses deep space black, with a quiet internal moving light. Cube themes and theme cycling remain unchanged. Logical hit geometry stays 10×56, including the Windows native minimum-width container alignment and shaped hit region; the visible capsule is 8×52 at (1,2).

## Rendering and resource behavior

macOS uses an adaptive `NSVisualEffectView` with behind-window blending, a small tint/rim gradient and one cached shimmer layer. The keyframe translation takes eight seconds with a preferred 24 FPS range (12–30); no application frame callback or timer is added. Animation requires presented + visible + non-occluded state and allowed motion/transparency. Reduced motion, reduced transparency and macOS Low Power Mode keep a static reflection. Hidden/shutdown states remove the animation. Appearance, accessibility, power and occlusion updates are event driven; Combine subscriptions use weak owners and are cancelled at shutdown/deallocation. Backing-scale changes refresh the tiny raster cache. [Apple material documentation](https://developer.apple.com/documentation/appkit/nsvisualeffectview).

Windows uses local packaged HTML/CSS/TypeScript, system color-scheme media and a single child gradient animation (8.4 seconds). Reduced-motion/transparency and forced-colors modes are static. Native BrowserWindow visibility, actual document visibility and page lifecycle cancel the animation and release `will-change`; there are no JavaScript timers, requestAnimationFrame calls, canvas or WebGL. Existing native container shaping and reveal behavior remain unchanged. This is frosted styling, not a claim of desktop backdrop blur on shaped transparent Windows windows. Strict local CSP, sandboxing, context isolation and navigation restrictions remain intact.

Neither implementation wakes the cube renderer, adds a window, fetches images, changes launcher data or adds persistent configuration fields. Limits and gating describe this decoration, not a universal total-application CPU/RSS guarantee.

## Verification

- Regression-first native test reproduced the old solid accent slab having no background material. Static-reflection regression reproduced transform-dependent frame layout pushing the reduced-motion reflection out of the capsule; bounds/position layout now preserves its translated location.
- `swift test --no-parallel --scratch-path .build/tests` passed: 6 XCTest, 146 native Swift Testing and 126 core registered; 269 actually executed/passed, nine opt-in diagnostic/live/render cases skipped. A separate enabled native preview run passed all four edge view cases and checked visible material pixels in both appearances.
- Tests cover light/dark changes on the same layer hierarchy, 40 reveal/hide cycles with exactly one/zero flow animations, occluded/visible restoration, reduced motion/transparency, shutdown, accessibility press, unchanged hit geometry and the existing 30-cycle real RealityKit detach/window-count test.
- The host reported a test panel as visible but fully occluded (raw state 8192, while the public visible bit is 2), correctly suppressing flow. Unit fixtures inject only the window-visibility input to test transitions deterministically; production retains the native visibility + non-occlusion predicate. No production gate was weakened to make the test pass.
- Node 22 typecheck, build and all 227 registered local cases passed (226 executed/passed, one Win32-only case skipped on macOS). Actual Chrome renderer checks cover live light/dark changes, reduced motion/transparency/forced colors, hide/reveal cancellation, repeated-show animation count and absence of script frame/timer loops. Actual Electron checks additionally exercise initially-hidden painting, four visibility cycles, private media emulation, strict CSP and right-container translation. These use owned windows/media overrides, not global OS appearance changes.
- Native and renderer previews were inspected. The macOS view-cache export shows actual tint, rim and static reflection; live WindowServer desktop backdrop blur was not screen-captured. Windows screenshots use the actual packaged renderer.
- Independent read-only review found no important remaining issues in animation lifecycle, resource gates, weak observations, palette updates, packaging/CSP, container alignment or the final transform-independent static reflection fix.
- Release app build, mounted DMG checksum/files/signature/Applications-link verification and `git diff --check` passed.

## Preview artifacts

| macOS light | macOS dark | Windows light | Windows dark |
| --- | --- | --- | --- |
| <img src="../images/system-edge-mac-light.png" width="40" alt="Native white frosted edge capsule"> | <img src="../images/system-edge-mac-dark.png" width="40" alt="Native dark edge capsule with static highlight"> | <img src="../images/system-edge-windows-light.png" width="40" alt="Windows white frosted style"> | <img src="../images/system-edge-windows-dark.png" width="40" alt="Windows space black style"> |

## Local and remote acceptance

After the user normally quit 0.20.0, process absence was confirmed. The previous application and all four recursive user JSON files were preserved under ignored `build/install-backups/0.20.1/20261103-181027/`, with a second JSON backup taken after exit. The locally signed 0.20.1 (build 36) app was staged, verified, and installed into `/Applications/T-Cube.app`; installed/built executable hashes match. Deep strict code-signature verification passed, and all four JSON files matched their post-exit backups byte for byte before launch. The installed executable launched successfully as PID 98667. The computer-use native service was still unavailable, so this verifies installation, process startup and automated/native fixture behavior; manual desktop clicking and live desktop glass inspection were not performed.

The initial Windows native run at `760fe084da5b30e02e69c64e918e500fb1f4085f` passed visible appearance/media checks but failed the hidden cancellation check. A controlled actual Electron fixture then reproduced native hide leaving one animation when the DOM visibility getter stayed visible. A dedicated one-way Boolean preload now carries coalesced native show/hide and reload baselines; hidden assertions check native window state, native/page gate flags, zero animations and released compositor hints, retaining DOM visibility only as a diagnostic. Missing visibility authority defaults to static, covered by a separate observed red/green renderer case. Listener cleanup, stale DOM state and real helper/preload packaging were reverified without adding polling.

## Final remote candidate

Source commit: `839d82de7e7e28a91fa25c3573a119ee8ad53a67` (the macOS source and bundle resources are unchanged from the fully tested `760fe08` tree).

- [Windows 2022/2025 source verification](https://github.com/gd0306/t-cube/actions/runs/41620176546): completed successfully at the candidate commit.
- [Windows x64 NSIS and actual installed application verification](https://github.com/gd0306/t-cube/actions/runs/41620280456): completed successfully at the same commit. Both downloaded source and installer diagnostics contain 25 native checks and four hidden cycles with zero animations, false native visibility and released compositor hints. DOM visibility stayed visible in these samples, confirming that native authority cancels flow independently.
- Installer artifact `SOURCE_COMMIT.txt` matches the full candidate commit; the installer SHA-256 matches the CI checksum.
- macOS DMG SHA-256: `2363cf372e767ef4fb5f0eedeff372a7f6b8b6165d4099d16a8a543902e49d9f`.
- Windows installer SHA-256: `22c025751a7e843630bca2682d88e96b6e94b15d0b56a29189548c13b40b1f28`.
- Release app executable SHA-256 (0.20.1, build 36): `77114ba27b1c9966f86fac604391aa2cf42492170082a848165e622ee5869d5e`; the installed executable matches this hash.


## Published release

[Release v0.20.1](https://github.com/gd0306/t-cube/releases/tag/v0.20.1) is public and the latest release, with both platform installers and `SHA256SUMS.txt`. The tag resolves to the tested source commit above. All three uploaded assets match local byte sizes and SHA-256 digests; the public checksum download was fetched and compared byte for byte. Final acceptance documentation is a later documentation-only commit on master; the release tag retains the validated application source.
