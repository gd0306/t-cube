# Transparent full-length edge glass / 0.20.2 (38)

Only the collapsed edge handle changes. The user first reported a bright middle with black ends, then rejected the installed unpublished build 37 because it remained opaque. The original short reflection was 20 points high over a 52-point body; the follow-up full-length reflection addressed coverage but retained a heavy tint/native material. New actual Chrome RGBA samples exposed 88–96% opacity. The maintainer's Reduce Transparency and Reduce Motion settings were both read as false, so accessibility settings were not the cause.

## Current behavior

A transparent pane keeps the background visible through a slight white or blue-black system tint, a thin rim and a full-length soft moving reflection. Native material alpha is 0.14, tint alpha 0.08–0.14, with low-alpha reflection and shadow. Windows uses corresponding low-alpha CSS rather than nearly opaque color stops. Native sampled center-line RGBA alpha is around 0.32–0.37; Chrome samples around 0.18–0.24. These describe controlled fixture pixels, not a universal optical-transmission guarantee for every backdrop or border pixel.

The reflection spans three capsule heights and gently translates while always covering both ends. Static motion/low-power modes retain it; Reduce Transparency uses the explicit opaque accessibility fallback, and Windows forced colors use system colors. The 10×56 hit region, 8×52 body, right-window shape alignment, reveal behavior, cube appearance, configuration and saved data remain unchanged.

One tiny cached gradient/one compositor translation remain. Native duration is eight seconds, preferred 24 FPS (12–30); the 2× cached gradient is about 20 KiB before platform overhead. Windows uses one CSS transform animation. No additional windows, dependencies, JavaScript/Swift frame callbacks, timers or 3D rendering are introduced. Visibility/occlusion/static-mode gates and fail-closed native visibility authority remain intact.

## Verification

- The original real native dark-end pixel check failed at both ends before the full-length fix. Restoring the old short production animation failed the extrema pixel test; the fix passed.
- New transparency regression failed on build 37 in both native and actual Chrome rendering. Native material opacity was 1.0; actual Chrome body samples were 88–96% opaque. Lowered material/tint/reflection passes both-appearance center and end RGBA checks.
- Native AppKit and actual Chrome black/white background checks preserve more than 0.52 brightness contrast through the pane in both appearances. Restoring build 37 failed the native changing-background check. The native backdrop is a parent view in the same window captured with cacheDisplay: it proves subtree alpha/composition, not live WindowServer desktop backdrop composition.
- Chrome checks actual screenshot pixels at five animation phases in both appearances, not just layer geometry. The earlier missing-reflection mutation also failed screenshot checks despite full geometric coverage.
- Full serial native suite: 6 XCTest + 150 native + 126 core registered; 273 executed/passed, nine opt-in cases skipped. Separately enabled edge preview/focused verification passed all eight edge cases.
- Node 22 typecheck/build passed; 226 unit cases passed and one Win32-only case skipped on macOS. Actual Chrome appearance/alpha/background contrast and actual Electron hidden/show/media/CSP/right-offset/stale-DOM visibility fixtures passed.
- Existing 40-cycle one/zero-animation checks remain passing; no lifecycle code changed.
- Independent read-only follow-up review found no implementation blocker. It correctly separates cacheDisplay/subtree alpha evidence from actual desktop composition, which requires separate manual acceptance.
- Release app build, mounted DMG checksums/signature/executable/Applications-link/install-note checks and git diff --check passed.

## Preview artifacts

| macOS light | macOS dark | Windows light | Windows dark |
| --- | --- | --- | --- |
| <img src="../images/full-edge-mac-light.png" width="40" alt="Transparent native light pane"> | <img src="../images/full-edge-mac-dark.png" width="40" alt="Transparent native dark pane"> | <img src="../images/full-edge-windows-light.png" width="40" alt="Transparent Windows light pane"> | <img src="../images/full-edge-windows-dark.png" width="40" alt="Transparent Windows dark pane"> |

The PNGs preserve alpha. Native previews now use a transparent/clear host window instead of the misleading default opaque test window. They do not capture WindowServer desktop blur; Windows PNGs are actual local renderer screenshots.

## Acceptance

Build 37 was locally installed and rejected by the user; it was never published. After the user normally quit it, process absence was verified and all four recursive user JSON files were backed up again. The previous app and pre-/post-exit JSON snapshots are preserved under ignored `build/install-backups/0.20.2/20261104-015027/`. Build 38 was staged, deep-strict code-signature verified, installed into `/Applications/T-Cube.app`, and launched as PID 46816. Built/staged/installed executable hashes match and all four JSON files matched their post-exit backup byte for byte before launch. The native computer-use service remains unavailable: the agent has not performed actual desktop clicking/live backdrop inspection. The user inspected the installed build and explicitly confirmed that the background visibly transmits through the handle (reply: “能”). This is user desktop acceptance in the current system appearance; both appearances were covered by automated fixtures. Both exact-source Windows CI runs have passed and the release is now public.


## Current source and artifact provenance

- Source: `f8b460606ce94cf161f9ba8113150c486a33a731`.
- Built/installed executable SHA-256: `1bb1a66c41431a641ae454a8cec6b2a9eab5e6846a40db1d6abce93c4f71ae72`.
- macOS DMG SHA-256: `75bdb804a37a0ee2ab31c045211aa728908205174be7569bc5b2309c2cfc0dbd`.


## Remote verification

- [Windows source native verification](https://github.com/gd0306/t-cube/actions/runs/41688324742): Windows 2022 passed all 25 native checks. The first Windows 2025 attempt passed edge appearance/static preferences and all four hidden zero-animation cycles, then failed at the later ordinary widget expansion-hover stage; diagnostics also contain the fixture's 150-second watchdog marker. The exact cause is not proven by those artifacts. Only the failed 2025 job was rerun at the same source, with code and assertions unchanged; it passed all 25 native checks. The successful attempt artifact was selected by its latest creation time/ID (`13256382025`), since a name-only CLI download selected the earlier failed artifact. Its results and four hidden zero-animation cycles were verified. The initial failure is preserved as diagnostic evidence, not described as a proven product fix.
- [Actual x64 NSIS installation verification](https://github.com/gd0306/t-cube/actions/runs/41688341994): passed at the current source. Downloaded SOURCE_COMMIT.txt matches the full source commit; installer checksum matches CI. Installed-app diagnostics contain 25 checks and four hidden cycles with zero animation and released compositor hints.
- Windows installer SHA-256: `71f3c40bc47736f7ca318a3faef2c03d3d01eda56ca3a57f7d1ad752b7f3df06`.


## Published release

[Release v0.20.2](https://github.com/gd0306/t-cube/releases/tag/v0.20.2) is public and latest. Both platform installers and SHA256SUMS.txt have uploaded digests and byte sizes matching local files. The public checksum file was downloaded and compared byte for byte. The release tag points to the tested transparent source `f8b460606ce94cf161f9ba8113150c486a33a731`; subsequent master changes only record acceptance. Build 37 was never published; the macOS release contains build 38.
