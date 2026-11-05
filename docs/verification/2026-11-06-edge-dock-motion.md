# macOS edge docking motion — 0.22.2

## Behavior and scope

macOS replaces the immediate cube/handle swap with a short absorption (0.36 s) and gentle reveal (0.46 s). The cube stretches toward the exposed edge, narrows and blends into the existing transparent glass handle. Reveal has a small settling motion. Existing colors, transparency, handle dimensions, 32-point proximity and 0.8-second departure delay remain intact. Windows runtime behavior is unchanged; its package version advances with this release.

The animation uses a snapshot of this app’s own RealityKit renderer or its existing frozen frame. It never captures the desktop and requests no screen-recording permission. One input-transparent native transition window is reused; Core Animation interpolates the frames without a per-frame application timer. The regular cube window and saved resting coordinates do not move. The renderer detaches when collapsed, and one small snapshot remains for the return transition. The transition window releases image contents on completion; the snapshot is released on reveal or manual hide.

Reversal starts from the current presentation layer. Generation guards invalidate stale snapshot and animation completions. A missing snapshot falls back after 180 ms. Manual hiding, fullscreen changes, busy interactions, changed screen/handle geometry, changed cube size and shutdown cancel the transition. Hover enlargement is suspended while the image moves. Reduce Motion uses the existing direct state change. Short transitions remain available in Low Power Mode; continuous handle shimmer continues to respect its existing energy policy.

## Native verification

- `swift test --scratch-path .build/tests --no-parallel`: passed before the final narrow resize guard. XCTest reported 12 tests with one opt-in export skipped; Swift Testing reported 181 TCube and 133 CubeCore tests, zero failures, with hardware/preview checks skipped as declared.
- After the resize regression fix, `env TCUBE_DOCK_PREVIEWS=1 swift test --scratch-path .build/tests --no-parallel --filter 'EdgeDockAnimationTests|DesktopAutoHide|CubeHover|FrozenFrame|ThemeTransition'`: passed. Six docking XCTest cases (including real renderer export), 21 native Swift Testing cases and four core cases passed.
- Additional completed-transition check confirmed that the hidden 3D renderer remains detached during reveal; it passed without additional production changes.
- Regression cases cover delayed/late capture, missing capture, Reduce Motion, interrupted reveal/manual hide, unchanged saved geometry, repeated transitions/window reuse and a resize with unchanged handle coordinates. Delayed capture and resize cases were observed failing before their fixes.
- Native presentation-layer sampling exposed a repeat-reveal reset when AppKit’s default window animation overlapped the explicit layer animation. Explicit `.none` window animation removes that overlap. The export asserts that the image reaches at least 95% of the target cube width before handoff; that assertion failed before the fix and passed afterward. Completion now follows Core Animation transaction completion rather than a wall-clock sleep.
- `bash scripts/build-app.sh`, `bash scripts/build-dmg.sh` and `bash scripts/verify-dmg.sh`: passed. Built and installed executable hashes and signatures were checked again on November 6.
- Independent code review found no blocking issues. No new dependencies were added.

[Native motion preview](../images/mac-edge-dock.gif) renders the actual RealityKit snapshot and transition layer presentation on a fixed backdrop. It is an artifact preview, not a recording of a user desktop; native system backdrop material may differ from layer-only exports.

## Local installation and desktop checks

Installed `/Applications/T-Cube.app` 0.22.2 build 44 after normal quit on November 5. Previous application and all user JSON before/after quit are preserved under ignored `build/install-backups/0.22.2/20261105-204841/`. JSON hashes before and after quit matched; fixtures were not written to user storage. CUA observed the installed handle, reveal handoff and fully rendered cube, followed by recollapse. Automated cases cover interruption and repeated cycles; these checks are distinguished from manual desktop observation.

Executable SHA256: `93623a2e8704c05bb1a5925b058b5119ae6826c553ce8da835f59991550d9d62`.

A short post-install collapsed-state `top` sample on this Mac in Low Power Mode reported 0.8% CPU, 257 MB and eight threads. This is a single process sample, not a benchmark, sustained frame-rate guarantee or cross-version memory comparison. No Instruments GPU/energy profile was collected.

## Windows release checks

Packaged source: `b2bf2c9b0eb13216ca0216b6443f3ef9f44473dd`.

- [Source client CI](https://github.com/gd0306/t-cube/actions/runs/42030822276): Windows Server 2022 and 2025 passed.
- [Installer build and installed-app acceptance](https://github.com/gd0306/t-cube/actions/runs/42066821289): passed. Downloaded installer SHA-256 and full source commit were checked against the workflow artifact. No manual maintainer-PC Windows check is claimed.

[Release 0.22.2](https://github.com/gd0306/t-cube/releases/tag/v0.22.2) provides both installers, `SHA256SUMS.txt` and `SOURCE_COMMIT.txt`.
