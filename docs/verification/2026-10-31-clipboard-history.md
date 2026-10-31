# Clipboard history / 0.18.0 (32)

## Behavior and scope

Both platforms provide a text history tab and direct menu/tray entry. Recording is disabled at each launch and requires explicit enable. Enabling/resuming baselines the current clipboard sequence. History stays in memory, is excluded from export/backup and is discarded on exit. Limits: 100 entries, 64 KiB UTF-8 per item and 2 MiB text total. Exact-byte deduplication promotes an entry without changing its identity; accepted whitespace is preserved. Blank, NUL and oversize text are skipped. Search, delete, clear, copy, existing focus-checked paste and explicit common-content draft saving are supported. Ordinary library/template drafts remain intact.

Polling is sequence-first at 500 ms only while enabled. Lifecycle generations invalidate pending reads across pause/resume/clear/self-writes. Native format exclusions precede payload reads: macOS concealed/transient/generated and file types; Windows native monitor exclusion, CanIncludeInClipboardHistory DWORD and file-drop formats, with MIME defense in depth. These are best-effort exclusions and cannot identify all unmarked sensitive text. There is no image history, persistence or cloud synchronization.

## Automated checks

- `swift test --no-parallel --scratch-path .build/tests` passed: 6 synchronous XCTest, 111 native Swift Testing and 112 core cases. Named pasteboards and temporary stores isolate clipboard and persistence tests from user data.
- A preceding concurrent full run failed two existing rendering lifecycle snapshot tests; the complete serial run passed without product/test changes. These GUI snapshots require exclusive window visibility.
- Node 22: Windows typecheck and production build passed. 174 test cases: 173 passed, one Win32-only case skipped on macOS.
- Owned headless Chromium UI flow used production history services with a fake clipboard and temporary snippet store. Inspected its history screen; no user clipboard content was read.
- Independent cross-platform reviews covered draft retention, exclusion ordering and async read invalidation; regression fixes were verified before final full checks.
- Release app build, mounted DMG content/signature verification and `git diff --check` passed.

## Local acceptance

Installed at `/Applications/T-Cube.app` after normal menu quit of 0.17.1. Previous application and all three live user JSON files were preserved under ignored `build/install-backups/0.18.0/20261031-115625/`; installed JSON bytes match post-quit backups. Installed and built executable SHA-256: `9f1c70912e8d5bc929294906bb6c6b1ed91c73270818202b6467cdcff4026d1b`. Signature verified before replacement.

Manual desktop check opened the new history menu and tab, inspected the complete layout and confirmed empty history with an explicit Enable button and default-paused status. Recording was left OFF and no new permissions were granted. Populated copy/paste/exclusion behavior on macOS was checked by isolated automated tests, not by monitoring the maintainer clipboard. Windows native source/installer CI results and publication details will be recorded after remote verification.
