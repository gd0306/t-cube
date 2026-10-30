# Memory resource optimization / 0.17.1

## Controlled local workload

Separate native test processes used identical temporary configuration (24 system-app entries), 164-point viewport, idle-saving mode, 12 unchanged refreshes, six one-face reorder operations, six 164/656-point resizes, four theme changes, and hide. No user fixture data was installed. Debug test builds, macOS 27.0.1 / arm64, one baseline run and one optimized run. Per-step waits were fixed but operation execution times differed. Footprint is process accounting, including compressed/swapped memory, not RSS.

| Stage | Before MiB | After MiB |
| --- | ---: | ---: |
| warm | 350.7 | 135.8 |
| unchangedRefresh12 | 2340.3 | 135.5 |
| singleFaceEdits6 | 3115.3 | 159.9 |
| resize6 | 915.7 | 267.3 |
| themes4 | 916.1 | 267.9 |
| hidden | 915.9 | 267.6 |

Sampled lifetime peak: **3323.8 → 303.5 MiB** (90.9% lower). Workload time: 96.469 → 16.500 seconds. These are synthetic workload results, not a claim that daily memory drops by that percentage. The separate pre-optimization 14-hour app had 448–452 MB footprint and a 2435 MB historical peak; comparing that process to a fresh optimized launch would not establish causality.

## Changes

- Face images now render into explicit1024×1024 bitmaps. The old1024-point NSImage rasterized as2048×2048 on Retina here: six raw RGBA atlases alone were96 MiB, now24 MiB, excluding mipmaps/driver copies.
- Six bounded artwork signatures reuse live material resources and update only changed URL/kind/bookmark/slot contents. Names and theme/hover preferences do not regenerate icon atlases. Empty faces own no texture. All four slot alpha bounds remain aligned with shared hit geometry.
- Live reveal/input resume releases obsolete frozen images; hidden/warming static fallbacks remain available to prevent visual gaps. Prepared theme blends convert endpoints and create a working context once per transition, preserving the existing premultiplied linear blending behavior. Cancellation releases prior transition images.
- Windows serialized picker icons use LRU256. NativeImage caching is pending-only (up to32 retained keys), avoiding completed bitmap residency. Successful catalog refresh clears stale resources; failed refresh preserves usable prior entries. Already admitted loads may finish after eviction; the bound is cache ownership, not a concurrency limit.

The opt-in reproduction is `TCUBE_MEMORY_PROFILE=1 TCUBE_MEMORY_PROFILE_OUTPUT=/absolute/output.json swift test --scratch-path .build/tests --filter MemoryResourceBenchmarkTests`. Ordinary tests skip the profiling workload. Raw local samples are under ignored `.build/memory-audit/`.

## Automated and visual checks

- Full `swift test --parallel --num-workers 1 --scratch-path .build/tests` passed: six synchronous XCTest cases, 99 native Swift Testing cases, and 106 core cases; opt-in preview/profile workloads are disabled in ordinary runs.
- `TCUBE_RENDER_PREVIEWS=1 swift test --scratch-path .build/tests --filter 'GlassRenderPreviewTests|IconEdgeRenderingTests'` passed (two suites). Inspected the enlarged native render against the previous capture: four-slot artwork orientation/placement and transparent edges remain correct at the tested440-point viewport and560×420 gallery view.
- Node22 typecheck/build and161 Windows tests passed locally (160 passed, one Win32-only skipped).
- Release app build and mounted DMG verification passed for0.17.1(31). Old application and all three live user JSON files were copied under ignored `build/install-backups/0.17.1/` before replacing the application.
- Independent cross-platform reviews found no blocking issues. No rendering engine replacement, draft-window destruction, or configuration changes were introduced.

## Installed build and remote verification

Installed0.17.1(31) at `/Applications/T-Cube.app`. The installed and built executable SHA-256 both equal `3bb7a972056dc1123d0e22138297b21d83b9659648ba7a0b6d8f4235df4a44b8`; signature verification passed and the running path was checked. All three live user JSON files were byte-identical to the post-quit backup after installation. The new app's real desktop surface was observed normally running. A24-second initial sample and a subsequent120-second installed-process sample both remained115–120 MB footprint,156 MB lifetime peak. These fresh-process observations are distinct from the controlled before/after workload and from the old14-hour process.

[Windows source installation CI](https://github.com/gd0306/t-cube/actions/runs/41009138808) passed on Windows2022 and2025. [Actual Windows NSIS installer verification](https://github.com/gd0306/t-cube/actions/runs/41009159385) passed, including the existing application picker, website/settings entry, template paste, backup and theme/rendering interaction checks. Downloaded SOURCE_COMMIT matches `e3104330d51e3e26fc76a78ccb7ac39b63c07ce5`. Windows memory savings have not been measured on a physical device; the implemented cache bounds are covered by regression tests.

## Published0.17.1

[Release](https://github.com/gd0306/t-cube/releases/tag/v0.17.1), tag target `e3104330d51e3e26fc76a78ccb7ac39b63c07ce5`.

| Asset | SHA-256 |
| --- | --- |
| T-Cube-0.17.1-macos-arm64.dmg | 4539590281e26fad0420d29772f99290c296a92ebe37918ec429983b3b1433e2 |
| T-Cube-0.17.1-windows-x64-setup.exe | 48e09e2c6fa3b7acfe7911829c637517eddc95ca6d4edd32dfec5737e11e3e26 |

SHA256SUMS.txt accompanies both installers. Existing ad-hoc macOS signing and unsigned Windows distribution remain as documented in the release notes.
