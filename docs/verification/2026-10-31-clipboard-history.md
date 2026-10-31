# Clipboard history / 0.18.0 (32)

## Behavior and scope

Both platforms provide a text history tab and direct menu/tray entry. Recording is disabled at each launch and requires explicit enable. Enabling/resuming baselines the current clipboard sequence. History stays in memory, is excluded from export/backup and is discarded on exit. Limits: 100 entries, 64 KiB UTF-8 per item and 2 MiB text total. Exact-byte deduplication promotes an entry without changing its identity; accepted whitespace is preserved. Blank, NUL and oversize text are skipped. Search, delete, clear, copy, existing focus-checked paste and explicit common-content draft saving are supported. Ordinary library/template drafts remain intact.

Polling is sequence-first at 500 ms only while enabled. Lifecycle generations invalidate pending reads across pause/resume/clear/self-writes. Native format exclusions precede payload reads: macOS concealed/transient/generated and file types; Windows native monitor exclusion, CanIncludeInClipboardHistory DWORD and file-drop formats, with MIME defense in depth. These are best-effort exclusions and cannot identify all unmarked sensitive text. There is no image history, persistence or cloud synchronization.

## Automated checks

- `swift test --no-parallel --scratch-path .build/tests` passed: 6 synchronous XCTest, 111 native Swift Testing and 112 core cases. Named pasteboards and temporary stores isolate clipboard and persistence tests from user data.
- A preceding concurrent full run failed two existing rendering lifecycle snapshot tests; the complete serial run passed without product/test changes. These GUI snapshots require exclusive window visibility.
- Node 22: Windows typecheck and production build passed. 175 test cases: 174 passed, one Win32-only case skipped on macOS.
- Owned headless Chromium UI flow used production history services with a fake clipboard and temporary snippet store. Inspected its history screen; no user clipboard content was read.
- Independent cross-platform reviews covered draft retention, exclusion ordering and async read invalidation; regression fixes were verified before final full checks.
- Initial Windows native CI exposed a production default-scheduler parameter shadowing error. A default-constructor regression reproduced the ReferenceError before the module scheduler was renamed; all local Windows checks passed after the fix. Remote native verification is rerun against the corrected commit.
- Release app build, mounted DMG content/signature verification and `git diff --check` passed.

## Local acceptance

Installed at `/Applications/T-Cube.app` after normal menu quit of 0.17.1. Previous application and all three live user JSON files were preserved under ignored `build/install-backups/0.18.0/20261031-115625/`; installed JSON bytes match post-quit backups. Installed and built executable SHA-256: `9f1c70912e8d5bc929294906bb6c6b1ed91c73270818202b6467cdcff4026d1b`. Signature verified before replacement.

Manual desktop check opened the new history menu and tab, inspected the complete layout and confirmed empty history with an explicit Enable button and default-paused status. Recording was left OFF and no new permissions were granted. Populated copy/paste/exclusion behavior on macOS was checked by isolated automated tests, not by monitoring the maintainer clipboard. Windows native source CI and publication verification are recorded below.

## Windows native acceptance

[Source installation CI](https://github.com/gd0306/t-cube/actions/runs/41199258649) passed on Windows 2022 and 2025 at `b570390a90201ce97ab4e7edae62bce993053e8f`. All 175 Windows unit cases passed on the target platform. Native smoke covered enable/resume baselines, exact deduplication, real registered privacy DWORD/exclusion formats and CF_HDROP, copy/paste into an owned WinForms receiver, ordinary draft retention, explicit snippet saving, pause/delete/clear, existing templates/backup/rendering and final cube expansion.

A diagnostic run established that accepting Chromium's confirmation through CDP left Electron native Windows message boxes visible over the widget. The history smoke now supplies only the two exact confirmation choices in its disposable, isolated renderer, asserts their order and count, and restores the original function before cleanup requests. Production confirmation protection is unchanged. Native Windows confirmation-dialog appearance/button interaction is not covered by this fixture. Real clipboard format/paste/receiver interactions remain native; the original CI clipboard snapshot is restored by the surrounding fixture. No maintainer clipboard was monitored for local acceptance.

The macOS application sources and bundle metadata are identical between the initial verified app build and this source CI commit; subsequent changes affect Windows and test/documentation code only.

## Installer and publication verification

[Actual Windows NSIS installation](https://github.com/gd0306/t-cube/actions/runs/41199367594) passed, including the native clipboard history/paste flow and existing rendering, input, template and backup checks. Downloaded `SOURCE_COMMIT.txt` exactly matches `b570390a90201ce97ab4e7edae62bce993053e8f`; the installer matched its build-provided SHA-256. A subsequent test-only cleanup-order adjustment restores the confirmation fixture before any fallible cleanup IPC; [source CI](https://github.com/gd0306/t-cube/actions/runs/41199604429) passed on both Windows versions for `572744c116166f1972e26a4a460b85a480dac6d2`.

Published [0.18.0](https://github.com/gd0306/t-cube/releases/tag/v0.18.0), with tag target `b570390a90201ce97ab4e7edae62bce993053e8f`. Release API confirms a public, non-draft/non-prerelease publication. All three remote asset digests match the local artifacts, and the publicly downloaded checksum manifest matches byte-for-byte.

| Asset | SHA-256 |
| --- | --- |
| T-Cube-0.18.0-macos-arm64.dmg | b0aa64a5110c9f7b7dc9dc6a47b38cc2b7561ce216fe905f89678d387b1bc383 |
| T-Cube-0.18.0-windows-x64-setup.exe | cfc15faf59ffadc37c8d97ec44c61b697916875f452ed044b385e0bfb4382ed2 |
| SHA256SUMS.txt | d23316f02b74d79db733f3e49f157006bc0e5133026b101710fc775bfb717ff8 |

macOS remains ad-hoc signed and unnotarized; Windows remains unsigned, as disclosed in the release notes. No production update keys, signing credentials or new permissions were configured by this feature.
