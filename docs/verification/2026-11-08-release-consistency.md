# 0.22.4 installer and source consistency

## Audit and packaged source

The initial local and remote master were `2cfe71e96ebaa7a057697180d9f0880750b125bb`. GitHub latest and both root README download tables pointed to `0.22.3`, packaged from `b5d0b5dbdb60e60095e9889be2d0e097cb9a05b0`. The publicly downloaded `SOURCE_COMMIT.txt` confirmed that older commit. Published installer SHA-256 values matched the previous local release files. Monitor discovery, removal of model presets, input-code help and the macOS nested-modal fix were absent from those installers despite unchanged application version metadata.

Both `0.22.4` installers package `99660628f8e9d99a8d90a4b159b9f811d320d0b4`. That commit only advances macOS to `0.22.4` build `46` and Windows package/lockfile versions to `0.22.4`; application logic is the audited current source. The release tag and `SOURCE_COMMIT.txt` retain that exact commit. Later documentation commits update published download links and this acceptance record. The previous release is preserved.

## Automated verification

- Release app built from a fresh `.build/app` directory using `bash scripts/build-app.sh`; DMG built with `bash scripts/build-dmg.sh --skip-build` and checked with `bash scripts/verify-dmg.sh`. Checks compare the mounted executable and plist with the built bundle, verify its deep/strict signature, installation note and `/Applications` link. The old build cache is retained under ignored `.build/release-audit-0.22.4/`.
- Swift full serial checks used both the existing `.build/tests` and a fresh `.build/release-audit-0.22.4/current-tests` directory. Swift Testing reported 186 native and 133 core entries passing, including declared opt-in skips. **The full run is not green:** one XCTest case, `EdgeDockAnimationTests.testCompletedTransitionsDetachTheRendererAndReuseOneOverlay`, fails six renderer-paused assertions across three reveal cycles. The clean XCTest run reports 16 cases, two skipped, with those six assertions failing in that one case. Menu/help interaction checks pass on recheck and in the clean full run.
- Diagnostic split execution also passed: `swift test --scratch-path .build/release-audit-0.22.4/current-tests --no-parallel --skip DisplayInputHelpInteractionTests` exited zero (14 XCTest cases, two opt-in skips; 186 native and 133 core Swift Testing entries), followed by `--filter DisplayInputHelpInteractionTests` in a separate process (both real modal interaction cases passed). This does not replace or relabel the failing same-process full-suite result.
- The same animation case passes when run alone against the current source in the fresh directory and against published `v0.22.3` source in an isolated directory. The animation implementation and its test have no diff from that release. Running it after menu/help cases reproduces the failure. This establishes a suite-context dependency, not a confirmed production diagnosis or proof of harmlessness. No assertions were weakened, tests skipped to claim a green full suite, or product behavior changed during this packaging task. Logs are retained under ignored `.build/release-audit-0.22.4/`.
- [Windows source CI](https://github.com/gd0306/t-cube/actions/runs/42392887469) passed on Windows Server 2022 and 2025 at the packaged commit, including typecheck, unit tests, build and isolated installed-source desktop smoke.
- [Windows installer CI](https://github.com/gd0306/t-cube/actions/runs/42392982294) passed at the same commit: 257 unit tests passed, two environment-only cases skipped, zero failures; typecheck/build, x64 NSIS packaging and actual installed-application checks passed. Downloaded diagnostics contain 25 native acceptance results. Installer source metadata and its SHA-256 match the downloaded CI artifact. An earlier dispatch used an abbreviated SHA that checkout treated as a branch; it failed before building, was replaced by the full-SHA run, and supplied no release artifact.
- `git diff --check` passed.

## Local installation and scope

The maintainer's Mac normally quit the previous application before replacement. Its previous application and all five recursive user JSON files were backed up before/after quit under ignored `build/install-backups/0.22.4/`. No fixtures replaced user configuration. Installed executable bytes, version/build and deep/strict signature were checked against the release build; `/Applications/T-Cube.app/Contents/MacOS/TCube` was observed running. All five JSON files remained byte-identical after replacement, launch and UI inspection.

Computer-use checks opened the installed app's Settings → Startup & Updates page, observed `当前版本 0.22.4`, and closed settings without changing preferences. These desktop checks confirm startup, the settings flow and displayed version. They do not claim a physical monitor switch or installed input-setup → help → return acceptance. No new hardware compatibility, Intel support or maintainer-PC Windows manual acceptance is claimed.

The release remains ad-hoc signed on macOS and unsigned on Windows. Signing/notarization policy and the empty authenticated Sparkle appcast are unchanged.

## Published artifacts

[Release v0.22.4](https://github.com/gd0306/t-cube/releases/tag/v0.22.4) provides both installers, `SHA256SUMS.txt` and `SOURCE_COMMIT.txt`.

```text
cbff6e36cf07055f5d5080b56854ea2e80202262d309fba067d33b804d9f3c2b  T-Cube-0.22.4-macos-arm64.dmg
95642af625f26f0865b245bc68481cfe6f8db73934b1e9034944c4d6169d09e3  T-Cube-0.22.4-windows-x64-setup.exe
```

GitHub asset sizes and SHA-256 digests were checked against all four local release files. The latest stable release and tag resolve to the packaged source above. Public unauthenticated downloads of `SHA256SUMS.txt` and `SOURCE_COMMIT.txt` were compared byte for byte with the local files. Root English/Chinese README download rows, release notes, feature availability wording and the Windows README now refer to the published `0.22.4` installers; the established layout and historical records are retained.
